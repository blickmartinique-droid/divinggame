-- The Centre de plongée's till and the gear each diver wears.
--   * On joining: PlayerData is loaded; banked Pièces go back into
--     leaderstats, bought gear and what was equipped are restored.
--   * Stats follow the equipped gear: MaxOxygen (tank), OxygenDrainPerSecond
--     (suit), the SwimSpeedMultiplier attribute (fins, read by
--     SwimController); the lamp is a real light on the diver's head
--     (EquipmentVisuals, which also dresses the character).
--   * ReplicatedStorage.EquipmentRequest (RemoteFunction): the shop UI asks
--     ("Buy" | "Equip", itemId); everything is validated here -- the item
--     exists, is not owned yet, the diver has the Pièces -- and the answer is
--     { ok, message }.
--   * The player's owned/equipped gear is mirrored in attributes
--     (OwnedEquipment "id,id,...", Equipped_<Category>) for the UI.
-- Saved on change (PlayerData autosave), on leaving and on shutdown.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EquipmentConfig = require(ReplicatedStorage.Shared.Config.EquipmentConfig)
local OxygenConfig = require(ReplicatedStorage.Shared.Config.OxygenConfig)
local PlayerData = require(script.Parent.PlayerData)
local PlayerInventory = require(script.Parent.PlayerInventory)
local EquipmentVisuals = require(script.Parent.EquipmentVisuals)

local AUTOSAVE = 90
local REQUEST_COOLDOWN = 0.25

local itemsById = {}
for _, item in ipairs(EquipmentConfig.Items) do
	itemsById[item.Id] = item
end

local request = ReplicatedStorage:FindFirstChild("EquipmentRequest")
if not request then
	request = Instance.new("RemoteFunction")
	request.Name = "EquipmentRequest"
	request.Parent = ReplicatedStorage
end

local lastRequest: { [Player]: number } = {}

local function equippedItems(data)
	local items = {}
	for category, id in pairs(data.Equipped) do
		items[category] = itemsById[id]
	end
	return items
end

local function coinsValue(player: Player): IntValue?
	PlayerInventory.Setup(player)
	local leaderstats = player:FindFirstChild("leaderstats")
	return leaderstats and leaderstats:FindFirstChild(PlayerInventory.CoinsStatName) :: IntValue?
end

-- Pushes the equipped gear's effects onto the player.
local function applyStats(player: Player)
	local data = PlayerData.Get(player)
	if not data then
		return
	end
	local items = equippedItems(data)
	local maxOxygen = player:FindFirstChild("MaxOxygen")
	local drain = player:FindFirstChild("OxygenDrainPerSecond")
	local oxygen = player:FindFirstChild("Oxygen")
	local depth = player:FindFirstChild("Depth")
	if maxOxygen and items.Tank then
		maxOxygen.Value = items.Tank.MaxOxygen
		if oxygen then
			-- Topped up at the surface (a new tank is a full one), never
			-- above the new capacity.
			if not depth or depth.Value <= 0 then
				oxygen.Value = maxOxygen.Value
			else
				oxygen.Value = math.min(oxygen.Value, maxOxygen.Value)
			end
		end
	end
	if drain and items.Suit then
		drain.Value = OxygenConfig.DrainPerSecond * items.Suit.DrainMultiplier
	end
	player:SetAttribute("SwimSpeedMultiplier", items.Fins and items.Fins.SpeedMultiplier or 1)
	player:SetAttribute("LampRange", items.Lamp and items.Lamp.LampRange or 0)
	for category, id in pairs(data.Equipped) do
		player:SetAttribute("Equipped_" .. category, id)
	end
	local owned = {}
	for id in pairs(data.Owned) do
		table.insert(owned, id)
	end
	table.sort(owned)
	player:SetAttribute("OwnedEquipment", table.concat(owned, ","))

	local character = player.Character
	if character then
		EquipmentVisuals.Apply(character, items)
	end
end

local function onCharacterAdded(player: Player, character: Model)
	character:WaitForChild("Head", 10)
	local data = PlayerData.Get(player)
	if data then
		EquipmentVisuals.Apply(character, equippedItems(data))
	end
end

local function onPlayerAdded(player: Player)
	local data = PlayerData.Load(player)
	local coins = coinsValue(player)
	if coins then
		coins.Value = data.Coins
		coins.Changed:Connect(function(value)
			data.Coins = value
			PlayerData.MarkDirty(player)
		end)
	end
	-- OxygenManager creates these on the same PlayerAdded; wait for them.
	player:WaitForChild("MaxOxygen", 10)
	player:WaitForChild("OxygenDrainPerSecond", 10)
	applyStats(player)
	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
	if player.Character then
		onCharacterAdded(player, player.Character)
	end
end

local function handle(player: Player, action: string, itemId: string)
	local now = os.clock()
	if lastRequest[player] and now - lastRequest[player] < REQUEST_COOLDOWN then
		return { ok = false, message = "Doucement !" }
	end
	lastRequest[player] = now
	local data = PlayerData.Get(player)
	local item = type(itemId) == "string" and itemsById[itemId] or nil
	if not data or not item then
		return { ok = false, message = "Article inconnu" }
	end
	if action == "Buy" then
		if data.Owned[item.Id] then
			return { ok = false, message = "Déjà acheté" }
		end
		local coins = coinsValue(player)
		if not coins or coins.Value < item.Price then
			return { ok = false, message = string.format("Il manque %d pièces", item.Price - (coins and coins.Value or 0)) }
		end
		coins.Value -= item.Price
		data.Owned[item.Id] = true
		data.Equipped[item.Category] = item.Id
		PlayerData.MarkDirty(player)
		applyStats(player)
		task.spawn(PlayerData.Save, player)
		return { ok = true, message = item.Name .. " achetée et équipée" }
	elseif action == "Equip" then
		if not data.Owned[item.Id] then
			return { ok = false, message = "Pas encore acheté" }
		end
		data.Equipped[item.Category] = item.Id
		PlayerData.MarkDirty(player)
		applyStats(player)
		return { ok = true, message = item.Name .. " équipée" }
	end
	return { ok = false, message = "Action inconnue" }
end

request.OnServerInvoke = handle

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, player)
end
Players.PlayerRemoving:Connect(function(player)
	lastRequest[player] = nil
	PlayerData.Release(player)
end)
game:BindToClose(function()
	for _, player in ipairs(Players:GetPlayers()) do
		PlayerData.Save(player)
	end
end)

task.spawn(function()
	while true do
		task.wait(AUTOSAVE)
		PlayerData.SaveDirty()
	end
end)
