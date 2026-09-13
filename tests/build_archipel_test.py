"""Assembles tests/archipel_test.lua from the real game sources.

Same idea as build_creature_test.py (see its docstring): inline TitanShip
.server.lua and ArchipelWorld.server.lua plus their data tables on top of
tests/stub.lua, and actually EXECUTE them with the standalone `luau` CLI.

    python3 tests/build_archipel_test.py && luau tests/archipel_test.lua

The point is to catch what static analysis can't: a real Enum.Material
typo, a degenerate zero-size Part, or -- the actual bug this pipeline
found -- two source meshes sharing one bounding box that would have
rebuilt as a single giant solid slab plugging a real entrance.
"""
import pathlib, re

HERE = pathlib.Path(__file__).resolve().parent
SRC = pathlib.Path("/home/user/divinggame/src")

def read(rel):
    return (SRC / rel).read_text()

def wrap(name, body):
    return f"local {name} = (function()\n{body}\nend)()\n"

parts = [HERE.joinpath("stub.lua").read_text()]

titan_data = read("ServerScriptService/World/TitanShipData.lua")
parts.append(wrap("TitanShipData", titan_data))

archipel_world_data = read("ServerScriptService/World/ArchipelWorldData.lua")
parts.append(wrap("ArchipelWorldData", archipel_world_data))

archipel_terrain_data = read("ServerScriptService/World/ArchipelTerrainData.lua")
parts.append(wrap("ArchipelTerrainData", archipel_terrain_data))

titan_script = read("ServerScriptService/World/TitanShip.server.lua")
titan_script = titan_script.replace('local ShipData = require(script.Parent.TitanShipData)', 'local ShipData = TitanShipData')
titan_script = "local script = Instance.new(\"Script\")\nscript.Name = \"TitanShip\"\n" + titan_script
parts.append("function RUN_TITAN()\n" + titan_script + "\nend\n")

archipel_script = read("ServerScriptService/World/ArchipelWorld.server.lua")
archipel_script = archipel_script.replace('local WorldData = require(script.Parent.ArchipelWorldData)', 'local WorldData = ArchipelWorldData')
archipel_script = archipel_script.replace('local TerrainData = require(script.Parent.ArchipelTerrainData)', 'local TerrainData = ArchipelTerrainData')
archipel_script = "local script = Instance.new(\"Script\")\nscript.Name = \"ArchipelWorld\"\n" + archipel_script
parts.append("function RUN_ARCHIPEL()\n" + archipel_script + "\nend\n")

parts.append(HERE.joinpath("archipel_assertions.lua").read_text())

HERE.joinpath("archipel_test.lua").write_text("\n".join(parts))
print("built", sum(len(p.splitlines()) for p in parts), "lines")
