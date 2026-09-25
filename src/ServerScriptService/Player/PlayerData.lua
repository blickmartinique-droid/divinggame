-- What a player keeps between sessions: banked Pièces, the gear they
-- bought and what they wear. Saved in a DataStore (one key per UserId) on
-- leaving, every AUTOSAVE seconds when something changed, and on server
-- shutdown. Without DataStore access (Studio with API access off, or the
-- service failing) everything still works for the session and a single
-- warning says the progress will not be kept.

local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EquipmentConfig = require(ReplicatedStorage.Shared.Config.EquipmentConfig)
local PlayerInventory = require(script.Parent.PlayerInventory)

local PlayerData = {}

local STORE_NAME = "BlickDiving_v1"
local RETRIES = 3

local store = nil
local storeAvailable = true
local warned = false
local cache: { [Player]: any } = {}
local dirty: { [Player]: boolean } = {}

local function warnOnce(message: string)
	if not warned then
		warned = true
		warn("[PlayerData] " .. message .. " -- la progression ne sera pas sauvegardée cette session.")
	end
end

local function getStore()
	if store or not storeAvailable then
		return store
	end
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	if ok and result then
		store = result
	else
		storeAvailable = false
		warnOnce("DataStore indisponible (" .. tostring(result) .. ")")
	end
	return store
end

function PlayerData.Default()
	local owned = {}
	for _, id in pairs(EquipmentConfig.Defaults) do
		owned[id] = true
	end
	local equipped = {}
	for category, id in pairs(EquipmentConfig.Defaults) do
		equipped[category] = id
	end
	return { Version = 1, Coins = 0, Owned = owned, Equipped = equipped }
end

-- Keeps only known items, and always the free defaults.
local function sanitize(data)
	local clean = PlayerData.Default()
	if type(data) ~= "table" then
		return clean
	end
	clean.Coins = math.max(0, math.floor(tonumber(data.Coins) or 0))
	local known = {}
	for _, item in ipairs(EquipmentConfig.Items) do
		known[item.Id] = item
	end
	if type(data.Owned) == "table" then
		for id, owned in pairs(data.Owned) do
			if owned and known[id] then
				clean.Owned[id] = true
			end
		end
	end
	if type(data.Equipped) == "table" then
		for category, id in pairs(data.Equipped) do
			local item = known[id]
			if item and item.Category == category and clean.Owned[id] then
				clean.Equipped[category] = id
			end
		end
	end
	return clean
end

local function key(player: Player): string
	return "player_" .. tostring(player.UserId)
end

function PlayerData.Load(player: Player)
	if cache[player] then
		return cache[player]
	end
	local data = nil
	local s = getStore()
	if s then
		for attempt = 1, RETRIES do
			local ok, result = pcall(function()
				return s:GetAsync(key(player))
			end)
			if ok then
				data = result
				break
			elseif attempt == RETRIES then
				warnOnce("lecture impossible (" .. tostring(result) .. ")")
			else
				task.wait(1)
			end
		end
	end
	cache[player] = sanitize(data)
	return cache[player]
end

-- The banked Pièces live in leaderstats while playing; the saved copy
-- follows them.
local function syncCoins(player: Player, data)
	local leaderstats = player:FindFirstChild("leaderstats")
	local coins = leaderstats and leaderstats:FindFirstChild(PlayerInventory.CoinsStatName)
	if coins and coins.Value ~= data.Coins then
		data.Coins = coins.Value
		dirty[player] = true
	end
end

function PlayerData.Get(player: Player)
	local data = cache[player]
	if data then
		syncCoins(player, data)
	end
	return data
end

function PlayerData.MarkDirty(player: Player)
	if cache[player] then
		dirty[player] = true
	end
end

function PlayerData.Save(player: Player): boolean
	local data = cache[player]
	local s = getStore()
	if not data or not s then
		return false
	end
	syncCoins(player, data)
	for attempt = 1, RETRIES do
		local ok, result = pcall(function()
			s:SetAsync(key(player), data)
		end)
		if ok then
			dirty[player] = nil
			return true
		elseif attempt == RETRIES then
			warnOnce("écriture impossible (" .. tostring(result) .. ")")
		else
			task.wait(1)
		end
	end
	return false
end

function PlayerData.SaveDirty()
	for player, data in pairs(cache) do
		syncCoins(player, data)
	end
	for player in pairs(dirty) do
		PlayerData.Save(player)
	end
end

function PlayerData.Release(player: Player)
	PlayerData.Save(player)
	cache[player] = nil
	dirty[player] = nil
end

return PlayerData
