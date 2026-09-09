-- Very subtle ambient underwater particles: drifting sediment specks and a
-- trickle of background bubbles, independent of the swim-triggered hand
-- trail/bubbles in SwimController (not touched here). Attached to the
-- player's own HumanoidRootPart -- necessary despite generally avoiding
-- per-player effects, since a single world-anchored emitter can only be
-- seen near its own position and the ocean is 500m deep; without this, the
-- water has zero ambiance anywhere except right next to the beach. Kept
-- deliberately low-rate (a handful of particles at most) so it stays cheap
-- and doesn't clutter the screen.
--
-- When the player is inside an underwater current, these particles pick up
-- a small drift bias toward it (via CurrentField, the same value
-- SwimController reads to push the player) so the surrounding water reads
-- as moving too, not just the player -- scaled well down from the actual
-- push so it stays a background detail.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DepthUtils = require(ReplicatedStorage.Shared.Modules.DepthUtils)
local CurrentField = require(ReplicatedStorage.Shared.Modules.CurrentField)

local player = Players.LocalPlayer

local CHECK_INTERVAL = 0.5
local SEDIMENT_RATE = 4
local BUBBLE_RATE = 1.5
local BUBBLE_BASE_ACCELERATION = Vector3.new(0, 4, 0)
local CURRENT_DRIFT_SCALE = 0.5

local function createSedimentEmitter(rootPart)
	local sediment = Instance.new("ParticleEmitter")
	sediment.Name = "AmbientSediment"
	sediment.Rate = 0
	sediment.Lifetime = NumberRange.new(6, 10)
	sediment.Speed = NumberRange.new(0.1, 0.4)
	sediment.SpreadAngle = Vector2.new(180, 180)
	sediment.Size = NumberSequence.new(0.12)
	sediment.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.7),
		NumberSequenceKeypoint.new(0.5, 0.6),
		NumberSequenceKeypoint.new(1, 1),
	})
	sediment.Color = ColorSequence.new(Color3.fromRGB(215, 210, 190))
	sediment.LightInfluence = 1
	sediment.Parent = rootPart
	return sediment
end

local function createBubbleEmitter(rootPart)
	local bubbles = Instance.new("ParticleEmitter")
	bubbles.Name = "AmbientBubbles"
	bubbles.Rate = 0
	bubbles.Lifetime = NumberRange.new(2, 4)
	bubbles.Speed = NumberRange.new(1, 2)
	bubbles.SpreadAngle = Vector2.new(15, 15)
	bubbles.Acceleration = BUBBLE_BASE_ACCELERATION
	bubbles.Size = NumberSequence.new(0.1)
	bubbles.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.5),
		NumberSequenceKeypoint.new(1, 1),
	})
	bubbles.Color = ColorSequence.new(Color3.new(1, 1, 1))
	bubbles.Parent = rootPart
	return bubbles
end

local function onCharacterAdded(character)
	local rootPart = character:WaitForChild("HumanoidRootPart")
	local sediment = createSedimentEmitter(rootPart)
	local bubbles = createBubbleEmitter(rootPart)
	local isActive = false
	local accumulated = 0

	local connection
	connection = RunService.Heartbeat:Connect(function(deltaTime)
		if not character.Parent then
			connection:Disconnect()
			return
		end

		accumulated += deltaTime
		if accumulated < CHECK_INTERVAL then
			return
		end
		accumulated = 0

		local underwater = DepthUtils.GetDepth(rootPart.Position) > 0
		if underwater ~= isActive then
			isActive = underwater
			sediment.Rate = isActive and SEDIMENT_RATE or 0
			bubbles.Rate = isActive and BUBBLE_RATE or 0
		end

		-- Subtle drift bias toward any current the player is currently in
		-- (zero when there isn't one), so the water around the player
		-- reads as moving too.
		local currentDrift = CurrentField.GetVelocity() * CURRENT_DRIFT_SCALE
		sediment.Acceleration = currentDrift
		bubbles.Acceleration = BUBBLE_BASE_ACCELERATION + currentDrift
	end)
end

if player.Character then
	onCharacterAdded(player.Character)
end
player.CharacterAdded:Connect(onCharacterAdded)
