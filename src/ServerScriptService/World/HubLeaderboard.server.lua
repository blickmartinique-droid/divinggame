-- Keeps the hub's "Meilleurs plongeurs" board (built by Builders/Hub) up to
-- date: the five richest divers on the server, by banked Pièces.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")

local REFRESH = 5
local MEDALS = { "🥇", "🥈", "🥉", "4.", "5." }

local function coinsOf(player: Player): number
	local leaderstats = player:FindFirstChild("leaderstats")
	local coins = leaderstats and leaderstats:FindFirstChild("Pièces")
	return coins and coins.Value or 0
end

local function refresh()
	local ranking = {}
	for _, player in ipairs(Players:GetPlayers()) do
		table.insert(ranking, { name = player.DisplayName or player.Name, coins = coinsOf(player) })
	end
	table.sort(ranking, function(a, b)
		return a.coins > b.coins
	end)
	for _, board in ipairs(CollectionService:GetTagged("HubLeaderboard")) do
		local gui = board:FindFirstChild("LeaderboardGui")
		local frame = gui and gui:FindFirstChildOfClass("Frame")
		if frame then
			for rank = 1, 5 do
				local line = frame:FindFirstChild("Line" .. (rank + 1))
				if line then
					local entry = ranking[rank]
					if entry then
						line.Text = string.format("%s  %s  —  %d ◉", MEDALS[rank], entry.name, entry.coins)
					else
						line.Text = rank == 1 and "En attente de plongeurs..." or ""
					end
				end
			end
		end
	end
end

task.spawn(function()
	while Workspace:GetAttribute("WorldReady") ~= true do
		task.wait(1)
	end
	while true do
		refresh()
		task.wait(REFRESH)
	end
end)
