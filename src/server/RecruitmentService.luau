--[[
	RecruitmentService
	Per-player army budget and roster, validated server-side.
	  • points carry over between rounds (+ rewards, + Income zones during battle)
	  • surviving squads of a won round come back as "veterans" in the next roster
	  • a defeat resets points and roster to the starting values
	Deployment is automatic for v1: squads are spread across the PlayerDeployZone.
	-- STRETCH GOAL: let players click to place each squad inside the deploy zone.
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

local sessions: { [Player]: any } = {}
local phaseOpen = false

-- Front row first, guns at the back
local DEPLOY_PRIORITY = { LineInfantry = 1, EliteGuard = 2, Skirmishers = 3, Cavalry = 4, Artillery = 5 }

local function sendState(player: Player)
	local session = sessions[player]
	if not session then
		return
	end
	local unlocked = {}
	for unitId in UnitDefinitions.Units do
		unlocked[unitId] = DataService.isUnlocked(player, unitId)
	end
	local roster = {}
	for _, entry in session.roster do
		table.insert(roster, { unitId = entry.unitId, carried = entry.carried })
	end
	stateRemote:FireClient(player, {
		points = math.floor(session.points),
		roster = roster,
		maxSquads = R.MaxSquadsPerPlayer,
		unlocked = unlocked,
		ready = session.ready,
		open = phaseOpen,
	})
end

function RecruitmentService.initPlayer(player: Player)
	sessions[player] = { points = R.StartingPoints, roster = {}, ready = false }
	sendState(player)
end

function RecruitmentService.removePlayer(player: Player)
	sessions[player] = nil
end

function RecruitmentService.openPhase()
	phaseOpen = true
	for player, session in sessions do
		session.ready = false
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

function RecruitmentService.addPoints(player: Player, amount: number)
	local session = sessions[player]
	if session and amount ~= 0 then
		session.points += amount
		sendState(player)
	end
end

function RecruitmentService.resetAll()
	for player, session in sessions do
		session.points = R.StartingPoints
		session.roster = {}
		sendState(player)
	end
end

Remotes.get("RequestRecruit").OnServerEvent:Connect(function(player: Player, unitId: unknown, delta: unknown)
	local session = sessions[player]
	if not phaseOpen or not session or session.ready then
		return
	end
	if typeof(unitId) ~= "string" or typeof(delta) ~= "number" then
		return
	end
	local def = UnitDefinitions.get(unitId)
	if not def then
		return
	end
	if delta > 0 then
		if #session.roster >= R.MaxSquadsPerPlayer then
			return
		end
		if not DataService.isUnlocked(player, unitId) or session.points < def.cost then
			return
		end
		session.points -= def.cost
		table.insert(session.roster, { unitId = unitId, carried = false })
	elseif delta < 0 then
		-- Undo the latest purchase of that type (refunded); otherwise dismiss a veteran (no refund)
		local removed = false
		for i = #session.roster, 1, -1 do
			local entry = session.roster[i]
			if entry.unitId == unitId and not entry.carried then
				table.remove(session.roster, i)
				session.points += def.cost
				removed = true
				break
			end
		end
		if not removed then
			for i = #session.roster, 1, -1 do
				if session.roster[i].unitId == unitId then
					table.remove(session.roster, i)
					break
				end
			end
		end
	end
	sendState(player)
end)

Remotes.get("ConfirmRecruit").OnServerEvent:Connect(function(player: Player)
	local session = sessions[player]
	if phaseOpen and session then
		session.ready = true
		sendState(player)
	end
end)

-- Spawns every player's roster in the player deployment zone. Returns the created squads.
function RecruitmentService.deployAll(): { any }
	local entries = {}
	for player, session in sessions do
		if #session.roster == 0 and R.FreeSquadIfEmpty then
			table.insert(session.roster, { unitId = R.FreeSquadIfEmpty, carried = false })
		end
		for _, entry in session.roster do
			table.insert(entries, { player = player, unitId = entry.unitId })
		end
	end
	table.sort(entries, function(a, b)
		return (DEPLOY_PRIORITY[a.unitId] or 9) < (DEPLOY_PRIORITY[b.unitId] or 9)
	end)
	local spots = MapService.deployPositions("Blue", #entries, R.DeploySpacing)
	local created = {}
	for i, entry in entries do
		local squad = SquadService.create({
			unitId = entry.unitId,
			team = "Blue",
			position = spots[i].position,
			yaw = spots[i].yaw,
			owner = entry.player,
		})
		squad.order = "Hold"
		table.insert(created, squad)
	end
	return created
end

-- After a win: every surviving squad returns next round as a veteran
function RecruitmentService.collectSurvivors()
	for _, session in sessions do
		session.roster = {}
	end
	for _, squad in SquadService.getByTeam("Blue") do
		local session = squad.owner and sessions[squad.owner]
		if session then
			table.insert(session.roster, { unitId = squad.unitId, carried = true })
		end
	end
	for player in sessions do
		sendState(player)
	end
end

return RecruitmentService
