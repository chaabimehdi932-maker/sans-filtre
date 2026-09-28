--[[
	GameConfig (ReplicatedStorage.Modules.GameConfig)
	Every tunable number that isn't a unit or formation stat lives here.
	⚠ All values are PLACEHOLDERS meant to be tuned.
]]

local GameConfig = {}

-- Bump on every update: printed in the Output and shown in the HUD so you can check what runs
GameConfig.Version = "0.12"

GameConfig.Teams = {
	Blue = { displayName = "France", color = Color3.fromRGB(45, 95, 215), uniform = Color3.fromRGB(35, 60, 150) },
	Red = { displayName = "Coalition", color = Color3.fromRGB(205, 45, 45), uniform = Color3.fromRGB(175, 35, 35) },
	Neutral = { displayName = "Neutral", color = Color3.fromRGB(200, 200, 200) },
}

GameConfig.Phases = {
	RecruitmentTime = 40, -- seconds to pick your unit before deployment
	BattleTimeLimit = 420, -- seconds before the battle ends on its own
	RewardTime = 25, -- seconds the summary stays up (or until everyone clicks Continue)
}

GameConfig.Recruitment = {
	DefaultUnit = "LineInfantry", -- picked for you if you don't choose
	Reinforcements = 3, -- times your squad comes back per battle after being wiped out
	ReinforcementDelay = 15, -- seconds before the fresh squad arrives
	DeploySpacing = 72, -- studs between squads when deploying (single-rank lines are wide)
	MaxVeteranRank = 3, -- stars earned by surviving battles
	VeteranBonusPerRank = 0.08, -- +8% HP and damage per star
}

GameConfig.Rewards = {
	FastWinTime = 180, -- win faster than this (seconds) for the bonus XP
	FastWinBonusXP = 60,
	XPPerZoneHeld = 25,
	XPWin = 150,
	XPLoss = 40,
	XPPerKill = 4, -- per enemy soldier killed by YOUR squad or by you
	KillComboWindow = 6, -- seconds to chain kills into a combo
	XPPerHeroDamage = 0.15, -- XP per point of damage the commander deals personally
	XPPerZoneCapture = 40,
}

-- The player's own character (the commander)
GameConfig.Hero = {
	MaxHealth = 200,
	HealthPerLevel = 5,
	DamagePerLevelMult = 0.02, -- +2% personal damage per level
	WalkSpeed = 16,
	JumpPower = 50,
	MountedSpeed = 30,
	MountLift = 2.2, -- how much higher the character sits when mounted (studs)
	AutoMountOnSpawn = true,
	BlockSpeedMult = 0.5,
	BlockReduction = 0.8, -- 80% less damage from the front while blocking

	AttackDamage = 45,
	AttackRange = 8,
	AttackCooldown = 0.7,
	AttackConeDegrees = 100,
	MountedAttackRange = 11,
	MountedAttackCooldown = 1.1,
	MountedChargeMultiplier = 2.5, -- damage multiplier at full gallop

	RollCooldown = 3,
	RollIFrames = 0.45,
	RollSpeed = 55,
	RollDuration = 0.3,

	HealCooldown = 25,
	HealFraction = 0.4, -- heals 40% of max HP
	HealMoraleBoost = 20, -- morale given to your squads nearby
	HealMoraleRadius = 40,

	MountCooldown = 1.5,
	DamageTakenFromSquadsMult = 0.25, -- squads deal this fraction of their damage to the commander
	MountedDamageTakenMult = 0.85,
	RespawnTime = 6,
}

GameConfig.Orders = {
	List = { "Hold", "Follow", "Attack", "Rush" },
	FollowDistance = 24, -- how far behind the commander following squads stand
	FollowSpacing = 30, -- side-by-side spacing of several following squads
	RushSpeedMult = 2.1, -- rushing infantry sprint
	RushCavalrySpeedMult = 1.7, -- cavalry at full gallop
	RushMaxDistance = 220, -- furthest point a Rush can be aimed at (studs from the squad)
	RushPierceMult = 1.4, -- rushing cavalry hit every squad they ride through (× charge damage)
	RushDamageTakenMult = 1.2, -- rushing breaks formation discipline
	AttackSearchRadius = 350,
	HoldAhead = 16, -- the Hold preview is placed this far in front of the commander
	HoldMaxDistance = 250, -- server rejects Hold positions further than this from the commander
	RushEnemyRadius = 90,
	RushCooldown = 15, -- seconds between two Rush orders (server enforced)
}

