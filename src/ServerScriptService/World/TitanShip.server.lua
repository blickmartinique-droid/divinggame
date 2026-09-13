-- Builds the TITAN -- a huge sunken research/exploration vessel -- from
-- TitanShipData.lua, an auto-generated table of ~3753 part records
-- extracted from Archipel_des_Profondeurs.blend (see that file's header
-- for exactly how). Replaces MegaWreckShip entirely, per instruction:
-- "enlever l'ancien bateau ... par [le contenu du nouveau fichier]".
--
-- UNLIKE MegaWreckShip: that source model was arbitrary curved geometry,
-- so its ~645 parts are PCA-derived oriented-box approximations. This
-- source model is built entirely from Blender primitives (box/cylinder/
-- sphere), so every record's Shape/Center/Right/Up/Size is the real,
-- exact transform -- nothing approximated. The only conversion applied
-- (done once, in the Python extraction script, not here) is the
-- coordinate basis change Blender Z-up -> Roblox Y-up, (x,y,z)->(x,z,-y)
-- (a proper rotation, not a reflection -- preserves handedness) plus a
-- +(300,0,300) world offset chosen to clear the existing beach at the
-- origin. Depth is otherwise 1:1 -- the source file's own units already
-- match this game's "1 stud = 1 metre" depth convention (confirmed: its
-- deepest point lands at -501, this game's seafloor is -500), so unlike
-- MegaWreckShip there is no extra SHIP_SCALE here.
--
-- Hierarchy: Workspace/World/Underwater/WreckZone/TitanShip --
--   Exterior: Hull, Superstructure (the outer envelope + weather deck).
--   Interior: Ballast, Machines, Laboratoires, Habitats, Promenade,
--             Infirmerie, Passerelle -- the 7 decks, bow to stern order
--             matches the source file's own D00..D06 collections.
-- plus Lighting, Landmarks, LootSpots, CreatureRegion.
--
-- Hull/entrance safety: unlike MegaWreckShip there is no breach
-- bookkeeping to maintain by hand -- almost every panel (Cloison, Sol,
-- Hublot...) is placed at its own exact real position from the source
-- file, so wherever the original designer left a real gap (a doorway, a
-- porthole run, an open deck edge) that gap exists in Roblox too, simply
-- by including the record faithfully. One real exception was found and
-- excluded at the data stage, not here: TITAN_Coque's "Coque_Creuse_-1/1"
-- (hollow hull shell) and "Baies_Laterales_-1/1" (its own bay openings)
-- share the exact same bounding box, so reconstructing either as a single
-- oriented box would have rebuilt it as one giant solid 328-stud slab --
-- exactly MegaWreckShip's old "hull_layer" bug (see its header). See
-- TitanShipData.lua's header for why they are skipped; Hull below is only
-- the 3 genuine end-cap plates, and Superstructure's own 466 panels are
-- what actually define the visible/collidable exterior envelope.

local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")

local ShipData = require(script.Parent.TitanShipData)

-- Folders -----------------------------------------------------------------------

local function ensureFolder(parent: Instance, name: string): Folder
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("Folder") then
		return existing
	end
	if existing then
		existing:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

local worldFolder = ensureFolder(Workspace, "World")
local underwaterFolder = ensureFolder(worldFolder, "Underwater")
local wreckZoneFolder = ensureFolder(underwaterFolder, "WreckZone")

local existingShip = wreckZoneFolder:FindFirstChild("TitanShip")
if existingShip then
	existingShip:Destroy()
end
-- The old ship, if this is running right after an upgrade from a save that
-- still has it, is removed here too -- "enlever l'ancien bateau" applies
-- even if MegaWreckShip.server.lua's own file is already gone from source.
local staleOldShip = wreckZoneFolder:FindFirstChild("MegaWreckShip")
if staleOldShip then
	staleOldShip:Destroy()
end

local shipFolder = Instance.new("Folder")
shipFolder.Name = "TitanShip"
shipFolder.Parent = wreckZoneFolder

