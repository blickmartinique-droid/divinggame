-- Underwater sun shafts: a handful of tall, soft, additive Beams hanging
-- from just under the surface, leaning along the sun direction, placed on
-- a coarse world grid around the camera so they stay put while the player
-- swims through them (a shaft that followed the camera would read as
-- glued to the screen). Shafts fade in over their first second and out
-- when their grid cell drops out of range, sway slowly, and fade with
-- depth: full in the shallows, gone past SHAFT_MAX_DEPTH where the sun no
-- longer reaches. Client-only, invisible parts, no lights -- just Beams,
-- which are about the cheapest large translucent thing Roblox can draw.
-- Count comes from the graphics level (0 on Low).

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DepthUtils = require(ReplicatedStorage.Shared.Modules.DepthUtils)
local GraphicsQuality = require(ReplicatedStorage.Shared.Modules.GraphicsQuality)

local CELL_SIZE = 34
local RANGE_CELLS = 2 -- ring of cells around the camera considered
local SHAFT_LENGTH = 75
local SHAFT_FULL_DEPTH = 45
local SHAFT_MAX_DEPTH = 110
local FADE_TIME = 1.2
local UPDATE_INTERVAL = 0.1
local REASSIGN_INTERVAL = 0.6
local BASE_OPACITY = 0.22

local rig = Instance.new("Part")
rig.Name = "LightShaftRig"
rig.Anchored = true
rig.CanCollide = false
rig.CanQuery = false
rig.CanTouch = false
rig.Transparency = 1
rig.Size = Vector3.new(1, 1, 1)
rig.CFrame = CFrame.new()
rig.Parent = Workspace

local shafts = {}

local function createShaft()
	local top = Instance.new("Attachment")
	top.Parent = rig
	local bottom = Instance.new("Attachment")
	bottom.Parent = rig

	local beam = Instance.new("Beam")
	beam.Attachment0 = top
	beam.Attachment1 = bottom
	beam.FaceCamera = true
	beam.LightEmission = 1
	beam.LightInfluence = 0
	beam.Color = ColorSequence.new(Color3.fromRGB(255, 244, 220), Color3.fromRGB(190, 235, 245))
	beam.Segments = 4
	beam.Transparency = NumberSequence.new(1)
	beam.Enabled = false
	beam.Parent = rig

	return {
		top = top,
		bottom = bottom,
		beam = beam,
		cell = nil,
		opacity = 0,
		targetOpacity = 0,
		phase = math.random() * math.pi * 2,
		width0 = 3 + math.random() * 3,
		width1 = 10 + math.random() * 8,
		jitter = Vector3.new((math.random() - 0.5) * CELL_SIZE * 0.6, 0, (math.random() - 0.5) * CELL_SIZE * 0.6),
	}
end

local function setShaftCount(count: number)
	for i = #shafts + 1, count do
		shafts[i] = createShaft()
	end
	for i = #shafts, count + 1, -1 do
		local shaft = table.remove(shafts, i)
		shaft.beam:Destroy()
		shaft.top:Destroy()
		shaft.bottom:Destroy()
	end
end

setShaftCount(GraphicsQuality.Get().LightShafts)
GraphicsQuality.Changed:Connect(function()
	setShaftCount(GraphicsQuality.Get().LightShafts)
end)

local function cellKey(cx: number, cz: number): string
	return cx .. ":" .. cz
end

