-- Builds the "mega wreck" -- a huge sunken ship -- from
-- MegaWreckShipData.lua, an auto-generated table of ~645 part records
-- extracted from pirate_megaship_explorable.glb (see that file's header
-- for exactly how). This is a genuine limitation worth stating plainly:
-- this session has no path to run Roblox Studio's mesh importer or
-- Roblox's asset-upload API, so the source .glb's actual curved/smoothed
-- geometry cannot be turned into real MeshParts here. What CAN be done
-- losslessly is extract each of the model's 645 named sub-objects' exact
-- oriented bounding box (position, rotation, size) and average colour and
-- rebuild it as a Part -- a faithful low-poly proxy of the real model's
-- layout, scale and room structure, in the same "boxy primitives" style
-- OceanGenerator/WorldDecor already use elsewhere in this project. If the
-- .glb is later imported for real (Studio's "Import 3D", or Blender ->
-- .fbx -> Studio bulk import), the resulting MeshParts can be dropped in
-- to replace these boxes 1:1 by name -- the folder layout and all the
-- gameplay hooks below (EntryPoints/LootSpots/Landmarks/InteractionPoints)
-- do not depend on the visual representation and need no changes.
--
-- Hierarchy (matches the requested spec): Workspace/World/Underwater/
-- WreckZone/MegaWreckShip, with two organisational parents --
--   Exterior: Hull (CanCollide = true -- see below), Railings, Masts,
--             BrokenSails, Rigging, Cannons, Decoration, Debris
--             (CanCollide = false: fiddly detail nobody should catch on).
--   Interior: Decks, Corridors, Rooms, Stairs (CanCollide = true: these
--             are literally the floor/ceiling/wall/step plates).
-- plus Collision (currently unused -- see below), and EntryPoints /
-- LootSpots / Landmarks / InteractionPoints -- Attachments/marker Parts
-- for future systems.
--
-- Hull collision: the model's own hull_wall_<side>_<station> and
-- hull_wall_upper_<side>_<station> segments (16 total minus whichever are
-- breached) ARE the hull collider -- individually correctly sized/placed
-- panels of the real skin, so a breach (skipped at creation, both here and
-- as a visual) is a genuine hole in the collision too, not just the
-- visuals. An earlier version instead reused the model's 4 "hull_layer_*"
-- pieces as one big simplified invisible collider per side; those turned
-- out to be near-full-length, near-full-height CENTRAL slabs (not thin
-- exterior shells), so as colliders they formed one solid, un-breached
-- wall straight through the ship's midline -- exactly what made the wreck
-- impossible to enter. They are now skipped entirely (see below).
--
-- Scale/placement/tilt/damage staging are the only "artistic" numbers
-- here; the geometry itself is 100% data-driven from the source model.

local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")

local WreckData = require(script.Parent.MegaWreckShipData)

-- Placement -------------------------------------------------------------------

-- The source model's own vertical axis is its Z, not Y: raw Y is a
-- narrow, symmetric ~-18..18 range (the hull's BEAM, symmetric about the
-- centerline) while raw Z is a tall, asymmetric ~-12.5..58 range (keel to
-- masthead) -- confirmed beyond doubt by the masts, whose long axis (34-46
-- studs) is their Size.Z, with only a ~3-stud pole diameter on X/Y. Every
-- record's Center/Right/Up is therefore run through remapAxes (swap Y and
-- Z) before use, so the ship's real height ends up along Roblox's +Y
-- instead of sideways along Z. Sizes need no remap -- swapping which
-- world axis a local direction vector points along doesn't change how far
-- the box extends along it.
local function remapAxes(v: Vector3): Vector3
	return Vector3.new(v.X, v.Z, v.Y)
end

-- Right next to EpaveVortex (CurrentGenerator.server.lua) and the small
-- placeholder silhouette WorldDecor used to build here (now removed in
-- favour of this) -- the existing Épave zone's landmark slot. Raw model
-- is ~201 long x ~70.5 tall x ~36.4 beam (see remapAxes above); at this
-- scale that is ~724 x ~254 x ~131 studs -- masts reaching up toward
-- Grottes, keel resting near the bottom of Épave, still comfortably a
-- biome-scale landmark without spanning all the way to the surface.
local SHIP_CENTER = Vector3.new(150, -359, -150)
local SHIP_SCALE = 3.6
local SHIP_ROLL = math.rad(15) -- listing to one side, like it settled on the seabed
local SHIP_PITCH = math.rad(4) -- very slightly bow-down
local SHIP_YAW = math.rad(35) -- off the world axes, reads as "settled" rather than neatly placed

