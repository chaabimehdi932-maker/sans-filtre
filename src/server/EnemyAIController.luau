--[[
	EnemyAIController
	Server-side brain for every Red squad, evaluated every AI.DecisionInterval (not per frame).

	Squad state machine:  Idle → Advancing → Engaging → Routing → Regrouping
	  • Routing is automatic (morale hits 0, handled by SquadService).
	  • Regrouping: morale under `retreatThreshold` → fall back to friends, return at `regroupRecover`.

	Tactics (kept readable rather than perfect):
	  • infantry heads for objectives, engages what comes into range, sometimes flanks a Line
	  • cavalry hunts artillery and exposed squads, avoids squares, hits and runs to re-charge
	  • artillery stays at long range and prefers packed targets (Square / Column)
	  • routed player squads are not chased: objectives come first
	  • infantry forms Square when enemy cavalry is close, Column for long marches

	Tuning per round comes from GameConfig.getRound(round).ai via setTuning().
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local GameConfig = require(Modules:WaitForChild("GameConfig"))
local MathUtil = require(Modules:WaitForChild("MathUtil"))

local MapService = require(script.Parent:WaitForChild("MapService"))
local SquadService = require(script.Parent:WaitForChild("SquadService"))
local ZoneService = require(script.Parent:WaitForChild("ZoneService"))

local AI = GameConfig.AI

local EnemyAIController = {}

local tuning = { aggression = 0.5, flankPreference = 0.3, retreatThreshold = 0.25, regroupRecover = 0.7 }
local rng = Random.new()

function EnemyAIController.setTuning(newTuning: any)
	tuning = newTuning
end

-- units = { { unitId, name?, statMultiplier?, damageMultiplier? } }
function EnemyAIController.spawnWave(units: { any })
	local spots = MapService.deployPositions("Red", #units, GameConfig.Recruitment.DeploySpacing)
	for i, unit in units do
		SquadService.create({
			unitId = unit.unitId,
			team = "Red",
			position = spots[i].position,
			yaw = spots[i].yaw,
			name = unit.name,
			statMultiplier = unit.statMultiplier,
			damageMultiplier = unit.damageMultiplier,
		})
	end
end

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

local function nearestIn(
	from: Vector3,
	list: { any },
	maxDistance: number,
	scoreFn: ((any, number) -> number)?
): (any, number)
	local best, bestScore, bestDistance = nil, math.huge, math.huge
	for _, other in list do
		local distance = MathUtil.flatDistance(from, other.position)
		if distance <= maxDistance then
			local score = if scoreFn then scoreFn(other, distance) else distance
			if score < bestScore then
				best, bestScore, bestDistance = other, score, distance
			end
		end
	end
	return best, bestDistance
end

local function isExposed(squad: any, allies: { any }): boolean
	for _, other in allies do
		if
			other ~= squad
			and MathUtil.flatDistance(other.position, squad.position) <= AI.ExposedRadius + other.radius
		then
			return false
		end
	end
	return true
end

-- Zones to capture first (not ours / contested), else the nearest one of ours to defend
local function objectiveZone(squad: any): any
	local best, bestScore = nil, math.huge
	for _, zone in ZoneService.getZones() do
		local priority = if zone.owner ~= "Red" or zone.contested then 0 else 1
		local score = MathUtil.flatDistance(squad.position, zone.position) + priority * 100000
		if score < bestScore then
			best, bestScore = zone, score
		end
	end
	return best
end

-- Spread squads around a zone instead of stacking them on its centre
local function zoneSpot(squad: any, zone: any): Vector3
	local angle = squad.id * 2.39996
	local radius = math.min(zone.radius * 0.55, 14)
	return zone.position + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
end

local function goToObjective(squad: any, enemies: { any })
	squad.preferredTarget = nil
	local zone = objectiveZone(squad)
	if zone then
		SquadService.moveTo(squad, zoneSpot(squad, zone), 4)
		return
	end
	local enemy = nearestIn(squad.position, enemies, math.huge)
	if enemy then
		SquadService.moveTo(squad, enemy.position, squad.def.attackRange * 0.85)
	else
		SquadService.stop(squad)
	end
end

local function chooseFormation(squad: any, enemies: { any }, nearestEnemyDistance: number, now: number)
	local mem = squad.aiMemory
	if now - (mem.lastFormation or -math.huge) < AI.FormationChangeCooldown then
		return
	end
	local def = squad.def
	local want = def.formations[1]
	if table.find(def.formations, "Square") then
		for _, enemy in enemies do
			if
				enemy.def.visual == "Cavalry"
				and MathUtil.flatDistance(enemy.position, squad.position) <= AI.SquareThreatRadius
			then
				want = "Square"
				break
			end
		end
	end
	if want ~= "Square" and table.find(def.formations, "Column") then
		local goal = squad.goal
		if
			goal
			and MathUtil.flatDistance(goal, squad.position) > 90
			and nearestEnemyDistance > def.attackRange + 40
		then
			want = "Column" -- long march, nobody close: move fast
		end
	end
	if want ~= squad.formation and SquadService.setFormation(squad, want) then
		mem.lastFormation = now
	end
end

---------------------------------------------------------------------------
-- Behaviours
---------------------------------------------------------------------------

local function wantsFlank(squad: any, target: any): boolean
	local mem = squad.aiMemory
	if mem.flankTargetId ~= target.id then
		mem.flankTargetId = target.id
		mem.flank = rng:NextNumber() < tuning.flankPreference
		mem.flankSide = nil
	end
	return mem.flank
end

local function infantry(squad: any, enemies: { any }, allies: { any })
	local def = squad.def
	local engageRadius = def.attackRange + 20 + tuning.aggression * 80
	local isSkirmisher = def.canMoveAndFire
	local target = nearestIn(squad.position, enemies, engageRadius, function(enemy, distance)
		-- skirmishers love isolated targets
		if isSkirmisher and isExposed(enemy, allies) then
			return distance * 0.6
		end
		return distance
	end)
	if not target then
		goToObjective(squad, enemies)
		return
	end
	squad.preferredTarget = target
	local standoff = def.attackRange * 0.85
	if target.formation == "Line" and wantsFlank(squad, target) then
		-- Swing around to the side of a Line, where it takes extra damage
		local mem = squad.aiMemory
		local right = MathUtil.rightFromYaw(target.yaw)
		if not mem.flankSide then
			mem.flankSide = if (squad.position - target.position):Dot(right) >= 0 then 1 else -1
		end
		SquadService.moveTo(squad, target.position + right * mem.flankSide * standoff, 5)
	else
		SquadService.moveTo(squad, target.position, standoff)
	end
end

local function cavalry(squad: any, enemies: { any }, allies: { any }, now: number)
	local mem = squad.aiMemory
	-- Hit and run: after a charge lands, ride away to build speed for the next one
	if mem.disengageUntil and now < mem.disengageUntil then
		if MathUtil.flatDistance(squad.position, mem.disengagePoint) > 5 then
			SquadService.moveTo(squad, mem.disengagePoint, 3)
			return
		end
		mem.disengageUntil = nil
	end
	if squad.lastChargeAt and squad.lastChargeAt ~= mem.handledCharge then
		mem.handledCharge = squad.lastChargeAt
		local target = squad.preferredTarget
		local from = if target and target.alive
			then target.position
			else squad.position + MathUtil.lookFromYaw(squad.yaw)
		local away = MathUtil.flat(squad.position - from)
		if away.Magnitude < 0.1 then
			away = -MathUtil.lookFromYaw(squad.yaw)
		end
		mem.disengagePoint = squad.position + away.Unit * AI.CavalryDisengageDistance
		mem.disengageUntil = now + AI.CavalryDisengageTime
		squad.preferredTarget = nil
		SquadService.moveTo(squad, mem.disengagePoint, 3)
		return
	end

	local search = 120 + tuning.aggression * 150
	local target = nearestIn(squad.position, enemies, search, function(enemy, distance)
		if enemy.def.attackType == "Artillery" then
			return distance * 0.4 -- guns first
		elseif enemy.formation == "Square" then
			return distance * 3 -- avoid squares
		elseif isExposed(enemy, allies) then
			return distance * 0.7
		end
		return distance
	end)
	if target and (target.formation ~= "Square" or tuning.aggression > 0.8) then
		squad.preferredTarget = target
		SquadService.moveTo(squad, target.position, squad.radius + target.radius + squad.def.meleeRange * 0.5)
	else
		goToObjective(squad, enemies)
	end
end

local function artillery(squad: any, enemies: { any })
	local def = squad.def
	local range = def.attackRange
	local target = nearestIn(squad.position, enemies, range, function(enemy, distance)
		if distance < (def.minRange or 0) then
			return math.huge
		end
		-- packed formations make juicy targets
		if enemy.formation == "Square" or enemy.formation == "Column" then
			return distance * 0.6
		end
		return distance
	end)
	if target then
		squad.preferredTarget = target
		SquadService.stop(squad)
		return
	end
	squad.preferredTarget = nil
	local anyEnemy = nearestIn(squad.position, enemies, math.huge)
	if anyEnemy then
		SquadService.moveTo(squad, anyEnemy.position, range * 0.75)
	else
		goToObjective(squad, enemies)
	end
end

local function think(squad: any, enemies: { any }, allies: { any }, now: number)
	local mem = squad.aiMemory

	-- Regrouping: fall back instead of suiciding in
	if squad.aiRegrouping then
		if squad.morale >= squad.maxMorale * tuning.regroupRecover then
			squad.aiRegrouping = false
		else
			SquadService.moveTo(squad, mem.regroupPoint or squad.homePosition, 5)
			return
		end
	elseif squad.morale < squad.maxMorale * tuning.retreatThreshold then
		squad.aiRegrouping = true
		squad.preferredTarget = nil
		local friend = nearestIn(squad.position, allies, 200, function(other, distance)
			return if other == squad then math.huge else distance
		end)
		local regroup = squad.homePosition
		if friend then
			local toHome = MathUtil.flat(squad.homePosition - friend.position)
			regroup = if toHome.Magnitude > 1 then friend.position + toHome.Unit * 15 else friend.position
		end
		mem.regroupPoint = regroup
		SquadService.moveTo(squad, mem.regroupPoint, 5)
		return
	end

	local _, nearestDistance = nearestIn(squad.position, enemies, math.huge)
	chooseFormation(squad, enemies, nearestDistance, now)

	local attackType = squad.def.attackType
	if attackType == "Melee" then
		cavalry(squad, enemies, allies, now)
	elseif attackType == "Artillery" then
		artillery(squad, enemies)
	else
		infantry(squad, enemies, allies)
	end
end

function EnemyAIController.tick()
	local now = time()
	-- Routed player squads are ignored: chasing them is a waste of time
	local enemies = {}
	for _, squad in SquadService.getByTeam("Blue") do
		if not squad.routing then
			table.insert(enemies, squad)
		end
	end
	local allies = SquadService.getByTeam("Red")
	for _, squad in allies do
		if squad.alive and not squad.routing then
			think(squad, enemies, allies, now)
		end
	end
end

return EnemyAIController
