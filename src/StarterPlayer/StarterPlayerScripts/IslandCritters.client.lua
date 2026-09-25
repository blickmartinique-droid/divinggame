-- Brings the island's animals to life, locally on each client (purely
-- cosmetic; the server only places them, see Builders/IslandLife):
--   Crab       scuttles sideways around its Home on the beach, pausing,
--              and runs off when a diver comes close
--   Seagull    circles high over the island, flapping then gliding
--   Butterfly  flutters around its flower
--   Parrot     turns its head on its perch
--   Dolphin    swims round the lagoon and leaps out of the water
--   Spin       turns in place (the lighthouse lamp and its beam)
-- Models are moved with their parts' rest offsets kept, wings flapped
-- about the body's axis. Nothing runs while the camera is far from the
-- island.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")

local player = Players.LocalPlayer
local ACTIVE_RADIUS = 450
local FLEE_DISTANCE = 9

local rigs = setmetatable({}, { __mode = "k" })

-- Rest offsets of every part relative to the model's primary part.
local function rig(model: Model)
	local cached = rigs[model]
	if cached then
		return cached
	end
	local primary = model.PrimaryPart
	if not primary then
		return nil
	end
	local parts = {}
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") then
			table.insert(parts, { part = p, offset = primary.CFrame:ToObjectSpace(p.CFrame), wing = string.sub(p.Name, 1, 4) == "Wing" and (string.find(p.Name, "Left") and -1 or 1) or nil })
		end
	end
	cached = { parts = parts, rest = primary.CFrame, state = {} }
	rigs[model] = cached
	return cached
end

local function place(r, base: CFrame, flap: number?)
	for _, entry in ipairs(r.parts) do
		if entry.wing and flap then
			entry.part.CFrame = base * CFrame.Angles(0, 0, entry.wing * flap) * entry.offset
		else
			entry.part.CFrame = base * entry.offset
		end
	end
end

local function nearestDiver(position: Vector3): number
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return root and (root.Position - position).Magnitude or math.huge
end

local function crab(model: Model, r, t: number, dt: number)
	local s = r.state
	local home = model:GetAttribute("Home") or r.rest.Position
	local range = model:GetAttribute("Range") or 5
	local speed = model:GetAttribute("Speed") or 3
	s.position = s.position or r.rest.Position
	s.wait = (s.wait or 0) - dt
	local away = nearestDiver(s.position)
	if away < FLEE_DISTANCE then
		-- Scuttle straight away from the diver, fast.
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root then
			local flee = Vector3.new(s.position.X - root.Position.X, 0, s.position.Z - root.Position.Z)
			if flee.Magnitude > 0.01 then
				s.target = s.position + flee.Unit * 6
				s.wait = 0
			end
		end
	end
	if not s.target or s.wait > 0 then
		if s.wait <= 0 then
			local a = math.random() * math.pi * 2
			s.target = Vector3.new(home.X + math.cos(a) * range * math.random(), s.position.Y, home.Z + math.sin(a) * range * math.random())
		end
	end
	local toTarget = s.target and (s.target - s.position) or Vector3.zero
	local moving = toTarget.Magnitude > 0.2 and s.wait <= 0
	if moving then
		local stepLength = math.min(toTarget.Magnitude, speed * (away < FLEE_DISTANCE and 2.5 or 1) * dt)
		s.position += toTarget.Unit * stepLength
		s.heading = toTarget.Unit
	elseif s.target and toTarget.Magnitude <= 0.2 then
		s.target = nil
		s.wait = 0.8 + math.random() * 2.5
	end
	-- Crabs walk sideways: their X axis follows the way they go.
	local heading = s.heading or Vector3.new(1, 0, 0)
	local facing = Vector3.new(-heading.Z, 0, heading.X)
	local wobble = moving and math.sin(t * 30) * 0.05 or 0
	local base = CFrame.lookAt(s.position, s.position + facing) * CFrame.Angles(0, 0, wobble)
	place(r, base)
end

