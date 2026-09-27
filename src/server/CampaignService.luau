--[[
	CampaignService
	The mercenary overworld, one private campaign per player (saved in profile.Campaign):
	  • character creation: pick the faction you serve (Francia / Albion / Borussia)
	  • the map: towns, castles (change hands) and bandit camps, joined by roads
	  • travel: click a place or a point, your army walks there. Time controls ❚❚ ▶ ▶▶
	    (menus and towns pause time). Off-road travel is more dangerous (random encounters)
	  • towns: "Enter town" puts your commander on foot in a real town (TownService) where you
	    talk to people: contracts, recruits, mercenaries, quartermaster, arms merchant
	  • a living world: bandit warbands roam around their camps, faction patrols travel
	    between their castles; hostile parties chase you and force a battle on contact
	  • battles: queued for the single battlefield (GameManager runs them one at a time) and
	    resolved here — loot, gold penalty on defeat, retreat to your town, roster losses/XP

	Contracts live in QuestService, which plugs in through CampaignService.hooks.
	View per player: "Creation" → "Overworld" ⇄ "Battle" / "Town".
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local CampaignConfig = require(Modules:WaitForChild("CampaignConfig"))
local GameConfig = require(Modules:WaitForChild("GameConfig"))
local Remotes = require(Modules:WaitForChild("Remotes"))
local UnitDefinitions = require(Modules:WaitForChild("UnitDefinitions"))

local DataService = require(script.Parent:WaitForChild("DataService"))
local RecruitmentService = require(script.Parent:WaitForChild("RecruitmentService"))
local ReputationService = require(script.Parent:WaitForChild("ReputationService"))

local Travel = CampaignConfig.Travel
local Parties = CampaignConfig.Parties
local Difficulty = CampaignConfig.Difficulty
local Economy = CampaignConfig.Economy

local stateRemote = Remotes.get("CampaignState")
local tickRemote = Remotes.get("CampaignTick")
local notifyRemote = Remotes.get("Notify")

local CampaignService = {}

CampaignService.hooks = {
	-- QuestService plugs in here
	onNewDay = function(_camp: any) end,
	onTime = function(_camp: any) end, -- every tick while time flows
	onArrive = function(_camp: any, _location: any) end,
	onPartyArrived = function(_camp: any, _party: any) end, -- a party finished its route
	onPartyContact = function(_camp: any, _party: any, _target: any) end, -- a party reached its target party
	onPartyDefeated = function(_camp: any, _party: any) end,
	onFactionChosen = function(_camp: any) end,
	describe = function(_camp: any): any
		return nil
	end, -- { contract, board } for the client
}

-- defined with the town code below (declared here so earlier functions can call it)
CampaignService.refreshMercenaries = function(_camp: any) end

-- extra client actions registered by other services: actions[name] = function(camp, arg)
CampaignService.actions = {}

local camps: { [Player]: any } = {}
local battleQueue: { any } = {}
local rng = Random.new()

-- Where characters wait while their owner is on the overworld (far from the battlefield)
local CAMP_CFRAME = CFrame.new(0, 104, 9000)
do
	local platform = Instance.new("Part")
	platform.Name = "OverworldCamp"
	platform.Anchored = true
	platform.Size = Vector3.new(80, 2, 80)
	platform.CFrame = CAMP_CFRAME * CFrame.new(0, -4, 0)
	platform.Transparency = 1
	platform.Parent = Workspace
end
CampaignService.CampCFrame = CAMP_CFRAME
-- set by GameManager from TownService (where you appear when you enter a town)
CampaignService.TownCFrame = CAMP_CFRAME

local function v2(x: number, z: number): Vector2
	return Vector2.new(x, z)
end

local function locationPos(location: any): Vector2
	return v2(location.x, location.z)
end

function CampaignService.notify(camp: any, text: string, tone: string?)
	notifyRemote:FireClient(camp.player, text, tone or "info")
end

function CampaignService.markDirty(camp: any)
	camp.dirty = true
end

function CampaignService.get(player: Player): any
	return camps[player]
end

function CampaignService.employer(camp: any): string
	return camp.data.Faction
end

function CampaignService.threat(camp: any): number
	return math.min(Difficulty.MaxThreat, 1 + math.floor(camp.data.BattlesWon / Difficulty.ThreatPerWins))
end

function CampaignService.getOwner(camp: any, locationId: string): string
	local location = CampaignConfig.getLocation(locationId)
	return camp.data.CastleOwners[locationId] or (location and location.faction) or "Bandits"
end

function CampaignService.setOwner(camp: any, locationId: string, faction: string)
	camp.data.CastleOwners[locationId] = faction
	camp.dirty = true
end

-- Locations of a kind owned by a faction
function CampaignService.locationsOwnedBy(camp: any, faction: string, kind: string?): { any }
	local list = {}
	for _, location in CampaignConfig.Locations do
		if (not kind or location.kind == kind) and CampaignService.getOwner(camp, location.id) == faction then
			table.insert(list, location)
		end
	end
	return list
end

function CampaignService.homeTown(camp: any): any
	return CampaignService.locationsOwnedBy(camp, camp.data.Faction, "Town")[1]
end

function CampaignService.distanceToPlayer(camp: any, pos: Vector2): number
	return (camp.pos - pos).Magnitude
end

---------------------------------------------------------------------------
-- Parties (roaming icons on the map)
---------------------------------------------------------------------------

local function isHostile(camp: any, party: any): boolean
	return party.kind ~= "Caravan" and CampaignConfig.hostile(party.faction, camp.data.Faction)
end

--[[
	props = { kind, faction, name, pos, speed, strength, home?, roamRadius?, route?, targetParty?,
	          boss?, contractId?, waiting? }
	kind: "Bandit" | "Patrol" | "Bounty" | "Ambush" | "Caravan"
]]
function CampaignService.spawnParty(camp: any, props: any): any
	camp.nextPartyId += 1
	local party = props
	party.id = camp.nextPartyId
	party.dest = party.dest or party.pos
	party.noContactUntil = party.noContactUntil or 0
	camp.parties[party.id] = party
	return party
end

function CampaignService.removeParty(camp: any, party: any)
	camp.parties[party.id] = nil
end

local function randomStrength(camp: any, range: { number }): number
	return rng:NextInteger(range[1], range[2]) + CampaignService.threat(camp) - 1
end

local function farFromPlayer(camp: any, pos: Vector2): boolean
	return (pos - camp.pos).Magnitude > Parties.ChaseRadius + 30
end

local function clampToMap(pos: Vector2): Vector2
	local size = CampaignConfig.MapSize
	return v2(math.clamp(pos.X, 10, size - 10), math.clamp(pos.Y, 10, size - 10))
end

local function roamPoint(home: Vector2, radius: number): Vector2
	local angle = rng:NextNumber(0, math.pi * 2)
	return clampToMap(home + v2(math.cos(angle), math.sin(angle)) * rng:NextNumber(radius * 0.3, radius))
end

local function spawnBandits(camp: any)
	local camps_ = CampaignConfig.Locations
	local candidates = {}
	for _, location in camps_ do
		if location.kind == "BanditCamp" and farFromPlayer(camp, locationPos(location)) then
			table.insert(candidates, location)
		end
	end
	if #candidates == 0 then
		return
	end
	local home = candidates[rng:NextInteger(1, #candidates)]
	local homePos = locationPos(home)
	CampaignService.spawnParty(camp, {
		kind = "Bandit",
		faction = "Bandits",
		name = "Bandit warband",
		pos = roamPoint(homePos, 30),
		speed = Parties.BanditSpeed,
		strength = randomStrength(camp, Difficulty.BanditStrength),
		home = homePos,
		roamRadius = Parties.BanditRoamRadius,
	})
end

local function spawnPatrol(camp: any, faction: string)
	local owned = CampaignService.locationsOwnedBy(camp, faction)
	if #owned == 0 then
		return
	end
	local start = owned[rng:NextInteger(1, #owned)]
	if not farFromPlayer(camp, locationPos(start)) and faction ~= camp.data.Faction then
		return -- try again tomorrow rather than spawning on top of the player
	end
	CampaignService.spawnParty(camp, {
		kind = "Patrol",
		faction = faction,
		name = CampaignConfig.Factions[faction].short .. " patrol",
		pos = locationPos(start),
		speed = Parties.PatrolSpeed,
		strength = randomStrength(camp, Difficulty.PatrolStrength),
		patrol = true,
	})
end

-- Keep the world populated
local function maintainParties(camp: any)
	local bandits, patrols = 0, {}
	for _, party in camp.parties do
		if party.kind == "Bandit" then
			bandits += 1
		elseif party.kind == "Patrol" then
			patrols[party.faction] = (patrols[party.faction] or 0) + 1
		end
	end
	for _ = bandits + 1, Parties.BanditParties do
		spawnBandits(camp)
	end
	for _, faction in CampaignConfig.FactionOrder do
		for _ = (patrols[faction] or 0) + 1, Parties.PatrolsPerFaction do
			spawnPatrol(camp, faction)
		end
	end
end

local function pickPatrolDestination(camp: any, party: any): Vector2
	local owned = CampaignService.locationsOwnedBy(camp, party.faction)
	if #owned == 0 then
		return roamPoint(party.pos, 150)
	end
	return locationPos(owned[rng:NextInteger(1, #owned)])
end

---------------------------------------------------------------------------
-- Battles
---------------------------------------------------------------------------

local function enemyUnits(base: any): { any }
	local list = {}
	for _, wave in base.waves do
		for _, unit in wave.units do
			table.insert(list, unit)
		end
	end
	return list
end

-- Turn a battle spec into a GameManager battle config (reuses GameConfig.getRound)
local function buildBattleConfig(camp: any, spec: any): any
	local strength = math.max(1, spec.strength or 1)
	local base = GameConfig.getRound(strength)
	local bandits = spec.enemyFaction == "Bandits"
	local sourceWaves = if spec.kind == "Raid"
		then base.waves -- castle garrisons get relief columns
		else { { delay = 0, units = enemyUnits(base) } }
	local waves = {}
	for _, wave in sourceWaves do
		local units = {}
		for _, unit in wave.units do
			if unit == base.boss then
				continue -- the boss is added below
			end
			local copy = table.clone(unit)
			if bandits then
				if Difficulty.BanditNoArtillery then
					if copy.unitId == "Artillery" then
						copy.unitId = "Skirmishers"
					elseif copy.unitId == "EliteGuard" then
						copy.unitId = "LineInfantry"
					end
				end
				copy.statMultiplier = (copy.statMultiplier or 1) * Difficulty.BanditStatMult
				copy.damageMultiplier = (copy.damageMultiplier or 1) * Difficulty.BanditStatMult
				copy.name = "Bandit " .. UnitDefinitions.get(copy.unitId).displayName
			end
			table.insert(units, copy)
		end
		table.insert(waves, { delay = wave.delay, units = units })
	end
	local boss = spec.boss or (if bandits then nil else base.boss)
	if boss then
		table.insert(waves[#waves].units, boss)
	end
	local allies = {}
	local employer = CampaignConfig.Factions[camp.data.Faction]
	for _, unitId in spec.allies or {} do
		table.insert(
			allies,
			{ unitId = unitId, name = employer.short .. " " .. UnitDefinitions.get(unitId).displayName }
		)
	end
	local side = spec.side or "Defender"
	return {
		round = strength,
		title = spec.title,
		side = side,
		allies = allies,
		winCondition = if side == "Attacker" then "CaptureZones" else "Eliminate",
		waves = waves,
		boss = boss,
		ai = base.ai,
		reinforcements = CampaignConfig.Battle.Reinforcements,
		teamFactions = { Blue = camp.data.Faction, Red = spec.enemyFaction },
	}
end

--[[
	Queue a battle for this player. spec = { kind, title, enemyFaction, strength, side?, allies?,
	boss?, party?, onVictory?(camp, lines), onDefeat?(camp, lines) }
	The battle loads after a short warning banner.
]]
function CampaignService.startBattle(camp: any, spec: any)
	if camp.pendingBattle or camp.view ~= "Overworld" then
		return
	end
	camp.pendingBattle = spec
	camp.moving = false
	camp.dirty = true
	spec.player = camp.player
	spec.camp = camp
	spec.cfg = buildBattleConfig(camp, spec)
	stateRemote:FireClient(camp.player, { encounter = { title = spec.title, faction = spec.enemyFaction } })
	task.delay(Travel.EncounterWarning, function()
		if camps[camp.player] == camp and camp.pendingBattle == spec then
			table.insert(battleQueue, spec)
			camp.dirty = true
		end
	end)
end

-- Blocks until a battle is queued (GameManager's loop)
function CampaignService.waitForBattle(): any
	while true do
		while #battleQueue == 0 do
			task.wait(0.25)
		end
		local spec = table.remove(battleQueue, 1)
		if spec.player.Parent and camps[spec.player] == spec.camp then
			return spec
		end
	end
end

-- Park a character on the overworld platform (out of the battlefield)
local function parkCharacter(player: Player)
	local character = player.Character
	if character then
		character:PivotTo(CAMP_CFRAME * CFrame.new(rng:NextNumber(-20, 20), 0, rng:NextNumber(-20, 20)))
	end
end

function CampaignService.onBattleStarting(spec: any)
	local camp = spec.camp
	camp.view = "Battle"
	camp.dirty = true
	CampaignService.flush(camp)
end

function CampaignService.inBattle(player: Player): boolean
	local camp = camps[player]
	return camp ~= nil and camp.view == "Battle"
end

local function retreatHome(camp: any)
	local town = CampaignService.homeTown(camp)
	if town then
		camp.pos = locationPos(town)
		camp.atLocation = town.id
	end
	camp.dest = nil
	camp.moving = false
end

--[[
	Called by GameManager when the battle ends, before the summary screen.
	Applies every consequence and returns report lines (rich text) for the summary.
]]
function CampaignService.resolveBattle(spec: any, victory: boolean): { string }
	local camp = spec.camp
	local data = camp.data
	local lines = {}
	camp.pendingReport = lines
	if victory then
		data.BattlesWon += 1
		for _, name in DataService.recordRoundWon(camp.player) do
			table.insert(lines, string.format('<font color="#78E682"><b>New unit available: %s!</b></font>', name))
		end
		local party = spec.party
		if party then
			local loot = math.floor(Economy.LootBase + Economy.LootPerStrength * (party.strength or 1))
			if loot > 0 then
				data.Gold += loot
				table.insert(lines, string.format('Loot: <font color="#FFCD28"><b>+%d gold</b></font>', loot))
			end
			CampaignService.removeParty(camp, party)
			CampaignService.hooks.onPartyDefeated(camp, party)
		end
		if spec.onVictory then
			spec.onVictory(camp, lines)
		end
	else
		local penalty = math.floor(data.Gold * Economy.LossGoldPercent + Economy.LossGoldFlat)
		penalty = math.min(data.Gold, penalty)
		if penalty > 0 then
			data.Gold -= penalty
			table.insert(lines, string.format('<font color="#FF8070">Defeat costs you <b>%d gold</b>.</font>', penalty))
		end
		if spec.party then
			spec.party.noContactUntil = data.Day + 1.5
		end
		if spec.onDefeat then
			spec.onDefeat(camp, lines)
		end
		retreatHome(camp)
		table.insert(
			lines,
			"Your army falls back to " .. (CampaignService.homeTown(camp) or { name = "town" }).name .. "."
		)
	end
	local report = RecruitmentService.afterBattle(camp.player, victory)
	for _, name in report.lost do
		table.insert(
			lines,
			string.format('<font color="#FF8070">💀 %s was wiped out — gone for good.</font>', name)
		)
	end
	for _, evolved in report.evolved do
		table.insert(
			lines,
			string.format(
				'<font color="#FFCD28">★ %s evolved: %s %s</font>',
				evolved.name,
				evolved.tierName,
				string.rep("★", evolved.stars)
			)
		)
	end
	if RecruitmentService.ensureArmy(camp.player) then
		table.insert(lines, "With no army left, a few volunteers join you as a levy.")
	end
	camp.safeUntil = data.Day + Travel.SafeAfterBattleDays
	camp.pendingReport = nil
	return lines
end

function CampaignService.onBattleFinished(spec: any)
	local camp = spec.camp
	if camps[camp.player] ~= camp then
		return
	end
	camp.pendingBattle = nil
	camp.view = "Overworld"
	camp.dirty = true
	parkCharacter(camp.player)
	CampaignService.flush(camp)
end

---------------------------------------------------------------------------
-- Players
---------------------------------------------------------------------------

local function newRuntime(player: Player, data: any): any
	local camp = {
		player = player,
		data = data,
		view = if data.Faction then "Overworld" else "Creation",
		pos = v2(500, 500),
		dest = nil,
		destLocation = nil,
		atLocation = nil,
		moving = false,
		timeMode = "Play", -- "Pause" | "Play" | "Fast"
		paused = false, -- a menu is open
		mercenaries = {},
		mercenaryRefreshDay = 0,
		parties = {},
		nextPartyId = 0,
		safeUntil = 0,
		pendingBattle = nil,
		board = {},
		contract = nil,
		dirty = true,
		sendTimer = 0,
	}
	return camp
end

local function startCampaign(camp: any)
	retreatHome(camp)
	maintainParties(camp)
	CampaignService.refreshMercenaries(camp)
	CampaignService.hooks.onFactionChosen(camp)
	camp.dirty = true
end

function CampaignService.initPlayer(player: Player)
	local data = DataService.getCampaign(player)
	if not data then
		return
	end
	local camp = newRuntime(player, data)
	camps[player] = camp
	if data.Faction then
		startCampaign(camp)
	end
	parkCharacter(player)
	CampaignService.flush(camp)
end

function CampaignService.removePlayer(player: Player)
	camps[player] = nil
end

---------------------------------------------------------------------------
-- Client state
---------------------------------------------------------------------------

function CampaignService.flush(camp: any)
	camp.dirty = false
	local data = camp.data
	local owners = {}
	for _, location in CampaignConfig.Locations do
		owners[location.id] = CampaignService.getOwner(camp, location.id)
	end
	local reputation = ReputationService.get(camp.player)
	local tier, nextTier = CampaignConfig.reputationTier(reputation)
	local quest = CampaignService.hooks.describe(camp) or {}
	local queued = table.find(battleQueue, camp.pendingBattle) ~= nil
	stateRemote:FireClient(camp.player, {
		view = camp.view,
		faction = data.Faction,
		gold = math.floor(data.Gold),
		reputation = reputation,
		tier = tier,
		nextTier = nextTier,
		day = data.Day,
		owners = owners,
		atLocation = camp.atLocation,
		contract = quest.contract,
		board = quest.board,
		battlesWon = data.BattlesWon,
		threat = CampaignService.threat(camp),
		queued = queued and CampaignService.battlefieldBusy(camp.player),
		timeMode = camp.timeMode,
		mercenaries = camp.mercenaries,
	})
	RecruitmentService.sendState(camp.player)
end

local function sendTick(camp: any)
	local parties = {}
	for _, party in camp.parties do
		table.insert(parties, {
			id = party.id,
			kind = party.kind,
			faction = party.faction,
			name = party.name,
			x = party.pos.X,
			z = party.pos.Y,
			strength = party.strength,
			hostile = isHostile(camp, party),
			contract = party.contractId ~= nil,
		})
	end
	tickRemote:FireClient(camp.player, {
		day = camp.data.Day,
		x = camp.pos.X,
		z = camp.pos.Y,
		moving = camp.moving,
		waiting = camp.timeMode == "Fast",
		timeMode = camp.timeMode,
		dest = if camp.dest and camp.moving then { x = camp.dest.X, z = camp.dest.Y } else nil,
		parties = parties,
	})
end

-- Is another player's battle using the field while this player waits?
local currentBattlePlayer: Player? = nil
function CampaignService.setCurrentBattle(player: Player?)
	currentBattlePlayer = player
end
function CampaignService.battlefieldBusy(player: Player): boolean
	return currentBattlePlayer ~= nil and currentBattlePlayer ~= player
end

---------------------------------------------------------------------------
-- Simulation
---------------------------------------------------------------------------

local function nearestLocation(pos: Vector2, radius: number): any
	local best, bestDistance = nil, radius
	for _, location in CampaignConfig.Locations do
		local distance = (locationPos(location) - pos).Magnitude
		if distance <= bestDistance then
			best, bestDistance = location, distance
		end
	end
	return best
end

local function moveToward(from: Vector2, to: Vector2, step: number): (Vector2, boolean)
	local offset = to - from
	if offset.Magnitude <= step then
		return to, true
	end
	return from + offset.Unit * step, false
end

local function randomEncounter(camp: any)
	local encounters = CampaignConfig.Encounters
	local offset = v2(rng:NextNumber(-1, 1), rng:NextNumber(-1, 1))
	offset = if offset.Magnitude > 0.01 then offset.Unit * 18 else v2(18, 0)
	local party
	if rng:NextNumber() < encounters.RivalPatrolShare then
		local rivals = {}
		for _, faction in CampaignConfig.FactionOrder do
			if faction ~= camp.data.Faction then
				table.insert(rivals, faction)
			end
		end
		local faction = rivals[rng:NextInteger(1, #rivals)]
		party = CampaignService.spawnParty(camp, {
			kind = "Patrol",
			faction = faction,
			name = CampaignConfig.Factions[faction].short .. " patrol",
			pos = clampToMap(camp.pos + offset),
			speed = Parties.PatrolSpeed,
			strength = randomStrength(camp, Difficulty.PatrolStrength),
			patrol = true,
		})
	else
		party = CampaignService.spawnParty(camp, {
			kind = "Bandit",
			faction = "Bandits",
			name = "Bandit warband",
			pos = clampToMap(camp.pos + offset),
			speed = Parties.BanditSpeed,
			strength = randomStrength(camp, Difficulty.BanditStrength),
			home = camp.pos,
			roamRadius = Parties.BanditRoamRadius,
		})
	end
	CampaignService.notify(camp, "Ambush! A " .. party.name .. " falls upon your column!", "bad")
	CampaignService.battleWithParty(camp, party, "Ambush!")
end

-- Fight a roaming party (contact, chase, ambush)
function CampaignService.battleWithParty(camp: any, party: any, title: string?)
	CampaignService.startBattle(camp, {
		kind = party.kind,
		title = (title or "Battle") .. " — " .. party.name,
		enemyFaction = party.faction,
		strength = party.strength,
		side = "Defender",
		allies = party.battleAllies,
		boss = party.boss,
		party = party,
		onVictory = party.onVictory,
		onDefeat = party.onDefeat,
	})
end

local function updateParties(camp: any, dtDays: number)
	local day = camp.data.Day
	local safe = day < camp.safeUntil
	for _, party in table.clone(camp.parties) do
		if not camp.parties[party.id] then
			continue
		end
		if party.paused or party.waiting then
			continue
		end
		local speed = party.speed
		local toPlayer = (camp.pos - party.pos).Magnitude
		local hostile = isHostile(camp, party)
		if party.targetParty then
			-- ambushers go for their prey (a caravan)
			local target = camp.parties[party.targetParty]
			if not target then
				CampaignService.removeParty(camp, party)
				continue
			end
			party.dest = target.pos
		elseif hostile and not safe and day >= party.noContactUntil and toPlayer <= Parties.ChaseRadius then
			party.dest = camp.pos
			speed *= Parties.ChaseSpeedMult
		elseif party.route then
			party.dest = party.route[party.routeIndex or 1]
		end
		local arrived
		party.pos, arrived = moveToward(party.pos, party.dest, speed * dtDays)
		if party.route and arrived and not party.targetParty then
			party.routeIndex = (party.routeIndex or 1) + 1
			if party.routeIndex > #party.route then
				party.route = nil
				CampaignService.hooks.onPartyArrived(camp, party)
				continue
			end
		elseif arrived and not party.route and not party.targetParty then
			if party.patrol then
				party.dest = pickPatrolDestination(camp, party)
			elseif party.home then
				party.dest = roamPoint(party.home, party.roamRadius or Parties.BanditRoamRadius)
			end
		end
		if party.targetParty then
			local target = camp.parties[party.targetParty]
			if target and (target.pos - party.pos).Magnitude <= Travel.ContactRadius then
				CampaignService.hooks.onPartyContact(camp, party, target)
				if camp.pendingBattle then
					return
				end
				continue
			end
		end
		-- contact with the player's army
		toPlayer = (camp.pos - party.pos).Magnitude
		if hostile and not safe and day >= party.noContactUntil and toPlayer <= Travel.ContactRadius then
			CampaignService.battleWithParty(camp, party, "Battle")
			return
		end
	end
end

local function advanceTime(camp: any, dtDays: number)
	local data = camp.data
	local before = math.floor(data.Day)
	data.Day += dtDays
	if math.floor(data.Day) > before then
		maintainParties(camp)
		if data.Day >= camp.mercenaryRefreshDay then
			CampaignService.refreshMercenaries(camp)
		end
		CampaignService.hooks.onNewDay(camp)
		camp.dirty = true
	end
	CampaignService.hooks.onTime(camp)
end

local function stepCamp(camp: any, dt: number)
	if camp.view ~= "Overworld" or camp.pendingBattle then
		return
	end
	local timeScale = if camp.paused or camp.timeMode == "Pause"
		then 0
		elseif camp.timeMode == "Fast" then Travel.FastSpeedMult
		else 1
	if timeScale <= 0 then
		return
	end
	local dtDays = dt * Travel.DaysPerSecond * timeScale
	advanceTime(camp, dtDays)
	if camp.pendingBattle then
		return
	end
	if camp.moving and camp.dest then
		local arrived
		camp.pos, arrived = moveToward(camp.pos, camp.dest, Travel.ArmySpeed * dtDays)
		camp.atLocation = nil
		if arrived then
			camp.moving = false
			local location = nearestLocation(camp.pos, Travel.ArriveRadius)
			if location then
				camp.atLocation = location.id
				CampaignService.hooks.onArrive(camp, location)
			end
			camp.dirty = true
		elseif camp.data.Day >= camp.safeUntil then
			-- random encounters: far more likely off the road
			local onRoad = CampaignConfig.distanceToRoad(camp.pos.X, camp.pos.Y) <= Travel.RoadWidth
			local chance = if onRoad
				then CampaignConfig.Encounters.ChancePerDayOnRoad
				else CampaignConfig.Encounters.ChancePerDayOffRoad
			if rng:NextNumber() < chance * dtDays then
				randomEncounter(camp)
				return
			end
		end
	end
	updateParties(camp, dtDays)
end

RunService.Heartbeat:Connect(function(dt)
	for _, camp in camps do
		local ok, err = pcall(stepCamp, camp, dt)
		if not ok then
			warn("CampaignService:", err)
		end
		camp.sendTimer += dt
		if camp.view == "Overworld" and camp.sendTimer >= 0.2 then
			camp.sendTimer = 0
			sendTick(camp)
		end
		if camp.dirty then
			CampaignService.flush(camp)
		end
	end
end)

---------------------------------------------------------------------------
-- Client actions
---------------------------------------------------------------------------

local function atFriendly(camp: any, kinds: { string }): any
	local location = camp.atLocation and CampaignConfig.getLocation(camp.atLocation)
	if
		location
		and table.find(kinds, location.kind)
		and CampaignService.getOwner(camp, location.id) == camp.data.Faction
	then
		return location
	end
	return nil
end
CampaignService.atFriendly = atFriendly

local ACTIONS = {}
local TOWN_ACTIONS: { [string]: boolean }

function ACTIONS.ChooseFaction(camp: any, faction: unknown)
	if camp.data.Faction or typeof(faction) ~= "string" or not table.find(CampaignConfig.FactionOrder, faction) then
		return
	end
	camp.data.Faction = faction
	camp.data.Reputation[faction] = camp.data.Reputation[faction] or 0
	if #camp.data.Roster == 0 then
		RecruitmentService.giveStartingRoster(camp.player)
	end
	camp.view = "Overworld"
	startCampaign(camp)
	CampaignService.notify(
		camp,
		"You now fight for the " .. CampaignConfig.Factions[faction].displayName .. ".",
		"good"
	)
end

function ACTIONS.Travel(camp: any, arg: unknown)
	if typeof(arg) ~= "table" then
		return
	end
	local target: Vector2? = nil
	local locationId = (arg :: any).location
	if typeof(locationId) == "string" then
		local location = CampaignConfig.getLocation(locationId)
		if location then
			target = locationPos(location)
		end
	else
		local x, z = (arg :: any).x, (arg :: any).z
		if typeof(x) == "number" and typeof(z) == "number" and x == x and z == z then
			target = clampToMap(v2(x, z))
		end
	end
	if target then
		camp.dest = target
		camp.moving = (target - camp.pos).Magnitude > 0.5
		if camp.timeMode == "Pause" then
			camp.timeMode = "Play" -- giving a march order un-pauses, like Bannerlord
		end
		camp.paused = false
		camp.atLocation = nil
		camp.dirty = true
	end
end

function ACTIONS.Stop(camp: any)
	camp.moving = false
	camp.dirty = true
end

function ACTIONS.TimeMode(camp: any, mode: unknown)
	if mode == "Pause" or mode == "Play" or mode == "Fast" then
		camp.timeMode = mode
		camp.dirty = true
	end
end

-- (older clients) Wait = fast-forward
function ACTIONS.Wait(camp: any, on: unknown)
	ACTIONS.TimeMode(camp, if on == true then "Fast" else "Play")
end

function ACTIONS.Pause(camp: any, on: unknown)
	camp.paused = on == true
end

function ACTIONS.Hire(camp: any, unitId: unknown)
	if typeof(unitId) ~= "string" then
		return
	end
	if not atFriendly(camp, { "Town" }) then
		CampaignService.notify(camp, "You can only hire in one of your employer's towns.", "bad")
		return
	end
	local ok, message = RecruitmentService.hire(camp.player, unitId)
	CampaignService.notify(camp, message, if ok then "good" else "bad")
	camp.dirty = true
end

function ACTIONS.Replenish(camp: any)
	if not atFriendly(camp, { "Town", "Castle" }) then
		CampaignService.notify(camp, "Replenish in a town or castle of your employer.", "bad")
		return
	end
	local added, spent = RecruitmentService.replenish(camp.player)
	if added > 0 then
		CampaignService.notify(camp, string.format("%d recruits joined your squads (-%d gold)", added, spent), "good")
	else
		CampaignService.notify(camp, "Nothing to replenish (or not enough gold).", "info")
	end
	camp.dirty = true
end

function ACTIONS.Dismiss(camp: any, squadId: unknown)
	if typeof(squadId) == "number" and #camp.data.Roster > 1 then
		RecruitmentService.dismiss(camp.player, squadId)
		camp.dirty = true
	end
end

---------------------------------------------------------------------------
-- Towns: walk around, talk to people
---------------------------------------------------------------------------

function ACTIONS.EnterTown(camp: any)
	local town = atFriendly(camp, { "Town" })
	if not town then
		return
	end
	camp.view = "Town"
	camp.moving = false
	camp.paused = false
	local character = camp.player.Character
	if character then
		character:PivotTo(CampaignService.TownCFrame)
	end
	camp.dirty = true
end

function ACTIONS.LeaveTown(camp: any)
	if camp.view == "Town" then
		camp.view = "Overworld"
		parkCharacter(camp.player)
		camp.dirty = true
	end
end

-- Where a character (re)spawns outside battles
function CampaignService.spawnCFrame(player: Player): CFrame
	local camp = camps[player]
	return if camp and camp.view == "Town" then CampaignService.TownCFrame else CAMP_CFRAME
end

local TownConfig = CampaignConfig.Town

local function refreshMercenaries(camp: any)
	camp.mercenaries = {}
	local units = {}
	for _, unitId in UnitDefinitions.Order do
		if DataService.isUnlocked(camp.player, unitId) then
			table.insert(units, unitId)
		end
	end
	for i = 1, TownConfig.MercenaryOffers do
		local unitId = units[rng:NextInteger(1, #units)]
		local stars = rng:NextInteger(TownConfig.MercenaryStars[1], TownConfig.MercenaryStars[2])
		table.insert(camp.mercenaries, {
			id = i + math.floor(camp.data.Day) * 10,
			unitId = unitId,
			stars = stars,
			xp = CampaignConfig.tierInfo(stars).xp,
			cost = math.floor(RecruitmentService.hireCost(unitId) * (1 + stars * TownConfig.MercenaryCostPerStar)),
		})
	end
	camp.mercenaryRefreshDay = camp.data.Day + TownConfig.MercenaryRefreshDays
	camp.dirty = true
end
CampaignService.refreshMercenaries = refreshMercenaries

function ACTIONS.HireMercenary(camp: any, id: unknown)
	if not atFriendly(camp, { "Town" }) then
		return
	end
	for index, offer in camp.mercenaries do
		if offer.id == id then
			local data = camp.data
			if #data.Roster >= Economy.MaxRosterSize then
				CampaignService.notify(camp, "Your company is full (" .. Economy.MaxRosterSize .. " squads).", "bad")
			elseif data.Gold < offer.cost then
				CampaignService.notify(camp, "Not enough gold (" .. offer.cost .. " needed).", "bad")
			else
				data.Gold -= offer.cost
				local entry = RecruitmentService.addSquad(camp.player, offer.unitId)
				entry.xp = offer.xp
				table.remove(camp.mercenaries, index)
				CampaignService.notify(
					camp,
					string.format(
						"The free company joins you: %s %s",
						UnitDefinitions.get(offer.unitId).displayName,
						string.rep("★", offer.stars)
					),
					"good"
				)
				RecruitmentService.sendState(camp.player)
			end
			camp.dirty = true
			return
		end
	end
end

function CampaignService.drillCost(entry: any): number
	local stars = CampaignConfig.tierForXP(entry.xp)
	return math.floor(TownConfig.DrillCost * (1 + stars * TownConfig.DrillCostPerStar))
end

-- Arms merchant: better kit and drill for one squad (gold → squad XP)
function ACTIONS.Drill(camp: any, squadId: unknown)
	if not atFriendly(camp, { "Town" }) then
		return
	end
	for _, entry in camp.data.Roster do
		if entry.id == squadId then
			local cost = CampaignService.drillCost(entry)
			if camp.data.Gold < cost then
				CampaignService.notify(camp, "Not enough gold (" .. cost .. " needed).", "bad")
				return
			end
			local before = CampaignConfig.tierForXP(entry.xp)
			camp.data.Gold -= cost
			entry.xp += TownConfig.DrillXP
			local after = CampaignConfig.tierForXP(entry.xp)
			CampaignService.notify(
				camp,
				if after > before
					then string.format(
						"Your squad evolves: %s %s",
						CampaignConfig.tierInfo(after).name,
						string.rep("★", after)
					)
					else string.format("New kit and hard drill: +%d XP (-%d gold)", TownConfig.DrillXP, cost),
				"good"
			)
			RecruitmentService.sendState(camp.player)
			camp.dirty = true
			return
		end
	end
end

-- Start over (new character): wipes the campaign, keeps commander level and unlocks
function ACTIONS.NewCampaign(camp: any)
	DataService.resetCampaign(camp.player)
	local data = DataService.getCampaign(camp.player)
	local fresh = newRuntime(camp.player, data)
	camps[camp.player] = fresh
	CampaignService.flush(fresh)
end

TOWN_ACTIONS = {
	Hire = true,
	Replenish = true,
	Dismiss = true,
	HireMercenary = true,
	Drill = true,
	LeaveTown = true,
	AcceptContract = true,
	DeclineContract = true,
	AbandonContract = true,
	Pause = true,
}

Remotes.get("CampaignAction").OnServerEvent:Connect(function(player: Player, action: unknown, arg: unknown)
	local camp = camps[player]
	if not camp or typeof(action) ~= "string" then
		return
	end
	local busy = camp.view == "Battle" or camp.pendingBattle ~= nil
	if action == "NewCampaign" then
		if busy then
			return
		end
	elseif camp.view == "Town" then
		if not TOWN_ACTIONS[action] then
			return -- in town you can only deal with its people (or leave)
		end
	elseif action ~= "ChooseFaction" and (camp.view ~= "Overworld" or busy) then
		return
	end
	local handler = ACTIONS[action] or CampaignService.actions[action]
	if handler then
		handler(camp, arg)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	camps[player] = nil
end)

return CampaignService
