--[[
	SoldierService
	Every soldier is a unit of its own (Mount & Blade style): his own position, HP, facing,
	enemy and attack timer, simulated here every GameConfig.Soldiers.TickInterval.
	A squad is the GROUP the soldiers belong to (SquadService): it takes the orders, has a
	formation anchor (squad.position) and facing (squad.yaw) and one morale.

	  • Formation: each man walks to his own loose spot around the anchor ("good enough": he
	    doesn't shuffle once he's close). The formation only turns when the group moves or is
	    given a facing, never to stare at an enemy; single men turn to face their foe / target.
	  • Melee: a man picks an enemy soldier near him (at most MaxAttackersPerFoe on the same
	    man, so the fight spreads along the front), walks up and swings on his own timer.
	    Line infantry only fight what comes close unless the group charges; archers, skirmishers
	    and gun crews only defend themselves.
	  • Shooting: each shooter fires on his own reload at a man of the group's target; arrows
	    and balls take time to land (arrows fly in a visible arc, see VFX "Shots").
	  • Cavalry: a rider moving fast has his charge armed (first hit ×chargeMultiplier);
	    rushing riders also hit every man they ride through.
	Damage goes through SquadService.applyDamage (formation / flank / morale rules) with
	info.soldier = the man hit.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local FormationDefinitions = require(Modules:WaitForChild("FormationDefinitions"))
local GameConfig = require(Modules:WaitForChild("GameConfig"))
local MathUtil = require(Modules:WaitForChild("MathUtil"))
local UnitDefinitions = require(Modules:WaitForChild("UnitDefinitions"))

local MapService = require(script.Parent:WaitForChild("MapService"))

local S = GameConfig.Soldiers
local Combat = GameConfig.Combat
local Morale = GameConfig.Morale

local SoldierService = {}

-- Wired by SquadService (avoids a circular require)
SoldierService.api = {
	applyDamage = function(_squad: any, _amount: number, _info: any): number
		return 0
	end,
	damageHero = function(_player: Player, _amount: number, _from: Vector3, _kind: string) end,
	accuracy = function(_squad: any, _now: number): number
		return 1
	end,
	-- damage multipliers of the attacking group (damageMult, high ground, random roll…)
	meleeMult = function(_squad: any, _targetPosition: Vector3): number
		return 1
	end,
	rangedMult = function(_squad: any, _targetPosition: Vector3): number
		return 1
	end,
	chargeImpact = function(_squad: any, _position: Vector3, _targetSquad: any) end,
	shots = function(_list: { any }) end, -- VFX batch
}

local CELL = 8
local grid: { [number]: { any } } = {}
local pendingShots: { any } = {}
local shotBatch: { any } = {}

local function cellKey(cx: number, cz: number): number
	return cx * 100003 + cz
end

local function flatDistance(a: Vector3, b: Vector3): number
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

---------------------------------------------------------------------------
-- Creation / formation spots
---------------------------------------------------------------------------

local function newSoldier(squad: any, hp: number): any
	squad.nextSid += 1
	return {
		sid = squad.nextSid,
		squad = squad,
		team = squad.team,
		pos = squad.position,
		yaw = squad.yaw,
		hp = hp,
		maxHp = hp,
		alive = true,
		noise = Vector3.new(math.random() - 0.5, 0, math.random() - 0.5) * 2 * S.SlotNoise,
		idleYaw = (math.random() - 0.5) * 0.35,
		speedJitter = 0.9 + math.random() * 0.2,
		attackers = 0,
		foe = nil,
		nextSwing = 0,
		nextShot = 0,
		swingUntil = 0,
		hitUntil = 0,
		chargeUntil = 0,
		fastTime = 0,
		speed = 0,
	}
end

-- Recompute the formation spots when the formation or the headcount changed
function SoldierService.refreshSlots(squad: any)
	local count = #squad.soldiers
	local key = squad.formation .. ":" .. count
	if squad.slotsKey == key then
		return
	end
	squad.slotsKey = key
	local slots =
		FormationDefinitions.layout(squad.formation, count, (squad.def.spacingMult or 1) * S.FormationLooseness)
	if squad.def.attackType == "Artillery" then
		for i, slot in slots do
			slots[i] = slot + Vector3.new(0, 0, 2) -- the crew stands behind the gun
		end
	end
	squad.slots = slots
end

local function spotOf(squad: any, index: number, soldier: any, rotation: CFrame): Vector3
	local slot = (squad.slots[index] or Vector3.zero) + soldier.noise
	return squad.position + rotation:VectorToWorldSpace(slot)
end

-- Fill a new squad with `count` men standing in formation
function SoldierService.populate(squad: any, count: number)
	squad.soldiers = {}
	squad.nextSid = 0
	local hp = squad.maxHealth / squad.def.soldiers
	for _ = 1, count do
		table.insert(squad.soldiers, newSoldier(squad, hp))
	end
	SoldierService.refreshSlots(squad)
	local rotation = CFrame.Angles(0, squad.yaw, 0)
	for i, soldier in squad.soldiers do
		soldier.pos = spotOf(squad, i, soldier, rotation)
	end
	squad.health = hp * count
end

-- A man died: out of the group (the others close ranks)
function SoldierService.kill(squad: any, soldier: any)
	soldier.alive = false
	soldier.hp = 0
	local index = table.find(squad.soldiers, soldier)
	if index then
		table.remove(squad.soldiers, index)
	end
end

-- Men nearest to `from` first (damage without a specific victim lands on the nearest men)
function SoldierService.nearest(squad: any, from: Vector3?): { any }
	local list = table.clone(squad.soldiers)
	if from then
		table.sort(list, function(a, b)
			return flatDistance(a.pos, from) < flatDistance(b.pos, from)
		end)
	end
	return list
end

---------------------------------------------------------------------------
-- Spatial grid
---------------------------------------------------------------------------

local function rebuildGrid(squads: { any })
	table.clear(grid)
	for _, squad in squads do
		if squad.alive then
			for _, soldier in squad.soldiers do
				soldier.attackers = 0
				local key = cellKey(math.floor(soldier.pos.X / CELL), math.floor(soldier.pos.Z / CELL))
				local cell = grid[key]
				if not cell then
					cell = {}
					grid[key] = cell
				end
				table.insert(cell, soldier)
			end
		end
	end
	-- how many men already go for each man
	for _, squad in squads do
		if squad.alive then
			for _, soldier in squad.soldiers do
				local foe = soldier.foe
				if foe and foe.alive then
					foe.attackers += 1
				end
			end
		end
	end
end

local function forEachNear(position: Vector3, radius: number, fn: (any) -> ())
	local x0, x1 = math.floor((position.X - radius) / CELL), math.floor((position.X + radius) / CELL)
	local z0, z1 = math.floor((position.Z - radius) / CELL), math.floor((position.Z + radius) / CELL)
	for cx = x0, x1 do
		for cz = z0, z1 do
			local cell = grid[cellKey(cx, cz)]
			if cell then
				for _, other in cell do
					fn(other)
				end
			end
		end
	end
end

---------------------------------------------------------------------------
-- Fighting
---------------------------------------------------------------------------

-- The enemy man this soldier goes for: close, near his spot (leash), not already swamped
local function findFoe(soldier: any, radius: number, spot: Vector3, leash: number, heroes: { any }): any
	local best, bestScore = nil, math.huge
	forEachNear(soldier.pos, radius, function(other)
		if other.team ~= soldier.team and other.alive then
			local d = flatDistance(soldier.pos, other.pos)
			if d <= radius and flatDistance(spot, other.pos) <= leash then
				local score = d + other.attackers * 5
				if other.attackers >= S.MaxAttackersPerFoe then
					score += 1000 -- only if nobody else is free
				end
				if score < bestScore then
					best, bestScore = other, score
				end
			end
		end
	end)
	if soldier.team == "Red" then
		for _, hero in heroes do
			local d = flatDistance(soldier.pos, hero.pos)
			if d <= radius and d < bestScore then
				best, bestScore = hero, d
			end
		end
	end
	return best
end

local function swing(squad: any, soldier: any, foe: any, now: number)
	local def = squad.def
	soldier.nextSwing = now + def.meleeCooldown * (0.85 + math.random() * 0.3)
	soldier.swingUntil = now + 0.5
	squad.inCombatUntil = now + Morale.CombatCooldown
	local damage = def.meleeDamage
		/ def.soldiers
		/ S.MeleeHitChance
		* S.MeleeDamageMult
		* SoldierService.api.meleeMult(squad, foe.pos)
	local kind = "Melee"
	if def.chargeMultiplier > 1 and now < soldier.chargeUntil then
		-- armed charge: the first hit lands hard, then he must build speed again
		damage *= def.chargeMultiplier
		kind = "Charge"
		soldier.chargeUntil = 0
		soldier.fastTime = 0
		squad.lastChargeAt = now
		if now - (squad.lastImpactVfx or 0) > 0.6 then
			squad.lastImpactVfx = now
			SoldierService.api.chargeImpact(squad, foe.pos, foe.squad)
		end
	elseif math.random() > S.MeleeHitChance then
		return -- parried / missed
	end
	if foe.hero then
		SoldierService.api.damageHero(
			foe.player,
			damage * GameConfig.Hero.DamageTakenFromSquadsMult,
			soldier.pos,
			if kind == "Charge" then "Charge" else "Melee"
		)
		return
	end
	SoldierService.api.applyDamage(foe.squad, damage, {
		kind = kind,
		fromPosition = soldier.pos,
		attackerTeam = squad.team,
		attacker = squad,
		soldier = foe,
	})
end

-- One of the few men of `target` nearest to the shooter
local function pickVictim(target: any, from: Vector3): any
	local first, second, third = nil, nil, nil
	local d1, d2, d3 = math.huge, math.huge, math.huge
	for _, soldier in target.soldiers do
		local d = flatDistance(soldier.pos, from)
		if d < d1 then
			third, d3, second, d2 = second, d2, first, d1
			first, d1 = soldier, d
		elseif d < d2 then
			third, d3 = second, d2
			second, d2 = soldier, d
		elseif d < d3 then
			third, d3 = soldier, d
		end
	end
	local options = { first, second, third }
	local count = if third then 3 elseif second then 2 elseif first then 1 else 0
	return if count > 0 then options[math.random(1, count)] else nil
end

local function shoot(squad: any, soldier: any, target: any, now: number)
	local def = squad.def
	local victim, aim
	if target.kind == "Squad" then
		if not target.squad.alive then
			return
		end
		victim = pickVictim(target.squad, soldier.pos)
		aim = victim and victim.pos
	elseif target.kind == "Hero" then
		victim = { hero = true, player = target.player }
		aim = target.position
	end
	if not victim or not aim then
		return
	end
	local distance = flatDistance(soldier.pos, aim)
	if distance > def.attackRange then
		soldier.nextShot = now + 0.4 -- out of reach from where he stands: try again soon
		return
	end
	soldier.nextShot = now + def.attackCooldown * (0.85 + math.random() * 0.3)
	squad.inCombatUntil = now + Morale.CombatCooldown
	local chance = SoldierService.api.accuracy(squad, now)
		* (1 - (1 - S.ShotHitAtMaxRange) * math.clamp(distance / def.attackRange, 0, 1))
	local hit = math.random() < chance
	local projectile = UnitDefinitions.projectile(def)
	local speed = if projectile == "Arrow" then S.ArrowSpeed else S.BulletSpeed
	local flight = distance / speed
	local landing = aim
	if not hit then
		local angle = math.random() * math.pi * 2
		landing = aim + Vector3.new(math.cos(angle), 0, math.sin(angle)) * (1.5 + math.random() * 4)
	end
	table.insert(pendingShots, {
		at = now + flight,
		hit = hit,
		victim = victim,
		from = soldier.pos,
		attacker = squad,
		team = squad.team,
		damage = def.damage / def.soldiers * S.RangedDamageMult * SoldierService.api.rangedMult(squad, aim),
	})
	table.insert(shotBatch, {
		s = squad.id,
		i = soldier.sid,
		x = landing.X,
		y = landing.Y,
		z = landing.Z,
		t = flight,
		a = projectile == "Arrow",
	})
	soldier.yaw = MathUtil.yawFromDirection(MathUtil.flat(aim - soldier.pos))
end

local function landShots(now: number)
	for i = #pendingShots, 1, -1 do
		local shot = pendingShots[i]
		if now >= shot.at then
			table.remove(pendingShots, i)
			if shot.hit then
				local victim = shot.victim
				if victim.hero then
					SoldierService.api.damageHero(
						victim.player,
						shot.damage * GameConfig.Hero.DamageTakenFromSquadsMult,
						shot.from,
						"Ranged"
					)
				elseif victim.alive and victim.squad.alive then
					SoldierService.api.applyDamage(victim.squad, shot.damage, {
						kind = "Ranged",
						fromPosition = shot.from,
						attackerTeam = shot.team,
						attacker = if shot.attacker.alive then shot.attacker else nil,
						soldier = victim,
					})
				end
			end
		end
	end
end

-- Rushing riders hit every man they gallop through (once each)
local function pierce(squad: any, soldier: any)
	local def = squad.def
	soldier.pierced = soldier.pierced or {}
	forEachNear(soldier.pos, S.PierceRadius, function(other)
		if
			other.team ~= soldier.team
			and other.alive
			and not soldier.pierced[other]
			and flatDistance(other.pos, soldier.pos) <= S.PierceRadius
		then
			soldier.pierced[other] = true
			local damage = def.meleeDamage
				/ def.soldiers
				* def.chargeMultiplier
				* S.MeleeDamageMult
				* GameConfig.Orders.RushPierceMult
				* SoldierService.api.meleeMult(squad, other.pos)
			SoldierService.api.applyDamage(other.squad, damage, {
				kind = "Charge",
				fromPosition = soldier.pos,
				attackerTeam = squad.team,
				attacker = squad,
				soldier = other,
			})
		end
	end)
end

---------------------------------------------------------------------------
-- Per-group step
---------------------------------------------------------------------------

local function stepSquad(squad: any, heroes: { any }, dt: number, now: number)
	local def = squad.def
	if #squad.soldiers == 0 then
		return
	end
	SoldierService.refreshSlots(squad)
	local rotation = CFrame.Angles(0, squad.yaw, 0)
	local cavalry = def.visual == "Cavalry"
	local artillery = def.attackType == "Artillery"
	local archer = UnitDefinitions.isArcher(def)
	local routing = squad.routing
	local forming = now < squad.formingUntil
	local engageRadius = if routing
		then 0
		elseif artillery or archer then S.SelfDefenseRadius
		elseif squad.meleeCommitted then S.ChargeEngageRadius
		elseif def.attackType == "Melee" then S.EngageRadius
		else S.LineEngageRadius
	local leash = if squad.meleeCommitted then S.ChargeLeash else S.ChaseLeash
	local reach = if cavalry then 4.2 else S.MeleeReach
	local space = S.PersonalSpace * (if cavalry then 1.8 else 1)
	local baseSpeed = squad.moveSpeedNow or def.moveSpeed
	local target = squad.fireTarget
	local canShoot = def.attackType == "Ranged"
		and target ~= nil
		and not forming
		and not routing
		and (not squad.isMoving or def.canMoveAndFire)
	local piercing = cavalry and squad.rushing and squad.rushTarget ~= nil

	for i, soldier in squad.soldiers do
		local spot = spotOf(squad, i, soldier, rotation)
		local goal = spot
		local face: Vector3? = nil

		-- 1) his enemy: keep him while he's close, else look for one
		local foe = soldier.foe
		if
			foe
			and (
				not foe.alive
				or routing
				or engageRadius == 0
				or flatDistance(foe.pos, soldier.pos) > engageRadius * 1.8 + reach
			)
		then
			soldier.foe = nil
			foe = nil
		end
		if not foe and engageRadius > 0 and not piercing then
			foe = findFoe(soldier, engageRadius, spot, leash, heroes)
			if foe then
				soldier.foe = foe
				foe.attackers += 1
			end
		end

		-- 2) fight, shoot, or stand in the formation
		local tolerance = S.SlotTolerance
		if foe then
			local offset = MathUtil.flat(soldier.pos - foe.pos)
			local d = offset.Magnitude
			face = foe.pos
			tolerance = 0.3
			if d <= reach + 0.4 then
				goal = soldier.pos
			else
				goal = foe.pos + (if d > 0.01 then offset / d else Vector3.xAxis) * reach * 0.85
			end
			if d <= reach + 0.8 and now >= soldier.nextSwing and not forming then
				swing(squad, soldier, foe, now)
			end
		elseif canShoot and target then
			face = target.position
			if now >= soldier.nextShot then
				shoot(squad, soldier, target, now)
			end
		end
		if soldier.detour and now < soldier.detourUntil and flatDistance(soldier.pos, soldier.detour) > 2 then
			goal = soldier.detour
		end

		-- 3) walk (own pace; faster when far from his spot)
		local toGoal = MathUtil.flat(goal - soldier.pos)
		local d = toGoal.Magnitude
		local velocity = Vector3.zero
		if d > tolerance then
			local speed = baseSpeed * soldier.speedJitter * (if d > 4 then S.CatchUpMult else 1)
			if foe then
				speed = math.max(speed, def.moveSpeed * 0.9)
			end
			velocity = toGoal / d * math.min(speed, d / dt)
		end
		-- personal space (friends and foes alike: lines don't walk through each other)
		local push = Vector3.zero
		forEachNear(soldier.pos, space, function(other)
			if other ~= soldier and other.alive then
				local offset = MathUtil.flat(soldier.pos - other.pos)
				local distance = offset.Magnitude
				local minimum = if other.squad.def.visual == "Cavalry" or cavalry then space * 1.2 else space
				if distance < minimum then
					local away = if distance > 0.01
						then offset / distance
						else Vector3.new(math.random() - 0.5, 0, math.random() - 0.5).Unit
					push += away * (minimum - distance) * 5
				end
			end
		end)
		local newPosition = soldier.pos + (velocity + push) * dt
		if #MapService.walls > 0 then
			local blocked, _, wall, along = MapService.crossing(soldier.pos, newPosition)
			if blocked then
				if blocked == "Wall" then
					soldier.detour = MapService.detour(wall, along, soldier.pos)
					soldier.detourUntil = now + 8
				end
				newPosition = soldier.pos
			end
		end
		local moved = MathUtil.flat(newPosition - soldier.pos).Magnitude
		soldier.speed = moved / dt
		soldier.pos = Vector3.new(newPosition.X, squad.position.Y, newPosition.Z)

		-- 4) charge build-up (riders, and brawlers with a charge bonus)
		if def.chargeMultiplier > 1 then
			if soldier.speed >= def.moveSpeed * Combat.ChargeSpeedFraction then
				soldier.fastTime += dt
				if soldier.fastTime >= Combat.ChargeBuildTime then
					soldier.chargeUntil = now + Combat.ChargeGrace
				end
			else
				soldier.fastTime = math.max(0, soldier.fastTime - dt * 2)
			end
		end
		if piercing and soldier.speed > def.moveSpeed * 0.8 then
			pierce(squad, soldier)
		elseif not squad.rushing then
			soldier.pierced = nil
		end

		-- 5) facing: his foe / target, where he walks, else the formation's front
		local desiredYaw
		if face then
			local toFace = MathUtil.flat(face - soldier.pos)
			desiredYaw = if toFace.Magnitude > 0.1 then MathUtil.yawFromDirection(toFace) else soldier.yaw
		elseif soldier.speed > 1.5 then
			desiredYaw = MathUtil.yawFromDirection(velocity + push)
		else
			desiredYaw = squad.yaw + soldier.idleYaw
		end
		soldier.yaw = MathUtil.turnTowards(soldier.yaw, desiredYaw, 7 * dt)
	end
