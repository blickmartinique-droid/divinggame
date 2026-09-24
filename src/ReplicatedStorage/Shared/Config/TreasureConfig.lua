-- Treasure types. Rarity sets the spawn weight within a zone (higher weight
-- = more common) and the glow; Value is added to the bag, sold on
-- surfacing. MinZoneIndex is the shallowest zone (1=Récif, 2=Grottes,
-- 3=Épave, 4=Entrée de l'abysse, ZonesConfig.Zones order) the type can
-- spawn in, so better loot unlocks with depth. Each Id has its own model
-- in Shared/Modules/TreasureModels.

return {
	Types = {
		-- Commune
		{ Id = "Coin", Name = "Pièces d'or", Value = 5, Rarity = "Commune", Weight = 22, MinZoneIndex = 1 },
		{ Id = "Bottle", Name = "Bouteille à la mer", Value = 7, Rarity = "Commune", Weight = 16, MinZoneIndex = 1 },
		{ Id = "Conch", Name = "Conque nacrée", Value = 6, Rarity = "Commune", Weight = 14, MinZoneIndex = 1 },
		-- Peu commune
		{ Id = "Jewel", Name = "Bague sertie", Value = 20, Rarity = "Peu commune", Weight = 9, MinZoneIndex = 1 },
		{ Id = "Pearl", Name = "Perle géante", Value = 24, Rarity = "Peu commune", Weight = 8, MinZoneIndex = 1 },
		{ Id = "Compass", Name = "Boussole en laiton", Value = 18, Rarity = "Peu commune", Weight = 8, MinZoneIndex = 1 },
		-- Rare
		{ Id = "Chest", Name = "Coffret au trésor", Value = 45, Rarity = "Rare", Weight = 6, MinZoneIndex = 2 },
		{ Id = "Goblet", Name = "Calice doré", Value = 50, Rarity = "Rare", Weight = 5, MinZoneIndex = 2 },
		{ Id = "Spyglass", Name = "Longue-vue du capitaine", Value = 40, Rarity = "Rare", Weight = 5, MinZoneIndex = 2 },
		-- Très rare
		{ Id = "Artifact", Name = "Idole d'or", Value = 110, Rarity = "Très rare", Weight = 3, MinZoneIndex = 3 },
		{ Id = "Crown", Name = "Couronne engloutie", Value = 130, Rarity = "Très rare", Weight = 2.5, MinZoneIndex = 3 },
		{ Id = "Hourglass", Name = "Sablier ancien", Value = 100, Rarity = "Très rare", Weight = 2.5, MinZoneIndex = 3 },
		-- Légendaire
		{ Id = "Relic", Name = "Trident des abysses", Value = 300, Rarity = "Légendaire", Weight = 0.8, MinZoneIndex = 4 },
		{ Id = "CrystalSkull", Name = "Crâne de cristal", Value = 260, Rarity = "Légendaire", Weight = 0.8, MinZoneIndex = 4 },
		{ Id = "OceanHeart", Name = "Cœur de l'Océan", Value = 320, Rarity = "Légendaire", Weight = 0.6, MinZoneIndex = 4 },
	},
}
