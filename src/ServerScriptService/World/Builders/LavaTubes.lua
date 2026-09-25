-- "Le Réseau du Volcan": the island is an old volcano, and its lava tubes
-- are the real underwater network of the map. Under the island lies a
-- vast hall, Le Cœur du volcan, with a sunken temple at its heart; six
-- tubes radiate from it:
--   * Le Puits du Lagon  -- a second blue hole, up to the lagoon floor
--     right off the beach: the way in from the hub;
--   * Tube de l'Éperon   -- joins the Éperon caves (Salle des Cristaux);
--   * Tube de l'Épave    -- down to the Sirène's ledge, through the
--     Galerie des Échos;
--   * Tube de la Forêt   -- out into the giant kelp forest (west);
--   * Tube du Kelp doré  -- out into the golden kelp (east);
--   * Tube des Abysses   -- the long descent to the rift, through the
--     Salle des Orgues and its basalt columns.
-- Tubes are carved as chains of spheres along splines (Air, then Water:
-- see Caves), their walls turned to basalt. Every opening is framed by an
-- ancient stone arch with glowing runes and a sign saying where it leads;
-- rune beacons line the tubes so a diver never loses the way. The hall
-- holds the temple (tiers, columns -- some fallen --, guardian statues, an
-- altar with a glowing orb), lava cracks glowing in its floor.
-- Publishes the "Network" anchor (chambers, tubes, entrances) used by the
-- currents, decor, biomes and tests.

local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")

local Noise = require(script.Parent.Noise)

local LavaTubes = {}

local STONE = Color3.fromRGB(176, 168, 150)
local STONE_DARK = Color3.fromRGB(120, 114, 100)
local BASALT = Color3.fromRGB(44, 42, 48)
local RUNE = Color3.fromRGB(110, 230, 255)
local LAVA = Color3.fromRGB(255, 110, 30)
local GOLD = Color3.fromRGB(230, 190, 80)

local HEART = { center = Vector3.new(0, -160, 0), radius = 58 }

local function dir(bearing: number): Vector3
	local a = math.rad(bearing)
	return Vector3.new(math.cos(a), 0, math.sin(a))
end
local function at(bearing: number, r: number, y: number): Vector3
	return dir(bearing) * r + Vector3.new(0, y, 0)
end

-- Tubes, from the hall outward. `exit`: the last point is outside the rock
-- (an entrance); `into`: the tube ends inside another chamber.
local TUBES = {
	{ id = "PuitsDuLagon", name = "Le Puits du Lagon", radius = 11, exit = true, points = { at(330, 32, -122), at(330, 70, -80), at(330, 98, -42), at(330, 112, -18), at(330, 118, -6) } },
	{ id = "TubeEperon", name = "Grottes de l'Éperon", radius = 10, into = "Cristaux", points = { at(154, 52, -165), at(154, 130, -152), at(154, 200, -138) } },
	{ id = "TubeEpave", name = "Cimetière de la Sirène", radius = 13, exit = true, chamber = { id = "Echos", name = "Galerie des Échos", at = 3, radius = 24 }, points = { at(35, 52, -178), at(35, 105, -205), at(35, 145, -228), at(35, 190, -262), at(35, 232, -296), at(35, 268, -302) } },
	{ id = "TubeForet", name = "Forêt de kelp", radius = 12, exit = true, points = { at(265, 54, -168), at(265, 130, -162), at(265, 200, -156), at(265, 262, -151), at(265, 292, -148) } },
	{ id = "TubeKelpDore", name = "Kelp doré", radius = 12, exit = true, points = { at(115, 54, -168), at(115, 130, -162), at(115, 200, -156), at(115, 262, -151), at(115, 292, -148) } },
	{ id = "TubeAbysses", name = "Faille abyssale", radius = 13, exit = true, chamber = { id = "Orgues", name = "Salle des Orgues", at = 3, radius = 28 }, points = { at(300, 52, -182), at(300, 160, -232), at(300, 300, -312), at(300, 400, -382), at(300, 478, -432), at(300, 540, -446) } },
}

local function catmullRom(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: number): Vector3
	local t2, t3 = t * t, t * t * t
	return 0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3)
