-- Treasure types for V1. Rarity affects spawn weight (higher weight = more
-- common) within a zone; value is added to Coins when sold at the surface
-- (a later step). MinZoneIndex is the earliest zone (1=Récif, 2=Grottes,
-- 3=Épave, 4=Abysses, matching ZonesConfig.Zones order) this type can spawn
-- in, so better loot unlocks progressively with depth.

return {
	Types = {
		{ Id = "Coin", Name = "Pièce", Value = 5, Rarity = "Commune", Weight = 50, MinZoneIndex = 1 },
		{ Id = "Jewel", Name = "Bijou", Value = 20, Rarity = "Peu commune", Weight = 25, MinZoneIndex = 1 },
		{ Id = "Chest", Name = "Coffret", Value = 40, Rarity = "Rare", Weight = 15, MinZoneIndex = 2 },
		{ Id = "Artifact", Name = "Artefact ancien", Value = 100, Rarity = "Très rare", Weight = 8, MinZoneIndex = 3 },
		{ Id = "Relic", Name = "Relique", Value = 250, Rarity = "Légendaire", Weight = 2, MinZoneIndex = 4 },
	},
}
