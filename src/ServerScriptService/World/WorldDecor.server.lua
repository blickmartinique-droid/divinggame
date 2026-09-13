-- Light procedural set dressing so the ocean has shape and silhouettes at
-- every depth, built from cheap anchored primitives (no meshes, no
-- textures) and meant to be replaced piece by piece by real Blender
-- assets later: everything lives in Workspace.WorldDecor and is rebuilt
-- from scratch each start, so deleting a section here is enough to make
-- room for the real thing. Deliberately sparse -- silhouettes and colour
-- accents, not a filled-in map.
--
--   * Shelf reef: coral clusters, kelp and boulders on the beach's submerged
--     shelf and slope (the only shallow seabed there is).
--   * Pinnacles: tall rock spires rising from the seafloor to various
--     heights around the island, so the mid-water and deep zones have
--     dark shapes looming through the fog instead of empty blue.
--   * Grottes arch and Épave seafloor plateau: landmarks at two example
--     current locations, so the currents visibly lead somewhere (the
--     Épave plateau is also the foundation MegaWreckShip.server.lua's
--     much bigger wreck sits on).
--   * Abyss glow: a few bioluminescent nodes near the floor.

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ZonesConfig = require(ReplicatedStorage.Shared.Config.ZonesConfig)

local FLOOR_Y = -ZonesConfig.MaxDepth

local existing = Workspace:FindFirstChild("WorldDecor")
if existing then
	existing:Destroy()
end
local decor = Instance.new("Folder")
decor.Name = "WorldDecor"
decor.Parent = Workspace

local function folder(name: string)
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = decor
	return f
end

local function prop(parent: Instance, name: string, size: Vector3, cframe: CFrame, material: Enum.Material, color: Color3, shape: Enum.PartType?)
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = true
	part.CanTouch = false
	part.CastShadow = size.Magnitude > 6
	part.Shape = shape or Enum.PartType.Block
	part.Size = size
	part.CFrame = cframe
	part.Material = material
	part.Color = color
	part.Parent = parent
	return part
end

local function randomRotation(): CFrame
	return CFrame.Angles(math.random() * math.pi * 2, math.random() * math.pi * 2, math.random() * math.pi * 2)
end

local function ringPoint(minRadius: number, maxRadius: number): (number, number)
	local angle = math.random() * math.pi * 2
	local radius = minRadius + math.random() * (maxRadius - minRadius)
	return math.cos(angle) * radius, math.sin(angle) * radius
end

