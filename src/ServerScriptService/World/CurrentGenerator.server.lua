-- Places underwater current zones: an invisible gameplay marker (read every
-- frame by UnderwaterCurrents.client.lua to push the local player) plus its
-- visible particle flow, built here server-side so it replicates once to
-- every client instead of each client building its own copy -- the same
-- pattern OceanGenerator already uses for shore foam and whitecaps.
--
-- Two shapes:
--   Directional -- a straight flow through open water or a corridor.
--     Particles drift the whole length of the zone along one fixed
--     direction (the marker part's own orientation).
--   Circular -- a vortex. A ring of small bubble emitters continuously
--     orbits the center (with a slight inward spiral), suited to sit near
--     a wreck, cave mouth, or other landmark.
--
-- Currents are plain Parts with Attributes (shape, flow speed, tier,
-- enabled, canBoost, size/radius) rather than a ModuleScript registry, so
-- they show up and stay editable directly in the Studio Explorer --
-- duplicate one and tweak its Attributes (or reposition/reorient it) to
-- add more without touching this script at all.
--
-- Only a handful of example currents are placed below, each commented with
-- what it demonstrates -- this is not meant to populate the whole ocean,
-- matching the rest of the map at this stage (see OceanGenerator's own
-- notes on why zone interiors are left simple for now).

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CurrentsConfig = require(ReplicatedStorage.Shared.Config.CurrentsConfig)

local existing = Workspace:FindFirstChild("Currents")
if existing then
	existing:Destroy()
end

local currentsFolder = Instance.new("Folder")
currentsFolder.Name = "Currents"
currentsFolder.Parent = Workspace

-- Shared look: translucent, cool-toned motes and bubbles rather than
-- anything glowing or saturated, so it reads as moving water rather than a
-- magic effect, a UI marker, or a flat floating texture. No custom
-- textures are used anywhere here -- every other particle effect in this
-- project relies on the default ParticleEmitter look for the same reason
-- (no asset-permission risk, proven to already work).
local FLOW_COLOR = Color3.fromRGB(205, 230, 235)
local BUBBLE_COLOR = Color3.new(1, 1, 1)

local function applyCommonAttributes(part, tierName, tier, overrides)
	overrides = overrides or {}

	-- Explicit if/else for CanBoost rather than `overrides.CanBoost or
	-- tier.CanBoost`: that idiom silently falls through to the tier default
	-- whenever an override deliberately sets CanBoost = false, since false
	-- is itself falsy in Lua.
	local canBoost
	if overrides.CanBoost ~= nil then
		canBoost = overrides.CanBoost
	else
		canBoost = tier.CanBoost
	end

	part:SetAttribute("CurrentTier", tierName)
	part:SetAttribute("CurrentEnabled", overrides.Enabled ~= false)
	part:SetAttribute("CurrentFlowSpeed", overrides.FlowSpeed or tier.FlowSpeed)
	part:SetAttribute("CurrentCanBoost", canBoost)
	part:SetAttribute("CurrentVisualIntensity", overrides.VisualIntensity or tier.VisualIntensity)
end

-- Directional current -------------------------------------------------------

-- props: Name, Position (Vector3, center), Direction (Vector3 -- may include
-- a vertical component, e.g. to draw the player gradually down toward a
-- deeper area), Length, Width, Height, Tier ("Weak"/"Medium"/"Strong"),
-- plus optional overrides (Enabled, FlowSpeed, CanBoost, VisualIntensity).
local function createDirectionalCurrent(props)
	local tier = CurrentsConfig.Tiers[props.Tier]
	local direction = props.Direction
	if direction.Magnitude < 0.01 then
		direction = Vector3.new(0, 0, -1)
	else
		direction = direction.Unit
	end

	local part = Instance.new("Part")
	part.Name = props.Name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.Transparency = 1
	part.Size = Vector3.new(props.Width, props.Height, props.Length)
	-- CFrame.lookAt orients the part so its LookVector (Front, the emission
	-- direction below) matches the current's flow direction -- the part's
	-- own orientation IS the current's direction, no separate attribute
	-- needed for it. lookAt's LookVector points from eye toward target, so
	-- the target must be ahead of the position along direction (position +
	-- direction), not behind it.
	part.CFrame = CFrame.lookAt(props.Position, props.Position + direction)
	part:SetAttribute("CurrentShape", "Directional")
	applyCommonAttributes(part, props.Tier, tier, props)
	part.Parent = currentsFolder

	local intensity = part:GetAttribute("CurrentVisualIntensity")
	local flowSpeed = part:GetAttribute("CurrentFlowSpeed")

	-- Fine motes spread along the whole flow, giving the "water itself is
	-- moving" density variation rather than a single visible jet.
	local motes = Instance.new("ParticleEmitter")
	motes.Name = "CurrentFlowMotes"
	motes.EmissionDirection = Enum.NormalId.Front
	motes.Rate = 10 * intensity
	motes.Lifetime = NumberRange.new(2, 3.5)
	motes.Speed = NumberRange.new(flowSpeed * 0.5, flowSpeed * 0.9)
	motes.SpreadAngle = Vector2.new(6, 6)
	motes.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.18),
		NumberSequenceKeypoint.new(0.5, 0.28),
		NumberSequenceKeypoint.new(1, 0.05),
	})
	motes.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.15, 1 - 0.55 * intensity),
		NumberSequenceKeypoint.new(0.85, 1 - 0.55 * intensity),
		NumberSequenceKeypoint.new(1, 1),
	})
	motes.Color = ColorSequence.new(FLOW_COLOR)
	motes.LightEmission = 0.25
	motes.LightInfluence = 0
	motes.Rotation = NumberRange.new(0, 360)
	motes.RotSpeed = NumberRange.new(-15, 15)
	motes.Parent = part

	-- Larger, sparser bubbles drifting with the current, reinforcing that
	-- the water is physically carrying things along.
	local bubbles = Instance.new("ParticleEmitter")
	bubbles.Name = "CurrentFlowBubbles"
	bubbles.EmissionDirection = Enum.NormalId.Front
	bubbles.Rate = 3 * intensity
	bubbles.Lifetime = NumberRange.new(1.5, 2.5)
	bubbles.Speed = NumberRange.new(flowSpeed * 0.6, flowSpeed * 1.1)
	bubbles.SpreadAngle = Vector2.new(10, 10)
	bubbles.Acceleration = Vector3.new(0, 1.5, 0)
	bubbles.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.15),
		NumberSequenceKeypoint.new(1, 0.22),
	})
	bubbles.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.2, 1 - 0.4 * intensity),
		NumberSequenceKeypoint.new(0.8, 1 - 0.4 * intensity),
		NumberSequenceKeypoint.new(1, 1),
	})
	bubbles.Color = ColorSequence.new(BUBBLE_COLOR)
	bubbles.Parent = part

	return part