end

--[[
	One simulation step for every soldier. `heroes` = { { player, position } } (the Blue
	commanders: Red soldiers fight them too).
]]
function SoldierService.tick(squads: { any }, heroes: { any }, dt: number, now: number)
	rebuildGrid(squads)
	local heroFoes = {}
	for _, hero in heroes do
		table.insert(heroFoes, { hero = true, player = hero.player, pos = hero.position, alive = true, attackers = 0 })
	end
	for _, squad in table.clone(squads) do
		if squad.alive then
			stepSquad(squad, heroFoes, dt, now)
		end
	end
	landShots(now)
	if #shotBatch > 0 then
		SoldierService.api.shots(shotBatch)
		shotBatch = {}
	end
end

function SoldierService.clearShots()
	table.clear(pendingShots)
	table.clear(shotBatch)
end

--[[
	Network: 8 bytes per living man
	  u16 sid · i16 x×8 · i16 z×8 · u8 yaw (0-255 = 0-2π) · u8 flags
	  flags: 1 swinging · 2 hit just now · 4 charge armed
]]
function SoldierService.pack(squad: any, now: number): buffer
	local list = squad.soldiers
	local data = buffer.create(#list * 8)
	for i, soldier in list do
		local offset = (i - 1) * 8
		buffer.writeu16(data, offset, soldier.sid % 65536)
		buffer.writei16(data, offset + 2, math.clamp(math.floor(soldier.pos.X * 8 + 0.5), -32768, 32767))
		buffer.writei16(data, offset + 4, math.clamp(math.floor(soldier.pos.Z * 8 + 0.5), -32768, 32767))
		buffer.writeu8(data, offset + 6, math.floor((soldier.yaw % (2 * math.pi)) / (2 * math.pi) * 256) % 256)
		local flags = 0
		if now < soldier.swingUntil then
			flags += 1
		end
		if now < soldier.hitUntil then
			flags += 2
		end
		if now < soldier.chargeUntil then
			flags += 4
		end
		buffer.writeu8(data, offset + 7, flags)
	end
	return data
end

return SoldierService
