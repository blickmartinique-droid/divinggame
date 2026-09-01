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

local OCEAN_WIDTH = 1000 -- studs, horizontal extent (X and Z)
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

-- Visual tuning: default Terrain water looks flat and murky. A deeper,
-- more saturated color with some waves and reflectance reads as an ocean
-- rather than a puddle.
terrain.WaterColor = Color3.fromRGB(11, 83, 108)
terrain.WaterTransparency = 0.3
terrain.WaterReflectance = 0.15
terrain.WaterWaveSize = 0.15
terrain.WaterWaveSpeed = 8
