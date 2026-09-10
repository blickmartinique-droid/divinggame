-- Client-side graphics level: which GraphicsConfig tier is active, and a
-- Changed signal so effects can rescale live. Auto-picks a sensible
-- default (touch -> Medium; a very low Roblox quality setting -> Low),
-- and SetLevel is the hook for a future settings menu.

local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GraphicsConfig = require(ReplicatedStorage.Shared.Config.GraphicsConfig)

local GraphicsQuality = {}

local changedEvent = Instance.new("BindableEvent")
GraphicsQuality.Changed = changedEvent.Event

local function autoLevel(): string
	local ok, savedLevel = pcall(function()
		return UserSettings():GetService("UserGameSettings").SavedQualityLevel
	end)
	if ok and savedLevel ~= Enum.SavedQualitySetting.Automatic and savedLevel.Value <= 3 then
		return "Low"
	end
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		return "Medium"
	end
	return GraphicsConfig.DefaultLevel
end

local currentLevel = autoLevel()

function GraphicsQuality.GetLevel(): string
	return currentLevel
end

function GraphicsQuality.Get()
	return GraphicsConfig.Levels[currentLevel] or GraphicsConfig.Levels.High
end

function GraphicsQuality.SetLevel(level: string)
	if GraphicsConfig.Levels[level] and level ~= currentLevel then
		currentLevel = level
		changedEvent:Fire(level)
	end
end

return GraphicsQuality