local shipCFrame = CFrame.new(SHIP_CENTER) * CFrame.Angles(SHIP_PITCH, SHIP_YAW, SHIP_ROLL)

-- A few of the hull's lower/upper skin segments are skipped entirely
-- (real gaps in the geometry, not a transparent trick) so the player can
-- actually swim into the hull; an EntryPoint marks each. The model names
-- each hull skin segment "hull_wall[_upper]_<side>_<station>" (side -1/1 =
-- port/starboard, station 0-3 = bow-to-stern), so keys below are
-- "<side>_<station>" strings, picked by hand for a spread across both
-- sides and the hull's length: starboard bow, port forward-mid, starboard
-- stern (lower), plus one port midship opening higher up.
local HULL_BREACH_LOWER = { ["1_0"] = true, ["-1_1"] = true, ["1_3"] = true }
local HULL_BREACH_UPPER = { ["-1_2"] = true }

-- Roughly 40% of sails are gone entirely (blown away); the rest are torn
-- (partial transparency + a small extra tilt) rather than crisp and taut.
local SAIL_SKIP_EVERY = 3
local SNAPPED_MAST_NAME = "mast_1" -- the one mast given an extra broken-looking lean

-- Corridors were a passable but tight ~14x12-stud tube (raw 4x3.4 studs x
-- SHIP_SCALE) -- fine, but "agrandir certains couloirs" is explicitly
-- authorised and a wider tube reads much better at this monumental scale.
-- Widens each segment's wall1/wall2/floor/ceiling around its own central
-- axis (not the ship's), so segments at different heights/positions each
-- widen correctly in place instead of drifting toward a shared origin.
local CORRIDOR_WIDEN_FACTOR = 1.6

-- Rooms an explorer should remember: warm lantern light instead of the
-- default cool blue, per the brief's "quelques lumières chaudes très
-- faibles dans certaines salles importantes."
local WARM_ROOMS = { captain_suite = true, chart_room = true, bridge_hall = true }

-- Lighting palette -- dark blue/cyan/turquoise throughout, warm lantern
-- only in WARM_ROOMS above. Kept low-brightness/short-range/no-shadow by
-- default (a "mega wreck" could otherwise mean hundreds of dynamic
-- shadow-casters); CastShadow is only ever turned on for the handful of
-- warm hero lights, where the shadow actually reads as a lantern-lit room.
local COOL_LIGHT_COLOR = Color3.fromRGB(80, 180, 200)
local WARM_LIGHT_COLOR = Color3.fromRGB(255, 185, 120)
local ENTRANCE_LIGHT_COLOR = Color3.fromRGB(150, 215, 235)
local NAV_LOW_COLOR = Color3.fromRGB(85, 165, 185)
local NAV_HIGH_COLOR = Color3.fromRGB(150, 195, 180)
local AMBIENT_LIGHT_COLOR = Color3.fromRGB(70, 140, 130)

-- Folders -----------------------------------------------------------------------

local function ensureFolder(parent: Instance, name: string): Folder
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("Folder") then
		return existing
	end
	if existing then
		existing:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

local worldFolder = ensureFolder(Workspace, "World")
local underwaterFolder = ensureFolder(worldFolder, "Underwater")
local wreckZoneFolder = ensureFolder(underwaterFolder, "WreckZone")

local existingShip = wreckZoneFolder:FindFirstChild("MegaWreckShip")
if existingShip then
	existingShip:Destroy()
end
local shipFolder = Instance.new("Folder")
shipFolder.Name = "MegaWreckShip"
shipFolder.Parent = wreckZoneFolder

local exteriorFolder = ensureFolder(shipFolder, "Exterior")
local interiorFolder = ensureFolder(shipFolder, "Interior")
local hullFolder = ensureFolder(exteriorFolder, "Hull")
local railingsFolder = ensureFolder(exteriorFolder, "Railings")
local mastsFolder = ensureFolder(exteriorFolder, "Masts")
local sailsFolder = ensureFolder(exteriorFolder, "BrokenSails")
local riggingFolder = ensureFolder(exteriorFolder, "Rigging")
local cannonsFolder = ensureFolder(exteriorFolder, "Cannons")
local decorationFolder = ensureFolder(exteriorFolder, "Decoration")
local debrisFolder = ensureFolder(exteriorFolder, "Debris")
local decksFolder = ensureFolder(interiorFolder, "Decks")
local corridorsFolder = ensureFolder(interiorFolder, "Corridors")
local roomsFolder = ensureFolder(interiorFolder, "Rooms")
local stairsFolder = ensureFolder(interiorFolder, "Stairs")
-- Kept empty for now (see the header comment on hull collision above) --
-- reserved for real simplified colliders if/when the model is imported
-- for real and needs a proper low-poly physics proxy.
ensureFolder(shipFolder, "Collision")
local entryPointsFolder = ensureFolder(shipFolder, "EntryPoints")
local landmarksFolder = ensureFolder(shipFolder, "Landmarks")
local lootSpotsFolder = ensureFolder(shipFolder, "LootSpots")
local interactionPointsFolder = ensureFolder(shipFolder, "InteractionPoints")

-- Interior lighting rework (see the bottom of this script): organised per
-- the requested spec, adapted to this file's existing layout -- Rooms/
-- Corridors/Stairs already live under Interior and are reused/widened in
-- place rather than duplicated into a separate "ReworkedInterior" tree.
local lightingFolder = ensureFolder(shipFolder, "Lighting")
local corridorLightsFolder = ensureFolder(lightingFolder, "CorridorLights")
local roomLightsFolder = ensureFolder(lightingFolder, "RoomLights")
local entranceLightsFolder = ensureFolder(lightingFolder, "EntranceLights")
local navigationLightsFolder = ensureFolder(lightingFolder, "NavigationLights")
local ambientLightsFolder = ensureFolder(lightingFolder, "AmbientLights")

local CATEGORY_FOLDERS = {
	Hull = hullFolder,
	Railings = railingsFolder,
	Masts = mastsFolder,
	BrokenSails = sailsFolder,
	Rigging = riggingFolder,
	Cannons = cannonsFolder,
	Decoration = decorationFolder,
	Decks = decksFolder,
	Corridors = corridorsFolder,
	Stairs = stairsFolder,
}

-- CanCollide = false for exterior detail categories nobody should catch
-- on while swimming past (rigging, rails, loose cannons, decoration).
-- Hull is deliberately NOT in this list: its individual skin segments are
-- the ship's real hull collider (see the header comment above).
local EXTERIOR_NO_COLLIDE = {
	Railings = true,
	Masts = false, -- a mast is a single clean cylinder-ish shape; fine to collide with
	BrokenSails = true,
	Rigging = true,
	Cannons = true,
	Decoration = true,
}

-- Materials per category, so the wreck doesn't read as one uniform grey
-- blockout -- SmoothPlastic for the ship's own structure (its vertex
-- colours from the source model do the real work), wood-family materials
-- where that reads better (masts, rails, stairs), metal for cannons.
local CATEGORY_MATERIAL = {
	Hull = Enum.Material.WoodPlanks,
	Railings = Enum.Material.Wood,
	Masts = Enum.Material.Wood,
	BrokenSails = Enum.Material.Fabric,
	Rigging = Enum.Material.Fabric, -- there is no "Rope" Material in Roblox; Fabric reads closest for rope/rigging
	Cannons = Enum.Material.Metal,
	Decoration = Enum.Material.SmoothPlastic,
	Decks = Enum.Material.WoodPlanks,
	Corridors = Enum.Material.WoodPlanks,
	Stairs = Enum.Material.Wood,
	Rooms = Enum.Material.WoodPlanks,
}