-- Assigns free shafts to the nearest unoccupied cells, releasing shafts
-- whose cell went out of range (they fade out before being reused).
local function reassign(cameraPosition: Vector3)
	local centerX = math.floor(cameraPosition.X / CELL_SIZE + 0.5)
	local centerZ = math.floor(cameraPosition.Z / CELL_SIZE + 0.5)

	local wanted = {}
	for dx = -RANGE_CELLS, RANGE_CELLS do
		for dz = -RANGE_CELLS, RANGE_CELLS do
			local key = cellKey(centerX + dx, centerZ + dz)
			wanted[key] = { x = (centerX + dx) * CELL_SIZE, z = (centerZ + dz) * CELL_SIZE, dist = dx * dx + dz * dz }
		end
	end

	local occupied = {}
	for _, shaft in ipairs(shafts) do
		if shaft.cell and not wanted[shaft.cell] then
			shaft.targetOpacity = 0
			if shaft.opacity <= 0.01 then
				shaft.cell = nil
			end
		elseif shaft.cell then
			occupied[shaft.cell] = true
		end
	end

	local candidates = {}
	for key, cell in pairs(wanted) do
		if not occupied[key] then
			table.insert(candidates, { key = key, cell = cell })
		end
	end
	table.sort(candidates, function(a, b)
		return a.cell.dist < b.cell.dist
	end)

	local next = 1
	for _, shaft in ipairs(shafts) do
		if not shaft.cell and candidates[next] then
			local candidate = candidates[next]
			next += 1
			shaft.cell = candidate.key
			shaft.opacity = 0
			shaft.targetOpacity = 1
			local x, z = candidate.cell.x + shaft.jitter.X, candidate.cell.z + shaft.jitter.Z
			shaft.top.Position = Vector3.new(x, DepthUtils.SURFACE_Y - 1, z)
			shaft.bottom.Position = Vector3.new(x, DepthUtils.SURFACE_Y - 1 - SHAFT_LENGTH, z)
		end
	end
end

local sinceUpdate = 0
local sinceReassign = REASSIGN_INTERVAL
local elapsed = 0

RunService.Heartbeat:Connect(function(deltaTime)
	elapsed += deltaTime
	sinceUpdate += deltaTime
	sinceReassign += deltaTime
	if sinceUpdate < UPDATE_INTERVAL or #shafts == 0 then
		return
	end
	local dt = sinceUpdate
	sinceUpdate = 0

	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local cameraPosition = camera.CFrame.Position
	local depth = DepthUtils.GetDepth(cameraPosition)

	-- Depth envelope: none above water, ramps in over the first metres,
	-- full through the shallows, gone where the sun no longer reaches.
	local depthFactor = 0
	if depth > 0 then
		depthFactor = math.min(depth / 4, 1) * (1 - math.clamp((depth - SHAFT_FULL_DEPTH) / (SHAFT_MAX_DEPTH - SHAFT_FULL_DEPTH), 0, 1))
	end

	if depthFactor <= 0 then
		for _, shaft in ipairs(shafts) do
			shaft.beam.Enabled = false
		end
		return
	end

	if sinceReassign >= REASSIGN_INTERVAL then
		sinceReassign = 0
		reassign(cameraPosition)
	end

	-- Lean the shafts along the sun direction so they read as light, not pillars.
	local sun = Lighting:GetSunDirection()
	local lean = Vector3.new(-sun.X, 0, -sun.Z) * SHAFT_LENGTH * 0.35

	local fadeAlpha = math.min(dt / FADE_TIME, 1)
	for _, shaft in ipairs(shafts) do
		if shaft.cell then
			shaft.opacity += (shaft.targetOpacity - shaft.opacity) * fadeAlpha
			local sway = 1 + 0.15 * math.sin(elapsed * 0.35 + shaft.phase)
			shaft.beam.Width0 = shaft.width0 * sway
			shaft.beam.Width1 = shaft.width1 * (2 - sway)
			shaft.bottom.Position = Vector3.new(shaft.top.Position.X, shaft.top.Position.Y - SHAFT_LENGTH, shaft.top.Position.Z)
				+ lean * (1 + 0.1 * math.sin(elapsed * 0.2 + shaft.phase))

			local opacity = BASE_OPACITY * shaft.opacity * depthFactor
			shaft.beam.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1 - opacity),
				NumberSequenceKeypoint.new(0.55, 1 - opacity * 0.7),
				NumberSequenceKeypoint.new(1, 1),
			})
			shaft.beam.Enabled = opacity > 0.005
		else
			shaft.beam.Enabled = false
		end
	end
end)
