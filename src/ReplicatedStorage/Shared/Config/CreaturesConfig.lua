-- Marine creature species. Each entry is data only; the behaviour itself
-- lives in CreatureBrain (server) and is selected by the Behavior field:
--
--   "Passive"  wanders, ignores players entirely (schools of small fish).
--   "Skittish" wanders, darts away when a player comes within FleeDistance.
--   "Predator" wanders, chases any underwater player within ChaseDistance,
--              bites when within AttackRange, gives up past LoseDistance.
--
-- Depth: MinDepth/MaxDepth (studs below the surface) bound both where the
-- species can spawn in fallback placement and where it wanders; a
-- SpawnRegion (see SpawnRegions.lua) can still put it anywhere.
-- Rarity: Weight is the relative pick chance when a region lists several
-- species. Rare = low weight.
--
-- Model: the spawner looks for ReplicatedStorage.Assets.Creatures.<Id>
-- (a Model with a PrimaryPart, facing -Z) -- the slot for Blender assets.
-- Until one exists it builds the flat placeholder described by Size/Color.
--
-- Speeds are studs/s. Sizes are the placeholder's body dimensions.

return {
	Species = {
		{
			Id = "Sardine",
			Name = "Sardine",
			Behavior = "Passive",
			Weight = 60,
			MinDepth = 3,
			MaxDepth = 120,
			Speed = 6,
			TurnResponsiveness = 3,
			WanderRadius = 40,
			Size = Vector3.new(0.4, 0.5, 1.4),
			Color = Color3.fromRGB(180, 195, 210),
			FallbackCount = 24,
		},
		{
			Id = "Tortue",
			Name = "Tortue de mer",
			Behavior = "Skittish",
			Weight = 25,
			MinDepth = 5,
			MaxDepth = 200,
			Speed = 5,
			FleeSpeed = 11,
			FleeDistance = 18,
			TurnResponsiveness = 2,
			WanderRadius = 70,
			Size = Vector3.new(2.2, 0.9, 3),
			Color = Color3.fromRGB(70, 110, 80),
			FallbackCount = 6,
		},
		{
			Id = "Raie",
			Name = "Raie manta",
			Behavior = "Skittish",
			Weight = 12,
			MinDepth = 40,
			MaxDepth = 320,
			Speed = 7,
			FleeSpeed = 14,
			FleeDistance = 22,
			TurnResponsiveness = 1.5,
			WanderRadius = 120,
			Size = Vector3.new(5, 0.5, 4),
			Color = Color3.fromRGB(45, 50, 60),
			FallbackCount = 4,
		},
		{
			Id = "Requin",
			Name = "Requin",
			Behavior = "Predator",
			Weight = 8,
			MinDepth = 60,
			MaxDepth = 400,
			Speed = 8,
			ChaseSpeed = 17,
			ChaseDistance = 55,
			LoseDistance = 110,
			AttackRange = 4.5,
			AttackDamage = 25,
			AttackCooldown = 1.6,
			TurnResponsiveness = 2.5,
			WanderRadius = 150,
			Size = Vector3.new(1.4, 1.4, 5.5),
			Color = Color3.fromRGB(95, 105, 120),
			FallbackCount = 3,
		},
		{
			Id = "Baudroie",
			Name = "Baudroie des abysses",
			Behavior = "Predator",
			Weight = 2,
			MinDepth = 380,
			MaxDepth = 495,
			Speed = 4,
			ChaseSpeed = 12,
			ChaseDistance = 30,
			LoseDistance = 70,
			AttackRange = 4,
			AttackDamage = 40,
			AttackCooldown = 2,
			TurnResponsiveness = 2,
			WanderRadius = 60,
			Size = Vector3.new(1.6, 1.6, 2.6),
			Color = Color3.fromRGB(40, 30, 45),
			Glow = Color3.fromRGB(120, 220, 255),
			FallbackCount = 2,
		},
	},
}
