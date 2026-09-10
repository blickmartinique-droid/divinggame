-- Animates the moving parts of every current's visuals locally on each
-- client: the spiralling strands of vortices and the chain of course-gate
-- rings that travel along directional/path currents. The server
-- (CurrentGenerator.server.lua) only places these parts once and describes
-- the motion through the current's Attributes; moving them here means zero
-- per-frame replication traffic and lets each client skip currents it is
-- nowhere near (their emitters are switched off locally too). Anchored
-- server-owned parts can be moved client-side freely -- the change stays
-- local, which is exactly what a cosmetic wants.
--
-- Pacing reads the same CurrentMaxSpeed/CurrentSpin/CurrentSpiralBias the
-- push physics uses, so what the player sees always matches the push.

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local UPDATE_INTERVAL = 1 / 20
local CULL_REFRESH_INTERVAL = 1
local CULL_MARGIN = 350
local INNER_RADIUS_FRACTION = 0.12
local RING_MIN_SPEED = 4
local RING_MAX_SPEED = 18
local BUILD_RETRIES = 5

local visuals = {} -- [instance] = { center, boundingRadius, emitters, strands?, track? }
local active = {}

local function collectEmitters(root: Instance, list)
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("ParticleEmitter") or descendant:IsA("Trail") then
			table.insert(list, descendant)
		end
	end
end

local function getPathPoints(container: Instance): { Vector3 }
	local parts = {}
	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("BasePart") and child.Name:match("^CurrentPoint") then
			table.insert(parts, child)
		end
	end
	table.sort(parts, function(a, b)
		return a.Name < b.Name
	end)
	local points = {}
	for _, part in ipairs(parts) do
		table.insert(points, part.Position)
	end
	return points
end

