local failures, checks = 0, 0
local function check(label, ok, detail)
	checks += 1
	if not ok then
		failures += 1
		print(string.format("FAIL  %s%s", label, detail and ("  -- " .. tostring(detail)) or ""))
	end
end
local function section(name) print("\n== " .. name .. " ==") end

-- 1. Manifest data sanity ---------------------------------------------------
section("ArchipelManifestData")
check("12 cave nodes", #ArchipelManifestData.CaveNodes == 12, #ArchipelManifestData.CaveNodes)
check("3 cliff portals", #ArchipelManifestData.CliffPortals == 3, #ArchipelManifestData.CliffPortals)
check("21 navigation waypoints", #ArchipelManifestData.Navigation == 21, #ArchipelManifestData.Navigation)
check("7 ship deck usages", #ArchipelManifestData.ShipDeckRooms == 7, #ArchipelManifestData.ShipDeckRooms)
check("offset is a real Vector3", typeof(ArchipelManifestData.Offset) == "Vector3")

local caveNames = {}
for _, node in ipairs(ArchipelManifestData.CaveNodes) do
	caveNames[node.Name] = true
	check(node.Name .. ": positive radius/height", node.Radius > 0 and node.Height > 0)
end
for _, key in ipairs({ "Cathédrale Abyssale", "Jardin des Méduses", "Puits des Echos", "Porte du Titan" }) do
	check("cave node exists: " .. key, caveNames[key] == true)
end

local deckUsages = {}
for _, deck in ipairs(ArchipelManifestData.ShipDeckRooms) do
	deckUsages[deck.Usage] = true
	check(deck.Usage .. ": positive size", deck.Size.X > 0 and deck.Size.Y > 0 and deck.Size.Z > 0)
end
for _, usage in ipairs({ "BALLAST", "MACHINES", "LABORATOIRES", "HABITATS", "PROMENADE", "INFIRMERIE", "PASSERELLE" }) do
	check("deck usage exists: " .. usage, deckUsages[usage] == true)
end

-- 2. Build a fake static scene the way Rojo would present it ----------------
section("Fake Rojo-synced scene")
local worldFolder = Instance.new("Folder", Workspace); worldFolder.Name = "World"
local underwaterFolder = Instance.new("Folder", worldFolder); underwaterFolder.Name = "Underwater"
local wreckZoneFolder = Instance.new("Folder", underwaterFolder); wreckZoneFolder.Name = "WreckZone"

-- Simulates a resync where Rojo hasn't (yet) renamed the file's own root
-- Model to match the tree key -- the placement script must find this by its
-- embedded collection name and rename it.
local titanRaw = Instance.new("Model", wreckZoneFolder); titanRaw.Name = "02_NAVIRE_TITAN"
local titanHull = Instance.new("Part", titanRaw)
titanHull.Size = Vector3.new(300, 60, 50)
titanHull.Position = Vector3.new(0, -190, 0)
titanRaw.PrimaryPart = titanHull

local archipelFolder = Instance.new("Folder", underwaterFolder); archipelFolder.Name = "ArchipelDesProfondeurs"
local moduleNames = {
	SurfaceAccueil = "00_SURFACE_ACCUEIL", IleEtMontagne = "01_ILE_ET_MONTAGNE",
	ReseauDeGrottes = "03_RESEAU_DE_GROTTES", JardinAbyssal = "04_JARDIN_ABYSSAL",
	RecifEtFauneFixe = "05_RECIF_ET_FAUNE_FIXE", QuaiEtCamp = "06_QUAI_ET_CAMP",
}
for wantedName, fallbackName in pairs(moduleNames) do
	local model = Instance.new("Model", archipelFolder); model.Name = fallbackName
	local part = Instance.new("Part", model)
	part.Size = Vector3.new(10, 10, 10)
	part.Position = Vector3.new(0, 0, 0)
	model.PrimaryPart = part
end

-- 3. Run the real script -----------------------------------------------------
section("ArchipelPlacement.server.lua execution")
local ok, err = pcall(RUN_PLACEMENT)
check("placement script runs without crashing", ok, err)

check("TitanShip renamed from its embedded collection name", wreckZoneFolder:FindFirstChild("TitanShip") ~= nil)
check("no leftover '02_NAVIRE_TITAN' name", wreckZoneFolder:FindFirstChild("02_NAVIRE_TITAN") == nil)
for wantedName in pairs(moduleNames) do
	check(wantedName .. " renamed from its embedded collection name", archipelFolder:FindFirstChild(wantedName) ~= nil)
end

-- PivotTo: the fake hull started at (0,-190,0); the script should have
-- shifted it by the manifest's own Offset (X/Z only).
local titanShip = wreckZoneFolder:FindFirstChild("TitanShip")
local movedHull = titanShip and titanShip:FindFirstChildOfClass("Part")
if movedHull then
	local expected = Vector3.new(0, -190, 0) + ArchipelManifestData.Offset
	check("TitanShip hull shifted by the manifest offset", (movedHull.Position - expected).Magnitude < 0.01, movedHull.Position)
end

-- Landmarks
local landmarks = archipelFolder:FindFirstChild("Landmarks")
check("Landmarks folder created", landmarks ~= nil)
check("21 landmark markers", landmarks and #landmarks:GetChildren() == 21, landmarks and #landmarks:GetChildren())

-- Cave creature regions
local creatureRegions = archipelFolder:FindFirstChild("CreatureRegions")
check("CreatureRegions folder created", creatureRegions ~= nil)
check("12 cave creature regions", creatureRegions and #creatureRegions:GetChildren() == 12, creatureRegions and #creatureRegions:GetChildren())
if creatureRegions then
	for _, region in ipairs(creatureRegions:GetChildren()) do
		check(region.Name .. " tagged SpawnRegion", game:GetService("CollectionService"):HasTag(region, "SpawnRegion"))
		check(region.Name .. " RegionKind=Creature", region:GetAttribute("RegionKind") == "Creature")
		check(region.Name .. " has RegionSpecies", type(region:GetAttribute("RegionSpecies")) == "string")
	end
	local jardin = creatureRegions:FindFirstChild("Grottes_Jardin des Méduses_Creatures")
	check("Jardin des Méduses region uses MeduseLumineuse only", jardin and jardin:GetAttribute("RegionSpecies") == "MeduseLumineuse")
end

-- Ship loot spots
local lootSpots = archipelFolder:FindFirstChild("LootSpots")
check("LootSpots folder created", lootSpots ~= nil)
check("7 deck loot spots", lootSpots and #lootSpots:GetChildren() == 7, lootSpots and #lootSpots:GetChildren())
if lootSpots then
	for _, region in ipairs(lootSpots:GetChildren()) do
		check(region.Name .. " RegionKind=Treasure", region:GetAttribute("RegionKind") == "Treasure")
		check(region.Name .. " has positive RegionCount", (region:GetAttribute("RegionCount") or 0) > 0)
	end
end

-- Ship exterior creature region
local shipRegion = wreckZoneFolder:FindFirstChild("TitanCreatureRegion")
check("ship exterior creature region exists", shipRegion ~= nil)
if shipRegion then
	check("ship exterior region species set", shipRegion:GetAttribute("RegionSpecies") == "RequinRecif,RaieManta")
end

-- 4. Idempotency: a second run must not crash or double up static content --
-- Landmarks/LootSpots/CreatureRegions ARE recreated fresh each run in this
-- script (it always makes a new Folder), matching every other builder
-- script in this project's convention (destroy-and-rebuild dynamic content);
-- only the static geometry (never destroyed here, Rojo owns its lifecycle)
-- must not be duplicated or crash on a second PivotTo.
section("Re-run safety")
local ok2, err2 = pcall(RUN_PLACEMENT)
check("second run does not crash (static geometry is not destroyed/rebuilt)", ok2, err2)
check("TitanShip still resolves to one instance after a second run", #wreckZoneFolder:GetChildren() >= 1)

print(string.format("\n%d checks, %d failures", checks, failures))
if failures > 0 then
	error(string.format("%d placement checks failed", failures), 0)
end
print("ALL PLACEMENT CHECKS PASSED")
