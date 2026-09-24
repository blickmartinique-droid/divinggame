-- Death/respawn overlay: blur + dark red wash, then a glass card that says
-- what happened (LastDeathCause, set by the server when a diver drowns or a
-- creature lands the last bite), the deepest point of that dive, what the
-- bag held and was lost (LootEvent "Lost"), and a bar that empties until
-- the respawn. Respawn timing itself is Roblox's default auto-respawn; this
-- just shows/hides the overlay.

local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UITheme = require(ReplicatedStorage.Shared.Modules.UITheme)
local C, F = UITheme.Colors, UITheme.Fonts

local player = Players.LocalPlayer
local respawnSeconds = Players.RespawnTime > 0 and Players.RespawnTime or 5

local blur = Instance.new("BlurEffect")
blur.Name = "DeathBlur"
blur.Size = 0
blur.Enabled = false
blur.Parent = Lighting

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "DeathScreen"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 10
screenGui.Enabled = false
screenGui.Parent = player:WaitForChild("PlayerGui")
UITheme.AutoScale(screenGui)

local overlay = Instance.new("Frame")
overlay.Name = "Overlay"
overlay.Size = UDim2.fromScale(1, 1)
overlay.BackgroundColor3 = Color3.fromRGB(20, 2, 8)
overlay.BackgroundTransparency = 1
overlay.BorderSizePixel = 0
overlay.Parent = screenGui
local wash = Instance.new("UIGradient")
wash.Rotation = 90
wash.Color = ColorSequence.new(Color3.fromRGB(10, 14, 24), Color3.fromRGB(70, 8, 18))
wash.Parent = overlay

local CARD_SHOWN = UDim2.fromScale(0.5, 0.5)
local CARD_HIDDEN = UDim2.new(0.5, 0, 0.5, 40)

local card = UITheme.Panel(overlay, "Card", UDim2.fromOffset(420, 262), CARD_HIDDEN, Vector2.new(0.5, 0.5))
card.BackgroundTransparency = 0.18
local cardStroke = card:FindFirstChildOfClass("UIStroke") :: UIStroke
cardStroke.Color = C.Danger
cardStroke.Transparency = 0.5
UITheme.Padding(card, 26, 22)
local cardScale = Instance.new("UIScale")
cardScale.Parent = card

local icon = UITheme.Label(card, "Icon", "✕", F.Title, 22, C.Danger)
icon.TextXAlignment = Enum.TextXAlignment.Center
icon.Size = UDim2.fromOffset(40, 40)
icon.AnchorPoint = Vector2.new(0.5, 0)
icon.Position = UDim2.new(0.5, 0, 0, 0)
icon.BackgroundTransparency = 0.8
icon.BackgroundColor3 = C.Danger
UITheme.Corner(icon)

local title = UITheme.Label(card, "Title", "VOUS AVEZ SUCCOMBÉ", F.Title, 26, C.Text)
title.TextXAlignment = Enum.TextXAlignment.Center
title.Position = UDim2.fromOffset(0, 50)

local cause = UITheme.Label(card, "Cause", "", F.Medium, 15, C.Danger)
cause.TextXAlignment = Enum.TextXAlignment.Center
cause.Position = UDim2.fromOffset(0, 84)

-- Two stat tiles side by side.
local stats = Instance.new("Frame")
stats.Name = "Stats"
stats.BackgroundTransparency = 1
stats.Position = UDim2.fromOffset(0, 116)
stats.Size = UDim2.new(1, 0, 0, 58)
stats.Parent = card
local statsLayout = Instance.new("UIListLayout")
statsLayout.FillDirection = Enum.FillDirection.Horizontal
statsLayout.Padding = UDim.new(0, 10)
statsLayout.Parent = stats

local function statTile(name: string, caption: string, color: Color3): TextLabel
	local tile = Instance.new("Frame")
	tile.Name = name
	tile.Size = UDim2.new(0.5, -5, 1, 0)
	tile.BackgroundColor3 = C.GlassLight
	tile.BackgroundTransparency = 0.35
	tile.BorderSizePixel = 0
	tile.Parent = stats
	UITheme.Corner(tile, 10)
	UITheme.Padding(tile, 12, 8)
	local captionLabel = UITheme.Label(tile, "Caption", caption, F.Bold, 10, C.TextDim)
	captionLabel.Position = UDim2.fromOffset(0, 0)
	local value = UITheme.Label(tile, "Value", "", F.Title, 18, color)
	value.Position = UDim2.fromOffset(0, 16)
	return value
