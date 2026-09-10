-- Announces the current depth zone (Récif/Grottes/Épave/Entrée de l'abysse)
-- with a fade-in/out banner when the CHARACTER crosses into it, and
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

local BANNER_FADE_IN = 0.6
local BANNER_HOLD = 2
local BANNER_FADE_OUT = 0.8
local DEPTH_APPLY_EPSILON = 0.05

-- Banner ------------------------------------------------------------------

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "ZoneAnnouncer"
screenGui.ResetOnSpawn = false
screenGui.Parent = player:WaitForChild("PlayerGui")

local label = Instance.new("TextLabel")
label.Name = "ZoneLabel"
label.AnchorPoint = Vector2.new(0.5, 0.5)
label.Position = UDim2.new(0.5, 0, 0.35, 0)
label.Size = UDim2.new(0, 500, 0, 60)
label.BackgroundTransparency = 1
label.Font = Enum.Font.GothamBold
label.TextSize = 36
label.TextColor3 = Color3.new(1, 1, 1)
label.TextTransparency = 1
label.Text = ""
label.Parent = screenGui

local stroke = Instance.new("UIStroke")
stroke.Color = Color3.new(0, 0, 0)
stroke.Thickness = 2
stroke.Transparency = 1
stroke.Parent = label

local function announceZone(zone)
	label.Text = zone.Name:upper()
	label.TextTransparency = 1
	stroke.Transparency = 1

	TweenService:Create(label, TweenInfo.new(BANNER_FADE_IN), { TextTransparency = 0 }):Play()
	TweenService:Create(stroke, TweenInfo.new(BANNER_FADE_IN), { Transparency = 0.5 }):Play()

	task.delay(BANNER_FADE_IN + BANNER_HOLD, function()
		TweenService:Create(label, TweenInfo.new(BANNER_FADE_OUT), { TextTransparency = 1 }):Play()
		TweenService:Create(stroke, TweenInfo.new(BANNER_FADE_OUT), { Transparency = 1 }):Play()
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
			announceZone(zone)
		end
	else
		currentZoneName = nil
	end
end)