-- Building ------------------------------------------------------------------------

local function partCFrame(record)
	return shipCFrame * CFrame.fromMatrix(remapAxes(record.Center) * SHIP_SCALE, remapAxes(record.Right), remapAxes(record.Up))
end

local function partSize(record)
	return record.Size * SHIP_SCALE
end

local function buildPart(record, parent: Instance, overrides: { [string]: any }?)
	overrides = overrides or {}
	local part = Instance.new("Part")
	part.Name = record.Name
	part.Anchored = true
	part.CanTouch = false
	part.CanQuery = overrides.CanQuery ~= false
	part.CastShadow = overrides.CastShadow ~= false
	part.CFrame = overrides.CFrame or partCFrame(record)
	part.Size = overrides.Size or partSize(record)
	part.Color = overrides.Color or record.Color
	part.Material = overrides.Material or CATEGORY_MATERIAL[record.Category] or Enum.Material.SmoothPlastic
	part.Transparency = overrides.Transparency or 0
	if overrides.CanCollide ~= nil then
		part.CanCollide = overrides.CanCollide
	else
		part.CanCollide = not EXTERIOR_NO_COLLIDE[record.Category]
	end
	part.Parent = parent
	return part
end

-- Corridor widening pre-pass: pushes each segment's wall1/wall2 (offset
-- from the corridor's own centerline in raw Y) and floor/ceiling (offset
-- in raw Z) outward by CORRIDOR_WIDEN_FACTOR, growing their Size to match
-- -- widening around each segment's OWN axis (not the ship's shared
-- origin), since the 3 segments sit at different heights/positions.
local corridorOverride = {} -- [recordName] = { Center: Vector3, Size: Vector3 }
do
	local segments = {}
	for _, record in ipairs(WreckData) do
		if record.Category == "Corridors" then
			local segmentName, part = record.Name:match("^(corridor_%d+)_(%a+)$")
			if segmentName then
				segments[segmentName] = segments[segmentName] or {}
				segments[segmentName][part] = record
			end
		end
	end

	for _, seg in pairs(segments) do
		if seg.floor and seg.ceiling and seg.wall1 and seg.wall2 then
			local centerZ = (seg.floor.Center.Z + seg.ceiling.Center.Z) / 2
			corridorOverride[seg.wall1.Name] = {
				Center = Vector3.new(seg.wall1.Center.X, seg.wall1.Center.Y * CORRIDOR_WIDEN_FACTOR, seg.wall1.Center.Z),
				Size = Vector3.new(seg.wall1.Size.X, seg.wall1.Size.Y, seg.wall1.Size.Z * CORRIDOR_WIDEN_FACTOR),
			}
			corridorOverride[seg.wall2.Name] = {
				Center = Vector3.new(seg.wall2.Center.X, seg.wall2.Center.Y * CORRIDOR_WIDEN_FACTOR, seg.wall2.Center.Z),
				Size = Vector3.new(seg.wall2.Size.X, seg.wall2.Size.Y, seg.wall2.Size.Z * CORRIDOR_WIDEN_FACTOR),
			}
			corridorOverride[seg.floor.Name] = {
				Center = Vector3.new(seg.floor.Center.X, seg.floor.Center.Y, centerZ + (seg.floor.Center.Z - centerZ) * CORRIDOR_WIDEN_FACTOR),
				Size = Vector3.new(seg.floor.Size.X, seg.floor.Size.Y * CORRIDOR_WIDEN_FACTOR, seg.floor.Size.Z),
			}
			corridorOverride[seg.ceiling.Name] = {
				Center = Vector3.new(seg.ceiling.Center.X, seg.ceiling.Center.Y, centerZ + (seg.ceiling.Center.Z - centerZ) * CORRIDOR_WIDEN_FACTOR),
				Size = Vector3.new(seg.ceiling.Size.X, seg.ceiling.Size.Y * CORRIDOR_WIDEN_FACTOR, seg.ceiling.Size.Z),
			}
		end
	end
