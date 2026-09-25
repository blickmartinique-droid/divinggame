-- Procedural bodies for the 5 marine species, used until the pack's real
-- rigged FBX models are imported (CreatureSpawner always prefers
-- ReplicatedStorage.Assets.Creatures.<ModelName> when it exists).
--
-- Built from primitives, but shaped like the real animals:
--   * bodies are LOFTED -- a chain of overlapping ellipsoids following a
--     tapering profile from the snout to the tail stock -- with a lighter
--     belly layered underneath (countershading), instead of one egg;
--   * fins, tails and wings are exact TRIANGLES (each a pair of wedges),
--     so a shark's dorsal is raked and sharp, a manta's wing pointed, a
--     reef fish's tail forked;
--   * eyes have a white, an iris, a pupil and a glint;
--   * the swimming is articulated: fish and sharks flex at mid-body and
--     again at the tail, a manta's wing ripples from root to tip, a
--     turtle's flipper bends at the elbow, a jellyfish's tentacles wave in
--     three segments.
--
-- Conventions: built around the origin, nose toward -Z (the direction
-- CreatureBrain steers), Y up; dimensions come from the species' real
-- measured Size (X = length, Y = height, Z = width/span), times `scale`.
-- The PrimaryPart is "Body". Rigid details are welded to what they sit
-- on; moving parts hang off Motor6D joints carrying Swing* attributes,
-- which CreatureAnimator (client) turns into motion locally.

local CreatureBodies = {}

local REEF_PALETTES = {
	-- clownfish: three white bands edged in black
	{ body = Color3.fromRGB(255, 118, 26), belly = Color3.fromRGB(255, 160, 80), band = Color3.fromRGB(250, 250, 250), edge = Color3.fromRGB(22, 22, 26), fin = Color3.fromRGB(255, 132, 40), iris = Color3.fromRGB(255, 150, 40), bands = { 0.17, 0.47, 0.76 } },
	-- blue tang: dark saddle, yellow tail
	{ body = Color3.fromRGB(36, 104, 228), belly = Color3.fromRGB(80, 150, 240), band = Color3.fromRGB(16, 26, 70), edge = Color3.fromRGB(16, 26, 70), fin = Color3.fromRGB(255, 212, 40), iris = Color3.fromRGB(40, 60, 120), bands = {}, saddle = true },
	-- yellow tang
	{ body = Color3.fromRGB(255, 212, 36), belly = Color3.fromRGB(255, 232, 120), band = Color3.fromRGB(255, 238, 130), edge = Color3.fromRGB(240, 186, 26), fin = Color3.fromRGB(255, 224, 80), iris = Color3.fromRGB(40, 40, 50), bands = {} },
	-- angelfish: yellow with dark bars and blue fins
	{ body = Color3.fromRGB(250, 228, 90), belly = Color3.fromRGB(252, 240, 170), band = Color3.fromRGB(26, 34, 70), edge = Color3.fromRGB(26, 34, 70), fin = Color3.fromRGB(70, 130, 230), iris = Color3.fromRGB(60, 120, 220), bands = { 0.28, 0.5, 0.7 } },
	-- royal gramma: magenta front, gold rear
	{ body = Color3.fromRGB(226, 70, 170), belly = Color3.fromRGB(240, 130, 200), band = Color3.fromRGB(255, 208, 60), edge = Color3.fromRGB(120, 40, 120), fin = Color3.fromRGB(255, 200, 70), iris = Color3.fromRGB(255, 200, 60), bands = {}, rearColor = Color3.fromRGB(255, 196, 50) },
}
CreatureBodies.ReefPaletteCount = #REEF_PALETTES

local EYE_WHITE = Color3.fromRGB(245, 245, 240)
local PUPIL = Color3.fromRGB(10, 10, 14)
local GLINT = Color3.fromRGB(255, 255, 255)

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

local function weld(to: BasePart, part: BasePart)
	local constraint = Instance.new("WeldConstraint")
	constraint.Part0 = to
	constraint.Part1 = part
	constraint.Parent = part
	return part
end

-- An invisible anchor for a group of parts that moves together (a tail,
-- a wing): the Motor6D drives it, the group is welded to it.
local function hub(model: Model, name: string, at: Vector3): Part
	local part = basePart("Part", model, name, Vector3.new(0.2, 0.2, 0.2), CFrame.new(at), Color3.new(1, 1, 1))
	part.Transparency = 1
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

-- An exact triangle a-b-c as two wedges (the classic Roblox technique):
-- the longest edge is split at the foot of the height from the opposite
-- corner, and each half is a right-angled wedge.
local function triangle(model: Model, name: string, a: Vector3, b: Vector3, c: Vector3, color: Color3, thickness: number, to: BasePart?, transparency: number?)
	local ab, ac, bc = b - a, c - a, c - b
	local abd, acd, bcd = ab:Dot(ab), ac:Dot(ac), bc:Dot(bc)
	-- Make b-c the longest edge.
	if abd > acd and abd > bcd then
		c, a = a, c
	elseif acd > bcd and acd > abd then
		a, b = b, a
	end
	ab, ac, bc = b - a, c - a, c - b
	local normal = ac:Cross(ab)
	if normal.Magnitude < 1e-6 or bc.Magnitude < 1e-6 then
		return {}
	end
	local right = normal.Unit
	local up = bc:Cross(right).Unit
	local back = bc.Unit
	local height = math.abs(ab:Dot(up))
	local wedges = {}
	local lengthB, lengthC = math.abs(ab:Dot(back)), math.abs(ac:Dot(back))
	if lengthB > 0.01 then
		table.insert(wedges, basePart("WedgePart", model, name, Vector3.new(thickness, height, lengthB), CFrame.fromMatrix((a + b) / 2, right, up, back), color))
	end
	if lengthC > 0.01 then
		table.insert(wedges, basePart("WedgePart", model, name, Vector3.new(thickness, height, lengthC), CFrame.fromMatrix((a + c) / 2, -right, up, -back), color))
	end
	for _, w in ipairs(wedges) do
		w.Transparency = transparency or 0
		if to then
			weld(to, w)
		end
	end
	return wedges