local function seagull(model: Model, r, t: number)
	local center = model:GetAttribute("Center") or Vector3.zero
	local radius = model:GetAttribute("Radius") or 50
	local height = model:GetAttribute("Height") or 35
	local speed = model:GetAttribute("Speed") or 0.3
	local phase = model:GetAttribute("Phase") or 0
	local a = phase + t * speed
	local position = center + Vector3.new(math.cos(a) * radius, height + math.sin(t * 0.7 + phase) * 3, math.sin(a) * radius)
	local tangent = Vector3.new(-math.sin(a), 0, math.cos(a))
	local base = CFrame.lookAt(position, position + tangent) * CFrame.Angles(0, 0, -0.25)
	-- Bursts of flapping between long glides.
	local flapping = math.sin(t * 0.6 + phase) > 0.35
	local flap = flapping and math.sin(t * 9) * 0.55 or 0.08
	place(r, base, flap)
end

local function butterfly(model: Model, r, t: number)
	local home = model:GetAttribute("Home") or r.rest.Position
	local phase = model:GetAttribute("Phase") or 0
	local position = home + Vector3.new(math.sin(t * 1.3 + phase) * 1.6, 1 + math.sin(t * 2.1 + phase) * 0.6, math.cos(t * 0.9 + phase) * 1.6)
	local velocity = Vector3.new(math.cos(t * 1.3 + phase) * 1.3, 0, -math.sin(t * 0.9 + phase) * 0.9)
	local base = CFrame.lookAt(position, position + (velocity.Magnitude > 0.01 and velocity or Vector3.new(0, 0, -1)))
	place(r, base, math.sin(t * 22 + phase) * 0.9)
end

local function parrot(model: Model, r, t: number)
	local phase = model:GetAttribute("Phase") or 0
	local turn = math.sin(t * 0.5 + phase) * 0.5 + math.sin(t * 1.7 + phase) * 0.1
	place(r, r.rest * CFrame.Angles(0, turn, 0))
end

local function dolphin(model: Model, r, t: number)
	local center = model:GetAttribute("Center") or Vector3.zero
	local radius = model:GetAttribute("Radius") or 150
	local speed = model:GetAttribute("Speed") or 0.08
	local phase = model:GetAttribute("Phase") or 0
	local a = phase + t * speed
	-- Three leaps per lap, each over a short stretch of the circle.
	local lap = (a / (math.pi * 2) * 3) % 1
	local leap = lap < 0.12 and math.sin(lap / 0.12 * math.pi) or 0
	local rising = lap < 0.12 and math.cos(lap / 0.12 * math.pi) or 0
	local y = -3.2 + leap * 7 + math.sin(t * 2 + phase) * 0.2
	local position = center + Vector3.new(math.cos(a) * radius, y, math.sin(a) * radius)
	local tangent = Vector3.new(-math.sin(a), 0, math.cos(a))
	local pitch = rising * 0.9
	local base = CFrame.lookAt(position, position + tangent) * CFrame.Angles(pitch, 0, 0)
	place(r, base)
end

local HANDLERS = { Crab = crab, Seagull = seagull, Butterfly = butterfly, Parrot = parrot, Dolphin = dolphin }

local clock = 0
RunService.Heartbeat:Connect(function(dt)
	clock += dt
	local camera = Workspace.CurrentCamera
	if not camera or camera.CFrame.Position.Magnitude > ACTIVE_RADIUS + 200 then
		return
	end
	for tag, handler in pairs(HANDLERS) do
		for _, model in ipairs(CollectionService:GetTagged(tag)) do
			if model:IsA("Model") and model.Parent then
				local r = rig(model)
				if r then
					handler(model, r, clock, dt)
				end
			end
		end
	end
	for _, spinner in ipairs(CollectionService:GetTagged("Spin")) do
		if spinner:IsA("BasePart") then
			local rest = spinner:GetAttribute("RestPosition")
			if not rest then
				rest = spinner.Position
				spinner:SetAttribute("RestPosition", rest)
			end
			spinner.CFrame = CFrame.new(rest) * CFrame.Angles(0, clock * (spinner:GetAttribute("SpinSpeed") or 1), 0)
		end
	end
end)
