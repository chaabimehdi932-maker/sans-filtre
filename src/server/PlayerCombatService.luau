--[[
	PlayerCombatService
	The commander's personal combat, validated server-side. Clients only send intent
	(CombatAction remote); cooldowns, hits, damage and i-frames are decided here.

	Actions: Attack | BlockStart | BlockEnd | Roll | Heal | Mount
	The horse is a placeholder model welded under the character (HipHeight is raised).
	The roll's dash movement is done by the client (it owns its character's physics);
	the server only grants the invulnerability window.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local GameConfig = require(Modules:WaitForChild("GameConfig"))
local MathUtil = require(Modules:WaitForChild("MathUtil"))
local Remotes = require(Modules:WaitForChild("Remotes"))

local SquadService = require(script.Parent:WaitForChild("SquadService"))

local Hero = GameConfig.Hero

local combatRemote = Remotes.get("CombatAction")
local feedbackRemote = Remotes.get("CombatFeedback")
local vfxRemote = Remotes.get("VFX")

local PlayerCombatService = {}

PlayerCombatService.hooks = {
	getSpawnCFrame = function(_player: Player): CFrame
		return CFrame.new(0, 10, 0)
	end,
	getLevel = function(_player: Player): number
		return 1
	end,
	onDamageDealt = function(_player: Player, _amount: number) end,
}

local states: { [Player]: any } = {}

local function getParts(player: Player): (Model?, Humanoid?, BasePart?)
	local character = player.Character
	if not character then
		return nil, nil, nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or not root:IsA("BasePart") or humanoid.Health <= 0 then
		return nil, nil, nil
	end
	return character, humanoid, root
end

local function feedback(player: Player, action: string, ok: boolean, remaining: number?)
	feedbackRemote:FireClient(player, action, ok, remaining)
end

local function refreshSpeed(player: Player)
	local state = states[player]
	local _, humanoid = getParts(player)
	if not state or not humanoid then
		return
	end
	local speed = if state.mounted then Hero.MountedSpeed else Hero.WalkSpeed
	if state.blocking then
		speed *= Hero.BlockSpeedMult
	end
	humanoid.WalkSpeed = speed
	humanoid.UseJumpPower = true
	humanoid.JumpPower = if state.mounted then 0 else Hero.JumpPower
end

local function maxHealthFor(player: Player): number
	return Hero.MaxHealth + (PlayerCombatService.hooks.getLevel(player) - 1) * Hero.HealthPerLevel
end

function PlayerCombatService.refreshMaxHealth(player: Player)
	local _, humanoid = getParts(player)
	if humanoid then
		local newMax = maxHealthFor(player)
		local ratio = humanoid.Health / humanoid.MaxHealth
		humanoid.MaxHealth = newMax
		humanoid.Health = newMax * ratio
	end
end

---------------------------------------------------------------------------
-- Equipment: sabre, shield, horse (placeholders)
---------------------------------------------------------------------------

local function gearPart(name: string, size: Vector3, color: Color3, material: Enum.Material?): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.Massless = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	return part
end

local function weld(part0: BasePart, part1: BasePart, c0: CFrame, name: string): Weld
	local w = Instance.new("Weld")
	w.Name = name
	w.Part0 = part0
	w.Part1 = part1
	w.C0 = c0
	w.Parent = part1
	return w
end

local function attachGear(player: Player, character: Model)
	local state = states[player]
	local hand = character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
	local torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
	if hand and hand:IsA("BasePart") then
		local sabre =
			gearPart("Sabre", Vector3.new(0.12, 0.25, 3.4), Color3.fromRGB(205, 205, 215), Enum.Material.Metal)
		weld(hand, sabre, CFrame.new(0, -hand.Size.Y / 2, -1.6), "SabreWeld")
		sabre.Parent = character
	end
	if torso and torso:IsA("BasePart") then
		local shield =
			gearPart("Shield", Vector3.new(2.2, 2.6, 0.25), GameConfig.Teams.Blue.uniform, Enum.Material.Wood)
		local carry = CFrame.new(0, 0, torso.Size.Z / 2 + 0.2) -- on the back
		local raised = CFrame.new(-0.4, 0.2, -(torso.Size.Z / 2 + 0.9)) -- in front of the chest
		state.shieldWeld = weld(torso, shield, carry, "ShieldWeld")
		state.shieldCarry = carry
		state.shieldRaised = raised
		shield.Parent = character
	end
end

-- Placeholder horse welded under the character. Joint welds are named (BodyWeld, NeckWeld,
-- LegFL/LegFR/LegBL/LegBR, TailWeld) so every client can animate the gait (CharacterAnimator).
local HORSE_COATS = {
	{ Color3.fromRGB(110, 70, 40), Color3.fromRGB(40, 28, 20) }, -- bay
	{ Color3.fromRGB(35, 30, 30), Color3.fromRGB(15, 15, 15) }, -- black
	{ Color3.fromRGB(200, 195, 185), Color3.fromRGB(120, 115, 110) }, -- grey
	{ Color3.fromRGB(150, 85, 45), Color3.fromRGB(230, 210, 170) }, -- chestnut, flaxen mane
}

local function mount(player: Player)
	local state = states[player]
	local character, humanoid, root = getParts(player)
	if not state or state.mounted or not character or not humanoid or not root then
		return
	end
	local groundDistance = if humanoid.RigType == Enum.HumanoidRigType.R15
		then humanoid.HipHeight + root.Size.Y / 2
		else 3
	local groundY = -(groundDistance + Hero.MountLift) -- ground height relative to the root once lifted
	local coat = HORSE_COATS[(player.UserId % #HORSE_COATS) + 1]
	local brown, dark = coat[1], coat[2]
	local cloth = GameConfig.Teams.Blue.uniform
	local leather = Color3.fromRGB(60, 40, 25)

	local horse = Instance.new("Model")
	horse.Name = "Horse"
	-- part welded to `parent` at `c0` (joint position); `c1` offsets the part from its joint
	local function part(
		name: string,
		size: Vector3,
		parent: BasePart,
		c0: CFrame,
		c1: CFrame?,
		color: Color3?,
		weldName: string?
	): Part
		local p = gearPart(name, size, color or brown)
		local w = weld(parent, p, c0, weldName or (name .. "Weld"))
		if c1 then
			w.C1 = c1
		end
		p.Parent = horse
		return p
	end

	local body = part("Body", Vector3.new(1.7, 1.6, 4.2), root, CFrame.new(0, -1.9, 0.1), nil, brown, "BodyWeld")
	part("Chest", Vector3.new(1.6, 1.5, 1.2), body, CFrame.new(0, 0.1, -1.9))
	part("Rump", Vector3.new(1.75, 1.55, 1.3), body, CFrame.new(0, 0.12, 1.75))
	local bodyBottom = -2.7 + 0.1
	local legLength = math.max(0.6, bodyBottom - groundY)
	for _, leg in
		{
			{ "FL", -0.55, -1.7 },
			{ "FR", 0.55, -1.7 },
			{ "BL", -0.55, 1.7 },
			{ "BR", 0.55, 1.7 },
		}
	do
		-- pivot at the top of the leg so rotating the weld swings it like a hip/shoulder
		local l = part(
			"Leg" .. leg[1],
			Vector3.new(0.42, legLength, 0.45),
			body,
			CFrame.new(leg[2], -0.6, leg[3]),
			CFrame.new(0, legLength / 2 - 0.2, 0),
			brown,
			"Leg" .. leg[1]
		)
		part("Hoof", Vector3.new(0.46, 0.25, 0.5), l, CFrame.new(0, -legLength / 2 + 0.12, -0.02), nil, dark)
	end
	local neck = part(
		"Neck",
		Vector3.new(0.75, 1.9, 0.9),
		body,
		CFrame.new(0, 0.55, -2.2) * CFrame.Angles(math.rad(-35), 0, 0),
		CFrame.new(0, -0.8, 0),
		brown,
		"NeckWeld"
	)
	local head = part(
		"Head",
		Vector3.new(0.65, 0.75, 1.5),
		neck,
		-- neck leans forward-up 35°, the head points forward-down
		CFrame.new(0, 0.95, -0.2)
			* CFrame.Angles(math.rad(5), 0, 0)
			* CFrame.new(0, 0, -0.5)
	)
	part("Muzzle", Vector3.new(0.55, 0.55, 0.5), head, CFrame.new(0, -0.1, -0.85), nil, dark)
	part("EarL", Vector3.new(0.14, 0.35, 0.14), head, CFrame.new(-0.2, 0.5, 0.45))
	part("EarR", Vector3.new(0.14, 0.35, 0.14), head, CFrame.new(0.2, 0.5, 0.45))
	part("Mane", Vector3.new(0.2, 1.8, 0.35), neck, CFrame.new(0, 0.05, 0.5), nil, dark)
	part(
		"Tail",
		Vector3.new(0.3, 1.6, 0.3),
		body,
		CFrame.new(0, 0.5, 2.4) * CFrame.Angles(math.rad(-25), 0, 0),
		CFrame.new(0, 0.75, 0),
		dark,
		"TailWeld"
	)
	part("Saddle", Vector3.new(1.8, 0.3, 1.5), body, CFrame.new(0, 0.85, -0.1), nil, leather)
	part("Blanket", Vector3.new(1.9, 1.0, 1.9), body, CFrame.new(0, 0.45, -0.05), nil, cloth)
	horse.Parent = character

	state.baseHipHeight = humanoid.HipHeight
	humanoid.HipHeight += Hero.MountLift
	state.horse = horse
	state.mounted = true
	character:SetAttribute("Mounted", true)
	refreshSpeed(player)
end

local function dismount(player: Player)
	local state = states[player]
	if not state or not state.mounted then
		return
	end
	local character, humanoid = getParts(player)
	if state.horse then
		state.horse:Destroy()
		state.horse = nil
	end
	if humanoid and state.baseHipHeight then
		humanoid.HipHeight = state.baseHipHeight
	end
	state.mounted = false
	if character then
		character:SetAttribute("Mounted", false)
	end
	refreshSpeed(player)
end

local function setBlocking(player: Player, blocking: boolean)
	local state = states[player]
	if not state or state.blocking == blocking then
		return
	end
	state.blocking = blocking
	local character = player.Character
	if character then
		character:SetAttribute("Blocking", blocking) -- clients raise the shield arm
	end
	if state.shieldWeld then
		state.shieldWeld.C0 = if blocking then state.shieldRaised else state.shieldCarry
	end
	refreshSpeed(player)
end

---------------------------------------------------------------------------
-- Actions
---------------------------------------------------------------------------

local function onAttack(player: Player)
	local state = states[player]
	local character, _, root = getParts(player)
	if not character or not root or state.blocking then
		feedback(player, "Attack", false)
		return
	end
	local now = time()
	local cooldown = if state.mounted then Hero.MountedAttackCooldown else Hero.AttackCooldown
	if now - state.lastAttack < cooldown - 0.1 then
		feedback(player, "Attack", false, cooldown - (now - state.lastAttack))
		return
	end
	state.lastAttack = now

	local range = if state.mounted then Hero.MountedAttackRange else Hero.AttackRange
	local look = MathUtil.flat(root.CFrame.LookVector)
	look = if look.Magnitude > 0.01 then look.Unit else Vector3.new(0, 0, -1)
	local damage = Hero.AttackDamage * (1 + (PlayerCombatService.hooks.getLevel(player) - 1) * Hero.DamagePerLevelMult)
	local kind = "Hero"
	if state.mounted then
		-- Mounted charge: damage scales with gallop speed
		local speed = MathUtil.flat(root.AssemblyLinearVelocity).Magnitude
		local factor = math.clamp(speed / Hero.MountedSpeed, 0, 1)
		damage *= 1 + (Hero.MountedChargeMultiplier - 1) * factor
		if factor >= 0.7 then
			kind = "Charge"
		end
	end

	local coneCos = math.cos(math.rad(Hero.AttackConeDegrees / 2))
	local best, bestEdge = nil, math.huge
	for _, squad in SquadService.getByTeam("Red") do
		local offset = MathUtil.flat(squad.position - root.Position)
		local distance = offset.Magnitude
		local edge = distance - squad.radius
		if edge <= range and edge < bestEdge then
			-- inside the squad = always a hit; otherwise it must be in front of us
			if distance <= squad.radius or look:Dot(offset.Unit) >= coneCos then
				best, bestEdge = squad, edge
			end
		end
	end

	vfxRemote:FireAllClients({ kind = "Swing", character = character })
	if best then
		local dealt = SquadService.applyDamage(best, damage, {
			kind = kind,
			fromPosition = root.Position,
			attackerTeam = "Blue",
			creditPlayer = player,
		})
		PlayerCombatService.hooks.onDamageDealt(player, dealt)
		vfxRemote:FireAllClients({ kind = "Hit", position = root.Position + look * 3 + Vector3.new(0, 1, 0) })
	end
	feedback(player, "Attack", true)
end

local function onRoll(player: Player)
	local state = states[player]
	local character = getParts(player)
	local now = time()
	if not character or state.mounted then
		feedback(player, "Roll", false)
		return
	end
	if now - state.lastRoll < Hero.RollCooldown - 0.1 then
		feedback(player, "Roll", false, Hero.RollCooldown - (now - state.lastRoll))
		return
	end
	state.lastRoll = now
	state.iFrameUntil = now + Hero.RollIFrames
	vfxRemote:FireAllClients({ kind = "Roll", character = character })
	feedback(player, "Roll", true)
end

local function onHeal(player: Player)
	local state = states[player]
	local character, humanoid, root = getParts(player)
	local now = time()
	if not character or not humanoid or not root then
		feedback(player, "Heal", false)
		return
	end
	if now - state.lastHeal < Hero.HealCooldown - 0.1 then
		feedback(player, "Heal", false, Hero.HealCooldown - (now - state.lastHeal))
		return
	end
	state.lastHeal = now
	humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + humanoid.MaxHealth * Hero.HealFraction)
	-- Rallying cry: nearby squads regain morale
	for _, squad in SquadService.getOwnedBy(player) do
		if MathUtil.flatDistance(squad.position, root.Position) <= Hero.HealMoraleRadius then
			SquadService.addMorale(squad, Hero.HealMoraleBoost)
		end
	end
	vfxRemote:FireAllClients({ kind = "Heal", position = root.Position })
	feedback(player, "Heal", true)
end

local function onMount(player: Player)
	local state = states[player]
	local now = time()
	if not getParts(player) then
		feedback(player, "Mount", false)
		return
	end
	if now - state.lastMount < Hero.MountCooldown - 0.1 then
		feedback(player, "Mount", false, Hero.MountCooldown - (now - state.lastMount))
		return
	end
	state.lastMount = now
	if state.mounted then
		dismount(player)
	else
		mount(player)
	end
	feedback(player, "Mount", true)
end

local handlers = {
	Attack = onAttack,
	Roll = onRoll,
	Heal = onHeal,
	Mount = onMount,
	BlockStart = function(player: Player)
		if getParts(player) then
			setBlocking(player, true)
		end
	end,
	BlockEnd = function(player: Player)
		setBlocking(player, false)
	end,
}

combatRemote.OnServerEvent:Connect(function(player: Player, action: unknown)
	if typeof(action) ~= "string" or not states[player] then
		return
	end
	local handler = handlers[action]
	if handler then
		handler(player)
	end
end)

---------------------------------------------------------------------------
-- Damage taken, heroes list, lifecycle
---------------------------------------------------------------------------

function PlayerCombatService.damageHero(player: Player, amount: number, fromPosition: Vector3?, kind: string)
	local state = states[player]
	local character, humanoid, root = getParts(player)
	if not state or not character or not humanoid or not root then
		return
	end
	if time() < state.iFrameUntil then
		return -- rolling
	end
	if state.blocking and fromPosition then
		local toAttacker = MathUtil.flat(fromPosition - root.Position)
		local look = MathUtil.flat(root.CFrame.LookVector)
		if toAttacker.Magnitude > 0.01 and look.Magnitude > 0.01 and look.Unit:Dot(toAttacker.Unit) > 0.2 then
			local reduction = if kind == "Artillery" then Hero.BlockReduction * 0.5 else Hero.BlockReduction
			amount *= 1 - reduction
		end
	end
	if state.mounted then
		amount *= Hero.MountedDamageTakenMult
	end
	humanoid:TakeDamage(amount)
	if amount >= 0.5 then
		vfxRemote:FireAllClients({
			kind = "DamageNumber",
			position = root.Position + Vector3.new(math.random() * 2 - 1, 4, math.random() * 2 - 1),
			amount = math.floor(amount + 0.5),
			victimTeam = "Blue",
			hero = true,
		})
	end
end

-- Living commanders, used by squads (targets, morale) and zones (presence)
function PlayerCombatService.getHeroes(): { any }
	local heroes = {}
	for player in states do
		local _, _, root = getParts(player)
		if root then
			table.insert(heroes, { player = player, position = root.Position })
		end
	end
	return heroes
end

function PlayerCombatService.teleportAll(cframe: CFrame)
	local index = 0
	for player in states do
		local character = getParts(player)
		if character then
			character:PivotTo(cframe * CFrame.new(index * 6, 0, 0))
			index += 1
		end
	end
end

local function onCharacterAdded(player: Player, character: Model)
	local state = states[player]
	if not state then
		return
	end
	state.mounted = false
	state.blocking = false
	state.horse = nil
	state.shieldWeld = nil
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid or not humanoid:IsA("Humanoid") then
		return
	end
	character:SetAttribute("Mounted", false)
	local maxHealth = maxHealthFor(player)
	humanoid.MaxHealth = maxHealth
	humanoid.Health = maxHealth
	humanoid.Died:Connect(function()
		if states[player] then
			states[player].blocking = false
		end
	end)

	task.spawn(function()
		-- Wait for the avatar to finish loading (it changes HipHeight) before gearing up
		if not player:HasAppearanceLoaded() then
			local loaded = false
			local connection = player.CharacterAppearanceLoaded:Connect(function()
				loaded = true
			end)
			local deadline = time() + 5
			while not loaded and time() < deadline do
				task.wait(0.1)
			end
			connection:Disconnect()
		end
		if player.Character ~= character or not character.Parent then
			return
		end
		character:PivotTo(PlayerCombatService.hooks.getSpawnCFrame(player))
		attachGear(player, character)
		refreshSpeed(player)
		if Hero.AutoMountOnSpawn then
			mount(player)
		end
	end)
end

function PlayerCombatService.initPlayer(player: Player)
	states[player] = {
		mounted = false,
		blocking = false,
		lastAttack = -math.huge,
		lastRoll = -math.huge,
		lastHeal = -math.huge,
		lastMount = -math.huge,
		iFrameUntil = 0,
	}
	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
	if player.Character then
		task.spawn(onCharacterAdded, player, player.Character)
	end
end

function PlayerCombatService.removePlayer(player: Player)
	states[player] = nil
end

pcall(function()
	Players.RespawnTime = Hero.RespawnTime
end)

return PlayerCombatService
