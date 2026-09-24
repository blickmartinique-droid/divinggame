-- The ocean itself: clears any terrain left in the place file, fills the
-- 2000x2000 water column from the surface down to -MaxDepth over a rock
-- seafloor, raises the beach island at the center, sets the sky/lighting
-- defaults, and walls the ocean's edge so nobody swims out of the water
-- volume into the void. First builder WorldBootstrap runs -- everything
-- else carves into or sits on top of what this lays down.
--
-- Terrain:FillBlock errors ("Extents are too large") on very large single
-- calls, so each volume is filled in smaller chunks instead of one call.

local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ZonesConfig = require(ReplicatedStorage.Shared.Config.ZonesConfig)

local Ocean = {}

local OCEAN_WIDTH = 2000 -- studs, horizontal extent (X and Z)
local SURFACE_Y = 0
local FLOOR_THICKNESS = 20
local CHUNK_SIZE = 200
local EDGE_WALL_HEIGHT = 760 -- from below the seafloor to well above the surface
local EDGE_WALL_THICKNESS = 4

-- Natural beach at sea level: a dry sand core (where the player spawns)
-- pokes just above the waterline, surrounded by a wider, gently submerged
-- sand shelf, then a further outer slope -- three steps down in height
-- (not just radius), so the beach-to-ocean transition reads as a gradual
-- slope rather than a sudden drop-off. Each tier's TOP must be lower than
-- the previous one, and fill order is widest+lowest first so each tier
-- pokes through the one before it instead of being buried by it.
Ocean.BEACH_CORE_RADIUS = 70
Ocean.BEACH_SHELF_RADIUS = 140
Ocean.BEACH_SLOPE_RADIUS = 180
Ocean.CORE_TOP_Y = 4
Ocean.SHELF_TOP_Y = -6
Ocean.SLOPE_TOP_Y = -15
local CORE_BOTTOM_Y = -3
local SHELF_BOTTOM_Y = -20
local SLOPE_BOTTOM_Y = -35

-- Also used by later builders that need to (re)lay large terrain slabs.
function Ocean.FillChunked(terrain: Terrain, minCorner: Vector3, fullSize: Vector3, material: Enum.Material)
	local chunksX = math.ceil(fullSize.X / CHUNK_SIZE)
	local chunksY = math.ceil(fullSize.Y / CHUNK_SIZE)
	local chunksZ = math.ceil(fullSize.Z / CHUNK_SIZE)

	for cx = 0, chunksX - 1 do
		local sizeX = math.min(CHUNK_SIZE, fullSize.X - cx * CHUNK_SIZE)
		for cy = 0, chunksY - 1 do
			local sizeY = math.min(CHUNK_SIZE, fullSize.Y - cy * CHUNK_SIZE)
			for cz = 0, chunksZ - 1 do
				local sizeZ = math.min(CHUNK_SIZE, fullSize.Z - cz * CHUNK_SIZE)
				local chunkCenter = minCorner + Vector3.new(
					cx * CHUNK_SIZE + sizeX / 2,
					cy * CHUNK_SIZE + sizeY / 2,
					cz * CHUNK_SIZE + sizeZ / 2
				)
				terrain:FillBlock(CFrame.new(chunkCenter), Vector3.new(sizeX, sizeY, sizeZ), material)
			end
		end
	end
end

local function replaceFolder(name: string): Folder
	local existing = Workspace:FindFirstChild(name)
	if existing then
		existing:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = Workspace
	return folder
end

local function buildWater(terrain: Terrain, maxDepth: number)
	Ocean.FillChunked(terrain, Vector3.new(-OCEAN_WIDTH / 2, SURFACE_Y - maxDepth, -OCEAN_WIDTH / 2), Vector3.new(OCEAN_WIDTH, maxDepth, OCEAN_WIDTH), Enum.Material.Water)
	Ocean.FillChunked(terrain, Vector3.new(-OCEAN_WIDTH / 2, SURFACE_Y - maxDepth - FLOOR_THICKNESS, -OCEAN_WIDTH / 2), Vector3.new(OCEAN_WIDTH, FLOOR_THICKNESS, OCEAN_WIDTH), Enum.Material.Rock)

	-- Water look: a clear, saturated tropical teal with strong sky
	-- reflection and gentle waves. Water colour is a global Terrain
	-- property shared by everyone, so the per-depth mood is layered on top
	-- by ZoneAnnouncer's Lighting/Atmosphere/ColorCorrection, per client.
	terrain.WaterColor = Color3.fromRGB(24, 132, 152)
	terrain.WaterTransparency = 0.55
	terrain.WaterReflectance = 0.42
	terrain.WaterWaveSize = 0.22
	terrain.WaterWaveSpeed = 9

	-- Stylised terrain palette (free: no geometry, no textures).
	terrain:SetMaterialColor(Enum.Material.Sand, Color3.fromRGB(236, 222, 186))
	terrain:SetMaterialColor(Enum.Material.Grass, Color3.fromRGB(96, 168, 78))
	terrain:SetMaterialColor(Enum.Material.LeafyGrass, Color3.fromRGB(78, 150, 70))
	terrain:SetMaterialColor(Enum.Material.Rock, Color3.fromRGB(86, 96, 108))
	terrain:SetMaterialColor(Enum.Material.Slate, Color3.fromRGB(70, 82, 96))
	terrain:SetMaterialColor(Enum.Material.Ground, Color3.fromRGB(150, 130, 100))
	terrain:SetMaterialColor(Enum.Material.Mud, Color3.fromRGB(58, 52, 62))
	terrain:SetMaterialColor(Enum.Material.Basalt, Color3.fromRGB(40, 38, 46))
