-- Free-swim movement controller, active only while underwater (depth > 0).
-- On land / in the air, the default Roblox Humanoid movement (walking,
-- gravity, jumping) is left alone. Underwater, Roblox's built-in ground-
-- follow logic would otherwise cancel any vertical velocity we set, so
-- PlatformStand fully disables the built-in controller and this script
-- drives 100% of the character's motion: horizontal (camera-relative
-- WASD/ZQSD), vertical (Space/LeftControl/C), facing direction, and swim
-- animations.

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

	local leftHand = character:FindFirstChild("LeftHand")
	local rightHand = character:FindFirstChild("RightHand")
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

local function onCharacterAdded(character)
	local humanoid = character:WaitForChild("Humanoid")
	local rootPart = character:WaitForChild("HumanoidRootPart")
	local animateScript = character:WaitForChild("Animate")

	humanoid.WalkSpeed = MovementConfig.BaseSwimSpeed

	local animationTracks = loadSwimAnimations(character, humanoid)
	local swimEffects = setupSwimEffects(character)
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
		if swimEffects.splash then
			swimEffects.splash:Emit(20)
		end
	end

	local function exitSwimMode()
		isSwimming = false
		humanoid.PlatformStand = false
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

		local shouldSwim = DepthUtils.GetDepth(rootPart.Position) > 0
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

		local moveDirection = Vector3.new()
		if isAnyKeyHeld(FORWARD_KEYS) then
			moveDirection += flatLook
		end
		if isAnyKeyHeld(BACK_KEYS) then
			moveDirection -= flatLook
		end
		if isAnyKeyHeld(RIGHT_KEYS) then
			moveDirection += flatRight
		end
		if isAnyKeyHeld(LEFT_KEYS) then
			moveDirection -= flatRight
		end
		if moveDirection.Magnitude > 0 then
			moveDirection = moveDirection.Unit
		end

		local verticalSpeed = 0
		if isAnyKeyHeld(ASCEND_KEYS) then
			verticalSpeed += MovementConfig.VerticalSwimSpeed
		end
		if isAnyKeyHeld(DESCEND_KEYS) then
			verticalSpeed -= MovementConfig.VerticalSwimSpeed
		end

		local horizontalVelocity = moveDirection * MovementConfig.BaseSwimSpeed
		local fullVelocity = Vector3.new(horizontalVelocity.X, verticalSpeed, horizontalVelocity.Z)
		rootPart.AssemblyLinearVelocity = fullVelocity

		if fullVelocity.Magnitude > 0.01 then
			local targetCFrame = CFrame.new(rootPart.Position, rootPart.Position + fullVelocity.Unit)
			local turnAlpha = 1 - math.exp(-TURN_RESPONSIVENESS * deltaTime)
			rootPart.CFrame = rootPart.CFrame:Lerp(targetCFrame, turnAlpha)
		end

		local movingBackward = isAnyKeyHeld(BACK_KEYS)
		local isMoving = moveDirection.Magnitude > 0 or verticalSpeed ~= 0

		local targetState
		if movingBackward then
			targetState = "Backward"
		elseif isMoving then
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
