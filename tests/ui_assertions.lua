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
	if class == "TextButton" or class == "ImageButton" then
		local clicked = realNew("BindableEvent")
		o.Activated = clicked.Event
	end
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

section("Shop")
local shopRequests = {}
local shopOwned = { "TankStarter", "SuitNone", "FinsNone", "LampNone" }
ok, err = pcall(function()
	local ProximityPromptService = game:GetService("ProximityPromptService")
	ProximityPromptService.PromptTriggered = Instance.new("BindableEvent").Event
	local remote = Instance.new("RemoteFunction")
	remote.Name = "EquipmentRequest"
	remote.InvokeServer = function(_, action, id)
		table.insert(shopRequests, action .. ":" .. id)
		if action == "Buy" then
			table.insert(shopOwned, id)
			player:SetAttribute("OwnedEquipment", table.concat(shopOwned, ","))
			player:SetAttribute("Equipped_Tank", id)
			set(coins, coins.Value - 150)
			return { ok = true, message = "Bouteille alu 12 L achetée et équipée" }
		end
		return { ok = false, message = "?" }
	end
	remote.Parent = ReplicatedStorage
	player:SetAttribute("Equipped_Tank", "TankStarter")
	RUN_SCRIPT("StarterPlayer", "StarterPlayerScripts", "DiveShop")
end)
check("DiveShop starts", ok, err)
local shop = playerGui:FindFirstChild("DiveShop")
check("shop closed until the counter is used", shop and shop.Enabled == false)
ok, err = pcall(function()
	local counterPart = Instance.new("Part")
	counterPart.Position = root.Position
	local prompt = Instance.new("ProximityPrompt")
	prompt:SetAttribute("OpensShop", true)
	prompt.Parent = counterPart
	game:GetService("ProximityPromptService").PromptTriggered:Fire(prompt)
	for _ = 1, 5 do frame() end
end)
check("counter prompt opens the shop", ok and shop.Enabled == true, err)
local items = shop and shop.Panel:FindFirstChild("Items")
local cards = 0
for _, c in ipairs(items and items:GetChildren() or {}) do
	if c:IsA("Frame") then cards += 1 end
end
check("tank tab lists the five tanks", cards == 5, cards)
check("equipped tank shows ÉQUIPÉ", items.TankStarter.Action.Text == "ÉQUIPÉ ✓", items.TankStarter.Action.Text)
check("tank for sale shows its price", items.Tank15.Action.Text == "600 ◉", items.Tank15.Action.Text)
check("coins shown in the shop", findText(shop, "◉ 12 480") ~= nil)
ok, err = pcall(function()
	items.Tank12.Action.Activated:Fire()
end)
check("buying goes to the server", ok and shopRequests[1] == "Buy:Tank12", err or shopRequests[1])
check("server's answer shown", findText(shop, "achetée et équipée") ~= nil)
ok, err = pcall(function()
	shop.Panel.Tabs.Suit.Activated:Fire()
end)
local suitCards = 0
for _, c in ipairs(shop.Panel.Items:GetChildren()) do
	if c:IsA("Frame") then suitCards += 1 end
end
check("suits tab lists the five suits", ok and suitCards == 5, err or suitCards)
check("suit card shows its saving", findText(shop, "Consommation  −20") ~= nil)
ok, err = pcall(function()
	shop.Panel.Close.Activated:Fire()
end)
check("✕ closes the shop", ok and shop.Enabled == false, err)

section("Island critters")
local CollectionService = game:GetService("CollectionService")
local function critter(tag, attributes, at)
	local model = Instance.new("Model")
	local body = Instance.new("Part")
	body.Name = "Body"
	body.CFrame = CFrame.new(at)
	body.Parent = model
	for _, side in ipairs({ "WingLeft", "WingRight" }) do
		local wing = Instance.new("Part")
		wing.Name = side
		wing.CFrame = CFrame.new(at + Vector3.new(side == "WingLeft" and -1 or 1, 0, 0))
		wing.Parent = model
	end
	model.PrimaryPart = body
	for key, value in pairs(attributes) do model:SetAttribute(key, value) end
	model.Parent = Workspace
	CollectionService:AddTag(model, tag)
	return model, body
end
local crabModel, crabBody = critter("Crab", { Home = Vector3.new(60, 4.3, 0), Range = 5, Speed = 4 }, Vector3.new(60, 4.3, 0))
local gullModel, gullBody = critter("Seagull", { Center = Vector3.zero, Radius = 50, Height = 35, Speed = 0.3, Phase = 0 }, Vector3.new(0, 40, 0))
local dolphinModel, dolphinBody = critter("Dolphin", { Center = Vector3.zero, Radius = 150, Speed = 0.1, Phase = 0 }, Vector3.new(150, -3, 0))
ok, err = pcall(function()
	camera.CFrame = CFrame.new(Vector3.new(0, 10, 0))
	root.Position = Vector3.new(0, 5, 0)
	RUN_SCRIPT("StarterPlayer", "StarterPlayerScripts", "IslandCritters")
	for _ = 1, 120 do frame() end
end)
check("IslandCritters runs", ok, err)
check("crab walks around its home", (crabBody.Position - Vector3.new(60, 4.3, 0)).Magnitude > 0.2 and (crabBody.Position - Vector3.new(60, 4.3, 0)).Magnitude < 7, crabBody.Position)
check("seagull circles high above", gullBody.Position.Y > 30 and math.abs(Vector3.new(gullBody.Position.X, 0, gullBody.Position.Z).Magnitude - 50) < 1, gullBody.Position)
check("seagull wings follow the body", (gullModel.WingLeft.Position - gullBody.Position).Magnitude < 1.6)
check("dolphin swims round the lagoon", math.abs(Vector3.new(dolphinBody.Position.X, 0, dolphinBody.Position.Z).Magnitude - 150) < 1, dolphinBody.Position)

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
