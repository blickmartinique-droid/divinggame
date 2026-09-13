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
	return rawget(V3, k)
end
Vector3 = { new = v3, zero = v3(0, 0, 0), one = v3(1, 1, 1) }

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
CF.__index = function(t, k)
	if k == "Position" or k == "p" then return rawget(t, "p") end
	if k == "LookVector" then return -col(t.r, 3) end
	if k == "RightVector" then return col(t.r, 1) end
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

Color3 = {
	fromRGB = function(r, g, b) return { R = r / 255, G = g / 255, B = b / 255 } end,
	new = function(r, g, b) return { R = r, G = g, B = b } end,
}

-- Enum: only members that really exist, so a typo fails like in Studio --
local REAL = {
	Material = { SmoothPlastic = true, Plastic = true, Slate = true, Rock = true, Sand = true, Water = true, Air = true, Fabric = true, Metal = true, Glass = true, Neon = true, Marble = true, Concrete = true, Granite = true, Basalt = true, CrackedLava = true, Limestone = true, Mud = true, Salt = true, Ice = true, Glacier = true, Snow = true, WoodPlanks = true, Wood = true, Cobblestone = true, Brick = true, Pebble = true, Asphalt = true, CorrodedMetal = true, DiamondPlate = true, Foil = true, ForceField = true, Grass = true, LeafyGrass = true, Ground = true, Sandstone = true },
	PartType = { Ball = true, Block = true, Cylinder = true, Wedge = true, CornerWedge = true },
	PositionAlignmentMode = { OneAttachment = true, TwoAttachment = true },
	OrientationAlignmentMode = { OneAttachment = true, TwoAttachment = true },
	AnimationPriority = { Core = true, Idle = true, Movement = true, Action = true, Action2 = true },
	NormalId = { Top = true, Bottom = true, Front = true, Back = true, Left = true, Right = true },
	EasingStyle = { Linear = true, Sine = true, Quad = true, Quart = true, Quint = true, Back = true, Cubic = true, Exponential = true },
	EasingDirection = { In = true, Out = true, InOut = true },
	Font = { SourceSans = true, GothamMedium = true, Gotham = true, GothamBold = true },
	RenderPriority = { Camera = true, Character = true, First = true, Input = true, Last = true },
}
Enum = setmetatable({}, { __index = function(_, group)
	local members = REAL[group]
	return setmetatable({}, { __index = function(_, name)
		if members and not members[name] then
			error(string.format("Enum.%s.%s does not exist", group, name), 2)
		end
		return { Name = name, EnumType = group, Value = 0 }
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
	}
end

TRACKS = {}

local function newInstance(class)
	local o = { ClassName = class, Name = class, _children = {}, _attributes = {}, _parent = nil }
	o.Size = v3(1, 1, 1)
	o.Position = v3(0, 0, 0)
	o.CFrame = CFrame.new(v3(0, 0, 0))
	o.Shape = Enum.PartType.Block
	o.Transparency = 0
	o.Anchored = false
	o.CanCollide = true
	o.AncestryChanged = newSignal()
	o.Changed = newSignal()
	o.Event = newSignal()
	return setmetatable(o, Inst)
end

Inst.__index = function(t, k)
	if k == "Parent" then return rawget(t, "_parent") end
	local v = rawget(Inst, k)
	if v then return v end
	-- Real Roblox instances resolve dot-indexing (workspace.SomeChild) to
	-- FindFirstChild -- match that here so scripts under test can use
	-- either style, same as in Studio.
	local children = rawget(t, "_children")
	if children then
		for _, c in ipairs(children) do
			if c.Name == k then return c end
		end
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
		return
	end
	rawset(t, k, v)
end

function Inst:IsA(class)
	if self.ClassName == class then return true end
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
function Inst:SetAttribute(k, v) self._attributes[k] = v end
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
function Inst:PivotTo(target)
	local origin = rawget(self, "PrimaryPart") and self.PrimaryPart.Position or self.Position
	for _, d in ipairs(self:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Position = d.Position + (target.Position - origin)
			d.CFrame = CFrame.new(d.Position)
		end
	end
	self.Position = target.Position
end
function Inst:GetPivot() return CFrame.new(self.Position) end
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
TERRAIN_FILLS = {}
local terrainInst = newInstance("Terrain")
terrainInst.Name = "Terrain"
terrainInst.Parent = Workspace
function terrainInst:FillBall(center, radius, material)
	table.insert(TERRAIN_FILLS, { op = "FillBall", center = center, radius = radius, material = material })
end
function terrainInst:FillCylinder(cf, height, radius, material)
	table.insert(TERRAIN_FILLS, { op = "FillCylinder", cframe = cf, height = height, radius = radius, material = material })
end
function terrainInst:FillBlock(cf, size, material)
	table.insert(TERRAIN_FILLS, { op = "FillBlock", cframe = cf, size = size, material = material })
end
ReplicatedStorage = service("ReplicatedStorage", "ReplicatedStorage")
ServerScriptService = service("ServerScriptService", "ServerScriptService")
local PlayersService = service("Players", "Players")
local RunServiceStub = service("RunService", "RunService")
local CollectionStub = service("CollectionService", "CollectionService")

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
	if mt == Inst then return "Instance" end
	return type(v)
end

task = { wait = function() end, spawn = function(fn, ...) fn(...) end, defer = function(fn, ...) fn(...) end, delay = function(_, fn, ...) fn(...) end }

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
