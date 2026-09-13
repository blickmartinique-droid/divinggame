-- Assertions -----------------------------------------------------------
math.randomseed(20260913) -- reproducible spawns
local failures, checks = 0, 0
local function check(label, ok, detail)
	checks += 1
	if not ok then
		failures += 1
		print(string.format("FAIL  %s%s", label, detail and ("  -- " .. tostring(detail)) or ""))
	end
end
local function section(name) print("\n== " .. name .. " ==") end

-- 1. Config schema -----------------------------------------------------
section("CreaturesConfig")
local byId = {}
for _, s in ipairs(CreaturesConfig.Species) do byId[s.Id] = s end

check("5 species delivered", #CreaturesConfig.Species == 5, #CreaturesConfig.Species)
for _, s in ipairs(CreaturesConfig.Species) do
	check(s.Id .. ": has ModelName", type(s.ModelName) == "string" and s.ModelName ~= "")
	check(s.Id .. ": behaviour known", s.Behavior == "Passive" or s.Behavior == "Skittish" or s.Behavior == "Predator", s.Behavior)
	check(s.Id .. ": MinDepth < MaxDepth", s.MinDepth < s.MaxDepth)
	check(s.Id .. ": depth within playable 0..500", s.MinDepth >= 0 and s.MaxDepth <= 500, s.MaxDepth)
	check(s.Id .. ": positive size", s.Size.X > 0 and s.Size.Y > 0 and s.Size.Z > 0)
	check(s.Id .. ": positive speed", s.Speed > 0)
	check(s.Id .. ": Weight > 0", (s.Weight or 0) > 0)
	check(s.Id .. ": animation ids unset (never invented)",
		s.SlowSwimAnimationId == nil and s.FastSwimAnimationId == nil)
	if s.Behavior == "Skittish" then
		check(s.Id .. ": FleeDistance set", (s.FleeDistance or 0) > 0)
		check(s.Id .. ": flees faster than it cruises", (s.FleeSpeed or 0) > s.Speed)
	end
	if s.Behavior == "Predator" then
		for _, field in ipairs({ "ChaseSpeed", "ChaseDistance", "LoseDistance", "AttackRange", "AttackDamage", "AttackCooldown" }) do
			check(s.Id .. ": " .. field .. " set", (s[field] or 0) > 0)
		end
		check(s.Id .. ": LoseDistance > ChaseDistance", s.LoseDistance > s.ChaseDistance)
		-- The player sprints at 22.4; a chase the player cannot outrun is a
		-- death sentence rather than a threat.
		check(s.Id .. ": escapable (ChaseSpeed < 22.4)", s.ChaseSpeed < 22.4, s.ChaseSpeed)
	end
end

for alias, target in pairs(CreaturesConfig.Aliases) do
	check("alias " .. alias .. " -> real species", byId[target] ~= nil, target)
	check("alias " .. alias .. " is not itself a species id", byId[alias] == nil)
end

-- Metre -> stud conversion matches the two figures the pack quotes.
check("StudsPerMetre ~= 3.5714", APPROX(CreaturesConfig.StudsPerMetre, 1 / 0.28, 1e-6))
check("shark length 16.85 studs", APPROX(byId.RequinRecif.Size.X, 4.719 * CreaturesConfig.StudsPerMetre, 0.02), byId.RequinRecif.Size.X)
check("manta wingspan 14.57 studs", APPROX(byId.RaieManta.Size.Z, 4.080 * CreaturesConfig.StudsPerMetre, 0.02), byId.RaieManta.Size.Z)
-- Every animal must read as big next to a ~5-stud avatar.
check("shark longer than a player is tall", byId.RequinRecif.Size.X > 5)

-- Depth bands must cover the whole 0..500 column, or some depth spawns nothing.
local covered = {}
for depth = 5, 495, 5 do
	for _, s in ipairs(CreaturesConfig.Species) do
		if depth >= s.MinDepth and depth <= s.MaxDepth then covered[depth] = true end
	end
end
local gaps = {}
for depth = 5, 495, 5 do
	if not covered[depth] then table.insert(gaps, depth) end
end
check("depth column 5..495 m fully populated", #gaps == 0, table.concat(gaps, ","))

-- 2. Region species strings resolve ------------------------------------
section("RegionSpecies strings referenced by the world scripts")
local function resolve(id) return byId[id] or byId[CreaturesConfig.Aliases[id] or ""] end
local REGION_STRINGS = {
	"PoissonRecif,TortueMarine,RaieManta",
	"RaieManta,RequinRecif",
	"RequinRecif,RaieManta",
	"RequinRecif,MeduseLumineuse",
	"Sardine,Tortue", -- legacy, must still resolve through Aliases
	"Requin,Baudroie",
}
for _, raw in ipairs(REGION_STRINGS) do
	for id in string.gmatch(raw, "[^,%s]+") do
		check(string.format("%q resolves %s", raw, id), resolve(id) ~= nil)
	end
end

-- 3. Spawner: placeholder path (no assets, no animation ids) -----------
section("Spawner -- placeholder path")
CLEAR_TAGS()
RUN_SPAWNER()
local creatures = Workspace:FindFirstChild("Creatures")
check("Creatures folder created", creatures ~= nil)
local expected = 0
for _, s in ipairs(CreaturesConfig.Species) do expected += (s.FallbackCount or 0) end
check("fallback spawned every FallbackCount", #creatures:GetChildren() == expected, #creatures:GetChildren())
check("no AnimationController while ids are nil", #TRACKS == 0, #TRACKS)

local sample = creatures:GetChildren()[1]
check("model tagged Creature", game:GetService("CollectionService"):HasTag(sample, "Creature"))
check("placeholder flagged not-imported", sample:GetAttribute("ImportedRig") == false)
check("Species attribute set", byId[sample:GetAttribute("Species")] ~= nil)
local root = sample.PrimaryPart
check("PrimaryPart present", root ~= nil)
check("MoveTarget constraint", root and root:FindFirstChild("MoveTarget") ~= nil)
check("FaceTarget constraint", root and root:FindFirstChild("FaceTarget") ~= nil)
check("body cannot collide with the player", root and root.CanCollide == false)
check("body unanchored (physics-driven)", root and root.Anchored == false)

-- Every spawned creature must sit inside its own depth band.
local outOfBand = 0
for _, model in ipairs(creatures:GetChildren()) do
	local s = byId[model:GetAttribute("Species")]
	local depth = DepthUtils.GetDepth(model.PrimaryPart.Position)
	if depth < s.MinDepth - 0.01 or depth > s.MaxDepth + 0.01 then outOfBand += 1 end
end
check("all spawns inside their depth band", outOfBand == 0, outOfBand)

-- 4. Brain: facing, depth clamping, states -----------------------------
section("CreatureBrain")
local shark = byId.RequinRecif
local placeholder = nil
for _, model in ipairs(creatures:GetChildren()) do
	if model:GetAttribute("Species") == "RequinRecif" then placeholder = model break end
end
check("a shark was spawned", placeholder ~= nil)

-- Placeholder body already faces -Z, so no yaw offset may be applied.
local pBrain = CreatureBrain.new(placeholder, shark, placeholder.PrimaryPart.Position, nil)
pBrain.heading = Vector3.new(1, 0, 0)
pBrain.goal = pBrain.position + Vector3.new(1, 0, 0) * 50
pBrain:Update(0.1, nil, math.huge)
local look = placeholder.PrimaryPart:FindFirstChild("FaceTarget").CFrame.LookVector
check("placeholder nose (-Z) follows the heading",
	APPROX(look.X, 1, 0.02) and APPROX(look.Z, 0, 0.02), tostring(look))

-- Imported rig: local -X must end up along the heading.
local rig = Instance.new("Model")
rig.Name = "02_Requin_Recif"
local rigBody = Instance.new("Part", rig)
rigBody.Name = "Requin_Recif_Mesh"
rig.PrimaryPart = rigBody
rig:SetAttribute("ImportedRig", true)
Instance.new("AlignOrientation", rigBody).Name = "FaceTarget"
local rBrain = CreatureBrain.new(rig, shark, Vector3.new(0, -100, 0), nil)
local heading = Vector3.new(0.6, 0, 0.8)
rBrain.heading = heading
rBrain.goal = rBrain.position + heading * 50
rBrain:Update(0.1, nil, math.huge)
local rigCF = rigBody:FindFirstChild("FaceTarget").CFrame
local nose = rigCF:VectorToWorldSpace(Vector3.new(-1, 0, 0))
check("imported rig's -X nose follows the heading",
	APPROX(nose.X, heading.X, 0.02) and APPROX(nose.Z, heading.Z, 0.02), tostring(nose))

-- Depth clamping holds for the deepest and shallowest species.
local jelly = byId.MeduseLumineuse
local jellyModel = Instance.new("Model")
local jellyBody = Instance.new("Part", jellyModel)
jellyModel.PrimaryPart = jellyBody
jellyBody.Position = Vector3.new(0, -400, 0)
Instance.new("AlignPosition", jellyBody).Name = "MoveTarget"
Instance.new("AlignOrientation", jellyBody).Name = "FaceTarget"
local jBrain = CreatureBrain.new(jellyModel, jelly, Vector3.new(0, -400, 0), nil)
local minY, maxY = -math.huge, math.huge
for _ = 1, 400 do
	jBrain:Update(0.2, nil, math.huge)
	minY = math.max(minY, jBrain.position.Y)
end
local escaped = false
for _ = 1, 400 do
	jBrain:Update(0.5, nil, math.huge)
	local depth = DepthUtils.GetDepth(jBrain.position)
	if depth < jelly.MinDepth - 0.01 or depth > jelly.MaxDepth + 0.01 then escaped = true end
end
check("jellyfish never leaves its abyssal band", not escaped)

-- Predator state machine.
local function fakePlayer(position)
	local character = Instance.new("Model")
	character.Name = "TestPlayer"
	local hrp = Instance.new("Part", character)
	hrp.Name = "HumanoidRootPart"
	hrp.Position = position
	local humanoid = Instance.new("Humanoid", character)
	humanoid.Health = 100
	humanoid.TakeDamage = function(self, amount) self.Health -= amount end
	return { Name = "Tester", Character = character }, hrp, humanoid
end

local attacks = 0
local sharkModel = Instance.new("Model")
local sharkBody = Instance.new("Part", sharkModel)
sharkModel.PrimaryPart = sharkBody
sharkBody.Position = Vector3.new(0, -120, 0)
Instance.new("AlignPosition", sharkBody).Name = "MoveTarget"
Instance.new("AlignOrientation", sharkBody).Name = "FaceTarget"
local sBrain = CreatureBrain.new(sharkModel, shark, Vector3.new(0, -120, 0), function() attacks += 1 end)
check("predator starts calm", sBrain.state == "Wander", sBrain.state)

local player, hrp, humanoid = fakePlayer(Vector3.new(20, -120, 0))
sBrain:Update(0.1, hrp, 20)
check("predator chases a nearby diver", sBrain.state == "Chase", sBrain.state)

for _ = 1, 60 do sBrain:Update(0.2, hrp, (sBrain.position - hrp.Position).Magnitude) end
check("predator closes to attack range", attacks > 0, attacks)
check("attack respects its cooldown", attacks <= 60 * 0.2 / shark.AttackCooldown + 2, attacks)

hrp.Position = Vector3.new(0, 20, 0) -- diver surfaces
sBrain:Update(0.1, hrp, 140)
check("predator gives up on a surfaced diver", sBrain.state == "Wander", sBrain.state)

-- Skittish.
local turtle = byId.TortueMarine
local turtleModel = Instance.new("Model")
local turtleBody = Instance.new("Part", turtleModel)
turtleModel.PrimaryPart = turtleBody
turtleBody.Position = Vector3.new(0, -60, 0)
Instance.new("AlignPosition", turtleBody).Name = "MoveTarget"
Instance.new("AlignOrientation", turtleBody).Name = "FaceTarget"
local tBrain = CreatureBrain.new(turtleModel, turtle, Vector3.new(0, -60, 0), nil)
local diverPos = Vector3.new(5, -60, 0)
local _, diverRoot = fakePlayer(diverPos)
local before = (tBrain.position - diverPos).Magnitude
tBrain:Update(0.1, diverRoot, before)
check("skittish flees", tBrain.state == "Flee", tBrain.state)
for _ = 1, 30 do tBrain:Update(0.2, diverRoot, (tBrain.position - diverPos).Magnitude) end
check("skittish actually gains distance", (tBrain.position - diverPos).Magnitude > before, (tBrain.position - diverPos).Magnitude)

-- 5. Spawner: imported assets + published animation ids -----------------
section("Spawner -- imported rigs and animation clips")
CLEAR_TAGS()
TRACKS = {}
WARNINGS = {}

local assets = Instance.new("Folder", ReplicatedStorage)
assets.Name = "Assets"
local creatureAssets = Instance.new("Folder", assets)
creatureAssets.Name = "Creatures"
for _, s in ipairs(CreaturesConfig.Species) do
	local model = Instance.new("Model", creatureAssets)
	model.Name = s.ModelName
	local body = Instance.new("Part", model)
	body.Name = s.Id .. "_Mesh"
	body.Size = s.Size
	model.PrimaryPart = body
	local fin = Instance.new("Part", model) -- a second rig part, like a real import
	fin.Name = "Bone_01"
	-- Pretend the clips have been published.
	s.SlowSwimAnimationId = "rbxassetid://1000" .. tostring(#TRACKS + 1)
	s.FastSwimAnimationId = "rbxassetid://2000" .. tostring(#TRACKS + 1)
end

-- One hand-placed region, naming species by their OLD ids on purpose.
local region = Instance.new("Part", Workspace)
region.Name = "LegacyRegion"
region.Position = Vector3.new(0, -80, 0)
region.CFrame = CFrame.new(region.Position)
region.Size = Vector3.new(60, 30, 60)
region:SetAttribute("RegionKind", "Creature")
region:SetAttribute("RegionCount", 8)
region:SetAttribute("RegionSpecies", "Sardine,Tortue")
game:GetService("CollectionService"):AddTag(region, "SpawnRegion")

-- A second, tight region of turtles only, so the flee/animation assertions
-- below do not depend on a weighted roll going a particular way.
local turtleRegion = Instance.new("Part", Workspace)
turtleRegion.Name = "TurtleRegion"
turtleRegion.Position = Vector3.new(200, -80, 0)
turtleRegion.CFrame = CFrame.new(turtleRegion.Position)
turtleRegion.Size = Vector3.new(10, 10, 10)
turtleRegion:SetAttribute("RegionKind", "Creature")
turtleRegion:SetAttribute("RegionCount", 4)
turtleRegion:SetAttribute("RegionSpecies", "Tortue")
game:GetService("CollectionService"):AddTag(turtleRegion, "SpawnRegion")

RUN_SPAWNER()
creatures = Workspace:FindFirstChild("Creatures")
check("region counts honoured (no fallback ring)", #creatures:GetChildren() == 12, #creatures:GetChildren())

local spawnedIds = {}
for _, model in ipairs(creatures:GetChildren()) do spawnedIds[model:GetAttribute("Species")] = true end
check("legacy 'Sardine' spawned PoissonRecif or TortueMarine",
	(spawnedIds.PoissonRecif or spawnedIds.TortueMarine) and not spawnedIds.RequinRecif)
check("no 'unknown species' warning for legacy ids", #WARNINGS == 0, WARNINGS[1])

local imported = creatures:GetChildren()[1]
check("imported rig flagged", imported:GetAttribute("ImportedRig") == true)
check("rig cloned, not replaced by a placeholder", imported:FindFirstChild("Bone_01") ~= nil)
local controller = imported:FindFirstChild("CreatureAnimationController")
check("AnimationController added (not a Humanoid)", controller ~= nil)
check("no Humanoid on a non-humanoid animal", imported:FindFirstChildOfClass("Humanoid") == nil)
check("Animator under the controller", controller and controller:FindFirstChildOfClass("Animator") ~= nil)
check("two clips loaded per creature", #TRACKS == 12 * 2, #TRACKS)

local playing, loopedAll = 0, true
for _, t in ipairs(TRACKS) do
	if t.IsPlaying then playing += 1 end
	if not t.Looped then loopedAll = false end
end
check("all swim clips loop", loopedAll)
check("exactly one clip plays per creature at rest", playing == 12, playing)
local slowPlaying = 0
for _, t in ipairs(TRACKS) do
	if t.IsPlaying and string.find(t._id, "1000") then slowPlaying += 1 end
end
check("wandering creatures play the SLOW clip", slowPlaying == 12, slowPlaying)

-- Drive one heartbeat with a diver right on top of them: skittish species
-- switch to the fast clip.
PLAYERS = {}
local p = fakePlayer(Vector3.new(200, -80, 0)) -- dropped into the turtle region
table.insert(PLAYERS, p)
CLOCK = 100
HEARTBEAT.fn(1)

local fleeing, fastPlaying = 0, 0
for _, model in ipairs(creatures:GetChildren()) do
	if model:GetAttribute("Species") == "TortueMarine"
		and (model.PrimaryPart.Position - Vector3.new(200, -80, 0)).Magnitude < byId.TortueMarine.FleeDistance then
		fleeing += 1
	end
end
for _, t in ipairs(TRACKS) do
	if t.IsPlaying and string.find(t._id, "2000") then fastPlaying += 1 end
end
check("all 4 turtles are inside flee range", fleeing == 4, fleeing)
check("fleeing creatures switch to the FAST clip", fastPlaying == fleeing, fastPlaying)
local stillOne = 0
for _, t in ipairs(TRACKS) do if t.IsPlaying then stillOne += 1 end end
check("still exactly one clip per creature after switching", stillOne == 12, stillOne)

-- Published ids but no imported rig: a placeholder is rigid geometry, so
-- an Animator on it would deform nothing.
section("Spawner -- published ids, no imported model")
CLEAR_TAGS()
TRACKS = {}
assets:Destroy()
RUN_SPAWNER()
check("no Animator on a placeholder even with published ids", #TRACKS == 0, #TRACKS)
local ph = Workspace:FindFirstChild("Creatures"):GetChildren()[1]
check("placeholder has no AnimationController", ph:FindFirstChild("CreatureAnimationController") == nil)

-- A bad/unpublished id must not take the spawner down.
section("Spawner -- unpublished / broken animation id")
CLEAR_TAGS()
TRACKS = {}
WARNINGS = {}
region:Destroy()
turtleRegion:Destroy()
for _, s in ipairs(CreaturesConfig.Species) do
	s.SlowSwimAnimationId = nil
	s.FastSwimAnimationId = nil
end
local ok = pcall(RUN_SPAWNER)
check("spawner survives with every animation id back to nil", ok)
check("no AnimationController when ids are nil again", #TRACKS == 0, #TRACKS)

print(string.format("\n%d checks, %d failures", checks, failures))
if failures > 0 then
	error(string.format("%d creature checks failed", failures), 0)
end
print("ALL CREATURE CHECKS PASSED")
