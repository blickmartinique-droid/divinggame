"""Assembles the test suites from the real game sources.

There is no Roblox runtime here, so every .lua file under the Rojo tree
(default.project.json) is mounted into a small, deliberately strict fake
of the Roblox API (tests/stub.lua: Enum members that do not exist really
do error, IsA models inheritance, Terrain records every fill) exactly where
Rojo would put it -- ModuleScripts, Scripts and LocalScripts under their
real parents, with a Roblox-like `require` (tests/registry.lua). Each
suite is that tree + its assertions file, run with the `luau` CLI:

    python3 tests/build_tests.py
    luau tests/creature_test.lua
    luau tests/world_test.lua

The point is to actually EXECUTE the game code, not just lint it: past
bugs in this project (a non-existent Enum member, a facing offset applied
to the wrong body, an ocean fill drowning the caves) were invisible to
static analysis.
"""
import json, pathlib

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parent
project = json.loads((ROOT / "default.project.json").read_text())

mounts = []

def mount_dir(instance_path, directory):
    for entry in sorted(directory.iterdir()):
        if entry.is_dir():
            mount_dir(instance_path + [entry.name], entry)
        elif entry.suffix == ".lua":
            name = entry.name
            if name.endswith(".server.lua"):
                cls, name = "Script", name[: -len(".server.lua")]
            elif name.endswith(".client.lua"):
                cls, name = "LocalScript", name[: -len(".client.lua")]
            else:
                cls, name = "ModuleScript", name[: -len(".lua")]
            mounts.append((instance_path + [name], cls, entry))

def walk(node, instance_path):
    if "$path" in node:
        mount_dir(instance_path, ROOT / node["$path"])
    for key, child in node.items():
        if not key.startswith("$") and isinstance(child, dict):
            walk(child, instance_path + [key])

walk(project["tree"], [])

tree = [(HERE / "stub.lua").read_text(), (HERE / "registry.lua").read_text()]
for path, cls, file in mounts:
    lua_path = "{" + ", ".join(json.dumps(p) for p in path) + "}"
    tree.append("MOUNT(%s, %s, function(script)\n%s\nend)\n" % (lua_path, json.dumps(cls), file.read_text()))

for suite in ("creature", "world"):
    body = "\n".join(tree + [(HERE / f"{suite}_assertions.lua").read_text()])
    (HERE / f"{suite}_test.lua").write_text(body)
    print(f"built tests/{suite}_test.lua ({len(mounts)} scripts mounted)")
