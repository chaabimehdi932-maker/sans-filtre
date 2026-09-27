--[[
	CampaignConfig (ReplicatedStorage.Modules.CampaignConfig)
	Everything about the mercenary campaign layer (overworld, factions, contracts, reputation,
	gold, squad evolution). Shared so the client can draw the map and show the same tables.

	⚠ Every number marked PLACEHOLDER is a first guess waiting for your tuning.

	Map units: the overworld is a 1000 × 1000 square (x, z). The client draws it 1 unit = 1 stud.
	Time: in-game days. Time only flows while your army travels or while you Wait.
]]

local CampaignConfig = {}

---------------------------------------------------------------------------
-- Factions (all use the same unit roster in v1: only colours and banners differ)
---------------------------------------------------------------------------

CampaignConfig.FactionOrder = { "Francia", "Albion", "Borussia" }

CampaignConfig.Factions = {
	Francia = {
		id = "Francia",
		displayName = "Empire of Francia",
		short = "Francia",
		emblem = "⚜",
		description = "A young empire hungry for glory. Pays well for daring raids.",
		color = Color3.fromRGB(45, 95, 215),
		uniform = {
			coat = Color3.fromRGB(34, 54, 140),
			facing = Color3.fromRGB(200, 35, 35),
			trousers = Color3.fromRGB(236, 236, 230),
			plume = Color3.fromRGB(210, 35, 35),
			saddlecloth = Color3.fromRGB(35, 55, 140),
		},
	},
	Albion = {
		id = "Albion",
		displayName = "Kingdom of Albion",
		short = "Albion",
		emblem = "♔",
		description = "Island redcoats with deep pockets and long supply lines.",
		color = Color3.fromRGB(205, 45, 45),
		uniform = {
			coat = Color3.fromRGB(185, 32, 32),
			facing = Color3.fromRGB(28, 38, 90),
			trousers = Color3.fromRGB(215, 215, 210),
			plume = Color3.fromRGB(240, 240, 240),
			saddlecloth = Color3.fromRGB(150, 30, 30),
		},
	},
	Borussia = {
		id = "Borussia",
		displayName = "Grand Duchy of Borussia",
		short = "Borussia",
		emblem = "✠",
		description = "Drilled, disciplined and always at war with somebody.",
		color = Color3.fromRGB(60, 150, 75),
		uniform = {
			coat = Color3.fromRGB(38, 70, 48),
			facing = Color3.fromRGB(215, 175, 60),
			trousers = Color3.fromRGB(225, 220, 200),
			plume = Color3.fromRGB(20, 20, 20),
			saddlecloth = Color3.fromRGB(40, 80, 50),
		},
	},
	-- Neutral third party, hostile to everyone
	Bandits = {
		id = "Bandits",
		displayName = "Bandits",
		short = "Bandits",
		emblem = "☠",
		description = "Deserters and cutthroats.",
		color = Color3.fromRGB(120, 85, 55),
		uniform = {
			coat = Color3.fromRGB(95, 70, 45),
			facing = Color3.fromRGB(60, 45, 30),
			trousers = Color3.fromRGB(130, 115, 90),
			plume = Color3.fromRGB(30, 30, 30),
			saddlecloth = Color3.fromRGB(70, 50, 35),
		},
	},
}

-- v1 diplomacy: every faction is at war with the other two; bandits are hostile to all
function CampaignConfig.hostile(a: string, b: string): boolean
	return a ~= b
end

---------------------------------------------------------------------------
-- Overworld locations and roads
---------------------------------------------------------------------------

CampaignConfig.MapSize = 1000

-- kind: "Town" (quest board, hire, replenish; never changes hands)
--       "Castle" (can be raided / must be garrisoned; changes hands)
--       "BanditCamp" (bandits roam around it)
CampaignConfig.Locations = {
	{ id = "Lutece", name = "Lutèce", kind = "Town", faction = "Francia", x = 210, z = 760 },
	{ id = "Montfort", name = "Castle Montfort", kind = "Castle", faction = "Francia", x = 360, z = 640 },
	{ id = "Valbonne", name = "Castle Valbonne", kind = "Castle", faction = "Francia", x = 130, z = 560 },

	{ id = "Londinium", name = "Londinium", kind = "Town", faction = "Albion", x = 790, z = 780 },
	{ id = "Ashford", name = "Castle Ashford", kind = "Castle", faction = "Albion", x = 640, z = 650 },
	{ id = "Greywick", name = "Castle Greywick", kind = "Castle", faction = "Albion", x = 880, z = 580 },

	{ id = "Konigsberg", name = "Königsberg", kind = "Town", faction = "Borussia", x = 500, z = 180 },
	{ id = "Eisenwald", name = "Castle Eisenwald", kind = "Castle", faction = "Borussia", x = 340, z = 300 },
	{ id = "Falkenhorst", name = "Castle Falkenhorst", kind = "Castle", faction = "Borussia", x = 670, z = 310 },

	{ id = "WolfDen", name = "Wolf's Den", kind = "BanditCamp", faction = "Bandits", x = 500, z = 520 },
	{ id = "RavenHollow", name = "Raven Hollow", kind = "BanditCamp", faction = "Bandits", x = 180, z = 330 },
	{ id = "SmugglersCove", name = "Smugglers' Cove", kind = "BanditCamp", faction = "Bandits", x = 830, z = 390 },
}

