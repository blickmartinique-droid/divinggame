-- Hand-placed spawn volumes for the real map. Any Part tagged "SpawnRegion"
-- (CollectionService, via the Tag Editor in Studio) becomes a region; its
-- box (or ball, if Shape = Ball) is the volume, its orientation is
-- respected, and Attributes describe what spawns there:
--
--   RegionKind    "Treasure" | "Creature"  (required)
--   RegionCount   number of things to spawn in it (default per consumer)
--   RegionSpecies for creatures: species Id, or several separated by
--                 commas ("PoissonRecif,TortueMarine") -- picked at
--                 random per spawn. Old names (Sardine, Tortue, Raie,
--                 Requin, Baudroie) still resolve via CreaturesConfig
--                 .Aliases, so regions tagged in Studio before the real
--                 assets arrived keep spawning.
--   RegionEnabled false to keep a region placed but inactive
--   RegionWanderRadius for creatures: caps how far anything spawned here
--                 roams from its spawn point (keeps cave dwellers in
--                 their cave -- creatures have no obstacle avoidance)
--
-- Regions can live anywhere in Workspace (inside the wreck model, the cave
-- model, a canyon...), so spawn areas move with the Blender/Studio geometry
-- they belong to instead of being coordinates in a script. Consumers
-- (TreasureSpawner, CreatureSpawner) fall back to their procedural ring
-- placement only when no region of their kind exists, so the current
-- prototype map keeps working untouched until real regions are placed.

local CollectionService = game:GetService("CollectionService")

local TAG = "SpawnRegion"

local SpawnRegions = {}

SpawnRegions.Tag = TAG

function SpawnRegions.GetRegions(kind: string): { BasePart }
	local regions = {}
	for _, instance in ipairs(CollectionService:GetTagged(TAG)) do
		if instance:IsA("BasePart") and instance:GetAttribute("RegionKind") == kind
			and instance:GetAttribute("RegionEnabled") ~= false then
			table.insert(regions, instance)
		end
	end
	return regions
end

local function isBall(region: BasePart): boolean
	return region:IsA("Part") and region.Shape == Enum.PartType.Ball
end

function SpawnRegions.RandomPointIn(region: BasePart): Vector3
	local size = region.Size
	if isBall(region) then
		local radius = math.min(size.X, size.Y, size.Z) / 2
		-- Rejection sampling in the unit cube: uniform inside the ball
		-- (a normalised cube sample would favour the cube's corners).
		for _ = 1, 32 do
			local point = Vector3.new(math.random() * 2 - 1, math.random() * 2 - 1, math.random() * 2 - 1)
			if point.Magnitude <= 1 then
				return region.Position + point * radius
			end
		end
		return region.Position
	end

	local localPoint = Vector3.new(
		(math.random() - 0.5) * size.X,
		(math.random() - 0.5) * size.Y,
		(math.random() - 0.5) * size.Z
	)
	return region.CFrame:PointToWorldSpace(localPoint)
end

function SpawnRegions.Contains(region: BasePart, position: Vector3): boolean
	if isBall(region) then
		return (position - region.Position).Magnitude <= math.min(region.Size.X, region.Size.Y, region.Size.Z) / 2
	end
	local localPoint = region.CFrame:PointToObjectSpace(position)
	local half = region.Size / 2
	return math.abs(localPoint.X) <= half.X and math.abs(localPoint.Y) <= half.Y and math.abs(localPoint.Z) <= half.Z
end

function SpawnRegions.GetSpeciesList(region: BasePart): { string }
	local raw = region:GetAttribute("RegionSpecies")
	local list = {}
	if typeof(raw) == "string" then
		for entry in string.gmatch(raw, "[^,%s]+") do
			table.insert(list, entry)
		end
	end
	return list
end

-- Waits (yielding) until WorldBootstrap has built the world, so a spawner
-- sees every generated region before deciding where open-water fallback
-- placement is still needed.
function SpawnRegions.WaitForWorld()
	local Workspace = game:GetService("Workspace")
	if not Workspace:GetAttribute("WorldReady") then
		Workspace:GetAttributeChangedSignal("WorldReady"):Wait()
	end
end

-- Fires for regions added after startup (e.g. content streamed or spawned
-- later), so consumers can populate them without a restart.
function SpawnRegions.OnRegionAdded(callback: (BasePart) -> ())
	return CollectionService:GetInstanceAddedSignal(TAG):Connect(function(instance)
		if instance:IsA("BasePart") then
			callback(instance)
		end
	end)
end

return SpawnRegions
