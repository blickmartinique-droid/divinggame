-- Scatters collectible treasures through all 4 depth zones. Deeper zones
-- unlock rarer treasure types (TreasureConfig.MinZoneIndex), so loot value
-- tracks how deep the player had to go. Pickup is a server-side
-- ProximityPrompt (can't be triggered remotely by a client); the treasure
-- goes into the diver's bag (PlayerInventory), sold on surfacing.
--
-- Placement is a set of "slots", each refilled RESPAWN_TIME after its
-- treasure is taken, so the ocean never runs dry over a long session:
--   * one slot per RegionCount of every SpawnRegion with RegionKind =
--     "Treasure" (the wreck's rooms, the cave chambers, the reef's clam
--     beds, anything tagged by hand in Studio);
--   * open-water slots topping each depth zone up to TREASURES_PER_ZONE
--     when its regions hold fewer than that -- so a zone with no real
--     geometry yet still has loot, and one full of rooms isn't doubled.
-- Waits for WorldBootstrap first, so every generated region is known
-- before the open-water top-up is decided.

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local TreasureConfig = require(ReplicatedStorage.Shared.Config.TreasureConfig)
local ZonesConfig = require(ReplicatedStorage.Shared.Config.ZonesConfig)
local DepthUtils = require(ReplicatedStorage.Shared.Modules.DepthUtils)
local SpawnRegions = require(ReplicatedStorage.Shared.Modules.SpawnRegions)
local WorldLayout = require(script.Parent.Builders.WorldLayout)
local PlayerInventory = require(ServerScriptService.Player.PlayerInventory)

local treasureCollected = Instance.new("BindableEvent")
treasureCollected.Name = "TreasureCollected"
treasureCollected.Parent = script

local TREASURES_PER_ZONE = 15
local TREASURES_PER_REGION = 8
local RESPAWN_MIN, RESPAWN_MAX = 90, 150
-- Open water only: clear of the beach (its terrain reaches 180 studs out)
-- and inside the part of the ocean the other systems use.
local MIN_RADIUS = 200
local MAX_RADIUS = 880
local PLACEMENT_ATTEMPTS = 40

local RARITY_COLORS = {
	Commune = Color3.fromRGB(200, 200, 200),
	["Peu commune"] = Color3.fromRGB(90, 200, 120),
	Rare = Color3.fromRGB(80, 140, 230),
	["Très rare"] = Color3.fromRGB(180, 90, 220),
	["Légendaire"] = Color3.fromRGB(240, 180, 40),
}

local rng = Random.new()

local function pickWeightedTreasureType(zoneIndex: number)
	local candidates = {}
	local totalWeight = 0
	for _, treasureType in ipairs(TreasureConfig.Types) do
		if treasureType.MinZoneIndex <= zoneIndex then
			table.insert(candidates, treasureType)
			totalWeight += treasureType.Weight
		end
	end
	local roll = rng:NextNumber() * totalWeight
	local cumulative = 0
	for _, treasureType in ipairs(candidates) do
		cumulative += treasureType.Weight
		if roll <= cumulative then
			return treasureType
		end
	end
	return candidates[#candidates]
end

local existingFolder = Workspace:FindFirstChild("Treasures")
if existingFolder then
	existingFolder:Destroy()
end
local treasureFolder = Instance.new("Folder")
treasureFolder.Name = "Treasures"
treasureFolder.Parent = Workspace

-- Distinct shape/material per treasure type, so they read as objects.
-- TreasureAnimator (client) spins/bobs anything with the Animate attribute.
local function buildTreasureModel(treasureType)
	local part = Instance.new("Part")
	part.Name = treasureType.Id
	part.Anchored = true
	part.CanCollide = false
	part.CastShadow = false

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
	end

	-- A faint glow so loot can be spotted in the dark zones, stronger for
	-- rarer finds.
	if treasureType.Id ~= "Coin" then
		local light = Instance.new("PointLight")
		light.Color = RARITY_COLORS[treasureType.Rarity]
		light.Range = treasureType.Id == "Relic" and 12 or 7
		light.Brightness = treasureType.Id == "Relic" and 2 or 0.8
		light.Parent = part
	end

	return part
end

local spawnInSlot -- forward declaration (a slot refills itself)

local function spawnTreasure(slot, position: Vector3)
	local zoneIndex = DepthUtils.GetZoneIndexForDepth(DepthUtils.GetDepth(position))
	local treasureType = pickWeightedTreasureType(zoneIndex)

	local part = buildTreasureModel(treasureType)
	part.Position = position
	part:SetAttribute("TreasureId", treasureType.Id)
	part:SetAttribute("Value", treasureType.Value)
	part:SetAttribute("Rarity", treasureType.Rarity)
	part:SetAttribute("Animate", true)

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Ramasser"
	prompt.ObjectText = string.format("%s (%d)", treasureType.Name, treasureType.Value)
	prompt.HoldDuration = 0.5
	prompt.MaxActivationDistance = 8
	prompt.RequiresLineOfSight = false
	prompt.Parent = part

	prompt.Triggered:Connect(function(player)
		if not part.Parent then
			return
		end
		part.Parent = nil
		local data = { Id = treasureType.Id, Name = treasureType.Name, Value = treasureType.Value, Rarity = treasureType.Rarity }
		PlayerInventory.AddCarried(player, data)
		treasureCollected:Fire(player, data)
		part:Destroy()
		task.delay(rng:NextNumber(RESPAWN_MIN, RESPAWN_MAX), spawnInSlot, slot)
	end)

	part.Parent = treasureFolder
end

-- Open water inside a zone's depth band, clear of everything the world
-- builders reserved (wreck, mountains, currents, beach).
local function openWaterPoint(zone): Vector3?
	local layout = WorldLayout.Current
	for _ = 1, PLACEMENT_ATTEMPTS do
		local angle = rng:NextNumber() * math.pi * 2
		local radius = rng:NextNumber(MIN_RADIUS, MAX_RADIUS)
		local depth = rng:NextNumber(zone.MinDepth + 5, zone.MaxDepth - 5)
		local point = Vector3.new(math.cos(angle) * radius, DepthUtils.SURFACE_Y - depth, math.sin(angle) * radius)
		if not layout or layout:IsFree(point, 6) then
			return point
		end
	end
	return nil
end

function spawnInSlot(slot)
	if slot.region then
		if slot.region.Parent and slot.region:GetAttribute("RegionEnabled") ~= false then
			spawnTreasure(slot, SpawnRegions.RandomPointIn(slot.region))
		end
		return
	end
	local point = openWaterPoint(slot.zone)
	if point then
		spawnTreasure(slot, point)
	end
end

local populated = {}

local function populateRegion(region: BasePart)
	if populated[region] or region:GetAttribute("RegionKind") ~= "Treasure" or region:GetAttribute("RegionEnabled") == false then
		return 0
	end
	populated[region] = true
	local count = region:GetAttribute("RegionCount") or TREASURES_PER_REGION
	for _ = 1, count do
		spawnInSlot({ region = region })
	end
	return count
end

SpawnRegions.WaitForWorld()

local perZone = {}
for _, region in ipairs(SpawnRegions.GetRegions("Treasure")) do
	local zoneIndex = DepthUtils.GetZoneIndexForDepth(DepthUtils.GetDepth(region.Position))
	perZone[zoneIndex] = (perZone[zoneIndex] or 0) + populateRegion(region)
end
SpawnRegions.OnRegionAdded(populateRegion)

local openWater = 0
for zoneIndex, zone in ipairs(ZonesConfig.Zones) do
	for _ = 1, math.max(0, TREASURES_PER_ZONE - (perZone[zoneIndex] or 0)) do
		spawnInSlot({ zone = zone })
		openWater += 1
	end
end

print(string.format("[Treasure] %d treasures (%d in open water)", #treasureFolder:GetChildren(), openWater))
