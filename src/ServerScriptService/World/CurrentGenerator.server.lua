-- Builds the visuals of every underwater current in Workspace.Currents and
-- fills in default Attributes, so a current is fully described by its
-- instance + Attributes (see CurrentsConfig.lua for the list) and never by
-- code. Both the example currents placed at the bottom of this script and
-- any current you place by hand in Studio go through the same decorate
-- pass -- to add a current, place a Part (Directional / Circular) or a
-- Model with CurrentPoint_01.. children (Path) inside Workspace.Currents,
-- set CurrentShape and whatever Attributes you want to override, and it
-- is live on the next play. Nothing hand-placed is ever destroyed here:
-- only instances this script generated (tagged) are cleared and rebuilt.
--
-- Gameplay (the actual push) is computed on the client from these same
-- instances/Attributes by UnderwaterCurrents.client.lua; visuals here are
-- built once server-side so they replicate to every client as plain
-- instances, and everything that moves (vortex strands, path rings) is
-- animated per-client by CurrentVisualAnimator.client.lua -- no per-frame
-- server work, no replication traffic.
--
-- Visual language, shared by every shape: fine motes + sparse bubbles +
-- near-straight streamer threads all drifting in the flow direction
-- (the water itself is moving), soft particle "veils" at the entry and
-- exit so the zone's ends are readable, and -- for directional/path
-- currents -- a chain of translucent particle rings that travel along the
-- trajectory, so the path and its direction can be read at a glance the
-- way flight-game course gates are, without any solid geometry sitting in
-- the water. Nothing glows or saturates.

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local CurrentsConfig = require(ReplicatedStorage.Shared.Config.CurrentsConfig)

local GENERATED_TAG = "GeneratedCurrent"
local VISUAL_TAG = "CurrentVisual"

local FLOW_COLOR = Color3.fromRGB(205, 230, 235)
local BUBBLE_COLOR = Color3.new(1, 1, 1)
local VISUAL_SPEED_CAP = 32 -- particle speeds stop scaling past this so fast lanes stay readable
local RING_SPACING = 22
local MIN_RINGS = 2
local MAX_RINGS = 12
local DEFAULT_PATH_WIDTH = 12
local VORTEX_STRAND_COUNT = 14
local VORTEX_INNER_RADIUS_FRACTION = 0.12

local currentsFolder = Workspace:FindFirstChild("Currents")
if not currentsFolder then
	currentsFolder = Instance.new("Folder")
	currentsFolder.Name = "Currents"
	currentsFolder.Parent = Workspace
end

-- Idempotent: clear what a previous run of this script produced (examples
-- + every visual), keep anything placed by hand.
for _, instance in ipairs(CollectionService:GetTagged(GENERATED_TAG)) do
	instance:Destroy()
end
for _, instance in ipairs(CollectionService:GetTagged(VISUAL_TAG)) do
	instance:Destroy()
end

local function markVisual(instance: Instance)
	CollectionService:AddTag(instance, VISUAL_TAG)
	return instance
end

-- Attributes ----------------------------------------------------------------------

local function defaultAttribute(instance: Instance, name: string, value)
	if instance:GetAttribute(name) == nil then
		instance:SetAttribute(name, value)
	end
end

local function resolveAttributes(instance: Instance)
	local tierName = instance:GetAttribute("CurrentTier")
	local tier = CurrentsConfig.Tiers[tierName]
	if not tier then
		tierName, tier = "Medium", CurrentsConfig.Tiers.Medium
		instance:SetAttribute("CurrentTier", tierName)
	end

	defaultAttribute(instance, "CurrentEnabled", true)
	defaultAttribute(instance, "CurrentMaxSpeed", instance:GetAttribute("CurrentFlowSpeed") or tier.MaxSpeed)
	defaultAttribute(instance, "CurrentAcceleration", tier.Acceleration)
	defaultAttribute(instance, "CurrentExitDeceleration", tier.ExitDeceleration)
	defaultAttribute(instance, "CurrentCentering", tier.Centering)
	defaultAttribute(instance, "CurrentCanBoost", tier.CanBoost)
	defaultAttribute(instance, "CurrentVisualIntensity", tier.VisualIntensity)
	defaultAttribute(instance, "CurrentDisplayName", instance.Name)
