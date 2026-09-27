--[[
	CommandService
	Army orders from the commander (X Hold · C Follow · V Attack · B Rush), formations
	(Line / Column / Square) and multi-squad selection, all validated server-side.

	Selection: the client sends the ids it wants selected (SelectSquads remote: number keys,
	Shift+number, 0 = all, Ctrl+drag box, squad panel clicks). The server keeps only squads the
	player owns and publishes the result in the player attribute "SelectedSquads" ("3,5,8").
	Orders and formation changes apply to every selected squad.
	-- STRETCH GOAL: command radius model — also allow "every friendly squad within N studs".

	tick() runs every AI.CommandInterval and turns each squad's standing order into movement.
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

local VALID_ORDERS = { Hold = true, Follow = true, Attack = true, Rush = true }
local MAX_SELECTION = 64

local selections: { [Player]: { [number]: boolean } } = {}

local function publish(player: Player)
	local ids = {}
	local selection = selections[player]
	if selection then
		for id in selection do
			table.insert(ids, id)
		end
	end
	table.sort(ids)
	player:SetAttribute("SelectedSquads", table.concat(ids, ","))
end

-- Selected squads that are still alive (dead ones are dropped from the selection)
function CommandService.getSelected(player: Player): { any }
	local selection = selections[player]
	local list = {}
	if not selection then
		return list
	end
	local changed = false
	for id in selection do
		local squad = SquadService.getById(id)
		if squad and squad.alive and squad.owner == player then
			table.insert(list, squad)
		else
			selection[id] = nil
			changed = true
		end
	end
	if changed then
		publish(player)
	end
	table.sort(list, function(a, b)
		return a.id < b.id
	end)
	return list
end

function CommandService.prune(player: Player)
	CommandService.getSelected(player)
end

function CommandService.selectAll(player: Player)
	local selection = {}
	for _, squad in SquadService.getOwnedBy(player) do
		selection[squad.id] = true
	end
	selections[player] = selection
	publish(player)
end

function CommandService.removePlayer(player: Player)
	selections[player] = nil
end

Remotes.get("SelectSquads").OnServerEvent:Connect(function(player: Player, ids: unknown)
	if typeof(ids) ~= "table" then
		return
	end
	local selection = {}
	local count = 0
	for _, id in ids :: { any } do
		count += 1
		if count > MAX_SELECTION then
			break
		end
		if typeof(id) == "number" then
			local squad = SquadService.getById(id)
			if squad and squad.alive and squad.owner == player then
				selection[squad.id] = true
			end
		end
	end
	selections[player] = selection
	publish(player)
end)

Remotes.get("OrderUnits").OnServerEvent:Connect(function(player: Player, order: unknown)
	if typeof(order) ~= "string" or not VALID_ORDERS[order] then
		return
	end
	for _, squad in CommandService.getSelected(player) do
		if not squad.routing then -- routing squads ignore orders
			squad.order = order
			squad.preferredTarget = nil
			if order == "Hold" then
				squad.idleYaw = squad.yaw
				SquadService.stop(squad)
			end
		end
	end
end)

Remotes.get("SetFormation").OnServerEvent:Connect(function(player: Player, formation: unknown)
	if typeof(formation) ~= "string" or not FormationDefinitions.Formations[formation] then
		return
	end
	for _, squad in CommandService.getSelected(player) do
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
	SquadService.stop(squad)
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

local function doRush(squad: any)
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

function CommandService.tick()
	-- Group following squads per commander so they line up side by side
	local followers: { [Player]: { any } } = {}
	for _, squad in SquadService.getByTeam("Blue") do
		if squad.owner and squad.order == "Follow" and not squad.routing then
			followers[squad.owner] = followers[squad.owner] or {}
			table.insert(followers[squad.owner], squad)
		end
	end

	for _, squad in SquadService.getByTeam("Blue") do
		if not squad.owner then
			continue
		end
		squad.rushing = squad.order == "Rush" and not squad.routing
		if squad.routing or time() < squad.regroupUntil then
			continue
		end
		local order = squad.order
		if order == "Hold" then
			doHold(squad)
		elseif order == "Follow" then
			local list = followers[squad.owner]
			doFollow(squad, table.find(list, squad) or 1, #list)
		elseif order == "Attack" then
			doAttack(squad)
		elseif order == "Rush" then
			doRush(squad)
		end
	end
end

return CommandService
