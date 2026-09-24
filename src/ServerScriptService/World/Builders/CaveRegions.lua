-- Places the 4 mountain/cave regions (see CaveRegionBuilder.lua for how
-- each is actually built) and a handful of Path currents linking them to
-- each other and toward the Épave zone. Runs right after the ocean fill
-- (WorldBootstrap) -- it carves into that water, so it must never run
-- first: an ocean fill after it would drown every mountain.
--
--   Region 1 -- Montagnes & arches (blockout model): shallow-mid water,
--     Grottes reaching just up into Récif, far NE of the beach.
--   Region 2 -- Réseau de cavernes (v2, has its own abyssal pit built in):
--     mid-to-deep water, far NW.
--   Region 3 -- Ruines sous-marines (v3, explicit named entries): near
--     the Épave zone, clear of the wreck's own footprint.
--   Region 4 -- Zone abyssale (v4, "citadel"/"high sanctum" chambers):
--     the deepest, far SW.
--
-- Scale (2.2x) turns each ~320-420-stud-wide source model into a
-- ~700-900-stud region, each within roughly one depth-zone band.

local Workspace = game:GetService("Workspace")

local CaveRegionBuilder = require(script.Parent.CaveRegionBuilder)
local WorldLayout = require(script.Parent.WorldLayout)
local Ocean = require(script.Parent.Ocean)

local CaveRegions = {}

local REGIONS = {
	{
		module = "CaveRegion1Data",
		config = {
			Name = "Region1_MountainsAndArches",
			DisplayName = "Montagnes de l'arche brisée",
			WorldCenter = Vector3.new(750, -230, 500),
			Scale = 2.2,
			Yaw = math.rad(17),
			TreasureCount = 6,
			CreatureCount = 4,
			CreatureSpecies = "RaieManta,RequinRecif", -- a cathedral-sized chamber in the Grottes band
		},
	},
	{
		module = "CaveRegion2Data",
		config = {
			Name = "Region2_CavernNetwork",
			DisplayName = "Réseau des cavernes abyssales",
			WorldCenter = Vector3.new(-750, -330, 600),
			Scale = 2.2,
			Yaw = math.rad(-29),
			TreasureCount = 8,
			CreatureCount = 5,
			CreatureSpecies = "MeduseLumineuse,RaieManta",
		},
	},
	{
		module = "CaveRegion3Data",
		config = {
			Name = "Region3_SunkenRuins",
			DisplayName = "Ruines englouties",
			WorldCenter = Vector3.new(850, -360, -820),
			Scale = 2.2,
			Yaw = math.rad(63),
			TreasureCount = 8,
			CreatureCount = 5,
			CreatureSpecies = "MeduseLumineuse,RequinRecif",
		},
	},
	{
		module = "CaveRegion4Data",
		config = {
			Name = "Region4_AbyssalDepths",
			DisplayName = "Cité abyssale",
			WorldCenter = Vector3.new(-750, -440, -400),
			Scale = 2.2,
			Yaw = math.rad(-80),
			TreasureCount = 10,
			CreatureCount = 5,
			CreatureSpecies = "MeduseLumineuse", -- glowing drifters in the lightless citadel
		},
	},
}

local function ensureFolder(parent: Instance, name: string): Instance
	local existing = parent:FindFirstChild(name)
	if existing then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

-- Connector currents -----------------------------------------------------------------
-- Reuses the existing current system as-is (Currents.lua decorates
-- everything in Workspace.Currents, including these) rather than
-- inventing a second way to link regions.

-- Endpoints name a region entry ({ region, entry }): the current starts
-- or ends in the open water just outside that cave mouth, wherever the
-- rock actually ended up, instead of at a hand-picked coordinate that may
-- sit inside the mountain.
local CONNECTORS = {
	-- Région 1 <-> Région 2: a long mid-water crossing, well below the beach.
	{ name = "Region1To2Current", display = "Traversée des montagnes", tier = "Medium", width = 20, points = {
		{ region = "Region1_MountainsAndArches", entry = "side_tunnel" },
		Vector3.new(300, -300, 330),
		Vector3.new(-200, -330, 380),
		{ region = "Region2_CavernNetwork", entry = "lower_cave" },
	} },
	-- Région 3 <-> Région 4: a deep connector heading further into the abyss.
	{ name = "Region3To4Current", display = "Faille vers l'abysse", tier = "Strong", width = 18, points = {
		{ region = "Region3_SunkenRuins", entry = "south_entry" },
		Vector3.new(300, -420, -620),
		Vector3.new(-100, -440, -560),
		{ region = "Region4_AbyssalDepths", entry = "west_lower_entry" },
	} },
	-- Épave <-> Région 3: gives divers leaving the wreck somewhere new to go.
	{ name = "EpaveToRuinsCurrent", display = "Sortie vers les ruines", tier = "Medium", width = 16, points = {
		Vector3.new(560, -330, -500),
		Vector3.new(700, -350, -580),
		{ region = "Region3_SunkenRuins", entry = "left_entry" },
	} },
}

