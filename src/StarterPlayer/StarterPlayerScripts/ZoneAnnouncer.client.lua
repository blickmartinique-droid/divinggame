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
-- A glass card that drops in under the top edge: a small eyebrow line, the
-- place's name in large letters, a one-line description, and an accent
-- line in its colour that draws itself from the centre outward. Shown when
-- the diver enters a new depth zone ("ZONE 3 · 250 – 400 m / ÉPAVE") or a
-- new biome ("ÉPAVE · 332 m / CIMETIÈRE DE LA SIRÈNE / ...").

local UITheme = require(ReplicatedStorage.Shared.Modules.UITheme)
local BiomeLookup = require(ReplicatedStorage.Shared.Modules.BiomeLookup)
local C, F = UITheme.Colors, UITheme.Fonts

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "ZoneAnnouncer"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 5
screenGui.Parent = player:WaitForChild("PlayerGui")
UITheme.AutoScale(screenGui)

local HIDDEN_Y = UDim2.new(0.5, 0, 0, -140)
local SHOWN_Y = UDim2.new(0.5, 0, 0, 96)

local card = UITheme.Panel(screenGui, "ZoneCard", UDim2.fromOffset(440, 112), HIDDEN_Y, Vector2.new(0.5, 0))
card.Visible = false
local cardStroke = card:FindFirstChildOfClass("UIStroke") :: UIStroke

local eyebrow = UITheme.Label(card, "Eyebrow", "", F.Bold, 12, C.TextDim)
eyebrow.TextXAlignment = Enum.TextXAlignment.Center
eyebrow.Position = UDim2.fromOffset(0, 12)

local title = UITheme.Label(card, "Title", "", F.Title, 30, C.Text)
title.TextXAlignment = Enum.TextXAlignment.Center
title.Position = UDim2.fromOffset(0, 30)

local description = UITheme.Label(card, "Description", "", F.Medium, 13, C.TextDim)
description.TextXAlignment = Enum.TextXAlignment.Center
description.Position = UDim2.fromOffset(0, 68)

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

local function showCard(eyebrowText: string, titleText: string, descriptionText: string, color: Color3)
	bannerToken += 1
	local token = bannerToken

	eyebrow.Text = eyebrowText
	title.Text = UITheme.Upper(titleText)
	description.Text = descriptionText
	accent.BackgroundColor3 = color
	accent.Size = UDim2.fromOffset(0, 3)
	cardStroke.Color = color
	card.Position = HIDDEN_Y
	card.Visible = true

	TweenService:Create(card, TweenInfo.new(BANNER_IN, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = SHOWN_Y }):Play()
	TweenService:Create(accent, TweenInfo.new(BANNER_IN + 0.4, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
		Size = UDim2.fromOffset(240, 3),
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

local function announceZone(zone, index: number)
	showCard(string.format("ZONE %d  ·  %d – %d m", index, zone.MinDepth, zone.MaxDepth), zone.Name, "", zoneAccent(zone))
end

local function announceBiome(biome, depth: number)
	local zone = DepthUtils.GetZoneForDepth(depth)
	showCard(string.format("%s  ·  %d m", UITheme.Upper(zone.Name), math.floor(depth + 0.5)), biome.DisplayName, biome.Description or "", biome.Color or C.Oxygen)
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

-- `fogFloor`: a biome can see further than its depth allows (the great
-- wrecks must read as a whole); the atmosphere thins to match.
local function applyVisuals(visuals, fogFloor: number)
	local fogEnd = math.max(visuals.FogEnd, fogFloor)
	Lighting.FogColor = visuals.FogColor
	Lighting.FogEnd = fogEnd
	Lighting.Brightness = visuals.Brightness
	Lighting.Ambient = visuals.Ambient
	Lighting.OutdoorAmbient = visuals.OutdoorAmbient
	Lighting.ExposureCompensation = visuals.ExposureCompensation
	atmosphere.Density = visuals.AtmosphereDensity * math.clamp(visuals.FogEnd / fogEnd, 0.35, 1)
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

-- Biomes: announced once the diver has stayed in one for a moment (no
-- flicker along a border), and not again for a while after leaving it.
local BIOME_SETTLE = 0.6
local BIOME_REPEAT = 25
local currentBiome = nil
local candidateBiome, candidateSince = nil, 0
local lastAnnounced = {}
local biomeCheckAt = 0
local clock = 0 -- seconds of play, from Heartbeat

local fogTarget, fogFloor, appliedFogFloor, fogCheck = 0, 0, 0, 0

RunService.Heartbeat:Connect(function(dt)
	clock += dt
	local camera = Workspace.CurrentCamera
	if camera then
		fogCheck -= dt
		if fogCheck <= 0 then
			fogCheck = 0.25
			local biome = BiomeLookup.Find(camera.CFrame.Position)
			fogTarget = biome and biome.FogEnd or 0
		end
		fogFloor += (fogTarget - fogFloor) * math.min(1, dt * 1.2)
		local cameraDepth = DepthUtils.GetDepth(camera.CFrame.Position)
		if not lastAppliedDepth or math.abs(cameraDepth - lastAppliedDepth) >= DEPTH_APPLY_EPSILON or math.abs(fogFloor - appliedFogFloor) > 0.5 then
			lastAppliedDepth = cameraDepth
			appliedFogFloor = fogFloor
			applyVisuals(computeVisualsAtDepth(cameraDepth), fogFloor)
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

	local now = clock
	if now < biomeCheckAt then
		return
	end
	biomeCheckAt = now + 0.25
	local biome = depth > 0 and BiomeLookup.Find(rootPart.Position) or nil
	local name = biome and biome.DisplayName
	if name ~= candidateBiome then
		candidateBiome, candidateSince = name, now
	end
	if name ~= currentBiome and now - candidateSince >= BIOME_SETTLE then
		currentBiome = name
		if biome and now - (lastAnnounced[name] or -math.huge) > BIOME_REPEAT then
			lastAnnounced[name] = now
			announceBiome(biome, depth)
		end
	end
end)
