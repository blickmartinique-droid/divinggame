-- The seabed's relief: the beach island is the summit of a volcanic
-- seamount, so a dive is one continuous descent instead of a drop into an
-- empty box --
--   * the reef crest just past the beach, then the "tombant", a near-
--     vertical reef wall down to ~110 m;
--   * a steep flank easing into long slopes down to the abyssal plain;
--   * a flat sandy terrace at ~330 m on the north-east flank, where the
--     galleon wreck lies (Shipwreck.lua);
--   * a massive rocky spur on the north-west flank, rising to ~50 m, that
--     holds the cave network (Caves.lua carves it);
--   * on the abyssal plain, a rift: two long basalt ridges with a canyon
--     between them, home of the hydrothermal vents.
--
-- The surface is a heightfield (height per x/z, from deterministic noise)
-- written as thin Terrain columns: rock up to a few studs under the
-- surface, then a top layer whose material follows depth and slope --
-- pale reef limestone in the shallows, sand on gentle slopes and terraces,
-- rock/slate on cliffs, dark mud and basalt in the abyss. Terrain fills
-- give partial occupancy to the top voxel, so neighbouring columns of
-- different heights render as smooth slopes, not steps. Cliff strata are
-- painted afterwards with ReplaceMaterial bands.
--
-- Publishes layout:GroundHeight (used by IsFree, decor, the wreck, the
-- spawners) and anchors: WreckSite, CaveSpur, RiftFrame.

local Workspace = game:GetService("Workspace")

local Noise = require(script.Parent.Noise)
local WorldLayout = require(script.Parent.WorldLayout)

local Seabed = {}

local FLOOR_Y = WorldLayout.FloorY
local FINE = 4 -- column size near the island
local COARSE = 8 -- column size on the open plain
local FINE_RADIUS = 600
local TOP_LAYER = 3
local YIELD_EVERY = 2500

-- Geography (bearings in degrees from +X toward +Z) ----------------------------------

Seabed.WRECK_BEARING = 35
Seabed.WRECK_DISTANCE = 400
Seabed.WRECK_DEPTH = -330
Seabed.SPUR_BEARING = 155
Seabed.RIFT_BEARING = 300
Seabed.RIFT_DISTANCE = 720

local function bearingVector(degrees: number): (number, number)
	local a = math.rad(degrees)
	return math.cos(a), math.sin(a)
end

-- Island profile: (radius, height) control points, smoothly interpolated.
local PROFILE = {
	-- Up to the beach's edge the rock sits right under the sand tiers.
	{ 0, -16 }, { 176, -18 }, { 192, -52 }, { 212, -112 }, { 250, -150 },
	{ 330, -245 }, { 430, -385 }, { 520, -468 }, { 610, -500 },
}

local function smoothstep(a: number, b: number, x: number): number
	local t = math.clamp((x - a) / (b - a), 0, 1)
	return t * t * (3 - 2 * t)
end

local function profile(r: number): number
	for i = 2, #PROFILE do
		local r1, h1 = PROFILE[i][1], PROFILE[i][2]
		if r <= r1 then
			local r0, h0 = PROFILE[i - 1][1], PROFILE[i - 1][2]
			local t = (r - r0) / (r1 - r0)
			t = t * t * (3 - 2 * t)
			return h0 + (h1 - h0) * t
		end
	end
	return FLOOR_Y
end

-- The height function --------------------------------------------------------------

