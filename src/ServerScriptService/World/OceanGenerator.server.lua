-- Builds the V1 ocean volume out of Roblox Terrain on server start: a wide
-- water block from the surface down to -MaxDepth, plus a seafloor beneath it.
-- Regenerating on every start is cheap enough for a prototype and keeps the
-- world fully defined by code rather than hand-placed Studio state.

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ZonesConfig = require(ReplicatedStorage.Shared.Config.ZonesConfig)

local OCEAN_WIDTH = 3000 -- studs, horizontal extent (X and Z)
local SURFACE_Y = 0
local FLOOR_THICKNESS = 20

local maxDepth = ZonesConfig.MaxDepth
local terrain = Workspace.Terrain

local oceanCenter = CFrame.new(0, SURFACE_Y - maxDepth / 2, 0)
local oceanSize = Vector3.new(OCEAN_WIDTH, maxDepth, OCEAN_WIDTH)
terrain:FillBlock(oceanCenter, oceanSize, Enum.Material.Water)

local floorCenter = CFrame.new(0, SURFACE_Y - maxDepth - FLOOR_THICKNESS / 2, 0)
local floorSize = Vector3.new(OCEAN_WIDTH, FLOOR_THICKNESS, OCEAN_WIDTH)
terrain:FillBlock(floorCenter, floorSize, Enum.Material.Rock)
