-- Per-creature behaviour: a small state machine (Wander / Flee / Chase)
-- selected by the species' Behavior field in CreaturesConfig. The brain
-- simulates a kinematic "logical" position and heading itself, then hands
-- them to the AlignPosition/AlignOrientation constraints on the model's
-- PrimaryPart (built by CreatureSpawner); the physics engine smooths and
-- replicates the actual body motion, so the brain can tick at a low rate
-- (see CreatureSpawner's UPDATE_INTERVAL and LOD) without visible stutter.
--
-- Deliberately simple: no pathfinding or obstacle avoidance yet. Bodies are
-- CanCollide = false so a creature can never trap or shove a player; they
-- can currently pass through terrain, which is acceptable for open water
-- and will need a raycast-based avoidance step once caves/wrecks exist.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DepthUtils = require(ReplicatedStorage.Shared.Modules.DepthUtils)

local CreatureBrain = {}
CreatureBrain.__index = CreatureBrain

local GOAL_REACHED_DISTANCE = 3
local FLEE_STEP = 30
local WANDER_RETARGET_MIN = 4
local WANDER_RETARGET_MAX = 9

local function randomUnitVector(): Vector3
	local v = Vector3.new(math.random() - 0.5, (math.random() - 0.5) * 0.5, math.random() - 0.5)
	if v.Magnitude < 0.001 then
		return Vector3.new(1, 0, 0)
	end
	return v.Unit
end

function CreatureBrain.new(model: Model, species, home: Vector3, onAttack)
	local root = model.PrimaryPart
	local self = setmetatable({
		model = model,
		species = species,
		home = home,
		root = root,
		alignPosition = root:FindFirstChild("MoveTarget"),
		alignOrientation = root:FindFirstChild("FaceTarget"),
		position = root.Position,
		heading = Vector3.new(0, 0, -1),
		state = "Wander",
		goal = nil,
		retargetTimer = 0,
		attackCooldown = 0,
		onAttack = onAttack,
	}, CreatureBrain)
	self:pickWanderGoal()
	return self
end

-- Keeps any goal inside the species' depth band so a creature never
-- wanders up to the surface or into the seafloor.
function CreatureBrain:clampToDepthBand(position: Vector3): Vector3
	local minY = DepthUtils.SURFACE_Y - self.species.MaxDepth
	local maxY = DepthUtils.SURFACE_Y - self.species.MinDepth
	return Vector3.new(position.X, math.clamp(position.Y, minY, maxY), position.Z)
end

function CreatureBrain:pickWanderGoal()
	local offset = randomUnitVector() * (self.species.WanderRadius * (0.3 + math.random() * 0.7))
	self.goal = self:clampToDepthBand(self.home + offset)
	self.retargetTimer = WANDER_RETARGET_MIN + math.random() * (WANDER_RETARGET_MAX - WANDER_RETARGET_MIN)
end

function CreatureBrain:decide(dt: number, playerRoot: BasePart?, playerDistance: number)
	local species = self.species
	local behavior = species.Behavior

	if behavior == "Skittish" and playerRoot then
		if self.state ~= "Flee" and playerDistance < species.FleeDistance then
			self.state = "Flee"
		elseif self.state == "Flee" and playerDistance > species.FleeDistance * 2.5 then
			self.state = "Wander"
			self:pickWanderGoal()
		end
		if self.state == "Flee" then
			local away = self.position - playerRoot.Position
			away = Vector3.new(away.X, away.Y * 0.3, away.Z)
			if away.Magnitude > 0.01 then
				self.goal = self:clampToDepthBand(self.position + away.Unit * FLEE_STEP)
			end
			return species.FleeSpeed or species.Speed * 2
		end
	elseif behavior == "Predator" and playerRoot then
		local playerUnderwater = DepthUtils.GetDepth(playerRoot.Position) > 0
		if self.state ~= "Chase" and playerUnderwater and playerDistance < species.ChaseDistance then
			self.state = "Chase"
		elseif self.state == "Chase" and (not playerUnderwater or playerDistance > species.LoseDistance) then
			self.state = "Wander"
			self:pickWanderGoal()
		end
		if self.state == "Chase" then
			self.goal = playerRoot.Position
			self.attackCooldown = math.max(0, self.attackCooldown - dt)
			if playerDistance <= species.AttackRange and self.attackCooldown <= 0 then
				self.attackCooldown = species.AttackCooldown
				if self.onAttack then
					self.onAttack(self, playerRoot)
				end
			end
			return species.ChaseSpeed or species.Speed * 2
		end
	elseif self.state ~= "Wander" then
		self.state = "Wander"
		self:pickWanderGoal()
	end

	self.retargetTimer -= dt
	if self.retargetTimer <= 0 or (self.goal - self.position).Magnitude < GOAL_REACHED_DISTANCE then
		self:pickWanderGoal()
	end
	return species.Speed
end

function CreatureBrain:Update(dt: number, playerRoot: BasePart?, playerDistance: number)
	local speed = self:decide(dt, playerRoot, playerDistance)

	local toGoal = self.goal - self.position
	if toGoal.Magnitude > 0.01 then
		local desired = toGoal.Unit
		local alpha = 1 - math.exp(-self.species.TurnResponsiveness * dt)
		local blended = self.heading + (desired - self.heading) * alpha
		if blended.Magnitude > 0.01 then
			self.heading = blended.Unit
		end
	end

	-- Chase closes in on the goal without overshooting through the player.
	local step = math.min(speed * dt, math.max(0, toGoal.Magnitude - (self.state == "Chase" and 2 or 0)))
	self.position = self:clampToDepthBand(self.position + self.heading * step)

	if self.alignPosition then
		self.alignPosition.Position = self.position
	end
	if self.alignOrientation then
		self.alignOrientation.CFrame = CFrame.lookAt(self.position, self.position + self.heading)
	end
end

return CreatureBrain
