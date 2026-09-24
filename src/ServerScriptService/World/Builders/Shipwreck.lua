-- "La Sirène Noire": a three-masted galleon lying on the sandy terrace of
-- the seamount's north-east flank (~330 m, Seabed.lua), built entirely
-- from primitives so it needs no mesh import.
--
-- The hull is lofted: a smooth parametric hull shape (sharp bow, full
-- midship, broad transom stern, rising sheer and keel at the ends) is
-- sampled into stations x strakes, and every cell of that grid becomes one
-- plank laid exactly on the surface -- so the sides are genuinely curved
-- and read as planked wood, not a box. Inside: a cargo hold, a gun deck
-- with cannons at their gunports, the main deck, a forecastle, and the
-- captain's cabin under the poop deck with its stern gallery windows.
--
-- The wreck story: she settled with a list to port, half sunk into the
-- sand; a great breach tore open her port side below the gun deck (the
-- way into the hold), the main deck collapsed around the snapped
-- mainmast, whose top now lies on the seabed beside her with its sail;
-- the mizzen broke too, the foremast still stands with a torn sail.
-- Coral, sponges and kelp have colonised her; faint bioluminescence and a
-- dim lantern guide divers inside. Her cargo lies scattered around.
--
-- Ship frame: Z along the length (bow at -Z), Y up from the keel's
-- baseline, X across (+X starboard).

local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")

local Shipwreck = {}

local LENGTH = 190
local BEAM = 50
local DEPTH = 30 -- keel baseline to the main deck at the sides
local STATIONS = 24
local STRAKES = 9
local PLANK = 1.2
local HOLD_T, GUN_T = 0.18, 0.55
local LIST = math.rad(9) -- roll toward the downslope side
local TRIM = math.rad(1.5)
local SINK = 4 -- how deep the keel sits in the sand

local WOOD = Color3.fromRGB(96, 78, 60)
local WOOD_DARK = Color3.fromRGB(66, 52, 40)
local WOOD_ALGAE = Color3.fromRGB(78, 88, 62)
local SAIL = Color3.fromRGB(196, 186, 160)
local IRON = Color3.fromRGB(46, 48, 52)
local BRASS = Color3.fromRGB(176, 140, 62)
local GLOW = Color3.fromRGB(110, 230, 255)

-- Hull shape -------------------------------------------------------------------------

local function halfBeamAtDeck(s: number): number
	if s < 0.32 then
		return BEAM / 2 * math.sin(s / 0.32 * math.pi / 2) ^ 0.75
	elseif s < 0.72 then
		return BEAM / 2
	end
	return BEAM / 2 * (1 - 0.22 * ((s - 0.72) / 0.28) ^ 2)
end

local function keelY(s: number): number
	return 7 * math.max(0, (0.22 - s) / 0.22) ^ 2 + 3 * math.max(0, (s - 0.86) / 0.14) ^ 2
end

local function deckY(s: number): number
	return DEPTH + 4 * ((s - 0.5) * 2) ^ 2
end

local function stationZ(s: number): number
	return -LENGTH / 2 + s * LENGTH
end

-- Point on the hull surface: station fraction s (0 bow .. 1 stern),
-- strake fraction t (0 keel .. 1 deck edge), side -1 port / +1 starboard.
local function hullPoint(s: number, t: number, side: number): Vector3
	local y = keelY(s) + (deckY(s) - keelY(s)) * t
	local halfWidth = halfBeamAtDeck(s) * t ^ 0.55
	return Vector3.new(side * halfWidth, y, stationZ(s))
end

local function halfWidthAt(s: number, t: number): number
	return halfBeamAtDeck(s) * t ^ 0.55
end

-- Build ------------------------------------------------------------------------------------

