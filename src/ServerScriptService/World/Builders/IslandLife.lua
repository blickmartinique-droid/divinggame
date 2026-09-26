-- Life on the island itself, around the hub:
--   * flora: curved coconut palms with coconuts and drooping fronds,
--     banana plants, ferns, hibiscus and bird-of-paradise flowers, tall
--     grass, mossy rocks; shells, starfish, driftwood and coconuts on the
--     sand; a parasol and deckchairs by the plaza;
--   * fauna (models placed here, animated by IslandCritters on each
--     client): crabs and hermit crabs scuttling on the beach, seagulls
--     circling, butterflies around the flowers, parrots perched on palms,
--     dolphins leaping in the lagoon.
-- Plants keep clear of the hub's buildings (its reserved "Hub_*" boxes)
-- and stand on the real ground.

local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")

local MarineFlora = require(script.Parent.MarineFlora)

local IslandLife = {}

local LAND = 3 -- the dry island is above this height

function IslandLife.Build(layout)
	local rng = layout:Random("IslandLife")
	local kit = MarineFlora.new(layout:Random("IslandFronds"))
	local function random(): number
		return rng:NextNumber()
	end
	local old = Workspace:FindFirstChild("IslandLife")
	if old then
		old:Destroy()
	end
	local root = Instance.new("Folder")
	root.Name = "IslandLife"
	root.Parent = Workspace
	local function folder(name: string): Folder
		local f = Instance.new("Folder")
		f.Name = name
		f.Parent = root
		return f
	end
	local flora, beach, fauna = folder("Flora"), folder("Beach"), folder("Fauna")

	local function part(parent: Instance, name: string, size: Vector3, cframe: CFrame, material: Enum.Material, color: Color3, shape: Enum.PartType?): Part
		local p = Instance.new("Part")
		p.Name = name
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = size.Magnitude > 3
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
	local function groundAt(x: number, z: number): Vector3
		return Vector3.new(x, layout:GroundHeight(x, z), z)
	end
	-- Clear of the hub's buildings (the whole island is the reserved
	-- "Beach" volume, so layout:IsFree cannot tell).
	local function clearOfHub(p: Vector3, margin: number): boolean
		for _, volume in ipairs(layout.reserved) do
			if volume.kind == "box" and (volume.name:match("^Hub_") or volume.name:match("^Island_")) then
				local l = volume.cframe:PointToObjectSpace(p)
				if math.abs(l.X) < volume.half.X + margin and math.abs(l.Y) < volume.half.Y + margin and math.abs(l.Z) < volume.half.Z + margin then
					return false
				end
			end
		end
		-- The spawn pad in the middle stays open.
		return Vector3.new(p.X, 0, p.Z).Magnitude > 9
	end
	-- A free spot on dry land between two radii.
	local function landSpot(minRadius: number, maxRadius: number, margin: number): Vector3?
		for _ = 1, 20 do
			local a = random() * math.pi * 2
			local r = minRadius + random() * (maxRadius - minRadius)
			local p = groundAt(math.cos(a) * r, math.sin(a) * r)
			if p.Y >= LAND and clearOfHub(p + Vector3.new(0, 2, 0), margin) then
				return p
			end
		end
		return nil
	end

	-- Palms -----------------------------------------------------------------------------------
	local palmTops = {}
	local FROND = { Color3.fromRGB(64, 150, 60), Color3.fromRGB(86, 168, 64), Color3.fromRGB(52, 132, 58) }
	for _ = 1, 16 do
		local base = landSpot(14, 64, 3)
		if base then
			local height = 12 + random() * 8
			local heading = random() * math.pi * 2
			local lean = 0.12 + random() * 0.18
			-- A trunk that curves: five segments, each a little more bent.
			local frame = CFrame.new(base) * CFrame.Angles(0, heading, 0)
			local segment = height / 5
			for k = 1, 5 do
				frame = frame * CFrame.Angles(lean * (0.4 + k * 0.15), 0, 0)
				local p = part(flora, "PalmTrunk", Vector3.new(segment + 0.3, 1.3 - k * 0.08, 1.3 - k * 0.08), frame * CFrame.new(0, segment / 2, 0) * CFrame.Angles(0, 0, math.pi / 2), Enum.Material.Wood, Color3.fromRGB(140 - k * 6, 106 - k * 4, 70))
				p.Shape = Enum.PartType.Cylinder
				-- Rings on the trunk.
				part(flora, "PalmRing", Vector3.new(0.25, 1.45 - k * 0.08, 1.45 - k * 0.08), frame * CFrame.new(0, segment * 0.9, 0) * CFrame.Angles(0, 0, math.pi / 2), Enum.Material.Wood, Color3.fromRGB(110, 82, 56), Enum.PartType.Cylinder)
				frame = frame * CFrame.new(0, segment, 0)
			end
			local crown = frame
			for c = 1, 4 do
				part(flora, "Coconut", Vector3.new(0.9, 0.9, 0.9), crown * CFrame.new(math.cos(c * 1.6) * 0.6, -0.5, math.sin(c * 1.6) * 0.6), Enum.Material.Wood, Color3.fromRGB(96, 70, 40), Enum.PartType.Ball)
			end
			-- Fronds: leaflets along an arching midrib (MarineFlora), a
			-- ring of eight and a young spear standing in the middle.
			local fronds = 8
			for f = 1, fronds do
				kit:PalmFrond(flora, crown, f / fronds * math.pi * 2 + random() * 0.3, 7 + random() * 3, FROND[rng:NextInteger(1, #FROND)])
			end
			part(flora, "PalmSpear", Vector3.new(0.3, 2.6, 0.3), crown * CFrame.new(0, 1.2, 0), Enum.Material.Grass, Color3.fromRGB(120, 170, 80))
			part(flora, "PalmHeart", Vector3.new(1.5, 1, 1.5), crown * CFrame.new(0, 0.1, 0), Enum.Material.Wood, Color3.fromRGB(110, 90, 60), Enum.PartType.Ball)
			table.insert(palmTops, crown)
		end
	end

	-- Undergrowth and flowers ---------------------------------------------------------------------
	local flowers = {}
	for _ = 1, 70 do
		local p = landSpot(6, 62, 1.5)
		if p then
			local roll = random()
			local yaw = CFrame.Angles(0, random() * math.pi * 2, 0)
			if roll < 0.2 then
				-- Banana plant: a short trunk and big paddle leaves.
				part(flora, "BananaStem", Vector3.new(4, 0.9, 0.9), CFrame.new(p + Vector3.new(0, 2, 0)) * CFrame.Angles(0, 0, math.pi / 2), Enum.Material.Grass, Color3.fromRGB(110, 150, 70), Enum.PartType.Cylinder)
				for k = 1, 5 do
					local leaf = ellipsoid(flora, "BananaLeaf", Vector3.new(1.8, 0.15, 6), CFrame.new(p + Vector3.new(0, 4, 0)) * yaw * CFrame.Angles(0, k * 1.26, 0) * CFrame.Angles(math.rad(-30), 0, 0) * CFrame.new(0, 0, -2.8), Enum.Material.Grass, Color3.fromRGB(70, 160, 70))
					sway(leaf, 0.06, 0.4)
				end
			elseif roll < 0.42 then
				-- Fern: a rosette of arching fronds.
				for k = 1, 7 do
					local leaf = part(flora, "Fern", Vector3.new(0.5, 0.08, 2.6), CFrame.new(p + Vector3.new(0, 0.6, 0)) * yaw * CFrame.Angles(0, k * 0.9, 0) * CFrame.Angles(math.rad(-35), 0, 0) * CFrame.new(0, 0, -1.2), Enum.Material.Grass, Color3.fromRGB(50, 130 + rng:NextInteger(0, 30), 60))
					sway(leaf, 0.08, 0.6)
				end
			elseif roll < 0.62 then
				-- Hibiscus bush with big red or pink flowers.
				local size = 2.4 + random() * 1.5
				ellipsoid(flora, "HibiscusBush", Vector3.new(size, size * 0.8, size), CFrame.new(p + Vector3.new(0, size * 0.35, 0)), Enum.Material.Grass, Color3.fromRGB(46, 120, 52))
				local color = random() < 0.5 and Color3.fromRGB(230, 40, 60) or Color3.fromRGB(250, 120, 170)
				for k = 1, 5 do
					local a = k * 1.25 + random()
					local at = p + Vector3.new(math.cos(a) * size * 0.45, size * 0.55 + random() * 0.4, math.sin(a) * size * 0.45)
					for petal = 1, 5 do
						ellipsoid(flora, "Petal", Vector3.new(0.5, 0.08, 0.3), CFrame.new(at) * CFrame.Angles(0, petal * 1.26, 0.3) * CFrame.new(0.25, 0, 0), Enum.Material.SmoothPlastic, color)
					end
					part(flora, "Pistil", Vector3.new(0.12, 0.12, 0.12), CFrame.new(at + Vector3.new(0, 0.1, 0)), Enum.Material.Neon, Color3.fromRGB(255, 220, 80), Enum.PartType.Ball)
					table.insert(flowers, at)
				end
			elseif roll < 0.72 then
				-- Bird of paradise: orange and blue crests on green stalks.
				for k = 1, 3 do
					local stalk = p + Vector3.new(random() * 1.2 - 0.6, 0, random() * 1.2 - 0.6)
					local h = 2.4 + random()
					part(flora, "ParadiseStalk", Vector3.new(0.18, h, 0.18), CFrame.new(stalk + Vector3.new(0, h / 2, 0)), Enum.Material.Grass, Color3.fromRGB(70, 130, 70))
					local head = CFrame.new(stalk + Vector3.new(0, h, 0)) * CFrame.Angles(0, random() * 6, 0)
					part(flora, "ParadiseCrest", Vector3.new(0.12, 0.7, 0.5), head * CFrame.new(0, 0.3, 0) * CFrame.Angles(0.4, 0, 0), Enum.Material.SmoothPlastic, Color3.fromRGB(255, 140, 20))
					part(flora, "ParadiseCrest", Vector3.new(0.12, 0.5, 0.4), head * CFrame.new(0, 0.3, 0.2) * CFrame.Angles(-0.2, 0, 0), Enum.Material.SmoothPlastic, Color3.fromRGB(60, 80, 220))
					part(flora, "ParadiseBeak", Vector3.new(0.2, 0.2, 1), head * CFrame.new(0, 0, -0.3), Enum.Material.SmoothPlastic, Color3.fromRGB(80, 110, 60))
					table.insert(flowers, stalk + Vector3.new(0, h, 0))
				end
			elseif roll < 0.9 then
				-- Tall grass tuft.
				for k = 1, 6 do
					local blade = part(flora, "GrassBlade", Vector3.new(0.15, 1.6 + random(), 0.15), CFrame.new(p + Vector3.new(random() - 0.5, 0.9, random() - 0.5)) * CFrame.Angles(random() * 0.4 - 0.2, 0, random() * 0.4 - 0.2), Enum.Material.Grass, Color3.fromRGB(110 + rng:NextInteger(0, 40), 170, 70))
					sway(blade, 0.12, 0.7 + k * 0.05)
				end
			else
				-- Mossy rock.
				local size = 1.6 + random() * 2.4
				ellipsoid(flora, "Rock", Vector3.new(size * 1.3, size * 0.7, size), CFrame.new(p + Vector3.new(0, size * 0.2, 0)) * yaw, Enum.Material.Slate, Color3.fromRGB(110, 112, 116))
				ellipsoid(flora, "Moss", Vector3.new(size * 1.1, size * 0.3, size * 0.8), CFrame.new(p + Vector3.new(0, size * 0.45, 0)) * yaw, Enum.Material.Grass, Color3.fromRGB(80, 130, 60))
			end
		end
	end

	-- The beach ---------------------------------------------------------------------------------
	local SHELL = { Color3.fromRGB(250, 220, 200), Color3.fromRGB(240, 190, 170), Color3.fromRGB(230, 230, 220) }
	for _ = 1, 60 do
		local p = landSpot(52, 70, 1)
		if p then
			local roll = random()
			if roll < 0.45 then
				ellipsoid(beach, "Shell", Vector3.new(0.7, 0.3, 0.6), CFrame.new(p + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, random() * 6, 0), Enum.Material.SmoothPlastic, SHELL[rng:NextInteger(1, #SHELL)])
			elseif roll < 0.7 then
				local star = CFrame.new(p + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, random() * 6, 0)
				local color = random() < 0.5 and Color3.fromRGB(240, 110, 60) or Color3.fromRGB(200, 60, 120)
				for arm = 1, 5 do
					part(beach, "StarfishArm", Vector3.new(0.35, 0.15, 1), star * CFrame.Angles(0, arm * 1.2566, 0) * CFrame.new(0, 0, -0.45), Enum.Material.SmoothPlastic, color)
				end
			elseif roll < 0.85 then
				part(beach, "Driftwood", Vector3.new(4 + random() * 4, 0.6, 0.6), CFrame.new(p + Vector3.new(0, 0.25, 0)) * CFrame.Angles(0, random() * 6, 0.05), Enum.Material.Wood, Color3.fromRGB(190, 170, 140), Enum.PartType.Cylinder)
			else
				part(beach, "Coconut", Vector3.new(0.9, 0.9, 0.9), CFrame.new(p + Vector3.new(0, 0.4, 0)), Enum.Material.Wood, Color3.fromRGB(96, 70, 40), Enum.PartType.Ball)
			end
		end
	end
	-- A parasol and two deckchairs looking at the lagoon.
	local spot = landSpot(50, 60, 5)
	if spot then
		local out = Vector3.new(spot.X, 0, spot.Z).Unit
		local base = CFrame.lookAt(spot, spot + out)
		part(beach, "ParasolPole", Vector3.new(0.3, 7, 0.3), base * CFrame.new(0, 3.5, 0), Enum.Material.Wood, Color3.fromRGB(230, 220, 200))
		for k = 0, 7 do
			part(beach, "ParasolPanel", Vector3.new(2.6, 0.1, 4.2), base * CFrame.new(0, 6.8, 0) * CFrame.Angles(0, k * math.pi / 4, 0) * CFrame.Angles(math.rad(18), 0, 0) * CFrame.new(0, 0, -2), Enum.Material.Fabric, k % 2 == 0 and Color3.fromRGB(240, 70, 70) or Color3.fromRGB(250, 250, 245))
		end
		for _, x in ipairs({ -2.2, 2.2 }) do
			part(beach, "Deckchair", Vector3.new(2, 0.3, 5), base * CFrame.new(x, 0.9, -1) * CFrame.Angles(math.rad(-15), 0, 0), Enum.Material.Fabric, Color3.fromRGB(40, 150, 210))
		end
		layout:ReserveBox("Island_Parasol", base * CFrame.new(0, 3, 0), Vector3.new(9, 8, 9))
	end

	-- Fauna ---------------------------------------------------------------------------------------
	local function critter(name: string, tag: string, attributes: { [string]: any }): Model
		local model = Instance.new("Model")
		model.Name = name
		for key, value in pairs(attributes) do
			model:SetAttribute(key, value)
		end
		model.Parent = fauna
		CollectionService:AddTag(model, tag)
		return model
	end
	local function finish(model: Model, primary: BasePart)
		model.PrimaryPart = primary
	end

	-- Crabs: a red shell, eyes on stalks, claws and legs.
	for k = 1, 10 do
		local p = landSpot(56, 69, 0.5)
		if p then
			local hermit = k % 3 == 0
			local model = critter(hermit and "BernardLErmite" or "Crabe", "Crab", { Home = p, Range = hermit and 3 or 6, Speed = hermit and 1.2 or 4 })
			local f = CFrame.new(p + Vector3.new(0, 0.35, 0))
			local body
			if hermit then
				body = ellipsoid(model, "Shell", Vector3.new(1.1, 1, 1.3), f * CFrame.new(0, 0.3, 0.2) * CFrame.Angles(0.3, 0, 0), Enum.Material.SmoothPlastic, Color3.fromRGB(230, 200, 170))
				ellipsoid(model, "Spiral", Vector3.new(0.6, 0.6, 0.7), f * CFrame.new(0, 0.75, 0.4), Enum.Material.SmoothPlastic, Color3.fromRGB(200, 150, 120))
				part(model, "Head", Vector3.new(0.5, 0.35, 0.4), f * CFrame.new(0, 0, -0.5), Enum.Material.SmoothPlastic, Color3.fromRGB(220, 110, 70))
			else
				body = ellipsoid(model, "Body", Vector3.new(1.6, 0.55, 1.1), f, Enum.Material.SmoothPlastic, Color3.fromRGB(220, 60, 40))
				for _, x in ipairs({ -1, 1 }) do
					part(model, "Claw", Vector3.new(0.45, 0.35, 0.6), f * CFrame.new(x * 0.95, 0.05, -0.55) * CFrame.Angles(0, x * 0.4, 0), Enum.Material.SmoothPlastic, Color3.fromRGB(235, 80, 50))
					for leg = 1, 3 do
						part(model, "Leg", Vector3.new(0.7, 0.1, 0.1), f * CFrame.new(x * 0.95, -0.15, -0.3 + leg * 0.28) * CFrame.Angles(0, 0, x * -0.5), Enum.Material.SmoothPlastic, Color3.fromRGB(200, 50, 35))
					end
					part(model, "EyeStalk", Vector3.new(0.08, 0.35, 0.08), f * CFrame.new(x * 0.2, 0.4, -0.45), Enum.Material.SmoothPlastic, Color3.fromRGB(200, 50, 35))
					part(model, "Eye", Vector3.new(0.14, 0.14, 0.14), f * CFrame.new(x * 0.2, 0.6, -0.45), Enum.Material.SmoothPlastic, Color3.fromRGB(20, 20, 20), Enum.PartType.Ball)
				end
			end
			finish(model, body)
		end
	end

	-- Seagulls circling above the island.
	for k = 1, 5 do
		local center = Vector3.new(random() * 60 - 30, 0, random() * 60 - 30)
		local model = critter("Mouette", "Seagull", { Center = center, Radius = 40 + random() * 50, Height = 28 + random() * 22, Speed = 0.25 + random() * 0.2, Phase = random() * 6.28 })
		local f = CFrame.new(center + Vector3.new(0, 40, 0))
		local body = ellipsoid(model, "Body", Vector3.new(0.9, 0.8, 2.2), f, Enum.Material.SmoothPlastic, Color3.fromRGB(245, 245, 245))
		ellipsoid(model, "Head", Vector3.new(0.6, 0.6, 0.7), f * CFrame.new(0, 0.25, -1.1), Enum.Material.SmoothPlastic, Color3.fromRGB(250, 250, 250))
		part(model, "Beak", Vector3.new(0.15, 0.15, 0.5), f * CFrame.new(0, 0.2, -1.6), Enum.Material.SmoothPlastic, Color3.fromRGB(250, 190, 40))
		part(model, "Tail", Vector3.new(0.8, 0.1, 0.8), f * CFrame.new(0, 0.05, 1.3), Enum.Material.SmoothPlastic, Color3.fromRGB(90, 96, 106))
		for _, x in ipairs({ -1, 1 }) do
			local wing = part(model, x < 0 and "WingLeft" or "WingRight", Vector3.new(2.6, 0.1, 1), f * CFrame.new(x * 1.6, 0.2, 0), Enum.Material.SmoothPlastic, Color3.fromRGB(235, 236, 240))
			part(model, x < 0 and "WingTipLeft" or "WingTipRight", Vector3.new(0.8, 0.11, 0.8), wing.CFrame * CFrame.new(x * 1.4, 0, 0.1), Enum.Material.SmoothPlastic, Color3.fromRGB(40, 40, 44))
		end
		finish(model, body)
	end

	-- Butterflies around the flowers.
	local WINGS = { Color3.fromRGB(60, 130, 250), Color3.fromRGB(250, 170, 40), Color3.fromRGB(240, 90, 180), Color3.fromRGB(250, 240, 90) }
	for k = 1, math.min(12, #flowers) do
		local home = flowers[rng:NextInteger(1, #flowers)]
		local model = critter("Papillon", "Butterfly", { Home = home, Phase = random() * 6.28 })
		local f = CFrame.new(home + Vector3.new(0, 1, 0))
		local body = part(model, "Body", Vector3.new(0.1, 0.1, 0.5), f, Enum.Material.SmoothPlastic, Color3.fromRGB(30, 30, 30))
		local color = WINGS[(k - 1) % #WINGS + 1]
		for _, x in ipairs({ -1, 1 }) do
			ellipsoid(model, x < 0 and "WingLeft" or "WingRight", Vector3.new(0.6, 0.05, 0.5), f * CFrame.new(x * 0.32, 0, 0), Enum.Material.SmoothPlastic, color)
		end
		finish(model, body)
	end

	-- Parrots perched in the palms.
	local PARROTS = { { Color3.fromRGB(220, 40, 40), Color3.fromRGB(40, 110, 230) }, { Color3.fromRGB(40, 170, 80), Color3.fromRGB(250, 210, 40) }, { Color3.fromRGB(40, 110, 230), Color3.fromRGB(250, 200, 40) } }
	for k = 1, math.min(4, #palmTops) do
		local top = palmTops[k] * CFrame.new(0.9, 0.2, 0)
		local colors = PARROTS[(k - 1) % #PARROTS + 1]
		local model = critter("Perroquet", "Parrot", { Phase = random() * 6.28 })
		local body = ellipsoid(model, "Body", Vector3.new(0.7, 1.1, 0.7), top * CFrame.new(0, 0.5, 0), Enum.Material.SmoothPlastic, colors[1])
		ellipsoid(model, "Head", Vector3.new(0.55, 0.55, 0.55), top * CFrame.new(0, 1.2, -0.1), Enum.Material.SmoothPlastic, colors[1])
		part(model, "Beak", Vector3.new(0.2, 0.25, 0.25), top * CFrame.new(0, 1.1, -0.4), Enum.Material.SmoothPlastic, Color3.fromRGB(40, 36, 30))
		part(model, "Tail", Vector3.new(0.3, 1.1, 0.12), top * CFrame.new(0, -0.3, 0.3) * CFrame.Angles(0.3, 0, 0), Enum.Material.SmoothPlastic, colors[2])
		for _, x in ipairs({ -1, 1 }) do
			part(model, "Wing", Vector3.new(0.12, 0.8, 0.5), top * CFrame.new(x * 0.36, 0.55, 0.05), Enum.Material.SmoothPlastic, colors[2])
		end
		finish(model, body)
	end

	-- Dolphins leaping in the outer lagoon.
	for k = 1, 3 do
		local model = critter("Dauphin", "Dolphin", { Center = Vector3.zero, Radius = 150 + k * 10, Speed = 0.07 + k * 0.01, Phase = k * 2.1 })
		local f = CFrame.new(155, -3, 0)
		local grey = Color3.fromRGB(120, 136, 150)
		local body = ellipsoid(model, "Body", Vector3.new(1.4, 1.5, 5.6), f, Enum.Material.SmoothPlastic, grey)
		ellipsoid(model, "Belly", Vector3.new(1.2, 1, 4.6), f * CFrame.new(0, -0.35, -0.2), Enum.Material.SmoothPlastic, Color3.fromRGB(220, 226, 230))
		ellipsoid(model, "Snout", Vector3.new(0.5, 0.45, 1.2), f * CFrame.new(0, -0.15, -3.1), Enum.Material.SmoothPlastic, grey)
		part(model, "DorsalFin", Vector3.new(0.18, 1.1, 0.9), f * CFrame.new(0, 0.95, 0.4) * CFrame.Angles(-0.5, 0, 0), Enum.Material.SmoothPlastic, grey)
		part(model, "Fluke", Vector3.new(2.2, 0.15, 0.8), f * CFrame.new(0, 0, 3.1), Enum.Material.SmoothPlastic, grey)
		for _, x in ipairs({ -1, 1 }) do
			part(model, "Flipper", Vector3.new(0.9, 0.1, 0.5), f * CFrame.new(x * 0.8, -0.4, -1) * CFrame.Angles(0, 0, x * 0.5), Enum.Material.SmoothPlastic, grey)
			part(model, "Eye", Vector3.new(0.14, 0.14, 0.14), f * CFrame.new(x * 0.55, 0.05, -2.3), Enum.Material.SmoothPlastic, Color3.fromRGB(20, 20, 20), Enum.PartType.Ball)
		end
		finish(model, body)
	end

	local parts = 0
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("BasePart") then
			parts += 1
		end
	end
	print(string.format("[IslandLife] %d parts", parts))
end

return IslandLife
