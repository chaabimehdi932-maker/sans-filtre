--[[
	BattlePlan
	One shared plan per side, so the AI fights as an army instead of a crowd of loners.
	Every AI squad of a side (the enemy, your allies, your companion-led squads) gets a slot:

	            cavalry   [melee] [melee]              cavalry        ← front (towards the enemy)
	             (flank)  [line ] [line ] [line ]      (flank)
	                         [guns]    [guns]                         ← behind

	  • the line advances TOGETHER: the plan's centre moves at the pace of the slowest line
	    squad and waits while squads lag behind their slots (nobody runs ahead)
	  • it halts at musket range from the enemy (or on the objective) and the line fires
	  • squads keep their left-to-right order, so slots never cross
	  • when a squad is caught in a melee, idle neighbours nearby move up to support it
	The plan is recomputed twice a second (GameConfig.AI.Plan). SquadAI reads it.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local GameConfig = require(Modules:WaitForChild("GameConfig"))
local MathUtil = require(Modules:WaitForChild("MathUtil"))

local ZoneService = require(script.Parent:WaitForChild("ZoneService"))

local Plan = GameConfig.AI.Plan

local BattlePlan = {}

local plans: { [string]: any } = {}

local function role(squad: any): string
	local def = squad.def
	if def.visual == "Cavalry" then
		return "Cavalry"
	elseif def.attackType == "Artillery" then
		return "Artillery"
	elseif def.attackType == "Melee" then
		return "Melee"
	end
	return "Line"
end
BattlePlan.role = role

local function centroid(list: { any }): Vector3?
	if #list == 0 then
		return nil
	end
	local sum = Vector3.zero
	for _, squad in list do
		sum += squad.position
	end
	return sum / #list
end

-- The spot the side is heading for: an objective it doesn't hold, else the enemy army
local function objective(team: string, enemies: { any }, from: Vector3): (Vector3?, boolean)
	local zones = ZoneService.getZones()
	local best, bestDistance = nil, math.huge
	local holdsAll = #zones > 0
	for _, zone in zones do
		if zone.owner ~= team or zone.contested then
			holdsAll = false
			local d = MathUtil.flatDistance(zone.position, from)
			if d < bestDistance then
				best, bestDistance = zone.position, d
			end
		end
	end
	if best then
		return best, false
	end
	if holdsAll then
		return centroid(enemies), true -- defend: face them, don't march off the zones
	end
	return centroid(enemies), false
end

local function isEngaged(squad: any, enemies: { any }, now: number): boolean
	if now >= squad.inCombatUntil then
		return false
	end
	for _, enemy in enemies do
		local edge = MathUtil.flatDistance(enemy.position, squad.position) - squad.radius - enemy.radius
		if edge <= 12 then
			return true
		end
	end
	return false
end

--[[
	Rebuild a side's plan. `squads` = its living, non-routing squads; only the AI-run ones
	(not under the player's direct command) are placed in the line.
]]
function BattlePlan.update(team: string, squads: { any }, enemies: { any }, dt: number, now: number)
	local ai = {}
	for _, squad in squads do
		if not squad.isPlayerControlled then
			table.insert(ai, squad)
		end
	end
	local plan = plans[team]
	if #ai == 0 then
		plans[team] = nil
		return
	end
	local here = centroid(ai) :: Vector3
	if not plan then
		plan = { center = here, yaw = ai[1].yaw, slots = {}, engaged = {}, lastUpdate = now }
		plans[team] = plan
	end

	local target, defending = objective(team, enemies, plan.center)
	local forward = MathUtil.lookFromYaw(plan.yaw)
	if target then
		local toTarget = MathUtil.flat(target - plan.center)
		if toTarget.Magnitude > 1 then
			forward = toTarget.Unit
			plan.yaw = MathUtil.yawFromDirection(forward)
		end
	end
	local right = MathUtil.rightFromYaw(plan.yaw)

	-- who is where: keep the left-to-right order so slots never cross
	local line, melee, guns, cavalry = {}, {}, {}, {}
	for _, squad in ai do
		local kind = role(squad)
		if kind == "Cavalry" then
			table.insert(cavalry, squad)
		elseif kind == "Artillery" then
			table.insert(guns, squad)
		elseif kind == "Melee" then
			table.insert(melee, squad)
		else
			table.insert(line, squad)
		end
	end
	local function byLateral(a: any, b: any): boolean
		return (a.position - plan.center):Dot(right) < (b.position - plan.center):Dot(right)
	end
	for _, list in { line, melee, guns, cavalry } do
		table.sort(list, byLateral)
	end

	local slots = {}
	local function row(list: { any }, depth: number): number
		local widths, total = {}, 0
		for i, squad in list do
			widths[i] = math.max(squad.radius * 2, 20) + Plan.SquadGap
			total += widths[i]
		end
		local cursor = -total / 2
		for i, squad in list do
			slots[squad] = plan.center + right * (cursor + widths[i] / 2) + forward * depth
			cursor += widths[i]
		end
		return total / 2
	end
	local halfWidth = row(line, 0)
	halfWidth = math.max(halfWidth, row(melee, Plan.MeleeDepth))
	row(guns, Plan.ArtilleryDepth)
	for i, squad in cavalry do
		local side = if i % 2 == 1 then -1 else 1
		local rank = math.floor((i - 1) / 2)
		slots[squad] = plan.center
			+ right * side * (halfWidth + Plan.CavalryFlankGap + rank * 28)
			+ forward * Plan.CavalryDepth
	end
	plan.slots = slots

	-- engaged squads (for support)
	local engaged = {}
	for _, squad in ai do
		if isEngaged(squad, enemies, now) then
			table.insert(engaged, squad)
		end
	end
	plan.engaged = engaged

	-- advance together: only when nobody lags, at the pace of the slowest line squad,
	-- and halt at musket range / on the objective
	local lag = 0
	local slowest = math.huge
	local shortestRange = math.huge
	for _, squad in ai do
		local kind = role(squad)
		if kind == "Line" or kind == "Melee" then
			local slot = slots[squad]
			lag = math.max(lag, MathUtil.flatDistance(squad.position, slot))
			slowest = math.min(slowest, squad.def.moveSpeed)
			if kind == "Line" then
				shortestRange = math.min(shortestRange, squad.def.attackRange)
			end
		end
	end
	if slowest == math.huge then
		slowest = 10
	end
	if shortestRange == math.huge then
		shortestRange = 60
	end
	local nearestEnemy = math.huge
	for _, enemy in enemies do
		nearestEnemy = math.min(nearestEnemy, MathUtil.flatDistance(enemy.position, plan.center))
	end
	local halt = nearestEnemy <= shortestRange * Plan.StandoffFraction + halfWidth * 0.2
		or (target ~= nil and MathUtil.flatDistance(target, plan.center) < 6)
		or defending
		or lag > Plan.LagTolerance
	plan.halted = halt
	if not halt and target then
		local step = slowest * Plan.AdvanceSpeedMult * dt
		plan.center += forward * math.min(step, MathUtil.flatDistance(target, plan.center))
	end
	-- never let the plan drift far from where the army really is
	if MathUtil.flatDistance(plan.center, here) > 60 then
		plan.center = here + MathUtil.flat(plan.center - here).Unit * 60
	end
end

function BattlePlan.get(team: string): any
	return plans[team]
end

-- An engaged friend close enough to deserve help (nil if none)
function BattlePlan.supportTarget(squad: any): any
	local plan = plans[squad.team]
	if not plan then
		return nil
	end
	local best, bestDistance = nil, Plan.SupportRadius
	for _, other in plan.engaged do
		if other ~= squad then
			local distance = MathUtil.flatDistance(other.position, squad.position)
			if distance < bestDistance then
				best, bestDistance = other, distance
			end
		end
	end
	return best
end

function BattlePlan.reset()
	table.clear(plans)
end

return BattlePlan
