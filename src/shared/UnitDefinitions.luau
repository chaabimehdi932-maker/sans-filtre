--[[
	UnitDefinitions (ReplicatedStorage.Modules.UnitDefinitions)
	Data table for every recruitable unit type. All combat math reads from here.

	⚠ EVERY NUMBER BELOW IS A PLACEHOLDER — tune freely. No other script hardcodes unit balance.

	Field reference:
	  attackType        "Ranged" | "Melee" | "Artillery"
	  health            pooled squad HP (the whole squad shares one health pool)
	  moveSpeed         studs/second in Line formation (formations multiply this)
	  damage            damage of one volley / one cannon shot at full strength
	  attackRange       max firing distance in studs (unused for Melee units)
	  minRange          artillery cannot fire closer than this
	  attackCooldown    seconds between volleys / shots
	  meleeDamage       damage per melee exchange (bayonets, sabres…)
	  meleeRange        edge-to-edge distance (studs) at which the squad fights hand to hand
	  meleeCooldown     seconds between melee hits
	  chargeMultiplier  melee damage multiplier on the first hit after a charge (1 = cannot charge)
	  splashRadius      artillery explosion radius (studs)
	  cost              recruitment points
	  morale            max morale
	  soldiers          number of visual soldier models at full HP. Cheaper, weaker
                    units field MORE men (line/skirmishers) than elite ones (artillery, guard)
	  presenceWeight    how much the squad counts when capturing a zone
	  formations        formations this unit may use (first one = default)
	  formationModifiers optional per-formation multipliers on top of FormationDefinitions
	  canMoveAndFire    true = can shoot while walking
	  spacingMult       multiplies soldier spacing inside formations
	  visual            "Infantry" | "Cavalry" | "Artillery" (placeholder look)
	  hatColor/hatHeight placeholder colours that make unit types recognisable
	  unlockRoundsWon   locked until the player has won this many rounds in total (saved)
	  tier              card rarity colour: 1 grey · 2 blue · 3 purple · 4 gold
	  icon              emoji shown when no portrait is available
	  hidden            not recruitable (bandit-only units)
	  weapon            "Sword" = sword & buckler infantry instead of a musket
	  headgear          "Hood" | "Bandana" instead of the shako (bandits)
]]

local UnitDefinitions = {}

-- Display order in the recruitment shop
UnitDefinitions.Order = { "LineInfantry", "Skirmishers", "Cavalry", "Artillery", "EliteGuard" }

-- Bandit armies are made of these (never offered to the player)
UnitDefinitions.BanditOrder = { "BanditSwordsmen", "BanditGunners" }

