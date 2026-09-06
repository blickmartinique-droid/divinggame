-- Free-swim movement controller, active only while underwater (depth > 0).
-- On land / in the air, the default Roblox Humanoid movement (walking,
-- gravity, jumping) is left alone. Underwater, Roblox's built-in ground-
-- follow logic would otherwise cancel any vertical velocity we set, so
-- PlatformStand fully disables the built-in controller and this script
-- drives 100% of the character's motion: horizontal + camera-pitch-driven
-- vertical (W/S follow the camera's full look direction, A/D stay
-- horizontal), an additional manual vertical control (Space/LeftControl/C),
-- facing direction, and swim animations.
--
-- Orientation is driven by the SAME 3D direction the physics actually
-- moves the character in (the combined camera-look + manual-vertical
-- velocity), not by an artificial fixed tilt. While swimming forward, the
-- pitch is solved so the body's head-to-feet axis points exactly along the
-- real velocity vector -- level swimming reads as a fully horizontal
-- "torpedo" body with the head leading, and looking/swimming up or down
-- banks the body to match, proportionally, with no separate hand-tuned
-- angle. Backward keeps a smaller, fixed recline (a floating-on-back look)
-- since it isn't meant to mirror forward's full dive. The moment there's no
-- input at all, the character smoothly levels back out to a vertical rest
-- pose instead of staying frozen mid-tilt (see the Idle branch in the
-- movement loop).
--
-- This script is the SOLE owner of the character's rotation while
-- swimming. Humanoid.AutoRotate is explicitly disabled in enterSwimMode
-- so Roblox's own Shift Lock controller never also tries to rotate the
-- character to face the camera -- PlatformStand alone does not block
-- that path, and the two fighting over rotation each frame is what
-- caused visible shaking. The camera's facing (used for WASD direction)
-- and the character's body facing (set here) are intentionally
-- independent: the camera is free to look anywhere without ever
-- rotating the body itself.
--
-- AssemblyAngularVelocity is zeroed every frame while swimming, separate
-- from all of the above: a PlatformStand part is still simulated by the
-- physics engine (bumping the terrain/water can impart spin), and
-- nothing else ever damps that rotation. Left alone it never decays, so
-- the character would slowly turn in place forever even while sitting
-- completely idle with no rotation code running at all.
--
-- Depth holding while idle uses a LinearVelocity constraint (depthHold),
-- not just the AssemblyLinearVelocity write below: resetting Y velocity
-- to 0 once per Heartbeat still lets gravity integrate downward in the
-- gaps between frames (a small sawtooth that averages out to a steady
-- sink). depthHold enforces the same target Y velocity continuously
-- inside the physics solver instead, with zero force on X/Z so it never
-- touches horizontal movement.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local MovementConfig = require(ReplicatedStorage.Shared.Config.MovementConfig)
local DepthUtils = require(ReplicatedStorage.Shared.Modules.DepthUtils)
local SwimAnimationsConfig = require(ReplicatedStorage.Shared.Config.SwimAnimationsConfig)

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera

local FORWARD_KEYS = { [Enum.KeyCode.W] = true, [Enum.KeyCode.Up] = true }
local BACK_KEYS = { [Enum.KeyCode.S] = true, [Enum.KeyCode.Down] = true }
local LEFT_KEYS = { [Enum.KeyCode.A] = true, [Enum.KeyCode.Left] = true }
local RIGHT_KEYS = { [Enum.KeyCode.D] = true, [Enum.KeyCode.Right] = true }
local ASCEND_KEYS = { [Enum.KeyCode.Space] = true }
local DESCEND_KEYS = { [Enum.KeyCode.LeftControl] = true, [Enum.KeyCode.C] = true }

local TURN_RESPONSIVENESS = 8 -- higher = snappier turning, lower = floatier
local ANIMATION_FADE_TIME = 0.3
local ANIMATION_PLAYBACK_SPEEDS = {
	Idle = 0.25,
	Forward = 0.4,
	Backward = 0.25,
}

-- Small hysteresis margin above the surface (Y = 0) before swim mode
-- actually exits. Without it, tiny position noise right at the waterline
-- (most visible swimming backward, where the recline pitch tilts the head
-- up) flickers isSwimming on/off, which stops and restarts whatever swim
-- animation is currently playing. Entering swim mode is unaffected -- it
-- still happens the instant depth > 0, same as before.
local SURFACE_EXIT_BUFFER = 1.5

