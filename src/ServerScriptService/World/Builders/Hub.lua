-- The island's hub: a small dive village around the spawn.
--   * Centre de plongée: an open-fronted thatched building on the island's
--     rim with the shop counter (ProximityPrompt "Boutique" -> DiveShop UI),
--     Marius the instructor behind it, racks of tanks, suits on a rail,
--     fins on the wall, lamps on a shelf.
--   * Le Ponton: a boardwalk from the centre out over the lagoon to a
--     diving platform (dive flag, ladder into the water) with the club's
--     dive boat moored alongside, and two bungalows on stilts.
--   * Le Phare: a red-and-white lighthouse on the rim, its lamp turning.
--   * The plaza: a fire pit with log benches, tiki torches along the path,
--     a signpost pointing to every dive site, and the "Meilleurs plongeurs"
--     board (HubLeaderboard keeps it up to date).
-- Everything stands on the real ground (layout:GroundHeight); the stilts go
-- down to the lagoon floor. Each building reserves its volume ("Hub_*") so
-- island life keeps clear, and the palms/rocks the Ocean builder scattered
-- inside those volumes are removed.

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local EquipmentConfig = require(ReplicatedStorage.Shared.Config.EquipmentConfig)

local Hub = {}

local TOP = 4 -- the island's dry sand
local DECK = 5 -- boardwalk and floors
local WOOD = Color3.fromRGB(150, 110, 70)
local WOOD_DARK = Color3.fromRGB(104, 74, 48)
local WOOD_LIGHT = Color3.fromRGB(190, 150, 100)
local THATCH = Color3.fromRGB(206, 176, 112)
local BAMBOO = Color3.fromRGB(186, 170, 100)
local ROPE = Color3.fromRGB(200, 180, 140)
local FLAME = Color3.fromRGB(255, 170, 80)

local CENTER_BEARING = 200
local DOCK_FROM, DOCK_TO = 64, 160

local function dir(bearing: number): Vector3
	local a = math.rad(bearing)
	return Vector3.new(math.cos(a), 0, math.sin(a))
end

