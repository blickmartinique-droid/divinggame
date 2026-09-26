-- "Le Cimetière de la Sirène": the wreck site as a whole biome. The Sirène
-- Noire (Shipwreck.lua) is not alone on her ledge: the terrace that curves
-- along the NE flank (~330 m, Seabed.lua) is a graveyard of ships.
--
--   * Le Brick chaviré: a brig lying upside down, keel to the sky, half
--     sunk in the sand; a hole torn in her bottom and her open stern lead
--     into the dark space under the hull.
--   * La Chaloupe brisée: a sloop broken in two, bow and stern apart, her
--     mast fallen between them.
--   * Le Squelette: an old hull eaten down to its keel and ribs.
--   * A debris trail of cargo along the whole ledge (barrels, crates,
--     cannons and shot, amphorae, a ship's wheel, a bell, anchors with
--     their chains, half-buried chests), sunken lanterns still glowing,
--     and deep-water life: sea whips, gorgonian fans on the hulls, black
--     coral, glass sponges, glowing anemones and sea pens.
--
-- Everything is placed along the ledge's arc (layout WreckSite anchor) and
-- rests on layout:GroundHeight. Each wreck reserves its volume.

local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")

local MarineFlora = require(script.Parent.MarineFlora)

local WreckGraveyard = {}

local WOOD = Color3.fromRGB(92, 76, 58)
local WOOD_DARK = Color3.fromRGB(60, 48, 38)
local WOOD_ALGAE = Color3.fromRGB(76, 86, 60)
local IRON = Color3.fromRGB(46, 48, 52)
local BRASS = Color3.fromRGB(170, 134, 60)
local LANTERN = Color3.fromRGB(255, 196, 110)
local GLOW = Color3.fromRGB(110, 230, 255)

-- A simple lofted hull in its own frame: Z along the length (bow at -Z),
-- Y up from the keel, X across. `skip(i, j, side)` leaves a plank out.
local function hullShape(length: number, beam: number, depth: number)
	local function halfBeam(s: number): number
		if s < 0.35 then
			return beam / 2 * math.sin(s / 0.35 * math.pi / 2) ^ 0.75
		elseif s < 0.7 then
			return beam / 2
		end
		return beam / 2 * (1 - 0.3 * ((s - 0.7) / 0.3) ^ 2)
	end
	local function keel(s: number): number
		return depth * 0.16 * math.max(0, (0.2 - s) / 0.2) ^ 2
	end
	local function deck(s: number): number
		return depth + depth * 0.1 * ((s - 0.5) * 2) ^ 2
	end
	return function(s: number, t: number, side: number): Vector3
		local y = keel(s) + (deck(s) - keel(s)) * t
		return Vector3.new(side * halfBeam(s) * t ^ 0.55, y, -length / 2 + s * length)
	end
end

