-- Gives each depth zone a distinct look instead of open empty water:
-- coral clusters in the Récif, rock formations in the Grottes, a basic
-- shipwreck in the Épave, and jagged spires in the Abysses. Built from
-- Terrain and basic Parts — no custom models needed.

local Workspace = game:GetService("Workspace")
local terrain = Workspace.Terrain

local MIN_RADIUS = 60
local MAX_RADIUS = 420

local function randomPointInBand(minDepth, maxDepth)
	local angle = math.random() * math.pi * 2
	local radius = MIN_RADIUS + math.random() * (MAX_RADIUS - MIN_RADIUS)
	local depth = minDepth + math.random() * (maxDepth - minDepth)
	return Vector3.new(math.cos(angle) * radius, -depth, math.sin(angle) * radius)
end

local function scatterTerrainClumps(count, minDepth, maxDepth, minSize, maxSize, material)
	for _ = 1, count do
		local position = randomPointInBand(minDepth, maxDepth)
		local size = minSize + math.random() * (maxSize - minSize)
		terrain:FillBall(position, size, material)
	end
end

-- Récif (0-100m): coral clusters near the island.
local CORAL_COLORS = {
	Color3.fromRGB(255, 120, 90),
	Color3.fromRGB(255, 180, 60),
	Color3.fromRGB(255, 90, 160),
	Color3.fromRGB(120, 220, 200),
}

local coralFolder = Instance.new("Folder")
coralFolder.Name = "ReefCoral"
coralFolder.Parent = Workspace

for _ = 1, 35 do
	local position = randomPointInBand(8, 90)
	local coral = Instance.new("Part")
	coral.Name = "Coral"
	coral.Shape = Enum.PartType.Cylinder
	coral.Anchored = true
	coral.CanCollide = false
	coral.Material = Enum.Material.Neon
	coral.Color = CORAL_COLORS[math.random(1, #CORAL_COLORS)]
	local height = 2 + math.random() * 4
	coral.Size = Vector3.new(height, 1 + math.random() * 1.5, 1 + math.random() * 1.5)
	coral.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90 + (math.random() - 0.5) * 30))
	coral.Parent = coralFolder
end

-- Grottes (100-250m): rock clusters forming passages, physically reducing
-- visibility on top of the fog from ZoneAnnouncer.
scatterTerrainClumps(50, 105, 245, 8, 22, Enum.Material.Slate)

-- Épave (250-400m): a simple shipwreck built from basic Parts.
local wreckFolder = Instance.new("Folder")
wreckFolder.Name = "Shipwreck"
wreckFolder.Parent = Workspace

local WRECK_POSITION = Vector3.new(250, -320, 100)
local WRECK_ORIENTATION = CFrame.Angles(0, math.rad(35), math.rad(18))

local hull = Instance.new("Part")
hull.Name = "Hull"
hull.Anchored = true
hull.Material = Enum.Material.WoodPlanks
hull.Color = Color3.fromRGB(60, 45, 35)
hull.Size = Vector3.new(14, 10, 60)
hull.CFrame = CFrame.new(WRECK_POSITION) * WRECK_ORIENTATION
hull.Parent = wreckFolder

local deck = Instance.new("Part")
deck.Name = "Deck"
deck.Anchored = true
deck.Material = Enum.Material.WoodPlanks
deck.Color = Color3.fromRGB(80, 60, 45)
deck.Size = Vector3.new(12, 1, 55)
deck.CFrame = hull.CFrame * CFrame.new(0, 5.2, 0)
deck.Parent = wreckFolder

local mast = Instance.new("Part")
mast.Name = "Mast"
mast.Anchored = true
mast.Material = Enum.Material.Wood
mast.Color = Color3.fromRGB(50, 35, 25)
mast.Size = Vector3.new(2, 30, 2)
mast.CFrame = deck.CFrame * CFrame.new(0, 15, -10) * CFrame.Angles(0, 0, math.rad(8))
mast.Parent = wreckFolder

-- Rubble scattered around the wreck for context.
scatterTerrainClumps(15, 260, 390, 6, 14, Enum.Material.Rock)

-- Abysses (400-500m): tall jagged rock spires for an imposing sense of scale.
for _ = 1, 20 do
	local position = randomPointInBand(410, 480)
	local spireHeight = 30 + math.random() * 60
	terrain:FillCylinder(
		CFrame.new(position) * CFrame.new(0, spireHeight / 2 - 10, 0),
		spireHeight,
		4 + math.random() * 6,
		Enum.Material.Basalt
	)
end