function Hub.Build(layout)
	local rng = layout:Random("Hub")
	local function random(): number
		return rng:NextNumber()
	end
	local old = Workspace:FindFirstChild("Hub")
	if old then
		old:Destroy()
	end
	local root = Instance.new("Folder")
	root.Name = "Hub"
	root.Parent = Workspace
	local function folder(name: string): Folder
		local f = Instance.new("Folder")
		f.Name = name
		f.Parent = root
		return f
	end

	local function part(parent: Instance, name: string, size: Vector3, cframe: CFrame, material: Enum.Material, color: Color3, shape: Enum.PartType?, collide: boolean?): Part
		local p = Instance.new("Part")
		p.Name = name
		p.Anchored = true
		p.CanCollide = collide ~= false
		p.CanTouch = false
		p.CastShadow = true
		p.Shape = shape or Enum.PartType.Block
		p.Size = size
		p.CFrame = cframe
		p.Material = material
		p.Color = color
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Parent = parent
		return p
	end
	-- An upright cylinder (Roblox cylinders lie along X).
	local function post(parent: Instance, name: string, diameter: number, bottom: Vector3, height: number, material: Enum.Material, color: Color3): Part
		return part(parent, name, Vector3.new(height, diameter, diameter), CFrame.new(bottom + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, 0, math.pi / 2), material, color, Enum.PartType.Cylinder)
	end
	local function ground(x: number, z: number): number
		return layout:GroundHeight(x, z)
	end
	local function light(parent: BasePart, color: Color3, range: number, brightness: number)
		local l = Instance.new("PointLight")
		l.Color = color
		l.Range = range
		l.Brightness = brightness
		l.Parent = parent
	end
	local function fire(parent: BasePart, size: number)
		local f = Instance.new("Fire")
		f.Size = size
		f.Heat = size * 1.5
		f.Color = Color3.fromRGB(255, 140, 50)
		f.SecondaryColor = Color3.fromRGB(255, 220, 90)
		f.Parent = parent
		light(parent, FLAME, 18, 1.4)
	end
	local function sign(board: BasePart, face: Enum.NormalId, lines: { { text: string, size: number, color: Color3 } }, background: Color3?)
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.PixelsPerStud = 30
		gui.LightInfluence = 0.4
		local frame = Instance.new("Frame")
		frame.Size = UDim2.fromScale(1, 1)
		frame.BackgroundColor3 = background or Color3.fromRGB(40, 28, 18)
		frame.BackgroundTransparency = background and 0 or 1
		frame.Parent = gui
		local layoutList = Instance.new("UIListLayout")
		layoutList.VerticalAlignment = Enum.VerticalAlignment.Center
		layoutList.HorizontalAlignment = Enum.HorizontalAlignment.Center
		layoutList.Parent = frame
		for index, line in ipairs(lines) do
			local label = Instance.new("TextLabel")
			label.Name = "Line" .. index
			label.BackgroundTransparency = 1
			label.Size = UDim2.fromScale(1, line.size)
			label.Font = index == 1 and Enum.Font.GothamBlack or Enum.Font.GothamBold
			label.TextScaled = true
			label.TextColor3 = line.color
			label.Text = line.text
			label.LayoutOrder = index
			label.Parent = frame
		end
		gui.Parent = board
		return gui
	end
	-- A thatched gable roof over a `width` x `depth` footprint whose ridge
	-- runs along the frame's X, `height` above the frame.
	local function roof(parent: Instance, frame: CFrame, width: number, depth: number, height: number, pitch: number)
		local slope = depth / 2 / math.cos(pitch) + 2
		for _, side in ipairs({ -1, 1 }) do
			part(parent, "Thatch", Vector3.new(width + 4, 0.9, slope),
				frame * CFrame.new(0, height + math.tan(pitch) * depth / 4, side * depth / 4) * CFrame.Angles(side * pitch, 0, 0), Enum.Material.Grass, THATCH)
		end
		part(parent, "Ridge", Vector3.new(width + 4, 0.8, 0.8), frame * CFrame.new(0, height + math.tan(pitch) * depth / 2 + 0.2, 0), Enum.Material.Wood, WOOD_DARK)
	end

	local reserved = {}
	local function reserve(name: string, cframe: CFrame, size: Vector3)
		layout:ReserveBox(name, cframe, size)
		table.insert(reserved, { cframe = cframe, half = size / 2 })
	end

	-- Centre de plongée ---------------------------------------------------------------------
	local centerFolder = folder("CentreDePlongee")
	local outward = dir(CENTER_BEARING)
	local centerPos = outward * 48
	local W, D, H = 40, 26, 12
	-- Front (-Z) faces the lagoon.
	local centerFrame = CFrame.lookAt(Vector3.new(centerPos.X, DECK, centerPos.Z), Vector3.new(centerPos.X, DECK, centerPos.Z) + outward)
	part(centerFolder, "Floor", Vector3.new(W, 1, D), centerFrame * CFrame.new(0, -0.5, 0), Enum.Material.WoodPlanks, WOOD_LIGHT)
	for _, x in ipairs({ -W / 2 + 1, 0, W / 2 - 1 }) do
		for _, z in ipairs({ -D / 2 + 1, D / 2 - 1 }) do
			local foot = centerFrame * Vector3.new(x, -1, z)
			post(centerFolder, "Stilt", 1.2, Vector3.new(foot.X, ground(foot.X, foot.Z) - 1, foot.Z), foot.Y - ground(foot.X, foot.Z) + 1, Enum.Material.Wood, WOOD_DARK)
		end
	end
	part(centerFolder, "BackWall", Vector3.new(W, H, 1), centerFrame * CFrame.new(0, H / 2, D / 2 - 0.5), Enum.Material.WoodPlanks, WOOD)
	for _, x in ipairs({ -1, 1 }) do
		part(centerFolder, "SideWall", Vector3.new(1, H, D), centerFrame * CFrame.new(x * (W / 2 - 0.5), H / 2, 0), Enum.Material.WoodPlanks, WOOD)
		part(centerFolder, "Window", Vector3.new(1.2, 4, 8), centerFrame * CFrame.new(x * (W / 2 - 0.5), H * 0.6, 2), Enum.Material.Glass, Color3.fromRGB(150, 210, 230)).Transparency = 0.5
	end
	for _, x in ipairs({ -W / 2 + 0.6, -8, 8, W / 2 - 0.6 }) do
		local foot = centerFrame * Vector3.new(x, 0, -D / 2 + 0.6)
		post(centerFolder, "BambooPost", 1, foot, H, Enum.Material.Wood, BAMBOO)
	end
	roof(centerFolder, centerFrame, W, D, H, math.rad(28))
	local boardFrame = centerFrame * CFrame.new(0, H + 2.5, -D / 2 - 0.8)
	local board = part(centerFolder, "Sign", Vector3.new(30, 5, 0.6), boardFrame, Enum.Material.Wood, WOOD_DARK)
	sign(board, Enum.NormalId.Front, {
		{ text = "CENTRE DE PLONGÉE", size = 0.6, color = Color3.fromRGB(255, 226, 150) },
		{ text = "Bouteilles · Tenues · Palmes · Lampes", size = 0.3, color = Color3.fromRGB(180, 230, 250) },
	})
	-- The counter, where the shop opens.
	local counter = part(centerFolder, "Counter", Vector3.new(22, 3.6, 3), centerFrame * CFrame.new(0, 1.8, -D / 2 + 6), Enum.Material.WoodPlanks, WOOD_DARK)
	part(centerFolder, "CounterTop", Vector3.new(23, 0.4, 3.6), centerFrame * CFrame.new(0, 3.8, -D / 2 + 6), Enum.Material.Wood, WOOD_LIGHT)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "ShopPrompt"
	prompt.ActionText = "Boutique"
	prompt.ObjectText = "Centre de plongée"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("OpensShop", true)
	prompt.Parent = counter
	-- Marius, the instructor, behind the counter.
	local marius = folder("Marius")
	marius.Parent = centerFolder
	local mFrame = centerFrame * CFrame.new(0, 0, -D / 2 + 9.5) * CFrame.Angles(0, math.pi, 0)
	local skin, tee, shorts = Color3.fromRGB(196, 140, 100), Color3.fromRGB(40, 190, 210), Color3.fromRGB(30, 50, 90)
	for _, x in ipairs({ -0.5, 0.5 }) do
		part(marius, "Leg", Vector3.new(1, 2, 1), mFrame * CFrame.new(x, 1, 0), Enum.Material.SmoothPlastic, x < 0 and shorts or shorts)
	end
	part(marius, "Torso", Vector3.new(2, 2, 1), mFrame * CFrame.new(0, 3, 0), Enum.Material.SmoothPlastic, tee)
	for _, x in ipairs({ -1.5, 1.5 }) do
		part(marius, "Arm", Vector3.new(1, 2, 1), mFrame * CFrame.new(x, 3, 0), Enum.Material.SmoothPlastic, skin)
	end
	local head = part(marius, "Head", Vector3.new(1.2, 1.2, 1.2), mFrame * CFrame.new(0, 4.6, 0), Enum.Material.SmoothPlastic, skin, Enum.PartType.Ball)
	part(marius, "Cap", Vector3.new(1.3, 0.35, 1.3), mFrame * CFrame.new(0, 5.15, 0), Enum.Material.Fabric, Color3.fromRGB(230, 60, 60))
	part(marius, "CapVisor", Vector3.new(1.1, 0.12, 0.8), mFrame * CFrame.new(0, 5.02, -0.8), Enum.Material.Fabric, Color3.fromRGB(230, 60, 60))
	for _, x in ipairs({ -0.25, 0.25 }) do
		part(marius, "Eye", Vector3.new(0.15, 0.15, 0.05), mFrame * CFrame.new(x, 4.75, -0.58), Enum.Material.SmoothPlastic, Color3.fromRGB(20, 20, 20))
	end
	part(marius, "Whistle", Vector3.new(0.3, 0.3, 0.3), mFrame * CFrame.new(0.4, 3.4, -0.55), Enum.Material.Metal, Color3.fromRGB(250, 200, 40), Enum.PartType.Ball)
	local tag = Instance.new("BillboardGui")
	tag.Name = "NameTag"
	tag.Size = UDim2.fromOffset(180, 40)
	tag.StudsOffset = Vector3.new(0, 1.8, 0)
	tag.MaxDistance = 60
	local tagLabel = Instance.new("TextLabel")
	tagLabel.Size = UDim2.fromScale(1, 1)
	tagLabel.BackgroundTransparency = 1
	tagLabel.Font = Enum.Font.GothamBold
	tagLabel.TextScaled = true
	tagLabel.TextColor3 = Color3.fromRGB(255, 240, 200)
	tagLabel.TextStrokeTransparency = 0.4
	tagLabel.Text = "Marius · moniteur"
	tagLabel.Parent = tag
	tag.Parent = head
	-- The gear on display, in its real colours.
	local tanks, suits, fins, lamps = {}, {}, {}, {}
	for _, item in ipairs(EquipmentConfig.Items) do
		if item.Category == "Tank" then
			table.insert(tanks, item)
		elseif item.Category == "Suit" and item.Color then
			table.insert(suits, item)
		elseif item.Category == "Fins" and item.Color then
			table.insert(fins, item)
		elseif item.Category == "Lamp" and item.Color then
			table.insert(lamps, item)
		end
	end
	for index, item in ipairs(tanks) do
		local x = -W / 2 + 4 + index * 3.2
		local base = centerFrame * Vector3.new(x, 0, D / 2 - 2.2)
		post(centerFolder, "DisplayTank", 1.3, base, 3.4, Enum.Material.Metal, item.Color)
		post(centerFolder, "DisplayValve", 0.5, base + Vector3.new(0, 3.4, 0), 0.6, Enum.Material.Metal, Color3.fromRGB(190, 190, 196))
	end
	part(centerFolder, "SuitRail", Vector3.new(0.3, 0.3, 14), centerFrame * CFrame.new(W / 2 - 2, 8, 0), Enum.Material.Metal, Color3.fromRGB(170, 170, 176))
	for index, item in ipairs(suits) do
		local z = -6 + index * 3
		part(centerFolder, "DisplaySuit", Vector3.new(0.5, 2.6, 2), centerFrame * CFrame.new(W / 2 - 2, 6.4, z), Enum.Material.SmoothPlastic, item.Color)
		for _, dz in ipairs({ -0.5, 0.5 }) do
			part(centerFolder, "DisplaySuitLeg", Vector3.new(0.5, 2.6, 0.8), centerFrame * CFrame.new(W / 2 - 2, 3.8, z + dz), Enum.Material.SmoothPlastic, item.Color)
		end
		if item.Accent then
			part(centerFolder, "DisplaySuitStripe", Vector3.new(0.55, 2.6, 0.3), centerFrame * CFrame.new(W / 2 - 2, 6.4, z), Enum.Material.SmoothPlastic, item.Accent)
		end
	end
	for index, item in ipairs(fins) do
		for _, dz in ipairs({ -0.7, 0.7 }) do
			part(centerFolder, "DisplayFin", Vector3.new(0.3, 3.2, 1.2), centerFrame * CFrame.new(-W / 2 + 1.2, 5.5, -8 + index * 4 + dz) * CFrame.Angles(0, 0, 0.1), Enum.Material.SmoothPlastic, item.Color)
		end
	end
	part(centerFolder, "LampShelf", Vector3.new(2, 0.4, 12), centerFrame * CFrame.new(-W / 2 + 2, 3, 4), Enum.Material.Wood, WOOD_DARK)
	for index, item in ipairs(lamps) do
		local lampFrame = centerFrame * CFrame.new(-W / 2 + 2, 3.6, index * 3)
		part(centerFolder, "DisplayLamp", Vector3.new(0.8, 0.8, 1.4), lampFrame, Enum.Material.Metal, item.Color)
		part(centerFolder, "DisplayLampLens", Vector3.new(0.6, 0.6, 0.1), lampFrame * CFrame.new(0, 0, 0.72), Enum.Material.Neon, Color3.fromRGB(255, 240, 200))
	end
	local ceilingLamp = part(centerFolder, "CeilingLamp", Vector3.new(1.2, 1.2, 1.2), centerFrame * CFrame.new(0, H - 1, 0), Enum.Material.Neon, Color3.fromRGB(255, 220, 160), Enum.PartType.Ball, false)
	light(ceilingLamp, Color3.fromRGB(255, 220, 160), 30, 1)
	reserve("Hub_DiveCentre", centerFrame * CFrame.new(0, H / 2, 0), Vector3.new(W + 6, H + 12, D + 6))

	-- Le Ponton -----------------------------------------------------------------------------
	local dock = folder("Ponton")
	local dockStart, dockEnd = outward * DOCK_FROM, outward * DOCK_TO
	local side = Vector3.new(-outward.Z, 0, outward.X)
	local length = DOCK_TO - DOCK_FROM
	for k = 0, math.floor(length / 2) - 1 do
		local p = dockStart + outward * (k * 2 + 1)
		part(dock, "DeckPlank", Vector3.new(8, 0.5, 1.9), CFrame.lookAt(Vector3.new(p.X, DECK - 0.25, p.Z), Vector3.new(p.X, DECK - 0.25, p.Z) + outward) * CFrame.Angles(0, 0, (random() - 0.5) * 0.02),
			Enum.Material.WoodPlanks, WOOD:Lerp(WOOD_LIGHT, random() * 0.6))
	end
	for k = 0, math.floor(length / 8) do
		for _, s in ipairs({ -1, 1 }) do
			local p = dockStart + outward * (k * 8) + side * (s * 3.6)
			local g = ground(p.X, p.Z)
			post(dock, "Piling", 1.1, Vector3.new(p.X, g - 1, p.Z), DECK + 3.5 - g, Enum.Material.Wood, WOOD_DARK)
			if k % 2 == 0 then
				local lantern = part(dock, "Lantern", Vector3.new(0.8, 1, 0.8), CFrame.new(p.X, DECK + 4, p.Z), Enum.Material.Neon, FLAME, nil, false)
				light(lantern, FLAME, 14, 0.8)
			end
		end
	end
	for _, s in ipairs({ -1, 1 }) do
		local a, b = dockStart + side * (s * 3.6), dockEnd + side * (s * 3.6)
		part(dock, "Rope", Vector3.new(0.25, 0.25, (b - a).Magnitude), CFrame.lookAt((a + b) / 2 + Vector3.new(0, DECK + 2.6, 0), b + Vector3.new(0, DECK + 2.6, 0)), Enum.Material.Fabric, ROPE, nil, false)
	end
	-- The diving platform at the end.
	local platformFrame = CFrame.lookAt(Vector3.new(dockEnd.X, DECK - 0.4, dockEnd.Z), Vector3.new(dockEnd.X, DECK - 0.4, dockEnd.Z) + outward)
	part(dock, "Platform", Vector3.new(26, 0.8, 18), platformFrame * CFrame.new(0, 0, -6), Enum.Material.WoodPlanks, WOOD_LIGHT)
	for _, x in ipairs({ -12, 12 }) do
		for _, z in ipairs({ -14, 2 }) do
			local foot = platformFrame * Vector3.new(x, 0, z)
			local g = ground(foot.X, foot.Z)
			post(dock, "Piling", 1.3, Vector3.new(foot.X, g - 1, foot.Z), DECK - g + 1, Enum.Material.Wood, WOOD_DARK)
		end
	end
	-- The "diver down" flag: red with a white diagonal.
	post(dock, "FlagPole", 0.4, platformFrame * Vector3.new(11, 0, -13), 12, Enum.Material.Metal, Color3.fromRGB(220, 220, 220))
	local flag = part(dock, "DiveFlag", Vector3.new(4.5, 3, 0.1), platformFrame * CFrame.new(8.6, 10.2, -13), Enum.Material.Fabric, Color3.fromRGB(220, 30, 40), nil, false)
	part(dock, "DiveFlagStripe", Vector3.new(5.3, 0.6, 0.12), flag.CFrame * CFrame.Angles(0, 0, math.atan2(3, 4.5)), Enum.Material.Fabric, Color3.fromRGB(250, 250, 250), nil, false)
	-- A ladder down into the lagoon.
	local ladderTop = platformFrame * CFrame.new(0, 0, -15.2)
	for _, x in ipairs({ -1.2, 1.2 }) do
		part(dock, "LadderRail", Vector3.new(0.3, 9, 0.3), ladderTop * CFrame.new(x, -3.5, 0), Enum.Material.Metal, Color3.fromRGB(200, 200, 206))
	end
	for k = 0, 6 do
		part(dock, "LadderRung", Vector3.new(2.4, 0.25, 0.25), ladderTop * CFrame.new(0, 0.5 - k * 1.2, 0), Enum.Material.Metal, Color3.fromRGB(200, 200, 206))
	end
	-- The club's dive boat, moored alongside.
	local boat = folder("BateauDePlongee")
	boat.Parent = dock
	local boatFrame = platformFrame * CFrame.new(20, -5.4, -6) -- hull bottom a little under the surface
	local hullWhite, stripe = Color3.fromRGB(240, 240, 236), Color3.fromRGB(30, 110, 200)
	part(boat, "HullBottom", Vector3.new(8, 1.5, 24), boatFrame * CFrame.new(0, 0.75, 0), Enum.Material.SmoothPlastic, hullWhite)
	for _, x in ipairs({ -1, 1 }) do
		part(boat, "HullSide", Vector3.new(0.8, 3.4, 22), boatFrame * CFrame.new(x * 4.4, 2.4, 1), Enum.Material.SmoothPlastic, hullWhite)
		part(boat, "HullStripe", Vector3.new(0.9, 0.6, 22), boatFrame * CFrame.new(x * 4.4, 3.2, 1), Enum.Material.SmoothPlastic, stripe)
		part(boat, "Bow", Vector3.new(0.8, 3.4, 7), boatFrame * CFrame.new(x * 2.3, 2.4, -12.2) * CFrame.Angles(0, -x * 0.62, 0), Enum.Material.SmoothPlastic, hullWhite)
		part(boat, "Tube", Vector3.new(22, 1.6, 1.6), boatFrame * CFrame.new(x * 5.1, 3.4, 1) * CFrame.Angles(0, math.pi / 2, 0), Enum.Material.SmoothPlastic, Color3.fromRGB(40, 44, 52), Enum.PartType.Cylinder)
	end
	part(boat, "Deck", Vector3.new(8, 0.4, 22), boatFrame * CFrame.new(0, 1.7, 1), Enum.Material.WoodPlanks, WOOD_LIGHT)
	part(boat, "Console", Vector3.new(3, 3, 2.4), boatFrame * CFrame.new(0, 3.4, -3), Enum.Material.SmoothPlastic, hullWhite)
	part(boat, "Windscreen", Vector3.new(3, 1.4, 0.2), boatFrame * CFrame.new(0, 5.6, -4), Enum.Material.Glass, Color3.fromRGB(170, 220, 240)).Transparency = 0.5
	part(boat, "Bimini", Vector3.new(7, 0.2, 7), boatFrame * CFrame.new(0, 8.4, -1), Enum.Material.Fabric, stripe)
	for _, x in ipairs({ -3.2, 3.2 }) do
		part(boat, "BiminiPole", Vector3.new(0.2, 6.6, 0.2), boatFrame * CFrame.new(x, 5.1, -1), Enum.Material.Metal, Color3.fromRGB(200, 200, 206))
	end
	part(boat, "Outboard", Vector3.new(1.6, 4.4, 1.6), boatFrame * CFrame.new(0, 2.4, 12.4), Enum.Material.SmoothPlastic, Color3.fromRGB(30, 30, 34))
	for index = 1, 4 do
		local item = tanks[math.min(index, #tanks)]
		post(boat, "BoatTank", 1.1, boatFrame * Vector3.new(-2.6 + (index - 1) * 1.7, 1.9, 7), 3, Enum.Material.Metal, item.Color)
	end
	reserve("Hub_Dock", CFrame.lookAt((dockStart + dockEnd) / 2 + Vector3.new(0, DECK, 0), dockEnd + Vector3.new(0, DECK, 0)), Vector3.new(14, 14, length + 30))

	-- Bungalows on stilts, off the boardwalk.
	for index, s in ipairs({ -1, 1 }) do
		local joint = dockStart + outward * 46
		local hutCenter = joint + side * (s * 20)
		local hutFrame = CFrame.lookAt(Vector3.new(hutCenter.X, DECK, hutCenter.Z), Vector3.new(joint.X, DECK, joint.Z))
		local hut = folder("Bungalow" .. index)
		part(hut, "Walkway", Vector3.new(4, 0.5, 10), CFrame.lookAt((joint + hutCenter) / 2 + Vector3.new(0, DECK - 0.25, 0), hutCenter + Vector3.new(0, DECK - 0.25, 0)), Enum.Material.WoodPlanks, WOOD)
		part(hut, "Floor", Vector3.new(14, 0.8, 14), hutFrame * CFrame.new(0, -0.4, 0), Enum.Material.WoodPlanks, WOOD_LIGHT)
		for _, x in ipairs({ -6, 6 }) do
			for _, z in ipairs({ -6, 6 }) do
				local foot = hutFrame * Vector3.new(x, 0, z)
				local g = ground(foot.X, foot.Z)
				post(hut, "Stilt", 1, Vector3.new(foot.X, g - 1, foot.Z), DECK - g + 1, Enum.Material.Wood, WOOD_DARK)
			end
		end
		part(hut, "BackWall", Vector3.new(12, 8, 0.8), hutFrame * CFrame.new(0, 4, 5.6), Enum.Material.WoodPlanks, WOOD)
		for _, x in ipairs({ -1, 1 }) do
			part(hut, "SideWall", Vector3.new(0.8, 8, 12), hutFrame * CFrame.new(x * 5.6, 4, 0), Enum.Material.WoodPlanks, WOOD)
			part(hut, "FrontWall", Vector3.new(3.6, 8, 0.8), hutFrame * CFrame.new(x * 3.9, 4, -5.6), Enum.Material.WoodPlanks, WOOD)
		end
		part(hut, "Lintel", Vector3.new(4.2, 2, 0.8), hutFrame * CFrame.new(0, 7, -5.6), Enum.Material.WoodPlanks, WOOD)
		roof(hut, hutFrame, 12, 12, 8, math.rad(32))
		local hammock = part(hut, "Hammock", Vector3.new(2, 0.3, 6), hutFrame * CFrame.new(-8.5, 1.2, 0), Enum.Material.Fabric, Color3.fromRGB(230, 90, 60), nil, false)
		hammock.CFrame = hammock.CFrame * CFrame.Angles(0.08, 0, 0)
		reserve("Hub_Bungalow" .. index, hutFrame * CFrame.new(0, 6, 0), Vector3.new(18, 18, 18))
	end

	-- Le Phare ------------------------------------------------------------------------------
	local lighthouse = folder("Phare")
	local lhPos = dir(20) * 56
	local lhBase = Vector3.new(lhPos.X, ground(lhPos.X, lhPos.Z) - 0.5, lhPos.Z)
	post(lighthouse, "Base", 14, lhBase, 3, Enum.Material.Slate, Color3.fromRGB(120, 120, 124))
	local y = lhBase.Y + 3
	for k = 0, 7 do
		local diameter = 11 - k * 0.45
		post(lighthouse, "Tower", diameter, Vector3.new(lhBase.X, y, lhBase.Z), 4.5, Enum.Material.SmoothPlastic, k % 2 == 0 and Color3.fromRGB(245, 245, 240) or Color3.fromRGB(210, 40, 40))
		y += 4.5
	end
	post(lighthouse, "Gallery", 10.5, Vector3.new(lhBase.X, y, lhBase.Z), 0.6, Enum.Material.Metal, Color3.fromRGB(40, 40, 44))
	for k = 0, 11 do
		local a = k / 12 * math.pi * 2
		part(lighthouse, "Railing", Vector3.new(0.2, 2, 0.2), CFrame.new(lhBase.X + math.cos(a) * 5, y + 1.6, lhBase.Z + math.sin(a) * 5), Enum.Material.Metal, Color3.fromRGB(40, 40, 44))
	end
	local lanternRoom = post(lighthouse, "LanternGlass", 5.6, Vector3.new(lhBase.X, y + 0.6, lhBase.Z), 5, Enum.Material.Glass, Color3.fromRGB(200, 230, 240))
	lanternRoom.Transparency = 0.55
	local lamp = part(lighthouse, "Lamp", Vector3.new(2.4, 2.4, 2.4), CFrame.new(lhBase.X, y + 3, lhBase.Z), Enum.Material.Neon, Color3.fromRGB(255, 240, 180), Enum.PartType.Ball, false)
	light(lamp, Color3.fromRGB(255, 240, 180), 40, 2)
	local beam = Instance.new("SpotLight")
	beam.Range = 60
	beam.Brightness = 4
	beam.Angle = 25
	beam.Face = Enum.NormalId.Front
	beam.Parent = lamp
	lamp:SetAttribute("SpinSpeed", 0.9)
	CollectionService:AddTag(lamp, "Spin")
	local roofCap = part(lighthouse, "Roof", Vector3.new(6.4, 3.6, 6.4), CFrame.new(lhBase.X, y + 7, lhBase.Z), Enum.Material.SmoothPlastic, Color3.fromRGB(190, 30, 30))
	local capMesh = Instance.new("SpecialMesh")
	capMesh.MeshType = Enum.MeshType.Sphere
	capMesh.Parent = roofCap
	part(lighthouse, "Door", Vector3.new(0.4, 5, 3), CFrame.lookAt(lhBase + Vector3.new(0, 5.5, 0) - dir(20) * 5.2, lhBase + Vector3.new(0, 5.5, 0) - dir(20) * 10) * CFrame.Angles(0, math.pi / 2, 0), Enum.Material.Wood, WOOD_DARK)
	reserve("Hub_Lighthouse", CFrame.new(lhBase + Vector3.new(0, 25, 0)), Vector3.new(16, 52, 16))

	-- The plaza ------------------------------------------------------------------------------
	local plaza = folder("Place")
	local pitCenter = dir(20) * 22
	local pit = Vector3.new(pitCenter.X, TOP, pitCenter.Z)
	for k = 0, 9 do
		local a = k / 10 * math.pi * 2
		part(plaza, "PitStone", Vector3.new(1.4, 1, 1.2), CFrame.new(pit + Vector3.new(math.cos(a) * 2.6, 0.4, math.sin(a) * 2.6)) * CFrame.Angles(0, a, 0), Enum.Material.Slate, Color3.fromRGB(110, 110, 112))
	end
	local embers = part(plaza, "Embers", Vector3.new(3, 0.6, 3), CFrame.new(pit + Vector3.new(0, 0.3, 0)), Enum.Material.Neon, Color3.fromRGB(255, 110, 40), nil, false)
	fire(embers, 5)
	for k = 0, 3 do
		local a = k / 4 * math.pi * 2 + 0.4
		local seat = pit + Vector3.new(math.cos(a) * 7, 0.7, math.sin(a) * 7)
		part(plaza, "LogBench", Vector3.new(7, 1.4, 1.4), CFrame.lookAt(seat, pit + Vector3.new(0, 0.7, 0)) * CFrame.Angles(0, math.pi / 2, 0), Enum.Material.Wood, WOOD_DARK, Enum.PartType.Cylinder)
	end
	-- Tiki torches along the path to the dive centre.
	for k = 1, 4 do
		for _, s in ipairs({ -1, 1 }) do
			local p = outward * (8 + k * 7) + Vector3.new(-outward.Z, 0, outward.X) * (s * 4.5)
			local base = Vector3.new(p.X, ground(p.X, p.Z), p.Z)
			post(plaza, "TikiPole", 0.5, base, 5, Enum.Material.Wood, BAMBOO)
			local torchHead = part(plaza, "TikiHead", Vector3.new(1, 1.2, 1), CFrame.new(base + Vector3.new(0, 5.6, 0)), Enum.Material.Wood, WOOD_DARK)
			fire(torchHead, 1.4)
		end
	end
	-- Signpost: one board per dive site, pointing at it.
	local signBase = dir(110) * 16
	local signFoot = Vector3.new(signBase.X, ground(signBase.X, signBase.Z), signBase.Z)
	post(plaza, "SignPost", 0.7, signFoot, 11, Enum.Material.Wood, WOOD_DARK)
	local destinations = {}
	local caves = layout:GetAnchor("Caves")
	if caves then
		for _, entrance in ipairs(caves.entrances) do
			if entrance.id == "TrouBleu" then
				table.insert(destinations, { "⛰ Trou Bleu · grottes", entrance.mouth })
			end
		end
	end
	local site = layout:GetAnchor("WreckSite")
	if site then
		table.insert(destinations, { "⚓ La Sirène Noire", site.position })
	end
	local liner = layout:GetAnchor("Liner")
	if liner then
		table.insert(destinations, { "🚢 L'Impératrice", liner.center })
	end
	table.insert(destinations, { "🌿 Forêt de kelp", dir(265) * 265 })
	local rift = layout:GetAnchor("RiftFrame")
	if rift then
		table.insert(destinations, { "🔥 Faille abyssale", rift.center })
	end
	for index, destination in ipairs(destinations) do
		local target = destination[2]
		local flat = Vector3.new(target.X - signFoot.X, 0, target.Z - signFoot.Z)
		local distance = flat.Magnitude
		local heading = flat.Unit
		local boardY = signFoot.Y + 10.5 - index * 1.7
		local signBoard = part(plaza, "SignBoard", Vector3.new(7, 1.4, 0.3),
			CFrame.lookAt(Vector3.new(signFoot.X, boardY, signFoot.Z) + heading * 3.4, Vector3.new(signFoot.X, boardY, signFoot.Z) + heading * 3.4 + Vector3.new(-heading.Z, 0, heading.X)),
			Enum.Material.Wood, WOOD_LIGHT)
		for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
			sign(signBoard, face, {
				{ text = destination[1], size = 0.62, color = Color3.fromRGB(60, 36, 20) },
				{ text = string.format("%d m", math.floor(distance + 0.5)), size = 0.36, color = Color3.fromRGB(110, 70, 40) },
			})
		end
	end
	-- The "Meilleurs plongeurs" board (rows filled by HubLeaderboard).
	local lbPos = dir(290) * 26
	local lbFoot = Vector3.new(lbPos.X, ground(lbPos.X, lbPos.Z), lbPos.Z)
	local lbFrame = CFrame.lookAt(lbFoot + Vector3.new(0, 6.5, 0), Vector3.new(0, lbFoot.Y + 6.5, 0))
	for _, x in ipairs({ -6.5, 6.5 }) do
		local foot = lbFrame * Vector3.new(x, -6.5, 0.4)
		post(plaza, "BoardLeg", 0.6, Vector3.new(foot.X, lbFoot.Y, foot.Z), 12, Enum.Material.Wood, WOOD_DARK)
	end
	local leaderboard = part(plaza, "Leaderboard", Vector3.new(14, 9, 0.5), lbFrame, Enum.Material.Wood, WOOD_DARK)
	local lines = { { text = "MEILLEURS PLONGEURS", size = 0.2, color = Color3.fromRGB(255, 220, 130) } }
	for k = 1, 5 do
		table.insert(lines, { text = k == 1 and "En attente de plongeurs..." or "", size = 0.14, color = Color3.fromRGB(230, 240, 245) })
	end
	local lbGui = sign(leaderboard, Enum.NormalId.Front, lines, Color3.fromRGB(20, 36, 48))
	lbGui.Name = "LeaderboardGui"
	CollectionService:AddTag(leaderboard, "HubLeaderboard")

	-- Clear what the beach builder scattered inside the new buildings.
	local props = Workspace:FindFirstChild("BeachProps")
	if props then
		for _, p in ipairs(props:GetChildren()) do
			if p:IsA("BasePart") then
				for _, box in ipairs(reserved) do
					local l = box.cframe:PointToObjectSpace(p.Position)
					if math.abs(l.X) < box.half.X + 2 and math.abs(l.Y) < box.half.Y + 2 and math.abs(l.Z) < box.half.Z + 2 then
						p:Destroy()
						break
					end
				end
			end
		end
	end

	layout:SetAnchor("Hub", { diveCentre = centerFrame, dockEnd = dockEnd, platform = platformFrame, lighthouse = lhBase, plaza = pit, leaderboard = leaderboard, shopPrompt = prompt })
	print(string.format("[Hub] %d parts", #root:GetDescendants()))
end

return Hub
