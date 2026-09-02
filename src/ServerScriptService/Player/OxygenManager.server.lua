-- Tracks each player's oxygen server-side (authoritative). Drains while
-- underwater (Depth > 0, from DepthTracker), regenerates at the surface.
-- On reaching 0, the player is rescued to the surface with a partial
-- refill rather than dying outright. Fires PlayerOutOfOxygen so a later
-- system (inventory) can drop unsecured treasures on this event.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local OxygenConfig = require(ReplicatedStorage.Shared.Config.OxygenConfig)

local playerOutOfOxygen = Instance.new("BindableEvent")
playerOutOfOxygen.Name = "PlayerOutOfOxygen"
playerOutOfOxygen.Parent = script

local UPDATE_INTERVAL = 0.25

local function onPlayerAdded(player: Player)
	local oxygenValue = Instance.new("NumberValue")
	oxygenValue.Name = "Oxygen"
	oxygenValue.Value = OxygenConfig.MaxOxygen
	oxygenValue.Parent = player
end

local function emergencySurface(player: Player)
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		return
	end

	rootPart.CFrame = CFrame.new(rootPart.Position.X, 3, rootPart.Position.Z)
	rootPart.AssemblyLinearVelocity = Vector3.new()

	local oxygenValue = player:FindFirstChild("Oxygen")
	if oxygenValue then
		oxygenValue.Value = OxygenConfig.MaxOxygen * OxygenConfig.EmergencyRefillFraction
	end

	playerOutOfOxygen:Fire(player)
end

local function updateOxygen(deltaTime: number)
	for _, player in ipairs(Players:GetPlayers()) do
		local depthValue = player:FindFirstChild("Depth")
		local oxygenValue = player:FindFirstChild("Oxygen")
		if depthValue and oxygenValue then
			if depthValue.Value > 0 then
				oxygenValue.Value = math.max(0, oxygenValue.Value - OxygenConfig.DrainPerSecond * deltaTime)
				if oxygenValue.Value <= 0 then
					emergencySurface(player)
				end
			else
				oxygenValue.Value = math.min(OxygenConfig.MaxOxygen, oxygenValue.Value + OxygenConfig.RegenPerSecond * deltaTime)
			end
		end
	end
end

for _, player in ipairs(Players:GetPlayers()) do
	onPlayerAdded(player)
end
Players.PlayerAdded:Connect(onPlayerAdded)

local accumulated = 0
RunService.Heartbeat:Connect(function(deltaTime)
	accumulated += deltaTime
	if accumulated >= UPDATE_INTERVAL then
		updateOxygen(accumulated)
		accumulated = 0
	end
end)