local exteriorFolder = ensureFolder(shipFolder, "Exterior")
local interiorFolder = ensureFolder(shipFolder, "Interior")

local CATEGORY_PARENT = {
	Hull = exteriorFolder,
	Superstructure = exteriorFolder,
	Ballast = interiorFolder,
	Machines = interiorFolder,
	Laboratoires = interiorFolder,
	Habitats = interiorFolder,
	Promenade = interiorFolder,
	Infirmerie = interiorFolder,
	Passerelle = interiorFolder,
}

-- Deck order matches the source file's own D00..D06 numbering (bow to
-- stern / bottom to top), used below for both folder creation order and
-- Lighting/LootSpot naming -- purely cosmetic (Explorer order), no
-- gameplay depends on it.
local DECK_ORDER = { "Ballast", "Machines", "Laboratoires", "Habitats", "Promenade", "Infirmerie", "Passerelle" }

local categoryFolders = {}
for _, category in ipairs({ "Hull", "Superstructure" }) do
	categoryFolders[category] = ensureFolder(CATEGORY_PARENT[category], category)
end
for _, category in ipairs(DECK_ORDER) do
	categoryFolders[category] = ensureFolder(CATEGORY_PARENT[category], category)
end

local lightingFolder = ensureFolder(shipFolder, "Lighting")
local landmarksFolder = ensureFolder(shipFolder, "Landmarks")
local lootSpotsFolder = ensureFolder(shipFolder, "LootSpots")

-- Building ------------------------------------------------------------------------

local PART_SHAPE = {
	Block = Enum.PartType.Block,
	Cylinder = Enum.PartType.Cylinder,
	Ball = Enum.PartType.Ball,
}

