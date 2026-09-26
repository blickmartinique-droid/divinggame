-- Sways the underwater plants tagged "Sway" by the world builders, with
-- their SwayAmplitude (radians) and SwaySpeed (Hz) and a per-plant phase
-- so a meadow ripples instead of moving in lockstep:
--   * a BasePart (seagrass blade, anemone tentacle, worm plume) rocks
--     about its own base;
--   * a Model bends at its joints (Joint1..JointN CFrame attributes, see
--     MarineFlora): each joint turns a little on top of the one below,
--     with a lag, so a wave travels up a kelp stalk; each part follows the
--     joint named by its Segment attribute (0 = rooted, never moves).
-- Client-only CFrame writes on anchored parts -- nothing replicates --
-- batched through BulkMoveTo, and only plants near the camera move; the
-- list is refreshed on a slow timer.

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local RANGE = 140
local REFRESH_INTERVAL = 1
local UPDATE_INTERVAL = 1 / 30
local WAVE_LAG = 0.55 -- phase delay per joint, radians

type PartRest = { base: CFrame, half: number, amplitude: number, speed: number, phase: number }
type ChainRest = {
	origin: Vector3,
	joints: { CFrame }, -- rest frames
	links: { CFrame }, -- joint k relative to joint k-1
	segments: { { part: BasePart, offset: CFrame } }, -- per joint
	amplitude: number,
	speed: number,
	phase: number,
}

local partRest: { [BasePart]: PartRest } = setmetatable({}, { __mode = "k" }) :: any
local chainRest: { [Model]: ChainRest | false } = setmetatable({}, { __mode = "k" }) :: any
local nearbyParts: { BasePart } = {}
local nearbyChains: { Model } = {}
local sinceRefresh = REFRESH_INTERVAL
local sinceUpdate = 0

local function phaseOf(position: Vector3): number
	return (position.X * 0.13 + position.Z * 0.07) % (math.pi * 2)
end

-- A chain's rest pose, read the first time it comes near (by then all of
-- its parts have replicated). False if the model is not a valid chain.
local function buildChain(model: Model): ChainRest | false
	local count = tonumber(model:GetAttribute("SwayJoints")) or 0
	local joints = {}
	for index = 1, count do
		local joint = model:GetAttribute("Joint" .. index)
		if typeof(joint) ~= "CFrame" then
			return false
		end
		joints[index] = joint
	end
	if #joints == 0 then
		return false
	end
	local links = {}
	for index = 2, #joints do
		links[index] = joints[index - 1]:Inverse() * joints[index]
	end
	local segments = {}
	for index = 1, #joints do
		segments[index] = {}
	end
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			local index = tonumber(descendant:GetAttribute("Segment")) or 1
			if index >= 1 then
				index = math.min(index, #joints)
				table.insert(segments[index], { part = descendant, offset = joints[index]:Inverse() * descendant.CFrame })
			end
		end
	end
	return {
		origin = joints[1].Position,
		joints = joints,
		links = links,
		segments = segments,
		amplitude = tonumber(model:GetAttribute("SwayAmplitude")) or 0.05,
		speed = (tonumber(model:GetAttribute("SwaySpeed")) or 0.4) * math.pi * 2,
		phase = phaseOf(joints[1].Position),
	}
end

local function refreshNearby()
	table.clear(nearbyParts)
	table.clear(nearbyChains)
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local origin = camera.CFrame.Position
	for _, plant in ipairs(CollectionService:GetTagged("Sway")) do
		if not plant.Parent then
			continue
		end
		if plant:IsA("BasePart") then
			local rest = partRest[plant]
			if not rest then
				rest = {
					base = plant.CFrame * CFrame.new(0, -plant.Size.Y / 2, 0),
					half = plant.Size.Y / 2,
					amplitude = tonumber(plant:GetAttribute("SwayAmplitude")) or 0.1,
					speed = (tonumber(plant:GetAttribute("SwaySpeed")) or 0.6) * math.pi * 2,
					phase = phaseOf(plant.Position),
				}
				partRest[plant] = rest
			end
			if (rest.base.Position - origin).Magnitude <= RANGE then
				table.insert(nearbyParts, plant)
			end
		elseif plant:IsA("Model") then
			local rest = chainRest[plant]
			local first = plant:GetAttribute("Joint1")
			local position = rest and rest.origin or (typeof(first) == "CFrame" and first.Position or nil)
			if position and (position - origin).Magnitude <= RANGE then
				if rest == nil then
					rest = buildChain(plant)
					chainRest[plant] = rest
				end
				if rest then
					table.insert(nearbyChains, plant)
				end
			end
		end
	end
end

local moveParts: { BasePart } = {}
local moveFrames: { CFrame } = {}

local function step(now: number)
	table.clear(moveParts)
	table.clear(moveFrames)
	for _, plant in ipairs(nearbyParts) do
		local rest = partRest[plant]
		if rest and plant.Parent then
			local t = now * rest.speed + rest.phase
			local tilt = CFrame.Angles(math.sin(t) * rest.amplitude, 0, math.sin(t * 0.7 + 1.3) * rest.amplitude * 0.6)
			table.insert(moveParts, plant)
			table.insert(moveFrames, rest.base * tilt * CFrame.new(0, rest.half, 0))
		end
	end
	for _, model in ipairs(nearbyChains) do
		local rest = chainRest[model]
		if rest and model.Parent then
			local frame
			for index, joint in ipairs(rest.joints) do
				local t = now * rest.speed + rest.phase - (index - 1) * WAVE_LAG
				local tilt = CFrame.Angles(math.sin(t) * rest.amplitude, 0, math.sin(t * 0.7 + 1.3) * rest.amplitude * 0.6)
				frame = (index == 1 and joint or frame * rest.links[index]) * tilt
				for _, entry in ipairs(rest.segments[index]) do
					table.insert(moveParts, entry.part)
					table.insert(moveFrames, frame * entry.offset)
				end
			end
		end
	end
	if #moveParts > 0 then
		Workspace:BulkMoveTo(moveParts, moveFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

RunService.Heartbeat:Connect(function(deltaTime)
	sinceRefresh += deltaTime
	if sinceRefresh >= REFRESH_INTERVAL then
		sinceRefresh = 0
		refreshNearby()
	end
	sinceUpdate += deltaTime
	if sinceUpdate < UPDATE_INTERVAL then
		return
	end
	sinceUpdate = 0
	step(os.clock())
end)
