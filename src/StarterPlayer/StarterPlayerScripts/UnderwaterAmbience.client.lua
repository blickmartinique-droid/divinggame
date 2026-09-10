-- Ambient particles that give the water volume, attached to the player's
-- own HumanoidRootPart (a single world-anchored emitter can only be seen
-- near its own position and the ocean is 500m deep). Independent of the
-- swim-triggered bubbles/wake in SwimWaterEffects (not touched here).
--
-- Layers, each faded in by depth so the water changes character on the
-- way down instead of just getting darker:
--   * Sediment specks  -- everywhere underwater, the base "volume" cue.
--   * Background bubbles -- a trickle, strongest in the shallows.
--   * Marine snow -- slow-sinking pale flakes, from the mid-water down.
--   * Bioluminescence -- rare tiny cyan glows, only in the abyss.
-- All rates are scaled by the graphics level's ParticleScale, and pick up
-- a small drift bias toward any current the player is in (CurrentField,
-- the same value SwimController reads) so the water reads as moving too.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DepthUtils = require(ReplicatedStorage.Shared.Modules.DepthUtils)
local CurrentField = require(ReplicatedStorage.Shared.Modules.CurrentField)
local GraphicsQuality = require(ReplicatedStorage.Shared.Modules.GraphicsQuality)

local player = Players.LocalPlayer

local CHECK_INTERVAL = 0.4
local SEDIMENT_RATE = 5
local BUBBLE_RATE = 1.5
local SNOW_RATE = 6
local GLOW_RATE = 2.5
local BUBBLE_BASE_ACCELERATION = Vector3.new(0, 4, 0)
local SNOW_BASE_ACCELERATION = Vector3.new(0, -0.15, 0)
local CURRENT_DRIFT_SCALE = 0.5

local function volumeEmitter(name: string, rootPart: BasePart)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = name
	emitter.Rate = 0
	emitter.Shape = Enum.ParticleEmitterShape.Sphere
	emitter.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	emitter.Parent = rootPart
	return emitter
end

local function createEmitters(rootPart: BasePart)
	-- Emitters use their parent's size as their volume, which is tiny on
	-- HumanoidRootPart; a bigger invisible carrier welded to it gives them
	-- a real volume to spread through.
	local carrier = Instance.new("Part")
	carrier.Name = "AmbienceVolume"
	carrier.Size = Vector3.new(36, 24, 36)
	carrier.Transparency = 1
	carrier.CanCollide = false
	carrier.CanQuery = false
	carrier.CanTouch = false
	carrier.Massless = true
	carrier.CFrame = rootPart.CFrame
	carrier.Parent = rootPart
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = rootPart
	weld.Part1 = carrier
	weld.Parent = carrier

	local sediment = volumeEmitter("AmbientSediment", carrier)
	sediment.Lifetime = NumberRange.new(6, 10)
	sediment.Speed = NumberRange.new(0.05, 0.3)
	sediment.SpreadAngle = Vector2.new(180, 180)
	sediment.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.2, 0.11),
		NumberSequenceKeypoint.new(0.8, 0.11),
		NumberSequenceKeypoint.new(1, 0),
	})
	sediment.Transparency = NumberSequence.new(0.55)
	sediment.Color = ColorSequence.new(Color3.fromRGB(220, 225, 215))
	sediment.LightInfluence = 1

	local bubbles = volumeEmitter("AmbientBubbles", carrier)
	bubbles.Lifetime = NumberRange.new(2.5, 5)
	bubbles.Speed = NumberRange.new(0.5, 1.5)
	bubbles.SpreadAngle = Vector2.new(15, 15)
	bubbles.Acceleration = BUBBLE_BASE_ACCELERATION
	bubbles.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.06),
		NumberSequenceKeypoint.new(1, 0.14),
	})
	bubbles.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.5),
		NumberSequenceKeypoint.new(1, 1),
	})
	bubbles.Color = ColorSequence.new(Color3.new(1, 1, 1))
	bubbles.Rotation = NumberRange.new(0, 360)
	bubbles.RotSpeed = NumberRange.new(-60, 60)

	local snow = volumeEmitter("MarineSnow", carrier)
	snow.Lifetime = NumberRange.new(8, 14)
	snow.Speed = NumberRange.new(0.05, 0.2)
	snow.SpreadAngle = Vector2.new(180, 180)
	snow.Acceleration = SNOW_BASE_ACCELERATION
	snow.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.15, 0.16),
		NumberSequenceKeypoint.new(0.85, 0.16),
		NumberSequenceKeypoint.new(1, 0),
	})
	snow.Transparency = NumberSequence.new(0.35)
	snow.Color = ColorSequence.new(Color3.fromRGB(200, 215, 230))
	snow.LightEmission = 0.2
	snow.LightInfluence = 0.6
	snow.Rotation = NumberRange.new(0, 360)
	snow.RotSpeed = NumberRange.new(-20, 20)

	local glow = volumeEmitter("Bioluminescence", carrier)
	glow.Lifetime = NumberRange.new(3, 6)
	glow.Speed = NumberRange.new(0.05, 0.25)
	glow.SpreadAngle = Vector2.new(180, 180)
	glow.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.3, 0.18),
		NumberSequenceKeypoint.new(0.7, 0.12),
		NumberSequenceKeypoint.new(1, 0),
	})
	glow.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.3, 0.1),
		NumberSequenceKeypoint.new(0.7, 0.3),
		NumberSequenceKeypoint.new(1, 1),
	})
	glow.Color = ColorSequence.new(Color3.fromRGB(110, 230, 255), Color3.fromRGB(80, 160, 255))
	glow.LightEmission = 1
	glow.LightInfluence = 0
	glow.Brightness = 2

	return { sediment = sediment, bubbles = bubbles, snow = snow, glow = glow }
end

local function onCharacterAdded(character)
	local rootPart = character:WaitForChild("HumanoidRootPart")
	local emitters = createEmitters(rootPart)
	local accumulated = CHECK_INTERVAL

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

		local depth = DepthUtils.GetDepth(rootPart.Position)
		local scale = GraphicsQuality.Get().ParticleScale
		if depth <= 0 then
			scale = 0
		end

		local shallow = 1 - math.clamp((depth - 60) / 140, 0, 1)
		local mid = math.clamp((depth - 80) / 120, 0, 1)
		local abyss = math.clamp((depth - 360) / 80, 0, 1)

		emitters.sediment.Rate = SEDIMENT_RATE * scale
		emitters.bubbles.Rate = BUBBLE_RATE * shallow * scale
		emitters.snow.Rate = SNOW_RATE * mid * scale
		emitters.glow.Rate = GLOW_RATE * abyss * scale

		local currentDrift = CurrentField.GetVelocity() * CURRENT_DRIFT_SCALE
		emitters.sediment.Acceleration = currentDrift
		emitters.bubbles.Acceleration = BUBBLE_BASE_ACCELERATION + currentDrift
		emitters.snow.Acceleration = SNOW_BASE_ACCELERATION + currentDrift
		emitters.glow.Acceleration = currentDrift * 0.5
	end)
end

if player.Character then
	onCharacterAdded(player.Character)
end
player.CharacterAdded:Connect(onCharacterAdded)
