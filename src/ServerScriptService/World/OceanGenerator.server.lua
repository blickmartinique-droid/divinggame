-- Builds the V1 ocean volume out of Roblox Terrain on server start: a wide
-- water block from the surface down to -MaxDepth, plus a seafloor beneath it.
-- Regenerating on every start is cheap enough for a prototype and keeps the
-- world fully defined by code rather than hand-placed Studio state.
--
-- Terrain:FillBlock errors ("Extents are too large") on very large single
-- calls, so each volume is filled in smaller chunks instead of one call.

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ZonesConfig = require(ReplicatedStorage.Shared.Config.ZonesConfig)

local OCEAN_WIDTH = 2000 -- studs, horizontal extent (X and Z)
local SURFACE_Y = 0
local FLOOR_THICKNESS = 20
local CHUNK_SIZE = 200

local maxDepth = ZonesConfig.MaxDepth
local terrain = Workspace.Terrain

local function fillChunked(minCorner: Vector3, fullSize: Vector3, material: Enum.Material)
	local chunksX = math.ceil(fullSize.X / CHUNK_SIZE)
	local chunksY = math.ceil(fullSize.Y / CHUNK_SIZE)
	local chunksZ = math.ceil(fullSize.Z / CHUNK_SIZE)

	for cx = 0, chunksX - 1 do
		local sizeX = math.min(CHUNK_SIZE, fullSize.X - cx * CHUNK_SIZE)
		for cy = 0, chunksY - 1 do
			local sizeY = math.min(CHUNK_SIZE, fullSize.Y - cy * CHUNK_SIZE)
			for cz = 0, chunksZ - 1 do
				local sizeZ = math.min(CHUNK_SIZE, fullSize.Z - cz * CHUNK_SIZE)

				local chunkSize = Vector3.new(sizeX, sizeY, sizeZ)
				local chunkCenter = minCorner + Vector3.new(
					cx * CHUNK_SIZE + sizeX / 2,
					cy * CHUNK_SIZE + sizeY / 2,
					cz * CHUNK_SIZE + sizeZ / 2
				)
				terrain:FillBlock(CFrame.new(chunkCenter), chunkSize, material)
			end
		end
	end
end

local oceanMin = Vector3.new(-OCEAN_WIDTH / 2, SURFACE_Y - maxDepth, -OCEAN_WIDTH / 2)
local oceanSize = Vector3.new(OCEAN_WIDTH, maxDepth, OCEAN_WIDTH)
fillChunked(oceanMin, oceanSize, Enum.Material.Water)

local floorMin = Vector3.new(-OCEAN_WIDTH / 2, SURFACE_Y - maxDepth - FLOOR_THICKNESS, -OCEAN_WIDTH / 2)
local floorSize = Vector3.new(OCEAN_WIDTH, FLOOR_THICKNESS, OCEAN_WIDTH)
fillChunked(floorMin, floorSize, Enum.Material.Rock)

-- Water look: a clear, saturated tropical teal with strong sky reflection
-- and gentle waves -- stylised, not a murky "big blue block". Water colour
-- is a global Terrain property shared by everyone, so the per-depth mood
-- (darker, bluer, foggier) is layered on top by ZoneAnnouncer's Lighting /
-- Atmosphere / ColorCorrection, which is per-client. Transparency stays
-- moderate so the submerged shelf and reef silhouettes read through the
-- surface from the beach, which is what makes the sea inviting.
terrain.WaterColor = Color3.fromRGB(24, 132, 152)
terrain.WaterTransparency = 0.55
terrain.WaterReflectance = 0.42
terrain.WaterWaveSize = 0.22
terrain.WaterWaveSpeed = 9