end

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

function LavaTubes.Build(layout)
	local terrain = Workspace.Terrain
	local rng = layout:Random("LavaTubes")
	local noise = Noise.new(layout.seed + 404)
	local function random(): number
		return rng:NextNumber()
	end
	-- Air then Water (see Caves); near the surface, the air above the sea
	-- is put back so no dome of water stands over the lagoon.
	local function carve(center: Vector3, radius: number)
		terrain:FillBall(center, radius, Enum.Material.Air)
		terrain:FillBall(center, radius, Enum.Material.Water)
		local top = center.Y + radius
		if top > 0 then
			terrain:FillBlock(CFrame.new(center.X, top / 2 + 0.25, center.Z), Vector3.new(radius * 2 + 4, top - 0.5 + 4, radius * 2 + 4), Enum.Material.Air)
		end
	end

	local worldFolder = Workspace:FindFirstChild("World") or Instance.new("Folder")
	worldFolder.Name = "World"
	worldFolder.Parent = Workspace
	local underwater = worldFolder:FindFirstChild("Underwater") or Instance.new("Folder")
	underwater.Name = "Underwater"
	underwater.Parent = worldFolder
	local old = underwater:FindFirstChild("ReseauDuVolcan")
	if old then
		old:Destroy()
	end
	local root = Instance.new("Folder")
	root.Name = "ReseauDuVolcan"
	root.Parent = underwater
	local function folder(name: string): Folder
		local f = Instance.new("Folder")
		f.Name = name
		f.Parent = root
		return f
	end
	local temple, arches, beacons, decor, regions = folder("Temple"), folder("Arches"), folder("Beacons"), folder("Decor"), folder("SpawnRegions")

	local function part(parent: Instance, name: string, size: Vector3, cframe: CFrame, material: Enum.Material, color: Color3, shape: Enum.PartType?, collide: boolean?): Part
		local p = Instance.new("Part")
		p.Name = name
		p.Anchored = true
		p.CanCollide = collide ~= false
		p.CanQuery = collide ~= false
		p.CanTouch = false
		p.CastShadow = size.Magnitude > 6
		p.Shape = shape or Enum.PartType.Block
		p.Size = size
		p.CFrame = cframe
		p.Material = material
		p.Color = color
		p.Parent = parent
		return p
	end
	-- Upright cylinder (Roblox cylinders lie along X).
	local function column(parent: Instance, name: string, diameter: number, bottom: Vector3, height: number, material: Enum.Material, color: Color3): Part
		return part(parent, name, Vector3.new(height, diameter, diameter), CFrame.new(bottom + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, 0, math.pi / 2), material, color, Enum.PartType.Cylinder)
	end
	local function light(parent: BasePart, color: Color3, range: number, brightness: number)
		local l = Instance.new("PointLight")
		l.Color = color
		l.Range = range
		l.Brightness = brightness
		l.Shadows = false
		l.Parent = parent
	end
	local function sign(board: BasePart, face: Enum.NormalId, title: string, subtitle: string)
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.PixelsPerStud = 24
		gui.LightInfluence = 0
		local list = Instance.new("UIListLayout")
		list.VerticalAlignment = Enum.VerticalAlignment.Center
		list.HorizontalAlignment = Enum.HorizontalAlignment.Center
		list.Parent = gui
		for index, line in ipairs({ { title, 0.6, RUNE }, { subtitle, 0.34, Color3.fromRGB(220, 240, 250) } }) do
			local label = Instance.new("TextLabel")
			label.BackgroundTransparency = 1
			label.Size = UDim2.fromScale(1, line[2])
			label.Font = index == 1 and Enum.Font.GothamBlack or Enum.Font.GothamBold
			label.TextScaled = true
			label.TextColor3 = line[3]
			label.Text = line[1]
			label.LayoutOrder = index
			label.Parent = gui
		end
		gui.Parent = board
	end
	local function region(name: string, center: Vector3, size: Vector3, kind: string, attributes: { [string]: any })
		local p = part(regions, name, size, CFrame.new(center), Enum.Material.SmoothPlastic, Color3.new(1, 1, 1), nil, false)
		p.Transparency = 1
		p:SetAttribute("RegionKind", kind)
		p:SetAttribute("RegionEnabled", true)
		for key, value in pairs(attributes) do
			p:SetAttribute(key, value)
		end
		CollectionService:AddTag(p, "SpawnRegion")
	end

	-- 1. Chambers: the heart, and the halls along the tubes.
	local chambers = {}
	local function carveChamber(id: string, name: string, center: Vector3, r: number)
		carve(center, r)
		for k = 1, 7 do
			local angle = k / 7 * math.pi * 2 + random() * 0.5
			local offset = Vector3.new(math.cos(angle), 0, math.sin(angle)) * r * (0.45 + random() * 0.2)
			carve(center + offset - Vector3.new(0, r * (0.12 + random() * 0.15), 0), r * (0.5 + random() * 0.15))
		end
		local floorY = center.Y - r * 0.55
		local chamber = { id = id, name = name, center = center, radius = r, floorY = floorY }
		table.insert(chambers, chamber)
		return chamber
	end
	local heart = carveChamber("Coeur", "Le Cœur du volcan", HEART.center, HEART.radius)
	local byId = { Coeur = heart }
	for _, spec in ipairs(TUBES) do
		if spec.chamber then
			byId[spec.chamber.id] = carveChamber(spec.chamber.id, spec.chamber.name, spec.points[spec.chamber.at], spec.chamber.radius)
		end
	end

	-- 2. Tubes.
	local caves = layout:GetAnchor("Caves")
	local tubes = {}
	for _, spec in ipairs(TUBES) do
		local points = table.clone(spec.points)
		table.insert(points, 1, HEART.center + (points[1] - HEART.center) * 0.5)
		if spec.into and caves then
			for _, chamber in ipairs(caves.chambers) do
				if chamber.spec.id == spec.into then
					table.insert(points, chamber.center)
				end
			end
		end
		local samples = sampleSpline(points, 3)
		local radii = {}
		for index, sample in ipairs(samples) do
			local radius = spec.radius * (1 + 0.15 * noise:Get(index * 0.17, #spec.id))
			radii[index] = radius
			carve(sample, radius)
		end
		-- Basalt walls: the tube's rock turned volcanic, segment by segment.
		for i = 1, #samples, 8 do
			local a, b = samples[i], samples[math.min(i + 8, #samples)]
			local reach = spec.radius * 1.6
			local minCorner = Vector3.new(math.min(a.X, b.X) - reach, math.min(a.Y, b.Y) - reach, math.min(a.Z, b.Z) - reach)
			local maxCorner = Vector3.new(math.max(a.X, b.X) + reach, math.max(a.Y, b.Y) + reach, math.max(a.Z, b.Z) + reach)
			local box = Region3.new(minCorner, maxCorner):ExpandToGrid(4)
			terrain:ReplaceMaterial(box, 4, Enum.Material.Rock, Enum.Material.Basalt)
			terrain:ReplaceMaterial(box, 4, Enum.Material.Slate, Enum.Material.Basalt)
		end
		tubes[spec.id] = { spec = spec, points = points, samples = samples, radii = radii }
	end

	-- Sand floors, then the tubes crossing a hall are cut again through
	-- its floor: the tube carries on as a trench across the sand.
	for _, chamber in ipairs(chambers) do
		terrain:FillCylinder(CFrame.new(chamber.center.X, chamber.floorY - 7, chamber.center.Z), 14, chamber.radius * 1.08, Enum.Material.Sand)
	end
	for _, tube in pairs(tubes) do
		for index, sample in ipairs(tube.samples) do
			for _, chamber in ipairs(chambers) do
				local flat = Vector3.new(sample.X - chamber.center.X, 0, sample.Z - chamber.center.Z).Magnitude
				if flat < chamber.radius * 1.08 + tube.radii[index] and sample.Y - tube.radii[index] < chamber.floorY then
					carve(sample, tube.radii[index])
					break
				end
			end
		end
	end
	-- Where to see a hall's sand: halfway out, across its tube.
	for _, spec in ipairs(TUBES) do
		local chamberSpec = spec.chamber
		if chamberSpec then
			local chamber = byId[chamberSpec.id]
			local across = (spec.points[chamberSpec.at + 1] - spec.points[chamberSpec.at - 1]):Cross(Vector3.new(0, 1, 0)).Unit
			chamber.floorProbe = Vector3.new(chamber.center.X, chamber.floorY - 2, chamber.center.Z) + across * chamber.radius * 0.55
		end
	end
	heart.floorProbe = Vector3.new(heart.center.X + heart.radius * 0.4, heart.floorY - 2, heart.center.Z + heart.radius * 0.2)

	-- 3. Entrances: where each open tube meets the seabed surface; a
	-- flared porch there (as in Caves) so the hole reads from outside.
	local entrances = {}
	for _, spec in ipairs(TUBES) do
		if spec.exit then
			local tube = tubes[spec.id]
			local samples = tube.samples
			local rimIndex = #samples
			for i = #samples, 1, -1 do
				if layout:GroundHeight(samples[i].X, samples[i].Z) > samples[i].Y then
					rimIndex = i
					break
				end
			end
			local rim = samples[rimIndex]
			local inward = (samples[math.max(rimIndex - 3, 1)] - rim).Unit
			for k, factor in ipairs({ 1.8, 1.6, 1.4, 1.2 }) do
				carve(rim + inward * ((k - 2) * 5), spec.radius * factor)
			end
			table.insert(entrances, { id = spec.id, name = spec.name, mouth = rim, inward = inward, radius = spec.radius, clearRadius = spec.radius * 2.8 })
			layout:ReserveSphere("NetworkMouth_" .. spec.id, rim, spec.radius * 2.8)
		end
	end

	-- 4. Stone arches: at every exterior mouth (facing out, "RÉSEAU DU
	-- VOLCAN -> Cœur du volcan") and at every tube's opening in the heart
	-- (facing in, naming where it leads).
	local function arch(center: Vector3, facing: Vector3, radius: number, title: string, subtitle: string)
		local flat = Vector3.new(facing.X, 0, facing.Z)
		if flat.Magnitude < 0.2 then
			flat = Vector3.new(1, 0, 0)
		end
		local frame = CFrame.lookAt(center, center + flat.Unit)
		local width, height = radius * 2.3, radius * 2.2
		for _, side in ipairs({ -1, 1 }) do
			local pillar = frame * CFrame.new(side * width / 2, -radius * 0.3, 0)
			part(arches, "ArchPillar", Vector3.new(3.2, height, 3.2), pillar, Enum.Material.Limestone, STONE)
			part(arches, "ArchCapital", Vector3.new(4.2, 1.4, 4.2), pillar * CFrame.new(0, height / 2, 0), Enum.Material.Limestone, STONE_DARK)
			for k = 1, 3 do
				local runeStone = part(arches, "Rune", Vector3.new(0.3, 1.2, 1.2), pillar * CFrame.new(0, -height * 0.3 + k * height * 0.18, -1.7) * CFrame.Angles(0, math.pi / 2, math.pi / 4), Enum.Material.Neon, RUNE, nil, false)
				runeStone.Transparency = 0.15
			end
		end
		local lintel = part(arches, "ArchLintel", Vector3.new(width + 5, 3, 3.6), frame * CFrame.new(0, height / 2 - radius * 0.3 + 2, 0), Enum.Material.Limestone, STONE)
		sign(lintel, Enum.NormalId.Front, title, subtitle)
		local keystone = part(arches, "Keystone", Vector3.new(2.4, 2.6, 0.6), frame * CFrame.new(0, height / 2 - radius * 0.3 + 2, -1.9), Enum.Material.Neon, RUNE, nil, false)
		keystone.Transparency = 0.1
		light(keystone, RUNE, 34, 1.4)
		return frame
	end
	for _, entrance in ipairs(entrances) do
		arch(entrance.mouth - entrance.inward * 3, -entrance.inward, entrance.radius, "RÉSEAU DU VOLCAN", "→ Le Cœur du volcan · " .. entrance.name)
	end
	local heartDoors = {}
	for _, spec in ipairs(TUBES) do
		local samples = tubes[spec.id].samples
		for i, sample in ipairs(samples) do
			if (sample - HEART.center).Magnitude > HEART.radius * 0.92 then
				local outward = (samples[math.min(i + 3, #samples)] - sample).Unit
				arch(sample - outward * 2, -outward, spec.radius, spec.name:upper(), "↦ " .. (spec.exit and "sortie" or "passage"))
				heartDoors[spec.id] = sample
				break
			end
		end
	end

	-- 5. Rune beacons along every tube, on alternate walls, every ~27 studs.
	for _, spec in ipairs(TUBES) do
		local tube = tubes[spec.id]
		local samples = tube.samples
		for i = 6, #samples - 4, 9 do
			local sample = samples[i]
			local inside = false
			for _, chamber in ipairs(chambers) do
				if (sample - chamber.center).Magnitude < chamber.radius * 1.05 then
					inside = true
				end
			end
			if not inside then
				local ahead = (samples[i + 1] - samples[i - 1]).Unit
				local side = ahead:Cross(Vector3.new(0, 1, 0))
				if side.Magnitude < 0.2 then
					side = Vector3.new(1, 0, 0)
				end
				side = side.Unit * ((i // 9) % 2 == 0 and 1 or -1)
				local spot = sample + side * (tube.radii[i] - 1.2) - Vector3.new(0, tube.radii[i] * 0.35, 0)
				local beacon = part(beacons, "Beacon", Vector3.new(0.9, 1.8, 0.9), CFrame.new(spot) * CFrame.Angles(0, i, 0.2), Enum.Material.Neon, RUNE, nil, false)
				beacon.Transparency = 0.1
				if (i // 9) % 3 == 0 then
					light(beacon, RUNE, 18, 0.9)
				end
			end
		end
	end

	-- 6. The sunken temple in the heart.
	local floor = Vector3.new(HEART.center.X, heart.floorY, HEART.center.Z)
	local tiers = { { 40, 2 }, { 31, 2 }, { 22, 2 } }
	local y = floor.Y
	for index, tier in ipairs(tiers) do
		part(temple, "TempleTier", Vector3.new(tier[1], tier[2], tier[1]), CFrame.new(floor.X, y + tier[2] / 2, floor.Z) * CFrame.Angles(0, math.rad(8), 0), Enum.Material.Limestone, index % 2 == 0 and STONE_DARK or STONE)
		y += tier[2]
	end
	local top = Vector3.new(floor.X, y, floor.Z)
	-- Stairs up the front (facing the lagoon shaft).
	local front = CFrame.lookAt(floor, floor + dir(330)) * CFrame.Angles(0, math.rad(8), 0)
	for step = 0, 5 do
		part(temple, "Step", Vector3.new(8, 1, 2), front * CFrame.new(0, step + 0.5, -20 - 1 + step * 1.5 + 1), Enum.Material.Limestone, STONE)
	end
	-- A ring of columns, some standing whole, some broken, two fallen.
	for k = 0, 7 do
		local a = k / 8 * math.pi * 2 + math.rad(8)
		local base = top + Vector3.new(math.cos(a) * 9, 0, math.sin(a) * 9)
		local state = k % 4
		if state == 3 then
			-- Fallen: lying on the tier and the sand below, in drums.
			local lie = Vector3.new(math.cos(a + 0.5), 0, math.sin(a + 0.5))
			for d = 0, 2 do
				local drum = base + lie * (3 + d * 4.4)
				-- Each drum rests on whatever is under it: a tier or the sand.
				local reach = math.max(math.abs(drum.X - floor.X), math.abs(drum.Z - floor.Z))
				local restY = reach < 11 and top.Y or reach < 15.5 and floor.Y + 4 or reach < 20 and floor.Y + 2 or floor.Y
				drum = Vector3.new(drum.X, restY + 1.3, drum.Z)
				part(temple, "FallenDrum", Vector3.new(4.2, 2.6, 2.6), CFrame.lookAt(drum, drum + lie) * CFrame.Angles(0, math.pi / 2, 0.1 * d), Enum.Material.Limestone, STONE, Enum.PartType.Cylinder)
			end
			column(temple, "ColumnBase", 3, base, 2, Enum.Material.Limestone, STONE_DARK)
		else
			local height = state == 2 and 7 + random() * 3 or 16
			column(temple, "ColumnBase", 3.2, base, 1.2, Enum.Material.Limestone, STONE_DARK)
			column(temple, "Column", 2.4, base + Vector3.new(0, 1.2, 0), height, Enum.Material.Limestone, STONE)
			if height >= 16 then
				part(temple, "ColumnCapital", Vector3.new(3.6, 1.2, 3.6), CFrame.new(base + Vector3.new(0, 1.2 + height + 0.6, 0)), Enum.Material.Limestone, STONE_DARK)
			end
		end
	end
	-- Lintel stones still spanning two pairs of columns.
	for _, pair in ipairs({ { 0, 1 }, { 4, 5 } }) do
		local a0, a1 = pair[1] / 8 * math.pi * 2 + math.rad(8), pair[2] / 8 * math.pi * 2 + math.rad(8)
		local p0 = top + Vector3.new(math.cos(a0) * 9, 18.4, math.sin(a0) * 9)
		local p1 = top + Vector3.new(math.cos(a1) * 9, 18.4, math.sin(a1) * 9)
		part(temple, "Lintel", Vector3.new(2.4, 1.6, (p1 - p0).Magnitude + 3), CFrame.lookAt((p0 + p1) / 2, p1), Enum.Material.Limestone, STONE)
	end
	-- The altar and its orb.
	part(temple, "Altar", Vector3.new(6, 3, 4), CFrame.new(top + Vector3.new(0, 1.5, 0)), Enum.Material.Limestone, STONE_DARK)
	for _, x in ipairs({ -2.6, 2.6 }) do
		part(temple, "AltarGold", Vector3.new(0.4, 3.1, 4.1), CFrame.new(top + Vector3.new(x, 1.5, 0)), Enum.Material.Metal, GOLD)
	end
	local orb = part(temple, "Orb", Vector3.new(2.6, 2.6, 2.6), CFrame.new(top + Vector3.new(0, 4.6, 0)), Enum.Material.Neon, RUNE, Enum.PartType.Ball, false)
	orb.Transparency = 0.1
	light(orb, RUNE, 60, 2.2)
	orb:SetAttribute("SpinSpeed", 0.6)
	CollectionService:AddTag(orb, "Spin")
	-- Two guardian statues either side of the stairs: seated figures with
	-- fish-tailed crowns, green with age.
	for _, x in ipairs({ -8, 8 }) do
		local base = front * CFrame.new(x, 0, -22)
		part(temple, "StatuePlinth", Vector3.new(4, 3, 4), base * CFrame.new(0, 1.5, 0), Enum.Material.Limestone, STONE_DARK)
		part(temple, "StatueBody", Vector3.new(2.8, 4.4, 2.2), base * CFrame.new(0, 5.2, 0), Enum.Material.Slate, Color3.fromRGB(96, 130, 110))
		part(temple, "StatueHead", Vector3.new(2, 2, 2), base * CFrame.new(0, 8.4, 0), Enum.Material.Slate, Color3.fromRGB(96, 130, 110), Enum.PartType.Ball)
		part(temple, "StatueCrown", Vector3.new(2.6, 1.2, 0.4), base * CFrame.new(0, 9.6, 0), Enum.Material.Metal, GOLD)
		for _, s in ipairs({ -1, 1 }) do
			local eyeGlow = part(temple, "StatueEye", Vector3.new(0.35, 0.35, 0.2), base * CFrame.new(s * 0.45, 8.6, -0.95), Enum.Material.Neon, RUNE, nil, false)
			eyeGlow.Transparency = 0.1
		end
	end
	-- Lava cracks glowing in the sand around the temple.
	for k = 1, 16 do
		local a = random() * math.pi * 2
		local r = 26 + random() * (HEART.radius * 0.7 - 26)
		local p = floor + Vector3.new(math.cos(a) * r, 0.1, math.sin(a) * r)
		local crack = part(decor, "LavaCrack", Vector3.new(0.6, 0.3, 5 + random() * 8), CFrame.new(p) * CFrame.Angles(0, random() * 3, 0), Enum.Material.Neon, LAVA, nil, false)
		crack.Transparency = 0.05
		if k % 4 == 0 then
			light(crack, LAVA, 22, 1.2)
		end
	end

	-- 7. The Salle des Orgues: basalt organ pipes rising from the floor and
	-- hanging from the roof. The Galerie des Échos: pale crystals.
	local orgues = byId.Orgues
	if orgues then
		for k = 1, 26 do
			local a = random() * math.pi * 2
			local r = random() * orgues.radius * 0.75
			local base = Vector3.new(orgues.center.X + math.cos(a) * r, orgues.floorY, orgues.center.Z + math.sin(a) * r)
			local height = 3 + random() * 10
			column(decor, "OrganPipe", 2 + random() * 1.5, base - Vector3.new(0, 1, 0), height + 1, Enum.Material.Basalt, BASALT)
		end
		local glow = part(decor, "OrguesGlow", Vector3.new(1, 1, 1), CFrame.new(orgues.center), Enum.Material.Neon, LAVA, Enum.PartType.Ball, false)
		glow.Transparency = 0.5
		light(glow, LAVA, 40, 1)
	end
	local echos = byId.Echos
	if echos then
		for k = 1, 18 do
			local a = random() * math.pi * 2
			local r = random() * echos.radius * 0.7
			local base = Vector3.new(echos.center.X + math.cos(a) * r, echos.floorY, echos.center.Z + math.sin(a) * r)
			local height = 2 + random() * 4
			local crystal = part(decor, "EchoCrystal", Vector3.new(0.9, height, 0.9), CFrame.new(base + Vector3.new(0, height / 2 - 0.3, 0)) * CFrame.Angles(random() * 0.5, random() * 3, random() * 0.5), Enum.Material.Neon, Color3.fromRGB(200, 170, 255), nil, false)
			crystal.Transparency = 0.2
			if k % 6 == 0 then
				light(crystal, Color3.fromRGB(200, 170, 255), 20, 0.9)
			end
		end
	end

	-- 8. Gameplay: loot in the halls, life in the heart.
	region("Loot_Temple", top + Vector3.new(0, 3, 0), Vector3.new(14, 2, 14), "Treasure", { RegionCount = 3 })
	region("Loot_Coeur", floor + Vector3.new(0, 3, 0), Vector3.new(HEART.radius * 0.8, 2, HEART.radius * 0.8), "Treasure", { RegionCount = 5 })
	if orgues then
		region("Loot_Orgues", Vector3.new(orgues.center.X, orgues.floorY + 16, orgues.center.Z), Vector3.new(orgues.radius * 0.6, 2, orgues.radius * 0.6), "Treasure", { RegionCount = 3 })
		region("Creatures_Orgues", orgues.center + Vector3.new(0, 4, 0), Vector3.new(1, 0.3, 1) * orgues.radius, "Creature", {
			RegionCount = 4, RegionSpecies = "MeduseLumineuse", RegionWanderRadius = math.floor(orgues.radius * 0.5), RegionUnderground = true,
		})
	end
	if echos then
		region("Loot_Echos", Vector3.new(echos.center.X, echos.floorY + 3, echos.center.Z), Vector3.new(echos.radius * 0.6, 2, echos.radius * 0.6), "Treasure", { RegionCount = 3 })
	end
	region("Creatures_Coeur", HEART.center + Vector3.new(0, 10, 0), Vector3.new(0.8, 0.2, 0.8) * HEART.radius, "Creature", {
		RegionCount = 4, RegionSpecies = "TortueMarine,RequinRecif", RegionWanderRadius = math.floor(HEART.radius * 0.6), RegionUnderground = true,
	})

	layout:SetAnchor("Network", { chambers = chambers, tubes = tubes, entrances = entrances, heart = heart, heartDoors = heartDoors, templeTop = top })
	print(string.format("[LavaTubes] %d chambers, %d tubes, %d entrances, %d parts", #chambers, #TUBES, #entrances, #root:GetDescendants()))
end

return LavaTubes
