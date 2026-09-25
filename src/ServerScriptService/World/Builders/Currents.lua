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

-- Flow ribbons: three glittering bands twisting slowly around a path's
-- centre line, their texture scrolling in the flow direction at a pace set
-- by the current's speed -- the stream itself made visible, like the
-- great ocean currents in films, without any solid geometry in the water.
-- Consecutive segments continue each other's twist.
local RIBBON_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"
local RIBBON_COLOR = Color3.fromRGB(150, 225, 255)
local function attachRibbons(segment: BasePart, index: number, length: number, width: number, intensity: number, maxSpeed: number)
	local radius = width * 0.38
	for strand = 0, 2 do
		local angleStart = strand * math.pi * 2 / 3 + index * 0.45
		local angleEnd = angleStart + 0.45
		-- The segment looks from its start point toward its end (-Z).
		local a0 = Instance.new("Attachment")
		a0.Name = "RibbonStart"
		a0.Position = Vector3.new(math.cos(angleStart) * radius, math.sin(angleStart) * radius, length / 2)
		a0.Parent = segment
		local a1 = Instance.new("Attachment")
		a1.Name = "RibbonEnd"
		a1.Position = Vector3.new(math.cos(angleEnd) * radius, math.sin(angleEnd) * radius, -length / 2)
		a1.Parent = segment
		local beam = Instance.new("Beam")
		beam.Name = "FlowRibbon"
		beam.Attachment0 = a0
		beam.Attachment1 = a1
		beam.FaceCamera = true
		beam.Width0 = 0.9 + strand * 0.3
		beam.Width1 = 0.9 + strand * 0.3
		beam.Segments = 4
		beam.Color = ColorSequence.new(RIBBON_COLOR, Color3.fromRGB(230, 250, 255))
		beam.Transparency = NumberSequence.new(1 - 0.32 * intensity)
		beam.LightEmission = 0.6
		beam.LightInfluence = 0.2
		beam.Texture = RIBBON_TEXTURE
		beam.TextureMode = Enum.TextureMode.Wrap
		beam.TextureLength = 7
		beam.TextureSpeed = math.clamp(maxSpeed / 10, 0.3, 4)
		beam.Parent = segment
		markVisual(a0)
		markVisual(a1)
		markVisual(beam)
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
		-- By number, not by name: "CurrentPoint_100" must come after "_99".
		return (tonumber(a.Name:match("(%d+)$")) or 0) < (tonumber(b.Name:match("(%d+)$")) or 0)
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
				-- Long smoothed paths have many short segments: particles on
				-- every other one keep the density (and the cost) in check.
				if #points <= 40 or i % 2 == 1 then
					attachFlowEmitters(segment, intensity, maxSpeed)
				end
				attachRibbons(segment, i, length, width, intensity, maxSpeed)
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

-- A path through `points`, optionally smoothed into a Catmull-Rom curve
-- (props.Smooth = spacing in studs) and lifted clear of the seabed after
-- smoothing (props.Lift = clearance), so the curve between control points
-- never dips into the rock either. props.Riders: shoals of fish that ride
-- it (client). props.Beacon: { title, subtitle } for an entry marker.
local function catmullRom(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: number): Vector3
	local t2, t3 = t * t, t * t * t
	return 0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3)
