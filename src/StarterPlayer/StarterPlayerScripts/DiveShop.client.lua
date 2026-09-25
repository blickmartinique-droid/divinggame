-- The Centre de plongée's shop, opened at the counter (the hub's
-- ProximityPrompt tagged OpensShop). One tab per gear category; each item
-- is a card with its colour, description, what it does (a bar against the
-- best of its kind) and one button: its price, "Équiper", or "Équipé".
-- Purchases go through ReplicatedStorage.EquipmentRequest, which checks
-- everything server-side; the cards follow the player's OwnedEquipment /
-- Equipped_* attributes and their Pièces. Closes with ✕ or by walking away.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ProximityPromptService = game:GetService("ProximityPromptService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local EquipmentConfig = require(ReplicatedStorage.Shared.Config.EquipmentConfig)
local UITheme = require(ReplicatedStorage.Shared.Modules.UITheme)
local C, F = UITheme.Colors, UITheme.Fonts

local player = Players.LocalPlayer
local CLOSE_DISTANCE = 24

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "DiveShop"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 8
screenGui.Enabled = false
screenGui.Parent = player:WaitForChild("PlayerGui")
UITheme.AutoScale(screenGui)

local dim = Instance.new("Frame")
dim.Name = "Dim"
dim.Size = UDim2.fromScale(1, 1)
dim.BackgroundColor3 = Color3.new(0, 0, 0)
dim.BackgroundTransparency = 0.55
dim.BorderSizePixel = 0
dim.Parent = screenGui

local panel = UITheme.Panel(screenGui, "Panel", UDim2.fromOffset(840, 540), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5))
panel.BackgroundTransparency = 0.12
local panelScale = Instance.new("UIScale")
panelScale.Parent = panel

-- Header ---------------------------------------------------------------------------------
local title = UITheme.Label(panel, "Title", "CENTRE DE PLONGÉE", F.Title, 26, C.Text)
title.Position = UDim2.fromOffset(28, 22)
title.Size = UDim2.new(1, -300, 0, 30)
local subtitle = UITheme.Label(panel, "Subtitle", "Équipe-toi pour descendre plus profond, plus longtemps.", F.Medium, 14, C.TextDim)
subtitle.Position = UDim2.fromOffset(28, 54)
subtitle.Size = UDim2.new(1, -300, 0, 18)

local coinsChip = UITheme.Panel(panel, "Coins", UDim2.fromOffset(170, 40), UDim2.new(1, -78, 0, 24), Vector2.new(1, 0))
coinsChip.BackgroundColor3 = C.GlassLight
local coinsLabel = UITheme.Label(coinsChip, "Value", "◉ 0", F.Bold, 18, C.Gold)
coinsLabel.Size = UDim2.fromScale(1, 1)
coinsLabel.TextXAlignment = Enum.TextXAlignment.Center

local closeButton = Instance.new("TextButton")
closeButton.Name = "Close"
closeButton.AnchorPoint = Vector2.new(1, 0)
closeButton.Position = UDim2.new(1, -22, 0, 24)
closeButton.Size = UDim2.fromOffset(40, 40)
closeButton.BackgroundColor3 = C.GlassLight
closeButton.BackgroundTransparency = 0.2
closeButton.Text = "✕"
closeButton.Font = F.Bold
closeButton.TextSize = 18
closeButton.TextColor3 = C.Text
closeButton.AutoButtonColor = true
closeButton.Parent = panel
UITheme.Corner(closeButton, 12)

-- Tabs -----------------------------------------------------------------------------------
local tabs = Instance.new("Frame")
tabs.Name = "Tabs"
tabs.BackgroundTransparency = 1
tabs.Position = UDim2.fromOffset(22, 92)
tabs.Size = UDim2.new(0, 190, 1, -150)
tabs.Parent = panel
local tabList = Instance.new("UIListLayout")
tabList.Padding = UDim.new(0, 8)
tabList.SortOrder = Enum.SortOrder.LayoutOrder
tabList.Parent = tabs

local list = Instance.new("ScrollingFrame")
list.Name = "Items"
list.BackgroundTransparency = 1
list.BorderSizePixel = 0
list.Position = UDim2.fromOffset(226, 92)
list.Size = UDim2.new(1, -250, 1, -150)
list.ScrollBarThickness = 4
list.ScrollBarImageColor3 = C.Stroke
list.AutomaticCanvasSize = Enum.AutomaticSize.Y
list.CanvasSize = UDim2.new()
list.Parent = panel
local itemList = Instance.new("UIListLayout")
itemList.Padding = UDim.new(0, 10)
itemList.SortOrder = Enum.SortOrder.LayoutOrder
itemList.Parent = list

local status = UITheme.Label(panel, "Status", "", F.Medium, 14, C.TextDim)
status.AnchorPoint = Vector2.new(0, 1)
status.Position = UDim2.new(0, 28, 1, -18)
status.Size = UDim2.new(1, -56, 0, 20)