end

-- Tapering body profile, 0..1 along the body: rises from `nose` to 1 at
-- `peak`, falls to `tail` at the end.
local function profile(s: number, peak: number, tail: number, nose: number): number
	if s <= peak then
		return nose + (1 - nose) * math.sin(s / peak * math.pi / 2) ^ 0.75
	end
	local u = (s - peak) / (1 - peak)
	return tail + (1 - tail) * math.cos(u * math.pi / 2) ^ 1.1
end

-- A smooth body section: overlapping ellipsoids at `count` stations from
-- sFrom to sTo. `shape(s)` gives width, height and centre height at s;
-- `z(s)` the position along the body. The first ellipsoid is returned and
-- the others are welded to it (or all to `root`).
local function loft(model: Model, name: string, sFrom: number, sTo: number, count: number, z: (number) -> number, shape, color: Color3, root: BasePart?, material: Enum.Material?)
	local first = root
	local step = (sTo - sFrom) / math.max(count - 1, 1)
	local spacing = math.abs(z(sFrom + step) - z(sFrom))
	for i = 0, count - 1 do
		local s = sFrom + i * step
		local w, h, y = shape(s)
		-- Heavy overlap inside the section keeps the outline smooth (no
		-- bead-chain scallops); the end pieces stay short so the snout and
		-- the tail stock end where the profile says.
		local reach = (i == 0 or i == count - 1) and 1.7 or 3.4
		local segment = ellipsoid(model, (i == 0 and not root) and name or name .. "Seg", Vector3.new(w, h, spacing * reach), CFrame.new(0, y, z(s)), color, material)
		if first then
			weld(first, segment)
		else
			first = segment
		end
	end
	return first :: BasePart
end

local function eye(model: Model, on: BasePart, center: Vector3, size: number, side: number, iris: Color3, white: boolean?)
	if white ~= false then
		weld(on, ellipsoid(model, "EyeWhite", Vector3.new(size * 0.34, size, size), CFrame.new(center), EYE_WHITE))
	end
	weld(on, ellipsoid(model, "Iris", Vector3.new(size * 0.3, size * 0.8, size * 0.8), CFrame.new(center + Vector3.new(side * size * 0.07, 0, 0)), iris))
	weld(on, ellipsoid(model, "Pupil", Vector3.new(size * 0.3, size * 0.48, size * 0.48), CFrame.new(center + Vector3.new(side * size * 0.12, 0, 0)), PUPIL, Enum.Material.Glass))
	weld(on, ellipsoid(model, "EyeGlint", Vector3.new(size * 0.12, size * 0.16, size * 0.16), CFrame.new(center + Vector3.new(side * size * 0.17, size * 0.17, -size * 0.12)), GLINT, Enum.Material.Neon))
end

-- Species ---------------------------------------------------------------------------

