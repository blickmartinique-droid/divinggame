-- Temporary debug readout for the depth system (step 3). Shows the
-- server-authoritative Depth value on screen so it can be verified without
-- digging through the Explorer. The real HUD (oxygen, bag, coins) is a
-- later step and will replace this.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "DepthDebugUI"
screenGui.ResetOnSpawn = false
screenGui.Parent = player:WaitForChild("PlayerGui")

local label = Instance.new("TextLabel")
label.Name = "DepthLabel"
label.AnchorPoint = Vector2.new(0.5, 0)
label.Position = UDim2.new(0.5, 0, 0, 20)
label.Size = UDim2.new(0, 220, 0, 40)
label.BackgroundColor3 = Color3.new(0, 0, 0)
label.BackgroundTransparency = 0.4
label.TextColor3 = Color3.new(1, 1, 1)
label.Font = Enum.Font.GothamBold
label.TextScaled = true
label.Text = "Profondeur : 0 m"
label.Parent = screenGui

RunService.Heartbeat:Connect(function()
	local depthValue = player:FindFirstChild("Depth")
	if depthValue then
		label.Text = string.format("Profondeur : %d m", depthValue.Value)
	end
end)
