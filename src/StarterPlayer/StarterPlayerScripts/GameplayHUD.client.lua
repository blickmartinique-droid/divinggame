-- Minimal gameplay HUD: oxygen, depth, and current zone name. Purely a
-- display layer -- it holds no game logic of its own, and reuses the
-- systems that already own each value instead of recomputing them:
--   * Depth: DepthTracker.server.lua (authoritative), replicated to the
--     client as the player's Depth NumberValue.
--   * Oxygen: OxygenManager.server.lua (authoritative), replicated as
--     Oxygen / MaxOxygen. MaxOxygen is a per-player value (not the
--     OxygenConfig constant) specifically so future equipment (Bouteille)
--     can raise or lower it per player -- this bar reads whatever that
--     value currently is, so equipping better gear later needs no UI
--     change at all.
--   * Zone: DepthUtils.GetZoneForDepth, the same shared pure function
--     ZoneAnnouncer's big banner and the server both use, applied to the
--     same replicated Depth value read above (no separate depth source).
--
-- Replaces the earlier DepthDebugUI stand-in.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local OxygenConfig = require(ReplicatedStorage.Shared.Config.OxygenConfig)
local DepthUtils = require(ReplicatedStorage.Shared.Modules.DepthUtils)
local CurrentField = require(ReplicatedStorage.Shared.Modules.CurrentField)

local player = Players.LocalPlayer

local ACCENT_COLOR = Color3.fromRGB(80, 200, 255)
local OXYGEN_LOW_COLOR = Color3.fromRGB(255, 80, 70)
local LOW_OXYGEN_THRESHOLD = 0.25

-- Zone label: briefly emphasized (bigger, fully opaque) when entering a new
-- zone, then settles into a smaller, more transparent resting style so it
-- stays readable without competing for attention -- separate from
-- ZoneAnnouncer's big banner, which fades all the way to invisible instead.
local ZONE_EMPHASIS_SIZE = 16
local ZONE_REST_SIZE = 13
local ZONE_REST_TRANSPARENCY = 0.35
local ZONE_EMPHASIS_HOLD = 1.4
local ZONE_SETTLE_TIME = 0.5

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "GameplayHUD"
screenGui.ResetOnSpawn = false
screenGui.Parent = player:WaitForChild("PlayerGui")

local container = Instance.new("Frame")
container.Name = "HudContainer"
container.AnchorPoint = Vector2.new(0, 0)
container.Position = UDim2.new(0, 20, 0, 20)
container.Size = UDim2.new(0, 220, 0, 0)
container.AutomaticSize = Enum.AutomaticSize.Y
container.BackgroundColor3 = Color3.fromRGB(10, 20, 28)
container.BackgroundTransparency = 0.25
container.BorderSizePixel = 0
container.Parent = screenGui

local containerCorner = Instance.new("UICorner")
containerCorner.CornerRadius = UDim.new(0, 16)
containerCorner.Parent = container

local containerStroke = Instance.new("UIStroke")
containerStroke.Color = Color3.fromRGB(255, 255, 255)
containerStroke.Transparency = 0.85
containerStroke.Thickness = 1
containerStroke.Parent = container

local padding = Instance.new("UIPadding")
padding.PaddingTop = UDim.new(0, 14)
padding.PaddingBottom = UDim.new(0, 14)
padding.PaddingLeft = UDim.new(0, 16)
padding.PaddingRight = UDim.new(0, 16)
padding.Parent = container

local layout = Instance.new("UIListLayout")
layout.FillDirection = Enum.FillDirection.Vertical
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Padding = UDim.new(0, 8)
layout.Parent = container

local zoneLabel = Instance.new("TextLabel")
zoneLabel.Name = "ZoneLabel"
zoneLabel.LayoutOrder = 1
zoneLabel.Size = UDim2.new(1, 0, 0, 18)
zoneLabel.BackgroundTransparency = 1
zoneLabel.TextXAlignment = Enum.TextXAlignment.Left
zoneLabel.Font = Enum.Font.GothamBold
zoneLabel.TextSize = ZONE_REST_SIZE
zoneLabel.TextColor3 = ACCENT_COLOR
zoneLabel.TextTransparency = ZONE_REST_TRANSPARENCY
zoneLabel.Text = "📍 SURFACE"
zoneLabel.Parent = container

