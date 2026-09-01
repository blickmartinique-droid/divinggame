-- Free-swim movement controller. Roblox's default Humanoid movement actively
-- snaps the character to the ground and cancels any vertical velocity we try
-- to set while grounded, so instead of fighting that, PlatformStand fully
-- disables the built-in controller and this script drives 100% of the
-- character's motion: horizontal (camera-relative WASD/ZQSD), vertical
-- (Space/LeftControl/C), facing direction, and swim animations.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local MovementConfig = require(ReplicatedStorage.Shared.Config.MovementConfig)

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

-- Reuses the swim animations Roblox already ships on every default avatar
-- (normally auto-played by the built-in Animate script when touching Terrain
-- water). PlatformStand disables that script's control, so it's disabled
-- here and its animations are played manually instead.
local function loadSwimAnimations(character, humanoid)
	local animateScript = character:FindFirstChild("Animate")
	if not animateScript then
		return nil
	end
	animateScript.Disabled = true

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

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

	local tracks = {}
	if moveAnim then
		tracks.move = animator:LoadAnimation(moveAnim)
		tracks.move.Looped = true
	end
	if idleAnim then
		tracks.idle = animator:LoadAnimation(idleAnim)
		tracks.idle.Looped = true
	end
	return tracks
end

local function onCharacterAdded(character)
	local humanoid = character:WaitForChild("Humanoid")
	local rootPart = character:WaitForChild("HumanoidRootPart")

	humanoid.PlatformStand = true

	local animationTracks = loadSwimAnimations(character, humanoid)
	local isMoving = false

	local heartbeatConnection
	heartbeatConnection = RunService.Heartbeat:Connect(function(deltaTime)
		if humanoid.Health <= 0 or not character.Parent then
			heartbeatConnection:Disconnect()
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

		local nowMoving = moveDirection.Magnitude > 0 or verticalSpeed ~= 0
		if animationTracks and nowMoving ~= isMoving then
			isMoving = nowMoving
			if isMoving then
				if animationTracks.idle then
					animationTracks.idle:Stop(ANIMATION_FADE_TIME)
				end
				if animationTracks.move then
					animationTracks.move:Play(ANIMATION_FADE_TIME)
				end
			else
				if animationTracks.move then
					animationTracks.move:Stop(ANIMATION_FADE_TIME)
				end
				if animationTracks.idle then
					animationTracks.idle:Play(ANIMATION_FADE_TIME)
				end
			end
		end
	end)
end

if player.Character then
	onCharacterAdded(player.Character)
end
player.CharacterAdded:Connect(onCharacterAdded)