end

local function applyCorridorWiden(record)
	local override = corridorOverride[record.Name]
	if not override then
		return record
	end
	return {
		Name = record.Name, Category = record.Category, Room = record.Room,
		Center = override.Center, Right = record.Right, Up = record.Up,
		Size = override.Size, Color = record.Color,
	}
end

-- Hull skin: skip the chosen breach segments entirely (a real hole), mark
-- the model's own big cross-section slabs (hull_layer_*) as invisible and
-- moved into Collision instead of the visible Hull folder -- those are
-- the actual outer hull collider (see the header comment for why).
local roomRecords = {} -- [roomName] = { record, ... }
local mastRecordByName = {}
local corridorParts = {} -- [segmentName] = { floor=Part, ceiling=Part }
local stairParts = {} -- [stairName] = Part
local sailIndex = 0

for _, rawRecord in ipairs(WreckData) do
	local record = applyCorridorWiden(rawRecord)
	if record.Category == "Hull" and record.Name:match("^hull_layer_") then
		-- Skipped entirely -- see the header comment: these are big central
		-- slabs, not a thin exterior shell, and were the cause of the
		-- "can't get in, invisible wall" bug when used as a collider.
		continue
	end

	do
		local upperSide, upperStation = record.Name:match("^hull_wall_upper_(%-?%d+)_(%d+)$")
		if upperSide then
			if HULL_BREACH_UPPER[upperSide .. "_" .. upperStation] then
				continue
			end
		else
			local side, station = record.Name:match("^hull_wall_(%-?%d+)_(%d+)$")
			if side and HULL_BREACH_LOWER[side .. "_" .. station] then
				continue
			end
		end
	end

	if record.Category == "Rooms" then
		roomRecords[record.Room] = roomRecords[record.Room] or {}
		table.insert(roomRecords[record.Room], record)
		continue -- built below, once per room, into its own subfolder
	end

	if record.Category == "Masts" then
		local part = buildPart(record, mastsFolder)
		mastRecordByName[record.Name] = { record = record, part = part }
		continue
	end

	if record.Category == "BrokenSails" then
		sailIndex += 1
		if sailIndex % SAIL_SKIP_EVERY == 0 then
			continue -- blown away
		end
		buildPart(record, sailsFolder, {
			Transparency = 0.35,
			CFrame = partCFrame(record) * CFrame.Angles(math.rad((sailIndex * 37) % 11 - 5), math.rad((sailIndex * 53) % 9 - 4), 0),
		})
		continue
	end

	local folder = CATEGORY_FOLDERS[record.Category]
	if folder then
		local part = buildPart(record, folder)

		if record.Category == "Corridors" then
			local segmentName, piece = record.Name:match("^(corridor_%d+)_(%a+)$")
			if segmentName then
				corridorParts[segmentName] = corridorParts[segmentName] or {}
				corridorParts[segmentName][piece] = part
			end
		elseif record.Category == "Stairs" then
			stairParts[record.Name] = part
		end
	end
