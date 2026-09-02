-- Generic death/respawn overlay (blur + message + countdown). Nothing in
-- V1 currently kills the player — running out of oxygen rescues to the
-- surface instead, per the design ("le joueur ne doit pas mourir
-- instantanément") — but this is a ready fallback for any future damage
-- source (hostile creatures, harpoon, etc.). Respawn timing itself is left
-- to Roblox's default auto-respawn; this just shows/hides the overlay.

local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")

local RESPAWN_COUNTDOWN_SECONDS = 5

local player = Players.LocalPlayer

local blur = Instance.new("BlurEffect")
blur.Name = "DeathBlur"
blur.Size = 0
blur.Enabled = false
blur.Parent = Lighting

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "DeathScreen"
screenGui.ResetOnSpawn = false
screenGui.DisplayOrder = 10
screenGui.Enabled = false
screenGui.Parent = player:WaitForChild("PlayerGui")

local overlay = Instance.new("Frame")
overlay.Size = UDim2.fromScale(1, 1)
overlay.BackgroundColor3 = Color3.new(0, 0, 0)
overlay.BackgroundTransparency = 1
overlay.BorderSizePixel = 0
overlay.Parent = screenGui

local title = Instance.new("TextLabel")
title.AnchorPoint = Vector2.new(0.5, 0.5)
title.Position = UDim2.fromScale(0.5, 0.42)
title.Size = UDim2.new(0, 500, 0, 60)
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamBold
title.TextSize = 40
title.TextColor3 = Color3.new(1, 1, 1)
title.Text = "VOUS AVEZ SUCCOMBÉ"
title.Parent = overlay

local subtitle = Instance.new("TextLabel")
subtitle.AnchorPoint = Vector2.new(0.5, 0.5)
subtitle.Position = UDim2.fromScale(0.5, 0.5)
subtitle.Size = UDim2.new(0, 400, 0, 30)
subtitle.BackgroundTransparency = 1
subtitle.Font = Enum.Font.Gotham
subtitle.TextSize = 18
subtitle.TextColor3 = Color3.fromRGB(200, 200, 200)
subtitle.Text = ""
subtitle.Parent = overlay

local function showDeathScreen()
	screenGui.Enabled = true
	blur.Enabled = true
	overlay.BackgroundTransparency = 1
	blur.Size = 0
	TweenService:Create(overlay, TweenInfo.new(0.5), { BackgroundTransparency = 0.4 }):Play()
	TweenService:Create(blur, TweenInfo.new(0.5), { Size = 18 }):Play()
end

local function hideDeathScreen()
	TweenService:Create(overlay, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play()
	TweenService:Create(blur, TweenInfo.new(0.4), { Size = 0 }):Play()
	task.delay(0.4, function()
		screenGui.Enabled = false
		blur.Enabled = false
	end)
end

local function onCharacterAdded(character)
	hideDeathScreen()

	local humanoid = character:WaitForChild("Humanoid")
	humanoid.Died:Connect(function()
		showDeathScreen()

		task.spawn(function()
			local timeLeft = RESPAWN_COUNTDOWN_SECONDS
			while timeLeft > 0 and screenGui.Enabled do
				subtitle.Text = string.format("Réapparition dans %d s", math.ceil(timeLeft))
				task.wait(0.2)
				timeLeft -= 0.2
			end
		end)
	end)
end

if player.Character then
	onCharacterAdded(player.Character)
end
player.CharacterAdded:Connect(onCharacterAdded)
