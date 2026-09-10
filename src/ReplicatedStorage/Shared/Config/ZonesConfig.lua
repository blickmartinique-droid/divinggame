-- Depth ranges (in studs, 1 stud = 1 meter) for the V1 zones (0-500m) and
-- the look of the water at each one. Deeper tiers (1000m+) are intentionally
-- not defined yet: extend the list and raise MaxDepth when they arrive.
--
-- Visuals per zone are the environment's state AT that zone's MinDepth;
-- ZoneAnnouncer blends continuously from one zone to the next as the
-- CAMERA's depth changes, so 0-500m reads as one smooth gradient: bright
-- tropical shallows with visible colour and strong sun rays, dimming and
-- desaturating through the mid-water, to a near-black abyss where only
-- bioluminescence remains. Surface is a separate preset (blended over the
-- first SurfaceBlendDepth studs) so breaking the surface is an immediate,
-- readable change of world rather than a continuation of the beach look.
--
-- Fields: FogColor/FogEnd (Lighting fog), Brightness, Ambient,
-- OutdoorAmbient, ExposureCompensation, AtmosphereDensity/Haze/Color/Decay
-- (volume feel), Saturation/Contrast/Tint (ColorCorrection), SunRays
-- (SunRaysEffect intensity: the god rays seen looking up near the surface).

return {
	MaxDepth = 500,
	SurfaceBlendDepth = 3,

	Surface = {
		FogColor = Color3.fromRGB(196, 222, 235),
		FogEnd = 3200,
		Brightness = 2.6,
		Ambient = Color3.fromRGB(118, 130, 140),
		OutdoorAmbient = Color3.fromRGB(150, 175, 190),
		ExposureCompensation = 0.1,
		AtmosphereDensity = 0.32,
		AtmosphereHaze = 1.4,
		AtmosphereColor = Color3.fromRGB(205, 228, 242),
		AtmosphereDecay = Color3.fromRGB(96, 142, 168),
		Saturation = 0.12,
		Contrast = 0.06,
		Tint = Color3.fromRGB(255, 252, 245),
		SunRays = 0.1,
	},

	Zones = {
		{
			Name = "Récif",
			MinDepth = 0,
			MaxDepth = 100,
			FogColor = Color3.fromRGB(38, 140, 165),
			FogEnd = 330,
			Brightness = 2.2,
			Ambient = Color3.fromRGB(40, 95, 110),
			OutdoorAmbient = Color3.fromRGB(70, 150, 170),
			ExposureCompensation = 0.2,
			AtmosphereDensity = 0.62,
			AtmosphereHaze = 2.4,
			AtmosphereColor = Color3.fromRGB(60, 170, 190),
			AtmosphereDecay = Color3.fromRGB(20, 90, 120),
			Saturation = 0.2,
			Contrast = 0.08,
			Tint = Color3.fromRGB(215, 245, 255),
			SunRays = 0.32,
		},
		{
			Name = "Grottes",
			MinDepth = 100,
			MaxDepth = 250,
			FogColor = Color3.fromRGB(14, 62, 92),
			FogEnd = 190,
			Brightness = 1.2,
			Ambient = Color3.fromRGB(14, 36, 52),
			OutdoorAmbient = Color3.fromRGB(24, 70, 95),
			ExposureCompensation = 0.1,
			AtmosphereDensity = 0.78,
			AtmosphereHaze = 3,
			AtmosphereColor = Color3.fromRGB(22, 90, 125),
			AtmosphereDecay = Color3.fromRGB(8, 40, 65),
			Saturation = -0.05,
			Contrast = 0.12,
			Tint = Color3.fromRGB(190, 220, 255),
			SunRays = 0.08,
		},
		{
			Name = "Épave",
			MinDepth = 250,
			MaxDepth = 400,
			FogColor = Color3.fromRGB(5, 22, 42),
			FogEnd = 110,
			Brightness = 0.55,
			Ambient = Color3.fromRGB(6, 14, 24),
			OutdoorAmbient = Color3.fromRGB(10, 26, 42),
			ExposureCompensation = 0,
			AtmosphereDensity = 0.88,
			AtmosphereHaze = 4,
			AtmosphereColor = Color3.fromRGB(8, 34, 60),
			AtmosphereDecay = Color3.fromRGB(2, 12, 26),
			Saturation = -0.25,
			Contrast = 0.18,
			Tint = Color3.fromRGB(170, 200, 255),
			SunRays = 0,
		},
		{
			Name = "Entrée de l'abysse",
			MinDepth = 400,
			MaxDepth = 500,
			FogColor = Color3.fromRGB(1, 4, 10),
			FogEnd = 55,
			Brightness = 0.15,
			Ambient = Color3.fromRGB(2, 3, 6),
			OutdoorAmbient = Color3.fromRGB(3, 6, 12),
			ExposureCompensation = -0.1,
			AtmosphereDensity = 0.95,
			AtmosphereHaze = 5,
			AtmosphereColor = Color3.fromRGB(2, 8, 18),
			AtmosphereDecay = Color3.fromRGB(0, 2, 6),
			Saturation = -0.45,
			Contrast = 0.25,
			Tint = Color3.fromRGB(150, 180, 255),
			SunRays = 0,
		},
	},
}