local depthLabel = Instance.new("TextLabel")
depthLabel.Name = "DepthLabel"
depthLabel.LayoutOrder = 2
depthLabel.Size = UDim2.new(1, 0, 0, 26)
depthLabel.BackgroundTransparency = 1
depthLabel.TextXAlignment = Enum.TextXAlignment.Left
depthLabel.Font = Enum.Font.GothamBold
depthLabel.TextSize = 22
depthLabel.TextColor3 = Color3.fromRGB(235, 245, 250)
depthLabel.Text = "📏 0 m"
depthLabel.Parent = container

local oxygenBarBackground = Instance.new("Frame")
oxygenBarBackground.Name = "OxygenBarBackground"
oxygenBarBackground.LayoutOrder = 3
oxygenBarBackground.Size = UDim2.new(1, 0, 0, 20)
oxygenBarBackground.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
oxygenBarBackground.BackgroundTransparency = 0.4
oxygenBarBackground.BorderSizePixel = 0
oxygenBarBackground.Parent = container

local oxygenBarBackgroundCorner = Instance.new("UICorner")
oxygenBarBackgroundCorner.CornerRadius = UDim.new(1, 0)
oxygenBarBackgroundCorner.Parent = oxygenBarBackground

local oxygenBarFill = Instance.new("Frame")
oxygenBarFill.Name = "OxygenBarFill"
oxygenBarFill.Size = UDim2.new(1, 0, 1, 0)
oxygenBarFill.BackgroundColor3 = ACCENT_COLOR
oxygenBarFill.BorderSizePixel = 0
oxygenBarFill.Parent = oxygenBarBackground

local oxygenBarFillCorner = Instance.new("UICorner")
oxygenBarFillCorner.CornerRadius = UDim.new(1, 0)
oxygenBarFillCorner.Parent = oxygenBarFill

-- Low-oxygen alert: a soft red outline that pulses (rather than a static
-- color change alone) so it reads as an active warning, not just a tint.
local oxygenBarStroke = Instance.new("UIStroke")
oxygenBarStroke.Color = OXYGEN_LOW_COLOR
oxygenBarStroke.Thickness = 1.5
oxygenBarStroke.Transparency = 1
oxygenBarStroke.Parent = oxygenBarBackground

local oxygenCaption = Instance.new("TextLabel")
oxygenCaption.Name = "OxygenCaption"
oxygenCaption.LayoutOrder = 4
oxygenCaption.Size = UDim2.new(1, 0, 0, 14)
oxygenCaption.BackgroundTransparency = 1
oxygenCaption.TextXAlignment = Enum.TextXAlignment.Left
oxygenCaption.Font = Enum.Font.Gotham
oxygenCaption.TextSize = 12
oxygenCaption.TextColor3 = Color3.fromRGB(160, 190, 200)
oxygenCaption.Text = "🫁 -- / --"
oxygenCaption.Parent = container

-- Current indicator: only present while inside a current (the row
-- collapses out of the layout otherwise), driven by CurrentField's
-- enter/exit signals rather than any polling of its own.
local currentLabel = Instance.new("TextLabel")
currentLabel.Name = "CurrentLabel"
currentLabel.LayoutOrder = 5
currentLabel.Size = UDim2.new(1, 0, 0, 16)
currentLabel.BackgroundTransparency = 1
currentLabel.TextXAlignment = Enum.TextXAlignment.Left
currentLabel.Font = Enum.Font.GothamBold
currentLabel.TextSize = 13
currentLabel.TextColor3 = Color3.fromRGB(170, 225, 240)
currentLabel.Text = ""
currentLabel.Visible = false
currentLabel.Parent = container

local TIER_LABELS = { Weak = "faible", Medium = "moyen", Strong = "fort" }

local function showCurrent(currentPart: BasePart)
	local name = currentPart:GetAttribute("CurrentDisplayName") or currentPart.Name
	local tier = TIER_LABELS[currentPart:GetAttribute("CurrentTier")] or ""
	currentLabel.Text = string.format("🌊 %s (%s)", name, tier)
	currentLabel.Visible = true
end

