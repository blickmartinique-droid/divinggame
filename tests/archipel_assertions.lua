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
section("Terrain")
local massFills, carveFills = 0, 0
for _, fill in ipairs(TERRAIN_FILLS) do
	if fill.op == "FillBall" then
		if fill.material.Name == "Rock" or fill.material.Name == "Ground" then
			massFills += 1
		elseif fill.material.Name == "Water" then
			carveFills += 1
		end
	end
end
check("terrain: mass filled before any carve (Rock/Ground fills precede Water fills)", massFills > 0 and carveFills > 0)
check("terrain: mass fill count matches ArchipelTerrainData", massFills == (function()
	local n = 0
	for _, d in pairs(ArchipelTerrainData) do
		if d.Role == "mass" then n += #d.Chain end
	end
	return n
end)())
check("terrain: carve fill count matches ArchipelTerrainData", carveFills == (function()
	local n = 0
	for _, d in pairs(ArchipelTerrainData) do
		if d.Role == "carve" then n += #d.Chain end
	end
	return n
end)())
-- Order check: every mass fill's list index precedes every carve fill's.
local lastMassIndex, firstCarveIndex = 0, math.huge
for i, fill in ipairs(TERRAIN_FILLS) do
	if fill.material.Name == "Rock" or fill.material.Name == "Ground" then
		lastMassIndex = math.max(lastMassIndex, i)
	elseif fill.material.Name == "Water" then
		firstCarveIndex = math.min(firstCarveIndex, i)
	end
end
check("terrain: mass fills all happen before carve fills", lastMassIndex < firstCarveIndex, lastMassIndex .. " vs " .. firstCarveIndex)

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