-- State ----------------------------------------------------------------------------------
local selected = EquipmentConfig.Categories[1].Id
local tabButtons = {}
local request = ReplicatedStorage:WaitForChild("EquipmentRequest", 10)
local counterPart: BasePart? = nil

local function coins(): number
	local leaderstats = player:FindFirstChild("leaderstats")
	local value = leaderstats and leaderstats:FindFirstChild("Pièces")
	return value and value.Value or 0
end

local function owns(id: string): boolean
	local owned = player:GetAttribute("OwnedEquipment") or ""
	for entry in string.gmatch(owned, "[^,]+") do
		if entry == id then
			return true
		end
	end
	for _, default in pairs(EquipmentConfig.Defaults) do
		if default == id then
			return true
		end
	end
	return false
end

local function statOf(item): (number, string)
	if item.Category == "Tank" then
		return item.MaxOxygen, string.format("Autonomie  %d s", item.MaxOxygen)
	elseif item.Category == "Suit" then
		local saving = math.floor((1 - item.DrainMultiplier) * 100 + 0.5)
		return saving, saving > 0 and string.format("Consommation  −%d %%", saving) or "Consommation normale"
	elseif item.Category == "Fins" then
		local bonus = math.floor((item.SpeedMultiplier - 1) * 100 + 0.5)
		return bonus, bonus > 0 and string.format("Vitesse  +%d %%", bonus) or "Vitesse normale"
	end
	return item.LampRange or 0, (item.LampRange or 0) > 0 and string.format("Portée  %d m", item.LampRange) or "Pas de lumière"
end

local function setStatus(text: string, color: Color3?)
	status.Text = text
	status.TextColor3 = color or C.TextDim
end

local refresh -- forward

local function act(action: string, item)
	if not request then
		setStatus("Boutique indisponible", C.Danger)
		return
	end
	setStatus("…")
	local ok, result = pcall(function()
		return request:InvokeServer(action, item.Id)
	end)
	if ok and type(result) == "table" then
		setStatus(result.message or "", result.ok and C.Success or C.Danger)
	else
		setStatus("Erreur de connexion", C.Danger)
	end
	refresh()
end

local function card(item, index: number, best: number)
	local frame = Instance.new("Frame")
	frame.Name = item.Id
	frame.LayoutOrder = index
	frame.Size = UDim2.new(1, -8, 0, 96)
	frame.BackgroundColor3 = C.GlassLight
	frame.BackgroundTransparency = 0.3
	frame.BorderSizePixel = 0
	frame.Parent = list
	UITheme.Corner(frame, 12)
	local stroke = UITheme.Stroke(frame, 0.85)

	local swatch = Instance.new("Frame")
	swatch.Name = "Swatch"
	swatch.Position = UDim2.fromOffset(16, 20)
	swatch.Size = UDim2.fromOffset(56, 56)
	swatch.BackgroundColor3 = item.Color or C.GlassLight
	swatch.BorderSizePixel = 0
	swatch.Parent = frame
	UITheme.Corner(swatch, 14)
	UITheme.Stroke(swatch, 0.6)
	if item.Accent then
		local accent = Instance.new("Frame")
		accent.AnchorPoint = Vector2.new(0.5, 0)
		accent.Position = UDim2.fromScale(0.5, 0)
		accent.Size = UDim2.new(0.2, 0, 1, 0)
		accent.BackgroundColor3 = item.Accent
		accent.BorderSizePixel = 0
		accent.Parent = swatch
	end

	local name = UITheme.Label(frame, "Name", item.Name, F.Bold, 18, C.Text)
	name.Position = UDim2.fromOffset(88, 12)
	name.Size = UDim2.new(1, -250, 0, 22)
	local description = UITheme.Label(frame, "Description", item.Description or "", F.Body, 13, C.TextDim)
	description.Position = UDim2.fromOffset(88, 36)
	description.Size = UDim2.new(1, -250, 0, 16)
	description.TextTruncate = Enum.TextTruncate.AtEnd

	local value, text = statOf(item)
	local statLabel = UITheme.Label(frame, "Stat", text, F.Medium, 13, C.Oxygen)
	statLabel.Position = UDim2.fromOffset(88, 58)
	statLabel.Size = UDim2.new(0, 190, 0, 16)
	local track = Instance.new("Frame")
	track.Name = "StatTrack"
	track.Position = UDim2.fromOffset(88, 78)
	track.Size = UDim2.new(1, -250, 0, 6)
	track.BackgroundColor3 = C.Glass
	track.BorderSizePixel = 0
	track.Parent = frame
	UITheme.Corner(track)
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(best > 0 and math.clamp(value / best, 0.04, 1) or 0.04, 1)
	fill.BackgroundColor3 = C.Oxygen
	fill.BorderSizePixel = 0
	fill.Parent = track
	UITheme.Corner(fill)

	local button = Instance.new("TextButton")
	button.Name = "Action"
	button.AnchorPoint = Vector2.new(1, 0.5)
	button.Position = UDim2.new(1, -16, 0.5, 0)
	button.Size = UDim2.fromOffset(136, 44)
	button.Font = F.Bold
	button.TextSize = 16
	button.AutoButtonColor = true
	button.Parent = frame
	UITheme.Corner(button, 12)
	local buttonStroke = UITheme.Stroke(button, 0.4)

	local equipped = player:GetAttribute("Equipped_" .. item.Category) == item.Id
		or (player:GetAttribute("Equipped_" .. item.Category) == nil and EquipmentConfig.Defaults[item.Category] == item.Id)
	if equipped then
		button.Text = "ÉQUIPÉ ✓"
		button.BackgroundColor3 = C.Success
		button.BackgroundTransparency = 0.75
		button.TextColor3 = C.Success
		buttonStroke.Color = C.Success
		button.AutoButtonColor = false
		stroke.Color = C.Success
		stroke.Transparency = 0.5
	elseif owns(item.Id) then
		button.Text = "ÉQUIPER"
		button.BackgroundColor3 = C.Oxygen
		button.BackgroundTransparency = 0.8
		button.TextColor3 = C.Oxygen
		buttonStroke.Color = C.Oxygen
		button.Activated:Connect(function()
			act("Equip", item)
		end)
	else
		local affordable = coins() >= item.Price
		button.Text = string.format("%s ◉", UITheme.FormatNumber(item.Price))
		button.BackgroundColor3 = affordable and C.Gold or C.Glass
		button.BackgroundTransparency = affordable and 0.1 or 0.3
		button.TextColor3 = affordable and Color3.fromRGB(40, 28, 8) or C.Danger
		buttonStroke.Color = affordable and C.Gold or C.Danger
		button.Activated:Connect(function()
			act("Buy", item)
		end)
	end
	return frame
