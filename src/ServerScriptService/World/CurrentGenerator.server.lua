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
--   Circular -- a vortex. A set of small strands continuously spiral inward
--     while orbiting the center (respawning at the edge once they reach the
--     middle), suited to sit near a wreck, cave mouth, or other landmark.
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
	part:SetAttribute("CurrentDisplayName", overrides.DisplayName or part.Name)
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
	motes.LightEmission = 0.1
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

	-- Sparser, brighter, near-straight threads (tight SpreadAngle) read as
	-- distinct lines of water actually moving through the corridor, instead
	-- of the fine motes above just reading as diffuse drifting dust.
	local streamers = Instance.new("ParticleEmitter")
	streamers.Name = "CurrentStreamers"
	streamers.EmissionDirection = Enum.NormalId.Front
	streamers.Rate = 2 * intensity
	streamers.Lifetime = NumberRange.new(1.5, 2.5)
	streamers.Speed = NumberRange.new(flowSpeed * 0.8, flowSpeed * 1.3)
	streamers.SpreadAngle = Vector2.new(2, 2)
	streamers.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.05),
		NumberSequenceKeypoint.new(0.5, 0.1),
		NumberSequenceKeypoint.new(1, 0.02),
	})
	streamers.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.1, 1 - 0.6 * intensity),
		NumberSequenceKeypoint.new(0.9, 1 - 0.6 * intensity),
		NumberSequenceKeypoint.new(1, 1),
	})
	streamers.Color = ColorSequence.new(FLOW_COLOR)
	streamers.LightEmission = 0.08
	streamers.LightInfluence = 0
	streamers.Parent = part

	-- A soft, sparse puff right at each end face marks where the zone
	-- actually starts/stops -- larger and slower than the flow motes so it
	-- reads as a boundary, but still just loose particles (never a flat
	-- disc or wall) so it stays consistent with "the water itself moves"
	-- rather than a hard edge.
	local function createBoundaryVeil(name, localZ)
		local attachment = Instance.new("Attachment")
		attachment.Name = name .. "Attachment"
		attachment.Position = Vector3.new(0, 0, localZ)
		attachment.Parent = part

		local veil = Instance.new("ParticleEmitter")
		veil.Name = name
		veil.Rate = 2.5 * intensity
		veil.Lifetime = NumberRange.new(2.5, 4)
		veil.Speed = NumberRange.new(0.3, 0.8)
		veil.SpreadAngle = Vector2.new(150, 150)
		veil.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.3),
			NumberSequenceKeypoint.new(0.5, 0.5),
			NumberSequenceKeypoint.new(1, 0.1),
		})
		veil.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.3, 1 - 0.35 * intensity),
			NumberSequenceKeypoint.new(0.7, 1 - 0.35 * intensity),
			NumberSequenceKeypoint.new(1, 1),
		})
		veil.Color = ColorSequence.new(FLOW_COLOR)
		veil.LightEmission = 0
		veil.LightInfluence = 1
		veil.Rotation = NumberRange.new(0, 360)
		veil.RotSpeed = NumberRange.new(-10, 10)
		veil.Parent = attachment
	end

	createBoundaryVeil("CurrentEntryVeil", -props.Length / 2)
	createBoundaryVeil("CurrentExitVeil", props.Length / 2)

	return part
end

-- Circular current (vortex) --------------------------------------------------

-- props: Name, Position (Vector3, center), Radius, Tier, Spin (1 or -1,
-- default 1), SpiralBias (0-1ish, default 0.15 = drawn slightly inward),
-- plus the same optional overrides as above.
--
-- Visual model: a set of strands spiral inward from the outer radius toward
-- the center while orbiting, each respawning back at the edge once it
-- reaches the middle, rather than a fixed ring of points orbiting at one
-- radius -- at any instant strands sit at every radius between edge and
-- center, so the shape reads as a filled funnel of moving water instead of
-- a static glowing ring (which is what a single fixed orbit radius looks
-- like from a distance). Each strand also gets its own small, fixed height
-- offset so the funnel has real vertical depth instead of lying flat, and
-- turns to face its own direction of travel so its short Trail always
-- points the way the water is actually spiralling.
--
-- The server only PLACES the strands (below); the motion itself runs in
-- CurrentVortexAnimator.client.lua, on each client, reading the same
-- Attributes -- so there is no per-frame server work and no replication
-- traffic for what is purely a cosmetic.
local VORTEX_STRAND_COUNT = 14
local VORTEX_INNER_RADIUS_FRACTION = 0.12

