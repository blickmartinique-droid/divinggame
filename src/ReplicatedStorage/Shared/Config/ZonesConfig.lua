-- Depth ranges (in studs, 1 stud = 1 meter) for the V1 zones (0-500m).
-- Deeper tiers (1000m+) are intentionally not defined yet: extend this list
-- and raise MaxDepth when a future update adds them.
--
-- Visuals per zone (used by ZoneAnnouncer) get progressively darker/murkier
-- with depth, giving the "impression de profondeur" called for in the
-- design: good visibility at the reef, near-blackness in the abysses.

return {
	MaxDepth = 500,
	Zones = {
		{
			Name = "Récif",
			MinDepth = 0,
			MaxDepth = 100,
			FogColor = Color3.fromRGB(120, 170, 180),
			FogEnd = 1200,
			Brightness = 3,
			AtmosphereHaze = 1.2,
		},
		{
			Name = "Grottes",
			MinDepth = 100,
			MaxDepth = 250,
			FogColor = Color3.fromRGB(40, 70, 90),
			FogEnd = 400,
			Brightness = 1.5,
			AtmosphereHaze = 2,
		},
		{
			Name = "Épave",
			MinDepth = 250,
			MaxDepth = 400,
			FogColor = Color3.fromRGB(15, 30, 45),
			FogEnd = 200,
			Brightness = 0.8,
			AtmosphereHaze = 3,
		},
		{
			Name = "Abysses",
			MinDepth = 400,
			MaxDepth = 500,
			FogColor = Color3.fromRGB(2, 5, 10),
			FogEnd = 80,
			Brightness = 0.2,
			AtmosphereHaze = 4,
		},
	},
}