end

-- Circular current (vortex) --------------------------------------------------

-- props: Name, Position (Vector3, center), Radius, Tier, Spin (1 or -1,
-- default 1), SpiralBias (0-1ish, default 0.15 = drawn slightly inward),
-- plus the same optional overrides as above.
local ORBIT_ANCHOR_COUNT = 8
local ORBIT_UPDATE_INTERVAL = 1 / 20 -- 20Hz is smooth enough for a slow drift and cheaper than every frame

local activeVortices = {}

local function createCircularCurrent(props)
	local tier = CurrentsConfig.Tiers[props.Tier]

	local part = Instance.new("Part")
	part.Name = props.Name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.Transparency = 1
	part.Size = Vector3.new(1, 1, 1)
	part.CFrame = CFrame.new(props.Position)
	part:SetAttribute("CurrentShape", "Circular")
	part:SetAttribute("CurrentRadius", props.Radius)
	part:SetAttribute("CurrentSpin", props.Spin or 1)
	part:SetAttribute("CurrentSpiralBias", props.SpiralBias or 0.15)
	applyCommonAttributes(part, props.Tier, tier, props)
	part.Parent = currentsFolder

	local intensity = part:GetAttribute("CurrentVisualIntensity")
	local flowSpeed = part:GetAttribute("CurrentFlowSpeed")
	local radius = props.Radius
	local spin = props.Spin or 1
	local angularSpeed = math.max(0.15, flowSpeed / radius) -- radians/sec, faster currents swirl visibly faster

	local vortexFolder = Instance.new("Folder")
	vortexFolder.Name = "VortexAnchors"
	vortexFolder.Parent = part

	local anchors = {}
	for i = 1, ORBIT_ANCHOR_COUNT do
		local anchor = Instance.new("Part")
		anchor.Name = "VortexAnchor"
		anchor.Anchored = true
		anchor.CanCollide = false
		anchor.CanQuery = false
		anchor.Transparency = 1
		anchor.Size = Vector3.new(0.5, 0.5, 0.5)
		anchor.Parent = vortexFolder

		local bubbles = Instance.new("ParticleEmitter")
		bubbles.Name = "VortexBubbles"
		bubbles.Rate = 4 * intensity
		bubbles.Lifetime = NumberRange.new(1, 2)
		bubbles.Speed = NumberRange.new(0.3, 0.8)
		bubbles.SpreadAngle = Vector2.new(180, 180)
		bubbles.Acceleration = Vector3.new(0, 1, 0)
		bubbles.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.12),
			NumberSequenceKeypoint.new(1, 0.2),
		})
		bubbles.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.25, 1 - 0.5 * intensity),
			NumberSequenceKeypoint.new(0.75, 1 - 0.5 * intensity),
			NumberSequenceKeypoint.new(1, 1),
		})
		bubbles.Color = ColorSequence.new(BUBBLE_COLOR)
		bubbles.LightEmission = 0.2
		bubbles.LightInfluence = 0
		bubbles.Parent = anchor

		table.insert(anchors, {
			part = anchor,
			angleOffset = (i / ORBIT_ANCHOR_COUNT) * math.pi * 2,
			radiusPhase = math.random() * math.pi * 2,
		})
	end

	table.insert(activeVortices, {
		center = props.Position,
		radius = radius,
		spin = spin,
		angularSpeed = angularSpeed,
		anchors = anchors,
	})

	return part
