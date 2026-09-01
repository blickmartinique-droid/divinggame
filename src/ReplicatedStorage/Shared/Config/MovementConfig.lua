-- Base swim movement tuning shared by client and (later) server systems.
-- Morphology multipliers (Petit/Moyen/Grand) will read from this table in a later step.

return {
	BaseSwimSpeed = 16, -- horizontal speed in studs/s, applied to Humanoid.WalkSpeed
	VerticalSwimSpeed = 12, -- ascend/descend speed in studs/s
}
