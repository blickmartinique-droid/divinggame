-- The dive's risk/reward loop, server-authoritative:
--   * picking up a treasure adds it to the diver's bag (CarriedValue /
--     CarriedCount under the Player) -- it is not money yet;
--   * surfacing (Depth back to 0) sells the whole bag into
--     leaderstats.Pièces, the banked total shown on the player list;
--   * dying (drowning, a shark) loses whatever was still in the bag.
-- Every change is also sent to the owning client through the
-- ReplicatedStorage.LootEvent RemoteEvent ("Collected" / "Banked" /
-- "Lost") so the HUD can show a toast; the values themselves replicate
-- on their own. Equipment and a real shop can later read/write the same
-- values without touching this flow.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerInventory = {}

PlayerInventory.CoinsStatName = "Pièces"

local lootEvent = ReplicatedStorage:FindFirstChild("LootEvent")
if not lootEvent then
	lootEvent = Instance.new("RemoteEvent")
	lootEvent.Name = "LootEvent"
	lootEvent.Parent = ReplicatedStorage
end
PlayerInventory.LootEvent = lootEvent

local function intValue(parent: Instance, name: string): IntValue
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("IntValue") then
		return existing
	end
	local value = Instance.new("IntValue")
	value.Name = name
	value.Value = 0
	value.Parent = parent
	return value
end

function PlayerInventory.Setup(player: Player)
	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then
		leaderstats = Instance.new("Folder")
		leaderstats.Name = "leaderstats"
		leaderstats.Parent = player
	end
	intValue(leaderstats, PlayerInventory.CoinsStatName)
	intValue(player, "CarriedValue")
	intValue(player, "CarriedCount")
end

function PlayerInventory.GetCarried(player: Player): (number, number)
	local value = player:FindFirstChild("CarriedValue")
	local count = player:FindFirstChild("CarriedCount")
	return value and value.Value or 0, count and count.Value or 0
end

function PlayerInventory.GetCoins(player: Player): number
	local leaderstats = player:FindFirstChild("leaderstats")
	local coins = leaderstats and leaderstats:FindFirstChild(PlayerInventory.CoinsStatName)
	return coins and coins.Value or 0
end

local function values(player: Player): (IntValue, IntValue, IntValue)
	PlayerInventory.Setup(player)
	local leaderstats = player:FindFirstChild("leaderstats") :: Folder
	return player:FindFirstChild("CarriedValue") :: IntValue,
		player:FindFirstChild("CarriedCount") :: IntValue,
		leaderstats:FindFirstChild(PlayerInventory.CoinsStatName) :: IntValue
end

function PlayerInventory.AddCarried(player: Player, treasure: { Name: string, Value: number, Rarity: string })
	local carried, count = values(player)
	carried.Value += treasure.Value
	count.Value += 1
	lootEvent:FireClient(player, "Collected", treasure.Name, treasure.Value, treasure.Rarity)
end

-- Sells the bag. Returns the amount banked (0 when the bag was empty).
function PlayerInventory.Bank(player: Player): number
	local carried, count, coins = values(player)
	local amount, items = carried.Value, count.Value
	if amount <= 0 and items <= 0 then
		return 0
	end
	coins.Value += amount
	carried.Value = 0
	count.Value = 0
	lootEvent:FireClient(player, "Banked", amount, items, coins.Value)
	return amount
end

-- Empties the bag without banking it. Returns what was lost.
function PlayerInventory.DropCarried(player: Player): number
	local carried, count = values(player)
	local amount, items = carried.Value, count.Value
	if amount <= 0 and items <= 0 then
		return 0
	end
	carried.Value = 0
	count.Value = 0
	lootEvent:FireClient(player, "Lost", amount, items)
	return amount
end

return PlayerInventory
