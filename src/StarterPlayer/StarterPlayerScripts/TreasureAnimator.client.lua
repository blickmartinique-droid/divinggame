-- Purely cosmetic: spins and gently bobs any treasure part flagged with the
-- Animate attribute, so they read as objects floating in the current
-- instead of static markers.

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ROTATION_SPEED = math.rad(30) -- radians/second
local BOB_HEIGHT = 0.3
local BOB_SPEED = 2

local baseHeights = setmetatable({}, { __mode = "k" })

RunService.Heartbeat:Connect(function()
	local treasuresFolder = Workspace:FindFirstChild("Treasures")
	if not treasuresFolder then
		return
	end

	local now = os.clock()
	for _, treasure in ipairs(treasuresFolder:GetChildren()) do
		if treasure:IsA("BasePart") and treasure:GetAttribute("Animate") then
			local baseHeight = baseHeights[treasure]
			if not baseHeight then
				baseHeight = treasure.Position.Y
				baseHeights[treasure] = baseHeight
			end

			local bobOffset = math.sin(now * BOB_SPEED + treasure.Position.X) * BOB_HEIGHT
			local newPosition = Vector3.new(treasure.Position.X, baseHeight + bobOffset, treasure.Position.Z)
			treasure.CFrame = CFrame.new(newPosition) * CFrame.Angles(0, now * ROTATION_SPEED, 0)
		end
	end
end)
