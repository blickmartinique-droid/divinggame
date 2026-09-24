-- Announces the current depth zone (Récif/Grottes/Épave/Entrée de l'abysse)
-- with a sliding banner card when the CHARACTER crosses into it, and
-- continuously blends the whole look of the water -- Lighting fog,
-- brightness, ambient, exposure, Atmosphere (volume), ColorCorrection
-- (saturation/contrast/tint) and SunRays (god rays) -- to match the
-- CAMERA's exact depth, so 0-500m reads as one smooth gradient and
-- breaking the surface is an immediate change of world (ZonesConfig.Surface
-- vs the Récif preset, blended over the first SurfaceBlendDepth studs).
--
-- The camera, not the character, drives the look: in third person the
-- camera is often above the water while the character swims just under
-- it (or the reverse), and the fog/tint must match what the lens is
-- actually in. Purely client-local (each player's own Lighting override).
-- Post effects are created here (not in Studio) so they can be turned
-- off wholesale on the Low graphics level.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DepthUtils = require(ReplicatedStorage.Shared.Modules.DepthUtils)
local ZonesConfig = require(ReplicatedStorage.Shared.Config.ZonesConfig)
local GraphicsQuality = require(ReplicatedStorage.Shared.Modules.GraphicsQuality)

local player = Players.LocalPlayer

local BANNER_IN = 0.55
local BANNER_HOLD = 2.6
local BANNER_OUT = 0.6
local DEPTH_APPLY_EPSILON = 0.05

-- Banner ------------------------------------------------------------------
-- A glass card that drops in under the top edge: a small "ZONE n · depth
-- range" eyebrow, the zone name in large letters, and an accent line in
-- the zone's colour that draws itself from the centre outward.

local UITheme = require(ReplicatedStorage.Shared.Modules.UITheme)
local C, F = UITheme.Colors, UITheme.Fonts

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "ZoneAnnouncer"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 5
screenGui.Parent = player:WaitForChild("PlayerGui")
UITheme.AutoScale(screenGui)

local HIDDEN_Y = UDim2.new(0.5, 0, 0, -120)
local SHOWN_Y = UDim2.new(0.5, 0, 0, 96)

local card = UITheme.Panel(screenGui, "ZoneCard", UDim2.fromOffset(380, 92), HIDDEN_Y, Vector2.new(0.5, 0))
card.Visible = false
local cardStroke = card:FindFirstChildOfClass("UIStroke") :: UIStroke

local eyebrow = UITheme.Label(card, "Eyebrow", "", F.Bold, 12, C.TextDim)
eyebrow.TextXAlignment = Enum.TextXAlignment.Center
eyebrow.Position = UDim2.fromOffset(0, 14)

local title = UITheme.Label(card, "Title", "", F.Title, 34, C.Text)
title.TextXAlignment = Enum.TextXAlignment.Center
title.Position = UDim2.fromOffset(0, 32)

local accent = Instance.new("Frame")
accent.Name = "Accent"
accent.AnchorPoint = Vector2.new(0.5, 1)
accent.Position = UDim2.new(0.5, 0, 1, -10)
accent.Size = UDim2.fromOffset(0, 3)
accent.BorderSizePixel = 0
accent.Parent = card
UITheme.Corner(accent)

local function zoneAccent(zone): Color3
	return zone.FogColor:Lerp(Color3.new(1, 1, 1), 0.45)
end

local bannerToken = 0

local function announceZone(zone, index: number)
	bannerToken += 1
	local token = bannerToken
	local color = zoneAccent(zone)

	eyebrow.Text = string.format("ZONE %d  ·  %d – %d m", index, zone.MinDepth, zone.MaxDepth)
	title.Text = zone.Name:upper()
	accent.BackgroundColor3 = color
	accent.Size = UDim2.fromOffset(0, 3)
	cardStroke.Color = color
	card.Position = HIDDEN_Y
	card.Visible = true

	TweenService:Create(card, TweenInfo.new(BANNER_IN, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = SHOWN_Y }):Play()
	TweenService:Create(accent, TweenInfo.new(BANNER_IN + 0.4, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
		Size = UDim2.fromOffset(220, 3),
	}):Play()

	task.delay(BANNER_IN + BANNER_HOLD, function()
		if token ~= bannerToken then
			return
		end
		local out = TweenService:Create(card, TweenInfo.new(BANNER_OUT, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = HIDDEN_Y })
		out:Play()
		out.Completed:Connect(function()
			if token == bannerToken then
				card.Visible = false
			end
		end)
	end)
end

-- Effects -------------------------------------------------------------------

local function getOrCreate(className: string, name: string)
	local existing = Lighting:FindFirstChild(name)
	if existing and existing:IsA(className) then
		return existing
	end
	local instance = Instance.new(className)
	instance.Name = name
	instance.Parent = Lighting
	return instance
end

local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere") or getOrCreate("Atmosphere", "Atmosphere")
local colorCorrection = getOrCreate("ColorCorrectionEffect", "DepthColorCorrection")
local sunRays = getOrCreate("SunRaysEffect", "DepthSunRays")
sunRays.Spread = 0.7

local function applyQuality()
	local settings = GraphicsQuality.Get()
	colorCorrection.Enabled = settings.PostEffects
	sunRays.Enabled = settings.SunRays
end
applyQuality()
GraphicsQuality.Changed:Connect(applyQuality)

-- Blending ------------------------------------------------------------------

local FIELDS = {
	"FogColor", "FogEnd", "Brightness", "Ambient", "OutdoorAmbient", "ExposureCompensation",
	"AtmosphereDensity", "AtmosphereHaze", "AtmosphereColor", "AtmosphereDecay",
	"Saturation", "Contrast", "Tint", "SunRays",
}

local function lerpVisuals(a, b, t)
	local result = {}
	for _, field in ipairs(FIELDS) do
		local va, vb = a[field], b[field]
		if typeof(va) == "Color3" then
			result[field] = va:Lerp(vb, t)
		else
			result[field] = va + (vb - va) * t
		end
	end
	return result
end

-- Zone[i]'s visuals are its state at zone[i].MinDepth, blended toward
-- zone[i+1]'s as depth moves between their MinDepths; the surface preset
-- blends into zone[1] across the first few studs.
local function computeVisualsAtDepth(depth: number)
	local zones = ZonesConfig.Zones
	if depth <= 0 then
		return ZonesConfig.Surface
	end
	if depth < ZonesConfig.SurfaceBlendDepth then
		return lerpVisuals(ZonesConfig.Surface, zones[1], depth / ZonesConfig.SurfaceBlendDepth)
	end

	for i = 1, #zones - 1 do
		local current, nextZone = zones[i], zones[i + 1]
		if depth < nextZone.MinDepth then
			local t = (depth - current.MinDepth) / (nextZone.MinDepth - current.MinDepth)
			return lerpVisuals(current, nextZone, t)
		end
	end

	return zones[#zones]
end

local function applyVisuals(visuals)
	Lighting.FogColor = visuals.FogColor
	Lighting.FogEnd = visuals.FogEnd
	Lighting.Brightness = visuals.Brightness
	Lighting.Ambient = visuals.Ambient
	Lighting.OutdoorAmbient = visuals.OutdoorAmbient
	Lighting.ExposureCompensation = visuals.ExposureCompensation
	atmosphere.Density = visuals.AtmosphereDensity
	atmosphere.Haze = visuals.AtmosphereHaze
	atmosphere.Color = visuals.AtmosphereColor
	atmosphere.Decay = visuals.AtmosphereDecay
	colorCorrection.Saturation = visuals.Saturation
	colorCorrection.Contrast = visuals.Contrast
	colorCorrection.TintColor = visuals.Tint
	sunRays.Intensity = visuals.SunRays
end

-- Loop ----------------------------------------------------------------------

local currentZoneName = nil
local lastAppliedDepth = nil

RunService.Heartbeat:Connect(function()
	local camera = Workspace.CurrentCamera
	if camera then
		local cameraDepth = DepthUtils.GetDepth(camera.CFrame.Position)
		if not lastAppliedDepth or math.abs(cameraDepth - lastAppliedDepth) >= DEPTH_APPLY_EPSILON then
			lastAppliedDepth = cameraDepth
			applyVisuals(computeVisualsAtDepth(cameraDepth))
		end
	end

	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		return
	end
	local depth = DepthUtils.GetDepth(rootPart.Position)
	if depth > 0 then
		local zone = DepthUtils.GetZoneForDepth(depth)
		if zone.Name ~= currentZoneName then
			currentZoneName = zone.Name
			announceZone(zone, table.find(ZonesConfig.Zones, zone) or 1)
		end
	else
		currentZoneName = nil
	end
end)
