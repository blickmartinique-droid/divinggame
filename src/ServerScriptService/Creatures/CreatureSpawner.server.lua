-- Spawns marine creatures and ticks their brains. Placement comes from
-- SpawnRegion parts (RegionKind = "Creature", see SpawnRegions.lua) -- the
-- biome decor, wreck and caves all place their own, and more can be tagged
-- by hand in Studio. A species no region hosts at all still gets its
-- FallbackCount scattered through open water in its own depth band, so
-- every animal in CreaturesConfig exists somewhere.
--
-- A region only spawns species that actually live at its depth (a reef
-- fish listed for a 300 m cave would just swim up through the rock to its
-- band); its RegionWanderRadius caps how far they roam from home.
-- Schooling species (SchoolSize > 1) spawn as whole shoals sharing one
-- CreatureBrain School.
--
-- Models: ReplicatedStorage.Assets.Creatures.<ModelName> (then .<Id>) is
-- cloned when present -- where the imported animal assets go, ModelName
-- being the exact name the pack's FBX imports under, e.g.
-- "02_Requin_Recif". Otherwise a flat placeholder body is built from the
-- species' Size/Color. Either way the spawner adds the movement
-- constraints the brain drives.
--
-- Animation: these animals are NOT humanoids, so an imported rig gets an
-- AnimationController + Animator (never a Humanoid), and the brain's own
-- state picks the clip -- the slow swim while wandering, the fast one
-- while fleeing or chasing. Both clip ids live in CreaturesConfig and are
-- nil until the clips are published under this game's owner; with them
-- nil setupAnimator simply does nothing.
--
-- Bodies are unanchored, server-owned physics parts moved by AlignPosition/
-- AlignOrientation (not anchored + CFrame writes), so clients get smooth,
-- interpolated motion even though the brain only updates a few times per
-- second. One loop ticks every creature at UPDATE_INTERVAL; creatures
-- farther than FAR_DISTANCE from every player only tick at FAR_INTERVAL.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local CreaturesConfig = require(ReplicatedStorage.Shared.Config.CreaturesConfig)
local SpawnRegions = require(ReplicatedStorage.Shared.Modules.SpawnRegions)
local DepthUtils = require(ReplicatedStorage.Shared.Modules.DepthUtils)
local CreatureBrain = require(script.Parent.CreatureBrain)
local CreatureBodies = require(ReplicatedStorage.Shared.Modules.CreatureBodies)
local WorldLayout = require(game:GetService("ServerScriptService").World.Builders.WorldLayout)

local UPDATE_INTERVAL = 0.1
local FAR_DISTANCE = 350
local FAR_INTERVAL = 1
local DEFAULT_REGION_COUNT = 5
local FALLBACK_MIN_RADIUS = 200
local FALLBACK_MAX_RADIUS = 700
local PLACEMENT_ATTEMPTS = 24

local creatureAttacked = Instance.new("BindableEvent")
creatureAttacked.Name = "CreatureAttacked"
creatureAttacked.Parent = script

local existing = Workspace:FindFirstChild("Creatures")
if existing then
	existing:Destroy()
end
local creaturesFolder = Instance.new("Folder")
creaturesFolder.Name = "Creatures"
creaturesFolder.Parent = Workspace

local speciesById = {}
for _, species in ipairs(CreaturesConfig.Species) do
	speciesById[species.Id] = species
end

-- A SpawnRegion may still name a species by an id used before the real
-- assets arrived (see CreaturesConfig.Aliases) -- resolve those rather
-- than silently spawning nothing in a region somebody tagged in Studio.
local function resolveSpecies(id: string)
	return speciesById[id] or speciesById[CreaturesConfig.Aliases[id] or ""]
end

-- Model construction ----------------------------------------------------------

-- Tries the pack's own model name first (what the FBX imports as), then
-- the species id, so the asset works whether or not it was renamed after
-- importing.
local function findAssetModel(species): Model?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local creatures = assets and assets:FindFirstChild("Creatures")
	if not creatures then
		return nil
	end
	for _, name in ipairs({ species.ModelName, species.Id }) do
		local model = name and creatures:FindFirstChild(name)
		if model and model:IsA("Model") and model.PrimaryPart then
			return model
		end
	end
	return nil
end

-- No imported rig yet: a detailed procedural body (see CreatureBodies),
-- already facing -Z like the brain steers, with its own swim joints.
local function buildPlaceholder(species, options): Model
	return CreatureBodies.Build(species, options)
