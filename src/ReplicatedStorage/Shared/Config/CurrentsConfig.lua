-- Shared tuning for underwater currents.
--
-- A current is any instance inside Workspace.Currents with a CurrentShape
-- Attribute. CurrentGenerator.server.lua builds the visuals for every one
-- of them at startup -- both the examples it places itself and anything
-- you place by hand in Studio -- so creating a new current never requires
-- editing a script: place it, set a few Attributes, done. Missing
-- Attributes are filled in from the CurrentTier preset below (or Medium).
--
-- Shapes
--   "Directional"  a Part: its box is the zone, its LookVector (Front) is
--                  the flow direction. Size = Width x Height x Length.
--   "Circular"     a Part at the vortex center + CurrentRadius, CurrentSpin
--                  (1 / -1), CurrentSpiralBias (0-1, pull toward center).
--   "Path"         a Model/Folder holding Parts named CurrentPoint_01,
--                  CurrentPoint_02, ... (sorted by name): the flow follows
--                  that polyline through every point -- straight, diagonal,
--                  vertical, climbing, diving, turning, any number of legs.
--                  CurrentWidth is the tube radius around the line.
--
-- Attributes (all shapes)
--   CurrentEnabled          bool, default true
--   CurrentTier             "Weak" | "Medium" | "Strong" | "FastLane"
--   CurrentMaxSpeed         studs/s the water pushes at, at the zone center
--   CurrentAcceleration     studs/s^2 the push ramps up at when entering
--   CurrentExitDeceleration studs/s^2 the push ramps down at when leaving
--   CurrentCentering        0-1, how strongly the flow steers a swimmer back
--                           toward the center line (makes a path "carry"
--                           you along it instead of letting you drift out)
--   CurrentCanBoost         false caps the push at NO_BOOST_CAP: a nudge
--                           that can never become a fast lane
--   CurrentVisualIntensity  0-1, particle density/visibility only
--   CurrentDisplayName      shown in the HUD while inside
--   CurrentSoundId          optional "rbxassetid://..." looped while inside
--
-- The push is added to the player's own swim velocity (real current
-- physics: ground speed = own speed + the water's speed), so swimming with
-- a current adds up and against one genuinely fights it, and the player
-- keeps full control of their own motion inside it. ABSOLUTE_MAX_SPEED is
-- a safety clamp on the summed push of overlapping currents.

return {
	NO_BOOST_CAP = 4,
	ABSOLUTE_MAX_SPEED = 90,

	-- Used when the player is leaving all currents and there is no last
	-- dominant one to take the value from.
	DefaultExitDeceleration = 8,

	-- How quickly the applied push direction follows the local flow
	-- direction (seconds), e.g. through a path's turns.
	DirectionResponseTime = 0.35,

	Tiers = {
		Weak = {
			MaxSpeed = 4,
			Acceleration = 4,
			ExitDeceleration = 4,
			Centering = 0.2,
			CanBoost = false,
			VisualIntensity = 0.4,
		},
		Medium = {
			MaxSpeed = 10,
			Acceleration = 7,
			ExitDeceleration = 7,
			Centering = 0.3,
			CanBoost = true,
			VisualIntensity = 0.7,
		},
		Strong = {
			MaxSpeed = 20,
			Acceleration = 12,
			ExitDeceleration = 10,
			Centering = 0.35,
			CanBoost = true,
			VisualIntensity = 0.9,
		},
		FastLane = {
			MaxSpeed = 48,
			Acceleration = 20,
			ExitDeceleration = 16,
			Centering = 0.45,
			CanBoost = true,
			VisualIntensity = 1,
		},
	},
}
