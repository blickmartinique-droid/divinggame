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

-- Visual tuning: default Terrain water looks flat and murky. A vivid
-- turquoise with strong waves and sun reflectance goes for a bright,
-- lively open-ocean look (Sea of Thieves-ish) rather than a puddle.
terrain.WaterColor = Color3.fromRGB(15, 118, 130)
terrain.WaterTransparency = 0.35
terrain.WaterReflectance = 0.3
terrain.WaterWaveSize = 0.35
terrain.WaterWaveSpeed = 12

local Lighting = game:GetService("Lighting")
Lighting.ClockTime = 14
Lighting.Brightness = 3
Lighting.Ambient = Color3.fromRGB(70, 90, 100)
Lighting.OutdoorAmbient = Color3.fromRGB(130, 160, 170)
Lighting.FogColor = Color3.fromRGB(120, 170, 180)
Lighting.FogEnd = 1500

-- Small spawn island carved out of the ocean (grass poking above the water
-- line, sand rim underwater) instead of a flat Baseplate, so the start of
-- the dive feels like leaving land rather than standing on a floating slab.
local ISLAND_RADIUS = 55
local ISLAND_HEIGHT = 18
local islandCFrame = CFrame.new(0, 2, 0)
terrain:FillCylinder(islandCFrame, ISLAND_HEIGHT, ISLAND_RADIUS, Enum.Material.Sand)
terrain:FillCylinder(islandCFrame * CFrame.new(0, 3, 0), ISLAND_HEIGHT - 6, ISLAND_RADIUS - 12, Enum.Material.Grass)

local oldBaseplate = Workspace:FindFirstChild("Baseplate")
if oldBaseplate then
	oldBaseplate:Destroy()
end

local ISLAND_TOP_Y = 11 -- top surface of the grass cylinder above, from its CFrame/height

local spawnLocation = Workspace:FindFirstChild("SpawnLocation")
if spawnLocation then
	spawnLocation.Position = Vector3.new(0, ISLAND_TOP_Y + 0.5, 0)
	spawnLocation.Size = Vector3.new(12, 1, 12)
end

-- Wooden ramp from the water up to the island: the cylinder island has a
-- flat top and steep sides, too steep to walk up, so a simple staircase of
-- steps bridges the gap.
local existingRamp = Workspace:FindFirstChild("IslandRamp")
if existingRamp then
	existingRamp:Destroy()
end

local rampFolder = Instance.new("Folder")
rampFolder.Name = "IslandRamp"
rampFolder.Parent = Workspace

local RAMP_STEP_COUNT = 10
local RAMP_STEP_WIDTH = 14
local RAMP_STEP_DEPTH = 4
local RAMP_RUN = 40 -- studs, horizontal distance the ramp covers

for i = 1, RAMP_STEP_COUNT do
	local t = i / RAMP_STEP_COUNT
	local step = Instance.new("Part")
	step.Name = "RampStep"
	step.Anchored = true
	step.Material = Enum.Material.WoodPlanks
	step.Color = Color3.fromRGB(120, 90, 60)
	step.Size = Vector3.new(RAMP_STEP_WIDTH, 1.5, RAMP_STEP_DEPTH)
	local distanceFromCenter = ISLAND_RADIUS + RAMP_RUN * (1 - t)
	local stepY = ISLAND_TOP_Y * t
	step.Position = Vector3.new(distanceFromCenter, stepY, 0)
	step.Parent = rampFolder
end

-- Atmosphere for a softer horizon/sky (cheap but effective realism boost).
local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
if not atmosphere then
	atmosphere = Instance.new("Atmosphere")
	atmosphere.Parent = Lighting
end
atmosphere.Density = 0.3
atmosphere.Offset = 0.25
atmosphere.Color = Color3.fromRGB(199, 232, 247)
atmosphere.Decay = Color3.fromRGB(106, 150, 168)
atmosphere.Glare = 0.2
atmosphere.Haze = 1.2

-- Shore foam: a ring of small particle emitters lapping at the island's
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
	anchor.Position = Vector3.new(math.cos(angle) * (ISLAND_RADIUS + 3), 0.3, math.sin(angle) * (ISLAND_RADIUS + 3))
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

-- Underwater light dust near the island's shallow water: soft drifting
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
