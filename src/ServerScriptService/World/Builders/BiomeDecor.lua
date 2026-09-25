-- Life and set dressing for each biome, placed on the real seabed
-- (layout:GroundHeight from Seabed.lua) with a seeded generator, so the
-- same reef is there on every server start. Last WorldBootstrap step.
--
--   * Lagoon reef (the beach's submerged shelf, 6-15 m): coral gardens --
--     branching, brain, table and fan corals, tube sponges, anemones,
--     urchins, starfish, giant clams -- seagrass meadows and kelp.
--   * The reef wall ("tombant", 50-110 m): sea fans and sponges growing
--     out of the cliff face.
--   * Kelp forest on the western flank (90-160 m): tall swaying stalks.
--   * Abyssal rift (500 m): black-smoker vents with glowing throats and
--     smoke, tube-worm colonies, glowing cracks in the rock, glass sponges.
--   * The abyssal plain: bioluminescent sea pens and glowing nodes.
-- Creature SpawnRegions are placed with the habitats they belong to.
-- Anything tall enough to wave carries a "Sway" attribute, animated per
-- client by FloraAnimator.

local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")


local BiomeDecor = {}

local CORAL_COLORS = {
	Color3.fromRGB(240, 120, 90), Color3.fromRGB(255, 170, 60), Color3.fromRGB(230, 90, 150),
	Color3.fromRGB(120, 200, 190), Color3.fromRGB(250, 220, 120), Color3.fromRGB(150, 110, 220),
}
local KELP_GREEN = Color3.fromRGB(78, 132, 58)
local KELP_GOLD = Color3.fromRGB(128, 120, 52)

function BiomeDecor.Build(layout)
	local rng = layout:Random("BiomeDecor")
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

	local count = 0
	local function prop(parent: Instance, name: string, size: Vector3, cframe: CFrame, material: Enum.Material, color: Color3, shape: Enum.PartType?): Part
		local part = Instance.new("Part")
		part.Name = name
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = size.Magnitude > 8
		part.Shape = shape or Enum.PartType.Block
		part.Size = size
		part.CFrame = cframe
		part.Material = material
		part.Color = color
		part.Parent = parent
		count += 1
		return part
	end
	local function ellipsoid(parent: Instance, name: string, size: Vector3, cframe: CFrame, material: Enum.Material, color: Color3): Part
		local part = prop(parent, name, size, cframe, material, color)
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = part
		return part
	end
	local function sway(part: Part, amplitude: number, speed: number)
		CollectionService:AddTag(part, "Sway")
		part:SetAttribute("Sway", true)
		part:SetAttribute("SwayAmplitude", amplitude)
		part:SetAttribute("SwaySpeed", speed)
		return part
	end
	local function ground(x: number, z: number): Vector3
		return Vector3.new(x, layout:GroundHeight(x, z), z)
	end
	local function onBearing(degrees: number, radius: number): (number, number)
		local a = math.rad(degrees)
		return math.cos(a) * radius, math.sin(a) * radius
	end
	local function creatureRegion(name: string, center: Vector3, size: Vector3, species: string, amount: number, wander: number?)
		local region = prop(decor, name, size, CFrame.new(center), Enum.Material.SmoothPlastic, Color3.new(1, 1, 1))
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

	-- Lagoon reef --------------------------------------------------------------------
	local reef = folder("LagoonReef")
	local function lagoonPoint(minRadius: number, maxRadius: number): Vector3
		local angle = random() * math.pi * 2
		local radius = minRadius + random() * (maxRadius - minRadius)
		local x, z = math.cos(angle) * radius, math.sin(angle) * radius
		return ground(x, z)
	end

	-- One coral head: a random mix of branching, brain, table, fan corals,
	-- tube sponges and anemones around a point on the seabed.
	local function coralHead(parent: Instance, base: Vector3)
		local color = CORAL_COLORS[rng:NextInteger(1, #CORAL_COLORS)]
		local kind = random()
		if kind < 0.3 then
			for _ = 1, rng:NextInteger(4, 7) do -- branching coral
				local height = 1.5 + random() * 3
				local tilt = CFrame.Angles((random() - 0.5) * 1, random() * math.pi * 2, (random() - 0.5) * 1)
				prop(parent, "BranchCoral", Vector3.new(0.4, height, 0.4), CFrame.new(base) * tilt * CFrame.new(0, height / 2, 0), Enum.Material.SmoothPlastic, color)
			end
		elseif kind < 0.52 then -- brain coral
			local size = 2 + random() * 3
			ellipsoid(parent, "BrainCoral", Vector3.new(size, size * 0.65, size), CFrame.new(base + Vector3.new(0, size * 0.2, 0)), Enum.Material.Pebble, color)
		elseif kind < 0.66 then -- table coral
			local width = 4 + random() * 4
			prop(parent, "TableStalk", Vector3.new(0.8, 1.8, 0.8), CFrame.new(base + Vector3.new(0, 0.9, 0)), Enum.Material.SmoothPlastic, color)
			local top = prop(parent, "TableCoral", Vector3.new(0.5, width, width), CFrame.new(base + Vector3.new(0, 1.9, 0)) * CFrame.Angles(0, 0, math.pi / 2), Enum.Material.Pebble, color, Enum.PartType.Cylinder)
			top.CastShadow = true
		elseif kind < 0.8 then -- fan coral
			local width = 2.5 + random() * 3
			sway(prop(parent, "FanCoral", Vector3.new(width, width * 0.9, 0.15), CFrame.new(base + Vector3.new(0, width * 0.45, 0)) * CFrame.Angles(0, random() * math.pi, 0), Enum.Material.Fabric, color), 0.08, 0.8)
		elseif kind < 0.9 then -- tube sponges
			for _ = 1, rng:NextInteger(3, 5) do
				local height = 1.5 + random() * 3
				local at = base + Vector3.new((random() - 0.5) * 2, 0, (random() - 0.5) * 2)
				prop(parent, "TubeSponge", Vector3.new(height, 0.9, 0.9), CFrame.new(at + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, 0, math.pi / 2), Enum.Material.Pebble, Color3.fromRGB(230, 140, 60), Enum.PartType.Cylinder)
			end
		else -- anemone with its fringe of tentacles
			ellipsoid(parent, "AnemoneBase", Vector3.new(1.8, 1, 1.8), CFrame.new(base + Vector3.new(0, 0.3, 0)), Enum.Material.SmoothPlastic, Color3.fromRGB(200, 70, 90))
			for k = 1, 10 do
				local angle = k / 10 * math.pi * 2
				local tentacle = prop(parent, "AnemoneTentacle", Vector3.new(0.2, 1.4, 0.2), CFrame.new(base + Vector3.new(math.cos(angle) * 0.6, 1.2, math.sin(angle) * 0.6)) * CFrame.Angles(math.sin(angle) * 0.5, 0, -math.cos(angle) * 0.5), Enum.Material.Neon, Color3.fromRGB(255, 170, 200))
				tentacle.Transparency = 0.2
			end
		end
	end
	for _ = 1, 150 do
		coralHead(reef, lagoonPoint(76, 176))
	end
	for _ = 1, 40 do -- urchins and starfish on the sand
		local base = lagoonPoint(70, 178)
		if random() < 0.5 then
			ellipsoid(reef, "Urchin", Vector3.new(0.9, 0.7, 0.9), CFrame.new(base + Vector3.new(0, 0.3, 0)), Enum.Material.Pebble, Color3.fromRGB(40, 30, 60))
		else
			local color = random() < 0.5 and Color3.fromRGB(240, 110, 60) or Color3.fromRGB(90, 110, 230)
			local spin = random() * math.pi
			for arm = 1, 5 do
				local angle = spin + arm / 5 * math.pi * 2
				prop(reef, "StarfishArm", Vector3.new(0.35, 0.2, 1.1), CFrame.new(base + Vector3.new(math.cos(angle) * 0.5, 0.1, math.sin(angle) * 0.5)) * CFrame.Angles(0, -angle + math.pi / 2, 0), Enum.Material.Pebble, color)
			end
		end
	end
	for _ = 1, 8 do -- giant clams, each hiding a pearl
		local base = lagoonPoint(90, 170)
		local yaw = random() * math.pi * 2
		ellipsoid(reef, "ClamShell", Vector3.new(3, 1.2, 2.2), CFrame.new(base + Vector3.new(0, 0.5, 0)) * CFrame.Angles(0, yaw, 0.15), Enum.Material.Pebble, Color3.fromRGB(160, 150, 170))
		ellipsoid(reef, "ClamShell", Vector3.new(3, 1.2, 2.2), CFrame.new(base + Vector3.new(0, 1.2, 0)) * CFrame.Angles(0, yaw, -0.35), Enum.Material.Pebble, Color3.fromRGB(150, 140, 165))
		ellipsoid(reef, "ClamMantle", Vector3.new(2.4, 0.4, 1.6), CFrame.new(base + Vector3.new(0, 0.95, 0)) * CFrame.Angles(0, yaw, 0), Enum.Material.Neon, Color3.fromRGB(60, 190, 200)).Transparency = 0.3
	end
	for _ = 1, 30 do -- seagrass meadows
		local center = lagoonPoint(80, 170)
		for _ = 1, 16 do
			local at = ground(center.X + (random() - 0.5) * 12, center.Z + (random() - 0.5) * 12)
			local height = 1.5 + random() * 2.5
			sway(prop(reef, "Seagrass", Vector3.new(0.25, height, 0.08), CFrame.new(at + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, random() * math.pi, (random() - 0.5) * 0.3), Enum.Material.Grass, Color3.fromRGB(80, 150, 70)), 0.18, 1.1)
		end
	end
	for _ = 1, 40 do
		local base = lagoonPoint(80, 176)
		local height = 6 + random() * 9
		sway(prop(reef, "Kelp", Vector3.new(0.5, height, 0.5), CFrame.new(base + Vector3.new(0, height / 2, 0)) * CFrame.Angles((random() - 0.5) * 0.2, random() * math.pi * 2, (random() - 0.5) * 0.2), Enum.Material.Grass, KELP_GREEN), 0.12, 0.6)
	end
	for k = 1, 6 do
		local x, z = onBearing(k * 60 + 20, 128)
		creatureRegion("Creatures_Lagoon" .. k, Vector3.new(x, -10, z), Vector3.new(50, 5, 50), "PoissonRecif,TortueMarine", 8)
	end

	-- Coral gardens on the upper flanks (60-150 m), just below the wall:
	-- coral heads in clusters, with anemone fields, and reef fish over them.
	local flank = folder("FlankGardens")
	local gardens = 0
	for attempt = 1, 400 do
		if gardens >= 55 then
			break
		end
		local bearing = random() * 360
		local x, z = onBearing(bearing, 215 + random() * 90)
		local center = ground(x, z)
		if center.Y < -60 and center.Y > -150 and layout:IsFree(center + Vector3.new(0, 8, 0), 2) then
			gardens += 1
			for _ = 1, rng:NextInteger(4, 8) do
				local at = ground(center.X + (random() - 0.5) * 22, center.Z + (random() - 0.5) * 22)
				coralHead(flank, at)
			end
			if gardens % 11 == 0 then
				-- Reef fish only live above 120 m; deeper gardens get turtles and rays.
				local species = center.Y + 12 > -110 and "PoissonRecif,TortueMarine" or "TortueMarine,RaieManta"
				creatureRegion("Creatures_FlankGarden" .. gardens, center + Vector3.new(0, 12, 0), Vector3.new(40, 10, 40), species, 8, 30)
			end
		end
	end
	-- Anemone fields deeper on the flanks, glowing in the dim light.
	for _ = 1, 30 do
		local x, z = onBearing(random() * 360, 280 + random() * 120)
		local center = ground(x, z)
		if center.Y < -160 and center.Y > -300 and layout:IsFree(center + Vector3.new(0, 6, 0), 2) then
			for _ = 1, rng:NextInteger(6, 12) do
				local at = ground(center.X + (random() - 0.5) * 16, center.Z + (random() - 0.5) * 16)
				local hue = random() < 0.5 and Color3.fromRGB(255, 120, 200) or Color3.fromRGB(120, 255, 200)
				ellipsoid(flank, "AnemoneBase", Vector3.new(1.4, 0.9, 1.4), CFrame.new(at + Vector3.new(0, 0.3, 0)), Enum.Material.SmoothPlastic, Color3.fromRGB(120, 60, 90))
				for k = 1, 8 do
					local angle = k / 8 * math.pi * 2
					local tentacle = sway(prop(flank, "AnemoneTentacle", Vector3.new(0.18, 1.6, 0.18), CFrame.new(at + Vector3.new(math.cos(angle) * 0.45, 1.2, math.sin(angle) * 0.45)) * CFrame.Angles(math.sin(angle) * 0.5, 0, -math.cos(angle) * 0.5), Enum.Material.Neon, hue), 0.25, 0.9)
					tentacle.Transparency = 0.25
				end
			end
		end
	end

	-- The reef wall -------------------------------------------------------------------
	-- A spot on the cliff: march outward along a bearing until the seabed
	-- drops below the target depth; the growth sticks out of the face there.
	local wall = folder("ReefWall")
	for _ = 1, 170 do
		local bearing = random() * 360
		local targetY = -55 - random() * 55
		local a = math.rad(bearing)
		local dirX, dirZ = math.cos(a), math.sin(a)
		for radius = 180, 320, 2 do
			local x, z = dirX * radius, dirZ * radius
			if layout:GroundHeight(x, z) < targetY then
				local face = Vector3.new(x - dirX * 2.5, targetY, z - dirZ * 2.5)
				local outward = CFrame.lookAt(face, face + Vector3.new(dirX, 0, dirZ))
				local color = CORAL_COLORS[rng:NextInteger(1, #CORAL_COLORS)]
				if random() < 0.55 then
					local width = 4 + random() * 5
					sway(prop(wall, "SeaFan", Vector3.new(width, width * 0.85, 0.2), outward * CFrame.Angles(0.3, 0, 0) * CFrame.new(0, width * 0.3, -1.5), Enum.Material.Fabric, color), 0.06, 0.7)
				else
					local length = 2.5 + random() * 3
					prop(wall, "BarrelSponge", Vector3.new(length, 2.4, 2.4), outward * CFrame.new(0, 0, -length / 2) * CFrame.Angles(0, math.pi / 2, 0) * CFrame.Angles(0, 0, 0.5), Enum.Material.Pebble, Color3.fromRGB(170, 90, 70), Enum.PartType.Cylinder)
				end
				break
			end
		end
	end

	-- Kelp forest on the western flank ---------------------------------------------------
	local kelpForest = folder("KelpForest")
	local planted = 0
	for _ = 1, 400 do
		if planted >= 130 then
			break
		end
		local x, z = onBearing(235 + random() * 60, 215 + random() * 110)
		local base = ground(x, z)
		if base.Y < -85 and base.Y > -165 then
			planted += 1
			local height = 24 + random() * 26
			local color = random() < 0.7 and KELP_GREEN or KELP_GOLD
			local stalk = sway(prop(kelpForest, "GiantKelp", Vector3.new(0.9, height, 0.9), CFrame.new(base + Vector3.new(0, height / 2 - 0.5, 0)) * CFrame.Angles((random() - 0.5) * 0.12, random() * math.pi * 2, (random() - 0.5) * 0.12), Enum.Material.Grass, color), 0.025, 0.3 + random() * 0.15)
			stalk.CastShadow = false
			for leaf = 1, 4 do
				local along = (leaf / 5) * height
				prop(kelpForest, "KelpBlade", Vector3.new(0.12, 5, 2), stalk.CFrame * CFrame.new(0, along - height / 2, 0) * CFrame.Angles(0, leaf * 1.9, 0.5) * CFrame.new(0, 2, 1), Enum.Material.Grass, color)
			end
		end
	end
	do
		local x, z = onBearing(265, 270)
		creatureRegion("Creatures_KelpForest", Vector3.new(x, -110, z), Vector3.new(120, 30, 120), "TortueMarine,RaieManta", 6, 70)
	end
	-- A second, golden kelp forest on the eastern flank.
	planted = 0
	for _ = 1, 400 do
		if planted >= 100 then
			break
		end
		local x, z = onBearing(95 + random() * 40, 215 + random() * 100)
		local base = ground(x, z)
		if base.Y < -80 and base.Y > -170 and layout:IsFree(base + Vector3.new(0, 10, 0), 3) then
			planted += 1
			local height = 20 + random() * 24
			local stalk = sway(prop(kelpForest, "GiantKelp", Vector3.new(0.9, height, 0.9), CFrame.new(base + Vector3.new(0, height / 2 - 0.5, 0)) * CFrame.Angles((random() - 0.5) * 0.12, random() * math.pi * 2, (random() - 0.5) * 0.12), Enum.Material.Grass, KELP_GOLD), 0.025, 0.3 + random() * 0.15)
			stalk.CastShadow = false
			for leaf = 1, 3 do
				prop(kelpForest, "KelpBlade", Vector3.new(0.12, 5, 2), stalk.CFrame * CFrame.new(0, (leaf / 4) * height - height / 2, 0) * CFrame.Angles(0, leaf * 2.1, 0.5) * CFrame.new(0, 2, 1), Enum.Material.Grass, KELP_GOLD)
			end
		end
	end
	do
		local x, z = onBearing(115, 265)
		creatureRegion("Creatures_KelpForestEast", Vector3.new(x, -105, z), Vector3.new(110, 30, 110), "TortueMarine,RaieManta,PoissonRecif", 8, 60)
	end

	-- Abyssal rift ---------------------------------------------------------------------------
	local rift = layout:GetAnchor("RiftFrame")
	local abyss = folder("Abyss")
	local terrain = Workspace.Terrain
	if rift then
		for k = -2, 2 do
			local at = rift.center + rift.along * (k * 60 + (random() - 0.5) * 20) + rift.across * ((random() - 0.5) * 16)
			local base = ground(at.X, at.Z)
			-- Glowing cracks in the rock around the vent.
			terrain:FillBall(base - Vector3.new(0, 2, 0), 7 + random() * 3, Enum.Material.CrackedLava)
			local height = 14 + random() * 12
			local y = base.Y - 1
			for segment = 1, 4 do
				local segmentHeight = height / 4
				local width = 6 - segment * 1.1
				prop(abyss, "Chimney", Vector3.new(width, segmentHeight + 0.4, width), CFrame.new(base.X + (random() - 0.5), y + segmentHeight / 2, base.Z + (random() - 0.5)) * CFrame.Angles(0, random() * 3, 0), Enum.Material.Basalt, Color3.fromRGB(34, 30, 34))
				y += segmentHeight
			end
			local throat = prop(abyss, "VentThroat", Vector3.new(1.6, 0.6, 1.6), CFrame.new(base.X, y, base.Z), Enum.Material.Neon, Color3.fromRGB(255, 110, 40))
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
			-- Tube worms: white stalks, blood-red plumes.
			for _ = 1, 20 do
				local angle = random() * math.pi * 2
				local distance = 5 + random() * 8
				local foot = ground(base.X + math.cos(angle) * distance, base.Z + math.sin(angle) * distance)
				local wormHeight = 2 + random() * 4
				prop(abyss, "TubeWorm", Vector3.new(0.35, wormHeight, 0.35), CFrame.new(foot + Vector3.new(0, wormHeight / 2, 0)) * CFrame.Angles((random() - 0.5) * 0.3, 0, (random() - 0.5) * 0.3), Enum.Material.SmoothPlastic, Color3.fromRGB(230, 226, 214))
				ellipsoid(abyss, "WormPlume", Vector3.new(0.8, 0.6, 0.8), CFrame.new(foot + Vector3.new(0, wormHeight + 0.2, 0)), Enum.Material.Neon, Color3.fromRGB(220, 40, 50))
			end
		end
		creatureRegion("Creatures_Rift", rift.center + Vector3.new(0, 40, 0), Vector3.new(200, 30, 60), "MeduseLumineuse", 6, 60)
	end

	-- Abyssal plain -----------------------------------------------------------------------------
	-- Sea lilies (crinoids): a slim stalk crowned with feathery arms.
	for _ = 1, 70 do
		local angle = random() * math.pi * 2
		local radius = 500 + random() * 420
		local base = ground(math.cos(angle) * radius, math.sin(angle) * radius)
		if base.Y < -440 and math.abs(base.X) < 980 and math.abs(base.Z) < 980 then
			local height = 4 + random() * 5
			local color = random() < 0.5 and Color3.fromRGB(230, 180, 90) or Color3.fromRGB(200, 90, 120)
			prop(abyss, "CrinoidStalk", Vector3.new(0.3, height, 0.3), CFrame.new(base + Vector3.new(0, height / 2, 0)), Enum.Material.SmoothPlastic, Color3.fromRGB(190, 170, 150))
			for arm = 1, 6 do
				local a = arm / 6 * math.pi * 2
				sway(prop(abyss, "CrinoidArm", Vector3.new(0.25, 2.4, 0.5), CFrame.new(base + Vector3.new(math.cos(a) * 0.7, height + 0.9, math.sin(a) * 0.7)) * CFrame.Angles(math.sin(a) * 0.7, 0, -math.cos(a) * 0.7), Enum.Material.Fabric, color), 0.15, 0.4)
			end
		end
	end
	for _ = 1, 110 do
		local angle = random() * math.pi * 2
		local radius = 480 + random() * 450
		local base = ground(math.cos(angle) * radius, math.sin(angle) * radius)
		if base.Y < -440 and math.abs(base.X) < 980 and math.abs(base.Z) < 980 then
			local kind = random()
			if kind < 0.4 then -- sea pen: a thin stalk with a glowing feather
				local height = 3 + random() * 4
				prop(abyss, "SeaPenStalk", Vector3.new(0.25, height, 0.25), CFrame.new(base + Vector3.new(0, height / 2, 0)), Enum.Material.SmoothPlastic, Color3.fromRGB(200, 180, 200))
				sway(ellipsoid(abyss, "SeaPenFeather", Vector3.new(0.4, height * 0.6, 1.4), CFrame.new(base + Vector3.new(0, height * 0.8, 0)), Enum.Material.Neon, Color3.fromRGB(150, 110, 255)), 0.1, 0.5)
			elseif kind < 0.7 then -- glass sponge
				local height = 5 + random() * 8
				local sponge = prop(abyss, "GlassSponge", Vector3.new(height, 2.4, 2.4), CFrame.new(base + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, 0, math.pi / 2), Enum.Material.Glass, Color3.fromRGB(220, 235, 240), Enum.PartType.Cylinder)
				sponge.Transparency = 0.4
			else -- a glowing node
				local color = random() < 0.5 and Color3.fromRGB(90, 220, 255) or Color3.fromRGB(150, 110, 255)
				local node = prop(abyss, "GlowNode", Vector3.new(1.2, 1.2, 1.2), CFrame.new(base + Vector3.new(0, 0.6, 0)), Enum.Material.Neon, color, Enum.PartType.Ball)
				local light = Instance.new("PointLight")
				light.Color = color
				light.Range = 22
				light.Brightness = 1.1
				light.Parent = node
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

	-- Keep the cave mouths clear: decor is planted on the heightfield, which
	-- knows nothing of the holes, so anything that landed in (or over) a
	-- porch or its cleft would float there and hide the way in.
	-- Same for the wrecks' volumes (the Sirène, the graveyard, the liner)
	-- and the hub's buildings: no coral growing through a hull or a jetty.
	local caves = layout:GetAnchor("Caves")
	local wreckBoxes = {}
	for _, volume in ipairs(layout.reserved) do
		if volume.kind == "box" and (volume.name == "Shipwreck" or volume.name:match("^Graveyard_") or volume.name:match("^Liner_") or volume.name:match("^Hub_")) then
			table.insert(wreckBoxes, volume)
		end
	end
	local network = layout:GetAnchor("Network")
	local function blocked(position: Vector3): boolean
		for _, anchor in ipairs({ caves, network }) do
			for _, entrance in ipairs(anchor and anchor.entrances or {}) do
				if (position - entrance.mouth).Magnitude < entrance.clearRadius then
					return true
				end
			end
		end
		for _, volume in ipairs(wreckBoxes) do
			local l = volume.cframe:PointToObjectSpace(position)
			if math.abs(l.X) < volume.half.X and math.abs(l.Y) < volume.half.Y and math.abs(l.Z) < volume.half.Z then
				return true
			end
		end
		return false
	end
	for _, part in ipairs(decor:GetDescendants()) do
		if part:IsA("BasePart") and part.Name:sub(1, 9) ~= "Creatures" and part.Parent and blocked(part.Position) then
			part:Destroy()
			count -= 1
		end
	end

	print(string.format("[BiomeDecor] %d decor parts", count))
end


return BiomeDecor