local function resolvePoint(point, infosByName): Vector3?
	if typeof(point) == "Vector3" then
		return point
	end
	local info = infosByName[point.region]
	for _, entry in ipairs(info and info.entries or {}) do
		if entry.name == point.entry then
			return entry.exit + entry.direction * 30
		end
	end
	return nil
end

local function createPathCurrent(currentsFolder: Instance, spec, points: { Vector3 }, layout)
	local model = Instance.new("Model")
	model.Name = spec.name
	for index, position in ipairs(points) do
		local point = Instance.new("Part")
		point.Name = string.format("CurrentPoint_%02d", index)
		point.Anchored = true
		point.CanCollide = false
		point.CanQuery = false
		point.Transparency = 1
		point.Size = Vector3.new(2, 2, 2)
		point.CFrame = CFrame.new(position)
		point.Parent = model
		if index > 1 then
			layout:ReserveCapsule(spec.name, points[index - 1], position, spec.width)
		end
	end
	model:SetAttribute("CurrentShape", "Path")
	model:SetAttribute("CurrentTier", spec.tier)
	model:SetAttribute("CurrentDisplayName", spec.display)
	model:SetAttribute("CurrentWidth", spec.width)
	model.Parent = currentsFolder
	return model
end

function CaveRegions.Build(layout)
	local worldFolder = ensureFolder(Workspace, "World")
	local underwaterFolder = ensureFolder(worldFolder, "Underwater")
	local existing = underwaterFolder:FindFirstChild("CaveRegions")
	if existing then
		existing:Destroy()
	end
	local caveRegionsFolder = Instance.new("Folder")
	caveRegionsFolder.Name = "CaveRegions"
	caveRegionsFolder.Parent = underwaterFolder

	local infos = {}
	for _, region in ipairs(REGIONS) do
		local data = require(script.Parent[region.module])
		local _, info = CaveRegionBuilder.Build(data, region.config, caveRegionsFolder, layout:Random(region.config.Name))
		info.name = region.config.Name
		table.insert(infos, info)
		-- The whole mountain, so later decor keeps its spires off it.
		local extent = info.extent
		layout:ReserveCylinder(region.config.Name, info.center, extent.radius, extent.minY, extent.maxY)
	end
	layout:SetAnchor("CaveRegions", infos)

	-- Tunnels aimed at a mountain's base can carve right through the rock
	-- seafloor into the void beneath it (a hole to fall through). Re-lay
	-- the floor slab under every region -- nothing legitimate lives below
	-- the seafloor.
	local terrain = Workspace.Terrain
	local floorY = WorldLayout.FloorY
	for _, info in ipairs(infos) do
		local half = info.extent.radius + 20
		local minX = math.max(info.center.X - half, -WorldLayout.OceanHalfWidth)
		local maxX = math.min(info.center.X + half, WorldLayout.OceanHalfWidth)
		local minZ = math.max(info.center.Z - half, -WorldLayout.OceanHalfWidth)
		local maxZ = math.min(info.center.Z + half, WorldLayout.OceanHalfWidth)
		Ocean.FillChunked(terrain, Vector3.new(minX, floorY - 20, minZ), Vector3.new(maxX - minX, 20, maxZ - minZ), Enum.Material.Rock)
	end

	local infosByName = {}
	for _, info in ipairs(infos) do
		infosByName[info.name] = info
	end
	local currentsFolder = ensureFolder(Workspace, "Currents")
	for _, spec in ipairs(CONNECTORS) do
		local points = {}
		for _, point in ipairs(spec.points) do
			local resolved = resolvePoint(point, infosByName)
			if resolved then
				table.insert(points, resolved)
			else
				warn(string.format("[CaveRegions] %s: unknown entry %s.%s", spec.name, tostring(point.region), tostring(point.entry)))
			end
		end
		if #points >= 2 then
			createPathCurrent(currentsFolder, spec, points, layout)
		end
	end

	print(string.format("[CaveRegions] %d regions + %d connector currents built", #infos, #CONNECTORS))
end

return CaveRegions