end

local function prepareModel(model: Model, species, imported: boolean)
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.Massless = descendant ~= model.PrimaryPart
		end
	end

	local root = model.PrimaryPart
	local attachment = Instance.new("Attachment")
	attachment.Name = "BrainAttachment"
	attachment.Parent = root

	local alignPosition = Instance.new("AlignPosition")
	alignPosition.Name = "MoveTarget"
	alignPosition.Mode = Enum.PositionAlignmentMode.OneAttachment
	alignPosition.Attachment0 = attachment
	alignPosition.MaxForce = math.huge
	alignPosition.MaxVelocity = math.huge
	alignPosition.Responsiveness = 12
	alignPosition.Position = root.Position
	alignPosition.Parent = root

	local alignOrientation = Instance.new("AlignOrientation")
	alignOrientation.Name = "FaceTarget"
	alignOrientation.Mode = Enum.OrientationAlignmentMode.OneAttachment
	alignOrientation.Attachment0 = attachment
	alignOrientation.MaxTorque = math.huge
	alignOrientation.Responsiveness = 8
	alignOrientation.CFrame = root.CFrame
	alignOrientation.Parent = root

	model.Name = species.Id
	model:SetAttribute("Species", species.Id)
	-- Read by CreatureBrain: only an imported rig needs the species'
	-- ModelYawOffsetDegrees, the placeholder body is built facing -Z.
	model:SetAttribute("ImportedRig", imported)
	model:SetAttribute("DisplayName", species.Name)
	model:SetAttribute("Behavior", species.Behavior)
	CollectionService:AddTag(model, "Creature")
end

-- Loads the two swim clips onto a non-humanoid rig. Returns nil when the
-- species has no published clip ids yet (the normal state until they are
-- uploaded) or when the model has no rig to animate -- a placeholder body
-- is rigid geometry, so there is nothing for an Animator to deform.
local function setupAnimator(model: Model, species, imported: boolean)
	if not imported or not (species.SlowSwimAnimationId or species.FastSwimAnimationId) then
		return nil
	end

	local controller = Instance.new("AnimationController")
	controller.Name = "CreatureAnimationController"
	controller.Parent = model

	local animator = Instance.new("Animator")
	animator.Parent = controller

	local function loadTrack(assetId: string?)
		if not assetId then
			return nil
		end
		local animation = Instance.new("Animation")
		animation.AnimationId = assetId
		local ok, track = pcall(function()
			return animator:LoadAnimation(animation)
		end)
		if not ok or not track then
			-- A wrong/unpublished id must not take the whole spawner down
			-- with it: the creature just swims without body animation.
			warn(string.format("[Creatures] %s: could not load animation %s", species.Id, assetId))
			return nil
		end
		track.Looped = true
		track.Priority = Enum.AnimationPriority.Movement
		return track
	end

	local tracks = { slow = loadTrack(species.SlowSwimAnimationId), fast = loadTrack(species.FastSwimAnimationId) }
	if not (tracks.slow or tracks.fast) then
		controller:Destroy()
		return nil
	end
	return tracks
end

-- The brain's own state drives which clip plays: calm wandering uses the
-- slow swim, fleeing or chasing uses the fast one. Falls back to whichever
-- clip exists if only one has been published.
local function applyAnimationState(entry, state: string)
	if entry.animationState == state then
		return
	end
	entry.animationState = state
	-- Replicated once per state change: CreatureAnimator (client) beats a
	-- procedural body's tail/fins faster while fleeing or chasing.
	entry.model:SetAttribute("State", state)
	local tracks = entry.tracks
	if not tracks then
		return
	end

	local wanted = (state == "Wander") and (tracks.slow or tracks.fast) or (tracks.fast or tracks.slow)
	for _, track in pairs(tracks) do
		if track ~= wanted and track.IsPlaying then
			track:Stop(0.3)
		end
	end
	if wanted and not wanted.IsPlaying then
		wanted:Play(0.3)
	end
end

-- Spawning ----------------------------------------------------------------------

local brains = {}

local function onAttack(brain, playerRoot: BasePart)
	local character = playerRoot.Parent
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local player = character and Players:GetPlayerFromCharacter(character)
	if humanoid and humanoid.Health > 0 then
		if player and humanoid.Health <= brain.species.AttackDamage then
			-- Read by the client's DeathScreen to say what happened.
			player:SetAttribute("LastDeathCause", "Attaqué par : " .. brain.species.Name)
		end
		humanoid:TakeDamage(brain.species.AttackDamage)
		creatureAttacked:Fire(player, brain.species.Id, brain.model)
	end
