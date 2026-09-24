-- "L'Impératrice": a colossal ocean liner lying on the abyssal plain
-- (~500 m) beyond the Sirène Noire's ledge -- on the far side of the
-- first wreck, seen from the island. 900 studs long, broken in two like
-- the great liners that went down: the bow section rests upright,
-- nose in the mud, with her four-funnel superstructure; the stern
-- section lies twisted away 330 studs further, crumpled, her great
-- bronze propellers still on their shafts; between them a trail of boilers, coal, a fallen
-- funnel and everything the passengers left behind.
--
-- Built from steel plates lofted on a smooth liner hull (fine bow,
-- parallel midbody, rounded counter stern), with rows of portholes (a few
-- still glowing), internal decks, a grand staircase under a glass dome,
-- a ballroom with chandeliers, a dining saloon, the bridge, lifeboat
-- davits, rusticles hanging off every edge, and faint bioluminescent
-- colonies along her waterline so her lines read in the dark.
--
-- Ship frame: Z along the length (bow at -Z), Y up from the keel, X
-- across (+X starboard). Each half has its own world frame.

local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")

local Liner = {}

local LENGTH = 900
local BEAM = 112
local HULL = 86 -- keel to the upper deck at the sides
local DECKS = { 20, 38, 56 } -- internal decks, height above the keel
local TIER = 17 -- superstructure storey
local STATION = 14 -- plate length
local STRAKES = 10
local BOW_END, STERN_START = 0.58, 0.64
local DISTANCE = 730 -- from the island's centre, on the wreck's bearing
local BOW_OFFSET, STERN_OFFSET = -40, 330 -- along the contour

local STEEL = Color3.fromRGB(40, 36, 35)
local RED_BOTTOM = Color3.fromRGB(104, 44, 34)
local RUST = Color3.fromRGB(122, 64, 36)
local RUST_LIGHT = Color3.fromRGB(156, 88, 46)
local WHITE = Color3.fromRGB(168, 160, 144)
local DECK_WOOD = Color3.fromRGB(96, 90, 80)
local FUNNEL = Color3.fromRGB(172, 116, 52)
local FUNNEL_TOP = Color3.fromRGB(26, 24, 24)
local BRASS = Color3.fromRGB(176, 140, 64)
local BRONZE = Color3.fromRGB(150, 110, 60)
local DARK_GLASS = Color3.fromRGB(18, 34, 44)
local GLOW = Color3.fromRGB(120, 225, 255)
local WARM = Color3.fromRGB(255, 200, 120)

-- Hull shape ------------------------------------------------------------------------------

local function halfBeam(s: number): number
	if s < 0.18 then
		return BEAM / 2 * math.sin(s / 0.18 * math.pi / 2) ^ 0.8
	elseif s < 0.86 then
		return BEAM / 2
	end
	return BEAM / 2 * (1 - 0.45 * ((s - 0.86) / 0.14) ^ 2)
end

local function keelY(s: number): number
	return 14 * math.max(0, (s - 0.9) / 0.1) ^ 2
end

local function deckY(s: number): number
	return HULL + 7 * ((s - 0.5) * 2) ^ 2
end

local function stationZ(s: number): number
	return -LENGTH / 2 + s * LENGTH
end

local function hullPoint(s: number, t: number, side: number): Vector3
	local y = keelY(s) + (deckY(s) - keelY(s)) * t
	return Vector3.new(side * halfBeam(s) * t ^ 0.3, y, stationZ(s))
end

-- Inside half-width of the hull at height y.
local function insideHalf(s: number, y: number): number
	local t = math.clamp((y - keelY(s)) / (deckY(s) - keelY(s)), 0, 1)
	return math.max(halfBeam(s) * t ^ 0.3 - 1.6, 1)
end