end

-- The chosen snapped mast leans at a broken angle rather than standing
-- straight -- the clearest "damage" a single rigid box can show.
local snapped = mastRecordByName[SNAPPED_MAST_NAME]
if snapped then
	snapped.part.CFrame = partCFrame(snapped.record) * CFrame.Angles(math.rad(22), 0, math.rad(10))
end

-- Rooms: each of the 9 named rooms gets its own subfolder under Rooms,
-- containing its floor/ceiling/wall plates -- a real walkable, enclosed
-- space rather than a pile of loose panels.
local ROOM_DISPLAY_NAMES = {
	armory = "Armurerie",
	ballroom_lounge = "Salon de bal",
	bridge_hall = "Passerelle",
	captain_suite = "Cabine du capitaine",
	cargo_hall = "Cale à cargaison",
	chart_room = "Salle des cartes",
	crew_mess = "Mess de l'équipage",
	crew_quarters = "Quartiers de l'équipage",
	galley = "Cambuse",
}

local roomFloorRecord = {} -- [roomName] = the room's own "_floor" record, for LootSpots below
local roomParts = {} -- [roomName] = { ceiling=Part, wall_x1=Part, wall_x2=Part, wall_y1a=Part, ... }

for roomName, records in pairs(roomRecords) do
	local roomFolder = Instance.new("Folder")
	roomFolder.Name = ROOM_DISPLAY_NAMES[roomName] or roomName
	roomFolder.Parent = roomsFolder
	roomParts[roomName] = {}
	for _, record in ipairs(records) do
		local part = buildPart(record, roomFolder, { CanCollide = true })
		if record.Name:match("_floor$") then
			roomFloorRecord[roomName] = record
			roomParts[roomName].floor = part
		elseif record.Name:match("_ceiling$") then
			roomParts[roomName].ceiling = part
		elseif record.Name:match("_wall_(.+)$") then
			roomParts[roomName][record.Name:match("_wall_(.+)$")] = part
		end
	end
end

-- Landmarks, entry points, interaction points --------------------------------------

-- Attachment-only markers: no functional behaviour yet, just named,
-- correctly-placed hooks for whatever reads them later (minimap, quest
-- system, prompts). Kept as plain Attachments parented to a small anchored
-- Part so they show up as real positioned Instances in the Explorer.
local function createMarker(parent: Instance, name: string, worldPosition: Vector3, attributes: { [string]: any }?)
	local anchor = Instance.new("Part")
	anchor.Name = name
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(1, 1, 1)
	anchor.CFrame = CFrame.new(worldPosition)
	if attributes then
		for key, value in pairs(attributes) do
			anchor:SetAttribute(key, value)
		end
	end
	local attachment = Instance.new("Attachment")
	attachment.Parent = anchor
	anchor.Parent = parent
	return anchor
end

local function worldPositionOf(record)
	return (shipCFrame * CFrame.new(remapAxes(record.Center) * SHIP_SCALE)).Position
end

-- Entry points: one per breached hull segment, found by name from the raw data.
for _, record in ipairs(WreckData) do
	local upperSide, upperStation = record.Name:match("^hull_wall_upper_(%-?%d+)_(%d+)$")
	if upperSide and HULL_BREACH_UPPER[upperSide .. "_" .. upperStation] then
		createMarker(entryPointsFolder, "EntryPoint_HullUpper_" .. upperSide .. "_" .. upperStation, worldPositionOf(record), { Level = "Upper" })
		continue
	end
	local side, station = record.Name:match("^hull_wall_(%-?%d+)_(%d+)$")
	if side and HULL_BREACH_LOWER[side .. "_" .. station] then
		createMarker(entryPointsFolder, "EntryPoint_Hull_" .. side .. "_" .. station, worldPositionOf(record), { Level = "Lower" })
	end
