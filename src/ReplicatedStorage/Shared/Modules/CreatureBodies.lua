-- Procedural bodies for the 5 marine species, used until the pack's real
-- rigged FBX models are imported (CreatureSpawner always prefers
-- ReplicatedStorage.Assets.Creatures.<ModelName> when it exists). Each body
-- is a small assembly of primitives -- ellipsoids (a Block with a Sphere
-- SpecialMesh stretches to any proportions), wedges for the sharp fins --
-- coloured and patterned per species so the animals read as the real
-- thing at a glance: a banded tropical fish in one of several reef
-- palettes, a grey reef shark with black fin tips, a manta with its white
-- shoulder chevrons, a sea turtle with a plated carapace, a translucent
-- jellyfish glowing from the inside.
--
-- Conventions: built around the origin, nose toward -Z (the direction
-- CreatureBrain steers), Y up; dimensions come from the species' real
-- measured Size (X = length, Y = height, Z = width/span), times `scale`.
-- The PrimaryPart is "Body". Rigid details are welded to what they sit
-- on; the parts that swim (tail, wings, flippers, tentacles) hang off
-- Motor6D joints carrying Swing* attributes -- CreatureAnimator (client)
-- turns those into motion locally, so nothing is replicated per frame.

local CreatureBodies = {}

local REEF_PALETTES = {
	{ body = Color3.fromRGB(255, 122, 32), band = Color3.fromRGB(250, 250, 250), edge = Color3.fromRGB(25, 25, 30), fin = Color3.fromRGB(255, 140, 45), bands = 2 }, -- clownfish
	{ body = Color3.fromRGB(38, 105, 225), band = Color3.fromRGB(18, 28, 70), edge = Color3.fromRGB(18, 28, 70), fin = Color3.fromRGB(255, 212, 40), bands = 0, saddle = true }, -- blue tang
	{ body = Color3.fromRGB(255, 214, 40), band = Color3.fromRGB(255, 238, 130), edge = Color3.fromRGB(245, 190, 30), fin = Color3.fromRGB(255, 226, 90), bands = 0 }, -- yellow tang
	{ body = Color3.fromRGB(248, 232, 96), band = Color3.fromRGB(28, 36, 70), edge = Color3.fromRGB(28, 36, 70), fin = Color3.fromRGB(70, 130, 225), bands = 3 }, -- angelfish
	{ body = Color3.fromRGB(235, 90, 160), band = Color3.fromRGB(255, 220, 90), edge = Color3.fromRGB(120, 40, 120), fin = Color3.fromRGB(255, 200, 80), bands = 1 }, -- royal gramma-ish
}
CreatureBodies.ReefPaletteCount = #REEF_PALETTES

local EYE_WHITE = Color3.fromRGB(245, 245, 240)
local PUPIL = Color3.fromRGB(12, 12, 16)

-- Primitives ------------------------------------------------------------------------

local function basePart(className: string, model: Model, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?)
	local part = Instance.new(className)
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Anchored = false
	part.Massless = true
	part.Parent = model
	return part
end

local function ellipsoid(model: Model, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?)
	local part = basePart("Part", model, name, size, cframe, color, material)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = part
	return part
end

-- A WedgePart: full height at its back (+Z), sloping to nothing at the
-- front-bottom edge -- a fin with a raked leading edge.
local function wedge(model: Model, name: string, size: Vector3, cframe: CFrame, color: Color3)
	return basePart("WedgePart", model, name, size, cframe, color)
end

local function weld(to: BasePart, part: BasePart)
	local constraint = Instance.new("WeldConstraint")
	constraint.Part0 = to
	constraint.Part1 = part
	constraint.Parent = part
	return part
end