end

local function hidePart(part: BasePart)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
end

-- Particle builders ---------------------------------------------------------------

local function transparencyEnvelope(peak: number, inAt: number, outAt: number)
	return NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(inAt, 1 - peak),
		NumberSequenceKeypoint.new(outAt, 1 - peak),
		NumberSequenceKeypoint.new(1, 1),
	})
end

-- The moving-water layer on a box-shaped part whose Front faces the flow:
-- fine motes spread through the whole volume, sparse bubbles, and a few
-- near-straight streamer threads that read as distinct lines of flow.
local function attachFlowEmitters(part: BasePart, intensity: number, maxSpeed: number)
	local speed = math.min(maxSpeed, VISUAL_SPEED_CAP)

	local motes = Instance.new("ParticleEmitter")
	motes.Name = "CurrentFlowMotes"
	motes.EmissionDirection = Enum.NormalId.Front
	motes.Rate = 10 * intensity
	motes.Lifetime = NumberRange.new(2, 3.5)
	motes.Speed = NumberRange.new(speed * 0.5, speed * 0.9)
	motes.SpreadAngle = Vector2.new(6, 6)
	motes.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.18),
		NumberSequenceKeypoint.new(0.5, 0.28),
		NumberSequenceKeypoint.new(1, 0.05),
	})
	motes.Transparency = transparencyEnvelope(0.55 * intensity, 0.15, 0.85)
	motes.Color = ColorSequence.new(FLOW_COLOR)
	motes.LightEmission = 0.1
	motes.LightInfluence = 0
	motes.Rotation = NumberRange.new(0, 360)
	motes.RotSpeed = NumberRange.new(-15, 15)
	motes.Parent = part

	local bubbles = Instance.new("ParticleEmitter")
	bubbles.Name = "CurrentFlowBubbles"
	bubbles.EmissionDirection = Enum.NormalId.Front
	bubbles.Rate = 3 * intensity
	bubbles.Lifetime = NumberRange.new(1.5, 2.5)
	bubbles.Speed = NumberRange.new(speed * 0.6, speed * 1.1)
	bubbles.SpreadAngle = Vector2.new(10, 10)
	bubbles.Acceleration = Vector3.new(0, 1.5, 0)
	bubbles.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.15),
		NumberSequenceKeypoint.new(1, 0.22),
	})
	bubbles.Transparency = transparencyEnvelope(0.4 * intensity, 0.2, 0.8)
	bubbles.Color = ColorSequence.new(BUBBLE_COLOR)
	bubbles.Parent = part

	local streamers = Instance.new("ParticleEmitter")
	streamers.Name = "CurrentStreamers"
	streamers.EmissionDirection = Enum.NormalId.Front
	streamers.Rate = 2 * intensity
	streamers.Lifetime = NumberRange.new(1.5, 2.5)
	streamers.Speed = NumberRange.new(speed * 0.8, speed * 1.3)
	streamers.SpreadAngle = Vector2.new(2, 2)
	streamers.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.05),
		NumberSequenceKeypoint.new(0.5, 0.1),
		NumberSequenceKeypoint.new(1, 0.02),
	})
	streamers.Transparency = transparencyEnvelope(0.6 * intensity, 0.1, 0.9)
	streamers.Color = ColorSequence.new(FLOW_COLOR)
	streamers.LightEmission = 0.08
	streamers.LightInfluence = 0
	streamers.Parent = part

	markVisual(motes)
	markVisual(bubbles)
	markVisual(streamers)
end

-- A soft, sparse puff marking where the zone starts/stops -- larger and
-- slower than the flow motes, still just loose particles, never a wall.
local function attachBoundaryVeil(part: BasePart, name: string, localZ: number, intensity: number)
	local attachment = Instance.new("Attachment")
	attachment.Name = name .. "Attachment"
	attachment.Position = Vector3.new(0, 0, localZ)
	attachment.Parent = part
	markVisual(attachment)

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
	veil.Transparency = transparencyEnvelope(0.35 * intensity, 0.3, 0.7)
	veil.Color = ColorSequence.new(FLOW_COLOR)
	veil.LightEmission = 0
	veil.LightInfluence = 1
	veil.Rotation = NumberRange.new(0, 360)
	veil.RotSpeed = NumberRange.new(-10, 10)
	veil.Parent = attachment