-- Every material name in TitanShipData.lua was hand-picked from Roblox's
-- real Enum.Material list while generating it (see that file's palette) --
-- indexed straight through rather than re-validated per part, which is
-- exactly the kind of extra bookkeeping that hid the previous
-- "Enum.Material.Rope" typo. This lookup instead FAILS LOUD at the very
-- first bad name (Enum indexing errors immediately, it does not silently
-- return nil), so a typo here still crashes the whole script at load --
-- exactly like before, and exactly what makes it safe to trust afterwards.
local MATERIAL = setmetatable({}, {
	__index = function(t, key)
		local value = Enum.Material[key]
		rawset(t, key, value)
		return value
	end,
})

-- Neon-lit fixtures (screens, glow strips) shouldn't block a diver, and
-- there are enough of them scattered through every deck that leaving them
-- solid would make corridors feel snaggy for no gameplay reason.
local function shouldCollide(record)
	return record.Material ~= "Neon"
end

local aabb = {} -- [category] = { min = Vector3, max = Vector3 }
local function trackAabb(category: string, position: Vector3)
	local box = aabb[category]
	if not box then
		aabb[category] = { min = position, max = position }
		return
	end
	box.min = Vector3.new(math.min(box.min.X, position.X), math.min(box.min.Y, position.Y), math.min(box.min.Z, position.Z))
	box.max = Vector3.new(math.max(box.max.X, position.X), math.max(box.max.Y, position.Y), math.max(box.max.Z, position.Z))
end

for _, record in ipairs(ShipData) do
	local folder = categoryFolders[record.Category]
	if not folder then
		continue
	end
	local part = Instance.new("Part")
	part.Name = record.Name
	part.Shape = PART_SHAPE[record.Shape] or Enum.PartType.Block
	part.Anchored = true
	part.CanTouch = false
	part.CanQuery = true
	part.CastShadow = false -- thousands of parts; shadow-casting is reserved for the small Lighting fixtures below
	part.CFrame = CFrame.fromMatrix(record.Center, record.Right, record.Up)
	part.Size = record.Size
	part.Color = record.Color
	part.Material = MATERIAL[record.Material]
	part.CanCollide = shouldCollide(record)
	part.Parent = folder
	trackAabb(record.Category, record.Center)
end

-- Lighting ------------------------------------------------------------------------
-- The source file's own light placements (Lumiere_D0.._D6..), converted
-- from Blender's Watt-scale energy to a small, cheap Roblox Brightness/
-- Range so thousands of parts + ~20 lights stays light on the renderer --
-- guidance lights, not room-filling ones, matching this project's existing
-- "dark but legible" interior lighting philosophy (see the old
-- MegaWreckShip header for why: never a bright, evenly-lit interior).
local TITAN_LIGHTS = {
	{Name="Lumiere_D0_-102",Pos=Vector3.new(198.9045,-207.9051,340.0000),Color=Color3.new(0.3000,0.7800,1.0000),Energy=450.0},
	{Name="Lumiere_D0_-14",Pos=Vector3.new(286.7404,-202.5329,340.0000),Color=Color3.new(0.3000,0.7800,1.0000),Energy=450.0},
	{Name="Lumiere_D0_74",Pos=Vector3.new(374.5762,-197.1606,340.0000),Color=Color3.new(0.3000,0.7800,1.0000),Energy=450.0},
	{Name="Lumiere_D1_-102",Pos=Vector3.new(198.5871,-202.7148,340.0000),Color=Color3.new(0.3000,0.7800,1.0000),Energy=450.0},
	{Name="Lumiere_D1_-14",Pos=Vector3.new(286.4229,-197.3426,340.0000),Color=Color3.new(0.3000,0.7800,1.0000),Energy=450.0},
	{Name="Lumiere_D1_74",Pos=Vector3.new(374.2588,-191.9703,340.0000),Color=Color3.new(0.3000,0.7800,1.0000),Energy=450.0},
	{Name="Lumiere_D2_-102",Pos=Vector3.new(198.2696,-197.5245,340.0000),Color=Color3.new(0.3000,0.7800,1.0000),Energy=450.0},
	{Name="Lumiere_D2_-14",Pos=Vector3.new(286.1055,-192.1523,340.0000),Color=Color3.new(0.3000,0.7800,1.0000),Energy=450.0},
	{Name="Lumiere_D2_74",Pos=Vector3.new(373.9413,-186.7800,340.0000),Color=Color3.new(0.3000,0.7800,1.0000),Energy=450.0},
	{Name="Lumiere_D3_-102",Pos=Vector3.new(197.9522,-192.3342,340.0000),Color=Color3.new(0.3000,0.7800,1.0000),Energy=450.0},
	{Name="Lumiere_D3_-14",Pos=Vector3.new(285.7880,-186.9620,340.0000),Color=Color3.new(0.3000,0.7800,1.0000),Energy=450.0},
	{Name="Lumiere_D3_74",Pos=Vector3.new(373.6239,-181.5897,340.0000),Color=Color3.new(0.3000,0.7800,1.0000),Energy=450.0},
	{Name="Lumiere_D4_-102",Pos=Vector3.new(197.6347,-187.1439,340.0000),Color=Color3.new(0.3000,0.7800,1.0000),Energy=450.0},
	{Name="Lumiere_D4_-14",Pos=Vector3.new(285.4706,-181.7717,340.0000),Color=Color3.new(0.3000,0.7800,1.0000),Energy=450.0},
	{Name="Lumiere_D4_74",Pos=Vector3.new(373.3064,-176.3994,340.0000),Color=Color3.new(0.3000,0.7800,1.0000),Energy=450.0},
	{Name="Lumiere_D5_-102",Pos=Vector3.new(197.3173,-181.9536,340.0000),Color=Color3.new(0.3000,0.7800,1.0000),Energy=450.0},
	{Name="Lumiere_D5_-14",Pos=Vector3.new(285.1531,-176.5814,340.0000),Color=Color3.new(0.3000,0.7800,1.0000),Energy=450.0},
	{Name="Lumiere_D5_74",Pos=Vector3.new(372.9890,-171.2091,340.0000),Color=Color3.new(0.3000,0.7800,1.0000),Energy=450.0},
	{Name="Lumiere_D6_-14",Pos=Vector3.new(284.8357,-171.3911,340.0000),Color=Color3.new(0.3000,0.7800,1.0000),Energy=450.0},
	{Name="Lumiere_D6_74",Pos=Vector3.new(372.6715,-166.0188,340.0000),Color=Color3.new(0.3000,0.7800,1.0000),Energy=450.0},
}

local function addLight(name: string, worldPosition: Vector3, color: Color3, energy: number)
	local anchor = Instance.new("Part")
	anchor.Name = name
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.CastShadow = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.5, 0.5, 0.5)
	anchor.CFrame = CFrame.new(worldPosition)
	anchor.Parent = lightingFolder
	local light = Instance.new("PointLight")
	light.Color = color
	light.Brightness = math.clamp(energy / 300, 0.5, 4)
	light.Range = 26
	light.Shadows = false
	light.Parent = anchor
