-- Shoals riding the currents, like turtles on the great ocean currents:
-- every Path current with a CurrentRiders attribute gets that many small
-- shoals travelling along it -- silver fish on the open-water highways,
-- blue glowing fish in the dark deep ones --, weaving round the centre
-- line at the current's pace, so the network is visibly alive and its
-- direction reads from afar. Client-only and cosmetic: anchored models
-- moved with PivotTo, and only the shoals near the camera move.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local CreatureBodies = require(ReplicatedStorage.Shared.Modules.CreatureBodies)
local GraphicsQuality = require(ReplicatedStorage.Shared.Modules.GraphicsQuality)

local ACTIVE_RANGE = 320
local FISH_BY_LEVEL = { High = 9, Medium = 6, Low = 3 }
local SPEED_SHARE = 0.7 -- the fish go a little slower than the water
local MAX_SPEED = 30

local folder = Instance.new("Folder")
folder.Name = "CurrentRiders"
folder.Parent = Workspace

local shoals = {}

local function pathOf(current: Instance)
	local points = {}
	for _, child in ipairs(current:GetChildren()) do
		if child:IsA("BasePart") and child.Name:match("^CurrentPoint") then
			table.insert(points, child)
		end
	end
	table.sort(points, function(a, b)
		return (tonumber(a.Name:match("(%d+)$")) or 0) < (tonumber(b.Name:match("(%d+)$")) or 0)
	end)
	local positions, lengths, total = {}, {}, 0
	for i, p in ipairs(points) do
		positions[i] = p.Position
		if i > 1 then
			total += (positions[i] - positions[i - 1]).Magnitude
		end
		lengths[i] = total
	end
	return positions, lengths, total
end

-- Position and direction at distance `d` along the polyline.
local function sample(positions, lengths, d: number): (Vector3, Vector3)
	for i = 2, #positions do
		if d <= lengths[i] or i == #positions then
			local span = math.max(lengths[i] - lengths[i - 1], 0.001)
			local t = math.clamp((d - lengths[i - 1]) / span, 0, 1)
			local a, b = positions[i - 1], positions[i]
			return a:Lerp(b, t), (b - a).Unit
		end
	end
	return positions[1], Vector3.new(0, 0, -1)
end

local function addShoals(current: Instance)
	local count = tonumber(current:GetAttribute("CurrentRiders")) or 0
	if count <= 0 or current:GetAttribute("CurrentShape") ~= "Path" then
		return
	end
	local positions, lengths, total = pathOf(current)
	if #positions < 2 or total < 10 then
		return
	end
	local closed = (positions[1] - positions[#positions]).Magnitude < 1
	local speed = math.min((tonumber(current:GetAttribute("CurrentMaxSpeed")) or 10) * SPEED_SHARE, MAX_SPEED)
	local width = (tonumber(current:GetAttribute("CurrentWidth")) or 12) * 0.45
	local deep = positions[1].Y < -250 or positions[#positions].Y < -250
	local fishCount = FISH_BY_LEVEL[GraphicsQuality.GetLevel()] or 6
	for k = 1, count do
		local shoal = {
			positions = positions,
			lengths = lengths,
			total = total,
			closed = closed,
			speed = speed * (0.85 + math.random() * 0.3),
			distance = total * (k - 1) / count + math.random() * 20,
			fish = {},
		}
		for f = 1, fishCount do
			local tint = deep and Color3.fromRGB(90, 170, 255) or Color3.fromRGB(196, 210, 220)
			local model = CreatureBodies.BuildSmallFish(1.4 + math.random() * 0.6, 1, tint, deep)
			model.Parent = folder
			table.insert(shoal.fish, {
				model = model,
				offset = Vector3.new((math.random() - 0.5) * width, (math.random() - 0.5) * width * 0.6, (math.random() - 0.5) * 6),
				phase = math.random() * math.pi * 2,
			})
		end
		table.insert(shoals, shoal)
	end
end

local currents = Workspace:WaitForChild("Currents", 60)
if currents then
	-- The server builds currents at startup; give it the WorldReady signal.
	while Workspace:GetAttribute("WorldReady") ~= true do
		task.wait(0.5)
	end
	for _, current in ipairs(currents:GetChildren()) do
		addShoals(current)
	end
end

local clock = 0
RunService.Heartbeat:Connect(function(dt)
	clock += dt
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local eye = camera.CFrame.Position
	for _, shoal in ipairs(shoals) do
		shoal.distance += shoal.speed * dt
		if shoal.distance > shoal.total then
			-- A loop goes round forever; a one-way current sends its riders
			-- back to the start, out of sight, to ride again.
			shoal.distance = shoal.closed and shoal.distance - shoal.total or 0
		end
		local head = sample(shoal.positions, shoal.lengths, shoal.distance)
		if (head - eye).Magnitude < ACTIVE_RANGE then
			for index, fish in ipairs(shoal.fish) do
				local d = shoal.distance - index * 1.2
				if d < 0 then
					d += shoal.closed and shoal.total or 0
				end
				local position, direction = sample(shoal.positions, shoal.lengths, math.max(d, 0))
				local side = direction:Cross(Vector3.new(0, 1, 0))
				side = side.Magnitude > 0.1 and side.Unit or Vector3.new(1, 0, 0)
				local up = side:Cross(direction).Unit
				local weave = math.sin(clock * 1.6 + fish.phase) * 1.2
				local at = position + side * (fish.offset.X + weave) + up * fish.offset.Y + direction * fish.offset.Z
				fish.model:PivotTo(CFrame.lookAt(at, at + direction + side * math.cos(clock * 1.6 + fish.phase) * 0.15))
			end
		end
	end
end)
