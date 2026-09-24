-- A small, detailed model for every treasure type (TreasureConfig Ids),
-- built from primitives: a stack of gold coins, a message in a bottle, a
-- pearl in its open clam, a crown, a golden idol, a crystal skull...
--
-- Each model is ~3 studs across, centred on its pivot, with an invisible
-- "Core" part as PrimaryPart (it carries the pickup prompt and the glow:
-- a light and sparkles in the rarity's colour, brighter for rarer finds).
-- Every part is anchored and non-colliding; TreasureAnimator (client) turns
-- and bobs the whole model with PivotTo.

local TreasureModels = {}

TreasureModels.RarityColors = {
	Commune = Color3.fromRGB(220, 220, 210),
	["Peu commune"] = Color3.fromRGB(90, 220, 130),
	Rare = Color3.fromRGB(80, 160, 255),
	["Très rare"] = Color3.fromRGB(190, 110, 255),
	["Légendaire"] = Color3.fromRGB(255, 190, 50),
}

local GLOW = {
	Commune = { range = 6, brightness = 0.6, sparkles = 0 },
	["Peu commune"] = { range = 8, brightness = 0.9, sparkles = 2 },
	Rare = { range = 10, brightness = 1.2, sparkles = 4 },
	["Très rare"] = { range = 13, brightness = 1.6, sparkles = 7 },
	["Légendaire"] = { range = 18, brightness = 2.4, sparkles = 12 },
}

local GOLD = Color3.fromRGB(240, 196, 70)
local GOLD_DARK = Color3.fromRGB(196, 150, 50)
local BRASS = Color3.fromRGB(190, 150, 70)
local WOOD = Color3.fromRGB(112, 74, 44)
local RUBY = Color3.fromRGB(220, 40, 70)
local EMERALD = Color3.fromRGB(40, 200, 110)
local SAPPHIRE = Color3.fromRGB(50, 110, 255)

-- Builders ------------------------------------------------------------------------------

local function newBuilder(model: Model)
	local b = {}
	function b.part(name: string, size: Vector3, cframe: CFrame, material: Enum.Material, color: Color3, shape: Enum.PartType?): Part
		local p = Instance.new("Part")
		p.Name = name
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Shape = shape or Enum.PartType.Block
		p.Size = size
		p.CFrame = cframe
		p.Material = material
		p.Color = color
		p.Parent = model
		return p
	end
	-- Cylinder standing up (Roblox cylinders lie along X).
	function b.disc(name: string, diameter: number, height: number, cframe: CFrame, material: Enum.Material, color: Color3): Part
		return b.part(name, Vector3.new(height, diameter, diameter), cframe * CFrame.Angles(0, 0, math.pi / 2), material, color, Enum.PartType.Cylinder)
	end
	function b.ball(name: string, diameter: number, cframe: CFrame, material: Enum.Material, color: Color3): Part
		return b.part(name, Vector3.new(diameter, diameter, diameter), cframe, material, color, Enum.PartType.Ball)
	end
	function b.ellipsoid(name: string, size: Vector3, cframe: CFrame, material: Enum.Material, color: Color3): Part
		local p = b.part(name, size, cframe, material, color)
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = p
		return p
	end
	function b.gem(name: string, diameter: number, cframe: CFrame, color: Color3): Part
		local p = b.part(name, Vector3.new(diameter, diameter, diameter), cframe * CFrame.Angles(math.pi / 4, 0, math.pi / 4), Enum.Material.Glass, color)
		p.Transparency = 0.15
		p.Reflectance = 0.2
		return p
	end
	return b
end

local MODELS = {}

MODELS.Coin = function(b)
	for stack = 0, 2 do
		local angle = stack / 3 * math.pi * 2
		local base = CFrame.new(math.cos(angle) * 0.8, -1, math.sin(angle) * 0.8)
		for k = 0, 3 + stack do
			b.disc("Coin", 1.3, 0.22, base * CFrame.new(0, k * 0.24, 0) * CFrame.Angles(0, k * 0.7, 0), Enum.Material.Metal, k % 2 == 0 and GOLD or GOLD_DARK)
		end
	end
	-- One coin standing on its edge, showing its face.
	b.part("Coin", Vector3.new(0.22, 1.5, 1.5), CFrame.new(0, 0.3, 0) * CFrame.Angles(0, 0.6, 0.15), Enum.Material.Metal, GOLD, Enum.PartType.Cylinder)
end

MODELS.Bottle = function(b)
	local tilt = CFrame.Angles(0, 0, math.rad(62))
	local body = b.part("Bottle", Vector3.new(2.2, 1.1, 1.1), tilt, Enum.Material.Glass, Color3.fromRGB(60, 150, 90), Enum.PartType.Cylinder)
	body.Transparency = 0.35
	b.part("BottleNeck", Vector3.new(0.9, 0.45, 0.45), tilt * CFrame.new(1.5, 0, 0), Enum.Material.Glass, Color3.fromRGB(60, 150, 90), Enum.PartType.Cylinder).Transparency = 0.3
	b.part("Cork", Vector3.new(0.4, 0.42, 0.42), tilt * CFrame.new(2.1, 0, 0), Enum.Material.Wood, Color3.fromRGB(170, 120, 70), Enum.PartType.Cylinder)
	b.part("Message", Vector3.new(1.5, 0.5, 0.5), tilt * CFrame.new(-0.1, 0, 0), Enum.Material.SmoothPlastic, Color3.fromRGB(240, 228, 196), Enum.PartType.Cylinder)
	b.part("Ribbon", Vector3.new(0.2, 0.56, 0.56), tilt * CFrame.new(-0.1, 0, 0), Enum.Material.Fabric, RUBY, Enum.PartType.Cylinder)
end

MODELS.Conch = function(b)
	local pink, cream = Color3.fromRGB(250, 170, 160), Color3.fromRGB(252, 236, 210)
	b.ellipsoid("Whorl", Vector3.new(2.6, 1.7, 1.8), CFrame.new(0, 0, 0) * CFrame.Angles(0, 0, 0.3), Enum.Material.SmoothPlastic, cream)
	b.ellipsoid("Whorl", Vector3.new(1.6, 1.2, 1.3), CFrame.new(-1.1, 0.5, 0) * CFrame.Angles(0, 0, 0.5), Enum.Material.SmoothPlastic, Color3.fromRGB(236, 206, 176))
	b.ellipsoid("Spire", Vector3.new(0.9, 0.7, 0.7), CFrame.new(-1.8, 0.9, 0) * CFrame.Angles(0, 0, 0.7), Enum.Material.SmoothPlastic, Color3.fromRGB(214, 180, 150))
	local lip = b.ellipsoid("Lip", Vector3.new(1.8, 1.4, 0.4), CFrame.new(0.6, -0.1, 0.8) * CFrame.Angles(0.3, 0.2, 0.2), Enum.Material.SmoothPlastic, pink)
	lip.Reflectance = 0.15
	for k = 0, 3 do
		b.ball("Knob", 0.35, CFrame.new(-0.6 + k * 0.5, 0.75, -0.2), Enum.Material.SmoothPlastic, cream)
	end
end

MODELS.Jewel = function(b)
	-- A gold ring standing up, crowned with an emerald.
	local beads = 14
	for k = 0, beads - 1 do
		local a = k / beads * math.pi * 2
		b.ball("Band", 0.42, CFrame.new(math.cos(a) * 1.05, math.sin(a) * 1.05 - 0.2, 0), Enum.Material.Metal, GOLD)
	end
	b.part("Setting", Vector3.new(0.7, 0.35, 0.7), CFrame.new(0, 0.95, 0), Enum.Material.Metal, GOLD_DARK)
	b.gem("Emerald", 0.9, CFrame.new(0, 1.45, 0), EMERALD)
	for _, x in ipairs({ -0.45, 0.45 }) do
		b.gem("Diamond", 0.3, CFrame.new(x, 1.05, 0), Color3.fromRGB(230, 245, 255))
	end
end

MODELS.Pearl = function(b)
	local shell = Color3.fromRGB(200, 180, 190)
	b.ellipsoid("ClamBottom", Vector3.new(3, 0.8, 2.4), CFrame.new(0, -0.6, 0), Enum.Material.SmoothPlastic, shell)
	b.ellipsoid("ClamTop", Vector3.new(3, 0.8, 2.4), CFrame.new(0, 0.2, -0.9) * CFrame.Angles(math.rad(-50), 0, 0), Enum.Material.SmoothPlastic, Color3.fromRGB(180, 160, 175))
	b.ellipsoid("Nacre", Vector3.new(2.6, 0.3, 2), CFrame.new(0, -0.25, 0), Enum.Material.SmoothPlastic, Color3.fromRGB(240, 226, 240)).Reflectance = 0.3
	local pearl = b.ball("Pearl", 1.1, CFrame.new(0, 0.3, 0.2), Enum.Material.SmoothPlastic, Color3.fromRGB(250, 246, 240))
	pearl.Reflectance = 0.35
end

MODELS.Compass = function(b)
	b.disc("Case", 2.4, 0.5, CFrame.new(0, -0.3, 0), Enum.Material.Metal, BRASS)
	local face = b.disc("Face", 2.1, 0.1, CFrame.new(0, 0, 0), Enum.Material.SmoothPlastic, Color3.fromRGB(240, 232, 210))
	face.Reflectance = 0.1
	b.part("NeedleNorth", Vector3.new(0.2, 0.08, 0.9), CFrame.new(0, 0.1, -0.4), Enum.Material.SmoothPlastic, RUBY)
	b.part("NeedleSouth", Vector3.new(0.2, 0.08, 0.9), CFrame.new(0, 0.1, 0.4), Enum.Material.SmoothPlastic, Color3.fromRGB(230, 230, 230))
	b.disc("Lid", 2.4, 0.2, CFrame.new(0, 0.9, -1.1) * CFrame.Angles(math.rad(-70), 0, 0), Enum.Material.Metal, BRASS)
	b.ball("Ring", 0.5, CFrame.new(0, -0.3, 1.3), Enum.Material.Metal, BRASS)
end

MODELS.Chest = function(b)
	local body = CFrame.new(0, -0.5, 0)
	b.part("Box", Vector3.new(3, 1.6, 2), body, Enum.Material.WoodPlanks, WOOD)
	b.part("Lid", Vector3.new(3, 0.4, 2), CFrame.new(0, 0.7, -1) * CFrame.Angles(math.rad(-55), 0, 0) * CFrame.new(0, 0, 1), Enum.Material.WoodPlanks, WOOD)
	for _, x in ipairs({ -1.1, 0, 1.1 }) do
		b.part("Band", Vector3.new(0.25, 1.7, 2.1), body * CFrame.new(x, 0, 0), Enum.Material.Metal, GOLD_DARK)
	end
	b.part("Lock", Vector3.new(0.5, 0.6, 0.2), body * CFrame.new(0, 0.3, 1.05), Enum.Material.Metal, GOLD)
	-- Heaped gold and gems spilling over the rim.
	for k = 0, 8 do
		b.disc("Coin", 0.7, 0.14, CFrame.new(-1 + (k % 3) * 1, 0.35 + math.floor(k / 3) * 0.12, -0.5 + math.floor(k / 3) * 0.4) * CFrame.Angles(0.3 * (k % 2), 0, 0.2), Enum.Material.Metal, GOLD)
	end
	b.gem("Ruby", 0.55, CFrame.new(0.4, 0.75, 0.2), RUBY)
	b.gem("Sapphire", 0.5, CFrame.new(-0.6, 0.7, 0.4), SAPPHIRE)
end

MODELS.Goblet = function(b)
	b.disc("Foot", 1.6, 0.25, CFrame.new(0, -1.3, 0), Enum.Material.Metal, GOLD_DARK)
	b.disc("Stem", 0.35, 1.3, CFrame.new(0, -0.6, 0), Enum.Material.Metal, GOLD)
	b.ball("Knot", 0.6, CFrame.new(0, -0.5, 0), Enum.Material.Metal, GOLD)
	b.disc("Bowl", 1.9, 1.2, CFrame.new(0, 0.55, 0), Enum.Material.Metal, GOLD)
	b.ellipsoid("BowlBase", Vector3.new(1.9, 0.8, 1.9), CFrame.new(0, -0.05, 0), Enum.Material.Metal, GOLD)
	for k = 0, 5 do
		local a = k / 6 * math.pi * 2
		b.gem("Gem", 0.3, CFrame.new(math.cos(a) * 0.97, 0.55, math.sin(a) * 0.97), k % 2 == 0 and RUBY or SAPPHIRE)
	end
end

MODELS.Spyglass = function(b)
	local axis = CFrame.Angles(0, 0.4, math.rad(18))
	b.part("Barrel", Vector3.new(1.8, 0.9, 0.9), axis * CFrame.new(-0.9, 0, 0), Enum.Material.Metal, BRASS, Enum.PartType.Cylinder)
	b.part("Leather", Vector3.new(1.2, 0.95, 0.95), axis * CFrame.new(-1, 0, 0), Enum.Material.Fabric, Color3.fromRGB(90, 50, 30), Enum.PartType.Cylinder)
	b.part("Draw1", Vector3.new(1.3, 0.72, 0.72), axis * CFrame.new(0.5, 0, 0), Enum.Material.Metal, BRASS, Enum.PartType.Cylinder)
	b.part("Draw2", Vector3.new(1.1, 0.56, 0.56), axis * CFrame.new(1.6, 0, 0), Enum.Material.Metal, GOLD, Enum.PartType.Cylinder)
	local lens = b.part("Lens", Vector3.new(0.1, 0.8, 0.8), axis * CFrame.new(-1.85, 0, 0), Enum.Material.Glass, Color3.fromRGB(160, 220, 255), Enum.PartType.Cylinder)
	lens.Transparency = 0.2
	lens.Reflectance = 0.4
end

MODELS.Artifact = function(b)
	-- A small golden idol: seated body, big head, jewelled eyes, headdress.
	b.part("Plinth", Vector3.new(1.8, 0.4, 1.4), CFrame.new(0, -1.4, 0), Enum.Material.Slate, Color3.fromRGB(90, 84, 76))
	b.part("Body", Vector3.new(1.2, 1.4, 0.9), CFrame.new(0, -0.5, 0), Enum.Material.Metal, GOLD)
	for _, x in ipairs({ -0.75, 0.75 }) do
		b.part("Arm", Vector3.new(0.35, 1, 0.35), CFrame.new(x, -0.5, 0.2) * CFrame.Angles(0.4, 0, 0), Enum.Material.Metal, GOLD_DARK)
	end
	b.part("Head", Vector3.new(1.3, 1.1, 1), CFrame.new(0, 0.75, 0), Enum.Material.Metal, GOLD)
	for _, x in ipairs({ -0.3, 0.3 }) do
		b.gem("Eye", 0.28, CFrame.new(x, 0.85, 0.52), EMERALD)
	end
	b.part("Mouth", Vector3.new(0.5, 0.1, 0.1), CFrame.new(0, 0.45, 0.52), Enum.Material.Slate, Color3.fromRGB(60, 40, 20))
	b.part("Headdress", Vector3.new(1.8, 0.35, 1.1), CFrame.new(0, 1.4, 0), Enum.Material.Metal, GOLD_DARK)
	for k = -2, 2 do
		b.part("Feather", Vector3.new(0.25, 0.9, 0.2), CFrame.new(k * 0.35, 1.9, -0.2) * CFrame.Angles(0, 0, k * 0.2), Enum.Material.Metal, GOLD)
	end
	b.gem("Forehead", 0.35, CFrame.new(0, 1.2, 0.52), RUBY)
end

MODELS.Crown = function(b)
	b.disc("Band", 2.4, 0.7, CFrame.new(0, -0.3, 0), Enum.Material.Metal, GOLD)
	local inner = b.disc("Velvet", 2.1, 0.72, CFrame.new(0, -0.28, 0), Enum.Material.Fabric, Color3.fromRGB(140, 20, 40))
	inner.Size += Vector3.new(0.02, 0, 0)
	for k = 0, 7 do
		local a = k / 8 * math.pi * 2
		local p = CFrame.new(math.cos(a) * 1.12, 0.4, math.sin(a) * 1.12) * CFrame.Angles(0, -a, 0)
		b.part("Point", Vector3.new(0.2, 0.9, 0.45), p, Enum.Material.Metal, GOLD)
		b.ball("Pearl", 0.3, p * CFrame.new(0, 0.55, 0), Enum.Material.SmoothPlastic, Color3.fromRGB(250, 246, 240))
		b.gem("Gem", 0.28, CFrame.new(math.cos(a) * 1.22, -0.3, math.sin(a) * 1.22), ({ RUBY, SAPPHIRE, EMERALD })[k % 3 + 1])
	end
	b.ball("Orb", 0.6, CFrame.new(0, 0.9, 0), Enum.Material.Metal, GOLD)
	b.part("Cross", Vector3.new(0.15, 0.6, 0.15), CFrame.new(0, 1.4, 0), Enum.Material.Metal, GOLD)
end

MODELS.Hourglass = function(b)
	for _, y in ipairs({ -1.3, 1.3 }) do
		b.disc("Cap", 2, 0.3, CFrame.new(0, y, 0), Enum.Material.Wood, WOOD)
	end
	for k = 0, 2 do
		local a = k / 3 * math.pi * 2
		b.disc("Post", 0.22, 2.6, CFrame.new(math.cos(a) * 0.8, 0, math.sin(a) * 0.8), Enum.Material.Wood, WOOD)
	end
	for _, y in ipairs({ -0.6, 0.6 }) do
		local bulb = b.ellipsoid("Glass", Vector3.new(1.2, 1.3, 1.2), CFrame.new(0, y, 0), Enum.Material.Glass, Color3.fromRGB(200, 230, 240))
		bulb.Transparency = 0.55
	end
	b.ellipsoid("Sand", Vector3.new(0.9, 0.5, 0.9), CFrame.new(0, -0.95, 0), Enum.Material.Sand, Color3.fromRGB(236, 200, 120))
	b.ellipsoid("Sand", Vector3.new(0.6, 0.35, 0.6), CFrame.new(0, 0.4, 0), Enum.Material.Sand, Color3.fromRGB(236, 200, 120))
	b.part("Stream", Vector3.new(0.06, 0.8, 0.06), CFrame.new(0, -0.3, 0), Enum.Material.Sand, Color3.fromRGB(236, 200, 120))
end

MODELS.Relic = function(b)
	-- The trident of the abyss: a golden shaft, three barbed prongs, a
	-- glowing heart where they meet.
	b.disc("Shaft", 0.28, 4.2, CFrame.new(0, -0.9, 0), Enum.Material.Metal, GOLD)
	b.disc("Grip", 0.36, 0.9, CFrame.new(0, -1.8, 0), Enum.Material.Fabric, Color3.fromRGB(30, 60, 120))
	b.part("Crossbar", Vector3.new(1.8, 0.28, 0.28), CFrame.new(0, 1.2, 0), Enum.Material.Metal, GOLD)
	for _, x in ipairs({ -0.8, 0, 0.8 }) do
		local height = x == 0 and 1.6 or 1.2
		b.part("Prong", Vector3.new(0.22, height, 0.22), CFrame.new(x, 1.3 + height / 2, 0), Enum.Material.Metal, GOLD)
		b.part("Barb", Vector3.new(0.35, 0.35, 0.2), CFrame.new(x, 1.35 + height, 0) * CFrame.Angles(0, 0, math.pi / 4), Enum.Material.Metal, GOLD_DARK)
	end
	local heart = b.ball("Heart", 0.6, CFrame.new(0, 1.2, 0.2), Enum.Material.Neon, Color3.fromRGB(80, 220, 255))
	heart.Transparency = 0.1
end

MODELS.CrystalSkull = function(b)
	local crystal = Color3.fromRGB(190, 230, 255)
	local cranium = b.ellipsoid("Cranium", Vector3.new(2, 2, 2.3), CFrame.new(0, 0.3, 0), Enum.Material.Glass, crystal)
	cranium.Transparency = 0.35
	cranium.Reflectance = 0.3
	local jaw = b.ellipsoid("Jaw", Vector3.new(1.4, 0.8, 1.4), CFrame.new(0, -0.7, 0.35), Enum.Material.Glass, crystal)
	jaw.Transparency = 0.35
	for _, x in ipairs({ -0.42, 0.42 }) do
		b.ball("EyeSocket", 0.55, CFrame.new(x, 0.25, 0.95), Enum.Material.Neon, Color3.fromRGB(120, 60, 255)).Transparency = 0.2
	end
	b.part("Nose", Vector3.new(0.3, 0.35, 0.2), CFrame.new(0, -0.15, 1.08) * CFrame.Angles(0, 0, math.pi / 4), Enum.Material.Glass, Color3.fromRGB(120, 160, 200))
	for k = -2, 2 do
		b.part("Tooth", Vector3.new(0.18, 0.25, 0.12), CFrame.new(k * 0.2, -0.5, 1.02), Enum.Material.Glass, Color3.fromRGB(230, 245, 255))
	end
end

MODELS.OceanHeart = function(b)
	-- A great heart-shaped sapphire on a chain of diamonds.
	for _, x in ipairs({ -0.42, 0.42 }) do
		local lobe = b.ellipsoid("Sapphire", Vector3.new(1.3, 1.3, 0.8), CFrame.new(x, 0.25, 0), Enum.Material.Glass, SAPPHIRE)
		lobe.Reflectance = 0.3
		lobe.Transparency = 0.1
	end
	local tip = b.part("Sapphire", Vector3.new(1.3, 1.3, 0.7), CFrame.new(0, -0.35, 0) * CFrame.Angles(0, 0, math.pi / 4), Enum.Material.Glass, SAPPHIRE)
	tip.Reflectance = 0.3
	tip.Transparency = 0.1
	for k = 0, 11 do
		local a = math.pi * 0.15 + k / 11 * math.pi * 0.7
		b.gem("Diamond", 0.25, CFrame.new(math.cos(a) * 1.6, math.sin(a) * 1.4 + 0.2, 0), Color3.fromRGB(235, 245, 255))
	end
	for k = 0, 9 do
		local a = k / 10 * math.pi * 2
		b.ball("Setting", 0.18, CFrame.new(math.cos(a) * 1.05, math.sin(a) * 0.95 + 0.05, 0.3), Enum.Material.Metal, Color3.fromRGB(220, 220, 230))
	end
end

-- Builds the model for a treasure type, pivoted at its centre.
function TreasureModels.Build(treasureType): Model
	local model = Instance.new("Model")
	model.Name = treasureType.Id
	local core = Instance.new("Part")
	core.Name = "Core"
	core.Anchored = true
	core.CanCollide = false
	core.CanTouch = false
	core.CanQuery = false
	core.Transparency = 1
	core.Size = Vector3.new(3, 3, 3)
	core.CFrame = CFrame.new()
	core.Parent = model
	model.PrimaryPart = core

	local builder = newBuilder(model)
	local build = MODELS[treasureType.Id]
	if build then
		build(builder)
	else
		builder.gem("Gem", 1.4, CFrame.new(), TreasureModels.RarityColors[treasureType.Rarity] or GOLD)
	end

	local color = TreasureModels.RarityColors[treasureType.Rarity] or GOLD
	local glow = GLOW[treasureType.Rarity] or GLOW.Commune
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = glow.range
	light.Brightness = glow.brightness
	light.Shadows = false
	light.Parent = core
	if glow.sparkles > 0 then
		local sparkles = Instance.new("ParticleEmitter")
		sparkles.Name = "Sparkles"
		sparkles.Color = ColorSequence.new(color)
		sparkles.LightEmission = 1
		sparkles.Rate = glow.sparkles
		sparkles.Lifetime = NumberRange.new(0.8, 1.6)
		sparkles.Speed = NumberRange.new(0.4, 1.2)
		sparkles.SpreadAngle = Vector2.new(180, 180)
		sparkles.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 0) })
		sparkles.Transparency = NumberSequence.new(0.2)
		sparkles.Parent = core
	end
	return model
end

function TreasureModels.Has(id: string): boolean
	return MODELS[id] ~= nil
end

return TreasureModels
