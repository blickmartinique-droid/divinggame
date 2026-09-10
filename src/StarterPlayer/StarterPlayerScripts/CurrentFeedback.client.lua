-- Player-side feel for being carried by a current, driven entirely by what
-- CurrentField already publishes (push velocity + enter/exit signals) --
-- nothing here touches movement, rotation, or the swim animations.
--
--   * Field of view: widens by up to FOV_BOOST degrees as the push grows
--     past FOV_START_SPEED, smoothly, and eases back to the camera's own
--     FOV on exit. Only ever an offset on top of whatever FOV the camera
--     currently has, so any other system changing FOV still works.
--   * Speed streaks: thin motes rushing past the player against the push
--     direction, only while the push is genuinely fast (fast lanes), so
--     gentle currents stay quiet. Bubbles and the wake already scale with
--     real speed in SwimWaterEffects, so they need nothing here.
--   * Sound: if the current carries a CurrentSoundId Attribute, a looped
--     Sound is played on the character with volume following the push,
--     and fades out on exit. Off by default (no asset assumed).
--
-- No camera shake, no screen overlays: everything stays comfortable and
-- never obstructs the view.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CurrentField = require(ReplicatedStorage.Shared.Modules.CurrentField)

local player = Players.LocalPlayer

local FOV_BOOST = 8
local FOV_START_SPEED = 12
local FOV_FULL_SPEED = 40
local FOV_RESPONSE_TIME = 0.5
local STREAK_START_SPEED = 18
local STREAK_FULL_SPEED = 45
local STREAK_MAX_RATE = 40
local SOUND_MAX_VOLUME = 0.6
local SOUND_FADE_TIME = 0.8

local camera = Workspace.CurrentCamera
local appliedFovOffset = 0

local function createStreaks(rootPart: BasePart)
	local attachment = Instance.new("Attachment")
	attachment.Name = "CurrentStreakAttachment"
	attachment.Parent = rootPart

	local streaks = Instance.new("ParticleEmitter")
	streaks.Name = "CurrentSpeedStreaks"
	streaks.Rate = 0
	streaks.Lifetime = NumberRange.new(0.25, 0.45)
	streaks.Speed = NumberRange.new(18, 30)
	streaks.SpreadAngle = Vector2.new(35, 35)
	streaks.EmissionDirection = Enum.NormalId.Front
	streaks.Orientation = Enum.ParticleOrientation.VelocityParallel
	streaks.Squash = NumberSequence.new(-3)
	streaks.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.08),
		NumberSequenceKeypoint.new(0.5, 0.12),
		NumberSequenceKeypoint.new(1, 0),
	})
	streaks.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.6),
		NumberSequenceKeypoint.new(1, 1),
	})
	streaks.Color = ColorSequence.new(Color3.fromRGB(215, 235, 240))
	streaks.LightEmission = 0.1
	streaks.LightInfluence = 0
	streaks.Parent = attachment

	return attachment, streaks
end

local function onCharacterAdded(character)
	local rootPart = character:WaitForChild("HumanoidRootPart")
	local humanoid = character:WaitForChild("Humanoid")
	local streakAttachment, streaks = createStreaks(rootPart)

	local sound: Sound? = nil
	local soundTargetVolume = 0

	local function stopSound()
		if sound then
			local fading = sound
			sound = nil
			task.delay(SOUND_FADE_TIME, function()
				fading:Destroy()
			end)
		end
		soundTargetVolume = 0
	end

	local function startSound(current: Instance)
		stopSound()
		local soundId = current:GetAttribute("CurrentSoundId")
		if typeof(soundId) ~= "string" or soundId == "" then
			return
		end
		local newSound = Instance.new("Sound")
		newSound.Name = "CurrentLoop"
		newSound.SoundId = soundId
		newSound.Looped = true
		newSound.Volume = 0
		newSound.RollOffMaxDistance = 40
		newSound.Parent = rootPart
		newSound:Play()
		sound = newSound
	end

	local enteredConnection = CurrentField.Entered:Connect(startSound)
	local changedConnection = CurrentField.Changed:Connect(startSound)
	local exitedConnection = CurrentField.Exited:Connect(stopSound)

	local heartbeat
	heartbeat = RunService.Heartbeat:Connect(function(deltaTime)
		if not character.Parent then
			heartbeat:Disconnect()
			enteredConnection:Disconnect()
			changedConnection:Disconnect()
			exitedConnection:Disconnect()
			stopSound()
			if camera and appliedFovOffset ~= 0 then
				camera.FieldOfView -= appliedFovOffset
				appliedFovOffset = 0
			end
			return
		end

		-- A dead character is no longer swimming (SwimController stops
		-- applying the push), so every effect eases out as if the push were 0.
		local velocity = humanoid.Health > 0 and CurrentField.GetVelocity() or Vector3.new()
		local speed = velocity.Magnitude

		-- FOV: applied as a tracked offset so it composes with any base FOV.
		local fovFraction = math.clamp((speed - FOV_START_SPEED) / (FOV_FULL_SPEED - FOV_START_SPEED), 0, 1)
		local targetOffset = fovFraction * fovFraction * FOV_BOOST
		local alpha = 1 - math.exp(-deltaTime / FOV_RESPONSE_TIME)
		local newOffset = appliedFovOffset + (targetOffset - appliedFovOffset) * alpha
		if math.abs(newOffset) < 0.02 and targetOffset == 0 then
			newOffset = 0
		end
		if camera and newOffset ~= appliedFovOffset then
			camera.FieldOfView += newOffset - appliedFovOffset
			appliedFovOffset = newOffset
		end

		-- Streaks rush against the push direction, from just ahead of the player.
		local streakFraction = math.clamp((speed - STREAK_START_SPEED) / (STREAK_FULL_SPEED - STREAK_START_SPEED), 0, 1)
		streaks.Rate = streakFraction * STREAK_MAX_RATE
		if speed > 0.5 then
			local direction = velocity / speed
			streakAttachment.WorldCFrame = CFrame.lookAt(rootPart.Position + direction * 6, rootPart.Position - direction)
		end

		if sound then
			soundTargetVolume = math.clamp(speed / FOV_FULL_SPEED, 0.15, 1) * SOUND_MAX_VOLUME * CurrentField.GetInfluence()
			sound.Volume += (soundTargetVolume - sound.Volume) * alpha
		end
	end)
end

if player.Character then
	onCharacterAdded(player.Character)
end
player.CharacterAdded:Connect(onCharacterAdded)