function Seabed.CreateHeightFunction(seed: number)
	local noise = Noise.new(seed)
	local detail = Noise.new(seed + 17)
	local wreckX, wreckZ = bearingVector(Seabed.WRECK_BEARING)
	wreckX, wreckZ = wreckX * Seabed.WRECK_DISTANCE, wreckZ * Seabed.WRECK_DISTANCE
	local spurX, spurZ = bearingVector(Seabed.SPUR_BEARING)
	local riftDirX, riftDirZ = bearingVector(Seabed.RIFT_BEARING)
	local riftX, riftZ = riftDirX * Seabed.RIFT_DISTANCE, riftDirZ * Seabed.RIFT_DISTANCE
	-- The rift runs across its bearing (tangentially).
	local riftAlongX, riftAlongZ = -riftDirZ, riftDirX

	return function(x: number, z: number): number
		local r = math.sqrt(x * x + z * z)
		local theta = math.atan2(z, x)

		-- Seamount: the crest stays a clean ring around the beach; further
		-- out the radius wobbles so the flanks have bays and headlands.
		local warp = 1 + smoothstep(190, 280, r) * (0.2 * noise:Fbm(math.cos(theta) * 2.2 + 11, math.sin(theta) * 2.2 + 11, 3) + 0.07 * noise:Fbm(x / 110, z / 110, 2))
		local h = profile(r / warp)
		local roughness = 2 + smoothstep(190, 450, r) * 14
		h += detail:Fbm(x / 55, z / 55, 4) * roughness
		-- Rocky ribs and gullies running down the flanks, and outcrops.
		local flank = smoothstep(215, 300, r) * (1 - smoothstep(560, 640, r))
		h += noise:Ridged(x / 95, z / 95, 3) * 16 * flank
		h += math.max(0, detail:Fbm(x / 38 + 7, z / 38 - 3, 2) - 0.25) * 30 * flank

		-- Cave spur: a long rounded ridge down the NW flank, with cliffs.
		local along = x * spurX + z * spurZ
		if along > 150 and along < 640 then
			local across = math.abs(x * -spurZ + z * spurX)
			local crest = -50 - (along - 200) * 0.4 + detail:Fbm(along / 45, 3.3, 3) * 8
			local halfWidth = 105 + (along - 150) * 0.08
			local spur = crest - math.max(0, across - halfWidth * 0.45) ^ 1.35 * 0.9
			spur -= smoothstep(560, 640, along) * 220
			h = math.max(h, spur + detail:Fbm(x / 30, z / 30, 3) * 5)
		end

		-- Wreck terrace: a flat, sandy ledge cut into the NE flank.
		local dx, dz = x - wreckX, z - wreckZ
		local radial = (dx * wreckX + dz * wreckZ) / Seabed.WRECK_DISTANCE
		local tangent = (dx * -wreckZ + dz * wreckX) / Seabed.WRECK_DISTANCE
		local ellipse = math.sqrt((tangent / 265) ^ 2 + (radial / 145) ^ 2)
		-- A wide blend band so the ledge eases into the slope below it (a
		-- narrow one left a flat table standing on a cliff).
		if ellipse < 1.8 then
			local shelf = Seabed.WRECK_DEPTH + detail:Fbm(x / 40, z / 40, 2) * 1.5
			h += (shelf - h) * smoothstep(1.8, 0.85, ellipse)
		end

		-- Abyssal rift: twin basalt ridges with a canyon between them.
		local rdx, rdz = x - riftX, z - riftZ
		local rAlong = rdx * riftAlongX + rdz * riftAlongZ
		local rAcross = rdx * riftDirX + rdz * riftDirZ
		if math.abs(rAlong) < 300 and math.abs(rAcross) < 140 then
			local taper = 1 - smoothstep(170, 300, math.abs(rAlong))
			local ridge = math.exp(-((math.abs(rAcross) - 48) / 22) ^ 2)
			local rift = FLOOR_Y + (70 + noise:Ridged(rAlong / 60, rAcross / 60, 3) * 18) * ridge * taper
			h = math.max(h, rift)
		end

		-- Gentle swells on the open plain.
		if r > 480 then
			h = math.max(h, FLOOR_Y + math.max(0, detail:Fbm(x / 140, z / 140, 3)) * 14)
		end

		return math.max(h, FLOOR_Y)
	end
end

-- Top-layer material from depth and slope.
local function topMaterial(height: number, slope: number): Enum.Material
	if height > -70 then
		return slope < 0.45 and Enum.Material.Sand or Enum.Material.Limestone
	elseif height > -380 then
		if slope < 0.35 then
			return Enum.Material.Sand
		end
		return slope < 0.9 and Enum.Material.Ground or Enum.Material.Rock
	end
	if slope < 0.3 then
		return Enum.Material.Mud
	end
	return Enum.Material.Basalt
end

local function writeColumn(terrain: Terrain, x: number, z: number, size: number, height: number, slope: number)
	local bottom = FLOOR_Y - 4
	local rockTop = height - TOP_LAYER
	if rockTop > bottom then
		terrain:FillBlock(CFrame.new(x, (bottom + rockTop) / 2, z), Vector3.new(size, rockTop - bottom, size), Enum.Material.Rock)
	end
	local layerBottom = math.max(bottom, rockTop)
	terrain:FillBlock(CFrame.new(x, (layerBottom + height) / 2, z), Vector3.new(size, height - layerBottom, size), topMaterial(height, slope))
end

local function paintStrata(terrain: Terrain)
	-- Darker bands across every cliff, like layered volcanic rock.
	for _, band in ipairs({ { -128, -140 }, { -200, -212 }, { -280, -292 }, { -350, -360 } }) do
		local region = Region3.new(Vector3.new(-FINE_RADIUS, band[2], -FINE_RADIUS), Vector3.new(FINE_RADIUS, band[1], FINE_RADIUS)):ExpandToGrid(4)
		terrain:ReplaceMaterial(region, 4, Enum.Material.Rock, Enum.Material.Slate)
		terrain:ReplaceMaterial(region, 4, Enum.Material.Ground, Enum.Material.Slate)
	end
