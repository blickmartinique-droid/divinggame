-- Custom swim animation asset IDs, added back one at a time to isolate
-- which ones actually work. A nil entry means that direction isn't set
-- yet — SwimController falls back to the default avatar's own swim
-- animation for it.

return {
	Idle = "rbxassetid://138464368236764",
	Backward = "rbxassetid://121324014130406",
	Forward = "rbxassetid://138297722607060",
	Sprint = "rbxassetid://98064963802805",
}