GameConfig.Morale = {
	CasualtyLossFactor = 120, -- losing 100% HP would cost 120 morale (so 25% HP ≈ 30 morale)
	FlankedMult = 1.5, -- morale loss multiplier when hit from the side/rear
	ChargeShock = 20, -- extra morale lost when hit by a charge
	IsolationRadius = 45, -- no friendly squad this close = isolated
	IsolationDrain = 2, -- morale/second lost while fighting isolated
	RegenOutOfCombat = 4, -- morale/second regained out of combat, near friends
	RegenAloneMult = 0.4,
	CombatCooldown = 5, -- seconds without fighting before a squad counts as "out of combat"
	RoutRecoverDelay = 4, -- seconds without being hit before a routing squad starts recovering
	RoutRegen = 3,
	RoutRecoverFraction = 0.5, -- routing squads rally at 50% morale…
	RoutSafeDistance = 15, -- …or when they reach their spawn
	RoutSpeedMult = 1.2,
	RegroupTime = 3,
}

GameConfig.Combat = {
	TickInterval = 0.2, -- how often targeting/firing is evaluated (not every frame)
	DamageRandomMin = 0.8,
	DamageRandomMax = 1.2,
	RangeFalloff = 0.4, -- volleys lose up to 40% damage at max range
	MinStrengthFactor = 0.3, -- a squad at 1 HP still fires at 30% strength
	FiringArcDegrees = 50, -- must face the target within this angle to fire
	TurnSpeed = math.rad(120), -- radians/second
	ArtilleryTurnSpeed = math.rad(40),
	ArtilleryShellSpeed = 120, -- studs/second
	ArtilleryScatter = 8, -- max miss distance at max range
	ChargeBuildTime = 1.5, -- seconds at speed before a charge is "armed"
	ChargeSpeedFraction = 0.7, -- must move at 70%+ of base speed to build a charge
	ChargeGrace = 0.8, -- a charge stays armed this long after stopping (contact frame)
	RoutingDamageTakenMult = 1.25,
	-- Musket precision by formation quality (multiplies volley damage). A clean single-rank
	-- Line fires at full precision; every extra rank, a column, a disordered or moving unit less.
	-- Square keeps its anti-cavalry role but shoots poorly.
	Accuracy = {
		Line = 1, -- PLACEHOLDER: single rank
		PerExtraRank = 0.2, -- PLACEHOLDER: −20 % per rank behind the first
		Column = 0.45, -- PLACEHOLDER
		Square = 0.6, -- PLACEHOLDER
		Forming = 0.5, -- PLACEHOLDER: changing formation (disordered)
		Moving = 0.6, -- PLACEHOLDER: firing on the move (skirmishers)
		Settling = 0.75, -- PLACEHOLDER: just halted, the men are still finding their places
		SettleTime = 1.5, -- PLACEHOLDER: seconds to settle into strict formation after a halt
		Turning = 0.8, -- PLACEHOLDER: wheeling to face the target
		Minimum = 0.2,
	},
}

-- Every squad is led by an officer on horseback, riding at its front (the player leads the
-- squads they command directly). Killing him shakes the whole squad.
GameConfig.Commander = {
	Health = 140, -- PLACEHOLDER
	-- share of the damage a squad takes that hits its officer, by attack kind
	Exposure = { Ranged = 0.05, Artillery = 0.06, Melee = 0.1, Charge = 0.18, Hero = 0.35 }, -- PLACEHOLDER
	DeathMorale = 45, -- PLACEHOLDER: morale lost when the officer falls
	RaiseTime = 1.6, -- seconds the officer raises his sabre after an order
	FrontOffset = 7, -- studs ahead of the front rank
}

-- Battlefield terrain: height, woods and water
GameConfig.Terrain = {
	HeightAdvantage = 4, -- studs higher than the target to count as high ground
	HighGroundMult = 1.15, -- PLACEHOLDER: damage (volleys and melee) from above
	LowGroundMult = 0.9, -- PLACEHOLDER: damage from below
	ForestAccuracy = 0.6, -- PLACEHOLDER: formations break up among the trees
	ForestCover = 0.75, -- PLACEHOLDER: musket damage taken inside woods
	ForestSpeed = { Cavalry = 0.55, Infantry = 0.85, Artillery = 0.5 }, -- PLACEHOLDER
	WaterSpeed = 0.6, -- PLACEHOLDER: wading through a river
	WaterAccuracy = 0.8, -- PLACEHOLDER
	CheckInterval = 0.5,
}