-- Backward-only pitch tuning (see the forward branch in the movement loop
-- for how forward's pitch is computed instead -- directly from the real
-- velocity angle, not from constants like these).
local BACKWARD_BASE_PITCH = math.rad(20) -- slight nose-up recline, floating on back
local VERTICAL_PITCH_RANGE = math.rad(45)
local MAX_SWIM_PITCH = math.rad(65)

local heldKeys = {}

UserInputService.InputBegan:Connect(function(input, gameProcessedEvent)
	if gameProcessedEvent then
		return
	end
	heldKeys[input.KeyCode] = true
end)

UserInputService.InputEnded:Connect(function(input)
	heldKeys[input.KeyCode] = nil
end)

local function isAnyKeyHeld(keySet)
	for keyCode in pairs(keySet) do
		if heldKeys[keyCode] then
			return true
		end
	end
	return false
end

local function flattenAndNormalize(vector)
	local flat = Vector3.new(vector.X, 0, vector.Z)
	if flat.Magnitude > 0 then
		return flat.Unit
	end
	return flat
end

-- Finds the swim/swim-idle animations Roblox ships on every default avatar
-- (normally auto-played by the built-in Animate script when touching Terrain
-- water), used as a fallback for any direction not yet set in
-- SwimAnimationsConfig.
local function findDefaultSwimAnimations(animateScript)
	local moveAnim, idleAnim
	for _, descendant in ipairs(animateScript:GetDescendants()) do
		if descendant:IsA("Animation") then
			local lowerName = descendant.Name:lower()
			if lowerName:find("swim") then
				if lowerName:find("idle") then
					idleAnim = idleAnim or descendant
				else
					moveAnim = moveAnim or descendant
				end
			end
		end
	end
	return moveAnim, idleAnim
end

-- Loads one track per swim state (Idle/Forward/Backward): a custom asset ID
-- from SwimAnimationsConfig if one has been picked, otherwise the default
-- avatar animation as a placeholder. Swim mode disables the default Animate
-- script's own control, so these are played manually instead while swimming.
local function loadSwimAnimations(character, humanoid)
	local animateScript = character:FindFirstChild("Animate")
	local defaultMoveAnim, defaultIdleAnim
	if animateScript then
		defaultMoveAnim, defaultIdleAnim = findDefaultSwimAnimations(animateScript)
	end

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	local function loadTrack(assetId, fallbackAnim)
		local animation = Instance.new("Animation")
		if assetId then
			animation.AnimationId = assetId
		elseif fallbackAnim then
			animation.AnimationId = fallbackAnim.AnimationId
		else
			return nil
		end

		local track = animator:LoadAnimation(animation)
		track.Looped = true
		return track
	end

	return {
		Idle = loadTrack(SwimAnimationsConfig.Idle, defaultIdleAnim),
		Forward = loadTrack(SwimAnimationsConfig.Forward, defaultMoveAnim),
		Backward = loadTrack(SwimAnimationsConfig.Backward, defaultMoveAnim),
	}
end

-- Bubble trail behind the hands while swimming, purely cosmetic feedback for
-- movement speed/direction.
local function createHandTrail(hand)
	local attachmentFront = Instance.new("Attachment")
	attachmentFront.Position = Vector3.new(0, 0.4, 0)
	attachmentFront.Parent = hand

	local attachmentBack = Instance.new("Attachment")
	attachmentBack.Position = Vector3.new(0, -0.4, 0)
	attachmentBack.Parent = hand

	local trail = Instance.new("Trail")
	trail.Attachment0 = attachmentFront
	trail.Attachment1 = attachmentBack
	trail.Lifetime = 0.5
	trail.MinLength = 0
	trail.FaceCamera = true
	trail.Color = ColorSequence.new(Color3.fromRGB(235, 250, 255))
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.4),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.WidthScale = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(1, 0),
	})
	trail.Enabled = false
	trail.Parent = hand

	return trail
end

