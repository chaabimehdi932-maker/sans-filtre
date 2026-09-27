--[[
	RecruitmentService
	Before each battle every player picks ONE unit (free) — that is the squad they command.
	The rest of the army is AI: allied squads come from the round config, like the enemy's.
	  • veteran stars: each round your unit survives, that unit type earns a star (session)
	  • reinforcements: when your squad is wiped out, a fresh one of the same unit arrives at
	    the deployment zone after a delay (limited per battle; "Reinforcements" zones speed it up)
	Deployment is automatic: your squad in the middle of the line, allies around it.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local GameConfig = require(Modules:WaitForChild("GameConfig"))
local Remotes = require(Modules:WaitForChild("Remotes"))
local UnitDefinitions = require(Modules:WaitForChild("UnitDefinitions"))

local DataService = require(script.Parent:WaitForChild("DataService"))
local MapService = require(script.Parent:WaitForChild("MapService"))
local SquadService = require(script.Parent:WaitForChild("SquadService"))

local R = GameConfig.Recruitment

local stateRemote = Remotes.get("RecruitState")

local RecruitmentService = {}

RecruitmentService.hooks = {
	-- called when a reinforcement squad arrives for a player
	onReinforced = function(_player: Player, _squad: any) end,
	-- zones held granting faster reinforcements
	getReinforcementBonus = function(): number
		return 0
	end,
}

local sessions: { [Player]: any } = {}
local phaseOpen = false

local function sendState(player: Player)
	local session = sessions[player]
	if not session then
		return
	end
	local unlocked = {}
	for unitId in UnitDefinitions.Units do
		unlocked[unitId] = DataService.isUnlocked(player, unitId)
	end
	stateRemote:FireClient(player, {
		chosen = session.unitId,
		unlocked = unlocked,
		ranks = session.ranks,
		ready = session.ready,
		open = phaseOpen,
		reinforcements = session.reinforcements,
		reinforcementAt = session.reinforcementAt,
	})
end

function RecruitmentService.initPlayer(player: Player)
	sessions[player] = { unitId = R.DefaultUnit, ready = false, reinforcements = R.Reinforcements, ranks = {} }
	sendState(player)
end

function RecruitmentService.removePlayer(player: Player)
	sessions[player] = nil
end

function RecruitmentService.openPhase()
	phaseOpen = true
	for player, session in sessions do
		session.ready = false
		session.reinforcements = R.Reinforcements
		session.reinforcementAt = nil
		session.squad = nil
		sendState(player)
	end
end

function RecruitmentService.closePhase()
	phaseOpen = false
	for player in sessions do
		sendState(player)
	end
end

function RecruitmentService.allReady(): boolean
	local any = false
	for _, session in sessions do
		any = true
		if not session.ready then
			return false
		end
	end
	return any
end

-- After a defeat, veteran stars are lost
function RecruitmentService.resetAll()
	for player, session in sessions do
		session.ranks = {}
		sendState(player)
	end
end

Remotes.get("RequestRecruit").OnServerEvent:Connect(function(player: Player, unitId: unknown)
	local session = sessions[player]
	if not phaseOpen or not session or session.ready or typeof(unitId) ~= "string" then
		return
	end
	if UnitDefinitions.get(unitId) and DataService.isUnlocked(player, unitId) then
		session.unitId = unitId
		sendState(player)
	end
end)

Remotes.get("ConfirmRecruit").OnServerEvent:Connect(function(player: Player)
	local session = sessions[player]
	if phaseOpen and session then
		session.ready = true
		sendState(player)
	end
end)

local function spawnPlayerSquad(player: Player, spot: any): any
	local session = sessions[player]
	local rank = session.ranks[session.unitId] or 0
	local squad = SquadService.create({
		unitId = session.unitId,
		team = "Blue",
		position = spot.position,
		yaw = spot.yaw,
		owner = player,
		rank = rank,
		-- veterans are a bit tougher and hit a bit harder
		statMultiplier = 1 + rank * R.VeteranBonusPerRank,
		damageMultiplier = 1 + rank * R.VeteranBonusPerRank,
	})
	session.squad = squad
	return squad
end

--[[
	Deploys every player's chosen squad plus the round's allied AI squads.
	Returns { [Player] = squad }.
]]
function RecruitmentService.deployAll(cfg: any): { [Player]: any }
	local players = {}
	for player in sessions do
		table.insert(players, player)
	end
	local allies = cfg.allies or {}
	local spots = MapService.deployPositions("Blue", #players + #allies, R.DeploySpacing)
	-- players get the spots closest to the centre of the front line
	local order = {}
	for i in spots do
		table.insert(order, i)
	end
	table.sort(order, function(a, b)
		if spots[a].row ~= spots[b].row then
			return spots[a].row < spots[b].row
		end
		return math.abs(spots[a].lateral) < math.abs(spots[b].lateral)
	end)
	local created = {}
	local next = 1
	for _, player in players do
		created[player] = spawnPlayerSquad(player, spots[order[next]])
		next += 1
	end
	for _, ally in allies do
		local spot = spots[order[next]]
		next += 1
		SquadService.create({ unitId = ally.unitId, team = "Blue", position = spot.position, yaw = spot.yaw })
	end
	return created
end

-- Called when a player's squad is destroyed during a battle
function RecruitmentService.onPlayerSquadLost(player: Player)
	local session = sessions[player]
	if not session or session.reinforcements <= 0 or session.reinforcementAt then
		return
	end
	session.reinforcements -= 1
	local delay = R.ReinforcementDelay * math.max(0.3, 1 - RecruitmentService.hooks.getReinforcementBonus() * 0.4)
	session.reinforcementAt = workspace:GetServerTimeNow() + delay
	sendState(player)
	task.delay(delay, function()
		if sessions[player] ~= session or not session.reinforcementAt then
			return -- the battle ended meanwhile
		end
		session.reinforcementAt = nil
		local spot = MapService.deployPositions("Blue", 1, R.DeploySpacing)[1]
		local squad = spawnPlayerSquad(player, spot)
		sendState(player)
		RecruitmentService.hooks.onReinforced(player, squad)
	end)
end

-- Can the Blue side still get squads back?
function RecruitmentService.reinforcementsPending(): boolean
	for _, session in sessions do
		if session.reinforcementAt or session.reinforcements > 0 then
			return true
		end
	end
	return false
end

function RecruitmentService.cancelReinforcements()
	for player, session in sessions do
		session.reinforcementAt = nil
		sendState(player)
	end
end

-- After a win: if your unit survived it earns a veteran star
function RecruitmentService.recordSurvivors()
	for player, session in sessions do
		local squad = session.squad
		if squad and squad.alive then
			session.ranks[squad.unitId] = math.min(R.MaxVeteranRank, (session.ranks[squad.unitId] or 0) + 1)
		end
		sendState(player)
	end
end

return RecruitmentService
