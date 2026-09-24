-- Shared placement bookkeeping for the world builders, created once by
-- WorldBootstrap and handed to each builder in order.
--
--   * Reserved volumes: every builder that places something big (beach,
--     cave mountains, the wreck, current tubes) reserves its volume here,
--     and decor placed afterwards asks IsFree() first -- so a coral spire
--     never grows through the wreck's hull or blocks a current's path.
--   * Anchors: named positions one builder publishes for a later one
--     (e.g. the wreck's stern, where the Épave vortex goes).
--   * Seeded randomness: every builder draws from its own Random seeded
--     from one world seed, so the map is identical on every server start
--     instead of reshuffling reefs and spires each time.

local WorldLayout = {}
WorldLayout.__index = WorldLayout

-- The layout WorldBootstrap built the world with, so server systems that
-- place things at runtime (treasure/creature fallback placement) can ask
-- IsFree() against the same reserved volumes. nil until the world is built.
WorldLayout.Current = nil

WorldLayout.OceanHalfWidth = 1000
WorldLayout.SurfaceY = 0
WorldLayout.FloorY = -500

function WorldLayout.new(seed: number?)
	return setmetatable({
		seed = seed or 20260924,
		reserved = {},
		anchors = {},
	}, WorldLayout)
end

function WorldLayout:Random(salt: string): Random
	local hash = self.seed
	for i = 1, #salt do
		hash = (hash * 31 + string.byte(salt, i)) % 2147483647
	end
	return Random.new(hash)
end

function WorldLayout:SetAnchor(name: string, value: any)
	self.anchors[name] = value
end

function WorldLayout:GetAnchor(name: string): any
	return self.anchors[name]
end

-- Oriented box (a CFrame + full Size, like a Part).
function WorldLayout:ReserveBox(name: string, cframe: CFrame, size: Vector3)
	table.insert(self.reserved, { kind = "box", name = name, cframe = cframe, half = size / 2 })
end

function WorldLayout:ReserveSphere(name: string, center: Vector3, radius: number)
	table.insert(self.reserved, { kind = "sphere", name = name, center = center, radius = radius })
end

-- Vertical cylinder between minY and maxY.
function WorldLayout:ReserveCylinder(name: string, center: Vector3, radius: number, minY: number, maxY: number)
	table.insert(self.reserved, { kind = "cylinder", name = name, center = center, radius = radius, minY = minY, maxY = maxY })
end

-- Segment with a radius around it (current tubes, tunnels).
function WorldLayout:ReserveCapsule(name: string, a: Vector3, b: Vector3, radius: number)
	table.insert(self.reserved, { kind = "capsule", name = name, a = a, b = b, radius = radius })
end

local function distanceToSegment(point: Vector3, a: Vector3, b: Vector3): number
	local ab = b - a
	local lengthSquared = ab:Dot(ab)
	if lengthSquared < 1e-9 then
		return (point - a).Magnitude
	end
	local t = math.clamp((point - a):Dot(ab) / lengthSquared, 0, 1)
	return (point - (a + ab * t)).Magnitude
end

local function inside(volume, point: Vector3, margin: number): boolean
	if volume.kind == "sphere" then
		return (point - volume.center).Magnitude <= volume.radius + margin
	elseif volume.kind == "capsule" then
		return distanceToSegment(point, volume.a, volume.b) <= volume.radius + margin
	elseif volume.kind == "cylinder" then
		if point.Y < volume.minY - margin or point.Y > volume.maxY + margin then
			return false
		end
		local dx, dz = point.X - volume.center.X, point.Z - volume.center.Z
		return math.sqrt(dx * dx + dz * dz) <= volume.radius + margin
	end
	local localPoint = volume.cframe:PointToObjectSpace(point)
	local half = volume.half
	return math.abs(localPoint.X) <= half.X + margin
		and math.abs(localPoint.Y) <= half.Y + margin
		and math.abs(localPoint.Z) <= half.Z + margin
end

-- Returns true when the point (grown by margin) touches no reserved
-- volume and stays inside the ocean; otherwise false and the name of the
-- first volume in the way.
function WorldLayout:IsFree(point: Vector3, margin: number?): (boolean, string?)
	local m = margin or 0
	local limit = WorldLayout.OceanHalfWidth - m
	if math.abs(point.X) > limit or math.abs(point.Z) > limit then
		return false, "OceanEdge"
	end
	for _, volume in ipairs(self.reserved) do
		if inside(volume, point, m) then
			return false, volume.name
		end
	end
	return true, nil
end

-- Samples a segment (e.g. a spire's axis) every `step` studs.
function WorldLayout:IsSegmentFree(a: Vector3, b: Vector3, margin: number?, step: number?): (boolean, string?)
	local length = (b - a).Magnitude
	local count = math.max(1, math.ceil(length / (step or 8)))
	for i = 0, count do
		local ok, blocker = self:IsFree(a:Lerp(b, i / count), margin)
		if not ok then
			return false, blocker
		end
	end
	return true, nil
end

return WorldLayout
