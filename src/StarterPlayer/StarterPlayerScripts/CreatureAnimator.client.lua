-- Swims the procedural creature bodies (CreatureBodies): every Motor6D
-- carrying Swing* attributes -- a fish's tail and pectoral fins, a manta's
-- wings, a turtle's flippers, a jellyfish's tentacles and oral arms -- gets
-- a looping sine rotation about its SwingAxis, written to Motor6D.Transform
-- on this client only (never replicated, costs the server nothing). The
-- beat doubles while the creature flees or chases (the server's "State"
-- attribute). Only creatures near the camera animate; the candidate list
-- is refreshed on a slow timer. Imported rigs with published clips are
-- animated by their own Animator instead and have no Swing joints.

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local RANGE = 170
local REFRESH_INTERVAL = 0.5
local FAST_BEAT = 2.2

local jointsByModel = setmetatable({}, { __mode = "k" })
-- Per-creature swim clock, advanced faster while it hurries: changing the
-- beat then speeds the motion up smoothly instead of jumping its phase.
local clockByModel = setmetatable({}, { __mode = "k" })
local nearby = {}
local sinceRefresh = REFRESH_INTERVAL

local function collectJoints(model: Instance)
	local joints = {}
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("Motor6D") then
			local amplitude = descendant:GetAttribute("SwingAmplitude")
			local axis = descendant:GetAttribute("SwingAxis")
			if amplitude and typeof(axis) == "Vector3" and axis.Magnitude > 0 then
				table.insert(joints, {
					motor = descendant,
					axis = axis.Unit,
					amplitude = amplitude,
					frequency = (descendant:GetAttribute("SwingFrequency") or 1) * math.pi * 2,
					phase = (descendant:GetAttribute("SwingPhase") or 0) + math.random() * 0.5,
				})
			end
		end
	end
	return joints
end

local function refreshNearby()
	table.clear(nearby)
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local origin = camera.CFrame.Position
	for _, model in ipairs(CollectionService:GetTagged("Creature")) do
		if model:IsA("Model") and model.PrimaryPart and (model.PrimaryPart.Position - origin).Magnitude <= RANGE then
			local joints = jointsByModel[model]
			if not joints then
				joints = collectJoints(model)
				jointsByModel[model] = joints
			end
			if #joints > 0 then
				table.insert(nearby, { model = model, joints = joints })
			end
		end
	end
end

RunService.Heartbeat:Connect(function(deltaTime)
	sinceRefresh += deltaTime
	if sinceRefresh >= REFRESH_INTERVAL then
		sinceRefresh = 0
		refreshNearby()
	end

	for _, entry in ipairs(nearby) do
		local model = entry.model
		if model.Parent then
			local state = model:GetAttribute("State")
			local beat = (state == "Flee" or state == "Chase") and FAST_BEAT or 1
			local clock = (clockByModel[model] or math.random() * 10) + deltaTime * beat
			clockByModel[model] = clock
			for _, joint in ipairs(entry.joints) do
				local angle = math.sin(clock * joint.frequency + joint.phase) * joint.amplitude
				joint.motor.Transform = CFrame.fromAxisAngle(joint.axis, angle)
			end
		end
	end
end)