end

-- Landmarks: the ship's own signature features.
local LANDMARK_NAMES = { "figurehead", "funnel_0", "funnel_1", "stern_grand_stairs" }
for _, record in ipairs(WreckData) do
	if table.find(LANDMARK_NAMES, record.Name) then
		createMarker(landmarksFolder, record.Name, worldPositionOf(record))
	end
end
for _, record in ipairs(WreckData) do
	if record.Name == "crownest_1" then
		createMarker(landmarksFolder, "CrowsNest", worldPositionOf(record))
	end
end

-- Interaction points: the helm, and the two "desk" rooms a future
-- quest/notes system would want a precise interact spot in.
for _, record in ipairs(WreckData) do
	if record.Name == "helm_wheel_outer" then
		createMarker(interactionPointsFolder, "Helm", worldPositionOf(record))
	end
end
for _, roomName in ipairs({ "captain_suite", "chart_room" }) do
	local floorRecord = roomFloorRecord[roomName]
	if floorRecord then
		createMarker(interactionPointsFolder, roomName .. "_desk", worldPositionOf(floorRecord) + Vector3.new(0, 6, 0))
	end
end

-- Loot spots: a SpawnRegion (the same tag/Attribute system SpawnRegions.lua
-- and TreasureSpawner already read) sized to each room's own floor
-- footprint, so treasures populate inside the wreck with zero new code --
-- TreasureSpawner picks these up automatically over its own procedural
-- scatter the moment they exist.
local LOOT_ROOM_COUNTS = {
	cargo_hall = 6,
	captain_suite = 3,
	armory = 4,
	crew_quarters = 2,
	chart_room = 2,
	galley = 1,
	ballroom_lounge = 3,
}

for roomName, count in pairs(LOOT_ROOM_COUNTS) do
	local floorRecord = roomFloorRecord[roomName]
	if floorRecord then
		local region = buildPart(floorRecord, lootSpotsFolder, {
			Transparency = 1,
			CanCollide = false,
			CanQuery = false,
			CastShadow = false,
			Size = Vector3.new(floorRecord.Size.X * SHIP_SCALE * 0.7, 10, floorRecord.Size.Z * SHIP_SCALE * 0.7),
			CFrame = partCFrame(floorRecord) * CFrame.new(0, 6, 0),
		})
		region.Name = "LootSpot_" .. roomName
		CollectionService:AddTag(region, "SpawnRegion")
		region:SetAttribute("RegionKind", "Treasure")
		region:SetAttribute("RegionCount", count)
		region:SetAttribute("RegionEnabled", true)
	end
end

-- A creature spawn region around the whole wreck exterior, for sharks/eels
-- that would naturally patrol a wreck -- same SpawnRegions mechanism.
do
	local exteriorRegion = Instance.new("Part")
	exteriorRegion.Name = "WreckCreatureRegion"
	exteriorRegion.Anchored = true
	exteriorRegion.CanCollide = false
	exteriorRegion.CanQuery = false
	exteriorRegion.CanTouch = false
	exteriorRegion.Transparency = 1
	exteriorRegion.Size = Vector3.new(950, 330, 350) -- comfortably covers the ~724x254x131 ship with margin
	exteriorRegion.CFrame = shipCFrame
	exteriorRegion.Parent = shipFolder
	CollectionService:AddTag(exteriorRegion, "SpawnRegion")
	exteriorRegion:SetAttribute("RegionKind", "Creature")
	exteriorRegion:SetAttribute("RegionCount", 5)
	exteriorRegion:SetAttribute("RegionSpecies", "Requin,Raie")
	exteriorRegion:SetAttribute("RegionEnabled", true)
end

