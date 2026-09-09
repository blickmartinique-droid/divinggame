-- Computes how much the underwater currents in Workspace.Currents push the
-- local player, and publishes the result through CurrentField for
-- SwimController to add into its own velocity. This script only reads
-- world data (the current marker Parts placed by CurrentGenerator.server.lua
-- and their Attributes) and does local vector math -- it never touches the
-- character, camera, or animations directly, and never writes to
-- AssemblyLinearVelocity or CFrame itself. SwimController remains the sole
-- owner of the character's actual movement and rotation; this just hands it
-- one extra velocity to fold in, the same way it already combines camera
-- input and manual vertical control.
--
-- Falloff at each current's edge uses a smoothstep (not a hard cutoff), so
-- crossing into or out of a current is gradual, and overlapping currents
-- just sum -- no special-casing needed for multiple zones affecting the
-- player at once. The combined result is also smoothed over time (the same
-- exponential-approach shape SwimController already uses for turning and
-- the rest pose), so it can never pop in a single frame even if the player
-- crosses a boundary quickly.
--
-- Each current's Attributes are cached once into a plain table when it
-- appears (and re-read on AttributeChanged, so live edits in Studio still
-- apply), and every current carries a bounding radius so the per-frame
-- loop is one cheap distance check per zone for everything the player is
-- nowhere near. Both keep the per-frame cost flat as the world gains
-- dozens of currents.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DepthUtils = require(ReplicatedStorage.Shared.Modules.DepthUtils)
local CurrentsConfig = require(ReplicatedStorage.Shared.Config.CurrentsConfig)
local CurrentField = require(ReplicatedStorage.Shared.Modules.CurrentField)

local player = Players.LocalPlayer

local RESPONSE_TIME = 1.2 -- seconds for the applied push to catch up to the freshly computed target

local function smoothstep(t)
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

-- Current registry ----------------------------------------------------------

local currents = {} -- [part] = cached data

local function readCurrent(part: BasePart)
	local shape = part:GetAttribute("CurrentShape")
	local data = {
		part = part,
		shape = shape,
		enabled = part:GetAttribute("CurrentEnabled") == true,
		flowSpeed = part:GetAttribute("CurrentFlowSpeed") or 0,
		canBoost = part:GetAttribute("CurrentCanBoost") == true,
		radius = part:GetAttribute("CurrentRadius") or 0,
		spin = part:GetAttribute("CurrentSpin") or 1,
		spiralBias = part:GetAttribute("CurrentSpiralBias") or 0,
		boundingRadius = 0,
	}

	if shape == "Circular" then
		data.boundingRadius = data.radius
	else
		data.boundingRadius = part.Size.Magnitude / 2
	end

	return data
end

local function registerCurrent(part: Instance)
	if not part:IsA("BasePart") or not part:GetAttribute("CurrentShape") then
		return
	end
	currents[part] = readCurrent(part)
	part.AttributeChanged:Connect(function()
		if currents[part] then
			currents[part] = readCurrent(part)
		end
	end)
end

local function watchCurrentsFolder(folder: Instance)
	for _, child in ipairs(folder:GetChildren()) do
		registerCurrent(child)
	end
	folder.ChildAdded:Connect(registerCurrent)
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

-- Directional: falloff from the marker's own local axes (Right/Up/Front =
-- width/height/length), so it only affects players actually within the
-- zone's box instead of an unrelated sphere around its center.
local function directionalInfluence(data, playerPosition)
	local part = data.part
	local localPoint = part.CFrame:PointToObjectSpace(playerPosition)
	local halfWidth = part.Size.X / 2
	local halfHeight = part.Size.Y / 2
	local halfLength = part.Size.Z / 2

	local widthFalloff = smoothstep(1 - math.abs(localPoint.X) / halfWidth)
	local heightFalloff = smoothstep(1 - math.abs(localPoint.Y) / halfHeight)
	local lengthFalloff = smoothstep(1 - math.abs(localPoint.Z) / halfLength)

	local falloff = widthFalloff * heightFalloff * lengthFalloff
	if falloff <= 0 then
		return nil, nil
	end

	return part.CFrame.LookVector, falloff
end

-- Circular: a vortex. The push direction is tangent to the circle at the
-- player's own position (rotated according to the current's spin) blended
-- with a small bias toward the center, for a spiral rather than a single
-- fixed push direction -- it depends on where around the vortex the player
-- actually is.
local function circularInfluence(data, playerPosition)
	local radius = data.radius
	if radius <= 0 then
		return nil, nil
	end

	local toPlayer = playerPosition - data.part.Position
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

-- Returns the summed push plus the single strongest contributing current
-- (and its falloff), which CurrentField exposes as the "dominant" one.
local function computeCurrentVelocity(playerPosition)
	local totalVelocity = Vector3.new()
	local dominant, dominantFalloff, dominantStrength = nil, 0, 0

	for part, data in pairs(currents) do
		if data.enabled and (playerPosition - part.Position).Magnitude <= data.boundingRadius then
			local direction, falloff
			if data.shape == "Directional" then
				direction, falloff = directionalInfluence(data, playerPosition)
			elseif data.shape == "Circular" then
				direction, falloff = circularInfluence(data, playerPosition)
			end

			if direction and falloff and falloff > 0 then
				local flowSpeed = data.flowSpeed
				if not data.canBoost then
					flowSpeed = math.min(flowSpeed, CurrentsConfig.NO_BOOST_CAP)
				end
				local strength = flowSpeed * falloff
				totalVelocity += direction * strength
				if strength > dominantStrength then
					dominant, dominantFalloff, dominantStrength = part, falloff, strength
				end
			end
		end
	end

	return totalVelocity, dominant, dominantFalloff
end

-- Per-player loop ---------------------------------------------------------------

local function onCharacterAdded(character)
	local rootPart = character:WaitForChild("HumanoidRootPart")
	local smoothedVelocity = Vector3.new()

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

		local alpha = 1 - math.exp(-(1 / RESPONSE_TIME) * deltaTime)
		smoothedVelocity = smoothedVelocity + (targetVelocity - smoothedVelocity) * alpha
		CurrentField.SetVelocity(smoothedVelocity)
		CurrentField.SetDominantCurrent(dominant, dominantFalloff)
	end)
end

if player.Character then
	onCharacterAdded(player.Character)
end
player.CharacterAdded:Connect(onCharacterAdded)