end

-- One course-gate ring: an invisible thin part whose emitter spawns small
-- motes only on the rim of a cylinder (Shape = Cylinder, Surface), drifting
-- gently inward. As CurrentVisualAnimator slides the part along the path,
-- the particles it leaves behind (world-locked) trace a short translucent
-- tube, so the chain of rings both marks the trajectory and shows the
-- direction of travel. The part's Y axis is the ring's axis.
local function createRing(parent: Instance, radius: number, intensity: number)
	local ring = Instance.new("Part")
	ring.Name = "PathRing"
	ring.Size = Vector3.new(radius * 2, 0.2, radius * 2)
	hidePart(ring)
	ring.Parent = parent

	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "RingMotes"
	emitter.Shape = Enum.ParticleEmitterShape.Cylinder
	emitter.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
	emitter.ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward
	emitter.EmissionDirection = Enum.NormalId.Top
	emitter.Rate = math.clamp(3 * radius, 20, 60) * intensity
	emitter.Lifetime = NumberRange.new(0.6, 1)
	emitter.Speed = NumberRange.new(0.2, 0.6)
	emitter.SpreadAngle = Vector2.new(10, 10)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.12),
		NumberSequenceKeypoint.new(0.3, 0.32),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1 - 0.5 * intensity),
		NumberSequenceKeypoint.new(0.6, 1 - 0.35 * intensity),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Color = ColorSequence.new(FLOW_COLOR)
	emitter.LightEmission = 0.15
	emitter.LightInfluence = 0
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-30, 30)
	emitter.Parent = ring

	return ring
end

-- Rings are just created here (all at the path start); the client spaces
-- them evenly and moves them, reading the track from the current itself.
local function createRings(container: Instance, startPosition: Vector3, totalLength: number, radius: number, intensity: number)
	local folder = Instance.new("Folder")
	folder.Name = "PathRings"
	folder.Parent = container
	markVisual(folder)

	local count = math.clamp(math.floor(totalLength / RING_SPACING), MIN_RINGS, MAX_RINGS)
	for _ = 1, count do
		local ring = createRing(folder, radius, intensity)
		ring.CFrame = CFrame.new(startPosition)
	end
end

-- Shapes --------------------------------------------------------------------------

local function decorateDirectional(part: BasePart)
	hidePart(part)
	local intensity = part:GetAttribute("CurrentVisualIntensity")
	local maxSpeed = part:GetAttribute("CurrentMaxSpeed")

	attachFlowEmitters(part, intensity, maxSpeed)
	attachBoundaryVeil(part, "CurrentEntryVeil", -part.Size.Z / 2, intensity)
	attachBoundaryVeil(part, "CurrentExitVeil", part.Size.Z / 2, intensity)

	local ringRadius = math.min(part.Size.X, part.Size.Y) / 2
	createRings(part, part.Position - part.CFrame.LookVector * (part.Size.Z / 2), part.Size.Z, ringRadius, intensity)
end

