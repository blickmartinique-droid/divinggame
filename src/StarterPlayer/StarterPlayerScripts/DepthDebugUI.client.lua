-- Temporary debug readout for the depth (step 3) and oxygen (step 4)
-- systems. Shows the server-authoritative values on screen so they can be
-- verified without digging through the Explorer. The real HUD (oxygen bar,
-- bag, coins) is a later step and will replace this.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "DepthDebugUI"
screenGui.ResetOnSpawn = false
screenGui.Parent = player:WaitForChild("PlayerGui")

local depthLabel = Instance.new("TextLabel")
depthLabel.Name = "DepthLabel"
depthLabel.AnchorPoint = Vector2.new(0.5, 0)
depthLabel.Position = UDim2.new(0.5, 0, 0, 20)
depthLabel.Size = UDim2.new(0, 220, 0, 40)
depthLabel.BackgroundColor3 = Color3.new(0, 0, 0)
depthLabel.BackgroundTransparency = 0.4
depthLabel.TextColor3 = Color3.new(1, 1, 1)
depthLabel.Font = Enum.Font.GothamBold
depthLabel.TextScaled = true
depthLabel.Text = "Profondeur : 0 m"
depthLabel.Parent = screenGui

local oxygenLabel = Instance.new("TextLabel")
oxygenLabel.Name = "OxygenLabel"
oxygenLabel.AnchorPoint = Vector2.new(0.5, 0)
oxygenLabel.Position = UDim2.new(0.5, 0, 0, 64)
oxygenLabel.Size = UDim2.new(0, 220, 0, 40)
oxygenLabel.BackgroundColor3 = Color3.new(0, 0, 0)
oxygenLabel.BackgroundTransparency = 0.4
oxygenLabel.TextColor3 = Color3.fromRGB(150, 220, 255)
oxygenLabel.Font = Enum.Font.GothamBold
oxygenLabel.TextScaled = true
oxygenLabel.Text = "Oxygène : 0 s"
oxygenLabel.Parent = screenGui

RunService.Heartbeat:Connect(function()
	local depthValue = player:FindFirstChild("Depth")
	if depthValue then
		depthLabel.Text = string.format("Profondeur : %d m", depthValue.Value)
	end

	local oxygenValue = player:FindFirstChild("Oxygen")
	if oxygenValue then
		oxygenLabel.Text = string.format("Oxygène : %d s", math.ceil(oxygenValue.Value))
	end
end)
