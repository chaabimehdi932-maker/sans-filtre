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
	onGearChanged = function(_player: Player) end, -- PlayerCombatService re-equips the commander
	onVillageRaided = function(_camp: any, _villageId: string) end, -- QuestService (raid contracts)
	onSiegeStarted = function(_camp: any, _lord: any, _castleId: string) end, -- QuestService posts a Defend contract
	onSiegeEnded = function(_camp: any, _lord: any) end, -- QuestService drops that contract
	describe = function(_camp: any): any
		return nil
	end, -- { contract, board } for the client
}

-- defined with the town code below (declared here so earlier functions can call it)
CampaignService.refreshMercenaries = function(_camp: any) end
CampaignService.atFriendly = function(_camp: any, _kinds: { string }): any
	return nil
end
CampaignService.stepRaid = function(_camp: any, _dtDays: number) end
CampaignService.lordRaids = function(_camp: any, _lord: any) end
CampaignService.lordSieges = function(_camp: any, _lord: any, _dtDays: number) end

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
local Enlist = CampaignConfig.Enlist

-- A general's army: big, hunts the enemies of its faction; you can enlist in your employer's
local function spawnLord(camp: any, faction: string, strength: number?)
	local owned = CampaignService.locationsOwnedBy(camp, faction)
	if #owned == 0 then
		return
	end
	local start = owned[rng:NextInteger(1, #owned)]
	local names = Enlist.Generals[faction] or { "The General" }
	local used = {}
	for _, party in camp.parties do
		if party.lordName then
			used[party.lordName] = true
		end
	end
	local name = names[1]
	for _, candidate in names do
		if not used[candidate] then
			name = candidate
			break
		end
	end
	CampaignService.spawnParty(camp, {
		kind = "Lord",
		faction = faction,
		name = name .. "'s army",
		lordName = name,
		pos = locationPos(start),
		speed = Enlist.LordSpeed,
		strength = strength or randomStrength(camp, Enlist.LordStrength),
		maxStrength = randomStrength(camp, Enlist.LordStrength), -- he rebuilds up to this
		wounded = 0,
		home = start.id,
		patrol = true,
	})
end

local function maintainParties(camp: any)
	local bandits, patrols, lords = 0, {}, {}
	for _, party in camp.parties do
		if party.kind == "Bandit" then
			bandits += 1
		elseif party.kind == "Patrol" then
			patrols[party.faction] = (patrols[party.faction] or 0) + 1
		elseif party.kind == "Lord" then
			lords[party.faction] = (lords[party.faction] or 0) + 1
		end
	end
	camp.lordRespawn = camp.lordRespawn or {}
	for _, faction in CampaignConfig.FactionOrder do
		-- a destroyed general is replaced only after a while, and starts weak
		local respawnAt = camp.lordRespawn[faction]
		if not respawnAt or camp.data.Day >= respawnAt then
			for _ = (lords[faction] or 0) + 1, Enlist.LordsPerFaction do
				spawnLord(camp, faction, if respawnAt then CampaignConfig.Generals.RespawnStrength else nil)
			end
			camp.lordRespawn[faction] = nil
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

-- regular unit → what a bandit band fields instead
local BANDIT_EQUIVALENT = {
	LineInfantry = "BanditSwordsmen",
	Skirmishers = "BanditGunners",
	Cavalry = "BanditSwordsmen",
	Artillery = "BanditGunners",
	Howitzer = "BanditGunners",
	EliteGuard = "BanditSwordsmen",
}

-- Turn a battle spec into a GameManager battle config (reuses GameConfig.getRound)
local function buildBattleConfig(camp: any, spec: any): any
	local strength = math.max(1, math.floor(spec.strength or 1))
	local base = GameConfig.getRound(strength)
	local bandits = spec.enemyFaction == "Bandits"
	local sourceWaves = if spec.kind == "Raid"
		then base.waves -- castle garrisons get relief columns
		else { { delay = 0, units = enemyUnits(base) } }
	local waves = {}
	local bandIndex = 0
	for _, wave in sourceWaves do
		local units = {}
		for _, unit in wave.units do
			if unit == base.boss then
				continue -- the boss is added below
			end
			local copy = table.clone(unit)
			if bandits then
				-- bandits field their own troops: sword-and-buckler brawlers and gunners
				bandIndex += 1
				copy.unitId = BANDIT_EQUIVALENT[copy.unitId] or "BanditSwordsmen"
				if copy.unitId == "BanditSwordsmen" and bandIndex % 5 == 0 then
					copy.unitId = "BanditGunners" -- a few extra guns among the line
				end
				copy.statMultiplier = (copy.statMultiplier or 1) * Difficulty.BanditStatMult
				copy.damageMultiplier = (copy.damageMultiplier or 1) * Difficulty.BanditStatMult
				copy.name = nil
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
	-- where the fight happens decides the battlefield (Mount & Blade style)
	local battlefield
	if spec.kind == "Raid" or spec.kind == "Garrison" then
		battlefield = { theme = "Castle", defender = if spec.kind == "Raid" then "Red" else "Blue" }
		-- the castle flies its owner's banner (the kingdom holding it right now)
		local owner = spec.castleId and CampaignConfig.Factions[CampaignService.getOwner(camp, spec.castleId)]
		if owner then
			battlefield.banner = { color = owner.color, emblem = owner.emblem, name = owner.short }
		end
	else
		-- field battles (encounters, ambushes, bounties, escorts, generals' fights): open
		-- terrain shaped by where you are on the map, no buildings, no capture zones
		local near = CampaignConfig.nearPlace(camp.pos.X, camp.pos.Y)
		battlefield = { theme = CampaignConfig.terrainThemeAt(camp.pos.X, camp.pos.Y), field = true }
		battlefield.place = near and ("near " .. near.name)
	end
	battlefield.name = CampaignConfig.BattlefieldNames[battlefield.theme]
		.. (if battlefield.place then " · " .. battlefield.place else "")
	return {
		enlisted = spec.enlisted,
		lordName = spec.lordName,
		battlefield = battlefield,
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
local PrisonerRules = CampaignConfig.Prisoners

function CampaignService.prisonerCount(camp: any): number
	local total = 0
	for _, count in camp.data.Prisoners or {} do
		total += count
	end
	return total
end

function CampaignService.ransomValue(camp: any): number
	local total = 0
	for unitId, count in camp.data.Prisoners or {} do
		local def = UnitDefinitions.get(unitId)
		if def then
			local mult = if def.hidden then PrisonerRules.BanditRansomMult else PrisonerRules.RansomMult
			total += count * (def.cost or 100) / def.soldiers * mult
		end
	end
	return math.floor(total)
end

-- Take routed enemies prisoner, up to the capacity. Returns a report line or nil.
local function takePrisoners(camp: any, prisoners: { [string]: number }): string?
	local data = camp.data
	data.Prisoners = data.Prisoners or {}
	local room = PrisonerRules.Capacity - CampaignService.prisonerCount(camp)
	local taken, released, parts = 0, 0, {}
	for unitId, count in prisoners do
		local keep = math.clamp(room - taken, 0, count)
		released += count - keep
		if keep > 0 then
			taken += keep
			data.Prisoners[unitId] = (data.Prisoners[unitId] or 0) + keep
			table.insert(parts, UnitDefinitions.get(unitId).displayName .. " ×" .. keep)
		end
	end
	if taken == 0 and released == 0 then
		return nil
	end
	return string.format(
		"⛓ %d prisoners taken%s%s",
		taken,
		if #parts > 0 then " (" .. table.concat(parts, ", ") .. ")" else "",
		if released > 0 then string.format(" — %d released, no room", released) else ""
	)
end

function CampaignService.resolveBattle(spec: any, victory: boolean, prisoners: { [string]: number }?): { string }
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
			if spec.enlisted then
				loot = math.floor(loot * Enlist.LootShare) -- the general keeps most of it
			end
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
		-- a piece of gear left on the field
		local lootChance = CampaignConfig.ItemLootChance + (spec.strength or 1) * 0.02
		if not spec.enlisted and rng:NextNumber() < lootChance then
			local owned = {}
			for _, id in data.Items do
				owned[id] = true
			end
			local pool = {}
			for _, id in CampaignConfig.ItemOrder do
				if not owned[id] and CampaignConfig.Items[id].price > 0 then
					table.insert(pool, id)
				end
			end
			if #pool > 0 then
				local id = pool[rng:NextInteger(1, #pool)]
				table.insert(data.Items, id)
				table.insert(
					lines,
					string.format(
						'<font color="#FFCD28">🎁 Found on the field: %s!</font>',
						CampaignConfig.Items[id].name
					)
				)
			end
		end
		if prisoners and not spec.enlisted then
			local line = takePrisoners(camp, prisoners)
			if line then
				table.insert(lines, line)
			end
		end
	else
		local penalty = math.floor(data.Gold * Economy.LossGoldPercent + Economy.LossGoldFlat)
		if spec.enlisted then
			penalty = 0 -- a soldier in someone else's army loses no gold
		end
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
		if not camp.enlisted then
			retreatHome(camp)
			table.insert(
				lines,
				"Your army falls back to " .. (CampaignService.homeTown(camp) or { name = "town" }).name .. "."
			)
		end
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
				'<font color="#FFCD28">★ %s evolved: %s %s%s</font>',
				evolved.name,
				evolved.tierName,
				string.rep("★", evolved.stars),
				if evolved.branch then " — choose its new path in your company panel!" else ""
			)
		)
	end
	local woundedTotal, deadTotal = 0, 0
	for _, c in report.casualties do
		woundedTotal += c.wounded
		deadTotal += c.dead
	end
	if woundedTotal + deadTotal > 0 then
		table.insert(
			lines,
			string.format(
				'<font color="#FFB070">🩹 %d wounded (they will heal), %d dead.</font>',
				woundedTotal,
				deadTotal
			)
		)
	end
	for _, name in report.wounded do
		table.insert(
			lines,
			string.format(
				'<font color="#FFB070">✚ %s is wounded and can\'t lead for %d days.</font>',
				name,
				CampaignConfig.Companions.WoundDays
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
		prisoners = camp.data.Prisoners or {},
		gear = camp.data.Gear,
		companions = CampaignService.describeCompanions(camp),
		villages = camp.data.VillageProsperity or {},
		garrisons = camp.data.Garrisons or {},
		sieges = CampaignService.describeSieges(camp),
		items = camp.data.Items,
		prisonerCount = CampaignService.prisonerCount(camp),
		prisonerCapacity = CampaignConfig.Prisoners.Capacity,
		ransomValue = CampaignService.ransomValue(camp),
		enlisted = CampaignService.describeEnlisted(camp),
	})
	RecruitmentService.sendState(camp.player)
end

function CampaignService.describeCompanions(camp: any): { any }
	local out = {}
	for _, companion in camp.data.Companions or {} do
		local leads = nil
		for _, entry in camp.data.Roster do
			if entry.companion == companion.id then
				leads = entry.id
			end
		end
		table.insert(out, {
			id = companion.id,
			woundedDays = math.max(0, (companion.woundedUntil or 0) - camp.data.Day),
			squadId = leads,
		})
	end
	return out
end

function CampaignService.describeEnlisted(camp: any): any
	local enlisted = camp.enlisted
	if not enlisted then
		return nil
	end
	local lord = camp.parties[enlisted.partyId]
	local rank, nextRank = CampaignConfig.enlistRank(enlisted.battles)
	return {
		partyId = enlisted.partyId,
		lordName = lord and lord.lordName or "?",
		title = rank.title,
		unit = rank.unit,
		wage = Enlist.WagePerDay * rank.wageMult,
		battles = enlisted.battles,
		nextRank = nextRank and nextRank.battles,
		nextTitle = nextRank and nextRank.title,
	}
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
			strength = math.floor(party.strength or 0),
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
		raiding = camp.raiding,
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
		local hunted = if party.kind == "Lord" then CampaignService.lordTarget(camp, party) else nil
		if hunted then
			-- generals ride down the enemies of their faction
			party.dest = hunted.pos
			if (hunted.pos - party.pos).Magnitude <= Travel.ContactRadius then
				CampaignService.lordContact(camp, party, hunted)
				if camp.pendingBattle then
					return
				end
				continue
			end
		elseif party.siegeTarget then
			CampaignService.lordSieges(camp, party, dtDays)
			if not camp.parties[party.id] then
				continue
			end
		elseif party.resting and party.restPoint then
			party.dest = party.restPoint -- a weakened general goes home to rest and refill
		elseif party.raidTarget then
			local village = CampaignConfig.getLocation(party.raidTarget)
			if village then
				party.dest = locationPos(village)
				if (party.dest - party.pos).Magnitude <= Travel.ArriveRadius then
					CampaignService.lordRaids(camp, party)
				end
			else
				party.raidTarget = nil
			end
		elseif party.targetParty then
			-- ambushers go for their prey (a caravan)
			local target = camp.parties[party.targetParty]
			if not target then
				CampaignService.removeParty(camp, party)
				continue
			end
			party.dest = target.pos
		elseif
			hostile
			and not camp.enlisted
			and not safe
			and day >= party.noContactUntil
			and toPlayer <= Parties.ChaseRadius
		then
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
		if
			hostile
			and not camp.enlisted
			and not safe
			and day >= party.noContactUntil
			and toPlayer <= Travel.ContactRadius
		then
			CampaignService.battleWithParty(camp, party, "Battle")
			return
		end
	end
end

---------------------------------------------------------------------------
-- Generals and enlisting
---------------------------------------------------------------------------

-- The party a general is hunting (hostile to his faction, not tied to your contract), if any
function CampaignService.lordTarget(camp: any, lord: any): any
	if camp.data.Day < (lord.restUntil or 0) or lord.resting or lord.siegeUntil then
		return nil -- resting, or camped outside a castle it besieges
	end
	local best, bestDistance = nil, Enlist.LordHuntRadius
	for _, other in camp.parties do
		if
			other ~= lord
			and other.kind ~= "Caravan"
			and not other.contractId
			and CampaignConfig.hostile(other.faction, lord.faction)
		then
			local distance = (other.pos - lord.pos).Magnitude
			if distance < bestDistance then
				best, bestDistance = other, distance
			end
		end
	end
	return best
end

function CampaignService.discharge(camp: any, message: string)
	if camp.enlisted then
		camp.enlisted = nil
		CampaignService.notify(camp, message, "info")
		camp.dirty = true
	end
end

-- A general caught a hostile party: you fight in his army if you serve him, else it's decided off-screen
function CampaignService.lordContact(camp: any, lord: any, enemy: any)
	local enlisted = camp.enlisted
	if enlisted and enlisted.partyId == lord.id and camp.view == "Overworld" and not camp.pendingBattle then
		local rank = CampaignConfig.enlistRank(enlisted.battles)
		local allies = {}
		local base = GameConfig.getRound(math.max(1, math.floor(lord.strength)))
		for _, wave in base.waves do
			for _, unit in wave.units do
				table.insert(allies, unit.unitId)
			end
		end
		CampaignService.startBattle(camp, {
			kind = "Enlisted",
			title = lord.lordName .. " vs " .. enemy.name,
			enemyFaction = enemy.faction,
			strength = enemy.strength,
			side = "Defender",
			allies = allies,
			party = enemy,
			enlisted = { unitId = rank.unit, name = rank.title .. " " .. camp.player.DisplayName .. "'s squad" },
			lordName = lord.lordName,
			onVictory = function(c: any, lines: { string })
				local e = c.enlisted
				if not e then
					return
				end
				local before = CampaignConfig.enlistRank(e.battles)
				e.battles += 1
				local after = CampaignConfig.enlistRank(e.battles)
				ReputationService.add(c.player, Enlist.ReputationPerVictory)
				table.insert(
					lines,
					string.format("%s is pleased: +%d reputation.", lord.lordName, Enlist.ReputationPerVictory)
				)
				if after ~= before then
					table.insert(
						lines,
						string.format(
							'<font color="#FFCD28"><b>Promoted to %s!</b> You now lead his %s.</font>',
							after.title,
							UnitDefinitions.get(after.unit).displayName
						)
					)
				end
				CampaignService.lordLoss(c, lord, 1, false)
			end,
			onDefeat = function(c: any, lines: { string })
				lord.restUntil = c.data.Day + 2
				if CampaignService.lordLoss(c, lord, 2, true) then
					CampaignService.discharge(c, lord.lordName .. "'s army is broken. You are discharged.")
					table.insert(lines, lord.lordName .. "'s army is broken — you are discharged.")
				else
					table.insert(lines, lord.lordName .. " falls back to regroup.")
				end
			end,
		})
		return
	end
	-- off-screen fight: the stronger side usually wins
	local lordWins = rng:NextNumber() < lord.strength / (lord.strength + math.max(1, enemy.strength))
	local loser = if lordWins then enemy else lord
	if lordWins then
		CampaignService.removeParty(camp, enemy)
		CampaignService.lordLoss(camp, lord, 1, false)
		lord.restUntil = camp.data.Day + 0.5
	else
		lord.restUntil = camp.data.Day + 2
		CampaignService.lordLoss(camp, lord, 2, true)
	end
	if camp.enlisted and camp.enlisted.partyId == loser.id and not camp.parties[loser.id] then
		CampaignService.discharge(camp, "Your general's army was destroyed. You are discharged.")
	end
end

-- A general loses strength: most of it is wounded men who come back later. Returns true if
-- his army broke up (it is removed, and replaced after a while).
local Generals = CampaignConfig.Generals
function CampaignService.lordLoss(camp: any, lord: any, amount: number, beaten: boolean): boolean
	lord.strength -= amount
	lord.wounded = (lord.wounded or 0) + amount * Generals.WoundedShare
	if beaten then
		lord.beatenUntil = camp.data.Day + Generals.BeatenDays
	end
	if lord.strength < Generals.MinStrength then
		CampaignService.removeParty(camp, lord)
		camp.lordRespawn = camp.lordRespawn or {}
		camp.lordRespawn[lord.faction] = camp.data.Day + Generals.RespawnDays
		return true
	end
	return false
end

-- Villages -----------------------------------------------------------------------
local Villages = CampaignConfig.Villages

function CampaignService.prosperity(camp: any, villageId: string): number
	local value = (camp.data.VillageProsperity or {})[villageId]
	return if value then value else 1
end

local function setProsperity(camp: any, villageId: string, value: number)
	camp.data.VillageProsperity = camp.data.VillageProsperity or {}
	camp.data.VillageProsperity[villageId] = math.clamp(value, 0, 1)
	camp.dirty = true
end

-- Share (0-1) of a faction's recruits still coming in: the mean prosperity of its villages
function CampaignService.factionProsperity(camp: any, faction: string): number
	local total, count = 0, 0
	for _, location in CampaignService.locationsOwnedBy(camp, faction, "Village") do
		total += CampaignService.prosperity(camp, location.id)
		count += 1
	end
	return if count > 0 then total / count else 1
end

-- A village is sacked: it loses prosperity. Returns the gold taken.
function CampaignService.sackVillage(camp: any, villageId: string, mult: number?): number
	local before = CampaignService.prosperity(camp, villageId)
	setProsperity(camp, villageId, before - Villages.ProsperityLoss * (mult or 1))
	return math.floor(Villages.RaidGold * before)
end

-- Once a day: villages recover; idle generals may ride out to raid a hostile village
function CampaignService.villagesDaily(camp: any)
	for _, location in CampaignConfig.Locations do
		if location.kind == "Village" then
			local value = CampaignService.prosperity(camp, location.id)
			if value < 1 then
				setProsperity(camp, location.id, value + Villages.RecoveryPerDay)
			end
		end
	end
	for _, lord in camp.parties do
		if
			lord.kind == "Lord"
			and not lord.resting
			and not lord.raidTarget
			and not lord.siegeTarget
			and rng:NextNumber() < Villages.AIRaidChancePerDay
		then
			local best, bestDistance = nil, Villages.AIRaidRadius
			for _, location in CampaignConfig.Locations do
				local owner = CampaignService.getOwner(camp, location.id)
				if
					location.kind == "Village"
					and owner ~= "Bandits"
					and CampaignConfig.hostile(owner, lord.faction)
					and CampaignService.prosperity(camp, location.id) >= 0.5
				then
					local distance = (locationPos(location) - lord.pos).Magnitude
					if distance < bestDistance then
						best, bestDistance = location, distance
					end
				end
			end
			if best then
				lord.raidTarget = best.id
			end
		end
	end
end

-- A general reached the village he wanted to raid
function CampaignService.lordRaids(camp: any, lord: any)
	local location = CampaignConfig.getLocation(lord.raidTarget)
	lord.raidTarget = nil
	if not location or CampaignService.prosperity(camp, location.id) < Villages.MinToRaid then
		return
	end
	CampaignService.sackVillage(camp, location.id, 0.8)
	if CampaignService.getOwner(camp, location.id) == camp.data.Faction then
		CampaignService.notify(camp, lord.lordName .. " has raided " .. location.name .. "!", "bad")
	end
end

-- Castles --------------------------------------------------------------------------
local Capture = CampaignConfig.Capture

function CampaignService.garrison(camp: any, castleId: string): number
	local value = (camp.data.Garrisons or {})[castleId]
	return if value then value else 1
end

local function setGarrison(camp: any, castleId: string, value: number)
	camp.data.Garrisons = camp.data.Garrisons or {}
	camp.data.Garrisons[castleId] = math.clamp(value, 0, 1)
	camp.dirty = true
end

-- A Raid won: the castle goes to your employer with a weak garrison (you get a bonus, not the castle)
function CampaignService.captureCastle(camp: any, castleId: string, faction: string)
	CampaignService.setOwner(camp, castleId, faction)
	camp.data.Captured = camp.data.Captured or {}
	camp.data.Captured[castleId] = if faction == camp.data.Faction then true else nil
	setGarrison(camp, castleId, Capture.GarrisonStart)
end

-- Castles under siege, for the client: [castleId] = { lordName, faction, assaultDay }
function CampaignService.describeSieges(camp: any): any
	local sieges = {}
	for _, party in camp.parties do
		if party.kind == "Lord" and party.siegeTarget and party.siegeUntil then
			sieges[party.siegeTarget] =
				{ lordName = party.lordName, faction = party.faction, assaultDay = party.siegeUntil }
		end
	end
	return sieges
end

-- The general who besieges a castle (nil if none)
function CampaignService.besieger(camp: any, castleId: string): any
	for _, party in camp.parties do
		if party.kind == "Lord" and party.siegeTarget == castleId then
			return party
		end
	end
	return nil
end

-- Lift a siege: the castle held (the besieger is beaten back) or fell (it changes hands)
function CampaignService.endSiege(camp: any, lord: any, fell: boolean)
	local castleId = lord.siegeTarget
	lord.siegeTarget = nil
	lord.siegeUntil = nil
	CampaignService.hooks.onSiegeEnded(camp, lord)
	if not castleId then
		return
	end
	local location = CampaignConfig.getLocation(castleId)
	if fell then
		CampaignService.captureCastle(camp, castleId, lord.faction)
		CampaignService.notify(
			camp,
			string.format("%s has taken %s!", lord.lordName, location.name),
			if CampaignConfig.hostile(lord.faction, camp.data.Faction) then "bad" else "info"
		)
	elseif camp.parties[lord.id] then
		CampaignService.lordLoss(camp, lord, lord.strength * Capture.LordLossOnRepulse, true)
	end
	camp.dirty = true
end

-- Nobody came to help: the garrison fights alone
function CampaignService.autoResolveSiege(camp: any, lord: any)
	local castleId = lord.siegeTarget
	local defence = CampaignService.garrison(camp, castleId) * Capture.GarrisonPower
	local fell = rng:NextNumber() < lord.strength / (lord.strength + defence)
	local location = CampaignConfig.getLocation(castleId)
	if not fell then
		setGarrison(camp, castleId, CampaignService.garrison(camp, castleId) * 0.6)
		CampaignService.notify(camp, string.format("%s held against %s.", location.name, lord.lordName), "info")
	end
	CampaignService.endSiege(camp, lord, fell)
end

-- A general besieging a castle: ride there, camp outside, then assault on the day
function CampaignService.lordSieges(camp: any, lord: any, _dtDays: number)
	local location = CampaignConfig.getLocation(lord.siegeTarget)
	if not location or not CampaignConfig.hostile(CampaignService.getOwner(camp, location.id), lord.faction) then
		lord.siegeTarget = nil
		lord.siegeUntil = nil
		CampaignService.hooks.onSiegeEnded(camp, lord)
		return
	end
	if lord.resting and not lord.siegeUntil then
		lord.siegeTarget = nil -- too weak to start a siege: goes home instead
		return
	end
	lord.dest = locationPos(location) + Vector2.new(20, 14) -- camps outside the walls (out of contact range)
	if not lord.siegeUntil and (lord.dest - lord.pos).Magnitude <= Travel.ArriveRadius then
		lord.siegeUntil = camp.data.Day + Capture.SiegeDays
		CampaignService.notify(
			camp,
			string.format("⚔ %s besieges %s! A Defend contract is posted.", lord.lordName, location.name),
			if CampaignService.getOwner(camp, location.id) == camp.data.Faction then "bad" else "info"
		)
		CampaignService.hooks.onSiegeStarted(camp, lord, location.id)
		camp.dirty = true
	elseif lord.siegeUntil and camp.data.Day >= lord.siegeUntil then
		-- the Defend contract you hold for this siege decides it (you fight); else auto-resolve
		local contract = camp.contract
		if not (contract and contract.lordId == lord.id) then
			CampaignService.autoResolveSiege(camp, lord)
		end
	end
end

-- Once a day: garrisons grow back; idle enemy generals ride out to retake your employer's castles
function CampaignService.castlesDaily(camp: any)
	for _, location in CampaignConfig.Locations do
		if location.kind == "Castle" then
			local value = CampaignService.garrison(camp, location.id)
			if value < 1 then
				setGarrison(camp, location.id, value + Capture.GarrisonPerDay)
			end
		end
	end
	local employer = camp.data.Faction
	if not employer then
		return
	end
	local besieged = CampaignService.describeSieges(camp)
	for _, lord in camp.parties do
		if
			lord.kind ~= "Lord"
			or lord.resting
			or lord.raidTarget
			or lord.siegeTarget
			or not CampaignConfig.hostile(lord.faction, employer)
			or rng:NextNumber() >= Capture.RetakeChancePerDay
		then
			continue
		end
		local best, bestScore = nil, math.huge
		for _, location in CampaignService.locationsOwnedBy(camp, employer, "Castle") do
			local distance = (locationPos(location) - lord.pos).Magnitude
			if distance <= Capture.RetakeRadius and not besieged[location.id] then
				-- captured castles first: they were theirs, and their garrison is weak
				local score = distance - (if camp.data.Captured and camp.data.Captured[location.id] then 1000 else 0)
				if score < bestScore then
					best, bestScore = location, score
				end
			end
		end
		if best then
			lord.siegeTarget = best.id
			besieged[best.id] = true
		end
	end
end

-- Once a day: wounded heal (faster at a friendly town/castle), recruits trickle in unless the
-- general was beaten recently; weak generals head home to rest
function CampaignService.reinforceLords(camp: any, days: number)
	for _, lord in camp.parties do
		if lord.kind ~= "Lord" then
			continue
		end
		local maxStrength = lord.maxStrength or lord.strength
		local home = lord.home and CampaignConfig.getLocation(lord.home)
		local atHome = false
		for _, location in CampaignService.locationsOwnedBy(camp, lord.faction) do
			if
				location.kind ~= "Village" -- generals rest in towns and castles, not villages
				and (locationPos(location) - lord.pos).Magnitude <= Generals.RestRadius
			then
				atHome = true
				home = location
			end
		end
		local heal =
			math.min(lord.wounded or 0, (if atHome then Generals.HealPerDayResting else Generals.HealPerDayRoad) * days)
		lord.wounded = (lord.wounded or 0) - heal
		lord.strength += heal
		if camp.data.Day >= (lord.beatenUntil or 0) then
			local room = maxStrength - lord.strength - (lord.wounded or 0)
			lord.strength += math.clamp(
				Generals.RecruitPerDay * days * CampaignService.factionProsperity(camp, lord.faction),
				0,
				math.max(0, room)
			)
		end
		if lord.strength < maxStrength * Generals.RestBelow then
			lord.resting = true
		elseif lord.strength >= maxStrength * Generals.RestUntil then
			lord.resting = false
		end
		if lord.resting and home and CampaignService.getOwner(camp, home.id) == lord.faction then
			lord.restPoint = locationPos(home)
		else
			lord.restPoint = nil
		end
	end
end

-- Troop wages, paid continuously as days pass. No gold: squads go unpaid, sulk, then desert.
local Wages = CampaignConfig.Wages
local function payWages(camp: any, dtDays: number)
	local data = camp.data
	local due = RecruitmentService.totalWages(camp.player) * dtDays
	if camp.enlisted then
		due *= Wages.EnlistedMult
	end
	if due <= 0 then
		return
	end
	if data.Gold >= due then
		data.Gold -= due
		if (data.UnpaidDays or 0) > 0 then
			data.UnpaidDays = 0
			CampaignService.notify(camp, "Your troops have been paid. Spirits rise again.", "good")
			RecruitmentService.sendState(camp.player)
		end
	else
		data.Gold = 0
		local before = data.UnpaidDays or 0
		data.UnpaidDays = before + dtDays
		if before == 0 then
			CampaignService.notify(camp, "Your treasury is empty! Unpaid troops lose heart and will desert.", "bad")
		end
	end
end

local function desertions(camp: any)
	local data = camp.data
	if (data.UnpaidDays or 0) < Wages.DesertAfterDays or #data.Roster == 0 then
		return
	end
	-- the least experienced squad leaves first
	local worst, index = nil, nil
	for i, entry in data.Roster do
		if not worst or entry.xp < worst.xp then
			worst, index = entry, i
		end
	end
	if worst and index then
		table.remove(data.Roster, index)
		CampaignService.notify(
			camp,
			string.format(
				"Unpaid for %d days, your %s %s deserted!",
				math.floor(data.UnpaidDays),
				UnitDefinitions.get(worst.unitId).displayName,
				"squad"
			),
			"bad"
		)
		RecruitmentService.sendState(camp.player)
	end
end

local function advanceTime(camp: any, dtDays: number)
	local data = camp.data
	local before = math.floor(data.Day)
	data.Day += dtDays
	payWages(camp, dtDays)
	if math.floor(data.Day) > before then
		CampaignService.reinforceLords(camp, 1)
		CampaignService.villagesDaily(camp)
		CampaignService.castlesDaily(camp)
		RecruitmentService.healWounded(camp.player, CampaignService.atFriendly(camp, { "Town", "Castle" }) ~= nil, 1)
		desertions(camp)
		RecruitmentService.sendState(camp.player)
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
	CampaignService.stepRaid(camp, dtDays)
	if camp.enlisted then
		local lord = camp.parties[camp.enlisted.partyId]
		if not lord then
			CampaignService.discharge(camp, "Your general's army has been scattered. You are on your own again.")
		else
			camp.pos = lord.pos
			camp.moving = false
			camp.atLocation = nil
			local rank = CampaignConfig.enlistRank(camp.enlisted.battles)
			camp.data.Gold += Enlist.WagePerDay * rank.wageMult * dtDays
		end
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
	if camp.enlisted then
		local lord = camp.parties[camp.enlisted.partyId]
		if lord then
			camp.pos = lord.pos -- march with the general
		end
	end
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
	if camp.enlisted then
		CampaignService.notify(camp, "You march with your general. Leave his service to go your own way.", "info")
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

function ACTIONS.Enlist(camp: any, partyId: unknown)
	local lord = if typeof(partyId) == "number" then camp.parties[partyId] else nil
	if camp.enlisted or not lord or lord.kind ~= "Lord" or lord.faction ~= camp.data.Faction then
		return
	end
	if (lord.pos - camp.pos).Magnitude > Enlist.EnlistRadius then
		CampaignService.notify(camp, "Ride closer to " .. lord.lordName .. " to join him.", "bad")
		return
	end
	if camp.contract then
		CampaignService.notify(camp, "Finish or abandon your contract before enlisting.", "bad")
		return
	end
	camp.enlisted = { partyId = lord.id, battles = 0 }
	camp.dest = nil
	camp.moving = false
	local rank = CampaignConfig.enlistRank(0)
	CampaignService.notify(
		camp,
		string.format(
			"You join %s as a %s: %d gold a day, you lead one of his %s squads.",
			lord.lordName,
			rank.title,
			Enlist.WagePerDay * rank.wageMult,
			UnitDefinitions.get(rank.unit).displayName
		),
		"good"
	)
	camp.dirty = true
end

function ACTIONS.LeaveService(camp: any)
	if camp.enlisted then
		local lord = camp.parties[camp.enlisted.partyId]
		CampaignService.discharge(
			camp,
			"You leave "
				.. (if lord then lord.lordName else "the general")
				.. "'s service. Your company is yours again."
		)
	end
end

-- Branching evolution: pick what a squad becomes at its branching point
function ACTIONS.ChooseBranch(camp: any, arg: unknown)
	if typeof(arg) ~= "table" then
		return
	end
	local squadId, unitId = (arg :: any).squadId, (arg :: any).unitId
	if typeof(squadId) ~= "number" or typeof(unitId) ~= "string" then
		return
	end
	local ok, message = RecruitmentService.chooseBranch(camp.player, squadId, unitId)
	CampaignService.notify(camp, message, if ok then "good" else "bad")
	camp.dirty = true
end

-- Ransom broker (in town): every prisoner for gold
function ACTIONS.RansomPrisoners(camp: any)
	if not atFriendly(camp, { "Town" }) then
		return
	end
	local value = CampaignService.ransomValue(camp)
	if value <= 0 then
		return
	end
	camp.data.Gold += value
	camp.data.Prisoners = {}
	CampaignService.notify(camp, "Prisoners ransomed for " .. value .. " gold.", "good")
	camp.dirty = true
end

-- Offer prisoners of one unit a place in your company: some accept, a new squad forms
function ACTIONS.RecruitPrisoners(camp: any, unitId: unknown)
	local data = camp.data
	local count = typeof(unitId) == "string" and data.Prisoners and data.Prisoners[unitId]
	local def = typeof(unitId) == "string" and UnitDefinitions.get(unitId)
	if not count or not def then
		return
	end
	if count < PrisonerRules.MinToRecruit then
		CampaignService.notify(
			camp,
			"Too few of them to form a squad (" .. PrisonerRules.MinToRecruit .. " needed).",
			"bad"
		)
		return
	end
	if #data.Roster >= Economy.MaxRosterSize then
		CampaignService.notify(camp, "Your company is full.", "bad")
		return
	end
	local joined = 0
	for _ = 1, math.min(count, def.soldiers) do
		if rng:NextNumber() < PrisonerRules.RecruitChance then
			joined += 1
		end
	end
	-- everyone asked is either in your ranks now or sent packing
	data.Prisoners[unitId] = count - math.min(count, def.soldiers)
	if data.Prisoners[unitId] <= 0 then
		data.Prisoners[unitId] = nil
	end
	if joined == 0 then
		CampaignService.notify(camp, "None of the prisoners would take your coin.", "bad")
	else
		RecruitmentService.addSquad(camp.player, def.id, joined / def.soldiers)
		CampaignService.notify(camp, string.format("%d %s join your company!", joined, def.displayName), "good")
	end
	camp.dirty = true
end

-- Commander gear -------------------------------------------------------------------

-- The equipped items of a player: { weapon = item, armor = item, horse = item }
function CampaignService.gearOf(player: Player): any
	local data = DataService.getCampaign(player)
	local gear = (data and data.Gear) or CampaignConfig.StartingGear
	local out = {}
	for slot, fallback in CampaignConfig.StartingGear do
		out[slot] = CampaignConfig.Items[gear[slot] or fallback] or CampaignConfig.Items[fallback]
	end
	return out
end

function ACTIONS.BuyItem(camp: any, itemId: unknown)
	local item = typeof(itemId) == "string" and CampaignConfig.Items[itemId]
	if not item or item.lootOnly or not atFriendly(camp, { "Town" }) then
		return
	end
	if table.find(camp.data.Items, itemId) then
		CampaignService.notify(camp, "You already own it.", "info")
		return
	end
	if camp.data.Gold < item.price then
		CampaignService.notify(camp, "Not enough gold (" .. item.price .. " needed).", "bad")
		return
	end
	camp.data.Gold -= item.price
	table.insert(camp.data.Items, itemId :: string)
	camp.data.Gear[item.slot] = itemId
	CampaignService.notify(camp, "Bought and equipped: " .. item.name, "good")
	CampaignService.hooks.onGearChanged(camp.player)
	camp.dirty = true
end

function ACTIONS.EquipItem(camp: any, itemId: unknown)
	local item = typeof(itemId) == "string" and CampaignConfig.Items[itemId]
	if not item or not table.find(camp.data.Items, itemId) then
		return
	end
	camp.data.Gear[item.slot] = itemId
	CampaignService.hooks.onGearChanged(camp.player)
	camp.dirty = true
end

-- Companions ---------------------------------------------------------------------

function ACTIONS.HireCompanion(camp: any, id: unknown)
	local info = typeof(id) == "string" and CampaignConfig.Companions.List[id]
	local data = camp.data
	data.Companions = data.Companions or {}
	if not info or not atFriendly(camp, { "Town" }) then
		return
	end
	for _, companion in data.Companions do
		if companion.id == id then
			return
		end
	end
	if #data.Companions >= CampaignConfig.Companions.MaxHired then
		CampaignService.notify(camp, "You can't keep more officers.", "bad")
		return
	end
	if data.Gold < info.cost then
		CampaignService.notify(camp, "Not enough gold (" .. info.cost .. " needed).", "bad")
		return
	end
	data.Gold -= info.cost
	table.insert(data.Companions, { id = id :: string, woundedUntil = 0 })
	CampaignService.notify(camp, info.name .. " joins your company. Assign him a squad (OFFICERS).", "good")
	camp.dirty = true
end

-- Put a companion at the head of a squad (squadId = nil: he stands down)
function ACTIONS.AssignCompanion(camp: any, arg: unknown)
	if typeof(arg) ~= "table" then
		return
	end
	local id, squadId = (arg :: any).companion, (arg :: any).squadId
	local data = camp.data
	local hired = false
	for _, companion in data.Companions or {} do
		if companion.id == id then
			hired = true
		end
	end
	if not hired then
		return
	end
	for _, entry in data.Roster do
		if entry.companion == id then
			entry.companion = nil
		end
	end
	for _, entry in data.Roster do
		if entry.id == squadId then
			entry.companion = id
		end
	end
	RecruitmentService.sendState(camp.player)
	camp.dirty = true
end

-- Raid the hostile village you stand in (takes a little while; moving away cancels it)
function ACTIONS.RaidVillage(camp: any)
	local location = camp.atLocation and CampaignConfig.getLocation(camp.atLocation)
	if not location or location.kind ~= "Village" or camp.raiding then
		return
	end
	local owner = CampaignService.getOwner(camp, location.id)
	if owner == camp.data.Faction or owner == "Bandits" then
		CampaignService.notify(camp, "You won't raid your own employer's village.", "bad")
		return
	end
	if CampaignService.prosperity(camp, location.id) < Villages.MinToRaid then
		CampaignService.notify(camp, location.name .. " has nothing left to take.", "info")
		return
	end
	camp.raiding = { id = location.id, progress = 0 }
	if camp.timeMode == "Pause" then
		camp.timeMode = "Play"
	end
	CampaignService.notify(camp, "Your men start plundering " .. location.name .. "…", "info")
	camp.dirty = true
end

function CampaignService.stepRaid(camp: any, dtDays: number)
	local raid = camp.raiding
	if not raid then
		return
	end
	if camp.moving or camp.atLocation ~= raid.id then
		camp.raiding = nil -- rode off: raid abandoned
		camp.dirty = true
		return
	end
	raid.progress += dtDays / Villages.RaidDays
	if raid.progress < 1 then
		return
	end
	camp.raiding = nil
	local location = CampaignConfig.getLocation(raid.id)
	local gold = CampaignService.sackVillage(camp, raid.id)
	camp.data.Gold += gold
	local loot = ""
	if rng:NextNumber() < Villages.RaidLootChance then
		for _, id in CampaignConfig.ItemOrder do
			local item = CampaignConfig.Items[id]
			if item.price > 0 and not table.find(camp.data.Items, id) then
				table.insert(camp.data.Items, id)
				loot = " and found a " .. item.name
				break
			end
		end
	end
	CampaignService.notify(camp, string.format("%s plundered: +%d gold%s.", location.name, gold, loot), "good")
	CampaignService.hooks.onVillageRaided(camp, raid.id)
	camp.dirty = true
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
	if not town or camp.enlisted then
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
	ChooseBranch = true,
	HireCompanion = true,
	AssignCompanion = true,
	BuyItem = true,
	EquipItem = true,
	RansomPrisoners = true,
	RecruitPrisoners = true,
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
