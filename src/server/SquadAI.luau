--[[
	SquadAI
	The shared squad brain used by BOTH EnemyAIController (Red) and AllyAIController (Blue
	squads the player isn't commanding). Same state machine, only the team differs:
	targets are always "the other team", objectives are "zones my team doesn't hold yet".

	Squad state machine:  Idle → Advancing → Engaging → Routing → Regrouping
	  • Routing is automatic (morale hits 0, handled by SquadService).
	  • Regrouping: morale under `retreatThreshold` → fall back to friends, return at `regroupRecover`.

	Teamwork (BattlePlan): every AI squad has a slot in its side's shared line. Squads walk to
	their slot, fire from it, don't run ahead of the line, and move up to support an engaged
	neighbour. Cavalry waits on the flanks until there is something worth charging.

	Tactics (kept readable rather than perfect):
	  • infantry heads for objectives, engages what comes into range, sometimes flanks a Line
	  • cavalry hunts artillery and exposed squads, avoids squares, hits and runs to re-charge
	  • artillery stays at long range and prefers packed targets (Square / Column)
	  • routed enemies are not chased: objectives come first
	  • infantry forms Square when enemy cavalry is close, Column for long marches
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local GameConfig = require(Modules:WaitForChild("GameConfig"))
local MathUtil = require(Modules:WaitForChild("MathUtil"))

local UnitDefinitions = require(Modules:WaitForChild("UnitDefinitions"))

local BattlePlan = require(script.Parent:WaitForChild("BattlePlan"))
local SquadService = require(script.Parent:WaitForChild("SquadService"))
local ZoneService = require(script.Parent:WaitForChild("ZoneService"))

local AI = GameConfig.AI

local SquadAI = {}

local rng = Random.new()

local tuning: any = AI.Ally -- set by SquadAI.think for the squad being evaluated

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
		local priority = if zone.owner ~= squad.team or zone.contested then 0 else 1
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

local function share(value: number, maximum: number): number
	return value / math.max(1, maximum)
end

-- Charge `target` at a sprint (AI): melee range, charge bonus, running animation
local function chargeAt(squad: any, target: any)
	squad.preferredTarget = target
	squad.rushing = true
	SquadService.moveTo(squad, target.position, squad.radius + target.radius + 1, AI.Plan.ChargeSpeedMult)
end

-- During the assault a line squad fixes bayonets against a shaken or weaker enemy
local function bayonetTarget(squad: any, enemies: { any }): any
	local def = squad.def
	if def.canMoveAndFire or def.meleeDamage < AI.Plan.BayonetMinMelee then
		return nil -- skirmishers / archers stay shooters
	end
	local mem = squad.aiMemory
	local current = mem.bayonetTarget
	if current and current.alive and not current.routing then
		return current -- committed: see the charge through
	end
	local mine = share(squad.health, squad.maxHealth)
	local target = nearestIn(squad.position, enemies, def.attackRange * 1.2, function(enemy, distance)
		local shaken = share(enemy.morale, enemy.maxMorale) < AI.Plan.BayonetMoraleBelow
		local weaker = mine - share(enemy.health, enemy.maxHealth) >= AI.Plan.BayonetHealthEdge
		if shaken or weaker or enemy.def.attackType == "Artillery" then
			return distance
		end
		return math.huge
	end)
	mem.bayonetTarget = target
	return target
end

-- Teamwork: hold your slot in the shared line; fire what comes into range; help neighbours.
-- Returns false when there is no plan (the old lone-wolf behaviour then applies).
local function lineInfantry(squad: any, enemies: { any }): boolean
	local plan = BattlePlan.get(squad.team)
	local slot = plan and plan.slots[squad]
	if not slot then
		return false
	end
	local def = squad.def
	local range = def.attackRange
	squad.idleYaw = plan.yaw
	if plan.assault then
		local foe = bayonetTarget(squad, enemies)
		if foe then
			chargeAt(squad, foe)
			return true
		end
	else
		squad.aiMemory.bayonetTarget = nil
	end
	local target = nearestIn(squad.position, enemies, range * 0.95)
	if target then
		squad.preferredTarget = target
		if MathUtil.flatDistance(squad.position, slot) > AI.Plan.SlotLeash then
			SquadService.moveTo(squad, slot, 4) -- drifted off: back into the line
		else
			SquadService.stop(squad) -- in range: stand and fire
		end
		return true
	end
	-- a neighbour is caught in a fight: move up so its enemy is in our range
	local friend = BattlePlan.supportTarget(squad)
	if friend then
		local foe = nearestIn(friend.position, enemies, friend.radius + 40)
		if foe then
			squad.preferredTarget = foe
			SquadService.moveTo(squad, foe.position, range * 0.85)
			return true
		end
	end
	squad.preferredTarget = nil
	SquadService.moveTo(squad, slot, 4)
	return true
end

local function infantry(squad: any, enemies: { any }, allies: { any })
	if lineInfantry(squad, enemies) then
		return
	end
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
	-- teamwork: wait on the flank until the lines meet, or a gun / an exposed squad is near
	local plan = BattlePlan.get(squad.team)
	local slot = plan and plan.slots[squad]
	if slot and not (mem.disengageUntil and now < mem.disengageUntil) then
		local lineEngaged = #plan.engaged > 0 or plan.assault
		local prey = nearestIn(squad.position, enemies, AI.Plan.CavalryPreyRadius, function(enemy, distance)
			if enemy.formation == "Square" then
				return math.huge
			end
			-- guns, archers / skirmishers (they can't hold a melee) and lonely squads
			if enemy.def.attackType == "Artillery" or enemy.def.canMoveAndFire or isExposed(enemy, enemies) then
				return distance
			end
			return math.huge
		end)
		if not lineEngaged and not prey and not squad.preferredTarget then
			SquadService.moveTo(squad, slot, 5)
			squad.idleYaw = plan.yaw
			return
		end
	end
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
		elseif enemy.def.canMoveAndFire and enemy.formation ~= "Square" then
			return distance * 0.55 -- then archers / skirmishers
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

-- Foot brawlers (bandit swordsmen): rush the nearest enemy, gunners and guns first, and stay
-- in the melee (no charge-and-pull-back like cavalry)
local function brawlers(squad: any, enemies: { any })
	-- teamwork: stand in front of the line until an enemy comes within charging reach
	local plan = BattlePlan.get(squad.team)
	local slot = plan and plan.slots[squad]
	if slot then
		local reach = if plan.assault then AI.Plan.AssaultReach else AI.Plan.ChargeReach
		local near = nearestIn(squad.position, enemies, reach, function(enemy, distance)
			if enemy.def.attackType ~= "Melee" then
				return distance * 0.75 -- shooters can't hold a brawl
			end
			return distance
		end)
		local friend = BattlePlan.supportTarget(squad)
		if not near and friend then
			near = nearestIn(friend.position, enemies, friend.radius + 40)
		end
		if near then
			chargeAt(squad, near)
		else
			squad.preferredTarget = nil
			SquadService.moveTo(squad, slot, 4)
			squad.idleYaw = plan.yaw
		end
		return
	end
	local search = 140 + tuning.aggression * 160
	local target = nearestIn(squad.position, enemies, search, function(enemy, distance)
		if enemy.def.attackType ~= "Melee" then
			return distance * 0.75 -- shooters can't hold a brawl
		end
		return distance
	end)
	if target then
		chargeAt(squad, target)
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
	-- teamwork: guns follow the line from behind instead of trundling at the enemy alone
	local plan = BattlePlan.get(squad.team)
	local slot = plan and plan.slots[squad]
	if slot then
		SquadService.moveTo(squad, slot, 4)
		squad.idleYaw = plan.yaw
		return
	end
	local anyEnemy = nearestIn(squad.position, enemies, math.huge)
	if anyEnemy then
		SquadService.moveTo(squad, anyEnemy.position, range * 0.75)
	else
		goToObjective(squad, enemies)
	end
end

-- An enemy charging at `target`: cavalry or a rushing squad close and heading at it (nil if none)
local function chargeComingAt(enemies: { any }, target: any): any
	local T = AI.Threat
	for _, enemy in enemies do
		if enemy.def.attackType ~= "Artillery" and (enemy.def.visual == "Cavalry" or enemy.rushing) then
			local offset = MathUtil.flat(target.position - enemy.position)
			local distance = offset.Magnitude
			if distance <= T.Radius and distance > 0.1 then
				local heading = MathUtil.lookFromYaw(enemy.moveYaw or enemy.yaw)
				if
					enemy.rushing
					or enemy.preferredTarget == target
					or (enemy.isMoving and heading:Dot(offset / distance) >= T.HeadingDot)
				then
					return enemy
				end
			end
		end
	end
	return nil
end

-- Archers under a charge pull back behind their infantry (or just away). True = handled.
local function evade(squad: any, enemies: { any }, allies: { any }, now: number): boolean
	local mem = squad.aiMemory
	if mem.evadeUntil and now < mem.evadeUntil then
		return true -- keep running to the cover spot
	end
	if not UnitDefinitions.isArcher(squad.def) then
		return false
	end
	local threat = chargeComingAt(enemies, squad)
	if not threat then
		return false
	end
	local T = AI.Threat
	local cover = nearestIn(squad.position, allies, 150, function(other, distance)
		if other == squad or UnitDefinitions.isArcher(other.def) or other.def.attackType == "Artillery" then
			return math.huge
		end
		return distance
	end)
	local away = MathUtil.flat(squad.position - threat.position)
	away = if away.Magnitude > 0.1 then away.Unit else -MathUtil.lookFromYaw(squad.yaw)
	local spot
	if cover then
		local behind = MathUtil.flat(cover.position - threat.position)
		behind = if behind.Magnitude > 0.1 then behind.Unit else away
		spot = cover.position + behind * (cover.radius + squad.radius + T.CoverDepth)
	else
		spot = squad.position + away * 60
	end
	squad.preferredTarget = nil
	SquadService.moveTo(squad, spot, 3, T.RetreatSpeedMult)
	mem.evadeUntil = now + T.RetreatTime
	return true
end

-- Melee foot near a friendly archer squad under a charge move in to intercept the riders
local function intercept(squad: any, enemies: { any }, allies: { any }): boolean
	local def = squad.def
	if def.attackType ~= "Melee" or def.visual == "Cavalry" then
		return false
	end
	for _, friend in allies do
		if
			friend ~= squad
			and UnitDefinitions.isArcher(friend.def)
			and MathUtil.flatDistance(friend.position, squad.position) <= AI.Threat.InterceptRadius
		then
			local threat = chargeComingAt(enemies, friend)
			if threat then
				chargeAt(squad, threat)
				return true
			end
		end
	end
	return false
end

-- Decide what `squad` does next. enemies = non-routing squads of the other team.
function SquadAI.think(squad: any, enemies: { any }, allies: { any }, tuningValues: any, now: number)
	tuning = tuningValues
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

	-- answer the enemy's moves first: archers dodge charges, foot soldiers cover them
	if evade(squad, enemies, allies, now) or intercept(squad, enemies, allies) then
		return
	end

	local _, nearestDistance = nearestIn(squad.position, enemies, math.huge)
	chooseFormation(squad, enemies, nearestDistance, now)

	local attackType = squad.def.attackType
	if attackType == "Melee" and squad.def.visual ~= "Cavalry" then
		brawlers(squad, enemies)
	elseif attackType == "Melee" then
		cavalry(squad, enemies, allies, now)
	elseif attackType == "Artillery" then
		artillery(squad, enemies)
	else
		infantry(squad, enemies, allies)
	end
end

return SquadAI
