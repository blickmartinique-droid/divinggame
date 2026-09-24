-- Drives PlayerInventory's loop from the authoritative server state: the
-- bag is sold as soon as DepthTracker reports the diver back at the
-- surface, and lost when the character dies (drowning or an attack).

local Players = game:GetService("Players")

local PlayerInventory = require(script.Parent.PlayerInventory)

local function onCharacterAdded(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	humanoid.Died:Connect(function()
		PlayerInventory.DropCarried(player)
	end)
end

local function onPlayerAdded(player: Player)
	PlayerInventory.Setup(player)

	local depth = player:WaitForChild("Depth") :: NumberValue
	depth.Changed:Connect(function(value)
		if value <= 0 then
			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.Health > 0 then
				PlayerInventory.Bank(player)
			end
		end
	end)

	if player.Character then
		task.spawn(onCharacterAdded, player, player.Character)
	end
	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
end

for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, player)
end
Players.PlayerAdded:Connect(onPlayerAdded)