end

-- Single shared loop drives every vortex's orbiting anchors, matching the
-- rest of this codebase's pattern of one continuous server-side loop per
-- family of cosmetic effect (see OceanGenerator's whitecap loop) rather
-- than a per-instance Heartbeat connection.
task.spawn(function()
	local elapsed = 0
	while true do
		task.wait(ORBIT_UPDATE_INTERVAL)
		elapsed += ORBIT_UPDATE_INTERVAL

		for _, vortex in ipairs(activeVortices) do
			for _, anchor in ipairs(vortex.anchors) do
				local angle = anchor.angleOffset + elapsed * vortex.angularSpeed * vortex.spin
				-- Radius breathes slowly in and out (a soft spiral) instead
				-- of tracing a perfectly flat circle every time.
				local radiusFraction = 0.65 + 0.35 * ((math.sin(elapsed * 0.4 + anchor.radiusPhase) + 1) / 2)
				local currentRadius = vortex.radius * radiusFraction
				local offset = Vector3.new(math.cos(angle) * currentRadius, 0, math.sin(angle) * currentRadius)
				anchor.part.Position = vortex.center + offset
			end
		end
	end
end)

-- Example placements ---------------------------------------------------------
-- Reposition, retune, or duplicate these once real zone geometry (canyons,
-- wrecks, cave mouths) exists -- these are just here to demonstrate each
-- tier/shape combination in sensible starting spots.

-- A gentle drift just past the beach shelf, easing new swimmers out toward
-- open water. Weak + no boost, so it's felt but never turns into a shortcut.
createDirectionalCurrent({
	Name = "ReefDrift",
	Position = Vector3.new(0, -15, -260),
	Direction = Vector3.new(0, 0, -1),
	Length = 200,
	Width = 90,
	Height = 40,
	Tier = "Weak",
})

-- A clearly perceptible mid-water current a diver can actually ride partway
-- across the open Récif, demonstrating the "natural fast lane" idea.
createDirectionalCurrent({
	Name = "RecifFastLane",
	Position = Vector3.new(400, -50, 0),
	Direction = Vector3.new(-1, 0, 0),
	Length = 500,
	Width = 60,
	Height = 50,
	Tier = "Medium",
})

-- A strong corridor current deeper down (Grottes range), the kind meant to
-- eventually run through an actual canyon/tunnel once that geometry exists.
createDirectionalCurrent({
	Name = "GrottesCorridorCurrent",
	Position = Vector3.new(-200, -180, 300),
	Direction = Vector3.new(1, -0.15, -1),
	Length = 400,
	Width = 45,
	Height = 45,
	Tier = "Strong",
})

-- A vortex sitting where a wreck or cave mouth would naturally go (Épave
-- range) -- demonstrates the circular/spiral shape and a strong pull.
createCircularCurrent({
	Name = "EpaveVortex",
	Position = Vector3.new(150, -300, -150),
	Radius = 70,
	Spin = 1,
	Tier = "Strong",
})

-- A smaller, calmer vortex near the surface as a second example of the
-- circular shape at a gentler strength.
createCircularCurrent({
	Name = "ShallowEddy",
	Position = Vector3.new(-250, -40, -100),
	Radius = 35,
	Spin = -1,
	Tier = "Medium",
})
