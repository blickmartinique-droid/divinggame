-- A kit of detailed marine life models, shared by the world builders
-- (BiomeDecor for the reef, the kelp forests and the abyss; the wreck
-- graveyard for its growth). Every model is built from plain parts --
-- rods (cylinders run between two points), ellipsoids and exact
-- triangles -- in organic arrangements:
--
--   * stony corals: branching staghorn with pale growing tips, brain
--     coral with its maze of ridges, table coral with a scalloped rim,
--     mushroom coral, puffy soft coral;
--   * sea fans (a branch lattice over a translucent mesh), barrel and
--     tube sponges with their dark openings, anemones with two rings of
--     tentacles (and their clownfish);
--   * giant kelp: holdfast, a jointed stipe with gas bladders and blades
--     and a crown of fronds -- animated as a chain by FloraAnimator, so a
--     wave travels up each stalk;
--   * urchins, starfish, giant clams, black-smoker chimneys, tube worms,
--     sea lilies, sea pens, Venus' flower baskets, glowing tunicates.
--
-- Swaying: a Model tagged "Sway" bends at its joints (Joint1..JointN
-- CFrame attributes; each part's Segment attribute says which joint it
-- hangs from, 0 = rooted); a BasePart tagged "Sway" rocks about its own
-- base. Both are animated per client by FloraAnimator.

local CollectionService = game:GetService("CollectionService")

local MarineFlora = {}
MarineFlora.__index = MarineFlora

local UP = Vector3.new(0, 1, 0)
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)

export type Kit = typeof(setmetatable({} :: { rng: Random, count: number }, MarineFlora))

function MarineFlora.new(rng: Random): Kit
	return setmetatable({ rng = rng, count = 0 }, MarineFlora)
end

-- Random helpers ----------------------------------------------------------------------
function MarineFlora.random(self: Kit): number
	return self.rng:NextNumber()
end

function MarineFlora.range(self: Kit, low: number, high: number): number
	return low + self.rng:NextNumber() * (high - low)
end