-- Debris field: fallen crates/barrels/planks scattered on the seabed
-- around the hull, plus the pieces the hull breaches "lost" -- same
-- simple-primitive style as WorldDecor.server.lua's other set dressing.
-- Authored directly in the same corrected local convention as everything
-- else (X = length, Y = true vertical, Z = beam -- see remapAxes above),
-- then scaled once like every other local offset in this script. Keel
-- bottom is at raw Y (post-remap) ~-12.5, so -18..-8 sits at/just below it.
local function scatterDebris()
	local halfLength = 100 -- raw studs; half the ~201-stud hull length
	for i = 1, 40 do
		local along = (math.random() - 0.5) * halfLength * 2
		local across = (math.random() - 0.5) * 40 -- raw studs; a bit wider than the ~36 beam
		local local_ = Vector3.new(along, -18 + math.random() * 10, across) * SHIP_SCALE
		local worldPos = (shipCFrame * CFrame.new(local_)).Position
		local kind = math.random()
		local size = 1.5 + math.random() * 3
		local piece
		if kind < 0.4 then
			piece = Instance.new("Part")
			piece.Size = Vector3.new(size, size, size)
			piece.Material = Enum.Material.WoodPlanks
			piece.Color = Color3.fromRGB(70, 55, 42)
		elseif kind < 0.7 then
			piece = Instance.new("Part")
			piece.Shape = Enum.PartType.Cylinder
			piece.Size = Vector3.new(size * 1.4, size, size)
			piece.Material = Enum.Material.Wood
			piece.Color = Color3.fromRGB(90, 68, 48)
		else
			piece = Instance.new("Part")
			piece.Size = Vector3.new(size * 2.5, size * 0.25, size * 0.9)
			piece.Material = Enum.Material.WoodPlanks
			piece.Color = Color3.fromRGB(60, 48, 38)
		end
		piece.Name = "Debris"
		piece.Anchored = true
		piece.CanTouch = false
		piece.CastShadow = false
		piece.CFrame = CFrame.new(worldPos) * CFrame.Angles(math.random() * math.pi, math.random() * math.pi, math.random() * math.pi)
		piece.Parent = debrisFolder
	end
end
scatterDebris()

-- Interior lighting rework -----------------------------------------------------------
-- The interior previously had zero light sources of its own -- just the
-- Épave zone's own very dim ambient (Brightness ~0.55, see ZonesConfig),
-- which is why it read as near-pitch-black. This adds small, cheap,
-- mostly-shadowless lights guiding the player through it, dark blue/cyan/
-- turquoise throughout with a warm lantern accent only in WARM_ROOMS --
-- never a bright, evenly-lit interior, just enough to read the space.
--
-- Every light needs a real position, which in Roblox means being parented
-- (directly or via an Attachment) to a BasePart -- but the brief also asks
-- for all of them filed under Lighting/<Category>, not scattered as
-- children of the room/corridor geometry they illuminate. Both at once:
-- each light gets its own small invisible anchor Part, positioned with the
-- exact same CFrame-offset math used everywhere else in this script
-- (`hostPart.CFrame * CFrame.new(localOffset)`), then parented straight
-- into the right Lighting subfolder -- correct position, correct folder,
-- and the anchor moves/deletes cleanly with the rest of the ship on a
-- rebuild since it's real Instance-tree content, not a loose reference.
local function createLightAnchor(folder: Instance, name: string, worldCFrame: CFrame): BasePart
	local anchor = Instance.new("Part")
	anchor.Name = name
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.CastShadow = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.5, 0.5, 0.5)
	anchor.CFrame = worldCFrame
	anchor.Parent = folder
	return anchor
end

local function addLightAt(folder: Instance, name: string, hostPart: BasePart, localOffset: Vector3, color: Color3, brightness: number, range: number, castShadow: boolean?)
	local anchor = createLightAnchor(folder, name, hostPart.CFrame * CFrame.new(localOffset))
	local light = Instance.new("PointLight")
	light.Color = color
	light.Brightness = brightness
	light.Range = range
	light.Shadows = castShadow == true
	light.Parent = anchor
	return light
end

local corridorLightCount, roomLightCount, entranceLightCount, navLightCount, ambientLightCount = 0, 0, 0, 0, 0

-- Corridors: 3 lights spread along each segment's own length (using its
-- own ceiling part, whatever its length/position/height -- so this works
-- unchanged if CORRIDOR_WIDEN_FACTOR above ever changes), dimmer at the
-- ends and brightest towards the middle third, so a corridor never goes
-- fully dark along its run without looking like an evenly-lit hallway.
for segmentName, parts in pairs(corridorParts) do
	if parts.ceiling then
		local length = parts.ceiling.Size.X
		for i, fraction in ipairs({ -0.32, 0, 0.32 }) do
			addLightAt(corridorLightsFolder, segmentName .. "_Light" .. i, parts.ceiling, Vector3.new(length * fraction, 0, 0), COOL_LIGHT_COLOR, 0.7, 16, false)
			corridorLightCount += 1
		end
	end
end

