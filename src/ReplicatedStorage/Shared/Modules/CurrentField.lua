-- Client-side bridge between the current computation
-- (UnderwaterCurrents.client.lua, the only writer) and everything that
-- reacts to currents: SwimController folds GetVelocity() into its own
-- velocity; ambience/effects scripts bias their particles by it; and any
-- future system (sound, camera shake, HUD, VFX made separately) hooks the
-- Entered/Exited/Changed signals below instead of re-deriving zone
-- membership itself. All of this runs on the same client -- it's a shared
-- Lua value, not a replication or networking mechanism.
--
-- "Dominant" current = the single zone contributing the most push right
-- now. Entered fires when that goes from nil to a zone, Exited when it goes
-- back to nil, Changed when it switches directly from one zone to another.
-- Each signal passes the current's instance (a Part, or a Model for Path
-- currents), so listeners can read any Attribute on it (CurrentTier,
-- CurrentDisplayName, CurrentMaxSpeed, CurrentSoundId, or custom ones
-- added in Studio) to decide what to do.

local CurrentField = {}

local velocity = Vector3.new()
local dominantCurrent: Instance? = nil
local influence = 0

local enteredEvent = Instance.new("BindableEvent")
local exitedEvent = Instance.new("BindableEvent")
local changedEvent = Instance.new("BindableEvent")

CurrentField.Entered = enteredEvent.Event
CurrentField.Exited = exitedEvent.Event
CurrentField.Changed = changedEvent.Event

-- Tides: a current with a CurrentTidePeriod (seconds) reverses with the
-- tide, on a clock shared by every client (the server's time), so all
-- divers see the same water. Returns a signed factor: its sign is the
-- flow's direction (1 = as built, -1 = reversed), its size how strong the
-- flow is right now (0 at slack water, 1 at full flow). 1 for a current
-- without tides.
local function sharedTime(): number
	local ok, now = pcall(function()
		return workspace:GetServerTimeNow()
	end)
	return ok and now or os.clock()
end

function CurrentField.TideFactor(instance: Instance): number
	local period = instance:GetAttribute("CurrentTidePeriod")
	if type(period) ~= "number" or period <= 0 then
		return 1
	end
	local phase = instance:GetAttribute("CurrentTidePhase") or 0
	local wave = math.sin(sharedTime() / period * math.pi * 2 + phase)
	local strength = math.min(1, math.abs(wave) * 1.6)
	return wave >= 0 and strength or -strength
end

-- "Flot" (flowing in, as built) or "Jusant" (flowing out), for the HUD.
function CurrentField.TideLabel(instance: Instance): string?
	local period = instance:GetAttribute("CurrentTidePeriod")
	if type(period) ~= "number" or period <= 0 then
		return nil
	end
	local factor = CurrentField.TideFactor(instance)
	if math.abs(factor) < 0.2 then
		return "étale"
	end
	return factor > 0 and "flot" or "jusant"
end

function CurrentField.SetVelocity(newVelocity: Vector3)
	velocity = newVelocity
end

function CurrentField.GetVelocity(): Vector3
	return velocity
end

-- influence: 0-1, how deep inside the dominant current the player is (its
-- smoothstep falloff), for effects that want to fade in with it.
function CurrentField.SetDominantCurrent(current: Instance?, newInfluence: number)
	influence = newInfluence
	if current == dominantCurrent then
		return
	end

	local previous = dominantCurrent
	dominantCurrent = current

	if previous and current then
		changedEvent:Fire(current, previous)
	elseif current then
		enteredEvent:Fire(current)
	else
		exitedEvent:Fire(previous)
	end
end

function CurrentField.GetDominantCurrent(): Instance?
	return dominantCurrent
end

function CurrentField.GetInfluence(): number
	return influence
end

return CurrentField