end

local depthStat = statTile("Depth", "PROFONDEUR MAX", C.Oxygen)
local lootStat = statTile("Loot", "BUTIN PERDU", C.Gold)

local respawnLabel = UITheme.Label(card, "Respawn", "", F.Medium, 13, C.TextDim)
respawnLabel.TextXAlignment = Enum.TextXAlignment.Center
respawnLabel.Position = UDim2.new(0, 0, 1, -34)

local track = Instance.new("Frame")
track.Name = "RespawnTrack"
track.AnchorPoint = Vector2.new(0, 1)
track.Position = UDim2.new(0, 0, 1, 0)
track.Size = UDim2.new(1, 0, 0, 6)
track.BackgroundColor3 = C.GlassLight
track.BorderSizePixel = 0
track.Parent = card
UITheme.Corner(track)
local fill = Instance.new("Frame")
fill.Name = "Fill"
fill.Size = UDim2.fromScale(1, 1)
fill.BackgroundColor3 = C.Oxygen
fill.BorderSizePixel = 0
fill.Parent = track
UITheme.Corner(fill)

-- Dive bookkeeping --------------------------------------------------------------

local maxDepthThisLife = 0
local lostValue, lostItems = 0, 0

task.spawn(function()
	local depthValue = player:WaitForChild("Depth") :: NumberValue
	depthValue.Changed:Connect(function(value)
		if value > maxDepthThisLife then
			maxDepthThisLife = value
		end
	end)
end)

task.spawn(function()
	local lootEvent = ReplicatedStorage:WaitForChild("LootEvent") :: RemoteEvent
	lootEvent.OnClientEvent:Connect(function(kind: string, amount: number, items: number)
		if kind == "Lost" then
			lostValue, lostItems = amount, items
			lootStat.Text = string.format("%s ◉  ·  %d obj.", UITheme.FormatNumber(amount), items)
		end
	end)
end)

-- Show / hide --------------------------------------------------------------------

local showToken = 0

local function showDeathScreen()
	showToken += 1
	local token = showToken

	cause.Text = player:GetAttribute("LastDeathCause") or "Le récif ne pardonne pas"
	depthStat.Text = string.format("%d m", math.floor(maxDepthThisLife + 0.5))
	lootStat.Text = lostValue > 0 and string.format("%s ◉  ·  %d obj.", UITheme.FormatNumber(lostValue), lostItems) or "Rien"

	screenGui.Enabled = true
	blur.Enabled = true
	overlay.BackgroundTransparency = 1
	blur.Size = 0
	card.Position = CARD_HIDDEN
	cardScale.Scale = 0.92
	fill.Size = UDim2.fromScale(1, 1)

	TweenService:Create(overlay, TweenInfo.new(0.6), { BackgroundTransparency = 0.3 }):Play()
	TweenService:Create(blur, TweenInfo.new(0.6), { Size = 20 }):Play()
	TweenService:Create(card, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = CARD_SHOWN }):Play()
	TweenService:Create(cardScale, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	TweenService:Create(fill, TweenInfo.new(respawnSeconds, Enum.EasingStyle.Linear), { Size = UDim2.fromScale(0, 1) }):Play()

	task.spawn(function()
		local timeLeft = respawnSeconds
		while timeLeft > 0 and token == showToken and screenGui.Enabled do
			respawnLabel.Text = string.format("Retour à la plage dans %d s", math.ceil(timeLeft))
			task.wait(0.2)
			timeLeft -= 0.2
		end
		respawnLabel.Text = "Retour à la plage…"
	end)
end

local function hideDeathScreen()
	showToken += 1
	local token = showToken
	TweenService:Create(overlay, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play()
	TweenService:Create(blur, TweenInfo.new(0.4), { Size = 0 }):Play()
	TweenService:Create(card, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = CARD_HIDDEN }):Play()
	task.delay(0.4, function()
		if token == showToken then
			screenGui.Enabled = false
			blur.Enabled = false
		end
	end)
end

local function onCharacterAdded(character)
	hideDeathScreen()
	maxDepthThisLife = 0
	lostValue, lostItems = 0, 0

	local humanoid = character:WaitForChild("Humanoid")
	humanoid.Died:Connect(function()
		-- The server empties the bag on Died; give its "Lost" event a moment
		-- to arrive so the card shows the right amount.
		task.delay(0.25, showDeathScreen)
	end)
end

if player.Character then
	onCharacterAdded(player.Character)
end
player.CharacterAdded:Connect(onCharacterAdded)