-- Roads (pairs of location ids). Travelling on a road is safer (fewer random encounters).
CampaignConfig.Roads = {
	{ "Lutece", "Montfort" },
	{ "Lutece", "Valbonne" },
	{ "Montfort", "Ashford" },
	{ "Montfort", "Eisenwald" },
	{ "Valbonne", "Eisenwald" },
	{ "Londinium", "Ashford" },
	{ "Londinium", "Greywick" },
	{ "Ashford", "Falkenhorst" },
	{ "Greywick", "Falkenhorst" },
	{ "Konigsberg", "Eisenwald" },
	{ "Konigsberg", "Falkenhorst" },
}

function CampaignConfig.getLocation(id: string): any
	for _, location in CampaignConfig.Locations do
		if location.id == id then
			return location
		end
	end
	return nil
end

-- Distance from (x, z) to the nearest road segment
function CampaignConfig.distanceToRoad(x: number, z: number): number
	local best = math.huge
	for _, road in CampaignConfig.Roads do
		local a, b = CampaignConfig.getLocation(road[1]), CampaignConfig.getLocation(road[2])
		local abx, abz = b.x - a.x, b.z - a.z
		local lengthSq = abx * abx + abz * abz
		local t = math.clamp(((x - a.x) * abx + (z - a.z) * abz) / lengthSq, 0, 1)
		local px, pz = a.x + abx * t, a.z + abz * t
		best = math.min(best, math.sqrt((x - px) ^ 2 + (z - pz) ^ 2))
	end
	return best
end

-- Shortest road route between two locations (list of location ids, inclusive), nil if none
function CampaignConfig.roadRoute(fromId: string, toId: string): { string }?
	local previous: { [string]: string } = {}
	local visited = { [fromId] = true }
	local queue = { fromId }
	while #queue > 0 do
		local current = table.remove(queue, 1) :: string
		if current == toId then
			local route = { toId }
			while route[1] ~= fromId do
				table.insert(route, 1, previous[route[1]])
			end
			return route
		end
		for _, road in CampaignConfig.Roads do
			local other = if road[1] == current then road[2] elseif road[2] == current then road[1] else nil
			if other and not visited[other] then
				visited[other] = true
				previous[other] = current
				table.insert(queue, other)
			end
		end
	end
	return nil
end

---------------------------------------------------------------------------
-- Travel, time and the living world
---------------------------------------------------------------------------

CampaignConfig.Travel = {
	DaysPerSecond = 0.1, -- PLACEHOLDER: real seconds → in-game days while moving (10 s = 1 day)
	-- time controls (bottom of the map screen): ❚❚ pause · ▶ play · ▶▶ fast. Menus and towns pause.
	FastSpeedMult = 3, -- PLACEHOLDER: ▶▶ speed
	ArmySpeed = 110, -- PLACEHOLDER: map units per day
	RoadWidth = 18, -- PLACEHOLDER: within this distance of a road you count as "on the road"
	ArriveRadius = 14, -- reaching a location
	ContactRadius = 12, -- PLACEHOLDER: a hostile party this close forces a battle
	EncounterWarning = 2.5, -- seconds the "Ambush!" banner shows before the battle loads
	SafeAfterBattleDays = 0.6, -- PLACEHOLDER: no encounters/contacts right after a battle
}

CampaignConfig.Encounters = {
	ChancePerDayOffRoad = 0.35, -- PLACEHOLDER: random encounter chance per travelled day off-road
	ChancePerDayOnRoad = 0.07, -- PLACEHOLDER: …and on a road
	RivalPatrolShare = 0.35, -- PLACEHOLDER: share of random encounters that are rival patrols (rest: bandits)
}

