-- Sways the underwater plants tagged "Sway" by the world builders (kelp,
-- seagrass, sea fans, sea-pen feathers): each one rocks gently about its
-- own base, with its SwayAmplitude (radians) and SwaySpeed (Hz) and a
-- per-plant phase so a meadow ripples instead of moving in lockstep.
-- Client-only CFrame writes on anchored parts -- nothing replicates -- and
-- only plants near the camera move; the list is refreshed on a slow timer.

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local RANGE = 160
local REFRESH_INTERVAL = 1

local restFrames = setmetatable({}, { __mode = "k" })
local nearby = {}
local sinceRefresh = REFRESH_INTERVAL

local function refreshNearby()
	table.clear(nearby)
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local origin = camera.CFrame.Position
	for _, plant in ipairs(CollectionService:GetTagged("Sway")) do
		if plant:IsA("BasePart") and plant.Parent then
			local rest = restFrames[plant]
			if not rest then
				rest = {
					base = plant.CFrame * CFrame.new(0, -plant.Size.Y / 2, 0),
					half = plant.Size.Y / 2,
					amplitude = plant:GetAttribute("SwayAmplitude") or 0.1,
					speed = (plant:GetAttribute("SwaySpeed") or 0.6) * math.pi * 2,
					phase = (plant.Position.X * 0.13 + plant.Position.Z * 0.07) % (math.pi * 2),
				}
				restFrames[plant] = rest
			end
			if (rest.base.Position - origin).Magnitude <= RANGE then
				table.insert(nearby, plant)
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
	for _, plant in ipairs(nearby) do
		local rest = restFrames[plant]
		if rest and plant.Parent then
			local t = now * rest.speed + rest.phase
			local tilt = CFrame.Angles(math.sin(t) * rest.amplitude, 0, math.sin(t * 0.7 + 1.3) * rest.amplitude * 0.6)
			plant.CFrame = rest.base * tilt * CFrame.new(0, rest.half, 0)
		end
	end
end)
