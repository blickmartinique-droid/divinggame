-- Small reef animals placed by the world builders (MarineFlora), brought
-- to life locally on each client -- purely cosmetic:
--   ReefFish  a clownfish hovering over its anemone (its Home attribute):
--             it circles and bobs just above the tentacles, wagging its
--             tail, and dives into the anemone when a diver comes close.
-- Parts keep their rest offsets from the fish's body; only fish near the
-- camera move, all in one BulkMoveTo.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")

local player = Players.LocalPlayer
local RANGE = 120
local REFRESH_INTERVAL = 1
local HIDE_DISTANCE = 7

type Rig = { parts: { { part: BasePart, offset: CFrame, tail: boolean } }, home: Vector3, phase: number, hide: number }

local rigs: { [Model]: Rig | false } = setmetatable({}, { __mode = "k" }) :: any
local nearby: { Model } = {}
local sinceRefresh = REFRESH_INTERVAL

local function rig(model: Model): Rig | false
	local body = model.PrimaryPart
	local home = model:GetAttribute("Home")
	if not body or typeof(home) ~= "Vector3" then
		return false
	end
	local parts = {}
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			table.insert(parts, { part = descendant, offset = body.CFrame:ToObjectSpace(descendant.CFrame), tail = descendant.Name == "Tail" })
		end
	end
	return { parts = parts, home = home, phase = tonumber(model:GetAttribute("Phase")) or 0, hide = 0 }
end

local function refresh()
	table.clear(nearby)
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local origin = camera.CFrame.Position
	for _, model in ipairs(CollectionService:GetTagged("ReefFish")) do
		local home = model:GetAttribute("Home")
		if model:IsA("Model") and model.Parent and typeof(home) == "Vector3" and (home - origin).Magnitude <= RANGE then
			if rigs[model] == nil then
				rigs[model] = rig(model)
			end
			if rigs[model] then
				table.insert(nearby, model)
			end
		end
	end
end

local function diverDistance(position: Vector3): number
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return root and root:IsA("BasePart") and (root.Position - position).Magnitude or math.huge
end

local moveParts: { BasePart } = {}
local moveFrames: { CFrame } = {}

-- Where the fish is at time t: a lazy, wobbling loop over the tentacles.
local function pathAt(r: Rig, t: number): Vector3
	local angle = t * 0.9 + r.phase
	local radius = 0.9 + 0.35 * math.sin(t * 0.37 + r.phase)
	return r.home + Vector3.new(math.cos(angle) * radius, 0.25 * math.sin(t * 1.7 + r.phase) - r.hide * 1.1, math.sin(angle) * radius)
end

RunService.Heartbeat:Connect(function(dt)
	sinceRefresh += dt
	if sinceRefresh >= REFRESH_INTERVAL then
		sinceRefresh = 0
		refresh()
	end
	if #nearby == 0 then
		return
	end
	local now = os.clock()
	table.clear(moveParts)
	table.clear(moveFrames)
	for _, model in ipairs(nearby) do
		local r = rigs[model]
		if r and model.Parent then
			-- Duck into the anemone while a diver is close, come out after.
			local target = diverDistance(r.home) < HIDE_DISTANCE and 1 or 0
			r.hide += (target - r.hide) * math.min(1, dt * (target > r.hide and 4 or 0.8))
			local position = pathAt(r, now)
			local ahead = pathAt(r, now + 0.15)
			local body = CFrame.lookAt(position, ahead + Vector3.new(0, 0.001, 0))
			local wag = CFrame.Angles(0, math.sin(now * 12 + r.phase) * 0.45, 0)
			for _, entry in ipairs(r.parts) do
				table.insert(moveParts, entry.part)
				table.insert(moveFrames, entry.tail and body * CFrame.new(0, 0, 0.45) * wag * CFrame.new(0, 0, -0.45) * entry.offset or body * entry.offset)
			end
		end
	end
	if #moveParts > 0 then
		Workspace:BulkMoveTo(moveParts, moveFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end
end)
