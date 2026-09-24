-- Ambient shoals around the diver: small decorative fish that exist only
-- on this client (anchored parts moved by CFrame, nothing replicated, no
-- server cost), so the water always feels alive between the real
-- creatures. What swims depends on the depth: bright reef fish in the
-- shallows, silver shoals in the mid-water, tiny glowing fish in the
-- abyss. A shoal wanders, keeps between the seabed and the surface (a
-- raycast down finds the ground), scatters when the diver swims into it,
-- and is recycled once it falls far behind. Count from the graphics level.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CreatureBodies = require(ReplicatedStorage.Shared.Modules.CreatureBodies)
local DepthUtils = require(ReplicatedStorage.Shared.Modules.DepthUtils)
local GraphicsQuality = require(ReplicatedStorage.Shared.Modules.GraphicsQuality)

local player = Players.LocalPlayer

local SHOALS_BY_LEVEL = { High = 7, Medium = 4, Low = 2 }
local SPAWN_MIN, SPAWN_MAX = 35, 85
local DESPAWN_DISTANCE = 150
local SCATTER_DISTANCE = 14
local SILVER = Color3.fromRGB(190, 205, 215)
local ABYSS_GLOW = Color3.fromRGB(90, 200, 255)

local folder = Instance.new("Folder")
folder.Name = "AmbientFish"
folder.Parent = Workspace

local shoals = {}
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true

local function groundBelow(position: Vector3): number?
	rayParams.FilterDescendantsInstances = { folder, player.Character }
	local hit = Workspace:Raycast(position + Vector3.new(0, 60, 0), Vector3.new(0, -400, 0), rayParams)
	return hit and hit.Position.Y or nil
end

local function makeShoal(center: Vector3, depth: number)
	local count, length, tint, glow
	if depth < 110 then
		count, length = math.random(8, 14), 1.4 + math.random() * 0.8
	elseif depth < 330 then
		count, length, tint = math.random(10, 18), 1.1 + math.random() * 0.6, SILVER
	else
		count, length, tint, glow = math.random(6, 10), 0.8 + math.random() * 0.4, ABYSS_GLOW, true
	end
	local variant = math.random(1, CreatureBodies.ReefPaletteCount)
	local shoal = {
		center = center,
		heading = Vector3.new(math.random() - 0.5, 0, math.random() - 0.5).Unit,
		speed = 5 + math.random() * 3,
		turn = 0,
		scatter = 0,
		fish = {},
		groundCheck = 0,
		ground = groundBelow(center),
	}
	for index = 1, count do
		local model = CreatureBodies.BuildSmallFish(length, variant, tint, glow)
		model.Parent = folder
		table.insert(shoal.fish, {
			model = model,
			slot = Vector3.new((math.random() - 0.5) * 9, (math.random() - 0.5) * 4, (math.random() - 0.5) * 9),
			phase = math.random() * math.pi * 2,
			index = index,
		})
	end
	return shoal
end

local function destroyShoal(shoal)
	for _, fish in ipairs(shoal.fish) do
		fish.model:Destroy()
	end
end

local function trySpawn(origin: Vector3)
	local angle = math.random() * math.pi * 2
	local distance = SPAWN_MIN + math.random() * (SPAWN_MAX - SPAWN_MIN)
	local point = origin + Vector3.new(math.cos(angle) * distance, (math.random() - 0.5) * 30, math.sin(angle) * distance)
	point = Vector3.new(point.X, math.min(point.Y, DepthUtils.SURFACE_Y - 4), point.Z)
	local ground = groundBelow(point)
	if ground and point.Y < ground + 5 then
		point = Vector3.new(point.X, ground + 5 + math.random() * 10, point.Z)
		if point.Y > DepthUtils.SURFACE_Y - 4 then
			return
		end
	end
	table.insert(shoals, makeShoal(point, DepthUtils.GetDepth(point)))
end

RunService.Heartbeat:Connect(function(dt)
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local origin = camera.CFrame.Position
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local diver = root and root.Position or origin
	local wanted = DepthUtils.GetDepth(origin) > 2 and (SHOALS_BY_LEVEL[GraphicsQuality.GetLevel()] or 4) or 0

	for i = #shoals, 1, -1 do
		local shoal = shoals[i]
		if (shoal.center - origin).Magnitude > DESPAWN_DISTANCE or #shoals > wanted then
			destroyShoal(shoal)
			table.remove(shoals, i)
		end
	end
	if #shoals < wanted then
		trySpawn(origin)
	end

	local now = os.clock()
	for _, shoal in ipairs(shoals) do
		-- Wander: the heading drifts; the diver swimming in scatters them.
		shoal.turn += (math.random() - 0.5) * dt * 1.5
		shoal.turn = math.clamp(shoal.turn, -0.6, 0.6)
		local away = shoal.center - diver
		if away.Magnitude < SCATTER_DISTANCE then
			shoal.heading = Vector3.new(away.X, away.Y * 0.3, away.Z).Unit
			shoal.scatter = 1.5
		else
			shoal.heading = (CFrame.Angles(0, shoal.turn * dt, 0) * shoal.heading).Unit
		end
		shoal.scatter = math.max(0, shoal.scatter - dt)
		local speed = shoal.speed * (1 + shoal.scatter * 1.5)
		local nextCenter = shoal.center + shoal.heading * speed * dt

		shoal.groundCheck -= dt
		if shoal.groundCheck <= 0 then
			shoal.groundCheck = 1
			shoal.ground = groundBelow(nextCenter)
		end
		local minY = (shoal.ground or -1e6) + 4
		local maxY = DepthUtils.SURFACE_Y - 3
		if nextCenter.Y < minY or nextCenter.Y > maxY then
			shoal.heading = Vector3.new(shoal.heading.X, (nextCenter.Y < minY) and 0.3 or -0.3, shoal.heading.Z).Unit
			nextCenter = Vector3.new(nextCenter.X, math.clamp(nextCenter.Y, minY, maxY), nextCenter.Z)
		end
		shoal.center = nextCenter

		local spread = 1 + shoal.scatter * 1.2
		for _, fish in ipairs(shoal.fish) do
			local wobble = Vector3.new(math.sin(now * 1.3 + fish.phase), math.sin(now * 0.9 + fish.phase * 2) * 0.5, math.cos(now * 1.1 + fish.phase))
			local position = shoal.center + fish.slot * spread + wobble
			local wiggle = math.sin(now * 12 + fish.phase) * 0.15
			fish.model:PivotTo(CFrame.lookAt(position, position + shoal.heading) * CFrame.Angles(0, wiggle, 0))
		end
	end
end)
