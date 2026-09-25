-- Names the places of the map: each biome is a volume (cylinder, box or
-- sphere) with a display name, a one-line description, an accent colour
-- and a priority (the most specific place wins where volumes overlap).
-- Published as Configuration instances in ReplicatedStorage.Biomes --
-- plain data, never streamed out -- and read on the client by
-- Shared/Modules/BiomeLookup (banner on entering, name on the HUD).
-- Built last, from the anchors the other builders published.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Biomes = {}

local function onBearing(degrees: number, radius: number): Vector3
	local a = math.rad(degrees)
	return Vector3.new(math.cos(a) * radius, 0, math.sin(a) * radius)
end

function Biomes.Build(layout)
	local list = {}
	-- `extra`: optional look overrides while inside (FogEnd).
	local function add(entry, extra)
		for key, value in pairs(extra or {}) do
			entry[key] = value
		end
		table.insert(list, entry)
	end
	local function cylinder(name: string, description: string, color: Color3, priority: number, center: Vector3, radius: number, minY: number, maxY: number, extra: { [string]: any }?)
		add({ Shape = "Cylinder", DisplayName = name, Description = description, Color = color, Priority = priority, Center = center, Radius = radius, MinY = minY, MaxY = maxY }, extra)
	end
	local function sphere(name: string, description: string, color: Color3, priority: number, center: Vector3, radius: number, extra: { [string]: any }?)
		add({ Shape = "Sphere", DisplayName = name, Description = description, Color = color, Priority = priority, Center = center, Radius = radius }, extra)
	end
	local function box(name: string, description: string, color: Color3, priority: number, cframe: CFrame, size: Vector3, extra: { [string]: any }?)
		add({ Shape = "Box", DisplayName = name, Description = description, Color = color, Priority = priority, CFrame = cframe, Size = size }, extra)
	end

	box("Le Grand Bleu", "Pleine eau : raies manta et requins patrouillent", Color3.fromRGB(70, 150, 255), 0, CFrame.new(0, -280, 0), Vector3.new(2000, 240, 2000))
	box("Plaine abyssale", "Vase et lys de mer, les méduses éclairent le noir", Color3.fromRGB(150, 110, 255), 0, CFrame.new(0, -460, 0), Vector3.new(2000, 120, 2000))
	cylinder("Tombant du récif", "La falaise plonge dans le bleu, jardins de gorgones", Color3.fromRGB(90, 220, 200), 1, Vector3.zero, 340, -170, -15)
	cylinder("Le Lagon", "Coraux, poissons de récif et tortues à l'abri du récif", Color3.fromRGB(90, 230, 255), 2, Vector3.zero, 185, -45, 2)
	cylinder("Forêt de kelp", "Kelp géant, colonnes de lumière et tortues", Color3.fromRGB(120, 210, 110), 3, onBearing(265, 265), 125, -200, -10)
	cylinder("Kelp doré", "Une forêt de kelp doré sur le flanc est", Color3.fromRGB(240, 200, 90), 3, onBearing(115, 265), 115, -200, -10)

	local rift = layout:GetAnchor("RiftFrame")
	if rift then
		box("Faille abyssale", "Cheminées hydrothermales et roche en fusion", Color3.fromRGB(255, 120, 70), 3,
			CFrame.fromMatrix(rift.center + Vector3.new(0, 70, 0), rift.along, Vector3.new(0, 1, 0)), Vector3.new(620, 180, 300))
	end

	-- The Cimetière follows its curved ledge: a string of cylinders along
	-- the arc. Wreck biomes see further (FogEnd): their giants must read.
	local graveyard = layout:GetAnchor("Graveyard")
	local site = layout:GetAnchor("WreckSite")
	local wreckFog = { FogEnd = 200 }
	if graveyard and site then
		for t = -site.halfArc, site.halfArc, 85 do
			local angle = site.angle + t / site.distance
			local center = Vector3.new(math.cos(angle), 0, math.sin(angle)) * (site.distance + 25)
			cylinder("Cimetière de la Sirène", "La Sirène Noire et les épaves qui l'ont suivie", Color3.fromRGB(255, 196, 110), 4,
				center, 150, site.position.Y - 60, site.position.Y + 150, wreckFog)
		end
	end

	-- L'Impératrice: around each half, and the debris field between them.
	local liner = layout:GetAnchor("Liner")
	if liner then
		local name, text, color = "L'Impératrice", "Le paquebot géant, brisé en deux dans la plaine abyssale", Color3.fromRGB(120, 225, 255)
		local fog = { FogEnd = 240 }
		box(name, text, color, 4, liner.bowBox.cframe, liner.bowBox.size + Vector3.new(160, 80, 160), fog)
		box(name, text, color, 4, liner.sternBox.cframe, liner.sternBox.size + Vector3.new(160, 80, 160), fog)
		cylinder(name, text, color, 4, Vector3.new(liner.center.X, 0, liner.center.Z), 170, -530, -300, fog)
	end

	-- The volcano's lava tubes: each tube a string of capsules between its
	-- control points, its halls named on top.
	local network = layout:GetAnchor("Network")
	if network then
		for _, tube in pairs(network.tubes) do
			local points = tube.points
			for i = 1, #points - 1 do
				add({ Shape = "Capsule", DisplayName = "Tunnels de lave", Description = "Vers " .. tube.spec.name .. " — suis les runes", Color = Color3.fromRGB(255, 140, 70), Priority = 4, A = points[i], B = points[i + 1], Radius = tube.spec.radius + 4 })
			end
		end
		local descriptions = {
			Coeur = "Un temple englouti sous le volcan, six tunnels en partent",
			Echos = "Cristaux pâles sur la route de l'épave",
			Orgues = "Orgues de basalte sur la route des abysses",
		}
		for _, chamber in ipairs(network.chambers) do
			sphere(chamber.name, descriptions[chamber.id] or "Réseau du Volcan", Color3.fromRGB(255, 150, 80), 5, chamber.center, chamber.radius * 1.2)
		end
	end

	local caves = layout:GetAnchor("Caves")
	if caves then
		for _, chamber in ipairs(caves.chambers) do
			sphere(chamber.spec.name, "Grottes de l'Éperon", Color3.fromRGB(150, 230, 255), 5, chamber.center, chamber.radius * 1.25)
		end
	end

	local old = ReplicatedStorage:FindFirstChild("Biomes")
	if old then
		old:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "Biomes"
	for index, biome in ipairs(list) do
		local config = Instance.new("Configuration")
		config.Name = string.format("%02d_%s", index, biome.DisplayName)
		for key, value in pairs(biome) do
			config:SetAttribute(key, value)
		end
		config.Parent = folder
	end
	folder.Parent = ReplicatedStorage
	print(string.format("[Biomes] %d biomes", #list))
end

return Biomes