local function setupSwimEffects(character)
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	local effects = { trails = {} }

	-- R15 names these LeftHand/RightHand; R6 only has whole-arm parts.
	local leftHand = character:FindFirstChild("LeftHand") or character:FindFirstChild("Left Arm")
	local rightHand = character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
	if leftHand then
		table.insert(effects.trails, createHandTrail(leftHand))
	end
	if rightHand then
		table.insert(effects.trails, createHandTrail(rightHand))
	end

	if rootPart then
		local bubbles = Instance.new("ParticleEmitter")
		bubbles.Rate = 0
		bubbles.Lifetime = NumberRange.new(0.4, 0.8)
		bubbles.Speed = NumberRange.new(1, 2)
		bubbles.Size = NumberSequence.new(0.15)
		bubbles.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.3),
			NumberSequenceKeypoint.new(1, 1),
		})
		bubbles.Color = ColorSequence.new(Color3.new(1, 1, 1))
		bubbles.Parent = rootPart
		effects.bubbles = bubbles

		local splash = Instance.new("ParticleEmitter")
		splash.Name = "SplashEmitter"
		splash.Rate = 0
		splash.Lifetime = NumberRange.new(0.3, 0.6)
		splash.Speed = NumberRange.new(6, 14)
		splash.SpreadAngle = Vector2.new(180, 180)
		splash.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.6),
			NumberSequenceKeypoint.new(1, 0),
		})
		splash.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.2),
			NumberSequenceKeypoint.new(1, 1),
		})
		splash.Color = ColorSequence.new(Color3.new(1, 1, 1))
		splash.Parent = rootPart
		effects.splash = splash
	end

	return effects
end

local function setSwimEffectsActive(effects, active)
	if not effects then
		return
	end
	for _, trail in ipairs(effects.trails) do
		trail.Enabled = active
	end
	if effects.bubbles then
		effects.bubbles.Rate = active and 25 or 0
	end
end

-- Resetting AssemblyLinearVelocity.Y once per Heartbeat isn't enough to
-- cancel gravity: the physics engine keeps integrating gravity between our
-- writes, so the character still drifts down on average (a "sawtooth"
-- velocity -- reset to 0, pulled down again, reset to 0...). A LinearVelocity
-- constraint holds a target velocity continuously inside the physics solver
-- itself, so it cancels gravity every step instead of once per frame.
-- ForceLimitMode.PerAxis with zero force on X/Z keeps it from touching
-- horizontal movement at all -- only Y is affected.
local function setupDepthHold(rootPart)
	local attachment = Instance.new("Attachment")
	attachment.Name = "SwimDepthHoldAttachment"
	attachment.Parent = rootPart

	local depthHold = Instance.new("LinearVelocity")
	depthHold.Name = "SwimDepthHold"
	depthHold.Attachment0 = attachment
	depthHold.RelativeTo = Enum.ActuatorRelativeTo.World
	depthHold.ForceLimitMode = Enum.ForceLimitMode.PerAxis
	depthHold.MaxAxesForce = Vector3.new(0, math.huge, 0)
	depthHold.VectorVelocity = Vector3.new()
	depthHold.Enabled = false
	depthHold.Parent = rootPart

	return depthHold
end

