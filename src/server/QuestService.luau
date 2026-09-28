--[[
	QuestService
	The rotating quest board at your employer's town and the contract you are working on.
	  Raid     — storm an enemy castle (it becomes your employer's on success)
	  Bounty   — hunt down a named bandit warband roaming the map
	  Escort   — walk a caravan from your town to one of your castles; bandits ambush it on the
	             way, you must be close enough to intercept. Caravan lost = failed
	  Garrison — be at one of your castles when it is attacked (a set day) and defend it
	Declining a contract is free. Completing one pays gold + reputation, failing one (deadline
	missed, caravan lost, castle fallen, raid repulsed, abandoned) costs reputation.
	All numbers: CampaignConfig.Contracts.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local CampaignConfig = require(Modules:WaitForChild("CampaignConfig"))

local CampaignService = require(script.Parent:WaitForChild("CampaignService"))
local ReputationService = require(script.Parent:WaitForChild("ReputationService"))

local Contracts = CampaignConfig.Contracts
local Types = Contracts.Types
local Difficulty = CampaignConfig.Difficulty
local Battle = CampaignConfig.Battle
local Parties = CampaignConfig.Parties

local QuestService = {}

local rng = Random.new()
local nextContractId = 0

local function v2(x: number, z: number): Vector2
	return Vector2.new(x, z)
end

local function locationPos(location: any): Vector2
	return v2(location.x, location.z)
end

local function rivalsOf(faction: string): { string }
	local list = {}
	for _, other in CampaignConfig.FactionOrder do
		if other ~= faction then
			table.insert(list, other)
		end
	end
	return list
end

local function pick(list: { any }): any
	return if #list > 0 then list[rng:NextInteger(1, #list)] else nil
end

---------------------------------------------------------------------------
-- Board generation
---------------------------------------------------------------------------

local function newContract(kind: string, fields: any): any
	nextContractId += 1
	local info = Types[kind]
	local contract = fields
	contract.id = nextContractId
	contract.type = kind
	contract.gold = info.gold
	contract.reputation = info.reputation
	contract.failReputation = info.failReputation
	return contract
end

local GENERATORS = {}

function GENERATORS.Raid(camp: any): any
	local employer = CampaignService.employer(camp)
	local targets = {}
	for _, location in CampaignConfig.Locations do
		local owner = CampaignService.getOwner(camp, location.id)
		if location.kind == "Castle" and owner ~= employer and owner ~= "Bandits" then
			table.insert(targets, location)
		end
	end
	local target = pick(targets)
	if not target then
		return nil
	end
	local owner = CampaignService.getOwner(camp, target.id)
	return newContract("Raid", {
		title = "Raid " .. target.name,
		description = string.format(
			"Storm %s, held by %s. Take and hold its objectives. The castle becomes your employer's.",
			target.name,
			CampaignConfig.Factions[owner].short
		),
		targetLocation = target.id,
		enemyFaction = owner,
		strength = Difficulty.CastleStrength + CampaignService.threat(camp),
		days = Types.Raid.deadlineDays,
	})
end

function GENERATORS.Bounty(camp: any): any
	local lairs = {}
	for _, location in CampaignConfig.Locations do
		if location.kind == "BanditCamp" then
			table.insert(lairs, location)
		end
	end
	local lair = pick(lairs)
	local used = {}
	for _, contract in camp.board do
		if contract.bountyName then
			used[contract.bountyName] = true
		end
	end
	local names = {}
	for _, name in Contracts.BountyNames do
		if not used[name] then
			table.insert(names, name)
		end
	end
	local name = pick(names) or "Nameless brigands"
	return newContract("Bounty", {
		title = "Bounty: " .. name,
		description = string.format("%s have been raiding near %s. Hunt them down and destroy them.", name, lair.name),
		bountyName = name,
		lair = lair.id,
		strength = Difficulty.BountyStrength + CampaignService.threat(camp),
		days = Types.Bounty.deadlineDays,
	})
end

function GENERATORS.Escort(camp: any): any
	local town = CampaignService.homeTown(camp)
	local destination = pick(CampaignService.locationsOwnedBy(camp, CampaignService.employer(camp), "Castle"))
	if not town or not destination then
		return nil
	end
	return newContract("Escort", {
		title = "Escort a caravan to " .. destination.name,
		description = string.format(
			"A supply caravan leaves %s for %s. It sets off when you join it. Bandits will strike — stay close (within %d).",
			town.name,
			destination.name,
			Types.Escort.escortRadius
		),
		fromLocation = town.id,
		toLocation = destination.id,
		strength = Difficulty.AmbushStrength + CampaignService.threat(camp),
		days = Types.Escort.deadlineDays,
	})
end

function GENERATORS.RaidVillage(camp: any): any
	local employer = CampaignService.employer(camp)
	local targets = {}
	for _, location in CampaignConfig.Locations do
		local owner = CampaignService.getOwner(camp, location.id)
		if
			location.kind == "Village"
			and owner ~= employer
			and owner ~= "Bandits"
			and CampaignService.prosperity(camp, location.id) >= 0.6
		then
			table.insert(targets, location)
		end
	end
	local target = pick(targets)
	if not target then
		return nil
	end
	local owner = CampaignService.getOwner(camp, target.id)
	return newContract("RaidVillage", {
		title = "Raid " .. target.name,
		description = string.format(
			"Burn %s's granaries: raiding %s cuts their recruits for weeks. Keep what you plunder.",
			CampaignConfig.Factions[owner].short,
			target.name
		),
		targetLocation = target.id,
		enemyFaction = owner,
		strength = 1,
		days = Types.RaidVillage.deadlineDays,
	})
end

function GENERATORS.Garrison(camp: any): any
	local target = pick(CampaignService.locationsOwnedBy(camp, CampaignService.employer(camp), "Castle"))
	if not target then
		return nil
	end
	local attacker = pick(rivalsOf(CampaignService.employer(camp)))
	local lead = Types.Garrison.leadDays
	return newContract("Garrison", {
		title = "Defend " .. target.name,
		description = string.format(
			"Scouts report a %s army marching on %s. Be there (within %d) when it attacks.",
			CampaignConfig.Factions[attacker].short,
			target.name,
			Types.Garrison.stationRadius
		),
		targetLocation = target.id,
		enemyFaction = attacker,
		strength = Difficulty.GarrisonAttackStrength + CampaignService.threat(camp),
		days = rng:NextInteger(lead[1], lead[2]),
	})
end

local function generateContract(camp: any): any
	local total = 0
	for _, weight in Contracts.Weights do
		total += weight
	end
	for _ = 1, 8 do
		local roll = rng:NextNumber() * total
		for kind, weight in Contracts.Weights do
			roll -= weight
			if roll <= 0 then
				local contract = GENERATORS[kind](camp)
				if contract then
					return contract
				end
				break
			end
		end
	end
	return nil
end

local function refreshBoard(camp: any)
	-- Defend contracts for sieges in progress stay up until the siege ends
	local keep = {}
	for _, contract in camp.board or {} do
		if contract.lordId and camp.parties[contract.lordId] then
			table.insert(keep, contract)
		end
	end
	camp.board = keep
	for _ = 1, Contracts.BoardSize do
		local contract = generateContract(camp)
		if contract then
			table.insert(camp.board, contract)
		end
	end
	camp.boardRefreshDay = camp.data.Day + Contracts.BoardRefreshDays
	CampaignService.markDirty(camp)
end

---------------------------------------------------------------------------
-- Outcomes
---------------------------------------------------------------------------

local function removeContractParties(camp: any, contract: any)
	for _, party in table.clone(camp.parties) do
		if party.contractId == contract.id then
			CampaignService.removeParty(camp, party)
		end
	end
end

local function report(camp: any, text: string)
	-- inside a battle resolution the line goes to the summary screen, otherwise a notification
	if camp.pendingReport then
		table.insert(camp.pendingReport, text)
	end
end

local function succeed(camp: any, contract: any)
	if camp.contract ~= contract then
		return
	end
	camp.contract = nil
	removeContractParties(camp, contract)
	camp.data.Gold += contract.gold
	camp.data.ContractsCompleted += 1
	ReputationService.add(camp.player, contract.reputation)
	local text = string.format(
		"Contract complete: %s  (+%d gold, +%d reputation)",
		contract.title,
		contract.gold,
		contract.reputation
	)
	CampaignService.notify(camp, text, "good")
	report(camp, '<font color="#78E682"><b>✔ ' .. text .. "</b></font>")
	CampaignService.markDirty(camp)
end

local function fail(camp: any, contract: any, reason: string)
	if camp.contract ~= contract then
		return
	end
	camp.contract = nil
	removeContractParties(camp, contract)
	ReputationService.add(camp.player, -contract.failReputation)
	local text =
		string.format("Contract failed: %s — %s  (-%d reputation)", contract.title, reason, contract.failReputation)
	CampaignService.notify(camp, text, "bad")
	report(camp, '<font color="#FF8070"><b>✘ ' .. text .. "</b></font>")
	CampaignService.markDirty(camp)
end

local function castleFalls(camp: any, contract: any)
	local location = CampaignConfig.getLocation(contract.targetLocation)
	CampaignService.setOwner(camp, contract.targetLocation, contract.enemyFaction)
	local text = location.name .. " has fallen to " .. CampaignConfig.Factions[contract.enemyFaction].short .. "."
	CampaignService.notify(camp, text, "bad")
	report(camp, '<font color="#FF8070">' .. text .. "</font>")
end

---------------------------------------------------------------------------
-- Accept / decline / abandon
---------------------------------------------------------------------------

local function findOnBoard(camp: any, id: unknown): (any, number?)
	for index, contract in camp.board do
		if contract.id == id then
			return contract, index
		end
	end
	return nil, nil
end

local function startEscort(camp: any, contract: any)
	local from = CampaignConfig.getLocation(contract.fromLocation)
	local route = CampaignConfig.roadRoute(contract.fromLocation, contract.toLocation)
		or { contract.fromLocation, contract.toLocation }
	local points = {}
	local length = 0
	for i, id in route do
		local pos = locationPos(CampaignConfig.getLocation(id))
		if i > 1 then
			table.insert(points, pos)
			length += (pos - (points[#points - 1] or locationPos(from))).Magnitude
		end
	end
	local ambushes = {}
	for _ = 1, Types.Escort.ambushes do
		table.insert(ambushes, rng:NextNumber(0.2, 0.85))
	end
	table.sort(ambushes)
	contract.ambushes = ambushes
	contract.routeLength = math.max(1, length)
	contract.travelled = 0
	local employer = CampaignService.employer(camp)
	local caravan = CampaignService.spawnParty(camp, {
		kind = "Caravan",
		faction = employer,
		name = CampaignConfig.Factions[employer].short .. " caravan",
		pos = locationPos(from),
		speed = Parties.CaravanSpeed,
		strength = 0,
		route = points,
		routeIndex = 1,
		contractId = contract.id,
		waiting = true, -- sets off when you join it
	})
	contract.caravanId = caravan.id
end

local function startBounty(camp: any, contract: any)
	local lair = locationPos(CampaignConfig.getLocation(contract.lair))
	local angle = rng:NextNumber(0, math.pi * 2)
	local party = CampaignService.spawnParty(camp, {
		kind = "Bounty",
		faction = "Bandits",
		name = contract.bountyName,
		pos = lair + v2(math.cos(angle), math.sin(angle)) * 40,
		speed = Parties.BanditSpeed,
		strength = contract.strength,
		home = lair,
		roamRadius = Parties.BanditRoamRadius,
		contractId = contract.id,
		boss = {
			unitId = Difficulty.BountyBoss.unitId,
			name = contract.bountyName .. " (leader)",
			statMultiplier = Difficulty.BountyBoss.statMultiplier,
			damageMultiplier = Difficulty.BountyBoss.damageMultiplier,
		},
	})
	contract.partyId = party.id
end

CampaignService.actions.AcceptContract = function(camp: any, id: unknown)
	local contract, index = findOnBoard(camp, id)
	if not contract or not index then
		return
	end
	if not CampaignService.atFriendly(camp, { "Town" }) then
		CampaignService.notify(camp, "Take contracts at your employer's town.", "bad")
		return
	end
	if camp.contract then
		CampaignService.notify(camp, "Finish (or abandon) your current contract first.", "bad")
		return
	end
	table.remove(camp.board, index)
	camp.contract = contract
	contract.deadlineDay = contract.assaultDay or (camp.data.Day + contract.days)
	if contract.type == "Bounty" then
		startBounty(camp, contract)
	elseif contract.type == "Escort" then
		startEscort(camp, contract)
	end
	CampaignService.notify(camp, "Contract accepted: " .. contract.title, "good")
	CampaignService.markDirty(camp)
end

CampaignService.actions.DeclineContract = function(camp: any, id: unknown)
	local contract, index = findOnBoard(camp, id)
	if contract and index then
		table.remove(camp.board, index) -- no penalty; the board refills when it rotates
		CampaignService.markDirty(camp)
	end
end

CampaignService.actions.AbandonContract = function(camp: any)
	if camp.contract then
		fail(camp, camp.contract, "abandoned")
	end
end

-- Raid: assault the target castle when you're there
CampaignService.actions.Assault = function(camp: any)
	local contract = camp.contract
	if not contract or contract.type ~= "Raid" or camp.atLocation ~= contract.targetLocation then
		return
	end
	local location = CampaignConfig.getLocation(contract.targetLocation)
	local allies = {}
	for i = 1, Battle.RaidAllies do
		table.insert(allies, if i % 2 == 0 then "Skirmishers" else "LineInfantry")
	end
	CampaignService.startBattle(camp, {
		kind = "Raid",
		castleId = location.id,
		title = "Raid — " .. location.name,
		enemyFaction = CampaignService.getOwner(camp, location.id),
		strength = contract.strength,
		side = "Attacker",
		allies = allies,
		onVictory = function(c: any)
			-- the castle goes to your employer (you stay a mercenary: a bonus, not the castle)
			CampaignService.captureCastle(c, location.id, CampaignService.employer(c))
			local Capture = CampaignConfig.Capture
			c.data.Gold += Capture.BonusGold
			ReputationService.add(c.player, Capture.BonusReputation)
			report(
				c,
				string.format(
					'%s now flies the %s flag. <font color="#FFCD28"><b>Capture bonus: +%d gold, +%d reputation.</b></font> Its garrison is weak: expect them to try to take it back.',
					location.name,
					CampaignConfig.Factions[CampaignService.employer(c)].short,
					Capture.BonusGold,
					Capture.BonusReputation
				)
			)
			succeed(c, contract)
		end,
		onDefeat = function(c: any)
			fail(c, contract, "the assault was repulsed")
		end,
	})
end

---------------------------------------------------------------------------
-- World hooks
---------------------------------------------------------------------------

local function garrisonBattle(camp: any, contract: any)
	local location = CampaignConfig.getLocation(contract.targetLocation)
	local allies = {}
	for _ = 1, Battle.GarrisonAllies do
		table.insert(allies, "LineInfantry")
	end
	contract.fought = true
	-- a real siege: you face the besieging general's army; its outcome ends his siege
	local lord = contract.lordId and camp.parties[contract.lordId]
	CampaignService.startBattle(camp, {
		kind = "Garrison",
		castleId = location.id,
		title = "Defence of " .. location.name .. (if lord then " against " .. lord.lordName else ""),
		enemyFaction = contract.enemyFaction,
		strength = if lord then math.max(1, math.floor(lord.strength + 0.5)) else contract.strength,
		side = "Defender",
		allies = allies,
		onVictory = function(c: any)
			succeed(c, contract)
			if lord and c.parties[lord.id] then
				CampaignService.endSiege(c, lord, false)
			end
		end,
		onDefeat = function(c: any)
			fail(c, contract, "the castle fell")
			if lord and c.parties[lord.id] then
				CampaignService.endSiege(c, lord, true)
			else
				castleFalls(c, contract)
			end
		end,
	})
end

-- A general started a siege: post a Defend contract for it (the assault day is fixed)
CampaignService.hooks.onSiegeStarted = function(camp: any, lord: any, castleId: string)
	local location = CampaignConfig.getLocation(castleId)
	if CampaignService.getOwner(camp, castleId) ~= CampaignService.employer(camp) then
		return
	end
	local contract = newContract("Garrison", {
		title = "Defend " .. location.name,
		description = string.format(
			"%s besieges %s and will assault on day %d. Be there (within %d) to hold the walls.",
			lord.lordName,
			location.name,
			math.floor(lord.siegeUntil) + 1,
			Types.Garrison.stationRadius
		),
		targetLocation = castleId,
		enemyFaction = lord.faction,
		strength = math.max(1, math.floor(lord.strength + 0.5)),
		days = math.max(1, math.ceil(lord.siegeUntil - camp.data.Day)),
		assaultDay = lord.siegeUntil,
		lordId = lord.id,
	})
	table.insert(camp.board, 1, contract)
	CampaignService.markDirty(camp)
end

-- The siege ended (castle held, fell, or the besieger left): drop its contract
CampaignService.hooks.onSiegeEnded = function(camp: any, lord: any)
	for index = #camp.board, 1, -1 do
		if camp.board[index].lordId == lord.id then
			table.remove(camp.board, index)
		end
	end
	local contract = camp.contract
	if contract and contract.lordId == lord.id and not contract.fought then
		succeed(camp, contract) -- the besiegers left before the assault
	end
	CampaignService.markDirty(camp)
end

local function updateEscort(camp: any, contract: any)
	local caravan = camp.parties[contract.caravanId]
	if not caravan then
		return
	end
	local radius = Types.Escort.escortRadius
	local near = (caravan.pos - camp.pos).Magnitude <= radius
	if caravan.waiting then
		if near then
			caravan.waiting = false
			contract.departed = true
			CampaignService.notify(camp, "The caravan sets off. Stay close!", "info")
			CampaignService.markDirty(camp)
		end
		return
	end
	-- progress along the route
	local last = caravan.lastPos or caravan.pos
	contract.travelled += (caravan.pos - last).Magnitude
	caravan.lastPos = caravan.pos
	local progress = contract.travelled / contract.routeLength
	local nextAmbush = contract.ambushes[1]
	if nextAmbush and progress >= nextAmbush then
		table.remove(contract.ambushes, 1)
		local angle = rng:NextNumber(0, math.pi * 2)
		CampaignService.spawnParty(camp, {
			kind = "Ambush",
			faction = "Bandits",
			name = "Bandit ambushers",
			pos = caravan.pos + v2(math.cos(angle), math.sin(angle)) * 45,
			speed = Parties.BanditSpeed * 1.3,
			strength = contract.strength,
			targetParty = caravan.id,
			contractId = contract.id,
		})
		CampaignService.notify(camp, "Bandits are closing in on the caravan!", "bad")
	end
end

CampaignService.hooks.onTime = function(camp: any)
	local contract = camp.contract
	if not contract then
		return
	end
	local day = camp.data.Day
	if contract.type == "Garrison" then
		if not contract.fought and day >= contract.deadlineDay then
			local location = CampaignConfig.getLocation(contract.targetLocation)
			local lord = contract.lordId and camp.parties[contract.lordId]
			if contract.lordId and not lord then
				succeed(camp, contract) -- the besieging army is gone
			elseif (locationPos(location) - camp.pos).Magnitude <= Types.Garrison.stationRadius then
				garrisonBattle(camp, contract)
			elseif lord then
				contract.fought = true
				fail(camp, contract, "you were not there when it was attacked")
				CampaignService.autoResolveSiege(camp, lord) -- the garrison fights alone
			else
				castleFalls(camp, contract)
				fail(camp, contract, "you were not there when it was attacked")
			end
		end
		return
	end
	if contract.type == "Escort" then
		updateEscort(camp, contract)
		if contract.departed then
			return -- once under way, the caravan has no deadline
		end
	end
	if day > contract.deadlineDay then
		fail(camp, contract, "the deadline passed")
	end
end

CampaignService.hooks.onNewDay = function(camp: any)
	if camp.data.Day >= (camp.boardRefreshDay or 0) then
		refreshBoard(camp)
	end
end

CampaignService.hooks.onFactionChosen = function(camp: any)
	refreshBoard(camp)
end

CampaignService.hooks.onArrive = function(camp: any, location: any)
	local contract = camp.contract
	if contract and contract.type == "Raid" and contract.targetLocation == location.id then
		CampaignService.notify(camp, "You reach " .. location.name .. ". Press ASSAULT when ready.", "info")
	end
	CampaignService.markDirty(camp)
end

-- The caravan reached its destination
CampaignService.hooks.onPartyArrived = function(camp: any, party: any)
	local contract = camp.contract
	if party.kind == "Caravan" then
		CampaignService.removeParty(camp, party)
		if contract and contract.caravanId == party.id then
			succeed(camp, contract)
		end
	end
end

-- Ambushers reached the caravan: fight if you're close enough, else it's lost
CampaignService.hooks.onPartyContact = function(camp: any, ambush: any, caravan: any)
	local contract = camp.contract
	if not contract or contract.caravanId ~= caravan.id then
		CampaignService.removeParty(camp, ambush)
		return
	end
	if (caravan.pos - camp.pos).Magnitude <= Types.Escort.escortRadius then
		caravan.paused = true
		local guards = {}
		for _ = 1, Battle.CaravanGuards do
			table.insert(guards, "LineInfantry")
		end
		ambush.battleAllies = guards
		ambush.onVictory = function(c: any)
			caravan.paused = false
			report(c, "The caravan is safe and moves on.")
		end
		ambush.onDefeat = function(c: any)
			CampaignService.removeParty(c, ambush)
			fail(c, contract, "the caravan was plundered")
		end
		CampaignService.battleWithParty(camp, ambush, "Caravan ambush")
	else
		CampaignService.removeParty(camp, ambush)
		fail(camp, contract, "the caravan was plundered while you were away")
	end
end

CampaignService.hooks.onVillageRaided = function(camp: any, villageId: string)
	local contract = camp.contract
	if contract and contract.type == "RaidVillage" and contract.targetLocation == villageId then
		succeed(camp, contract)
	end
end

CampaignService.hooks.onPartyDefeated = function(camp: any, party: any)
	local contract = camp.contract
	if contract and party.kind == "Bounty" and contract.partyId == party.id then
		succeed(camp, contract)
	end
end

---------------------------------------------------------------------------
-- Client view
---------------------------------------------------------------------------

local function describeContract(camp: any, contract: any, active: boolean): any
	local out = {
		id = contract.id,
		type = contract.type,
		title = contract.title,
		description = contract.description,
		gold = contract.gold,
		reputation = contract.reputation,
		failReputation = contract.failReputation,
		days = contract.days,
		strength = contract.strength,
		targetLocation = contract.targetLocation,
	}
	if not active then
		return out
	end
	local day = camp.data.Day
	out.daysLeft = contract.deadlineDay - day
	if contract.type == "Raid" then
		out.status = "March on " .. CampaignConfig.getLocation(contract.targetLocation).name .. " and assault it"
		out.canAssault = camp.atLocation == contract.targetLocation
	elseif contract.type == "Bounty" then
		local party = camp.parties[contract.partyId]
		out.targetParty = contract.partyId
		out.status = if party then "Last seen near " .. CampaignConfig.getLocation(contract.lair).name else "—"
	elseif contract.type == "Escort" then
		local caravan = camp.parties[contract.caravanId]
		out.targetParty = contract.caravanId
		out.targetLocation = contract.toLocation
		if caravan and caravan.waiting then
			out.status = "The caravan waits for you at " .. CampaignConfig.getLocation(contract.fromLocation).name
		else
			out.status = string.format(
				"Caravan under way: %d%%",
				math.floor(math.clamp(contract.travelled / contract.routeLength, 0, 1) * 100)
			)
			out.daysLeft = nil
		end
	elseif contract.type == "RaidVillage" then
		out.status = "Ride to " .. CampaignConfig.getLocation(contract.targetLocation).name .. " and raid it"
	elseif contract.type == "Garrison" then
		out.status = string.format(
			"Attack on %s in %.1f days — be there",
			CampaignConfig.getLocation(contract.targetLocation).name,
			math.max(0, contract.deadlineDay - day)
		)
	end
	return out
end

CampaignService.hooks.describe = function(camp: any): any
	local board = {}
	for _, contract in camp.board do
		table.insert(board, describeContract(camp, contract, false))
	end
	return {
		board = board,
		contract = if camp.contract then describeContract(camp, camp.contract, true) else nil,
	}
end

return QuestService