function MarineFlora.pick(self: Kit, list: { any }): any
	return list[self.rng:NextInteger(1, #list)]
end

-- `dir` turned by `angle` towards a random side.
function MarineFlora.bend(self: Kit, dir: Vector3, angle: number): Vector3
	local ref = math.abs(dir.Y) < 0.95 and UP or Vector3.new(1, 0, 0)
	local u = dir:Cross(ref).Unit
	local v = dir:Cross(u).Unit
	local spin = self:random() * math.pi * 2
	local side = u * math.cos(spin) + v * math.sin(spin)
	return (dir * math.cos(angle) + side * math.sin(angle)).Unit
end

-- A frame at `position` whose Y axis is `dir`.
local function frameY(position: Vector3, dir: Vector3): CFrame
	local ref = math.abs(dir.Y) < 0.95 and UP or Vector3.new(1, 0, 0)
	local right = ref:Cross(dir).Unit
	return CFrame.fromMatrix(position, right, dir)
end
MarineFlora.frameY = frameY

-- Primitives ------------------------------------------------------------------------------
function MarineFlora.part(self: Kit, parent: Instance, name: string, size: Vector3, cframe: CFrame, material: Enum.Material, color: Color3, shape: Enum.PartType?): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = size.Magnitude > 6
	part.Shape = shape or Enum.PartType.Block
	part.Size = size
	part.CFrame = cframe
	part.Material = material
	part.Color = color
	part.Parent = parent
	self.count += 1
	return part
end

function MarineFlora.ellipsoid(self: Kit, parent: Instance, name: string, size: Vector3, cframe: CFrame, material: Enum.Material, color: Color3): Part
	local part = self:part(parent, name, size, cframe, material, color)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = part
	return part
end

-- A cylinder from a to b (a Cylinder part's axis is its X). `overlap`
-- lengthens it past both ends so jointed rods read as one piece.
function MarineFlora.rod(self: Kit, parent: Instance, name: string, a: Vector3, b: Vector3, radius: number, material: Enum.Material, color: Color3, overlap: number?): Part
	local axis = b - a
	local length = axis.Magnitude
	local dir = length > 1e-4 and axis / length or UP
	local ref = math.abs(dir.Y) < 0.95 and UP or Vector3.new(1, 0, 0)
	local up = dir:Cross(ref).Unit
	local extra = overlap or radius * 0.8
	return self:part(parent, name, Vector3.new(length + extra, radius * 2, radius * 2), CFrame.fromMatrix((a + b) / 2, dir, up), material, color, Enum.PartType.Cylinder)
end

-- A flat disc of `diameter`, lying in the plane whose normal is `normal`.
function MarineFlora.disc(self: Kit, parent: Instance, name: string, center: Vector3, normal: Vector3, diameter: number, thickness: number, material: Enum.Material, color: Color3): Part
	local ref = math.abs(normal.Y) < 0.95 and UP or Vector3.new(1, 0, 0)
	return self:part(parent, name, Vector3.new(thickness, diameter, diameter), CFrame.fromMatrix(center, normal, normal:Cross(ref).Unit), material, color, Enum.PartType.Cylinder)
end

-- An exact triangle a-b-c as two wedges (the longest edge is split at the
-- foot of the height from the opposite corner).
function MarineFlora.triangle(self: Kit, parent: Instance, name: string, a: Vector3, b: Vector3, c: Vector3, material: Enum.Material, color: Color3, thickness: number, transparency: number?): { WedgePart }
	local ab, ac, bc = b - a, c - a, c - b
	local abd, acd, bcd = ab:Dot(ab), ac:Dot(ac), bc:Dot(bc)
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
	local function wedge(size: Vector3, cframe: CFrame)
		local w = Instance.new("WedgePart")
		w.Name = name
		w.Anchored = true
		w.CanCollide = false
		w.CanQuery = false
		w.CanTouch = false
		w.CastShadow = false
		w.Size = size
		w.CFrame = cframe
		w.Material = material
		w.Color = color
		w.Transparency = transparency or 0
		w.Parent = parent
		self.count += 1
		table.insert(wedges, w)
	end
	local lengthB, lengthC = math.abs(ab:Dot(back)), math.abs(ac:Dot(back))
	if lengthB > 0.01 then
		wedge(Vector3.new(thickness, height, lengthB), CFrame.fromMatrix((a + b) / 2, right, up, back))
	end
	if lengthC > 0.01 then
		wedge(Vector3.new(thickness, height, lengthC), CFrame.fromMatrix((a + c) / 2, -right, up, -back))
	end
	return wedges
end

function MarineFlora.model(_self: Kit, parent: Instance, name: string): Model
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = parent
	return model
end

-- Pivot set once the parts are in (a new Model's pivot follows its first
-- part otherwise).
local function finish(model: Model, pivot: CFrame): Model
	model.WorldPivot = pivot
	return model
end

-- Tags a model to bend at `joints` (see the header).
function MarineFlora.swayModel(_self: Kit, model: Model, joints: { CFrame }, amplitude: number, speed: number)
	CollectionService:AddTag(model, "Sway")
	model:SetAttribute("SwayAmplitude", amplitude)
	model:SetAttribute("SwaySpeed", speed)
	model:SetAttribute("SwayJoints", #joints)
	for index, joint in ipairs(joints) do
		model:SetAttribute("Joint" .. index, joint)
	end
end

function MarineFlora.swayPart(_self: Kit, part: BasePart, amplitude: number, speed: number): BasePart
	CollectionService:AddTag(part, "Sway")
	part:SetAttribute("Sway", true)
	part:SetAttribute("SwayAmplitude", amplitude)
	part:SetAttribute("SwaySpeed", speed)
	return part
end

local function segment(part: Instance, index: number)
	part:SetAttribute("Segment", index)
end

local function tint(color: Color3, amount: number): Color3
	return amount >= 0 and color:Lerp(WHITE, amount) or color:Lerp(BLACK, -amount)
end
MarineFlora.tint = tint

-- Stony corals -------------------------------------------------------------------------------

-- Staghorn / bush coral: antler branches forking out of an encrusting
-- base, each tip pale where the coral grows.
function MarineFlora.Branching(self: Kit, parent: Instance, base: Vector3, height: number, color: Color3): Model
	local model = self:model(parent, "BranchCoral")
	local tipColor = tint(color, 0.5)
	local radius = height * 0.05
	self:ellipsoid(model, "CoralBase", Vector3.new(height * 0.55, height * 0.16, height * 0.55), CFrame.new(base), Enum.Material.Pebble, tint(color, -0.25))
	local bushy = self:random() < 0.4
	local primaries = bushy and self.rng:NextInteger(5, 6) or self.rng:NextInteger(3, 4)
	for k = 1, primaries do
		local dir = self:bend(UP, self:range(0.45, 1.05))
		local length = height * (bushy and self:range(0.35, 0.5) or self:range(0.45, 0.6))
		local from = base + Vector3.new(0, height * 0.04, 0)
		local to = from + dir * length
		self:rod(model, "Branch", from, to, radius, Enum.Material.SmoothPlastic, color)
		local forks = bushy and 1 or 2
		for f = 1, forks do
			local childDir = (self:bend(dir, self:range(0.4, 0.8)) + UP * 0.2).Unit
			local childLength = length * self:range(0.6, 0.9)
			local tip = to + childDir * childLength
			self:rod(model, "Branch", to, tip, radius * 0.72, Enum.Material.SmoothPlastic, color)
			self:ellipsoid(model, "BranchTip", Vector3.new(radius * 1.7, radius * 2.6, radius * 1.7), frameY(tip, childDir), Enum.Material.SmoothPlastic, tipColor)
		end
		if k % 2 == 0 then
			self:ellipsoid(model, "BranchKnot", Vector3.new(radius * 2.3, radius * 2.3, radius * 2.3), CFrame.new(to), Enum.Material.SmoothPlastic, color)
		end
	end
	return finish(model, CFrame.new(base))
end

-- Brain coral: a dome grooved by meandering ridges (random walks over
-- its surface).
function MarineFlora.Brain(self: Kit, parent: Instance, base: Vector3, size: number, color: Color3): Model
	local model = self:model(parent, "BrainCoral")
	local a, b = size / 2, size * 0.31
	local center = base + Vector3.new(0, b * 0.45, 0)
	self:ellipsoid(model, "BrainDome", Vector3.new(size, b * 2, size), CFrame.new(center), Enum.Material.Pebble, tint(color, -0.2))
	local ridgeColor = tint(color, 0.3)
	local segmentLength = size * 0.15
	-- A point of the dome (relative to its centre), its outward normal and
	-- its direction on the unit sphere.
	local function onDome(v: Vector3): (Vector3, Vector3, Vector3)
		local u = Vector3.new(v.X / a, v.Y / b, v.Z / a).Unit
		return Vector3.new(u.X * a, u.Y * b, u.Z * a), Vector3.new(u.X / a, u.Y / b, u.Z / a).Unit, u
	end
	-- Each ridge is a walk over the dome, one segment from the end of the
	-- last, turning left and right: a continuous meander. Walks start
	-- spread over the cap (golden-angle spiral) so the maze covers it.
	local walks = 8
	for w = 1, walks do
		local theta = math.acos(1 - (w - 1) / (walks - 1) * 0.75)
		local phi = w * 2.39996 + self:range(-0.3, 0.3)
		local here, normal, u = onDome(Vector3.new(math.sin(theta) * math.cos(phi), math.cos(theta), math.sin(theta) * math.sin(phi)))
		local along = self:bend(normal, math.pi / 2)
		local turn = self:random() < 0.5 and -1 or 1
		for _ = 1, 4 do
			if u.Y < 0.08 then
				break
			end
			local nextPoint, nextNormal, nextU = onDome(here + along * segmentLength)
			local mid, midNormal = onDome((here + nextPoint) / 2)
			local step = nextPoint - here
			local dir = (step - midNormal * step:Dot(midNormal)).Unit
			self:ellipsoid(model, "BrainRidge", Vector3.new(size * 0.07, size * 0.09, step.Magnitude * 1.3), CFrame.fromMatrix(center + mid + midNormal * size * 0.015, midNormal:Cross(dir), midNormal), Enum.Material.SmoothPlastic, ridgeColor)
			-- Carry the heading over the curve, then swing it.
			local tangent = (along - nextNormal * along:Dot(nextNormal)).Unit
			local angle = self:range(0.35, 0.9) * turn
			along = (tangent * math.cos(angle) + nextNormal:Cross(tangent) * math.sin(angle)).Unit
			if self:random() < 0.6 then
				turn = -turn
			end
			here, u = nextPoint, nextU
		end
	end
	return finish(model, CFrame.new(base))
end

-- Table coral: a stalk under a wide, slightly tilted plate with a
-- scalloped rim and upturned branchlets on top.
function MarineFlora.Table(self: Kit, parent: Instance, base: Vector3, width: number, color: Color3): Model
	local model = self:model(parent, "TableCoral")
	local h = width * self:range(0.22, 0.32)
	self:ellipsoid(model, "CoralBase", Vector3.new(width * 0.3, width * 0.1, width * 0.3), CFrame.new(base), Enum.Material.Pebble, tint(color, -0.25))
	self:rod(model, "TableStalk", base, base + Vector3.new(0, h, 0), width * 0.06, Enum.Material.SmoothPlastic, tint(color, -0.1))
	local top = CFrame.new(base + Vector3.new(0, h, 0)) * CFrame.Angles(self:range(-0.12, 0.12), self:range(0, math.pi * 2), self:range(-0.12, 0.12))
	local plate = self:part(model, "TableCoral", Vector3.new(width * 0.05, width, width), top * CFrame.Angles(0, 0, math.pi / 2), Enum.Material.Pebble, color, Enum.PartType.Cylinder)
	plate.CastShadow = true
	local offset = Vector3.new(self:range(-0.1, 0.1) * width, width * 0.04, self:range(-0.1, 0.1) * width)
	self:part(model, "TableCoral", Vector3.new(width * 0.05, width * 0.62, width * 0.62), top * CFrame.new(offset) * CFrame.Angles(0, 0, math.pi / 2), Enum.Material.Pebble, tint(color, 0.08), Enum.PartType.Cylinder)
	local rim = 10
	for k = 1, rim do
		local angle = k / rim * math.pi * 2 + self:range(-0.1, 0.1)
		self:ellipsoid(model, "TableRim", Vector3.new(width * 0.13, width * 0.07, width * 0.26), top * CFrame.Angles(0, -angle, 0) * CFrame.new(width * 0.47, width * 0.02, 0) * CFrame.Angles(0, 0, 0.3), Enum.Material.SmoothPlastic, tint(color, 0.15))
	end
	local nubColor = tint(color, 0.35)
	for _ = 1, 8 do
		local angle, r = self:range(0, math.pi * 2), math.sqrt(self:random()) * width * 0.4
		local foot = top * Vector3.new(math.cos(angle) * r, width * 0.02, math.sin(angle) * r)
		self:rod(model, "TableNub", foot, foot + top:VectorToWorldSpace(Vector3.new(0, width * 0.09, 0)), width * 0.018, Enum.Material.SmoothPlastic, nubColor)
	end
	return finish(model, CFrame.new(base))
end

-- Mushroom coral: a free-living disc with radiating septa.
function MarineFlora.Mushroom(self: Kit, parent: Instance, base: Vector3, size: number, color: Color3): Model
	local model = self:model(parent, "MushroomCoral")
	local frame = CFrame.new(base + Vector3.new(0, size * 0.08, 0)) * CFrame.Angles(self:range(-0.1, 0.1), self:range(0, math.pi * 2), 0)
	self:ellipsoid(model, "MushroomDisc", Vector3.new(size, size * 0.22, size * 0.8), frame, Enum.Material.SmoothPlastic, color)
	for k = 1, 8 do
		local angle = k / 8 * math.pi * 2
		self:ellipsoid(model, "MushroomSeptum", Vector3.new(size * 0.46, size * 0.08, size * 0.05), frame * CFrame.Angles(0, angle, 0) * CFrame.new(size * 0.2, size * 0.08, 0), Enum.Material.SmoothPlastic, tint(color, 0.25))
	end
	return finish(model, CFrame.new(base))
end

-- Soft coral (Dendronephthya): a translucent trunk branching into puffs
-- of polyps.
function MarineFlora.SoftCoral(self: Kit, parent: Instance, base: Vector3, height: number, color: Color3): Model
	local model = self:model(parent, "SoftCoral")
	local trunkTop = base + Vector3.new(0, height * 0.35, 0)
	local trunk = self:rod(model, "SoftTrunk", base, trunkTop, height * 0.09, Enum.Material.SmoothPlastic, tint(color, 0.55))
	trunk.Transparency = 0.25
	local puff = tint(color, 0.1)
	for k = 1, 4 do
		local dir = self:bend(UP, self:range(0.35, 0.8))
		local tip = trunkTop + dir * height * self:range(0.35, 0.55)
		local branch = self:rod(model, "SoftBranch", trunkTop, tip, height * 0.045, Enum.Material.SmoothPlastic, tint(color, 0.5))
		branch.Transparency = 0.25
		for p = 1, 3 do
			local at = tip + self:bend(dir, self:range(0.2, 1.1)) * height * 0.11 * (p == 1 and 0.4 or 1)
			local s = height * self:range(0.14, 0.22)
			self:ellipsoid(model, "SoftPolyps", Vector3.new(s, s * 0.85, s), CFrame.new(at) * CFrame.Angles(0, k + p, 0), Enum.Material.SmoothPlastic, k % 2 == 0 and puff or color)
		end
	end
	self:swayModel(model, { CFrame.new(base) }, 0.05, 0.5)
	return finish(model, CFrame.new(base))
end

-- Sea fans and sponges -------------------------------------------------------------------------

-- Gorgonian sea fan in the XY plane of `frame` (Y up the fan): a trunk,
-- fanning branches and their twigs over a translucent mesh.
function MarineFlora.SeaFan(self: Kit, parent: Instance, frame: CFrame, height: number, color: Color3): Model
	local model = self:model(parent, "SeaFan")
	local base = frame.Position
	local hub = frame * Vector3.new(0, height * 0.18, 0)
	local branchColor = tint(color, -0.15)
	self:rod(model, "FanTrunk", base, hub, height * 0.035, Enum.Material.SmoothPlastic, branchColor)
	for k = 1, 5 do
		local spread = (k - 3) / 2 * 1.0 + self:range(-0.1, 0.1)
		local dir = frame:VectorToWorldSpace(Vector3.new(math.sin(spread), math.cos(spread), 0))
		local mid = hub + dir * height * self:range(0.36, 0.46)
		self:rod(model, "FanBranch", hub, mid, height * 0.02, Enum.Material.SmoothPlastic, branchColor)
		for _, side in ipairs({ -1, 1 }) do
			local twist = spread + side * self:range(0.18, 0.34)
			local twigDir = frame:VectorToWorldSpace(Vector3.new(math.sin(twist), math.cos(twist), 0))
			self:rod(model, "FanTwig", mid, mid + twigDir * height * self:range(0.26, 0.4), height * 0.013, Enum.Material.SmoothPlastic, branchColor)
		end
	end
	local mesh = self:ellipsoid(model, "FanMesh", Vector3.new(height * 1.2, height * 0.88, 0.06), frame * CFrame.new(0, height * 0.56, 0), Enum.Material.Fabric, color)
	mesh.Transparency = 0.3
	self:swayModel(model, { frame }, 0.06, self:range(0.5, 0.8))
	return finish(model, frame)
end

-- Barrel sponge: ridged staves flaring out to a wide rim around a dark
-- cavity. `frame`'s Y is the barrel's axis.
function MarineFlora.Barrel(self: Kit, parent: Instance, frame: CFrame, height: number, color: Color3): Model
	local model = self:model(parent, "BarrelSponge")
	local r0, r1 = height * 0.3, height * 0.44
	local rMid = (r0 + r1) / 2
	local lean = math.atan((r1 - r0) / height)
	local staves = 10
	for k = 1, staves do
		local angle = k / staves * math.pi * 2
		self:part(model, "BarrelStave", Vector3.new(2 * math.pi * rMid / staves * 1.12, height / math.cos(lean), height * 0.1), frame * CFrame.Angles(0, angle, 0) * CFrame.new(0, height / 2, -rMid) * CFrame.Angles(-lean, 0, 0), Enum.Material.Pebble, k % 2 == 0 and color or tint(color, -0.18))
	end
	self:part(model, "BarrelCavity", Vector3.new(0.15, r1 * 1.75, r1 * 1.75), frame * CFrame.new(0, height * 0.72, 0) * CFrame.Angles(0, 0, math.pi / 2), Enum.Material.SmoothPlastic, Color3.fromRGB(28, 18, 16), Enum.PartType.Cylinder)
	self:ellipsoid(model, "BarrelFoot", Vector3.new(r0 * 2.3, height * 0.25, r0 * 2.3), frame, Enum.Material.Pebble, tint(color, -0.3))
	return finish(model, frame)
end

-- Tube sponges: a clump of hollow tubes, each with a lip and a dark mouth.
function MarineFlora.TubeSponges(self: Kit, parent: Instance, base: Vector3, height: number, color: Color3): Model
	local model = self:model(parent, "TubeSponges")
	local dark = Color3.fromRGB(34, 20, 18)
	for _ = 1, self.rng:NextInteger(3, 5) do
		local foot = base + Vector3.new(self:range(-0.9, 0.9), -0.2, self:range(-0.9, 0.9)) * height * 0.3
		local dir = self:bend(UP, self:range(0.05, 0.35))
		local h = height * self:range(0.55, 1)
		local r = height * self:range(0.09, 0.13)
		local top = foot + dir * h
		self:rod(model, "TubeSponge", foot, top, r, Enum.Material.Pebble, color)
		self:rod(model, "TubeLip", top - dir * r * 0.5, top + dir * 0.04, r * 1.15, Enum.Material.Pebble, tint(color, 0.12), 0)
		self:rod(model, "TubeMouth", top + dir * 0.04, top + dir * 0.1, r * 0.82, Enum.Material.SmoothPlastic, dark, 0)
	end
	return finish(model, CFrame.new(base))
end

-- Anemone: a column, an oral disc and two rings of tentacles, each
-- rocking on its own. Returns the model and the point over its disc.
function MarineFlora.Anemone(self: Kit, parent: Instance, base: Vector3, radius: number, column: Color3, tentacle: Color3, glow: boolean?, outer: number?): (Model, Vector3)
	local model = self:model(parent, "Anemone")
	local top = base + Vector3.new(0, radius * 0.8, 0)
	self:rod(model, "AnemoneColumn", base - Vector3.new(0, 0.2, 0), top, radius * 0.62, Enum.Material.SmoothPlastic, column)
	self:ellipsoid(model, "AnemoneDisc", Vector3.new(radius * 1.8, radius * 0.35, radius * 1.8), CFrame.new(top), Enum.Material.SmoothPlastic, tint(column, 0.2))
	local material = glow and Enum.Material.Neon or Enum.Material.SmoothPlastic
	local rings = { { count = outer or 12, at = 0.78, lean = 0.62, length = 1.55, color = tentacle }, { count = math.max(5, math.floor((outer or 12) * 0.6)), at = 0.4, lean = 0.25, length = 1.15, color = tint(tentacle, 0.3) } }
	local spin = self:range(0, math.pi)
	for _, ring in ipairs(rings) do
		for k = 1, ring.count do
			local angle = spin + k / ring.count * math.pi * 2
			local out = Vector3.new(math.cos(angle), 0, math.sin(angle))
			local dir = (out * math.sin(ring.lean) + UP * math.cos(ring.lean)).Unit
			local length = radius * ring.length * self:range(0.85, 1.1)
			local foot = top + out * radius * ring.at
			local t = self:ellipsoid(model, "AnemoneTentacle", Vector3.new(radius * 0.2, length, radius * 0.2), frameY(foot + dir * length * 0.45, dir), material, ring.color)
			t.Transparency = glow and 0.2 or 0.05
			self:swayPart(t, 0.2, self:range(0.6, 1))
		end
	end
	return finish(model, CFrame.new(base)), top + Vector3.new(0, radius * 1.2, 0)
end

-- Clownfish: orange, three white bands, a rounded tail. Animated by
-- ReefLife on each client around its `Home` anemone.
function MarineFlora.Clownfish(self: Kit, parent: Instance, home: Vector3, index: number): Model
	local model = self:model(parent, "Clownfish")
	local frame = CFrame.new(home + Vector3.new(index * 0.8 - 0.4, 0, 0))
	local orange, white = Color3.fromRGB(255, 120, 30), Color3.fromRGB(250, 250, 245)
	local body = self:ellipsoid(model, "Body", Vector3.new(0.32, 0.46, 0.95), frame, Enum.Material.SmoothPlastic, orange)
	self:ellipsoid(model, "Band", Vector3.new(0.34, 0.47, 0.1), frame * CFrame.new(0, 0, -0.24), Enum.Material.SmoothPlastic, white)
	self:ellipsoid(model, "Band", Vector3.new(0.33, 0.42, 0.1), frame * CFrame.new(0, 0, 0.1), Enum.Material.SmoothPlastic, white)
	self:ellipsoid(model, "Tail", Vector3.new(0.06, 0.42, 0.26), frame * CFrame.new(0, 0, 0.55), Enum.Material.SmoothPlastic, orange)
	self:ellipsoid(model, "Band", Vector3.new(0.07, 0.34, 0.08), frame * CFrame.new(0, 0, 0.45), Enum.Material.SmoothPlastic, white)
	for _, side in ipairs({ -1, 1 }) do
		self:ellipsoid(model, "Eye", Vector3.new(0.06, 0.1, 0.1), frame * CFrame.new(side * 0.14, 0.06, -0.34), Enum.Material.SmoothPlastic, Color3.fromRGB(10, 10, 12))
	end
	model.PrimaryPart = body
	model:SetAttribute("Home", home)
	model:SetAttribute("Phase", index * math.pi + self:range(0, 1))
	CollectionService:AddTag(model, "ReefFish")
	return finish(model, frame)
end

-- Kelp ------------------------------------------------------------------------------------------

-- Giant kelp: a holdfast, a stipe of `n` jointed segments -- each with a
-- gas bladder and a blade -- and a crown of fronds. Bends as a chain.
function MarineFlora.Kelp(self: Kit, parent: Instance, base: Vector3, height: number, color: Color3): Model
	local model = self:model(parent, "GiantKelp")
	local n = math.clamp(math.floor(height / 7 + 0.5), 4, 7)
	local length = height / n
	local stipeColor = tint(color, -0.18)
	local bladderColor = color:Lerp(Color3.fromRGB(190, 170, 70), 0.45)
	for k = 1, 3 do
		local root = self:ellipsoid(model, "Holdfast", Vector3.new(0.5, 0.45, 1.6), CFrame.new(base) * CFrame.Angles(0, k * math.pi * 2 / 3 + self:range(-0.4, 0.4), 0) * CFrame.new(0, 0.05, -0.55) * CFrame.Angles(0.35, 0, 0), Enum.Material.Grass, tint(color, -0.35))
		segment(root, 0)
	end
	local frame = CFrame.new(base) * CFrame.Angles(self:range(-0.06, 0.06), self:range(0, math.pi * 2), self:range(-0.06, 0.06))
	local joints = {}
	local yaw = self:range(0, math.pi * 2)
	for k = 1, n do
		joints[k] = frame
		local top = frame * Vector3.new(0, length, 0)
		local stipe = self:rod(model, "KelpStipe", frame.Position, top, 0.3 - 0.12 * (k - 1) / n, Enum.Material.Grass, stipeColor)
		stipe.CastShadow = false
		segment(stipe, k)
		do
			yaw += 2.4
			local at = frame * CFrame.new(0, length * 0.9, 0) * CFrame.Angles(0, yaw, 0)
			local bladder = self:ellipsoid(model, "KelpBladder", Vector3.new(0.5, 0.8, 0.5), at * CFrame.new(0, 0.1, -0.4) * CFrame.Angles(-0.6, 0, 0), Enum.Material.SmoothPlastic, bladderColor)
			segment(bladder, k)
			local bladeLength = self:range(4.8, 7)
			local blade = self:ellipsoid(model, "KelpBlade", Vector3.new(self:range(1.2, 1.7), bladeLength, 0.08), at * CFrame.new(0, 0.3, -0.75) * CFrame.Angles(-0.5, 0, self:range(-0.15, 0.15)) * CFrame.new(0, bladeLength / 2, 0), Enum.Material.SmoothPlastic, k % 2 == 0 and color or tint(color, 0.08))
			blade.CastShadow = false
			segment(blade, k)
		end
		frame = CFrame.new(top) * frame.Rotation * CFrame.Angles(self:range(-0.08, 0.08), 0, self:range(-0.08, 0.08))
	end
	local crown = frame
	for k = 1, 3 do
		local frondLength = self:range(4.5, 6.5)
		local frond = self:ellipsoid(model, "KelpBlade", Vector3.new(1.3, frondLength, 0.08), crown * CFrame.Angles(0, k * 2.1, 0) * CFrame.Angles(-0.9, 0, 0) * CFrame.new(0, frondLength / 2, 0), Enum.Material.SmoothPlastic, tint(color, 0.05))
		frond.CastShadow = false
		segment(frond, n)
	end
	self:swayModel(model, joints, 0.05, self:range(0.22, 0.34))
	return finish(model, CFrame.new(base))
end

-- Reef floor --------------------------------------------------------------------------------------

function MarineFlora.Urchin(self: Kit, parent: Instance, base: Vector3, size: number): Model
	local model = self:model(parent, "Urchin")
	local center = base + Vector3.new(0, size * 0.28, 0)
	local body = self:pick({ Color3.fromRGB(40, 30, 60), Color3.fromRGB(70, 24, 40), Color3.fromRGB(20, 20, 28) })
	self:ellipsoid(model, "UrchinBody", Vector3.new(size, size * 0.72, size), CFrame.new(center), Enum.Material.Pebble, body)
	local spines = 14
	for k = 1, spines do
		-- Fibonacci points over the upper three quarters of the sphere.
		local y = 1 - (k - 0.5) / spines * 1.5
		local r = math.sqrt(math.max(0, 1 - y * y))
		local phi = k * 2.39996
		local dir = Vector3.new(math.cos(phi) * r, y, math.sin(phi) * r)
		self:rod(model, "UrchinSpine", center + dir * size * 0.3, center + dir * size * self:range(0.95, 1.2), size * 0.03, Enum.Material.SmoothPlastic, tint(body, -0.3), 0)
	end
	return finish(model, CFrame.new(base))
end

function MarineFlora.Starfish(self: Kit, parent: Instance, base: Vector3, size: number, color: Color3): Model
	local model = self:model(parent, "Starfish")
	local frame = CFrame.new(base + Vector3.new(0, size * 0.06, 0)) * CFrame.Angles(0, self:range(0, math.pi * 2), 0)
	self:ellipsoid(model, "StarfishDisc", Vector3.new(size * 0.45, size * 0.16, size * 0.45), frame, Enum.Material.Pebble, color)
	for k = 1, 5 do
		local arm = frame * CFrame.Angles(0, k / 5 * math.pi * 2, 0) * CFrame.new(size * 0.33, 0, 0) * CFrame.Angles(0, 0, 0.08)
		self:ellipsoid(model, "StarfishArm", Vector3.new(size * 0.66, size * 0.13, size * 0.24), arm, Enum.Material.Pebble, color)
		self:ellipsoid(model, "StarfishRidge", Vector3.new(size * 0.46, size * 0.06, size * 0.07), arm * CFrame.new(-size * 0.04, size * 0.06, 0), Enum.Material.Pebble, tint(color, 0.3))
	end
	return finish(model, CFrame.new(base))
end

-- Giant clam: two scalloped valves of fanned ribs, gaping on a blue mantle.
function MarineFlora.Clam(self: Kit, parent: Instance, base: Vector3, size: number): Model
	local model = self:model(parent, "GiantClam")
	local frame = CFrame.new(base + Vector3.new(0, size * 0.05, 0)) * CFrame.Angles(0, self:range(0, math.pi * 2), 0)
	local shell = Color3.fromRGB(170, 160, 176)
	for _, side in ipairs({ -1, 1 }) do
		for k = 1, 5 do
			local t = (k - 3) / 2
			local tall = size * (0.62 - 0.14 * t * t)
			self:ellipsoid(model, "ClamShell", Vector3.new(size * 0.24, tall, size * 0.16), frame * CFrame.new(t * size * 0.36, 0, 0) * CFrame.Angles(side * 0.45, 0, t * -0.25) * CFrame.new(0, tall * 0.42, 0), Enum.Material.Pebble, k % 2 == 0 and shell or tint(shell, -0.1))
		end
	end
	local mantle = { Color3.fromRGB(40, 170, 210), Color3.fromRGB(70, 90, 220), Color3.fromRGB(40, 190, 170) }
	for k = 1, 3 do
		local t = (k - 2)
		self:ellipsoid(model, "ClamMantle", Vector3.new(size * 0.42, size * 0.16, size * 0.3), frame * CFrame.new(t * size * 0.3, size * 0.5, 0) * CFrame.Angles(0, 0, t * 0.2), Enum.Material.SmoothPlastic, mantle[k])
	end
	for k = 1, 4 do
		local spot = self:ellipsoid(model, "ClamSpot", Vector3.new(size * 0.07, size * 0.04, size * 0.07), frame * CFrame.new((k - 2.5) * size * 0.2, size * 0.58, self:range(-0.06, 0.06) * size), Enum.Material.Neon, Color3.fromRGB(140, 240, 255))
		spot.Transparency = 0.2
	end
	return finish(model, CFrame.new(base))
end

-- Seagrass meadow: blades rocking on their own.
function MarineFlora.Seagrass(self: Kit, parent: Instance, ground: (number, number) -> Vector3, center: Vector3, spread: number, blades: number)
	local greens = { Color3.fromRGB(80, 150, 70), Color3.fromRGB(96, 160, 64), Color3.fromRGB(70, 132, 74), Color3.fromRGB(120, 160, 70) }
	for _ = 1, blades do
		local at = ground(center.X + self:range(-0.5, 0.5) * spread, center.Z + self:range(-0.5, 0.5) * spread)
		local height = self:range(1.5, 4)
		self:swayPart(self:part(parent, "Seagrass", Vector3.new(0.28, height, 0.06), CFrame.new(at + Vector3.new(0, height / 2 - 0.1, 0)) * CFrame.Angles(0, self:range(0, math.pi), self:range(-0.15, 0.15)), Enum.Material.Grass, self:pick(greens)), 0.18, self:range(0.9, 1.3))
	end
end

-- Hydrothermal vents ------------------------------------------------------------------------------

-- Black smoker: an uneven stack of sulphide blocks with ledges ("flanges")
-- and mineral crusts, smaller spires beside it and bacterial mats around.
-- Returns the model and its glowing throat.
function MarineFlora.Chimney(self: Kit, parent: Instance, base: Vector3, height: number, ground: (number, number) -> Vector3): (Model, Part)
	local model = self:model(parent, "BlackSmoker")
	local rock = { Color3.fromRGB(34, 30, 34), Color3.fromRGB(52, 40, 36), Color3.fromRGB(78, 52, 38) }
	local crust = { Color3.fromRGB(170, 120, 50), Color3.fromRGB(190, 160, 70), Color3.fromRGB(120, 70, 40) }
	local function stack(foot: Vector3, total: number, bottomWidth: number, topWidth: number, count: number, withLedges: boolean): Vector3
		local y = foot.Y - 1.2
		local drift = Vector3.new(self:range(-0.25, 0.25), 0, self:range(-0.25, 0.25))
		local center = Vector3.new(foot.X, 0, foot.Z)
		for s = 1, count do
			local sh = total / count
			local width = (bottomWidth + (topWidth - bottomWidth) * (s - 1) / math.max(1, count - 1)) * self:range(0.85, 1.1)
			if s > 1 then
				center += drift * width * 0.3
			end
			local frame = CFrame.new(center.X, y + sh / 2, center.Z) * CFrame.Angles(self:range(-0.08, 0.08), self:range(0, 3), self:range(-0.08, 0.08))
			self:part(model, "Chimney", Vector3.new(width, sh + 0.6, width * self:range(0.8, 1)), frame, Enum.Material.Basalt, rock[(s % #rock) + 1])
			if withLedges and s >= 2 and s < count and self:random() < 0.65 then
				local ledge = frame * CFrame.new(self:range(-0.3, 0.3) * width, sh * 0.4, self:range(-0.3, 0.3) * width)
				self:part(model, "Flange", Vector3.new(0.5, width * 1.7, width * 1.5), ledge * CFrame.Angles(0, 0, math.pi / 2), Enum.Material.Basalt, Color3.fromRGB(58, 44, 38), Enum.PartType.Cylinder)
			end
			if withLedges then
				local side = self:range(0, math.pi * 2)
				self:ellipsoid(model, "MineralCrust", Vector3.new(width * 0.5, sh * 0.7, width * 0.35), frame * CFrame.new(math.cos(side) * width * 0.45, 0, math.sin(side) * width * 0.45), Enum.Material.Sand, self:pick(crust))
			end
			y += sh
		end
		return Vector3.new(center.X, y, center.Z)
	end
	local mouth = stack(base, height, 6.5, 2.2, 6, true)
	local throat = self:part(model, "VentThroat", Vector3.new(1.6, 0.6, 1.6), CFrame.new(mouth), Enum.Material.Neon, Color3.fromRGB(255, 110, 40))
	for k = 1, 2 do
		local angle = self:range(0, math.pi * 2)
		local spot = ground(base.X + math.cos(angle) * (5 + k), base.Z + math.sin(angle) * (5 + k))
		local top = stack(spot, height * self:range(0.25, 0.4), 2, 0.9, 3, false)
		self:part(model, "SpireThroat", Vector3.new(0.6, 0.3, 0.6), CFrame.new(top), Enum.Material.Neon, Color3.fromRGB(255, 140, 60))
	end
	for _ = 1, 5 do
		local angle, distance = self:range(0, math.pi * 2), self:range(4, 10)
		local spot = ground(base.X + math.cos(angle) * distance, base.Z + math.sin(angle) * distance)
		local s = self:range(3, 6)
		self:ellipsoid(model, "BacterialMat", Vector3.new(s, 0.25, s * self:range(0.6, 1)), CFrame.new(spot) * CFrame.Angles(0, angle, 0), Enum.Material.SmoothPlastic, self:random() < 0.5 and Color3.fromRGB(235, 232, 220) or Color3.fromRGB(220, 200, 120))
	end
	return finish(model, CFrame.new(base)), throat
end

-- Riftia tube worms: white tubes with a collar and a blood-red plume.
function MarineFlora.TubeWorm(self: Kit, parent: Instance, foot: Vector3, height: number): Model
	local model = self:model(parent, "TubeWorm")
	local dir = self:bend(UP, self:range(0, 0.2))
	local top = foot + dir * height
	self:rod(model, "TubeWorm", foot - dir * 0.3, top, 0.17, Enum.Material.SmoothPlastic, Color3.fromRGB(230, 226, 214))
	self:rod(model, "WormCollar", top - dir * 0.15, top + dir * 0.05, 0.22, Enum.Material.SmoothPlastic, Color3.fromRGB(245, 240, 232), 0)
	local plume = self:ellipsoid(model, "WormPlume", Vector3.new(0.55, 0.9, 0.55), frameY(top + dir * 0.4, dir), Enum.Material.Neon, Color3.fromRGB(220, 40, 50))
	plume.Transparency = 0.1
	self:swayPart(plume, 0.2, self:range(0.5, 0.9))
	return finish(model, CFrame.new(foot))
end

-- Abyss ---------------------------------------------------------------------------------------------

-- Sea lily: a jointed stalk with cirri whorls, a cup and curling
-- feather arms. Sways from the seabed and again at the cup.
function MarineFlora.Crinoid(self: Kit, parent: Instance, base: Vector3, height: number, color: Color3): Model
	local model = self:model(parent, "Crinoid")
	local stalkColor = Color3.fromRGB(190, 170, 150)
	local dir = self:bend(UP, self:range(0, 0.12))
	local joints = { frameY(base, dir) }
	local cup = base + dir * height
	for s = 1, 3 do
		local a, b = base + dir * height * (s - 1) / 3, base + dir * height * s / 3
		segment(self:rod(model, "CrinoidStalk", a, b, 0.14, Enum.Material.SmoothPlastic, stalkColor), 1)
		if s < 3 then
			segment(self:ellipsoid(model, "CrinoidCirri", Vector3.new(0.7, 0.14, 0.7), frameY(b, dir), Enum.Material.Fabric, tint(stalkColor, -0.15)), 1)
		end
	end
	joints[2] = frameY(cup, dir)
	segment(self:ellipsoid(model, "CrinoidCup", Vector3.new(0.7, 0.5, 0.7), frameY(cup, dir), Enum.Material.SmoothPlastic, tint(color, -0.2)), 2)
	local arms = 7
	for k = 1, arms do
		local angle = k / arms * math.pi * 2
		local out = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local rise = (out * 0.75 + UP * 0.66).Unit
		local mid = cup + rise * 1.3
		segment(self:ellipsoid(model, "CrinoidArm", Vector3.new(0.5, 1.6, 0.14), frameY(cup + rise * 0.7, rise), Enum.Material.Fabric, color), 2)
		local curl = (out * 0.85 - UP * 0.5).Unit
		segment(self:ellipsoid(model, "CrinoidArm", Vector3.new(0.4, 1.3, 0.12), frameY(mid + curl * 0.55, curl), Enum.Material.Fabric, tint(color, 0.15)), 2)
	end
	self:swayModel(model, joints, 0.07, self:range(0.3, 0.45))
	return finish(model, CFrame.new(base))
end

-- Sea pen: a stalk and a glowing feather of polyp leaves.
function MarineFlora.SeaPen(self: Kit, parent: Instance, base: Vector3, height: number, glowColor: Color3): Model
	local model = self:model(parent, "SeaPen")
	local stalkTop = base + Vector3.new(0, height * 0.35, 0)
	self:rod(model, "SeaPenStalk", base - Vector3.new(0, 0.3, 0), stalkTop, 0.13, Enum.Material.SmoothPlastic, Color3.fromRGB(200, 180, 200))
	local rachis = self:rod(model, "SeaPenRachis", stalkTop, base + Vector3.new(0, height, 0), 0.09, Enum.Material.Neon, tint(glowColor, 0.3))
	rachis.Transparency = 0.25
	local yaw = self:range(0, math.pi * 2)
	for k = 1, 8 do
		local t = 0.42 + (k - 1) / 7 * 0.52
		local side = k % 2 == 0 and 1 or -1
		local length = height * 0.22 * (1.25 - t * 0.7)
		local leaf = self:ellipsoid(model, "SeaPenLeaf", Vector3.new(length, height * 0.08, 0.12), CFrame.new(base + Vector3.new(0, height * t, 0)) * CFrame.Angles(0, yaw, 0) * CFrame.new(side * length * 0.45, 0, 0) * CFrame.Angles(0, 0, side * 0.35), Enum.Material.Neon, glowColor)
		leaf.Transparency = 0.25
	end
	self:swayModel(model, { CFrame.new(base) }, 0.08, self:range(0.35, 0.55))
	return finish(model, CFrame.new(base))
end

-- Venus' flower basket: a glass vase woven of two opposite spirals of
-- silica staves, capped by a sieve plate.
function MarineFlora.GlassSponge(self: Kit, parent: Instance, base: Vector3, height: number): Model
	local model = self:model(parent, "GlassSponge")
	local glass = Color3.fromRGB(220, 235, 240)
	local r0, r1 = height * 0.09, height * 0.15
	local lower = self:rod(model, "GlassSponge", base, base + Vector3.new(0, height * 0.55, 0), r0 * 0.95, Enum.Material.Glass, glass)
	lower.Transparency = 0.45
	local upper = self:rod(model, "GlassSponge", base + Vector3.new(0, height * 0.45, 0), base + Vector3.new(0, height, 0), r1 * 0.9, Enum.Material.Glass, glass)
	upper.Transparency = 0.45
	for _, twist in ipairs({ 0.55, -0.55 }) do
		for k = 1, 6 do
			local angle = k / 6 * math.pi * 2
			local a = base + Vector3.new(math.cos(angle) * r0, 0, math.sin(angle) * r0)
			local b = base + Vector3.new(math.cos(angle + twist) * r1, height, math.sin(angle + twist) * r1)
			local stave = self:rod(model, "GlassStave", a, b, 0.06, Enum.Material.SmoothPlastic, Color3.fromRGB(240, 245, 248), 0)
			stave.Transparency = 0.15
		end
	end
	local sieve = self:disc(model, "GlassSieve", base + Vector3.new(0, height, 0), UP, r1 * 2.1, 0.12, Enum.Material.Glass, Color3.fromRGB(235, 245, 250))
	sieve.Transparency = 0.3
	return finish(model, CFrame.new(base))
end

-- Land -------------------------------------------------------------------------------------------

-- A coconut palm frond: a midrib rising out of the crown then arching
-- down in three jointed lengths, each carrying a pair of leaflet sheets
-- that hang in a V. Bends as a chain in the breeze.
function MarineFlora.PalmFrond(self: Kit, parent: Instance, crown: CFrame, yaw: number, length: number, color: Color3): Model
	local model = self:model(parent, "PalmFrond")
	local frame = crown * CFrame.Angles(0, yaw, 0) * CFrame.Angles(self:range(0.3, 0.6), 0, 0)
	local lengths = { length * 0.34, length * 0.36, length * 0.3 }
	local widths = { 1.9, 1.7, 1.0 }
	local droops = { 0.4, 0.5, 0.55 }
	local rib = color:Lerp(Color3.fromRGB(190, 180, 100), 0.5)
	local joints = {}
	for k = 1, 3 do
		joints[k] = frame
		local l = lengths[k]
		segment(self:part(model, "FrondRib", Vector3.new(0.16, 0.16, l + 0.12), frame * CFrame.new(0, 0, -l / 2), Enum.Material.Wood, rib), k)
		-- Leaflets: long narrow strips swept forward from the rib and
		-- hanging down, two per side along each length.
		local leaflet = widths[k] * length / 8 * 1.35
		local hang = 0.55 + k * 0.1
		for _, side in ipairs({ -1, 1 }) do
			for _, t in ipairs({ 0.3, 0.78 }) do
				local strip = self:ellipsoid(model, "PalmLeaflet", Vector3.new(0.42, 0.05, leaflet), frame * CFrame.new(0, 0, -l * t) * CFrame.Angles(0, -side * 1.0, 0) * CFrame.Angles(-hang, 0, 0) * CFrame.new(0, 0, -leaflet / 2), Enum.Material.Grass, t < 0.5 and color or tint(color, -0.1))
				segment(strip, k)
			end
		end
		frame = frame * CFrame.new(0, 0, -l) * CFrame.Angles(-droops[k], 0, 0)
	end
	self:swayModel(model, joints, 0.035, self:range(0.25, 0.4))
	return finish(model, crown)
end

-- Caves -------------------------------------------------------------------------------------------

-- A crystal: a hexagonal prism (three blocks turned 60 degrees apart --
-- their corners are exactly the hexagon's) ending in a six-faced point
-- (three crossed gables). Grows from `base` along `dir`.
function MarineFlora.Crystal(self: Kit, parent: Instance, base: Vector3, dir: Vector3, height: number, width: number, color: Color3, transparency: number?): Model
	local model = self:model(parent, "Crystal")
	local frame = frameY(base, dir) * CFrame.Angles(0, self:range(0, math.pi), 0)
	local side = width / math.sqrt(3)
	local body = height * 0.78
	for k = 0, 2 do
		local block = self:part(model, "CrystalBody", Vector3.new(width, body, side), frame * CFrame.Angles(0, k * math.pi / 3, 0) * CFrame.new(0, body / 2, 0), Enum.Material.Neon, color)
		block.Transparency = transparency or 0.12
	end
	local apex = frame * Vector3.new(0, height, 0)
	for k = 0, 2 do
		local across = frame:VectorToWorldSpace(Vector3.new(math.cos(k * math.pi / 3), 0, math.sin(k * math.pi / 3)))
		local shoulder = frame * Vector3.new(0, body - 0.02, 0)
		for _, w in ipairs(self:triangle(model, "CrystalTip", shoulder + across * width / 2, shoulder - across * width / 2, apex, Enum.Material.Neon, tint(color, 0.25), side)) do
			w.Transparency = transparency or 0.12
		end
	end
	return finish(model, CFrame.new(base))
end

-- Stalactite (dir down) or stalagmite (dir up): tapering stacked rods,
-- each a little off the last, ending in a drop-shaped point.
function MarineFlora.Dripstone(self: Kit, parent: Instance, base: Vector3, dir: Vector3, length: number, width: number, color: Color3, name: string): Model
	local model = self:model(parent, name)
	local at = base
	local heading = dir
	local segments = 3
	for s = 1, segments do
		local segmentLength = length / (segments + 0.6)
		local radius = width / 2 * (1 - (s - 1) * 0.27)
		local tip = at + heading * segmentLength
		self:rod(model, name, at, tip, radius, Enum.Material.Limestone, s % 2 == 0 and color or tint(color, 0.08), radius * 0.4)
		self:ellipsoid(model, name .. "Ring", Vector3.new(radius * 2.25, radius * 0.5, radius * 2.25), frameY(at + heading * segmentLength * 0.15, heading), Enum.Material.Limestone, tint(color, -0.08))
		at = tip
		heading = self:bend(heading, self:range(0, 0.08))
	end
	local drop = width * 0.4
	self:ellipsoid(model, name .. "Tip", Vector3.new(drop, length * 0.3, drop), frameY(at + heading * length * 0.1, heading), Enum.Material.Limestone, tint(color, 0.15))
	return finish(model, CFrame.new(base))
end

-- Glowing cave mushrooms: pale stalks under luminous domed caps with a
-- ring of gills beneath.
function MarineFlora.GlowFungi(self: Kit, parent: Instance, ground: (number, number) -> Vector3, center: Vector3, spread: number, glow: Color3): Model
	local model = self:model(parent, "GlowFungi")
	for _ = 1, self.rng:NextInteger(3, 6) do
		local foot = ground(center.X + self:range(-1, 1) * spread, center.Z + self:range(-1, 1) * spread)
		local stalk = self:range(0.8, 2.4)
		local dir = self:bend(UP, self:range(0, 0.25))
		local top = foot + dir * stalk
		self:rod(model, "FungusStalk", foot - dir * 0.2, top, 0.18, Enum.Material.SmoothPlastic, Color3.fromRGB(205, 215, 205))
		local cap = self:range(0.9, 2.2)
		self:disc(model, "FungusGills", top - dir * 0.02, dir, cap * 0.92, 0.08, Enum.Material.SmoothPlastic, Color3.fromRGB(190, 230, 215))
		self:ellipsoid(model, "FungusCap", Vector3.new(cap, cap * 0.5, cap), frameY(top + dir * cap * 0.12, dir), Enum.Material.Neon, glow)
	end
	return finish(model, CFrame.new(center))
end

-- Glowing tunicates: bulbs on short stalks, the largest lighting the mud.
function MarineFlora.GlowCluster(self: Kit, parent: Instance, base: Vector3, color: Color3): Model
	local model = self:model(parent, "GlowCluster")
	local biggest, biggestSize = nil, 0
	for _ = 1, self.rng:NextInteger(3, 5) do
		local dir = self:bend(UP, self:range(0.1, 0.7))
		local length = self:range(0.6, 2)
		local top = base + dir * length
		self:rod(model, "GlowStalk", base, top, 0.1, Enum.Material.SmoothPlastic, Color3.fromRGB(80, 70, 100))
		local s = self:range(0.5, 1.2)
		local bulb = self:ellipsoid(model, "GlowNode", Vector3.new(s, s * 1.3, s), frameY(top + dir * s * 0.5, dir), Enum.Material.Neon, color)
		bulb.Transparency = 0.15
		if s > biggestSize then
			biggest, biggestSize = bulb, s
		end
	end
	if biggest then
		local light = Instance.new("PointLight")
		light.Color = color
		light.Range = 22
		light.Brightness = 1.1
		light.Parent = biggest
	end
	return finish(model, CFrame.new(base))
end

return MarineFlora
