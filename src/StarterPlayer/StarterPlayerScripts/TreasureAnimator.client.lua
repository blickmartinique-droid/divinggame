-- Purely cosmetic: spins and gently bobs any treasure part flagged with the
-- Animate attribute, so they read as objects floating in the current
-- instead of static markers.
--
-- Only treasures within ANIMATE_RADIUS of the local camera are moved, and
-- the candidate list is refreshed on a slow timer rather than scanning the
-- whole folder every frame: the world is meant to hold far more treasures
-- than are ever visible at once, and moving parts nobody can see is wasted
-- CFrame work every frame. Treasures out of range simply hold their rest
-- pose (which is also the pose the server placed them in).

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ROTATION_SPEED = math.rad(30) -- radians/second
local BOB_HEIGHT = 0.3
local BOB_SPEED = 2
local ANIMATE_RADIUS = 250
local REFRESH_INTERVAL = 1

local baseHeights = setmetatable({}, { __mode = "k" })
local nearby = {}
local sinceRefresh = REFRESH_INTERVAL

local function refreshNearby()
	table.clear(nearby)
	local treasuresFolder = Workspace:FindFirstChild("Treasures")
	local camera = Workspace.CurrentCamera
	if not treasuresFolder or not camera then
		return
	end

	local origin = camera.CFrame.Position
	for _, treasure in ipairs(treasuresFolder:GetChildren()) do
		if treasure:IsA("BasePart") and treasure:GetAttribute("Animate") then
			if (treasure.Position - origin).Magnitude <= ANIMATE_RADIUS then
				table.insert(nearby, treasure)
			end
		end
	end
end

RunService.Heartbeat:Connect(function(deltaTime)
	sinceRefresh += deltaTime
	if sinceRefresh >= REFRESH_INTERVAL then
		sinceRefresh = 0
		refreshNearby()
	end

	local now = os.clock()
	for _, treasure in ipairs(nearby) do
		if treasure.Parent then
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