end

local schools = {}

local function spawnCreature(species, position: Vector3, options)
	options = options or {}
	local asset = findAssetModel(species)
	local model = asset and asset:Clone() or buildPlaceholder(species, {
		variant = options.variant or math.random(1, CreatureBodies.ReefPaletteCount),
		scale = options.scale or (0.88 + math.random() * 0.24),
	})
	prepareModel(model, species, asset ~= nil)
	model:PivotTo(CFrame.new(position))
	model.Parent = creaturesFolder
	model.PrimaryPart:SetNetworkOwner(nil)

	local brain = CreatureBrain.new(model, species, position, onAttack, options)
	local entry = { brain = brain, model = model, nextTick = 0, tracks = setupAnimator(model, species, asset ~= nil) }
	applyAnimationState(entry, brain.state)
	table.insert(brains, entry)

	model.AncestryChanged:Connect(function(_, parent)
		if not parent then
			local index = table.find(brains, entry)
			if index then
				table.remove(brains, index)
			end
		end
	end)
end

-- Spawns one creature, or a whole shoal for a schooling species (up to
-- `budget` members). Returns how many were spawned.
-- Open-water creatures keep clear of the seabed; cave dwellers (their
-- region flagged RegionUnderground) live below it by definition.
local function groundFunction(underground: boolean?)
	local layout = WorldLayout.Current
	if underground or not layout then
		return nil
	end
	return function(x: number, z: number): number
		return layout:GroundHeight(x, z)
	end
end

local function spawnGroup(species, position: Vector3, budget: number, wanderRadius: number?, underground: boolean?): number
	local size = math.min(species.SchoolSize or 1, budget)
	local ground = groundFunction(underground)
	if ground then
		local shallowest = DepthUtils.SURFACE_Y - species.MinDepth
		position = Vector3.new(position.X, math.min(math.max(position.Y, ground(position.X, position.Z) + 3), shallowest), position.Z)
	end
	if size <= 1 then
		spawnCreature(species, position, { wanderRadius = wanderRadius, ground = ground })
		return 1
	end
	local school = CreatureBrain.newSchool(species, position, wanderRadius, ground)
	table.insert(schools, school)
	-- One palette per shoal (a school of mixed colours reads as random
	-- noise, a matching one as a real school), sizes within a few percent.
	local variant = math.random(1, CreatureBodies.ReefPaletteCount)
	for index = 1, size do
		local spread = Vector3.new((index % 3 - 1) * 2, (index % 2) * 1.5, (math.floor(index / 3) % 3 - 1) * 2)
		spawnCreature(species, position + spread, { school = school, wanderRadius = wanderRadius, ground = ground, variant = variant, scale = 0.95 + math.random() * 0.1 })
	end
	return size
end

