-- Spawns marine creatures and ticks their brains. Placement comes from
-- hand-placed SpawnRegion parts (RegionKind = "Creature", see
-- SpawnRegions.lua) so populations follow the real map; with no such
-- region present it falls back to scattering each species' FallbackCount
-- across its own depth band in the open-ocean ring, which is what the
-- current prototype map uses.
--
-- Models: ReplicatedStorage.Assets.Creatures.<SpeciesId> (a Model with a
-- PrimaryPart) is cloned when present -- that is where Blender assets go.
-- Otherwise a flat placeholder body is built from the species' Size/Color.
-- Either way the spawner adds the movement constraints the brain drives.
--
-- Bodies are unanchored, server-owned physics parts moved by AlignPosition/
-- AlignOrientation (not anchored + CFrame writes), so clients get smooth,
-- interpolated motion from the physics replication even though the brain
-- only updates targets a few times per second.
--
-- One loop ticks every creature at UPDATE_INTERVAL; creatures farther than
-- FAR_DISTANCE from every player only tick at FAR_INTERVAL, so a large
-- world full of fish nobody is near costs almost nothing.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local CreaturesConfig = require(ReplicatedStorage.Shared.Config.CreaturesConfig)
local SpawnRegions = require(ReplicatedStorage.Shared.Modules.SpawnRegions)
local DepthUtils = require(ReplicatedStorage.Shared.Modules.DepthUtils)
local CreatureBrain = require(script.Parent.CreatureBrain)

local UPDATE_INTERVAL = 0.1
local FAR_DISTANCE = 350
local FAR_INTERVAL = 1
local DEFAULT_REGION_COUNT = 5
local FALLBACK_MIN_RADIUS = 200
local FALLBACK_MAX_RADIUS = 450

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

-- Model construction ----------------------------------------------------------

local function findAssetModel(speciesId: string): Model?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local creatures = assets and assets:FindFirstChild("Creatures")
	local model = creatures and creatures:FindFirstChild(speciesId)
	if model and model:IsA("Model") and model.PrimaryPart then
		return model
	end
	return nil
end

local function buildPlaceholder(species): Model
	local model = Instance.new("Model")

	local body = Instance.new("Part")
	body.Name = "Body"
	body.Size = species.Size
	body.Color = species.Color
	body.Material = Enum.Material.SmoothPlastic
	body.Parent = model

	local tail = Instance.new("WedgePart")
	tail.Name = "Tail"
	tail.Size = Vector3.new(species.Size.X * 0.4, species.Size.Y * 0.8, species.Size.Z * 0.45)
	tail.Color = species.Color
	tail.Material = Enum.Material.SmoothPlastic
	tail.CFrame = CFrame.new(0, 0, species.Size.Z / 2 + tail.Size.Z / 2) * CFrame.Angles(0, math.pi, 0)
	tail.Parent = model

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = body
	weld.Part1 = tail
	weld.Parent = body

	if species.Glow then
		local light = Instance.new("PointLight")
		light.Color = species.Glow
		light.Range = 14
		light.Brightness = 1.5
		light.Parent = body
	end

	model.PrimaryPart = body
	return model
end

local function prepareModel(model: Model, species)
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
	model:SetAttribute("DisplayName", species.Name)
	model:SetAttribute("Behavior", species.Behavior)
	CollectionService:AddTag(model, "Creature")
end

-- Spawning ----------------------------------------------------------------------

local brains = {}

local function onAttack(brain, playerRoot: BasePart)
	local character = playerRoot.Parent
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local player = character and Players:GetPlayerFromCharacter(character)
	if humanoid and humanoid.Health > 0 then
		humanoid:TakeDamage(brain.species.AttackDamage)
		creatureAttacked:Fire(player, brain.species.Id, brain.model)
	end
end

local function spawnCreature(species, position: Vector3)
	local asset = findAssetModel(species.Id)
	local model = asset and asset:Clone() or buildPlaceholder(species)
	prepareModel(model, species)
	model:PivotTo(CFrame.new(position))
	model.Parent = creaturesFolder
	model.PrimaryPart:SetNetworkOwner(nil)

	local brain = CreatureBrain.new(model, species, position, onAttack)
	local entry = { brain = brain, model = model, nextTick = 0 }
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

local function populateRegion(region: BasePart)
	if region:GetAttribute("RegionKind") ~= "Creature" or region:GetAttribute("RegionEnabled") == false then
		return
	end

	local candidates = {}
	for _, id in ipairs(SpawnRegions.GetSpeciesList(region)) do
		if speciesById[id] then
			table.insert(candidates, speciesById[id])
		end
	end
	if #candidates == 0 then
		-- No explicit list: any species whose depth band covers the region's center.
		local depth = DepthUtils.GetDepth(region.Position)
		for _, species in ipairs(CreaturesConfig.Species) do
			if depth >= species.MinDepth and depth <= species.MaxDepth then
				table.insert(candidates, species)
			end
		end
	end
	if #candidates == 0 then
		warn(string.format("[Creatures] SpawnRegion %s: no species fits its depth", region:GetFullName()))
		return
	end

	local count = region:GetAttribute("RegionCount") or DEFAULT_REGION_COUNT
	for _ = 1, count do
		spawnCreature(pickWeighted(candidates), SpawnRegions.RandomPointIn(region))
	end
end

local function populateFallback()
	for _, species in ipairs(CreaturesConfig.Species) do
		for _ = 1, species.FallbackCount or 0 do
			local angle = math.random() * math.pi * 2
			local radius = FALLBACK_MIN_RADIUS + math.random() * (FALLBACK_MAX_RADIUS - FALLBACK_MIN_RADIUS)
			local depth = species.MinDepth + math.random() * (species.MaxDepth - species.MinDepth)
			spawnCreature(species, Vector3.new(math.cos(angle) * radius, DepthUtils.SURFACE_Y - depth, math.sin(angle) * radius))
		end
	end
end

local regions = SpawnRegions.GetRegions("Creature")
if #regions > 0 then
	for _, region in ipairs(regions) do
		populateRegion(region)
	end
else
	populateFallback()
end
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

	for _, entry in ipairs(brains) do
		if now >= entry.nextTick then
			local brain = entry.brain
			local playerRoot, distance = nearestPlayerRoot(brain.position)
			local dt = math.min(now - (entry.lastTick or now), FAR_INTERVAL * 2)
			entry.lastTick = now
			brain:Update(dt > 0 and dt or accumulated, playerRoot, distance)
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