-- A Motor6D pivoting at `pivot` (model space). Swing* attributes describe
-- the looping motion the client animator plays on it.
local function joint(name: string, part0: BasePart, part1: BasePart, pivot: Vector3, axis: Vector3, amplitude: number, frequency: number, phase: number?)
	local pivotFrame = CFrame.new(pivot)
	local motor = Instance.new("Motor6D")
	motor.Name = name
	motor.Part0 = part0
	motor.Part1 = part1
	motor.C0 = part0.CFrame:Inverse() * pivotFrame
	motor.C1 = part1.CFrame:Inverse() * pivotFrame
	motor:SetAttribute("SwingAxis", axis)
	motor:SetAttribute("SwingAmplitude", amplitude)
	motor:SetAttribute("SwingFrequency", frequency)
	motor:SetAttribute("SwingPhase", phase or 0)
	motor.Parent = part0
	return motor
end

local function eyes(model: Model, on: BasePart, x: number, y: number, z: number, size: number, withWhite: boolean)
	for _, side in ipairs({ -1, 1 }) do
		local center = Vector3.new(x * side, y, z)
		if withWhite then
			weld(on, ellipsoid(model, "EyeWhite", Vector3.new(size * 0.5, size, size), CFrame.new(center), EYE_WHITE))
		end
		weld(on, ellipsoid(model, "Eye", Vector3.new(size * 0.4, size * 0.62, size * 0.62), CFrame.new(center + Vector3.new(side * size * 0.14, 0, -size * 0.05)), PUPIL, Enum.Material.Glass))
	end
end

-- Species ---------------------------------------------------------------------------

