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

local Currents = {}

local currentsFolder: Instance

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

-- Every current's volume is reserved so later decor keeps clear of it.
local function reserve(layout, instance: Instance)
	local shape = instance:GetAttribute("CurrentShape")
	if shape == "Directional" and instance:IsA("BasePart") then
		layout:ReserveBox(instance.Name, instance.CFrame, instance.Size)
	elseif shape == "Circular" and instance:IsA("BasePart") then
		local radius = instance:GetAttribute("CurrentRadius") or 40
		layout:ReserveCylinder(instance.Name, instance.Position, radius, instance.Position.Y - radius * 0.3, instance.Position.Y + radius * 0.3)
	elseif shape == "Path" then
		local points = getPathPoints(instance)
		local width = instance:GetAttribute("CurrentWidth") or DEFAULT_PATH_WIDTH
		for i = 2, #points do
			layout:ReserveCapsule(instance.Name, points[i - 1].Position, points[i].Position, width)
		end
	end
end

function Currents.Build(layout)
	local existing = Workspace:FindFirstChild("Currents")
	if existing then
		currentsFolder = existing
	else
		local folder = Instance.new("Folder")
		folder.Name = "Currents"
		folder.Parent = Workspace
		currentsFolder = folder
	end

	-- Idempotent: clear what a previous build produced (examples + every
	-- visual), keep anything placed by hand.
	for _, instance in ipairs(CollectionService:GetTagged(GENERATED_TAG)) do
		instance:Destroy()
	end
	for _, instance in ipairs(CollectionService:GetTagged(VISUAL_TAG)) do
		instance:Destroy()
	end

	-- Every example follows the real relief: control points are lifted to
	-- keep at least `clearance` studs of water over the seabed, so no
	-- current runs through the seamount.
	local function aboveGround(point: Vector3, clearance: number): Vector3
		return Vector3.new(point.X, math.max(point.Y, layout:GroundHeight(point.X, point.Z) + clearance), point.Z)
	end
	local function onBearing(degrees: number, radius: number, y: number): Vector3
		local a = math.rad(degrees)
		return Vector3.new(math.cos(a) * radius, y, math.sin(a) * radius)
	end

	-- A gentle drift off the beach's south shelf, easing new swimmers out
	-- over the reef wall. Weak + no boost: felt, never a shortcut.
	exampleDirectional({
		Name = "ReefDrift",
		DisplayName = "Dérive du récif",
		Position = Vector3.new(0, -20, -300),
		Direction = Vector3.new(0, 0, -1),
		Length = 160,
		Width = 90,
		Height = 36,
		Tier = "Weak",
	})

	-- A fast lane circling the island along the top of the reef wall.
	local tourPoints = {}
	for index, bearing in ipairs({ 195, 230, 265, 300, 335 }) do
		table.insert(tourPoints, aboveGround(onBearing(bearing, 290, -52 - index * 3), 22))
	end
	examplePath({
		Name = "RecifFastLane",
		DisplayName = "Tour du tombant",
		Tier = "FastLane",
		Width = 14,
		Points = tourPoints,
	})

	-- The way down: from the reef crest, down the flank, to the terrace
	-- where the wreck lies.
	local descentPoints = {}
	for _, step in ipairs({ { 62, 240, -45 }, { 62, 275, -115 }, { 60, 310, -185 }, { 58, 345, -245 }, { 57, 372, -285 } }) do
		table.insert(descentPoints, aboveGround(onBearing(step[1], step[2], step[3]), 24))
	end
	examplePath({
		Name = "DescenteDuTombant",
		DisplayName = "Descente du tombant",
		Tier = "Strong",
		Width = 12,
		Points = descentPoints,
	})

	-- The pull into the caves: open water in front of the Porche du Récif,
	-- flowing into its mouth.
	local caves = layout:GetAnchor("Caves")
	if caves then
		for _, entrance in ipairs(caves.entrances) do
			if entrance.id == "Porche" then
				examplePath({
					Name = "CourantDesGrottes",
					DisplayName = "Courant des grottes",
					Tier = "Medium",
					Width = 10,
					Points = {
						aboveGround(entrance.mouth - entrance.inward * 90 + Vector3.new(0, 6, 0), 14),
						aboveGround(entrance.mouth - entrance.inward * 40 + Vector3.new(0, 2, 0), 10),
						entrance.mouth + entrance.inward * 2,
					},
				})
			end
		end
	end

	-- The Épave vortex swirls in the open water just off the wreck's stern,
	-- downslope (the anchor Shipwreck publishes from its real hull).
	local vortexPosition = layout:GetAnchor("WreckVortex") or Vector3.new(420, -300, 300)
	exampleCircular({
		Name = "EpaveVortex",
		DisplayName = "Tourbillon de l'épave",
		Position = vortexPosition,
		Radius = 60,
		Spin = 1,
		Tier = "Strong",
	})

	-- A calmer eddy over the reef wall, west of the beach.
	exampleCircular({
		Name = "ShallowEddy",
		DisplayName = "Remous peu profond",
		Position = aboveGround(Vector3.new(-250, -40, -100), 20),
		Radius = 35,
		Spin = -1,
		Tier = "Medium",
	})

	-- The quick way home after a deep dive: a column rising from beside the
	-- vortex, on the first bearing where it is clear of the hull, the
	-- seamount and the other currents.
	local updraftTopY = -120
	local updraftPoints = nil
	for step = 0, 11 do
		local angle = step * math.pi / 6
		local base = vortexPosition + Vector3.new(math.cos(angle), 0, math.sin(angle)) * 95
		local bottom = Vector3.new(base.X, vortexPosition.Y - 10, base.Z)
		local top = Vector3.new(base.X, updraftTopY, base.Z)
		if layout:IsSegmentFree(bottom, top, 14) then
			updraftPoints = { bottom, bottom:Lerp(top, 0.5) + Vector3.new(2, 0, -2), top + Vector3.new(6, 0, -6) }
			break
		end
	end
	if updraftPoints then
		examplePath({
			Name = "EpaveUpdraft",
			DisplayName = "Remontée de l'épave",
			Tier = "Strong",
			Width = 10,
			Points = updraftPoints,
		})
	else
		warn("[Currents] no clear column found for EpaveUpdraft")
	end

	-- A strong flow along the floor of the abyssal rift.
	local rift = layout:GetAnchor("RiftFrame")
	if rift then
		exampleDirectional({
			Name = "CourantDeLaFaille",
			DisplayName = "Courant de la faille",
			Position = rift.center + Vector3.new(0, 26, 0),
			Direction = rift.along,
			Length = 340,
			Width = 36,
			Height = 24,
			Tier = "Strong",
		})
	end

	-- Decorate everything, hand-placed and generated alike (every visual is
	-- tagged as it is created, so a rebuild clears exactly those), and keep
	-- decorating currents added later at runtime.
	for _, instance in ipairs(currentsFolder:GetChildren()) do
		decorateCurrent(instance)
		reserve(layout, instance)
	end

	currentsFolder.ChildAdded:Connect(function(instance)
		task.defer(decorateCurrent, instance)
	end)
end

return Currents
