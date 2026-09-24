-- UI suite: runs the three screen-UI LocalScripts (GameplayHUD,
-- ZoneAnnouncer, DeathScreen) against a fake local player and drives them
-- through a dive: depth and oxygen changes, loot events, a current, a
-- death and a respawn. Checks that nothing errors and that the widgets show
-- what the state says.
local failures, checks = 0, 0
local function check(label, ok, detail)
	checks += 1
	if not ok then
		failures += 1
		print(string.format("FAIL  %s%s", label, detail and ("  -- " .. tostring(detail)) or ""))
	end
end
local function section(name) print("\n== " .. name .. " ==") end

-- Client-side fakes -----------------------------------------------------------------

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local TWEENS = {}
TweenService.Create = function(_, instance, info, goal)
	assert(typeof(instance) == "Instance", "TweenService:Create on a non-instance")
	local tween = { Completed = nil }
	local completed = Instance.new("BindableEvent")
	tween.Completed = completed.Event
	tween.Play = function()
		-- Tweens land instantly: the test cares about end states.
		for k, v in pairs(goal) do instance[k] = v end
		-- Completed fires on a later frame, like in Roblox.
		table.insert(TWEENS, completed)
	end
	tween.Cancel = function() end
	return tween
end

-- Layout isn't simulated: every GUI object reports a fixed box.
local realNew = Instance.new
Instance.new = function(class, parent)
	local o = realNew(class, parent)
	o.AbsolutePosition = Vector2.new(0, 0)
	o.AbsoluteSize = Vector2.new(100, 400)
	return o
end

local RENDER = {}
RunService.RenderStepped = { Connect = function(_, fn) table.insert(RENDER, fn); return { Disconnect = function() end } end }
RunService.IsClient = function() return true end
local function frame(dt)
	local done = TWEENS
	TWEENS = {}
	for _, completed in ipairs(done) do completed.Event:Fire(Enum.PlaybackState.Completed) end
	for _, fn in ipairs(RENDER) do fn(dt or 1 / 60) end
	if HEARTBEAT.fn then HEARTBEAT.fn(dt or 1 / 60) end
end

local camera = Instance.new("Camera")
camera.ViewportSize = Vector2.new(1920, 1080)
camera.CFrame = CFrame.new(Vector3.new(0, 20, 0))
Workspace.CurrentCamera = camera
Players.RespawnTime = 5

local player = Instance.new("Player")
player.Name = "Diver"
player.CharacterAdded = Instance.new("BindableEvent").Event
local characterAdded = player.CharacterAdded
local playerGui = Instance.new("PlayerGui")
playerGui.Name = "PlayerGui"
playerGui.Parent = player
Players.LocalPlayer = player

local function value(class, name, v, parent)
	local o = Instance.new(class)
	o.Name = name
	o.Value = v
	o.Parent = parent or player
	return o
end
local depth = value("NumberValue", "Depth", 0)
local oxygen = value("NumberValue", "Oxygen", 60)
value("NumberValue", "MaxOxygen", 60)
value("NumberValue", "OxygenDrainPerSecond", 1)
local carried = value("IntValue", "CarriedValue", 0)
local carriedCount = value("IntValue", "CarriedCount", 0)
local leaderstats = Instance.new("Folder")
leaderstats.Name = "leaderstats"
leaderstats.Parent = player
local coins = value("IntValue", "Pièces", 0, leaderstats)
local lootEvent = Instance.new("RemoteEvent")
lootEvent.Name = "LootEvent"
lootEvent.Parent = ReplicatedStorage

-- Every Value's .Changed fires when .Value is set, like in Roblox.
local function set(object, v)
	object.Value = v
	object.Changed:Fire(v)
end

local function newCharacter(y)
	local character = Instance.new("Model")
	character.Name = "Diver"
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Position = Vector3.new(0, y, 0)
	root.Parent = character
	local humanoid = Instance.new("Humanoid")
	humanoid.Health = 100
	humanoid.Parent = character
	player.Character = character
	return character, root, humanoid
end
local character, root, humanoid = newCharacter(5)

local function findText(gui, pattern)
	for _, d in ipairs(gui:GetDescendants()) do
		if type(d.Text) == "string" and d.Text:find(pattern) then return d end
	end
	return nil
end

-- Run the scripts -----------------------------------------------------------------------

section("Boot")
local ok, err = pcall(RUN_SCRIPT, "StarterPlayer", "StarterPlayerScripts", "GameplayHUD")
check("GameplayHUD starts", ok, err)
ok, err = pcall(RUN_SCRIPT, "StarterPlayer", "StarterPlayerScripts", "ZoneAnnouncer")
check("ZoneAnnouncer starts", ok, err)
ok, err = pcall(RUN_SCRIPT, "StarterPlayer", "StarterPlayerScripts", "DeathScreen")
check("DeathScreen starts", ok, err)
local hud = playerGui:FindFirstChild("GameplayHUD")
local announcer = playerGui:FindFirstChild("ZoneAnnouncer")
local death = playerGui:FindFirstChild("DeathScreen")
check("three ScreenGuis mounted", hud and announcer and death)
for _, gui in ipairs({ hud, announcer, death }) do
	if gui then
		check(gui.Name .. ": fills the screen under the top bar", gui.IgnoreGuiInset == true)
		check(gui.Name .. ": scales with the viewport", gui:FindFirstChildOfClass("UIScale") ~= nil)
	end
