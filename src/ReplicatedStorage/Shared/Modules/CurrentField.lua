-- Tiny shared accessor decoupling the current-influence calculation
-- (UnderwaterCurrents.client.lua, the writer) from the swim controller that
-- applies it (SwimController.client.lua, the reader), so neither needs to
-- know anything about the other's internals -- SwimController stays the
-- sole owner of the character's velocity/rotation, this just hands it one
-- extra number to add in. Both scripts run on the same client: this is a
-- shared Lua value, not a replication or networking mechanism.

local CurrentField = {}

local velocity = Vector3.new()

function CurrentField.SetVelocity(newVelocity: Vector3)
	velocity = newVelocity
end

function CurrentField.GetVelocity(): Vector3
	return velocity
end

return CurrentField
