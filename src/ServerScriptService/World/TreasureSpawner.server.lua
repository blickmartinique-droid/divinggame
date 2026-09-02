-- Scatters collectible treasures through the Récif zone (0-100m) around the
-- spawn island. Pickup is a server-side ProximityPrompt (Roblox's built-in
-- prompt UI, no custom interface needed) so it can't be triggered remotely
-- by a client. Inventory doesn't exist yet (a later step), so collection
-- just fires TreasureCollected for that system to hook into, and logs to
-- the server output for now.

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TreasureConfig = require(ReplicatedStorage.Shared.Config.TreasureConfig)

local treasureCollected = Instance.new("BindableEvent")
treasureCollected.Name = "TreasureCollected"
treasureCollected.Parent = script

local TREASURE_COUNT = 40
local MIN_RADIUS = 80 -- studs from the island center, stay clear of the island itself
local MAX_RADIUS = 400
local MIN_DEPTH = 5
local MAX_DEPTH = 95 -- stay within the Récif zone (0-100m) for V1

local RARITY_COLORS = {
	Commune = Color3.fromRGB(200, 200, 200),
	["Peu commune"] = Color3.fromRGB(90, 200, 120),
	Rare = Color3.fromRGB(80, 140, 230),
	["Très rare"] = Color3.fromRGB(180, 90, 220),
	Légendaire = Color3.fromRGB(240, 180, 40),
}

local function pickWeightedTreasureType()
	local totalWeight = 0
	for _, treasureType in ipairs(TreasureConfig.Types) do
		totalWeight += treasureType.Weight
	end

	local roll = math.random() * totalWeight
	local cumulative = 0
	for _, treasureType in ipairs(TreasureConfig.Types) do
		cumulative += treasureType.Weight
		if roll <= cumulative then
			return treasureType
		end
	end
	return TreasureConfig.Types[1]
end

local treasureFolder = Instance.new("Folder")
treasureFolder.Name = "Treasures"
treasureFolder.Parent = Workspace

local function spawnTreasure()
	local treasureType = pickWeightedTreasureType()

	local angle = math.random() * math.pi * 2
	local radius = MIN_RADIUS + math.random() * (MAX_RADIUS - MIN_RADIUS)
	local depth = MIN_DEPTH + math.random() * (MAX_DEPTH - MIN_DEPTH)

	local part = Instance.new("Part")
	part.Name = treasureType.Id
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(2, 2, 2)
	part.Anchored = true
	part.CanCollide = false
	part.Material = Enum.Material.Neon
	part.Color = RARITY_COLORS[treasureType.Rarity] or Color3.new(1, 1, 1)
	part.Position = Vector3.new(math.cos(angle) * radius, -depth, math.sin(angle) * radius)
	part:SetAttribute("TreasureId", treasureType.Id)
	part:SetAttribute("Value", treasureType.Value)
	part:SetAttribute("Rarity", treasureType.Rarity)

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Ramasser"
	prompt.ObjectText = treasureType.Name
	prompt.HoldDuration = 0.5
	prompt.MaxActivationDistance = 8
	prompt.Parent = part

	prompt.Triggered:Connect(function(player)
		if not part.Parent then
			return
		end
		part.Parent = nil
		treasureCollected:Fire(player, {
			Id = treasureType.Id,
			Name = treasureType.Name,
			Value = treasureType.Value,
			Rarity = treasureType.Rarity,
		})
		part:Destroy()
	end)

	part.Parent = treasureFolder
end

for _ = 1, TREASURE_COUNT do
	spawnTreasure()
end

treasureCollected.Event:Connect(function(player, treasureData)
	print(string.format("[Treasure] %s a ramassé %s (%s, %d)", player.Name, treasureData.Name, treasureData.Rarity, treasureData.Value))
end)
