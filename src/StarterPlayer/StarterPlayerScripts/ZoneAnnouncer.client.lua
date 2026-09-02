-- Announces the current depth zone (Récif/Grottes/Épave/Abysses) with a
-- fade-in/out banner when the player crosses into it, and smoothly tweens
-- Lighting fog/brightness and Atmosphere haze to match — each zone reads
-- progressively darker and murkier with depth. Purely client-local (each
-- player's own Lighting override), driven by the same DepthUtils/ZonesConfig
-- used by the server's authoritative depth tracking.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DepthUtils = require(ReplicatedStorage.Shared.Modules.DepthUtils)

local player = Players.LocalPlayer

local ATMOSPHERE_TWEEN_TIME = 2
local BANNER_FADE_IN = 0.6
local BANNER_HOLD = 2
local BANNER_FADE_OUT = 0.8

local SURFACE_VISUALS = {
	FogColor = Color3.fromRGB(120, 170, 180),
	FogEnd = 1500,
	Brightness = 3,
	AtmosphereHaze = 1.2,
}

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

local function tweenVisuals(visuals)
	local atmosphere = getAtmosphere()
	TweenService:Create(Lighting, TweenInfo.new(ATMOSPHERE_TWEEN_TIME), {
		FogColor = visuals.FogColor,
		FogEnd = visuals.FogEnd,
		Brightness = visuals.Brightness,
	}):Play()
	TweenService:Create(atmosphere, TweenInfo.new(ATMOSPHERE_TWEEN_TIME), {
		Haze = visuals.AtmosphereHaze,
	}):Play()
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

		if depth > 0 then
			local zone = DepthUtils.GetZoneForDepth(depth)
			if zone.Name ~= currentZoneName then
				currentZoneName = zone.Name
				announceZone(zone)
				tweenVisuals(zone)
			end
		elseif currentZoneName ~= nil then
			currentZoneName = nil
			tweenVisuals(SURFACE_VISUALS)
		end
	end)
end

if player.Character then
	onCharacterAdded(player.Character)
end
player.CharacterAdded:Connect(onCharacterAdded)
