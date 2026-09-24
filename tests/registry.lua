-- Module registry: scripts mounted into the stub's instance tree where Rojo
-- would place them (see build_world_test.py), plus a Roblox-like require.
local moduleCache = {}

function MOUNT(path, className, loader)
	local node = game:GetService(path[1])
	for i = 2, #path - 1 do
		local child = node:FindFirstChild(path[i])
		if not child then
			child = Instance.new("Folder")
			child.Name = path[i]
			child.Parent = node
		end
		node = child
	end
	local scriptInstance = Instance.new(className)
	scriptInstance.Name = path[#path]
	rawset(scriptInstance, "_loader", loader)
	scriptInstance.Parent = node
end

function require(instance)
	if moduleCache[instance] ~= nil then
		return moduleCache[instance]
	end
	local loader = rawget(instance, "_loader")
	assert(loader and instance.ClassName == "ModuleScript", "require: not a ModuleScript")
	local result = loader(instance)
	moduleCache[instance] = result
	return result
end

function RESET_MODULES()
	moduleCache = {}
end

function RUN_SCRIPT(...)
	local node = game:GetService((...))
	local path = { ... }
	for i = 2, #path do
		node = node:FindFirstChild(path[i])
		assert(node, "RUN_SCRIPT: missing " .. table.concat(path, "."))
	end
	return rawget(node, "_loader")(node)
end
