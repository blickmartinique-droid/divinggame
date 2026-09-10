-- Computes how much the underwater currents in Workspace.Currents push the
-- local player, and publishes the result through CurrentField for
-- SwimController to add into its own velocity. This script only reads
-- world data (the current instances and their Attributes, see
-- CurrentsConfig.lua) and does local vector math -- it never touches the
-- character, camera, or animations directly, and never writes to
-- AssemblyLinearVelocity or CFrame itself. SwimController remains the sole
-- owner of the character's actual movement and rotation; this just hands it
-- one extra velocity to fold in, the same way it already combines camera
-- input and manual vertical control.
--
-- Feel: the push never jumps. Spatially, every shape fades in from its
-- edge with a smoothstep; temporally, the applied speed ramps toward the
-- target at the dominant current's CurrentAcceleration when growing and
-- at its CurrentExitDeceleration when shrinking (rate-limited, so entering
-- a fast lane is a genuine build-up and leaving one a genuine coast-down),
-- and the applied direction turns toward the local flow direction over
-- DirectionResponseTime, so path bends carry the player round instead of
-- kinking. Each shape also steers slightly back toward its own center line
-- (CurrentCentering), which is what makes a path "carry" a swimmer along
-- it rather than letting them drift out the side.
--
-- Overlapping currents sum; the sum is clamped to a little above the
-- strongest contributor's MaxSpeed (and ABSOLUTE_MAX_SPEED) so stacking
-- can never run away. Upward push is dropped within a few studs of the
-- surface so no current can fling the player out of the water.
--
-- Currents are cached into plain tables on registration (re-read on
-- AttributeChanged so Studio edits apply live) and rejected per frame by a
-- single bounding-sphere check, so cost stays flat as the world fills up.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DepthUtils = require(ReplicatedStorage.Shared.Modules.DepthUtils)
local CurrentsConfig = require(ReplicatedStorage.Shared.Config.CurrentsConfig)
local CurrentField = require(ReplicatedStorage.Shared.Modules.CurrentField)

local player = Players.LocalPlayer

local SURFACE_GUARD = 3 -- studs below the surface where upward push is dropped
local STACK_HEADROOM = 1.15
-- The sideways "back to the center line" steer is capped in absolute studs/s
-- (not just as a fraction of MaxSpeed) so even a fast lane can always be
-- swum out of sideways at normal swim speed -- it guides, never traps.
local MAX_CENTERING_SPEED = 6

-- Blends a centering pull into the flow direction, with the cap above.
local function steerTowardCenter(direction: Vector3, pull: Vector3, centering: number, offsetFraction: number, maxSpeed: number)
	local k = math.min(centering * offsetFraction, MAX_CENTERING_SPEED / math.max(maxSpeed, 0.01))
	if k <= 0.001 then
		return direction
	end
	return (direction + pull * k).Unit
end

local function smoothstep(t)
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

local function moveToward(value: number, target: number, maxDelta: number): number
	if math.abs(target - value) <= maxDelta then
		return target
	end
	return value + math.sign(target - value) * maxDelta
end

-- Current registry ----------------------------------------------------------

local currents = {} -- [instance] = cached data

local function getPathPoints(container: Instance): { BasePart }
	local points = {}
	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("BasePart") and child.Name:match("^CurrentPoint") then
			table.insert(points, child)
		end
	end
	table.sort(points, function(a, b)
		return a.Name < b.Name
	end)
	return points
end

local function readCurrent(instance: Instance)
	local tier = CurrentsConfig.Tiers[instance:GetAttribute("CurrentTier")] or CurrentsConfig.Tiers.Medium
	-- Explicit nil check: a missing CanBoost must fall back to the tier, and
	-- `attr == true` would silently turn "not set yet" into "capped".
	local canBoost = instance:GetAttribute("CurrentCanBoost")
	if canBoost == nil then
		canBoost = tier.CanBoost
	end
	local data = {
		instance = instance,
		shape = instance:GetAttribute("CurrentShape"),
		enabled = instance:GetAttribute("CurrentEnabled") ~= false,
		maxSpeed = instance:GetAttribute("CurrentMaxSpeed") or instance:GetAttribute("CurrentFlowSpeed") or tier.MaxSpeed,
		acceleration = instance:GetAttribute("CurrentAcceleration") or tier.Acceleration,
		exitDeceleration = instance:GetAttribute("CurrentExitDeceleration") or tier.ExitDeceleration,
		centering = instance:GetAttribute("CurrentCentering") or tier.Centering,
		canBoost = canBoost == true,
		radius = instance:GetAttribute("CurrentRadius") or 0,
		spin = instance:GetAttribute("CurrentSpin") or 1,
		spiralBias = instance:GetAttribute("CurrentSpiralBias") or 0,
		width = instance:GetAttribute("CurrentWidth") or 12,
		center = Vector3.new(),
		boundingRadius = 0,
		segments = nil,
	}

	if data.shape == "Path" then
		local points = getPathPoints(instance)
		local segments = {}
		local sum = Vector3.new()
		for i = 1, #points - 1 do
			local a, b = points[i].Position, points[i + 1].Position
			local length = (b - a).Magnitude
			if length > 0.01 then
				table.insert(segments, { a = a, b = b, dir = (b - a) / length, length = length })
			end
		end
		for _, point in ipairs(points) do
			sum += point.Position
		end
		if #points > 0 then
			data.center = sum / #points
		end
		local farthest = 0
		for _, point in ipairs(points) do
			farthest = math.max(farthest, (point.Position - data.center).Magnitude)
		end
		data.boundingRadius = farthest + data.width
		data.segments = segments
		data.enabled = data.enabled and #segments > 0
	elseif instance:IsA("BasePart") then
		data.center = instance.Position
		if data.shape == "Circular" then
			data.boundingRadius = data.radius
		else
			data.boundingRadius = instance.Size.Magnitude / 2
		end
	else
		data.enabled = false
	end

	return data
