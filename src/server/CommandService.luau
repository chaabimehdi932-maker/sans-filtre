--[[
	CommandService
	The player commands ONE squad at a time (squad.isPlayerControlled = true). That squad obeys
	the X Hold · C Follow · V Attack · B Rush hotkeys; every other friendly squad is run by
	AllyAIController. SquadController decides each tick which of the two drives a squad, so
	there is a single code path per squad and the handoff is just this flag.

	Switching: SelectSquad remote (Tab / Shift+Tab / clicking a squad card). The previous squad
	goes back to AI control instantly; the new one holds where it stands until given an order.
	The controlled squad id is published in the player attribute "ControlledSquad".
	-- STRETCH GOAL: command radius model — also order every friendly squad within N studs.
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

local controlled: { [Player]: any } = {}

-- Reset the per-order state so the squad starts clean under its new controller
local function clearOrderState(squad: any)
	squad.rushTarget = nil
	squad.preferredTarget = nil
	squad.holdPosition = nil
	squad.pendingFormation = nil
	squad.rushing = false
	squad.speedMult = 1
end

function CommandService.getControlled(player: Player): any
	local squad = controlled[player]
	if squad and squad.alive then
		return squad
	end
	return nil
end

-- Hand direct command of `squad` (or nothing) to the player
function CommandService.setControlled(player: Player, squad: any)
	local previous = controlled[player]
	if previous == squad then
		return
	end
	if previous and previous.alive then
		previous.isPlayerControlled = false -- back to AllyAIController
		clearOrderState(previous)
	end
	controlled[player] = squad
	if squad then
		squad.isPlayerControlled = true
		clearOrderState(squad)
		squad.order = "Hold"
		squad.holdYaw = squad.yaw
		squad.idleYaw = squad.yaw
		SquadService.stop(squad)
	end
	player:SetAttribute("ControlledSquad", if squad then squad.id else 0)
end

-- Make sure the player commands a living squad (first owned one), e.g. after it was destroyed
function CommandService.ensureControlled(player: Player)
	if CommandService.getControlled(player) then
		return
	end
	controlled[player] = nil
	CommandService.setControlled(player, SquadService.getOwnedBy(player)[1])
end

function CommandService.removePlayer(player: Player)
	controlled[player] = nil
end

-- SelectSquad(id) takes command of that squad; SelectSquad("next" | "prev") cycles
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
	end
end)

-- Hold with a placement (from the client preview): the squad marches to the spot, then forms up
-- in the chosen formation. Without placement data it holds where it stands.
local function holdAt(player: Player, squad: any, data: any): boolean
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
	local placement = FormationDefinitions.placeSquads({
		{ soldiers = squad.soldierCount, spacingMult = squad.def.spacingMult, formations = squad.def.formations },
	}, anchor, yaw, formation)[1]
	clearOrderState(squad)
	squad.order = "Hold"
	squad.holdPosition = placement.center
	squad.holdYaw = yaw
	squad.idleYaw = yaw
	squad.pendingFormation = placement.formation
	return true
end

Remotes.get("OrderUnits").OnServerEvent:Connect(function(player: Player, order: unknown, data: unknown)
	if typeof(order) ~= "string" or not VALID_ORDERS[order] then
		return
	end
	local squad = CommandService.getControlled(player)
	if not squad or squad.routing then -- routing squads ignore orders
		return
	end
	if order == "Hold" and holdAt(player, squad, data) then
		return
	end
	clearOrderState(squad)
	squad.order = order
	squad.rushTarget = nil
	if order == "Rush" and typeof(data) == "table" then
		local x, z = (data :: any).x, (data :: any).z
		if typeof(x) == "number" and typeof(z) == "number" and x == x and z == z then
			local target = Vector3.new(x, squad.position.Y, z)
			local offset = MathUtil.flat(target - squad.position)
			if offset.Magnitude > Orders.RushMaxDistance then
				target = squad.position + offset.Unit * Orders.RushMaxDistance
			end
			if offset.Magnitude > 1 then
				squad.rushTarget = target
				squad.rushYaw = MathUtil.yawFromDirection(offset)
				squad.pierced = {} -- each enemy squad can be pierced once per rush
			end
		end
	end
	if order == "Hold" then
		squad.idleYaw = squad.yaw
		squad.holdYaw = squad.yaw
		SquadService.stop(squad)
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

-- Turn the controlled squad's standing order into movement (called by SquadController)
function CommandService.applyOrder(squad: any)
	squad.rushing = squad.order == "Rush"
	if time() < squad.regroupUntil then
		return
	end
	local order = squad.order
	if order == "Hold" then
		doHold(squad)
	elseif order == "Follow" then
		doFollow(squad, 1, 1)
	elseif order == "Attack" then
		doAttack(squad)
	elseif order == "Rush" then
		doRush(squad)
	end
end

return CommandService