local function reefFish(model: Model, L: number, H: number, _W: number, variant: number)
	local palette = REEF_PALETTES[(variant - 1) % #REEF_PALETTES + 1]
	local bodyLength, bodyHeight, bodyWidth = L * 0.66, H * 0.78, L * 0.24
	local body = ellipsoid(model, "Body", Vector3.new(bodyWidth, bodyHeight, bodyLength), CFrame.new(0, 0, -L * 0.06), palette.body)

	-- Vertical bands (edged in a dark outline, like a clownfish's).
	local bandCount = palette.bands
	for i = 1, bandCount do
		local z = -L * 0.06 + bodyLength * ((i / (bandCount + 1)) - 0.5) * 0.9
		local taper = 1 - math.abs((i / (bandCount + 1)) - 0.5) * 0.9
		weld(body, ellipsoid(model, "BandEdge", Vector3.new(bodyWidth * 1.04, bodyHeight * taper * 0.98, L * 0.17), CFrame.new(0, 0, z), palette.edge))
		weld(body, ellipsoid(model, "Band", Vector3.new(bodyWidth * 1.07, bodyHeight * taper * 0.95, L * 0.13), CFrame.new(0, 0, z), palette.band))
	end
	if palette.saddle then
		weld(body, ellipsoid(model, "Saddle", Vector3.new(bodyWidth * 1.05, bodyHeight * 0.45, bodyLength * 0.62), CFrame.new(0, bodyHeight * 0.18, -L * 0.03), palette.band))
	end

	weld(body, ellipsoid(model, "Lips", Vector3.new(bodyWidth * 0.35, bodyHeight * 0.18, L * 0.08), CFrame.new(0, -bodyHeight * 0.05, -L * 0.06 - bodyLength * 0.48), palette.edge))
	weld(body, ellipsoid(model, "DorsalFin", Vector3.new(0.12, bodyHeight * 0.55, bodyLength * 0.62), CFrame.new(0, bodyHeight * 0.44, -L * 0.02) * CFrame.Angles(math.rad(8), 0, 0), palette.fin))
	weld(body, ellipsoid(model, "AnalFin", Vector3.new(0.1, bodyHeight * 0.36, bodyLength * 0.34), CFrame.new(0, -bodyHeight * 0.42, L * 0.06), palette.fin))
	eyes(model, body, bodyWidth * 0.36, bodyHeight * 0.14, -L * 0.06 - bodyLength * 0.3, bodyHeight * 0.26, true)

	-- Tail: a stock with a two-lobed fin, beating from side to side.
	local stockZ = -L * 0.06 + bodyLength * 0.5
	local stock = ellipsoid(model, "TailStock", Vector3.new(bodyWidth * 0.45, bodyHeight * 0.36, L * 0.16), CFrame.new(0, 0, stockZ + L * 0.05), palette.body)
	for _, side in ipairs({ 1, -1 }) do
		weld(stock, ellipsoid(model, "TailLobe", Vector3.new(0.12, bodyHeight * 0.55, L * 0.2), CFrame.new(0, side * bodyHeight * 0.2, stockZ + L * 0.17) * CFrame.Angles(math.rad(side * 32), 0, 0), palette.fin))
	end
	joint("TailJoint", body, stock, Vector3.new(0, 0, stockZ - L * 0.02), Vector3.new(0, 1, 0), math.rad(22), 2.2)

	for _, side in ipairs({ -1, 1 }) do
		local fin = ellipsoid(model, "PectoralFin", Vector3.new(bodyWidth * 0.7, 0.1, L * 0.14), CFrame.new(side * bodyWidth * 0.55, -bodyHeight * 0.1, -L * 0.1) * CFrame.Angles(0, math.rad(side * -35), math.rad(side * -20)), palette.fin)
		fin.Transparency = 0.15
		joint(side < 0 and "FinL" or "FinR", body, fin, Vector3.new(side * bodyWidth * 0.4, -bodyHeight * 0.1, -L * 0.12), Vector3.new(0, 0, 1), math.rad(25), 2.6, side < 0 and 0 or math.pi)
	end
	return body
end

local function reefShark(model: Model, L: number, H: number, W: number)
	local TOP = Color3.fromRGB(108, 122, 136)
	local BELLY = Color3.fromRGB(236, 238, 240)
	local FIN = Color3.fromRGB(98, 112, 126)
	local TIP = Color3.fromRGB(26, 30, 36)

	local bodyWidth, bodyHeight, bodyLength = L * 0.19, H * 0.42, L * 0.62
	local body = ellipsoid(model, "Body", Vector3.new(bodyWidth, bodyHeight, bodyLength), CFrame.new(0, 0, -L * 0.04), TOP)
	weld(body, ellipsoid(model, "Belly", Vector3.new(bodyWidth * 0.9, bodyHeight * 0.7, bodyLength * 0.86), CFrame.new(0, -bodyHeight * 0.2, -L * 0.05), BELLY))
	weld(body, ellipsoid(model, "Snout", Vector3.new(bodyWidth * 0.72, bodyHeight * 0.66, L * 0.24), CFrame.new(0, -bodyHeight * 0.02, -L * 0.33), TOP))
	weld(body, ellipsoid(model, "Jaw", Vector3.new(bodyWidth * 0.62, bodyHeight * 0.4, L * 0.16), CFrame.new(0, -bodyHeight * 0.24, -L * 0.3), BELLY))
	eyes(model, body, bodyWidth * 0.34, bodyHeight * 0.14, -L * 0.33, bodyHeight * 0.16, false)
	for i = 0, 2 do
		for _, side in ipairs({ -1, 1 }) do
			weld(body, basePart("Part", model, "Gill", Vector3.new(0.06, bodyHeight * 0.34, 0.1), CFrame.new(side * bodyWidth * 0.47, 0, -L * 0.2 + i * L * 0.025) * CFrame.Angles(0, 0, side * 0.12), Color3.fromRGB(70, 80, 92)))
		end
	end

	local dorsal = wedge(model, "DorsalFin", Vector3.new(0.35, H * 0.34, L * 0.17), CFrame.new(0, bodyHeight * 0.44 + H * 0.15, -L * 0.04), FIN)
	weld(body, dorsal)
	weld(body, wedge(model, "DorsalTip", Vector3.new(0.4, H * 0.1, L * 0.05), CFrame.new(0, bodyHeight * 0.44 + H * 0.28, L * 0.02), TIP))
	weld(body, wedge(model, "SecondDorsal", Vector3.new(0.25, H * 0.09, L * 0.06), CFrame.new(0, bodyHeight * 0.3 + H * 0.04, L * 0.2), FIN))

	for _, side in ipairs({ -1, 1 }) do
		local span = (W - bodyWidth) * 0.5
		-- Rolled onto its side so the wedge's height points outward and a
		-- little down: a swept-back, drooping pectoral fin.
		local fin = wedge(model, "PectoralFin", Vector3.new(0.3, span, L * 0.16), CFrame.new(side * (bodyWidth * 0.4 + span * 0.47), -bodyHeight * 0.3 - span * 0.17, -L * 0.1) * CFrame.Angles(0, 0, side * -(math.pi / 2 + 0.35)), FIN)
		weld(body, fin)
	end

	-- Tail stock + heterocercal caudal fin (big upper lobe, small lower).
	local stockZ = -L * 0.04 + bodyLength * 0.46
	local stock = ellipsoid(model, "TailStock", Vector3.new(bodyWidth * 0.42, bodyHeight * 0.4, L * 0.24), CFrame.new(0, bodyHeight * 0.03, stockZ + L * 0.08), TOP)
	weld(stock, wedge(model, "CaudalUpper", Vector3.new(0.3, H * 0.4, L * 0.16), CFrame.new(0, H * 0.2, stockZ + L * 0.24) * CFrame.Angles(math.rad(18), 0, 0), FIN))
	weld(stock, wedge(model, "CaudalUpperTip", Vector3.new(0.34, H * 0.1, L * 0.05), CFrame.new(0, H * 0.37, stockZ + L * 0.3) * CFrame.Angles(math.rad(18), 0, 0), TIP))
	weld(stock, wedge(model, "CaudalLower", Vector3.new(0.3, H * 0.2, L * 0.1), CFrame.new(0, -H * 0.1, stockZ + L * 0.22) * CFrame.Angles(math.rad(-18), 0, math.pi), FIN))
	joint("TailJoint", body, stock, Vector3.new(0, 0, stockZ - L * 0.02), Vector3.new(0, 1, 0), math.rad(14), 1.1)
	return body
end

local function manta(model: Model, L: number, H: number, W: number)
	local TOP = Color3.fromRGB(34, 42, 56)
	local BELLY = Color3.fromRGB(232, 236, 240)
	local PATCH = Color3.fromRGB(128, 136, 148)

	local body = ellipsoid(model, "Body", Vector3.new(W * 0.3, H * 0.95, L * 0.56), CFrame.new(0, 0, -L * 0.05), TOP)
	weld(body, ellipsoid(model, "Belly", Vector3.new(W * 0.27, H * 0.6, L * 0.48), CFrame.new(0, -H * 0.22, -L * 0.05), BELLY))
	for _, side in ipairs({ -1, 1 }) do
		weld(body, ellipsoid(model, "ShoulderPatch", Vector3.new(W * 0.1, H * 0.14, L * 0.2), CFrame.new(side * W * 0.1, H * 0.38, -L * 0.06) * CFrame.Angles(0, math.rad(side * 40), 0), PATCH))
		-- Cephalic lobes curling forward either side of the mouth.
		weld(body, ellipsoid(model, "CephalicLobe", Vector3.new(W * 0.04, H * 0.5, L * 0.16), CFrame.new(side * W * 0.1, -H * 0.05, -L * 0.36) * CFrame.Angles(0, 0, side * 0.3), TOP))
		weld(body, ellipsoid(model, "Eye", Vector3.new(W * 0.025, H * 0.28, H * 0.28), CFrame.new(side * W * 0.145, H * 0.06, -L * 0.25), PUPIL, Enum.Material.Glass))

		-- Wing: a broad swept ellipsoid, white underneath, flapping slowly.
		local wingCenter = Vector3.new(side * W * 0.32, 0, L * 0.02)
		local wing = ellipsoid(model, "Wing", Vector3.new(W * 0.42, H * 0.3, L * 0.36), CFrame.new(wingCenter) * CFrame.Angles(0, math.rad(side * -26), 0), TOP)
		weld(wing, ellipsoid(model, "WingUnder", Vector3.new(W * 0.36, H * 0.2, L * 0.36), CFrame.new(wingCenter + Vector3.new(0, -H * 0.06, 0)) * CFrame.Angles(0, math.rad(side * -22), 0), BELLY))
		-- Long pointed tips swept back: the manta's unmistakable outline.
		weld(wing, ellipsoid(model, "WingTip", Vector3.new(W * 0.26, H * 0.14, L * 0.1), CFrame.new(side * W * 0.47, 0, L * 0.15) * CFrame.Angles(0, math.rad(side * -38), 0), TOP))
		weld(wing, ellipsoid(model, "WingTipEnd", Vector3.new(W * 0.12, H * 0.1, L * 0.05), CFrame.new(side * W * 0.58, 0, L * 0.25) * CFrame.Angles(0, math.rad(side * -48), 0), TOP))
		joint(side < 0 and "WingL" or "WingR", body, wing, Vector3.new(side * W * 0.12, 0, -L * 0.02), Vector3.new(0, 0, side), math.rad(24), 0.32, 0)
	end
	local tail = basePart("Part", model, "Tail", Vector3.new(L * 0.5, 0.22, 0.22), CFrame.new(0, 0, L * 0.45) * CFrame.Angles(0, math.pi / 2, 0), TOP)
	tail.Shape = Enum.PartType.Cylinder
	weld(body, tail)
	return body
end

local function seaTurtle(model: Model, L: number, H: number, W: number)
	local SHELL = Color3.fromRGB(92, 104, 56)
	local SCUTE_A = Color3.fromRGB(128, 104, 60)
	local SCUTE_B = Color3.fromRGB(86, 92, 48)
	local RIM = Color3.fromRGB(150, 138, 86)
	local PLASTRON = Color3.fromRGB(222, 206, 150)
	local SKIN = Color3.fromRGB(122, 142, 90)
	local SPOT = Color3.fromRGB(78, 92, 56)

	local shellW, shellH, shellL = W * 0.52, H * 0.62, L * 0.6
	local body = ellipsoid(model, "Body", Vector3.new(shellW, shellH, shellL), CFrame.new(0, H * 0.05, 0), SHELL)
	weld(body, ellipsoid(model, "ShellRim", Vector3.new(shellW * 1.06, shellH * 0.35, shellL * 1.05), CFrame.new(0, -H * 0.06, 0), RIM))
	weld(body, ellipsoid(model, "Plastron", Vector3.new(shellW * 0.85, shellH * 0.4, shellL * 0.9), CFrame.new(0, -H * 0.16, 0), PLASTRON))
	-- Carapace plates: a central row and two side rows, alternating shades.
	local scutes = {
		{ 0, -0.28 }, { 0, 0 }, { 0, 0.28 },
		{ -0.26, -0.16 }, { 0.26, -0.16 }, { -0.28, 0.14 }, { 0.28, 0.14 },
	}
	for index, spot in ipairs(scutes) do
		local x, z = spot[1] * shellW, spot[2] * shellL
		local rise = shellH * 0.5 * math.sqrt(math.max(0, 1 - (spot[1] * 2) ^ 2 - (spot[2] * 2) ^ 2)) - shellH * 0.05
		weld(body, ellipsoid(model, "Scute", Vector3.new(shellW * 0.26, shellH * 0.22, shellL * 0.22), CFrame.new(x, H * 0.05 + rise, z), index % 2 == 0 and SCUTE_A or SCUTE_B))
	end

	local head = ellipsoid(model, "Head", Vector3.new(W * 0.14, H * 0.42, L * 0.2), CFrame.new(0, H * 0.02, -L * 0.4), SKIN)
	weld(body, head)
	weld(head, ellipsoid(model, "Beak", Vector3.new(W * 0.1, H * 0.2, L * 0.07), CFrame.new(0, -H * 0.05, -L * 0.49), SPOT))
	weld(head, ellipsoid(model, "HeadSpot", Vector3.new(W * 0.1, H * 0.12, L * 0.08), CFrame.new(0, H * 0.18, -L * 0.42), SPOT))
	eyes(model, head, W * 0.06, H * 0.1, -L * 0.44, H * 0.16, false)

	for _, side in ipairs({ -1, 1 }) do
		local front = ellipsoid(model, "FrontFlipper", Vector3.new(W * 0.36, H * 0.12, L * 0.14), CFrame.new(side * (shellW * 0.5 + W * 0.14), -H * 0.05, -L * 0.14) * CFrame.Angles(0, math.rad(side * -32), 0), SKIN)
		weld(front, ellipsoid(model, "FlipperSpot", Vector3.new(W * 0.12, H * 0.13, L * 0.06), CFrame.new(side * (shellW * 0.5 + W * 0.18), -H * 0.04, -L * 0.15), SPOT))
		joint(side < 0 and "FlipperFL" or "FlipperFR", body, front, Vector3.new(side * shellW * 0.42, -H * 0.05, -L * 0.18), Vector3.new(0, 0, side), math.rad(32), 0.45, 0)
		local rear = ellipsoid(model, "RearFlipper", Vector3.new(W * 0.16, H * 0.1, L * 0.12), CFrame.new(side * shellW * 0.45, -H * 0.08, L * 0.26) * CFrame.Angles(0, math.rad(side * 40), 0), SKIN)
		joint(side < 0 and "FlipperRL" or "FlipperRR", body, rear, Vector3.new(side * shellW * 0.35, -H * 0.08, L * 0.22), Vector3.new(0, 1, 0), math.rad(18), 0.45, math.pi / 2)
	end
	weld(body, ellipsoid(model, "Tail", Vector3.new(W * 0.05, H * 0.12, L * 0.1), CFrame.new(0, -H * 0.05, L * 0.34), SKIN))
	return body
end

local function jellyfish(model: Model, L: number, H: number, W: number, glow: Color3?)
	local BELL = Color3.fromRGB(172, 212, 246)
	local GLOW = glow or Color3.fromRGB(120, 220, 255)
	local ARM = Color3.fromRGB(232, 168, 222)

	local diameter = math.max(L, W) * 0.82
	local bellY = H * 0.28
	local body = ellipsoid(model, "Body", Vector3.new(diameter, diameter * 0.6, diameter), CFrame.new(0, bellY, 0), BELL, Enum.Material.Glass)
	body.Transparency = 0.35
	local core = ellipsoid(model, "GlowCore", Vector3.new(diameter * 0.56, diameter * 0.32, diameter * 0.56), CFrame.new(0, bellY - diameter * 0.02, 0), GLOW, Enum.Material.Neon)
	core.Transparency = 0.3
	weld(body, core)
	local light = Instance.new("PointLight")
	light.Color = GLOW
	light.Range = 14
	light.Brightness = 1.6
	light.Parent = core

	local rimY = bellY - diameter * 0.2
	for i = 1, 8 do
		local angle = i / 8 * math.pi * 2
		local rimPoint = Vector3.new(math.cos(angle) * diameter * 0.44, rimY, math.sin(angle) * diameter * 0.44)
		weld(body, ellipsoid(model, "RimLight", Vector3.new(0.3, 0.3, 0.3), CFrame.new(rimPoint), GLOW, Enum.Material.Neon))
		local length = H * (0.5 + (i % 3) * 0.08)
		local tentacle = basePart("Part", model, "Tentacle", Vector3.new(0.1, length, 0.1), CFrame.new(rimPoint - Vector3.new(0, length / 2, 0)), GLOW, Enum.Material.Neon)
		tentacle.Transparency = 0.45
		joint("Tentacle" .. i, body, tentacle, rimPoint, Vector3.new(math.sin(angle), 0, -math.cos(angle)), math.rad(12), 0.5, i * 0.8)
	end
	-- Frilly oral arms hanging from the middle of the bell.
	for i = 1, 4 do
		local angle = i / 4 * math.pi * 2 + 0.4
		local top = Vector3.new(math.cos(angle) * diameter * 0.1, rimY + diameter * 0.05, math.sin(angle) * diameter * 0.1)
		local armLength = H * 0.42
		local arm = ellipsoid(model, "OralArm", Vector3.new(diameter * 0.12, armLength, diameter * 0.07), CFrame.new(top - Vector3.new(0, armLength / 2, 0)) * CFrame.Angles(0, angle, 0.08), ARM)
		arm.Transparency = 0.3
		weld(arm, ellipsoid(model, "OralFrill", Vector3.new(diameter * 0.16, armLength * 0.4, diameter * 0.05), CFrame.new(top - Vector3.new(0, armLength * 0.75, 0)) * CFrame.Angles(0, angle + 0.6, -0.1), ARM))
		joint("OralArm" .. i, body, arm, top, Vector3.new(math.cos(angle), 0, math.sin(angle)), math.rad(9), 0.35, i * 1.3)
	end
	return body
end

local BUILDERS = {
	PoissonRecif = reefFish,
	RequinRecif = reefShark,
	RaieManta = manta,
	TortueMarine = seaTurtle,
	MeduseLumineuse = jellyfish,
}

-- options: { variant = number? (reef fish palette), scale = number? }
function CreatureBodies.Build(species, options): Model
	options = options or {}
	local scale = options.scale or 1
	local size = species.Size * scale
	local model = Instance.new("Model")
	local builder = BUILDERS[species.Id]
	local body
	if builder == reefFish then
		body = reefFish(model, size.X, size.Y, size.Z, options.variant or 1)
	elseif builder == jellyfish then
		body = jellyfish(model, size.X, size.Y, size.Z, species.Glow)
	elseif builder then
		body = builder(model, size.X, size.Y, size.Z)
	else
		-- Unknown species id: a plain coloured body, facing -Z.
		body = ellipsoid(model, "Body", Vector3.new(size.Z * 0.5, size.Y, size.X), CFrame.new(), species.Color or Color3.new(0.6, 0.6, 0.6))
	end
	body.Massless = false
	model.PrimaryPart = body
	model:SetAttribute("ProceduralBody", true)
	return model
end

-- A tiny decorative fish for client-side ambient shoals: anchored parts,
-- moved by the client as a whole. `tint` (optional) replaces the reef
-- palette -- silver for mid-water, a glowing blue for the abyss.
function CreatureBodies.BuildSmallFish(length: number, variant: number, tint: Color3?, glow: boolean?): Model
	local model = Instance.new("Model")
	local palette = REEF_PALETTES[(variant - 1) % #REEF_PALETTES + 1]
	local bodyColor = tint or palette.body
	local finColor = tint and tint:Lerp(Color3.new(1, 1, 1), 0.25) or palette.fin
	local material = glow and Enum.Material.Neon or Enum.Material.SmoothPlastic
	local body = ellipsoid(model, "Body", Vector3.new(length * 0.22, length * 0.4, length * 0.7), CFrame.new(0, 0, -length * 0.08), bodyColor, material)
	local tail = ellipsoid(model, "Tail", Vector3.new(0.06, length * 0.36, length * 0.28), CFrame.new(0, 0, length * 0.36), finColor, material)
	local parts = { body, tail }
	if not tint and palette.bands > 0 then
		table.insert(parts, ellipsoid(model, "Band", Vector3.new(length * 0.24, length * 0.36, length * 0.1), CFrame.new(0, 0, -length * 0.12), palette.band))
	end
	for _, part in ipairs(parts) do
		part.Anchored = true
		part.Massless = false
	end
	model.PrimaryPart = body
	return model
end

return CreatureBodies
