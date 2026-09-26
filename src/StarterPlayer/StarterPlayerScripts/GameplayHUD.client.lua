-- The diving HUD. A display layer only: every value comes from the server
-- systems that own it (Depth from DepthTracker, Oxygen/MaxOxygen/
-- OxygenDrainPerSecond from OxygenManager, the bag and Pièces from
-- PlayerInventory, loot events on ReplicatedStorage.LootEvent, the
-- current from CurrentField).
--
--   * left: a vertical depth gauge 0-500 m painted with the zones, a
--     marker gliding down it with the depth and zone name;
--   * bottom centre: the oxygen capsule, seconds of air left, turning red
--     and pulsing when low -- with a red vignette and a "surface" cue;
--   * top right: Pièces and the bag, numbers rolling to their new value,
--     and loot cards sliding in below them (rarity-coloured);
--   * top centre: the current you are in, when you are in one.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UITheme = require(ReplicatedStorage.Shared.Modules.UITheme)
local ZonesConfig = require(ReplicatedStorage.Shared.Config.ZonesConfig)
local DepthUtils = require(ReplicatedStorage.Shared.Modules.DepthUtils)
local BiomeLookup = require(ReplicatedStorage.Shared.Modules.BiomeLookup)
local CurrentField = require(ReplicatedStorage.Shared.Modules.CurrentField)

local player = Players.LocalPlayer
local C = UITheme.Colors
local F = UITheme.Fonts

local LOW_OXYGEN = 0.25
local MAX_DEPTH = ZonesConfig.MaxDepth
local GAUGE_HEIGHT = 340

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "GameplayHUD"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = player:WaitForChild("PlayerGui")
UITheme.AutoScale(screenGui)

local function tween(instance: Instance, time: number, goal, style: Enum.EasingStyle?)
	local t = TweenService:Create(instance, TweenInfo.new(time, style or Enum.EasingStyle.Quint, Enum.EasingDirection.Out), goal)
	t:Play()
	return t
end

-- Depth gauge ---------------------------------------------------------------------------

local gauge = UITheme.Panel(screenGui, "DepthGauge", UDim2.fromOffset(46, GAUGE_HEIGHT + 56), UDim2.new(0, 22, 0.5, 0), Vector2.new(0, 0.5))
local surfaceMark = UITheme.Label(gauge, "Surface", "0", F.Bold, 11, C.TextDim)
surfaceMark.Position = UDim2.fromOffset(0, 8)
surfaceMark.TextXAlignment = Enum.TextXAlignment.Center
local bottomMark = UITheme.Label(gauge, "Bottom", tostring(MAX_DEPTH), F.Bold, 11, C.TextDim)
bottomMark.Position = UDim2.new(0, 0, 1, -22)
bottomMark.TextXAlignment = Enum.TextXAlignment.Center

local track = Instance.new("Frame")
track.Name = "Track"
track.Size = UDim2.fromOffset(8, GAUGE_HEIGHT)
track.Position = UDim2.new(0.5, 0, 0, 28)
track.AnchorPoint = Vector2.new(0.5, 0)
track.BackgroundTransparency = 1
track.Parent = gauge
for index, zone in ipairs(ZonesConfig.Zones) do
	local segment = Instance.new("Frame")
	segment.Name = zone.Name
	segment.Position = UDim2.new(0, 0, zone.MinDepth / MAX_DEPTH, index > 1 and 2 or 0)
	segment.Size = UDim2.new(1, 0, (zone.MaxDepth - zone.MinDepth) / MAX_DEPTH, index > 1 and -2 or 0)
	segment.BackgroundColor3 = zone.FogColor:Lerp(Color3.new(1, 1, 1), 0.35)
	segment.BorderSizePixel = 0
	segment.Parent = track
	UITheme.Corner(segment, 4)
end

-- The marker (and its readout) slides along the track.
local marker = Instance.new("Frame")
marker.Name = "Marker"
marker.Size = UDim2.fromOffset(18, 18)
marker.AnchorPoint = Vector2.new(0.5, 0.5)
marker.Position = UDim2.new(0.5, 0, 0, 0)
marker.BackgroundColor3 = C.Text
marker.Rotation = 45
marker.Parent = track
UITheme.Corner(marker, 4)
UITheme.Stroke(marker, 0.2, C.Glass)

local readout = UITheme.Panel(screenGui, "DepthReadout", UDim2.fromOffset(150, 52), UDim2.fromOffset(0, 0), Vector2.new(0, 0.5))
UITheme.Padding(readout, 12, 6)
local depthText = UITheme.Label(readout, "Depth", "0 m", F.Title, 22)
local zoneText = UITheme.Label(readout, "Zone", "SURFACE", F.Bold, 11, C.Oxygen)
zoneText.Position = UDim2.fromOffset(0, 24)