-- Battle rules
GameConfig.Battle = {
	-- Hopeless odds: if the enemy's strength (remaining HP) is this many times yours, your
	-- whole side routs and the battle is lost. Checked at the start and during the fight.
	HopelessRatio = 8, -- PLACEHOLDER (1:8)
	HopelessCheckInterval = 1,
	HopelessRoutTime = 4, -- seconds of fleeing before the Defeat screen
	-- An army whose every squad is routing has lost (after this many seconds)
	AllRoutedTime = 5, -- PLACEHOLDER
}

GameConfig.Zones = {
	TickInterval = 0.5,
	CaptureRate = 8, -- control points/second at weight 1 (full capture = 100, from enemy = 200)
	WeightBonusPerExtra = 0.25, -- each extra point of presence weight speeds capture by 25%
	MaxRateMult = 3,
	HeroPresenceWeight = 1,
	HoldTimeToWin = 20, -- seconds all zones must be held to win an attack round
	-- "Reinforcements" zones: each one held cuts your reinforcement delay by 40%
	ArtilleryRangeBonus = 0.25, -- +25% artillery range per ArtilleryRange zone held
	MoraleRegenBonus = 0.5, -- +50% morale regen per Morale zone held
}

GameConfig.AI = {
	-- Allied squads you are not commanding directly (AllyAIController)
	Ally = { aggression = 0.6, flankPreference = 0.35, retreatThreshold = 0.25, regroupRecover = 0.7 },
	DecisionInterval = 0.5,
	CommandInterval = 0.3, -- how often player squads re-evaluate their order
	PathRecalcInterval = 2,
	FormationChangeCooldown = 8,
	CavalryDisengageDistance = 45,
	CavalryDisengageTime = 5,
	ExposedRadius = 30, -- a squad with no friend this close is "exposed"
	SquareThreatRadius = 50, -- infantry forms square when enemy cavalry is this close
	-- Shared battle plan per side (BattlePlan): one line, advancing together
	Plan = {
		UpdateInterval = 0.5,
		SquadGap = 10, -- PLACEHOLDER: studs between neighbouring squads in the line
		MeleeDepth = 14, -- PLACEHOLDER: melee foot stand this far in front of the line
		ArtilleryDepth = -45, -- PLACEHOLDER: guns this far behind it
		CavalryDepth = -5,
		CavalryFlankGap = 35, -- PLACEHOLDER: cavalry wait this far beyond the line's ends
		LagTolerance = 30, -- PLACEHOLDER: the line waits while a squad is further than this from its slot
		AdvanceSpeedMult = 0.85, -- line pace = slowest line squad × this
		StandoffFraction = 0.9, -- halt at this share of the shortest musket range
		SupportRadius = 80, -- PLACEHOLDER: idle squads this close to an engaged friend help it
		ChargeReach = 60, -- PLACEHOLDER: melee foot leave the line to hit enemies this close
		SlotLeash = 45, -- a firing squad drifting further than this from its slot walks back
	},
}

-- Client-side soldier rendering
GameConfig.Rendering = {
	MaxActiveSoldiers = 200, -- cap on rendered soldiers (both teams); squads show fewer when over it
	MaxRagdolls = 40, -- physics ragdolls simulated at once; extra deaths use the scripted fall
	RagdollDistance = 180, -- only soldiers this close to the camera ragdoll
	RagdollSettleTime = 2.8, -- seconds before a ragdoll is frozen in place
	LodNearDistance = 150, -- full animation + per-soldier ground checks within this distance
	LodMidDistance = 300, -- beyond: animate every 3rd frame
	LodFarDistance = 500, -- beyond: every 8th frame, no limb animation
}

GameConfig.Network = {
	SnapshotInterval = 0.2, -- squad/zone state pushed to clients 5×/second (clients interpolate)
}

GameConfig.Data = {
	StoreName = "NapoleonicCommander_v1",
	AutosaveInterval = 120,
}

