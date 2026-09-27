--[[
	GameManager
	Round state machine and win/lose conditions. Wires the services together.

	  Waiting → Recruitment (timed) → Battle → Reward (summary) → next round
	  Victory: round + 1, surviving squads carry over.   Defeat: back to round 1.

	Heartbeat drives SquadService every frame; expensive systems are throttled:
	  CommandService 0.3 s · EnemyAIController 0.5 s · ZoneService 0.5 s · client snapshots 0.25 s
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local GameConfig = require(Modules:WaitForChild("GameConfig"))
local Remotes = require(Modules:WaitForChild("Remotes"))

local CommandService = require(script.Parent:WaitForChild("CommandService"))
local DataService = require(script.Parent:WaitForChild("DataService"))
local EnemyAIController = require(script.Parent:WaitForChild("EnemyAIController"))
local SquadController = require(script.Parent:WaitForChild("SquadController"))
local MapService = require(script.Parent:WaitForChild("MapService"))
local PlayerCombatService = require(script.Parent:WaitForChild("PlayerCombatService"))
local RecruitmentService = require(script.Parent:WaitForChild("RecruitmentService"))
local SquadService = require(script.Parent:WaitForChild("SquadService"))
local ZoneService = require(script.Parent:WaitForChild("ZoneService"))

local Phases = GameConfig.Phases
local Rewards = GameConfig.Rewards
local Zones = GameConfig.Zones

local roundStateRemote = Remotes.get("RoundStateChanged")
local squadStateRemote = Remotes.get("UpdateSquadState")
local zoneStateRemote = Remotes.get("UpdateZoneState")
local summaryRemote = Remotes.get("RoundSummary")
local notifyRemote = Remotes.get("Notify")
local killFeedRemote = Remotes.get("KillFeed")

local function notifyAll(text: string, tone: string?)
	notifyRemote:FireAllClients(text, tone or "info")
end

---------------------------------------------------------------------------
-- Map + service wiring
---------------------------------------------------------------------------

print("[Napoleonic Commander] server starting… version " .. GameConfig.Version)
MapService.ensureMap()
ZoneService.init()
print("[Napoleonic Commander] map ready:", #ZoneService.getZones(), "capture zones")

local battle: any = nil -- per-battle stats and state, nil outside the Battle phase

SquadService.hooks.getHeroes = PlayerCombatService.getHeroes
SquadService.hooks.damageHero = PlayerCombatService.damageHero
SquadService.hooks.getTeamBonus = ZoneService.getTeamBonus
SquadService.hooks.onCasualties = function(squad, lost, _attackerTeam, creditPlayer)
	if not battle then
		return
	end
	if squad.team == "Red" then
		battle.killsDealt += lost
	else
		battle.killsTaken += lost
	end
	-- kills made by YOUR squad or by you: live XP + the "KILL xN" combo on your screen
	if creditPlayer and squad.team == "Red" and creditPlayer.Parent then
		local xp = lost * Rewards.XPPerKill
		DataService.addXP(creditPlayer, xp)
		killFeedRemote:FireClient(creditPlayer, { kills = lost, xp = xp })
	end
end
SquadService.hooks.onRout = function(squad)
	if squad.owner then
		notifyRemote:FireClient(squad.owner, squad.name .. " is routing!", "bad")
	elseif squad.team == "Red" then
		notifyAll("Enemy " .. squad.name .. " is routing!", "good")
	end
end
SquadService.hooks.onSquadDestroyed = function(squad)
	if squad.owner then
		notifyRemote:FireClient(squad.owner, "Your " .. squad.name .. " was wiped out!", "bad")
		if battle and not battle.result then
			RecruitmentService.onPlayerSquadLost(squad.owner) -- reinforcements, if any left
		end
	elseif squad.team == "Red" then
		notifyAll("Enemy " .. squad.name .. " destroyed!", "good")
	end
end

ZoneService.hooks.getHeroes = PlayerCombatService.getHeroes
ZoneService.hooks.onOwnerChanged = function(zone, newOwner, oldOwner)
	if newOwner == "Blue" then
		notifyAll(zone.name .. " captured!", "good")
		for _, player in Players:GetPlayers() do
			DataService.addXP(player, Rewards.XPPerZoneCapture)
		end
	elseif newOwner == "Red" then
		notifyAll(zone.name .. " was taken by the enemy!", "bad")
	elseif oldOwner == "Blue" then
		notifyAll(zone.name .. " is being lost!", "bad")
	end
end

RecruitmentService.hooks.onReinforced = function(player, squad)
	CommandService.setControlled(player, squad)
	notifyRemote:FireClient(player, "Reinforcements have arrived: you command a fresh " .. squad.name .. "!", "good")
end
RecruitmentService.hooks.getReinforcementBonus = function()
	return ZoneService.getTeamBonus("Blue", "Reinforcements")
end

PlayerCombatService.hooks.getSpawnCFrame = function()
	return MapService.spawnCFrame("Blue")
end
PlayerCombatService.hooks.getLevel = DataService.getLevel
PlayerCombatService.hooks.onDamageDealt = function(player, amount)
	DataService.addXP(player, amount * Rewards.XPPerHeroDamage)
end

DataService.hooks.onLevelUp = function(player, level)
	notifyRemote:FireClient(player, "Level up! You are now level " .. level, "good")
	PlayerCombatService.refreshMaxHealth(player)
end

---------------------------------------------------------------------------
-- Phase broadcasting
---------------------------------------------------------------------------

local round = 1
local phaseInfo: any = { phase = "Waiting", round = round, endsAt = 0 }
local continueVotes: { [Player]: boolean } = {}

local function enemyPreview(cfg: any): { [string]: number }
	local counts = {}
	for _, wave in cfg.waves do
		for _, unit in wave.units do
			counts[unit.unitId] = (counts[unit.unitId] or 0) + 1
		end
	end
	return counts
end

local function computeObjective(cfg: any): string
	local zones = ZoneService.getZones()
	for _, zone in zones do
		if zone.owner ~= "Blue" then
			return (if cfg.side == "Attacker" then "CAPTURE " else "RETAKE ") .. string.upper(zone.name)
		end
	end
	if cfg.side == "Attacker" then
		return "HOLD ALL ZONES"
	end
	return if #zones == 1 then "DEFEND " .. string.upper(zones[1].name) else "DEFEND ALL ZONES"
end

local function setPhase(phase: string, duration: number, cfg: any, banner: boolean, extra: any?)
	phaseInfo = {
		phase = phase,
		round = round,
		endsAt = Workspace:GetServerTimeNow() + duration,
		side = cfg.side,
		winCondition = cfg.winCondition,
		objective = computeObjective(cfg),
		enemyPreview = enemyPreview(cfg),
		bossName = if cfg.boss then cfg.boss.name else nil,
		banner = banner,
		result = if extra then extra.result else nil,
	}
	roundStateRemote:FireAllClients(phaseInfo)
end

-- Re-announce the objective (big banner) when it changes mid-battle
local function refreshObjective(cfg: any)
	local objective = computeObjective(cfg)
	if phaseInfo.phase == "Battle" and objective ~= phaseInfo.objective then
		phaseInfo.objective = objective
		phaseInfo.banner = true
		roundStateRemote:FireAllClients(phaseInfo)
	end
end

---------------------------------------------------------------------------
-- Players
---------------------------------------------------------------------------

local function onPlayerAdded(player: Player)
	PlayerCombatService.initPlayer(player)
	DataService.load(player)
	if not player.Parent then
		return
	end
	RecruitmentService.initPlayer(player)
	PlayerCombatService.refreshMaxHealth(player)
	DataService.sendProgress(player)
	roundStateRemote:FireClient(player, phaseInfo)
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end

Players.PlayerRemoving:Connect(function(player)
	SquadService.removeOwnedBy(player)
	RecruitmentService.removePlayer(player)
	PlayerCombatService.removePlayer(player)
	DataService.release(player)
	continueVotes[player] = nil
end)

game:BindToClose(function()
	for _, player in Players:GetPlayers() do
		DataService.save(player)
	end
end)
DataService.startAutosave()

Remotes.get("ContinueRound").OnServerEvent:Connect(function(player)
	if phaseInfo.phase == "Reward" then
		continueVotes[player] = true
	end
end)

---------------------------------------------------------------------------
-- Frame loop
---------------------------------------------------------------------------

local timers = { command = 0, zone = 0, snapshot = 0 }
local holdInfo: any = nil

local function updateHold(step: number)
	if not battle or battle.result then
		return
	end
	-- Attackers win by holding every zone; defenders lose if the enemy holds every zone
	local holder = if ZoneService.allOwnedBy("Blue") then "Blue" elseif ZoneService.allOwnedBy("Red") then "Red" else nil
	local relevant = (battle.side == "Attacker" and holder == "Blue") or (battle.side == "Defender" and holder == "Red")
	if relevant then
		battle.holdTimer += step
		holdInfo = { team = holder, progress = math.min(1, battle.holdTimer / Zones.HoldTimeToWin) }
		if battle.holdTimer >= Zones.HoldTimeToWin then
			battle.result = if holder == "Blue" then "Victory" else "Defeat"
		end
	else
		battle.holdTimer = 0
		holdInfo = nil
	end
end

RunService.Heartbeat:Connect(function(dt)
	SquadService.update(dt)
	local inBattle = phaseInfo.phase == "Battle" and battle ~= nil and not battle.result

	-- every squad decides through SquadController (per-squad throttles inside)
	timers.command += dt
	if timers.command >= 0.1 then
		timers.command = 0
		if inBattle then
			SquadController.tick()
		end
	end

	timers.zone += dt
	if timers.zone >= Zones.TickInterval then
		local step = timers.zone
		timers.zone = 0
		if inBattle then
			ZoneService.tick(step)
			updateHold(step)
		end
	end

	timers.snapshot += dt
	if timers.snapshot >= GameConfig.Network.SnapshotInterval then
		timers.snapshot = 0
		squadStateRemote:FireAllClients(SquadService.snapshot())
		zoneStateRemote:FireAllClients({ zones = ZoneService.snapshot(), hold = holdInfo })
	end
end)

---------------------------------------------------------------------------
-- Round loop
---------------------------------------------------------------------------

local function runRecruitment(cfg: any)
	SquadService.clearAll()
	SquadService.setPaused(false)
	-- Attack rounds: the enemy holds the field. Defence rounds: we do.
	ZoneService.reset(if cfg.side == "Attacker" then "Red" else "Blue")
	holdInfo = nil
	RecruitmentService.openPhase()
	setPhase("Recruitment", Phases.RecruitmentTime, cfg, false)
	local deadline = time() + Phases.RecruitmentTime
	while time() < deadline and not RecruitmentService.allReady() do
		task.wait(0.25)
	end
	RecruitmentService.closePhase()
end

local function spawnDueWaves()
	local elapsed = time() - battle.startTime
	for _, wave in battle.waves do
		if not wave.spawned and elapsed >= wave.delay then
			wave.spawned = true
			EnemyAIController.spawnWave(wave.units)
			if wave.delay > 0 then
				notifyAll("Enemy reinforcements have arrived!", "bad")
			end
		end
	end
end

local function pendingWaves(): boolean
	for _, wave in battle.waves do
		if not wave.spawned then
			return true
		end
	end
	return false
end

local function runBattle(cfg: any): string
	local playerSquads = RecruitmentService.deployAll(cfg)
	PlayerCombatService.teleportAll(MapService.spawnCFrame("Blue"))
	for _, player in Players:GetPlayers() do
		CommandService.setControlled(player, nil)
		CommandService.setControlled(player, playerSquads[player]) -- your unit; allies run on the ally AI
		DataService.recordRoundReached(player, round)
	end
	EnemyAIController.setTuning(cfg.ai)

	local waves = {}
	for _, wave in cfg.waves do
		table.insert(waves, { delay = wave.delay, units = wave.units, spawned = false })
	end
	battle = {
		side = cfg.side,
		startTime = time(),
		killsDealt = 0,
		killsTaken = 0,
		holdTimer = 0,
		result = nil,
		waves = waves,
	}
	spawnDueWaves()
	setPhase("Battle", Phases.BattleTimeLimit, cfg, true)
	if cfg.boss then
		notifyAll(cfg.boss.name .. " has taken the field!", "bad")
	end

	local deadline = time() + Phases.BattleTimeLimit
	while not battle.result do
		task.wait(0.25)
		spawnDueWaves()
		if #SquadService.getByTeam("Blue") == 0 and not RecruitmentService.reinforcementsPending() then
			battle.result = "Defeat"
		elseif #SquadService.getByTeam("Red") == 0 and not pendingWaves() then
			battle.result = "Victory"
		elseif time() >= deadline then
			-- Out of time: attackers failed; defenders win if they still hold ground
			if cfg.side == "Attacker" then
				battle.result = "Defeat"
			else
				battle.result = if ZoneService.countOwned("Blue") > 0 then "Victory" else "Defeat"
			end
		else
			refreshObjective(cfg)
		end
	end
	SquadService.setPaused(true)
	RecruitmentService.cancelReinforcements()
	return battle.result
end

local function runReward(cfg: any, result: string)
	local victory = result == "Victory"
	if victory then
		RecruitmentService.recordSurvivors() -- your unit earns a veteran star if it survived
	end
	local zonesHeld = ZoneService.countOwned("Blue")
	local zonesTotal = #ZoneService.getZones()
	local elapsed = time() - battle.startTime

	table.clear(continueVotes)
	for _, player in Players:GetPlayers() do
		-- (kill XP was already given live, see onCasualties)
		local xp = if victory then Rewards.XPWin + zonesHeld * Rewards.XPPerZoneHeld else Rewards.XPLoss
		if victory and elapsed <= Rewards.FastWinTime then
			xp += Rewards.FastWinBonusXP
		end
		local unlocked = if victory then DataService.recordRoundWon(player) else {}
		DataService.addXP(player, xp)
		summaryRemote:FireClient(player, {
			victory = victory,
			round = round,
			side = cfg.side,
			killsDealt = battle.killsDealt,
			killsTaken = battle.killsTaken,
			zonesHeld = zonesHeld,
			zonesTotal = zonesTotal,
			timeTaken = elapsed,
			xpEarned = xp,
			unlocked = unlocked,
			nextRound = if victory then round + 1 else 1,
		})
	end

	setPhase("Reward", Phases.RewardTime, cfg, false, { result = result })
	local deadline = time() + Phases.RewardTime
	while time() < deadline do
		local everyone = true
		for _, player in Players:GetPlayers() do
			if not continueVotes[player] then
				everyone = false
			end
		end
		if everyone then
			break
		end
		task.wait(0.25)
	end

	battle = nil
	if victory then
		round += 1
	else
		round = 1
		RecruitmentService.resetAll()
	end
end

print("[Napoleonic Commander] server ready")
task.spawn(function()
	while true do
		while #Players:GetPlayers() == 0 do
			task.wait(1)
		end
		local cfg = GameConfig.getRound(round)
		runRecruitment(cfg)
		local result = runBattle(cfg)
		notifyAll(if result == "Victory" then "VICTORY!" else "DEFEAT", if result == "Victory" then "good" else "bad")
		runReward(cfg, result)
	end
end)
