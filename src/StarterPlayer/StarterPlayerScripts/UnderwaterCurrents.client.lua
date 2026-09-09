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

-- Directional: falloff from the marker's own local axes (Right/Up/Front =
-- width/height/length), so it only affects players actually within the
-- zone's box instead of an unrelated sphere around its center.
local function directionalInfluence(part, playerPosition)
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
local function circularInfluence(part, playerPosition)
	local radius = part:GetAttribute("CurrentRadius")
	if not radius or radius <= 0 then
		return nil, nil
	end

	local toPlayer = playerPosition - part.Position
	local flat = Vector3.new(toPlayer.X, 0, toPlayer.Z)
	local distance = flat.Magnitude
	if distance < 0.01 or distance > radius then
		return nil, nil
	end

	local falloff = smoothstep(1 - distance / radius)
	if falloff <= 0 then
		return nil, nil
	end

	local spin = part:GetAttribute("CurrentSpin") or 1
	local spiralBias = part:GetAttribute("CurrentSpiralBias") or 0

	local radial = flat.Unit
	local tangent = Vector3.new(-radial.Z, 0, radial.X) * spin
	local direction = tangent - radial * spiralBias
	if direction.Magnitude > 0.01 then
		direction = direction.Unit
	end

	return direction, falloff
end

local function computeCurrentVelocity(playerPosition)
	local currentsFolder = Workspace:FindFirstChild("Currents")
	if not currentsFolder then
		return Vector3.new()
	end

	local totalVelocity = Vector3.new()

	for _, part in ipairs(currentsFolder:GetChildren()) do
		if part:IsA("BasePart") and part:GetAttribute("CurrentEnabled") then
			local shape = part:GetAttribute("CurrentShape")
			local direction, falloff

			if shape == "Directional" then
				direction, falloff = directionalInfluence(part, playerPosition)
			elseif shape == "Circular" then
				direction, falloff = circularInfluence(part, playerPosition)
			end

			if direction and falloff and falloff > 0 then
				local flowSpeed = part:GetAttribute("CurrentFlowSpeed") or 0
				if not part:GetAttribute("CurrentCanBoost") then
					flowSpeed = math.min(flowSpeed, CurrentsConfig.NO_BOOST_CAP)
				end
				totalVelocity += direction * flowSpeed * falloff
			end
		end
	end

	return totalVelocity
end

local function onCharacterAdded(character)
	local rootPart = character:WaitForChild("HumanoidRootPart")
	local smoothedVelocity = Vector3.new()

	local connection
	connection = RunService.Heartbeat:Connect(function(deltaTime)
		if not character.Parent then
			connection:Disconnect()
			CurrentField.SetVelocity(Vector3.new())
			return
		end

		local targetVelocity = Vector3.new()
		if DepthUtils.GetDepth(rootPart.Position) > 0 then
			targetVelocity = computeCurrentVelocity(rootPart.Position)
		end

		local alpha = 1 - math.exp(-(1 / RESPONSE_TIME) * deltaTime)
		smoothedVelocity = smoothedVelocity + (targetVelocity - smoothedVelocity) * alpha
		CurrentField.SetVelocity(smoothedVelocity)
	end)
end

if player.Character then
	onCharacterAdded(player.Character)
end
player.CharacterAdded:Connect(onCharacterAdded)
