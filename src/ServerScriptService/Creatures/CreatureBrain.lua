-- Per-creature behaviour: a small state machine (Wander / Flee / Chase)
-- selected by the species' Behavior field in CreaturesConfig. The brain
-- simulates a kinematic "logical" position and heading itself, then hands
-- them to the AlignPosition/AlignOrientation constraints on the model's
-- PrimaryPart (built by CreatureSpawner); the physics engine smooths and
-- replicates the actual body motion, so the brain can tick at a low rate
-- (see CreatureSpawner's UPDATE_INTERVAL and LOD) without visible stutter.
--
-- Two touches of life on top of the state machine:
--   * Schools (species.SchoolSize > 1): members share a School whose
--     center wanders like a single creature; each member swims to its own
--     slowly drifting slot around that center, so the group moves as one
--     loose shoal. A member that flees breaks formation and rejoins after.
--   * Bobbing (species.Bob = { Amplitude, Speed }): a vertical sine added
--     to the body target only (not the logical position) -- a jellyfish's
--     pulse-and-drift instead of a straight glide.
--
-- Deliberately simple: no pathfinding or obstacle avoidance. Bodies are
-- CanCollide = false so a creature can never trap or shove a player; the
-- spawner's RegionWanderRadius keeps cave dwellers inside their chamber.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DepthUtils = require(ReplicatedStorage.Shared.Modules.DepthUtils)

local CreatureBrain = {}
CreatureBrain.__index = CreatureBrain

local GOAL_REACHED_DISTANCE = 3
local FLEE_STEP = 30
local WANDER_RETARGET_MIN = 4
local WANDER_RETARGET_MAX = 9
local SCHOOL_SPACING = 3.2 -- studs between neighbours' slots, per member size unit

local function randomUnitVector(): Vector3
	local v = Vector3.new(math.random() - 0.5, (math.random() - 0.5) * 0.5, math.random() - 0.5)
	if v.Magnitude < 0.001 then
		return Vector3.new(1, 0, 0)
	end
	return v.Unit
end

-- Depth band, and -- when the creature lives in open water (not in a
-- cave) -- at least GROUND_CLEARANCE above the seabed, so nothing swims
-- through the seamount.
-- (The band's shallow limit still wins over shallow water, e.g. a lagoon
-- only a few studs deep.)
local GROUND_CLEARANCE = 2

local function clampToBand(species, position: Vector3, ground: ((number, number) -> number)?): Vector3
	local minY = DepthUtils.SURFACE_Y - species.MaxDepth
	local maxY = DepthUtils.SURFACE_Y - species.MinDepth
	local y = math.clamp(position.Y, minY, maxY)
	if ground then
		y = math.min(math.max(y, ground(position.X, position.Z) + GROUND_CLEARANCE), maxY)
	end
	return Vector3.new(position.X, y, position.Z)
end

-- The delivered animal models face -X in their own space, while Roblox
-- steers by -Z (CFrame.lookAt's LookVector), so orienting them straight
-- at the heading would have every animal swimming sideways. Rotating the
-- model -90 degrees about Y after the look maps its local -X onto -Z:
-- Ry(-90) * (-1,0,0) = (0,0,-1). Per species, since the pack only
-- confirms the -X convention for the fish and the shark.
--
-- Only for an imported rig: CreatureSpawner's placeholder body is built
-- facing -Z already, so applying the offset to it would turn the fallback
-- creatures sideways. The spawner flags which one this is.
local function facingOffset(model: Model, species): CFrame
	local degrees = model:GetAttribute("ImportedRig") and (species.ModelYawOffsetDegrees or 0) or 0
	if degrees == 0 then
		return CFrame.identity
	end
	return CFrame.Angles(0, math.rad(degrees), 0)
end

-- School ------------------------------------------------------------------------------

local School = {}
School.__index = School

function CreatureBrain.newSchool(species, home: Vector3, wanderRadius: number?, ground: ((number, number) -> number)?)
	local self = setmetatable({
		species = species,
		ground = ground,
		home = home,
		wanderRadius = wanderRadius or species.WanderRadius,
		center = home,
		goal = home,
		heading = Vector3.new(0, 0, -1),
		retargetTimer = 0,
		members = 0,
		time = 0,
	}, School)
	return self
end

function School:Update(dt: number)
	self.time += dt
	self.retargetTimer -= dt
	if self.retargetTimer <= 0 or (self.goal - self.center).Magnitude < GOAL_REACHED_DISTANCE then
		local offset = randomUnitVector() * (self.wanderRadius * (0.3 + math.random() * 0.7))
		self.goal = clampToBand(self.species, self.home + offset, self.ground)
		self.retargetTimer = WANDER_RETARGET_MIN + math.random() * (WANDER_RETARGET_MAX - WANDER_RETARGET_MIN)
	end
	local toGoal = self.goal - self.center
	if toGoal.Magnitude > 0.01 then
		self.heading = toGoal.Unit
		self.center += self.heading * math.min(self.species.Speed * 0.85 * dt, toGoal.Magnitude)
	end
end

-- Each member's slot: a fixed spot on a loose ellipsoid around the center,
-- flattened vertically and slowly rotating, so the shoal breathes.
function School:SlotFor(index: number): Vector3
	local time = self.time
	local size = math.max(self.species.Size.X, self.species.Size.Z)
	local ring = math.floor((index - 1) / 6) + 1
	local angle = (index * 2.39996) + time * 0.15 -- golden-angle spread
	local radius = ring * size * SCHOOL_SPACING * 0.5
	return self.center + Vector3.new(math.cos(angle) * radius, math.sin(index * 1.7 + time * 0.4) * size * 0.6, math.sin(angle) * radius)
end

-- Brain -------------------------------------------------------------------------------

-- options: { school = School?, wanderRadius = number?, ground = (x, z) -> y? }
function CreatureBrain.new(model: Model, species, home: Vector3, onAttack, options)
	options = options or {}
	local root = model.PrimaryPart
	local self = setmetatable({
		model = model,
		species = species,
		home = home,
		root = root,
		facingOffset = facingOffset(model, species),
		alignPosition = root:FindFirstChild("MoveTarget"),
		alignOrientation = root:FindFirstChild("FaceTarget"),
		position = root.Position,
		heading = Vector3.new(0, 0, -1),
		state = "Wander",
		goal = nil,
		retargetTimer = 0,
		attackCooldown = 0,
		onAttack = onAttack,
		wanderRadius = options.wanderRadius or species.WanderRadius,
		ground = options.ground,
		school = options.school,
		schoolIndex = 0,
		time = math.random() * 100,
	}, CreatureBrain)
	if self.school then
		self.school.members += 1
		self.schoolIndex = self.school.members
	end
	self:pickWanderGoal()
	return self
end

-- Keeps any goal inside the species' depth band so a creature never
-- wanders up to the surface or into the seafloor.
function CreatureBrain:clampToDepthBand(position: Vector3): Vector3
	return clampToBand(self.species, position, self.ground)
end

function CreatureBrain:pickWanderGoal()
	if self.school then
		self.goal = self:clampToDepthBand(self.school:SlotFor(self.schoolIndex))
	else
		local offset = randomUnitVector() * (self.wanderRadius * (0.3 + math.random() * 0.7))
		self.goal = self:clampToDepthBand(self.home + offset)
	end
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

	if self.school then
		-- Formation: always heading for the (moving) slot; a member that has
		-- fallen behind swims faster to catch up with the shoal.
		self.goal = self:clampToDepthBand(self.school:SlotFor(self.schoolIndex))
		local lag = (self.goal - self.position).Magnitude
		return species.Speed * math.clamp(0.6 + lag / 12, 0.6, 1.8)
	end

	self.retargetTimer -= dt
	if self.retargetTimer <= 0 or (self.goal - self.position).Magnitude < GOAL_REACHED_DISTANCE then
		self:pickWanderGoal()
	end
	return species.Speed
end

function CreatureBrain:Update(dt: number, playerRoot: BasePart?, playerDistance: number)
	self.time += dt
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

	local bob = self.species.Bob
	local bodyPosition = self.position
	if bob then
		bodyPosition += Vector3.new(0, math.sin(self.time * bob.Speed) * bob.Amplitude, 0)
	end
	if self.alignPosition then
		self.alignPosition.Position = bodyPosition
	end
	if self.alignOrientation then
		-- A bobbing drifter stays upright rather than nosing up and down.
		local lookAt = bob and Vector3.new(self.heading.X, 0, self.heading.Z) or self.heading
		if lookAt.Magnitude < 0.01 then
			lookAt = Vector3.new(0, 0, -1)
		end
		self.alignOrientation.CFrame = CFrame.lookAt(bodyPosition, bodyPosition + lookAt) * self.facingOffset
	end
end

return CreatureBrain
