-- Marine creature species. Each entry is data only; the behaviour itself
-- lives in CreatureBrain (server) and is selected by the Behavior field:
--
--   "Passive"  wanders, ignores players entirely (reef fish, jellyfish).
--   "Skittish" wanders, darts away when a player comes within FleeDistance.
--   "Predator" wanders, chases any underwater player within ChaseDistance,
--              bites when within AttackRange, gives up past LoseDistance.
--
-- These 5 species match the 5 rigged/animated assets delivered in the
-- "Archipel des Profondeurs V2" pack (AnimauxMarins/), so a species Id here
-- lines up 1:1 with a real model instead of describing something that does
-- not exist. Every number below that describes the ANIMAL ITSELF (Size,
-- bone count, clip names) comes from that pack's own verification report
-- (AnimauxMarins/verification_animaux.json), not from guesswork.
--
-- SCALE -- the one judgement call worth reading. The pack is authored in
-- metres at 1 m = 1/0.28 studs (~3.5714), and Size below is its measured
-- rest dimensions converted at exactly that rate: the shark comes out
-- 16.85 studs long and the manta 14.57 studs across, matching the two
-- figures the pack's own import guide quotes. That rate is kept (rather
-- than this project's "1 stud = 1 m" depth convention, which exists so
-- 500 m of depth reads as 500 studs) because creature size only has to
-- look right next to a ~5-stud Roblox avatar -- at 1 stud/m a reef shark
-- would be shorter than the player. Depth numbers elsewhere are untouched.
--
-- Blender axes (X, Y, Z) become Roblox (X, Z, -Y), so Size below is the
-- pack's (X, Z, Y) reordered. The fish and shark face -X in Blender (the
-- pack states this explicitly); ModelYawOffsetDegrees rotates the imported
-- model so that nose ends up along Roblox's -Z, which is the direction
-- CreatureBrain steers. Verify it per species after importing -- the pack
-- only confirms the axis for those two.
--
-- ANIMATIONS -- deliberately left nil. The clips exist in the pack but
-- have NOT been published to Roblox, and an asset id cannot be guessed:
-- it is created when YOU upload the clip under the account/group that
-- owns this game. Import each animal, publish its two swims, then paste
-- the real ids below. Everything keeps working with them nil -- the
-- creature simply swims without a body animation (see CreatureSpawner's
-- setupAnimator), so nothing breaks while they are missing.

return {
	-- Metres -> studs, the pack's own rate. Kept here so anything else
	-- converting pack measurements uses one number, not a copy.
	StudsPerMetre = 1 / 0.28,

	-- Both swim clips run at 30 fps in the source files.
	AnimationFps = 30,

	-- Old ids used by SpawnRegions placed before the real assets arrived
	-- (and by any region hand-tagged in Studio since). Resolved by
	-- CreatureSpawner so those regions keep working after the rename.
	Aliases = {
		Sardine = "PoissonRecif",
		Tortue = "TortueMarine",
		Raie = "RaieManta",
		Requin = "RequinRecif",
		Baudroie = "MeduseLumineuse",
	},

	Species = {
		{
			Id = "PoissonRecif",
			Name = "Poisson de récif",
			ModelName = "01_Poisson_Recif", -- ReplicatedStorage.Assets.Creatures.<ModelName>
			Behavior = "Passive",
			Weight = 60,
			MinDepth = 3,
			MaxDepth = 120,
			Speed = 8,
			TurnResponsiveness = 3,
			WanderRadius = 40,
			-- 1.223 x 0.572 x 0.753 m
			Size = Vector3.new(4.37, 2.04, 2.69),
			Color = Color3.fromRGB(60, 180, 200),
			ModelYawOffsetDegrees = -90,
			SlowSwimAnimationId = nil, -- "rbxassetid://..." once 01_Poisson_Recif__Nage_Lente is published
			FastSwimAnimationId = nil, -- "rbxassetid://..." once 01_Poisson_Recif__Nage_Rapide is published
			FallbackCount = 24,
		},
		{
			Id = "TortueMarine",
			Name = "Tortue de mer",
			ModelName = "04_Tortue_Marine",
			Behavior = "Skittish",
			Weight = 25,
			MinDepth = 5,
			MaxDepth = 200,
			Speed = 6,
			FleeSpeed = 13,
			FleeDistance = 18,
			TurnResponsiveness = 2,
			WanderRadius = 70,
			-- 2.276 x 0.688 x 2.334 m
			Size = Vector3.new(8.13, 2.46, 8.34),
			Color = Color3.fromRGB(96, 150, 92),
			ModelYawOffsetDegrees = -90,
			SlowSwimAnimationId = nil,
			FastSwimAnimationId = nil,
			FallbackCount = 6,
		},
		{
			Id = "RaieManta",
			Name = "Raie manta",
			ModelName = "03_Raie_Manta",
			Behavior = "Skittish",
			Weight = 12,
			MinDepth = 40,
			MaxDepth = 320,
			Speed = 8,
			FleeSpeed = 16,
			FleeDistance = 22,
			TurnResponsiveness = 1.5,
			WanderRadius = 120,
			-- 3.523 x 0.385 x 4.080 m (the 14.57-stud wingspan the pack quotes)
			Size = Vector3.new(12.58, 1.38, 14.57),
			Color = Color3.fromRGB(78, 96, 112),
			ModelYawOffsetDegrees = -90,
			SlowSwimAnimationId = nil,
			FastSwimAnimationId = nil,
			FallbackCount = 4,
		},
		{
			Id = "RequinRecif",
			Name = "Requin de récif",
			ModelName = "02_Requin_Recif",
			Behavior = "Predator",
			Weight = 8,
			MinDepth = 60,
			MaxDepth = 400,
			Speed = 10,
			ChaseSpeed = 19, -- under the player's 22.4 sprint, so a chase is always escapable
			ChaseDistance = 55,
			LoseDistance = 110,
			AttackRange = 6,
			AttackDamage = 25,
			AttackCooldown = 1.6,
			TurnResponsiveness = 2.5,
			WanderRadius = 150,
			-- 4.719 x 2.184 x 2.875 m (the 16.85-stud length the pack quotes)
			Size = Vector3.new(16.85, 7.80, 10.27),
			Color = Color3.fromRGB(70, 104, 120),
			ModelYawOffsetDegrees = -90,
			SlowSwimAnimationId = nil,
			FastSwimAnimationId = nil,
			FallbackCount = 3,
		},
		{
			Id = "MeduseLumineuse",
			Name = "Méduse lumineuse",
			ModelName = "05_Meduse_Lumineuse",
			Behavior = "Passive",
			Weight = 4,
			MinDepth = 300,
			MaxDepth = 495,
			Speed = 3, -- barely swims; it drifts
			TurnResponsiveness = 1,
			WanderRadius = 50,
			-- 1.360 x 2.102 x 1.888 m
			Size = Vector3.new(4.86, 7.51, 6.74),
			Color = Color3.fromRGB(150, 190, 225),
			Glow = Color3.fromRGB(120, 220, 255),
			ModelYawOffsetDegrees = -90,
			SlowSwimAnimationId = nil,
			FastSwimAnimationId = nil,
			FallbackCount = 5,
		},
	},
}
