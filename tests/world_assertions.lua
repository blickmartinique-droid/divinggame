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
		-- The sign/ring sit on the face itself, not floating in front of it.
		check("entrance " .. entrance.id .. ": marked at the rock face", g > entrance.mouth.Y and g < entrance.mouth.Y + 40, g - entrance.mouth.Y)
		local clutter = 0
		for _, part in ipairs(Workspace.WorldDecor:GetDescendants()) do
			if part:IsA("BasePart") and part.Name:sub(1, 9) ~= "Creatures" and (part.Position - entrance.mouth).Magnitude < entrance.clearRadius then clutter += 1 end
		end
		check("entrance " .. entrance.id .. ": no decor in the mouth", clutter == 0, clutter)
		-- Visible from above: the face over a sideways mouth is cut open.
		if entrance.inward.Y > -0.6 then
			local open = 0
			for h = 6, 30, 6 do
				if isWater(entrance.mouth + Vector3.new(0, h, 0)) then open += 1 end
			end
			check("entrance " .. entrance.id .. ": cleft open above the mouth", open >= 4, open)
		end
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

section("Volcano network")
local network = layout:GetAnchor("Network")
check("lava tube network built", network ~= nil)
if network then
	for _, chamber in ipairs(network.chambers) do
		check(chamber.id .. ": hall is open water", isWater(chamber.center))
		check(chamber.id .. ": sand floor", TERRAIN_MATERIAL_AT(chamber.floorProbe) == "Sand", TERRAIN_MATERIAL_AT(chamber.floorProbe))
		local roofed = 0
		for i = 0, 7 do
			local a = i * math.pi / 4
			if TERRAIN_SOLID_AT(chamber.center + Vector3.new(math.cos(a) * chamber.radius * 0.3, chamber.radius + 10, math.sin(a) * chamber.radius * 0.3)) then roofed += 1 end
		end
		check(chamber.id .. ": under a rock roof", roofed >= 6, roofed)
	end
	for id, tube in pairs(network.tubes) do
		local blocked, roofless, interior = 0, 0, 0
		local mouth
		for _, e in ipairs(network.entrances) do if e.id == id then mouth = e.mouth end end
		for i, sample in ipairs(tube.samples) do
			if not isWater(sample) then blocked += 1 end
			-- Away from its mouth, a tube runs inside the rock.
			if not mouth or (sample - mouth).Magnitude > tube.spec.radius * 4 then
				local inHall = false
				for _, chamber in ipairs(network.chambers) do
					if (sample - chamber.center).Magnitude < chamber.radius * 1.3 then inHall = true end
				end
				for _, chamber in ipairs(caves.chambers) do
					if (sample - chamber.center).Magnitude < chamber.radius * 1.3 then inHall = true end
				end
				if not inHall and i > 3 then
					interior += 1
					-- Rock on both sides of the tube (works for shafts too).
					local ahead = (tube.samples[math.min(i + 1, #tube.samples)] - tube.samples[i - 1]).Unit
					local side = ahead:Cross(Vector3.new(0, 1, 0))
					side = side.Magnitude > 0.2 and side.Unit or Vector3.new(1, 0, 0)
					local reach = tube.radii[i] + 6
					if not (TERRAIN_SOLID_AT(sample + side * reach) and TERRAIN_SOLID_AT(sample - side * reach)) then roofless += 1 end
				end
			end
		end
		check("tube " .. id .. ": clear end to end", blocked == 0, blocked)
		check("tube " .. id .. ": inside the rock", interior > 0 and roofless <= interior * 0.1, roofless .. "/" .. interior)
	end
	for _, entrance in ipairs(network.entrances) do
		local outside = entrance.mouth - entrance.inward * 20
		check("network entrance " .. entrance.id .. ": opens to open water", isWater(entrance.mouth) and (isWater(outside) or outside.Y > 0), outside)
	end
	local lagoon
	for _, e in ipairs(network.entrances) do if e.id == "PuitsDuLagon" then lagoon = e end end
	check("the lagoon shaft opens in the lagoon, off the beach", lagoon and lagoon.mouth.Y > -20 and Vector3.new(lagoon.mouth.X, 0, lagoon.mouth.Z).Magnitude < 140, lagoon and lagoon.mouth)
	check("no water raised above the sea by the shaft", not isWater(Vector3.new(lagoon.mouth.X, 2, lagoon.mouth.Z)))
	-- The Éperon tube really joins the Salle des Cristaux.
	local eperon = network.tubes.TubeEperon
	local last = eperon.samples[#eperon.samples]
	local cristaux
	for _, chamber in ipairs(caves.chambers) do if chamber.spec.id == "Cristaux" then cristaux = chamber end end
	check("Éperon tube ends in the Salle des Cristaux", (last - cristaux.center).Magnitude < 1 and isWater(eperon.samples[#eperon.samples - 8]))
	local doors = 0
	for _ in pairs(network.heartDoors) do doors += 1 end
	check("an arch over every tube in the heart", doors == 6, doors)
	local temple = Workspace.World.Underwater.ReseauDuVolcan.Temple
	local base = temple:FindFirstChild("TempleTier")
	check("temple stands on the heart's floor", base and math.abs(base.Position.Y - base.Size.Y / 2 - network.heart.floorY) < 0.5)
	check("temple has its columns and altar", temple:FindFirstChild("Column") ~= nil and temple:FindFirstChild("Orb") ~= nil)
	local beacons = #Workspace.World.Underwater.ReseauDuVolcan.Beacons:GetChildren()
	check("rune beacons line the tubes", beacons > 40, beacons)
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

section("Graveyard")
local graveyard = layout:GetAnchor("Graveyard")
check("graveyard built", graveyard ~= nil)
if graveyard then
	local root = Workspace.World.Underwater.WreckZone.Graveyard
	local brigPlanks = 0
	for _, p in ipairs(root.Wrecks.BrickChavire:GetChildren()) do
		if p.Name == "Plank" then brigPlanks += 1 end
	end
	check("capsized brig is planked", brigPlanks > 150, brigPlanks)
	-- Upside down: her keel is the top of the wreck, well above the sand.
	local keel = root.Wrecks.BrickChavire:FindFirstChild("Keel")
	local g = layout:GroundHeight(keel.Position.X, keel.Position.Z)
	check("brig keel up, above the sand", keel.Position.Y > g + 18, keel.Position.Y - g)
	check("brig's torn bottom opens into water", isWater(graveyard.brigHole + Vector3.new(0, 2, 0)))
	for _, wreck in ipairs({ "ChaloupeBrisee", "Squelette" }) do
		local resting, total = 0, 0
		for _, p in ipairs(root.Wrecks[wreck]:GetChildren()) do
			if p.Name == "Keel" then
				total += 1
				local h = layout:GroundHeight(p.Position.X, p.Position.Z)
				if p.Position.Y > h - 7 and p.Position.Y < h + 8 then resting += 1 end
			end
		end
		check(wreck .. ": keel rests on the ledge", total > 0 and resting == total, resting .. "/" .. total)
	end
	-- No wreck overlaps the Sirène Noire.
	local ship
	for _, volume in ipairs(layout.reserved) do if volume.name == "Shipwreck" then ship = volume end end
	local overlaps = 0
	for _, box in ipairs(graveyard.reserved) do
		for x = -1, 1, 0.5 do for y = -1, 1, 0.5 do for z = -1, 1, 0.5 do
			local l = ship.cframe:PointToObjectSpace(box.cframe * (box.size / 2 * Vector3.new(x, y, z)))
			if math.abs(l.X) < ship.half.X and math.abs(l.Y) < ship.half.Y and math.abs(l.Z) < ship.half.Z then overlaps += 1 end
		end end end
	end
	check("graveyard wrecks clear of the Sirène Noire", overlaps == 0, overlaps)
	local floating = 0
	for _, p in ipairs(root.Life:GetChildren()) do
		if p.Name == "SeaWhip" or p.Name == "GlassSponge" or p.Name == "BlackCoral" then
			local h = layout:GroundHeight(p.Position.X, p.Position.Z)
			local foot = p.Name == "GlassSponge" and p.Position.Y - p.Size.X / 2 or p.Position.Y - p.Size.Y / 2
			if foot - h > 2.5 then floating += 1; print("  floating", p.Name, p.Position, h) end
		end
	end
	check("graveyard life planted on the ledge", floating == 0, floating)
end

section("Liner")
local liner = layout:GetAnchor("Liner")
check("L'Impératrice built", liner ~= nil)
if liner then
	local model = Workspace.World.Underwater.Imperatrice
	local plates = 0
	for _, p in ipairs(model.Hull:GetChildren()) do
		if p.Name == "Plate" then plates += 1 end
	end
	check("liner is plated", plates > 900, plates)
	-- Enormous: the halves span well over 800 studs end to end.
	local bowTip = liner.bow * Vector3.new(0, 0, -450)
	local sternTip = liner.stern * Vector3.new(0, 0, 450)
	check("liner is enormous (bow to stern > 800 studs)", (bowTip - sternTip).Magnitude > 800, (bowTip - sternTip).Magnitude)
	local outside = 0
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") and (math.abs(p.Position.X) > 985 or math.abs(p.Position.Z) > 985) then outside += 1 end
	end
	check("liner inside the ocean walls", outside == 0, outside)
	local resting = 0
	for _, keel in ipairs(liner.keelStations) do
		local g = layout:GroundHeight(keel.X, keel.Z)
		if keel.Y < g + 2 and keel.Y > g - 16 then resting += 1 end
	end
	check("bow keel sunk in the mud along her length", resting == #liner.keelStations, resting)
	check("the gash in her bow opens on water", isWater(liner.gash + Vector3.new(0, 0, 0)))
	check("grand staircase dome in open water", isWater(liner.wellTop + Vector3.new(0, 8, 0)))
	-- The halves do not overlap each other or the ledge's wrecks.
	local function corners(box)
		local list = {}
		for x = -1, 1, 2 do for y = -1, 1, 2 do for z = -1, 1, 2 do
			table.insert(list, box.cframe * (box.size / 2 * Vector3.new(x, y, z) * 0.9))
		end end end
		return list
	end
	local clash = 0
	for _, volume in ipairs(layout.reserved) do
		if volume.kind == "box" and (volume.name == "Shipwreck" or volume.name:match("^Graveyard_")) then
			for _, box in ipairs({ liner.bowBox, liner.sternBox }) do
				for _, c in ipairs(corners(box)) do
					local l = volume.cframe:PointToObjectSpace(c)
					if math.abs(l.X) < volume.half.X and math.abs(l.Y) < volume.half.Y and math.abs(l.Z) < volume.half.Z then clash += 1 end
				end
			end
		end
	end
	check("liner clear of the other wrecks", clash == 0, clash)
	local sternInBow = 0
	for _, c in ipairs(corners(liner.sternBox)) do
		local l = liner.bowBox.cframe:PointToObjectSpace(c)
		local h = liner.bowBox.size / 2
		if math.abs(l.X) < h.X and math.abs(l.Y) < h.Y and math.abs(l.Z) < h.Z then sternInBow += 1 end
	end
	check("the two halves lie apart", sternInBow == 0, sternInBow)
	local decorInHull = 0
	for _, p in ipairs(Workspace.WorldDecor:GetDescendants()) do
		if p:IsA("BasePart") and p.Name:sub(1, 9) ~= "Creatures" then
			local l = liner.bowBox.cframe:PointToObjectSpace(p.Position)
			local h = liner.bowBox.size / 2
			if math.abs(l.X) < h.X and math.abs(l.Y) < h.Y and math.abs(l.Z) < h.Z then decorInHull += 1 end
		end
	end
	check("no seabed decor growing through the liner", decorInHull == 0, decorInHull)
end

section("Biomes")
local BiomeLookup = require(ReplicatedStorage.Shared.Modules.BiomeLookup)
check("biomes published", ReplicatedStorage:FindFirstChild("Biomes") and #ReplicatedStorage.Biomes:GetChildren() >= 9)
local function biomeAt(p) local b = BiomeLookup.Find(p) return b and b.DisplayName end
local site = layout:GetAnchor("WreckSite")
check("wreck ledge is the Cimetière", biomeAt(site.position + Vector3.new(0, 12, 0)) == "Cimetière de la Sirène", biomeAt(site.position + Vector3.new(0, 12, 0)))
check("lagoon named", biomeAt(Vector3.new(120, -10, 0)) == "Le Lagon", biomeAt(Vector3.new(120, -10, 0)))
if caves then
	check("cave hall named", biomeAt(caves.chambers[2].center) == caves.chambers[2].spec.name, biomeAt(caves.chambers[2].center))
end
if network then
	check("volcano heart named", biomeAt(network.heart.center) == "Le Cœur du volcan", biomeAt(network.heart.center))
	local mid = network.tubes.TubeForet.samples[math.floor(#network.tubes.TubeForet.samples / 2)]
	check("lava tubes named", biomeAt(mid) == "Tunnels de lave", biomeAt(mid))
end
local rift = layout:GetAnchor("RiftFrame")
check("rift named", biomeAt(rift.center + Vector3.new(0, 60, 0)) == "Faille abyssale", biomeAt(rift.center + Vector3.new(0, 60, 0)))
check("open water named", biomeAt(Vector3.new(-700, -250, -700)) == "Le Grand Bleu", biomeAt(Vector3.new(-700, -250, -700)))
if liner then
	check("liner biome named", biomeAt(liner.center + Vector3.new(0, 20, 0)) == "L'Impératrice", biomeAt(liner.center + Vector3.new(0, 20, 0)))
	local b = BiomeLookup.Find(liner.center + Vector3.new(0, 20, 0))
	check("liner biome sees further", b and b.FogEnd and b.FogEnd >= 200)
	local bowMid = liner.bow * Vector3.new(0, 60, -250)
	check("liner bow is in its biome", biomeAt(bowMid) == "L'Impératrice", biomeAt(bowMid))
end

section("Currents")
for _, current in ipairs(Workspace.Currents:GetChildren()) do
	if not current:GetAttribute("CurrentShape") then continue end
	local points = {}
	if current:GetAttribute("CurrentShape") == "Path" then
		local parts = {}
		for _, c in ipairs(current:GetChildren()) do if c.Name:match("^CurrentPoint") then table.insert(parts, c) end end
		table.sort(parts, function(a, b) return tonumber(a.Name:match("(%d+)$")) < tonumber(b.Name:match("(%d+)$")) end)
		for i = 2, #parts do for t = 0, 1, 0.05 do table.insert(points, parts[i - 1].Position:Lerp(parts[i].Position, t)) end end
	else
		table.insert(points, current.Position)
	end
	local blocked, inWreck = 0, 0
	for _, p in ipairs(points) do
		if not isWater(p) and not (p.Y > 0 and not TERRAIN_SOLID_AT(p)) then
			blocked += 1
			if blocked <= 3 then print("  blocked", current.Name, p, TERRAIN_MATERIAL_AT(p), layout:GroundHeight(p.X, p.Z)) end
		end
		for _, volume in ipairs(layout.reserved) do
			if volume.name == "Shipwreck" or volume.name:sub(1, 10) == "Graveyard_" then
				local l = volume.cframe:PointToObjectSpace(p)
				if math.abs(l.X) < volume.half.X and math.abs(l.Y) < volume.half.Y and math.abs(l.Z) < volume.half.Z then
					inWreck += 1
					if inWreck <= 2 then print("  in wreck", current.Name, volume.name, p) end
				end
			end
		end
	end
	check(current.Name .. ": flows through water only", blocked == 0, blocked)
	check(current.Name .. ": stays out of the wreck", inWreck == 0, inWreck)
end
for _, name in ipairs({ "EpaveUpdraft", "CourantDeLaFaille", "ReefDrift", "EpaveVortex", "GrandCourant",
	"RiviereBleue", "VeineFroide", "DeriveDesMantas", "PlongeonDuLarge", "CourantDeFond", "VeineChaude",
	"RemonteeDuTombant", "CascadeDuTombant", "CourantDuLagon", "LaPasse", "PanacheDeLaFaille1", "GrandTourbillon", "RemousDeLEperon",
	"MareePuitsDuLagon", "MareeTubeEperon", "MareeTubeEpave", "MareeTubeForet", "MareeTubeKelpDore", "MareeTubeAbysses", "TourbillonDuCoeur", "RespirationDeLEperon" }) do
	check(name .. " placed", Workspace.Currents:FindFirstChild(name) ~= nil)
end
local function pathPoints(name)
	local parts = {}
	for _, c in ipairs(Workspace.Currents[name]:GetChildren()) do if c.Name:match("^CurrentPoint") then table.insert(parts, c) end end
	table.sort(parts, function(a, b) return tonumber(a.Name:match("(%d+)$")) < tonumber(b.Name:match("(%d+)$")) end)
	return parts
end
local loopPoints = pathPoints("GrandCourant")
local inner = math.huge
for _, p in ipairs(loopPoints) do inner = math.min(inner, Vector3.new(p.Position.X, 0, p.Position.Z).Magnitude) end
check("Grand Courant is a closed loop round the volcano", (loopPoints[1].Position - loopPoints[#loopPoints].Position).Magnitude < 1 and inner > 430 and #loopPoints > 100, inner)
-- Not a taxi: no current (tides aside) starts or ends at a site.
local sites = { layout:GetAnchor("WreckSite").position, layout:GetAnchor("Liner").center, layout:GetAnchor("Hub").dockEnd }
for _, anchorName in ipairs({ "Caves", "Network" }) do
	for _, entrance in ipairs(layout:GetAnchor(anchorName).entrances) do table.insert(sites, entrance.mouth) end
end
local taxis = {}
local rising, sinking, undulating = 0, 0, 0
for _, current in ipairs(Workspace.Currents:GetChildren()) do
	if current:GetAttribute("CurrentShape") == "Path" and not current:GetAttribute("CurrentTidePeriod") then
		local points = pathPoints(current.Name)
		for _, site in ipairs(sites) do
			for _, endPoint in ipairs({ points[1].Position, points[#points].Position }) do
				if (endPoint - site).Magnitude < 70 then table.insert(taxis, current.Name) end
			end
		end
		local net = points[#points].Position.Y - points[1].Position.Y
		if net > 80 then rising += 1 elseif net < -80 then sinking += 1 end
		local ups, downs = 0, 0
		for i = 2, #points do
			local dy = points[i].Position.Y - points[i - 1].Position.Y
			if dy > 2 then ups += 1 elseif dy < -2 then downs += 1 end
		end
		if ups >= 3 and downs >= 3 then undulating += 1 end
	end
end
check("no current is a taxi to a site", #taxis == 0, table.concat(taxis, ","))
check("some currents rise", rising >= 3, rising)
check("some currents sink", sinking >= 2, sinking)
check("currents rise and dive along the way", undulating >= 5, undulating)
local phases = {}
for _, current in ipairs(Workspace.Currents:GetChildren()) do
	if current:GetAttribute("CurrentTidePeriod") then phases[current:GetAttribute("CurrentTidePhase")] = true end
end
local phaseCount = 0
for _ in pairs(phases) do phaseCount += 1 end
check("the tunnels breathe with the tide, out of phase", phaseCount >= 6, phaseCount)
local ribbons, segments = 0, 0
for _, current in ipairs(Workspace.Currents:GetChildren()) do
	local folder = current:FindFirstChild("PathSegments")
	if folder then
		for _, segment in ipairs(folder:GetChildren()) do
			segments += 1
			for _, child in ipairs(segment:GetChildren()) do if child.ClassName == "Beam" then ribbons += 1 end end
		end
	end
end
check("every path segment carries flow ribbons", ribbons == segments * 3, ribbons .. "/" .. segments * 3)
check("entry beacons mark the main currents", #Workspace.Currents.Beacons:GetChildren() >= 7, #Workspace.Currents.Beacons:GetChildren())

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
	local position = t:GetPivot().Position
	local zone = DepthUtils.GetZoneIndexForDepth(DepthUtils.GetDepth(position))
	perZone[zone] = (perZone[zone] or 0) + 1
	if not isWater(position) then
		buried += 1
		print("  buried treasure", position, TERRAIN_MATERIAL_AT(position))
	end
end
for zone = 1, 4 do
	check("zone " .. zone .. " has at least 15 treasures", (perZone[zone] or 0) >= 15, perZone[zone])
end
check("no treasure buried in terrain", buried == 0, buried)
local TreasureConfig = require(ReplicatedStorage.Shared.Config.TreasureConfig)
local TreasureModels = require(ReplicatedStorage.Shared.Modules.TreasureModels)
local modelled, detailed = 0, 0
for _, kind in ipairs(TreasureConfig.Types) do
	if TreasureModels.Has(kind.Id) then modelled += 1 end
	local model = TreasureModels.Build(kind)
	if #model:GetChildren() >= 5 and model.PrimaryPart then detailed += 1 end
end
check("every treasure type has its own model", modelled == #TreasureConfig.Types, modelled .. "/" .. #TreasureConfig.Types)
check("treasure models are detailed (5+ parts)", detailed == #TreasureConfig.Types, detailed)
local prompted = 0
for _, t in ipairs(treasures) do
	if t:IsA("Model") and t.PrimaryPart and t.PrimaryPart:FindFirstChildOfClass("ProximityPrompt") then prompted += 1 end
end
check("every spawned treasure is a model with a pickup prompt", prompted == #treasures, prompted .. "/" .. #treasures)

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

section("Hub")
local hub = layout:GetAnchor("Hub")
check("hub built", hub ~= nil and Workspace:FindFirstChild("Hub") ~= nil)
if hub then
	check("shop counter opens the shop", hub.shopPrompt:GetAttribute("OpensShop") == true)
	local floating = 0
	for _, p in ipairs(Workspace.Hub:GetDescendants()) do
		if p.Name == "Piling" or p.Name == "Stilt" then
			local bottom = p.Position.Y - p.Size.X / 2
			if bottom > layout:GroundHeight(p.Position.X, p.Position.Z) + 0.1 then floating += 1 end
		end
	end
	check("every piling and stilt reaches the ground", floating == 0, floating)
	local boatBottom = Workspace.Hub.Ponton.BateauDePlongee.HullBottom
	local keel = boatBottom.Position.Y - boatBottom.Size.Y / 2
	check("dive boat floats at the surface", keel < 0 and keel > -3 and isWater(boatBottom.Position - Vector3.new(0, 0.5, 0)), keel)
	check("lighthouse stands on the island", layout:GroundHeight(hub.lighthouse.X, hub.lighthouse.Z) >= 3)
	local signs = 0
	for _, p in ipairs(Workspace.Hub.Place:GetChildren()) do
		if p.Name == "SignBoard" then signs += 1 end
	end
	check("signpost points to the dive sites", signs >= 4, signs)
	local clutter = 0
	for _, p in ipairs(Workspace.BeachProps:GetChildren()) do
		local l = hub.diveCentre:PointToObjectSpace(p.Position)
		if math.abs(l.X) < 20 and math.abs(l.Z) < 13 and l.Y < 12 then clutter += 1 end
	end
	check("no palm or rock inside the dive centre", clutter == 0, clutter)
end

section("Island life")
local life = Workspace:FindFirstChild("IslandLife")
check("island life planted", life ~= nil and #life.Flora:GetChildren() > 300, life and #life.Flora:GetChildren())
local wet, inBuildings = 0, 0
for _, p in ipairs(life.Flora:GetChildren()) do
	if p.Name == "PalmTrunk" or p.Name == "HibiscusBush" or p.Name == "BananaStem" then
		local g = layout:GroundHeight(p.Position.X, p.Position.Z)
		if g < 3 then wet += 1 end
		for _, volume in ipairs(layout.reserved) do
			if volume.kind == "box" and volume.name:match("^Hub_") then
				local l = volume.cframe:PointToObjectSpace(p.Position)
				if math.abs(l.X) < volume.half.X and math.abs(l.Y) < volume.half.Y and math.abs(l.Z) < volume.half.Z then inBuildings += 1 end
			end
		end
	end
end
check("island plants grow on dry land", wet == 0, wet)
check("no plant growing through the hub", inBuildings == 0, inBuildings)
local CollectionService = game:GetService("CollectionService")
for _, tag in ipairs({ "Crab", "Seagull", "Butterfly", "Parrot", "Dolphin" }) do
	local animals, rigged = 0, 0
	for _, m in ipairs(CollectionService:GetTagged(tag)) do
		animals += 1
		if m.PrimaryPart then rigged += 1 end
	end
	check(tag .. ": on the island, ready to animate", animals > 0 and rigged == animals, animals)
end

section("Equipment")
do
	local Players = game:GetService("Players")
	local player = Instance.new("Player")
	player.Name = "Diver"
	player.UserId = 4242
	player.CharacterAdded = Instance.new("BindableEvent").Event
	local function num(name, value)
		local v = Instance.new("NumberValue")
		v.Name = name
		v.Value = value
		v.Parent = player
		return v
	end
	local maxOxygen = num("MaxOxygen", 60)
	local drain = num("OxygenDrainPerSecond", 1)
	local oxygen = num("Oxygen", 60)
	num("Depth", 0)
	local character = Instance.new("Model")
	for name, size in pairs({ Head = Vector3.new(1.2, 1.2, 1.2), UpperTorso = Vector3.new(2, 1.6, 1), LowerTorso = Vector3.new(2, 0.4, 1), LeftFoot = Vector3.new(1, 0.3, 1), RightFoot = Vector3.new(1, 0.3, 1), LeftUpperArm = Vector3.new(1, 1.2, 1) }) do
		local limb = Instance.new("Part")
		limb.Name = name
		limb.Size = size
		limb.Color = Color3.fromRGB(200, 150, 110)
		limb.Parent = character
	end
	local shirt = Instance.new("Shirt")
	shirt.Parent = character
	player.Character = character
	table.insert(PLAYERS, player)
	RUN_SCRIPT("ServerScriptService", "Player", "EquipmentService")
	Players.PlayerAdded:Fire(player)
	local handler = ReplicatedStorage.EquipmentRequest.OnServerInvoke
	local coins = player.leaderstats["Pièces"]
	local function ask(action, id)
		CLOCK += 1
		return handler(player, action, id)
	end
	check("starts with the club's gear", player:GetAttribute("Equipped_Tank") == "TankStarter" and maxOxygen.Value == 60)
	check("tank on the back from the start", character.DiveGear:FindFirstChild("GearTank") ~= nil)
	check("cannot buy without the Pièces", ask("Buy", "Tank15").ok == false)
	coins.Value = 1000
	local bought = ask("Buy", "Tank15")
	check("buys a tank", bought.ok == true, bought.message)
	check("price taken", coins.Value == 400, coins.Value)
	check("new tank: more air", maxOxygen.Value == 120 and oxygen.Value == 120, maxOxygen.Value)
	check("cannot buy twice", ask("Buy", "Tank15").ok == false)
	check("can switch back to an owned tank", ask("Equip", "TankStarter").ok == true and maxOxygen.Value == 60)
	check("cannot equip what is not owned", ask("Equip", "Rebreather").ok == false)
	check("fins bought", ask("Buy", "FinsShort").ok == true and player:GetAttribute("SwimSpeedMultiplier") == 1.12)
	local finParts = 0
	for _, p in ipairs(character.DiveGear:GetChildren()) do if p.Name == "GearFin" then finParts += 1 end end
	check("fins on both feet", finParts == 2, finParts)
	check("lamp bought", ask("Buy", "LampTorch").ok == true)
	local lens = character.DiveGear:FindFirstChild("GearLampLens")
	check("head lamp casts a beam", lens ~= nil and lens:FindFirstChildOfClass("SpotLight") ~= nil and lens:FindFirstChildOfClass("SpotLight").Range == 40)
	coins.Value = 5000
	check("suit bought", ask("Buy", "Shorty").ok == true and math.abs(drain.Value - 0.9) < 1e-6, drain.Value)
	check("suit worn: body recoloured, shirt set aside", character.UpperTorso.Color.B > 0.6 and shirt.Parent ~= character)
	check("back in swimwear: skin and shirt restored", ask("Equip", "SuitNone").ok == true and shirt.Parent == character and math.abs(character.UpperTorso.Color.R - 200 / 255) < 0.01)
	check("unknown item refused", ask("Buy", "Submarine").ok == false)
	check("owned list mirrored for the UI", string.find(player:GetAttribute("OwnedEquipment"), "Tank15") ~= nil)
	local PlayerData = require(ServerScriptService.Player.PlayerData)
	local data = PlayerData.Get(player)
	check("progress kept in PlayerData", data.Coins == coins.Value and data.Owned.Shorty == true and data.Equipped.Suit == "SuitNone")
end

print(string.format("\n%d checks, %d failures", checks, failures))
if failures > 0 then
	error(string.format("%d world checks failed", failures), 0)
end
print("ALL WORLD CHECKS PASSED")
