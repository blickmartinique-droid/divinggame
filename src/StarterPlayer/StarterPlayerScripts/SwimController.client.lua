-- Free-swim movement controller. Roblox's default Humanoid movement actively
-- snaps the character to the ground and cancels any vertical velocity we try
-- to set while grounded, so instead of fighting that, PlatformStand fully
-- disables the built-in controller and this script drives 100% of the
-- character's motion: horizontal (camera-relative WASD/ZQSD), vertical
-- (Space/LeftControl/C), and facing direction.

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

local function onCharacterAdded(character)
	local humanoid = character:WaitForChild("Humanoid")
	local rootPart = character:WaitForChild("HumanoidRootPart")

	humanoid.PlatformStand = true

	local heartbeatConnection
	heartbeatConnection = RunService.Heartbeat:Connect(function()
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
		rootPart.AssemblyLinearVelocity = Vector3.new(horizontalVelocity.X, verticalSpeed, horizontalVelocity.Z)

		if moveDirection.Magnitude > 0 then
			rootPart.CFrame = CFrame.new(rootPart.Position, rootPart.Position + moveDirection)
		end
	end)
end

if player.Character then
	onCharacterAdded(player.Character)
end
player.CharacterAdded:Connect(onCharacterAdded)
