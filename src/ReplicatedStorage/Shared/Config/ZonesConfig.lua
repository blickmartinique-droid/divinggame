-- Depth ranges (in studs, 1 stud = 1 meter) for the V1 zones (0-500m).
-- Deeper tiers (1000m+) are intentionally not defined yet: extend this list
-- and raise MaxDepth when a future update adds them.
--
-- Visuals per zone are the environment's state AT that zone's MinDepth;
-- ZoneAnnouncer interpolates continuously between one zone's values and the
-- next as the player's actual depth changes, rather than snapping only at
-- the boundaries, so 0-500m reads as one smooth gradient. Ambient and
-- OutdoorAmbient (the base fill light that still illuminates surfaces in
-- fog/shadow) are included here specifically so light keeps fading with
-- depth instead of staying fixed at the bright surface default -- without
-- them, even a low Brightness still leaves everything looking flatly lit.
-- Récif's own Ambient/OutdoorAmbient match OceanGenerator's global surface
-- defaults, so depth 0 is a seamless continuation of standing on the beach.

return {
	MaxDepth = 500,
	Zones = {
		{
			Name = "Récif",
			MinDepth = 0,
			MaxDepth = 100,
			FogColor = Color3.fromRGB(110, 155, 165),
			FogEnd = 850,
			Brightness = 3,
			AtmosphereHaze = 1.2,
			Ambient = Color3.fromRGB(70, 90, 100),
			OutdoorAmbient = Color3.fromRGB(130, 160, 170),
		},
		{
			Name = "Grottes",
			MinDepth = 100,
			MaxDepth = 250,
			FogColor = Color3.fromRGB(35, 65, 85),
			FogEnd = 350,
			Brightness = 1.5,
			AtmosphereHaze = 2,
			Ambient = Color3.fromRGB(25, 35, 45),
			OutdoorAmbient = Color3.fromRGB(45, 60, 70),
		},
		{
			Name = "Épave",
			MinDepth = 250,
			MaxDepth = 400,
			FogColor = Color3.fromRGB(14, 27, 40),
			FogEnd = 180,
			Brightness = 0.8,
			AtmosphereHaze = 3,
			Ambient = Color3.fromRGB(10, 15, 20),
			OutdoorAmbient = Color3.fromRGB(15, 22, 28),
		},
		{
			Name = "Entrée de l'abysse",
			MinDepth = 400,
			MaxDepth = 500,
			FogColor = Color3.fromRGB(2, 5, 10),
			FogEnd = 70,
			Brightness = 0.2,
			AtmosphereHaze = 4,
			Ambient = Color3.fromRGB(2, 3, 5),
			OutdoorAmbient = Color3.fromRGB(3, 5, 8),
		},
	},
}