end

local function registerCurrent(instance: Instance)
	if not instance:GetAttribute("CurrentShape") then
		return
	end
	currents[instance] = readCurrent(instance)
	instance.AttributeChanged:Connect(function()
		if currents[instance] then
			currents[instance] = readCurrent(instance)
		end
	end)
	if instance:GetAttribute("CurrentShape") == "Path" then
		-- Points replicate as separate children right after the model.
		instance.ChildAdded:Connect(function()
			if currents[instance] then
				currents[instance] = readCurrent(instance)
			end
		end)
	end
end

local function watchCurrentsFolder(folder: Instance)
	for _, child in ipairs(folder:GetChildren()) do
		registerCurrent(child)
	end
	folder.ChildAdded:Connect(function(child)
		task.defer(registerCurrent, child)
	end)
	folder.ChildRemoved:Connect(function(child)
		currents[child] = nil
	end)
end

local currentsFolder = Workspace:FindFirstChild("Currents")
if currentsFolder then
	watchCurrentsFolder(currentsFolder)
else
	Workspace.ChildAdded:Connect(function(child)
		if child.Name == "Currents" and not currentsFolder then
			currentsFolder = child
			watchCurrentsFolder(child)
		end
	end)
end

-- Influence shapes ------------------------------------------------------------
-- Each returns (direction, falloff 0-1) or nil.

local function directionalInfluence(data, playerPosition)
	local part = data.instance
	local localPoint = part.CFrame:PointToObjectSpace(playerPosition)
	local halfWidth = part.Size.X / 2
	local halfHeight = part.Size.Y / 2
	local halfLength = part.Size.Z / 2

	local falloff = smoothstep(1 - math.abs(localPoint.X) / halfWidth)
		* smoothstep(1 - math.abs(localPoint.Y) / halfHeight)
		* smoothstep(1 - math.abs(localPoint.Z) / halfLength)
	if falloff <= 0 then
		return nil, nil
	end

	local direction = part.CFrame.LookVector
	local offsetFraction = math.clamp(math.sqrt((localPoint.X / halfWidth) ^ 2 + (localPoint.Y / halfHeight) ^ 2), 0, 1)
	if data.centering > 0 and offsetFraction > 0.01 then
		local pull = -(part.CFrame.RightVector * localPoint.X + part.CFrame.UpVector * localPoint.Y)
		direction = steerTowardCenter(direction, pull.Unit, data.centering, offsetFraction, data.maxSpeed)
	end
	return direction, falloff
end

local function circularInfluence(data, playerPosition)
	local radius = data.radius
	if radius <= 0 then
		return nil, nil
	end

	local toPlayer = playerPosition - data.center
	local flat = Vector3.new(toPlayer.X, 0, toPlayer.Z)
	local distance = flat.Magnitude
	if distance < 0.01 or distance > radius then
		return nil, nil
	end

	local falloff = smoothstep(1 - distance / radius)
	if falloff <= 0 then
		return nil, nil
	end

	local radial = flat.Unit
	local tangent = Vector3.new(-radial.Z, 0, radial.X) * data.spin
	local direction = tangent - radial * data.spiralBias
	if direction.Magnitude > 0.01 then
		direction = direction.Unit
	end
	return direction, falloff
end

