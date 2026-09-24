-- The one Script that builds the world, in a fixed order. Roblox gives no
-- run-order guarantee between sibling Scripts, and these steps depend on
-- each other: the ocean fill would drown the cave mountains if it ran
-- after them, the Épave vortex needs the wreck's real stern, decor must
-- know where the wreck/caves/currents are to keep clear of them, and the
-- spawners must see every SpawnRegion before deciding where the open-
-- water fallback is needed. So each builder is a ModuleScript and this
-- runs them one after another, then raises Workspace.WorldReady, which
-- TreasureSpawner and CreatureSpawner wait for.

local Workspace = game:GetService("Workspace")

local Builders = script.Parent.Builders
local WorldLayout = require(Builders.WorldLayout)

local ORDER = { "Ocean", "CaveRegions", "MegaWreckShip", "Currents", "BiomeDecor" }

Workspace:SetAttribute("WorldReady", false)

local layout = WorldLayout.new()
for _, name in ipairs(ORDER) do
	local started = os.clock()
	local ok, err = pcall(function()
		require(Builders[name]).Build(layout)
	end)
	if ok then
		print(string.format("[World] %s built in %.2fs", name, os.clock() - started))
	else
		-- One broken builder must not leave the whole server without a
		-- world or its spawners waiting forever.
		warn(string.format("[World] %s failed: %s", name, tostring(err)))
	end
end

WorldLayout.Current = layout
Workspace:SetAttribute("WorldReady", true)