end

-- Invisible walls just outside the water volume. Transparent parts never
-- occlude the default camera, so they are felt, not seen.
local function buildEdgeWalls(maxDepth: number)
	local folder = replaceFolder("OceanEdge")
	local half = OCEAN_WIDTH / 2
	local centerY = SURFACE_Y - maxDepth - FLOOR_THICKNESS + EDGE_WALL_HEIGHT / 2
	local sides = {
		{ Vector3.new(half + EDGE_WALL_THICKNESS / 2, centerY, 0), Vector3.new(EDGE_WALL_THICKNESS, EDGE_WALL_HEIGHT, OCEAN_WIDTH + 2 * EDGE_WALL_THICKNESS) },
		{ Vector3.new(-half - EDGE_WALL_THICKNESS / 2, centerY, 0), Vector3.new(EDGE_WALL_THICKNESS, EDGE_WALL_HEIGHT, OCEAN_WIDTH + 2 * EDGE_WALL_THICKNESS) },
		{ Vector3.new(0, centerY, half + EDGE_WALL_THICKNESS / 2), Vector3.new(OCEAN_WIDTH, EDGE_WALL_HEIGHT, EDGE_WALL_THICKNESS) },
		{ Vector3.new(0, centerY, -half - EDGE_WALL_THICKNESS / 2), Vector3.new(OCEAN_WIDTH, EDGE_WALL_HEIGHT, EDGE_WALL_THICKNESS) },
	}
	for index, side in ipairs(sides) do
		local wall = Instance.new("Part")
		wall.Name = "EdgeWall" .. index
		wall.Anchored = true
		wall.CanCollide = true
		wall.CanTouch = false
		wall.CastShadow = false
		wall.Transparency = 1
		wall.Position = side[1]
		wall.Size = side[2]
		wall.Parent = folder
	end
end

local function buildBeach(terrain: Terrain)
	local function tier(topY: number, bottomY: number, radius: number)
		terrain:FillCylinder(CFrame.new(0, (topY + bottomY) / 2, 0), topY - bottomY, radius, Enum.Material.Sand)
	end
	tier(Ocean.SLOPE_TOP_Y, SLOPE_BOTTOM_Y, Ocean.BEACH_SLOPE_RADIUS)
	tier(Ocean.SHELF_TOP_Y, SHELF_BOTTOM_Y, Ocean.BEACH_SHELF_RADIUS)
	tier(Ocean.CORE_TOP_Y, CORE_BOTTOM_Y, Ocean.BEACH_CORE_RADIUS)
	-- A thin patch of grass near the center of the dry sand.
	terrain:FillCylinder(CFrame.new(0, Ocean.CORE_TOP_Y - 1, 0), 2, Ocean.BEACH_CORE_RADIUS - 25, Enum.Material.Grass)

	for _, name in ipairs({ "IslandRamp", "Baseplate" }) do
		local old = Workspace:FindFirstChild(name)
		if old then
			old:Destroy()
		end
	end
	local spawnLocation = Workspace:FindFirstChild("SpawnLocation")
	if spawnLocation and spawnLocation:IsA("BasePart") then
		spawnLocation.Position = Vector3.new(0, Ocean.CORE_TOP_Y + 0.5, 0)
		spawnLocation.Size = Vector3.new(12, 1, 12)
	end
end

