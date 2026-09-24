-- Minimal Roblox stubs: enough to actually run the creature scripts.
local function approx(a, b, eps) return math.abs(a - b) <= (eps or 1e-4) end

-- Vector3 -------------------------------------------------------------
local V3 = {}
V3.__index = V3
local function v3(x, y, z) return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, V3) end
V3.__add = function(a, b) return v3(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
V3.__sub = function(a, b) return v3(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
V3.__unm = function(a) return v3(-a.X, -a.Y, -a.Z) end
V3.__mul = function(a, b)
	if type(b) == "number" then return v3(a.X * b, a.Y * b, a.Z * b) end
	if type(a) == "number" then return v3(b.X * a, b.Y * a, b.Z * a) end
	return v3(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
V3.__div = function(a, b)
	if type(b) == "number" then return v3(a.X / b, a.Y / b, a.Z / b) end
	return v3(a.X / b.X, a.Y / b.Y, a.Z / b.Z)
end
V3.__eq = function(a, b) return a.X == b.X and a.Y == b.Y and a.Z == b.Z end
V3.__tostring = function(a) return string.format("(%.3f, %.3f, %.3f)", a.X, a.Y, a.Z) end
V3.__index = function(t, k)
	if k == "Magnitude" then return math.sqrt(t.X * t.X + t.Y * t.Y + t.Z * t.Z) end
	if k == "Unit" then
		local m = math.sqrt(t.X * t.X + t.Y * t.Y + t.Z * t.Z)
		if m < 1e-9 then return v3(0, 0, 0) end
		return v3(t.X / m, t.Y / m, t.Z / m)
	end
	if k == "Cross" then
		return function(a, b) return v3(a.Y * b.Z - a.Z * b.Y, a.Z * b.X - a.X * b.Z, a.X * b.Y - a.Y * b.X) end
	end
	if k == "Dot" then return function(a, b) return a.X * b.X + a.Y * b.Y + a.Z * b.Z end end
	if k == "Lerp" then return function(a, b, t) return v3(a.X + (b.X - a.X) * t, a.Y + (b.Y - a.Y) * t, a.Z + (b.Z - a.Z) * t) end end
	if k == "Min" then return function(a, b) return v3(math.min(a.X, b.X), math.min(a.Y, b.Y), math.min(a.Z, b.Z)) end end
	if k == "Max" then return function(a, b) return v3(math.max(a.X, b.X), math.max(a.Y, b.Y), math.max(a.Z, b.Z)) end end
	if k == "Abs" then return function(a) return v3(math.abs(a.X), math.abs(a.Y), math.abs(a.Z)) end end
	return rawget(V3, k)
end
Vector3 = { new = v3, zero = v3(0, 0, 0), one = v3(1, 1, 1), xAxis = v3(1, 0, 0), yAxis = v3(0, 1, 0), zAxis = v3(0, 0, 1) }
IS_V3 = function(v) return getmetatable(v) == V3 end

-- CFrame: real 3x3 rotation (columns = Right, Up, Back) + position -----
local CF = {}
local function cf(p, r) return setmetatable({ p = p, r = r }, CF) end
local IDENT = { 1, 0, 0, 0, 1, 0, 0, 0, 1 } -- row-major
local function mulMat(a, b)
	local o = {}
	for i = 0, 2 do
		for j = 1, 3 do
			o[i * 3 + j] = a[i * 3 + 1] * b[j] + a[i * 3 + 2] * b[3 + j] + a[i * 3 + 3] * b[6 + j]
		end
	end
	return o
end
local function mulVec(m, v)
	return v3(m[1] * v.X + m[2] * v.Y + m[3] * v.Z, m[4] * v.X + m[5] * v.Y + m[6] * v.Z, m[7] * v.X + m[8] * v.Y + m[9] * v.Z)
end
local function col(m, j) return v3(m[j], m[3 + j], m[6 + j]) end
CF.__mul = function(a, b)
	if getmetatable(b) == V3 or (type(b) == "table" and b.X and not b.r) then
		return a.p + mulVec(a.r, b)
	end
	return cf(a.p + mulVec(a.r, b.p), mulMat(a.r, b.r))
end
CF.__add = function(a, b) return cf(a.p + b, a.r) end
CF.__sub = function(a, b) return cf(a.p - b, a.r) end
CF.__index = function(t, k)
	if k == "Position" or k == "p" then return rawget(t, "p") end
	if k == "Rotation" then return cf(v3(0, 0, 0), t.r) end
	if k == "X" then return t.p.X end
	if k == "Y" then return t.p.Y end
	if k == "Z" then return t.p.Z end
	if k == "Inverse" then
		return function(s)
			local r = s.r
			local rt = { r[1], r[4], r[7], r[2], r[5], r[8], r[3], r[6], r[9] }
			return cf(-mulVec(rt, s.p), rt)
		end
	end
	if k == "LookVector" then return -col(t.r, 3) end
	if k == "RightVector" or k == "XVector" then return col(t.r, 1) end
	if k == "YVector" then return col(t.r, 2) end
	if k == "ZVector" then return col(t.r, 3) end
	if k == "UpVector" then return col(t.r, 2) end
	if k == "VectorToWorldSpace" then return function(s, v) return mulVec(s.r, v) end end
	if k == "PointToWorldSpace" then return function(s, v) return s.p + mulVec(s.r, v) end end
	if k == "PointToObjectSpace" then
		return function(s, v)
			local d = v - s.p
			return v3(col(s.r, 1):Dot(d), col(s.r, 2):Dot(d), col(s.r, 3):Dot(d))
		end
	end
	return nil
end
CFrame = {
	new = function(a, b, c)
		if type(a) == "number" then return cf(v3(a, b, c), IDENT) end
		return cf(a, IDENT)
	end,
	identity = cf(v3(0, 0, 0), IDENT),
	Angles = function(rx, ry, rz)
		local function m(mat) return mat end
		local cx, sx, cy, sy, cz, sz = math.cos(rx), math.sin(rx), math.cos(ry), math.sin(ry), math.cos(rz), math.sin(rz)
		local Rx = { 1, 0, 0, 0, cx, -sx, 0, sx, cx }
		local Ry = { cy, 0, sy, 0, 1, 0, -sy, 0, cy }
		local Rz = { cz, -sz, 0, sz, cz, 0, 0, 0, 1 }
		return cf(v3(0, 0, 0), m(mulMat(mulMat(Rx, Ry), Rz)))
	end,
	lookAt = function(at, target, up)
		up = up or v3(0, 1, 0)
		local back = (at - target).Unit
		if back.Magnitude < 1e-6 then back = v3(0, 0, 1) end
		local right = up:Cross(back)
		if right.Magnitude < 1e-6 then right = v3(1, 0, 0) else right = right.Unit end
		local realUp = back:Cross(right)
		return cf(at, { right.X, realUp.X, back.X, right.Y, realUp.Y, back.Y, right.Z, realUp.Z, back.Z })
	end,
	fromMatrix = function(p, r, u)
		local b = r:Cross(u)
		return cf(p, { r.X, u.X, b.X, r.Y, u.Y, b.Y, r.Z, u.Z, b.Z })
	end,
}

local C3 = {}
C3.__index = C3
function C3:Lerp(o, t) return setmetatable({ R = self.R + (o.R - self.R) * t, G = self.G + (o.G - self.G) * t, B = self.B + (o.B - self.B) * t }, C3) end
Color3 = {
	fromRGB = function(r, g, b) return setmetatable({ R = r / 255, G = g / 255, B = b / 255 }, C3) end,
	new = function(r, g, b) return setmetatable({ R = r or 0, G = g or 0, B = b or 0 }, C3) end,
}
local function valueType(name)
	return { new = function(...) return { _type = name, _args = { ... } } end }
end
NumberSequence = valueType("NumberSequence")
NumberSequenceKeypoint = valueType("NumberSequenceKeypoint")
ColorSequence = valueType("ColorSequence")
ColorSequenceKeypoint = valueType("ColorSequenceKeypoint")
NumberRange = valueType("NumberRange")
TweenInfo = valueType("TweenInfo")
UDim = valueType("UDim")
UDim2 = { new = function(...) return { _type = "UDim2", _args = { ... } } end, fromScale = function(...) return { _type = "UDim2" } end, fromOffset = function(...) return { _type = "UDim2" } end }
Vector2 = { new = function(x, y) return { X = x or 0, Y = y or 0 } end, zero = { X = 0, Y = 0 }, one = { X = 1, Y = 1 } }

local Region3MT = {}
Region3MT.__index = Region3MT
function Region3MT:ExpandToGrid(res)
	local function down(v) return math.floor(v / res) * res end
	local function up(v) return math.ceil(v / res) * res end
	return setmetatable({ min = v3(down(self.min.X), down(self.min.Y), down(self.min.Z)), max = v3(up(self.max.X), up(self.max.Y), up(self.max.Z)) }, Region3MT)
end
Region3 = { new = function(a, b) return setmetatable({ min = a, max = b }, Region3MT) end }

-- Random: deterministic LCG with Roblox's API shape.
local RandomMT = {}
RandomMT.__index = RandomMT
function RandomMT:_next()
	self.state = (self.state * 1103515245 + 12345) % 2147483648
	return self.state / 2147483648
end
function RandomMT:NextNumber(a, b)
	local x = self:_next()
	if a then return a + (b - a) * x end
	return x
end
function RandomMT:NextInteger(a, b) return a + math.floor(self:_next() * (b - a + 1)) end
function RandomMT:NextUnitVector()
	local v = v3(self:_next() - 0.5, self:_next() - 0.5, self:_next() - 0.5)
	return v.Unit
end
Random = { new = function(seed) return setmetatable({ state = math.floor(math.abs(seed or 12345)) % 2147483648 + 1 }, RandomMT) end }

-- Enum: only members that really exist, so a typo fails like in Studio --
local REAL = {
	Material = { SmoothPlastic = true, Plastic = true, Slate = true, Rock = true, Sand = true, Water = true, Air = true, Fabric = true, Metal = true, Glass = true, Neon = true, Marble = true, Concrete = true, Granite = true, Basalt = true, CrackedLava = true, Limestone = true, Mud = true, Salt = true, Ice = true, Glacier = true, Snow = true, WoodPlanks = true, Wood = true, Cobblestone = true, Brick = true, Pebble = true, Asphalt = true, CorrodedMetal = true, DiamondPlate = true, Foil = true, ForceField = true, Grass = true, LeafyGrass = true, Ground = true, Sandstone = true },
	PartType = { Ball = true, Block = true, Cylinder = true, Wedge = true, CornerWedge = true },
	PositionAlignmentMode = { OneAttachment = true, TwoAttachment = true },
	OrientationAlignmentMode = { OneAttachment = true, TwoAttachment = true },
	AnimationPriority = { Core = true, Idle = true, Movement = true, Action = true, Action2 = true },
	NormalId = { Top = true, Bottom = true, Front = true, Back = true, Left = true, Right = true },
	EasingStyle = { Linear = true, Sine = true, Quad = true, Quart = true, Quint = true, Back = true, Cubic = true, Exponential = true, Elastic = true, Bounce = true, Circular = true },
	EasingDirection = { In = true, Out = true, InOut = true },
	Font = { SourceSans = true, GothamMedium = true, Gotham = true, GothamBold = true, GothamBlack = true },
	TextXAlignment = { Left = true, Center = true, Right = true },
	TextYAlignment = { Top = true, Center = true, Bottom = true },
	FillDirection = { Horizontal = true, Vertical = true },
	HorizontalAlignment = { Left = true, Center = true, Right = true },
	VerticalAlignment = { Top = true, Center = true, Bottom = true },
	SortOrder = { LayoutOrder = true, Name = true },
	ApplyStrokeMode = { Contextual = true, Border = true },
	ZIndexBehavior = { Global = true, Sibling = true },
	RenderPriority = { Camera = true, Character = true, First = true, Input = true, Last = true },
}
-- Enum items are cached so `part.Shape == Enum.PartType.Ball` compares
-- identities like in Roblox.
local ENUM_CACHE = {}
Enum = setmetatable({}, { __index = function(_, group)
	local members = REAL[group]
	ENUM_CACHE[group] = ENUM_CACHE[group] or {}
	return setmetatable({}, { __index = function(_, name)
		if members and not members[name] then
			error(string.format("Enum.%s.%s does not exist", group, name), 2)
		end
		ENUM_CACHE[group][name] = ENUM_CACHE[group][name] or { Name = name, EnumType = group, Value = 0 }
		return ENUM_CACHE[group][name]
	end })
end })

-- Instance ------------------------------------------------------------
local BASE_PARTS = { Part = true, WedgePart = true, MeshPart = true, CornerWedgePart = true, TrussPart = true, SpawnLocation = true, Seat = true, UnionOperation = true }
local Inst = {}
local function newSignal()
	local handlers = {}
	return {
		Connect = function(_, fn) table.insert(handlers, fn); return { Disconnect = function() end, Connected = true } end,
		Fire = function(_, ...) for _, fn in ipairs(handlers) do fn(...) end end,
		Wait = function() error("stub: waiting on a signal that never fires", 2) end,
		Once = function(_, fn) table.insert(handlers, fn); return { Disconnect = function() end } end,
	}
end

TRACKS = {}

local function newInstance(class)
	local o = { ClassName = class, Name = class, _children = {}, _attributes = {}, _parent = nil }
	o.Size = v3(1, 1, 1)
	o._cf = CFrame.new(v3(0, 0, 0))
	o.Shape = Enum.PartType.Block
	o.Transparency = 0
	o.Anchored = false
	o.CanCollide = true
	o.AncestryChanged = newSignal()
	o.Changed = newSignal()
	o.Event = newSignal()
	o.Triggered = newSignal()
	o.Died = newSignal()
	o.OnClientEvent = newSignal()
	o.OnServerEvent = newSignal()
	o.ChildAdded = newSignal()
	o.ChildRemoved = newSignal()
	o.AttributeChanged = newSignal()
	o._attrSignals = {}
	return setmetatable(o, Inst)
end

Inst.__index = function(t, k)
	if k == "Parent" then return rawget(t, "_parent") end
	if k == "CFrame" then return rawget(t, "_cf") end
	if k == "Position" then return rawget(t, "_cf").Position end
	local v = rawget(Inst, k)
	if v then return v end
	-- Like Roblox: an unknown key falls back to a child with that name.
	local children = rawget(t, "_children")
	if children then
		for _, c in ipairs(children) do if c.Name == k then return c end end
	end
	return nil
end
Inst.__newindex = function(t, k, v)
	if k == "Parent" then
		local old = rawget(t, "_parent")
		if old then
			for i, c in ipairs(old._children) do
				if c == t then table.remove(old._children, i) break end
			end
		end
		rawset(t, "_parent", v)
		if v then table.insert(v._children, t) end
		t.AncestryChanged:Fire(t, v)
		if v then v.ChildAdded:Fire(t) end
		return
	end
	-- A part's CFrame and Position are one value in Roblox.
	if k == "CFrame" then
		rawset(t, "_cf", v)
		return
	end
	if k == "Position" then
		local old = rawget(t, "_cf")
		rawset(t, "_cf", setmetatable({ p = v, r = old.r }, getmetatable(old)))
		return
	end
	rawset(t, k, v)
end

function Inst:IsA(class)
	if self.ClassName == class then return true end
	if class == "LuaSourceContainer" then return self.ClassName == "Script" or self.ClassName == "ModuleScript" or self.ClassName == "LocalScript" end
	if class == "Light" then return self.ClassName == "PointLight" or self.ClassName == "SpotLight" or self.ClassName == "SurfaceLight" end
	if class == "BasePart" then return BASE_PARTS[self.ClassName] == true end
	if class == "Instance" then return true end
	if class == "PVInstance" then return BASE_PARTS[self.ClassName] or self.ClassName == "Model" end
	return false
end
function Inst:FindFirstChild(name)
	for _, c in ipairs(self._children) do if c.Name == name then return c end end
	return nil
end
function Inst:WaitForChild(name) return self:FindFirstChild(name) end
function Inst:FindFirstChildOfClass(class)
	for _, c in ipairs(self._children) do if c.ClassName == class then return c end end
	return nil
end
function Inst:FindFirstChildWhichIsA(class)
	for _, c in ipairs(self._children) do if c:IsA(class) then return c end end
	return nil
end
function Inst:GetChildren()
	local out = {}
	for i, c in ipairs(self._children) do out[i] = c end
	return out
end
function Inst:GetDescendants()
	local out = {}
	local function walk(node)
		for _, c in ipairs(node._children) do table.insert(out, c); walk(c) end
	end
	walk(self)
	return out
end
function Inst:GetFullName()
	local names, node = {}, self
	while node do table.insert(names, 1, node.Name); node = node._parent end
	return table.concat(names, ".")
end
function Inst:SetAttribute(k, v)
	self._attributes[k] = v
	self.AttributeChanged:Fire(k)
	local sig = self._attrSignals[k]
	if sig then sig:Fire() end
end
function Inst:GetAttributeChangedSignal(k)
	self._attrSignals[k] = self._attrSignals[k] or newSignal()
	return self._attrSignals[k]
end
function Inst:GetPropertyChangedSignal() return newSignal() end
function Inst:ClearAllChildren() for _, c in ipairs(self:GetChildren()) do c:Destroy() end end
function Inst:IsDescendantOf(ancestor)
	local node = self._parent
	while node do if node == ancestor then return true end node = node._parent end
	return false
end
function Inst:Emit() end
function Inst:FireClient() end
function Inst:FireAllClients() end
function Inst:Play() end
function Inst:Stop() end
function Inst:Connect() return { Disconnect = function() end } end
function Inst:GetAttribute(k) return self._attributes[k] end
function Inst:GetAttributes() return self._attributes end
function Inst:Destroy()
	self.Parent = nil
	for _, c in ipairs(self:GetChildren()) do c:Destroy() end
end
function Inst:Clone()
	local copy = newInstance(self.ClassName)
	for k, v in pairs(self) do
		if k ~= "_children" and k ~= "_parent" and k ~= "_attributes" and type(v) ~= "function" then
			rawset(copy, k, v)
		end
	end
	copy._attributes = {}
	for k, v in pairs(self._attributes) do copy._attributes[k] = v end
	copy.AncestryChanged = newSignal()
	copy.Changed = newSignal()
	local primaryIndex = nil
	for i, c in ipairs(self._children) do
		if c == rawget(self, "PrimaryPart") then primaryIndex = i end
	end
	for i, c in ipairs(self._children) do
		local cc = c:Clone()
		cc.Parent = copy
		if i == primaryIndex then rawset(copy, "PrimaryPart", cc) end
	end
	return copy
end
function Inst:GetPivot()
	local primary = rawget(self, "PrimaryPart")
	if primary then return primary.CFrame end
	return self.CFrame
end
function Inst:PivotTo(target)
	local delta = target.Position - self:GetPivot().Position
	for _, d in ipairs(self:GetDescendants()) do
		if d:IsA("BasePart") then
			d.CFrame = d.CFrame + delta
		end
	end
	self.CFrame = self.CFrame + delta
end
function Inst:SetNetworkOwner() end
function Inst:ApplyImpulse() end
function Inst:LoadAnimation(animation)
	local track = {
		Looped = false, Priority = nil, IsPlaying = false, Length = 1,
		_id = animation.AnimationId, _owner = self:GetFullName(),
	}
	function track:Play() self.IsPlaying = true end
	function track:Stop() self.IsPlaying = false end
	function track:AdjustSpeed() end
	table.insert(TRACKS, track)
	return track
end

Instance = { new = function(class, parent)
	local o = newInstance(class)
	if parent then o.Parent = parent end
	return o
end }

-- Services ------------------------------------------------------------
local services = {}
local function service(class, name)
	local s = newInstance(class)
	s.Name = name or class
	services[name or class] = s
	return s
end

Workspace = service("Workspace", "Workspace")
ReplicatedStorage = service("ReplicatedStorage", "ReplicatedStorage")
ServerScriptService = service("ServerScriptService", "ServerScriptService")
local PlayersService = service("Players", "Players")
local RunServiceStub = service("RunService", "RunService")
local CollectionStub = service("CollectionService", "CollectionService")

-- Terrain: every fill is recorded, so tests can ask what material a point
-- ends up as (see TERRAIN_MATERIAL_AT for the water rule).
TERRAIN_OPS = {}
-- Ops are also filed into 32-stud XZ cells so a point query only scans the
-- ops that can touch it (the seabed alone is ~90k column fills).
local CELL = 32
local terrainCells = {}
local function cellKey(cx, cz) return cx * 100000 + cz end
local function fileOp(op, minX, maxX, minZ, maxZ)
	op.index = #TERRAIN_OPS + 1
	TERRAIN_OPS[op.index] = op
	for cx = math.floor(minX / CELL), math.floor(maxX / CELL) do
		for cz = math.floor(minZ / CELL), math.floor(maxZ / CELL) do
			local key = cellKey(cx, cz)
			local list = terrainCells[key]
			if not list then list = {}; terrainCells[key] = list end
			list[#list + 1] = op
		end
	end
end
local TerrainInst = newInstance("Terrain")
TerrainInst.Name = "Terrain"
TerrainInst.Parent = Workspace
rawset(Workspace, "Terrain", TerrainInst)
function TerrainInst:Clear() TERRAIN_OPS = {}; terrainCells = {} end
local function fileBox(op, center, reach)
	fileOp(op, center.X - reach, center.X + reach, center.Z - reach, center.Z + reach)
end
function TerrainInst:FillBlock(cframe, size, material)
	assert(size.X > 0 and size.Y > 0 and size.Z > 0, "FillBlock: empty size " .. tostring(size))
	assert(size.X * size.Y * size.Z / 64 <= 4194304, "FillBlock: extents too large " .. tostring(size))
	local r = cframe.r
	local axisAligned = r[1] == 1 and r[5] == 1 and r[9] == 1
	local c, h = cframe.Position, size / 2
	fileBox({ kind = axisAligned and "aabb" or "block", cframe = cframe, half = h, material = material.Name,
		minX = c.X - h.X, maxX = c.X + h.X, minY = c.Y - h.Y, maxY = c.Y + h.Y, minZ = c.Z - h.Z, maxZ = c.Z + h.Z }, c, h.Magnitude)
end
function TerrainInst:FillCylinder(cframe, height, radius, material)
	assert(height > 0 and radius > 0, "FillCylinder: empty")
	fileBox({ kind = "cylinder", cframe = cframe, height = height, radius = radius, material = material.Name }, cframe.Position, math.sqrt(radius * radius + height * height / 4))
end
function TerrainInst:FillBall(center, radius, material)
	fileBox({ kind = "ball", center = center, radius = radius, material = material.Name }, center, radius)
end
function TerrainInst:FillWedge(cframe, size, material)
	fileBox({ kind = "block", cframe = cframe, half = size / 2, material = material.Name }, cframe.Position, (size / 2).Magnitude)
end
function TerrainInst:SetMaterialColor() end
function TerrainInst:ReplaceMaterial(region, res, from, to)
	assert(res == 4 and region.min and region.max, "ReplaceMaterial: bad region")
end
local function opContains(op, p)
	if op.kind == "aabb" then
		return p.X >= op.minX and p.X <= op.maxX and p.Y >= op.minY and p.Y <= op.maxY and p.Z >= op.minZ and p.Z <= op.maxZ
	end
	if op.kind == "ball" then
		local c = op.center
		local dx, dy, dz = p.X - c.X, p.Y - c.Y, p.Z - c.Z
		return dx * dx + dy * dy + dz * dz <= op.radius * op.radius
	end
	local l = op.cframe:PointToObjectSpace(p)
	if op.kind == "cylinder" then
		return math.abs(l.Y) <= op.height / 2 and math.sqrt(l.X * l.X + l.Z * l.Z) <= op.radius
	end
	return math.abs(l.X) <= op.half.X and math.abs(l.Y) <= op.half.Y and math.abs(l.Z) <= op.half.Z
end
-- Shorelines semantics (the Roblox default): a voxel holds a solid AND a
-- liquid part, so filling Water over rock only wets it -- the rock stays.
-- Only a fill with Air clears a voxel (solid and water alike). Water
-- therefore wins only over what was empty.
TERRAIN_MATERIAL_AT = function(p)
	local list = terrainCells[cellKey(math.floor(p.X / CELL), math.floor(p.Z / CELL))]
	local wet = false
	if list then
		for i = #list, 1, -1 do
			local op = list[i]
			if opContains(op, p) then
				if op.material == "Water" then
					wet = true
				elseif op.material == "Air" then
					return wet and "Water" or "Air"
				else
					return op.material
				end
			end
		end
	end
	return wet and "Water" or "Air"
end
-- Anything that is neither water nor empty.
TERRAIN_SOLID_AT = function(p)
	local m = TERRAIN_MATERIAL_AT(p)
	return m ~= "Water" and m ~= "Air"
end

local LightingStub = service("Lighting", "Lighting")
function LightingStub:GetSunDirection() return v3(0.3, 0.8, 0.5).Unit end
local DebrisStub = service("Debris", "Debris")
function DebrisStub:AddItem() end

HEARTBEAT = {}
RunServiceStub.Heartbeat = { Connect = function(_, fn) HEARTBEAT.fn = fn; return { Disconnect = function() end } end }
RunServiceStub.IsServer = function() return true end
RunServiceStub.IsClient = function() return false end

PLAYERS = {}
PlayersService.GetPlayers = function() return PLAYERS end
PlayersService.GetPlayerFromCharacter = function(_, character)
	for _, p in ipairs(PLAYERS) do if p.Character == character then return p end end
	return nil
end
PlayersService.PlayerAdded = newSignal()

local tags = {}
local tagSignals = {}
CollectionStub.AddTag = function(_, instance, tag)
	tags[tag] = tags[tag] or {}
	table.insert(tags[tag], instance)
	if tagSignals[tag] then tagSignals[tag]:Fire(instance) end
end
CollectionStub.GetTagged = function(_, tag)
	local out = {}
	for _, i in ipairs(tags[tag] or {}) do table.insert(out, i) end
	return out
end
CollectionStub.HasTag = function(_, instance, tag)
	for _, i in ipairs(tags[tag] or {}) do if i == instance then return true end end
	return false
end
CollectionStub.GetInstanceAddedSignal = function(_, tag)
	tagSignals[tag] = tagSignals[tag] or newSignal()
	return tagSignals[tag]
end
CLEAR_TAGS = function() tags = {}; tagSignals = {} end

game = {
	GetService = function(_, name)
		if not services[name] then service(name, name) end
		return services[name]
	end,
	Workspace = Workspace,
}

typeof = function(v)
	local mt = getmetatable(v)
	if mt == V3 then return "Vector3" end
	if mt == CF then return "CFrame" end
	if mt == C3 then return "Color3" end
	if mt == Inst then return "Instance" end
	return type(v)
end

-- task: spawn/delay run the function in a coroutine; task.wait inside one
-- parks it forever (a `while true do task.wait() ... end` loop runs one
-- iteration instead of hanging the test), and is a no-op on the main thread.
local stubThreads = setmetatable({}, { __mode = "k" })
local function runThread(fn, ...)
	local co = coroutine.create(fn)
	stubThreads[co] = true
	local ok, err = coroutine.resume(co, ...)
	if not ok then error(err, 0) end
	return co
end
task = {
	wait = function() if stubThreads[coroutine.running()] then coroutine.yield() end return 0 end,
	spawn = function(fn, ...) return runThread(fn, ...) end,
	defer = function(fn, ...) return runThread(fn, ...) end,
	delay = function(_, fn, ...) return runThread(fn, ...) end,
	cancel = function() end,
}

WARNINGS = {}
local realPrint = print
warn = function(...)
	local parts = {}
	for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
	table.insert(WARNINGS, table.concat(parts, " "))
end

CLOCK = 0
os = setmetatable({ clock = function() return CLOCK end }, { __index = { time = function() return 0 end, date = function() return "" end } })

APPROX = approx