-- A vortex: strands spiral inward from the outer radius toward the center
-- while orbiting, respawning at the edge once they reach the middle
-- (animated per-client). At any instant strands sit at every radius, so
-- it reads as a filled 3D funnel of moving water rather than a ring; each
-- has its own height offset for depth and a short direction-facing Trail.
local function decorateCircular(part: BasePart)
	hidePart(part)
	defaultAttribute(part, "CurrentRadius", 40)
	defaultAttribute(part, "CurrentSpin", 1)
	defaultAttribute(part, "CurrentSpiralBias", 0.15)
	local intensity = part:GetAttribute("CurrentVisualIntensity")
	local radius = part:GetAttribute("CurrentRadius")

	local vortexFolder = Instance.new("Folder")
	vortexFolder.Name = "VortexStrands"
	vortexFolder.Parent = part
	markVisual(vortexFolder)

	for _ = 1, VORTEX_STRAND_COUNT do
		local strand = Instance.new("Part")
		strand.Name = "VortexStrand"
		strand.Size = Vector3.new(0.3, 0.3, 0.3)
		hidePart(strand)
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
		bubbles.Transparency = transparencyEnvelope(0.45 * intensity, 0.25, 0.75)
		bubbles.Color = ColorSequence.new(BUBBLE_COLOR)
		bubbles.LightEmission = 0
		bubbles.LightInfluence = 0
		bubbles.Parent = strand

		local startRadius = radius * (VORTEX_INNER_RADIUS_FRACTION + math.random() * (1 - VORTEX_INNER_RADIUS_FRACTION))
		local startAngle = math.random() * math.pi * 2
		local heightOffset = (math.random() - 0.5) * radius * 0.25
		strand.CFrame = CFrame.new(
			part.Position + Vector3.new(math.cos(startAngle) * startRadius, heightOffset, math.sin(startAngle) * startRadius)
		)
	end
end

-- Sorted CurrentPoint_XX parts of a Path current (shared by the client).
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

local function decoratePath(container: Instance)
	defaultAttribute(container, "CurrentWidth", DEFAULT_PATH_WIDTH)
	local points = getPathPoints(container)
	if #points < 2 then
		warn(string.format("[Currents] Path %s needs at least 2 CurrentPoint_XX parts", container:GetFullName()))
		return
	end

	local intensity = container:GetAttribute("CurrentVisualIntensity")
	local maxSpeed = container:GetAttribute("CurrentMaxSpeed")
	local width = container:GetAttribute("CurrentWidth")

	local segmentsFolder = Instance.new("Folder")
	segmentsFolder.Name = "PathSegments"
	segmentsFolder.Parent = container
	markVisual(segmentsFolder)

	local totalLength = 0
	for i = 1, #points do
		hidePart(points[i])
		if i < #points then
			local a, b = points[i].Position, points[i + 1].Position
			local length = (b - a).Magnitude
			if length > 0.01 then
				totalLength += length
				local segment = Instance.new("Part")
				segment.Name = string.format("PathSegment_%02d", i)
				segment.Size = Vector3.new(width * 2, width * 2, length)
				segment.CFrame = CFrame.lookAt((a + b) / 2, b)
				hidePart(segment)
				segment.Parent = segmentsFolder
				attachFlowEmitters(segment, intensity, maxSpeed)
				if i == 1 then
					attachBoundaryVeil(segment, "CurrentEntryVeil", -length / 2, intensity)
				end
				if i == #points - 1 then
					attachBoundaryVeil(segment, "CurrentExitVeil", length / 2, intensity)
				end
			end
		end
	end

	createRings(container, points[1].Position, totalLength, width, intensity)
end

local function decorateCurrent(instance: Instance)
	local shape = instance:GetAttribute("CurrentShape")
	if not shape and instance:IsA("BasePart") then
		shape = "Directional"
		instance:SetAttribute("CurrentShape", shape)
	end
	if not shape then
		return
	end

	resolveAttributes(instance)
	if shape == "Directional" and instance:IsA("BasePart") then
		decorateDirectional(instance)
	elseif shape == "Circular" and instance:IsA("BasePart") then
		decorateCircular(instance)
	elseif shape == "Path" then
		decoratePath(instance)
	else
		warn(string.format("[Currents] %s: unsupported CurrentShape %s for a %s", instance:GetFullName(), tostring(shape), instance.ClassName))
	end
end

-- Example placements ---------------------------------------------------------
-- Demonstrate each shape/tier; reposition, retune, or delete once the real
-- geometry (canyons, wrecks, cave mouths) exists. Anything placed by hand
-- in Workspace.Currents is decorated exactly the same way below.

local function generated(instance: Instance, attributes: { [string]: any })
	CollectionService:AddTag(instance, GENERATED_TAG)
	for name, value in pairs(attributes) do
		instance:SetAttribute(name, value)
	end
	instance.Parent = currentsFolder
	return instance
