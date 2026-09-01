-- Depth ranges (in studs, 1 stud = 1 meter) for the V1 zones (0-500m).
-- Deeper tiers (1000m+) are intentionally not defined yet: extend this list
-- and raise MaxDepth when a future update adds them.

return {
	MaxDepth = 500,
	Zones = {
		{ Name = "Récif", MinDepth = 0, MaxDepth = 100 },
		{ Name = "Grottes", MinDepth = 100, MaxDepth = 250 },
		{ Name = "Épave", MinDepth = 250, MaxDepth = 400 },
		{ Name = "Abysses", MinDepth = 400, MaxDepth = 500 },
	},
}
