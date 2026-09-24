-- "Les Grottes de l'Éperon": a cave network carved into the rocky spur on
-- the seamount's north-west flank (Seabed.lua raises the spur). One route
-- from the reef down into the dark, with a side exit:
--
--   Trou Bleu (~35 m): a blue hole opening right at the edge of the
--     lagoon, visible from the beach, dropping into the Salle des Cristaux
--   Porche du Récif (~118 m, north face)
--     -> Salle des Cristaux (~128 m): a geode of glowing crystals
--     -> La Cathédrale (~185 m): a vast hall with rock pillars, lit by a
--        shaft of daylight falling through a chimney from the ridge, an
--        ancient altar at its heart
--        -> Fenêtre (~190 m, south face): a side exit
--     -> Grotte aux Méduses (~312 m): a bioluminescent pool where the
--        glowing jellyfish drift
--     -> Sortie des Abysses (~325 m, south face), toward the deep.
--
-- Shapes are Terrain: tunnels are chains of overlapping water spheres
-- along smooth splines (radius wobbling with noise), chambers are a dome
-- plus lower satellite bubbles, with a flat sand floor filled into the
-- bowl. Every prop is placed on a surface computed from those exact
-- shapes (the sand floor, the dome's ceiling, the tunnel's roof), so
-- nothing floats or hangs in rock. Coordinates are in the spur's frame:
-- (along the spur, across it, depth).

local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")

local Noise = require(script.Parent.Noise)

local Caves = {}

local CHAMBERS = {
	{ id = "Cristaux", name = "Salle des Cristaux", along = 270, across = -5, y = -128, radius = 26 },
	{ id = "Cathedrale", name = "La Cathédrale", along = 365, across = 5, y = -185, radius = 42 },
	{ id = "Meduses", name = "Grotte aux Méduses", along = 470, across = -10, y = -312, radius = 34 },
}

-- Control points (along, across, y) and radius; the first/last points of
-- entry tunnels lie outside the rock, in open water.
local TUNNELS = {
	{ id = "TrouBleu", radius = 13, points = { { 204, 0, -28 }, { 207, 0, -60 }, { 222, -4, -94 }, { 250, -5, -118 }, { 270, -5, -128 } } },
	{ id = "Porche", radius = 14, points = { { 245, 100, -116 }, { 250, 60, -120 }, { 262, 25, -126 }, { 270, -5, -128 } } },
	{ id = "CristauxCathedrale", radius = 9, points = { { 270, -5, -128 }, { 300, 20, -148 }, { 335, -15, -170 }, { 365, 5, -185 } } },
	{ id = "Fenetre", radius = 12, points = { { 365, 5, -188 }, { 378, -40, -190 }, { 384, -80, -192 }, { 388, -112, -193 } } },
	{ id = "CathedraleMeduses", radius = 9, points = { { 365, 5, -190 }, { 400, 25, -222 }, { 430, -20, -265 }, { 455, 10, -295 }, { 470, -10, -312 } } },
	{ id = "SortieAbysses", radius = 14, points = { { 470, -10, -314 }, { 488, -60, -320 }, { 498, -110, -324 }, { 503, -145, -326 } } },
}
local ENTRANCES = {
	{ id = "TrouBleu", name = "Trou Bleu", tunnel = "TrouBleu", at = 1 },
	{ id = "Porche", name = "Porche du Récif", tunnel = "Porche", at = 1 },
	{ id = "Fenetre", name = "Fenêtre", tunnel = "Fenetre", at = 4 },
	{ id = "SortieAbysses", name = "Sortie des Abysses", tunnel = "SortieAbysses", at = 4 },
}

local CRYSTAL_COLORS = { Color3.fromRGB(90, 220, 255), Color3.fromRGB(170, 120, 255), Color3.fromRGB(80, 255, 190) }
local ROCK_COLOR = Color3.fromRGB(70, 74, 84)
local STONE_COLOR = Color3.fromRGB(150, 146, 132)
local GLOW_BLUE = Color3.fromRGB(120, 230, 255)

-- Geometry helpers -------------------------------------------------------------------

