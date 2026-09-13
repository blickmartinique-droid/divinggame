-- Builds the "Archipel des Profondeurs" -- island/mountain surface, cave
-- network, abyssal garden, coral reef and dock -- from ArchipelWorldData
-- .lua (~2628 primitive-derived part records) and ArchipelTerrainData.lua
-- (4 sculpted terrain meshes, converted to Terrain fill chains). Replaces
-- CaveRegions.server.lua/CaveRegionBuilder.lua entirely, per instruction:
-- "enlever ... les anciennes grottes par [le contenu du nouveau fichier]".
--
-- UNLIKE the old CaveRegionBuilder: that source was 4 SEPARATE, scattered
-- "blockout" models (deliberately rough placeholders, connected only by
-- hand-placed currents), so their masses/tunnels were reconstructed from a
-- handful of coarse placeholder tiers scaled way up. This source is ONE
-- continuous, already-detailed archipelago (island, mountain, caves, reef,
-- garden and dock all sharing one real coordinate space, already correctly
-- positioned relative to TitanShip.server.lua's ship) -- so there is no
-- per-region placement config, no artistic Scale/Yaw, and no connector
-- currents to invent: the source file's own layout already connects
-- everything (see e.g. the "Grottes — Porte du Titan" landmark below,
-- named for sitting right at the ship's own cave entrance).
--
-- Same coordinate conversion as TitanShipData.lua (see its header):
-- Blender Z-up -> Roblox Y-up, (x,y,z)->(x,z,-y), +(300,0,300) world
-- offset, no extra scale (the source file's units already match this
-- game's "1 stud = 1 metre" depth convention).
--
-- Terrain vs Parts: the 4 big sculpted meshes (cliff massif, island
-- surface, cave network, abyssal cathedral) become real smooth Terrain --
-- same reasoning as the old CaveRegionBuilder (organic shapes read as
-- organic in Terrain, not as stacked boxes) -- while everything else
-- (structural/decorative primitives: coral, sponges, crystals, ruins,
-- dock planks...) becomes Parts, exactly like TitanShip.server.lua. Each
-- mesh's medial-axis chain (ArchipelTerrainData.lua) is filled as tapered
-- capsules between consecutive nodes (see fillCapsule below), not isolated
-- balls -- an earlier version left them isolated and, confirmed in Studio,
-- that read as one giant smooth boulder rather than a ridge or tunnel.

local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")

local WorldData = require(script.Parent.ArchipelWorldData)
local TerrainData = require(script.Parent.ArchipelTerrainData)

local terrain = Workspace.Terrain

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

-- The old 4 scattered regions, if this is running right after an upgrade
-- from a save that still has them, are removed here too -- "enlever les
-- anciennes grottes" applies even if CaveRegions.server.lua's own file is
-- already gone from source.
local staleOldRegions = underwaterFolder:FindFirstChild("CaveRegions")
if staleOldRegions then
	staleOldRegions:Destroy()
end

local existing = underwaterFolder:FindFirstChild("ArchipelDesProfondeurs")
if existing then
	existing:Destroy()
end
local archipelFolder = Instance.new("Folder")
archipelFolder.Name = "ArchipelDesProfondeurs"
archipelFolder.Parent = underwaterFolder

local CATEGORY_DISPLAY_NAME = {
	Surface = "Surface_Accueil",
	IleEtMontagne = "Ile_Et_Montagne",
	ReseauDeGrottes = "Reseau_De_Grottes",
	JardinAbyssal = "Jardin_Abyssal",
	RecifEtFauneFixe = "Recif_Et_Faune_Fixe",
	QuaiEtCamp = "Quai_Et_Camp",
	OceanVisuel = "Ocean_Visuel",
}

local categoryFolders = {}
for category, name in pairs(CATEGORY_DISPLAY_NAME) do
	categoryFolders[category] = ensureFolder(archipelFolder, name)
end

local lightingFolder = ensureFolder(archipelFolder, "Lighting")
local landmarksFolder = ensureFolder(archipelFolder, "Landmarks")
local lootSpotsFolder = ensureFolder(archipelFolder, "LootSpots")
local creatureRegionsFolder = ensureFolder(archipelFolder, "CreatureRegions")

-- Terrain -----------------------------------------------------------------------
-- Unlike every Part/Folder above (destroyed and rebuilt fresh on every
-- run), Terrain is real persistent voxel data: FillBall/FillCylinder only
-- ADD material, they never remove what a previous run already placed.
-- Re-running this script after a bug in an earlier version (e.g. the
-- oversized-radius boulder this fix addresses) would otherwise just add
-- the corrected shape ON TOP of the old one, leaving the old one exactly
-- as visible as before -- confirmed to be exactly what happened in
-- Studio. So the archipel's own terrain footprint is cleared back to
-- Water FIRST, every run, before the mass/carve fills below -- the same
-- "regenerate fresh every start" contract OceanGenerator.server.lua uses
-- for its Terrain, applied here for the same reason.
--
-- Region: the real bounding box of every chain node (center +/- radius,
-- computed from the data, not hand-picked), padded by 20 studs, and
-- clamped to this game's actual water column (Y in [-500, 20] -- surface
-- to seafloor, +14 for the island's own above-water sliver) so this never
-- touches OceanGenerator's solid floor slab just below -500.
do
	local minV, maxV = nil, nil
	for _, data in pairs(TerrainData) do
		for _, seg in ipairs(data.Chain) do
			local lo = seg.Center - Vector3.new(seg.Radius, seg.Radius, seg.Radius)
			local hi = seg.Center + Vector3.new(seg.Radius, seg.Radius, seg.Radius)
			minV = minV and minV:Min(lo) or lo
			maxV = maxV and maxV:Max(hi) or hi
		end
	end
	if minV and maxV then
		local PAD = 20
		minV = minV - Vector3.new(PAD, PAD, PAD)
		maxV = maxV + Vector3.new(PAD, PAD, PAD)
		minV = Vector3.new(minV.X, math.max(minV.Y, -500), minV.Z)
		maxV = Vector3.new(maxV.X, math.min(maxV.Y, 20), maxV.Z)

		local CHUNK_SIZE = 200 -- Terrain:FillBlock errors on very large single calls (see OceanGenerator.server.lua)
		local fullSize = maxV - minV
		local chunksX = math.ceil(fullSize.X / CHUNK_SIZE)
		local chunksY = math.ceil(fullSize.Y / CHUNK_SIZE)
		local chunksZ = math.ceil(fullSize.Z / CHUNK_SIZE)
		for cx = 0, chunksX - 1 do
			local sizeX = math.min(CHUNK_SIZE, fullSize.X - cx * CHUNK_SIZE)
			for cy = 0, chunksY - 1 do
				local sizeY = math.min(CHUNK_SIZE, fullSize.Y - cy * CHUNK_SIZE)
				for cz = 0, chunksZ - 1 do
					local sizeZ = math.min(CHUNK_SIZE, fullSize.Z - cz * CHUNK_SIZE)
					local chunkCenter = minV + Vector3.new(
						cx * CHUNK_SIZE + sizeX / 2,
						cy * CHUNK_SIZE + sizeY / 2,
						cz * CHUNK_SIZE + sizeZ / 2
					)
					terrain:FillBlock(CFrame.new(chunkCenter), Vector3.new(sizeX, sizeY, sizeZ), Enum.Material.Water)
				end
			end
		end
	end
end

-- "mass" chains are filled solid FIRST (the mountain/island silhouette),
-- then "carve" chains hollow the real cave/cathedral passages back out of
-- it -- order matters, a carve before its surrounding mass exists would
-- just get refilled. Every chain is real geometry (a clustered medial-axis
-- reading of the source mesh's own sampled vertices), not a hand-placed
-- blockout -- see ArchipelTerrainData.lua's header.
local massChains, carveChains = {}, {}
for _, data in pairs(TerrainData) do
	if data.Role == "mass" then
		table.insert(massChains, data)
	else
		table.insert(carveChains, data)
	end
end

-- Connects two chain nodes with a tapered cylinder (radius = their average)
-- so the terrain reads as one continuous ridge/tunnel instead of a string
-- of separate balls -- confirmed in Studio: isolated FillBalls alone
-- looked like a giant smooth boulder chain, not a rock formation.
-- Terrain:FillCylinder's height runs along the CFrame's own Y axis, so
-- the cylinder is oriented with Y pointing from A to B; the arbitrary
-- reference vector only has to be non-parallel to that direction, picked
-- per-segment since a spine can run in any direction.
local function fillCapsule(pointA: Vector3, radiusA: number, pointB: Vector3, radiusB: number, material: Enum.Material)
	terrain:FillBall(pointA, radiusA, material)
	local diff = pointB - pointA
	local height = diff.Magnitude
	if height > 0.5 then
		local up = diff.Unit
		local reference = math.abs(up.Y) < 0.9 and Vector3.new(0, 1, 0) or Vector3.new(1, 0, 0)
		local right = up:Cross(reference).Unit
		local cf = CFrame.fromMatrix((pointA + pointB) / 2, right, up)
		terrain:FillCylinder(cf, height, (radiusA + radiusB) / 2, material)
	end
	terrain:FillBall(pointB, radiusB, material)
end

local function fillChain(data)
	local material = Enum.Material[data.Material]
	local chain = data.Chain
	if #chain == 1 then
		terrain:FillBall(chain[1].Center, chain[1].Radius, material)
		return
	end
	for i = 1, #chain - 1 do
		fillCapsule(chain[i].Center, chain[i].Radius, chain[i + 1].Center, chain[i + 1].Radius, material)
	end
end

for _, data in ipairs(massChains) do
	fillChain(data)
end
for _, data in ipairs(carveChains) do
	fillChain(data)
end

-- Parts ---------------------------------------------------------------------------

local PART_SHAPE = {
	Block = Enum.PartType.Block,
	Cylinder = Enum.PartType.Cylinder,
	Ball = Enum.PartType.Ball,
}

-- Same fail-loud-on-first-typo lookup as TitanShip.server.lua (see its
-- comment) -- every name in ArchipelWorldData.lua was picked from Roblox's
-- real Enum.Material list while generating it.
local MATERIAL = setmetatable({}, {
	__index = function(t, key)
		local value = Enum.Material[key]
		rawset(t, key, value)
		return value
	end,
})

local function shouldCollide(record)
	return record.Material ~= "Neon" and record.Category ~= "RecifEtFauneFixe"
	-- Coral/sponges/crystals are set dressing a diver swims through, same
	-- spirit as WorldDecor's existing shelf-reef props; every other
	-- category (rock, dock planks, ruins, island surface props) keeps its
	-- real collision -- there is real ground/rock to stand or bump into.
end

local aabb = {}
local function trackAabb(category: string, position: Vector3)
	local box = aabb[category]
	if not box then
		aabb[category] = { min = position, max = position }
		return
	end
	box.min = Vector3.new(math.min(box.min.X, position.X), math.min(box.min.Y, position.Y), math.min(box.min.Z, position.Z))
	box.max = Vector3.new(math.max(box.max.X, position.X), math.max(box.max.Y, position.Y), math.max(box.max.Z, position.Z))
end

for _, record in ipairs(WorldData) do
	local folder = categoryFolders[record.Category]
	if not folder then
		continue
	end
	local part = Instance.new("Part")
	part.Name = record.Name
	part.Shape = PART_SHAPE[record.Shape] or Enum.PartType.Block
	part.Anchored = true
	part.CanTouch = false
	part.CanQuery = true
	part.CastShadow = false -- thousands of parts; see TitanShip.server.lua's identical choice
	part.CFrame = CFrame.fromMatrix(record.Center, record.Right, record.Up)
	part.Size = record.Size
	part.Color = record.Color
	part.Material = MATERIAL[record.Material]
	part.CanCollide = shouldCollide(record)
	part.Parent = folder
	trackAabb(record.Category, record.Center)
end

-- Lighting ------------------------------------------------------------------------
-- Only the source file's POINT lights are ported -- its one SUN light
-- ("Soleil") was Blender's own scene-lighting stand-in, not a placed
-- gameplay light, and this game already has its own sun/atmosphere system
-- (OceanGenerator.server.lua / the per-depth Lighting rework). Energy
-- (Blender Watts) is a rougher, larger-scale unit here than TitanShip's
-- interior lights, so it is divided by a bigger constant to land in the
-- same 0.5-4 Roblox Brightness range while keeping the source's own
-- relative brightness differences (Phare beacons clearly brighter than
-- ambient glow).
local WORLD_LIGHTS = {
	{Name="Ambiance_A",Pos=Vector3.new(373.0000,-211.0000,394.0000),Color=Color3.new(0.1200,0.7000,1.0000),Energy=5000.0},
	{Name="Ambiance_B",Pos=Vector3.new(413.0000,-253.0000,343.0000),Color=Color3.new(0.1200,0.7000,1.0000),Energy=5000.0},
	{Name="Ambiance_C",Pos=Vector3.new(464.0000,-293.0000,299.0000),Color=Color3.new(0.1200,0.7000,1.0000),Energy=5000.0},
	{Name="Ambiance_D",Pos=Vector3.new(528.0000,-418.0000,278.0000),Color=Color3.new(0.2300,0.3500,1.0000),Energy=12000.0},
	{Name="Ambiance_E",Pos=Vector3.new(466.0000,-465.0000,231.0000),Color=Color3.new(0.1200,0.7000,1.0000),Energy=5000.0},
	{Name="Ambiance_F",Pos=Vector3.new(574.0000,-450.0000,197.0000),Color=Color3.new(0.2300,0.3500,1.0000),Energy=12000.0},
	{Name="Ambiance_G",Pos=Vector3.new(398.0000,-370.0000,225.0000),Color=Color3.new(0.1200,0.7000,1.0000),Energy=5000.0},
	{Name="Ambiance_H",Pos=Vector3.new(560.0000,-310.0000,370.0000),Color=Color3.new(0.1200,0.7000,1.0000),Energy=5000.0},
	{Name="Ambiance_I",Pos=Vector3.new(598.0000,-310.0000,259.0000),Color=Color3.new(0.1200,0.7000,1.0000),Energy=5000.0},
	{Name="Ambiance_J",Pos=Vector3.new(257.0000,-255.0000,332.0000),Color=Color3.new(0.1200,0.7000,1.0000),Energy=5000.0},
	{Name="Ambiance_K",Pos=Vector3.new(232.0000,-250.0000,415.0000),Color=Color3.new(0.1200,0.7000,1.0000),Energy=5000.0},
	{Name="Ambiance_L",Pos=Vector3.new(413.0000,-255.0000,343.0000),Color=Color3.new(0.1200,0.7000,1.0000),Energy=5000.0},
	{Name="Phare_Entree_A",Pos=Vector3.new(359.0007,-268.9972,558.1030),Color=Color3.new(0.1500,0.7000,1.0000),Energy=6000.0},
	{Name="Phare_Entree_G",Pos=Vector3.new(780.1579,-280.8943,268.2232),Color=Color3.new(0.1500,0.7000,1.0000),Energy=6000.0},
	{Name="Phare_Entree_K",Pos=Vector3.new(167.0000,-192.4631,371.5962),Color=Color3.new(0.1500,0.7000,1.0000),Energy=6000.0},
}

local function addLight(name: string, worldPosition: Vector3, color: Color3, energy: number)
	local anchor = Instance.new("Part")
	anchor.Name = name
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.CastShadow = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.5, 0.5, 0.5)
	anchor.CFrame = CFrame.new(worldPosition)
	anchor.Parent = lightingFolder
	local light = Instance.new("PointLight")
	light.Color = color
	light.Brightness = math.clamp(energy / 3000, 0.5, 4)
	light.Range = 34
	light.Shadows = false
	light.Parent = anchor
end

for _, light in ipairs(WORLD_LIGHTS) do
	addLight(light.Name, light.Pos, light.Color, light.Energy)
end

-- Landmarks + gameplay regions ------------------------------------------------------
-- Every named spot the source file itself authored (its own EMPTY marker
-- objects) becomes a Landmark; the cave-network ones ("Grottes — ...")
-- also anchor a small Creature SpawnRegion so the network reads as real
-- roamed territory, not empty carved rock -- same SpawnRegion tag/
-- Attribute convention TreasureSpawner/CreatureSpawner already read.
local WORLD_LANDMARKS = {
	{Name="Falaise — accès A",Pos=Vector3.new(359.0007,-268.9972,558.1030)},
	{Name="Falaise — accès G",Pos=Vector3.new(788.8361,-285.8435,268.6626)},
	{Name="Falaise — accès K",Pos=Vector3.new(167.0000,-197.9523,363.2375)},
	{Name="Grottes — Carrefour Bleu",Pos=Vector3.new(464.0000,-295.0000,299.0000)},
	{Name="Grottes — Cathédrale Abyssale",Pos=Vector3.new(528.0000,-420.0000,278.0000)},
	{Name="Grottes — Cheminée des Racines",Pos=Vector3.new(598.0000,-310.0000,259.0000)},
	{Name="Grottes — Coude des Cendres",Pos=Vector3.new(232.0000,-250.0000,415.0000)},
	{Name="Grottes — Galerie des Racines",Pos=Vector3.new(560.0000,-310.0000,370.0000)},
	{Name="Grottes — Galerie du Titan",Pos=Vector3.new(257.0000,-255.0000,332.0000)},
	{Name="Grottes — Jardin des Méduses",Pos=Vector3.new(574.0000,-450.0000,197.0000)},
	{Name="Grottes — Porte des Marées",Pos=Vector3.new(373.0000,-213.0000,394.0000)},
	{Name="Grottes — Porte du Titan",Pos=Vector3.new(167.0000,-200.0000,396.0000)},
	{Name="Grottes — Puits des Echos",Pos=Vector3.new(466.0000,-467.0000,231.0000)},
	{Name="Grottes — Siphon Violet",Pos=Vector3.new(398.0000,-370.0000,225.0000)},
	{Name="Grottes — Vestibule des Ancres",Pos=Vector3.new(413.0000,-255.0000,343.0000)},
	{Name="Montagne — station sismique",Pos=Vector3.new(511.0000,-92.9228,225.0000)},
	{Name="Ruines — ancien camp",Pos=Vector3.new(594.0000,-170.1776,319.0000)},
	{Name="Surface — accueil classique",Pos=Vector3.new(275.0000,7.7000,387.0000)},
	{Name="Surface — quai de plongée",Pos=Vector3.new(275.0000,3.0000,437.0000)},
}

-- Named per-room species, matching what each cave's own name suggests;
-- everything else falls back to a general cave-dweller mix.
local GROTTE_SPECIES = {
	["Grottes — Jardin des Méduses"] = "MeduseLumineuse",
	["Grottes — Cathédrale Abyssale"] = "RequinRecif,MeduseLumineuse",
	["Grottes — Puits des Echos"] = "MeduseLumineuse",
}
local DEFAULT_GROTTE_SPECIES = "RaieManta,RequinRecif,TortueMarine"

local function createMarker(parent: Instance, name: string, worldPosition: Vector3)
	local anchor = Instance.new("Part")
	anchor.Name = name
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(1, 1, 1)
	anchor.CFrame = CFrame.new(worldPosition)
	local attachment = Instance.new("Attachment")
	attachment.Parent = anchor
	anchor.Parent = parent
	return anchor
end

local function addSpawnRegion(parent: Instance, name: string, center: Vector3, size: Vector3, kind: string, attributes: { [string]: any })
	local region = Instance.new("Part")
	region.Name = name
	region.Anchored = true
	region.CanCollide = false
	region.CanQuery = false
	region.CanTouch = false
	region.Transparency = 1
	region.Size = size
	region.CFrame = CFrame.new(center)
	region.Parent = parent
	CollectionService:AddTag(region, "SpawnRegion")
	region:SetAttribute("RegionKind", kind)
	region:SetAttribute("RegionEnabled", true)
	for key, value in pairs(attributes) do
		region:SetAttribute(key, value)
	end
	return region
end

local TREASURE_LANDMARKS = {
	["Montagne — station sismique"] = 3,
	["Ruines — ancien camp"] = 5,
}

for _, landmark in ipairs(WORLD_LANDMARKS) do
	createMarker(landmarksFolder, landmark.Name, landmark.Pos)

	if landmark.Name:match("^Grottes — ") then
		addSpawnRegion(creatureRegionsFolder, landmark.Name .. "_Creatures", landmark.Pos, Vector3.new(90, 60, 90), "Creature", {
			RegionCount = 3,
			RegionSpecies = GROTTE_SPECIES[landmark.Name] or DEFAULT_GROTTE_SPECIES,
		})
	end

	local treasureCount = TREASURE_LANDMARKS[landmark.Name]
	if treasureCount then
		addSpawnRegion(lootSpotsFolder, "LootSpot_" .. landmark.Name, landmark.Pos, Vector3.new(50, 30, 50), "Treasure", {
			RegionCount = treasureCount,
		})
	end
end

-- Reef ambient life: one broad Creature region over the whole coral reef
-- footprint (05_RECIF_ET_FAUNE_FIXE's own real extent, tracked above),
-- same as the old regions' "whole-region roaming" creature spawn.
do
	local box = aabb.RecifEtFauneFixe
	if box then
		local center = (box.min + box.max) / 2
		local size = (box.max - box.min) + Vector3.new(60, 60, 60)
		addSpawnRegion(creatureRegionsFolder, "RecifCreatureRegion", center, size, "Creature", {
			RegionCount = 6,
			RegionSpecies = "PoissonRecif,TortueMarine",
		})
	end
end

print(string.format(
	"[ArchipelWorld] built (%d parts, %d terrain segments, %d lights, %d landmarks)",
	#WorldData,
	(function()
		local n = 0
		for _, data in pairs(TerrainData) do
			n += #data.Chain
		end
		return n
	end)(),
	#WORLD_LIGHTS,
	#WORLD_LANDMARKS
))
