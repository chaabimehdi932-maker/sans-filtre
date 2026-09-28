--[[
	RecruitmentService
	The player's ARMY is a saved roster of squads (profile.Campaign.Roster), each with its own
	headcount and XP. XP sets the squad's evolution tier = its veteran stars (★), which give
	real stats (CampaignConfig.Evolution.Tiers) and a better-looking uniform/weapon.
	  • before a battle (Deployment phase) the whole roster deploys; the player presses READY
	  • in battle the player commands up to N squads directly (reputation), the rest run on
	    the ally AI (CommandService / AllyAIController)
	  • after a battle: wiped squads are gone forever, survivors keep their casualties and
	    earn XP (kills + survival), possibly evolving a tier
	  • at a friendly town: hire new squads and replenish casualties with gold
	Reinforcements (a temporary squad when all of yours fall) are off by default in the
	campaign: CampaignConfig.Battle.Reinforcements.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local CampaignConfig = require(Modules:WaitForChild("CampaignConfig"))
local GameConfig = require(Modules:WaitForChild("GameConfig"))
local Remotes = require(Modules:WaitForChild("Remotes"))
local UnitDefinitions = require(Modules:WaitForChild("UnitDefinitions"))

local DataService = require(script.Parent:WaitForChild("DataService"))
local MapService = require(script.Parent:WaitForChild("MapService"))
local SquadService = require(script.Parent:WaitForChild("SquadService"))

local R = GameConfig.Recruitment
local Economy = CampaignConfig.Economy
local Evolution = CampaignConfig.Evolution

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

local function ordinal(n: number): string
	local lastTwo = n % 100
	local suffix = "th"
	if lastTwo < 11 or lastTwo > 13 then
		suffix = ({ "st", "nd", "rd" })[n % 10] or "th"
	end
	return n .. suffix
end

local function roster(player: Player): { any }
	local campaign = DataService.getCampaign(player)
	return if campaign then campaign.Roster else {}
end

local function entryName(entry: any): string
	return ordinal(entry.id) .. " " .. UnitDefinitions.get(entry.unitId).displayName
end

-- Daily wage of one squad (evolved squads and full ranks cost more)
function RecruitmentService.wageFor(entry: any): number
	local def = UnitDefinitions.get(entry.unitId)
	local stars = CampaignConfig.tierForXP(entry.xp)
	local wages = CampaignConfig.Wages
	return (def.cost or 100) * wages.CostFraction * (1 + stars * wages.PerStar) * (entry.soldiers / def.soldiers)
end

function RecruitmentService.totalWages(player: Player): number
	local total = 0
	for _, entry in roster(player) do
		total += RecruitmentService.wageFor(entry)
	end
	return total
end

-- Branch choices waiting for this squad (it reached the stars of a branching point)
function RecruitmentService.branchOptions(entry: any): { string }?
	local branch = CampaignConfig.Branches[entry.unitId]
	if branch and CampaignConfig.tierForXP(entry.xp) >= branch.stars then
		return branch.options
	end
	return nil
end

-- The player picks what the squad becomes; it keeps its XP, stars and share of its men
function RecruitmentService.chooseBranch(player: Player, squadId: number, unitId: string): (boolean, string)
	for _, entry in roster(player) do
		if entry.id == squadId then
			local options = RecruitmentService.branchOptions(entry)
			if not options or not table.find(options, unitId) then
				return false, "That squad can't take this path"
			end
			local old, new = UnitDefinitions.get(entry.unitId), UnitDefinitions.get(unitId)
			entry.unitId = unitId
			entry.soldiers = math.max(1, math.floor(entry.soldiers / old.soldiers * new.soldiers + 0.5))
			RecruitmentService.sendState(player)
			return true, string.format("The %s become %s!", old.displayName, new.displayName)
		end
	end
	return false, "Unknown squad"
end

local function nextTierXP(stars: number): number?
	local nextTier = Evolution.Tiers[stars + 2]
	return if nextTier then nextTier.xp else nil
end

local function campaignUnpaid(player: Player): number
	local campaign = DataService.getCampaign(player)
	return if campaign then math.floor((campaign.UnpaidDays or 0) * 10) / 10 else 0
end

function RecruitmentService.sendState(player: Player)
	local session = sessions[player]
	if not session then
		return
	end
	local unlocked = {}
	for unitId in UnitDefinitions.Units do
		unlocked[unitId] = DataService.isUnlocked(player, unitId)
	end
	local list = {}
	for _, entry in roster(player) do
		local def = UnitDefinitions.get(entry.unitId)
		local stars = CampaignConfig.tierForXP(entry.xp)
		table.insert(list, {
			id = entry.id,
			unitId = entry.unitId,
			wage = math.floor(RecruitmentService.wageFor(entry) * 10 + 0.5) / 10,
			companion = entry.companion,
			branchOptions = RecruitmentService.branchOptions(entry),
			name = entryName(entry),
			xp = math.floor(entry.xp),
			stars = stars,
			nextXP = nextTierXP(stars),
			soldiers = entry.soldiers,
			maxSoldiers = def.soldiers,
		})
	end
	stateRemote:FireClient(player, {
		roster = list,
		maxRoster = Economy.MaxRosterSize,
		unlocked = unlocked,
		ready = session.ready,
		open = phaseOpen and session.inPhase == true,
		reinforcements = session.reinforcements,
		reinforcementAt = session.reinforcementAt,
		replenishCost = RecruitmentService.replenishCost(player),
		dailyWages = math.floor(RecruitmentService.totalWages(player) + 0.5),
		unpaidDays = campaignUnpaid(player),
	})
end
local sendState = RecruitmentService.sendState

function RecruitmentService.initPlayer(player: Player)
	sessions[player] = { ready = false, reinforcements = 0, deployed = {} }
	sendState(player)
end

function RecruitmentService.removePlayer(player: Player)
	sessions[player] = nil
end

---------------------------------------------------------------------------
-- Roster management
---------------------------------------------------------------------------

function RecruitmentService.getRoster(player: Player): { any }
	return roster(player)
end

-- Adds a squad to the roster (fraction = starting headcount share). Returns the entry.
function RecruitmentService.addSquad(player: Player, unitId: string, fraction: number?): any
	local campaign = DataService.getCampaign(player)
	local def = UnitDefinitions.get(unitId)
	if not campaign or not def then
		return nil
	end
	local entry = {
		id = campaign.NextSquadId,
		unitId = unitId,
		xp = 0,
		soldiers = math.max(1, math.floor(def.soldiers * (fraction or 1) + 0.5)),
	}
	campaign.NextSquadId += 1
	table.insert(campaign.Roster, entry)
	sendState(player)
	return entry
end

function RecruitmentService.giveStartingRoster(player: Player)
	for _, unitId in Economy.StartingRoster do
		RecruitmentService.addSquad(player, unitId)
	end
end

function RecruitmentService.hireCost(unitId: string): number
	local def = UnitDefinitions.get(unitId)
	return if def then math.floor((def.cost or 100) * Economy.HireCostMult) else math.huge
end

-- Returns ok, message
function RecruitmentService.hire(player: Player, unitId: string): (boolean, string)
	local campaign = DataService.getCampaign(player)
	local def = UnitDefinitions.get(unitId)
	if not campaign or not def or def.hidden then
		return false, "Unknown unit"
	end
	if not DataService.isUnlocked(player, unitId) then
		return false, def.displayName .. " is locked (win " .. tostring(def.unlockRoundsWon) .. " battles)"
	end
	if #campaign.Roster >= Economy.MaxRosterSize then
		return false, "Your army is full (" .. Economy.MaxRosterSize .. " squads)"
	end
	local cost = RecruitmentService.hireCost(unitId)
	if campaign.Gold < cost then
		return false, "Not enough gold (" .. cost .. " needed)"
	end
	campaign.Gold -= cost
	local entry = RecruitmentService.addSquad(player, unitId)
	return true, "Hired the " .. entryName(entry) .. " for " .. cost .. " gold"
end

-- Dismiss a squad (frees a roster slot, no refund)
function RecruitmentService.dismiss(player: Player, squadId: number): boolean
	local list = roster(player)
	for i, entry in list do
		if entry.id == squadId then
			table.remove(list, i)
			sendState(player)
			return true
		end
	end
	return false
end

local function soldierCost(unitId: string): number
	local def = UnitDefinitions.get(unitId)
	return (def.cost or 100) / def.soldiers * Economy.ReplenishCostMult
end

function RecruitmentService.replenishCost(player: Player): number
	local total = 0
	for _, entry in roster(player) do
		local def = UnitDefinitions.get(entry.unitId)
		total += math.max(0, def.soldiers - entry.soldiers) * soldierCost(entry.unitId)
	end
	return math.ceil(total)
end

-- Refill as many missing soldiers as the player can afford. Returns soldiers added, gold spent.
function RecruitmentService.replenish(player: Player): (number, number)
	local campaign = DataService.getCampaign(player)
	if not campaign then
		return 0, 0
	end
	local added, spent = 0, 0
	for _, entry in campaign.Roster do
		local def = UnitDefinitions.get(entry.unitId)
		local price = soldierCost(entry.unitId)
		while entry.soldiers < def.soldiers and campaign.Gold - spent >= price do
			entry.soldiers += 1
			spent += price
			added += 1
		end
	end
	spent = math.ceil(spent)
	campaign.Gold = math.max(0, campaign.Gold - spent)
	sendState(player)
	return added, spent
end

-- Never leave a player with no army and no way to get one
function RecruitmentService.ensureArmy(player: Player): boolean
	local campaign = DataService.getCampaign(player)
	if not campaign or #campaign.Roster > 0 then
		return false
	end
	if campaign.Gold >= RecruitmentService.hireCost(Economy.FreeLevyUnit) then
		return false
	end
	RecruitmentService.addSquad(player, Economy.FreeLevyUnit, Economy.FreeLevyStrength)
	return true
end

---------------------------------------------------------------------------
-- Deployment phase
---------------------------------------------------------------------------

function RecruitmentService.openPhase(participants: { Player }, cfg: any)
	phaseOpen = true
	for _, player in participants do
		local session = sessions[player]
		if session then
			session.inPhase = true
			session.ready = false
			session.reinforcements = cfg.reinforcements or 0
			session.reinforcementAt = nil
			session.deployed = {}
			session.squad = nil
			sendState(player)
		end
	end
end

function RecruitmentService.closePhase()
	phaseOpen = false
	for player, session in sessions do
		if session.inPhase then
			sendState(player)
		end
	end
end

function RecruitmentService.allReady(participants: { Player }): boolean
	local any = false
	for _, player in participants do
		local session = sessions[player]
		if session then
			any = true
			if not session.ready then
				return false
			end
		end
	end
	return any
end

Remotes.get("ConfirmRecruit").OnServerEvent:Connect(function(player: Player)
	local session = sessions[player]
	if phaseOpen and session and session.inPhase then
		session.ready = true
		sendState(player)
	end
end)

-- The companion leading a roster squad, if he is fit to lead
local Companions = CampaignConfig.Companions
function RecruitmentService.companionOf(player: Player, entry: any): any
	local campaign = DataService.getCampaign(player)
	if not campaign or not entry.companion then
		return nil
	end
	for _, companion in campaign.Companions or {} do
		if companion.id == entry.companion and (companion.woundedUntil or 0) <= campaign.Day then
			return companion
		end
	end
	return nil
end

local function spawnRosterSquad(player: Player, entry: any, spot: any): any
	local def = UnitDefinitions.get(entry.unitId)
	local companion = RecruitmentService.companionOf(player, entry)
	local info = companion and Companions.List[companion.id]
	local stars = CampaignConfig.tierForXP(entry.xp)
	local tier = CampaignConfig.tierInfo(stars)
	local squad = SquadService.create({
		unitId = entry.unitId,
		team = "Blue",
		position = spot.position,
		yaw = spot.yaw,
		owner = player,
		name = entryName(entry),
		rank = stars,
		rosterId = entry.id,
		healthFraction = entry.soldiers / def.soldiers,
		-- unpaid troops come to the field sulking
		moraleFraction = math.max(
			CampaignConfig.Wages.MinMorale,
			1 - campaignUnpaid(player) * CampaignConfig.Wages.MoralePenaltyPerDay
		),
		statMultiplier = tier.statMult,
		damageMultiplier = tier.damageMult,
		commanderName = info and info.name,
		companionSkill = info and info.skill,
	})
	squad.companionId = companion and companion.id
	return squad
end

--[[
	Deploys every participant's roster plus the battle's allied AI squads.
	Returns { [Player] = { squads } } (roster order).
]]
function RecruitmentService.deployAll(cfg: any, participants: { Player }): { [Player]: { any } }
	local entries = {}
	for _, player in participants do
		if sessions[player] then
			if cfg.enlisted then
				-- serving in a general's army: you lead one of HIS squads, your company stays in camp
				table.insert(entries, { player = player, temporary = cfg.enlisted })
			else
				for _, entry in roster(player) do
					table.insert(entries, { player = player, entry = entry })
				end
			end
		end
	end
	local allies = cfg.allies or {}
	local spots = MapService.deployPositions("Blue", math.max(1, #entries + #allies), R.DeploySpacing)
	-- the player's squads get the spots closest to the centre of the front line
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
	local created: { [Player]: { any } } = {}
	local nextSpot = 1
	for _, item in entries do
		local spot = spots[order[nextSpot]]
		nextSpot += 1
		local session = sessions[item.player]
		local squad
		if item.temporary then
			squad = SquadService.create({
				unitId = item.temporary.unitId,
				team = "Blue",
				position = spot.position,
				yaw = spot.yaw,
				owner = item.player,
				name = item.temporary.name,
			})
		else
			squad = spawnRosterSquad(item.player, item.entry, spot)
			session.deployed[squad] = item.entry
		end
		session.squad = session.squad or squad
		created[item.player] = created[item.player] or {}
		table.insert(created[item.player], squad)
	end
	for _, ally in allies do
		local spot = spots[order[nextSpot]]
		nextSpot += 1
		SquadService.create({
			unitId = ally.unitId,
			team = "Blue",
			position = spot.position,
			yaw = spot.yaw,
			name = ally.name,
		})
	end
	return created
end

-- Called when one of a player's squads is destroyed during a battle
function RecruitmentService.onPlayerSquadLost(player: Player, lostSquad: any)
	local session = sessions[player]
	if not session or session.reinforcements <= 0 or session.reinforcementAt then
		return
	end
	if #SquadService.getOwnedBy(player) > 0 then
		return -- reinforcements only come once every one of your squads has fallen
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
		-- a temporary levy: not part of your saved roster
		local squad = SquadService.create({
			unitId = lostSquad.unitId,
			team = "Blue",
			position = spot.position,
			yaw = spot.yaw,
			owner = player,
			name = "Levy " .. lostSquad.def.displayName,
		})
		sendState(player)
		RecruitmentService.hooks.onReinforced(player, squad)
	end)
end

-- Can the Blue side still get squads back?
function RecruitmentService.reinforcementsPending(participants: { Player }): boolean
	for _, player in participants do
		local session = sessions[player]
		if session and (session.reinforcementAt or session.reinforcements > 0) then
			return true
		end
	end
	return false
end

function RecruitmentService.cancelReinforcements()
	for player, session in sessions do
		if session.reinforcementAt then
			session.reinforcementAt = nil
			sendState(player)
		end
	end
end

--[[
	After a battle: update the saved roster from what happened on the field.
	Returns a report { lost = { names }, evolved = { { name, stars, tierName } }, xp = { [name] = gained } }
]]
function RecruitmentService.afterBattle(player: Player, victory: boolean): any
	local session = sessions[player]
	local report = { lost = {}, evolved = {}, wounded = {}, survivors = 0 }
	if not session then
		return report
	end
	local campaign = DataService.getCampaign(player)
	for squad, entry in session.deployed do
		local name = entryName(entry)
		local index = table.find(campaign.Roster, entry)
		if not index then
			continue -- dismissed meanwhile
		end
		-- a companion whose squad was wiped or who fell is wounded (he never dies)
		local companionId = squad.companionId
		if companionId and (not squad.alive or not squad.commanderAlive) then
			for _, companion in campaign.Companions or {} do
				if companion.id == companionId then
					companion.woundedUntil = campaign.Day + Companions.WoundDays
					table.insert(report.wounded, Companions.List[companionId].name)
				end
			end
		end
		if not squad.alive then
			if victory and not CampaignConfig.Battle.WipedSquadsLostOnVictory then
				entry.soldiers = 1
			else
				table.remove(campaign.Roster, index) -- gone for good
				table.insert(report.lost, name)
				continue
			end
		else
			local skill = Companions.Skills[squad.companionSkill or ""]
			local dead = entry.soldiers - squad.soldierCount
			local recovered = if skill and skill.recover and dead > 0 then math.floor(dead * skill.recover) else 0
			entry.soldiers = math.max(1, squad.soldierCount + recovered)
			report.survivors += 1
		end
		local before = CampaignConfig.tierForXP(entry.xp)
		local gained = squad.stats.kills * Evolution.XPPerKill
		if squad.alive then
			gained += Evolution.XPSurvive + (if victory then Evolution.XPVictory else 0)
		end
		local xpSkill = Companions.Skills[squad.companionSkill or ""]
		entry.xp += gained * (if xpSkill and xpSkill.xpMult then xpSkill.xpMult else 1)
		local after = CampaignConfig.tierForXP(entry.xp)
		if after > before then
			table.insert(report.evolved, {
				name = name,
				stars = after,
				tierName = CampaignConfig.tierInfo(after).name,
				branch = RecruitmentService.branchOptions(entry) ~= nil,
			})
		end
	end
	session.deployed = {}
	session.squad = nil
	session.inPhase = false
	sendState(player)
	return report
end

return RecruitmentService
