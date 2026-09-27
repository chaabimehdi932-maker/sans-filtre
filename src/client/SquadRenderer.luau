--[[
	SquadRenderer
	Draws and animates every squad on this client from the server snapshots.
	The server only simulates logical squads (position, facing, formation, soldier count);
	here each soldier is a full-size R6 rig (SoldierModels) animated procedurally by writing
	its Motor6D joints' Transform:
	  march · aim · volley recoil · reload · bayonet thrust · rout run · death falls
	  cavalry gallop + sabre (point when charging, slashes in melee) · cannon recoil
	Only the anchored root of each rig is moved (BulkMoveTo); far squads update less often.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local FormationDefinitions = require(Modules:WaitForChild("FormationDefinitions"))
local GameConfig = require(Modules:WaitForChild("GameConfig"))
local MathUtil = require(Modules:WaitForChild("MathUtil"))
local UnitDefinitions = require(Modules:WaitForChild("UnitDefinitions"))

local SoldierModels = require(script.Parent:WaitForChild("SoldierModels"))

local player = Players.LocalPlayer

local SquadRenderer = {}

local renders: { [number]: any } = {}
local dying: { any } = {}
local frame = 0

local folder = Instance.new("Folder")
folder.Name = "SquadVisuals"
folder.Parent = Workspace

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude
groundParams.RespectCanCollide = true
local lastFilter = 0

local function refreshGroundFilter(now: number)
	if now - lastFilter < 1 then
		return
	end
	lastFilter = now
	local list: { Instance } = { folder }
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(list, p.Character)
		end
	end
	local map = Workspace:FindFirstChild("Map")
	local scenery = map and map:FindFirstChild("Scenery")
	if scenery then
		table.insert(list, scenery)
	end
	groundParams.FilterDescendantsInstances = list
end

local TORSO = SoldierModels.TORSO_HEIGHT
local HORSE = SoldierModels.HORSE_HEIGHT

-- Musket poses, relative to the torso centre (the musket lies along +Y from its butt)
local GUN_SHOULDER = CFrame.new(1.5, -1.5, -0.6) * CFrame.Angles(math.rad(-4), 0, 0)
local GUN_AIM = CFrame.new(0.8, 0.85, 0.2) * CFrame.Angles(math.rad(-90), 0, 0)
local GUN_RELOAD = CFrame.new(0.4, -2.3, -1.1) * CFrame.Angles(math.rad(-10), 0, 0)
local GUN_BAYONET = CFrame.new(0.6, -0.4, 0.5) * CFrame.Angles(math.rad(-95), 0, 0)
local GUN_PORT = CFrame.new(0.3, -0.6, -0.8) * CFrame.Angles(math.rad(-45), 0, math.rad(40))
local GUN_DROPPED = CFrame.new(1.8, -2.8, -1.2) * CFrame.Angles(math.rad(-90), 0, math.rad(80))
local MUZZLE = CFrame.new(0, 4.4, 0)

-- Arm poses: Vector2(forward swing, sideways spread)
local ARMS_SHOULDER = { Vector2.new(0, 0), Vector2.new(0.3, 0) }
local ARMS_AIM = { Vector2.new(1.5, 0.9), Vector2.new(1.45, -0.35) }
local ARMS_RELOAD = { Vector2.new(0.6, 0.4), Vector2.new(1.0, -0.3) }
local ARMS_BAYONET = { Vector2.new(1.2, 0.5), Vector2.new(0.7, -0.2) }
local ARMS_PORT = { Vector2.new(0.9, 0.4), Vector2.new(0.9, -0.3) }
local ARMS_DEAD = { Vector2.new(2.8, 0.4), Vector2.new(2.8, -0.4) }

local CANNON_OFFSET = CFrame.new(0, SoldierModels.CANNON_AXLE_HEIGHT, -4)
local DISC_ROTATION = CFrame.Angles(0, 0, math.rad(90))

local bulkParts: { BasePart } = {}
local bulkCFrames: { CFrame } = {}

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function angles(v: Vector2): CFrame
	return CFrame.Angles(v.X, 0, v.Y)
end

---------------------------------------------------------------------------
-- Building
---------------------------------------------------------------------------

local function newSoldier(r: any): any
	local rig = if r.def.visual == "Cavalry"
		then SoldierModels.cavalry(r.model, r.team, r.def)
		else SoldierModels.infantry(r.model, r.team, r.def, r.def.visual ~= "Artillery")
	local soldier = {
		rig = rig,
		kind = rig.kind,
		pos = r.pos,
		yaw = r.yaw,
		groundY = nil,
		nextGround = 0,
		phase = math.random() * math.pi * 2,
		legSwing = 0,
		armL = Vector2.zero,
		armR = Vector2.zero,
		gun = GUN_SHOULDER,
		look = 0,
		jitter = Vector3.new(math.random() * 4 - 2, 0, math.random() * 4 - 2),
		yawJitter = math.random() * 0.8 - 0.4,
		delay = math.random() * 0.15, -- volleys ripple down the line
	}
	if rig.kind == "Cavalry" then
		-- rider's legs straddle the horse (set once)
		rig.motors.legL.Transform = CFrame.Angles(0.55, 0, -0.6)
		rig.motors.legR.Transform = CFrame.Angles(0.55, 0, 0.6)
		rig.motors.armL.Transform = CFrame.Angles(0.8, 0, 0.3) -- reins
	end
	return soldier
end

local function recomputeSlots(r: any)
	local slots = FormationDefinitions.layout(r.formation, #r.soldiers, r.def.spacingMult)
	if r.def.visual == "Artillery" then
		for i, slot in slots do
			slots[i] = slot + Vector3.new(0, 0, 1.5) -- crew stands behind the gun
		end
	end
	r.slots = slots
end

local function buildBillboard(r: any)
	local teamColor = GameConfig.Teams[r.team].color
	local gui = Instance.new("BillboardGui")
	gui.Name = "Info"
	gui.Size = UDim2.fromOffset(120, 38)
	gui.StudsOffsetWorldSpace = Vector3.new(0, if r.def.visual == "Cavalry" then 11 else 8, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 260
	gui.LightInfluence = 0
	gui.Adornee = r.disc

	local name = Instance.new("TextLabel")
	name.BackgroundTransparency = 1
	name.Size = UDim2.new(1, 0, 0, 16)
	name.Font = Enum.Font.FredokaOne
	name.TextSize = 15
	name.TextColor3 = teamColor:Lerp(Color3.new(1, 1, 1), 0.55)
	name.TextStrokeTransparency = 0.2
	name.Parent = gui
	local back = Instance.new("Frame")
	back.Position = UDim2.fromOffset(20, 18)
	back.Size = UDim2.new(1, -40, 0, 7)
	back.BackgroundColor3 = Color3.fromRGB(15, 15, 18)
	back.BorderSizePixel = 0
	back.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = back
	local hp = Instance.new("Frame")
	hp.Size = UDim2.fromScale(1, 1)
	hp.BackgroundColor3 = if r.team == "Blue" then Color3.fromRGB(90, 160, 255) else Color3.fromRGB(235, 60, 60)
	hp.BorderSizePixel = 0
	hp.Parent = back
	corner:Clone().Parent = hp
	local status = Instance.new("TextLabel")
	status.BackgroundTransparency = 1
	status.Position = UDim2.fromOffset(0, 25)
	status.Size = UDim2.new(1, 0, 0, 13)
	status.Font = Enum.Font.FredokaOne
	status.TextSize = 12
	status.TextStrokeTransparency = 0.3
	status.Parent = gui
	gui.Parent = r.disc
	r.ui = { name = name, hp = hp, status = status }
end

local function createRender(s: any): any
	local def = UnitDefinitions.get(s.unitId)
	local model = Instance.new("Model")
	model.Name = "Squad_" .. s.id
	model.Parent = folder
	local position = Vector3.new(s.x, s.y, s.z)
	local r: any = {
		id = s.id,
		team = s.team,
		def = def,
		model = model,
		pos = position,
		yaw = s.yaw or 0,
		snapPos = position,
		snapYaw = s.yaw or 0,
		snapTime = os.clock(),
		vel = Vector3.zero,
		formation = s.formation,
		soldiers = {},
		slots = {},
		lastFire = -math.huge,
		aimUntil = 0,
		meleeUntil = 0,
		recoil = 0,
		accum = 0,
		state = s.state,
	}

	-- faint team ring on the ground (also carries the billboard and the charge dust)
	local disc = Instance.new("Part")
	disc.Name = "Disc"
	disc.Shape = Enum.PartType.Cylinder
	disc.Anchored = true
	disc.CanCollide = false
	disc.CanQuery = false
	disc.CanTouch = false
	disc.CastShadow = false
	disc.Material = Enum.Material.SmoothPlastic
	disc.Color = GameConfig.Teams[s.team].color
	disc.Transparency = 0.88
	disc.Parent = model
	r.disc = disc

	local dust = Instance.new("ParticleEmitter")
	dust.Texture = "rbxasset://textures/particles/smoke_main.dds"
	dust.Color = ColorSequence.new(Color3.fromRGB(165, 135, 100))
	dust.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 3), NumberSequenceKeypoint.new(1, 8) })
	dust.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 1) })
	dust.Lifetime = NumberRange.new(1, 1.6)
	dust.Rate = 35
	dust.Speed = NumberRange.new(2, 5)
	dust.SpreadAngle = Vector2.new(70, 70)
	dust.EmissionDirection = Enum.NormalId.Right -- the disc is rotated: +X points up
	dust.Enabled = false
	dust.Parent = disc
	r.dust = dust

	if def.visual == "Artillery" then
		r.cannon = SoldierModels.cannon(model)
	end
	for _ = 1, s.soldiers do
		table.insert(r.soldiers, newSoldier(r))
	end
	recomputeSlots(r)
	local base = CFrame.new(position) * CFrame.Angles(0, r.yaw, 0)
	for i, soldier in r.soldiers do
		local slot = r.slots[i] or Vector3.zero
		soldier.pos = (base * CFrame.new(slot.X, 0, slot.Z)).Position
	end
	buildBillboard(r)
	return r
