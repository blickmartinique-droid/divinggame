-- Treasure types for V1. Rarity affects spawn weight (higher weight = more
-- common); value is added to Coins when sold at the surface (a later step).

return {
	Types = {
		{ Id = "Coin", Name = "Pièce", Value = 5, Rarity = "Commune", Weight = 50 },
		{ Id = "Jewel", Name = "Bijou", Value = 20, Rarity = "Peu commune", Weight = 25 },
		{ Id = "Chest", Name = "Coffret", Value = 40, Rarity = "Rare", Weight = 15 },
		{ Id = "Artifact", Name = "Artefact ancien", Value = 100, Rarity = "Très rare", Weight = 8 },
		{ Id = "Relic", Name = "Relique", Value = 250, Rarity = "Légendaire", Weight = 2 },
	},
}