local function reefFish(model: Model, L: number, H: number, _W: number, variant: number)
	local palette = REEF_PALETTES[(variant - 1) % #REEF_PALETTES + 1]
	local Hb, Wb = H * 0.8, L * 0.19
	local nose = -L / 2
	local function z(s: number): number
		return nose + s * L
	end
	local function w(s: number): number
		return Wb * profile(s, 0.34, 0.26, 0.3)
	end
	local function h(s: number): number
		return Hb * profile(s, 0.4, 0.22, 0.32)
	end
	local function top(s: number): number
		return h(s) * 0.48 + Hb * 0.04 * math.sin(math.pi * s)
	end
	local function shape(s: number)
		return w(s), h(s), Hb * 0.04 * math.sin(math.pi * s)
	end
	local function bellyShape(s: number)
		return w(s) * 0.95, h(s) * 0.66, -h(s) * 0.19
	end
	local rearColor = palette.rearColor or palette.body

	-- Front half and rear half, the rear flexing behind the front.
	local body = loft(model, "Body", 0.05, 0.48, 6, z, shape, palette.body)
	loft(model, "Belly", 0.1, 0.48, 4, z, bellyShape, palette.belly, body)
	local rear = loft(model, "Rear", 0.48, 0.8, 5, z, shape, rearColor)
	loft(model, "RearBelly", 0.5, 0.74, 3, z, bellyShape, palette.belly, rear)
	joint("BodyFlex", body, rear, Vector3.new(0, 0, z(0.48)), Vector3.new(0, 1, 0), math.rad(7), 2.2, 0)

	for _, s in ipairs(palette.bands) do
		local on = s < 0.49 and body or rear
		weld(on, ellipsoid(model, "BandEdge", Vector3.new(w(s) * 1.05, h(s) * 0.99, L * 0.095), CFrame.new(0, 0, z(s)), palette.edge))
		weld(on, ellipsoid(model, "Band", Vector3.new(w(s) * 1.08, h(s) * 0.96, L * 0.065), CFrame.new(0, 0, z(s)), palette.band))
	end
	if palette.saddle then
		weld(body, ellipsoid(model, "Saddle", Vector3.new(w(0.4) * 1.03, h(0.4) * 0.55, L * 0.32), CFrame.new(0, h(0.4) * 0.16, z(0.4)), palette.band))
		weld(rear, ellipsoid(model, "Saddle", Vector3.new(w(0.6) * 1.04, h(0.6) * 0.5, L * 0.2), CFrame.new(0, h(0.6) * 0.14, z(0.6)), palette.band))
	end
	weld(body, ellipsoid(model, "Gill", Vector3.new(w(0.26) * 1.02, h(0.26) * 0.78, L * 0.012), CFrame.new(0, -h(0.26) * 0.04, z(0.26)) * CFrame.Angles(math.rad(-10), 0, 0), palette.body:Lerp(Color3.new(0, 0, 0), 0.3)))
	weld(body, ellipsoid(model, "Mouth", Vector3.new(w(0.05) * 0.8, h(0.05) * 0.3, L * 0.05), CFrame.new(0, -h(0.05) * 0.08, z(0.035)), palette.edge))
	for _, side in ipairs({ -1, 1 }) do
		eye(model, body, Vector3.new(side * w(0.14) * 0.42, h(0.14) * 0.13, z(0.14)), Hb * 0.2, side, palette.iris)
	end

	-- Dorsal fin: a spiny run of triangles along the back.
	local dorsal = { 0.24, 0.36, 0.48, 0.6, 0.72 }
	for i = 1, #dorsal - 1 do
		local s0, s1 = dorsal[i], dorsal[i + 1]
		local rise = Hb * (0.3 - (i - 1) * 0.03)
		local on = s1 <= 0.49 and body or rear
		triangle(model, "DorsalFin", Vector3.new(0, top(s0) - 0.05, z(s0)), Vector3.new(0, top(s1) - 0.05, z(s1)), Vector3.new(0, top(s0) + rise, z(s0 + 0.07)), palette.fin, 0.06, on, 0.1)
	end
	-- Anal fin under the rear.
	triangle(model, "AnalFin", Vector3.new(0, -h(0.56) * 0.46, z(0.56)), Vector3.new(0, -h(0.74) * 0.46, z(0.74)), Vector3.new(0, -h(0.64) * 0.46 - Hb * 0.26, z(0.72)), palette.fin, 0.06, rear, 0.1)
	-- Pelvic fins.
	for _, side in ipairs({ -1, 1 }) do
		triangle(model, "PelvicFin", Vector3.new(side * w(0.3) * 0.2, -h(0.3) * 0.44, z(0.28)), Vector3.new(side * w(0.3) * 0.2, -h(0.36) * 0.44, z(0.36)), Vector3.new(side * w(0.3) * 0.55, -h(0.3) * 0.44 - Hb * 0.2, z(0.4)), palette.fin, 0.05, body, 0.15)
	end

	-- Forked tail, beating on its own joint behind the flexing rear.
	local stock = z(0.8)
	local tail = hub(model, "Tail", Vector3.new(0, 0, stock))
	local tipUp, tipDown, notch = Vector3.new(0, Hb * 0.46, z(1.0)), Vector3.new(0, -Hb * 0.46, z(1.0)), Vector3.new(0, 0, z(0.93))
	local rootUp, rootDown = Vector3.new(0, h(0.8) * 0.45, stock), Vector3.new(0, -h(0.8) * 0.45, stock)
	triangle(model, "TailFin", rootUp, tipUp, notch, palette.fin, 0.06, tail, 0.05)
	triangle(model, "TailFin", rootUp, notch, rootDown, palette.fin, 0.06, tail, 0.05)
	triangle(model, "TailFin", rootDown, notch, tipDown, palette.fin, 0.06, tail, 0.05)
	if #palette.bands > 0 then
		for _, sign in ipairs({ 1, -1 }) do
			triangle(model, "TailEdge", tipUp * Vector3.new(1, sign, 1), Vector3.new(0, sign * Hb * 0.38, z(0.97)), Vector3.new(0, sign * Hb * 0.3, z(0.99)), palette.edge, 0.07, tail)
		end
	end
	joint("TailJoint", rear, tail, Vector3.new(0, 0, stock), Vector3.new(0, 1, 0), math.rad(24), 2.2, -1.1)

	-- Pectoral fins, sculling.
	for _, side in ipairs({ -1, 1 }) do
		local base = Vector3.new(side * w(0.3) * 0.48, -h(0.3) * 0.1, z(0.3))
		local fin = hub(model, side < 0 and "PectoralL" or "PectoralR", base)
		triangle(model, "PectoralFin", base, base + Vector3.new(side * Hb * 0.1, Hb * 0.05, L * 0.08), base + Vector3.new(side * Hb * 0.34, -Hb * 0.12, L * 0.17), palette.fin, 0.04, fin, 0.3)
		joint(side < 0 and "FinL" or "FinR", body, fin, base, Vector3.new(0, 0, 1), math.rad(28), 2.6, side < 0 and 0 or math.pi)
	end
	return body
end

local function reefShark(model: Model, L: number, H: number, W: number)
	local TOP = Color3.fromRGB(104, 118, 132)
	local FLANK = Color3.fromRGB(150, 160, 170)
	local BELLY = Color3.fromRGB(238, 240, 242)
	local FIN = Color3.fromRGB(96, 110, 124)
	local TIP = Color3.fromRGB(22, 26, 32)
	local Hb, Wb = L * 0.17, L * 0.16
	local nose = -L / 2
	local function z(s: number): number
		return nose + s * L
	end
	local function w(s: number): number
		return Wb * profile(s, 0.33, 0.12, 0.12)
	end
	local function h(s: number): number
		return Hb * profile(s, 0.36, 0.15, 0.14)
	end
	local function top(s: number): number
		return h(s) * 0.48 + Hb * 0.03
	end
	local function shape(s: number)
		return w(s), h(s), Hb * 0.03 * math.sin(math.pi * s)
	end
	local function flankShape(s: number)
		return w(s) * 1.01, h(s) * 0.5, -h(s) * 0.06
	end
	local function bellyShape(s: number)
		return w(s) * 0.94, h(s) * 0.62, -h(s) * 0.22
	end

	local body = loft(model, "Body", 0.03, 0.5, 8, z, shape, TOP)
	loft(model, "Flank", 0.08, 0.5, 6, z, flankShape, FLANK, body)
	loft(model, "Belly", 0.06, 0.5, 6, z, bellyShape, BELLY, body)
	local rear = loft(model, "Rear", 0.5, 0.84, 6, z, shape, TOP)
	loft(model, "RearBelly", 0.52, 0.76, 3, z, bellyShape, BELLY, rear)
	joint("BodyFlex", body, rear, Vector3.new(0, 0, z(0.5)), Vector3.new(0, 1, 0), math.rad(6), 1.1, 0)

	-- Head: a crescent mouth, gill slits, small dark eyes.
	weld(body, ellipsoid(model, "Mouth", Vector3.new(w(0.12) * 0.8, h(0.12) * 0.12, L * 0.05), CFrame.new(0, -h(0.12) * 0.36, z(0.13)) * CFrame.Angles(math.rad(-12), 0, 0), Color3.fromRGB(60, 40, 44)))
	for _, side in ipairs({ -1, 1 }) do
		eye(model, body, Vector3.new(side * w(0.1) * 0.45, h(0.1) * 0.12, z(0.1)), Hb * 0.13, side, Color3.fromRGB(40, 44, 48), false)
		for i = 0, 4 do
			local s = 0.2 + i * 0.022
			weld(body, basePart("Part", model, "Gill", Vector3.new(0.06, h(s) * 0.42, 0.1), CFrame.new(side * w(s) * 0.49, -h(s) * 0.02, z(s)) * CFrame.Angles(math.rad(-8), 0, side * 0.1), Color3.fromRGB(64, 72, 82)))
		end
	end

	-- First dorsal: raked leading edge, concave trailing edge, black tip.
	local d0, d1 = Vector3.new(0, top(0.34) - 0.1, z(0.34)), Vector3.new(0, top(0.47) - 0.1, z(0.47))
	local dTip = Vector3.new(0, top(0.4) + H * 0.34, z(0.46))
	local dNotch = Vector3.new(0, top(0.47) + H * 0.05, z(0.5))
	triangle(model, "DorsalFin", d0, d1, dTip, FIN, 0.3, body)
	triangle(model, "DorsalFin", d1, dNotch, dTip, FIN, 0.26, body)
	triangle(model, "DorsalTip", dTip, dTip + (d0 - dTip) * 0.2, dTip + (d1 - dTip) * 0.2, TIP, 0.32, body)
	-- Second dorsal and anal fins on the rear.
	triangle(model, "SecondDorsal", Vector3.new(0, top(0.66) - 0.05, z(0.66)), Vector3.new(0, top(0.71) - 0.05, z(0.71)), Vector3.new(0, top(0.66) + H * 0.1, z(0.72)), FIN, 0.2, rear)
	triangle(model, "AnalFin", Vector3.new(0, -h(0.68) * 0.46, z(0.67)), Vector3.new(0, -h(0.73) * 0.46, z(0.73)), Vector3.new(0, -h(0.68) * 0.46 - H * 0.08, z(0.74)), FIN, 0.2, rear)
	-- Pectoral fins: long, swept and drooping, black-tipped; pelvics behind.
	for _, side in ipairs({ -1, 1 }) do
		local root0 = Vector3.new(side * w(0.24) * 0.4, -h(0.24) * 0.3, z(0.24))
		local root1 = Vector3.new(side * w(0.4) * 0.4, -h(0.4) * 0.3, z(0.4))
		local tip = Vector3.new(side * W * 0.48, -h(0.3) * 0.9, z(0.44))
		local fin = hub(model, side < 0 and "PectoralL" or "PectoralR", root0)
		triangle(model, "PectoralFin", root0, root1, tip, FIN, 0.22, fin)
		triangle(model, "PectoralTip", tip, tip + (root0 - tip) * 0.18, tip + (root1 - tip) * 0.18, TIP, 0.24, fin)
		joint(side < 0 and "FinL" or "FinR", body, fin, root0, Vector3.new(0, 0, 1), math.rad(6), 0.55, side < 0 and 0 or math.pi)
		triangle(model, "PelvicFin", Vector3.new(side * w(0.56) * 0.3, -h(0.56) * 0.44, z(0.55)), Vector3.new(side * w(0.6) * 0.3, -h(0.6) * 0.44, z(0.6)), Vector3.new(side * w(0.56) * 0.75, -h(0.56) * 0.44 - H * 0.07, z(0.63)), FIN, 0.14, rear)
	end

	-- Heterocercal tail: a tall upper lobe, a short lower one.
	local stock = z(0.84)
	local tail = hub(model, "Tail", Vector3.new(0, 0, stock))
	local up0, down0 = Vector3.new(0, h(0.84) * 0.5, stock), Vector3.new(0, -h(0.84) * 0.5, stock)
	local upperTip = Vector3.new(0, H * 0.4, z(1.02))
	local lowerTip = Vector3.new(0, -H * 0.2, z(0.95))
	local notch = Vector3.new(0, H * 0.02, z(0.92))
	triangle(model, "CaudalFin", up0, upperTip, notch, FIN, 0.24, tail)
	triangle(model, "CaudalFin", up0, notch, down0, FIN, 0.24, tail)
	triangle(model, "CaudalFin", down0, notch, lowerTip, FIN, 0.24, tail)
	triangle(model, "CaudalTip", upperTip, upperTip + (up0 - upperTip) * 0.16, upperTip + (notch - upperTip) * 0.2, TIP, 0.26, tail)
	triangle(model, "CaudalTip", lowerTip, lowerTip + (down0 - lowerTip) * 0.25, lowerTip + (notch - lowerTip) * 0.3, TIP, 0.26, tail)
	joint("TailJoint", rear, tail, Vector3.new(0, 0, stock), Vector3.new(0, 1, 0), math.rad(16), 1.1, -1.2)
	return body
end

local function manta(model: Model, L: number, H: number, W: number)
	local TOP = Color3.fromRGB(30, 36, 48)
	local BELLY = Color3.fromRGB(236, 238, 242)
	local CHEVRON = Color3.fromRGB(214, 220, 228)
	local SPOT = Color3.fromRGB(46, 50, 60)
	local nose = -L * 0.42
	local function z(s: number): number
		return nose + s * L * 0.8
	end
	local function shape(s: number)
		return W * 0.2 * profile(s, 0.45, 0.2, 0.55), H * 0.85 * profile(s, 0.4, 0.2, 0.5), 0
	end
	local function bellyShape(s: number)
		local bw, bh = shape(s)
		return bw * 0.96, bh * 0.6, -bh * 0.22
	end
	local body = loft(model, "Body", 0.05, 0.85, 6, z, shape, TOP)
	loft(model, "Belly", 0.08, 0.8, 5, z, bellyShape, BELLY, body)

	-- Mouth, curled cephalic fins, eyes on the sides of the head.
	weld(body, ellipsoid(model, "Mouth", Vector3.new(W * 0.1, H * 0.2, L * 0.04), CFrame.new(0, -H * 0.05, z(0.03)), Color3.fromRGB(20, 22, 28)))
	for _, side in ipairs({ -1, 1 }) do
		weld(body, ellipsoid(model, "CephalicFin", Vector3.new(W * 0.035, H * 0.7, L * 0.15), CFrame.new(side * W * 0.075, -H * 0.1, z(-0.02)) * CFrame.Angles(0.35, 0, side * 0.35), TOP))
		weld(body, ellipsoid(model, "CephalicCurl", Vector3.new(W * 0.03, H * 0.4, L * 0.06), CFrame.new(side * W * 0.07, -H * 0.42, z(-0.08)) * CFrame.Angles(1.1, 0, 0), BELLY))
		eye(model, body, Vector3.new(side * W * 0.1, H * 0.08, z(0.12)), H * 0.3, side, Color3.fromRGB(30, 32, 40), false)
		-- White shoulder chevrons.
		triangle(model, "Chevron", Vector3.new(side * W * 0.035, H * 0.44, z(0.2)), Vector3.new(side * W * 0.2, H * 0.3, z(0.3)), Vector3.new(side * W * 0.06, H * 0.43, z(0.44)), CHEVRON, 0.08, body)
	end
	for i = 1, 5 do
		weld(body, ellipsoid(model, "BellySpot", Vector3.new(W * 0.025, 0.1, W * 0.025), CFrame.new((i % 2 == 0 and 1 or -1) * W * 0.03 * i * 0.5, -H * 0.43, z(0.3 + i * 0.07)), SPOT))
	end

	-- Wings: an inner panel and an outer, pointed, swept-back panel, each on
	-- its own joint so the flap travels out to the tip. Dark on top, white
	-- beneath (two layers).
	for _, side in ipairs({ -1, 1 }) do
		local rootLead = Vector3.new(side * W * 0.08, 0, z(0.12))
		local rootTrail = Vector3.new(side * W * 0.08, 0, z(0.72))
		local midLead = Vector3.new(side * W * 0.29, 0, z(0.3))
		local midTrail = Vector3.new(side * W * 0.27, 0, z(0.6))
		local tip = Vector3.new(side * W * 0.5, 0, z(0.66))
		local inner = hub(model, side < 0 and "WingL" or "WingR", rootLead)
		local outer = hub(model, side < 0 and "WingTipL" or "WingTipR", midLead)
		for _, layer in ipairs({ { TOP, 0.05 }, { BELLY, -0.07 } }) do
			local lift = Vector3.new(0, layer[2], 0)
			triangle(model, "Wing", rootLead + lift, midLead + lift, midTrail + lift, layer[1], 0.12, inner)
			triangle(model, "Wing", rootLead + lift, midTrail + lift, rootTrail + lift, layer[1], 0.12, inner)
			triangle(model, "WingOuter", midLead + lift, tip + lift, midTrail + lift, layer[1], 0.1, outer)
		end
		-- A rounded leading edge.
		weld(inner, ellipsoid(model, "LeadingEdge", Vector3.new(0.3, H * 0.28, (midLead - rootLead).Magnitude), CFrame.lookAt((rootLead + midLead) / 2, midLead), TOP))
		weld(outer, ellipsoid(model, "LeadingEdge", Vector3.new(0.24, H * 0.2, (tip - midLead).Magnitude), CFrame.lookAt((midLead + tip) / 2, tip), TOP))
		joint(side < 0 and "WingJointL" or "WingJointR", body, inner, rootLead, Vector3.new(0, 0, side), math.rad(20), 0.32, 0)
		joint(side < 0 and "WingTipJointL" or "WingTipJointR", inner, outer, midLead, Vector3.new(0, 0, side), math.rad(18), 0.32, -0.9)
	end
	-- Pelvic fins and the whip of a tail.
	for _, side in ipairs({ -1, 1 }) do
		triangle(model, "PelvicFin", Vector3.new(side * W * 0.03, -H * 0.1, z(0.8)), Vector3.new(side * W * 0.06, -H * 0.1, z(0.9)), Vector3.new(side * W * 0.1, -H * 0.1, z(0.84)), TOP, 0.08, body)
	end
	local tailRoot = hub(model, "TailWhip", Vector3.new(0, 0, z(0.88)))
	local tail = basePart("Part", model, "Tail", Vector3.new(L * 0.45, 0.2, 0.2), CFrame.new(0, 0, z(0.88) + L * 0.22) * CFrame.Angles(0, math.pi / 2, 0), TOP)
	tail.Shape = Enum.PartType.Cylinder
	weld(tailRoot, tail)
	joint("TailJoint", body, tailRoot, Vector3.new(0, 0, z(0.88)), Vector3.new(0, 1, 0), math.rad(8), 0.32, -1.5)
	return body
end

local function seaTurtle(model: Model, L: number, H: number, W: number)
	local SHELL = Color3.fromRGB(96, 76, 44)
	local SCUTE_LIGHT = Color3.fromRGB(150, 116, 62)
	local SCUTE_DARK = Color3.fromRGB(108, 84, 46)
	local SEAM = Color3.fromRGB(58, 44, 28)
	local RIM = Color3.fromRGB(170, 140, 80)
	local PLASTRON = Color3.fromRGB(226, 208, 150)
	local SKIN = Color3.fromRGB(120, 138, 92)
	local SCALE = Color3.fromRGB(78, 88, 56)

	local shellW, shellH, shellL = W * 0.5, H * 0.66, L * 0.62
	local body = ellipsoid(model, "Body", Vector3.new(shellW, shellH, shellL), CFrame.new(0, H * 0.06, L * 0.02), SHELL)
	weld(body, ellipsoid(model, "Plastron", Vector3.new(shellW * 0.86, shellH * 0.42, shellL * 0.9), CFrame.new(0, -H * 0.14, L * 0.02), PLASTRON))
	-- The carapace: a row of five vertebral scutes, four costal scutes each
	-- side, each on a darker seam so the plates read, and a ring of
	-- marginal scutes round the rim.
	local function dome(x: number, zz: number): number
		local u, v = x / (shellW * 0.5), (zz - L * 0.02) / (shellL * 0.5)
		return H * 0.06 + shellH * 0.5 * math.sqrt(math.max(0, 1 - u * u - v * v))
	end
	local function scute(x: number, zz: number, sx: number, sz: number, color: Color3)
		local y = dome(x, zz)
		local tilt = CFrame.Angles(-(zz - L * 0.02) / shellL * 0.9, 0, x / shellW * 0.9)
		weld(body, ellipsoid(model, "ScuteSeam", Vector3.new(sx * 1.12, shellH * 0.16, sz * 1.12), CFrame.new(x, y - shellH * 0.07, zz) * tilt, SEAM))
		weld(body, ellipsoid(model, "Scute", Vector3.new(sx, shellH * 0.16, sz), CFrame.new(x, y - shellH * 0.05, zz) * tilt, color))
	end
	for i = 0, 4 do
		local zz = L * 0.02 + (i - 2) * shellL * 0.19
		scute(0, zz, shellW * 0.28, shellL * 0.17, i % 2 == 0 and SCUTE_LIGHT or SCUTE_DARK)
	end
	for _, side in ipairs({ -1, 1 }) do
		for i = 0, 3 do
			local zz = L * 0.02 + (i - 1.5) * shellL * 0.21
			scute(side * shellW * 0.28, zz, shellW * 0.24, shellL * 0.19, (i + (side > 0 and 1 or 0)) % 2 == 0 and SCUTE_LIGHT or SCUTE_DARK)
		end
	end
	for i = 0, 21 do
		local a = i / 22 * math.pi * 2
		local x, zz = math.cos(a) * shellW * 0.5, L * 0.02 + math.sin(a) * shellL * 0.5
		weld(body, ellipsoid(model, "Marginal", Vector3.new(shellW * 0.12, shellH * 0.14, shellL * 0.1), CFrame.new(x, -H * 0.02, zz) * CFrame.Angles(0, -a, 0), i % 2 == 0 and RIM or SCUTE_DARK))
	end

	-- Head on a short neck, with plated scales, a hooked beak and eyes.
	local neck = ellipsoid(model, "Neck", Vector3.new(W * 0.12, H * 0.34, L * 0.14), CFrame.new(0, H * 0.02, -L * 0.33), SKIN)
	weld(body, neck)
	local head = ellipsoid(model, "Head", Vector3.new(W * 0.15, H * 0.44, L * 0.17), CFrame.new(0, H * 0.06, -L * 0.42), SKIN)
	weld(body, head)
	weld(head, ellipsoid(model, "Beak", Vector3.new(W * 0.09, H * 0.2, L * 0.06), CFrame.new(0, -H * 0.02, -L * 0.505) * CFrame.Angles(0.3, 0, 0), Color3.fromRGB(70, 66, 50)))
	for i, spot in ipairs({ { 0, 0.2, -0.43 }, { -0.035, 0.16, -0.39 }, { 0.035, 0.16, -0.39 }, { 0, 0.18, -0.36 } }) do
		weld(head, ellipsoid(model, "HeadScale", Vector3.new(W * 0.05, H * 0.08, L * 0.04), CFrame.new(spot[1] * W, spot[2] * H, spot[3] * L), i % 2 == 0 and SCALE or SCALE:Lerp(SKIN, 0.4)))
	end
	for _, side in ipairs({ -1, 1 }) do
		eye(model, head, Vector3.new(side * W * 0.06, H * 0.1, -L * 0.45), H * 0.15, side, Color3.fromRGB(50, 40, 30), false)
	end

	-- Front flippers: long curved paddles in two parts (arm and blade), the
	-- blade following the arm's stroke a moment later. Rear flippers:
	-- short rudders.
	for _, side in ipairs({ -1, 1 }) do
		local shoulder = Vector3.new(side * shellW * 0.4, -H * 0.06, -L * 0.2)
		local elbow = shoulder + Vector3.new(side * W * 0.16, 0, L * 0.02)
		local tip = elbow + Vector3.new(side * W * 0.24, -H * 0.04, L * 0.2)
		local arm = ellipsoid(model, "FrontFlipper", Vector3.new(W * 0.18, H * 0.14, L * 0.09), CFrame.lookAt((shoulder + elbow) / 2, elbow) * CFrame.Angles(0, math.pi / 2, 0), SKIN)
		local blade = ellipsoid(model, "FlipperBlade", Vector3.new((tip - elbow).Magnitude * 1.1, H * 0.1, L * 0.1), CFrame.lookAt((elbow + tip) / 2, tip) * CFrame.Angles(0, math.pi / 2, 0), SKIN)
		for k = 1, 3 do
			weld(blade, ellipsoid(model, "FlipperScale", Vector3.new(W * 0.05, H * 0.11, L * 0.035), CFrame.new(elbow:Lerp(tip, k * 0.25) + Vector3.new(0, H * 0.01, 0)), SCALE))
		end
		joint(side < 0 and "FlipperFL" or "FlipperFR", body, arm, shoulder, Vector3.new(0, 0, side), math.rad(30), 0.45, 0)
		joint(side < 0 and "FlipperBladeL" or "FlipperBladeR", arm, blade, elbow, Vector3.new(0, 0, side), math.rad(18), 0.45, -0.8)
		local rear = ellipsoid(model, "RearFlipper", Vector3.new(W * 0.16, H * 0.09, L * 0.13), CFrame.new(side * shellW * 0.44, -H * 0.08, L * 0.3) * CFrame.Angles(0, math.rad(side * 40), 0), SKIN)
		weld(rear, ellipsoid(model, "FlipperScale", Vector3.new(W * 0.05, H * 0.1, L * 0.04), CFrame.new(side * shellW * 0.5, -H * 0.07, L * 0.32), SCALE))
		joint(side < 0 and "FlipperRL" or "FlipperRR", body, rear, Vector3.new(side * shellW * 0.35, -H * 0.08, L * 0.26), Vector3.new(0, 1, 0), math.rad(16), 0.45, math.pi / 2)
	end
	weld(body, ellipsoid(model, "Tail", Vector3.new(W * 0.05, H * 0.12, L * 0.1), CFrame.new(0, -H * 0.05, L * 0.36), SKIN))
	return body
end

local function jellyfish(model: Model, L: number, H: number, W: number, glow: Color3?)
	local BELL = Color3.fromRGB(176, 214, 248)
	local INNER = Color3.fromRGB(210, 230, 252)
	local GLOW = glow or Color3.fromRGB(120, 220, 255)
	local GONAD = Color3.fromRGB(255, 150, 220)
	local ARM = Color3.fromRGB(232, 168, 222)

	local diameter = math.max(L, W) * 0.82
	local bellY = H * 0.28
	local body = ellipsoid(model, "Body", Vector3.new(diameter, diameter * 0.62, diameter), CFrame.new(0, bellY, 0), BELL, Enum.Material.Glass)
	body.Transparency = 0.45
	local inner = ellipsoid(model, "InnerBell", Vector3.new(diameter * 0.84, diameter * 0.46, diameter * 0.84), CFrame.new(0, bellY - diameter * 0.03, 0), INNER, Enum.Material.Glass)
	inner.Transparency = 0.55
	weld(body, inner)
	local core = ellipsoid(model, "GlowCore", Vector3.new(diameter * 0.4, diameter * 0.22, diameter * 0.4), CFrame.new(0, bellY - diameter * 0.04, 0), GLOW, Enum.Material.Neon)
	core.Transparency = 0.35
	weld(body, core)
	local light = Instance.new("PointLight")
	light.Color = GLOW
	light.Range = 16
	light.Brightness = 1.6
	light.Parent = core
	-- Four horseshoe gonads and eight radial canals glowing through the bell.
	for i = 1, 4 do
		local a = i / 4 * math.pi * 2 + math.pi / 4
		for k = -1, 1 do
			local b = a + k * 0.35
			weld(body, ellipsoid(model, "Gonad", Vector3.new(diameter * 0.1, diameter * 0.05, diameter * 0.06), CFrame.new(math.cos(b) * diameter * 0.17, bellY + diameter * 0.08, math.sin(b) * diameter * 0.17) * CFrame.Angles(0, -b, 0), GONAD, Enum.Material.Neon))
		end
	end
	for i = 1, 8 do
		local a = i / 8 * math.pi * 2
		local from = Vector3.new(math.cos(a) * diameter * 0.12, bellY + diameter * 0.24, math.sin(a) * diameter * 0.12)
		local to = Vector3.new(math.cos(a) * diameter * 0.46, bellY - diameter * 0.06, math.sin(a) * diameter * 0.46)
		local canal = weld(body, basePart("Part", model, "Canal", Vector3.new(0.08, 0.08, (to - from).Magnitude), CFrame.lookAt((from + to) / 2, to), GLOW, Enum.Material.Neon))
		canal.Transparency = 0.4
	end

	-- Scalloped rim, marginal tentacles in three waving segments.
	local rimY = bellY - diameter * 0.22
	for i = 1, 16 do
		local a = i / 16 * math.pi * 2
		weld(body, ellipsoid(model, "Lappet", Vector3.new(diameter * 0.16, diameter * 0.08, diameter * 0.1), CFrame.new(math.cos(a) * diameter * 0.45, rimY, math.sin(a) * diameter * 0.45) * CFrame.Angles(0, -a, 0), BELL, Enum.Material.Glass)).Transparency = 0.4
	end
	for i = 1, 12 do
		local a = i / 12 * math.pi * 2 + 0.13
		local top = Vector3.new(math.cos(a) * diameter * 0.44, rimY - 0.05, math.sin(a) * diameter * 0.44)
		local total = H * (0.52 + (i % 3) * 0.1)
		local swing = Vector3.new(math.sin(a), 0, -math.cos(a))
		local parent: BasePart = body
		for k = 1, 3 do
			local length = total / 3
			local segment = basePart("Part", model, "Tentacle", Vector3.new(0.09 - k * 0.015, length, 0.09 - k * 0.015), CFrame.new(top - Vector3.new(0, length / 2, 0)), GLOW, Enum.Material.Neon)
			segment.Transparency = 0.35 + k * 0.1
			joint("Tentacle" .. i .. "_" .. k, parent, segment, top, swing, math.rad(10 + k * 4), 0.5, i * 0.7 - k * 0.9)
			parent = segment
			top -= Vector3.new(0, length, 0)
		end
	end
	-- Frilly oral arms, two segments each.
	for i = 1, 4 do
		local a = i / 4 * math.pi * 2 + 0.4
		local top = Vector3.new(math.cos(a) * diameter * 0.08, rimY + diameter * 0.04, math.sin(a) * diameter * 0.08)
		local armLength = H * 0.26
		local swing = Vector3.new(math.cos(a), 0, math.sin(a))
		local parent: BasePart = body
		for k = 1, 2 do
			local arm = ellipsoid(model, "OralArm", Vector3.new(diameter * (0.13 - k * 0.02), armLength, diameter * 0.06), CFrame.new(top - Vector3.new(0, armLength / 2, 0)) * CFrame.Angles(0, a, 0.06), ARM)
			arm.Transparency = 0.3
			for f = 1, 2 do
				weld(arm, ellipsoid(model, "OralFrill", Vector3.new(diameter * 0.15, armLength * 0.3, diameter * 0.04), CFrame.new(top - Vector3.new(0, armLength * (0.3 + f * 0.3), 0)) * CFrame.Angles(0, a + f * 0.9, -0.12), ARM)).Transparency = 0.35
			end
			joint("OralArm" .. i .. "_" .. k, parent, arm, top, swing, math.rad(8 + k * 3), 0.35, i * 1.3 - k * 0.8)
			parent = arm
			top -= Vector3.new(0, armLength, 0)
		end
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

-- A small decorative fish for client-side ambient shoals: anchored parts,
-- moved by the client as a whole. A two-part lofted body with a lighter
-- belly, an eye, a dorsal fin and a forked tail -- few parts, since
-- shoals hold many. `tint` (optional) replaces the reef palette (silver
-- for mid-water, a glowing blue for the abyss).
function CreatureBodies.BuildSmallFish(length: number, variant: number, tint: Color3?, glow: boolean?): Model
	local model = Instance.new("Model")
	local palette = REEF_PALETTES[(variant - 1) % #REEF_PALETTES + 1]
	local bodyColor = tint or palette.body
	local bellyColor = tint and tint:Lerp(Color3.new(1, 1, 1), 0.45) or palette.belly
	local finColor = tint and tint:Lerp(Color3.new(1, 1, 1), 0.2) or palette.fin
	local material = glow and Enum.Material.Neon or Enum.Material.SmoothPlastic
	local h, w = length * 0.42, length * 0.2
	local body = ellipsoid(model, "Body", Vector3.new(w, h, length * 0.58), CFrame.new(0, 0, -length * 0.14), bodyColor, material)
	local parts = { body }
	table.insert(parts, ellipsoid(model, "Rear", Vector3.new(w * 0.7, h * 0.62, length * 0.4), CFrame.new(0, 0, length * 0.16), bodyColor, material))
	table.insert(parts, ellipsoid(model, "Belly", Vector3.new(w * 0.94, h * 0.6, length * 0.5), CFrame.new(0, -h * 0.18, -length * 0.12), bellyColor, material))
	if not tint and #palette.bands > 0 then
		table.insert(parts, ellipsoid(model, "Band", Vector3.new(w * 1.06, h * 0.95, length * 0.08), CFrame.new(0, 0, -length * 0.2), palette.band))
	end
	table.insert(parts, ellipsoid(model, "Eye", Vector3.new(w * 1.04, h * 0.22, h * 0.22), CFrame.new(0, h * 0.1, -length * 0.32), PUPIL, Enum.Material.Glass))
	local tail = length * 0.34
	for _, p in ipairs(triangle(model, "Tail", Vector3.new(0, 0, tail), Vector3.new(0, h * 0.55, length * 0.52), Vector3.new(0, 0, length * 0.44), finColor, 0.05)) do
		table.insert(parts, p)
	end
	for _, p in ipairs(triangle(model, "Tail", Vector3.new(0, 0, tail), Vector3.new(0, 0, length * 0.44), Vector3.new(0, -h * 0.55, length * 0.52), finColor, 0.05)) do
		table.insert(parts, p)
	end
	for _, p in ipairs(triangle(model, "Dorsal", Vector3.new(0, h * 0.42, -length * 0.22), Vector3.new(0, h * 0.34, length * 0.1), Vector3.new(0, h * 0.72, -length * 0.02), finColor, 0.04)) do
		table.insert(parts, p)
	end
	for _, part in ipairs(parts) do
		part.Anchored = true
		part.Massless = false
		if glow then
			part.Material = Enum.Material.Neon
		end
	end
	model.PrimaryPart = body
	return model
end

return CreatureBodies