end

---------------------------------------------------------------------------
-- Deaths
---------------------------------------------------------------------------

local function startDying(soldier: any, now: number)
	soldier.deathStart = now + math.random() * 0.3
	soldier.deathDir = if math.random() < 0.7 then 1 else -1
	soldier.deathFeet = CFrame.new(soldier.pos) * CFrame.Angles(0, soldier.yaw, 0)
	table.insert(dying, soldier)
end

local function destroyRender(r: any, animate: boolean)
	renders[r.id] = nil
	if r.disc then
		r.disc:Destroy()
	end
	if animate then
		local now = os.clock()
		for _, soldier in r.soldiers do
			startDying(soldier, now)
		end
		task.delay(6, function()
			r.model:Destroy()
		end)
	else
		r.model:Destroy()
	end
end

---------------------------------------------------------------------------
-- Snapshots
---------------------------------------------------------------------------

local function applySnapshot(r: any, s: any, now: number)
	local position = Vector3.new(s.x, s.y, s.z)
	local elapsed = now - r.snapTime
	if s.moving and elapsed > 0.05 then
		r.vel = (position - r.snapPos) / elapsed
	elseif not s.moving then
		r.vel = Vector3.zero
	end
	r.snapPos = position
	r.snapYaw = s.yaw or r.snapYaw
	r.snapTime = now
	r.state = s.state
	r.routing = s.state == "Routing"
	r.moving = s.moving
	r.rushing = s.rushing
	r.charging = s.charging
	r.forming = s.forming

	-- casualties: random soldiers fall, the rest close ranks
	local changed = false
	while #r.soldiers > s.soldiers and #r.soldiers > 0 do
		startDying(table.remove(r.soldiers, math.random(1, #r.soldiers)), now)
		changed = true
	end
	if s.formation ~= r.formation then
		r.formation = s.formation
		changed = true
	end
	if changed then
		recomputeSlots(r)
	end

	local diameter = (s.radius or 4) * 2 + 3
	r.disc.Size = Vector3.new(0.12, diameter, diameter)
	r.dust.Enabled = s.charging == true

	local ui = r.ui
	ui.name.Text = s.name
	ui.hp.Size = UDim2.fromScale(s.hp, 1)
	local status, color
	if r.routing then
		status, color = "ROUTING!", Color3.fromRGB(255, 90, 90)
	elseif s.forming then
		status, color = string.format("Forming %s %d%%", s.formation, s.forming * 100), Color3.fromRGB(255, 220, 120)
	elseif s.charging then
		status, color = "CHARGE!", Color3.fromRGB(255, 170, 60)
	elseif s.ownerId == player.UserId then
		status, color = s.order .. " · " .. s.formation, Color3.fromRGB(230, 235, 255)
	else
		status, color = s.formation, Color3.fromRGB(255, 220, 220)
	end
	ui.status.Text = status
	ui.status.TextColor3 = color
end

-- `instant` = remove missing squads without death animations (new round)
function SquadRenderer.sync(list: { any }, instant: boolean)
	local now = os.clock()
	local seen = {}
	for _, s in list do
		seen[s.id] = true
		local r = renders[s.id]
		if not r then
			r = createRender(s)
			renders[s.id] = r
		end
		applySnapshot(r, s, now)
	end
	for id, r in renders do
		if not seen[id] then
			destroyRender(r, not instant)
		end
	end
end

---------------------------------------------------------------------------
-- Poses
---------------------------------------------------------------------------

-- returns { armL, armR }, gun CFrame
local function infantryPose(r: any, s: any, now: number): ({ Vector2 }, CFrame)
	if r.routing then
		return ARMS_PORT, GUN_PORT
	end
	if now < r.meleeUntil then
		local thrust = math.max(0, math.sin(now * 7 + s.phase))
		local arms = { ARMS_BAYONET[1] + Vector2.new(thrust * 0.3, 0), ARMS_BAYONET[2] + Vector2.new(thrust * 0.35, 0) }
		return arms, GUN_BAYONET * CFrame.new(0, thrust * 1.1, 0)
	end
	local since = now - r.lastFire - s.delay
	if since >= 0 and since < 0.3 then
		local kick = 1 - since / 0.3
		return { ARMS_AIM[1], ARMS_AIM[2] + Vector2.new(kick * 0.3, 0) },
			GUN_AIM * CFrame.new(0, -0.5 * kick, 0.15 * kick)
	end
	local reloadTime = math.min(r.def.attackCooldown * 0.7, 5)
	if since >= 0.3 and since < reloadTime then
		local ram = math.sin(now * 5 + s.phase)
		return { ARMS_RELOAD[1], ARMS_RELOAD[2] + Vector2.new(ram * 0.35, 0) }, GUN_RELOAD
	end
	if (r.state == "Engaging" or now < r.aimUntil) and not r.moving then
		return ARMS_AIM, GUN_AIM
	end
	return ARMS_SHOULDER, GUN_SHOULDER
end

local CREW_COVER = { Vector2.new(2.6, 0.9), Vector2.new(2.6, -0.9) }
local CREW_PUSH = { Vector2.new(1.3, 0.3), Vector2.new(1.3, -0.3) }
local CREW_IDLE = { Vector2.new(0.1, 0), Vector2.new(0.2, 0) }

local function crewPose(r: any, s: any, now: number): { Vector2 }
	if now - r.lastFire < 0.7 then
		return CREW_COVER -- hands over the ears
	elseif r.routing then
		return ARMS_PORT
	elseif r.moving then
		return CREW_PUSH -- pushing the gun
	end
	return { CREW_IDLE[1], CREW_IDLE[2] + Vector2.new(math.sin(now + s.phase) * 0.05, 0) }
end

local function sabrePose(r: any, s: any, now: number): Vector2
	if r.routing then
		return Vector2.new(0.3, 0)
	elseif now < r.meleeUntil then
		return Vector2.new(1.0 + (math.sin(now * 9 + s.phase) + 1) * 0.85, -0.2) -- slashing
	elseif r.charging then
		return Vector2.new(1.55, 0) -- sabre pointed forward
	end
	return Vector2.new(0.35, 0.1)
end

---------------------------------------------------------------------------
-- Joints
---------------------------------------------------------------------------

local function poseInfantry(soldier: any, feet: CFrame, bob: number, swing: number, armSwing: number, lean: number)
	local m = soldier.rig.motors
	table.insert(bulkParts, soldier.rig.root)
	table.insert(bulkCFrames, feet * CFrame.new(0, TORSO + bob, 0))
	m.root.Transform = CFrame.Angles(lean, 0, 0)
	m.legL.Transform = CFrame.Angles(swing, 0, 0)
	m.legR.Transform = CFrame.Angles(-swing, 0, 0)
	m.armL.Transform = CFrame.Angles(soldier.armL.X - armSwing, 0, soldier.armL.Y)
	m.armR.Transform = angles(soldier.armR)
	m.neck.Transform = CFrame.Angles(0, soldier.look, 0)
	if m.gun then
		m.gun.Transform = soldier.gun
	end
end

local function poseCavalry(soldier: any, feet: CFrame, now: number)
	local m = soldier.rig.motors
	local gallop = soldier.legSwing
	local phase = soldier.phase
	local bob = math.abs(math.sin(phase)) * gallop * 0.5
	table.insert(bulkParts, soldier.rig.root)
	table.insert(
		bulkCFrames,
		feet * CFrame.new(0, HORSE + bob, 0) * CFrame.Angles(math.sin(phase) * gallop * 0.06, 0, 0)
	)
	m.legFL.Transform = CFrame.Angles(math.sin(phase) * gallop, 0, 0)
	m.legFR.Transform = CFrame.Angles(math.sin(phase + 0.6) * gallop, 0, 0)
	m.legBL.Transform = CFrame.Angles(math.sin(phase + math.pi) * gallop, 0, 0)
	m.legBR.Transform = CFrame.Angles(math.sin(phase + math.pi + 0.6) * gallop, 0, 0)
	m.neck.Transform =
		CFrame.Angles(math.sin(phase * 2) * gallop * 0.15 + math.sin(now * 0.8 + soldier.yawJitter * 9) * 0.05, 0, 0)
	m.tail.Transform = CFrame.Angles(math.sin(phase) * gallop * 0.3, math.sin(now * 1.3 + soldier.delay * 20) * 0.2, 0)
	m.rider.Transform = CFrame.new(0, -bob * 0.4, 0) * CFrame.Angles(-gallop * 0.12, 0, 0)
	m.armR.Transform = angles(soldier.armR)
end

local function updateDying(now: number, dt: number)
	for i = #dying, 1, -1 do
		local soldier = dying[i]
		local rig = soldier.rig
		if not rig.root.Parent then
			table.remove(dying, i) -- squad model already removed (new round)
			continue
		end
		local t = now - soldier.deathStart
		if t < 0 then
			continue
		elseif t < 0.8 then
			local fall = math.min(1, t / 0.7) ^ 2
			local alpha = math.min(1, dt * 8)
			if soldier.kind == "Cavalry" then
				-- horse and rider topple sideways
				soldier.legSwing = lerp(soldier.legSwing, 0, alpha)
				soldier.armR = soldier.armR:Lerp(Vector2.new(0.2, 0), alpha)
				local feet = soldier.deathFeet * CFrame.Angles(0, 0, fall * math.rad(80) * soldier.deathDir)
				poseCavalry(soldier, feet, now)
			else
				soldier.armL = soldier.armL:Lerp(ARMS_DEAD[1], alpha)
				soldier.armR = soldier.armR:Lerp(ARMS_DEAD[2], alpha)
				soldier.gun = soldier.gun:Lerp(GUN_DROPPED, alpha)
				-- pivot around the feet, falling backwards (or forwards)
				local feet = soldier.deathFeet * CFrame.Angles(fall * math.rad(84) * soldier.deathDir, 0, 0)
				poseInfantry(soldier, feet, 0, 0.3 * fall, 0, 0)
			end
		elseif t > 3 then
			local fade = (t - 3) / 1
			if fade >= 1 then
				rig.model:Destroy()
				table.remove(dying, i)
			else
				for _, p in rig.parts do
					p.Transparency = fade
				end
			end
		end
	end
end

---------------------------------------------------------------------------
-- Per-frame update
---------------------------------------------------------------------------

local function updateMotion(r: any, dt: number, now: number)
	local ahead = math.min(now - r.snapTime, 0.3)
	local predicted = r.snapPos + r.vel * ahead
	r.pos = r.pos:Lerp(predicted, 1 - math.exp(-dt * 10))
	r.yaw = MathUtil.normalizeAngle(r.yaw + MathUtil.angleDiff(r.yaw, r.snapYaw) * (1 - math.exp(-dt * 8)))
end

local function updateSquad(r: any, dt: number, now: number, near: boolean)
	local base = CFrame.new(r.pos) * CFrame.Angles(0, r.yaw, 0)
	local moveAlpha = 1 - math.exp(-dt * (if r.forming then 1.6 else 6))
	local poseAlpha = 1 - math.exp(-dt * 10)
	local running = r.rushing or r.routing or r.charging
	local cavalry = r.def.visual == "Cavalry"

	for i, soldier in r.soldiers do
		local slot = r.slots[i] or Vector3.zero
		if r.routing then
			slot += soldier.jitter * 2.5
		elseif r.rushing then
			slot += soldier.jitter
		end
		local target = (base * CFrame.new(slot.X, 0, slot.Z)).Position
		local flat = Vector3.new(soldier.pos.X, target.Y, soldier.pos.Z):Lerp(target, moveAlpha)

		if near and now >= soldier.nextGround then
			soldier.nextGround = now + 0.35 + math.random() * 0.3
			local hit = Workspace:Raycast(flat + Vector3.new(0, 8, 0), Vector3.new(0, -24, 0), groundParams)
			soldier.groundY = if hit then hit.Position.Y else nil
		end
		local groundY = if near and soldier.groundY then soldier.groundY else r.pos.Y
		soldier.pos = Vector3.new(flat.X, lerp(soldier.pos.Y, groundY, moveAlpha), flat.Z)

		local desiredYaw = r.yaw + (if r.routing then soldier.yawJitter else 0)
		soldier.yaw = MathUtil.normalizeAngle(soldier.yaw + MathUtil.angleDiff(soldier.yaw, desiredYaw) * poseAlpha)

		-- walking if the squad moves or this soldier is catching up with its slot
		local walking = r.moving or (target - flat).Magnitude > 0.4
		local rate = if not walking
			then 0
			elseif running then (if cavalry then 13 else 12)
			else (if cavalry then 6 else 7)
		soldier.phase += dt * rate
		local amplitude = if not walking then 0 elseif running then (if cavalry then 0.9 else 0.9) else 0.6
		soldier.legSwing = lerp(soldier.legSwing, amplitude, poseAlpha)

		local feet = CFrame.new(soldier.pos) * CFrame.Angles(0, soldier.yaw, 0)
		if cavalry then
			soldier.armR = soldier.armR:Lerp(sabrePose(r, soldier, now), poseAlpha)
			poseCavalry(soldier, feet, now)
		else
			local arms, gun
			if soldier.kind == "Crew" then
				arms, gun = crewPose(r, soldier, now), GUN_SHOULDER
			else
				arms, gun = infantryPose(r, soldier, now)
			end
			soldier.armL = soldier.armL:Lerp(arms[1], poseAlpha)
			soldier.armR = soldier.armR:Lerp(arms[2], poseAlpha)
			soldier.gun = soldier.gun:Lerp(gun, poseAlpha)
			-- idle soldiers glance around now and then
			soldier.look =
				lerp(soldier.look, if walking then 0 else math.sin(now * 0.3 + soldier.phase) * 0.35, poseAlpha * 0.3)
			local swing = math.sin(soldier.phase) * soldier.legSwing
			local bob = math.abs(math.cos(soldier.phase)) * soldier.legSwing * 0.25
			local armSwing = if gun == GUN_SHOULDER then swing * 0.8 else 0
			local lean = if running then -0.15 else 0
			poseInfantry(soldier, feet, bob, swing, armSwing, lean)
		end
	end

	if r.cannon then
		r.recoil = math.max(0, r.recoil - dt * 1.2)
		table.insert(bulkParts, r.cannon.root)
		table.insert(bulkCFrames, base * CANNON_OFFSET)
		r.cannon.motors.barrel.Transform = CFrame.new(0, 0, r.recoil * 1.8)
	end
	table.insert(bulkParts, r.disc)
	table.insert(bulkCFrames, CFrame.new(r.pos + Vector3.new(0, 0.1, 0)) * DISC_ROTATION)
end

function SquadRenderer.update(dt: number)
	local now = os.clock()
	frame += 1
	refreshGroundFilter(now)
	table.clear(bulkParts)
	table.clear(bulkCFrames)
	local camera = Workspace.CurrentCamera
	local cameraPosition = if camera then camera.CFrame.Position else Vector3.zero
	for id, r in renders do
		updateMotion(r, dt, now)
		r.accum += dt
		local distance = (r.pos - cameraPosition).Magnitude
		local every = if distance > 450 then 8 elseif distance > 260 then 3 else 1
		if (frame + id) % every == 0 then
			updateSquad(r, r.accum, now, distance < 260)
			r.accum = 0
		end
	end
	updateDying(now, dt)
	if #bulkParts > 0 then
		Workspace:BulkMoveTo(bulkParts, bulkCFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

---------------------------------------------------------------------------
-- Events from the VFX remote / queries
---------------------------------------------------------------------------

-- Volley: soldiers recoil and reload. Returns a few muzzle positions for flashes/smoke.
function SquadRenderer.fire(squadId: number): { Vector3 }
	local r = renders[squadId]
	local out = {}
	if not r then
		return out
	end
	local now = os.clock()
	r.lastFire = now
	r.aimUntil = now + r.def.attackCooldown + 2
	local step = math.max(1, #r.soldiers // 6)
	for i = 1, #r.soldiers, step do
		local soldier = r.soldiers[i]
		local torso = CFrame.new(soldier.pos) * CFrame.Angles(0, soldier.yaw, 0) * CFrame.new(0, TORSO, 0)
		table.insert(out, (torso * GUN_AIM * MUZZLE).Position)
	end
	return out
end

function SquadRenderer.cannonFire(squadId: number)
	local r = renders[squadId]
	if r then
		r.lastFire = os.clock()
		r.recoil = 1
	end
end

function SquadRenderer.melee(squadId: number?)
	local r = squadId and renders[squadId]
	if r then
		r.meleeUntil = os.clock() + 1.6
	end
end

function SquadRenderer.getModel(squadId: number): Model?
	local r = renders[squadId]
	return if r then r.model else nil
end

function SquadRenderer.getPosition(squadId: number): Vector3?
	local r = renders[squadId]
	return if r then r.pos else nil
end

return SquadRenderer
