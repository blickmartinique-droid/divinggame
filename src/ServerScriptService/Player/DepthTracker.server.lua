-- Tracks each player's current depth server-side (authoritative, since later
-- systems like oxygen drain and max-depth records must not trust the client).
-- Exposes it as a NumberValue under the Player instance so it replicates to
-- the client automatically and can be inspected live in the Explorer.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DepthUtils = require(ReplicatedStorage.Shared.Modules.DepthUtils)

local UPDATE_INTERVAL = 0.25

local function onPlayerAdded(player: Player)
	local depthValue = Instance.new("NumberValue")
	depthValue.Name = "Depth"
	depthValue.Value = 0
	depthValue.Parent = player
end

local function updateDepths()
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local depthValue = player:FindFirstChild("Depth")
		if character and depthValue then
			local rootPart = character:FindFirstChild("HumanoidRootPart")
			if rootPart then
				depthValue.Value = math.floor(DepthUtils.GetDepth(rootPart.Position))
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
		accumulated = 0
		updateDepths()
	end
end)
