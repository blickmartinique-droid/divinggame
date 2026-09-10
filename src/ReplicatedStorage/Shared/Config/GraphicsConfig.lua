-- Graphics quality tiers. GraphicsQuality (Modules) picks one at startup
-- (High by default, Medium on touch devices, Low when Roblox's own saved
-- quality level is very low) and every visual script reads its multipliers
-- from there, so adding a settings menu later is only a matter of calling
-- GraphicsQuality.SetLevel. Gameplay never depends on any of this.

return {
	DefaultLevel = "High",

	Levels = {
		High = {
			ParticleScale = 1, -- multiplies every ambient/effect emitter rate
			LightShafts = 6, -- underwater sun beams around the camera
			PostEffects = true, -- Bloom / ColorCorrection / SunRays
			SunRays = true,
			CurrentTubes = true, -- translucent 3D tube along path currents
			Clouds = true,
		},
		Medium = {
			ParticleScale = 0.6,
			LightShafts = 3,
			PostEffects = true,
			SunRays = false,
			CurrentTubes = true,
			Clouds = true,
		},
		Low = {
			ParticleScale = 0.3,
			LightShafts = 0,
			PostEffects = false,
			SunRays = false,
			CurrentTubes = false,
			Clouds = false,
		},
	},
}
