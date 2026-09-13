-- Places and hooks up the real "Archipel des Profondeurs V2" map -- TITAN ship
-- + island/mountain/caves/garden/reef/dock -- delivered as pre-built Roblox
-- geometry (Modules/*.rbxmx, ~38600 real Parts/WedgeParts from an actual
-- boolean-carved massif and per-triangle hull, not an approximation) and
-- synced statically by Rojo (see default.project.json's new Workspace tree)
-- rather than reconstructed in Lua. Replaces the old procedural MegaWreckShip
-- /CaveRegionBuilder entirely.
--
-- WHY STATIC RBXMX INSTEAD OF A BUILDER SCRIPT (like every earlier attempt
-- in this project): the pack's own Sources/export_archipel.py already walks
-- the real Blender scene -- booleaned massif, per-triangle hull WedgeParts,
-- real door/room/stair placement -- and was verified with 6698 geometry
-- assertions before delivery. Every earlier from-scratch reconstruction here
-- (MegaWreckShip's PCA-derived boxes, then a full custom Titan/Archipel
-- rebuild) introduced its own bugs along the way (an invisible hull wall, a
-- terrain sphere gulping nearby parts) precisely by re-deriving geometry
-- instead of trusting an already-verified export. This script does no
-- geometry work at all -- it only positions the delivered model and adds
-- this project's gameplay hooks (SpawnRegion tags, Landmarks) on top.
--
-- SCALE: the pack's own default (Sources/export_archipel.py's SCALE=1/.28)
-- targets Roblox's official human-scale convention, 1 stud = 0.28 m -- at
-- that rate the pack's own 500 m of depth becomes 1786 studs, and the 328 m
-- TITAN becomes ~1171 studs long. This project instead uses "1 stud = 1
-- metre" everywhere (ZonesConfig.MaxDepth = 500, OxygenManager, currents...),
-- so the copy of export_archipel.py used to generate assets/ArchipelDesProfondeurs
-- /*.rbxmx had that one constant changed to SCALE=1 before running -- every
-- other line, and all 6698 verified geometry assertions, are untouched.
-- ArchipelManifestData.lua (below) applies the exact same axis remap/scale to
-- the pack's own Plans/manifest.json for the gameplay-hook coordinates, so
-- landmarks and regions line up with the geometry exactly.
--
-- OFFSET: the real exported geometry's own bounding box (computed directly
-- from the generated Parts, not the manifest's more generous water-simulation
-- bounds) is roughly 843x587 studs, centered almost exactly on the world
-- origin -- which is where this game's existing beach/spawn already is. A
-- +(380, 0, 480) shift (X/Z only; depth is already correct at 1:1 scale)
-- clears the beach's ~180-stud shelf/slope with real margin while staying
-- inside the existing 2000x2000 ocean. Applied once here via Model:PivotTo,
-- not baked into the (large, regenerable-from-source) .rbxmx files.

local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")

local ManifestData = require(script.Parent.ArchipelManifestData)

-- Static roots (synced by Rojo, present from server start -- WaitForChild is
-- just the safe idiom, not a real race here).
local wreckZoneFolder = Workspace:WaitForChild("World"):WaitForChild("Underwater"):WaitForChild("WreckZone")
local archipelFolder = Workspace.World.Underwater:WaitForChild("ArchipelDesProfondeurs")

-- Rojo names a $path-synced model instance after the tree key ("TitanShip"),
-- but if a future resync ever surfaces the file's own embedded collection
-- name instead ("02_NAVIRE_TITAN"), find and rename it rather than silently
-- doing nothing.
local function findOrRename(parent: Instance, wantedName: string, fallbackName: string): Instance?
	local found = parent:FindFirstChild(wantedName)
	if found then
		return found
	end
	local fallback = parent:FindFirstChild(fallbackName)
	if fallback then
		fallback.Name = wantedName
		return fallback
	end
	return nil
end

local titanShip = findOrRename(wreckZoneFolder, "TitanShip", "02_NAVIRE_TITAN")
local moduleRenames = {
	SurfaceAccueil = "00_SURFACE_ACCUEIL",
	IleEtMontagne = "01_ILE_ET_MONTAGNE",
	ReseauDeGrottes = "03_RESEAU_DE_GROTTES",
	JardinAbyssal = "04_JARDIN_ABYSSAL",
	RecifEtFauneFixe = "05_RECIF_ET_FAUNE_FIXE",
	QuaiEtCamp = "06_QUAI_ET_CAMP",
}
for wantedName, fallbackName in pairs(moduleRenames) do
	findOrRename(archipelFolder, wantedName, fallbackName)
end

-- Placement: one rigid shift for each root -- every descendant Part moves
-- together, so the model's own internal room/door/stair layout is untouched.
local OFFSET = ManifestData.Offset -- Vector3, X/Z only (see header)
local function shiftInto(root: Instance?)
	if not root or not root:IsA("Model") then
		return
	end
	local pivot = root:GetPivot()
	root:PivotTo(pivot + OFFSET)
end
shiftInto(titanShip)
shiftInto(archipelFolder)

-- Gameplay hooks ------------------------------------------------------------
-- Same SpawnRegion tag/Attribute convention SpawnRegions.lua/TreasureSpawner
-- /CreatureSpawner already read -- built from the pack's own verified real
-- data (room centers+doors, cave node radius/height, navigation waypoints),
-- not guessed placeholder volumes.

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

local landmarksFolder = Instance.new("Folder")
landmarksFolder.Name = "Landmarks"
landmarksFolder.Parent = archipelFolder

local lootSpotsFolder = Instance.new("Folder")
lootSpotsFolder.Name = "LootSpots"
lootSpotsFolder.Parent = archipelFolder

local creatureRegionsFolder = Instance.new("Folder")
creatureRegionsFolder.Name = "CreatureRegions"
creatureRegionsFolder.Parent = archipelFolder

-- Named per-chamber species, matching what each cave's own name suggests;
-- everything else falls back to a general cave-dweller mix.
local CAVE_SPECIES = {
	["Jardin des Méduses"] = "MeduseLumineuse",
	["Cathédrale Abyssale"] = "RequinRecif,MeduseLumineuse",
	["Puits des Echos"] = "MeduseLumineuse",
}
local DEFAULT_CAVE_SPECIES = "RaieManta,RequinRecif,TortueMarine"

-- Landmarks: every named navigation waypoint the pack itself authored.
for _, waypoint in ipairs(ManifestData.Navigation) do
	createMarker(landmarksFolder, waypoint.Name, waypoint.Position)
end

-- Cave chambers: a real Creature SpawnRegion per named cavern, sized to its
-- own real radius/height (not a guessed box).
for _, node in ipairs(ManifestData.CaveNodes) do
	addSpawnRegion(
		creatureRegionsFolder,
		"Grottes_" .. node.Name .. "_Creatures",
		node.Center,
		Vector3.new(node.Radius * 2, node.Height * 2, node.Radius * 2),
		"Creature",
		{ RegionCount = 3, RegionSpecies = CAVE_SPECIES[node.Name] or DEFAULT_CAVE_SPECIES }
	)
end

-- Ship: one loot SpawnRegion per deck usage, sized to that deck's own real
-- room footprint (tracked from every room's real center in the manifest).
local DECK_LOOT_COUNT = {
	BALLAST = 3, MACHINES = 4, LABORATOIRES = 5, HABITATS = 4,
	PROMENADE = 3, INFIRMERIE = 3, PASSERELLE = 2,
}
for _, deck in ipairs(ManifestData.ShipDeckRooms) do
	local count = DECK_LOOT_COUNT[deck.Usage]
	if count then
		addSpawnRegion(lootSpotsFolder, "LootSpot_" .. deck.Usage, deck.Center, deck.Size, "Treasure", { RegionCount = count })
	end
end

-- A creature region around the whole ship exterior, for sharks/rays patrolling it.
do
	local shipCenter, shipSize = nil, nil
	if titanShip then
		local pivot = titanShip:GetPivot()
		local ok, size = pcall(function()
			return titanShip:GetExtentsSize()
		end)
		shipCenter = pivot.Position
		shipSize = (ok and size or Vector3.new(350, 70, 60)) + Vector3.new(80, 60, 80)
	end
	if shipCenter then
		addSpawnRegion(wreckZoneFolder, "TitanCreatureRegion", shipCenter, shipSize, "Creature", {
			RegionCount = 5,
			RegionSpecies = "RequinRecif,RaieManta",
		})
	end
end

print(string.format(
	"[ArchipelPlacement] positioned TITAN + Archipel (offset %s), %d landmarks, %d cave regions, %d loot spots",
	tostring(OFFSET),
	#ManifestData.Navigation,
	#ManifestData.CaveNodes,
	#ManifestData.ShipDeckRooms
))
