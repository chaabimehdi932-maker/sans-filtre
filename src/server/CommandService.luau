--[[
	CommandService
	The player directly commands a GROUP of squads (squad.isPlayerControlled = true), up to
	hooks.getMaxControlled(player) at once — 1 at the start of the campaign, more as your
	reputation grows (CampaignConfig.Reputation.Tiers). Every squad in the group obeys the
	X Hold · C Follow · V Attack · B Rush hotkeys together; every other friendly squad is run by
	AllyAIController. SquadController decides each tick which of the two drives a squad, so
	there is a single code path per squad and the handoff is just this flag.

	Switching (SelectSquad remote):
	  id            command only that squad            (click a squad card)
	  "next"/"prev" command only the next/prev squad    (Tab)
	  { pin = id }  add/remove that squad to the group  (Shift + click a card)
	  "pinNext"     add the next free squad to the group (T)
	The group is published in player attributes: "ControlledSquad" (first id),
	"ControlledSquads" ("3,5,8") and "MaxControlled".
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local FormationDefinitions = require(Modules:WaitForChild("FormationDefinitions"))
local GameConfig = require(Modules:WaitForChild("GameConfig"))
local MathUtil = require(Modules:WaitForChild("MathUtil"))
local Remotes = require(Modules:WaitForChild("Remotes"))

local SquadService = require(script.Parent:WaitForChild("SquadService"))
local ZoneService = require(script.Parent:WaitForChild("ZoneService"))

local Orders = GameConfig.Orders

local CommandService = {}

CommandService.hooks = {
	getMaxControlled = function(_player: Player): number
		return 1
	end,
	notify = function(_player: Player, _text: string, _tone: string) end,
}

local VALID_ORDERS = { Hold = true, Follow = true, Attack = true, Rush = true }

local groups: { [Player]: { any } } = {}

-- Reset the per-order state so the squad starts clean under its new controller
local function clearOrderState(squad: any)
	squad.rushTarget = nil
	squad.preferredTarget = nil
	squad.holdPosition = nil
	squad.pendingFormation = nil
	squad.rushing = false
	squad.speedMult = 1
end

-- Living squads of the player's command group (first = the "main" one)
function CommandService.getControlledList(player: Player): { any }
	local list = {}
	for _, squad in (groups[player] or {}) :: { any } do
		if squad.alive then
			table.insert(list, squad)
		end
	end
	return list
end

function CommandService.getControlled(player: Player): any
	return CommandService.getControlledList(player)[1]
end

local function publish(player: Player)
	local list = CommandService.getControlledList(player)
	local ids = {}
	for _, squad in list do
		table.insert(ids, tostring(squad.id))
	end
	player:SetAttribute("ControlledSquad", if list[1] then list[1].id else 0)
	player:SetAttribute("ControlledSquads", table.concat(ids, ","))
	player:SetAttribute("MaxControlled", CommandService.hooks.getMaxControlled(player))
end

local function takeCommand(squad: any)
	squad.isPlayerControlled = true
	clearOrderState(squad)
	squad.order = "Hold"
	squad.holdYaw = squad.yaw
	squad.idleYaw = squad.yaw
	SquadService.stop(squad)
end

local function releaseCommand(squad: any)
	if squad.alive then
		squad.isPlayerControlled = false -- back to AllyAIController
		clearOrderState(squad)
	end
end

-- Command exactly these squads (trimmed to the player's limit). {} = none.
function CommandService.setGroup(player: Player, squads: { any })
	local limit = CommandService.hooks.getMaxControlled(player)
	local wanted = {}
	for _, squad in squads do
		if #wanted < limit and squad.alive and not table.find(wanted, squad) then
			table.insert(wanted, squad)
		end
	end
	for _, squad in (groups[player] or {}) :: { any } do
		if not table.find(wanted, squad) then
			releaseCommand(squad)
		end
	end
	for _, squad in wanted do
		if not table.find(groups[player] or {}, squad) then
			takeCommand(squad)
		end
	end
	groups[player] = wanted
	publish(player)
end

-- Hand direct command of `squad` alone (or nothing) to the player
function CommandService.setControlled(player: Player, squad: any)
	CommandService.setGroup(player, if squad then { squad } else {})
end

-- Add / remove one squad from the command group
function CommandService.togglePin(player: Player, squad: any)
	local list = CommandService.getControlledList(player)
	local index = table.find(list, squad)
	if index then
		if #list > 1 then
			table.remove(list, index)
			CommandService.setGroup(player, list)
		end
		return
	end
	local limit = CommandService.hooks.getMaxControlled(player)
	if #list >= limit then
		CommandService.hooks.notify(
			player,
			string.format(
				"You can command %d squad%s at once. Earn reputation for more.",
				limit,
				if limit > 1 then "s" else ""
			),
			"info"
		)
		return
	end
	table.insert(list, squad)
	CommandService.setGroup(player, list)
end

-- Make sure the player commands at least one living squad (e.g. after one was destroyed)
function CommandService.ensureControlled(player: Player)
	local list = CommandService.getControlledList(player)
	if #list == 0 then
		local owned = SquadService.getOwnedBy(player)
		list = if owned[1] then { owned[1] } else {}
	end
	CommandService.setGroup(player, list)
end

-- Rush is on a cooldown so it cannot be spammed
local lastRushAt: { [Player]: number } = {}
local feedbackRemote = Remotes.get("CombatFeedback")

function CommandService.removePlayer(player: Player)
	groups[player] = nil
	lastRushAt[player] = nil
end

Remotes.get("SelectSquad").OnServerEvent:Connect(function(player: Player, which: unknown)
	local owned = SquadService.getOwnedBy(player)
	if #owned == 0 then
		return
	end
	if typeof(which) == "number" then
		local squad = SquadService.getById(which)
		if squad and squad.alive and squad.owner == player then
			CommandService.setControlled(player, squad)
		end
	elseif which == "next" or which == "prev" then
		local index = table.find(owned, CommandService.getControlled(player)) or 0
		local step = if which == "prev" then -1 else 1
		CommandService.setControlled(player, owned[(index - 1 + step) % #owned + 1])
	elseif which == "pinNext" then
		local list = CommandService.getControlledList(player)
		for _, squad in owned do
			if not table.find(list, squad) then
				CommandService.togglePin(player, squad)
				return
			end
		end
	elseif typeof(which) == "table" and typeof((which :: any).pin) == "number" then
		local squad = SquadService.getById((which :: any).pin)
		if squad and squad.alive and squad.owner == player then
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
		local now = os.clock()
		local remaining = (lastRushAt[player] or -math.huge) + Orders.RushCooldown - now
		if remaining > 0 then
			feedbackRemote:FireClient(player, "Rush", false, remaining)
			return
		end
		lastRushAt[player] = now
	end
	-- aimed rush: every squad of the group gets its own lane next to the aimed point
	local rushPoint: Vector3? = nil
	if order == "Rush" and typeof(data) == "table" then
		local x, z = (data :: any).x, (data :: any).z
		if typeof(x) == "number" and typeof(z) == "number" and x == x and z == z then
			rushPoint = Vector3.new(x, squads[1].position.Y, z)
		end
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
	end
end

return CommandService
