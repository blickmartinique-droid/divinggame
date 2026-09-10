-- Places the 4 mountain/cave regions (see CaveRegionBuilder.lua for how
-- each is actually built) and a handful of Path currents linking them to
-- each other and toward the Épave zone. Never touches MegaWreckShip.
--
-- Region placement was chosen to give each a full ~700-900 stud clearance
-- from the wreck, from each other, and from the existing beach/current/
-- decor placements (checked against their real extents, not just eyeballed):
--   Region 1 -- Montagnes & arches (blockout model): shallow-mid water,
--     Grottes reaching just up into Récif, far NE of the beach.
--   Region 2 -- Réseau de cavernes (v2, has its own abyssal pit built in):
--     mid-to-deep water, far NW.
--   Region 3 -- Ruines sous-marines (v3, explicit named entries): near
--     the Épave zone (visible from it, per the brief) but with enough
--     separation from the wreck's own ~724-stud footprint that neither
--     overlaps.
--   Region 4 -- Zone abyssale (v4, the most elaborate: "citadel"/"high
--     sanctum" chambers): the deepest, far SW.
--
-- Scale (2.2x) turns each ~320-420-stud-wide source model into a
-- ~700-900-stud region -- comparable to MegaWreckShip's own ~724-stud
-- length, and each region's vertical extent (~140-220 studs at this
-- scale) fits within a single depth-zone band rather than spanning the
-- whole water column.

local Workspace = game:GetService("Workspace")

local CaveRegionBuilder = require(script.Parent.CaveRegionBuilder)

local worldFolder = Workspace:FindFirstChild("World") or Instance.new("Folder", Workspace)
worldFolder.Name = "World"
local underwaterFolder = worldFolder:FindFirstChild("Underwater") or Instance.new("Folder", worldFolder)
underwaterFolder.Name = "Underwater"

local existing = underwaterFolder:FindFirstChild("CaveRegions")
if existing then
	existing:Destroy()
end
local caveRegionsFolder = Instance.new("Folder")
caveRegionsFolder.Name = "CaveRegions"
caveRegionsFolder.Parent = underwaterFolder

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
			CreatureSpecies = "Sardine,Tortue,Raie",
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
			CreatureSpecies = "Raie,Requin",
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
			CreatureSpecies = "Requin,Raie",
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
			CreatureSpecies = "Requin,Baudroie",
		},
	},
}

local built = {}
for _, region in ipairs(REGIONS) do
	local data = require(script.Parent[region.module])
	built[region.config.Name] = CaveRegionBuilder.Build(data, region.config, caveRegionsFolder)
end

-- Connector currents -----------------------------------------------------------------
-- Reuses the existing current system as-is (CurrentGenerator.server.lua's
-- ChildAdded listener decorates any current placed in Workspace.Currents
-- at runtime, exactly like this) rather than inventing a second way to
-- link regions -- ties the 4 new regions and the Épave zone into one
-- world without a single line of the current system changing.

local currentsFolder = Workspace:FindFirstChild("Currents")
if not currentsFolder then
	currentsFolder = Instance.new("Folder")
	currentsFolder.Name = "Currents"
	currentsFolder.Parent = Workspace
end

local function createPathCurrent(name: string, displayName: string, tier: string, width: number, points: { Vector3 })
	local model = Instance.new("Model")
	model.Name = name
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
	end
	model:SetAttribute("CurrentShape", "Path")
	model:SetAttribute("CurrentTier", tier)
	model:SetAttribute("CurrentDisplayName", displayName)
	model:SetAttribute("CurrentWidth", width)
	model.Parent = currentsFolder
	return model
end

-- Région 1 <-> Région 2: a long mid-water crossing between the two
-- mountain regions, dipping slightly to avoid the beach/reef currents.
createPathCurrent("Region1To2Current", "Traversée des montagnes", "Medium", 20, {
	Vector3.new(500, -260, 350),
	Vector3.new(150, -280, 100),
	Vector3.new(-200, -300, 200),
	Vector3.new(-550, -320, 450),
})

-- Région 3 <-> Région 4: a deep connector heading further into the abyss.
createPathCurrent("Region3To4Current", "Faille vers l'abysse", "Strong", 18, {
	Vector3.new(650, -390, -700),
	Vector3.new(300, -410, -580),
	Vector3.new(-100, -430, -470),
	Vector3.new(-550, -430, -420),
})

-- Épave (Region 3's neighbour) <-> Région 3: ends in open water well
-- clear of MegaWreckShip's own footprint -- never touches the wreck
-- itself, just gives divers leaving it somewhere new to head toward.
createPathCurrent("EpaveToRuinsCurrent", "Sortie vers les ruines", "Medium", 16, {
	Vector3.new(400, -370, -350),
	Vector3.new(580, -365, -560),
	Vector3.new(750, -360, -740),
})

print("[CaveRegions] 4 regions + 3 connector currents built")
