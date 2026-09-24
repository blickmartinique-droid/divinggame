-- Which named place (biome) a point is in, from the volumes the server's
-- Biomes builder publishes in ReplicatedStorage.Biomes. The most specific
-- place (highest Priority) wins where volumes overlap. Works on both sides.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

export type Biome = {
	DisplayName: string,
	Description: string,
	Color: Color3,
	Priority: number,
}

local BiomeLookup = {}

local cache = nil
local watched = false

local function load()
	local folder = ReplicatedStorage:FindFirstChild("Biomes")
	if not folder then
		return nil
	end
	if not watched then
		watched = true
		folder.ChildAdded:Connect(function()
			cache = nil
		end)
		folder.AncestryChanged:Connect(function()
			cache = nil
			watched = false
		end)
	end
	local list = {}
	for _, config in ipairs(folder:GetChildren()) do
		local entry = config:GetAttributes()
		if entry.Shape and entry.DisplayName then
			table.insert(list, entry)
		end
	end
	table.sort(list, function(a, b)
		return (a.Priority or 0) > (b.Priority or 0)
	end)
	return list
end

local function contains(entry, p: Vector3): boolean
	if entry.Shape == "Cylinder" then
		local c = entry.Center
		local dx, dz = p.X - c.X, p.Z - c.Z
		return p.Y >= entry.MinY and p.Y <= entry.MaxY and dx * dx + dz * dz <= entry.Radius * entry.Radius
	elseif entry.Shape == "Sphere" then
		return (p - entry.Center).Magnitude <= entry.Radius
	elseif entry.Shape == "Box" then
		local l = entry.CFrame:PointToObjectSpace(p)
		local h = entry.Size / 2
		return math.abs(l.X) <= h.X and math.abs(l.Y) <= h.Y and math.abs(l.Z) <= h.Z
	end
	return false
end

-- The biome at `position`, or nil (out of every volume, e.g. on the beach).
function BiomeLookup.Find(position: Vector3): Biome?
	if not cache then
		cache = load()
		if not cache then
			return nil
		end
	end
	for _, entry in ipairs(cache) do
		if contains(entry, position) then
			return entry
		end
	end
	return nil
end

return BiomeLookup