-- Stylised terrain palette: warm pale sand, saturated grass, cool slate
-- rock. SetMaterialColor is free (no extra geometry or textures) and is
-- the single biggest "this isn't default Roblox" win for the island.
terrain:SetMaterialColor(Enum.Material.Sand, Color3.fromRGB(236, 222, 186))
terrain:SetMaterialColor(Enum.Material.Grass, Color3.fromRGB(96, 168, 78))
terrain:SetMaterialColor(Enum.Material.LeafyGrass, Color3.fromRGB(78, 150, 70))
terrain:SetMaterialColor(Enum.Material.Rock, Color3.fromRGB(86, 96, 108))
terrain:SetMaterialColor(Enum.Material.Slate, Color3.fromRGB(70, 82, 96))
terrain:SetMaterialColor(Enum.Material.Ground, Color3.fromRGB(150, 130, 100))

-- Sky and sun: a mid-afternoon sun low enough to throw long reflections
-- and visible god rays underwater, a Sky instance so the sun disc / sky
-- reflection are consistent, and shadows on for shape on the island.
-- Matches ZonesConfig.Surface exactly (depth 0's anchor point), so there
-- is no seam between this one-time default and the continuous depth
-- lighting ZoneAnnouncer takes over as soon as a client is in.
local Lighting = game:GetService("Lighting")
Lighting.ClockTime = 15.2
Lighting.GeographicLatitude = 18
Lighting.Brightness = 2.6
Lighting.Ambient = Color3.fromRGB(118, 130, 140)
Lighting.OutdoorAmbient = Color3.fromRGB(150, 175, 190)
Lighting.FogColor = Color3.fromRGB(196, 222, 235)
Lighting.FogEnd = 3200
Lighting.ExposureCompensation = 0.1
Lighting.GlobalShadows = true
Lighting.ShadowSoftness = 0.35
Lighting.EnvironmentDiffuseScale = 0.55
Lighting.EnvironmentSpecularScale = 0.7

local sky = Lighting:FindFirstChildOfClass("Sky")
if not sky then
	sky = Instance.new("Sky")
	sky.Parent = Lighting
end
sky.SunAngularSize = 16
sky.MoonAngularSize = 9
sky.StarCount = 1500

-- Bloom kept deliberately tight: only genuinely bright things (sun glints
-- on the water, neon relics, abyss bioluminescence) bloom, nothing else.
local bloom = Lighting:FindFirstChild("OceanBloom")
if not bloom then
	bloom = Instance.new("BloomEffect")
	bloom.Name = "OceanBloom"
	bloom.Parent = Lighting
end
bloom.Intensity = 0.35
bloom.Size = 28
bloom.Threshold = 1.6

-- Soft dynamic clouds: cheap, and the sky stops being a flat gradient.
local clouds = terrain:FindFirstChildOfClass("Clouds")
if not clouds then
	clouds = Instance.new("Clouds")
	clouds.Parent = terrain
end
clouds.Cover = 0.42
clouds.Density = 0.28
clouds.Color = Color3.fromRGB(245, 248, 252)
clouds.Enabled = true

-- Natural beach at sea level, replacing the earlier raised floating island.
-- A dry sand core (where the player spawns) pokes just above the waterline,
-- surrounded by a wider, gently submerged sand shelf, then a further outer
-- slope that eases down before handing off to the open ocean floor -- three
-- steps down in height (not just radius) instead of one hard-edged shelf,
-- so the beach-to-ocean transition reads as an actual gradual slope rather
-- than a sudden drop-off. No ramp is needed since there's no cliff to
-- climb -- walking off the sand into deeper water is enough to trigger
-- swim mode.
--
-- Each tier's TOP height must be lower than the previous one for this to
-- actually be a slope (an earlier version gave every tier the same top,
-- which just produced one flat sand plateau poking above the waterline
-- out to the widest radius, with a hidden vertical cliff at its edge --
-- not a submerged shelf at all). Fill order matters too: widest+lowest
-- first, then progressively narrower+higher on top, so each tier pokes
-- through the one before it instead of being buried by it.
local BEACH_CORE_RADIUS = 70 -- dry sand, pokes just above the waterline
local BEACH_SHELF_RADIUS = 140 -- shallow submerged sand shelf around it
local BEACH_SLOPE_RADIUS = 180 -- deeper submerged slope easing toward open water
local CORE_TOP_Y = 4
local CORE_BOTTOM_Y = -3
local SHELF_TOP_Y = -6
local SHELF_BOTTOM_Y = -20
local SLOPE_TOP_Y = -15
local SLOPE_BOTTOM_Y = -35

local slopeHeight = SLOPE_TOP_Y - SLOPE_BOTTOM_Y
local slopeCFrame = CFrame.new(0, (SLOPE_TOP_Y + SLOPE_BOTTOM_Y) / 2, 0)
terrain:FillCylinder(slopeCFrame, slopeHeight, BEACH_SLOPE_RADIUS, Enum.Material.Sand)

local shelfHeight = SHELF_TOP_Y - SHELF_BOTTOM_Y
local shelfCFrame = CFrame.new(0, (SHELF_TOP_Y + SHELF_BOTTOM_Y) / 2, 0)
terrain:FillCylinder(shelfCFrame, shelfHeight, BEACH_SHELF_RADIUS, Enum.Material.Sand)

local coreHeight = CORE_TOP_Y - CORE_BOTTOM_Y
local coreCFrame = CFrame.new(0, (CORE_TOP_Y + CORE_BOTTOM_Y) / 2, 0)
terrain:FillCylinder(coreCFrame, coreHeight, BEACH_CORE_RADIUS, Enum.Material.Sand)

-- A thin patch of grass near the center of the dry sand for a bit of natural
-- color variation -- not a decorated zone, just a beach.
terrain:FillCylinder(CFrame.new(0, CORE_TOP_Y - 1, 0), 2, BEACH_CORE_RADIUS - 25, Enum.Material.Grass)

local oldIslandRamp = Workspace:FindFirstChild("IslandRamp")
if oldIslandRamp then
	oldIslandRamp:Destroy()
end

local oldBaseplate = Workspace:FindFirstChild("Baseplate")
if oldBaseplate then
	oldBaseplate:Destroy()
end

local spawnLocation = Workspace:FindFirstChild("SpawnLocation")
if spawnLocation then
	spawnLocation.Position = Vector3.new(0, CORE_TOP_Y + 0.5, 0)
	spawnLocation.Size = Vector3.new(12, 1, 12)
end

-- A handful of simple rocks and light vegetation on the beach -- plain
-- primitive shapes, not detailed decoration. Kept within the dry core's own
-- radius so they actually rest on its (higher) sand surface, rather than
-- the shelf/slope tiers further out, which now sit underwater.
local existingBeachProps = Workspace:FindFirstChild("BeachProps")
if existingBeachProps then
	existingBeachProps:Destroy()
end

local beachPropsFolder = Instance.new("Folder")
beachPropsFolder.Name = "BeachProps"
beachPropsFolder.Parent = Workspace

local function beachProp(name, size, cframe, material, color, shape)
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanTouch = false
	part.Shape = shape or Enum.PartType.Block
	part.Size = size
	part.CFrame = cframe
	part.Material = material
	part.Color = color
	part.Parent = beachPropsFolder
	return part
end

local ROCK_COUNT = 9
for i = 1, ROCK_COUNT do
	local angle = (i / ROCK_COUNT) * math.pi * 2 + 0.3
	local radius = BEACH_CORE_RADIUS - 30 + math.random() * 26
	local size = 2.5 + math.random() * 4
	beachProp(
		"BeachRock",
		Vector3.new(size, size * (0.5 + math.random() * 0.4), size * (0.7 + math.random() * 0.5)),
		CFrame.new(math.cos(angle) * radius, CORE_TOP_Y - 0.6, math.sin(angle) * radius)
			* CFrame.Angles((math.random() - 0.5) * 0.5, math.random() * math.pi * 2, (math.random() - 0.5) * 0.5),
		Enum.Material.Slate,
		Color3.fromRGB(96, 104, 112)
	)
end

-- Stylised palms: a leaning trunk topped with a fan of drooping fronds.
local PALM_COUNT = 7
for i = 1, PALM_COUNT do
	local angle = (i / PALM_COUNT) * math.pi * 2 + 0.7
	local radius = 18 + math.random() * (BEACH_CORE_RADIUS - 40)
	local base = Vector3.new(math.cos(angle) * radius, CORE_TOP_Y, math.sin(angle) * radius)
	local height = 9 + math.random() * 5
	local leanAngle = math.random() * math.pi * 2
	local lean = CFrame.Angles(0, leanAngle, 0) * CFrame.Angles(math.rad(6 + math.random() * 8), 0, 0)
	local trunkFrame = CFrame.new(base) * lean * CFrame.new(0, height / 2, 0)
	local trunk = beachProp("PalmTrunk", Vector3.new(1.1, height, 1.1), trunkFrame, Enum.Material.Wood, Color3.fromRGB(128, 96, 66))
	trunk.CanCollide = false
	local crown = trunkFrame * CFrame.new(0, height / 2, 0)
	for f = 1, 7 do
		local frondAngle = (f / 7) * math.pi * 2 + math.random() * 0.4
		local frondLength = 5 + math.random() * 2
		local frond = beachProp(
			"PalmFrond",
			Vector3.new(0.9, 0.15, frondLength),
			crown * CFrame.Angles(0, frondAngle, 0) * CFrame.Angles(math.rad(-28 - math.random() * 14), 0, 0) * CFrame.new(0, 0, -frondLength / 2),
			Enum.Material.Grass,
			Color3.fromRGB(70 + math.random(0, 25), 150 + math.random(0, 30), 60)
		)
		frond.CanCollide = false
	end
end

local BUSH_COUNT = 12
for _ = 1, BUSH_COUNT do
	local angle = math.random() * math.pi * 2
	local radius = math.random() * (BEACH_CORE_RADIUS - 22)
	local size = 1.4 + math.random() * 1.6
	local bush = beachProp(
		"BeachBush",
		Vector3.new(size, size * 0.75, size),
		CFrame.new(math.cos(angle) * radius, CORE_TOP_Y + size * 0.3, math.sin(angle) * radius),
		Enum.Material.Grass,
		Color3.fromRGB(80, 140 + math.random(0, 30), 65),
		Enum.PartType.Ball
	)
	bush.CanCollide = false
end

-- Atmosphere for a softer horizon/sky (cheap but effective). Offset lifts
-- the haze band up to the horizon so the sea meets the sky in a soft
-- gradient instead of a hard line; Glare puts a warm halo round the sun.
-- Density/Haze/Color/Decay are then driven per-depth by ZoneAnnouncer.
local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
if not atmosphere then
	atmosphere = Instance.new("Atmosphere")
	atmosphere.Parent = Lighting
end
atmosphere.Density = 0.32
atmosphere.Offset = 0.42
atmosphere.Color = Color3.fromRGB(205, 228, 242)
atmosphere.Decay = Color3.fromRGB(96, 142, 168)
atmosphere.Glare = 0.4
atmosphere.Haze = 1.4

-- Shore foam: a ring of small particle emitters lapping at the beach's
-- waterline.
local existingFoam = Workspace:FindFirstChild("ShoreFoam")
if existingFoam then
	existingFoam:Destroy()
end

local foamFolder = Instance.new("Folder")
foamFolder.Name = "ShoreFoam"
foamFolder.Parent = Workspace

local FOAM_POINTS = 28
for i = 1, FOAM_POINTS do
	local angle = (i / FOAM_POINTS) * math.pi * 2
	local anchor = Instance.new("Part")
	anchor.Name = "FoamAnchor"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(1, 1, 1)
	anchor.Position = Vector3.new(math.cos(angle) * (BEACH_CORE_RADIUS + 3), 0.3, math.sin(angle) * (BEACH_CORE_RADIUS + 3))
	anchor.Parent = foamFolder

	local foam = Instance.new("ParticleEmitter")
	foam.Rate = 4
	foam.Lifetime = NumberRange.new(1, 2)
	foam.Speed = NumberRange.new(0.5, 1.5)
	foam.SpreadAngle = Vector2.new(30, 30)
	foam.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.2),
		NumberSequenceKeypoint.new(1, 0),
	})
	foam.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.3),
		NumberSequenceKeypoint.new(1, 1),
	})
	foam.Color = ColorSequence.new(Color3.new(1, 1, 1))
	foam.Parent = anchor
