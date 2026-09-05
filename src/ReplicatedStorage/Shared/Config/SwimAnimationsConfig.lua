-- Custom swim animation asset IDs, added back one at a time to isolate
-- which ones actually work. A nil entry means that direction isn't set
-- yet — SwimController falls back to the default avatar's own swim
-- animation for it.

return {
	Idle = "rbxassetid://88717637028322",
	Backward = "rbxassetid://121324014130406",
	Forward = nil,
}
