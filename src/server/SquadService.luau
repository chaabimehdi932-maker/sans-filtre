--[[
	SquadService
	A squad is ONE logical object (pooled HP, morale, position, facing, formation).
	All combat math runs on the squad, never per soldier. The server owns NO soldier parts:
	clients draw and animate the soldiers from the snapshots (client/SquadRenderer).

	Frame loop (called from GameManager on Heartbeat):
	  • every frame   : movement along PathfindingService waypoints
	  • every 0.2 s   : morale, target selection, volleys / melee / artillery

	Behaviour layers (CommandService for the player's squads, EnemyAIController for the enemy)
	only set intent: moveTo / stop / setFormation / preferredTarget / idleYaw.
]]

local PathfindingService = game:GetService("PathfindingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local FormationDefinitions = require(Modules:WaitForChild("FormationDefinitions"))
local GameConfig = require(Modules:WaitForChild("GameConfig"))
local MathUtil = require(Modules:WaitForChild("MathUtil"))
local Remotes = require(Modules:WaitForChild("Remotes"))
local UnitDefinitions = require(Modules:WaitForChild("UnitDefinitions"))

local MapService = require(script.Parent:WaitForChild("MapService"))

local Combat = GameConfig.Combat
local Morale = GameConfig.Morale
local Formations = FormationDefinitions.Formations

local vfxRemote = Remotes.get("VFX")

type Squad = any

local SquadService = {}

-- Hooks wired by GameManager (avoids circular requires between services)
SquadService.hooks = {
	-- { { player: Player, position: Vector3 } } of living commanders (all on team Blue)
	getHeroes = function(): { any }
		return {}
	end,
	damageHero = function(_player: Player, _amount: number, _fromPosition: Vector3?, _kind: string) end,
	getTeamBonus = function(_team: string, _bonus: string): number
		return 0
	end,
	-- creditPlayer = the player whose own squad (or commander) caused the casualties, if any
	onCasualties = function(_squad: Squad, _soldiersLost: number, _attackerTeam: string?, _creditPlayer: Player?) end,
	onSquadDestroyed = function(_squad: Squad, _attackerTeam: string?) end,
	onRout = function(_squad: Squad) end,
	-- terrain (MapService): musket precision multiplier for where the squad stands
	getTerrainAccuracy = function(_squad: Squad): number
		return 1
	end,
	-- the squad's mounted officer was killed
	onCommanderKilled = function(_squad: Squad, _info: any) end,
	-- soldiers of `squad` died; info = { attacker?: Squad, creditPlayer?: Player, kind }
	onKill = function(_squad: Squad, _lost: number, _info: any) end,
}

local squadsById: { [number]: Squad } = {}
local squadList: { Squad } = {}
local nextId = 0
local paused = false
local combatTimer = 0

local PATH_MIN_DISTANCE = 30

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

local function formationStat(squad: Squad, key: string): number
	local base = Formations[squad.formation][key]
	local mods = squad.def.formationModifiers
	local mod = mods and mods[squad.formation] and mods[squad.formation][key]
	return base * (mod or 1)
end

local function strengthFactor(squad: Squad): number
	return Combat.MinStrengthFactor + (1 - Combat.MinStrengthFactor) * (squad.health / squad.maxHealth)
end

local function damageRoll(): number
	return Combat.DamageRandomMin + math.random() * (Combat.DamageRandomMax - Combat.DamageRandomMin)
end

local function rangeMultiplier(squad: Squad): number
	if squad.def.attackType == "Artillery" then
		return 1 + SquadService.hooks.getTeamBonus(squad.team, "ArtilleryRange") * GameConfig.Zones.ArtilleryRangeBonus
	end
	return 1
end

-- "Front" | "Flank" | "Rear" — where `fromPosition` is relative to the squad's facing
local function relativeSide(squad: Squad, fromPosition: Vector3): string
	local toAttacker = MathUtil.flat(fromPosition - squad.position)
	if toAttacker.Magnitude < 0.01 then
		return "Front"
	end
	local dot = MathUtil.lookFromYaw(squad.yaw):Dot(toAttacker.Unit)
	if dot > 0.5 then
		return "Front"
	elseif dot < -0.5 then
		return "Rear"
	end
	return "Flank"
end

local function removeFromList(squad: Squad)
	local index = table.find(squadList, squad)
	if index then
		table.remove(squadList, index)
	end
	squadsById[squad.id] = nil
end

---------------------------------------------------------------------------
-- Footprint (soldiers are drawn by each client, see client/SquadRenderer)
---------------------------------------------------------------------------

-- Radius of the squad on the ground, from the same layout the clients draw
local function recomputeRadius(squad: Squad)
	local slots = FormationDefinitions.layout(squad.formation, squad.soldierCount, squad.def.spacingMult)
	local radius = 2
	for _, slot in slots do
		radius = math.max(radius, slot.Magnitude + 1)
	end
	-- a wide single-rank line is still one body of men: cap the contact circle so its far
	-- flanks don't count as touching everything around it
	squad.radius = math.min(radius, 18)
end

---------------------------------------------------------------------------
-- Creation / lookup
---------------------------------------------------------------------------

--[[
	params = { unitId, team, position, yaw, formation?, owner?, name?, statMultiplier?, damageMultiplier?,
	           rank?, rosterId?, healthFraction? }
	healthFraction < 1 starts the squad under strength (campaign squads keep their casualties).
]]
function SquadService.create(params: any): Squad
	local def = UnitDefinitions.get(params.unitId)
	assert(def, "Unknown unit " .. tostring(params.unitId))
	nextId += 1
	local statMult = params.statMultiplier or 1
	local position = params.position
	position = Vector3.new(position.X, MapService.groundY(position.X, position.Z, position.Y), position.Z)
	local yaw = params.yaw or 0

	local squad: Squad = {
		id = nextId,
		unitId = def.id,
		def = def,
		team = params.team,
		owner = params.owner,
		name = params.name or def.displayName,
		maxHealth = def.health * statMult,
		health = def.health * statMult * math.clamp(params.healthFraction or 1, 0.01, 1),
		maxMorale = def.morale * statMult,
		morale = def.morale * statMult * math.clamp(params.moraleFraction or 1, 0.05, 1),
		damageMult = params.damageMultiplier or 1,
		alive = true,
		soldierCount = math.max(1, math.ceil(def.soldiers * math.clamp(params.healthFraction or 1, 0.01, 1))),
		radius = 2,

		position = position,
		homePosition = position,
		yaw = yaw,
		moveYaw = yaw,
		idleYaw = yaw, -- direction to face when idle (set by orders / AI)
		combatYaw = yaw,
		combatYawUntil = 0,
		formation = params.formation or def.formations[1],
		formingStarted = 0,
		formingUntil = 0,

		goal = nil,
		stopDistance = 2,
		speedMult = 1,
		waypoints = nil,
		waypointIndex = 1,
		pathGoal = nil,
		pathPending = false,
		lastPathTime = -math.huge,
		isMoving = false,
		movingTime = 0,
		chargeReadyUntil = 0,
		lastChargeAt = nil,
		rushing = false,

		preferredTarget = nil,
		lastAttack = -math.huge,
		lastMelee = -math.huge,
		lastDamagedAt = -math.huge,
		inCombatUntil = 0,

		state = "Idle",
		routing = false,
		regroupUntil = 0,
		aiRegrouping = false,
		order = "Hold", -- used while isPlayerControlled: Hold | Follow | Attack | Rush
		isPlayerControlled = false, -- true = obeys its owner's hotkeys, false = AI (SquadController)
		rank = params.rank or 0, -- veteran stars = evolution tier
		rosterId = params.rosterId, -- campaign roster entry this squad was deployed from
		commanderAlive = true, -- the mounted officer leading the squad
		commanderHealth = GameConfig.Commander.Health * statMult,
		commanderName = params.commanderName, -- a companion leads it (else a generic officer)
		aiMemory = {},
		stats = { damageDealt = 0, kills = 0 },
	}
	recomputeRadius(squad)
	squadsById[squad.id] = squad
	table.insert(squadList, squad)
	return squad
end

function SquadService.getAll(): { Squad }
	return squadList
end

function SquadService.getById(id: number): Squad?
	return squadsById[id]
end

function SquadService.getByTeam(team: string): { Squad }
	local list = {}
	for _, squad in squadList do
		if squad.team == team then
			table.insert(list, squad)
		end
	end
	return list
end

function SquadService.getOwnedBy(player: Player): { Squad }
	local list = {}
	for _, squad in squadList do
		if squad.owner == player then
			table.insert(list, squad)
		end
	end
	table.sort(list, function(a, b)
		return a.id < b.id
	end)
	return list
end

-- Nearest enemy squad of `squad` within maxDistance. `scoreFn(enemy, distance)` can reweight choices.
function SquadService.nearestEnemy(
	squad: Squad,
	maxDistance: number?,
	scoreFn: ((Squad, number) -> number?)?
): (Squad?, number)
	local best, bestScore, bestDistance = nil, math.huge, math.huge
	for _, other in squadList do
		if other.team ~= squad.team and other.alive then
			local distance = MathUtil.flatDistance(squad.position, other.position)
			if not maxDistance or distance <= maxDistance then
				local score = if scoreFn then scoreFn(other, distance) else distance
				if score and score < bestScore then
					best, bestScore, bestDistance = other, score, distance
				end
			end
		end
	end
	return best, bestDistance
end

---------------------------------------------------------------------------
-- Intent API (used by CommandService / EnemyAIController)
---------------------------------------------------------------------------

function SquadService.moveTo(squad: Squad, goal: Vector3, stopDistance: number?, speedMult: number?)
	if squad.routing then
		return -- routing squads ignore orders
	end
	squad.goal = goal
	squad.stopDistance = stopDistance or 2
	squad.speedMult = speedMult or 1
end

function SquadService.stop(squad: Squad)
	if squad.routing then
		return
	end
	squad.goal = nil
	squad.waypoints = nil
end

function SquadService.setFormation(squad: Squad, formation: string): boolean
	if not squad.alive or squad.routing or squad.formation == formation then
		return false
	end
	if not Formations[formation] or not table.find(squad.def.formations, formation) then
		return false
	end
	local now = time()
	if now < squad.formingUntil then
		return false
	end
	squad.formation = formation
	squad.formingStarted = now
	squad.formingUntil = now + FormationDefinitions.FORM_UP_TIME
	recomputeRadius(squad)
	return true
end

function SquadService.addMorale(squad: Squad, amount: number)
	if squad.alive then
		squad.morale = math.clamp(squad.morale + amount, 0, squad.maxMorale)
	end
end

---------------------------------------------------------------------------
-- Damage, casualties, rout
---------------------------------------------------------------------------

local function destroySquad(squad: Squad, attackerTeam: string?)
	squad.alive = false
	squad.soldierCount = 0
	removeFromList(squad)
	SquadService.hooks.onSquadDestroyed(squad, attackerTeam)
end

local function refreshSoldierCount(squad: Squad, attackerTeam: string?, creditPlayer: Player?): number
	local desired = if squad.health <= 0
		then 0
		else math.max(1, math.ceil(squad.def.soldiers * squad.health / squad.maxHealth))
	local lost = squad.soldierCount - desired
	if lost > 0 then
		squad.soldierCount = desired
		if desired > 0 then
			recomputeRadius(squad)
		end
		SquadService.hooks.onCasualties(squad, lost, attackerTeam, creditPlayer)
		return lost
	end
	return 0
end

local function startRout(squad: Squad)
	squad.routing = true
	squad.aiRegrouping = false
	squad.preferredTarget = nil
	squad.rushing = false
	squad.formingUntil = 0
	-- flee towards the spawn (internal move: bypasses the "routing ignores orders" guard)
	squad.goal = squad.homePosition
	squad.stopDistance = 3
	squad.speedMult = 1
	squad.state = "Routing"
	SquadService.hooks.onRout(squad)
end

-- Make a squad flee now; `forever` = it won't rally (hopeless battles)
function SquadService.forceRout(squad: Squad, forever: boolean?)
	if not squad.alive then
		return
	end
	squad.morale = 0
	squad.noRally = forever == true
	if not squad.routing then
		startRout(squad)
	end
end

local function recoverFromRout(squad: Squad, now: number)
	squad.routing = false
	squad.morale = math.max(squad.morale, squad.maxMorale * Morale.RoutRecoverFraction * 0.8)
	squad.regroupUntil = now + Morale.RegroupTime
	squad.order = "Hold"
	squad.holdPosition = nil
	squad.pendingFormation = nil
	squad.goal = nil
	squad.waypoints = nil
	squad.idleYaw = squad.yaw
end

--[[
	info = { kind = "Ranged" | "Melee" | "Charge" | "Artillery" | "Hero",
	         fromPosition = Vector3?, attackerTeam = string?, attacker = Squad?, creditPlayer = Player? }
	Clients get a DamageNumber effect where the damage landed.
	Returns the damage actually dealt after modifiers.
]]
function SquadService.applyDamage(squad: Squad, amount: number, info: any): number
	if not squad.alive then
		return 0
	end
	local now = time()
	local kind = info.kind
	local mult = 1
	if kind == "Artillery" then
		mult *= formationStat(squad, "artilleryTakenMult")
	elseif kind == "Charge" then
		mult *= formationStat(squad, "chargeTakenMult")
	elseif kind == "Ranged" then
		mult *= formationStat(squad, "rangedTakenMult")
	end
	local side = "Front"
	if info.fromPosition and kind ~= "Artillery" then
		side = relativeSide(squad, info.fromPosition)
		if side == "Flank" then
			mult *= formationStat(squad, "flankTakenMult")
		elseif side == "Rear" then
			mult *= formationStat(squad, "rearTakenMult")
		end
	end
	if now < squad.formingUntil then
		mult *= FormationDefinitions.FORMING_DAMAGE_TAKEN_MULT
	end
	if squad.rushing then
		mult *= GameConfig.Orders.RushDamageTakenMult
	end
	if squad.routing then
		mult *= Combat.RoutingDamageTakenMult
	end

	local dealt = math.min(squad.health, amount * mult)
	squad.health -= dealt
	squad.lastDamagedAt = now
	squad.inCombatUntil = now + Morale.CombatCooldown
	if info.attacker then
		info.attacker.stats.damageDealt += dealt
	end

	local moraleLoss = dealt / squad.maxHealth * Morale.CasualtyLossFactor
	if side ~= "Front" then
		moraleLoss *= Morale.FlankedMult
	end
	if kind == "Charge" then
		moraleLoss += Morale.ChargeShock * formationStat(squad, "chargeMoraleMult")
	end
	squad.morale = math.max(0, squad.morale - moraleLoss)

	-- the officer riding at the front can be hit too (not when the player leads the squad)
	if squad.commanderAlive and not squad.isPlayerControlled and dealt > 0 then
		local exposure = GameConfig.Commander.Exposure[kind] or 0.05
		squad.commanderHealth -= dealt * exposure
		if squad.commanderHealth <= 0 then
			squad.commanderAlive = false
			squad.morale = math.max(0, squad.morale - GameConfig.Commander.DeathMorale)
			SquadService.hooks.onCommanderKilled(squad, info)
		end
	end

	-- floating damage number at the spot that was hit
	if dealt >= 0.5 then
		local offset = Vector3.new(math.random() - 0.5, 0, math.random() - 0.5) * squad.radius
		vfxRemote:FireAllClients({
			kind = "DamageNumber",
			position = squad.position + offset + Vector3.new(0, 6, 0),
			amount = math.floor(dealt + 0.5),
			victimTeam = squad.team,
			big = kind == "Charge" or kind == "Artillery" or kind == "Hero",
		})
	end

	local creditPlayer = info.creditPlayer or (info.attacker and info.attacker.owner)
	local lost = refreshSoldierCount(squad, info.attackerTeam, creditPlayer)
	if lost > 0 and info.attacker then
		info.attacker.stats.kills += lost -- squad XP (campaign evolution)
	end
	if lost > 0 then
		SquadService.hooks.onKill(squad, lost, info)
	end
	if squad.health <= 0 then
		destroySquad(squad, info.attackerTeam)
	elseif squad.morale <= 0 and not squad.routing then
		startRout(squad)
	end
	return dealt
end

---------------------------------------------------------------------------
-- Combat resolution (server-authoritative)
---------------------------------------------------------------------------

local function reachOf(squad: Squad): number
	local def = squad.def
	local ranged = if def.attackType == "Melee" then 0 else def.attackRange * rangeMultiplier(squad)
	return math.max(ranged, squad.radius + def.meleeRange)
end

-- Target = { kind = "Squad", squad, position, radius } or { kind = "Hero", player, position, radius }
local function findTarget(squad: Squad, heroes: { any }): any
	local reach = reachOf(squad)
	local preferred = squad.preferredTarget
	if preferred and preferred.alive and preferred.team ~= squad.team then
		local distance = MathUtil.flatDistance(squad.position, preferred.position)
		if distance <= reach + preferred.radius then
			return { kind = "Squad", squad = preferred, position = preferred.position, radius = preferred.radius }
		end
	end

	local best, bestScore = nil, math.huge
	for _, other in squadList do
		if other.team ~= squad.team and other.alive then
			local distance = MathUtil.flatDistance(squad.position, other.position)
			-- don't waste volleys on fleeing units when a real threat is around
			local score = if other.routing then distance * 1.5 else distance
			if distance <= reach + other.radius and score < bestScore then
				best, bestScore = other, score
			end
		end
	end
	local target = nil
	local targetDistance = math.huge
	if best then
		target = { kind = "Squad", squad = best, position = best.position, radius = best.radius }
		targetDistance = MathUtil.flatDistance(squad.position, best.position)
	end
	-- Enemy squads can also shoot at / fight the player's commander
	if squad.team == "Red" then
		for _, hero in heroes do
			local distance = MathUtil.flatDistance(squad.position, hero.position)
			if distance <= reach + 1.5 and distance < targetDistance then
				target = { kind = "Hero", player = hero.player, position = hero.position, radius = 1.5 }
				targetDistance = distance
			end
		end
	end
	return target
end

local function dealDamage(attacker: Squad, target: any, amount: number, kind: string, now: number)
	attacker.inCombatUntil = now + Morale.CombatCooldown
	if target.kind == "Squad" then
		SquadService.applyDamage(target.squad, amount, {
			kind = kind,
			fromPosition = attacker.position,
			attackerTeam = attacker.team,
			attacker = attacker,
		})
	else
		SquadService.hooks.damageHero(
			target.player,
			amount * GameConfig.Hero.DamageTakenFromSquadsMult,
			attacker.position,
			kind
		)
	end
end

-- Musket precision from formation quality (GameConfig.Combat.Accuracy) and terrain
function SquadService.accuracy(squad: Squad, now: number?): number
	local acc = Combat.Accuracy
	local value
	if squad.formation == "Column" then
		value = acc.Column
	elseif squad.formation == "Square" then
		value = acc.Square
	else
		local ranks = FormationDefinitions.ranks(squad.formation, squad.soldierCount)
		value = acc.Line - acc.PerExtraRank * (ranks - 1)
	end
	if (now or time()) < squad.formingUntil then
		value *= acc.Forming
	end
	if squad.isMoving then
		value *= acc.Moving
	end
	value *= SquadService.hooks.getTerrainAccuracy(squad)
	return math.max(acc.Minimum, value)
end

local function fireVolley(squad: Squad, target: any, distance: number, range: number, now: number)
	local def = squad.def
	local falloff = 1 - Combat.RangeFalloff * math.clamp(distance / range, 0, 1)
	local damage = def.damage
		* SquadService.accuracy(squad, now)
		* squad.damageMult
		* formationStat(squad, "firepowerMult")
		* strengthFactor(squad)
		* damageRoll()
		* falloff
	dealDamage(squad, target, damage, "Ranged", now)
	vfxRemote:FireAllClients({ kind = "Volley", squadId = squad.id, direction = MathUtil.lookFromYaw(squad.yaw) })
end

local function fireArtillery(squad: Squad, target: any, distance: number, range: number)
	local def = squad.def
	local scatter = Combat.ArtilleryScatter * math.clamp(distance / range, 0.2, 1)
	local angle = math.random() * math.pi * 2
	local impact = target.position + Vector3.new(math.cos(angle), 0, math.sin(angle)) * (math.random() * scatter)
	impact = Vector3.new(impact.X, MapService.groundY(impact.X, impact.Z, target.position.Y), impact.Z)
	local muzzle = (CFrame.new(squad.position) * CFrame.Angles(0, squad.yaw, 0) * CFrame.new(0, 1.7, -5.3)).Position
	local flight = distance / Combat.ArtilleryShellSpeed
	vfxRemote:FireAllClients({ kind = "Cannon", squadId = squad.id, from = muzzle, to = impact, flight = flight })

	-- Damage lands when the ball does. Capture values now: the gun may be dead by then.
	local team = squad.team
	local baseDamage = def.damage * squad.damageMult * strengthFactor(squad) * damageRoll()
	local splash = def.splashRadius or 12
	task.delay(flight, function()
		for _, other in table.clone(squadList) do
			if other.alive and other.team ~= team then
				local d = MathUtil.flatDistance(other.position, impact)
				if d <= splash + other.radius * 0.5 then
					local falloff = 1 - 0.5 * math.clamp(d / (splash + other.radius * 0.5), 0, 1)
					SquadService.applyDamage(other, baseDamage * falloff, {
						kind = "Artillery",
						fromPosition = impact,
						attackerTeam = team,
						attacker = if squad.alive then squad else nil,
					})
				end
			end
		end
		if team == "Red" then
			for _, hero in SquadService.hooks.getHeroes() do
				local d = MathUtil.flatDistance(hero.position, impact)
				if d <= splash then
					SquadService.hooks.damageHero(
						hero.player,
						baseDamage * (1 - 0.5 * d / splash) * GameConfig.Hero.DamageTakenFromSquadsMult,
						impact,
						"Artillery"
					)
				end
			end
		end
	end)
end

local function doMelee(squad: Squad, target: any, now: number)
	local def = squad.def
	local damage = def.meleeDamage * squad.damageMult * strengthFactor(squad) * damageRoll()
	local kind = "Melee"
	if def.chargeMultiplier > 1 and now < squad.chargeReadyUntil then
		-- Charge bonus: consumed by the first hit; the squad must disengage and build speed again
		damage *= def.chargeMultiplier
		kind = "Charge"
		squad.chargeReadyUntil = 0
		squad.movingTime = 0
		squad.lastChargeAt = now
		vfxRemote:FireAllClients({
			kind = "ChargeImpact",
			position = target.position,
			squadId = squad.id,
			targetId = if target.squad then target.squad.id else nil,
		})
	elseif now - (squad.lastClashVfx or 0) > 1.2 then
		-- tells clients to play the melee animation on both squads (throttled)
		squad.lastClashVfx = now
		vfxRemote:FireAllClients({
			kind = "Clash",
			position = target.position,
			squadId = squad.id,
			targetId = if target.squad then target.squad.id else nil,
		})
	end
	dealDamage(squad, target, damage, kind, now)
end

-- Rushing cavalry ride straight through enemy squads, hitting each one once per rush
local function pierce(squad: Squad, now: number): boolean
	if not (squad.rushing and squad.rushTarget and squad.def.attackType == "Melee" and squad.isMoving) then
		return false
	end
	squad.pierced = squad.pierced or {}
	for _, other in table.clone(squadList) do
		if other.alive and other.team ~= squad.team and not squad.pierced[other.id] then
			if MathUtil.flatDistance(squad.position, other.position) <= squad.radius + other.radius then
				squad.pierced[other.id] = true
				local damage = squad.def.meleeDamage
					* squad.def.chargeMultiplier
					* GameConfig.Orders.RushPierceMult
					* squad.damageMult
					* strengthFactor(squad)
					* damageRoll()
				SquadService.applyDamage(other, damage, {
					kind = "Charge",
					fromPosition = squad.position,
					attackerTeam = squad.team,
					attacker = squad,
				})
				squad.inCombatUntil = now + Morale.CombatCooldown
				vfxRemote:FireAllClients({
					kind = "ChargeImpact",
					position = other.position,
					squadId = squad.id,
					targetId = other.id,
				})
			end
		end
	end
	return true -- keep galloping: no stopping to fight while piercing
end

local function attemptAttack(squad: Squad, target: any, now: number)
	local def = squad.def
	local offset = MathUtil.flat(target.position - squad.position)
	local distance = offset.Magnitude
	if distance > 0.01 then
		squad.combatYaw = MathUtil.yawFromDirection(offset)
		squad.combatYawUntil = now + 1
	end

	-- Hand-to-hand when close enough (bayonets for infantry, sabres for cavalry)
	local edge = distance - squad.radius - target.radius
	if edge <= def.meleeRange then
		if now - squad.lastMelee >= def.meleeCooldown then
			squad.lastMelee = now
			doMelee(squad, target, now)
		end
		return
	end
	if def.attackType == "Melee" then
		return
	end

	local range = def.attackRange * rangeMultiplier(squad)
	if distance > range or (def.minRange and distance < def.minRange) then
		return
	end
	if squad.isMoving and not def.canMoveAndFire then
		return
	end
	if math.abs(MathUtil.angleDiff(squad.yaw, squad.combatYaw)) > math.rad(Combat.FiringArcDegrees) then
		return -- still turning to face the target
	end
	if now - squad.lastAttack < def.attackCooldown then
		return
	end
	squad.lastAttack = now
	if def.attackType == "Artillery" then
		fireArtillery(squad, target, distance, range)
	else
		fireVolley(squad, target, distance, range, now)
	end
end

---------------------------------------------------------------------------
-- Morale & state
---------------------------------------------------------------------------

local function hasFriendNearby(squad: Squad, radius: number, heroes: { any }): boolean
	for _, other in squadList do
		if other ~= squad and other.team == squad.team and not other.routing then
			if MathUtil.flatDistance(other.position, squad.position) <= radius + other.radius then
				return true
			end
		end
	end
	if squad.team == "Blue" then
		-- the commander's presence steadies his troops
		for _, hero in heroes do
			if MathUtil.flatDistance(hero.position, squad.position) <= radius then
				return true
			end
		end
	end
	return false
end

local function updateMorale(squad: Squad, dt: number, now: number, heroes: { any })
	if squad.routing then
		if squad.noRally then
			return -- hopeless: they keep running
		end
		if now - squad.lastDamagedAt > Morale.RoutRecoverDelay then
			squad.morale = math.min(squad.maxMorale, squad.morale + Morale.RoutRegen * dt)
		end
		local safe = MathUtil.flatDistance(squad.position, squad.homePosition) <= Morale.RoutSafeDistance
		if squad.morale >= squad.maxMorale * Morale.RoutRecoverFraction or safe then
			recoverFromRout(squad, now)
		end
		return
	end

	local friendNear = hasFriendNearby(squad, Morale.IsolationRadius, heroes)
	if now < squad.inCombatUntil then
		if not friendNear then
			squad.morale -= Morale.IsolationDrain * dt
		end
	else
		local bonus = 1 + SquadService.hooks.getTeamBonus(squad.team, "Morale") * GameConfig.Zones.MoraleRegenBonus
		local regen = Morale.RegenOutOfCombat * (if friendNear then 1 else Morale.RegenAloneMult) * bonus
		squad.morale = math.min(squad.maxMorale, squad.morale + regen * dt)
	end
	if squad.morale <= 0 then
		squad.morale = 0
		startRout(squad)
	end
end

local function updateState(squad: Squad, now: number)
	if squad.routing then
		squad.state = "Routing"
	elseif now < squad.regroupUntil or squad.aiRegrouping then
		squad.state = "Regrouping"
	elseif now < squad.inCombatUntil then
		squad.state = "Engaging"
	elseif squad.isMoving then
		squad.state = "Advancing"
	else
		squad.state = "Idle"
	end
end

---------------------------------------------------------------------------
-- Movement (PathfindingService, throttled)
---------------------------------------------------------------------------

local function requestPath(squad: Squad, goal: Vector3, now: number)
	squad.pathPending = true
	squad.lastPathTime = now
	local start = squad.position
	task.spawn(function()
		local path = PathfindingService:CreatePath({
			AgentRadius = 4,
			AgentHeight = 6,
			AgentCanJump = false,
			WaypointSpacing = 10,
		})
		local ok = pcall(function()
			path:ComputeAsync(start + Vector3.new(0, 2, 0), goal + Vector3.new(0, 2, 0))
		end)
		squad.pathPending = false
		if not squad.alive then
			return
		end
		squad.pathGoal = goal
		if ok and path.Status == Enum.PathStatus.Success then
			local points = {}
			for _, waypoint in path:GetWaypoints() do
				table.insert(points, waypoint.Position)
			end
			squad.waypoints = points
			squad.waypointIndex = 1
		else
			squad.waypoints = nil -- no path: walk straight at the goal
		end
	end)
end

-- Next point to walk towards. Second value = true when it is the final goal (respect stopDistance).
local function nextPoint(squad: Squad, now: number): (Vector3?, boolean)
	local goal = squad.goal
	if not goal then
		return nil, false
	end
	local distance = MathUtil.flatDistance(squad.position, goal)
	if distance <= squad.stopDistance then
		return nil, false
	end
	if distance > PATH_MIN_DISTANCE then
		local stale = squad.pathGoal == nil or MathUtil.flatDistance(squad.pathGoal, goal) > 8
		if stale and not squad.pathPending and now - squad.lastPathTime >= GameConfig.AI.PathRecalcInterval then
			requestPath(squad, goal, now)
		end
		local waypoints = squad.waypoints
		if not stale and waypoints then
			while
				squad.waypointIndex <= #waypoints
				and MathUtil.flatDistance(squad.position, waypoints[squad.waypointIndex]) < 3
			do
				squad.waypointIndex += 1
			end
			if squad.waypointIndex < #waypoints then
				return waypoints[squad.waypointIndex], false
			end
		end
	end
	return goal, true
end

local function stepMovement(squad: Squad, dt: number, now: number)
	local def = squad.def
	local moving = false
	if now >= squad.formingUntil then
		local point, isFinal = nextPoint(squad, now)
		if point then
			local offset = MathUtil.flat(point - squad.position)
			local distance = offset.Magnitude
			local remaining = if isFinal then distance - squad.stopDistance else distance
			if remaining > 0.05 and distance > 0.01 then
				local speed = def.moveSpeed
					* formationStat(squad, "speedMult")
					* squad.speedMult
					* (if squad.routing then Morale.RoutSpeedMult else 1)
				local direction = offset / distance
				local newPosition = squad.position + direction * math.min(remaining, speed * dt)
				local y = MapService.groundY(newPosition.X, newPosition.Z, squad.position.Y)
				squad.position = Vector3.new(newPosition.X, y, newPosition.Z)
				squad.moveYaw = MathUtil.yawFromDirection(direction)
				moving = true
				-- Charge build-up: sustained speed arms the charge bonus
				if def.chargeMultiplier > 1 and speed >= def.moveSpeed * Combat.ChargeSpeedFraction then
					squad.movingTime += dt
					if squad.movingTime >= Combat.ChargeBuildTime then
						squad.chargeReadyUntil = now + Combat.ChargeGrace
					end
				end
			end
		end
	end
	if not moving then
		squad.movingTime = 0
	end
	squad.isMoving = moving

	local desired = if moving
		then squad.moveYaw
		elseif now < squad.combatYawUntil then squad.combatYaw
		else squad.idleYaw
	local turnSpeed = if def.attackType == "Artillery" then Combat.ArtilleryTurnSpeed else Combat.TurnSpeed
	local newYaw = MathUtil.turnTowards(squad.yaw, desired, turnSpeed * dt)
	squad.yaw = newYaw
end

---------------------------------------------------------------------------
-- Main loop
---------------------------------------------------------------------------

function SquadService.update(dt: number)
	if paused then
		return
	end
	local now = time()
	for _, squad in squadList do
		stepMovement(squad, dt, now)
	end
	-- friendly squads don't stack on top of each other: overlapping ones drift apart
	for i, a in squadList do
		for j = i + 1, #squadList do
			local b = squadList[j]
			if a.team == b.team then
				local offset = MathUtil.flat(a.position - b.position)
				local distance = offset.Magnitude
				local minimum = (a.radius + b.radius) * 0.85
				if distance < minimum then
					local push = (if distance > 0.01 then offset / distance else Vector3.new(1, 0, 0))
						* math.min(minimum - distance, 6 * dt)
					a.position += push
					b.position -= push
				end
			end
		end
	end

	combatTimer += dt
	if combatTimer < Combat.TickInterval then
		return
	end
	local tickDt = combatTimer
	combatTimer = 0
	local heroes = SquadService.hooks.getHeroes()
	-- Iterate over a copy: squads can be destroyed during the tick
	for _, squad in table.clone(squadList) do
		if squad.alive then
			updateMorale(squad, tickDt, now, heroes)
			if squad.alive and not squad.routing and now >= squad.formingUntil and not pierce(squad, now) then
				local target = findTarget(squad, heroes)
				if target then
					attemptAttack(squad, target, now)
				end
			end
			if squad.alive then
				updateState(squad, now)
			end
		end
	end
end

function SquadService.setPaused(value: boolean)
	paused = value
end

-- Compact state for clients (soldier rendering, HUD, minimap). Never trusted back from the client.
function SquadService.snapshot(): { any }
	local now = time()
	local out = table.create(#squadList)
	for _, squad in squadList do
		table.insert(out, {
			id = squad.id,
			team = squad.team,
			unitId = squad.unitId,
			name = squad.name,
			ownerId = if squad.owner then squad.owner.UserId else 0,
			hp = squad.health / squad.maxHealth,
			morale = squad.morale / squad.maxMorale,
			state = squad.state,
			formation = squad.formation,
			order = squad.order,
			forming = if now < squad.formingUntil
				then (now - squad.formingStarted) / (squad.formingUntil - squad.formingStarted)
				else nil,
			x = squad.position.X,
			y = squad.position.Y,
			z = squad.position.Z,
			yaw = squad.yaw,
			soldiers = squad.soldierCount,
			radius = squad.radius,
			moving = squad.isMoving,
			rushing = squad.rushing,
			charging = now < squad.chargeReadyUntil,
			controlled = squad.isPlayerControlled,
			commander = squad.commanderAlive,
			commanderName = squad.commanderName,
			rank = squad.rank,
			tier = squad.def.tier,
		})
	end
	return out
end

function SquadService.remove(squad: Squad)
	if squad.alive then
		squad.alive = false
		removeFromList(squad)
	end
end

function SquadService.removeOwnedBy(player: Player)
	for _, squad in SquadService.getOwnedBy(player) do
		SquadService.remove(squad)
	end
end

function SquadService.clearAll()
	for _, squad in table.clone(squadList) do
		SquadService.remove(squad)
	end
end

return SquadService