end

-- Underwater light dust near the beach's shallow water: soft drifting
-- particles standing in for sunbeams filtering through the surface.
local existingDust = Workspace:FindFirstChild("UnderwaterLightDust")
if existingDust then
	existingDust:Destroy()
end

local dustAnchor = Instance.new("Part")
dustAnchor.Name = "UnderwaterLightDust"
dustAnchor.Anchored = true
dustAnchor.CanCollide = false
dustAnchor.Transparency = 1
dustAnchor.Size = Vector3.new(1, 1, 1)
dustAnchor.Position = Vector3.new(0, -20, 0)
dustAnchor.Parent = Workspace

local dust = Instance.new("ParticleEmitter")
dust.Rate = 6
dust.Lifetime = NumberRange.new(4, 8)
dust.Speed = NumberRange.new(0.2, 0.6)
dust.SpreadAngle = Vector2.new(180, 30)
dust.LightEmission = 0.6
dust.LightInfluence = 0
dust.Size = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.4),
	NumberSequenceKeypoint.new(0.5, 1.2),
	NumberSequenceKeypoint.new(1, 0),
})
dust.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.6),
	NumberSequenceKeypoint.new(0.5, 0.7),
	NumberSequenceKeypoint.new(1, 1),
})
dust.Color = ColorSequence.new(Color3.fromRGB(210, 240, 255))
dust.Parent = dustAnchor