UnitDefinitions.Units = {
	LineInfantry = {
		id = "LineInfantry",
		displayName = "Line Infantry",
		icon = "🔫",
		tier = 2,
		description = "Balanced musket volleys, bayonets when enemies get close. Can form square.",
		attackType = "Ranged",
		health = 900, -- PLACEHOLDER
		moveSpeed = 9, -- PLACEHOLDER
		damage = 95, -- PLACEHOLDER
		attackRange = 120, -- PLACEHOLDER (+50 %, v0.13)
		attackCooldown = 5, -- PLACEHOLDER
		meleeDamage = 30, -- PLACEHOLDER
		meleeRange = 4,
		meleeCooldown = 1.5,
		chargeMultiplier = 1,
		cost = 100, -- PLACEHOLDER
		morale = 100, -- PLACEHOLDER
		soldiers = 20,
		presenceWeight = 2,
		formations = { "Line", "Column", "Square" },
		canMoveAndFire = false,
		spacingMult = 1,
		visual = "Infantry",
		hatColor = Color3.fromRGB(25, 25, 25),
		hatHeight = 0.8,
	},

	Skirmishers = {
		id = "Skirmishers",
		displayName = "Skirmishers",
		icon = "🎯",
		tier = 1,
		description = "Fast, loose-order sharpshooters. Fire on the move, weak in a stand-up fight.",
		attackType = "Ranged",
		health = 420, -- PLACEHOLDER
		moveSpeed = 13, -- PLACEHOLDER
		damage = 40, -- PLACEHOLDER
		attackRange = 120, -- PLACEHOLDER (+50 %, v0.13)
		attackCooldown = 2.5, -- PLACEHOLDER
		meleeDamage = 12, -- PLACEHOLDER
		meleeRange = 4,
		meleeCooldown = 1.5,
		chargeMultiplier = 1,
		cost = 60, -- PLACEHOLDER
		morale = 70, -- PLACEHOLDER
		soldiers = 14,
		presenceWeight = 1,
		formations = { "Line", "Column" },
		-- Loose order: enemy volleys hurt them less while spread out in Line
		formationModifiers = { Line = { rangedTakenMult = 0.7 } },
		canMoveAndFire = true,
		spacingMult = 1.4,
		visual = "Infantry",
		hatColor = Color3.fromRGB(40, 95, 50),
		hatHeight = 0.5,
	},

	Cavalry = {
		id = "Cavalry",
		displayName = "Cavalry",
		icon = "🐎",
		tier = 3,
		description = "Very fast. Devastating charges against infantry out of square, weak in a long melee.",
		attackType = "Melee",
		health = 650, -- PLACEHOLDER
		moveSpeed = 22, -- PLACEHOLDER
		damage = 0,
		attackRange = 0,
		attackCooldown = 1.2,
		meleeDamage = 38, -- PLACEHOLDER
		meleeRange = 4,
		meleeCooldown = 1.2, -- PLACEHOLDER
		chargeMultiplier = 3.5, -- PLACEHOLDER
		cost = 180, -- PLACEHOLDER
		morale = 95, -- PLACEHOLDER
		soldiers = 10,
		presenceWeight = 1.5,
		formations = { "Line", "Column" },
		canMoveAndFire = false,
		spacingMult = 1.7,
		visual = "Cavalry",
		hatColor = Color3.fromRGB(205, 165, 60),
		hatHeight = 0.6,
	},

	Artillery = {
		id = "Artillery",
		displayName = "Artillery",
		icon = "💣",
		tier = 3,
		description = "Huge area damage at long range. Slow, must stop to fire, helpless in melee.",
		attackType = "Artillery",
		health = 300, -- PLACEHOLDER
		moveSpeed = 5, -- PLACEHOLDER
		damage = 170, -- PLACEHOLDER
		attackRange = 270, -- PLACEHOLDER
		minRange = 30,
		attackCooldown = 9, -- PLACEHOLDER
		splashRadius = 16, -- PLACEHOLDER
		meleeDamage = 6, -- PLACEHOLDER
		meleeRange = 4,
		meleeCooldown = 2,
		chargeMultiplier = 1,
		cost = 200, -- PLACEHOLDER
		morale = 60, -- PLACEHOLDER
		soldiers = 4,
		presenceWeight = 0.5,
		formations = { "Line" },
		canMoveAndFire = false,
		spacingMult = 1.6,
		visual = "Artillery",
		hatColor = Color3.fromRGB(45, 45, 70),
		hatHeight = 0.6,
	},

	EliteGuard = {
		id = "EliteGuard",
		displayName = "Elite Guard",
		icon = "🎖️",
		tier = 4,
		description = "Veteran grenadiers: tough, deadly volleys, iron morale. Unlocked by winning rounds.",
		attackType = "Ranged",
		health = 1100, -- PLACEHOLDER
		moveSpeed = 10, -- PLACEHOLDER
		damage = 100, -- PLACEHOLDER
		attackRange = 128, -- PLACEHOLDER (+50 %, v0.13)
		attackCooldown = 4, -- PLACEHOLDER
		meleeDamage = 55, -- PLACEHOLDER
		meleeRange = 4,
		meleeCooldown = 1.2,
		chargeMultiplier = 1.5, -- PLACEHOLDER
		cost = 260, -- PLACEHOLDER
		morale = 170, -- PLACEHOLDER
		soldiers = 12,
		presenceWeight = 3,
		formations = { "Line", "Column", "Square" },
		canMoveAndFire = false,
		spacingMult = 1,
		visual = "Infantry",
		hatColor = Color3.fromRGB(15, 15, 15),
		hatHeight = 1.4,
		unlockRoundsWon = 3, -- PLACEHOLDER
	},

	-- Branches (squads evolve into these: CampaignConfig.Branches) -------------------
	Grenadiers = {
		id = "Grenadiers",
		displayName = "Grenadiers",
		icon = "💂",
		tier = 3,
		branchOnly = true,
		description = "Picked men in bearskins: heavier, slower, deadly with the bayonet, hard to break.",
		attackType = "Ranged",
		health = 1100, -- PLACEHOLDER
		moveSpeed = 8, -- PLACEHOLDER
		damage = 100, -- PLACEHOLDER
		attackRange = 120, -- PLACEHOLDER (+50 %, v0.13)
		attackCooldown = 5,
		meleeDamage = 44, -- PLACEHOLDER
		meleeRange = 4,
		meleeCooldown = 1.4,
		chargeMultiplier = 1.3,
		cost = 160,
		morale = 145, -- PLACEHOLDER
		soldiers = 18,
		presenceWeight = 2.5,
		formations = { "Line", "Column", "Square" },
		canMoveAndFire = false,
		spacingMult = 1,
		visual = "Infantry",
		hatColor = Color3.fromRGB(20, 20, 20),
		hatHeight = 1.5,
	},
	LightInfantry = {
		id = "LightInfantry",
		displayName = "Light Infantry",
		icon = "🏹",
		tier = 3,
		branchOnly = true,
		description = "Line troops trained to skirmish: faster, fire on the move, harder to hit in loose order.",
		attackType = "Ranged",
		health = 820, -- PLACEHOLDER
		moveSpeed = 12, -- PLACEHOLDER
		damage = 82, -- PLACEHOLDER
		attackRange = 132, -- PLACEHOLDER (+50 %, v0.13)
		attackCooldown = 4,
		meleeDamage = 26,
		meleeRange = 4,
		meleeCooldown = 1.5,
		chargeMultiplier = 1,
		cost = 150,
		morale = 105,
		soldiers = 20,
		presenceWeight = 2,
		formations = { "Line", "Column" },
		formationModifiers = { Line = { rangedTakenMult = 0.8 } },
		canMoveAndFire = true,
		spacingMult = 1.3,
		visual = "Infantry",
		hatColor = Color3.fromRGB(35, 70, 45),
		hatHeight = 0.7,
	},
	Riflemen = {
		id = "Riflemen",
		displayName = "Riflemen",
		icon = "🎯",
		tier = 3,
		branchOnly = true,
		description = "Rifled muskets: they pick off men at long range but reload slowly.",
		attackType = "Ranged",
		health = 420, -- PLACEHOLDER
		moveSpeed = 12,
		damage = 62, -- PLACEHOLDER
		attackRange = 188, -- PLACEHOLDER (+50 %, v0.13)
		attackCooldown = 4.5,
		meleeDamage = 12,
		meleeRange = 4,
		meleeCooldown = 1.5,
		chargeMultiplier = 1,
		cost = 110,
		morale = 80,
		soldiers = 14,
		presenceWeight = 1,
		formations = { "Line", "Column" },
		formationModifiers = { Line = { rangedTakenMult = 0.7 } },
		canMoveAndFire = false,
		spacingMult = 1.5,
		visual = "Infantry",
		hatColor = Color3.fromRGB(25, 60, 35),
		hatHeight = 0.6,
	},
	Voltigeurs = {
		id = "Voltigeurs",
		displayName = "Voltigeurs",
		icon = "⚡",
		tier = 3,
		branchOnly = true,
		description = "Very fast skirmishers: rapid fire on the move, run rings around lines.",
		attackType = "Ranged",
		health = 460, -- PLACEHOLDER
		moveSpeed = 16, -- PLACEHOLDER
		damage = 42,
		attackRange = 120, -- PLACEHOLDER (+50 %, v0.13)
		attackCooldown = 2.1, -- PLACEHOLDER
		meleeDamage = 18,
		meleeRange = 4,
		meleeCooldown = 1.3,
		chargeMultiplier = 1,
		cost = 100,
		morale = 85,
		soldiers = 14,
		presenceWeight = 1,
		formations = { "Line", "Column" },
		formationModifiers = { Line = { rangedTakenMult = 0.65 } },
		canMoveAndFire = true,
		spacingMult = 1.5,
		visual = "Infantry",
		hatColor = Color3.fromRGB(200, 170, 40),
		hatHeight = 0.6,
	},
	Cuirassiers = {
		id = "Cuirassiers",
		displayName = "Cuirassiers",
		icon = "🛡",
		tier = 4,
		branchOnly = true,
		description = "Armoured heavy cavalry: crushing charges, they can stay in a melee.",
		attackType = "Melee",
		health = 950, -- PLACEHOLDER
		moveSpeed = 19, -- PLACEHOLDER
		damage = 0,
		attackRange = 0,
		attackCooldown = 1.2,
		meleeDamage = 46, -- PLACEHOLDER
		meleeRange = 4,
		meleeCooldown = 1.2,
		chargeMultiplier = 4, -- PLACEHOLDER
		cost = 240,
		morale = 125,
		soldiers = 10,
		presenceWeight = 1.5,
		formations = { "Line", "Column" },
		canMoveAndFire = false,
		spacingMult = 1.7,
		visual = "Cavalry",
		hatColor = Color3.fromRGB(200, 200, 210),
		hatHeight = 0.7,
	},
	Hussars = {
		id = "Hussars",
		displayName = "Hussars",
		icon = "🐎",
		tier = 3,
		branchOnly = true,
		description = "Light cavalry: the fastest troops on the field, hit and run.",
		attackType = "Melee",
		health = 600, -- PLACEHOLDER
		moveSpeed = 26, -- PLACEHOLDER
		damage = 0,
		attackRange = 0,
		attackCooldown = 1.1,
		meleeDamage = 34,
		meleeRange = 4,
		meleeCooldown = 1.1,
		chargeMultiplier = 3.2,
		cost = 200,
		morale = 100,
		soldiers = 12,
		presenceWeight = 1.5,
		formations = { "Line", "Column" },
		canMoveAndFire = false,
		spacingMult = 1.6,
		visual = "Cavalry",
		hatColor = Color3.fromRGB(150, 30, 30),
		hatHeight = 0.9,
	},

	-- Bandits ---------------------------------------------------------------------
	BanditSwordsmen = {
		id = "BanditSwordsmen",
		displayName = "Bandit Swordsmen",
		icon = "🗡",
		tier = 1,
		hidden = true,
		description = "Cutthroats with sabres and bucklers. They rush in and brawl, no discipline, no volleys.",
		attackType = "Melee",
		weapon = "Sword",
		headgear = "Hood",
		health = 480, -- PLACEHOLDER
		moveSpeed = 12, -- PLACEHOLDER
		damage = 0,
		attackRange = 0,
		attackCooldown = 1.1,
		meleeDamage = 24, -- PLACEHOLDER
		meleeRange = 4,
		meleeCooldown = 1.1, -- PLACEHOLDER
		chargeMultiplier = 1.8, -- PLACEHOLDER: their wild rush hits hard
		cost = 70,
		morale = 60, -- PLACEHOLDER: they break quickly
		soldiers = 16,
		presenceWeight = 1,
		formations = { "Line", "Column" },
		canMoveAndFire = false,
		spacingMult = 1.3,
		visual = "Infantry",
		hatColor = Color3.fromRGB(70, 55, 40),
		hatHeight = 0.5,
	},

	BanditGunners = {
		id = "BanditGunners",
		displayName = "Bandit Gunners",
		icon = "🔫",
		tier = 1,
		hidden = true,
		description = "Deserters with stolen muskets. Ragged volleys from behind the swordsmen.",
		attackType = "Ranged",
		headgear = "Bandana",
		health = 320, -- PLACEHOLDER
		moveSpeed = 11, -- PLACEHOLDER
		damage = 38, -- PLACEHOLDER
		attackRange = 105, -- PLACEHOLDER (+50 %, v0.13)
		attackCooldown = 3.5, -- PLACEHOLDER
		meleeDamage = 10, -- PLACEHOLDER
		meleeRange = 4,
		meleeCooldown = 1.5,
		chargeMultiplier = 1,
		cost = 60,
		morale = 55, -- PLACEHOLDER
		soldiers = 12,
		presenceWeight = 1,
		formations = { "Line", "Column" },
		formationModifiers = { Line = { rangedTakenMult = 0.85 } },
		canMoveAndFire = false,
		spacingMult = 1.4,
		visual = "Infantry",
		hatColor = Color3.fromRGB(150, 40, 35),
		hatHeight = 0.5,
	},
}

function UnitDefinitions.get(unitId: string): any
	return UnitDefinitions.Units[unitId]
end

return UnitDefinitions
