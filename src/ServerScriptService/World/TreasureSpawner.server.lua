-- Scatters collectible treasures through all 4 depth zones. Deeper zones
-- unlock rarer treasure types (TreasureConfig.MinZoneIndex), so loot value
-- roughly tracks how deep the player had to go to find it. Pickup is a
-- server-side ProximityPrompt (Roblox's built-in prompt UI, no custom
-- interface needed) so it can't be triggered remotely by a client.
-- Inventory doesn't exist yet (a later step), so collection just fires
-- TreasureCollected for that system to hook into, and logs to the server
-- output for now.

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TreasureConfig = require(ReplicatedStorage.Shared.Config.TreasureConfig)
local ZonesConfig = require(ReplicatedStorage.Shared.Config.ZonesConfig)

local treasureCollected = Instance.new("BindableEvent")
treasureCollected.Name = "TreasureCollected"
treasureCollected.Parent = script

local TREASURES_PER_ZONE = 15
local MIN_RADIUS = 60 -- studs from the world center, stay clear of the island
local MAX_RADIUS = 420

local RARITY_COLORS = {
	Commune = Color3.fromRGB(200, 200, 200),
	["Peu commune"] = Color3.fromRGB(90, 200, 120),
	Rare = Color3.fromRGB(80, 140, 230),
	["Très rare"] = Color3.fromRGB(180, 90, 220),
	["Légendaire"] = Color3.fromRGB(240, 180, 40),
}

local function pickWeightedTreasureType(zoneIndex)
	local candidates = {}
	local totalWeight = 0
	for _, treasureType in ipairs(TreasureConfig.Types) do
		if treasureType.MinZoneIndex <= zoneIndex then
			table.insert(candidates, treasureType)
			totalWeight += treasureType.Weight
		end
	end

	local roll = math.random() * totalWeight
	local cumulative = 0
	for _, treasureType in ipairs(candidates) do
		cumulative += treasureType.Weight
		if roll <= cumulative then
			return treasureType
		end
	end
	return candidates[#candidates]
end

local treasureFolder = Instance.new("Folder")
treasureFolder.Name = "Treasures"
treasureFolder.Parent = Workspace

-- Distinct shape/material per treasure type instead of a uniform ball, so
-- they read as actual objects. TreasureAnimator (client) spins/bobs any
-- part tagged with the Animate attribute set here.
local function buildTreasureModel(treasureType)
	local part = Instance.new("Part")
	part.Name = treasureType.Id
	part.Anchored = true
	part.CanCollide = false

	if treasureType.Id == "Coin" then
		part.Shape = Enum.PartType.Cylinder
		part.Size = Vector3.new(0.3, 1.4, 1.4)
		part.Material = Enum.Material.Metal
		part.Color = Color3.fromRGB(230, 190, 60)
	elseif treasureType.Id == "Jewel" then
		part.Shape = Enum.PartType.Ball
		part.Size = Vector3.new(1.4, 1.4, 1.4)
		part.Material = Enum.Material.Glass
		part.Color = RARITY_COLORS[treasureType.Rarity]
	elseif treasureType.Id == "Chest" then
		part.Size = Vector3.new(2.2, 1.6, 1.6)
		part.Material = Enum.Material.WoodPlanks
		part.Color = Color3.fromRGB(110, 75, 45)
	elseif treasureType.Id == "Artifact" then
		part.Size = Vector3.new(1.6, 1.8, 1.4)
		part.Material = Enum.Material.Slate
		part.Color = Color3.fromRGB(140, 135, 120)
	else -- Relic
		part.Shape = Enum.PartType.Ball
		part.Size = Vector3.new(1.8, 1.8, 1.8)
		part.Material = Enum.Material.Neon
		part.Color = RARITY_COLORS[treasureType.Rarity]

		local light = Instance.new("PointLight")
		light.Color = RARITY_COLORS[treasureType.Rarity]
		light.Range = 12
		light.Brightness = 2
		light.Parent = part
	end

	return part
end

local function spawnTreasure(zoneIndex, minDepth, maxDepth)
	local treasureType = pickWeightedTreasureType(zoneIndex)

	local angle = math.random() * math.pi * 2
	local radius = MIN_RADIUS + math.random() * (MAX_RADIUS - MIN_RADIUS)
	local depth = minDepth + math.random() * (maxDepth - minDepth)

	local part = buildTreasureModel(treasureType)
	part.Position = Vector3.new(math.cos(angle) * radius, -depth, math.sin(angle) * radius)
	part:SetAttribute("TreasureId", treasureType.Id)
	part:SetAttribute("Value", treasureType.Value)
	part:SetAttribute("Rarity", treasureType.Rarity)
	part:SetAttribute("Animate", true)

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

for zoneIndex, zone in ipairs(ZonesConfig.Zones) do
	for _ = 1, TREASURES_PER_ZONE do
		spawnTreasure(zoneIndex, zone.MinDepth + 5, zone.MaxDepth - 5)
	end
end

treasureCollected.Event:Connect(function(player, treasureData)
	print(string.format("[Treasure] %s a ramassé %s (%s, %d)", player.Name, treasureData.Name, treasureData.Rarity, treasureData.Value))
end)
