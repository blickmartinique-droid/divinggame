-- World suite: runs the real WorldBootstrap, then the spawners, and checks
-- the result against the recorded terrain (TERRAIN_MATERIAL_AT).
local failures, checks = 0, 0
local function check(label, ok, detail)
	checks += 1
	if not ok then
		failures += 1
		print(string.format("FAIL  %s%s", label, detail and ("  -- " .. tostring(detail)) or ""))
	end
end
local function section(name) print("\n== " .. name .. " ==") end
math.randomseed(20260924)

section("WorldBootstrap")
WARNINGS = {}
RUN_SCRIPT("ServerScriptService", "World", "WorldBootstrap")
check("every builder succeeded (no warnings)", #WARNINGS == 0, WARNINGS[1])
check("WorldReady raised", Workspace:GetAttribute("WorldReady") == true)
local WorldLayout = require(ServerScriptService.World.Builders.WorldLayout)
local layout = WorldLayout.Current
check("layout published for runtime placement", layout ~= nil)

section("Terrain")
check("floor is rock", TERRAIN_MATERIAL_AT(Vector3.new(300, -510, 300)) == "Rock")
check("open ocean is water", TERRAIN_MATERIAL_AT(Vector3.new(300, -250, 300)) == "Water")
check("beach core is sand", TERRAIN_MATERIAL_AT(Vector3.new(20, 1, 20)) == "Sand")
-- No hole anywhere in the seafloor slab (a cave tunnel used to punch through).
local holes = 0
for x = -990, 990, 30 do
	for z = -990, 990, 30 do
		if TERRAIN_MATERIAL_AT(Vector3.new(x, -510, z)) ~= "Rock" then holes += 1 end
	end
end
check("seafloor slab intact", holes == 0, holes)
-- No water carved above the sea surface.
local floatingWater = 0
for _, op in ipairs(TERRAIN_OPS) do
	if op.kind == "ball" and op.material == "Water" and op.center.Y + op.radius > 0 then floatingWater += 1 end
end
check("no water carved above the surface", floatingWater == 0, floatingWater)

section("Cave regions")
local caves = layout:GetAnchor("CaveRegions")
check("4 cave regions", #caves == 4, #caves)
for _, info in ipairs(caves) do
	check(info.name .. ": rooted on the seafloor", info.extent.minY <= WorldLayout.FloorY + 1, info.extent.minY)
	check(info.name .. ": has entries", #info.entries >= 1, #info.entries)
	for _, cavern in ipairs(info.caverns) do
		check(info.name .. ": chamber center is water", TERRAIN_MATERIAL_AT(cavern.center) == "Water")
	end
	-- Secondary chambers may merge into the main one; the main chamber
	-- must be a closed cave.
	for _, cavern in ipairs({ info.caverns[1] }) do
		-- Roof: rock just above the chamber somewhere around it (straight
		-- up may be the summit shaft, a side may be a tunnel).
		local roofed = 0
		for i = 0, 7 do
			local angle = i * math.pi / 4
			local d = cavern.radius * 0.4
			local p = cavern.center + Vector3.new(math.cos(angle) * d, math.sqrt(cavern.radius ^ 2 - d * d) + 10, math.sin(angle) * d)
			if TERRAIN_MATERIAL_AT(p) == "Rock" then roofed += 1 end
		end
		check(info.name .. ": chamber roofed by rock", roofed >= 5, roofed)
	end
	for _, entry in ipairs(info.entries) do
		check(info.name .. ": entry " .. entry.name .. " opens to water", TERRAIN_MATERIAL_AT(entry.mouth) == "Water")
	end
end

section("Currents")
local wreckBox
for _, v in ipairs(layout.reserved) do if v.name == "MegaWreckShip" then wreckBox = v end end
check("wreck volume reserved", wreckBox ~= nil)
for _, current in ipairs(Workspace.Currents:GetChildren()) do
	local points = {}
	if current:GetAttribute("CurrentShape") == "Path" then
		local parts = {}
		for _, c in ipairs(current:GetChildren()) do if c.Name:match("^CurrentPoint") then table.insert(parts, c) end end
		table.sort(parts, function(a, b) return a.Name < b.Name end)
		for i = 2, #parts do for t = 0, 1, 0.05 do table.insert(points, parts[i - 1].Position:Lerp(parts[i].Position, t)) end end
	else
		table.insert(points, current.Position)
	end
	local blocked, inWreck = 0, 0
	for _, p in ipairs(points) do
		local material = TERRAIN_MATERIAL_AT(p)
		if material ~= "Water" and not (material == "Air" and p.Y > 0) then blocked += 1 end
		local l = wreckBox.cframe:PointToObjectSpace(p)
		if math.abs(l.X) < wreckBox.half.X and math.abs(l.Y) < wreckBox.half.Y and math.abs(l.Z) < wreckBox.half.Z then inWreck += 1 end
	end
	check(current.Name .. ": flows through water only", blocked == 0, blocked)
	if current.Name ~= "EpaveVortex" then
		check(current.Name .. ": stays out of the wreck", inWreck == 0, inWreck)
	end
end
check("Épave updraft placed", Workspace.Currents:FindFirstChild("EpaveUpdraft") ~= nil)

section("Decor")
local pinnacles = Workspace.WorldDecor.Pinnacles:GetChildren()
check("some pinnacles placed", #pinnacles > 0, #pinnacles)
local badSpires = 0
for _, part in ipairs(pinnacles) do
	if part.Name == "Pinnacle" then
		local ok = layout:IsFree(part.Position + Vector3.new(0, part.Size.Y / 2 - 12, 0), 0)
		-- the spire itself is not reserved, so any hit is a real overlap
		if not ok then badSpires += 1 end
	end
end
check("no pinnacle top inside a reserved volume", badSpires == 0, badSpires)

section("Spawners")
RUN_SCRIPT("ServerScriptService", "World", "TreasureSpawner")
local treasures = Workspace:FindFirstChild("Treasures"):GetChildren()
local DepthUtils = require(ReplicatedStorage.Shared.Modules.DepthUtils)
local perZone = {}
local buried = 0
for _, t in ipairs(treasures) do
	local zone = DepthUtils.GetZoneIndexForDepth(DepthUtils.GetDepth(t.Position))
	perZone[zone] = (perZone[zone] or 0) + 1
	if TERRAIN_MATERIAL_AT(t.Position) ~= "Water" then buried += 1 end
end
for zone = 1, 4 do
	check("zone " .. zone .. " has at least 15 treasures", (perZone[zone] or 0) >= 15, perZone[zone])
end
check("no treasure buried in terrain", buried == 0, buried)
local SpawnRegions = require(ReplicatedStorage.Shared.Modules.SpawnRegions)
local regions = SpawnRegions.GetRegions("Treasure")
check("treasure regions exist (wreck rooms + cave chambers)", #regions >= 11, #regions)

WARNINGS = {}
RUN_SCRIPT("ServerScriptService", "Creatures", "CreatureSpawner")
local creatures = Workspace.Creatures:GetChildren()
check("creatures spawned", #creatures > 30, #creatures)
check("no species/depth mismatch warnings", #WARNINGS == 0, WARNINGS[1])
local CreaturesConfig = require(ReplicatedStorage.Shared.Config.CreaturesConfig)
local seen = {}
for _, m in ipairs(creatures) do seen[m:GetAttribute("Species")] = true end
for _, s in ipairs(CreaturesConfig.Species) do
	check(s.Id .. " lives somewhere", seen[s.Id] == true)
end
local joints = 0
for _, m in ipairs(creatures) do
	for _, d in ipairs(m:GetDescendants()) do
		if d.ClassName == "Motor6D" and d:GetAttribute("SwingAmplitude") then joints += 1 end
	end
end
check("procedural bodies have swim joints", joints > #creatures, joints)

print(string.format("\n%d checks, %d failures", checks, failures))
if failures > 0 then
	error(string.format("%d world checks failed", failures), 0)
end
print("ALL WORLD CHECKS PASSED")