local function catmullRom(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: number): Vector3
	local t2, t3 = t * t, t * t * t
	return 0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3)
end

-- Evenly spaced samples along a spline through `points`.
local function sampleSpline(points: { Vector3 }, step: number): { Vector3 }
	local samples = {}
	for i = 1, #points - 1 do
		local p0 = points[math.max(i - 1, 1)]
		local p1, p2 = points[i], points[i + 1]
		local p3 = points[math.min(i + 2, #points)]
		local count = math.max(2, math.ceil((p2 - p1).Magnitude / step))
		for k = 0, count - 1 do
			table.insert(samples, catmullRom(p0, p1, p2, p3, k / count))
		end
	end
	table.insert(samples, points[#points])
	return samples
end

local function part(parent: Instance, name: string, size: Vector3, cframe: CFrame, material: Enum.Material, color: Color3, collide: boolean?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = collide == true
	p.CanQuery = collide == true
	p.CanTouch = false
	p.CastShadow = false
	p.Size = size
	p.CFrame = cframe
	p.Material = material
	p.Color = color
	p.Parent = parent
	return p
end

local function light(parent: BasePart, color: Color3, range: number, brightness: number)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Parent = parent
	return l
end

local function spawnRegion(parent: Instance, name: string, center: Vector3, size: Vector3, kind: string, attributes: { [string]: any })
	local region = part(parent, name, size, CFrame.new(center), Enum.Material.SmoothPlastic, Color3.new(1, 1, 1))
	region.Transparency = 1
	region:SetAttribute("RegionKind", kind)
	region:SetAttribute("RegionEnabled", true)
	for key, value in pairs(attributes) do
		region:SetAttribute(key, value)
	end
	CollectionService:AddTag(region, "SpawnRegion")
	return region
end

-- A tapering spike from three stacked, turned blocks (stalactite when
-- `direction` is -1, stalagmite when +1).
local function spike(parent: Instance, base: Vector3, direction: number, length: number, width: number)
	local y = base.Y
	for segment = 1, 3 do
		local segmentLength = length / 3
		local segmentWidth = width * (1 - (segment - 1) * 0.3)
		part(parent, direction < 0 and "Stalactite" or "Stalagmite", Vector3.new(segmentWidth, segmentLength, segmentWidth),
			CFrame.new(base.X, y + direction * segmentLength / 2, base.Z) * CFrame.Angles(0, math.pi / 4 * segment, 0), Enum.Material.Rock, ROCK_COLOR)
		y += direction * segmentLength * 0.9
	end
end

-- Build ------------------------------------------------------------------------------------

function Caves.Build(layout)
	local terrain = Workspace.Terrain
	local spur = layout:GetAnchor("CaveSpur")
	assert(spur, "Caves needs the Seabed's spur")
	local rng = layout:Random("Caves")
	local noise = Noise.new(layout.seed + 91)

	local function world(along: number, across: number, y: number): Vector3
		local flat = spur.along * along + spur.across * across
		return Vector3.new(flat.X, y, flat.Z)
	end

	local worldFolder = Workspace:FindFirstChild("World") or Instance.new("Folder")
	worldFolder.Name = "World"
	worldFolder.Parent = Workspace
	local underwater = worldFolder:FindFirstChild("Underwater") or Instance.new("Folder")
	underwater.Name = "Underwater"
	underwater.Parent = worldFolder
	local old = underwater:FindFirstChild("Caves")
	if old then
		old:Destroy()
	end
	local root = Instance.new("Folder")
	root.Name = "Caves"
	root.Parent = underwater
	local decor = Instance.new("Folder")
	decor.Name = "Decor"
	decor.Parent = root
	local markers = Instance.new("Folder")
	markers.Name = "EntryPoints"
	markers.Parent = root
	local regions = Instance.new("Folder")
	regions.Name = "SpawnRegions"
	regions.Parent = root

	-- 1. Chambers: a dome and a ring of lower bubbles, then a sand floor
	-- filling the bowl flat. Every carve sphere is kept for the ceiling.
	local chambers = {}
	for _, spec in ipairs(CHAMBERS) do
		local center = world(spec.along, spec.across, spec.y)
		local r = spec.radius
		local balls = { { center = center, radius = r } }
		for k = 1, 6 do
			local angle = k / 6 * math.pi * 2 + rng:NextNumber() * 0.5
			local offset = Vector3.new(math.cos(angle), 0, math.sin(angle)) * r * (0.45 + rng:NextNumber() * 0.2)
			table.insert(balls, { center = center + offset - Vector3.new(0, r * (0.1 + rng:NextNumber() * 0.15), 0), radius = r * (0.55 + rng:NextNumber() * 0.15) })
		end
		for _, ball in ipairs(balls) do
			terrain:FillBall(ball.center, ball.radius, Enum.Material.Water)
		end
		local floorY = center.Y - r * 0.55
		terrain:FillCylinder(CFrame.new(center.X, floorY - 7, center.Z), 14, r * 1.05, Enum.Material.Sand)
		table.insert(chambers, { spec = spec, center = center, radius = r, balls = balls, floorY = floorY })
	end
	local chamberById = {}
	for _, chamber in ipairs(chambers) do
		chamberById[chamber.spec.id] = chamber
	end

	-- 2. Tunnels.
	local tunnels = {}
	for _, spec in ipairs(TUNNELS) do
		local points = {}
		for _, p in ipairs(spec.points) do
			table.insert(points, world(p[1], p[2], p[3]))
		end
		local samples = sampleSpline(points, 3)
		local radii = {}
		for index, sample in ipairs(samples) do
			local radius = spec.radius * (1 + 0.18 * noise:Get(index * 0.21, #spec.id))
			radii[index] = radius
			terrain:FillBall(sample, radius, Enum.Material.Water)
		end
		tunnels[spec.id] = { spec = spec, points = points, samples = samples, radii = radii }
	end

	-- 2b. Entrances. A tube simply running into a steep face leaves a hole
	-- tucked under an overhang that nobody sees from above. So each mouth
	-- sits where the tube really meets the rock (its axis passes under the
	-- seabed surface), opens as a flared porch much wider than the tube,
	-- and, on a sideways entrance, a cleft is cut up the face above it: from
	-- the reef above, a diver sees a dark gash leading down into the hole.
	local mouths = {}
	for _, entrance in ipairs(ENTRANCES) do
		local tunnel = tunnels[entrance.tunnel]
		local samples, radius = tunnel.samples, tunnel.spec.radius
		local first, last, step = 1, #samples, 1
		if entrance.at ~= 1 then
			first, last, step = #samples, 1, -1
		end
		local rimIndex = first
		for i = first, last, step do
			if layout:GroundHeight(samples[i].X, samples[i].Z) > samples[i].Y then
				rimIndex = i
				break
			end
		end
		local rim = samples[rimIndex]
		local ahead = samples[math.clamp(rimIndex + step * 3, 1, #samples)]
		local inward = (ahead - rim).Unit
		-- The porch: a funnel of big bubbles narrowing into the tube.
		for k, factor in ipairs({ 1.9, 1.7, 1.45, 1.25, 1.1 }) do
			terrain:FillBall(rim + inward * ((k - 2) * 5), radius * factor, Enum.Material.Water)
		end
		-- The cleft up the face (not on a vertical shaft, already open above).
		if inward.Y > -0.6 then
			local flat = Vector3.new(inward.X, 0, inward.Z).Unit
			for k = 1, 14 do
				local center = rim + flat * (k * 2.5) + Vector3.new(0, k * 5, 0)
				terrain:FillBall(center, radius * (0.95 - k * 0.03), Enum.Material.Water)
				if center.Y > layout:GroundHeight(center.X, center.Z) + radius * 0.5 then
					break
				end
			end
		end
		mouths[entrance.id] = { rim = rim, inward = inward }
	end

	-- 3. Cathédrale: rock pillars from floor to ceiling (with flared foot
	-- and capital), and the chimney letting daylight in from the ridge.
	local cathedral = chamberById.Cathedrale
	-- Pillars never stand in a tunnel's mouth (the stretch of tube near
	-- the hall's wall); deeper inside the hall a pillar is just something
	-- to swim around.
	local function blocksTunnel(base: Vector3, reach: number): boolean
		for _, tunnel in pairs(tunnels) do
			for index, sample in ipairs(tunnel.samples) do
				local fromCenter = (sample - cathedral.center).Magnitude
				if fromCenter > cathedral.radius * 0.7 and fromCenter < cathedral.radius * 1.15 then
					local dx, dz = sample.X - base.X, sample.Z - base.Z
					if math.sqrt(dx * dx + dz * dz) < reach + tunnel.radii[index] then
						return true
					end
				end
			end
		end
		return false
	end
	local pillars = 0
	for k = 1, 16 do
		if pillars >= 5 then
			break
		end
		local angle = k / 16 * math.pi * 2 * 3 + 0.4
		local base = cathedral.center + Vector3.new(math.cos(angle), 0, math.sin(angle)) * cathedral.radius * 0.58
		local pillarRadius = 4.5 + rng:NextNumber() * 2
		if blocksTunnel(base, pillarRadius * 1.5) then
			continue
		end
		pillars += 1
		local bottom, top = cathedral.floorY - 4, cathedral.center.Y + cathedral.radius
		terrain:FillCylinder(CFrame.new(base.X, (bottom + top) / 2, base.Z), top - bottom, pillarRadius, Enum.Material.Rock)
		terrain:FillBall(Vector3.new(base.X, cathedral.floorY + 1, base.Z), pillarRadius * 1.5, Enum.Material.Rock)
		terrain:FillBall(Vector3.new(base.X, cathedral.center.Y + cathedral.radius * 0.72, base.Z), pillarRadius * 1.5, Enum.Material.Rock)
	end
	local shaftTop = cathedral.center + Vector3.new(0, 95, 0)
	for y = cathedral.center.Y + cathedral.radius * 0.6, shaftTop.Y, 3 do
		terrain:FillBall(Vector3.new(cathedral.center.X, y, cathedral.center.Z), 8 + 1.5 * noise:Get(y * 0.1, 4.2), Enum.Material.Water)
	end
	-- The daylight itself: a faint vertical glow column (a Cylinder's axis
	-- is its X, turned upright) with a spotlight shining down from its top.
	local beamTop, beamBottom = cathedral.center.Y + cathedral.radius + 25, cathedral.floorY
	local beam = part(decor, "DaylightShaft", Vector3.new(beamTop - beamBottom, 12, 12),
		CFrame.new(cathedral.center.X, (beamTop + beamBottom) / 2, cathedral.center.Z) * CFrame.Angles(0, 0, math.pi / 2), Enum.Material.Neon, Color3.fromRGB(220, 240, 255))
	beam.Shape = Enum.PartType.Cylinder
	beam.Transparency = 0.92
	local sun = Instance.new("SpotLight")
	sun.Face = Enum.NormalId.Left -- the column's local -X points down once turned upright
	sun.Angle = 40
	sun.Range = 60
	sun.Brightness = 3
	sun.Color = Color3.fromRGB(215, 235, 255)
	sun.Parent = beam
	local motes = Instance.new("ParticleEmitter")
	motes.Rate = 6
	motes.Lifetime = NumberRange.new(6, 10)
	motes.Speed = NumberRange.new(0.3, 1)
	motes.SpreadAngle = Vector2.new(20, 20)
	motes.LightEmission = 0.8
	motes.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.5, 0.3), NumberSequenceKeypoint.new(1, 0) })
	motes.Transparency = NumberSequence.new(0.4)
	motes.Parent = beam

	-- Surfaces for props ------------------------------------------------------------------

	local function ceilingAbove(chamber, x: number, z: number): number?
		local best = nil
		for _, ball in ipairs(chamber.balls) do
			local dx, dz = x - ball.center.X, z - ball.center.Z
			local d2 = dx * dx + dz * dz
			if d2 < ball.radius * ball.radius then
				local top = ball.center.Y + math.sqrt(ball.radius * ball.radius - d2)
				best = best and math.max(best, top) or top
			end
		end
		return best
	end

	local function floorPoint(chamber, spread: number): Vector3
		local angle = rng:NextNumber() * math.pi * 2
		local d = chamber.radius * spread * math.sqrt(rng:NextNumber())
		return Vector3.new(chamber.center.X + math.cos(angle) * d, chamber.floorY - 0.5, chamber.center.Z + math.sin(angle) * d)
	end

	local function crystalCluster(base: Vector3, color: Color3, scale: number)
		for shard = 1, rng:NextInteger(3, 6) do
			local height = (3 + rng:NextNumber() * 7) * scale
			local tilt = CFrame.Angles((rng:NextNumber() - 0.5) * 1.0, rng:NextNumber() * math.pi * 2, (rng:NextNumber() - 0.5) * 1.0)
			local crystal = part(decor, "Crystal", Vector3.new(0.9, height, 0.9) * math.max(scale, 0.8),
				CFrame.new(base) * tilt * CFrame.new(0, height / 2, 0) * CFrame.Angles(0, math.pi / 4, 0), Enum.Material.Neon, color)
			crystal.Transparency = 0.12
			if shard == 1 then
				light(crystal, color, 16, 1.2)
			end
		end
	end

	local function fungusPatch(center: Vector3, spread: number?)
		local width = (spread or 3) * 2
		for _ = 1, rng:NextInteger(3, 6) do
			local base = center + Vector3.new((rng:NextNumber() - 0.5) * width, 0, (rng:NextNumber() - 0.5) * width)
			local stalk = 0.8 + rng:NextNumber() * 1.6
			part(decor, "FungusStalk", Vector3.new(0.35, stalk, 0.35), CFrame.new(base + Vector3.new(0, stalk / 2, 0)), Enum.Material.SmoothPlastic, Color3.fromRGB(205, 215, 205))
			local cap = 0.9 + rng:NextNumber() * 1.3
			part(decor, "FungusCap", Vector3.new(cap, cap * 0.45, cap), CFrame.new(base + Vector3.new(0, stalk, 0)), Enum.Material.Neon, Color3.fromRGB(120, 255, 210)).Shape = Enum.PartType.Ball
		end
	end

	local function hangFromCeiling(chamber, count: number)
		for _ = 1, count do
			local p = floorPoint(chamber, 0.75)
			local ceiling = ceilingAbove(chamber, p.X, p.Z)
			if ceiling and ceiling - chamber.floorY > 12 then
				spike(decor, Vector3.new(p.X, ceiling + 1.5, p.Z), -1, math.min(4 + rng:NextNumber() * 10, (ceiling - chamber.floorY) * 0.4), 1.4 + rng:NextNumber() * 1.8)
			end
		end
	end

	-- 4. Salle des Cristaux: a geode.
	local crystals = chamberById.Cristaux
	for _ = 1, 16 do
		crystalCluster(floorPoint(crystals, 0.85), CRYSTAL_COLORS[rng:NextInteger(1, #CRYSTAL_COLORS)], 0.8 + rng:NextNumber() * 0.9)
	end
	for _ = 1, 6 do
		spike(decor, floorPoint(crystals, 0.8), 1, 3 + rng:NextNumber() * 5, 1.6 + rng:NextNumber())
	end
	hangFromCeiling(crystals, 14)

	-- 5. La Cathédrale: fungi, spikes, and the altar under the daylight.
	for _ = 1, 8 do
		fungusPatch(floorPoint(cathedral, 0.85))
	end
	hangFromCeiling(cathedral, 22)
	local altarBase = Vector3.new(cathedral.center.X, cathedral.floorY, cathedral.center.Z)
	for step = 1, 3 do
		local size = 22 - step * 5
		part(decor, "AltarStep", Vector3.new(size, 1.4, size), CFrame.new(altarBase + Vector3.new(0, step * 1.4 - 0.7, 0)) * CFrame.Angles(0, math.rad(12), 0), Enum.Material.Slate, STONE_COLOR, true)
	end
	part(decor, "AltarPedestal", Vector3.new(3, 4, 3), CFrame.new(altarBase + Vector3.new(0, 4.2 + 2, 0)), Enum.Material.Marble, Color3.fromRGB(200, 196, 180), true)
	local idol = part(decor, "Idol", Vector3.new(1.6, 2.6, 1.6), CFrame.new(altarBase + Vector3.new(0, 8.2 + 1.3, 0)), Enum.Material.Neon, Color3.fromRGB(255, 200, 80))
	light(idol, Color3.fromRGB(255, 200, 110), 22, 1.4)
	for k = 1, 4 do
		local angle = k / 4 * math.pi * 2 + 0.2
		local position = altarBase + Vector3.new(math.cos(angle) * 16, 0, math.sin(angle) * 16)
		local height = 9 + rng:NextNumber() * 6
		local broken = k % 2 == 0
		local column = part(decor, "Column", Vector3.new(broken and height * 0.5 or height, 2.4, 2.4),
			CFrame.new(position + Vector3.new(0, (broken and height * 0.5 or height) / 2, 0)) * CFrame.Angles(0, 0, math.pi / 2), Enum.Material.Marble, STONE_COLOR, true)
		column.Shape = Enum.PartType.Cylinder
	end

	-- 6. Grotte aux Méduses: a glowing pool.
	local jellies = chamberById.Meduses
	for _ = 1, 14 do
		local p = floorPoint(jellies, 0.8)
		local pad = part(decor, "GlowAlgae", Vector3.new(0.4, 3 + rng:NextNumber() * 4, 3 + rng:NextNumber() * 4), CFrame.new(p + Vector3.new(0, 0.3, 0)) * CFrame.Angles(0, 0, math.pi / 2), Enum.Material.Neon, GLOW_BLUE)
		pad.Shape = Enum.PartType.Cylinder
		pad.Transparency = 0.35
	end
	for _ = 1, 5 do
		fungusPatch(floorPoint(jellies, 0.8))
	end
	hangFromCeiling(jellies, 12)
	light(part(decor, "PoolGlow", Vector3.new(1, 1, 1), CFrame.new(jellies.center.X, jellies.floorY + 3, jellies.center.Z), Enum.Material.Neon, GLOW_BLUE), GLOW_BLUE, 40, 1.2).Parent.Transparency = 1

	-- 7. Tunnels: glow-worms on the roof, fungi on the floor, now and then.
	-- (Only where the tube is its own space: inside a chamber, the floor
	-- and roof are the chamber's, far from the tube's.)
	local function insideChamber(point: Vector3): boolean
		for _, chamber in ipairs(chambers) do
			if (point - chamber.center).Magnitude < chamber.radius * 1.2 + 4 then
				return true
			end
		end
		return false
	end
	for _, tunnel in pairs(tunnels) do
		for index = 4, #tunnel.samples - 3, 5 do
			local sample, radius = tunnel.samples[index], tunnel.radii[index]
			-- ...and not near a mouth, where the tube opens onto the cliff.
			if insideChamber(sample) or layout:GroundHeight(sample.X, sample.Z) < sample.Y + radius + 8 then
				continue
			end
			-- On a sloping tube the roof/floor straight above/below the axis is
			-- further than the radius: radius / (horizontal part of the tangent).
			local direction = (tunnel.samples[index + 1] - tunnel.samples[index - 1]).Unit
			local vertical = radius / math.max(math.sqrt(direction.X * direction.X + direction.Z * direction.Z), 0.4)
			local worm = part(decor, "GlowWorm", Vector3.new(0.3, 0.3, 0.3), CFrame.new(sample + Vector3.new(0, vertical - 1.4, 0)), Enum.Material.Neon, Color3.fromRGB(150, 240, 255))
			worm.Shape = Enum.PartType.Ball
			if index % 15 == 4 then
				fungusPatch(sample - Vector3.new(0, vertical + 0.6, 0), 1.5)
			end
		end
	end

	-- 8. Entrances: a marker and a faint ring of glowing algae so a diver
	-- can find the way in (and back out).
	local entrances = {}
	for _, entrance in ipairs(ENTRANCES) do
		local tunnel = tunnels[entrance.tunnel]
		local mouth, inward = mouths[entrance.id].rim, mouths[entrance.id].inward
		local marker = part(markers, "EntryPoint_" .. entrance.id, Vector3.new(1, 1, 1), CFrame.new(mouth), Enum.Material.SmoothPlastic, Color3.new(1, 1, 1))
		marker.Transparency = 1
		marker:SetAttribute("DisplayName", entrance.name)
		local glow = part(decor, "EntranceGlow", Vector3.new(0.6, 0.6, 0.6), CFrame.new(mouth + inward * 12), Enum.Material.Neon, GLOW_BLUE)
		glow.Transparency = 1
		light(glow, GLOW_BLUE, 60, 2.2)
		-- A ring of glowing algae around the mouth: a cave entrance reads
		-- from far away in the blue, not only once you bump into it.
		local ringFrame = CFrame.lookAt(mouth, mouth + inward * 10)
		local ringRadius = tunnel.spec.radius * 1.3
		for k = 1, 20 do
			local angle = k / 20 * math.pi * 2
			local bead = part(decor, "EntranceRing", Vector3.new(1.6, 1.6, 1.6), ringFrame * CFrame.new(math.cos(angle) * ringRadius, math.sin(angle) * ringRadius, 0), Enum.Material.Neon, GLOW_BLUE)
			bead.Shape = Enum.PartType.Ball
		end
		-- And a floating sign, readable from a distance.
		local sign = Instance.new("BillboardGui")
		sign.Name = "EntranceSign"
		sign.Size = UDim2.new(0, 240, 0, 44)
		sign.StudsOffset = Vector3.new(0, tunnel.spec.radius + 6, 0)
		sign.MaxDistance = 320
		sign.LightInfluence = 0
		local label = Instance.new("TextLabel")
		label.Size = UDim2.new(1, 0, 1, 0)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamBold
		label.TextScaled = true
		label.TextColor3 = Color3.fromRGB(170, 240, 255)
		label.TextStrokeTransparency = 0.3
		label.Text = "⛰ " .. entrance.name
		label.Parent = sign
		sign.Parent = marker
		table.insert(entrances, { id = entrance.id, name = entrance.name, mouth = mouth, inward = inward })
	end

	-- 9. Gameplay: loot in every chamber, life where it belongs. Cave
	-- regions are flagged underground so creatures skip the seabed clamp.
	spawnRegion(regions, "Loot_Cristaux", crystals.center - Vector3.new(0, crystals.radius * 0.25, 0), Vector3.new(1, 0.4, 1) * crystals.radius, "Treasure", { RegionCount = 4 })
	-- Hall regions stay inside the ring of pillars.
	spawnRegion(regions, "Loot_Cathedrale", Vector3.new(cathedral.center.X, cathedral.floorY + 6, cathedral.center.Z), Vector3.new(cathedral.radius * 0.7, 8, cathedral.radius * 0.7), "Treasure", { RegionCount = 5 })
	spawnRegion(regions, "Loot_Meduses", jellies.center - Vector3.new(0, jellies.radius * 0.25, 0), Vector3.new(1, 0.4, 1) * jellies.radius, "Treasure", { RegionCount = 4 })
	spawnRegion(regions, "Creatures_Cathedrale", cathedral.center, Vector3.new(0.7, 0.3, 0.7) * cathedral.radius, "Creature", {
		RegionCount = 3, RegionSpecies = "TortueMarine,RequinRecif", RegionWanderRadius = math.floor(cathedral.radius * 0.5), RegionUnderground = true,
	})
	spawnRegion(regions, "Creatures_Meduses", jellies.center, Vector3.new(1, 0.5, 1) * jellies.radius, "Creature", {
		RegionCount = 6, RegionSpecies = "MeduseLumineuse", RegionWanderRadius = math.floor(jellies.radius * 0.5), RegionUnderground = true,
	})

	layout:SetAnchor("Caves", { chambers = chambers, tunnels = tunnels, entrances = entrances })
	print(string.format("[Caves] %d chambers, %d tunnels, %d entrances", #chambers, #TUNNELS, #entrances))
end

return Caves
