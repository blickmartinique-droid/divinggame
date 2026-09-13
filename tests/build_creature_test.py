"""Assembles tests/creature_test.lua from the real game sources.

There is no Roblox runtime here, so each module is inlined into one file on
top of tests/stub.lua (a small, deliberately strict fake of the Roblox API --
Enum members that do not exist really do error, IsA models inheritance) and
run with the standalone `luau` CLI:

    python3 tests/build_creature_test.py && luau tests/creature_test.lua

The point is to actually EXECUTE CreatureSpawner and CreatureBrain, not just
lint them: past bugs in this project (a non-existent Enum member, a facing
offset applied to the wrong body) were invisible to static analysis.
"""
import pathlib, re

HERE = pathlib.Path(__file__).resolve().parent
SRC = HERE.parent / "src"
SCRATCH = HERE

def read(rel):
    return (SRC / rel).read_text()

def wrap(name, body):
    return f"local {name} = (function()\n{body}\nend)()\n"

parts = [SCRATCH.joinpath("stub.lua").read_text()]

# ZonesConfig is only needed so DepthUtils loads.
zones = read("ReplicatedStorage/Shared/Config/ZonesConfig.lua")
parts.append(wrap("ZonesConfig", zones))

depth = read("ReplicatedStorage/Shared/Modules/DepthUtils.lua")
depth = re.sub(r'local ZonesConfig = require\([^\)]*\)', 'local ZonesConfig = ZonesConfig', depth)
parts.append(wrap("DepthUtils", depth))

config = read("ReplicatedStorage/Shared/Config/CreaturesConfig.lua")
parts.append(wrap("CreaturesConfig", config))

spawnregions = read("ReplicatedStorage/Shared/Modules/SpawnRegions.lua")
parts.append(wrap("SpawnRegions", spawnregions))

brain = read("ServerScriptService/Creatures/CreatureBrain.lua")
brain = re.sub(r'local DepthUtils = require\([^\)]*\)', 'local DepthUtils = DepthUtils', brain)
parts.append(wrap("CreatureBrain", brain))

spawner = read("ServerScriptService/Creatures/CreatureSpawner.server.lua")
for mod in ("CreaturesConfig", "SpawnRegions", "DepthUtils", "CreatureBrain"):
    spawner = re.sub(r'local %s = require\([^\)]*\)' % mod, 'local %s = %s' % (mod, mod), spawner)
# the script's own `script` global
spawner = "local script = Instance.new(\"Script\")\nscript.Name = \"CreatureSpawner\"\n" + spawner
parts.append("function RUN_SPAWNER()\n" + spawner + "\nend\n")

parts.append(SCRATCH.joinpath("creature_assertions.lua").read_text())

SCRATCH.joinpath("creature_test.lua").write_text("\n".join(parts))
print("built", sum(len(p.splitlines()) for p in parts), "lines")
