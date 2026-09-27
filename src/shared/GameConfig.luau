--[[
	GameConfig (ReplicatedStorage.Modules.GameConfig)
	Every tunable number that isn't a unit or formation stat lives here.
	⚠ All values are PLACEHOLDERS meant to be tuned.
]]

local GameConfig = {}

-- Bump on every update: printed in the Output and shown in the HUD so you can check what runs
GameConfig.Version = "0.3"

GameConfig.Teams = {
	Blue = { displayName = "France", color = Color3.fromRGB(45, 95, 215), uniform = Color3.fromRGB(35, 60, 150) },
	Red = { displayName = "Coalition", color = Color3.fromRGB(205, 45, 45), uniform = Color3.fromRGB(175, 35, 35) },
	Neutral = { displayName = "Neutral", color = Color3.fromRGB(200, 200, 200) },
}

GameConfig.Phases = {
	RecruitmentTime = 40, -- seconds to spend points before deployment
	BattleTimeLimit = 420, -- seconds before the battle ends on its own
	RewardTime = 25, -- seconds the summary stays up (or until everyone clicks Continue)
}

GameConfig.Recruitment = {
	StartingPoints = 400,
	MaxSquadsPerPlayer = 8,
	FreeSquadIfEmpty = "LineInfantry", -- given for free if a player recruits nothing
	DeploySpacing = 22, -- studs between squads when deploying
}

GameConfig.Rewards = {
	BasePoints = 150,
	PointsPerZoneHeld = 40,
	PointsPerKill = 2, -- per enemy soldier killed
	FastWinTime = 180, -- win faster than this (seconds) for the bonus
	FastWinBonusPoints = 100,
	XPWin = 150,
	XPLoss = 40,
	XPPerKill = 4,
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
	FollowDistance = 18, -- how far behind the commander following squads stand
	FollowSpacing = 20, -- side-by-side spacing of several following squads
	RushSpeedMult = 1.3,
	RushDamageTakenMult = 1.2, -- rushing breaks formation discipline
	AttackSearchRadius = 350,
	FormationPromptTime = 3, -- after X (Hold), seconds during which 1/2/3 pick a formation
	RushEnemyRadius = 90,
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
}

GameConfig.Zones = {
	TickInterval = 0.5,
	CaptureRate = 8, -- control points/second at weight 1 (full capture = 100, from enemy = 200)
	WeightBonusPerExtra = 0.25, -- each extra point of presence weight speeds capture by 25%
	MaxRateMult = 3,
	HeroPresenceWeight = 1,
	HoldTimeToWin = 20, -- seconds all zones must be held to win an attack round
	IncomeInterval = 10,
	IncomePoints = 15, -- points per Income zone held, every IncomeInterval
	ArtilleryRangeBonus = 0.25, -- +25% artillery range per ArtilleryRange zone held
	MoraleRegenBonus = 0.5, -- +50% morale regen per Morale zone held
}

GameConfig.AI = {
	DecisionInterval = 0.5,
	CommandInterval = 0.3, -- how often player squads re-evaluate their order
	PathRecalcInterval = 2,
	FormationChangeCooldown = 8,
	CavalryDisengageDistance = 45,
	CavalryDisengageTime = 5,
	ExposedRadius = 30, -- a squad with no friend this close is "exposed"
	SquareThreatRadius = 50, -- infantry forms square when enemy cavalry is this close
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

	local units = {}
	local function add(unitId: string, count: number)
		for _ = 1, count do
			table.insert(units, { unitId = unitId })
		end
	end
	-- PLACEHOLDER composition curve
	add("LineInfantry", 2 + math.floor((round - 1) * 0.75))
	add("Skirmishers", if round >= 2 then math.floor(round / 2) else 0)
	add("Cavalry", if round >= 3 then math.floor((round - 1) / 2) else 0)
	add("Artillery", if round >= 4 then math.floor((round - 2) / 2) else 0)

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

	return {
		round = round,
		side = side,
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
