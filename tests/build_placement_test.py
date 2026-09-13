"""Assembles tests/placement_test.lua from the real game sources.

Same idea as build_creature_test.py/build_archipel_test.py: inline
ArchipelPlacement.server.lua and ArchipelManifestData.lua on top of
tests/stub.lua, and actually EXECUTE it with the standalone `luau` CLI. The
real static geometry (assets/ArchipelDesProfondeurs/*.rbxmx, synced by Rojo)
isn't present in this harness -- a couple of fake Parts stand in for it, just
enough to exercise the renaming/PivotTo/SpawnRegion logic this script itself
is responsible for.

    python3 tests/build_placement_test.py && luau tests/placement_test.lua
"""
import pathlib, re

HERE = pathlib.Path(__file__).resolve().parent
SRC = pathlib.Path("/home/user/divinggame/src")

def read(rel):
    return (SRC / rel).read_text()

def wrap(name, body):
    return f"local {name} = (function()\n{body}\nend)()\n"

parts = [HERE.joinpath("stub.lua").read_text()]

manifest_data = read("ServerScriptService/World/ArchipelManifestData.lua")
parts.append(wrap("ArchipelManifestData", manifest_data))

placement_script = read("ServerScriptService/World/ArchipelPlacement.server.lua")
placement_script = placement_script.replace(
    "local ManifestData = require(script.Parent.ArchipelManifestData)",
    "local ManifestData = ArchipelManifestData",
)
placement_script = "local script = Instance.new(\"Script\")\nscript.Name = \"ArchipelPlacement\"\n" + placement_script
parts.append("function RUN_PLACEMENT()\n" + placement_script + "\nend\n")

parts.append(HERE.joinpath("placement_assertions.lua").read_text())

HERE.joinpath("placement_test.lua").write_text("\n".join(parts))
print("built", sum(len(p.splitlines()) for p in parts), "lines")