local function beachProps(rng: Random)
	local folder = replaceFolder("BeachProps")
	local function prop(name, size, cframe, material, color, shape)
		local part = Instance.new("Part")
		part.Name = name
		part.Anchored = true
		part.CanTouch = false
		part.Shape = shape or Enum.PartType.Block
		part.Size = size
		part.CFrame = cframe
		part.Material = material
		part.Color = color
		part.Parent = folder
		return part
	end

	local coreRadius = Ocean.BEACH_CORE_RADIUS
	local coreTop = Ocean.CORE_TOP_Y
	for i = 1, 9 do
		local angle = (i / 9) * math.pi * 2 + 0.3
		local radius = coreRadius - 30 + rng:NextNumber() * 26
		local size = 2.5 + rng:NextNumber() * 4
		prop(
			"BeachRock",
			Vector3.new(size, size * (0.5 + rng:NextNumber() * 0.4), size * (0.7 + rng:NextNumber() * 0.5)),
			CFrame.new(math.cos(angle) * radius, coreTop - 0.6, math.sin(angle) * radius)
				* CFrame.Angles((rng:NextNumber() - 0.5) * 0.5, rng:NextNumber() * math.pi * 2, (rng:NextNumber() - 0.5) * 0.5),
			Enum.Material.Slate,
			Color3.fromRGB(96, 104, 112)
		)
	end

	-- Stylised palms: a leaning trunk topped with a fan of drooping fronds.
	for i = 1, 7 do
		local angle = (i / 7) * math.pi * 2 + 0.7
		local radius = 18 + rng:NextNumber() * (coreRadius - 40)
		local base = Vector3.new(math.cos(angle) * radius, coreTop, math.sin(angle) * radius)
		local height = 9 + rng:NextNumber() * 5
		local lean = CFrame.Angles(0, rng:NextNumber() * math.pi * 2, 0) * CFrame.Angles(math.rad(6 + rng:NextNumber() * 8), 0, 0)
		local trunkFrame = CFrame.new(base) * lean * CFrame.new(0, height / 2, 0)
		local trunk = prop("PalmTrunk", Vector3.new(1.1, height, 1.1), trunkFrame, Enum.Material.Wood, Color3.fromRGB(128, 96, 66))
		trunk.CanCollide = false
		local crown = trunkFrame * CFrame.new(0, height / 2, 0)
		for f = 1, 7 do
			local frondLength = 5 + rng:NextNumber() * 2
			local frond = prop(
				"PalmFrond",
				Vector3.new(0.9, 0.15, frondLength),
				crown * CFrame.Angles(0, (f / 7) * math.pi * 2 + rng:NextNumber() * 0.4, 0)
					* CFrame.Angles(math.rad(-28 - rng:NextNumber() * 14), 0, 0) * CFrame.new(0, 0, -frondLength / 2),
				Enum.Material.Grass,
				Color3.fromRGB(70 + rng:NextInteger(0, 25), 150 + rng:NextInteger(0, 30), 60)
			)
			frond.CanCollide = false
		end
	end

	for _ = 1, 12 do
		local angle = rng:NextNumber() * math.pi * 2
		local radius = rng:NextNumber() * (coreRadius - 22)
		local size = 1.4 + rng:NextNumber() * 1.6
		local bush = prop(
			"BeachBush",
			Vector3.new(size, size * 0.75, size),
			CFrame.new(math.cos(angle) * radius, coreTop + size * 0.3, math.sin(angle) * radius),
			Enum.Material.Grass,
			Color3.fromRGB(80, 140 + rng:NextInteger(0, 30), 65),
			Enum.PartType.Ball
		)
		bush.CanCollide = false
	end
end

