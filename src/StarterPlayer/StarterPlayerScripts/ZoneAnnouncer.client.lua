-- Announces the current depth zone (Récif/Grottes/Épave/Entrée de l'abysse)
-- with a fade-in/out banner when the player crosses into it, and
-- continuously blends Lighting fog/brightness/ambient and Atmosphere haze
-- to match the player's exact depth -- not just snapping at each zone
-- boundary, so the whole 0-500m range reads as one smooth gradient from
-- bright reef to near-black abyss. Purely client-local (each player's own
-- Lighting override), driven by the same DepthUtils/ZonesConfig used by the
-- server's authoritative depth tracking.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DepthUtils = require(ReplicatedStorage.Shared.Modules.DepthUtils)
local ZonesConfig = require(ReplicatedStorage.Shared.Config.ZonesConfig)

local player = Players.LocalPlayer

local BANNER_FADE_IN = 0.6
local BANNER_HOLD = 2
local BANNER_FADE_OUT = 0.8

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

local function getAtmosphere()
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if not atmosphere then
		atmosphere = Instance.new("Atmosphere")
		atmosphere.Parent = Lighting
	end
	return atmosphere
end
local atmosphere = getAtmosphere()

-- Blends zone[i]'s own visuals (its state at zone[i].MinDepth) toward
-- zone[i+1]'s as depth moves between their MinDepths, so the environment
-- changes gradually across the whole range instead of jumping the instant
-- a boundary is crossed. Depths at or past the last zone's MinDepth just
-- hold that zone's values (it's the final tier).
local function computeVisualsAtDepth(depth: number)
	local zones = ZonesConfig.Zones
	if depth <= zones[1].MinDepth then
		return zones[1]
	end

	for i = 1, #zones - 1 do
		local current, nextZone = zones[i], zones[i + 1]
		if depth < nextZone.MinDepth then
			local t = (depth - current.MinDepth) / (nextZone.MinDepth - current.MinDepth)
			return {
				FogColor = current.FogColor:Lerp(nextZone.FogColor, t),
				FogEnd = current.FogEnd + (nextZone.FogEnd - current.FogEnd) * t,
				Brightness = current.Brightness + (nextZone.Brightness - current.Brightness) * t,
				AtmosphereHaze = current.AtmosphereHaze + (nextZone.AtmosphereHaze - current.AtmosphereHaze) * t,
				Ambient = current.Ambient:Lerp(nextZone.Ambient, t),
				OutdoorAmbient = current.OutdoorAmbient:Lerp(nextZone.OutdoorAmbient, t),
			}
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
	atmosphere.Haze = visuals.AtmosphereHaze
end

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

local function onCharacterAdded(character)
	local currentZoneName = nil
	local rootPart = character:WaitForChild("HumanoidRootPart")

	local connection
	connection = RunService.Heartbeat:Connect(function()
		if not character.Parent then
			connection:Disconnect()
			return
		end

		local depth = DepthUtils.GetDepth(rootPart.Position)
		applyVisuals(computeVisualsAtDepth(depth))

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
end

if player.Character then
	onCharacterAdded(player.Character)
end
player.CharacterAdded:Connect(onCharacterAdded)
