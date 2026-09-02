-- Oxygen tuning. Equipment upgrades (Bouteille) will scale MaxOxygen in a
-- later step; morphology will also read from here.

return {
	MaxOxygen = 60, -- seconds of breath underwater with starting gear
	DrainPerSecond = 1, -- oxygen lost per second while depth > 0
	RegenPerSecond = 2, -- oxygen regained per second at the surface (depth == 0)
}
