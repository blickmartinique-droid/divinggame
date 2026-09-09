-- Animates the spiralling strands of every circular current locally on each
-- client. The server (CurrentGenerator.server.lua) only places the strand
-- Parts once at their starting positions and describes the motion through
-- Attributes on the parent current; moving them here instead of on the
-- server means zero per-frame replication traffic (each server-side CFrame
-- write would otherwise be sent to every client, 20 times a second, per
-- strand, per vortex) and lets each client skip vortices it can't see.
-- Anchored server-owned parts can be moved client-side freely -- the change
-- stays local to this client, which is exactly what a cosmetic wants.
--
-- The motion itself (orbit + inward drift + respawn at the edge) is purely
-- visual and reads its pacing from the same CurrentFlowSpeed/CurrentSpin/
-- CurrentSpiralBias Attributes the push physics uses, so the visible spin
-- always matches the actual push direction and relative strength.

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local UPDATE_INTERVAL = 1 / 20
local CULL_REFRESH_INTERVAL = 1
local CULL_MARGIN = 350 -- studs beyond a vortex's radius at which it stops animating
local INNER_RADIUS_FRACTION = 0.12

local vortices = {} -- [part] = { center, radius, spin, angularSpeed, inwardSpeed, strands }
local active = {}

local function buildVortex(part: BasePart)
	local radius = part:GetAttribute("CurrentRadius") or 0
	local flowSpeed = part:GetAttribute("CurrentFlowSpeed") or 0
	local spiralBias = part:GetAttribute("CurrentSpiralBias") or 0.15
	local strandsFolder = part:FindFirstChild("VortexStrands")
	if radius <= 0 or not strandsFolder then
		return nil
	end

	local strands = {}
	for _, strand in ipairs(strandsFolder:GetChildren()) do
		if strand:IsA("BasePart") then
			local offset = strand.Position - part.Position
			table.insert(strands, {
				part = strand,
				angle = math.atan2(offset.Z, offset.X),
				radius = math.max(radius * INNER_RADIUS_FRACTION, Vector3.new(offset.X, 0, offset.Z).Magnitude),
				height = offset.Y,
				previousPosition = strand.Position,
			})
		end
	end

	return {
		center = part.Position,
		radius = radius,
		spin = part:GetAttribute("CurrentSpin") or 1,
		angularSpeed = math.max(0.15, flowSpeed / radius),
		inwardSpeed = math.max(0.4, flowSpeed * spiralBias),
		strands = strands,
	}
end

local function register(part: Instance)
	if part:IsA("BasePart") and part:GetAttribute("CurrentShape") == "Circular" then
		task.defer(function()
			-- Strands arrive as separate replicated children right after the
			-- part itself; defer so they're all present before we read them.
			vortices[part] = buildVortex(part)
		end)
	end
end

local function watchFolder(folder: Instance)
	for _, child in ipairs(folder:GetChildren()) do
		register(child)
	end
	folder.ChildAdded:Connect(register)
	folder.ChildRemoved:Connect(function(child)
		vortices[child] = nil
		active[child] = nil
	end)
end

local currentsFolder = Workspace:FindFirstChild("Currents")
if currentsFolder then
	watchFolder(currentsFolder)
else
	Workspace.ChildAdded:Connect(function(child)
		if child.Name == "Currents" and not currentsFolder then
			currentsFolder = child
			watchFolder(child)
		end
	end)
end

local function refreshActive()
	table.clear(active)
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local origin = camera.CFrame.Position
	for part, vortex in pairs(vortices) do
		if vortex and (origin - vortex.center).Magnitude <= vortex.radius + CULL_MARGIN then
			active[part] = vortex
		end
	end
end

local function stepStrand(vortex, strand, dt)
	strand.angle += vortex.angularSpeed * vortex.spin * dt
	strand.radius -= vortex.inwardSpeed * dt

	if strand.radius <= vortex.radius * INNER_RADIUS_FRACTION then
		strand.radius = vortex.radius
		strand.angle = math.random() * math.pi * 2
		strand.height = (math.random() - 0.5) * vortex.radius * 0.25
	end

	local position = vortex.center
		+ Vector3.new(math.cos(strand.angle) * strand.radius, strand.height, math.sin(strand.angle) * strand.radius)

	if (position - strand.previousPosition).Magnitude > 0.01 then
		strand.part.CFrame = CFrame.lookAt(strand.previousPosition, position)
	else
		strand.part.CFrame = CFrame.new(position)
	end
	strand.previousPosition = position
end

local sinceUpdate = 0
local sinceCull = CULL_REFRESH_INTERVAL

RunService.Heartbeat:Connect(function(deltaTime)
	sinceCull += deltaTime
	if sinceCull >= CULL_REFRESH_INTERVAL then
		sinceCull = 0
		refreshActive()
	end

	sinceUpdate += deltaTime
	if sinceUpdate < UPDATE_INTERVAL then
		return
	end
	local dt = sinceUpdate
	sinceUpdate = 0

	for _, vortex in pairs(active) do
		for _, strand in ipairs(vortex.strands) do
			stepStrand(vortex, strand, dt)
		end
	end
end)
