-- Gives the character free-swim movement: WASD moves horizontally (camera-relative,
-- handled by Roblox's default controls), Space ascends, LeftControl/C descends.
-- The character neither falls nor needs to jump: vertical velocity is fully driven
-- by player input, which reads as neutral buoyancy for a diving game.
-- Humanoid is forced into the Swimming state every frame: while grounded, Roblox's
-- built-in ground-follow logic otherwise overrides/cancels any vertical velocity we set.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MovementConfig = require(ReplicatedStorage.Shared.Config.MovementConfig)

local player = Players.LocalPlayer

local ASCEND_KEYS = {
	[Enum.KeyCode.Space] = true,
}
local DESCEND_KEYS = {
	[Enum.KeyCode.LeftControl] = true,
	[Enum.KeyCode.C] = true,
}

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

local function onCharacterAdded(character)
	local humanoid = character:WaitForChild("Humanoid")
	local rootPart = character:WaitForChild("HumanoidRootPart")

	humanoid.WalkSpeed = MovementConfig.BaseSwimSpeed
	humanoid.JumpPower = 0
	humanoid.JumpHeight = 0
	humanoid.AutoJumpEnabled = false

	local heartbeatConnection
	heartbeatConnection = RunService.Heartbeat:Connect(function()
		if humanoid.Health <= 0 or not character.Parent then
			heartbeatConnection:Disconnect()
			return
		end

		if humanoid:GetState() ~= Enum.HumanoidStateType.Swimming then
			humanoid:ChangeState(Enum.HumanoidStateType.Swimming)
		end

		local verticalSpeed = 0
		if isAnyKeyHeld(ASCEND_KEYS) then
			verticalSpeed += MovementConfig.VerticalSwimSpeed
		end
		if isAnyKeyHeld(DESCEND_KEYS) then
			verticalSpeed -= MovementConfig.VerticalSwimSpeed
		end

		local currentVelocity = rootPart.AssemblyLinearVelocity
		rootPart.AssemblyLinearVelocity = Vector3.new(currentVelocity.X, verticalSpeed, currentVelocity.Z)
	end)
end

if player.Character then
	onCharacterAdded(player.Character)
end
player.CharacterAdded:Connect(onCharacterAdded)
