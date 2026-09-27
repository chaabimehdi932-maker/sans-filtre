--[[
	SquadRenderer
	Draws and animates every squad on this client from the server snapshots.
	The server only simulates logical squads (position, facing, formation, soldier count);
	here each soldier gets a part-based model and procedural animation:
	  march (legs/arms swing, bob) · aim · volley recoil · reload · bayonet thrust · rout run
	  cavalry gallop + sabre (point when charging, slashes in melee) · cannon recoil · death falls
	Soldiers are placed with BulkMoveTo; far squads update less often (LOD).
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

-- Gun poses (relative to the soldier's feet). The musket lies along the gun bone's +Y.
local GUN_SHOULDER = CFrame.new(0.72, 0.95, -0.12) * CFrame.Angles(math.rad(-6), 0, 0)
local GUN_AIM = CFrame.new(0.3, 1.95, 0.35) * CFrame.Angles(math.rad(-90), 0, 0)
local GUN_RELOAD = CFrame.new(0.15, 0.55, -0.6) * CFrame.Angles(math.rad(-12), 0, 0)
local GUN_BAYONET = CFrame.new(0.25, 1.3, 0.55) * CFrame.Angles(math.rad(-95), 0, 0)
local GUN_PORT = CFrame.new(0.2, 1.0, -0.35) * CFrame.Angles(math.rad(-40), 0, math.rad(35))
local GUN_DROPPED = CFrame.new(0.9, 0.12, -0.6) * CFrame.Angles(math.rad(-90), 0, math.rad(80))
local MUZZLE = CFrame.new(0, 3.1, 0)
local CANNON_OFFSET = CFrame.new(0, 0, -2.5)
local DISC_ROTATION = CFrame.Angles(0, 0, math.rad(90))

local bulkParts: { BasePart } = {}
local bulkCFrames: { CFrame } = {}
local bones: { [string]: CFrame } = {}

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

---------------------------------------------------------------------------
-- Building
---------------------------------------------------------------------------

local function newSoldier(r: any): any
	local model = if r.def.visual == "Cavalry"
		then SoldierModels.cavalry(r.model, r.team, r.def)
		else SoldierModels.infantry(r.model, r.team, r.def, r.def.visual ~= "Artillery")
	return {
		pieces = model.pieces,
		kind = if r.def.visual == "Artillery" then "Crew" else model.kind,
		pos = r.pos,
		yaw = r.yaw,
		groundY = nil,
		nextGround = 0,
		phase = math.random() * math.pi * 2,
		legSwing = 0,
		armL = 0,
		armR = 0,
		gun = GUN_SHOULDER,
		root = nil,
		jitter = Vector3.new(math.random() * 3 - 1.5, 0, math.random() * 3 - 1.5),
		yawJitter = math.random() * 0.8 - 0.4,
		delay = math.random() * 0.15, -- volleys ripple down the line
	}
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
	gui.Size = UDim2.fromOffset(130, 44)
	gui.StudsOffsetWorldSpace = Vector3.new(0, if r.def.visual == "Cavalry" then 7.5 else 5.5, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 300
	gui.LightInfluence = 0
	gui.Adornee = r.disc

	local function label(y: number, height: number, size: number, color: Color3): TextLabel
		local text = Instance.new("TextLabel")
		text.BackgroundTransparency = 1
		text.Position = UDim2.fromOffset(0, y)
		text.Size = UDim2.new(1, 0, 0, height)
		text.Font = Enum.Font.GothamBold
		text.TextSize = size
		text.TextColor3 = color
		text.TextStrokeTransparency = 0.3
		text.Parent = gui
		return text
	end
	local function bar(y: number, height: number, color: Color3): Frame
		local back = Instance.new("Frame")
		back.Position = UDim2.fromOffset(15, y)
		back.Size = UDim2.new(1, -30, 0, height)
		back.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
		back.BorderSizePixel = 0
		back.Parent = gui
		local fill = Instance.new("Frame")
		fill.Size = UDim2.fromScale(1, 1)
		fill.BackgroundColor3 = color
		fill.BorderSizePixel = 0
		fill.Parent = back
		return fill
	end
	local name = label(0, 15, 13, teamColor:Lerp(Color3.new(1, 1, 1), 0.5))
	local hp = bar(17, 6, Color3.fromRGB(225, 60, 60))
	local morale = bar(25, 4, Color3.fromRGB(240, 200, 60))
	local status = label(30, 13, 11, Color3.new(1, 1, 1))
	gui.Parent = r.disc
	r.ui = { name = name, hp = hp, morale = morale, status = status }
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
	disc.Transparency = 0.78
	disc.Parent = model
	r.disc = disc

	local dust = Instance.new("ParticleEmitter")
	dust.Texture = "rbxasset://textures/particles/smoke_main.dds"
	dust.Color = ColorSequence.new(Color3.fromRGB(165, 135, 100))
	dust.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2), NumberSequenceKeypoint.new(1, 6) })
	dust.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 1) })
	dust.Lifetime = NumberRange.new(1, 1.6)
	dust.Rate = 30
	dust.Speed = NumberRange.new(2, 5)
	dust.SpreadAngle = Vector2.new(70, 70)
	dust.EmissionDirection = Enum.NormalId.Right -- the disc is rotated: +X points up
	dust.Enabled = false
	dust.Parent = disc
	r.dust = dust

	if def.visual == "Artillery" then
		r.extras = SoldierModels.cannon(model)
	end
	for _ = 1, s.soldiers do
		table.insert(r.soldiers, newSoldier(r))
	end
	recomputeSlots(r)
	local base = CFrame.new(position) * CFrame.Angles(0, r.yaw, 0)
	for i, soldier in r.soldiers do
		local slot = r.slots[i] or Vector3.zero
		soldier.pos = (base * CFrame.new(slot.X, 0, slot.Z)).Position
		soldier.yaw = r.yaw
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
	soldier.deathRoot = CFrame.new(soldier.pos) * CFrame.Angles(0, soldier.yaw, 0)
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
		local soldier = table.remove(r.soldiers, math.random(1, #r.soldiers))
		startDying(soldier, now)
		changed = true
	end
	if s.formation ~= r.formation then
		r.formation = s.formation
		changed = true
	end
	if changed then
		recomputeSlots(r)
	end

	local diameter = (s.radius or 4) * 2 + 2
	r.disc.Size = Vector3.new(0.15, diameter, diameter)
	r.dust.Enabled = s.charging == true

	local ui = r.ui
	ui.name.Text = s.name
	ui.hp.Size = UDim2.fromScale(s.hp, 1)
	ui.morale.Size = UDim2.fromScale(s.morale, 1)
	local status, color
	if r.routing then
		status, color = "ROUTING!", Color3.fromRGB(255, 90, 90)
	elseif s.forming then
		status, color = string.format("Forming %s %d%%", s.formation, s.forming * 100), Color3.fromRGB(255, 220, 120)
	elseif s.charging then
		status, color = "CHARGE!", Color3.fromRGB(255, 170, 60)
	elseif s.ownerId == player.UserId then
		status, color = s.order .. " · " .. s.formation, Color3.new(1, 1, 1)
	else
		status, color = s.formation, Color3.new(1, 1, 1)
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

-- returns armL, armR, gun CFrame
local function infantryPose(r: any, s: any, now: number): (number, number, CFrame)
	if r.routing then
		return 0.9, 0.9, GUN_PORT
	end
	if now < r.meleeUntil then
		local thrust = math.max(0, math.sin(now * 7 + s.phase))
		return 1.2 + thrust * 0.3, 0.8 + thrust * 0.35, GUN_BAYONET * CFrame.new(0, thrust * 0.7, 0)
	end
	local since = now - r.lastFire - s.delay
	if since >= 0 and since < 0.3 then
		local kick = 1 - since / 0.3
		return 1.5, 1.25 + kick * 0.3, GUN_AIM * CFrame.new(0, -0.35 * kick, 0.1 * kick)
	end
	local reloadTime = math.min(r.def.attackCooldown * 0.7, 5)
	if since >= 0.3 and since < reloadTime then
		local ram = math.sin(now * 5 + s.phase)
		return 0.7, 1.0 + ram * 0.3, GUN_RELOAD
	end
	if (r.state == "Engaging" or now < r.aimUntil) and not r.moving then
		return 1.5, 1.25, GUN_AIM
	end
	return 0, 0.05, GUN_SHOULDER
end

local function crewPose(r: any, s: any, now: number): (number, number)
	local since = now - r.lastFire
	if since < 0.7 then
		return 2.3, 2.3 -- hands over the ears
	end
	if r.routing then
		return 0.6, 0.6
	end
	if r.moving then
		return 0.9, 0.9 -- pushing the gun
	end
	return 0.2, 0.3 + math.sin(now + s.phase) * 0.05
end

local function sabrePose(r: any, s: any, now: number): number
	if r.routing then
		return 0.3
	end
	if now < r.meleeUntil then
		return 1.0 + (math.sin(now * 9 + s.phase) + 1) * 0.85 -- slashing
	end
	if r.charging then
		return 1.55 -- sabre pointed forward
	end
	return 0.35
end

---------------------------------------------------------------------------
-- Bones → parts
---------------------------------------------------------------------------

local function emit(soldier: any)
	for _, piece in soldier.pieces do
		table.insert(bulkParts, piece.part)
		table.insert(bulkCFrames, bones[piece.bone] * piece.offset)
	end
end

local function infantryBones(soldier: any, root: CFrame, legL: number, legR: number, armSwing: number)
	bones.root = root
	bones.legL = root * SoldierModels.HIP_L * CFrame.Angles(legL, 0, 0)
	bones.legR = root * SoldierModels.HIP_R * CFrame.Angles(legR, 0, 0)
	bones.armL = root * SoldierModels.SHOULDER_L * CFrame.Angles(soldier.armL - armSwing, 0, 0)
	bones.armR = root * SoldierModels.SHOULDER_R * CFrame.Angles(soldier.armR, 0, 0)
	bones.gun = root * soldier.gun
end

local function cavalryBones(soldier: any, root: CFrame, now: number)
	local gallop = soldier.legSwing
	local phase = soldier.phase
	local bob = math.abs(math.sin(phase)) * gallop * 0.35
	local horse = root
		* CFrame.new(0, SoldierModels.HORSE_HEIGHT + bob, 0)
		* CFrame.Angles(math.sin(phase) * gallop * 0.06, 0, 0)
	bones.horse = horse
	local hips = SoldierModels.HORSE_HIPS
	bones.legFL = horse * hips.legFL * CFrame.Angles(math.sin(phase) * gallop, 0, 0)
	bones.legFR = horse * hips.legFR * CFrame.Angles(math.sin(phase + 0.6) * gallop, 0, 0)
	bones.legBL = horse * hips.legBL * CFrame.Angles(math.sin(phase + math.pi) * gallop, 0, 0)
	bones.legBR = horse * hips.legBR * CFrame.Angles(math.sin(phase + math.pi + 0.6) * gallop, 0, 0)
	local nod = math.sin(phase * 2) * gallop * 0.15 + math.sin(now * 0.8 + soldier.jitter.X) * 0.05
	bones.neck = horse * SoldierModels.NECK * CFrame.Angles(nod, 0, 0)
	local rider = horse * SoldierModels.SADDLE * CFrame.new(0, -bob * 0.4, 0)
	bones.rider = rider
	bones.armL = rider * SoldierModels.RIDER_SHOULDER_L * CFrame.Angles(0.7, 0, 0) -- reins
	bones.armR = rider * SoldierModels.RIDER_SHOULDER_R * CFrame.Angles(soldier.armR, 0, 0)
end

local DEAD_ARMS = 2.6

local function updateDying(now: number, dt: number)
	for i = #dying, 1, -1 do
		local soldier = dying[i]
		local t = now - soldier.deathStart
		if not soldier.pieces[1] or not soldier.pieces[1].part.Parent then
			table.remove(dying, i) -- squad model already removed (new round)
			continue
		end
		if t < 0 then
			continue
		elseif t < 0.8 then
			local fall = math.min(1, t / 0.7) ^ 2
			local alpha = math.min(1, dt * 8)
			if soldier.kind == "Cavalry" then
				-- horse and rider topple sideways
				local root = soldier.deathRoot * CFrame.Angles(0, 0, fall * math.rad(80) * soldier.deathDir)
				soldier.legSwing = lerp(soldier.legSwing, 0, alpha)
				soldier.armR = lerp(soldier.armR, 0.2, alpha)
				cavalryBones(soldier, root, now)
			else
				local root = soldier.deathRoot * CFrame.Angles(fall * math.rad(84) * soldier.deathDir, 0, 0)
				soldier.armL = lerp(soldier.armL, DEAD_ARMS, alpha)
				soldier.armR = lerp(soldier.armR, DEAD_ARMS, alpha)
				soldier.gun = soldier.gun:Lerp(GUN_DROPPED, alpha)
				infantryBones(soldier, root, 0.3 * fall, -0.2 * fall, 0)
			end
			emit(soldier)
		elseif t > 3 then
			local fade = (t - 3) / 1
			if fade >= 1 then
				for _, piece in soldier.pieces do
					piece.part:Destroy()
				end
				table.remove(dying, i)
			else
				for _, piece in soldier.pieces do
					piece.part.Transparency = fade
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
			local hit = Workspace:Raycast(flat + Vector3.new(0, 6, 0), Vector3.new(0, -20, 0), groundParams)
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
			elseif running then (if cavalry then 15 else 13)
			else (if cavalry then 7 else 8)
		soldier.phase += dt * rate
		local amplitude = if not walking then 0 elseif running then (if cavalry then 0.9 else 0.8) else 0.55
		soldier.legSwing = lerp(soldier.legSwing, amplitude, poseAlpha)

		local root = CFrame.new(soldier.pos) * CFrame.Angles(0, soldier.yaw, 0)
		if cavalry then
			soldier.armR = lerp(soldier.armR, sabrePose(r, soldier, now), poseAlpha)
			cavalryBones(soldier, root, now)
		else
			local armL, armR, gun
			if soldier.kind == "Crew" then
				armL, armR = crewPose(r, soldier, now)
				gun = GUN_SHOULDER
			else
				armL, armR, gun = infantryPose(r, soldier, now)
			end
			soldier.armL = lerp(soldier.armL, armL, poseAlpha)
			soldier.armR = lerp(soldier.armR, armR, poseAlpha)
			soldier.gun = soldier.gun:Lerp(gun, poseAlpha)
			local swing = math.sin(soldier.phase) * soldier.legSwing
			local bob = math.abs(math.cos(soldier.phase)) * soldier.legSwing * 0.18
			root = CFrame.new(soldier.pos + Vector3.new(0, bob, 0)) * CFrame.Angles(0, soldier.yaw, 0)
			-- only the free arm swings while marching (the right hand holds the musket)
			local armSwing = if gun == GUN_SHOULDER or soldier.kind == "Crew" then swing * 0.7 else 0
			infantryBones(soldier, root, swing, -swing, armSwing)
		end
		soldier.root = root
		emit(soldier)
	end

	if r.extras then
		r.recoil = math.max(0, r.recoil - dt * 1.2)
		local carriage = base * CANNON_OFFSET
		bones.carriage = carriage
		bones.barrel = carriage * CFrame.new(0, 1.55, r.recoil * 1.3)
		for _, piece in r.extras do
			table.insert(bulkParts, piece.part)
			table.insert(bulkCFrames, bones[piece.bone] * piece.offset)
		end
	end
	table.insert(bulkParts, r.disc)
	table.insert(bulkCFrames, CFrame.new(r.pos + Vector3.new(0, 0.12, 0)) * DISC_ROTATION)
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
-- Events from the VFX remote
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
		local root = soldier.root or CFrame.new(soldier.pos)
		table.insert(out, (root * GUN_AIM * MUZZLE).Position)
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
