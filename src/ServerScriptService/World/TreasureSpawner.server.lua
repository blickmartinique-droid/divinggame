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
local TreasureModels = require(ReplicatedStorage.Shared.Modules.TreasureModels)
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

local spawnInSlot -- forward declaration (a slot refills itself)

local function spawnTreasure(slot, position: Vector3)
	local zoneIndex = DepthUtils.GetZoneIndexForDepth(DepthUtils.GetDepth(position))
	local treasureType = pickWeightedTreasureType(zoneIndex)

	-- A detailed little model per type (TreasureModels), turned to a random
	-- heading; TreasureAnimator (client) spins/bobs anything with Animate.
	local model = TreasureModels.Build(treasureType)
	model:PivotTo(CFrame.new(position) * CFrame.Angles(0, rng:NextNumber() * math.pi * 2, 0))
	model:SetAttribute("TreasureId", treasureType.Id)
	model:SetAttribute("Value", treasureType.Value)
	model:SetAttribute("Rarity", treasureType.Rarity)
	model:SetAttribute("Animate", true)

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Ramasser"
	prompt.ObjectText = string.format("%s (%d)", treasureType.Name, treasureType.Value)
	prompt.HoldDuration = 0.5
	prompt.MaxActivationDistance = 9
	prompt.RequiresLineOfSight = false
	prompt.Parent = model.PrimaryPart

	prompt.Triggered:Connect(function(player)
		if not model.Parent then
			return
		end
		model.Parent = nil
		local data = { Id = treasureType.Id, Name = treasureType.Name, Value = treasureType.Value, Rarity = treasureType.Rarity }
		PlayerInventory.AddCarried(player, data)
		treasureCollected:Fire(player, data)
		model:Destroy()
		task.delay(rng:NextNumber(RESPAWN_MIN, RESPAWN_MAX), spawnInSlot, slot)
	end)

	model.Parent = treasureFolder
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