function Shipwreck.Build(layout)
	local site = layout:GetAnchor("WreckSite")
	assert(site, "Shipwreck needs the Seabed's wreck terrace")
	local rng = layout:Random("Shipwreck")

	local forward = -site.lengthAxis -- bow direction
	local right = forward:Cross(Vector3.new(0, 1, 0)).Unit
	-- Heel toward whichever side faces downslope.
	local downSide = right:Dot(site.outward) > 0 and 1 or -1
	local baseFrame = CFrame.fromMatrix(site.position - Vector3.new(0, SINK, 0), right, Vector3.new(0, 1, 0), -forward)
	local shipCFrame = baseFrame * CFrame.Angles(TRIM, 0, -downSide * LIST)

	local function toWorld(localPoint: Vector3): Vector3
		return shipCFrame * localPoint
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
	local old = wreckZone:FindFirstChild("Shipwreck")
	if old then
		old:Destroy()
	end
	local root = Instance.new("Model")
	root.Name = "Shipwreck"
	local folders = {}
	for _, name in ipairs({ "Hull", "Decks", "Cabin", "Rigging", "Cargo", "Growth", "Debris", "Lights", "EntryPoints", "SpawnRegions" }) do
		local folder = Instance.new("Folder")
		folder.Name = name
		folder.Parent = root
		folders[name] = folder
	end
	root.Parent = wreckZone
	root:SetAttribute("DisplayName", "La Sirène Noire")

	-- A part placed in ship space.
	local function shipPart(folder: string, name: string, size: Vector3, localFrame: CFrame, material: Enum.Material, color: Color3, collide: boolean?): Part
		local p = Instance.new("Part")
		p.Name = name
		p.Anchored = true
		p.CanTouch = false
		p.CanCollide = collide ~= false
		p.CanQuery = collide ~= false
		p.CastShadow = collide ~= false and size.Magnitude > 6
		p.Size = size
		p.CFrame = shipCFrame * localFrame
		p.Material = material
		p.Color = color
		p.Parent = folders[folder]
		return p
	end

	-- A plank covering a quad of the hull surface.
	local function plankFor(folder: string, name: string, a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color3)
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
		return shipPart(folder, name, Vector3.new(u.Magnitude * 1.06 + 0.3, vPerp.Magnitude * 1.08 + 0.2, PLANK),
			CFrame.fromMatrix(center, uHat, vPerp.Unit), Enum.Material.WoodPlanks, color)
	end

	-- 1. Hull planking, with gunports and the two breaches left open.
	local GUNPORT_STRAKE = math.floor(GUN_T * STRAKES + 0.5)
	local gunports = { [7] = true, [9] = true, [11] = true, [13] = true, [15] = true, [17] = true }
	local function isOpen(side: number, i: number, j: number): boolean
		if side < 0 and i >= 10 and i <= 13 and j >= 1 and j <= 4 then
			return true -- the great breach, port side, into the hold
		end
		if side > 0 and i >= 16 and i <= 17 and j >= 5 and j <= 6 then
			return true -- a smaller hole, starboard, into the gun deck
		end
		return j == GUNPORT_STRAKE and gunports[i] == true
	end
	local hullQuads = {}
	for _, side in ipairs({ -1, 1 }) do
		for i = 0, STATIONS - 1 do
			local s0, s1 = i / STATIONS, (i + 1) / STATIONS
			for j = 0, STRAKES - 1 do
				local t0, t1 = j / STRAKES, (j + 1) / STRAKES
				if not isOpen(side, i, j) then
					-- Weathered strakes: each one its own shade, planks varying a
					-- little along it, algae-green toward the keel.
					local strakeTone = ((j * 37) % 7) / 7
					local base = WOOD:Lerp(WOOD_DARK, strakeTone * 0.6)
					if j < 3 then
						base = base:Lerp(WOOD_ALGAE, 0.75 - j * 0.2)
					end
					local color = base:Lerp(WOOD_DARK, rng:NextNumber() * 0.18)
					local plank = plankFor("Hull", "Plank", hullPoint(s0, t0, side), hullPoint(s1, t0, side), hullPoint(s0, t1, side), hullPoint(s1, t1, side), color)
					if plank then
						table.insert(hullQuads, { plank = plank, side = side, i = i, j = j, s = (s0 + s1) / 2, t = (t0 + t1) / 2 })
					end
				end
			end
		end
	end

	-- Transom (flat stern), one horizontal plank per strake, with a row of
	-- gallery windows left open under the poop deck.
	local sternS = 1
	for j = 0, STRAKES + 3 do
		local t0 = math.min(j / STRAKES, 1)
		local y0 = keelY(sternS) + (deckY(sternS) - keelY(sternS)) * t0
		local halfWidth = halfWidthAt(sternS, math.min(t0 + 1 / STRAKES, 1))
		local y = j <= STRAKES and y0 or deckY(sternS) + (j - STRAKES) * 3.4
		if j <= STRAKES then
			shipPart("Hull", "Transom", Vector3.new(halfWidth * 2, (deckY(sternS) - keelY(sternS)) / STRAKES + 0.3, PLANK), CFrame.new(0, y + 1.6, LENGTH / 2), Enum.Material.WoodPlanks, WOOD_DARK)
		elseif j ~= STRAKES + 2 then
			shipPart("Cabin", "Transom", Vector3.new(halfWidth * 2, 3.5, PLANK), CFrame.new(0, y + 1.7, LENGTH / 2), Enum.Material.WoodPlanks, WOOD_DARK)
		else
			for w = -2, 2 do
				shipPart("Cabin", "WindowMullion", Vector3.new(1, 3.5, PLANK + 0.4), CFrame.new(w * 7, y + 1.7, LENGTH / 2), Enum.Material.Wood, WOOD_DARK)
			end
		end
	end

	-- Ribs showing through the port breach.
	for i = 10, 14 do
		local s = i / STATIONS
		for j = 0, 4 do
			local a = hullPoint(s, j / STRAKES, -1) + Vector3.new(1.4, 0, 0)
			local b = hullPoint(s, (j + 1) / STRAKES, -1) + Vector3.new(1.4, 0, 0)
			local mid, dir = (a + b) / 2, (b - a)
			shipPart("Hull", "Rib", Vector3.new(1.6, dir.Magnitude + 0.6, 1.6), CFrame.lookAt(mid, mid + Vector3.new(0, 0, 1), dir.Unit), Enum.Material.Wood, WOOD_DARK)
		end
	end
	-- Splintered plank ends around the breach.
	for _ = 1, 10 do
		local s = (9.6 + rng:NextNumber() * 4.8) / STATIONS
		local t = (0.6 + rng:NextNumber() * 4) / STRAKES
		local at = hullPoint(s, t, -1)
		shipPart("Hull", "Splinter", Vector3.new(0.9, 0.5, 2 + rng:NextNumber() * 5), CFrame.new(at) * CFrame.Angles(rng:NextNumber() - 0.5, rng:NextNumber() * 3, rng:NextNumber() - 0.5), Enum.Material.WoodPlanks, WOOD, false)
	end

	-- Keel and stem.
	for i = 0, STATIONS - 1 do
		local a, b = hullPoint(i / STATIONS, 0, 1), hullPoint((i + 1) / STATIONS, 0, 1)
		local mid = (a + b) / 2
		shipPart("Hull", "Keel", Vector3.new(2.4, 3, (b - a).Magnitude + 0.4), CFrame.lookAt(mid - Vector3.new(0, 1, 0), mid - Vector3.new(0, 1, 0) + (b - a)), Enum.Material.Wood, WOOD_DARK)
	end
	local stemBottom, stemTop = hullPoint(0, 0, 1), Vector3.new(0, deckY(0) + 6, -LENGTH / 2 - 6)
	shipPart("Hull", "Stem", Vector3.new(2.4, (stemTop - stemBottom).Magnitude, 2.4), CFrame.lookAt((stemBottom + stemTop) / 2, (stemBottom + stemTop) / 2 + Vector3.new(0, 0, -1), (stemTop - stemBottom).Unit), Enum.Material.Wood, WOOD_DARK)

	-- 2. Decks: one slab per station, following the hull's width.
	local function deckSlab(folder: string, name: string, i: number, t: number, lift: number, color: Color3)
		local s0, s1 = i / STATIONS, (i + 1) / STATIONS
		local s = (s0 + s1) / 2
		local y = keelY(s) + (deckY(s) - keelY(s)) * t + lift
		local width = math.min(halfWidthAt(s0, t), halfWidthAt(s1, t)) * 2 - 0.6
		if width > 2 then
			shipPart(folder, name, Vector3.new(width, 1, LENGTH / STATIONS + 0.3), CFrame.new(0, y, stationZ(s)), Enum.Material.WoodPlanks, color)
		end
	end
	for i = 2, STATIONS - 2 do
		deckSlab("Decks", "HoldFloor", i, HOLD_T, 0, WOOD_DARK)
	end
	for i = 2, STATIONS - 1 do
		if i ~= 8 and i ~= 15 then -- two open hatches down into the hold
			deckSlab("Decks", "GunDeck", i, GUN_T, 0, WOOD)
		end
	end
	for i = 1, STATIONS - 1 do
		if not (i >= 11 and i <= 13) and i ~= 5 then -- collapsed around the mainmast, and the main hatch
			deckSlab("Decks", "MainDeck", i, 1, -0.5, WOOD)
		end
	end
	-- Bulwarks along the main deck.
	for _, side in ipairs({ -1, 1 }) do
		for i = 1, STATIONS - 1 do
			local s = (i + 0.5) / STATIONS
			local edge = hullPoint(s, 1, side)
			shipPart("Hull", "Bulwark", Vector3.new(0.8, 3.2, LENGTH / STATIONS + 0.3), CFrame.new(edge + Vector3.new(-side * 0.4, 1.6, 0)), Enum.Material.WoodPlanks, WOOD_DARK)
		end
	end

	-- 3. Captain's cabin under the poop deck (stations 19-23), forecastle.
	local cabinFront = stationZ(19 / STATIONS)
	local cabinDeckY = deckY(0.9)
	local cabinHeight = 12
	for i = 19, STATIONS - 1 do
		local s = (i + 0.5) / STATIONS
		local halfWidth = halfWidthAt(s, 1) - 0.8
		for _, side in ipairs({ -1, 1 }) do
			shipPart("Cabin", "CabinWall", Vector3.new(0.8, cabinHeight, LENGTH / STATIONS + 0.3), CFrame.new(side * halfWidth, cabinDeckY + cabinHeight / 2, stationZ(s)), Enum.Material.WoodPlanks, WOOD)
		end
		deckSlab("Cabin", "PoopDeck", i, 1, cabinHeight, WOOD)
	end
	local frontHalf = halfWidthAt(19 / STATIONS, 1) - 0.8
	for _, side in ipairs({ -1, 1 }) do
		-- Front wall with a doorway in the middle.
		shipPart("Cabin", "CabinFront", Vector3.new(frontHalf - 4, cabinHeight, 0.8), CFrame.new(side * (4 + (frontHalf - 4) / 2), cabinDeckY + cabinHeight / 2, cabinFront), Enum.Material.WoodPlanks, WOOD_DARK)
	end
	shipPart("Cabin", "CabinLintel", Vector3.new(8, 3, 0.8), CFrame.new(0, cabinDeckY + cabinHeight - 1.5, cabinFront), Enum.Material.WoodPlanks, WOOD_DARK)
	local foreHalf = halfWidthAt(3.5 / STATIONS, 1) - 0.8
	for i = 1, 3 do
		deckSlab("Decks", "Forecastle", i, 1, 6, WOOD)
	end
	shipPart("Decks", "ForecastleWall", Vector3.new(foreHalf * 2, 6, 0.8), CFrame.new(0, deckY(4 / STATIONS) + 3, stationZ(4 / STATIONS)), Enum.Material.WoodPlanks, WOOD_DARK)

	-- Cabin furniture: the captain's table, a toppled chair, a chest, a lantern.
	local cabinCenter = Vector3.new(0, cabinDeckY, stationZ(0.9))
	shipPart("Cabin", "Table", Vector3.new(10, 0.8, 6), CFrame.new(cabinCenter + Vector3.new(0, 3.2, 0)) * CFrame.Angles(0, 0.2, 0.05), Enum.Material.Wood, WOOD_DARK)
	for _, corner in ipairs({ { -4, -2.4 }, { 4, -2.4 }, { -4, 2.4 }, { 4, 2.4 } }) do
		shipPart("Cabin", "TableLeg", Vector3.new(0.6, 3, 0.6), CFrame.new(cabinCenter + Vector3.new(corner[1], 1.5, corner[2])), Enum.Material.Wood, WOOD_DARK)
	end
	shipPart("Cabin", "Chair", Vector3.new(2.4, 4, 2.4), CFrame.new(cabinCenter + Vector3.new(6, 1.4, 3)) * CFrame.Angles(math.pi / 2, 0.4, 0), Enum.Material.Wood, WOOD, false)
	shipPart("Cabin", "Chest", Vector3.new(4, 2.6, 2.6), CFrame.new(cabinCenter + Vector3.new(-6, 1.3, 6)) * CFrame.Angles(0, 0.3, 0), Enum.Material.WoodPlanks, Color3.fromRGB(110, 70, 40))
	shipPart("Cabin", "ChestBand", Vector3.new(4.1, 0.4, 2.7), CFrame.new(cabinCenter + Vector3.new(-6, 1.8, 6)) * CFrame.Angles(0, 0.3, 0), Enum.Material.Metal, BRASS, false)
	local lantern = shipPart("Lights", "Lantern", Vector3.new(1.2, 1.8, 1.2), CFrame.new(cabinCenter + Vector3.new(0, cabinHeight - 2.5, -4)), Enum.Material.Neon, Color3.fromRGB(255, 190, 110), false)
	lantern.Transparency = 0.2
	local lanternLight = Instance.new("PointLight")
	lanternLight.Color = Color3.fromRGB(255, 180, 110)
	lanternLight.Range = 22
	lanternLight.Brightness = 1.1
	lanternLight.Shadows = true
	lanternLight.Parent = lantern

	-- 4. Guns: cannons behind every gunport still intact.
	for _, side in ipairs({ -1, 1 }) do
		for i in pairs(gunports) do
			local s = (i + 0.5) / STATIONS
			local deck = keelY(s) + (deckY(s) - keelY(s)) * GUN_T
			local inner = halfWidthAt(s, GUN_T + 0.1) - 6
			if not (side > 0 and i >= 16) then
				shipPart("Cargo", "GunCarriage", Vector3.new(5, 2, 3.5), CFrame.new(side * inner, deck + 1.5, stationZ(s)), Enum.Material.Wood, WOOD_DARK)
				local barrel = shipPart("Cargo", "Cannon", Vector3.new(8, 1.6, 1.6), CFrame.new(side * (inner + 2.5), deck + 3, stationZ(s)), Enum.Material.CorrodedMetal, IRON)
				barrel.Shape = Enum.PartType.Cylinder
			end
		end
	end

	-- 5. Cargo in the hold: crates and barrels, some toppled.
	local holdY = keelY(0.5) + (deckY(0.5) - keelY(0.5)) * HOLD_T + 0.5
	for _ = 1, 22 do
		local s = 0.25 + rng:NextNumber() * 0.5
		local x = (rng:NextNumber() - 0.5) * (halfWidthAt(s, HOLD_T) * 2 - 8)
		local z = stationZ(s)
		if rng:NextNumber() < 0.5 then
			local size = 3.5 + rng:NextNumber() * 2
			shipPart("Cargo", "Crate", Vector3.new(size, size, size), CFrame.new(x, holdY + size / 2, z) * CFrame.Angles(0, rng:NextNumber() * 3, 0), Enum.Material.WoodPlanks, Color3.fromRGB(120, 92, 62))
		else
			local barrel = shipPart("Cargo", "Barrel", Vector3.new(4.2, 3.2, 3.2), CFrame.new(x, holdY + 2.1, z) * CFrame.Angles(0, rng:NextNumber() * 3, rng:NextNumber() < 0.3 and 0 or math.pi / 2), Enum.Material.Wood, Color3.fromRGB(104, 76, 50))
			barrel.Shape = Enum.PartType.Cylinder
		end
	end

	-- 6. Masts, yards, sails, shrouds.
	local function mast(s: number, height: number, brokenAt: number?)
		local deck = deckY(s)
		local base = Vector3.new(0, keelY(s) + 2, stationZ(s))
		local standing = brokenAt or height
		local lower = shipPart("Rigging", "Mast", Vector3.new(standing + deck - base.Y, 3.2, 3.2),
			CFrame.new(base + Vector3.new(0, (standing + deck - base.Y) / 2, 0)) * CFrame.Angles(0, 0, math.pi / 2), Enum.Material.Wood, WOOD)
		lower.Shape = Enum.PartType.Cylinder
		if brokenAt then
			-- A jagged stump.
			shipPart("Rigging", "Splinter", Vector3.new(1.4, 4, 1.2), CFrame.new(0, deck + brokenAt + 1.5, stationZ(s) + 0.6) * CFrame.Angles(0.3, 0, 0.2), Enum.Material.Wood, WOOD, false)
			return nil
		end
		local top = Vector3.new(0, deck + height, stationZ(s))
		shipPart("Rigging", "Top", Vector3.new(9, 0.8, 9), CFrame.new(top - Vector3.new(0, height * 0.38, 0)), Enum.Material.WoodPlanks, WOOD_DARK)
		for k, yardHeight in ipairs({ 0.3, 0.62, 0.9 }) do
			local span = 38 - k * 7
			local yard = shipPart("Rigging", "Yard", Vector3.new(span, 1.4, 1.4), CFrame.new(0, deck + height * yardHeight, stationZ(s) + 1.5) * CFrame.Angles(0, 0.08 * k, 0), Enum.Material.Wood, WOOD)
			yard.Shape = Enum.PartType.Cylinder
			-- Torn sail hanging from the lower two yards, in ragged strips.
			if k < 3 then
				local drop = height * 0.28
				for strip = -2, 2 do
					if rng:NextNumber() > 0.3 then
						local stripDrop = drop * (0.4 + rng:NextNumber() * 0.6)
						local sail = shipPart("Rigging", "Sail", Vector3.new(span / 5 - 0.6, stripDrop, 0.3),
							CFrame.new(strip * span / 5, deck + height * yardHeight - stripDrop / 2, stationZ(s) + 2.4) * CFrame.Angles(0.12 + rng:NextNumber() * 0.15, 0, (rng:NextNumber() - 0.5) * 0.12), Enum.Material.Fabric, SAIL, false)
						sail.Transparency = 0.15
					end
				end
			end
		end
		for _, side in ipairs({ -1, 1 }) do
			for k = -1, 1 do
				local low = hullPoint(s + k * 0.02, 1, side) + Vector3.new(0, 2, 0)
				local high = top - Vector3.new(0, height * 0.38, 0) + Vector3.new(side * 4, 0, 0)
				local mid = (low + high) / 2
				shipPart("Rigging", "Shroud", Vector3.new(0.3, (high - low).Magnitude, 0.3), CFrame.lookAt(mid, mid + Vector3.new(0, 0, 1), (high - low).Unit), Enum.Material.Fabric, Color3.fromRGB(70, 64, 52), false)
			end
		end
		return top
	end
	mast(0.22, 70) -- foremast, still standing
	mast(0.5, 85, 22) -- mainmast, snapped
	mast(0.78, 58, 26) -- mizzen, broken
	-- Bowsprit and figurehead.
	local sprit = shipPart("Rigging", "Bowsprit", Vector3.new(42, 2.2, 2.2), CFrame.new(0, deckY(0) + 12, -LENGTH / 2 - 14) * CFrame.Angles(0, math.pi / 2, 0) * CFrame.Angles(0, 0, math.rad(28)), Enum.Material.Wood, WOOD)
	sprit.Shape = Enum.PartType.Cylinder
	local figure = shipPart("Hull", "Figurehead", Vector3.new(2.6, 6, 2.2), CFrame.new(0, deckY(0) - 2, -LENGTH / 2 - 5) * CFrame.Angles(math.rad(-30), 0, 0), Enum.Material.Metal, BRASS, false)
	local figureMesh = Instance.new("SpecialMesh")
	figureMesh.MeshType = Enum.MeshType.Sphere
	figureMesh.Parent = figure
	shipPart("Hull", "Rudder", Vector3.new(1.4, 24, 8), CFrame.new(0, 12, LENGTH / 2 + 4), Enum.Material.WoodPlanks, WOOD_DARK)

	-- 7. Life: growth on the hull and deck, kelp, seaweed on the yards.
	-- Encrusting life: flat patches hugging the planks (not balls stuck on
	-- them), muted like real growth at depth, thickest low on the hull.
	local GROWTH_COLORS = { Color3.fromRGB(150, 84, 70), Color3.fromRGB(170, 120, 70), Color3.fromRGB(120, 86, 120), Color3.fromRGB(96, 120, 96), Color3.fromRGB(150, 146, 132) }
	local lowQuads = {}
	for _, quad in ipairs(hullQuads) do
		if quad.j <= 4 or rng:NextNumber() < 0.25 then
			table.insert(lowQuads, quad)
		end
	end
	for _ = 1, 90 do
		local quad = lowQuads[rng:NextInteger(1, #lowQuads)]
		local plank = quad.plank
		-- The plank's face normal, flipped to point out of the hull.
		local outward = shipCFrame:VectorToWorldSpace(Vector3.new(quad.side, 0, 0))
		local normal = plank.CFrame.ZVector
		if normal:Dot(outward) < 0 then
			normal = -normal
		end
		local size = 1.5 + rng:NextNumber() * 3.5
		local growth = Instance.new("Part")
		growth.Name = rng:NextNumber() < 0.5 and "Encrustation" or "Sponge"
		growth.Anchored = true
		growth.CanCollide = false
		growth.CanQuery = false
		growth.CanTouch = false
		growth.CastShadow = false
		growth.Material = Enum.Material.Pebble
		growth.Color = GROWTH_COLORS[rng:NextInteger(1, #GROWTH_COLORS)]
		-- Flat along the plank (its Z is the plank's normal).
		growth.Size = Vector3.new(size, size * (0.5 + rng:NextNumber() * 0.5), 0.6 + rng:NextNumber() * 0.8)
		local along = (rng:NextNumber() - 0.5) * plank.Size.X * 0.8
		growth.CFrame = CFrame.lookAt(plank.Position + plank.CFrame.XVector * along + normal * (PLANK / 2), plank.Position + plank.CFrame.XVector * along + normal * 5)
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = growth
		growth.Parent = folders.Growth
	end
	for _ = 1, 16 do
		local s = 0.08 + rng:NextNumber() * 0.7
		if not (s > 11 / STATIONS and s < 14 / STATIONS) then
			local height = 8 + rng:NextNumber() * 12
			local x = (rng:NextNumber() - 0.5) * (halfWidthAt(s, 1) * 2 - 6)
			local kelp = shipPart("Growth", "Kelp", Vector3.new(0.6, height, 0.6), CFrame.new(x, deckY(s) + height / 2, stationZ(s)) * CFrame.Angles((rng:NextNumber() - 0.5) * 0.2, 0, (rng:NextNumber() - 0.5) * 0.2), Enum.Material.Grass, Color3.fromRGB(64, 128, 58), false)
			kelp:SetAttribute("SwayAmplitude", 0.1)
			kelp:SetAttribute("SwaySpeed", 0.5)
			CollectionService:AddTag(kelp, "Sway")
		end
	end

	-- 8. Inner glow: bioluminescent specks in the hold and on the gun deck,
	-- brighter by the breach so it reads as a way in.
	for _ = 1, 26 do
		local s = 0.2 + rng:NextNumber() * 0.6
		local t = rng:NextNumber() < 0.5 and HOLD_T or GUN_T
		local side = rng:NextNumber() < 0.5 and -1 or 1
		local wall = hullPoint(s, t + 0.12, side) + Vector3.new(-side * 1.2, 0, 0)
		local speck = shipPart("Lights", "Bioluminescence", Vector3.new(0.35, 0.35, 0.35), CFrame.new(wall), Enum.Material.Neon, GLOW, false)
		speck.Shape = Enum.PartType.Ball
	end
	local breachCenter = hullPoint(11.5 / STATIONS, 2.5 / STRAKES, -1)
	local breachGlow = shipPart("Lights", "BreachGlow", Vector3.new(0.5, 0.5, 0.5), CFrame.new(breachCenter + Vector3.new(6, 0, 0)), Enum.Material.Neon, GLOW, false)
	breachGlow.Transparency = 1
	local glowLight = Instance.new("PointLight")
	glowLight.Color = GLOW
	glowLight.Range = 30
	glowLight.Brightness = 1
	glowLight.Parent = breachGlow

	-- Entry points (for maps/quests): the breach, the starboard hole, the
	-- collapsed main deck, the cabin door.
	local entries = {
		Breach = breachCenter - Vector3.new(4, 0, 0),
		StarboardHole = hullPoint(17 / STATIONS, 5.5 / STRAKES, 1) + Vector3.new(4, 0, 0),
		CollapsedDeck = Vector3.new(0, deckY(0.5) + 6, stationZ(0.5)),
		CabinDoor = Vector3.new(0, cabinDeckY + 4, cabinFront - 4),
	}
	local entryWorld = {}
	for name, localPoint in pairs(entries) do
		local marker = shipPart("EntryPoints", "EntryPoint_" .. name, Vector3.new(1, 1, 1), CFrame.new(localPoint), Enum.Material.SmoothPlastic, Color3.new(1, 1, 1), false)
		marker.Transparency = 1
		entryWorld[name] = marker.Position
	end

	-- 9. Debris field on the terrace, resting on the real seabed.
	local function onGround(x: number, z: number, lift: number): Vector3
		return Vector3.new(x, layout:GroundHeight(x, z) + lift, z)
	end
	local center = site.position
	local function debrisPart(name: string, size: Vector3, position: Vector3, rotation: CFrame, material: Enum.Material, color: Color3, shape: Enum.PartType?)
		local p = Instance.new("Part")
		p.Name = name
		p.Anchored = true
		p.CanTouch = false
		p.CastShadow = size.Magnitude > 6
		p.Size = size
		p.CFrame = CFrame.new(position) * rotation
		p.Material = material
		p.Color = color
		if shape then
			p.Shape = shape
		end
		p.Parent = folders.Debris
		return p
	end
	-- The mainmast's broken top, lying beside the port side with its yard
	-- and a sail draped over the sand.
	local portSide = shipCFrame.RightVector * -1
	local fallenAt = center + portSide * 58 + forward * 10
	local fallenDir = (forward + portSide * 0.35).Unit
	local fallenBase = onGround(fallenAt.X, fallenAt.Z, 1.4)
	-- (A Cylinder's axis is its X; turning the look frame 90 degrees about Y
	-- lays that axis along fallenDir.)
	debrisPart("FallenMast", Vector3.new(60, 2.8, 2.8), fallenBase, CFrame.lookAt(Vector3.zero, fallenDir) * CFrame.Angles(0, math.pi / 2, 0), Enum.Material.Wood, WOOD, Enum.PartType.Cylinder)
	local yardAt = fallenBase + fallenDir * 18
	debrisPart("FallenYard", Vector3.new(34, 1.4, 1.4), onGround(yardAt.X, yardAt.Z, 1.2), CFrame.lookAt(Vector3.zero, fallenDir:Cross(Vector3.new(0, 1, 0))) * CFrame.Angles(0, math.pi / 2, 0), Enum.Material.Wood, WOOD, Enum.PartType.Cylinder)
	local drape = debrisPart("DrapedSail", Vector3.new(26, 0.3, 18), onGround(yardAt.X + fallenDir.X * 10, yardAt.Z + fallenDir.Z * 10, 0.6), CFrame.lookAt(Vector3.zero, fallenDir) * CFrame.Angles(0.06, 0, 0.05), Enum.Material.Fabric, SAIL)
	drape.CanCollide = false
	-- Anchor, half buried off the bow.
	local anchorAt = onGround(center.X + forward.X * 125 + portSide.X * 20, center.Z + forward.Z * 125 + portSide.Z * 20, 3)
	debrisPart("AnchorShank", Vector3.new(1.4, 14, 1.4), anchorAt, CFrame.Angles(0.4, 0.8, 0.9), Enum.Material.CorrodedMetal, IRON)
	debrisPart("AnchorArms", Vector3.new(10, 1.4, 1.4), anchorAt - Vector3.new(0, 4, 0), CFrame.Angles(0.4, 0.8, 0.2), Enum.Material.CorrodedMetal, IRON)
	-- Scattered cargo.
	for _ = 1, 28 do
		local angle = rng:NextNumber() * math.pi * 2
		local distance = 40 + rng:NextNumber() * 80
		local x = center.X + math.cos(angle) * distance
		local z = center.Z + math.sin(angle) * distance
		local ground = onGround(x, z, 0)
		local localPoint = shipCFrame:PointToObjectSpace(ground)
		if math.abs(localPoint.X) > BEAM / 2 + 6 or math.abs(localPoint.Z) > LENGTH / 2 + 10 then
			local roll = rng:NextNumber()
			if roll < 0.35 then
				local size = 3 + rng:NextNumber() * 2
				debrisPart("Crate", Vector3.new(size, size, size), ground + Vector3.new(0, size * 0.35, 0), CFrame.Angles(rng:NextNumber() * 0.4, rng:NextNumber() * 3, rng:NextNumber() * 0.4), Enum.Material.WoodPlanks, Color3.fromRGB(116, 90, 60))
			elseif roll < 0.65 then
				debrisPart("Barrel", Vector3.new(4.2, 3.2, 3.2), ground + Vector3.new(0, 1.4, 0), CFrame.Angles(0, rng:NextNumber() * 3, 0), Enum.Material.Wood, Color3.fromRGB(100, 74, 50), Enum.PartType.Cylinder)
			elseif roll < 0.8 then
				debrisPart("Cannon", Vector3.new(8, 1.6, 1.6), ground + Vector3.new(0, 0.6, 0), CFrame.Angles(0, rng:NextNumber() * 3, 0.1), Enum.Material.CorrodedMetal, IRON, Enum.PartType.Cylinder)
			else
				debrisPart("Plank", Vector3.new(1, 0.6, 8 + rng:NextNumber() * 10), ground + Vector3.new(0, 0.3, 0), CFrame.Angles(0, rng:NextNumber() * 3, 0.05), Enum.Material.WoodPlanks, WOOD)
			end
		end
	end

	-- 10. Sand banked against the hull: she is sinking into the terrace.
	local terrain = Workspace.Terrain
	for i = 1, STATIONS - 1 do
		local s = i / STATIONS
		for _, side in ipairs({ -1, 1 }) do
			-- Kept outside the planking so no bank spills into the hold.
			local bank = toWorld(Vector3.new(side * (halfWidthAt(s, 0.3) + 9), 2, stationZ(s)))
			terrain:FillBall(Vector3.new(bank.X, layout:GroundHeight(bank.X, bank.Z) + 1, bank.Z), 6 + rng:NextNumber() * 2, Enum.Material.Sand)
		end
	end

	-- 11. Gameplay: loot inside, life around.
	local function region(name: string, localCenter: Vector3, size: Vector3, kind: string, attributes)
		local p = shipPart("SpawnRegions", name, size, CFrame.new(localCenter), Enum.Material.SmoothPlastic, Color3.new(1, 1, 1), false)
		p.Transparency = 1
		p:SetAttribute("RegionKind", kind)
		p:SetAttribute("RegionEnabled", true)
		for key, value in pairs(attributes) do
			p:SetAttribute(key, value)
		end
		CollectionService:AddTag(p, "SpawnRegion")
		return p
	end
	local holdCenterY = keelY(0.5) + (deckY(0.5) - keelY(0.5)) * HOLD_T + 4
	local gunCenterY = keelY(0.5) + (deckY(0.5) - keelY(0.5)) * GUN_T + 4
	region("Loot_Hold", Vector3.new(0, holdCenterY, stationZ(0.5)), Vector3.new(BEAM * 0.5, 4, LENGTH * 0.4), "Treasure", { RegionCount = 5 })
	region("Loot_GunDeck", Vector3.new(0, gunCenterY, stationZ(0.5)), Vector3.new(BEAM * 0.4, 4, LENGTH * 0.45), "Treasure", { RegionCount = 3 })
	region("Loot_CaptainsCabin", Vector3.new(0, cabinDeckY + 3, stationZ(0.9)), Vector3.new(BEAM * 0.45, 3, LENGTH * 0.14), "Treasure", { RegionCount = 4 })
	local creatureRegion = Instance.new("Part")
	creatureRegion.Name = "Creatures_AroundWreck"
	creatureRegion.Anchored = true
	creatureRegion.CanCollide = false
	creatureRegion.CanQuery = false
	creatureRegion.CanTouch = false
	creatureRegion.Transparency = 1
	-- Low over the wreck: the jellyfish only live below 300 m.
	creatureRegion.Size = Vector3.new(LENGTH + 80, 30, LENGTH + 80)
	creatureRegion.CFrame = CFrame.new(center + Vector3.new(0, 22, 0))
	creatureRegion:SetAttribute("RegionKind", "Creature")
	creatureRegion:SetAttribute("RegionEnabled", true)
	creatureRegion:SetAttribute("RegionCount", 6)
	creatureRegion:SetAttribute("RegionSpecies", "RequinRecif,MeduseLumineuse")
	creatureRegion.Parent = folders.SpawnRegions
	CollectionService:AddTag(creatureRegion, "SpawnRegion")

	-- Layout: the ship's volume (hull + standing foremast), and open
	-- water off her stern, downslope, for the Épave vortex.
	local mastTop = deckY(0.22) + 70
	layout:ReserveBox("Shipwreck", shipCFrame * CFrame.new(0, mastTop / 2 - 2, 0), Vector3.new(BEAM + 16, mastTop + 6, LENGTH + 50))
	layout:SetAnchor("WreckCFrame", shipCFrame)
	layout:SetAnchor("WreckEntries", entryWorld)
	local stern = toWorld(Vector3.new(0, 0, LENGTH / 2))
	layout:SetAnchor("WreckVortex", Vector3.new(stern.X, site.position.Y + 34, stern.Z) + site.outward * 70 + forward * -30)

	print(string.format("[Shipwreck] La Sirène Noire: %d parts", #root:GetDescendants()))
end

return Shipwreck