function WreckGraveyard.Build(layout)
	local site = layout:GetAnchor("WreckSite")
	assert(site and site.distance, "WreckGraveyard needs the Seabed's wreck ledge")
	local rng = layout:Random("WreckGraveyard")
	local kit = MarineFlora.new(layout:Random("GraveyardLife"))
	local function random(): number
		return rng:NextNumber()
	end

	local worldFolder = Workspace:FindFirstChild("World") or Instance.new("Folder")
	worldFolder.Name = "World"
	worldFolder.Parent = Workspace
	local underwater = worldFolder:FindFirstChild("Underwater") or Instance.new("Folder")
	underwater.Name = "Underwater"
	underwater.Parent = worldFolder
	local wreckZone = underwater:FindFirstChild("WreckZone") or Instance.new("Folder")
	wreckZone.Name = "WreckZone"
	wreckZone.Parent = underwater
	local old = wreckZone:FindFirstChild("Graveyard")
	if old then
		old:Destroy()
	end
	local root = Instance.new("Folder")
	root.Name = "Graveyard"
	root.Parent = wreckZone
	local function folder(name: string): Folder
		local f = Instance.new("Folder")
		f.Name = name
		f.Parent = root
		return f
	end
	local wrecks, debris, life, lights, regions = folder("Wrecks"), folder("Debris"), folder("Life"), folder("Lights"), folder("SpawnRegions")

	local function part(parent: Instance, name: string, size: Vector3, cframe: CFrame, material: Enum.Material, color: Color3, shape: Enum.PartType?, collide: boolean?): Part
		local p = Instance.new("Part")
		p.Name = name
		p.Anchored = true
		p.CanCollide = collide == true
		p.CanQuery = collide == true
		p.CanTouch = false
		p.CastShadow = size.Magnitude > 8
		p.Shape = shape or Enum.PartType.Block
		p.Size = size
		p.CFrame = cframe
		p.Material = material
		p.Color = color
		p.Parent = parent
		return p
	end
	local function ellipsoid(parent: Instance, name: string, size: Vector3, cframe: CFrame, material: Enum.Material, color: Color3): Part
		local p = part(parent, name, size, cframe, material, color)
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = p
		return p
	end
	local function sway(p: Part, amplitude: number, speed: number)
		CollectionService:AddTag(p, "Sway")
		p:SetAttribute("Sway", true)
		p:SetAttribute("SwayAmplitude", amplitude)
		p:SetAttribute("SwaySpeed", speed)
	end
	local function ground(x: number, z: number): Vector3
		return Vector3.new(x, layout:GroundHeight(x, z), z)
	end
	-- A point on the ledge: `t` studs along the arc from its middle, `r`
	-- studs across it (+ downslope). Also returns the along-arc direction.
	local function onLedge(t: number, r: number): (Vector3, Vector3)
		local angle = site.angle + t / site.distance
		local radius = site.distance + r
		local along = Vector3.new(-math.sin(angle), 0, math.cos(angle))
		return ground(math.cos(angle) * radius, math.sin(angle) * radius), along
	end
	local function region(name: string, center: Vector3, size: Vector3, kind: string, attributes: { [string]: any })
		local p = part(regions, name, size, CFrame.new(center), Enum.Material.SmoothPlastic, Color3.new(1, 1, 1))
		p.Transparency = 1
		p:SetAttribute("RegionKind", kind)
		p:SetAttribute("RegionEnabled", true)
		for key, value in pairs(attributes) do
			p:SetAttribute(key, value)
		end
		CollectionService:AddTag(p, "SpawnRegion")
		return p
	end
	local function lantern(position: Vector3, range: number)
		local body = part(lights, "SunkenLantern", Vector3.new(1.6, 2.2, 1.6), CFrame.new(position) * CFrame.Angles(random() * 0.6, random() * 3, random() * 0.6), Enum.Material.CorrodedMetal, BRASS)
		local glass = part(lights, "LanternGlass", Vector3.new(1.1, 1.4, 1.1), body.CFrame, Enum.Material.Neon, LANTERN)
		glass.Transparency = 0.2
		local light = Instance.new("PointLight")
		light.Color = LANTERN
		light.Range = range
		light.Brightness = 1.6
		light.Shadows = false
		light.Parent = glass
	end
	-- Flat growths stuck on a surface (coral crust, sponges).
	local CRUST = { Color3.fromRGB(190, 90, 110), Color3.fromRGB(220, 150, 80), Color3.fromRGB(120, 170, 150), Color3.fromRGB(150, 110, 180) }
	local function crust(parent: Instance, cframe: CFrame)
		local size = 1.5 + random() * 3
		ellipsoid(parent, "Crust", Vector3.new(size, 0.7, size * (0.7 + random() * 0.5)), cframe * CFrame.new(0, 0.3, 0), Enum.Material.Sand, CRUST[rng:NextInteger(1, #CRUST)])
	end
	local function fan(parent: Instance, base: Vector3, height: number)
		local colors = { Color3.fromRGB(170, 60, 110), Color3.fromRGB(220, 110, 60), Color3.fromRGB(230, 200, 90) }
		local f = ellipsoid(parent, "GorgonianFan", Vector3.new(height * 0.9, height, 0.3), CFrame.new(base + Vector3.new(0, height * 0.45, 0)) * CFrame.Angles(0, random() * math.pi, (random() - 0.5) * 0.3), Enum.Material.Fabric, colors[rng:NextInteger(1, #colors)])
		f.Transparency = 0.15
		sway(f, 0.06, 0.4)
	end

	-- Hulls ------------------------------------------------------------------------------

	-- Planks a hull shape into `parent` under `frame`. Returns the number
	-- of planks and the surface function in world space.
	local function plankHull(parent: Instance, frame: CFrame, shape, stations: number, strakes: number, sMin: number, sMax: number, skip)
		local planks = 0
		local shades = {}
		for j = 0, strakes - 1 do
			shades[j] = ({ WOOD, WOOD_DARK, WOOD_ALGAE })[rng:NextInteger(1, 3)]
		end
		for i = 0, stations - 1 do
			local s0, s1 = sMin + (sMax - sMin) * i / stations, sMin + (sMax - sMin) * (i + 1) / stations
			for j = 0, strakes - 1 do
				local t0, t1 = j / strakes, (j + 1) / strakes
				for _, side in ipairs({ -1, 1 }) do
					if not (skip and skip(s0, t0, side)) then
						local a, b = shape(s0, t0, side), shape(s1, t0, side)
						local c, d = shape(s0, t1, side), shape(s1, t1, side)
						local center = (a + b + c + d) / 4
						local u = ((b - a) + (d - c)) / 2
						local v = ((c - a) + (d - b)) / 2
						if u.Magnitude > 0.05 and v.Magnitude > 0.05 then
							local uHat = u.Unit
							local vPerp = v - uHat * v:Dot(uHat)
							if vPerp.Magnitude > 0.05 then
								local p = part(parent, "Plank", Vector3.new(u.Magnitude * 1.06 + 0.3, vPerp.Magnitude * 1.08 + 0.2, 1.4),
									frame * CFrame.fromMatrix(center, uHat, vPerp.Unit), Enum.Material.WoodPlanks, shades[j], nil, true)
								planks += 1
								if random() < 0.12 then
									crust(parent, p.CFrame * CFrame.new(0, 0, side * 0.9) * CFrame.Angles(math.pi / 2, 0, 0))
								end
							end
						end
					end
				end
			end
		end
		return planks
	end
	-- Keel beam and stem along the bottom of a hull shape.
	local function keelBeam(parent: Instance, frame: CFrame, shape, sMin: number, sMax: number)
		local a, b = shape(sMin, 0, 1), shape(sMax, 0, 1)
		part(parent, "Keel", Vector3.new(2.6, 2.6, (b - a).Magnitude + 2), frame * CFrame.lookAt((a + b) / 2, b), Enum.Material.Wood, WOOD_DARK, nil, true)
	end
	-- Ribs: a chain of short beams up each side at one station.
	local function rib(parent: Instance, frame: CFrame, shape, s: number, top: number)
		for _, side in ipairs({ -1, 1 }) do
			local steps = 6
			for k = 0, steps - 1 do
				local a, b = shape(s, top * k / steps, side), shape(s, top * (k + 1) / steps, side)
				part(parent, "Rib", Vector3.new(1.6, 1.6, (b - a).Magnitude + 0.8), frame * CFrame.lookAt((a + b) / 2, b), Enum.Material.Wood, WOOD_DARK, nil, true)
			end
		end
	end

	local reserved = {}
	local function reserve(name: string, cframe: CFrame, size: Vector3)
		layout:ReserveBox(name, cframe, size)
		table.insert(reserved, { name = name, cframe = cframe, size = size })
	end

	-- 1. Le Brick chaviré: upside down, keel up, the deck edge buried.
	local BRIG_L, BRIG_B, BRIG_D = 150, 44, 30
	local brigShape = hullShape(BRIG_L, BRIG_B, BRIG_D)
	local brigBase, brigAlong = onLedge(300, -45)
	local brigDir = (brigAlong * math.cos(math.rad(20)) + Vector3.new(brigAlong.Z, 0, -brigAlong.X) * math.sin(math.rad(20))).Unit
	local brigRight = brigDir:Cross(Vector3.new(0, 1, 0)).Unit
	-- Turned over (180 degrees about her length) with a slight heel; the
	-- deck line (local Y = BRIG_D) ends ~3 studs under the sand.
	local brigFrame = CFrame.fromMatrix(brigBase + Vector3.new(0, BRIG_D - 3, 0), brigRight, Vector3.new(0, 1, 0), -brigDir) * CFrame.Angles(0, 0, math.pi + 0.12)
	local brig = folder("BrickChavire")
	brig.Parent = wrecks
	local planks = plankHull(brig, brigFrame, brigShape, 20, 8, 0, 1, function(s, t, side)
		-- The hole torn in her bottom (now her top), and the stern open.
		return (s > 0.42 and s < 0.56 and t < 0.35 and side > 0) or s > 0.93
	end)
	keelBeam(brig, brigFrame, brigShape, 0.02, 0.98)
	part(brig, "Rudder", Vector3.new(1.4, 16, 9), brigFrame * CFrame.new(0, 8, BRIG_L / 2 + 3), Enum.Material.Wood, WOOD_DARK, nil, true)
	for k = 1, 5 do
		fan(brig, brigFrame * brigShape(0.15 + k * 0.14, 0.05, (k % 2) * 2 - 1) + Vector3.new(0, 1, 0), 4 + random() * 3)
	end
	local brigHole = brigFrame * brigShape(0.49, 0.1, 1)
	lantern(brigFrame * Vector3.new(0, BRIG_D * 0.55, 0), 30)
	region("Loot_Brick", brigFrame * Vector3.new(0, BRIG_D * 0.62, 0), Vector3.new(BRIG_B * 0.35, 3, BRIG_L * 0.4), "Treasure", { RegionCount = 4 })
	reserve("Graveyard_Brick", brigFrame * CFrame.new(0, BRIG_D / 2, 0), Vector3.new(BRIG_B + 12, BRIG_D + 14, BRIG_L + 16))

	-- 2. La Chaloupe brisée: bow and stern lying apart, heeled over.
	local SLOOP_L, SLOOP_B, SLOOP_D = 104, 30, 20
	local sloopShape = hullShape(SLOOP_L, SLOOP_B, SLOOP_D)
	local sloop = folder("ChaloupeBrisee")
	sloop.Parent = wrecks
	local halves = {
		{ t = -304, r = 30, sMin = 0, sMax = 0.46, turn = 0.35, heel = 0.45 },
		{ t = -345, r = -22, sMin = 0.54, sMax = 1, turn = -0.35, heel = -0.3 },
	}
	for index, half in ipairs(halves) do
		local base, along = onLedge(half.t, half.r)
		local dir = (along * math.cos(half.turn) + Vector3.new(along.Z, 0, -along.X) * math.sin(half.turn)).Unit
		local right = dir:Cross(Vector3.new(0, 1, 0)).Unit
		-- Shift so this half's middle, not the whole hull's, sits at `base`.
		local mid = (half.sMin + half.sMax) / 2
		local frame = CFrame.fromMatrix(base - Vector3.new(0, 2, 0), right, Vector3.new(0, 1, 0), -dir) * CFrame.Angles(0, 0, half.heel) * CFrame.new(0, 0, -(-SLOOP_L / 2 + mid * SLOOP_L))
		planks += plankHull(sloop, frame, sloopShape, 9, 6, half.sMin, half.sMax, function(s, t, side)
			return side < 0 and t > 0.6 and s > 0.2 and s < 0.8 and random() < 0.5
		end)
		keelBeam(sloop, frame, sloopShape, half.sMin, half.sMax)
		-- Splintered frames where she broke.
		rib(sloop, frame, sloopShape, index == 1 and half.sMax or half.sMin, 0.9)
		if index == 2 then
			region("Loot_Chaloupe", frame * Vector3.new(0, SLOOP_D * 0.45, -SLOOP_L / 2 + mid * SLOOP_L), Vector3.new(SLOOP_B * 0.3, 2, SLOOP_L * 0.2), "Treasure", { RegionCount = 3 })
		end
		reserve("Graveyard_Chaloupe" .. index, frame * CFrame.new(0, SLOOP_D / 2, -SLOOP_L / 2 + mid * SLOOP_L), Vector3.new(SLOOP_B + 14, SLOOP_D + 16, SLOOP_L * 0.5 + 14))
	end
	local mastFrom, _ = onLedge(-300, 5)
	local mastTo, _ = onLedge(-335, 10)
	local mastDir = (mastTo - mastFrom).Unit
	part(sloop, "FallenMast", Vector3.new(60, 2.6, 2.6), CFrame.lookAt((mastFrom + mastTo) / 2 + Vector3.new(0, 1.2, 0), mastTo + mastDir * 30 + Vector3.new(0, 1.2, 0)) * CFrame.Angles(0, math.pi / 2, 0), Enum.Material.Wood, WOOD, Enum.PartType.Cylinder, true)
	local sail = part(sloop, "TornSail", Vector3.new(26, 0.3, 18), CFrame.new((mastFrom + mastTo) / 2 + Vector3.new(0, 0.8, 0)) * CFrame.Angles(0.05, random() * 3, 0.04), Enum.Material.Fabric, Color3.fromRGB(180, 170, 146))
	sail.Transparency = 0.1

	-- 3. Le Squelette: keel, ribs and a couple of strakes, down on the edge.
	local SKEL_L, SKEL_B, SKEL_D = 130, 38, 26
	local skelShape = hullShape(SKEL_L, SKEL_B, SKEL_D)
	local skelBase, skelAlong = onLedge(40, 128)
	local skelRight = skelAlong:Cross(Vector3.new(0, 1, 0)).Unit
	local skelFrame = CFrame.fromMatrix(skelBase - Vector3.new(0, 4, 0), skelRight, Vector3.new(0, 1, 0), -skelAlong) * CFrame.Angles(0, 0, 0.18)
	local skeleton = folder("Squelette")
	skeleton.Parent = wrecks
	keelBeam(skeleton, skelFrame, skelShape, 0, 1)
	for k = 1, 17 do
		rib(skeleton, skelFrame, skelShape, k / 18, 0.55 + 0.45 * math.sin(k / 18 * math.pi) * (0.6 + random() * 0.4))
	end
	planks += plankHull(skeleton, skelFrame, skelShape, 14, 2, 0.05, 0.95, function(s, t, side)
		return random() < 0.35
	end)
	reserve("Graveyard_Squelette", skelFrame * CFrame.new(0, SKEL_D / 2, 0), Vector3.new(SKEL_B + 12, SKEL_D + 10, SKEL_L + 12))

	local function clear(position: Vector3, margin: number): boolean
		return layout:IsFree(position + Vector3.new(0, 2, 0), margin)
	end

	-- 4. Debris trail along the ledge.
	local chests = {}
	for _ = 1, 170 do
		local position = onLedge((random() * 2 - 1) * 360, -100 + random() * 250)
		if clear(position, 3) then
			local yaw = CFrame.Angles(0, random() * math.pi * 2, 0)
			local roll = random()
			if roll < 0.2 then
				local size = 3 + random() * 2.5
				part(debris, "Crate", Vector3.new(size, size, size), CFrame.new(position + Vector3.new(0, size * 0.3, 0)) * yaw * CFrame.Angles(random() * 0.4, 0, random() * 0.4), Enum.Material.WoodPlanks, Color3.fromRGB(112, 88, 60), nil, true)
			elseif roll < 0.38 then
				part(debris, "Barrel", Vector3.new(4.2, 3.2, 3.2), CFrame.new(position + Vector3.new(0, 1.3, 0)) * yaw, Enum.Material.Wood, Color3.fromRGB(98, 72, 50), Enum.PartType.Cylinder, true)
			elseif roll < 0.5 then
				local cannon = part(debris, "Cannon", Vector3.new(9, 1.8, 1.8), CFrame.new(position + Vector3.new(0, 0.7, 0)) * yaw * CFrame.Angles(0, 0, 0.08), Enum.Material.CorrodedMetal, IRON, Enum.PartType.Cylinder, true)
				crust(debris, cannon.CFrame * CFrame.new(0, 0.8, 0))
			elseif roll < 0.6 then
				-- A pile of shot.
				for k = 0, 5 do
					local offset = Vector3.new((k % 3) * 1.3 - 1.3, math.floor(k / 3) * 1.1 + 0.6, (k % 2) * 1.1)
					part(debris, "CannonBall", Vector3.new(1.3, 1.3, 1.3), CFrame.new(position) * yaw * CFrame.new(offset), Enum.Material.CorrodedMetal, IRON, Enum.PartType.Ball)
				end
			elseif roll < 0.72 then
				-- Amphora, fallen on its side.
				local jar = CFrame.new(position + Vector3.new(0, 1.2, 0)) * yaw * CFrame.Angles(0, 0, math.pi / 2 - 0.2)
				ellipsoid(debris, "Amphora", Vector3.new(2.6, 4.2, 2.6), jar, Enum.Material.Slate, Color3.fromRGB(168, 102, 70))
				part(debris, "AmphoraNeck", Vector3.new(1, 1.6, 1), jar * CFrame.new(0, 2.6, 0), Enum.Material.Slate, Color3.fromRGB(150, 92, 64), Enum.PartType.Cylinder)
			elseif roll < 0.84 then
				part(debris, "Plank", Vector3.new(1, 0.6, 8 + random() * 12), CFrame.new(position + Vector3.new(0, 0.3, 0)) * yaw * CFrame.Angles(0, 0, 0.06), Enum.Material.WoodPlanks, WOOD)
			elseif roll < 0.9 and #chests < 5 then
				-- A chest half in the sand, brass bands, lid ajar.
				local chest = CFrame.new(position + Vector3.new(0, 0.9, 0)) * yaw * CFrame.Angles(0.15, 0, 0.1)
				part(debris, "Chest", Vector3.new(5, 2.6, 3.2), chest, Enum.Material.Wood, Color3.fromRGB(104, 70, 44), nil, true)
				part(debris, "ChestLid", Vector3.new(5, 0.6, 3.2), chest * CFrame.new(0, 1.8, -1.2) * CFrame.Angles(-0.7, 0, 0), Enum.Material.Wood, Color3.fromRGB(96, 64, 40))
				for band = -1, 1, 2 do
					part(debris, "ChestBand", Vector3.new(0.4, 2.8, 3.4), chest * CFrame.new(band * 1.6, 0, 0), Enum.Material.Metal, BRASS)
				end
				table.insert(chests, chest * Vector3.new(0, 3.5, 3.5))
			else
				-- Anchor with a length of chain snaking off it.
				local anchor = CFrame.new(position + Vector3.new(0, 4, 0)) * yaw * CFrame.Angles(0.35, 0, 0.5)
				part(debris, "AnchorShank", Vector3.new(1.8, 16, 1.8), anchor, Enum.Material.CorrodedMetal, IRON, nil, true)
				part(debris, "AnchorArms", Vector3.new(12, 1.8, 1.8), anchor * CFrame.new(0, -7, 0) * CFrame.Angles(0, 0, 0.3), Enum.Material.CorrodedMetal, IRON)
				local link = position
				local heading = random() * math.pi * 2
				for k = 1, 18 do
					heading += (random() - 0.5) * 0.5
					link += Vector3.new(math.cos(heading), 0, math.sin(heading)) * 1.5
					local g = ground(link.X, link.Z)
					part(debris, "ChainLink", Vector3.new(1.6, 0.4, 0.9), CFrame.new(g + Vector3.new(0, 0.3, 0)) * CFrame.Angles(0, -heading, (k % 2) * math.pi / 2), Enum.Material.CorrodedMetal, IRON)
				end
			end
		end
	end
	-- The ship's wheel and her bell, somewhere near the Sirène's stern.
	local wheelAt = onLedge(215, 70)
	local wheel = CFrame.new(wheelAt + Vector3.new(0, 0.5, 0)) * CFrame.Angles(math.pi / 2 - 0.15, random() * 3, 0)
	part(debris, "WheelHub", Vector3.new(1, 1.6, 1.6), wheel, Enum.Material.Wood, WOOD_DARK, Enum.PartType.Cylinder)
	for k = 0, 7 do
		part(debris, "WheelSpoke", Vector3.new(0.5, 7.5, 0.5), wheel * CFrame.Angles(k * math.pi / 8, 0, 0), Enum.Material.Wood, WOOD)
	end
	local bellAt = onLedge(-230, 85)
	part(debris, "ShipBell", Vector3.new(3, 2.6, 2.6), CFrame.new(bellAt + Vector3.new(0, 1, 0)) * CFrame.Angles(0.3, 0.4, math.pi / 2 + 0.4), Enum.Material.Metal, BRASS, Enum.PartType.Cylinder)
	for index, spot in ipairs(chests) do
		region("Loot_GraveyardChest" .. index, spot, Vector3.new(1, 1, 1), "Treasure", { RegionCount = 1 })
	end

	-- 5. Deep-water life: sea whips, black coral, glass sponges, glowing
	-- anemones and sea pens, gorgonian fans on the wrecks.
	local WHIP = { Color3.fromRGB(210, 80, 60), Color3.fromRGB(230, 150, 60), Color3.fromRGB(200, 60, 120) }
	for _ = 1, 150 do
		local position = onLedge((random() * 2 - 1) * 380, -120 + random() * 280)
		if clear(position, 2) then
			local roll = random()
			if roll < 0.3 then
				-- A tuft of sea whips.
				for k = 1, rng:NextInteger(3, 6) do
					local height = 5 + random() * 7
					local foot = ground(position.X + random() * 2 - 1, position.Z + random() * 2 - 1)
					local whip = part(life, "SeaWhip", Vector3.new(0.35, height, 0.35), CFrame.new(foot + Vector3.new(0, height / 2 - 0.3, 0)) * CFrame.Angles((random() - 0.5) * 0.2, 0, (random() - 0.5) * 0.2), Enum.Material.SmoothPlastic, WHIP[rng:NextInteger(1, #WHIP)])
					sway(whip, 0.1, 0.35 + k * 0.03)
				end
			elseif roll < 0.48 then
				-- Black coral: a dark trunk with pale feathery branches.
				local trunk = CFrame.new(position + Vector3.new(0, 3, 0)) * CFrame.Angles(0, random() * 3, 0)
				part(life, "BlackCoral", Vector3.new(0.6, 6, 0.6), trunk, Enum.Material.SmoothPlastic, Color3.fromRGB(30, 26, 28))
				for k = 1, 5 do
					part(life, "BlackCoralBranch", Vector3.new(0.3, 3 + random() * 2, 0.3), trunk * CFrame.new(0, -1 + k * 0.8, 0) * CFrame.Angles(0, k * 1.3, 0.8) * CFrame.new(0, 1.5, 0), Enum.Material.SmoothPlastic, Color3.fromRGB(236, 232, 220))
				end
			elseif roll < 0.63 then
				-- Glass sponge: a Venus' flower basket (MarineFlora).
				kit:GlassSponge(life, position - Vector3.new(0, 0.3, 0), 4 + random() * 6)
			elseif roll < 0.82 then
				-- Glowing anemones.
				for k = 1, rng:NextInteger(1, 3) do
					local base = ground(position.X + random() * 3 - 1.5, position.Z + random() * 3 - 1.5)
					kit:Anemone(life, base, 0.8 + random() * 0.3, Color3.fromRGB(120, 60, 90), k % 2 == 0 and GLOW or Color3.fromRGB(255, 120, 200), true, 8)
				end
			else
				-- A sea pen: a glowing quill on a stalk.
				kit:SeaPen(life, position, 3.5 + random() * 3, Color3.fromRGB(140, 255, 210))
			end
		end
	end

	-- 6. Sunken lanterns along the trail, and faint glows in the wrecks.
	for k = 1, 9 do
		local position = onLedge(-330 + k * 66, (k % 3) * 40 - 30)
		if clear(position, 2) then
			lantern(position + Vector3.new(0, 0.9, 0), 26)
		end
	end
	lantern(brigHole + Vector3.new(0, -3, 0), 22)

	-- 7. Life around the wrecks.
	region("Creatures_Graveyard_Brick", brigBase + site.outward * 70 + Vector3.new(0, 20, 0), Vector3.new(90, 10, 90), "Creature", { RegionCount = 5, RegionSpecies = "RequinRecif,MeduseLumineuse", RegionWanderRadius = 80 })
	local sloopCenter = onLedge(-318, 5)
	region("Creatures_Graveyard_Chaloupe", sloopCenter + Vector3.new(0, 22, 0), Vector3.new(80, 10, 80), "Creature", { RegionCount = 4, RegionSpecies = "RequinRecif,MeduseLumineuse", RegionWanderRadius = 60 })
	-- Mantas glide over the ledge just above their deepest range.
	region("Creatures_Graveyard_Above", site.position + Vector3.new(0, 36, 0) + site.outward * 60, Vector3.new(260, 10, 260), "Creature", { RegionCount = 4, RegionSpecies = "RaieManta,RequinRecif", RegionWanderRadius = 120 })

	layout:SetAnchor("Graveyard", {
		center = site.position,
		brig = brigFrame,
		brigHole = brigHole,
		sloop = sloopCenter,
		skeleton = skelFrame,
		reserved = reserved,
		radius = site.halfArc + 40,
	})
	local parts = 0
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("BasePart") then
			parts += 1
		end
	end
	print(string.format("[WreckGraveyard] %d wreck planks, %d parts", planks, parts))
end

return WreckGraveyard
