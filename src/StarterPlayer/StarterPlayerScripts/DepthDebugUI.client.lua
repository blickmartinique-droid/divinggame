-- Temporary debug HUD for depth (step 3) and oxygen (step 4). A styled
-- stand-in so both systems are easy to read while testing; the real HUD
-- (bag, coins) is a later step and will replace this.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local OxygenConfig = require(game:GetService("ReplicatedStorage").Shared.Config.OxygenConfig)

local player = Players.LocalPlayer

local OXYGEN_COLOR_FULL = Color3.fromRGB(80, 200, 255)
local OXYGEN_COLOR_LOW = Color3.fromRGB(255, 80, 70)
local LOW_OXYGEN_THRESHOLD = 0.25

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "DepthDebugUI"
screenGui.ResetOnSpawn = false
screenGui.Parent = player:WaitForChild("PlayerGui")

local container = Instance.new("Frame")
container.Name = "HudContainer"
container.AnchorPoint = Vector2.new(0, 0)
container.Position = UDim2.new(0, 20, 0, 20)
container.Size = UDim2.new(0, 240, 0, 92)
container.BackgroundColor3 = Color3.fromRGB(10, 20, 28)
container.BackgroundTransparency = 0.25
container.BorderSizePixel = 0
container.Parent = screenGui

local containerCorner = Instance.new("UICorner")
containerCorner.CornerRadius = UDim.new(0, 14)
containerCorner.Parent = container

local containerStroke = Instance.new("UIStroke")
containerStroke.Color = Color3.fromRGB(255, 255, 255)
containerStroke.Transparency = 0.85
containerStroke.Thickness = 1
containerStroke.Parent = container

local padding = Instance.new("UIPadding")
padding.PaddingTop = UDim.new(0, 12)
padding.PaddingBottom = UDim.new(0, 12)
padding.PaddingLeft = UDim.new(0, 14)
padding.PaddingRight = UDim.new(0, 14)
padding.Parent = container

local depthLabel = Instance.new("TextLabel")
depthLabel.Name = "DepthLabel"
depthLabel.Size = UDim2.new(1, 0, 0, 22)
depthLabel.BackgroundTransparency = 1
depthLabel.TextXAlignment = Enum.TextXAlignment.Left
depthLabel.Font = Enum.Font.GothamBold
depthLabel.TextSize = 18
depthLabel.TextColor3 = Color3.fromRGB(235, 245, 250)
depthLabel.Text = "Profondeur : 0 m"
depthLabel.Parent = container

local oxygenBarBackground = Instance.new("Frame")
oxygenBarBackground.Name = "OxygenBarBackground"
oxygenBarBackground.Position = UDim2.new(0, 0, 0, 40)
oxygenBarBackground.Size = UDim2.new(1, 0, 0, 22)
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
oxygenBarFill.BackgroundColor3 = OXYGEN_COLOR_FULL
oxygenBarFill.BorderSizePixel = 0
oxygenBarFill.Parent = oxygenBarBackground

local oxygenBarFillCorner = Instance.new("UICorner")
oxygenBarFillCorner.CornerRadius = UDim.new(1, 0)
oxygenBarFillCorner.Parent = oxygenBarFill

local oxygenCaption = Instance.new("TextLabel")
oxygenCaption.Name = "OxygenCaption"
oxygenCaption.Position = UDim2.new(0, 0, 0, 68)
oxygenCaption.Size = UDim2.new(1, 0, 0, 14)
oxygenCaption.BackgroundTransparency = 1
oxygenCaption.TextXAlignment = Enum.TextXAlignment.Left
oxygenCaption.Font = Enum.Font.Gotham
oxygenCaption.TextSize = 11
oxygenCaption.TextColor3 = Color3.fromRGB(160, 190, 200)
oxygenCaption.Text = "OXYGÈNE"
oxygenCaption.Parent = container

RunService.Heartbeat:Connect(function()
	local depthValue = player:FindFirstChild("Depth")
	if depthValue then
		depthLabel.Text = string.format("Profondeur : %d m", depthValue.Value)
	end

	local oxygenValue = player:FindFirstChild("Oxygen")
	if oxygenValue then
		local fraction = math.clamp(oxygenValue.Value / OxygenConfig.MaxOxygen, 0, 1)
		oxygenBarFill.Size = UDim2.new(fraction, 0, 1, 0)

		if fraction <= LOW_OXYGEN_THRESHOLD then
			local lowFraction = fraction / LOW_OXYGEN_THRESHOLD
			oxygenBarFill.BackgroundColor3 = OXYGEN_COLOR_LOW:Lerp(OXYGEN_COLOR_FULL, lowFraction)
		else
			oxygenBarFill.BackgroundColor3 = OXYGEN_COLOR_FULL
		end
	end
end)
