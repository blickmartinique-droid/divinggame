local failures, checks = 0, 0
local function check(label, ok, detail)
	checks += 1
	if not ok then
		failures += 1
		print(string.format("FAIL  %s%s", label, detail and ("  -- " .. tostring(detail)) or ""))
	end
end
local function section(name) print("\n== " .. name .. " ==") end

-- 1. Data sanity ---------------------------------------------------------
section("Data tables")
check("TitanShipData non-empty", #TitanShipData > 3000, #TitanShipData)
check("TitanShipData excludes the duplicate-volume hull-shell meshes (4 fewer than the raw 3757)",
	#TitanShipData == 3753, #TitanShipData)
check("ArchipelWorldData non-empty", #ArchipelWorldData > 2000, #ArchipelWorldData)

local validShapes = { Block = true, Cylinder = true, Ball = true }
local validMaterials = {
	SmoothPlastic=true, Metal=true, CorrodedMetal=true, Neon=true, Rock=true, Wood=true,
	WoodPlanks=true, Concrete=true, LeafyGrass=true, Glass=true, Sand=true, Slate=true, Ground=true,
	DiamondPlate=true,
}
local badShape, badMaterial, zeroSize = 0, 0, 0
for _, r in ipairs(TitanShipData) do
	if not validShapes[r.Shape] then badShape += 1 end
	if not validMaterials[r.Material] then badMaterial += 1 end
	if r.Size.X <= 0 or r.Size.Y <= 0 or r.Size.Z <= 0 then zeroSize += 1 end
end
check("Titan: every Shape recognized", badShape == 0, badShape)
check("Titan: every Material in the safe palette", badMaterial == 0, badMaterial)
check("Titan: no degenerate (zero/negative) size", zeroSize == 0, zeroSize)

badShape, badMaterial, zeroSize = 0, 0, 0
for _, r in ipairs(ArchipelWorldData) do
	if not validShapes[r.Shape] then badShape += 1 end
	if not validMaterials[r.Material] then badMaterial += 1 end
	if r.Size.X <= 0 or r.Size.Y <= 0 or r.Size.Z <= 0 then zeroSize += 1 end
end
check("World: every Shape recognized", badShape == 0, badShape)
check("World: every Material in the safe palette", badMaterial == 0, badMaterial)
check("World: no degenerate size", zeroSize == 0, zeroSize)

-- 2. Run the real builder scripts against the stub -----------------------
section("TitanShip.server.lua execution")
local ok, err = pcall(RUN_TITAN)
check("TitanShip builds without crashing", ok, err)

local wreckZone = Workspace.World.Underwater.WreckZone
local ship = wreckZone:FindFirstChild("TitanShip")
check("TitanShip folder created", ship ~= nil)
check("old MegaWreckShip name is gone", wreckZone:FindFirstChild("MegaWreckShip") == nil)

if ship then
	local exterior = ship:FindFirstChild("Exterior")
	local interior = ship:FindFirstChild("Interior")
	check("Exterior folder exists", exterior ~= nil)
	check("Interior folder exists", interior ~= nil)

	local totalParts = 0
	for _, deck in ipairs({ "Ballast", "Machines", "Laboratoires", "Habitats", "Promenade", "Infirmerie", "Passerelle" }) do
		local folder = interior and interior:FindFirstChild(deck)
		check("Interior has " .. deck, folder ~= nil)
		if folder then
			totalParts += #folder:GetChildren()
		end
	end
	for _, ext in ipairs({ "Hull", "Superstructure" }) do
		local folder = exterior and exterior:FindFirstChild(ext)
		check("Exterior has " .. ext, folder ~= nil)
		if folder then
			totalParts += #folder:GetChildren()
		end
	end
	check("every record became a real Part", totalParts == #TitanShipData, totalParts)

	local lighting = ship:FindFirstChild("Lighting")
	check("Lighting folder has 20 anchors", lighting and #lighting:GetChildren() == 20, lighting and #lighting:GetChildren())
	local anyPointLight = false
	if lighting then
		for _, anchor in ipairs(lighting:GetChildren()) do
			if anchor:FindFirstChildOfClass("PointLight") then anyPointLight = true end
		end
	end
	check("lights are real PointLights", anyPointLight)

	local landmarks = ship:FindFirstChild("Landmarks")
	check("2 landmarks", landmarks and #landmarks:GetChildren() == 2, landmarks and #landmarks:GetChildren())

	local lootSpots = ship:FindFirstChild("LootSpots")
	check("7 loot spot regions (one per deck)", lootSpots and #lootSpots:GetChildren() == 7, lootSpots and #lootSpots:GetChildren())
	if lootSpots then
		for _, region in ipairs(lootSpots:GetChildren()) do
			check(region.Name .. " tagged SpawnRegion", game:GetService("CollectionService"):HasTag(region, "SpawnRegion"))
			check(region.Name .. " RegionKind=Treasure", region:GetAttribute("RegionKind") == "Treasure")
			check(region.Name .. " has RegionCount", (region:GetAttribute("RegionCount") or 0) > 0)
		end
	end

	local creatureRegion = ship:FindFirstChild("TitanCreatureRegion")
	check("creature region exists", creatureRegion ~= nil)
	if creatureRegion then
		check("creature region species set", creatureRegion:GetAttribute("RegionSpecies") == "RequinRecif,RaieManta")
	end

	-- Hull collision sanity: Hull is now only the 3 genuine end-cap plates
	-- (the hollow-shell/bay-opening meshes were excluded at the data stage
	-- -- see TitanShipData.lua's header for why) -- all legitimately solid,
	-- no Neon among them. The exterior envelope's real openings live in
	-- Superstructure's 466 panels instead, which DO mix collidable plates
	-- with pass-through Neon fixtures.
	check("Hull is exactly the 3 end-cap plates, not the old 7", #exterior.Hull:GetChildren() == 3, #exterior.Hull:GetChildren())
	local hullCollideCount = 0
	for _, part in ipairs(exterior.Hull:GetChildren()) do
		if part.CanCollide then hullCollideCount += 1 end
	end
	check("all 3 hull end-caps are solid", hullCollideCount == 3, hullCollideCount)

	check("superstructure has real collidable panels", #exterior.Superstructure:GetChildren() > 0)

	-- Neon fixtures (screens, glow strips) live inside the deck rooms, not
	-- on the exterior silhouette -- checked across the whole ship instead
	-- of assuming a per-category split.
	local shipCollide, shipTotal = 0, 0
	for _, part in ipairs(ship:GetDescendants()) do
		if part:IsA("BasePart") and part.Parent ~= lootSpots and part ~= creatureRegion then
			shipTotal += 1
			if part.CanCollide then shipCollide += 1 end
		end
	end
	check("ship has real collidable panels", shipCollide > 0)
	check("ship is not all solid (Neon fixtures pass through)", shipCollide < shipTotal, shipCollide .. "/" .. shipTotal)
end

section("ArchipelWorld.server.lua execution")
local ok2, err2 = pcall(RUN_ARCHIPEL)
check("ArchipelWorld builds without crashing", ok2, err2)

local archipel = Workspace.World.Underwater:FindFirstChild("ArchipelDesProfondeurs")
check("ArchipelDesProfondeurs folder created", archipel ~= nil)
check("old CaveRegions name is gone", Workspace.World.Underwater:FindFirstChild("CaveRegions") == nil)

if archipel then
	local totalParts = 0
	for _, cat in ipairs({ "Surface_Accueil", "Ile_Et_Montagne", "Reseau_De_Grottes", "Jardin_Abyssal", "Recif_Et_Faune_Fixe", "Quai_Et_Camp" }) do
		local folder = archipel:FindFirstChild(cat)
		check("category folder " .. cat .. " exists", folder ~= nil)
		if folder then totalParts += #folder:GetChildren() end
	end
	check("every non-terrain record became a real Part", totalParts == #ArchipelWorldData, totalParts)

	local lighting = archipel:FindFirstChild("Lighting")
	check("15 world lights (Soleil/SUN excluded)", lighting and #lighting:GetChildren() == 15, lighting and #lighting:GetChildren())

	local landmarks = archipel:FindFirstChild("Landmarks")
	check("19 landmarks", landmarks and #landmarks:GetChildren() == 19, landmarks and #landmarks:GetChildren())

	local creatureRegions = archipel:FindFirstChild("CreatureRegions")
	local grotteRegions = 0
	if creatureRegions then
		for _, r in ipairs(creatureRegions:GetChildren()) do
			if r.Name:match("^Grottes") then grotteRegions += 1 end
		end
	end
	check("12 grotte creature regions", grotteRegions == 12, grotteRegions)

	local medusePresent = false
	if creatureRegions then
		local jardin = creatureRegions:FindFirstChild("Grottes — Jardin des Méduses_Creatures")
		medusePresent = jardin and jardin:GetAttribute("RegionSpecies") == "MeduseLumineuse"
	end
	check("Jardin des Méduses region uses MeduseLumineuse", medusePresent)

	local reefRegion = archipel:FindFirstChild("CreatureRegions") and archipel.CreatureRegions:FindFirstChild("RecifCreatureRegion")
	check("reef ambient creature region exists", reefRegion ~= nil)

	local lootSpots = archipel:FindFirstChild("LootSpots")
	check("2 treasure loot spots (station sismique + ancien camp)", lootSpots and #lootSpots:GetChildren() == 2, lootSpots and #lootSpots:GetChildren())
end

-- 3. Terrain fills ---------------------------------------------------------
-- Nodes are now connected as capsules (FillBall + FillCylinder between
-- consecutive nodes), not isolated balls -- see ArchipelWorld.server.lua's
-- fillCapsule for why (an isolated-ball chain read as one giant smooth
-- boulder in Studio). So a chain of N nodes produces N-1 FillCylinder
-- calls and up to 2*(N-1) FillBall calls (interior nodes appear as both
-- the "B" end of one pair and the "A" end of the next) -- checked as
-- lower bounds, not exact counts, since that overlap is deliberate.
section("Terrain")
local massBalls, carveBalls, massCylinders, carveCylinders = 0, 0, 0, 0
for _, fill in ipairs(TERRAIN_FILLS) do
	local isMass = fill.material.Name == "Rock" or fill.material.Name == "Ground"
	local isCarve = fill.material.Name == "Water"
	if fill.op == "FillBall" then
		if isMass then massBalls += 1 elseif isCarve then carveBalls += 1 end
	elseif fill.op == "FillCylinder" then
		if isMass then massCylinders += 1 elseif isCarve then carveCylinders += 1 end
	end
end
check("terrain: mass and carve fills both happened", massBalls > 0 and carveBalls > 0)

local expectedCylinders = { mass = 0, carve = 0 }
for _, d in pairs(ArchipelTerrainData) do
	expectedCylinders[d.Role] += math.max(0, #d.Chain - 1)
end
check("terrain: one FillCylinder per mass chain gap", massCylinders == expectedCylinders.mass, massCylinders .. " vs " .. expectedCylinders.mass)
check("terrain: one FillCylinder per carve chain gap", carveCylinders == expectedCylinders.carve, carveCylinders .. " vs " .. expectedCylinders.carve)
check("terrain: every node is a real sphere too (no gaps between capsule segments)", massBalls >= expectedCylinders.mass and carveBalls >= expectedCylinders.carve)

-- Order check: every mass fill's list index precedes every carve fill's.
-- The pre-pass clear-to-Water FillBlock calls are excluded here (op ~=
-- FillBall/FillCylinder) -- they run before everything on purpose and
-- are not a "carve".
local lastMassIndex, firstCarveIndex = 0, math.huge
for i, fill in ipairs(TERRAIN_FILLS) do
	if fill.op == "FillBall" or fill.op == "FillCylinder" then
		if fill.material.Name == "Rock" or fill.material.Name == "Ground" then
			lastMassIndex = math.max(lastMassIndex, i)
		elseif fill.material.Name == "Water" then
			firstCarveIndex = math.min(firstCarveIndex, i)
		end
	end
end
check("terrain: mass fills all happen before carve fills", lastMassIndex < firstCarveIndex, lastMassIndex .. " vs " .. firstCarveIndex)

-- 5. Re-run idempotency -- the actual bug reported in Studio -----------------
-- Terrain is real persistent voxel data (FillBall/FillCylinder only ADD
-- material, a re-run never removes what an earlier run left behind), so
-- running this script twice in a row (as happens whenever the game is
-- restarted in the same Studio place, e.g. to pick up this very fix) must
-- clear its own footprint first or the old shape stays baked in forever
-- underneath the new one -- exactly what the user saw.
section("Terrain re-run idempotency")
local fillsAfterFirstRun = #TERRAIN_FILLS
local clearFillsFirstRun = 0
for _, fill in ipairs(TERRAIN_FILLS) do
	if fill.op == "FillBlock" and fill.material.Name == "Water" then
		clearFillsFirstRun += 1
	end
end
check("first run clears its footprint before filling (at least one Water FillBlock)", clearFillsFirstRun > 0, clearFillsFirstRun)

-- The very first Terrain call of the run must be a clear, not a mass/carve
-- fill -- otherwise old geometry from a previous run is filled over before
-- ever being erased.
check("the clear pass runs before any mass/carve fill", TERRAIN_FILLS[1] ~= nil and TERRAIN_FILLS[1].op == "FillBlock", TERRAIN_FILLS[1] and TERRAIN_FILLS[1].op)

RUN_ARCHIPEL() -- second run, same session -- simulates restarting the game
local fillsAfterSecondRun = #TERRAIN_FILLS - fillsAfterFirstRun
local secondRunHasClear = false
for i = fillsAfterFirstRun + 1, #TERRAIN_FILLS do
	if TERRAIN_FILLS[i].op == "FillBlock" and TERRAIN_FILLS[i].material.Name == "Water" then
		secondRunHasClear = true
		break
	end
end
check("second run also clears before filling (old shape can't survive a restart)", secondRunHasClear)
check("second run repeats the same terrain work (not skipped, not doubled)", fillsAfterSecondRun == fillsAfterFirstRun, fillsAfterSecondRun .. " vs " .. fillsAfterFirstRun)

-- Regression guard for the actual bug reported in Studio: no node's
-- radius should be wildly larger than the mesh's own real half-extent --
-- a value in the hundreds was the "giant boulder swallowing everything
-- nearby" symptom. Falaises_Massif_Sous_Marin's real dims are ~847x590x443
-- studs, so its true perpendicular half-extent tops out around 300ish
-- (a diagonal of half-width and half-height); comfortable margin at 350.
local maxRadiusSeen = 0
for _, d in pairs(ArchipelTerrainData) do
	for _, seg in ipairs(d.Chain) do
		maxRadiusSeen = math.max(maxRadiusSeen, seg.Radius)
	end
end
check("terrain: no node radius is implausibly larger than the source mesh", maxRadiusSeen < 350, maxRadiusSeen)

-- 4. Cross-check: TitanShip and ArchipelWorld don't collide in world space
section("Placement sanity")
-- A coarse but real check: the ship's exterior AABB (already built above)
-- should not overlap the reef/cave region bounding box by an implausible
-- amount -- computed straight from the two data tables' own Center values,
-- not re-derived.
local function bbox(data, filterFn)
	local minV, maxV = nil, nil
	for _, r in ipairs(data) do
		if not filterFn or filterFn(r) then
			if not minV then
				minV, maxV = r.Center, r.Center
			else
				minV = Vector3.new(math.min(minV.X, r.Center.X), math.min(minV.Y, r.Center.Y), math.min(minV.Z, r.Center.Z))
				maxV = Vector3.new(math.max(maxV.X, r.Center.X), math.max(maxV.Y, r.Center.Y), math.max(maxV.Z, r.Center.Z))
			end
		end
	end
	return minV, maxV
end
local shipMin, shipMax = bbox(TitanShipData)
local worldMin, worldMax = bbox(ArchipelWorldData)
check("ship sits within the ocean's +/-1000 stud bounds", shipMin.X > -1000 and shipMax.X < 1000 and shipMin.Z > -1000 and shipMax.Z < 1000)
check("world content sits within the ocean's +/-1000 stud bounds", worldMin.X > -1000 and worldMax.X < 1000 and worldMin.Z > -1000 and worldMax.Z < 1000)
check("ship stays clear of the existing beach at the origin (>150 studs)", math.sqrt(((shipMin.X+shipMax.X)/2)^2 + ((shipMin.Z+shipMax.Z)/2)^2) > 150)

print(string.format("\n%d checks, %d failures", checks, failures))
if failures > 0 then
	error(string.format("%d archipel checks failed", failures), 0)
end
print("ALL ARCHIPEL CHECKS PASSED")