end

section("Dive")
ok, err = pcall(function()
	for _ = 1, 30 do frame() end
	root.Position = Vector3.new(0, -140, 0)
	camera.CFrame = CFrame.new(Vector3.new(0, -135, 0))
	set(depth, 140)
	set(oxygen, 40)
	for _ = 1, 240 do frame() end
end)
check("HUD runs through a dive", ok, err)
check("depth readout shows 140 m", findText(hud, "^140 m") ~= nil, findText(hud, " m$") and findText(hud, " m$").Text)
check("zone name shown on the gauge", findText(hud, "GROTTES") ~= nil)
local card = announcer:FindFirstChild("ZoneCard")
check("zone banner announced Grottes", card and findText(card, "GROTTES") ~= nil)
check("zone banner eyebrow gives the range", card and findText(card, "ZONE 2") ~= nil)
check("zone banner hides again", card and card.Visible == false)

section("Biome")
ok, err = pcall(function()
	local folder = Instance.new("Folder")
	folder.Name = "Biomes"
	local config = Instance.new("Configuration")
	config:SetAttribute("Shape", "Cylinder")
	config:SetAttribute("DisplayName", "Cimetière de la Sirène")
	config:SetAttribute("Description", "La Sirène Noire et les épaves qui l'ont suivie")
	config:SetAttribute("Color", Color3.fromRGB(255, 196, 110))
	config:SetAttribute("Priority", 4)
	config:SetAttribute("Center", Vector3.new(300, 0, 300))
	config:SetAttribute("Radius", 200)
	config:SetAttribute("MinY", -420)
	config:SetAttribute("MaxY", -200)
	config:SetAttribute("FogEnd", 200)
	config.Parent = folder
	folder.Parent = ReplicatedStorage
	root.Position = Vector3.new(320, -320, 290)
	camera.CFrame = CFrame.new(Vector3.new(320, -315, 290))
	set(depth, 320)
	for _ = 1, 90 do frame() end
end)
check("biome detection survives", ok, err)
check("biome banner names the Cimetière (accents upper-cased)", findText(card, "CIMETIÈRE DE LA SIRÈNE") ~= nil, findText(card, "CIMETI") and findText(card, "CIMETI").Text)
check("biome banner has its description", findText(card, "épaves qui l'ont suivie") ~= nil)
check("biome fog override lets the diver see further", game:GetService("Lighting").FogEnd > 150, game:GetService("Lighting").FogEnd)
check("HUD names the biome under the depth", findText(hud, "^CIMETIÈRE DE LA SIRÈNE$") ~= nil)
check("zone names keep their accents", findText(card, "ÉPAVE") ~= nil)

section("Loot")
ok, err = pcall(function()
	set(carried, 350)
	set(carriedCount, 2)
	lootEvent.OnClientEvent:Fire("Collected", "Coffre doré", 250, "Rare")
	for _ = 1, 60 do frame() end
end)
check("collect toast survives", ok, err)
check("bag chip shows value", findText(hud, "350") ~= nil)
ok, err = pcall(function()
	set(carried, 0)
	set(carriedCount, 0)
	set(coins, 12480)
	lootEvent.OnClientEvent:Fire("Banked", 350, 2, 12480)
	for _ = 1, 300 do frame() end
end)
check("bank toast survives", ok, err)
check("coin counter rolls up to 12 480", findText(hud, "12 480") ~= nil)

section("Low oxygen")
ok, err = pcall(function()
	set(oxygen, 8)
	for _ = 1, 240 do frame() end
end)
check("low-oxygen warning survives", ok, err)
check("surface hint is shown", findText(hud, "REMONTE") and findText(hud, "REMONTE").Visible ~= false)

section("Death")
ok, err = pcall(function()
	player:SetAttribute("LastDeathCause", "Attaqué par : Requin de récif")
	lootEvent.OnClientEvent:Fire("Lost", 420, 3)
	humanoid.Died:Fire()
	for _ = 1, 10 do frame() end
end)
check("death screen survives", ok, err)
check("death screen shown", death.Enabled == true)
check("death cause shown", findText(death, "Requin de récif") ~= nil)
check("deepest point of the dive shown", findText(death, "^320 m") ~= nil)
check("lost loot shown", findText(death, "420") ~= nil)

section("Respawn")
ok, err = pcall(function()
	player:SetAttribute("LastDeathCause", nil)
	character, root, humanoid = newCharacter(5)
	characterAdded:Fire(character)
	set(depth, 0)
	set(oxygen, 60)
	for _ = 1, 30 do frame() end
end)
check("respawn survives", ok, err)
check("death screen hidden after respawn", death.Enabled == false)
ok, err = pcall(function()
	humanoid.Died:Fire()
end)
check("second death survives", ok, err)
check("fallback cause on a death without one", findText(death, "pardonne") ~= nil)

print(string.format("\n%d checks, %d failures", checks, failures))
if failures > 0 then
	error(string.format("%d UI checks failed", failures), 0)
end
print("ALL UI CHECKS PASSED")