function Liner.Build(layout)
	local site = layout:GetAnchor("WreckSite")
	assert(site, "Liner needs the Seabed's wreck bearing")
	local rng = layout:Random("Liner")
	local function random(): number
		return rng:NextNumber()
	end

	local worldFolder = Workspace:FindFirstChild("World") or Instance.new("Folder")
	worldFolder.Name = "World"
	worldFolder.Parent = Workspace
	local underwater = worldFolder:FindFirstChild("Underwater") or Instance.new("Folder")
	underwater.Name = "Underwater"
	underwater.Parent = worldFolder
	local old = underwater:FindFirstChild("Imperatrice")
	if old then
		old:Destroy()
	end
	local root = Instance.new("Model")
	root.Name = "Imperatrice"
	local folders = {}
	for _, name in ipairs({ "Hull", "Decks", "Superstructure", "Interior", "Funnels", "Fittings", "Rust", "Debris", "Lights", "SpawnRegions" }) do
		local f = Instance.new("Folder")
		f.Name = name
		f.Parent = root
		folders[name] = f
	end

	local count = 0
	local function part(folder: string, name: string, size: Vector3, cframe: CFrame, material: Enum.Material, color: Color3, shape: Enum.PartType?, collide: boolean?): Part
		local p = Instance.new("Part")
		p.Name = name
		p.Anchored = true
		p.CanTouch = false
		p.CanCollide = collide ~= false
		p.CanQuery = collide ~= false
		p.CastShadow = size.Magnitude > 10
		p.Shape = shape or Enum.PartType.Block
		p.Size = size
		p.CFrame = cframe
		p.Material = material
		p.Color = color
		p.Parent = folders[folder]
		count += 1
		return p
	end
	local function light(parent: BasePart, color: Color3, range: number, brightness: number)
		local l = Instance.new("PointLight")
		l.Color = color
		l.Range = range
		l.Brightness = brightness
		l.Shadows = false
		l.Parent = parent
	end
	local function ground(x: number, z: number): number
		return layout:GroundHeight(x, z)
	end

	-- Placement: on the wreck's bearing, beyond the ledge, lengthwise along
	-- the contour.
	local outward = site.outward
	local along = Vector3.new(-outward.Z, 0, outward.X)
	local base = outward * DISTANCE
	local right = Vector3.new(0, 1, 0):Cross(along).Unit

	local function sectionFrame(center: Vector3, back: Vector3, sRange: { number }, sink: number, roll: number, pitch: number): CFrame
		local midZ = stationZ((sRange[1] + sRange[2]) / 2)
		local sideways = Vector3.new(0, 1, 0):Cross(back).Unit
		local y = ground(center.X, center.Z) - sink
		return CFrame.fromMatrix(Vector3.new(center.X, y, center.Z), sideways, Vector3.new(0, 1, 0), back) * CFrame.Angles(pitch, 0, roll) * CFrame.new(0, 0, -midZ)
	end
	local bowCenter = base + along * (BOW_OFFSET + (stationZ(0) + stationZ(BOW_END)) / 2)
	local bowFrame = sectionFrame(bowCenter, along, { 0, BOW_END }, 7, math.rad(4), math.rad(-1.2))
	-- The stern twisted away on the way down, her torn end toward the bow.
	local sternBack = (along * math.cos(math.rad(24)) + right * math.sin(math.rad(24))).Unit
	local sternFrame = sectionFrame(base + along * STERN_OFFSET, sternBack, { STERN_START, 1 }, 5, math.rad(-11), math.rad(2.5))

	-- Plating ------------------------------------------------------------------------------
	local plates = 0
	local function plate(frame: CFrame, a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color3)
		local center = (a + b + c + d) / 4
		local u = ((b - a) + (d - c)) / 2
		local v = ((c - a) + (d - b)) / 2
		if u.Magnitude < 0.05 or v.Magnitude < 0.05 then
			return nil
		end
		local uHat = u.Unit
		local vPerp = v - uHat * v:Dot(uHat)
		if vPerp.Magnitude < 0.05 then
			return nil
		end
		plates += 1
		return part("Hull", "Plate", Vector3.new(u.Magnitude * 1.04 + 0.3, vPerp.Magnitude * 1.06 + 0.2, 1.4), frame * CFrame.fromMatrix(center, uHat, vPerp.Unit), Enum.Material.CorrodedMetal, color)
	end

	local function stationsOf(sMin: number, sMax: number): { number }
		local n = math.max(2, math.ceil((sMax - sMin) * LENGTH / STATION))
		local list = {}
		for i = 0, n do
			table.insert(list, sMin + (sMax - sMin) * i / n)
		end
		return list
	end

	-- `broken` is the s of the torn end; plates near it are ragged.
	local function plateHull(frame: CFrame, sMin: number, sMax: number, broken: number, skip)
		local stations = stationsOf(sMin, sMax)
		for i = 1, #stations - 1 do
			local s0, s1 = stations[i], stations[i + 1]
			local nearBreak = math.abs((s0 + s1) / 2 - broken) * LENGTH
			for j = 0, STRAKES - 1 do
				local t0, t1 = j / STRAKES, (j + 1) / STRAKES
				for _, side in ipairs({ -1, 1 }) do
					local ragged = nearBreak < STATION * 2.5 and random() < 0.55 - nearBreak / (STATION * 8)
					if not ragged and not (skip and skip(s0, t0, side)) then
						local color = t1 <= 0.3 and RED_BOTTOM or STEEL
						local roll = random()
						if roll < 0.12 then
							color = RUST
						elseif roll < 0.15 then
							color = RUST_LIGHT
						end
						plate(frame, hullPoint(s0, t0, side), hullPoint(s1, t0, side), hullPoint(s0, t1, side), hullPoint(s1, t1, side), color)
					end
				end
			end
		end
	end

	-- Portholes: dark glass, a few still glowing.
	local function portholes(frame: CFrame, sMin: number, sMax: number, broken: number)
		for _, t in ipairs({ 0.66, 0.78, 0.9 }) do
			local s = sMin + 0.012
			while s < sMax - 0.012 do
				if math.abs(s - broken) * LENGTH > 18 then
					for _, side in ipairs({ -1, 1 }) do
						local point = hullPoint(s, t, side)
						local normal = Vector3.new(side, 0, 0)
						local glow = random() < 0.08
						local p = part("Hull", "Porthole", Vector3.new(0.6, 2.6, 2.6), frame * (CFrame.new(point + normal * 0.75) * CFrame.lookAt(Vector3.zero, normal) * CFrame.Angles(0, math.pi / 2, 0)),
							glow and Enum.Material.Neon or Enum.Material.Glass, glow and GLOW or DARK_GLASS, Enum.PartType.Cylinder, false)
						if glow then
							p.Transparency = 0.2
						end
					end
				end
				s += 8 / LENGTH
			end
		end
	end

	-- Decks: internal decks of steel, the upper deck of weathered planks.
	local function decks(frame: CFrame, sMin: number, sMax: number, broken: number, opening)
		local stations = stationsOf(sMin, sMax)
		for i = 1, #stations - 1 do
			local s0, s1 = stations[i], stations[i + 1]
			local s = (s0 + s1) / 2
			local z = stationZ(s)
			local length = (s1 - s0) * LENGTH + 0.3
			local nearBreak = math.abs(s - broken) * LENGTH
			for level, y in ipairs(DECKS) do
				if y > keelY(s) + 3 and not (opening and opening(s, level)) and not (nearBreak < STATION * 2 and random() < 0.6) then
					part("Decks", "Deck", Vector3.new(insideHalf(s, y) * 2, 1, length), frame * CFrame.new(0, y, z), Enum.Material.Metal, Color3.fromRGB(70, 62, 56))
				end
			end
			if not (opening and opening(s, 4)) and not (nearBreak < STATION * 2 and random() < 0.5) then
				local y = deckY(s)
				part("Decks", "UpperDeck", Vector3.new(halfBeam(s) * 2 - 1, 1.2, length), frame * CFrame.new(0, y, z), Enum.Material.WoodPlanks, DECK_WOOD)
				-- The rail along both edges.
				for _, side in ipairs({ -1, 1 }) do
					if random() > 0.15 then
						part("Fittings", "Rail", Vector3.new(0.4, 0.4, length), frame * CFrame.new(side * (halfBeam(s) - 0.6), y + 4, z), Enum.Material.CorrodedMetal, RUST, nil, false)
						part("Fittings", "RailPost", Vector3.new(0.4, 4, 0.4), frame * CFrame.new(side * (halfBeam(s) - 0.6), y + 2, z), Enum.Material.CorrodedMetal, RUST, nil, false)
					end
				end
			end
		end
	end

	-- Rusticles: rust icicles hanging off the edges.
	local function rusticles(frame: CFrame, sMin: number, sMax: number, amount: number)
		for _ = 1, amount do
			local s = sMin + random() * (sMax - sMin)
			local side = random() < 0.5 and -1 or 1
			local point = hullPoint(s, 1, side) + Vector3.new(side * 1.1, -0.6, 0)
			local length = 1.5 + random() * 4.5
			part("Rust", "Rusticle", Vector3.new(0.5, length, 0.5), frame * CFrame.new(point - Vector3.new(0, length / 2, 0)) * CFrame.Angles(0, random() * 3, 0), Enum.Material.CorrodedMetal, RUST, nil, false)
		end
	end

	-- Bioluminescent colonies along the waterline: her lines in the dark.
	local function glowLine(frame: CFrame, sMin: number, sMax: number)
		for _, side in ipairs({ -1, 1 }) do
			local stations = stationsOf(sMin, sMax)
			for i = 1, #stations - 1, 2 do
				if random() < 0.7 then
					local a, b = hullPoint(stations[i], 0.36, side), hullPoint(stations[i + 1], 0.36, side)
					local line = part("Lights", "GlowColony", Vector3.new(0.4, 0.6, (b - a).Magnitude), frame * CFrame.lookAt((a + b) / 2 + Vector3.new(side * 1, 0, 0), b + Vector3.new(side * 1, 0, 0)), Enum.Material.Neon, GLOW, nil, false)
					line.Transparency = 0.35
				end
			end
		end
	end

	-- Bow section ---------------------------------------------------------------------------
	-- Where she struck: a gash low on the starboard bow, the way into the holds.
	plateHull(bowFrame, 0, BOW_END, BOW_END, function(s, t, side)
		return side > 0 and s > 0.08 and s < 0.19 and t > 0.08 and t < 0.38
	end)
	portholes(bowFrame, 0.02, BOW_END, BOW_END)
	local WELL_A, WELL_B = 0.205, 0.235 -- the grand staircase well
	decks(bowFrame, 0.01, BOW_END, BOW_END, function(s, level)
		if s > WELL_A and s < WELL_B then
			return true
		end
		-- Forward holds open under the gash; cargo hatches on the foredeck.
		if level <= 2 and s > 0.1 and s < 0.18 then
			return true
		end
		return level == 4 and ((s > 0.05 and s < 0.065) or (s > 0.1 and s < 0.115))
	end)
	-- Keel and stem.
	local keelA, keelB = bowFrame * hullPoint(0.005, 0, 1), bowFrame * hullPoint(BOW_END - 0.01, 0, 1)
	part("Hull", "Keel", Vector3.new(4, 4, (keelB - keelA).Magnitude), CFrame.lookAt((keelA + keelB) / 2, keelB), Enum.Material.CorrodedMetal, STEEL)
	local stemA, stemB = bowFrame * Vector3.new(0, 0, stationZ(0) + 1), bowFrame * Vector3.new(0, deckY(0) + 2, stationZ(0) + 1)
	part("Hull", "Stem", Vector3.new(3, (stemB - stemA).Magnitude, 3), CFrame.lookAt((stemA + stemB) / 2, stemB) * CFrame.Angles(math.pi / 2, 0, 0), Enum.Material.CorrodedMetal, STEEL)
	rusticles(bowFrame, 0.03, BOW_END, 110)
	glowLine(bowFrame, 0.02, BOW_END - 0.02)

	-- Her name, in brass letters on both bows.
	for _, side in ipairs({ -1, 1 }) do
		local a, b = hullPoint(0.05, 0.93, side), hullPoint(0.1, 0.93, side)
		local normal = (b - a):Cross(Vector3.new(0, 1, 0)).Unit * -side
		if normal.X * side < 0 then
			normal = -normal
		end
		local boardFrame = CFrame.lookAt((a + b) / 2 + normal * 0.9, (a + b) / 2 + normal * 0.9 + (b - a))
		local board = part("Fittings", "NameBoard", Vector3.new(0.3, 7, (b - a).Magnitude), bowFrame * boardFrame, Enum.Material.CorrodedMetal, STEEL, nil, false)
		local gui = Instance.new("SurfaceGui")
		gui.Face = boardFrame.RightVector:Dot(normal) > 0 and Enum.NormalId.Right or Enum.NormalId.Left
		gui.LightInfluence = 0.3
		gui.PixelsPerStud = 20
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamBold
		label.TextScaled = true
		label.TextColor3 = BRASS
		label.Text = "L'IMPÉRATRICE"
		label.Parent = gui
		gui.Parent = board
		-- Anchor in its hawse pipe.
		local hawse = hullPoint(0.035, 0.8, side) + Vector3.new(side * 1.6, 0, 0)
		part("Fittings", "Anchor", Vector3.new(2.4, 16, 2.4), bowFrame * CFrame.new(hawse), Enum.Material.CorrodedMetal, STEEL)
		part("Fittings", "AnchorFluke", Vector3.new(1.6, 2.4, 9), bowFrame * CFrame.new(hawse - Vector3.new(side * 0.4, 8, 0)), Enum.Material.CorrodedMetal, STEEL)
	end

	-- Superstructure: two storeys of white deckhouses with rows of windows,
	-- a third for the bridge. Some walls have fallen in -- a way inside.
	local function deckhouse(frame: CFrame, sMin: number, sMax: number, storey: number, inset: number, broken: number)
		local stations = stationsOf(sMin, sMax)
		for i = 1, #stations - 1 do
			local s0, s1 = stations[i], stations[i + 1]
			local s = (s0 + s1) / 2
			local z = stationZ(s)
			local length = (s1 - s0) * LENGTH + 0.3
			local y0 = deckY(s) + 0.6 + (storey - 1) * TIER
			local half = halfBeam(s) - inset
			local nearBreak = math.abs(s - broken) * LENGTH
			if nearBreak > STATION * 1.5 or random() < 0.4 then
				for _, side in ipairs({ -1, 1 }) do
					if random() > 0.1 then
						part("Superstructure", "Wall", Vector3.new(1, TIER, length), frame * CFrame.new(side * half, y0 + TIER / 2, z), Enum.Material.CorrodedMetal, WHITE)
						for w = -1, 1, 2 do
							local glow = random() < 0.05
							local window = part("Superstructure", "Window", Vector3.new(0.3, TIER * 0.35, length * 0.3), frame * CFrame.new(side * (half + 0.6), y0 + TIER * 0.55, z + w * length * 0.22),
								glow and Enum.Material.Neon or Enum.Material.Glass, glow and WARM or DARK_GLASS, nil, false)
							if glow then
								window.Transparency = 0.3
							end
						end
					end
				end
				if random() > 0.08 then
					part("Superstructure", "Roof", Vector3.new(half * 2 + 3, 1, length), frame * CFrame.new(0, y0 + TIER, z), Enum.Material.CorrodedMetal, WHITE)
				end
			end
		end
		-- Front wall of the deckhouse.
		local y0 = deckY(sMin) + 0.6 + (storey - 1) * TIER
		local half = halfBeam(sMin) - inset
		part("Superstructure", "FrontWall", Vector3.new(half * 2, TIER, 1), frame * CFrame.new(0, y0 + TIER / 2, stationZ(sMin)), Enum.Material.CorrodedMetal, WHITE)
		for k = -3, 3 do
			part("Superstructure", "Window", Vector3.new(half * 0.18, TIER * 0.35, 0.3), frame * CFrame.new(k * half * 0.27, y0 + TIER * 0.55, stationZ(sMin) - 0.6), Enum.Material.Glass, DARK_GLASS, nil, false)
		end
	end
	deckhouse(bowFrame, 0.13, BOW_END - 0.01, 1, 8, BOW_END)
	deckhouse(bowFrame, 0.15, BOW_END - 0.03, 2, 16, BOW_END)
	-- Bridge and wheelhouse on top, forward.
	local bridgeY = deckY(0.16) + 0.6 + 2 * TIER
	part("Superstructure", "Wheelhouse", Vector3.new(44, 12, 18), bowFrame * CFrame.new(0, bridgeY + 6, stationZ(0.165)), Enum.Material.CorrodedMetal, WHITE)
	for k = -4, 4 do
		part("Superstructure", "Window", Vector3.new(3.6, 4, 0.3), bowFrame * CFrame.new(k * 4.6, bridgeY + 8, stationZ(0.165) - 9.2), Enum.Material.Glass, DARK_GLASS, nil, false)
	end
	for _, side in ipairs({ -1, 1 }) do
		part("Superstructure", "BridgeWing", Vector3.new(26, 1, 10), bowFrame * CFrame.new(side * 35, bridgeY + 0.5, stationZ(0.163)), Enum.Material.CorrodedMetal, WHITE)
	end
	local telegraph = part("Fittings", "Telegraph", Vector3.new(1.6, 4, 1.6), bowFrame * CFrame.new(-6, bridgeY + 2, stationZ(0.162)), Enum.Material.Metal, BRASS, Enum.PartType.Cylinder)
	telegraph.CFrame = bowFrame * CFrame.new(-6, bridgeY + 2, stationZ(0.162)) * CFrame.Angles(0, 0, math.pi / 2)
	part("Fittings", "Wheel", Vector3.new(0.6, 6, 6), bowFrame * CFrame.new(0, bridgeY + 4, stationZ(0.166)) * CFrame.Angles(0, math.pi / 2, 0), Enum.Material.Wood, Color3.fromRGB(90, 60, 38), Enum.PartType.Cylinder)

	-- The grand staircase: a well through every deck under a glass dome,
	-- with flights of steps and a glowing lamp on its newel.
	local wellZ = stationZ((WELL_A + WELL_B) / 2)
	local domeY = deckY(0.22) + 0.6 + 2 * TIER
	local dome = part("Superstructure", "GlassDome", Vector3.new(34, 12, 22), bowFrame * CFrame.new(0, domeY + 3, wellZ), Enum.Material.Glass, Color3.fromRGB(150, 200, 210), nil, false)
	dome.Transparency = 0.6
	local domeMesh = Instance.new("SpecialMesh")
	domeMesh.MeshType = Enum.MeshType.Sphere
	domeMesh.Parent = dome
	for k = -2, 2 do
		part("Superstructure", "DomeRib", Vector3.new(0.6, 7, 22), bowFrame * CFrame.new(k * 6.5, domeY + 3, wellZ) * CFrame.Angles(0, 0, k * 0.28), Enum.Material.CorrodedMetal, STEEL, nil, false)
	end
	for level = 1, #DECKS do
		local y = DECKS[level]
		for step = 0, 8 do
			part("Interior", "Step", Vector3.new(14, 1, 2.4), bowFrame * CFrame.new(0, y + step * 2, wellZ + 8 - step * 2), Enum.Material.WoodPlanks, Color3.fromRGB(110, 76, 48))
		end
		local newel = part("Interior", "NewelLamp", Vector3.new(1.2, 1.2, 1.2), bowFrame * CFrame.new(7, y + 4, wellZ + 9), Enum.Material.Neon, WARM, Enum.PartType.Ball, false)
		if level == #DECKS then
			light(newel, WARM, 26, 1.2)
		end
	end

	-- Ballroom inside the first deckhouse: chandeliers, a piano, tables.
	local ballY = deckY(0.34) + 0.6
	for _, s in ipairs({ 0.3, 0.36 }) do
		local chandelier = part("Interior", "Chandelier", Vector3.new(4, 4, 4), bowFrame * CFrame.new(0, ballY + TIER - 4, stationZ(s)), Enum.Material.Neon, WARM, Enum.PartType.Ball, false)
		chandelier.Transparency = 0.25
		light(chandelier, WARM, 34, 1.4)
		part("Interior", "ChandelierChain", Vector3.new(0.3, 3, 0.3), bowFrame * CFrame.new(0, ballY + TIER - 1.5, stationZ(s)), Enum.Material.Metal, BRASS, nil, false)
	end
	part("Interior", "Piano", Vector3.new(6, 3.2, 8), bowFrame * CFrame.new(-18, ballY + 1.6, stationZ(0.33)) * CFrame.Angles(0, 0.4, 0.05), Enum.Material.SmoothPlastic, Color3.fromRGB(20, 16, 16))
	part("Interior", "PianoLid", Vector3.new(5.6, 0.3, 7.4), bowFrame * CFrame.new(-18, ballY + 4.4, stationZ(0.33)) * CFrame.Angles(0, 0.4, 0.5), Enum.Material.SmoothPlastic, Color3.fromRGB(20, 16, 16), nil, false)
	-- Dining saloon on the deck below: rows of round tables, some chairs
	-- still standing.
	local diningY = DECKS[3]
	for row = -1, 1 do
		for k = 0, 5 do
			local z = stationZ(0.4) + k * 12
			local x = row * 16
			local diningTable = part("Interior", "DiningTable", Vector3.new(0.8, 6, 6), bowFrame * CFrame.new(x, diningY + 3, z) * CFrame.Angles(0, 0, math.pi / 2 + (random() - 0.5) * 0.2), Enum.Material.Wood, Color3.fromRGB(96, 64, 40), Enum.PartType.Cylinder)
			diningTable.CanCollide = true
			if random() < 0.5 then
				part("Interior", "Chair", Vector3.new(2, 3, 2), bowFrame * CFrame.new(x + 3.8, diningY + 2, z) * CFrame.Angles(0, random() * 3, random() < 0.4 and math.pi / 2 or 0), Enum.Material.Wood, Color3.fromRGB(90, 60, 38))
			end
		end
	end

	-- Funnels: the first standing, the second leaning, the third
	-- collapsed on the deck; the fourth lies in the debris field.
	local funnelBase = deckY(0.3) + 0.6 + 2 * TIER
	local function funnel(position: CFrame, height: number)
		part("Funnels", "Funnel", Vector3.new(height, 22, 22), position * CFrame.Angles(0, 0, math.pi / 2), Enum.Material.CorrodedMetal, FUNNEL, Enum.PartType.Cylinder)
		part("Funnels", "FunnelTop", Vector3.new(12, 22.6, 22.6), position * CFrame.new(0, height / 2 - 6, 0) * CFrame.Angles(0, 0, math.pi / 2), Enum.Material.CorrodedMetal, FUNNEL_TOP, Enum.PartType.Cylinder)
		for k = 1, 3 do
			part("Funnels", "FunnelBand", Vector3.new(1, 22.8, 22.8), position * CFrame.new(0, -height / 2 + k * height / 4, 0) * CFrame.Angles(0, 0, math.pi / 2), Enum.Material.CorrodedMetal, RUST, Enum.PartType.Cylinder)
		end
	end
	local FUNNEL_H = 64
	funnel(bowFrame * CFrame.new(0, funnelBase + FUNNEL_H / 2, stationZ(0.27)) * CFrame.Angles(math.rad(-4), 0, 0), FUNNEL_H)
	funnel(bowFrame * CFrame.new(0, funnelBase + FUNNEL_H / 2 - 3, stationZ(0.38)) * CFrame.new(0, -FUNNEL_H / 2, 0) * CFrame.Angles(math.rad(-16), 0, math.rad(10)) * CFrame.new(0, FUNNEL_H / 2, 0), FUNNEL_H)
	funnel(bowFrame * CFrame.new(20, funnelBase + 11, stationZ(0.49)) * CFrame.Angles(math.rad(82), 0, math.rad(25)), FUNNEL_H)

	-- Foremast, fallen back against the bridge; lifeboat davits (their
	-- boats long gone), cargo hatches and cranes on the foredeck.
	local mastFoot = bowFrame * Vector3.new(0, deckY(0.08) + 1, stationZ(0.08))
	local mastTip = bowFrame * Vector3.new(4, bridgeY + 14, stationZ(0.15))
	part("Fittings", "Foremast", Vector3.new(3.2, (mastTip - mastFoot).Magnitude, 3.2), CFrame.lookAt((mastFoot + mastTip) / 2, mastTip) * CFrame.Angles(math.pi / 2, 0, 0), Enum.Material.CorrodedMetal, STEEL)
	part("Fittings", "CrowsNest", Vector3.new(5, 6, 5), CFrame.new(mastFoot:Lerp(mastTip, 0.72)), Enum.Material.CorrodedMetal, STEEL)
	for _, s in ipairs({ 0.055, 0.11 }) do
		part("Fittings", "CargoCrane", Vector3.new(1.6, 26, 1.6), bowFrame * CFrame.new(12, deckY(s) + 13, stationZ(s)) * CFrame.Angles(0.5, 0, -0.3), Enum.Material.CorrodedMetal, RUST)
	end
	local davitY = deckY(0.3) + 0.6 + 2 * TIER
	for k = 0, 7 do
		local s = 0.2 + k * 0.045
		for _, side in ipairs({ -1, 1 }) do
			if random() > 0.2 then
				local x = side * (halfBeam(s) - 17)
				part("Fittings", "Davit", Vector3.new(1, 10, 1), bowFrame * CFrame.new(x, davitY + 5, stationZ(s)) * CFrame.Angles(0, 0, -side * 0.25), Enum.Material.CorrodedMetal, RUST, nil, false)
				part("Fittings", "DavitArm", Vector3.new(6, 1, 1), bowFrame * CFrame.new(x + side * 3, davitY + 10, stationZ(s)), Enum.Material.CorrodedMetal, RUST, nil, false)
			end
		end
	end

	-- Stern section ---------------------------------------------------------------------------
	plateHull(sternFrame, STERN_START, 1, STERN_START, function(s, t, side)
		-- Crumpled when she hit the bottom: a whole flank torn open.
		return side < 0 and s > 0.7 and s < 0.8 and t > 0.45 and random() < 0.7
	end)
	portholes(sternFrame, STERN_START, 0.97, STERN_START)
	decks(sternFrame, STERN_START, 0.99, STERN_START, function(s, level)
		return level == 4 and s > 0.7 and s < 0.8 and random() < 0.5
	end)
	deckhouse(sternFrame, 0.67, 0.86, 1, 10, STERN_START)
	rusticles(sternFrame, STERN_START, 0.98, 60)
	glowLine(sternFrame, STERN_START + 0.02, 0.98)
	-- The counter stern's transom, the rudder and three great propellers.
	for _, side in ipairs({ -1, 1 }) do
		for j = 0, STRAKES - 1 do
			local t0, t1 = j / STRAKES, (j + 1) / STRAKES
			plate(sternFrame, hullPoint(1, t0, 0), hullPoint(1, t0, side), hullPoint(1, t1, 0), hullPoint(1, t1, side), STEEL)
		end
	end
	part("Hull", "Rudder", Vector3.new(3, 52, 26), sternFrame * CFrame.new(0, keelY(1) + 12, stationZ(1) - 8), Enum.Material.CorrodedMetal, STEEL)
	for _, x in ipairs({ -30, 0, 30 }) do
		local hub = sternFrame * CFrame.new(x, x == 0 and 30 or 26, stationZ(0.975))
		part("Hull", "PropellerHub", Vector3.new(8, 7, 7), hub * CFrame.Angles(0, math.pi / 2, 0), Enum.Material.Metal, BRONZE, Enum.PartType.Cylinder)
		part("Hull", "PropellerShaft", Vector3.new(30, 2.4, 2.4), hub * CFrame.new(0, 0, -16) * CFrame.Angles(0, math.pi / 2, 0), Enum.Material.CorrodedMetal, STEEL, Enum.PartType.Cylinder)
		local blades = x == 0 and 4 or 3
		for b = 1, blades do
			local reach = x == 0 and 17 or 20
			part("Hull", "PropellerBlade", Vector3.new(1.2, reach, 9), hub * CFrame.Angles(0, 0, b / blades * math.pi * 2 + random()) * CFrame.new(0, reach / 2 + 2, 0) * CFrame.Angles(0, 0.45, 0), Enum.Material.Metal, BRONZE)
		end
	end
	-- Her engines, bared at the break: two great engine blocks.
	for _, x in ipairs({ -18, 18 }) do
		local block = sternFrame * CFrame.new(x, DECKS[1] + 18, stationZ(STERN_START + 0.035))
		part("Interior", "Engine", Vector3.new(22, 34, 40), block, Enum.Material.CorrodedMetal, Color3.fromRGB(56, 50, 46))
		for c = -1, 1 do
			part("Interior", "EngineCylinder", Vector3.new(12, 9, 9), block * CFrame.new(0, 21, c * 12) * CFrame.Angles(0, 0, math.pi / 2), Enum.Material.CorrodedMetal, RUST, Enum.PartType.Cylinder)
		end
	end

	-- Debris field between the halves --------------------------------------------------------
	local bowEnd = bowFrame * Vector3.new(0, 0, stationZ(BOW_END))
	local sternEnd = sternFrame * Vector3.new(0, 0, stationZ(STERN_START))
	local function debrisSpot(): Vector3
		local p = bowEnd:Lerp(sternEnd, 0.1 + random() * 0.8) + right * ((random() - 0.5) * 180) + along * ((random() - 0.5) * 60)
		return Vector3.new(p.X, ground(p.X, p.Z), p.Z)
	end
	-- Boilers spilled out of her.
	for k = 1, 6 do
		local p = debrisSpot()
		part("Debris", "Boiler", Vector3.new(26, 22, 22), CFrame.new(p + Vector3.new(0, 9, 0)) * CFrame.Angles(0, random() * math.pi, 0.08), Enum.Material.CorrodedMetal, k % 2 == 0 and RUST or Color3.fromRGB(58, 50, 44), Enum.PartType.Cylinder)
	end
	-- The fourth funnel.
	local funnelSpot = debrisSpot()
	funnel(CFrame.new(funnelSpot + Vector3.new(0, 10, 0)) * CFrame.Angles(math.rad(88), random() * 3, 0), FUNNEL_H)
	-- Coal, deck plates, and the passengers' things.
	for _ = 1, 170 do
		local p = debrisSpot()
		local yaw = CFrame.Angles(0, random() * math.pi * 2, 0)
		local roll = random()
		if roll < 0.3 then
			local size = 1.2 + random() * 1.6
			part("Debris", "Coal", Vector3.new(size, size * 0.8, size), CFrame.new(p + Vector3.new(0, size * 0.3, 0)) * yaw, Enum.Material.Slate, Color3.fromRGB(26, 24, 26), nil, false)
		elseif roll < 0.45 then
			part("Debris", "DeckPlate", Vector3.new(8 + random() * 10, 1, 6 + random() * 8), CFrame.new(p + Vector3.new(0, 1, 0)) * yaw * CFrame.Angles(random() * 0.4, 0, random() * 0.4), Enum.Material.CorrodedMetal, random() < 0.5 and RUST or STEEL)
		elseif roll < 0.55 then
			part("Debris", "Suitcase", Vector3.new(3, 1.2, 2), CFrame.new(p + Vector3.new(0, 0.6, 0)) * yaw, Enum.Material.Fabric, Color3.fromRGB(96, 60, 40))
		elseif roll < 0.65 then
			part("Debris", "Plate", Vector3.new(0.2, 1.4, 1.4), CFrame.new(p + Vector3.new(0, 0.2, 0)) * yaw * CFrame.Angles(0, 0, math.pi / 2), Enum.Material.SmoothPlastic, Color3.fromRGB(220, 216, 206), Enum.PartType.Cylinder, false)
		elseif roll < 0.73 then
			local bottle = part("Debris", "Bottle", Vector3.new(1.6, 0.6, 0.6), CFrame.new(p + Vector3.new(0, 0.3, 0)) * yaw, Enum.Material.Glass, Color3.fromRGB(40, 110, 60), Enum.PartType.Cylinder, false)
			bottle.Transparency = 0.3
		elseif roll < 0.8 then
			part("Debris", "DeckChair", Vector3.new(2.2, 0.4, 6), CFrame.new(p + Vector3.new(0, 1, 0)) * yaw * CFrame.Angles(0.5, 0, 0), Enum.Material.Wood, Color3.fromRGB(112, 80, 50))
		elseif roll < 0.86 then
			part("Debris", "Pipe", Vector3.new(14 + random() * 10, 1.6, 1.6), CFrame.new(p + Vector3.new(0, 0.8, 0)) * yaw, Enum.Material.CorrodedMetal, RUST, Enum.PartType.Cylinder)
		elseif roll < 0.9 then
			part("Debris", "Bathtub", Vector3.new(6, 2.4, 3), CFrame.new(p + Vector3.new(0, 1.2, 0)) * yaw * CFrame.Angles(0, 0, 0.2), Enum.Material.SmoothPlastic, Color3.fromRGB(210, 206, 196))
		elseif roll < 0.95 then
			part("Debris", "LifeboatPlank", Vector3.new(1.4, 0.5, 10 + random() * 8), CFrame.new(p + Vector3.new(0, 0.3, 0)) * yaw, Enum.Material.WoodPlanks, Color3.fromRGB(150, 130, 100))
		else
			local chandelier = part("Debris", "FallenChandelier", Vector3.new(4, 3, 4), CFrame.new(p + Vector3.new(0, 1.2, 0)) * yaw, Enum.Material.Glass, Color3.fromRGB(230, 220, 190), Enum.PartType.Ball, false)
			chandelier.Transparency = 0.3
		end
	end
	-- The purser's safes, burst open on the mud.
	local safes = {}
	for k = 1, 4 do
		local p = debrisSpot()
		part("Debris", "Safe", Vector3.new(5, 6, 5), CFrame.new(p + Vector3.new(0, 2.6, 0)) * CFrame.Angles(0.1, random() * 3, 0.12), Enum.Material.Metal, Color3.fromRGB(46, 58, 50))
		local front = p + along * 5
		safes[k] = Vector3.new(front.X, ground(front.X, front.Z) + 2, front.Z)
	end

	-- Gameplay ------------------------------------------------------------------------------
	local function region(name: string, frame: CFrame, size: Vector3, kind: string, attributes: { [string]: any })
		local p = part("SpawnRegions", name, size, frame, Enum.Material.SmoothPlastic, Color3.new(1, 1, 1), nil, false)
		p.Transparency = 1
		p:SetAttribute("RegionKind", kind)
		p:SetAttribute("RegionEnabled", true)
		for key, value in pairs(attributes) do
			p:SetAttribute(key, value)
		end
		CollectionService:AddTag(p, "SpawnRegion")
		return p
	end
	region("Loot_Imperatrice_Cales", bowFrame * CFrame.new(0, DECKS[1] + 3, stationZ(0.14)), Vector3.new(40, 2, 50), "Treasure", { RegionCount = 5 })
	region("Loot_Imperatrice_Salon", bowFrame * CFrame.new(10, ballY + 3, stationZ(0.33)), Vector3.new(40, 2, 60), "Treasure", { RegionCount = 5 })
	region("Loot_Imperatrice_Salle", bowFrame * CFrame.new(0, diningY + 3, stationZ(0.45)), Vector3.new(50, 2, 60), "Treasure", { RegionCount = 4 })
	region("Loot_Imperatrice_Poupe", sternFrame * CFrame.new(0, DECKS[2] + 3, stationZ(0.8)), Vector3.new(40, 2, 70), "Treasure", { RegionCount = 4 })
	for k, spot in ipairs(safes) do
		region("Loot_Imperatrice_Coffre" .. k, CFrame.new(spot), Vector3.new(1, 1, 1), "Treasure", { RegionCount = 1 })
	end
	-- Sharks patrol her upper deck (they go no deeper than 400 m), the
	-- glowing jellyfish drift along her and over the debris.
	local deckTop = bowFrame * Vector3.new(0, deckY(0.3) + 30, stationZ(0.3))
	region("Creatures_Imperatrice_Pont", CFrame.new(deckTop), Vector3.new(120, 12, 260), "Creature", { RegionCount = 6, RegionSpecies = "RequinRecif,MeduseLumineuse", RegionWanderRadius = 140 })
	local midDebris = bowEnd:Lerp(sternEnd, 0.5)
	region("Creatures_Imperatrice_Debris", CFrame.new(midDebris.X, ground(midDebris.X, midDebris.Z) + 40, midDebris.Z), Vector3.new(160, 14, 160), "Creature", { RegionCount = 6, RegionSpecies = "MeduseLumineuse", RegionWanderRadius = 100 })

	-- A few lights so her bulk reads in the dark: work lamps still lit on
	-- deck, like a ship that never quite went out.
	for k = 0, 5 do
		local s = 0.05 + k * 0.1
		local lamp = part("Lights", "DeckLamp", Vector3.new(1.4, 1.4, 1.4), bowFrame * CFrame.new(k % 2 == 0 and 30 or -30, deckY(s) + 6, stationZ(s)), Enum.Material.Neon, GLOW, Enum.PartType.Ball, false)
		light(lamp, GLOW, 60, 1.2)
	end
	local sternLamp = part("Lights", "DeckLamp", Vector3.new(1.4, 1.4, 1.4), sternFrame * CFrame.new(0, deckY(0.85) + 8, stationZ(0.85)), Enum.Material.Neon, GLOW, Enum.PartType.Ball, false)
	light(sternLamp, GLOW, 60, 1.2)

	root.Parent = underwater

	-- Layout: both halves reserved; anchors for the biome and the tests.
	local bowSize = Vector3.new(BEAM + 30, HULL + 3 * TIER + FUNNEL_H + 20, BOW_END * LENGTH + 30)
	local bowBox = bowFrame * CFrame.new(0, bowSize.Y / 2 - 6, stationZ(BOW_END / 2))
	layout:ReserveBox("Liner_Bow", bowBox, bowSize)
	local sternSize = Vector3.new(BEAM + 30, HULL + TIER + 40, (1 - STERN_START) * LENGTH + 40)
	local sternBox = sternFrame * CFrame.new(0, sternSize.Y / 2 - 10, stationZ((1 + STERN_START) / 2))
	layout:ReserveBox("Liner_Stern", sternBox, sternSize)
	layout:SetAnchor("Liner", {
		center = bowEnd:Lerp(sternEnd, 0.5),
		bow = bowFrame,
		stern = sternFrame,
		bowBox = { cframe = bowBox, size = bowSize },
		sternBox = { cframe = sternBox, size = sternSize },
		gash = bowFrame * hullPoint(0.14, 0.22, 1),
		wellTop = bowFrame * Vector3.new(0, domeY, wellZ),
		keelStations = { bowFrame * hullPoint(0.1, 0, 1), bowFrame * hullPoint(0.3, 0, 1), bowFrame * hullPoint(0.5, 0, 1) },
	})
	print(string.format("[Liner] L'Impératrice: %d plates, %d parts", plates, count))
end

return Liner
