-- Shared builder for the 4 "biome" cave/mountain regions
-- (CaveRegion1Data.lua .. CaveRegion4Data.lua, one per uploaded .glb).
-- Invoked once per region by CaveRegions.lua with a placement config.
--
-- WHY THIS IS TERRAIN, NOT PARTS (unlike MegaWreckShip): these models are
-- a handful of big, deliberately blocky "mass" placeholders (the filenames
-- literally say "blockout") standing in for organic mountains and caves.
-- Rebuilding them as boxes would keep exactly the cubic look the brief asks
-- to avoid; Roblox smooth Terrain always renders rounded, so the rock and
-- every cave/tunnel is real Terrain: Rock filled in, Water carved back out
-- (never Air -- an air pocket would put a water surface inside a cave).
--
-- WHAT THE SOURCE DATA IS USED FOR: placement, not literal geometry --
-- where each mass tier sits relative to the others (the authored stepped
-- silhouette), where the chambers and entries are and which way each
-- entry faces, where ruins/terraces/corals sit. Sizes are scaled up and
-- the placeholder chambers enlarged into real caverns.
--
-- MAKING IT A MOUNTAIN, NOT A FLOATING SLAB: the raw tiers are thin and
-- sit anywhere from 30 to 200+ studs above the seafloor, and the enlarged
-- caverns are taller than the tiers around them -- built literally, every
-- region floated in mid-water and its "caverns" were open craters. So:
--   * every cavern gets a rock envelope (its radius + CAVERN_SHELL), so a
--     cave is always a closed chamber inside the rock;
--   * a tapering skirt runs from the seafloor up to the lowest rock, so
--     the mountain is rooted like a seamount;
--   * a cavern is kept above the seafloor and well below the surface;
--   * tunnels start where the rock really ends (found by marching out
--     through this builder's own record of what it filled -- RockModel
--     below), so every entry is a real opening, never a sealed dimple;
--   * ruins, terraces and corals are dropped onto the rock surface (or
--     lifted out of it), never left floating or buried.
--
-- AXIS FIX (same finding as MegaWreckShip's): this generator's own vertical
-- axis is Z, not Y (Region 3's "central_mass" tiers are ~90x70 in X/Y but
-- only ~10 thick in Z). remapAxes swaps Y/Z on every raw point and size.

local WorldLayout = require(script.Parent.WorldLayout)

local CaveRegionBuilder = {}

local FLOOR_Y = WorldLayout.FloorY
local MASS_RADIUS_MULTIPLIER = 2.4 -- horizontal boost so the decoration sits ON the mountain
local CAVERN_ENLARGE = 5 -- source chambers are ~15-30 raw studs
local MIN_CAVERN_RADIUS = 70
local CAVERN_SHELL = 26 -- rock kept around every cavern
local SURFACE_CLEARANCE = 60 -- a cavern's rock roof stays at least this deep
local FLOOR_CLEARANCE = 10 -- a cavern's floor stays this far above the seafloor
local TUNNEL_STEP = 14 -- studs between carve spheres along a tunnel
local TUNNEL_EXIT_MARGIN = 18 -- tunnels start this far outside the rock

local function remapAxes(v: Vector3): Vector3
	return Vector3.new(v.X, v.Z, v.Y)
end

-- RockModel -------------------------------------------------------------------------
-- Every fill/carve this builder makes, in order, so it can ask "is this
-- point rock?" exactly like the voxels will answer (last write wins). The
-- seafloor counts as rock.

local function newRockModel(terrain: Terrain)
	return { terrain = terrain, ops = {} }
end

local function opContains(op, point: Vector3): boolean
	if op.kind == "ball" then
		return (point - op.center).Magnitude <= op.radius
	end
	local dx, dz = point.X - op.center.X, point.Z - op.center.Z
	return math.abs(point.Y - op.center.Y) <= op.height / 2 and dx * dx + dz * dz <= op.radius * op.radius
end

local function isRock(model, point: Vector3): boolean
	for i = #model.ops, 1, -1 do
		local op = model.ops[i]
		if opContains(op, point) then
			return op.rock
		end
	end
	return point.Y < FLOOR_Y
end

local function fillCylinder(model, center: Vector3, height: number, radius: number)
	model.terrain:FillCylinder(CFrame.new(center), height, radius, Enum.Material.Rock)
	table.insert(model.ops, { kind = "cylinder", center = center, height = height, radius = radius, rock = true })
end

local function fillBall(model, center: Vector3, radius: number, rock: boolean)
	model.terrain:FillBall(center, radius, rock and Enum.Material.Rock or Enum.Material.Water)
	table.insert(model.ops, { kind = "ball", center = center, radius = radius, rock = rock })
end

-- First point along the ray (from `origin`, which is inside the rock or a
-- cavern) where the rock ends for good, i.e. open water outside.
local function marchOut(model, origin: Vector3, direction: Vector3, maxDistance: number): Vector3?
	local lastRock = nil
	for distance = 0, maxDistance, 4 do
		local point = origin + direction * distance
		if isRock(model, point) then
			lastRock = distance
		elseif lastRock and distance - lastRock > 12 then
			return origin + direction * (lastRock + 4)
		end
	end
	return nil
end

-- Surface under/over a point: first rock straight down (or up) within range.
local function surfaceAlong(model, from: Vector3, step: number, maxDistance: number): Vector3?
	for distance = 0, maxDistance, math.abs(step) do
		local point = from + Vector3.new(0, step > 0 and distance or -distance, 0)
		if isRock(model, point) then
			return point
		end
	end
	return nil
end

-- Terrain builders ------------------------------------------------------------------

-- Widest tiers first, narrowest/tallest last, so each narrower tier pokes
-- out of the one below instead of being buried by it.
local function fillMassTiers(model, data, toWorld, scale: number)
	local tiers = {}
	for _, seed in ipairs(data.Mass) do
		local radius = math.max(seed.Size.X, seed.Size.Y) * 0.5 * scale * MASS_RADIUS_MULTIPLIER
		local height = math.max(seed.Size.Z * scale, 6)
		table.insert(tiers, { center = toWorld(seed.Center), radius = radius, height = height })
	end
	table.sort(tiers, function(a, b)
		return a.radius > b.radius
	end)
	for _, tier in ipairs(tiers) do
		fillCylinder(model, tier.center, tier.height, tier.radius)
	end
	return tiers
end

local function planCavern(center: Vector3, rawSize: Vector3, scale: number, enlarge: number)
	local radius = math.max(math.max(rawSize.X, rawSize.Y, rawSize.Z) * 0.5 * scale * enlarge, MIN_CAVERN_RADIUS)
	-- Keep the roof (radius + shell) under the surface clearance...
	local maxRadius = (-SURFACE_CLEARANCE - center.Y) - CAVERN_SHELL
	radius = math.min(radius, math.max(maxRadius, MIN_CAVERN_RADIUS))
	-- ...and the floor above the seafloor (lifting the chamber if needed).
	local lowest = FLOOR_Y + FLOOR_CLEARANCE + radius
	if center.Y < lowest then
		center = Vector3.new(center.X, lowest, center.Z)
	end
	return { center = center, radius = radius }
end

-- A tapering column of rock from the seafloor up into the lowest part of
-- the mass, plus a scatter of half-buried boulders around its foot.
local function fillSkirt(model, worldCenter: Vector3, reach: number, baseY: number, rng: Random)
	local height = baseY - FLOOR_Y
	if height <= 4 then
		return
	end
	local steps = 4
	for i = 0, steps - 1 do
		local bottom = FLOOR_Y - 6 + height * (i / steps)
		local top = FLOOR_Y + height * ((i + 1) / steps) + 8
		local radius = reach * (1.05 - 0.3 * (i / steps))
		fillCylinder(model, Vector3.new(worldCenter.X, (bottom + top) / 2, worldCenter.Z), top - bottom, radius)
	end
	for _ = 1, 10 do
		local angle = rng:NextNumber() * math.pi * 2
		local distance = reach * (1 + rng:NextNumber() * 0.25)
		local radius = 12 + rng:NextNumber() * 22
		fillBall(model, Vector3.new(worldCenter.X + math.cos(angle) * distance, FLOOR_Y + radius * 0.3, worldCenter.Z + math.sin(angle) * distance), radius, true)
	end
end

local function carveTunnel(model, from: Vector3, to: Vector3, radius: number)
	local offset = to - from
	local length = offset.Magnitude
	if length < 1 then
		return
	end
	local steps = math.max(2, math.ceil(length / TUNNEL_STEP))
	for i = 0, steps do
		fillBall(model, from:Lerp(to, i / steps), radius, false)
	end
end

-- Parts -----------------------------------------------------------------------------

local function newFolder(parent: Instance, name: string): Folder
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

local function marker(parent: Instance, name: string, position: Vector3)
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Size = Vector3.new(1, 1, 1)
	part.CFrame = CFrame.new(position)
	local attachment = Instance.new("Attachment")
	attachment.Parent = part
	part.Parent = parent
	return part
end

-- Places a ruin/terrace so it rests on the rock: dropped down onto the
-- first rock below it, or lifted out when the seed lands inside the rock.
-- Returns nil (nothing built) when there is no rock anywhere near it.
local function restOnRock(model, position: Vector3, halfHeight: number): Vector3?
	if isRock(model, position) then
		local top = nil
		for distance = 0, 160, 3 do
			if not isRock(model, position + Vector3.new(0, distance, 0)) then
				top = position.Y + distance
				break
			end
		end
		if not top then
			return nil
		end
		return Vector3.new(position.X, top + halfHeight - 1, position.Z)
	end
	local ground = surfaceAlong(model, position, -3, 220)
	if not ground then
		return nil
	end
	return Vector3.new(position.X, ground.Y + halfHeight - 1, position.Z)
end

local function buildProp(parent: Instance, seed, size: Vector3, position: Vector3, rotation: CFrame, material: Enum.Material, collide: boolean)
	local part = Instance.new("Part")
	part.Name = seed.Name
	part.Anchored = true
	part.CanTouch = false
	part.CanCollide = collide
	part.CanQuery = collide
	part.CastShadow = size.Magnitude > 8
	part.Material = material
	part.Color = seed.Color or Color3.fromRGB(110, 115, 122)
	part.Size = size
	part.CFrame = CFrame.new(position) * rotation
	part.Parent = parent
	return part
end

local function addSpawnRegion(parent: Instance, name: string, center: Vector3, size: Vector3, kind: string, extra: { [string]: any }?)
	local region = Instance.new("Part")
	region.Name = name
	region.Anchored = true
	region.CanCollide = false
	region.CanQuery = false
	region.CanTouch = false
	region.Transparency = 1
	region.Size = size
	region.CFrame = CFrame.new(center)
	-- Attributes first, tag last: a spawner listening for the tag must
	-- already see RegionKind when its handler runs.
	region:SetAttribute("RegionKind", kind)
	region:SetAttribute("RegionEnabled", true)
	if extra then
		for key, value in pairs(extra) do
			region:SetAttribute(key, value)
		end
	end
	region.Parent = parent
	game:GetService("CollectionService"):AddTag(region, "SpawnRegion")
	return region
end

-- Cavern life -----------------------------------------------------------------------
-- Lightless and coherent with a cave: glowing crystal clusters and
-- bioluminescent fungi on the floor, stalactites and glow-worm specks on
-- the ceiling. Floor/ceiling are found in the rock model (so the seafloor
-- or a neighbouring tunnel is respected), props sunk slightly into it.

local CAVE_CORAL_COLORS = {
	Color3.fromRGB(200, 120, 150), Color3.fromRGB(230, 150, 90), Color3.fromRGB(150, 110, 200), Color3.fromRGB(110, 170, 170),
}
local CRYSTAL_COLORS = { Color3.fromRGB(90, 220, 255), Color3.fromRGB(170, 120, 255), Color3.fromRGB(80, 255, 190) }
local FUNGUS_COLOR = Color3.fromRGB(120, 255, 210)
local ROCK_COLOR = Color3.fromRGB(62, 68, 78)

local function decorPart(parent: Instance, name: string, size: Vector3, cframe: CFrame, material: Enum.Material, color: Color3): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Size = size
	part.CFrame = cframe
	part.Material = material
	part.Color = color
	part.Parent = parent
	return part
end

local function cavernSurface(model, cavern, rng: Random, ceiling: boolean): Vector3?
	local angle = rng:NextNumber() * math.pi * 2
	local d = cavern.radius * math.sqrt(rng:NextNumber()) * 0.65
	local start = cavern.center + Vector3.new(math.cos(angle) * d, 0, math.sin(angle) * d)
	if isRock(model, start) then
		return nil
	end
	local hit = surfaceAlong(model, start, ceiling and 2 or -2, cavern.radius + 10)
	if not hit then
		return nil
	end
	return hit + Vector3.new(0, ceiling and 1 or -1, 0)
end

local function decorateCaverns(model, regionFolder: Instance, caverns, rng: Random): number
	local folder = newFolder(regionFolder, "CavernLife")
	local count = 0

	for _, cavern in ipairs(caverns) do
		local amount = math.clamp(cavern.radius / 70, 0.6, 1.6)

		for _ = 1, math.floor(5 * amount) do
			local base = cavernSurface(model, cavern, rng, false)
			if base then
				local color = CRYSTAL_COLORS[rng:NextInteger(1, #CRYSTAL_COLORS)]
				for shard = 1, rng:NextInteger(3, 5) do
					local height = 3 + rng:NextNumber() * 6
					local tilt = CFrame.Angles((rng:NextNumber() - 0.5) * 0.9, rng:NextNumber() * math.pi * 2, (rng:NextNumber() - 0.5) * 0.9)
					local crystal = decorPart(folder, "Crystal", Vector3.new(0.9, height, 0.9), CFrame.new(base) * tilt * CFrame.new(0, height / 2, 0) * CFrame.Angles(0, math.pi / 4, 0), Enum.Material.Neon, color)
					crystal.Transparency = 0.15
					if shard == 1 then
						local light = Instance.new("PointLight")
						light.Color = color
						light.Range = 18
						light.Brightness = 1.1
						light.Parent = crystal
					end
					count += 1
				end
			end
		end

		for _ = 1, math.floor(4 * amount) do
			local center = cavernSurface(model, cavern, rng, false)
			if center then
				for _ = 1, rng:NextInteger(3, 5) do
					local base = center + Vector3.new((rng:NextNumber() - 0.5) * 6, 0, (rng:NextNumber() - 0.5) * 6)
					local stalkHeight = 0.8 + rng:NextNumber() * 1.6
					decorPart(folder, "FungusStalk", Vector3.new(0.35, stalkHeight, 0.35), CFrame.new(base + Vector3.new(0, stalkHeight / 2, 0)), Enum.Material.SmoothPlastic, Color3.fromRGB(200, 210, 200))
					local capSize = 0.9 + rng:NextNumber() * 1.2
					decorPart(folder, "FungusCap", Vector3.new(capSize, capSize * 0.45, capSize), CFrame.new(base + Vector3.new(0, stalkHeight, 0)), Enum.Material.Neon, FUNGUS_COLOR).Shape = Enum.PartType.Ball
					count += 2
				end
			end
		end

		-- Stalactites: three stacked, shrinking, turned blocks read as a
		-- tapering spike without any mesh.
		for _ = 1, math.floor(8 * amount) do
			local top = cavernSurface(model, cavern, rng, true)
			if top then
				local length = 6 + rng:NextNumber() * 12
				local width = 1.6 + rng:NextNumber() * 1.8
				local y = top.Y + 1
				for segment = 1, 3 do
					local segmentLength = length / 3
					decorPart(folder, "Stalactite", Vector3.new(width * (1 - (segment - 1) * 0.3), segmentLength, width * (1 - (segment - 1) * 0.3)),
						CFrame.new(top.X, y - segmentLength / 2, top.Z) * CFrame.Angles(0, math.pi / 4 * segment, 0), Enum.Material.Rock, ROCK_COLOR)
					y -= segmentLength * 0.9
					count += 1
				end
			end
		end

		for _ = 1, math.floor(10 * amount) do
			local spot = cavernSurface(model, cavern, rng, true)
			if spot then
				decorPart(folder, "GlowWorm", Vector3.new(0.3, 0.3, 0.3), CFrame.new(spot - Vector3.new(0, 1.2, 0)), Enum.Material.Neon, Color3.fromRGB(140, 240, 255)).Shape = Enum.PartType.Ball
				count += 1
			end
		end
	end

	return count
end

-- Build -------------------------------------------------------------------------------

-- config: { WorldCenter: Vector3, Scale: number, Yaw: number (radians),
--           Name: string, DisplayName: string, TreasureCount: number,
--           CreatureCount: number, CreatureSpecies: string }
-- Returns the region folder and { center, caverns, extent }.
function CaveRegionBuilder.Build(data, config, parentFolder: Instance, rng: Random)
	local terrain = game:GetService("Workspace").Terrain
	local model = newRockModel(terrain)

	local regionFolder = newFolder(parentFolder, config.Name)
	local ruinsFolder = newFolder(regionFolder, "Ruins")
	local terracesFolder = newFolder(regionFolder, "Terraces")
	local coralFolder = newFolder(regionFolder, "Coral")
	local entryPointsFolder = newFolder(regionFolder, "EntryPoints")
	local landmarksFolder = newFolder(regionFolder, "Landmarks")
	local lootSpotsFolder = newFolder(regionFolder, "LootSpots")

	local rotation = CFrame.Angles(0, config.Yaw or 0, 0)
	local baseCFrame = CFrame.new(config.WorldCenter) * rotation
	local scale = config.Scale
	local function toWorld(rawPoint: Vector3): Vector3
		return (baseCFrame * CFrame.new(remapAxes(rawPoint - data.MassCenter) * scale)).Position
	end

	-- Plan the chambers first: their envelopes shape the mountain.
	local caverns = {}
	local sourceCaves = data.Cave
	if #sourceCaves > 0 then
		local biggest = sourceCaves[1]
		for _, cave in ipairs(sourceCaves) do
			if cave.Size.X * cave.Size.Y * cave.Size.Z > biggest.Size.X * biggest.Size.Y * biggest.Size.Z then
				biggest = cave
			end
		end
		local main = planCavern(toWorld(biggest.Center), biggest.Size, scale, CAVERN_ENLARGE)
		main.main = true
		table.insert(caverns, main)
		for _, cave in ipairs(sourceCaves) do
			if cave ~= biggest then
				table.insert(caverns, planCavern(toWorld(cave.Center), cave.Size, scale, 3.5))
			end
		end
	else
		-- Region 3/4's "with entries" versions describe no separate chamber:
		-- synthesize one at the mass centroid.
		local main = planCavern(toWorld(data.MassCenter), Vector3.new(70, 60, 50), scale, 1)
		main.main = true
		table.insert(caverns, main)
	end
	local mainCavern = caverns[1]

	-- 1. Rock: the authored tiers, an envelope around every chamber, and a
	-- skirt rooting the whole thing in the seafloor.
	local tiers = fillMassTiers(model, data, toWorld, scale)
	for _, cavern in ipairs(caverns) do
		fillBall(model, cavern.center, cavern.radius + CAVERN_SHELL, true)
	end
	local reach, baseY, topY = 0, math.huge, -math.huge
	local center = config.WorldCenter
	local function grow(position: Vector3, radius: number, bottom: number, top: number)
		local dx, dz = position.X - center.X, position.Z - center.Z
		reach = math.max(reach, math.sqrt(dx * dx + dz * dz) + radius)
		baseY = math.min(baseY, bottom)
		topY = math.max(topY, top)
	end
	for _, tier in ipairs(tiers) do
		grow(tier.center, tier.radius, tier.center.Y - tier.height / 2, tier.center.Y + tier.height / 2)
	end
	for _, cavern in ipairs(caverns) do
		local r = cavern.radius + CAVERN_SHELL
		grow(cavern.center, r, cavern.center.Y - r, cavern.center.Y + r)
	end
	fillSkirt(model, center, reach * 0.8, baseY + 20, rng)

	-- 2. Where the solid mountain ends along each authored entry bearing
	-- (and straight up, for a summit shaft) -- measured before anything is
	-- carved, so a march never mistakes another tunnel for open water.
	local entries = {}
	for index, entry in ipairs(data.Entries) do
		local direction = toWorld(entry.CorridorCenter) - mainCavern.center
		direction = Vector3.new(direction.X, math.max(direction.Y, -0.25 * direction.Magnitude), direction.Z)
		if direction.Magnitude < 1 then
			direction = rotation.RightVector
		end
		direction = direction.Unit
		local exit = marchOut(model, mainCavern.center, direction, 900)
		local radius = (index == 1) and (13 * scale) or (9 * scale)
		if exit and exit.Y - radius > FLOOR_Y + 4 then
			table.insert(entries, { name = entry.Name, exit = exit, direction = direction, radius = radius })
		end
	end
	local shaftExit = marchOut(model, mainCavern.center, Vector3.new(0, 1, 0), 400)
	if shaftExit and shaftExit.Y < -SURFACE_CLEARANCE / 2 then
		table.insert(entries, { name = "SummitShaft", exit = shaftExit, direction = Vector3.new(0, 1, 0), radius = 11 * scale })
	end

	-- 3. Chambers, linked back to the main one: a network, not bubbles.
	for _, cavern in ipairs(caverns) do
		fillBall(model, cavern.center, cavern.radius, false)
	end
	for _, cavern in ipairs(caverns) do
		if cavern ~= mainCavern then
			carveTunnel(model, cavern.center, mainCavern.center, 16 * scale)
		end
	end

	-- 4. Entry tunnels, from just outside the rock to the main chamber.
	for _, entry in ipairs(entries) do
		entry.mouth = entry.exit + entry.direction * TUNNEL_EXIT_MARGIN
		carveTunnel(model, entry.mouth, mainCavern.center, entry.radius)
		marker(entryPointsFolder, "EntryPoint_" .. entry.name, entry.exit)
	end

	-- 5. Ruins, terraces, corals -- resting on the rock, turned with the region.
	local placed, dropped = 0, 0
	local function placeSeed(seed, folder: Instance, size: Vector3, material: Enum.Material, collide: boolean)
		local position = restOnRock(model, toWorld(seed.Center), size.Y / 2)
		if position then
			placed += 1
			return buildProp(folder, seed, size, position, rotation, material, collide)
		end
		dropped += 1
		return nil
	end
	for _, seed in ipairs(data.Ruins) do
		placeSeed(seed, ruinsFolder, Vector3.new(math.max(seed.Size.X * scale, 1), math.max(seed.Size.Z * scale, 1), math.max(seed.Size.Y * scale, 1)), Enum.Material.Slate, true)
	end
	for _, seed in ipairs(data.Terraces) do
		placeSeed(seed, terracesFolder, Vector3.new(math.max(seed.Size.X * scale, 1), math.max(seed.Size.Z * scale, 1), math.max(seed.Size.Y * scale, 1)), Enum.Material.Rock, true)
	end
	for _, seed in ipairs(data.Corals) do
		local size = Vector3.new(3 + rng:NextNumber() * 3, 3 + rng:NextNumber() * 4, 3 + rng:NextNumber() * 3)
		local coral = placeSeed(seed, coralFolder, size, Enum.Material.Pebble, false)
		if coral then
			coral.Shape = Enum.PartType.Ball
			coral.Color = CAVE_CORAL_COLORS[rng:NextInteger(1, #CAVE_CORAL_COLORS)]
			coral.CastShadow = false
		end
	end

	for _, seed in ipairs(data.Markers) do
		marker(landmarksFolder, seed.Name, toWorld(seed.Center))
	end

	-- 6. Life inside the chambers.
	local decorCount = decorateCaverns(model, regionFolder, caverns, rng)

	-- 7. Loot and cave dwellers in the main chamber. RegionWanderRadius
	-- keeps what spawns here roaming the chamber instead of wandering off
	-- through the rock (creatures have no obstacle avoidance).
	addSpawnRegion(lootSpotsFolder, "LootSpot_MainCavern", mainCavern.center, Vector3.new(1, 0.5, 1) * mainCavern.radius * 1.1, "Treasure", {
		RegionCount = config.TreasureCount or 5,
	})
	addSpawnRegion(regionFolder, "CreatureRegion", mainCavern.center, Vector3.new(1, 0.5, 1) * mainCavern.radius * 1.1, "Creature", {
		RegionCount = config.CreatureCount or 4,
		RegionSpecies = config.CreatureSpecies or "RequinRecif,RaieManta",
		RegionWanderRadius = math.floor(mainCavern.radius * 0.55),
	})

	regionFolder:SetAttribute("DisplayName", config.DisplayName)
	print(string.format("[CaveRegionBuilder] %s: %d chambers, %d entries, %d/%d seeds resting on rock, %d cavern props",
		config.Name, #caverns, #entryPointsFolder:GetChildren(), placed, placed + dropped, decorCount))

	return regionFolder, {
		center = center,
		caverns = caverns,
		entries = entries,
		extent = { radius = reach * 1.05 + 12, minY = FLOOR_Y, maxY = topY },
	}
end

return CaveRegionBuilder