end

local function exampleDirectional(props)
	local part = Instance.new("Part")
	part.Name = props.Name
	part.Size = Vector3.new(props.Width, props.Height, props.Length)
	part.CFrame = CFrame.lookAt(props.Position, props.Position + props.Direction.Unit)
	hidePart(part)
	return generated(part, {
		CurrentShape = "Directional",
		CurrentTier = props.Tier,
		CurrentDisplayName = props.DisplayName,
	})
end

local function exampleCircular(props)
	local part = Instance.new("Part")
	part.Name = props.Name
	part.Size = Vector3.new(1, 1, 1)
	part.CFrame = CFrame.new(props.Position)
	hidePart(part)
	return generated(part, {
		CurrentShape = "Circular",
		CurrentTier = props.Tier,
		CurrentDisplayName = props.DisplayName,
		CurrentRadius = props.Radius,
		CurrentSpin = props.Spin,
	})
end

local function examplePath(props)
	local model = Instance.new("Model")
	model.Name = props.Name
	for index, position in ipairs(props.Points) do
		local point = Instance.new("Part")
		point.Name = string.format("CurrentPoint_%02d", index)
		point.Size = Vector3.new(2, 2, 2)
		point.CFrame = CFrame.new(position)
		hidePart(point)
		point.Parent = model
	end
	return generated(model, {
		CurrentShape = "Path",
		CurrentTier = props.Tier,
		CurrentDisplayName = props.DisplayName,
		CurrentWidth = props.Width,
	})
end

-- A gentle drift just past the beach shelf, easing new swimmers out toward
-- open water. Weak + no boost, so it's felt but never turns into a shortcut.
exampleDirectional({
	Name = "ReefDrift",
	DisplayName = "Dérive du récif",
	Position = Vector3.new(0, -15, -260),
	Direction = Vector3.new(0, 0, -1),
	Length = 200,
	Width = 90,
	Height = 40,
	Tier = "Weak",
})

-- A real fast lane across the open Récif: a multi-leg path that climbs,
-- turns, and dives, showing the trajectory system end to end.
examplePath({
	Name = "RecifFastLane",
	DisplayName = "Voie rapide du récif",
	Tier = "FastLane",
	Width = 14,
	Points = {
		Vector3.new(420, -45, 120),
		Vector3.new(300, -40, 40),
		Vector3.new(160, -55, -30),
		Vector3.new(20, -80, -120),
		Vector3.new(-120, -120, -180),
	},
})

-- A strong corridor current deeper down (Grottes range), diagonal and
-- descending, the kind meant to eventually run through an actual canyon.
exampleDirectional({
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
exampleCircular({
	Name = "EpaveVortex",
	DisplayName = "Tourbillon de l'épave",
	Position = Vector3.new(150, -300, -150),
	Radius = 70,
	Spin = 1,
	Tier = "Strong",
})

-- A smaller, calmer vortex near the surface as a second example of the
-- circular shape at a gentler strength.
exampleCircular({
	Name = "ShallowEddy",
	DisplayName = "Remous peu profond",
	Position = Vector3.new(-250, -40, -100),
	Radius = 35,
	Spin = -1,
	Tier = "Medium",
})

-- A vertical lift from the Épave range back up toward the Grottes: a
-- straight-up path, the quick way home after a deep dive.
examplePath({
	Name = "EpaveUpdraft",
	DisplayName = "Remontée de l'épave",
	Tier = "Strong",
	Width = 10,
	Points = {
		Vector3.new(260, -330, -260),
		Vector3.new(262, -250, -262),
		Vector3.new(270, -170, -270),
	},
})

-- Decorate everything, hand-placed and generated alike (every visual is
-- tagged as it is created, so the next run clears exactly those), and keep
-- decorating currents added later at runtime.
for _, instance in ipairs(currentsFolder:GetChildren()) do
	decorateCurrent(instance)
end

currentsFolder.ChildAdded:Connect(function(instance)
	task.defer(decorateCurrent, instance)
end)