-- Seabed height of the beach shelf/slope at a given radius (mirrors
-- OceanGenerator's tiers: shelf top -6 to r=140, slope top -15 to r=180).
local function shelfY(radius: number): number?
	if radius < 140 then
		return -6
	elseif radius < 180 then
		return -15
	end
	return nil
end

-- Shelf reef ----------------------------------------------------------------

local reef = folder("ShelfReef")
local CORAL_COLORS = {
	Color3.fromRGB(240, 120, 90), Color3.fromRGB(255, 170, 60), Color3.fromRGB(230, 90, 150),
	Color3.fromRGB(120, 200, 190), Color3.fromRGB(250, 220, 120), Color3.fromRGB(150, 110, 220),
}

for _ = 1, 55 do
	local x, z = ringPoint(78, 176)
	local y = shelfY(math.sqrt(x * x + z * z))
	if y then
		local base = Vector3.new(x, y, z)
		local color = CORAL_COLORS[math.random(#CORAL_COLORS)]
		local kind = math.random()
		if kind < 0.45 then
			-- Branching coral: a few tilted sticks from one point.
			for _ = 1, math.random(3, 5) do
				local height = 1.5 + math.random() * 2.5
				local tilt = CFrame.Angles((math.random() - 0.5) * 0.9, math.random() * math.pi * 2, (math.random() - 0.5) * 0.9)
				prop(reef, "Coral", Vector3.new(0.35, height, 0.35), CFrame.new(base) * tilt * CFrame.new(0, height / 2, 0), Enum.Material.SmoothPlastic, color)
			end
		elseif kind < 0.75 then
			-- Brain / boulder coral.
			local size = 1.5 + math.random() * 2.5
			prop(reef, "CoralDome", Vector3.new(size, size * 0.7, size), CFrame.new(base + Vector3.new(0, size * 0.25, 0)), Enum.Material.Pebble, color, Enum.PartType.Ball)
		else
			-- Fan coral: a thin upright plate.
			local width = 2 + math.random() * 2
			prop(reef, "CoralFan", Vector3.new(width, width * 0.9, 0.2), CFrame.new(base + Vector3.new(0, width * 0.45, 0)) * CFrame.Angles(0, math.random() * math.pi, 0), Enum.Material.Fabric, color)
		end
	end
end

for _ = 1, 40 do
	local x, z = ringPoint(80, 176)
	local y = shelfY(math.sqrt(x * x + z * z))
	if y then
		local height = 6 + math.random() * 8
		local lean = CFrame.Angles((math.random() - 0.5) * 0.25, math.random() * math.pi * 2, (math.random() - 0.5) * 0.25)
		local kelp = prop(reef, "Kelp", Vector3.new(0.5, height, 0.5), CFrame.new(x, y, z) * lean * CFrame.new(0, height / 2, 0), Enum.Material.Grass, Color3.fromRGB(70, 130, 60))
		kelp.CanCollide = false
	end
end

for _ = 1, 26 do
	local x, z = ringPoint(90, 200)
	local y = shelfY(math.sqrt(x * x + z * z)) or -35
	local size = 3 + math.random() * 9
	prop(reef, "Boulder", Vector3.new(size, size * (0.6 + math.random() * 0.5), size * (0.7 + math.random() * 0.5)), CFrame.new(x, y + size * 0.2, z) * randomRotation(), Enum.Material.Slate, Color3.fromRGB(78, 90, 104))
end

-- Pinnacles -----------------------------------------------------------------

local pinnacles = folder("Pinnacles")
local PINNACLE_COUNT = 14
for i = 1, PINNACLE_COUNT do
	local angle = (i / PINNACLE_COUNT) * math.pi * 2 + math.random() * 0.4
	local radius = 320 + math.random() * 360
	local x, z = math.cos(angle) * radius, math.sin(angle) * radius
	local topY = -60 - math.random() * 380
	local height = topY - FLOOR_Y
	local width = 22 + math.random() * 34
	local color = Color3.fromRGB(60, 70, 84)
	prop(pinnacles, "Pinnacle", Vector3.new(width, height, width * (0.7 + math.random() * 0.6)), CFrame.new(x, FLOOR_Y + height / 2, z) * CFrame.Angles(0, math.random() * math.pi, 0), Enum.Material.Slate, color)
	-- A couple of ledges break the silhouette.
	for _ = 1, 2 do
		local ledgeY = FLOOR_Y + height * (0.3 + math.random() * 0.6)
		local ledge = width * (0.8 + math.random() * 0.8)
		prop(pinnacles, "Ledge", Vector3.new(ledge, 6 + math.random() * 8, ledge * 0.8), CFrame.new(x, ledgeY, z) * randomRotation(), Enum.Material.Slate, color)
	end
end

-- Grottes arch (over the corridor current) ---------------------------------------

local arch = folder("GrottesArch")
local archCenter = Vector3.new(-200, -180, 300)
local archDir = Vector3.new(1, 0, -1).Unit
local archSide = Vector3.new(archDir.Z, 0, -archDir.X)
for _, side in ipairs({ -1, 1 }) do
	local footprint = archCenter + archSide * (side * 40)
	prop(arch, "ArchPillar", Vector3.new(26, 130, 26), CFrame.new(footprint.X, archCenter.Y - 20, footprint.Z) * CFrame.Angles(0, math.random() * math.pi, 0), Enum.Material.Slate, Color3.fromRGB(58, 66, 80))
end
prop(arch, "ArchSpan", Vector3.new(100, 16, 24), CFrame.lookAt(archCenter + Vector3.new(0, 40, 0), archCenter + Vector3.new(0, 40, 0) + archDir) * CFrame.Angles(0, math.pi / 2, 0), Enum.Material.Slate, Color3.fromRGB(58, 66, 80))

-- Épave seafloor plateau ------------------------------------------------------------
-- The small hand-built Hull/Bow/Deckhouse/Mast placeholder that used to
-- stand in for the wreck here has been replaced by the real, vastly
-- bigger MegaWreckShip.server.lua (a full multi-deck ship reconstructed
-- from an imported model) at this same spot -- only the seafloor rise it
-- rests on stays, plus a scattering of period-appropriate debris around it.

local wreck = folder("EpaveWreck")
local wreckCenter = Vector3.new(150, -300, -150)
prop(wreck, "Plateau", Vector3.new(160, 30, 140), CFrame.new(wreckCenter.X, wreckCenter.Y - 27, wreckCenter.Z), Enum.Material.Slate, Color3.fromRGB(52, 60, 72))
local hullColor = Color3.fromRGB(70, 55, 45)
for _ = 1, 8 do
	local size = 3 + math.random() * 6
	prop(wreck, "Debris", Vector3.new(size, size * 0.4, size * 0.7), CFrame.new(wreckCenter + Vector3.new((math.random() - 0.5) * 120, -10 + size * 0.2, (math.random() - 0.5) * 100)) * randomRotation(), Enum.Material.WoodPlanks, hullColor)
end

-- Abyss glow -------------------------------------------------------------------------

local abyss = folder("AbyssGlow")
for _ = 1, 9 do
	local x, z = ringPoint(250, 700)
	local y = FLOOR_Y + 2 + math.random() * 60
	local color = math.random() < 0.5 and Color3.fromRGB(90, 220, 255) or Color3.fromRGB(150, 110, 255)
	local node = prop(abyss, "GlowNode", Vector3.new(1.2, 1.2, 1.2), CFrame.new(x, y, z), Enum.Material.Neon, color, Enum.PartType.Ball)
	node.CanCollide = false
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 26
	light.Brightness = 1.2
	light.Parent = node
end