-- Ring track: polyline points + cumulative lengths for sampling.
local function buildTrack(points: { Vector3 }, ringsFolder: Instance, maxSpeed: number)
	local cumulative = { 0 }
	for i = 2, #points do
		cumulative[i] = cumulative[i - 1] + (points[i] - points[i - 1]).Magnitude
	end
	local total = cumulative[#points]
	if total <= 0.01 then
		return nil
	end

	local rings = {}
	for _, ring in ipairs(ringsFolder:GetChildren()) do
		if ring:IsA("BasePart") then
			table.insert(rings, { part = ring, distance = 0 })
		end
	end
	for index, ring in ipairs(rings) do
		ring.distance = ((index - 1) / #rings) * total
	end

	return {
		points = points,
		cumulative = cumulative,
		total = total,
		rings = rings,
		speed = math.clamp(maxSpeed * 0.6, RING_MIN_SPEED, RING_MAX_SPEED),
	}
end

local function sampleTrack(track, distance: number): (Vector3, Vector3)
	local points, cumulative = track.points, track.cumulative
	for i = 2, #points do
		if distance <= cumulative[i] then
			local segmentLength = cumulative[i] - cumulative[i - 1]
			local t = segmentLength > 0 and (distance - cumulative[i - 1]) / segmentLength or 0
			local tangent = (points[i] - points[i - 1]).Unit
			return points[i - 1]:Lerp(points[i], t), tangent
		end
	end
	local last = #points
	return points[last], (points[last] - points[last - 1]).Unit
end

local function buildVisual(instance: Instance)
	local shape = instance:GetAttribute("CurrentShape")
	local maxSpeed = instance:GetAttribute("CurrentMaxSpeed") or 0
	local visual = { emitters = {}, center = Vector3.new(), boundingRadius = 0 }

	if shape == "Circular" and instance:IsA("BasePart") then
		local radius = instance:GetAttribute("CurrentRadius") or 0
		local strandsFolder = instance:FindFirstChild("VortexStrands")
		if radius <= 0 or not strandsFolder then
			return nil
		end
		local strands = {}
		for _, strand in ipairs(strandsFolder:GetChildren()) do
			if strand:IsA("BasePart") then
				local offset = strand.Position - instance.Position
				table.insert(strands, {
					part = strand,
					angle = math.atan2(offset.Z, offset.X),
					radius = math.max(radius * INNER_RADIUS_FRACTION, Vector3.new(offset.X, 0, offset.Z).Magnitude),
					height = offset.Y,
					previousPosition = strand.Position,
				})
			end
		end
		visual.center = instance.Position
		visual.boundingRadius = radius
		visual.strands = strands
		visual.spin = instance:GetAttribute("CurrentSpin") or 1
		visual.angularSpeed = math.max(0.15, maxSpeed / radius)
		visual.inwardSpeed = math.max(0.4, maxSpeed * (instance:GetAttribute("CurrentSpiralBias") or 0.15))
		visual.vortexRadius = radius
		collectEmitters(strandsFolder, visual.emitters)
		return visual
	end

	local ringsFolder = instance:FindFirstChild("PathRings")
	if not ringsFolder then
		return nil
	end

	local points
	if shape == "Directional" and instance:IsA("BasePart") then
		local half = instance.CFrame.LookVector * (instance.Size.Z / 2)
		points = { instance.Position - half, instance.Position + half }
		visual.center = instance.Position
		visual.boundingRadius = instance.Size.Magnitude / 2
	elseif shape == "Path" then
		points = getPathPoints(instance)
		if #points < 2 then
			return nil
		end
		local sum = Vector3.new()
		for _, point in ipairs(points) do
			sum += point
		end
		visual.center = sum / #points
		local farthest = 0
		for _, point in ipairs(points) do
			farthest = math.max(farthest, (point - visual.center).Magnitude)
		end
		visual.boundingRadius = farthest + (instance:GetAttribute("CurrentWidth") or 12)
	else
		return nil
	end

	visual.track = buildTrack(points, ringsFolder, maxSpeed)
	if not visual.track then
		return nil
	end
	collectEmitters(ringsFolder, visual.emitters)
	return visual
end

-- Visual children replicate shortly after the current itself, so a build
-- that finds nothing yet is retried a few times instead of giving up.
local function register(instance: Instance, attempt: number?)
	attempt = attempt or 1
	if not instance:GetAttribute("CurrentShape") then
		return
	end
	task.delay(attempt == 1 and 0 or 1, function()
		if not instance.Parent then
			return
		end
		local visual = buildVisual(instance)
		if visual then
			visuals[instance] = visual
		elseif attempt < BUILD_RETRIES then
			register(instance, attempt + 1)
		end
	end)
end

local function watchFolder(folder: Instance)
	for _, child in ipairs(folder:GetChildren()) do
		register(child)
	end
	folder.ChildAdded:Connect(function(child)
		register(child)
	end)
	folder.ChildRemoved:Connect(function(child)
		visuals[child] = nil
		active[child] = nil
	end)
end

local currentsFolder = Workspace:FindFirstChild("Currents")
if currentsFolder then
	watchFolder(currentsFolder)
else
	Workspace.ChildAdded:Connect(function(child)
		if child.Name == "Currents" and not currentsFolder then
			currentsFolder = child
			watchFolder(child)
		end
	end)
end

local function setEmittersEnabled(visual, enabled: boolean)
	if visual.emittersEnabled == enabled then
		return
	end
	visual.emittersEnabled = enabled
	for _, emitter in ipairs(visual.emitters) do
		emitter.Enabled = enabled
	end
end

local function refreshActive()
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local origin = camera.CFrame.Position
	for instance, visual in pairs(visuals) do
		local near = (origin - visual.center).Magnitude <= visual.boundingRadius + CULL_MARGIN
		active[instance] = near and visual or nil
		setEmittersEnabled(visual, near)
	end
end

local function stepStrand(visual, strand, dt)
	strand.angle += visual.angularSpeed * visual.spin * dt
	strand.radius -= visual.inwardSpeed * dt

	if strand.radius <= visual.vortexRadius * INNER_RADIUS_FRACTION then
		strand.radius = visual.vortexRadius
		strand.angle = math.random() * math.pi * 2
		strand.height = (math.random() - 0.5) * visual.vortexRadius * 0.25
	end

	local position = visual.center
		+ Vector3.new(math.cos(strand.angle) * strand.radius, strand.height, math.sin(strand.angle) * strand.radius)

	if (position - strand.previousPosition).Magnitude > 0.01 then
		strand.part.CFrame = CFrame.lookAt(strand.previousPosition, position)
	else
		strand.part.CFrame = CFrame.new(position)
	end
	strand.previousPosition = position
end

-- Ring parts' Y axis is the ring axis, so rotate the look-frame's -Z
-- (tangent) onto +Y.
local RING_AXIS_FIX = CFrame.Angles(-math.pi / 2, 0, 0)

local function stepTrack(track, dt)
	for _, ring in ipairs(track.rings) do
		ring.distance = (ring.distance + track.speed * dt) % track.total
		local position, tangent = sampleTrack(track, ring.distance)
		ring.part.CFrame = CFrame.lookAt(position, position + tangent) * RING_AXIS_FIX
	end
end

local sinceUpdate = 0
local sinceCull = CULL_REFRESH_INTERVAL

RunService.Heartbeat:Connect(function(deltaTime)
	sinceCull += deltaTime
	if sinceCull >= CULL_REFRESH_INTERVAL then
		sinceCull = 0
		refreshActive()
	end

	sinceUpdate += deltaTime
	if sinceUpdate < UPDATE_INTERVAL then
		return
	end
	local dt = sinceUpdate
	sinceUpdate = 0

	for _, visual in pairs(active) do
		if visual.strands then
			for _, strand in ipairs(visual.strands) do
				stepStrand(visual, strand, dt)
			end
		elseif visual.track then
			stepTrack(visual.track, dt)
		end
	end
end)