end
local function smoothPoints(points: { Vector3 }, spacing: number): { Vector3 }
	local out = {}
	for i = 1, #points - 1 do
		local p0 = points[math.max(i - 1, 1)]
		local p1, p2 = points[i], points[i + 1]
		local p3 = points[math.min(i + 2, #points)]
		local count = math.max(1, math.ceil((p2 - p1).Magnitude / spacing))
		for k = 0, count - 1 do
			table.insert(out, catmullRom(p0, p1, p2, p3, k / count))
		end
	end
	table.insert(out, points[#points])
	return out
end

local beaconsFolder: Folder
local function entryBeacon(position: Vector3, direction: Vector3, title: string, subtitle: string)
	local ring = Instance.new("Model")
	ring.Name = "CurrentBeacon"
	local frame = CFrame.lookAt(position, position + (direction.Magnitude > 0.01 and direction.Unit or Vector3.new(0, 0, -1)))
	local core
	for k = 1, 16 do
		local a = k / 16 * math.pi * 2
		local bead = Instance.new("Part")
		bead.Name = "BeaconBead"
		bead.Shape = Enum.PartType.Ball
		bead.Size = Vector3.new(1.1, 1.1, 1.1)
		bead.Material = Enum.Material.Neon
		bead.Color = RIBBON_COLOR
		bead.Anchored = true
		bead.CanCollide = false
		bead.CanQuery = false
		bead.CanTouch = false
		bead.CFrame = frame * CFrame.new(math.cos(a) * 7, math.sin(a) * 7, 0)
		bead.Parent = ring
		core = core or bead
	end
	local sign = Instance.new("BillboardGui")
	sign.Name = "BeaconSign"
	sign.Size = UDim2.fromOffset(260, 56)
	sign.StudsOffsetWorldSpace = Vector3.new(0, 11, 0)
	sign.MaxDistance = 260
	sign.LightInfluence = 0
	local list = Instance.new("UIListLayout")
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.Parent = sign
	for index, line in ipairs({ { title, 30, RIBBON_COLOR }, { subtitle, 22, Color3.fromRGB(235, 245, 250) } }) do
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.new(1, 0, 0, line[2])
		label.Font = index == 1 and Enum.Font.GothamBlack or Enum.Font.GothamBold
		label.TextScaled = true
		label.TextColor3 = line[3]
		label.TextStrokeTransparency = 0.4
		label.Text = line[1]
		label.LayoutOrder = index
		label.Parent = sign
	end
	sign.Adornee = core
	sign.Parent = ring
	local light = Instance.new("PointLight")
	light.Color = RIBBON_COLOR
	light.Range = 26
	light.Brightness = 1.2
	light.Parent = core
	ring.Parent = beaconsFolder
	CollectionService:AddTag(ring, GENERATED_TAG)
	return ring
end

local function examplePath(props)
	local points = props.Points
	if props.Smooth then
		points = smoothPoints(points, props.Smooth)
	end
	if props.Lift then
		for i, point in ipairs(points) do
			points[i] = props.Lift(point)
		end
	end
	local model = Instance.new("Model")
	model.Name = props.Name
	for index, position in ipairs(points) do
		local point = Instance.new("Part")
		point.Name = string.format("CurrentPoint_%02d", index)
		point.Size = Vector3.new(2, 2, 2)
		point.CFrame = CFrame.new(position)
		hidePart(point)
		point.Parent = model
	end
	if props.Beacon and #points >= 2 then
		entryBeacon(points[1], points[2] - points[1], props.Beacon[1], props.Beacon[2])
	end
	return generated(model, {
		CurrentShape = "Path",
		CurrentTier = props.Tier,
		CurrentDisplayName = props.DisplayName,
		CurrentWidth = props.Width,
		CurrentRiders = props.Riders or 0,
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

	local existingBeacons = currentsFolder:FindFirstChild("Beacons")
	if existingBeacons and existingBeacons:IsA("Folder") then
		beaconsFolder = existingBeacons
	else
		beaconsFolder = Instance.new("Folder")
		beaconsFolder.Name = "Beacons"
		beaconsFolder.Parent = currentsFolder
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

	-- The current network ------------------------------------------------------
	-- A circulation that ties the whole map together, like the great ocean
	-- currents: Le Grand Courant runs round the volcano at mid-depth; ramps
	-- lead from it to every site (and one from the hub's diving platform
	-- down onto it); upwellings carry divers back up from the deep; and
	-- inside the volcano the water breathes through the lava tubes -- down
	-- the lagoon shaft, up from the abyss, out to the kelp and the wreck.
	local lift = function(clearance: number)
		return function(point: Vector3): Vector3
			return aboveGround(point, clearance)
		end
	end

	-- Le Grand Courant: a closed loop, clockwise seen from above, swinging
	-- wide round the Sirène's ledge (and over her masts' reach).
	local LOOP_Y = -190
	local function loopRadius(bearing: number): number
		local d = math.abs(((bearing - 35 + 180) % 360) - 180)
		return 470 + 95 * math.clamp(1 - (d - 45) / 30, 0, 1)
	end
	local function loopPoint(bearing: number): Vector3
		return onBearing(bearing, loopRadius(bearing), LOOP_Y)
	end
	local loop = {}
	for bearing = 0, 360, 22.5 do
		table.insert(loop, loopPoint(bearing % 360))
	end
	examplePath({
		Name = "GrandCourant",
		DisplayName = "Le Grand Courant",
		Tier = "FastLane",
		Width = 16,
		Points = loop,
		Smooth = 24,
		Lift = lift(20),
		Riders = 6,
		Beacon = { "LE GRAND COURANT", "↻ Le tour du volcan" },
	})

	-- From the hub's diving platform straight down onto the loop.
	local hub = layout:GetAnchor("Hub")
	if hub then
		local b = math.deg(math.atan2(hub.dockEnd.Z, hub.dockEnd.X))
		examplePath({
			Name = "PlongeeDuPonton",
			DisplayName = "Plongée du ponton",
			Tier = "Strong",
			Width = 12,
			Points = { hub.dockEnd + Vector3.new(0, -5, 0), onBearing(b, 205, -30), onBearing(b, 265, -80), onBearing(b, 340, -140), onBearing(b, 420, -178), loopPoint(b + 8) },
			Smooth = 20,
			Lift = lift(18),
			Riders = 2,
			Beacon = { "PLONGÉE DU PONTON", "↓ vers Le Grand Courant" },
		})
	end

	-- Ramps off the loop to the sites.
	local ramps = {
		{ name = "BretelleEpave", display = "Bretelle → La Sirène Noire", points = { loopPoint(58), onBearing(47, 530, -250), onBearing(38, 498, -292) }, beacon = "→ Cimetière de la Sirène" },
		{ name = "BretelleImperatrice", display = "Bretelle → L'Impératrice", points = { loopPoint(66), onBearing(55, 630, -320), onBearing(46, 675, -400), onBearing(43, 690, -440) }, beacon = "→ L'Impératrice" },
		{ name = "BretelleFaille", display = "Bretelle → Faille abyssale", points = { loopPoint(292), onBearing(298, 560, -320), onBearing(300, 630, -410) }, beacon = "→ Faille abyssale" },
	}
	local caves = layout:GetAnchor("Caves")
	if caves then
		for _, entrance in ipairs(caves.entrances) do
			if entrance.id == "Porche" then
				local b = math.deg(math.atan2(entrance.mouth.Z, entrance.mouth.X))
				table.insert(ramps, { name = "CourantDesGrottes", display = "Courant des grottes", points = { loopPoint(b + 12), onBearing(b + 4, 380, -135), entrance.mouth - entrance.inward * 40 + Vector3.new(0, 2, 0), entrance.mouth + entrance.inward * 2 }, beacon = "→ Grottes de l'Éperon" })
			end
		end
	end
	for _, ramp in ipairs(ramps) do
		examplePath({
			Name = ramp.name,
			DisplayName = ramp.display,
			Tier = "Strong",
			Width = 11,
			Points = ramp.points,
			Smooth = 20,
			Lift = lift(14),
			Riders = 1,
			Beacon = { "BRETELLE", ramp.beacon },
		})
	end

	-- Upwellings: the quick, safe way home from the deep, rising along the
	-- flank to just under the reef crest.
	for _, rise in ipairs({ { "RemonteeDesAbysses", "Remontée des abysses", 300, 600, -430 }, { "RemonteeImperatrice", "Remontée de l'Impératrice", 78, 640, -440 } }) do
		local b = rise[3]
		examplePath({
			Name = rise[1],
			DisplayName = rise[2],
			Tier = "Strong",
			Width = 12,
			Points = { onBearing(b, rise[4], rise[5]), onBearing(b, rise[4] - 110, -340), onBearing(b, 400, -240), onBearing(b, 310, -140), onBearing(b, 245, -40) },
			Smooth = 20,
			Lift = lift(22),
			Riders = 1,
			Beacon = { "REMONTÉE", "↑ vers le récif" },
		})
	end

	-- The volcano breathing through its lava tubes (see LavaTubes).
	local network = layout:GetAnchor("Network")
	if network then
		local function tubePath(id: string, inward: boolean, name: string, display: string, tier: string, beacon: string)
			local tube = network.tubes[id]
			if not tube then
				return
			end
			local points = {}
			for i = 1, #tube.samples, 5 do
				table.insert(points, tube.samples[i])
			end
			if points[#points] ~= tube.samples[#tube.samples] then
				table.insert(points, tube.samples[#tube.samples])
			end
			if inward then
				local reversed = {}
				for i = #points, 1, -1 do
					table.insert(reversed, points[i])
				end
				points = reversed
			end
			examplePath({
				Name = name,
				DisplayName = display,
				Tier = tier,
				Width = math.max(tube.spec.radius - 3, 6),
				Points = points,
				Riders = 1,
				Beacon = { "RÉSEAU DU VOLCAN", beacon },
			})
		end
		tubePath("PuitsDuLagon", true, "ChuteDuPuits", "Chute du Puits", "Strong", "↓ vers le Cœur du volcan")
		tubePath("TubeAbysses", true, "SouffleDesAbysses", "Souffle des abysses", "FastLane", "↑ vers le Cœur du volcan")
		tubePath("TubeForet", false, "CourantDeLaForet", "Courant de la forêt", "Strong", "→ Forêt de kelp")
		tubePath("TubeEpave", false, "CourantDeLEpave", "Courant de l'épave", "Strong", "→ Cimetière de la Sirène")
		tubePath("TubeKelpDore", true, "CourantDuKelpDore", "Courant du kelp doré", "Medium", "→ Cœur du volcan")
		tubePath("TubeEperon", false, "CourantDeLEperon", "Courant de l'Éperon", "Medium", "→ Salle des Cristaux")
		exampleCircular({
			Name = "TourbillonDuCoeur",
			DisplayName = "Tourbillon du Cœur",
			Position = network.heart.center + Vector3.new(0, 10, 0),
			Radius = 40,
			Spin = -1,
			Tier = "Weak",
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