local function pickWeighted(candidates)
	local total = 0
	for _, species in ipairs(candidates) do
		total += species.Weight
	end
	local roll = math.random() * total
	local cumulative = 0
	for _, species in ipairs(candidates) do
		cumulative += species.Weight
		if roll <= cumulative then
			return species
		end
	end
	return candidates[#candidates]
end

local function livesAt(species, depth: number): boolean
	return depth >= species.MinDepth and depth <= species.MaxDepth
end

-- The species a region would host: its explicit list, minus anything that
-- does not live at the region's depth; or, without a list, every species
-- whose band covers that depth.
local function regionCandidates(region: BasePart)
	local depth = DepthUtils.GetDepth(region.Position)
	local candidates = {}
	local listed = SpawnRegions.GetSpeciesList(region)
	for _, id in ipairs(listed) do
		local species = resolveSpecies(id)
		if not species then
			warn(string.format("[Creatures] SpawnRegion %s: unknown species %q", region:GetFullName(), id))
		elseif not livesAt(species, depth) then
			warn(string.format("[Creatures] SpawnRegion %s: %s does not live at %d m (%d-%d m)", region:GetFullName(), species.Id, depth, species.MinDepth, species.MaxDepth))
		else
			table.insert(candidates, species)
		end
	end
	if #listed == 0 then
		for _, species in ipairs(CreaturesConfig.Species) do
			if livesAt(species, depth) then
				table.insert(candidates, species)
			end
		end
	end
	return candidates
end

local populated = {}

local function populateRegion(region: BasePart)
	if populated[region] or region:GetAttribute("RegionKind") ~= "Creature" or region:GetAttribute("RegionEnabled") == false then
		return
	end
	populated[region] = true

	local candidates = regionCandidates(region)
	if #candidates == 0 then
		warn(string.format("[Creatures] SpawnRegion %s: no species fits its depth", region:GetFullName()))
		return
	end

	local count = region:GetAttribute("RegionCount") or DEFAULT_REGION_COUNT
	local wanderRadius = region:GetAttribute("RegionWanderRadius")
	local spawned = 0
	while spawned < count do
		local species = pickWeighted(candidates)
		local underground = region:GetAttribute("RegionUnderground") == true
		local ground = groundFunction(underground)
		-- A region can overlap a slope: retry until the spot has water deep
		-- enough for this species above the seabed.
		local position
		for _ = 1, 16 do
			position = SpawnRegions.RandomPointIn(region)
			local depth = DepthUtils.GetDepth(position)
			position = Vector3.new(position.X, DepthUtils.SURFACE_Y - math.clamp(depth, species.MinDepth, species.MaxDepth), position.Z)
			if not ground or ground(position.X, position.Z) + 3 <= DepthUtils.SURFACE_Y - species.MinDepth then
				break
			end
		end
		spawned += spawnGroup(species, position, count - spawned, wanderRadius, underground)
	end
end

local function openWaterPoint(species): Vector3
	local layout = WorldLayout.Current
	local point
	for _ = 1, PLACEMENT_ATTEMPTS do
		local angle = math.random() * math.pi * 2
		local radius = FALLBACK_MIN_RADIUS + math.random() * (FALLBACK_MAX_RADIUS - FALLBACK_MIN_RADIUS)
		local depth = species.MinDepth + math.random() * (species.MaxDepth - species.MinDepth)
		point = Vector3.new(math.cos(angle) * radius, DepthUtils.SURFACE_Y - depth, math.sin(angle) * radius)
		if not layout or layout:IsFree(point, 10) then
			break
		end
	end
	return point
end

-- Open-water population for every species no enabled region hosts.
local function populateFallback()
	local hosted = {}
	for _, region in ipairs(SpawnRegions.GetRegions("Creature")) do
		for _, species in ipairs(regionCandidates(region)) do
			hosted[species.Id] = true
		end
	end
	for _, species in ipairs(CreaturesConfig.Species) do
		if not hosted[species.Id] then
			local spawned = 0
			while spawned < (species.FallbackCount or 0) do
				spawned += spawnGroup(species, openWaterPoint(species), species.FallbackCount - spawned, nil)
			end
		end
	end
end

SpawnRegions.WaitForWorld()
for _, region in ipairs(SpawnRegions.GetRegions("Creature")) do
	populateRegion(region)
end
populateFallback()
SpawnRegions.OnRegionAdded(populateRegion)

-- Tick loop -------------------------------------------------------------------------

local function nearestPlayerRoot(position: Vector3): (BasePart?, number)
	local best, bestDistance = nil, math.huge
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if root and humanoid and humanoid.Health > 0 then
			local distance = (root.Position - position).Magnitude
			if distance < bestDistance then
				best, bestDistance = root, distance
			end
		end
	end
	return best, bestDistance
end

local accumulated = 0
RunService.Heartbeat:Connect(function(deltaTime)
	accumulated += deltaTime
	if accumulated < UPDATE_INTERVAL then
		return
	end
	local now = os.clock()

	for _, school in ipairs(schools) do
		school:Update(accumulated)
	end

	for _, entry in ipairs(brains) do
		if now >= entry.nextTick then
			local brain = entry.brain
			local playerRoot, distance = nearestPlayerRoot(brain.position)
			local dt = math.min(now - (entry.lastTick or now), FAR_INTERVAL * 2)
			entry.lastTick = now
			brain:Update(dt > 0 and dt or accumulated, playerRoot, distance)
			applyAnimationState(entry, brain.state)
			entry.nextTick = distance > FAR_DISTANCE and now + FAR_INTERVAL or 0
		end
	end

	accumulated = 0
end)

creatureAttacked.Event:Connect(function(player, speciesId)
	if player then
		print(string.format("[Creatures] %s attaqué par %s", player.Name, speciesId))
	end
end)