local function onCharacterAdded(character)
	local humanoid = character:WaitForChild("Humanoid")
	local rootPart = character:WaitForChild("HumanoidRootPart")
	local animateScript = character:WaitForChild("Animate")

	humanoid.WalkSpeed = MovementConfig.BaseSwimSpeed

	local animationTracks = loadSwimAnimations(character, humanoid)
	local swimEffects = setupSwimEffects(character)
	local depthHold = setupDepthHold(rootPart)
	local isSwimming = false
	local currentSwimState = nil

	local function playSwimState(state)
		if currentSwimState == state then
			return
		end
		if animationTracks and currentSwimState and animationTracks[currentSwimState] then
			animationTracks[currentSwimState]:Stop(ANIMATION_FADE_TIME)
		end
		currentSwimState = state
		if animationTracks and animationTracks[state] then
			animationTracks[state]:Play(ANIMATION_FADE_TIME)
			animationTracks[state]:AdjustSpeed(ANIMATION_PLAYBACK_SPEEDS[state] or 1)
		end
		setSwimEffectsActive(swimEffects, state ~= "Idle")
	end

	local function stopSwimAnimations()
		if animationTracks and currentSwimState and animationTracks[currentSwimState] then
			animationTracks[currentSwimState]:Stop(ANIMATION_FADE_TIME)
		end
		currentSwimState = nil
		setSwimEffectsActive(swimEffects, false)
	end

	local function enterSwimMode()
		isSwimming = true
		animateScript.Disabled = true
		humanoid.PlatformStand = true
		-- PlatformStand alone doesn't stop Roblox's own Shift Lock controller
		-- from trying to rotate the character to face the camera -- that
		-- path runs through AutoRotate, a separate flag. With both systems
		-- fighting over rotation while PlatformStand is also active, the
		-- result was visible camera/character shaking. Disabling AutoRotate
		-- hands rotation exclusively to this script, in every camera mode.
		humanoid.AutoRotate = false
		depthHold.Enabled = true
		if swimEffects.splash then
			swimEffects.splash:Emit(20)
		end
	end

	local function exitSwimMode()
		isSwimming = false
		humanoid.PlatformStand = false
		humanoid.AutoRotate = true
		depthHold.Enabled = false
		animateScript.Disabled = false
		stopSwimAnimations()
		if swimEffects.splash then
			swimEffects.splash:Emit(20)
		end
	end

	local heartbeatConnection
	heartbeatConnection = RunService.Heartbeat:Connect(function(deltaTime)
		if humanoid.Health <= 0 or not character.Parent then
			heartbeatConnection:Disconnect()
			return
		end

		local depth = DepthUtils.GetDepth(rootPart.Position)
		local shouldSwim
		if isSwimming then
			shouldSwim = depth > 0 or rootPart.Position.Y < SURFACE_EXIT_BUFFER
		else
			shouldSwim = depth > 0
		end
		if shouldSwim ~= isSwimming then
			if shouldSwim then
				enterSwimMode()
			else
				exitSwimMode()
			end
		end

		if not isSwimming then
			return
		end

		local flatLook = flattenAndNormalize(camera.CFrame.LookVector)
		local flatRight = flattenAndNormalize(camera.CFrame.RightVector)

		-- Forward/back use the camera's FULL look direction (including its
		-- pitch), not the flattened one: looking up while swimming forward
		-- now climbs, looking down dives, exactly like a diver swimming the
		-- way they're looking. Strafing (A/D) stays purely horizontal --
		-- camera pitch shouldn't push sideways movement up or down.
		local moveDirection3D = Vector3.new()
		if isAnyKeyHeld(FORWARD_KEYS) then
			moveDirection3D += camera.CFrame.LookVector
		end
		if isAnyKeyHeld(BACK_KEYS) then
			moveDirection3D -= camera.CFrame.LookVector
		end
		if isAnyKeyHeld(RIGHT_KEYS) then
			moveDirection3D += flatRight
		end
		if isAnyKeyHeld(LEFT_KEYS) then
			moveDirection3D -= flatRight
		end
		if moveDirection3D.Magnitude > 0 then
			moveDirection3D = moveDirection3D.Unit
		end

		-- Space/Ctrl remain available as a manual, additive vertical control
		-- on top of whatever camera-pitch-driven vertical speed W/S already
		-- produced above.
		local manualVerticalSpeed = 0
		if isAnyKeyHeld(ASCEND_KEYS) then
			manualVerticalSpeed += MovementConfig.VerticalSwimSpeed
		end
		if isAnyKeyHeld(DESCEND_KEYS) then
			manualVerticalSpeed -= MovementConfig.VerticalSwimSpeed
		end

		local fullVelocity = moveDirection3D * MovementConfig.BaseSwimSpeed + Vector3.new(0, manualVerticalSpeed, 0)
		rootPart.AssemblyLinearVelocity = fullVelocity
		-- depthHold (a LinearVelocity constraint, Y axis only) is what
		-- actually holds the vertical speed against gravity between frames;
		-- this AssemblyLinearVelocity write still sets the same Y target
		-- once per Heartbeat as before, the two simply agree. Uses the real
		-- combined Y (camera-pitch-driven + manual) so holding a climb/dive
		-- from looking up/down is just as stable as holding Space/Ctrl.
		depthHold.VectorVelocity = Vector3.new(0, fullVelocity.Y, 0)
		-- See the AssemblyAngularVelocity note near the top of this file:
		-- unrelated to AutoRotate, this stops leftover physics spin (e.g.
		-- from bumping terrain) from turning the character in place forever.
		rootPart.AssemblyAngularVelocity = Vector3.new()

		-- With AutoRotate disabled (see enterSwimMode), this script is the
		-- ONLY system that ever rotates the character while swimming --
		-- Shift Lock, first person, and classic camera all leave rotation
		-- alone now, so this runs unconditionally instead of trying to
		-- guess which camera mode is active.
		local movingBackward = isAnyKeyHeld(BACK_KEYS)

		if fullVelocity.Magnitude > 0.01 then
			-- Backward keeps facing the camera direction (a moonwalk-style
			-- backstroke) instead of spinning around to face the way it's
			-- actually traveling; forward faces the actual horizontal move
			-- direction (yaw only -- pitch is handled separately below).
			-- Falls back to the camera's facing when there's no horizontal
			-- input at all (e.g. holding only Space/Ctrl, or looking
			-- straight up/down), so vertical-only movement still has a
			-- sensible yaw instead of freezing the last one.
			local yawSourceDirection = movingBackward and flatLook or flattenAndNormalize(moveDirection3D)
			if yawSourceDirection.Magnitude < 0.01 then
				yawSourceDirection = flatLook
			end

			if yawSourceDirection.Magnitude > 0.01 then
				local pitch
				if movingBackward then
					-- Unchanged: a small fixed recline, nudged further by
					-- the real combined vertical speed, capped well under
					-- 90 degrees.
					local verticalFraction = fullVelocity.Y / MovementConfig.VerticalSwimSpeed
					pitch = BACKWARD_BASE_PITCH + verticalFraction * VERTICAL_PITCH_RANGE
					pitch = math.clamp(pitch, -MAX_SWIM_PITCH, MAX_SWIM_PITCH)
				else
					-- Forward: solve for the pitch that puts the body's Up
					-- axis (head-to-feet) exactly along the real velocity
					-- direction, instead of a fixed dip. elevationAngle is
					-- the actual angle of travel above/below horizontal (0
					-- = level, +90 = straight up, -90 = straight down);
					-- subtracting 90 degrees is the exact pitch that aligns
					-- Up with that direction. Level swimming (elevation 0)
					-- lands on pitch = -90, a fully horizontal torpedo body
					-- with the head leading -- not a small tilt -- and
					-- looking/swimming up or down (camera pitch and/or
					-- Space/Ctrl) smoothly reduces or extends that as the
					-- real velocity angle changes. No clamp needed: the
					-- formula is bounded to [-180, 0] by construction.
					local horizontalSpeed = Vector3.new(fullVelocity.X, 0, fullVelocity.Z).Magnitude
					local elevationAngle = math.atan2(fullVelocity.Y, horizontalSpeed)
					pitch = elevationAngle - math.pi / 2
				end

				local yawCFrame = CFrame.new(rootPart.Position, rootPart.Position + yawSourceDirection)
				local targetCFrame = yawCFrame * CFrame.Angles(pitch, 0, 0)
				local turnAlpha = 1 - math.exp(-TURN_RESPONSIVENESS * deltaTime)
				rootPart.CFrame = rootPart.CFrame:Lerp(targetCFrame, turnAlpha)
			end
		else
			-- Idle: nothing above touches rotation once movement stops, so
			-- without this the character stayed frozen in whatever tilt it
			-- last had -- including flat on its side after swimming level,
			-- since level swimming's pitch is a full -90 degrees. Smoothly
			-- levels back out to a vertical, natural diver rest pose while
			-- keeping the same horizontal facing. The Right vector is used
			-- (rather than Look) because it stays horizontal no matter the
			-- current pitch -- Look degenerates toward straight up/down
			-- exactly when the body is lying flat, which is the case this
			-- needs to recover from.
			local restRight = flattenAndNormalize(rootPart.CFrame.RightVector)
			if restRight.Magnitude > 0.01 then
				local restCFrame = CFrame.fromMatrix(rootPart.Position, restRight, Vector3.new(0, 1, 0))
				local turnAlpha = 1 - math.exp(-TURN_RESPONSIVENESS * deltaTime)
				rootPart.CFrame = rootPart.CFrame:Lerp(restCFrame, turnAlpha)
			end
		end

		local targetState
		if movingBackward then
			targetState = "Backward"
		elseif fullVelocity.Magnitude > 0.01 then
			targetState = "Forward"
		else
			targetState = "Idle"
		end
		playSwimState(targetState)
	end)
end

if player.Character then
	onCharacterAdded(player.Character)
end
player.CharacterAdded:Connect(onCharacterAdded)
