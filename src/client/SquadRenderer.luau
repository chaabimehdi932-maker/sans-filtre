--[[
	SquadRenderer
	Draws every squad on this client from the server snapshots: one full-size R6 rig per soldier
	(SoldierModels) walking to its formation slot, posed by SoldierAnimationService.
	  • Hybrid HP: the server keeps one pooled HP per squad; when its soldier count drops, random
	    soldiers here play a death animation and the rest close ranks.
	  • Performance: at most GameConfig.Rendering.MaxActiveSoldiers rigs across both teams
	    (squads show proportionally fewer soldiers when over the cap), distance LOD on animation,
	    and only each rig's anchored root is moved (BulkMoveTo).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local FormationDefinitions = require(Modules:WaitForChild("FormationDefinitions"))
local GameConfig = require(Modules:WaitForChild("GameConfig"))
local MathUtil = require(Modules:WaitForChild("MathUtil"))
local UnitDefinitions = require(Modules:WaitForChild("UnitDefinitions"))

local SoldierAnimationService = require(script.Parent:WaitForChild("SoldierAnimationService"))
local SoldierModels = require(script.Parent:WaitForChild("SoldierModels"))

local Rendering = GameConfig.Rendering
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

local CANNON_OFFSET = CFrame.new(0, SoldierModels.CANNON_AXLE_HEIGHT, -4)
local DISC_ROTATION = CFrame.Angles(0, 0, math.rad(90))

local bulkParts: { BasePart } = {}
local bulkCFrames: { CFrame } = {}

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

---------------------------------------------------------------------------
-- Building
---------------------------------------------------------------------------

local function newSoldier(r: any, index: number): any
	local rig
	if r.def.visual == "Cavalry" then
		rig = SoldierModels.cavalry(r.model, r.team, r.def)
	elseif r.def.visual == "Artillery" then
		rig = SoldierModels.infantry(
			r.model,
			r.team,
			r.def,
			false,
			if index == 1 then "Rammer" elseif index == 2 then "Linstock" else nil
		)
	else
		rig = SoldierModels.infantry(r.model, r.team, r.def, true)
	end
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
		gun = CFrame.new(),
		look = 0,
		lean = 0,
		hitUntil = 0,
		jitter = Vector3.new(math.random() * 4 - 2, 0, math.random() * 4 - 2),
		yawJitter = math.random() * 0.8 - 0.4,
		delay = math.random() * 0.15, -- volleys ripple down the line
		-- individuality: nobody moves exactly like their neighbour
		vel = Vector3.zero,
		speedMult = 0.85 + math.random() * 0.3,
		reaction = math.random() * 0.6,
		slotNoise = Vector3.new(math.random() - 0.5, 0, math.random() - 0.5) * 1.1,
		idleYaw = (math.random() - 0.5) * 0.3,
		foe = nil,
		foeUntil = 0,
	}
	if rig.kind == "Cavalry" then
		SoldierAnimationService.setupRider(soldier)
	end
	return soldier
end

local function recomputeSlots(r: any)
	local slots = FormationDefinitions.layout(r.formation, #r.soldiers, r.def.spacingMult)
	if r.def.visual == "Artillery" then
		for i, slot in slots do
			slots[i] = slot + Vector3.new(0, 0, 2) -- assistants stand behind the gun
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

local function createRender(s: any, shown: number): any
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
		lastHp = s.hp,
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
	for i = 1, shown do
		table.insert(r.soldiers, newSoldier(r, i))
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
			table.insert(bulkParts, rig.root)
			table.insert(bulkCFrames, SoldierAnimationService.death(soldier, soldier.deathFeet, fall, dt, now))
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
-- Snapshots
---------------------------------------------------------------------------

local function applySnapshot(r: any, s: any, shown: number, now: number)
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

	-- took damage: a few soldiers flinch (HitReact)
	if s.hp < r.lastHp - 0.001 then
		for _, soldier in r.soldiers do
			if math.random() < 0.3 then
				soldier.hitUntil = now + 0.35
			end
		end
	end
	r.lastHp = s.hp

	-- casualties: random soldiers fall, the rest close ranks. If the count only dropped because
	-- the soldier cap tightened (new squads arrived), the extra rigs vanish quietly instead.
	local silent = r.lastSoldiers ~= nil and s.soldiers == r.lastSoldiers
	r.lastSoldiers = s.soldiers
	local changed = false
	while #r.soldiers > shown and #r.soldiers > 0 do
		local index = math.random(1, #r.soldiers)
		if r.def.visual == "Artillery" and #r.soldiers > 2 then
			index = math.random(3, #r.soldiers) -- the loader and gunner are the last to fall
		end
		local soldier = table.remove(r.soldiers, index)
		if silent then
			soldier.rig.model:Destroy()
		else
			startDying(soldier, now)
		end
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
	ui.name.Text = (if s.controlled then "★ " else "") .. s.name
	ui.hp.Size = UDim2.fromScale(s.hp, 1)
	local status, color
	if r.routing then
		status, color = "ROUTING!", Color3.fromRGB(255, 90, 90)
	elseif s.forming then
		status, color = string.format("Forming %s %d%%", s.formation, s.forming * 100), Color3.fromRGB(255, 220, 120)
	elseif s.charging then
		status, color = "CHARGE!", Color3.fromRGB(255, 170, 60)
	elseif s.ownerId == player.UserId then
		status = if s.controlled then "YOUR COMMAND · " .. s.order else "Ally AI · " .. s.formation
		color = if s.controlled then Color3.fromRGB(255, 225, 110) else Color3.fromRGB(210, 225, 255)
	else
		status, color = s.formation, Color3.fromRGB(255, 220, 220)
	end
	ui.status.Text = status
	ui.status.TextColor3 = color
end

-- `instant` = remove missing squads without death animations (new round)
function SquadRenderer.sync(list: { any }, instant: boolean)
	local now = os.clock()
	-- performance cap: scale the number of drawn soldiers when the battle is too big
	local total = 0
	for _, s in list do
		total += UnitDefinitions.get(s.unitId).soldiers
	end
	local scale = math.min(1, Rendering.MaxActiveSoldiers / math.max(1, total))
	local seen = {}
	for _, s in list do
		seen[s.id] = true
		local def = UnitDefinitions.get(s.unitId)
		local fullShown = math.max(1, math.ceil(def.soldiers * scale))
		local shown = math.max(if s.soldiers > 0 then 1 else 0, math.ceil(s.soldiers * fullShown / def.soldiers))
		local r = renders[s.id]
		if not r then
			r = createRender(s, shown)
			renders[s.id] = r
		end
		applySnapshot(r, s, shown, now)
	end
	for id, r in renders do
		if not seen[id] then
			destroyRender(r, not instant)
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

-- Enemy soldiers near a point (for melee pairing)
local function enemiesNear(r: any, radius: number): { any }
	local found = {}
	for _, other in renders do
		if other.team ~= r.team and (other.pos - r.pos).Magnitude <= radius + 20 then
			for _, soldier in other.soldiers do
				table.insert(found, soldier)
			end
		end
	end
	return found
end

--[[
	Soldiers are individuals: each walks to its own spot (formation slot + a personal offset)
	with its own top speed and reaction delay, accelerates instead of snapping, steps aside
	from comrades that are too close, and in melee leaves the ranks to face an enemy soldier.
]]
local function updateSquad(r: any, dt: number, now: number, near: boolean, detail: boolean)
	local base = CFrame.new(r.pos) * CFrame.Angles(0, r.yaw, 0)
	local poseAlpha = 1 - math.exp(-dt * 10)
	local accel = 1 - math.exp(-dt * (if r.forming then 2 else 5))
	local running = r.rushing or r.routing or r.charging
	local cavalry = r.def.visual == "Cavalry"
	local artillery = r.def.visual == "Artillery"
	local personalSpace = if cavalry then 4.2 else 2.3
	local squadSpeed = math.max(r.vel.Magnitude, 0)
	local melee = now < r.meleeUntil and not artillery
	local foes = if melee then enemiesNear(r, 30) else nil

	if r.moving and not r.wasMoving then
		r.moveStart = now -- soldiers set off one after another
	end
	r.wasMoving = r.moving

	for i, soldier in r.soldiers do
		-- 1) where this soldier wants to be
		local slot = (r.slots[i] or Vector3.zero) + soldier.slotNoise
		local yawOffset = 0
		if artillery and not r.routing then
			local roleSlot, roleYaw = SoldierAnimationService.crewSlot(r, i, now)
			if roleSlot then
				slot, yawOffset = roleSlot, roleYaw
			end
		end
		if r.routing then
			slot += soldier.jitter * 2.5
		elseif r.rushing then
			slot += soldier.jitter
		end
		local target = (base * CFrame.new(slot.X, 0, slot.Z)).Position
		local facePoint: Vector3? = nil

		if foes and #foes > 0 then
			-- melee: pick an enemy soldier now and then and square up to them
			if
				not soldier.foe
				or soldier.foe.deathStart
				or not soldier.foe.rig.root.Parent
				or now >= soldier.foeUntil
			then
				local best, bestDistance = nil, math.huge
				for _, foe in foes do
					local d = (foe.pos - soldier.pos).Magnitude
					if d < bestDistance and not foe.deathStart then
						best, bestDistance = foe, d
					end
				end
				soldier.foe = best
				soldier.foeUntil = now + 0.6 + math.random() * 0.6
			end
			local foe = soldier.foe
			if foe then
				local away = Vector3.new(soldier.pos.X - foe.pos.X, 0, soldier.pos.Z - foe.pos.Z)
				if away.Magnitude < 0.1 then
					away = Vector3.new(1, 0, 0)
				end
				target = foe.pos + away.Unit * (personalSpace + 0.4)
				facePoint = foe.pos
			end
		else
			soldier.foe = nil
		end

		-- 2) accelerate towards it at this soldier's own pace
		local toTarget = Vector3.new(target.X - soldier.pos.X, 0, target.Z - soldier.pos.Z)
		local distance = toTarget.Magnitude
		local topSpeed = math.max(squadSpeed * 1.15, if running then 16 else 9) * soldier.speedMult
		if distance > 6 then
			topSpeed *= 1.35 -- catching up with the ranks
		end
		local desired = Vector3.zero
		local waiting = r.moving and now - (r.moveStart or 0) < soldier.reaction
		if distance > 0.25 and not waiting then
			desired = toTarget.Unit * math.min(topSpeed, distance * 3)
		end
		soldier.vel = soldier.vel:Lerp(desired, accel)

		-- 3) personal space: step away from comrades that are too close
		local push = Vector3.zero
		for j, other in r.soldiers do
			if j ~= i then
				local offset = Vector3.new(soldier.pos.X - other.pos.X, 0, soldier.pos.Z - other.pos.Z)
				local d = offset.Magnitude
				if d < personalSpace and d > 0.01 then
					push += offset / d * (personalSpace - d) * 4
				end
			end
		end
		local step = (soldier.vel + push) * dt
		local flat = Vector3.new(soldier.pos.X + step.X, soldier.pos.Y, soldier.pos.Z + step.Z)

		if near and now >= soldier.nextGround then
			soldier.nextGround = now + 0.35 + math.random() * 0.3
			local hit = Workspace:Raycast(flat + Vector3.new(0, 8, 0), Vector3.new(0, -24, 0), groundParams)
			soldier.groundY = if hit then hit.Position.Y else nil
		end
		local groundY = if near and soldier.groundY then soldier.groundY else r.pos.Y
		soldier.pos = Vector3.new(flat.X, lerp(soldier.pos.Y, groundY, math.min(1, dt * 8)), flat.Z)

		-- 4) face where you walk, your opponent, or the squad's front
		local speed = soldier.vel.Magnitude
		local desiredYaw
		if facePoint then
			desiredYaw =
				MathUtil.yawFromDirection(Vector3.new(facePoint.X - soldier.pos.X, 0, facePoint.Z - soldier.pos.Z))
		elseif speed > 1.5 then
			desiredYaw = MathUtil.yawFromDirection(soldier.vel)
		else
			desiredYaw = r.yaw + yawOffset + soldier.idleYaw + (if r.routing then soldier.yawJitter else 0)
		end
		soldier.yaw = MathUtil.normalizeAngle(soldier.yaw + MathUtil.angleDiff(soldier.yaw, desiredYaw) * poseAlpha)

		-- 5) legs follow the real speed
		local walking = speed > 0.8
		local soldierRunning = running or speed > 13
		soldier.phase += dt * speed * (if cavalry then 0.55 else 0.8)
		local amplitude = if not walking then 0 elseif soldierRunning then 0.9 else 0.6
		soldier.legSwing = lerp(soldier.legSwing, amplitude, poseAlpha)

		local feet = CFrame.new(soldier.pos) * CFrame.Angles(0, soldier.yaw, 0)
		table.insert(bulkParts, soldier.rig.root)
		table.insert(
			bulkCFrames,
			SoldierAnimationService.update(r, soldier, i, feet, dt, now, walking, soldierRunning, detail)
		)
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
		local every = if distance > Rendering.LodFarDistance
			then 8
			elseif distance > Rendering.LodMidDistance then 3
			else 1
		if (frame + id) % every == 0 then
			updateSquad(r, r.accum, now, distance < Rendering.LodNearDistance, distance <= Rendering.LodFarDistance)
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
		local torso = CFrame.new(soldier.pos)
			* CFrame.Angles(0, soldier.yaw, 0)
			* CFrame.new(0, SoldierModels.TORSO_HEIGHT, 0)
		table.insert(out, (torso * SoldierAnimationService.GUN_AIM * SoldierAnimationService.MUZZLE).Position)
	end
	return out
end

-- Cannon shot: barrel recoil and restarts the crew's load/aim timeline
function SquadRenderer.cannonFire(squadId: number)
	local r = renders[squadId]
	if r then
		local now = os.clock()
		r.lastFire = now
		r.aimUntil = now + r.def.attackCooldown + 2
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