end

for _, light in ipairs(TITAN_LIGHTS) do
	addLight(light.Name, light.Pos, light.Color, light.Energy)
end

-- Landmarks -----------------------------------------------------------------------

local function createMarker(parent: Instance, name: string, worldPosition: Vector3)
	local anchor = Instance.new("Part")
	anchor.Name = name
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(1, 1, 1)
	anchor.CFrame = CFrame.new(worldPosition)
	local attachment = Instance.new("Attachment")
	attachment.Parent = anchor
	anchor.Parent = parent
	return anchor
end

createMarker(landmarksFolder, "Navire — machines", Vector3.new(215.7000, -204.6000, 340.0000))
createMarker(landmarksFolder, "Navire — pont supérieur", Vector3.new(219.1000, -178.3000, 340.0000))

-- Loot spots + creature region ------------------------------------------------------
-- One SpawnRegion per deck, sized to that deck's own real bounding box
-- (tracked above while building), so treasures land inside real rooms with
-- zero extra authoring -- same mechanism as MegaWreckShip/CaveRegionBuilder.
local function addSpawnRegion(parent: Instance, name: string, center: Vector3, size: Vector3, kind: string, attributes: { [string]: any })
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
	CollectionService:AddTag(region, "SpawnRegion")
	region:SetAttribute("RegionKind", kind)
	region:SetAttribute("RegionEnabled", true)
	for key, value in pairs(attributes) do
		region:SetAttribute(key, value)
	end
	return region
end

local DECK_LOOT_COUNT = {
	Ballast = 3, Machines = 4, Laboratoires = 5, Habitats = 4,
	Promenade = 3, Infirmerie = 3, Passerelle = 2,
}

local shipMin, shipMax = nil, nil
for category, box in pairs(aabb) do
	shipMin = shipMin and Vector3.new(math.min(shipMin.X, box.min.X), math.min(shipMin.Y, box.min.Y), math.min(shipMin.Z, box.min.Z)) or box.min
	shipMax = shipMax and Vector3.new(math.max(shipMax.X, box.max.X), math.max(shipMax.Y, box.max.Y), math.max(shipMax.Z, box.max.Z)) or box.max

	local count = DECK_LOOT_COUNT[category]
	if count then
		local center = (box.min + box.max) / 2
		local size = (box.max - box.min) + Vector3.new(4, 4, 4)
		addSpawnRegion(lootSpotsFolder, "LootSpot_" .. category, center, size, "Treasure", { RegionCount = count })
	end
end

if shipMin and shipMax then
	local shipCenter = (shipMin + shipMax) / 2
	local shipSize = (shipMax - shipMin) + Vector3.new(80, 60, 80) -- margin so patrol species roam around the hull too, not just through it
	addSpawnRegion(shipFolder, "TitanCreatureRegion", shipCenter, shipSize, "Creature", {
		RegionCount = 5,
		RegionSpecies = "RequinRecif,RaieManta",
	})
end

print(string.format("[TitanShip] built (%d parts, %d lights, %d loot spots)", #ShipData, #TITAN_LIGHTS, #DECK_ORDER))