CampaignConfig.Parties = {
	BanditParties = 4, -- PLACEHOLDER: roaming bandit warbands kept on the map
	PatrolsPerFaction = 2, -- PLACEHOLDER: roaming patrols per faction
	BanditSpeed = 80, -- PLACEHOLDER: map units / day
	PatrolSpeed = 90, -- PLACEHOLDER
	CaravanSpeed = 55, -- PLACEHOLDER
	BanditRoamRadius = 170, -- how far bandits wander from their camp
	ChaseRadius = 70, -- PLACEHOLDER: hostile parties chase you when this close
	ChaseSpeedMult = 1.15, -- chasing parties speed up a little (you are still faster)
}

-- Strength of battles. A "strength" feeds GameConfig.getRound(strength) for the enemy army.
-- threat = 1 + floor(battlesWon / ThreatPerWins), capped: the world gets tougher as you grow.
CampaignConfig.Difficulty = {
	ThreatPerWins = 3, -- PLACEHOLDER
	MaxThreat = 8, -- PLACEHOLDER
	BanditStrength = { 1, 3 }, -- PLACEHOLDER: random range, + threat - 1
	PatrolStrength = { 2, 4 }, -- PLACEHOLDER
	CastleStrength = 4, -- PLACEHOLDER: raid garrison, + threat
	GarrisonAttackStrength = 3, -- PLACEHOLDER: attackers in a Garrison contract, + threat
	BountyStrength = 3, -- PLACEHOLDER: + threat
	AmbushStrength = 2, -- PLACEHOLDER: escort ambushes, + threat
	BanditStatMult = 0.8, -- PLACEHOLDER: bandits are weaker on average
	-- the named leader of a Bounty warband fights as a boss squad
	BountyBoss = { unitId = "EliteGuard", statMultiplier = 1.4, damageMultiplier = 1.2 }, -- PLACEHOLDER
	BanditNoArtillery = true, -- bandits field skirmishers instead of guns, line instead of guard
}

---------------------------------------------------------------------------
-- Economy
---------------------------------------------------------------------------

CampaignConfig.Economy = {
	StartingGold = 300, -- PLACEHOLDER
	StartingRoster = { "LineInfantry", "Skirmishers" }, -- PLACEHOLDER: squads you start with
	MaxRosterSize = 6, -- PLACEHOLDER: squads you can own at once
	-- hire price = UnitDefinitions[unit].cost × HireCostMult
	HireCostMult = 1, -- PLACEHOLDER
	-- refilling a missing soldier costs (unit cost / soldiers) × ReplenishCostMult
	ReplenishCostMult = 0.6, -- PLACEHOLDER
	-- losing a battle: lose LossGoldPercent of your gold, plus LossGoldFlat
	LossGoldPercent = 0.2, -- PLACEHOLDER (0.2 = 20 %)
	LossGoldFlat = 0, -- PLACEHOLDER
	-- loot after beating a roaming party: LootBase + LootPerStrength × strength
	LootBase = 40, -- PLACEHOLDER
	LootPerStrength = 20, -- PLACEHOLDER
	-- if every squad is gone and you can't afford one, you get a free levy of this unit
	FreeLevyUnit = "LineInfantry",
	FreeLevyStrength = 0.6, -- PLACEHOLDER: levy starts at 60 % of its men
}

CampaignConfig.Battle = {
	Reinforcements = 0, -- PLACEHOLDER: free replacement squads per battle (0 = losses are real)
	RaidAllies = 2, -- PLACEHOLDER: employer squads that join your raid
	GarrisonAllies = 2, -- PLACEHOLDER: castle garrison squads fighting beside you
	CaravanGuards = 1, -- PLACEHOLDER: caravan guard squads in an ambush battle
	WipedSquadsLostOnVictory = true, -- a squad wiped out is gone forever even if you win
}

