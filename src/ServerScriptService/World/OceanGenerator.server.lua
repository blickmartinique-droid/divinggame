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

-- Visual tuning: default Terrain water looks flat and murky. A deep
-- blue-teal with moderate waves and reflectance reads as an actual ocean
-- rather than a puddle, without tipping into a neon/artificial look --
-- these properties are global to the whole Terrain (shared by every
-- player), so the per-depth darkening is handled separately by
-- ZoneAnnouncer's Lighting/Atmosphere/fog, not by changing water color.
terrain.WaterColor = Color3.fromRGB(10, 80, 95)
terrain.WaterTransparency = 0.35
terrain.WaterReflectance = 0.18
terrain.WaterWaveSize = 0.45
terrain.WaterWaveSpeed = 12

-- Matches ZonesConfig's Récif entry exactly (depth 0's anchor point), so
-- there's no visual seam between this one-time default and the continuous
-- depth-based lighting ZoneAnnouncer takes over as soon as a character
-- exists.
local Lighting = game:GetService("Lighting")
Lighting.ClockTime = 14
Lighting.Brightness = 3
Lighting.Ambient = Color3.fromRGB(70, 90, 100)
Lighting.OutdoorAmbient = Color3.fromRGB(130, 160, 170)
Lighting.FogColor = Color3.fromRGB(110, 155, 165)
Lighting.FogEnd = 850

-- Natural beach at sea level, replacing the earlier raised floating island.
-- A dry sand core (where the player spawns) pokes just above the waterline,
-- surrounded by a wider, gently submerged sand shelf that blends into the
-- open ocean beyond it. No ramp is needed since there's no cliff to climb --
-- walking off the sand into deeper water is enough to trigger swim mode.
local BEACH_CORE_RADIUS = 70 -- dry sand, pokes just above the waterline
local BEACH_SHELF_RADIUS = 140 -- wider submerged sand shelf around it
local BEACH_TOP_Y = 4
local SHELF_BOTTOM_Y = -20

local shelfHeight = BEACH_TOP_Y - SHELF_BOTTOM_Y
local shelfCFrame = CFrame.new(0, (BEACH_TOP_Y + SHELF_BOTTOM_Y) / 2, 0)
terrain:FillCylinder(shelfCFrame, shelfHeight, BEACH_SHELF_RADIUS, Enum.Material.Sand)

local BEACH_CORE_BOTTOM_Y = -3
local coreHeight = BEACH_TOP_Y - BEACH_CORE_BOTTOM_Y
local coreCFrame = CFrame.new(0, (BEACH_TOP_Y + BEACH_CORE_BOTTOM_Y) / 2, 0)
terrain:FillCylinder(coreCFrame, coreHeight, BEACH_CORE_RADIUS, Enum.Material.Sand)

-- A thin patch of grass near the center of the dry sand for a bit of natural
-- color variation -- not a decorated zone, just a beach.
terrain:FillCylinder(CFrame.new(0, BEACH_TOP_Y - 1, 0), 2, BEACH_CORE_RADIUS - 25, Enum.Material.Grass)

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
	spawnLocation.Position = Vector3.new(0, BEACH_TOP_Y + 0.5, 0)
	spawnLocation.Size = Vector3.new(12, 1, 12)
end

-- A handful of simple rocks and light vegetation on the beach -- plain
-- primitive shapes, not detailed decoration.
local existingBeachProps = Workspace:FindFirstChild("BeachProps")
if existingBeachProps then
	existingBeachProps:Destroy()
end

local beachPropsFolder = Instance.new("Folder")
beachPropsFolder.Name = "BeachProps"
beachPropsFolder.Parent = Workspace

local ROCK_COUNT = 6
for i = 1, ROCK_COUNT do
	local angle = (i / ROCK_COUNT) * math.pi * 2 + 0.3
	local radius = BEACH_CORE_RADIUS + 10 + math.random() * 20
	local rock = Instance.new("Part")
	rock.Name = "BeachRock"
	rock.Anchored = true
	rock.Material = Enum.Material.Rock
	rock.Color = Color3.fromRGB(110, 110, 105)
	local size = 3 + math.random() * 3
	rock.Size = Vector3.new(size, size * 0.7, size * 0.9)
	rock.Position = Vector3.new(math.cos(angle) * radius, BEACH_TOP_Y - 1, math.sin(angle) * radius)
	rock.Orientation = Vector3.new(0, math.random(0, 360), 0)
	rock.Parent = beachPropsFolder
end

local PLANT_COUNT = 5
for i = 1, PLANT_COUNT do
	local angle = (i / PLANT_COUNT) * math.pi * 2
	local radius = math.random() * (BEACH_CORE_RADIUS - 15)
	local plant = Instance.new("Part")
	plant.Name = "BeachPlant"
	plant.Anchored = true
	plant.CanCollide = false
	plant.Material = Enum.Material.Grass
	plant.Color = Color3.fromRGB(60, 120, 60)
	plant.Size = Vector3.new(1, 2.5, 1)
	plant.Position = Vector3.new(math.cos(angle) * radius, BEACH_TOP_Y + 1, math.sin(angle) * radius)
	plant.Parent = beachPropsFolder
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

local WHITECAP_MIN_RADIUS = BEACH_SHELF_RADIUS + 20
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
