-- Player bubble + underwater wake visuals. Fully self-contained: reads only
-- rootPart.AssemblyLinearVelocity (already public) plus the same shared
-- DepthUtils/CurrentField/MovementConfig modules other ambient scripts
-- already use -- nothing in SwimController was touched to support this, per
-- "use data that's already available rather than modifying the swim
-- controller." This replaces the old flat hand-trail + single bubble
-- emitter that used to live inside SwimController.client.lua.
--
-- Three emitters:
--  - SwimBreathBubbles (on Head): slow, irregular little bursts, like
--    breathing, independent of movement speed.
--  - SwimMovementBubbles (on rootPart): rate scales with speed (nothing at
--    idle, more at sprint), plus a short burst whenever travel direction
--    changes sharply.
--  - SwimWakeTurbulence (on a floating Attachment): placed each frame behind
--    the character's ACTUAL velocity direction (not body orientation), so it
--    correctly trails behind forward/backward/vertical/current-pushed motion
--    without any per-case special logic. Kept small, soft and non-glowing so
--    it reads as water disturbance rather than smoke/fire/a trail effect.
--
-- Both bubble emitters get a small drift bias from CurrentField, matching
-- the pattern already used in UnderwaterAmbience.client.lua.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DepthUtils = require(ReplicatedStorage.Shared.Modules.DepthUtils)
local CurrentField = require(ReplicatedStorage.Shared.Modules.CurrentField)
local MovementConfig = require(ReplicatedStorage.Shared.Config.MovementConfig)

local player = Players.LocalPlayer

local MIN_EFFECT_SPEED = 1 -- studs/s below which movement bubbles/wake are fully off
local FAST_SPEED_REF = (MovementConfig.BaseSwimSpeed or 16) * 1.4 -- visual "fast" reference, independent of the sprint controller's own constant
local RATE_SMOOTH_TIME = 0.4
local WAKE_OFFSET = 2.5
local TURN_DOT_THRESHOLD = 0.6 -- below this, previous/current direction counts as a "sharp turn"
local CURRENT_DRIFT_SCALE = 0.4

local MOVEMENT_BUBBLES_MAX_RATE = 18
local BREATH_MIN_INTERVAL = 2.5
local BREATH_MAX_INTERVAL = 5.5

local function createBreathBubbles(head)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "SwimBreathBubbles"
	emitter.Rate = 0
	emitter.Lifetime = NumberRange.new(1.2, 2.6)
	emitter.Speed = NumberRange.new(1.5, 3.5)
	emitter.SpreadAngle = Vector2.new(20, 20)
	emitter.Acceleration = Vector3.new(0, 3.5, 0)
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-90, 90)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.08),
		NumberSequenceKeypoint.new(0.6, 0.16),
		NumberSequenceKeypoint.new(1, 0.05),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Color = ColorSequence.new(Color3.new(1, 1, 1))
	emitter.LightEmission = 0
	emitter.LightInfluence = 1
	emitter.Parent = head
	return emitter
end

local function createMovementBubbles(rootPart)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "SwimMovementBubbles"
	emitter.Rate = 0
	emitter.Lifetime = NumberRange.new(0.6, 2.2)
	emitter.Speed = NumberRange.new(1, 4)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Acceleration = Vector3.new(0, 4, 0)
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-120, 120)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.05),
		NumberSequenceKeypoint.new(0.5, 0.14),
		NumberSequenceKeypoint.new(1, 0.04),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.4),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Color = ColorSequence.new(Color3.new(1, 1, 1))
	emitter.LightEmission = 0
	emitter.LightInfluence = 1
	emitter.Parent = rootPart
	return emitter
end

