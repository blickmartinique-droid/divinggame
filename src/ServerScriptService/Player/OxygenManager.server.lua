-- Tracks each player's oxygen server-side (authoritative). Drains while
-- underwater (Depth > 0, from DepthTracker), regenerates at the surface.
-- On reaching 0, the player drowns (Humanoid.Health = 0), triggering the
-- Died event the DeathScreen listens for. Fires PlayerOutOfOxygen first so
-- a later system (inventory) can drop unsecured treasures on this event.

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

local function drown(player: Player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end

	playerOutOfOxygen:Fire(player)
	humanoid.Health = 0
end

local function updateOxygen(deltaTime: number)
	for _, player in ipairs(Players:GetPlayers()) do
		local depthValue = player:FindFirstChild("Depth")
		local oxygenValue = player:FindFirstChild("Oxygen")
		if depthValue and oxygenValue then
			if depthValue.Value > 0 then
				oxygenValue.Value = math.max(0, oxygenValue.Value - OxygenConfig.DrainPerSecond * deltaTime)
				if oxygenValue.Value <= 0 then
					drown(player)
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
