--[[
	CommandService
	You command every squad of your own army directly (squad.isPlayerControlled = true) —
	except a squad led by one of your companions: that one fights on its own under him (ally
	AI). In a general's army you only command your own squad; his run on their AI.
	(Reputation no longer limits this: it's kept for contract rewards and unlocks.)

	The SELECTION is the subset of your squads that receives the X Hold · C Follow · V Attack ·
	B Rush · T Fire-at orders.
	  Rush   aimed point (or an enemy squad under the cursor): sprint there at 2×, crash into it
	  FireAt an enemy squad: shooters and guns target it (walking into range if needed), melee
	         squads attack it. A spot on the ground: guns bombard it, shooters take the enemy
	         nearest to it. Unselected squads keep carrying out their last order.
	SelectSquad remote:
	  id             select only that squad            (click a card, or a number key 1-9)
	  "next"/"prev"  select only the next/prev squad   (Tab / Shift+Tab)
	  "all"          select every squad you command    (0)
	  { pin = id }   add/remove a squad to the selection (Shift + click / Shift + number)
	Published in player attributes: "ControlledSquad" (first selected id), "ControlledSquads"
	("3,5,8" = selection) and "CommandedSquads" (every squad you command).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local FormationDefinitions = require(Modules:WaitForChild("FormationDefinitions"))
local GameConfig = require(Modules:WaitForChild("GameConfig"))
local MathUtil = require(Modules:WaitForChild("MathUtil"))
local Remotes = require(Modules:WaitForChild("Remotes"))

local UnitDefinitions = require(Modules:WaitForChild("UnitDefinitions"))

local SquadService = require(script.Parent:WaitForChild("SquadService"))
local ZoneService = require(script.Parent:WaitForChild("ZoneService"))

local Orders = GameConfig.Orders

local CommandService = {}

CommandService.hooks = {
	notify = function(_player: Player, _text: string, _tone: string) end,
}

local VALID_ORDERS = { Hold = true, Follow = true, Attack = true, Rush = true, FireAt = true }

local commanded: { [Player]: { any } } = {} -- every squad the player commands
local selections: { [Player]: { any } } = {} -- the ones receiving orders

-- Reset the per-order state so the squad starts clean under its new controller
local function clearOrderState(squad: any)
	squad.rushTarget = nil
	squad.rushEnemy = nil
	squad.focusTarget = nil
	squad.firePoint = nil
	squad.preferredTarget = nil
	squad.holdPosition = nil
	squad.pendingFormation = nil
	squad.rushing = false
	squad.speedMult = 1
end

local function alive(list: { any }?): { any }
	local out = {}
	for _, squad in (list or {}) :: { any } do
		if squad.alive then
			table.insert(out, squad)
		end
	end
	return out
end

-- Living squads the player commands directly (roster order)
function CommandService.getCommanded(player: Player): { any }
	return alive(commanded[player])
end

-- Living selected squads (first = the "main" one)
function CommandService.getControlledList(player: Player): { any }
	return alive(selections[player])
end

function CommandService.getControlled(player: Player): any
	return CommandService.getControlledList(player)[1]
end

local function publish(player: Player)
	local function ids(list: { any }): string
		local out = {}
		for _, squad in list do
			table.insert(out, tostring(squad.id))
		end
		return table.concat(out, ",")
	end
	local selection = CommandService.getControlledList(player)
	player:SetAttribute("ControlledSquad", if selection[1] then selection[1].id else 0)
	player:SetAttribute("ControlledSquads", ids(selection))
	player:SetAttribute("CommandedSquads", ids(CommandService.getCommanded(player)))
end

local function takeCommand(squad: any)
	squad.isPlayerControlled = true
	clearOrderState(squad)
	squad.order = "Hold"
	squad.holdYaw = squad.yaw
	squad.idleYaw = squad.yaw
	SquadService.stop(squad)
end

--[[
	Start of a battle: the player takes command of these squads (companion-led squads are
	skipped: they fight on their own). Everything is selected at first.
]]
function CommandService.takeArmy(player: Player, squads: { any })
	for _, squad in (commanded[player] or {}) :: { any } do
		if squad.alive then
			squad.isPlayerControlled = false
		end
	end
	local list = {}
	for _, squad in squads do
		if squad.alive and not squad.companionId then
			takeCommand(squad)
			table.insert(list, squad)
		end
	end
	commanded[player] = list
	selections[player] = table.clone(list)
	publish(player)
end

-- A squad joins the player's command mid-battle (reinforcements) and is selected alone
function CommandService.addToArmy(player: Player, squad: any)
	commanded[player] = commanded[player] or {}
	if squad.alive and not table.find(commanded[player], squad) then
		takeCommand(squad)
		table.insert(commanded[player], squad)
	end
	CommandService.setControlled(player, squad)
end

-- Select exactly these squads (only ones the player commands)
function CommandService.setGroup(player: Player, squads: { any })
	local own = CommandService.getCommanded(player)
	local wanted = {}
	for _, squad in squads do
		if table.find(own, squad) and not table.find(wanted, squad) then
			table.insert(wanted, squad)
		end
	end
	selections[player] = wanted
	publish(player)
end

function CommandService.setControlled(player: Player, squad: any)
	CommandService.setGroup(player, if squad then { squad } else {})
end

function CommandService.togglePin(player: Player, squad: any)
	local list = CommandService.getControlledList(player)
	local index = table.find(list, squad)
	if index then
		if #list > 1 then
			table.remove(list, index)
		end
	else
		table.insert(list, squad)
	end
	CommandService.setGroup(player, list)
end

-- Keep a living selection (e.g. after the selected squad was destroyed)
function CommandService.ensureControlled(player: Player)
	if #CommandService.getControlledList(player) == 0 then
		local own = CommandService.getCommanded(player)
		CommandService.setGroup(player, if own[1] then { own[1] } else {})
	else
		publish(player)
	end
end

-- Rush is on a cooldown so it cannot be spammed
local lastRushAt: { [Player]: number } = {}
local feedbackRemote = Remotes.get("CombatFeedback")

function CommandService.removePlayer(player: Player)
	commanded[player] = nil
	selections[player] = nil
	lastRushAt[player] = nil
end

Remotes.get("SelectSquad").OnServerEvent:Connect(function(player: Player, which: unknown)
	local own = CommandService.getCommanded(player)
	if #own == 0 then
		return
	end
	if typeof(which) == "number" then
		local squad = SquadService.getById(which)
		if squad and table.find(own, squad) then
			CommandService.setControlled(player, squad)
		end
	elseif which == "all" then
		CommandService.setGroup(player, own)
	elseif which == "next" or which == "prev" then
		local index = table.find(own, CommandService.getControlled(player)) or 0
		local step = if which == "prev" then -1 else 1
		CommandService.setControlled(player, own[(index - 1 + step) % #own + 1])
	elseif typeof(which) == "table" and typeof((which :: any).pin) == "number" then
		local squad = SquadService.getById((which :: any).pin)
		if squad and table.find(own, squad) then
			CommandService.togglePin(player, squad)
		end
	end
end)

-- Hold with a placement (from the client preview): the squads march to the spot, side by side,
-- then form up in the chosen formation. Without placement data they hold where they stand.
local function holdAt(player: Player, squads: { any }, data: any): boolean
	if typeof(data) ~= "table" then
		return false
	end
	local x, z, yaw, formation = data.x, data.z, data.yaw, data.formation
	if typeof(x) ~= "number" or typeof(z) ~= "number" or typeof(yaw) ~= "number" or typeof(formation) ~= "string" then
		return false
	end
	if not FormationDefinitions.Formations[formation] or x ~= x or z ~= z or yaw ~= yaw then
		return false -- (x ~= x rejects NaN)
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return false
	end
	local anchor = Vector3.new(x, root.Position.Y, z)
	if MathUtil.flatDistance(anchor, root.Position) > Orders.HoldMaxDistance then
		return false
	end
	local entries = {}
	for _, squad in squads do
		table.insert(
			entries,
			{ soldiers = squad.soldierCount, spacingMult = squad.def.spacingMult, formations = squad.def.formations }
		)
	end
	local placements = FormationDefinitions.placeSquads(entries, anchor, yaw, formation)
	for i, squad in squads do
		clearOrderState(squad)
		squad.order = "Hold"
		squad.holdPosition = placements[i].center
		squad.holdYaw = yaw
		squad.idleYaw = yaw
		squad.pendingFormation = placements[i].formation
	end
	return true
end

Remotes.get("OrderUnits").OnServerEvent:Connect(function(player: Player, order: unknown, data: unknown)
	if typeof(order) ~= "string" or not VALID_ORDERS[order] then
		return
	end
	local squads = {}
	for _, squad in CommandService.getControlledList(player) do
		if not squad.routing then -- routing squads ignore orders
			table.insert(squads, squad)
		end
	end
	if #squads == 0 then
		return
	end
	if order == "Hold" and holdAt(player, squads, data) then
		return
	end
	if order == "Rush" then
		-- every unit can rush except archers (bows, skirmishers, sharpshooters) and guns
		local rushers = {}
		for _, squad in squads do
			if UnitDefinitions.canRush(squad.def) then
				table.insert(rushers, squad)
			end
		end
		if #rushers == 0 then
			CommandService.hooks.notify(player, "Archers and guns can't rush.", "bad")
			return
		end
		squads = rushers
		local now = os.clock()
		local remaining = (lastRushAt[player] or -math.huge) + Orders.RushCooldown - now
		if remaining > 0 then
			feedbackRemote:FireClient(player, "Rush", false, remaining)
			return
		end
		lastRushAt[player] = now
	end
	-- aimed orders: a point on the ground and/or an enemy squad under the cursor
	local rushPoint: Vector3? = nil
	local enemy: any = nil
	if typeof(data) == "table" then
		local x, z = (data :: any).x, (data :: any).z
		if typeof(x) == "number" and typeof(z) == "number" and x == x and z == z then
			rushPoint = Vector3.new(x, squads[1].position.Y, z)
		end
		local id = (data :: any).targetId
		local candidate = if typeof(id) == "number" then SquadService.getById(id) else nil
		if candidate and candidate.alive and candidate.team ~= squads[1].team then
			enemy = candidate
		end
	end
	if order == "FireAt" then
		if not enemy and not rushPoint then
			return
		end
		if rushPoint and MathUtil.flatDistance(rushPoint, squads[1].position) > Orders.FireAtMaxDistance then
			return
		end
		for _, squad in squads do
			clearOrderState(squad)
			if squad.def.attackType == "Melee" then
				-- sabres and spears can't shoot: they go for it
				squad.order = "Attack"
				squad.preferredTarget = enemy
					or SquadService.nearestEnemy(squad, math.huge, function(other)
						return MathUtil.flatDistance(other.position, rushPoint :: Vector3)
					end)
			else
				squad.order = "FireAt"
				squad.focusTarget = enemy
				squad.firePoint = if enemy then nil else rushPoint
			end
		end
		return
	end
	local center = Vector3.zero
	for _, squad in squads do
		center += squad.position / #squads
	end
	for i, squad in squads do
		clearOrderState(squad)
		squad.order = order
		if rushPoint then
			local direction = MathUtil.flat(rushPoint - center)
			local yaw = if direction.Magnitude > 0.01 then MathUtil.yawFromDirection(direction) else squad.yaw
			local lateral = (i - (#squads + 1) / 2) * Orders.FollowSpacing
			local target = rushPoint + MathUtil.rightFromYaw(yaw) * lateral
			local offset = MathUtil.flat(target - squad.position)
			if offset.Magnitude > Orders.RushMaxDistance then
				target = squad.position + offset.Unit * Orders.RushMaxDistance
			end
			if offset.Magnitude > 1 then
				squad.rushTarget = Vector3.new(target.X, squad.position.Y, target.Z)
				squad.rushYaw = MathUtil.yawFromDirection(offset)
				squad.pierced = {} -- each enemy squad can be pierced once per rush
			end
			squad.rushEnemy = enemy -- aimed at an enemy squad: charge it wherever it goes
		end
		if order == "Hold" then
			squad.idleYaw = squad.yaw
			squad.holdYaw = squad.yaw
			SquadService.stop(squad)
		end
	end
end)

Remotes.get("SetFormation").OnServerEvent:Connect(function(player: Player, formation: unknown)
	local squad = CommandService.getControlled(player)
	if squad and typeof(formation) == "string" and FormationDefinitions.Formations[formation] then
		SquadService.setFormation(squad, formation)
	end
end)

Players.PlayerRemoving:Connect(CommandService.removePlayer)

---------------------------------------------------------------------------
-- Order behaviours
---------------------------------------------------------------------------

local function nearestEnemy(squad: any, radius: number): any
	-- Prefer enemies that are still fighting over routed ones
	local target = SquadService.nearestEnemy(squad, radius, function(enemy, distance)
		return if enemy.routing then distance * 3 else distance
	end)
	return target
end

-- Distance at which a squad should stop when closing on `target`
local function engageDistance(squad: any, target: any): number
	local def = squad.def
	if def.attackType == "Melee" then
		return squad.radius + target.radius + def.meleeRange * 0.5
	elseif def.attackType == "Artillery" then
		return def.attackRange * 0.8
	end
	return def.attackRange * 0.85
end

local function doHold(squad: any)
	local target = squad.holdPosition
	if target and MathUtil.flatDistance(squad.position, target) > 2 then
		SquadService.moveTo(squad, target, 1.5)
	else
		SquadService.stop(squad)
		-- arrived: form up in the formation picked in the Hold preview
		local formation = squad.pendingFormation
		if formation and (formation == squad.formation or SquadService.setFormation(squad, formation)) then
			squad.pendingFormation = nil
		end
	end
	if squad.holdYaw then
		squad.idleYaw = squad.holdYaw
	end
end

local function doFollow(squad: any, index: number, count: number)
	local owner = squad.owner
	local character = owner and owner.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		SquadService.stop(squad)
		return
	end
	local look = MathUtil.flat(root.CFrame.LookVector)
	local yaw = if look.Magnitude > 0.01 then MathUtil.yawFromDirection(look) else squad.yaw
	local right = MathUtil.rightFromYaw(yaw)
	local back = -MathUtil.lookFromYaw(yaw)
	local lateral = (index - (count + 1) / 2) * Orders.FollowSpacing
	local slot = root.Position + back * Orders.FollowDistance + right * lateral
	local distance = MathUtil.flatDistance(slot, squad.position)
	if distance > 4 then
		SquadService.moveTo(squad, slot, 2, if distance > 40 then 1.2 else 1)
	end
	squad.idleYaw = yaw
end

local function doAttack(squad: any)
	local target = squad.preferredTarget
	if not (target and target.alive and not target.routing) then
		target = nearestEnemy(squad, Orders.AttackSearchRadius)
		squad.preferredTarget = target
	end
	if target then
		SquadService.moveTo(squad, target.position, engageDistance(squad, target))
	else
		SquadService.stop(squad)
	end
end

local function rushSpeed(squad: any): number
	return if squad.def.attackType == "Melee" then Orders.RushCavalrySpeedMult else Orders.RushSpeedMult
end

local function doRush(squad: any)
	-- Aimed rush (the client's path preview): sprint to the point, cavalry pierce through enemies
	local foe = squad.rushEnemy
	if foe then
		if foe.alive and not foe.routing then
			squad.preferredTarget = foe
			SquadService.moveTo(squad, foe.position, squad.radius + foe.radius + 1, rushSpeed(squad))
			return
		end
		squad.rushEnemy = nil
		squad.rushTarget = nil
	end
	local target = squad.rushTarget
	if target then
		if MathUtil.flatDistance(squad.position, target) <= 3 then
			-- arrived: hold there, facing the direction of the charge
			squad.rushTarget = nil
			squad.rushing = false
			squad.order = "Hold"
			squad.holdPosition = nil
			squad.holdYaw = squad.rushYaw or squad.yaw
			SquadService.stop(squad)
			-- landed next to an enemy: fight it instead of standing there
			local near = nearestEnemy(squad, squad.radius + 30)
			if near then
				squad.order = "Attack"
				squad.preferredTarget = near
			end
			return
		end
		if squad.def.attackType ~= "Melee" then
			-- infantry crash into the first enemy they meet and fight it out with bayonets
			local enemy = nearestEnemy(squad, squad.radius + 12)
			if enemy then
				squad.preferredTarget = enemy
				SquadService.moveTo(squad, enemy.position, squad.radius + enemy.radius + 1, rushSpeed(squad))
				return
			end
		end
		SquadService.moveTo(squad, target, 1, rushSpeed(squad))
		return
	end
	-- Charge the closest enemy if one is near, else the nearest objective not held by us
	local enemy = nearestEnemy(squad, Orders.RushEnemyRadius)
	if enemy then
		squad.preferredTarget = enemy
		-- close in to bayonet range, even for musket units: discipline is gone
		SquadService.moveTo(squad, enemy.position, squad.radius + enemy.radius + 2, Orders.RushSpeedMult)
		return
	end
	local bestZone, bestDistance = nil, math.huge
	for _, zone in ZoneService.getZones() do
		if zone.owner ~= "Blue" then
			local distance = MathUtil.flatDistance(zone.position, squad.position)
			if distance < bestDistance then
				bestZone, bestDistance = zone, distance
			end
		end
	end
	if bestZone then
		SquadService.moveTo(squad, bestZone.position, bestZone.radius * 0.4, Orders.RushSpeedMult)
		return
	end
	local anyEnemy = nearestEnemy(squad, math.huge)
	if anyEnemy then
		squad.preferredTarget = anyEnemy
		SquadService.moveTo(squad, anyEnemy.position, squad.radius + anyEnemy.radius + 2, Orders.RushSpeedMult)
	else
		SquadService.stop(squad)
	end
end

-- Fire at: shoot the chosen squad (walking into range first), or bombard / cover a spot
local function doFireAt(squad: any)
	local def = squad.def
	local range = def.attackRange
	local target = squad.focusTarget
	if target and not (target.alive and not target.routing) then
		target = nil
		squad.focusTarget = nil
		if not squad.firePoint then
			-- the target is gone: hold here
			squad.order = "Hold"
			squad.holdPosition = nil
			squad.holdYaw = squad.yaw
			squad.preferredTarget = nil
			SquadService.stop(squad)
			return
		end
	end
	local point = squad.firePoint
	if not target and point and def.attackType ~= "Artillery" then
		-- muskets / bows: the enemy nearest to the spot
		target = SquadService.nearestEnemy(squad, math.huge, function(other)
			local d = MathUtil.flatDistance(other.position, point)
			return if d <= Orders.FireAtPointRadius + other.radius then d else math.huge
		end)
	end
	local aim = if target then target.position else point
	if not aim then
		SquadService.stop(squad)
		return
	end
	squad.preferredTarget = target
	local distance = MathUtil.flatDistance(squad.position, aim)
	if distance > range * 0.95 then
		SquadService.moveTo(squad, aim, range * 0.85)
	elseif def.minRange and distance < def.minRange then
		local away = MathUtil.flat(squad.position - aim)
		SquadService.moveTo(
			squad,
			aim + (if away.Magnitude > 0.1 then away.Unit else Vector3.xAxis) * def.minRange * 1.3,
			2
		)
	else
		SquadService.stop(squad)
	end
	local toward = MathUtil.flat(aim - squad.position)
	if toward.Magnitude > 0.1 then
		squad.idleYaw = MathUtil.yawFromDirection(toward)
	end
end

-- Turn a controlled squad's standing order into movement (called by SquadController)
function CommandService.applyOrder(squad: any)
	squad.rushing = squad.order == "Rush"
	if time() < squad.regroupUntil then
		return
	end
	local order = squad.order
	if order == "Hold" then
		doHold(squad)
	elseif order == "Follow" then
		-- squads of the same group follow side by side
		local list = if squad.owner then CommandService.getControlledList(squad.owner) else { squad }
		doFollow(squad, table.find(list, squad) or 1, math.max(1, #list))
	elseif order == "Attack" then
		doAttack(squad)
	elseif order == "Rush" then
		doRush(squad)
	elseif order == "FireAt" then
		doFireAt(squad)
	end
end

return CommandService