-- Terrain water only exposes a single global wave size/speed (no native
-- support for mixed small/medium/large waves), so scattered whitecap
-- bursts of varying scale are used across the open ocean to fake that
-- impression of a choppier, more varied sea.
local Debris = game:GetService("Debris")

local WHITECAP_MIN_RADIUS = BEACH_SLOPE_RADIUS + 20
local WHITECAP_MAX_RADIUS = 900
local WHITECAP_MIN_INTERVAL = 1
local WHITECAP_MAX_INTERVAL = 3

task.spawn(function()
	while true do
		task.wait(WHITECAP_MIN_INTERVAL + math.random() * (WHITECAP_MAX_INTERVAL - WHITECAP_MIN_INTERVAL))

		local angle = math.random() * math.pi * 2
		local radius = WHITECAP_MIN_RADIUS + math.random() * (WHITECAP_MAX_RADIUS - WHITECAP_MIN_RADIUS)
		local position = Vector3.new(math.cos(angle) * radius, 0.3, math.sin(angle) * radius)

		local anchor = Instance.new("Part")
		anchor.Name = "WhitecapAnchor"
		anchor.Anchored = true
		anchor.CanCollide = false
		anchor.Transparency = 1
		anchor.Size = Vector3.new(1, 1, 1)
		anchor.Position = position
		anchor.Parent = Workspace

		local scale = 0.5 + math.random() * 2 -- small, medium, or large crest
		local whitecap = Instance.new("ParticleEmitter")
		whitecap.Rate = 0
		whitecap.Lifetime = NumberRange.new(0.8, 1.4)
		whitecap.Speed = NumberRange.new(1, 3)
		whitecap.SpreadAngle = Vector2.new(180, 180)
		whitecap.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 2 * scale),
			NumberSequenceKeypoint.new(1, 0),
		})
		whitecap.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.3),
			NumberSequenceKeypoint.new(1, 1),
		})
		whitecap.Color = ColorSequence.new(Color3.new(1, 1, 1))
		whitecap.Parent = anchor
		whitecap:Emit(math.floor(6 * scale))

		Debris:AddItem(anchor, 2)
	end
end)