CurrentField.Entered:Connect(showCurrent)
CurrentField.Changed:Connect(showCurrent)
CurrentField.Exited:Connect(function()
	currentLabel.Visible = false
end)

-- Zone label emphasis/settle transition --------------------------------

local zoneSettleThread = nil

local function setZoneRestStyle(displayName: string)
	if zoneSettleThread then
		task.cancel(zoneSettleThread)
		zoneSettleThread = nil
	end
	zoneLabel.Text = "📍 " .. displayName:upper()
	zoneLabel.TextSize = ZONE_REST_SIZE
	zoneLabel.TextTransparency = ZONE_REST_TRANSPARENCY
end

local function announceZoneChange(displayName: string)
	zoneLabel.Text = "📍 " .. displayName:upper()

	if zoneSettleThread then
		task.cancel(zoneSettleThread)
	end

	TweenService:Create(zoneLabel, TweenInfo.new(0.15), {
		TextSize = ZONE_EMPHASIS_SIZE,
		TextTransparency = 0,
	}):Play()

	zoneSettleThread = task.delay(ZONE_EMPHASIS_HOLD, function()
		zoneSettleThread = nil
		TweenService:Create(zoneLabel, TweenInfo.new(ZONE_SETTLE_TIME), {
			TextSize = ZONE_REST_SIZE,
			TextTransparency = ZONE_REST_TRANSPARENCY,
		}):Play()
	end)
end

-- Oxygen low-alert pulse -------------------------------------------------

local alertTween = nil

local function setLowOxygenAlertActive(active: boolean)
	if active then
		if alertTween then
			return
		end
		oxygenBarStroke.Transparency = 0.4
		alertTween = TweenService:Create(
			oxygenBarStroke,
			TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ Transparency = 0 }
		)
		alertTween:Play()
	else
		if alertTween then
			alertTween:Cancel()
			alertTween = nil
		end
		oxygenBarStroke.Transparency = 1
	end
end

-- Live updates ------------------------------------------------------------
-- Event-driven: the server only writes Depth/Oxygen a few times per second,
-- so redrawing from each value's Changed signal is both cheaper and exactly
-- as current as polling every frame was.

local currentZoneName = nil

local function refreshDepth(depth: number)
	depthLabel.Text = string.format("📏 %d m", depth)

	if depth > 0 then
		local zone = DepthUtils.GetZoneForDepth(depth)
		if zone.Name ~= currentZoneName then
			currentZoneName = zone.Name
			announceZoneChange(zone.Name)
		end
	elseif currentZoneName ~= nil then
		currentZoneName = nil
		setZoneRestStyle("Surface")
	end
end

local function refreshOxygen(oxygen: number, maxOxygenRaw: number)
	local maxOxygen = maxOxygenRaw > 0 and maxOxygenRaw or OxygenConfig.MaxOxygen
	local fraction = math.clamp(oxygen / maxOxygen, 0, 1)
	oxygenBarFill.Size = UDim2.new(fraction, 0, 1, 0)
	oxygenCaption.Text = string.format("🫁 %d / %d", math.ceil(oxygen), math.floor(maxOxygen))

	if fraction <= LOW_OXYGEN_THRESHOLD then
		oxygenBarFill.BackgroundColor3 = OXYGEN_LOW_COLOR:Lerp(ACCENT_COLOR, fraction / LOW_OXYGEN_THRESHOLD)
		setLowOxygenAlertActive(true)
	else
		oxygenBarFill.BackgroundColor3 = ACCENT_COLOR
		setLowOxygenAlertActive(false)
	end
end

local depthValue = player:WaitForChild("Depth")
local oxygenValue = player:WaitForChild("Oxygen")
local maxOxygenValue = player:WaitForChild("MaxOxygen")

depthValue.Changed:Connect(refreshDepth)
oxygenValue.Changed:Connect(function(oxygen)
	refreshOxygen(oxygen, maxOxygenValue.Value)
end)
maxOxygenValue.Changed:Connect(function(maxOxygen)
	refreshOxygen(oxygenValue.Value, maxOxygen)
end)

refreshDepth(depthValue.Value)
refreshOxygen(oxygenValue.Value, maxOxygenValue.Value)
