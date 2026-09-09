-- Pure depth/zone calculations shared by client and server systems.
-- 1 stud = 1 meter; the water surface is at Y = 0.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ZonesConfig = require(ReplicatedStorage.Shared.Config.ZonesConfig)

local SURFACE_Y = 0

local DepthUtils = {}

DepthUtils.SURFACE_Y = SURFACE_Y

function DepthUtils.GetDepth(position: Vector3): number
	return math.max(0, SURFACE_Y - position.Y)
end

function DepthUtils.GetZoneIndexForDepth(depth: number): number
	for index, zone in ipairs(ZonesConfig.Zones) do
		if depth >= zone.MinDepth and depth < zone.MaxDepth then
			return index
		end
	end
	return #ZonesConfig.Zones
end

function DepthUtils.GetZoneForDepth(depth: number)
	return ZonesConfig.Zones[DepthUtils.GetZoneIndexForDepth(depth)]
end

return DepthUtils
