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
-- Each signal passes the current's marker Part, so listeners can read any
-- Attribute on it (CurrentTier, CurrentDisplayName, CurrentFlowSpeed, or
-- custom ones added in Studio) to decide what to do.

local CurrentField = {}

local velocity = Vector3.new()
local dominantCurrent: BasePart? = nil
local influence = 0

local enteredEvent = Instance.new("BindableEvent")
local exitedEvent = Instance.new("BindableEvent")
local changedEvent = Instance.new("BindableEvent")

CurrentField.Entered = enteredEvent.Event
CurrentField.Exited = exitedEvent.Event
CurrentField.Changed = changedEvent.Event

function CurrentField.SetVelocity(newVelocity: Vector3)
	velocity = newVelocity
end

function CurrentField.GetVelocity(): Vector3
	return velocity
end

-- influence: 0-1, how deep inside the dominant current the player is (its
-- smoothstep falloff), for effects that want to fade in with it.
function CurrentField.SetDominantCurrent(current: BasePart?, newInfluence: number)
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

function CurrentField.GetDominantCurrent(): BasePart?
	return dominantCurrent
end

function CurrentField.GetInfluence(): number
	return influence
end

return CurrentField
