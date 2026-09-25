-- Dive gear sold at the Centre de plongée, one slot per category. Each
-- player starts with the free item of every category; the rest is bought
-- with Pièces and kept (PlayerData saves it). Effects:
--   Tank  MaxOxygen            seconds of air (OxygenManager's MaxOxygen)
--   Suit  DrainMultiplier      scales the oxygen drain (cold eats air)
--   Fins  SpeedMultiplier      scales swim speed (SwimController)
--   Lamp  LampRange/Brightness a light on the diver's head, for the dark
-- Color/Accent tint the gear the character visibly wears
-- (EquipmentVisuals): tank on the back, suit, fins, mask, lamp.

return {
	Categories = {
		{ Id = "Tank", Name = "Bouteilles", Icon = "◎", Stat = "Autonomie" },
		{ Id = "Suit", Name = "Tenues", Icon = "◆", Stat = "Consommation" },
		{ Id = "Fins", Name = "Palmes", Icon = "➤", Stat = "Vitesse" },
		{ Id = "Lamp", Name = "Lampes", Icon = "✦", Stat = "Portée" },
	},

	Items = {
		-- Bouteilles
		{ Id = "TankStarter", Category = "Tank", Name = "Bouteille 10 L", Price = 0, MaxOxygen = 60, Color = Color3.fromRGB(230, 200, 60), Description = "La bouteille du club, pour débuter au récif." },
		{ Id = "Tank12", Category = "Tank", Name = "Bouteille alu 12 L", Price = 150, MaxOxygen = 85, Color = Color3.fromRGB(200, 205, 212), Description = "Assez d'air pour visiter les grottes." },
		{ Id = "Tank15", Category = "Tank", Name = "Bouteille acier 15 L", Price = 600, MaxOxygen = 120, Color = Color3.fromRGB(60, 130, 220), Description = "Deux minutes au fond : l'épave est à portée." },
		{ Id = "TankTwin", Category = "Tank", Name = "Bi-bouteille 2×12 L", Price = 1800, MaxOxygen = 170, Twin = true, Color = Color3.fromRGB(40, 44, 52), Description = "Le choix des plongeurs d'épave." },
		{ Id = "Rebreather", Category = "Tank", Name = "Recycleur", Price = 5000, MaxOxygen = 260, Twin = true, Color = Color3.fromRGB(240, 120, 40), Description = "Recycle chaque souffle : cap sur les abysses." },

		-- Tenues
		{ Id = "SuitNone", Category = "Suit", Name = "Maillot de bain", Price = 0, DrainMultiplier = 1, Description = "Parfait pour le lagon." },
		{ Id = "Shorty", Category = "Suit", Name = "Shorty 3 mm", Price = 200, DrainMultiplier = 0.9, Color = Color3.fromRGB(30, 120, 190), Accent = Color3.fromRGB(250, 210, 60), Description = "Un peu de chaleur, un peu moins d'air consommé." },
		{ Id = "Wetsuit", Category = "Suit", Name = "Combinaison 5 mm", Price = 800, DrainMultiplier = 0.8, Color = Color3.fromRGB(26, 30, 38), Accent = Color3.fromRGB(40, 200, 230), Description = "Le néoprène des plongées profondes." },
		{ Id = "Drysuit", Category = "Suit", Name = "Combinaison étanche", Price = 2500, DrainMultiplier = 0.68, Color = Color3.fromRGB(150, 30, 40), Accent = Color3.fromRGB(230, 230, 230), Description = "Au sec, même à 400 m." },
		{ Id = "Abyssal", Category = "Suit", Name = "Scaphandre abyssal", Price = 7000, DrainMultiplier = 0.52, Color = Color3.fromRGB(196, 150, 60), Accent = Color3.fromRGB(60, 50, 40), Description = "Le cuivre et le laiton des pionniers des abysses." },

		-- Palmes
		{ Id = "FinsNone", Category = "Fins", Name = "Pieds nus", Price = 0, SpeedMultiplier = 1, Description = "On nage quand même." },
		{ Id = "FinsShort", Category = "Fins", Name = "Palmes courtes", Price = 120, SpeedMultiplier = 1.12, Color = Color3.fromRGB(250, 200, 40), Description = "Légères et maniables." },
		{ Id = "FinsLong", Category = "Fins", Name = "Palmes longues", Price = 700, SpeedMultiplier = 1.25, Color = Color3.fromRGB(40, 170, 230), Description = "Pour couvrir le tombant en quelques battements." },
		{ Id = "FinsCarbon", Category = "Fins", Name = "Palmes carbone", Price = 2200, SpeedMultiplier = 1.4, Color = Color3.fromRGB(30, 30, 34), Description = "Les palmes des apnéistes : rapides comme une raie." },

		-- Lampes
		{ Id = "LampNone", Category = "Lamp", Name = "Sans lampe", Price = 0, LampRange = 0, LampBrightness = 0, Description = "La lumière du jour suffit... au récif." },
		{ Id = "LampTorch", Category = "Lamp", Name = "Lampe torche", Price = 250, LampRange = 40, LampBrightness = 1.6, Color = Color3.fromRGB(250, 200, 40), Description = "Éclaire les grottes." },
		{ Id = "LampPro", Category = "Lamp", Name = "Phare de plongée", Price = 1100, LampRange = 70, LampBrightness = 2.4, Color = Color3.fromRGB(40, 40, 46), Description = "Un faisceau puissant pour l'épave." },
		{ Id = "LampAbyss", Category = "Lamp", Name = "Projecteur abyssal", Price = 3500, LampRange = 110, LampBrightness = 3.4, Color = Color3.fromRGB(200, 60, 40), Description = "Perce le noir des abysses." },
	},

	Defaults = { Tank = "TankStarter", Suit = "SuitNone", Fins = "FinsNone", Lamp = "LampNone" },
}
