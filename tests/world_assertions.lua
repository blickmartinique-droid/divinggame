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
local function isWater(p) return TERRAIN_MATERIAL_AT(p) == "Water" end
math.randomseed(20260924)

section("WorldBootstrap")
WARNINGS = {}
local started = os.clock()
RUN_SCRIPT("ServerScriptService", "World", "WorldBootstrap")
print(string.format("world built in %.1fs (test runtime), %d terrain ops", os.clock() - started, #TERRAIN_OPS))
check("every builder succeeded (no warnings)", #WARNINGS == 0, WARNINGS[1])
check("WorldReady raised", Workspace:GetAttribute("WorldReady") == true)
local WorldLayout = require(ServerScriptService.World.Builders.WorldLayout)
local layout = WorldLayout.Current
check("layout published for runtime placement", layout ~= nil)

section("Seabed")
check("beach core is sand", TERRAIN_MATERIAL_AT(Vector3.new(20, 1, 20)) == "Sand")
check("rock right under the lagoon (no water gap under the beach)", TERRAIN_SOLID_AT(Vector3.new(100, -19, 0)))
check("the reef wall drops away past the crest", isWater(Vector3.new(0, -80, 260)) and isWater(Vector3.new(260, -80, 0)))
check("island rooted in the abyss (rock at 300 m, 250 studs out)", TERRAIN_SOLID_AT(Vector3.new(0, -300, 250)))
check("open abyssal plain is water", isWater(Vector3.new(-850, -470, 850)))
local holes = 0
for x = -990, 990, 30 do
	for z = -990, 990, 30 do
		if not TERRAIN_SOLID_AT(Vector3.new(x, -510, z)) then holes += 1 end
	end
end
check("seafloor slab intact", holes == 0, holes)
local mismatched = 0
for i = 1, 400 do
	local angle, radius = i * 2.39996, 190 + (i % 40) * 18
	local x, z = math.cos(angle) * radius, math.sin(angle) * radius
	local h = layout:GroundHeight(x, z)
	if h > -499 and h < -2 then
		if not TERRAIN_SOLID_AT(Vector3.new(x, h - 3, z)) or not isWater(Vector3.new(x, h + 3, z)) then mismatched += 1 end
	end
end
check("GroundHeight matches the terrain (rock below, water above)", mismatched <= 4, mismatched)

section("Caves")
local caves = layout:GetAnchor("Caves")
check("caves built", caves ~= nil)
if caves then
	for _, chamber in ipairs(caves.chambers) do
		local name = chamber.spec.id
		check(name .. ": chamber is open water", isWater(chamber.center))
		check(name .. ": sand floor under it", TERRAIN_MATERIAL_AT(Vector3.new(chamber.center.X, chamber.floorY - 2, chamber.center.Z)) == "Sand")
		local roofed = 0
		for i = 0, 7 do
			local a = i * math.pi / 4
			local p = chamber.center + Vector3.new(math.cos(a) * chamber.radius * 0.3, chamber.radius + 10, math.sin(a) * chamber.radius * 0.3)
			if TERRAIN_SOLID_AT(p) then roofed += 1 end
		end
		check(name .. ": closed under a rock roof", roofed >= 5, roofed)
		check(name .. ": inside the spur (surface well above)", layout:GroundHeight(chamber.center.X, chamber.center.Z) > chamber.center.Y + chamber.radius, layout:GroundHeight(chamber.center.X, chamber.center.Z))
	end
	-- Every tunnel is clear up to where it opens into a hall (inside a
	-- hall a pillar may stand on the tube's axis: divers swim around it).
	local pillarsInHall = 0
	for id, tunnel in pairs(caves.tunnels) do
		local blocked = 0
		for _, sample in ipairs(tunnel.samples) do
			local inHall = false
			for _, chamber in ipairs(caves.chambers) do
				if (sample - chamber.center).Magnitude < chamber.radius * 0.7 then inHall = true end
			end
			if not isWater(sample) then
				if inHall then pillarsInHall += 1 else blocked += 1 end
			end
		end
		check("tunnel " .. id .. ": clear all the way", blocked == 0, blocked)
	end
	for _, entrance in ipairs(caves.entrances) do
		check("entrance " .. entrance.id .. ": opens to open water", isWater(entrance.mouth) and isWater(entrance.mouth - entrance.inward * 20), tostring(entrance.mouth))
		local g = layout:GroundHeight(entrance.mouth.X, entrance.mouth.Z)
		check("entrance " .. entrance.id .. ": mouth is outside the rock", entrance.mouth.Y > g - 2 or isWater(entrance.mouth - entrance.inward * 20), g)
	end
	-- The Cathédrale's pillars really stand (rock at mid-height around it).
	local cathedral
	for _, chamber in ipairs(caves.chambers) do if chamber.spec.id == "Cathedrale" then cathedral = chamber end end
	local pillarHits = 0
	for i = 0, 71 do
		local a = i / 72 * math.pi * 2
		if TERRAIN_SOLID_AT(cathedral.center + Vector3.new(math.cos(a), 0, math.sin(a)) * cathedral.radius * 0.58) then pillarHits += 1 end
	end
	check("Cathédrale: several pillars stand in the hall", pillarHits >= 12, pillarHits)
	local floating, buried = 0, 0
	for _, part in ipairs(Workspace.World.Underwater.Caves.Decor:GetChildren()) do
		if part.Name == "Stalactite" then
			if TERRAIN_SOLID_AT(part.Position) then buried += 1 end
		elseif part.Name == "Crystal" or part.Name == "FungusStalk" then
			local foot = part.CFrame * Vector3.new(0, -part.Size.Y / 2 - 1.5, 0)
			if not TERRAIN_SOLID_AT(foot) then
				floating += 1
				if floating <= 3 then print("  floating", part.Name, foot, TERRAIN_MATERIAL_AT(foot)) end
			end
		end
	end
	check("cave floor props rest on rock/sand", floating <= 3, floating)
end

section("Shipwreck")
local ship = Workspace.World.Underwater.WreckZone:FindFirstChild("Shipwreck")
check("shipwreck built", ship ~= nil)
local shipCFrame = layout:GetAnchor("WreckCFrame")
if ship and shipCFrame then
	local planks, sunk, afloat = 0, 0, 0
	for _, p in ipairs(ship.Hull:GetChildren()) do
		if p.Name == "Plank" then planks += 1 end
	end
	check("hull is planked", planks > 350, planks)
	-- Keel resting on (in) the terrace, not floating over it.
	for _, p in ipairs(ship.Hull:GetChildren()) do
		if p.Name == "Keel" then
			local g = layout:GroundHeight(p.Position.X, p.Position.Z)
			if p.Position.Y < g + 1 then sunk += 1 elseif p.Position.Y > g + 6 then afloat += 1 end
		end
	end
	check("keel rests in the sand along its length", afloat <= 2, afloat)
	-- The breach and the cabin door lead inside through water.
	local entries = layout:GetAnchor("WreckEntries")
	for name, position in pairs(entries) do
		check("wreck entry " .. name .. " is in open water", isWater(position), tostring(position))
	end
	local vortex = Workspace.Currents:FindFirstChild("EpaveVortex")
	check("vortex off the wreck in open water", vortex and isWater(vortex.Position) and layout:GroundHeight(vortex.Position.X, vortex.Position.Z) < vortex.Position.Y - 15)
end

section("Currents")
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
		if not isWater(p) and not (p.Y > 0 and not TERRAIN_SOLID_AT(p)) then blocked += 1 end
		for _, volume in ipairs(layout.reserved) do
			if volume.name == "Shipwreck" then
				local l = volume.cframe:PointToObjectSpace(p)
				if math.abs(l.X) < volume.half.X and math.abs(l.Y) < volume.half.Y and math.abs(l.Z) < volume.half.Z then inWreck += 1 end
			end
		end
	end
	check(current.Name .. ": flows through water only", blocked == 0, blocked)
	check(current.Name .. ": stays out of the wreck", inWreck == 0, inWreck)
end
for _, name in ipairs({ "EpaveUpdraft", "DescenteDuTombant", "CourantDesGrottes", "CourantDeLaFaille", "RecifFastLane" }) do
	check(name .. " placed", Workspace.Currents:FindFirstChild(name) ~= nil)
end

section("Decor")
local decorFloating = 0
for _, part in ipairs(Workspace.WorldDecor.KelpForest:GetChildren()) do
	if part.Name == "GiantKelp" and not TERRAIN_SOLID_AT(part.Position - Vector3.new(0, part.Size.Y / 2 + 1, 0)) then decorFloating += 1 end
end
check("giant kelp rooted in the seabed", decorFloating <= 2, decorFloating)
check("kelp forest planted", #Workspace.WorldDecor.KelpForest:GetChildren() > 200, #Workspace.WorldDecor.KelpForest:GetChildren())
check("rift vents built", Workspace.WorldDecor.Abyss:FindFirstChild("VentThroat") ~= nil)

section("Spawners")
RUN_SCRIPT("ServerScriptService", "World", "TreasureSpawner")
local treasures = Workspace:FindFirstChild("Treasures"):GetChildren()
local DepthUtils = require(ReplicatedStorage.Shared.Modules.DepthUtils)
local perZone, buried = {}, 0
for _, t in ipairs(treasures) do
	local zone = DepthUtils.GetZoneIndexForDepth(DepthUtils.GetDepth(t.Position))
	perZone[zone] = (perZone[zone] or 0) + 1
	if not isWater(t.Position) then
		buried += 1
		print("  buried treasure", t.Position, TERRAIN_MATERIAL_AT(t.Position))
	end
end
for zone = 1, 4 do
	check("zone " .. zone .. " has at least 15 treasures", (perZone[zone] or 0) >= 15, perZone[zone])
end
check("no treasure buried in terrain", buried == 0, buried)

WARNINGS = {}
RUN_SCRIPT("ServerScriptService", "Creatures", "CreatureSpawner")
local creatures = Workspace.Creatures:GetChildren()
check("creatures spawned", #creatures > 40, #creatures)
check("no species/depth mismatch warnings", #WARNINGS == 0, WARNINGS[1])
local CreaturesConfig = require(ReplicatedStorage.Shared.Config.CreaturesConfig)
local seen, inRock = {}, 0
for _, m in ipairs(creatures) do
	seen[m:GetAttribute("Species")] = true
	if not isWater(m.PrimaryPart.Position) then
		inRock += 1
		if inRock <= 4 then print("  in rock", m:GetAttribute("Species"), m.PrimaryPart.Position, TERRAIN_MATERIAL_AT(m.PrimaryPart.Position)) end
	end
end
for _, s in ipairs(CreaturesConfig.Species) do
	check(s.Id .. " lives somewhere", seen[s.Id] == true)
end
check("no creature spawned inside rock", inRock == 0, inRock)

print(string.format("\n%d checks, %d failures", checks, failures))
if failures > 0 then
	error(string.format("%d world checks failed", failures), 0)
end
print("ALL WORLD CHECKS PASSED")