local function createWakeTurbulence(attachment)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "SwimWakeTurbulence"
	emitter.Rate = 0
	emitter.Lifetime = NumberRange.new(0.4, 0.9)
	emitter.Speed = NumberRange.new(0.2, 1)
	emitter.SpreadAngle = Vector2.new(35, 35)
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-40, 40)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.15),
		NumberSequenceKeypoint.new(0.4, 0.4),
		NumberSequenceKeypoint.new(1, 0.05),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.55),
		NumberSequenceKeypoint.new(0.3, 0.65),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Color = ColorSequence.new(Color3.fromRGB(225, 240, 245))
	emitter.LightEmission = 0
	emitter.LightInfluence = 1
	emitter.Parent = attachment
	return emitter
end

local function onCharacterAdded(character)
	local rootPart = character:WaitForChild("HumanoidRootPart")
	local head = character:WaitForChild("Head")

	local breathBubbles = createBreathBubbles(head)
	local movementBubbles = createMovementBubbles(rootPart)

	local wakeAttachment = Instance.new("Attachment")
	wakeAttachment.Name = "SwimWakeAttachment"
	wakeAttachment.Parent = rootPart
	local wakeTurbulence = createWakeTurbulence(wakeAttachment)

	local movementRate = 0
	local wakeRate = 0
	local previousDirection = nil
	local nextBreathTime = os.clock() + (BREATH_MIN_INTERVAL + math.random() * (BREATH_MAX_INTERVAL - BREATH_MIN_INTERVAL))

	local connection
	connection = RunService.Heartbeat:Connect(function(deltaTime)
		if not character.Parent then
			connection:Disconnect()
			return
		end

		local underwater = DepthUtils.GetDepth(rootPart.Position) > 0
		if not underwater then
			if movementRate ~= 0 then
				movementRate = 0
				movementBubbles.Rate = 0
			end
			if wakeRate ~= 0 then
				wakeRate = 0
				wakeTurbulence.Rate = 0
			end
			breathBubbles.Rate = 0
			previousDirection = nil
			return
		end

		local velocity = rootPart.AssemblyLinearVelocity
		local speed = velocity.Magnitude
		local speedFraction = math.clamp((speed - MIN_EFFECT_SPEED) / (FAST_SPEED_REF - MIN_EFFECT_SPEED), 0, 1)

		-- Breathing bubbles: independent of movement, just a slow irregular timer.
		breathBubbles.Rate = 0
		local now = os.clock()
		if now >= nextBreathTime then
			breathBubbles:Emit(math.random(1, 3))
			nextBreathTime = now + (BREATH_MIN_INTERVAL + math.random() * (BREATH_MAX_INTERVAL - BREATH_MIN_INTERVAL))
		end

		-- Movement bubbles: rate scales with speed, plus a burst on sharp turns.
		local targetMovementRate = speedFraction * MOVEMENT_BUBBLES_MAX_RATE
		local rateAlpha = 1 - math.exp(-(1 / RATE_SMOOTH_TIME) * deltaTime)
		movementRate = movementRate + (targetMovementRate - movementRate) * rateAlpha
		movementBubbles.Rate = movementRate

		local targetWakeRate = speedFraction * MOVEMENT_BUBBLES_MAX_RATE
		wakeRate = wakeRate + (targetWakeRate - wakeRate) * rateAlpha
		wakeTurbulence.Rate = wakeRate

		if speed > MIN_EFFECT_SPEED then
			local direction = velocity.Unit
			wakeAttachment.WorldPosition = rootPart.Position - direction * WAKE_OFFSET

			if previousDirection then
				local dot = previousDirection:Dot(direction)
				if dot < TURN_DOT_THRESHOLD then
					movementBubbles:Emit(math.random(3, 5))
				end
			end
			previousDirection = direction
		else
			previousDirection = nil
		end

		local currentDrift = CurrentField.GetVelocity() * CURRENT_DRIFT_SCALE
		breathBubbles.Acceleration = Vector3.new(0, 3.5, 0) + currentDrift
		movementBubbles.Acceleration = Vector3.new(0, 4, 0) + currentDrift
	end)
end

if player.Character then
	onCharacterAdded(player.Character)
end
player.CharacterAdded:Connect(onCharacterAdded)