end

refresh = function()
	coinsLabel.Text = "◉ " .. UITheme.FormatNumber(coins())
	for id, button in pairs(tabButtons) do
		local active = id == selected
		button.BackgroundTransparency = active and 0.15 or 0.7
		button.BackgroundColor3 = active and C.Oxygen or C.GlassLight
		button.TextColor3 = active and Color3.fromRGB(6, 30, 40) or C.Text
	end
	for _, child in ipairs(list:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	local best = 0
	for _, item in ipairs(EquipmentConfig.Items) do
		if item.Category == selected then
			best = math.max(best, (statOf(item)))
		end
	end
	local index = 0
	for _, item in ipairs(EquipmentConfig.Items) do
		if item.Category == selected then
			index += 1
			card(item, index, best)
		end
	end
end

for index, category in ipairs(EquipmentConfig.Categories) do
	local button = Instance.new("TextButton")
	button.Name = category.Id
	button.LayoutOrder = index
	button.Size = UDim2.new(1, 0, 0, 52)
	button.BackgroundColor3 = C.GlassLight
	button.BackgroundTransparency = 0.7
	button.Font = F.Bold
	button.TextSize = 17
	button.TextColor3 = C.Text
	button.TextXAlignment = Enum.TextXAlignment.Left
	button.Text = "   " .. category.Icon .. "   " .. category.Name
	button.AutoButtonColor = true
	button.Parent = tabs
	UITheme.Corner(button, 12)
	tabButtons[category.Id] = button
	button.Activated:Connect(function()
		selected = category.Id
		setStatus("")
		refresh()
	end)
end

-- Open / close ---------------------------------------------------------------------------
local isOpen = false

local function close()
	if not isOpen then
		return
	end
	isOpen = false
	screenGui.Enabled = false
end

local function open(prompt: ProximityPrompt?)
	local parent = prompt and prompt.Parent
	counterPart = if parent and parent:IsA("BasePart") then parent else nil
	isOpen = true
	setStatus("")
	refresh()
	screenGui.Enabled = true
	panelScale.Scale = 0.9
	TweenService:Create(panelScale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

closeButton.Activated:Connect(close)
ProximityPromptService.PromptTriggered:Connect(function(prompt)
	if prompt:GetAttribute("OpensShop") then
		open(prompt)
	end
end)

-- Keep the cards in sync while open; close when the diver walks off.
player.AttributeChanged:Connect(function(name)
	if isOpen and (name == "OwnedEquipment" or string.sub(name, 1, 9) == "Equipped_") then
		refresh()
	end
end)
task.spawn(function()
	local leaderstats = player:WaitForChild("leaderstats", 30)
	local value = leaderstats and leaderstats:WaitForChild("Pièces", 30)
	if value then
		value.Changed:Connect(function()
			if isOpen then
				refresh()
			end
		end)
	end
end)
RunService.Heartbeat:Connect(function()
	if not isOpen or not counterPart then
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and (root.Position - counterPart.Position).Magnitude > CLOSE_DISTANCE then
		close()
	end
end)