-- Sky and sun: matches ZonesConfig.Surface exactly (depth 0's anchor), so
-- there is no seam between this server default and the per-client depth
-- lighting ZoneAnnouncer takes over as soon as a client is in.
local function buildSkyAndLighting(terrain: Terrain)
	local surface = ZonesConfig.Surface
	Lighting.ClockTime = 15.2
	Lighting.GeographicLatitude = 18
	Lighting.Brightness = surface.Brightness
	Lighting.Ambient = surface.Ambient
	Lighting.OutdoorAmbient = surface.OutdoorAmbient
	Lighting.FogColor = surface.FogColor
	Lighting.FogEnd = surface.FogEnd
	Lighting.ExposureCompensation = surface.ExposureCompensation
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

	-- Bloom kept tight: only genuinely bright things (sun glints, neon
	-- relics, bioluminescence) bloom.
	local bloom = Lighting:FindFirstChild("OceanBloom")
	if not bloom then
		bloom = Instance.new("BloomEffect")
		bloom.Name = "OceanBloom"
		bloom.Parent = Lighting
	end
	bloom.Intensity = 0.35
	bloom.Size = 28
	bloom.Threshold = 1.6

	local clouds = terrain:FindFirstChildOfClass("Clouds")
	if not clouds then
		clouds = Instance.new("Clouds")
		clouds.Parent = terrain
	end
	clouds.Cover = 0.42
	clouds.Density = 0.28
	clouds.Color = Color3.fromRGB(245, 248, 252)
	clouds.Enabled = true

	-- Offset lifts the haze band up to the horizon so sea meets sky in a
	-- soft gradient; Density/Haze/Color/Decay are then driven per depth.
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if not atmosphere then
		atmosphere = Instance.new("Atmosphere")
		atmosphere.Parent = Lighting
	end
	atmosphere.Density = surface.AtmosphereDensity
	atmosphere.Offset = 0.42
	atmosphere.Color = surface.AtmosphereColor
	atmosphere.Decay = surface.AtmosphereDecay
	atmosphere.Glare = 0.4
	atmosphere.Haze = surface.AtmosphereHaze
end

local function particleAnchor(name: string, position: Vector3, parent: Instance): Part
	local anchor = Instance.new("Part")
	anchor.Name = name
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(1, 1, 1)
	anchor.Position = position
	anchor.Parent = parent
	return anchor
end

local function buildSurfaceEffects()
	-- Shore foam lapping at the beach's waterline.
	local foamFolder = replaceFolder("ShoreFoam")
	for i = 1, 28 do
		local angle = (i / 28) * math.pi * 2
		local radius = Ocean.BEACH_CORE_RADIUS + 3
		local anchor = particleAnchor("FoamAnchor", Vector3.new(math.cos(angle) * radius, 0.3, math.sin(angle) * radius), foamFolder)
		local foam = Instance.new("ParticleEmitter")
		foam.Rate = 4
		foam.Lifetime = NumberRange.new(1, 2)
		foam.Speed = NumberRange.new(0.5, 1.5)
		foam.SpreadAngle = Vector2.new(30, 30)
		foam.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 0) })
		foam.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
		foam.Color = ColorSequence.new(Color3.new(1, 1, 1))
		foam.Parent = anchor
	end

	-- Soft drifting light dust in the lagoon's shallow water.
	local existingDust = Workspace:FindFirstChild("UnderwaterLightDust")
	if existingDust then
		existingDust:Destroy()
	end
	local dustAnchor = particleAnchor("UnderwaterLightDust", Vector3.new(0, -20, 0), Workspace)
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

	-- Terrain water has a single global wave size, so scattered whitecap
	-- bursts of varying scale fake a choppier, more varied sea. Their
	-- anchors live in one folder instead of littering Workspace.
	local whitecaps = replaceFolder("Whitecaps")
	local minRadius = Ocean.BEACH_SLOPE_RADIUS + 20
	task.spawn(function()
		local rng = Random.new()
		while true do
			task.wait(1 + rng:NextNumber() * 2)
			local angle = rng:NextNumber() * math.pi * 2
			local radius = minRadius + rng:NextNumber() * (900 - minRadius)
			local anchor = particleAnchor("WhitecapAnchor", Vector3.new(math.cos(angle) * radius, 0.3, math.sin(angle) * radius), whitecaps)
			local scale = 0.5 + rng:NextNumber() * 2
			local whitecap = Instance.new("ParticleEmitter")
			whitecap.Rate = 0
			whitecap.Lifetime = NumberRange.new(0.8, 1.4)
			whitecap.Speed = NumberRange.new(1, 3)
			whitecap.SpreadAngle = Vector2.new(180, 180)
			whitecap.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2 * scale), NumberSequenceKeypoint.new(1, 0) })
			whitecap.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
			whitecap.Color = ColorSequence.new(Color3.new(1, 1, 1))
			whitecap.Parent = anchor
			whitecap:Emit(math.floor(6 * scale))
			Debris:AddItem(anchor, 2)
		end
	end)
end

function Ocean.Build(layout)
	local terrain = Workspace.Terrain
	local maxDepth = ZonesConfig.MaxDepth

	-- Anything saved into the place's terrain (an old experiment, a stray
	-- sculpt) would otherwise survive under the fresh fill -- the cause of
	-- a past "giant boulder in the ocean" bug.
	terrain:Clear()

	buildWater(terrain, maxDepth)
	buildBeach(terrain)
	beachProps(layout:Random("BeachProps"))
	buildSkyAndLighting(terrain)
	buildSurfaceEffects()
	buildEdgeWalls(maxDepth)

	-- The island and its shelf, reserved from the dry core down to the
	-- slope's underside so no decor spire rises through the beach.
	layout:ReserveCylinder("Beach", Vector3.new(0, 0, 0), Ocean.BEACH_SLOPE_RADIUS + 6, SLOPE_BOTTOM_Y - 6, 40)
	layout:SetAnchor("BeachShelfTopY", Ocean.SHELF_TOP_Y)
	layout:SetAnchor("BeachSlopeTopY", Ocean.SLOPE_TOP_Y)
end

return Ocean
