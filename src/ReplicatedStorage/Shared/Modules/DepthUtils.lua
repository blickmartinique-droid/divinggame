-- Pure depth/zone calculations shared by client and server systems.
-- 1 stud = 1 meter; the water surface is at Y = 0.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ZonesConfig = require(ReplicatedStorage.Shared.Config.ZonesConfig)

local SURFACE_Y = 0

local DepthUtils = {}

function DepthUtils.GetDepth(position: Vector3): number
	return math.max(0, SURFACE_Y - position.Y)
end

function DepthUtils.GetZoneForDepth(depth: number)
	for _, zone in ipairs(ZonesConfig.Zones) do
		if depth >= zone.MinDepth and depth < zone.MaxDepth then
			return zone
		end
	end
	return ZonesConfig.Zones[#ZonesConfig.Zones]
end

return DepthUtils