-- Oxygen capsule ---------------------------------------------------------------------------

local oxygenPanel = UITheme.Panel(screenGui, "Oxygen", UDim2.fromOffset(400, 62), UDim2.new(0.5, 0, 1, -26), Vector2.new(0.5, 1))
UITheme.Padding(oxygenPanel, 16, 10)
local oxygenTitle = UITheme.Label(oxygenPanel, "Title", "OXYGÈNE", F.Bold, 12, C.TextDim)
local oxygenTime = UITheme.Label(oxygenPanel, "Seconds", "-- s", F.Title, 16)
oxygenTime.TextXAlignment = Enum.TextXAlignment.Right
local barTrack = Instance.new("Frame")
barTrack.Name = "BarTrack"
barTrack.Size = UDim2.new(1, 0, 0, 12)
barTrack.Position = UDim2.new(0, 0, 1, -12)
barTrack.BackgroundColor3 = Color3.new(0, 0, 0)
barTrack.BackgroundTransparency = 0.45
barTrack.Parent = oxygenPanel
UITheme.Corner(barTrack)
local barFill = Instance.new("Frame")
barFill.Name = "Fill"
barFill.Size = UDim2.fromScale(1, 1)
barFill.BackgroundColor3 = Color3.new(1, 1, 1)
barFill.Parent = barTrack
UITheme.Corner(barFill)
local barGradient = Instance.new("UIGradient")
barGradient.Color = ColorSequence.new(C.Oxygen, C.OxygenDeep)
barGradient.Parent = barFill
local oxygenStroke = UITheme.Stroke(oxygenPanel, 1, C.Danger)
oxygenStroke.Thickness = 2

-- Low-oxygen vignette: four soft red edges.
local vignette = Instance.new("Frame")
vignette.Name = "Vignette"
vignette.Size = UDim2.fromScale(1, 1)
vignette.BackgroundTransparency = 1
vignette.ZIndex = 0
vignette.Parent = screenGui
local edges = {}
for _, edge in ipairs({
	{ UDim2.fromScale(1, 0.22), UDim2.fromScale(0, 0), 90 },
	{ UDim2.fromScale(1, 0.22), UDim2.fromScale(0, 0.78), -90 },
	{ UDim2.fromScale(0.16, 1), UDim2.fromScale(0, 0), 0 },
	{ UDim2.fromScale(0.16, 1), UDim2.fromScale(0.84, 0), 180 },
}) do
	local frame = Instance.new("Frame")
	frame.Size = edge[1]
	frame.Position = edge[2]
	frame.BackgroundColor3 = C.Danger
	frame.BorderSizePixel = 0
	frame.Parent = vignette
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = edge[3]
	gradient.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) })
	gradient.Parent = frame
	table.insert(edges, frame)
end
local surfaceHint = UITheme.Label(screenGui, "SurfaceHint", "↑  REMONTE À LA SURFACE", F.Title, 20, C.Danger)
surfaceHint.Size = UDim2.fromOffset(420, 28)
surfaceHint.AnchorPoint = Vector2.new(0.5, 1)
surfaceHint.Position = UDim2.new(0.5, 0, 1, -100)
surfaceHint.TextXAlignment = Enum.TextXAlignment.Center
surfaceHint.TextStrokeTransparency = 0.4
surfaceHint.Visible = false

-- Wallet and bag -------------------------------------------------------------------------------

local rightColumn = Instance.new("Frame")
rightColumn.Name = "RightColumn"
rightColumn.BackgroundTransparency = 1
rightColumn.Size = UDim2.fromOffset(300, 600)
rightColumn.AnchorPoint = Vector2.new(1, 0)
rightColumn.Position = UDim2.new(1, -22, 0, 22)
rightColumn.Parent = screenGui
local rightLayout = Instance.new("UIListLayout")
rightLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
rightLayout.SortOrder = Enum.SortOrder.LayoutOrder
rightLayout.Padding = UDim.new(0, 8)
rightLayout.Parent = rightColumn

local function chip(order: number, icon: string, accent: Color3)
	local frame = UITheme.Panel(rightColumn, "Chip" .. order, UDim2.fromOffset(190, 42), UDim2.new(), nil)
	frame.LayoutOrder = order
	UITheme.Padding(frame, 12, 0)
	local iconLabel = UITheme.Label(frame, "Icon", icon, F.Bold, 20, accent)
	iconLabel.Size = UDim2.new(0, 28, 1, 0)
	local value = UITheme.Label(frame, "Value", "0", F.Title, 18)
	value.Size = UDim2.new(1, -32, 1, 0)
	value.Position = UDim2.fromOffset(32, 0)
	value.TextXAlignment = Enum.TextXAlignment.Right
	return frame, value
end
local coinsChip, coinsLabel = chip(1, "◉", C.Gold)
local bagChip, bagLabel = chip(2, "▣", C.Oxygen)