end

function Seabed.Build(layout)
	local terrain = Workspace.Terrain
	local heightAt = Seabed.CreateHeightFunction(layout.seed)
	local columns = 0

	-- Fine grid around the island: heights first, so slopes come from
	-- neighbours without evaluating the noise twice.
	local cells = math.floor(FINE_RADIUS * 2 / FINE)
	local heights = table.create(cells + 2)
	for i = 0, cells + 1 do
		local row = table.create(cells + 2)
		heights[i] = row
		local x = -FINE_RADIUS + (i - 0.5) * FINE
		for j = 0, cells + 1 do
			row[j] = heightAt(x, -FINE_RADIUS + (j - 0.5) * FINE)
		end
	end
	for i = 1, cells do
		local x = -FINE_RADIUS + (i - 0.5) * FINE
		for j = 1, cells do
			local z = -FINE_RADIUS + (j - 0.5) * FINE
			local height = heights[i][j]
			if height > FLOOR_Y + 0.5 then
				local gx = (heights[i + 1][j] - heights[i - 1][j]) / (2 * FINE)
				local gz = (heights[i][j + 1] - heights[i][j - 1]) / (2 * FINE)
				writeColumn(terrain, x, z, FINE, height, math.sqrt(gx * gx + gz * gz))
				columns += 1
				if columns % YIELD_EVERY == 0 then
					task.wait()
				end
			end
		end
	end

	-- Coarse grid for the rest of the ocean floor (the rift, the swells).
	local half = WorldLayout.OceanHalfWidth
	for x = -half + COARSE / 2, half, COARSE do
		for z = -half + COARSE / 2, half, COARSE do
			if math.abs(x) >= FINE_RADIUS or math.abs(z) >= FINE_RADIUS then
				local height = heightAt(x, z)
				if height > FLOOR_Y + 0.5 then
					local slope = math.abs(heightAt(x + COARSE, z) - height) / COARSE + math.abs(heightAt(x, z + COARSE) - height) / COARSE
					writeColumn(terrain, x, z, COARSE, height, slope)
					columns += 1
					if columns % YIELD_EVERY == 0 then
						task.wait()
					end
				end
			end
		end
	end

	paintStrata(terrain)

	-- The ground, for everything placed afterwards (the beach tiers win
	-- where they stand higher than the rock under them).
	-- Snapped to the column the point falls in, so what is placed on the
	-- ground sits on the terrain actually written (on a cliff, the exact
	-- noise height and its 4-stud column can differ by several studs).
	local function columnHeight(x: number, z: number): number
		if math.abs(x) < FINE_RADIUS and math.abs(z) < FINE_RADIUS then
			local i = math.clamp(math.floor((x + FINE_RADIUS) / FINE) + 1, 1, cells)
			local j = math.clamp(math.floor((z + FINE_RADIUS) / FINE) + 1, 1, cells)
			return heights[i][j]
		end
		local cx = math.floor((x + WorldLayout.OceanHalfWidth) / COARSE) * COARSE - WorldLayout.OceanHalfWidth + COARSE / 2
		local cz = math.floor((z + WorldLayout.OceanHalfWidth) / COARSE) * COARSE - WorldLayout.OceanHalfWidth + COARSE / 2
		return heightAt(cx, cz)
	end
	layout:SetGround(function(x: number, z: number): number
		local h = columnHeight(x, z)
		local r = math.sqrt(x * x + z * z)
		if r < 70 then
			return math.max(h, 4)
		elseif r < 140 then
			return math.max(h, -6)
		elseif r < 180 then
			return math.max(h, -15)
		end
		return h
	end)

	local wx, wz = bearingVector(Seabed.WRECK_BEARING)
	layout:SetAnchor("WreckSite", {
		position = Vector3.new(wx * Seabed.WRECK_DISTANCE, Seabed.WRECK_DEPTH, wz * Seabed.WRECK_DISTANCE),
		-- Lengthwise along the terrace (tangent to the slope).
		lengthAxis = Vector3.new(-wz, 0, wx),
		outward = Vector3.new(wx, 0, wz),
	})
	local sx, sz = bearingVector(Seabed.SPUR_BEARING)
	layout:SetAnchor("CaveSpur", { along = Vector3.new(sx, 0, sz), across = Vector3.new(-sz, 0, sx) })
	local rx, rz = bearingVector(Seabed.RIFT_BEARING)
	layout:SetAnchor("RiftFrame", {
		center = Vector3.new(rx * Seabed.RIFT_DISTANCE, FLOOR_Y, rz * Seabed.RIFT_DISTANCE),
		along = Vector3.new(-rz, 0, rx),
		across = Vector3.new(rx, 0, rz),
	})

	print(string.format("[Seabed] %d terrain columns", columns))
end

return Seabed