local function createCircularCurrent(props)
	local tier = CurrentsConfig.Tiers[props.Tier]
	local spiralBias = props.SpiralBias or 0.15

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
	part:SetAttribute("CurrentSpiralBias", spiralBias)
	applyCommonAttributes(part, props.Tier, tier, props)
	part.Parent = currentsFolder

	local intensity = part:GetAttribute("CurrentVisualIntensity")
	local radius = props.Radius

	local vortexFolder = Instance.new("Folder")
	vortexFolder.Name = "VortexStrands"
	vortexFolder.Parent = part

	local function randomHeightOffset()
		return (math.random() - 0.5) * radius * 0.25
	end

	for _ = 1, VORTEX_STRAND_COUNT do
		local strand = Instance.new("Part")
		strand.Name = "VortexStrand"
		strand.Anchored = true
		strand.CanCollide = false
		strand.CanQuery = false
		strand.Transparency = 1
		strand.Size = Vector3.new(0.3, 0.3, 0.3)
		strand.Parent = vortexFolder

		local attachmentFront = Instance.new("Attachment")
		attachmentFront.Position = Vector3.new(0, 0, -0.4)
		attachmentFront.Parent = strand

		local attachmentBack = Instance.new("Attachment")
		attachmentBack.Position = Vector3.new(0, 0, 0.4)
		attachmentBack.Parent = strand

		local trail = Instance.new("Trail")
		trail.Attachment0 = attachmentFront
		trail.Attachment1 = attachmentBack
		trail.Lifetime = 0.5
		trail.MinLength = 0
		trail.FaceCamera = true
		trail.Color = ColorSequence.new(FLOW_COLOR)
		trail.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1 - 0.5 * intensity),
			NumberSequenceKeypoint.new(1, 1),
		})
		trail.WidthScale = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(1, 0),
		})
		trail.Parent = strand

		local bubbles = Instance.new("ParticleEmitter")
		bubbles.Name = "VortexBubbles"
		bubbles.Rate = 2.2 * intensity
		bubbles.Lifetime = NumberRange.new(1, 2)
		bubbles.Speed = NumberRange.new(0.2, 0.6)
		bubbles.SpreadAngle = Vector2.new(180, 180)
		bubbles.Acceleration = Vector3.new(0, 1, 0)
		bubbles.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.1),
			NumberSequenceKeypoint.new(1, 0.18),
		})
		bubbles.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.25, 1 - 0.45 * intensity),
			NumberSequenceKeypoint.new(0.75, 1 - 0.45 * intensity),
			NumberSequenceKeypoint.new(1, 1),
		})
		bubbles.Color = ColorSequence.new(BUBBLE_COLOR)
		bubbles.LightEmission = 0
		bubbles.LightInfluence = 0
		bubbles.Parent = strand

		local startRadius = radius * (VORTEX_INNER_RADIUS_FRACTION + math.random() * (1 - VORTEX_INNER_RADIUS_FRACTION))
		local startAngle = math.random() * math.pi * 2
		local heightOffset = randomHeightOffset()
		local startPosition = props.Position
			+ Vector3.new(math.cos(startAngle) * startRadius, heightOffset, math.sin(startAngle) * startRadius)
		strand.CFrame = CFrame.new(startPosition)
	end

	return part
end

-- Example placements ---------------------------------------------------------
-- Reposition, retune, or duplicate these once real zone geometry (canyons,
-- wrecks, cave mouths) exists -- these are just here to demonstrate each
-- tier/shape combination in sensible starting spots.

-- A gentle drift just past the beach shelf, easing new swimmers out toward
-- open water. Weak + no boost, so it's felt but never turns into a shortcut.
createDirectionalCurrent({
	Name = "ReefDrift",
	DisplayName = "Dérive du récif",
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
	DisplayName = "Voie rapide du récif",
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
	DisplayName = "Couloir des grottes",
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
	DisplayName = "Tourbillon de l'épave",
	Position = Vector3.new(150, -300, -150),
	Radius = 70,
	Spin = 1,
	Tier = "Strong",
})

-- A smaller, calmer vortex near the surface as a second example of the
-- circular shape at a gentler strength.
createCircularCurrent({
	Name = "ShallowEddy",
	DisplayName = "Remous peu profond",
	Position = Vector3.new(-250, -40, -100),
	Radius = 35,
	Spin = -1,
	Tier = "Medium",
})