local toastHolder = Instance.new("Frame")
toastHolder.Name = "Toasts"
toastHolder.BackgroundTransparency = 1
toastHolder.Size = UDim2.fromOffset(300, 300)
toastHolder.LayoutOrder = 3
toastHolder.Parent = rightColumn
local toastLayout = Instance.new("UIListLayout")
toastLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
toastLayout.SortOrder = Enum.SortOrder.LayoutOrder
toastLayout.Padding = UDim.new(0, 8)
toastLayout.Parent = toastHolder

local toastOrder = 0
local function toast(title: string, subtitle: string, accent: Color3)
	toastOrder += 1
	local slot = Instance.new("Frame")
	slot.Name = "Toast"
	slot.BackgroundTransparency = 1
	slot.Size = UDim2.fromOffset(290, 58)
	slot.LayoutOrder = -toastOrder -- newest on top
	slot.ClipsDescendants = false
	slot.Parent = toastHolder
	local card = UITheme.Panel(slot, "Card", UDim2.fromScale(1, 1), UDim2.fromScale(1.2, 0), nil)
	local bar = Instance.new("Frame")
	bar.Size = UDim2.new(0, 4, 1, -16)
	bar.Position = UDim2.fromOffset(8, 8)
	bar.BackgroundColor3 = accent
	bar.BorderSizePixel = 0
	bar.Parent = card
	UITheme.Corner(bar)
	local titleLabel = UITheme.Label(card, "Title", title, F.Bold, 15)
	titleLabel.Position = UDim2.fromOffset(22, 9)
	titleLabel.Size = UDim2.new(1, -30, 0, 18)
	titleLabel.TextTruncate = Enum.TextTruncate.AtEnd
	local subtitleLabel = UITheme.Label(card, "Subtitle", subtitle, F.Medium, 12, accent)
	subtitleLabel.Position = UDim2.fromOffset(22, 31)
	subtitleLabel.Size = UDim2.new(1, -30, 0, 16)
	tween(card, 0.45, { Position = UDim2.fromScale(0, 0) }, Enum.EasingStyle.Back)
	local children = toastHolder:GetChildren()
	if #children > 5 then
		for _, child in ipairs(children) do
			if child:IsA("Frame") and child.LayoutOrder == -(toastOrder - 4) then
				child:Destroy()
			end
		end
	end
	task.delay(3.2, function()
		if slot.Parent then
			tween(card, 0.4, { Position = UDim2.fromScale(1.2, 0), BackgroundTransparency = 1 })
			task.wait(0.4)
			slot:Destroy()
		end
	end)
end

-- Current chip -------------------------------------------------------------------------------------

local TIER = {
	Weak = { "faible", Color3.fromRGB(150, 220, 240) },
	Medium = { "moyen", C.Oxygen },
	Strong = { "fort", Color3.fromRGB(255, 180, 80) },
	FastLane = { "voie rapide", Color3.fromRGB(255, 110, 200) },
}
local currentChip = UITheme.Panel(screenGui, "Current", UDim2.fromOffset(340, 38), UDim2.new(0.5, 0, 0, -50), Vector2.new(0.5, 0))
local currentLabel = UITheme.Label(currentChip, "Text", "", F.Bold, 15)
currentLabel.Size = UDim2.fromScale(1, 1)
currentLabel.TextXAlignment = Enum.TextXAlignment.Center
local function showCurrent(current: Instance)
	local tier = TIER[current:GetAttribute("CurrentTier")] or TIER.Medium
	local tide = CurrentField.TideLabel(current)
	currentLabel.Text = string.format("≈  %s  ·  %s%s", tostring(current:GetAttribute("CurrentDisplayName") or current.Name), UITheme.Upper(tier[1]), tide and ("  ·  marée : " .. tide) or "")
	currentLabel.TextColor3 = tier[2]
	tween(currentChip, 0.35, { Position = UDim2.new(0.5, 0, 0, 22) })
end
CurrentField.Entered:Connect(showCurrent)
CurrentField.Changed:Connect(showCurrent)
CurrentField.Exited:Connect(function()
	tween(currentChip, 0.35, { Position = UDim2.new(0.5, 0, 0, -50) })
end)

-- Live values -----------------------------------------------------------------------------------------

local depthValue = player:WaitForChild("Depth")
local oxygenValue = player:WaitForChild("Oxygen")
local maxOxygenValue = player:WaitForChild("MaxOxygen")
local drainValue = player:WaitForChild("OxygenDrainPerSecond")
local carriedValue = player:WaitForChild("CarriedValue")
local carriedCount = player:WaitForChild("CarriedCount")
local coinsValue = player:WaitForChild("leaderstats"):WaitForChild("Pièces")

