-- Shared builder for the 4 "biome" cave/mountain regions
-- (CaveRegion1Data.lua .. CaveRegion4Data.lua, one per uploaded .glb).
-- Invoked once per region by CaveRegions.server.lua with a placement
-- config; does NOT touch MegaWreckShip, its scripts, or its position.
--
-- WHY THIS IS TERRAIN, NOT PARTS (unlike MegaWreckShip): the ship's
-- source model was hundreds of small rigid boxes (a man-made structure),
-- so rebuilding it as boxes lost nothing. These 4 models are the opposite
-- -- a handful of big, deliberately blocky "mass" placeholders (the
-- filenames literally say "blockout") standing in for organic mountains
-- and caves. Rebuilding THOSE as boxes would keep exactly the cubic,
-- stacked-blocks look the brief explicitly asks to avoid. Roblox smooth
-- Terrain, by contrast, always renders rounded/smoothed regardless of the
-- fill shape used, and the same technique already builds this project's
-- beach (OceanGenerator.server.lua's stacked FillCylinder tiers) -- so
-- the rock mass and every cave/tunnel here is real Terrain: solid Rock
-- filled in, Water carved back out where the model says there's a void.
-- Carved-out space is Water (not Air): the whole game is underwater, and
-- an air pocket inside a cave would put a surface where none should be.
--
-- WHAT THE SOURCE DATA IS USED FOR: not literal geometry (these are
-- explicitly "des bases de travail," a few dozen studs across per
-- feature) but PLACEMENT -- where each mass tier sits relative to the
-- others (giving the real authored silhouette: a stepped mountain profile
-- for Region 1/3, a central peak plus satellite outcrops and an abyssal
-- pit for Region 2, etc.), where each entry breaches the surface and
-- which direction it faces, where ruins/terraces/corals sit relative to
-- the mass. All of that is preserved; the actual sizes are then scaled up
-- and the small placeholder chambers enlarged into real caverns.
--
-- AXIS FIX (same finding as MegaWreckShip's): this generator's own
-- vertical axis is Z, not Y (confirmed the same way -- e.g. Region 3's
-- "central_mass" tiers are wide/flat: ~90x70 in X/Y but only ~10 thick in
-- Z). remapAxes swaps Y/Z on every raw point before use.

local CaveRegionBuilder = {}

local function remapAxes(v: Vector3): Vector3
	return Vector3.new(v.X, v.Z, v.Y)
end

-- Mass tiers ------------------------------------------------------------------

-- Source "mass" seeds are the blockout's own placeholder tiers -- a few
-- dozen studs across, deliberately not meant to be taken as final size
-- (see the file header). MASS_RADIUS_MULTIPLIER is what actually makes
-- the mountain immense: applied on top of the region's own Scale, tuned
-- so the enlarged mass roughly catches up to where the source file's own
-- ruins/pillars/arches already sit (those were positioned assuming a
-- bigger mountain than the raw blockout tiers describe), so decoration
-- ends up ON the mountain's new surface instead of scattered in open
-- water far beyond a too-small core.
-- Only the horizontal spread is boosted by this: vertical extent already
-- lands in a sensible range (a couple hundred studs, comparable to
-- MegaWreckShip's own ~254-stud height) using just the region's Scale, so
-- multiplying height too would only push the mountain through more depth
-- zones than intended without making it feel any bigger to swim around.
local MASS_RADIUS_MULTIPLIER = 2.4

-- Fills widest tiers first, narrowest/tallest last -- same lesson as
-- OceanGenerator's beach tiers: if a narrower, higher tier were filled
-- before a wider one, the wide fill would bury it, leaving one flat mass
-- instead of a stepped mountain silhouette.
local function fillMassTiers(terrain: Terrain, data, toWorld, scale: number)
	local tiers = {}
	for _, seed in ipairs(data.Mass) do
		local radius = math.max(seed.Size.X, seed.Size.Y) * 0.5 * scale * MASS_RADIUS_MULTIPLIER
		local height = math.max(seed.Size.Z * scale, 6)
		table.insert(tiers, { seed = seed, radius = radius, height = height })
	end
	table.sort(tiers, function(a, b)
		return a.radius > b.radius
	end)

	for _, tier in ipairs(tiers) do
		local center = toWorld(tier.seed.Center)
		terrain:FillCylinder(CFrame.new(center), tier.height, tier.radius, Enum.Material.Rock)
	end

	return tiers
end

-- Caverns -----------------------------------------------------------------------

local CAVERN_ENLARGE = 5 -- source chambers are ~15-30 raw studs; this is what makes them monumental
local MIN_CAVERN_RADIUS = 70

local function carveCavern(terrain: Terrain, center: Vector3, rawSize: Vector3, scale: number, enlarge: number?)
	local radius = math.max(rawSize.X, rawSize.Y, rawSize.Z) * 0.5 * scale * (enlarge or CAVERN_ENLARGE)
	radius = math.max(radius, MIN_CAVERN_RADIUS)
	terrain:FillBall(center, radius, Enum.Material.Water)
	return radius
end

-- Entries / tunnels -----------------------------------------------------------------

local TUNNEL_OUTER_MARGIN = 30 -- raw studs pushed further out than CorridorCenter, guaranteeing a real breach in the filled rock
local TUNNEL_STEP = 18 -- raw studs between carve steps along a tunnel

-- Carves a tunnel as a chain of overlapping FillBall Water spheres from a
-- point beyond the mountain's filled surface, through the entry threshold,
-- continuing in the SAME direction to the interior cavern -- a real,
-- unbroken, open channel: never a visual opening with solid rock hiding
-- behind it, because every step along the line is actively carved.
local function carveTunnel(terrain: Terrain, outerRawPoint: Vector3, innerWorldPoint: Vector3, toWorld, scale: number, radius: number)
	local outerWorldPoint = toWorld(outerRawPoint)
	local direction = innerWorldPoint - outerWorldPoint
	local length = direction.Magnitude
	if length < 1 then
		return
	end
	direction = direction / length

	local steps = math.max(2, math.floor(length / (TUNNEL_STEP * scale)))
	for i = 0, steps do
		local point = outerWorldPoint + direction * (length * i / steps)
		terrain:FillBall(point, radius, Enum.Material.Water)
	end
end

local function buildEntries(terrain: Terrain, data, toWorld, scale: number, mainCavernCenter: Vector3, entryPointsFolder: Folder)
	for index, entry in ipairs(data.Entries) do
		local direction = (entry.CorridorCenter - data.MassCenter)
		if direction.Magnitude < 1 then
			direction = Vector3.new(1, 0, 0)
		else
			direction = direction.Unit
		end
		local outerRawPoint = entry.CorridorCenter + direction * TUNNEL_OUTER_MARGIN

		-- The first entry per region is the "grand" one; the rest are
		-- generously sized secondary/side entries -- all comfortably
		-- larger than a swimming player, none of them a crawl space.
		local radius = (index == 1) and (28 * scale) or (18 * scale)
		carveTunnel(terrain, outerRawPoint, mainCavernCenter, toWorld, scale, radius)

		local breachWorldPoint = toWorld(outerRawPoint)
		local marker = Instance.new("Part")
		marker.Name = "EntryPoint_" .. entry.Name
		marker.Anchored = true
		marker.CanCollide = false
		marker.CanQuery = false
		marker.CanTouch = false
		marker.Transparency = 1
		marker.Size = Vector3.new(1, 1, 1)
		marker.CFrame = CFrame.new(breachWorldPoint)
		local attachment = Instance.new("Attachment")
		attachment.Parent = marker
		marker.Parent = entryPointsFolder
	end
end

-- Ruins / terraces / corals ---------------------------------------------------------

local function buildProp(seed, parent: Instance, toWorld, scale: number, material: Enum.Material, collide: boolean)
	local part = Instance.new("Part")
	part.Name = seed.Name
	part.Anchored = true
	part.CanTouch = false
	part.CanCollide = collide
	part.CanQuery = collide
	part.Material = material
	part.Color = seed.Color or Color3.fromRGB(110, 115, 122)
	-- Coral seeds carry no Size (the builder picks their size itself, see
	-- below); everything else (Ruins, Terraces) has one from the source data.
	if seed.Size then
		part.Size = Vector3.new(math.max(seed.Size.X * scale, 1), math.max(seed.Size.Z * scale, 1), math.max(seed.Size.Y * scale, 1))
	else
		part.Size = Vector3.new(1, 1, 1)
	end
	part.CFrame = CFrame.new(toWorld(seed.Center))
	part.Parent = parent
	return part
end

-- Spawn regions / landmarks -----------------------------------------------------------

local function addSpawnRegion(parent: Instance, name: string, center: Vector3, size: Vector3, kind: string, extra: { [string]: any }?)
	local region = Instance.new("Part")
	region.Name = name
	region.Anchored = true
	region.CanCollide = false
	region.CanQuery = false
	region.CanTouch = false
	region.Transparency = 1
	region.Size = size
	region.CFrame = CFrame.new(center)
	region.Parent = parent

	local CollectionService = game:GetService("CollectionService")
	CollectionService:AddTag(region, "SpawnRegion")
	region:SetAttribute("RegionKind", kind)
	region:SetAttribute("RegionEnabled", true)
	if extra then
		for key, value in pairs(extra) do
			region:SetAttribute(key, value)
		end
	end
	return region
end

-- Build ---------------------------------------------------------------------------

-- config: { WorldCenter: Vector3, Scale: number, Yaw: number (radians),
--           Name: string, DisplayName: string, TreasureCount: number,
--           CreatureSpecies: string }
function CaveRegionBuilder.Build(data, config, parentFolder: Instance)
	local Workspace = game:GetService("Workspace")
	local terrain = Workspace.Terrain

	local regionFolder = Instance.new("Folder")
	regionFolder.Name = config.Name
	regionFolder.Parent = parentFolder

	local ruinsFolder = Instance.new("Folder")
	ruinsFolder.Name = "Ruins"
	ruinsFolder.Parent = regionFolder
	local terracesFolder = Instance.new("Folder")
	terracesFolder.Name = "Terraces"
	terracesFolder.Parent = regionFolder
	local coralFolder = Instance.new("Folder")
	coralFolder.Name = "Coral"
	coralFolder.Parent = regionFolder
	local entryPointsFolder = Instance.new("Folder")
	entryPointsFolder.Name = "EntryPoints"
	entryPointsFolder.Parent = regionFolder
	local landmarksFolder = Instance.new("Folder")
	landmarksFolder.Name = "Landmarks"
	landmarksFolder.Parent = regionFolder
	local lootSpotsFolder = Instance.new("Folder")
	lootSpotsFolder.Name = "LootSpots"
	lootSpotsFolder.Parent = regionFolder

	local baseCFrame = CFrame.new(config.WorldCenter) * CFrame.Angles(0, config.Yaw or 0, 0)
	local scale = config.Scale

	local function toWorld(rawPoint: Vector3): Vector3
		return (baseCFrame * CFrame.new(remapAxes(rawPoint - data.MassCenter) * scale)).Position
	end

	-- 1. Solid rock mass, widest tiers first.
	fillMassTiers(terrain, data, toWorld, scale)

	-- 2. Main interior cavern: an explicit Cave seed if the source has one
	-- (Region 1/2), otherwise synthesized at the mass centroid (Region 3/4,
	-- whose "with entries" versions describe entries/corridors but no
	-- separate interior chamber -- see CaveRegion3Data/4Data's header).
	local mainCavernWorld = toWorld(Vector3.new(0, 0, 0))
	if #data.Cave > 0 then
		local biggest = data.Cave[1]
		for _, cave in ipairs(data.Cave) do
			if cave.Size.X * cave.Size.Y * cave.Size.Z > biggest.Size.X * biggest.Size.Y * biggest.Size.Z then
				biggest = cave
			end
		end
		mainCavernWorld = toWorld(biggest.Center)
		carveCavern(terrain, mainCavernWorld, biggest.Size, scale)
		for _, cave in ipairs(data.Cave) do
			if cave ~= biggest then
				local secondaryCenter = toWorld(cave.Center)
				carveCavern(terrain, secondaryCenter, cave.Size, scale, 3.5)
				-- Connect every secondary chamber back to the main one --
				-- a real network, not isolated bubbles (see the brief's
				-- "entrer par un endroit, ressortir loin par une autre").
				carveTunnel(terrain, cave.Center, mainCavernWorld, toWorld, scale, 16 * scale)
			end
		end
	else
		carveCavern(terrain, mainCavernWorld, Vector3.new(70, 60, 50), scale, 1)
	end

	-- 3. Entries + the tunnels connecting them to the main cavern.
	buildEntries(terrain, data, toWorld, scale, mainCavernWorld, entryPointsFolder)

	-- 4. A vertical shaft from the main cavern up toward the mountain's
	-- peak-ish region, and one continuing down toward its base -- every
	-- region gets real vertical passages, not just horizontal tunnels.
	local peakRaw, baseRaw = nil, nil
	for _, seed in ipairs(data.Mass) do
		if not peakRaw or seed.Center.Z > peakRaw.Z then
			peakRaw = seed.Center
		end
		if not baseRaw or seed.Center.Z < baseRaw.Z then
			baseRaw = seed.Center
		end
	end
	if peakRaw then
		carveTunnel(terrain, Vector3.new(peakRaw.X, peakRaw.Y, peakRaw.Z + 25), mainCavernWorld, toWorld, scale, 14 * scale)
	end
	if baseRaw then
		carveTunnel(terrain, Vector3.new(baseRaw.X, baseRaw.Y, baseRaw.Z - 15), mainCavernWorld, toWorld, scale, 14 * scale)
	end

	-- 5. Ruins, terraces, coral -- real visible/walkable Parts.
	for _, seed in ipairs(data.Ruins) do
		buildProp(seed, ruinsFolder, toWorld, scale, Enum.Material.Slate, true)
	end
	for _, seed in ipairs(data.Terraces) do
		buildProp(seed, terracesFolder, toWorld, scale, Enum.Material.Rock, true)
	end
	for _, seed in ipairs(data.Corals) do
		local coral = buildProp(seed, coralFolder, toWorld, scale, Enum.Material.SmoothPlastic, false)
		coral.Size = Vector3.new(3 + math.random() * 3, 3 + math.random() * 4, 3 + math.random() * 3)
	end

	-- 6. Landmarks (source-authored spawn markers, if any).
	for _, seed in ipairs(data.Markers) do
		local marker = Instance.new("Part")
		marker.Name = seed.Name
		marker.Anchored = true
		marker.CanCollide = false
		marker.CanQuery = false
		marker.Transparency = 1
		marker.Size = Vector3.new(1, 1, 1)
		marker.CFrame = CFrame.new(toWorld(seed.Center))
		local attachment = Instance.new("Attachment")
		attachment.Parent = marker
		marker.Parent = landmarksFolder
	end

	-- 7. Future gameplay: loot in the main cavern, creatures roaming the
	-- whole region -- same SpawnRegion tag SpawnRegions.lua/TreasureSpawner
	-- /CreatureSpawner already read, so this needs no new plumbing.
	addSpawnRegion(lootSpotsFolder, "LootSpot_MainCavern", mainCavernWorld, Vector3.new(80, 40, 80) * (scale / 2.2), "Treasure", {
		RegionCount = config.TreasureCount or 5,
	})
	addSpawnRegion(regionFolder, "CreatureRegion", config.WorldCenter, Vector3.new(900, 400, 900) * (scale / 2.2), "Creature", {
		RegionCount = config.CreatureCount or 4,
		RegionSpecies = config.CreatureSpecies or "Requin,Raie",
	})

	regionFolder:SetAttribute("DisplayName", config.DisplayName)
	print(string.format("[CaveRegionBuilder] %s built at %s (scale %.1fx, %d entries, %d ruins)",
		config.Name, tostring(config.WorldCenter), scale, #data.Entries, #data.Ruins))

	return regionFolder
end

return CaveRegionBuilder