-- Built-in placeholder sounds. Replace with real asset ids ("rbxassetid://…") later.
GameConfig.Sounds = {
	Volley = "rbxasset://sounds/Rocket shot.wav",
	CannonFire = "rbxasset://sounds/Rocket shot.wav",
	Swing = "rbxasset://sounds/swordslash.wav",
	Hit = "rbxasset://sounds/swordlunge.wav",
	ChargeImpact = "rbxasset://sounds/collide.wav",
	Music = "", -- PLACEHOLDER: put a drum / battle music asset id here
}

-- XP needed to go from `level` to `level + 1`
function GameConfig.xpForLevel(level: number): number
	return math.floor(100 * level ^ 1.5) -- PLACEHOLDER curve
end

--[[
	Round configuration. Difficulty scales with the round number.
	  side          "Attacker" (capture & hold all zones) or "Defender" (destroy the attackers)
	  waves         enemy squads, each wave arriving `delay` seconds into the battle
	  ai            EnemyAIController tuning for that round
	  boss          optional named general squad (every 5th round)
]]
function GameConfig.getRound(round: number): any
	local side = if round % 2 == 1 then "Attacker" else "Defender"

	-- Army composition: a cheap, numerous backbone of line infantry with a few
	-- specialists on top. Line infantry always outnumber artillery.
	local function compose(total: number, withElite: boolean): { string }
		local art = if round >= 4 then math.max(1, math.min(2, math.floor(total / 6))) else 0
		local cav = if round >= 3 then math.max(1, math.floor(total / 6)) else 0
		local skirm = if round >= 2 then math.max(1, math.floor(total / 5)) else 0
		local elite = if withElite and round >= 7 then math.floor((round - 3) / 4) else 0
		local line = math.max(2, total - art - cav - skirm - elite, math.ceil(total / 2), art + 1)
		local list = {}
		for _ = 1, line do
			table.insert(list, "LineInfantry")
		end
		for _ = 1, skirm do
			table.insert(list, "Skirmishers")
		end
		for _ = 1, cav do
			table.insert(list, "Cavalry")
		end
		for _ = 1, art do
			table.insert(list, "Artillery")
		end
		for _ = 1, elite do
			table.insert(list, "EliteGuard")
		end
		return list
	end

	-- PLACEHOLDER difficulty curve: more squads, then slightly tougher squads
	local enemyTotal = math.min(12, 3 + math.floor(round * 0.8))
	local enemyStat = 1 + math.max(0, round - 3) * 0.04
	local units = {}
	for _, unitId in compose(enemyTotal, true) do
		table.insert(units, {
			unitId = unitId,
			statMultiplier = enemyStat,
			damageMultiplier = enemyStat,
		})
	end

	local boss = nil
	if round % 5 == 0 then
		boss = {
			unitId = "EliteGuard",
			name = "General Wellesley's Guard",
			statMultiplier = 2, -- ×2 HP and morale
			damageMultiplier = 1.5,
		}
	end

	-- From round 3 the enemy arrives in two waves
	local waves = {}
	if round >= 3 then
		local firstCount = math.ceil(#units * 0.6)
		local first, second = {}, {}
		for i, unit in units do
			table.insert(if i <= firstCount then first else second, unit)
		end
		table.insert(waves, { delay = 0, units = first })
		table.insert(waves, { delay = 60, units = second })
	else
		table.insert(waves, { delay = 0, units = units })
	end
	if boss then
		table.insert(waves[#waves].units, boss)
	end

	-- Allied AI squads fighting beside you: a little smaller than the enemy army
	-- (you and your reinforcements make up the difference). No elites for allies.
	local allies = {}
	for _, unitId in compose(math.max(2, math.floor(enemyTotal * 0.8) - 1), false) do
		table.insert(allies, { unitId = unitId })
	end

	return {
		round = round,
		side = side,
		allies = allies,
		winCondition = if side == "Attacker" then "CaptureZones" else "Eliminate",
		waves = waves,
		boss = boss,
		ai = {
			aggression = math.min(0.9, 0.35 + 0.06 * round), -- how far squads look for a fight
			flankPreference = math.min(0.8, 0.15 + 0.07 * round), -- chance to flank a Line
			retreatThreshold = 0.25, -- fall back when morale < 25%
			regroupRecover = 0.7, -- return to the fight at 70% morale
		},
	}
end

return GameConfig