local shownDepth, shownOxygen, shownCoins = depthValue.Value, 1, coinsValue.Value

local function refreshBag()
	if carriedCount.Value > 0 then
		bagLabel.Text = string.format("%d  ·  %s", carriedCount.Value, UITheme.FormatNumber(carriedValue.Value))
	else
		bagLabel.Text = "vide"
	end
end
carriedValue.Changed:Connect(refreshBag)
carriedCount.Changed:Connect(refreshBag)
refreshBag()

local function pulse(frame: Frame)
	local scale = frame:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
	scale.Parent = frame
	scale.Scale = 1.12
	tween(scale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
end
coinsValue.Changed:Connect(function()
	pulse(coinsChip)
end)
carriedValue.Changed:Connect(function()
	pulse(bagChip)
end)

local lootEvent = ReplicatedStorage:WaitForChild("LootEvent")
lootEvent.OnClientEvent:Connect(function(kind: string, a, b, c)
	if kind == "Collected" then
		toast(string.format("%s  +%s", a, UITheme.FormatNumber(b)), (c or "Trésor") .. "  ·  dans le sac", UITheme.Rarity[c] or C.Gold)
	elseif kind == "Banked" then
		toast(string.format("Vendu  +%s", UITheme.FormatNumber(a)), string.format("%d objet%s  ·  total %s", b, b > 1 and "s" or "", UITheme.FormatNumber(c)), C.Success)
	elseif kind == "Lost" then
		toast(string.format("Butin perdu  −%s", UITheme.FormatNumber(a)), string.format("%d objet%s au fond", b, b > 1 and "s" or ""), C.Danger)
	end
end)

-- Per frame: glide the gauge/bar/counters toward their values; pulse the
-- low-oxygen warning.
-- The name under the depth: the biome the diver is in (a few times a
-- second is plenty), else the depth zone.
local placeName, placeTimer = "SURFACE", 0
local function refreshPlace()
	local depth = depthValue.Value
	if depth <= 0 then
		placeName = "SURFACE"
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local biome = root and BiomeLookup.Find(root.Position)
	placeName = UITheme.Upper(biome and biome.DisplayName or DepthUtils.GetZoneForDepth(depth).Name)
end

RunService.RenderStepped:Connect(function(dt)
	placeTimer -= dt
	if placeTimer <= 0 then
		placeTimer = 0.25
		refreshPlace()
	end
	local alpha = 1 - math.exp(-dt * 10)

	shownDepth += (depthValue.Value - shownDepth) * alpha
	local fraction = math.clamp(shownDepth / MAX_DEPTH, 0, 1)
	marker.Position = UDim2.new(0.5, 0, fraction, 0)
	local absolute = track.AbsolutePosition.Y + track.AbsoluteSize.Y * fraction
	readout.Position = UDim2.fromOffset(gauge.AbsolutePosition.X + gauge.AbsoluteSize.X + 10, absolute + screenGui.AbsolutePosition.Y)
	depthText.Text = string.format("%d m", math.floor(shownDepth + 0.5))
	zoneText.Text = placeName

	local maxOxygen = maxOxygenValue.Value > 0 and maxOxygenValue.Value or 1
	local oxygenFraction = math.clamp(oxygenValue.Value / maxOxygen, 0, 1)
	shownOxygen += (oxygenFraction - shownOxygen) * alpha
	barFill.Size = UDim2.fromScale(shownOxygen, 1)
	local seconds = drainValue.Value > 0 and oxygenValue.Value / drainValue.Value or oxygenValue.Value
	oxygenTime.Text = string.format("%d s", math.ceil(seconds))

	local low = oxygenFraction <= LOW_OXYGEN and depthValue.Value > 0
	local beat = (math.sin(os.clock() * 6) + 1) / 2
	barGradient.Color = low and ColorSequence.new(C.Danger, Color3.fromRGB(255, 140, 90)) or ColorSequence.new(C.Oxygen, C.OxygenDeep)
	oxygenStroke.Transparency = low and (0.1 + beat * 0.5) or 1
	oxygenTime.TextColor3 = low and C.Danger or C.Text
	oxygenTitle.TextColor3 = low and C.Danger or C.TextDim
	local vignetteStrength = low and (1 - oxygenFraction / LOW_OXYGEN) * (0.6 + beat * 0.4) or 0
	for _, edge in ipairs(edges) do
		edge.BackgroundTransparency = 1 - vignetteStrength * 0.8
	end
	surfaceHint.Visible = low
	surfaceHint.TextTransparency = low and beat * 0.5 or 1

	shownCoins += (coinsValue.Value - shownCoins) * alpha
	if math.abs(coinsValue.Value - shownCoins) < 0.5 then
		shownCoins = coinsValue.Value
	end
	coinsLabel.Text = UITheme.FormatNumber(shownCoins)
end)