---------------------------------------------------------------------------
-- Towns you walk around in (your employer's towns)
---------------------------------------------------------------------------

CampaignConfig.Town = {
	-- the free-company captain in the tavern sells veteran squads (already ★ or ★★)
	MercenaryOffers = 3, -- PLACEHOLDER: offers at a time
	MercenaryRefreshDays = 4, -- PLACEHOLDER
	MercenaryStars = { 1, 2 }, -- PLACEHOLDER: random range of stars
	MercenaryCostPerStar = 0.6, -- PLACEHOLDER: price = hire price × (1 + stars × this)
	-- the arms merchant in the market re-equips and drills a squad: gold → squad XP
	DrillXP = 60, -- PLACEHOLDER
	DrillCost = 150, -- PLACEHOLDER: × (1 + stars × DrillCostPerStar)
	DrillCostPerStar = 0.5, -- PLACEHOLDER
}

---------------------------------------------------------------------------
-- Contracts (quest board at your employer's town)
---------------------------------------------------------------------------

CampaignConfig.Contracts = {
	BoardSize = 4, -- PLACEHOLDER: contracts on the board
	BoardRefreshDays = 3, -- PLACEHOLDER: untaken contracts are replaced this often
	MaxActive = 1, -- contracts you can hold at once
	Types = {
		Raid = {
			displayName = "Raid",
			icon = "⚔",
			gold = 600, -- PLACEHOLDER
			reputation = 30, -- PLACEHOLDER
			failReputation = 20, -- PLACEHOLDER: reputation lost on failure
			deadlineDays = 12, -- PLACEHOLDER
		},
		Bounty = {
			displayName = "Bounty",
			icon = "☠",
			gold = 350, -- PLACEHOLDER
			reputation = 20, -- PLACEHOLDER
			failReputation = 12, -- PLACEHOLDER
			deadlineDays = 10, -- PLACEHOLDER
		},
		Escort = {
			displayName = "Escort",
			icon = "🛒",
			gold = 300, -- PLACEHOLDER
			reputation = 18, -- PLACEHOLDER
			failReputation = 15, -- PLACEHOLDER
			deadlineDays = 5, -- PLACEHOLDER: days to meet the caravan before it gives up
			escortRadius = 60, -- PLACEHOLDER: you must be this close to intercept an ambush
			ambushes = 2, -- PLACEHOLDER: ambushes along the route
		},
		Garrison = {
			displayName = "Garrison",
			icon = "🏰",
			gold = 400, -- PLACEHOLDER
			reputation = 22, -- PLACEHOLDER
			failReputation = 18, -- PLACEHOLDER
			leadDays = { 4, 7 }, -- PLACEHOLDER: the attack comes this many days after accepting
			stationRadius = 30, -- PLACEHOLDER: be this close to the castle when it's attacked
		},
	},
	-- Chance weights when the board generates a contract
	Weights = { Raid = 3, Bounty = 3, Escort = 2, Garrison = 2 }, -- PLACEHOLDER
	BountyNames = {
		"Le Loup's Brigands",
		"Black Jack's Raiders",
		"The Red Hand",
		"Mad Otto's Deserters",
		"The Crows of Ravel",
		"Captain Grim's Cutthroats",
	},
}

---------------------------------------------------------------------------
-- Reputation → how many squads you command directly in battle
---------------------------------------------------------------------------

CampaignConfig.Reputation = {
	Min = 0, -- reputation never drops below this
	-- ascending: at `reputation` or more you command `maxSquads` squads at once
	Tiers = {
		{ reputation = 0, maxSquads = 1, title = "Sellsword" }, -- PLACEHOLDER
		{ reputation = 50, maxSquads = 2, title = "Captain" }, -- PLACEHOLDER
		{ reputation = 150, maxSquads = 3, title = "Condottiere" }, -- PLACEHOLDER
		{ reputation = 350, maxSquads = 4, title = "Warlord" }, -- PLACEHOLDER
	},
}

function CampaignConfig.reputationTier(reputation: number): (any, any?)
	local tiers = CampaignConfig.Reputation.Tiers
	local current, nextTier = tiers[1], nil
	for i, tier in tiers do
		if reputation >= tier.reputation then
			current = tier
			nextTier = tiers[i + 1]
		end
	end
	return current, nextTier
end

---------------------------------------------------------------------------
-- Squad evolution (the veteran stars ARE the evolution tiers)
---------------------------------------------------------------------------

CampaignConfig.Evolution = {
	XPPerKill = 2, -- PLACEHOLDER: squad XP per enemy soldier this squad killed
	XPSurvive = 20, -- PLACEHOLDER: squad XP for surviving a battle
	XPVictory = 15, -- PLACEHOLDER: extra squad XP when the battle is won
	-- tier = number of stars. statMult → HP & morale, damageMult → all damage
	Tiers = {
		{ xp = 0, statMult = 1, damageMult = 1, name = "Recruits" },
		{ xp = 100, statMult = 1.1, damageMult = 1.1, name = "Veterans" }, -- PLACEHOLDER
		{ xp = 300, statMult = 1.22, damageMult = 1.2, name = "Seasoned" }, -- PLACEHOLDER
		{ xp = 700, statMult = 1.35, damageMult = 1.32, name = "Elite" }, -- PLACEHOLDER
	},
}

-- Stars (0 = none) for an amount of squad XP
function CampaignConfig.tierForXP(xp: number): number
	local stars = 0
	for i, tier in CampaignConfig.Evolution.Tiers do
		if xp >= tier.xp then
			stars = i - 1
		end
	end
	return stars
end

function CampaignConfig.tierInfo(stars: number): any
	local tiers = CampaignConfig.Evolution.Tiers
	return tiers[math.clamp(stars + 1, 1, #tiers)]
end

return CampaignConfig
