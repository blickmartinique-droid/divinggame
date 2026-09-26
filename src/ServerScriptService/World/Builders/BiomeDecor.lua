-- Life and set dressing for each biome, placed on the real seabed
-- (layout:GroundHeight from Seabed.lua) with a seeded generator, so the
-- same reef is there on every server start. The models themselves come
-- from MarineFlora. Last WorldBootstrap step before the biome names.
--
--   * Lagoon reef (the beach's submerged shelf, 6-15 m): limestone reef
--     rocks crowned with coral (they also break up the shelf's edge);
--     coral heads -- staghorn, brain, table, mushroom, soft corals, sea
--     fans, tube and barrel sponges, anemones with their clownfish --
--     urchins, starfish, giant clams, seagrass meadows and young kelp.
--   * Coral gardens on the upper flanks, glowing anemone fields deeper.
--   * The reef wall ("tombant", 50-110 m): sea fans, barrel and tube
--     sponges and soft corals growing out of the cliff face.
--   * Kelp forests on the western and eastern flanks: jointed giant kelp
--     with bladders and blades, bending as a chain.
--   * Abyssal rift (500 m): black smokers with ledges and mineral crusts,
--     bacterial mats, tube-worm colonies, glowing cracks, shrimp swarms.
--   * The abyssal plain: sea lilies, sea pens, Venus' flower baskets and
--     glowing tunicates.
-- Creature SpawnRegions are placed with the habitats they belong to.
-- Swaying plants are tagged "Sway" (see MarineFlora / FloraAnimator).

local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")

local MarineFlora = require(script.Parent.MarineFlora)

local BiomeDecor = {}

local UP = Vector3.new(0, 1, 0)

local CORAL_COLORS = {
	Color3.fromRGB(240, 120, 90), Color3.fromRGB(255, 170, 60), Color3.fromRGB(230, 90, 150),
	Color3.fromRGB(120, 200, 190), Color3.fromRGB(250, 220, 120), Color3.fromRGB(150, 110, 220),
	Color3.fromRGB(160, 210, 100), Color3.fromRGB(90, 140, 225),
}
local SOFT_COLORS = { Color3.fromRGB(255, 110, 170), Color3.fromRGB(170, 90, 230), Color3.fromRGB(255, 140, 70), Color3.fromRGB(230, 60, 80) }
local SPONGE_COLORS = { Color3.fromRGB(230, 140, 60), Color3.fromRGB(170, 90, 70), Color3.fromRGB(230, 200, 80), Color3.fromRGB(140, 80, 160) }
local FAN_COLORS = { Color3.fromRGB(200, 60, 110), Color3.fromRGB(240, 150, 60), Color3.fromRGB(150, 80, 200), Color3.fromRGB(230, 200, 90) }
local ANEMONES = {
	{ column = Color3.fromRGB(200, 70, 90), tentacle = Color3.fromRGB(255, 170, 200) },
	{ column = Color3.fromRGB(120, 90, 60), tentacle = Color3.fromRGB(190, 230, 120) },
	{ column = Color3.fromRGB(150, 60, 140), tentacle = Color3.fromRGB(240, 200, 240) },
}
local KELP_GREEN = Color3.fromRGB(78, 132, 58)
local KELP_OLIVE = Color3.fromRGB(104, 118, 46)
local KELP_GOLD = Color3.fromRGB(128, 120, 52)

function BiomeDecor.Build(layout)
	local rng = layout:Random("BiomeDecor")
	local kit = MarineFlora.new(rng)
	-- Workspace attribute DecorDensity (0.25-1.5, default 1) scales how
	-- much life is planted: lower it for weaker devices.
	local density = math.clamp(tonumber(Workspace:GetAttribute("DecorDensity")) or 1, 0.25, 1.5)
	local function amount(count: number): number
		return math.max(1, math.floor(count * density + 0.5))
	end
	local function random(): number
		return rng:NextNumber()
	end

	local existing = Workspace:FindFirstChild("WorldDecor")
	if existing then
		existing:Destroy()
	end
	local decor = Instance.new("Folder")
	decor.Name = "WorldDecor"
	decor.Parent = Workspace
	local function folder(name: string)
		local f = Instance.new("Folder")
		f.Name = name
		f.Parent = decor
		return f
	end
	local terrain = Workspace.Terrain

	local function ground(x: number, z: number): Vector3
		return Vector3.new(x, layout:GroundHeight(x, z), z)
	end
	local function onBearing(degrees: number, radius: number): (number, number)
		local a = math.rad(degrees)
		return math.cos(a) * radius, math.sin(a) * radius
	end
	local function creatureRegion(name: string, center: Vector3, size: Vector3, species: string, amount: number, wander: number?)
		local region = kit:part(decor, name, size, CFrame.new(center), Enum.Material.SmoothPlastic, Color3.new(1, 1, 1))
		region.Transparency = 1
		region:SetAttribute("RegionKind", "Creature")
		region:SetAttribute("RegionEnabled", true)
		region:SetAttribute("RegionCount", amount)
		region:SetAttribute("RegionSpecies", species)
		if wander then
			region:SetAttribute("RegionWanderRadius", wander)
		end
		CollectionService:AddTag(region, "SpawnRegion")
	end

	-- Keep the cave mouths clear: decor is planted on the heightfield, which
	-- knows nothing of the holes, so anything that landed in (or over) a
	-- porch or its cleft would float there and hide the way in.
	-- Same for the wrecks' volumes (the Sirène, the graveyard, the liner)
	-- and the hub's buildings: no coral growing through a hull or a jetty.
	local caves = layout:GetAnchor("Caves")
	local network = layout:GetAnchor("Network")
	local keepOut = {}
	for _, volume in ipairs(layout.reserved) do
		if volume.kind == "box" and (volume.name == "Shipwreck" or volume.name:match("^Graveyard_") or volume.name:match("^Liner_") or volume.name:match("^Hub_")) then
			table.insert(keepOut, volume)
		end
	end
	local function blocked(position: Vector3, margin: number?): boolean
		local m = margin or 0
		for _, anchor in ipairs({ caves, network }) do
			for _, entrance in ipairs(anchor and anchor.entrances or {}) do
				if (position - entrance.mouth).Magnitude < entrance.clearRadius + m then
					return true
				end
			end
		end
		for _, volume in ipairs(keepOut) do
			local l = volume.cframe:PointToObjectSpace(position)
			if math.abs(l.X) < volume.half.X + m and math.abs(l.Y) < volume.half.Y + m and math.abs(l.Z) < volume.half.Z + m then
				return true
			end
		end
		return false
	end

	-- Lagoon reef --------------------------------------------------------------------
	local reef = folder("LagoonReef")

	-- Reef rocks, each a main boulder with a lump or two beside
	-- it; the heightfield knows nothing of them, so they are remembered
	-- (and reserved, for the treasure and creature spawners) and nothing
	-- else is planted inside one.
	local rocks = {}
	local function inRock(point: Vector3, margin: number): boolean
		for _, rock in ipairs(rocks) do
			if (point - rock.center).Magnitude < rock.radius + margin then
				return true
			end
		end
		return false
	end
	local function onlyBeach(name: string): boolean
		return name == "Beach"
	end
	local function lagoonPoint(minRadius: number, maxRadius: number): Vector3
		local angle = random() * math.pi * 2
		local radius = minRadius + random() * (maxRadius - minRadius)
		return ground(math.cos(angle) * radius, math.sin(angle) * radius)
	end

	-- One coral head: a random pick of the reef's corals, sponges and
	-- anemones. `deep` gardens get glowing anemones.
	local function coralHead(parent: Instance, base: Vector3, deep: boolean?)
		local color = kit:pick(CORAL_COLORS)
		local roll = random()
		if roll < 0.24 then
			kit:Branching(parent, base, kit:range(2.5, 5), color)
		elseif roll < 0.38 then
			kit:Brain(parent, base, kit:range(2.2, 5), color)
		elseif roll < 0.48 then
			kit:Table(parent, base, kit:range(4, 8), color)
		elseif roll < 0.6 then
			kit:SeaFan(parent, CFrame.new(base) * CFrame.Angles(0, kit:range(0, math.pi), 0), kit:range(2.5, 5), kit:pick(FAN_COLORS))
		elseif roll < 0.7 then
			kit:TubeSponges(parent, base, kit:range(2, 4), kit:pick(SPONGE_COLORS))
		elseif roll < 0.8 then
			kit:SoftCoral(parent, base, kit:range(2, 4), kit:pick(SOFT_COLORS))
		elseif roll < 0.86 then
			kit:Barrel(parent, CFrame.new(base) * CFrame.Angles(kit:range(-0.1, 0.1), kit:range(0, 3), kit:range(-0.1, 0.1)), kit:range(2, 4), kit:pick(SPONGE_COLORS))
		elseif roll < 0.93 then
			local look = kit:pick(ANEMONES)
			kit:Anemone(parent, base, kit:range(0.7, 1.1), look.column, look.tentacle, deep, 10)
		else
			kit:Mushroom(parent, base, kit:range(1, 1.8), color)
		end
	end

	local function reefRock(center: Vector3, radius: number, corals: number): boolean
		if blocked(center, radius + 4) or inRock(center, radius * 0.5) or layout:VolumeAt(center, radius + 2, onlyBeach) then
			return false
		end
		-- Grey rock under a brown turf of algae (the cap ball only touches
		-- the boulder's top, so the shape stays the boulder's).
		terrain:FillBall(center, radius, Enum.Material.Rock)
		terrain:FillBall(center + Vector3.new(0, radius * 0.3, 0), radius * 0.7, Enum.Material.Ground)
		table.insert(rocks, { center = center, radius = radius })
		for _ = 1, 2 do
			local angle = random() * math.pi * 2
			local lump = radius * kit:range(0.45, 0.7)
			local at = center + Vector3.new(math.cos(angle) * radius * 0.85, -lump * 0.25, math.sin(angle) * radius * 0.85)
			if not blocked(at, lump + 3) then
				terrain:FillBall(at, lump, random() < 0.5 and Enum.Material.Rock or Enum.Material.Limestone)
				table.insert(rocks, { center = at, radius = lump })
			end
		end
		for _ = 1, corals do
			coralHead(reef, center + kit:bend(UP, kit:range(0, 0.7)) * radius * 0.97)
		end
		return true
	end
	-- Along the shelf's step (6 m down to 15 m), softening the terrace.
	for k = 1, 30 do
		local x, z = onBearing(k * 12 + kit:range(-4, 4), 140 + kit:range(-3, 3))
		local radius = kit:range(4, 7)
		reefRock(Vector3.new(x, -10.5 + kit:range(-1.5, 0.5), z), radius, rng:NextInteger(1, 3))
	end
	-- Bommies on the outer ring, low rocks on the shelf.
	for _ = 1, 16 do
		local spot = lagoonPoint(150, 174)
		local radius = kit:range(3.5, 6)
		reefRock(spot - Vector3.new(0, radius * 0.35, 0), radius, rng:NextInteger(2, 4))
	end
	for _ = 1, 12 do
		local spot = lagoonPoint(86, 130)
		local radius = kit:range(2.4, 3.4)
		reefRock(spot - Vector3.new(0, radius * 0.4, 0), radius, rng:NextInteger(1, 2))
	end

	-- From here on the rocks are part of the seabed for everyone who asks
	-- the layout (coral, treasures, creatures and their wandering).
	layout:SetAnchor("ReefRocks", rocks)
	do
		local CELL = 16
		local cells = {}
		for _, rock in ipairs(rocks) do
			for cx = math.floor((rock.center.X - rock.radius) / CELL), math.floor((rock.center.X + rock.radius) / CELL) do
				for cz = math.floor((rock.center.Z - rock.radius) / CELL), math.floor((rock.center.Z + rock.radius) / CELL) do
					local key = cx * 100000 + cz
					cells[key] = cells[key] or {}
					table.insert(cells[key], rock)
				end
			end
		end
		local seabed = layout.ground
		if seabed and #rocks > 0 then
			layout:SetGround(function(x: number, z: number): number
				local height = seabed(x, z)
				local list = cells[math.floor(x / CELL) * 100000 + math.floor(z / CELL)]
				if list then
					for _, rock in ipairs(list) do
						local dx, dz = x - rock.center.X, z - rock.center.Z
						local left = rock.radius * rock.radius - dx * dx - dz * dz
						if left > 0 then
							height = math.max(height, rock.center.Y + math.sqrt(left))
						end
					end
				end
				return height
			end)
		end
	end

	-- A spot on the open sand of the lagoon, or nil in a rock, a mouth or
	-- under the hub.
	local function sand(minRadius: number, maxRadius: number, margin: number): Vector3?
		for _ = 1, 6 do
			local spot = lagoonPoint(minRadius, maxRadius)
			if not inRock(spot, margin) and not blocked(spot, margin) then
				return spot
			end
		end
		return nil
	end
	for _ = 1, amount(110) do
		local spot = sand(76, 176, 1.5)
		if spot then
			coralHead(reef, spot)
		end
	end
	-- Staghorn thickets.
	for _ = 1, amount(6) do
		local center = sand(90, 170, 4)
		if center then
			local color = kit:pick(CORAL_COLORS)
			for _ = 1, 5 do
				local spot = ground(center.X + kit:range(-4, 4), center.Z + kit:range(-4, 4))
				if not inRock(spot, 1) then
					kit:Branching(reef, spot, kit:range(3, 5.5), color)
				end
			end
		end
	end
	-- Anemones with their pair of clownfish.
	for _ = 1, amount(10) do
		local spot = sand(84, 172, 2)
		if spot then
			local look = kit:pick(ANEMONES)
			local anemone, over = kit:Anemone(reef, spot, 1.2, look.column, look.tentacle, false, 14)
			for index = 0, 1 do
				kit:Clownfish(anemone, over, index)
			end
		end
	end
	for _ = 1, amount(36) do -- urchins and starfish on the sand
		local spot = sand(70, 178, 1)
		if spot then
			if random() < 0.45 then
				kit:Urchin(reef, spot, kit:range(0.8, 1.2))
			else
				kit:Starfish(reef, spot, kit:range(1, 1.6), kit:pick({ Color3.fromRGB(240, 110, 60), Color3.fromRGB(90, 110, 230), Color3.fromRGB(230, 70, 80), Color3.fromRGB(250, 190, 70) }))
			end
		end
	end
	for _ = 1, amount(8) do -- giant clams
		local spot = sand(90, 170, 2)
		if spot then
			kit:Clam(reef, spot, kit:range(2.4, 3.4))
		end
	end
	for _ = 1, amount(26) do -- seagrass meadows
		local center = sand(80, 170, 6)
		if center then
			kit:Seagrass(reef, ground, center, 12, 14)
		end
	end
	for _ = 1, amount(24) do -- young kelp near the reef crest
		local spot = sand(150, 176, 1.5)
		if spot then
			kit:Kelp(reef, spot - Vector3.new(0, 0.3, 0), kit:range(7, 11), KELP_GREEN)
		end
	end
	for k = 1, 6 do
		local x, z = onBearing(k * 60 + 20, 128)
		creatureRegion("Creatures_Lagoon" .. k, Vector3.new(x, -10, z), Vector3.new(50, 5, 50), "PoissonRecif,TortueMarine", 8)
	end

	-- Coral gardens on the upper flanks (60-150 m), just below the wall:
	-- coral heads in clusters, with anemone fields, and reef fish over them.
	local flank = folder("FlankGardens")
	local gardens = 0
	for _ = 1, 400 do
		if gardens >= amount(36) then
			break
		end
		local x, z = onBearing(random() * 360, 215 + random() * 90)
		local center = ground(x, z)
		if center.Y < -60 and center.Y > -150 and layout:IsFree(center + Vector3.new(0, 8, 0), 2) and not blocked(center, 6) then
			gardens += 1
			for _ = 1, rng:NextInteger(3, 5) do
				coralHead(flank, ground(center.X + (random() - 0.5) * 22, center.Z + (random() - 0.5) * 22))
			end
			if gardens % 9 == 0 then
				-- Reef fish only live above 120 m; deeper gardens get turtles and rays.
				local species = center.Y + 12 > -110 and "PoissonRecif,TortueMarine" or "TortueMarine,RaieManta"
				creatureRegion("Creatures_FlankGarden" .. gardens, center + Vector3.new(0, 12, 0), Vector3.new(40, 10, 40), species, 8, 30)
			end
		end
	end
	-- Anemone fields deeper on the flanks, glowing in the dim light.
	for _ = 1, amount(24) do
		local x, z = onBearing(random() * 360, 280 + random() * 120)
		local center = ground(x, z)
		if center.Y < -160 and center.Y > -300 and layout:IsFree(center + Vector3.new(0, 6, 0), 2) and not blocked(center, 4) then
			for _ = 1, rng:NextInteger(3, 6) do
				local at = ground(center.X + (random() - 0.5) * 16, center.Z + (random() - 0.5) * 16)
				local hue = random() < 0.5 and Color3.fromRGB(255, 120, 200) or Color3.fromRGB(120, 255, 200)
				kit:Anemone(flank, at, kit:range(0.7, 1), Color3.fromRGB(120, 60, 90), hue, true, 9)
			end
		end
	end

	-- The reef wall -------------------------------------------------------------------
	-- A spot on the cliff: march outward along a bearing until the seabed
	-- drops below the target depth; the growth sticks out of the face there.
	local wall = folder("ReefWall")
	for _ = 1, amount(140) do
		local bearing = random() * 360
		local targetY = -55 - random() * 55
		local a = math.rad(bearing)
		local out = Vector3.new(math.cos(a), 0, math.sin(a))
		for radius = 180, 320, 2 do
			if layout:GroundHeight(out.X * radius, out.Z * radius) < targetY then
				local face = Vector3.new(out.X * (radius - 2.5), targetY, out.Z * (radius - 2.5))
				if blocked(face, 3) then
					break
				end
				local along = UP:Cross(out)
				local roll = random()
				if roll < 0.45 then
					-- Fans stand parallel to the face, leaning out into the current.
					local frame = CFrame.fromMatrix(face + out * 0.6, along, (UP * 0.94 + out * 0.34).Unit)
					kit:SeaFan(wall, frame, kit:range(4, 8), kit:pick(FAN_COLORS))
				elseif roll < 0.7 then
					kit:Barrel(wall, CFrame.fromMatrix(face - out * 0.3, along, (UP * 0.8 + out * 0.6).Unit), kit:range(2.5, 4.5), kit:pick(SPONGE_COLORS))
				elseif roll < 0.85 then
					kit:SoftCoral(wall, face + out * 0.5, kit:range(2.5, 4), kit:pick(SOFT_COLORS))
				else
					kit:TubeSponges(wall, face + out * 0.4, kit:range(2.5, 4), kit:pick(SPONGE_COLORS))
				end
				break
			end
		end
	end

	-- Kelp forests ---------------------------------------------------------------------------
	local kelpForest = folder("KelpForest")
	local function plantKelp(amount: number, bearingFrom: number, bearingSpan: number, radialSpan: number, minY: number, maxY: number, shortest: number, tallest: number, colors: { Color3 })
		local planted = 0
		for _ = 1, 400 do
			if planted >= amount then
				break
			end
			local x, z = onBearing(bearingFrom + random() * bearingSpan, 215 + random() * radialSpan)
			local base = ground(x, z)
			if base.Y < maxY and base.Y > minY and layout:IsFree(base + Vector3.new(0, 10, 0), 3) and not blocked(base, 3) then
				planted += 1
				kit:Kelp(kelpForest, base - Vector3.new(0, 0.5, 0), kit:range(shortest, tallest), kit:pick(colors))
			end
		end
	end
	-- The great forest on the western flank, a golden one on the east.
	plantKelp(amount(96), 235, 60, 110, -165, -85, 24, 48, { KELP_GREEN, KELP_GREEN, KELP_OLIVE, KELP_GOLD })
	plantKelp(amount(76), 95, 40, 100, -170, -80, 20, 42, { KELP_GOLD, KELP_GOLD, KELP_OLIVE })
	do
		local x, z = onBearing(265, 270)
		creatureRegion("Creatures_KelpForest", Vector3.new(x, -110, z), Vector3.new(120, 30, 120), "TortueMarine,RaieManta", 6, 70)
		x, z = onBearing(115, 265)
		creatureRegion("Creatures_KelpForestEast", Vector3.new(x, -105, z), Vector3.new(110, 30, 110), "TortueMarine,RaieManta,PoissonRecif", 8, 60)
	end

	-- Abyssal rift ---------------------------------------------------------------------------
	local rift = layout:GetAnchor("RiftFrame")
	local abyss = folder("Abyss")
	if rift then
		for k = -2, 2 do
			local at = rift.center + rift.along * (k * 60 + (random() - 0.5) * 20) + rift.across * ((random() - 0.5) * 16)
			local base = ground(at.X, at.Z)
			-- Glowing cracks in the rock around the vent.
			terrain:FillBall(base - Vector3.new(0, 2, 0), 7 + random() * 3, Enum.Material.CrackedLava)
			local _, throat = kit:Chimney(abyss, base, kit:range(16, 28), ground)
			local glow = Instance.new("PointLight")
			glow.Color = Color3.fromRGB(255, 120, 60)
			glow.Range = 24
			glow.Brightness = 1.6
			glow.Parent = throat
			local smoke = Instance.new("ParticleEmitter")
			smoke.Rate = 14
			smoke.Lifetime = NumberRange.new(4, 7)
			smoke.Speed = NumberRange.new(3, 6)
			smoke.SpreadAngle = Vector2.new(8, 8)
			smoke.EmissionDirection = Enum.NormalId.Top
			smoke.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 6) })
			smoke.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) })
			smoke.Color = ColorSequence.new(Color3.fromRGB(20, 18, 20))
			smoke.Parent = throat
			-- A swarm of pale vent shrimp flickering around the chimney's foot.
			local swarm = kit:part(abyss, "ShrimpSwarm", Vector3.new(12, 6, 12), CFrame.new(base + Vector3.new(0, 4, 0)), Enum.Material.SmoothPlastic, Color3.new(1, 1, 1))
			swarm.Transparency = 1
			local shrimp = Instance.new("ParticleEmitter")
			shrimp.Rate = 5
			shrimp.Lifetime = NumberRange.new(2, 4)
			shrimp.Speed = NumberRange.new(0.5, 1.5)
			shrimp.SpreadAngle = Vector2.new(180, 180)
			shrimp.Size = NumberSequence.new(0.25)
			shrimp.LightEmission = 0.3
			shrimp.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.2, 0.2), NumberSequenceKeypoint.new(0.8, 0.2), NumberSequenceKeypoint.new(1, 1) })
			shrimp.Color = ColorSequence.new(Color3.fromRGB(240, 230, 220))
			shrimp.Parent = swarm
			-- Tube worms: white stalks, blood-red plumes.
			for _ = 1, 18 do
				local angle = random() * math.pi * 2
				local distance = 5 + random() * 8
				kit:TubeWorm(abyss, ground(base.X + math.cos(angle) * distance, base.Z + math.sin(angle) * distance), kit:range(2, 6))
			end
		end
		creatureRegion("Creatures_Rift", rift.center + Vector3.new(0, 40, 0), Vector3.new(200, 30, 60), "MeduseLumineuse", 6, 60)
	end

	-- Abyssal plain -----------------------------------------------------------------------------
	local function plainSpot(minRadius: number, span: number): Vector3?
		local angle = random() * math.pi * 2
		local radius = minRadius + random() * span
		local base = ground(math.cos(angle) * radius, math.sin(angle) * radius)
		if base.Y < -440 and math.abs(base.X) < 980 and math.abs(base.Z) < 980 and not blocked(base, 4) then
			return base
		end
		return nil
	end
	for _ = 1, amount(50) do
		local base = plainSpot(500, 420)
		if base then
			kit:Crinoid(abyss, base, kit:range(4, 8), random() < 0.5 and Color3.fromRGB(230, 180, 90) or Color3.fromRGB(200, 90, 120))
		end
	end
	for _ = 1, amount(105) do
		local base = plainSpot(480, 450)
		if base then
			local kind = random()
			if kind < 0.4 then
				kit:SeaPen(abyss, base, kit:range(3, 7), Color3.fromRGB(150, 110, 255))
			elseif kind < 0.7 then
				kit:GlassSponge(abyss, base, kit:range(5, 12))
			else
				kit:GlowCluster(abyss, base, random() < 0.5 and Color3.fromRGB(90, 220, 255) or Color3.fromRGB(150, 110, 255))
			end
		end
	end

	-- Open water ("le grand bleu"): mantas and sharks patrol well off the
	-- island, where nothing blocks their long glides.
	for k = 1, 5 do
		local x, z = onBearing(k * 72 - 40, 690)
		if math.abs(x) < 900 and math.abs(z) < 900 then
			creatureRegion("Creatures_OpenWater" .. k, Vector3.new(x, -200, z), Vector3.new(200, 80, 200), "RaieManta,RequinRecif", 6)
		end
	end
	for k = 1, 2 do
		local x, z = onBearing(k * 150 + 70, 820)
		creatureRegion("Creatures_AbyssPlain" .. k, Vector3.new(x, -440, z), Vector3.new(160, 30, 160), "MeduseLumineuse", 5)
	end

	-- Final sweep: a model any part of which reaches into a mouth, a hull
	-- or the hub goes whole (spots are checked before planting, but a big
	-- fan or kelp can still lean in).
	local count = kit.count
	for _, group in ipairs(decor:GetChildren()) do
		if group:IsA("Folder") then
			for _, item in ipairs(group:GetChildren()) do
				local parts = {}
				if item:IsA("BasePart") then
					parts = { item }
				else
					for _, descendant in ipairs(item:GetDescendants()) do
						if descendant:IsA("BasePart") then
							table.insert(parts, descendant)
						end
					end
				end
				for _, part in ipairs(parts) do
					if blocked(part.Position) then
						item:Destroy()
						count -= #parts
						break
					end
				end
			end
		end
	end

	print(string.format("[BiomeDecor] %d decor parts, %d reef rocks", count, #rocks))
end

return BiomeDecor