-- Rooms: a light near one doorway (wall_y1a, "près de l'entrée"), one at
-- the far wall (wall_x2, "vers le fond" -- creates real depth instead of
-- one flat centered glow), and a ceiling light -- warm and shadow-casting
-- in the 3 memorable rooms, dim cool fill everywhere else.
for roomName, parts in pairs(roomParts) do
	local isWarm = WARM_ROOMS[roomName]
	local color = isWarm and WARM_LIGHT_COLOR or COOL_LIGHT_COLOR
	if parts.y1a then
		addLightAt(roomLightsFolder, roomName .. "_Entry", parts.y1a, Vector3.new(), COOL_LIGHT_COLOR, 0.6, 14, false)
		roomLightCount += 1
	end
	if parts.x2 then
		addLightAt(roomLightsFolder, roomName .. "_Far", parts.x2, Vector3.new(), color, isWarm and 1.0 or 0.6, isWarm and 20 or 14, false)
		roomLightCount += 1
	end
	if parts.ceiling then
		addLightAt(roomLightsFolder, roomName .. "_Ceiling", parts.ceiling, Vector3.new(), color, isWarm and 1.3 or 0.5, isWarm and 24 or 15, isWarm == true)
		roomLightCount += 1
	end
end

-- A soft, low fill light in the two biggest rooms only, so they don't
-- read as a flat-lit box or a single glowing point in a void -- everywhere
-- else stays legitimately darker corner-to-corner, per "je veux parfois
-- avoir des zones presque noires."
for _, roomName in ipairs({ "cargo_hall", "ballroom_lounge" }) do
	local parts = roomParts[roomName]
	if parts and parts.floor then
		addLightAt(ambientLightsFolder, roomName .. "_Ambient", parts.floor, Vector3.new(0, 6, 0), AMBIENT_LIGHT_COLOR, 0.35, 34, false)
		ambientLightCount += 1
	end
end

-- Entrances: brighter, slightly wider-range cool light at each breach --
-- reads as real (if dim) light leaking in from the ocean outside, and
-- doubles as a beacon guiding the player back toward an exit from inside.
for _, marker in ipairs(entryPointsFolder:GetChildren()) do
	if marker:IsA("BasePart") then
		addLightAt(entranceLightsFolder, marker.Name .. "_Light", marker, Vector3.new(), ENTRANCE_LIGHT_COLOR, 1.3, 30, false)
		entranceLightCount += 1
	end
end

-- Stairs: a light at the bottom and a slightly warmer/brighter one at the
-- top of every flight, so a change in level -- the easiest thing to miss
-- while swimming in 3D -- is always visibly marked at both ends.
for stairName, stairPart in pairs(stairParts) do
	local halfHeight = stairPart.Size.Y / 2
	addLightAt(navigationLightsFolder, stairName .. "_Bottom", stairPart, Vector3.new(0, -halfHeight * 0.8, 0), NAV_LOW_COLOR, 0.6, 14, false)
	addLightAt(navigationLightsFolder, stairName .. "_Top", stairPart, Vector3.new(0, halfHeight * 0.8, 0), NAV_HIGH_COLOR, 0.8, 16, false)
	navLightCount += 2
end

print(string.format("[MegaWreckShip] lighting: %d corridor, %d room, %d entrance, %d navigation, %d ambient (%d total)",
	corridorLightCount, roomLightCount, entranceLightCount, navLightCount, ambientLightCount,
	corridorLightCount + roomLightCount + entranceLightCount + navLightCount + ambientLightCount))

-- The ship is centered on the exact spot EpaveVortex (CurrentGenerator
-- .server.lua) already occupied, so without this the vortex would swirl
-- inside the hull instead of around it: the model's own local origin sits
-- inside its hull cross-section (see hull_layer_0's Center in the data).
-- Nudges the vortex's Position only -- radius/tier/spin/every other
-- gameplay Attribute stays exactly what CurrentGenerator gave it -- to a
-- point just aft of the stern in open water (stern's raw local X is ~-77;
-- -95 clears it, then scaled once like every other local offset here).
-- CurrentGenerator and this script are separate top-level Scripts with no
-- guaranteed run order, hence WaitForChild rather than an immediate
-- FindFirstChild.
task.spawn(function()
	local currentsFolder = Workspace:WaitForChild("Currents", 5)
	local vortex = currentsFolder and currentsFolder:WaitForChild("EpaveVortex", 5)
	if vortex then
		vortex.Position = (shipCFrame * CFrame.new(Vector3.new(-95, 5, 20) * SHIP_SCALE)).Position
	end
end)

print(string.format("[MegaWreckShip] built at %s, scale %.1fx (%d parts placed)", tostring(SHIP_CENTER), SHIP_SCALE, #WreckData))