-- Closest point on the polyline; tangent blends between neighbouring legs
-- across each node (50/50 exactly at the node) so bends are rounded.
local function pathInfluence(data, playerPosition)
	local segments = data.segments
	local bestIndex, bestT, bestDistance, bestPoint = nil, 0, math.huge, nil
	for index, segment in ipairs(segments) do
		local t = math.clamp((playerPosition - segment.a):Dot(segment.dir) / segment.length, 0, 1)
		local point = segment.a + segment.dir * (t * segment.length)
		local distance = (playerPosition - point).Magnitude
		if distance < bestDistance then
			bestIndex, bestT, bestDistance, bestPoint = index, t, distance, point
		end
	end
	if not bestIndex or bestDistance >= data.width then
		return nil, nil
	end

	local falloff = smoothstep(1 - bestDistance / data.width)
	local tangent = segments[bestIndex].dir
	if bestT > 0.5 and segments[bestIndex + 1] then
		tangent = tangent:Lerp(segments[bestIndex + 1].dir, bestT - 0.5)
	elseif bestT < 0.5 and segments[bestIndex - 1] then
		tangent = tangent:Lerp(segments[bestIndex - 1].dir, 0.5 - bestT)
	end
	if tangent.Magnitude < 0.01 then
		tangent = segments[bestIndex].dir
	end

	local direction = tangent.Unit
	if data.centering > 0 and bestDistance > 0.01 then
		local pull = (bestPoint - playerPosition).Unit
		direction = steerTowardCenter(direction, pull, data.centering, bestDistance / data.width, data.maxSpeed)
	end
	return direction, falloff
end

-- Returns the summed push, the strongest contributing current's data and
-- its falloff (exposed by CurrentField as the "dominant" current).
local function computeCurrentVelocity(playerPosition)
	local totalVelocity = Vector3.new()
	local dominant, dominantFalloff, dominantStrength = nil, 0, 0
	local strongestMaxSpeed = 0

	for _, data in pairs(currents) do
		if data.enabled and (playerPosition - data.center).Magnitude <= data.boundingRadius then
			local direction, falloff
			if data.shape == "Directional" then
				direction, falloff = directionalInfluence(data, playerPosition)
			elseif data.shape == "Circular" then
				direction, falloff = circularInfluence(data, playerPosition)
			elseif data.shape == "Path" then
				direction, falloff = pathInfluence(data, playerPosition)
			end

			if direction and falloff and falloff > 0 then
				local maxSpeed = data.maxSpeed
				if not data.canBoost then
					maxSpeed = math.min(maxSpeed, CurrentsConfig.NO_BOOST_CAP)
				end
				local strength = maxSpeed * falloff
				totalVelocity += direction * strength
				strongestMaxSpeed = math.max(strongestMaxSpeed, maxSpeed)
				if strength > dominantStrength then
					dominant, dominantFalloff, dominantStrength = data, falloff, strength
				end
			end
		end
	end

	local cap = math.min(strongestMaxSpeed * STACK_HEADROOM, CurrentsConfig.ABSOLUTE_MAX_SPEED)
	if totalVelocity.Magnitude > cap and cap > 0 then
		totalVelocity = totalVelocity.Unit * cap
	end

	return totalVelocity, dominant, dominantFalloff
end

-- Per-player loop ---------------------------------------------------------------

local function onCharacterAdded(character)
	local rootPart = character:WaitForChild("HumanoidRootPart")
	local appliedSpeed = 0
	local appliedDirection = Vector3.new(0, 0, -1)
	local exitDeceleration = CurrentsConfig.DefaultExitDeceleration

	local connection
	connection = RunService.Heartbeat:Connect(function(deltaTime)
		if not character.Parent then
			connection:Disconnect()
			CurrentField.SetVelocity(Vector3.new())
			CurrentField.SetDominantCurrent(nil, 0)
			return
		end

		local targetVelocity = Vector3.new()
		local dominant, dominantFalloff = nil, 0
		if DepthUtils.GetDepth(rootPart.Position) > 0 then
			targetVelocity, dominant, dominantFalloff = computeCurrentVelocity(rootPart.Position)
		end

		local targetSpeed = targetVelocity.Magnitude
		local acceleration = CurrentsConfig.DefaultExitDeceleration
		if dominant then
			acceleration = dominant.acceleration
			exitDeceleration = dominant.exitDeceleration
		end

		if targetSpeed > 0.01 then
			local alpha = 1 - math.exp(-deltaTime / CurrentsConfig.DirectionResponseTime)
			local blended = appliedDirection + (targetVelocity / targetSpeed - appliedDirection) * alpha
			appliedDirection = blended.Magnitude > 0.01 and blended.Unit or targetVelocity / targetSpeed
		end

		local rate = targetSpeed > appliedSpeed and acceleration or exitDeceleration
		appliedSpeed = moveToward(appliedSpeed, targetSpeed, rate * deltaTime)

		local velocity = appliedDirection * appliedSpeed
		if velocity.Y > 0 and rootPart.Position.Y > DepthUtils.SURFACE_Y - SURFACE_GUARD then
			velocity = Vector3.new(velocity.X, 0, velocity.Z)
		end

		CurrentField.SetVelocity(velocity)
		CurrentField.SetDominantCurrent(dominant and dominant.instance or nil, dominantFalloff)
	end)
end

if player.Character then
	onCharacterAdded(player.Character)
end
player.CharacterAdded:Connect(onCharacterAdded)
