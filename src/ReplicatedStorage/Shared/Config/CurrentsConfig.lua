-- Shared tuning for underwater current zones. Each placed current (see
-- CurrentGenerator.server.lua) starts from one of these tier presets and can
-- override any field via Attributes on its own marker Part -- these are
-- just sensible defaults per tier, not hardcoded per-instance limits, so
-- new currents can be tuned individually straight from the Explorer.
--
-- FlowSpeed: the speed (studs/s) the current pushes a player at when
-- they're at its center, in its own direction. It's combined ADDITIVELY
-- with the player's own swim velocity (real current physics: your speed
-- over the seafloor = your own swim speed + the water's own speed), so
-- swimming with a current genuinely adds up and swimming against one
-- genuinely fights it -- no separate boost/resist logic needed on top of
-- that vector sum.
--
-- CanBoost: if false, this current's contribution is capped at
-- NO_BOOST_CAP so it can still nudge or redirect the player but can never
-- become a fast lane; if true, its full FlowSpeed applies.
--
-- VisualIntensity: 0-1, scales particle rate/visibility only -- entirely
-- independent of gameplay strength, so a current can in principle look
-- more or less dramatic than it actually pushes, though the tiers below
-- keep them matched for a coherent "stronger = more visible" default.
--
-- Hooking enter/exit behaviour (sounds, camera effects, VFX built
-- separately, HUD): listen to CurrentField.Entered / Exited / Changed on
-- the client -- each passes the current's marker Part, so any Attribute on
-- it (CurrentTier, CurrentDisplayName, CurrentFlowSpeed, or custom ones
-- added in Studio) is available to decide what to do. CurrentField
-- .GetInfluence() gives a 0-1 "how deep inside" value for fading effects.

return {
	NO_BOOST_CAP = 4,

	Tiers = {
		Weak = {
			FlowSpeed = 3,
			CanBoost = false,
			VisualIntensity = 0.4,
		},
		Medium = {
			FlowSpeed = 7,
			CanBoost = true,
			VisualIntensity = 0.7,
		},
		Strong = {
			FlowSpeed = 13,
			CanBoost = true,
			VisualIntensity = 1,
		},
	},
}
