--[[
	SquadRenderer
	Draws every soldier on this client from the server snapshots. Since v0.16 every soldier is
	a unit of its own on the server (SoldierService): each snapshot carries every man's id,
	position, facing and flags (squad.men, 8 bytes a man). Here each man is one full-size R6
	rig (SoldierModels) that follows HIS server position smoothly, posed by
	SoldierAnimationService. A man missing from the snapshot died: he falls (ragdoll).
	  • Gun crews: the loader and gunner play their drill around the cannon locally.
	  • Performance: at most GameConfig.Rendering.MaxActiveSoldiers rigs across both teams (over
	    it, only every 2nd / 3rd… man is drawn), distance LOD on animation, and only each rig's
	    anchored root is moved (BulkMoveTo).
	  • No mounted officers and no squad health bars any more: a small name tag over your groups.
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

local soldierFromRig: (rig: any, r: any) -> any

local function newSoldier(r: any, index: number): any
	local rig
	if r.def.visual == "Cavalry" then
		rig = SoldierModels.cavalry(r.model, r.team, r.def, r.rank)
	elseif r.def.visual == "Artillery" then
		rig = SoldierModels.infantry(
			r.model,
			r.team,
			r.def,
			false,
			if index == 1 then "Rammer" elseif index == 2 then "Linstock" else nil,
			r.rank
		)
	else
		rig = SoldierModels.infantry(r.model, r.team, r.def, true, nil, r.rank)
	end
	return soldierFromRig(rig, r)
end

function soldierFromRig(rig: any, r: any): any
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
		lag = math.random() * 0.6, -- seconds this soldier trails the squad while marching
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

-- A small name tag over the group (no health bar: every man is his own unit now)
local function buildBillboard(r: any)
	local teamColor = GameConfig.Teams[r.team].color
	local gui = Instance.new("BillboardGui")
	gui.Name = "Info"
	gui.Size = UDim2.fromOffset(160, 30)
	gui.StudsOffsetWorldSpace = Vector3.new(0, if r.def.visual == "Cavalry" then 11 else 8, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 220
	gui.LightInfluence = 0
	gui.Adornee = r.disc

	local name = Instance.new("TextLabel")
	name.BackgroundTransparency = 1
	name.Size = UDim2.new(1, 0, 0, 16)
	name.Font = Enum.Font.FredokaOne
	name.TextSize = 14
	name.TextColor3 = teamColor:Lerp(Color3.new(1, 1, 1), 0.55)
	name.TextStrokeTransparency = 0.3
	name.Parent = gui
	local status = Instance.new("TextLabel")
	status.BackgroundTransparency = 1
	status.Position = UDim2.fromOffset(0, 16)
	status.Size = UDim2.new(1, 0, 0, 13)
	status.Font = Enum.Font.FredokaOne
	status.TextSize = 12
	status.TextStrokeTransparency = 0.3
	status.Parent = gui
	gui.Parent = r.disc
	r.ui = { gui = gui, name = name, status = status }
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
		rank = s.rank or 0, -- evolution tier: better uniforms and weapons
		def = def,
		model = model,
		pos = position,
		yaw = s.yaw or 0,
		snapPos = position,
		snapYaw = s.yaw or 0,
		snapTime = os.clock(),
		vel = Vector3.zero,
		formation = s.formation,
		soldiers = {}, -- drawn men, in the order they were first seen
		bySid = {}, -- server soldier id → drawn man
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
	disc.Transparency = 1 -- invisible: only carries the name tag and the charge dust
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
		r.cannon = SoldierModels.cannon(model, def.gunModel)
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

local activeRagdolls = 0

-- Fling direction: backwards (shot) with some sideways scatter; riders fall off to the side
local function ragdollVelocity(soldier: any): Vector3
	local back = Vector3.new(math.sin(soldier.yaw), 0, math.cos(soldier.yaw))
	local side = Vector3.new(back.Z, 0, -back.X)
	if soldier.kind == "Cavalry" then
		return side * (soldier.deathDir * (9 + math.random() * 5)) + back * 3 + Vector3.new(0, 7, 0)
	end
	return back * (7 + math.random() * 9) + side * ((math.random() - 0.5) * 8) + Vector3.new(0, 5, 0)
end

local function tryRagdoll(soldier: any): boolean
	if activeRagdolls >= Rendering.MaxRagdolls then
		return false
	end
	local camera = Workspace.CurrentCamera
	if camera and (camera.CFrame.Position - soldier.pos).Magnitude > Rendering.RagdollDistance then
		return false
	end
	if not SoldierModels.ragdoll(soldier.rig, ragdollVelocity(soldier)) then
		return false
	end
	activeRagdolls += 1
	return true
end

local function settleRagdoll(soldier: any)
	if soldier.ragdoll == "active" then
		soldier.ragdoll = "frozen"
		activeRagdolls -= 1
	end
end

local function updateDying(now: number, dt: number)
	for i = #dying, 1, -1 do
		local soldier = dying[i]
		local rig = soldier.rig
		if not rig.root.Parent then
			settleRagdoll(soldier)
			table.remove(dying, i) -- squad model already removed (new round)
			continue
		end
		local t = now - soldier.deathStart
		if t < 0 then
			continue
		end
		if soldier.ragdoll == nil then
			soldier.ragdoll = if tryRagdoll(soldier) then "active" else "scripted"
		end
		if soldier.ragdoll == "active" and t > Rendering.RagdollSettleTime then
			SoldierModels.freeze(rig)
			settleRagdoll(soldier)
		end
		-- scripted fall (and the horse under a ragdolled rider)
		if t < 0.8 and (soldier.ragdoll == "scripted" or soldier.kind == "Cavalry") then
			local fall = math.min(1, t / 0.7) ^ 2
			table.insert(bulkParts, rig.root)
			table.insert(bulkCFrames, SoldierAnimationService.death(soldier, soldier.deathFeet, fall, dt, now))
		elseif t > 3 then
			local fade = (t - 3) / 1
			if fade >= 1 then
				settleRagdoll(soldier)
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

-- squad.men: 8 bytes a man — u16 id · i16 x×8 · i16 z×8 · u8 facing · u8 flags
local function decodeMen(data: any): { any }
	local out = {}
	if typeof(data) ~= "buffer" then
		return out
	end
	for offset = 0, buffer.len(data) - 8, 8 do
		table.insert(out, {
			sid = buffer.readu16(data, offset),
			x = buffer.readi16(data, offset + 2) / 8,
			z = buffer.readi16(data, offset + 4) / 8,
			yaw = buffer.readu8(data, offset + 6) / 256 * math.pi * 2,
			flags = buffer.readu8(data, offset + 7),
		})
	end
	return out
end

-- `drawEvery` = 1 draws every man; 2 every other man… (performance cap)
local function applySnapshot(r: any, s: any, drawEvery: number, now: number)
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

	-- every man from the server: follow him; the ones missing died
	local artillery = r.def.visual == "Artillery"
	local seen = {}
	for _, man in decodeMen(s.men) do
		local drawn = artillery or man.sid % drawEvery == 0
		if not drawn then
			continue
		end
		seen[man.sid] = true
		local soldier = r.bySid[man.sid]
		local netPos = Vector3.new(man.x, r.snapPos.Y, man.z)
		if not soldier then
			soldier = newSoldier(r, #r.soldiers + 1)
			soldier.sid = man.sid
			soldier.pos = netPos
			soldier.netPos = netPos
			soldier.netVel = Vector3.zero
			soldier.netTime = now
			soldier.yaw = man.yaw
			r.bySid[man.sid] = soldier
			table.insert(r.soldiers, soldier)
		else
			local dtNet = now - soldier.netTime
			if dtNet > 0.05 then
				local velocity = (netPos - soldier.netPos) / dtNet
				soldier.netVel = if velocity.Magnitude < 60 then velocity else Vector3.zero
			end
			soldier.netPos = netPos
			soldier.netTime = now
		end
		soldier.netYaw = man.yaw
		if bit32.band(man.flags, 1) ~= 0 then
			soldier.meleeUntil = now + 0.7 -- swinging at his foe
		end
		if bit32.band(man.flags, 2) ~= 0 and now >= soldier.hitUntil then
			soldier.hitUntil = now + 0.35 -- just got hit
		end
		soldier.charging = bit32.band(man.flags, 4) ~= 0
	end
	local silent = r.drawEvery ~= nil and r.drawEvery ~= drawEvery -- the cap changed, nobody died
	r.drawEvery = drawEvery
	for i = #r.soldiers, 1, -1 do
		local soldier = r.soldiers[i]
		if not seen[soldier.sid] then
			table.remove(r.soldiers, i)
			r.bySid[soldier.sid] = nil
			if silent then
				soldier.rig.model:Destroy()
			else
				startDying(soldier, now)
			end
		end
	end
	if s.formation ~= r.formation then
		r.formation = s.formation
	end
	recomputeSlots(r)

	local diameter = (s.radius or 4) * 2 + 3
	r.disc.Size = Vector3.new(0.12, diameter, diameter)
	r.dust.Enabled = s.charging == true

	-- name tag: your groups (with the order), enemies only close by
	local ui = r.ui
	local mine = s.ownerId == player.UserId
	ui.gui.MaxDistance = if mine then 260 else 120
	ui.name.Text = (if s.controlled then "★ " else "")
		.. s.name
		.. (if s.commanderName then "  👤 " .. s.commanderName else "")
	local status, color = "", Color3.new(1, 1, 1)
	if r.routing then
		status, color = "ROUTING!", Color3.fromRGB(255, 90, 90)
	elseif s.charging or s.rushing then
		status, color = "CHARGE!", Color3.fromRGB(255, 170, 60)
	elseif s.forming then
		status, color = string.format("Forming %s", s.formation), Color3.fromRGB(255, 220, 120)
	elseif mine and s.controlled then
		status, color = string.upper(s.order), Color3.fromRGB(255, 225, 110)
	end
	ui.status.Text = status
	ui.status.TextColor3 = color
end

-- `instant` = remove missing squads without death animations (new round)
function SquadRenderer.sync(list: { any }, instant: boolean)
	local now = os.clock()
	-- performance cap: draw only every n-th man when the battle is too big
	local total = 0
	for _, s in list do
		total += s.soldiers or 0
	end
	local drawEvery = math.max(1, math.ceil(total / Rendering.MaxActiveSoldiers))
	local seen = {}
	for _, s in list do
		seen[s.id] = true
		local r = renders[s.id]
		if not r then
			r = createRender(s)
			renders[s.id] = r
		end
		applySnapshot(r, s, drawEvery, now)
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

--[[
	Every man follows his own server position (predicted a little ahead, smoothed), turns to
	his server facing, and his legs follow his real speed. Gun crews: the loader and gunner
	play their drill around the cannon here instead.
]]
local function updateSquad(r: any, dt: number, now: number, near: boolean, detail: boolean)
	local base = CFrame.new(r.pos) * CFrame.Angles(0, r.yaw, 0)
	local poseAlpha = 1 - math.exp(-dt * 10)
	local follow = 1 - math.exp(-dt * 12)
	local groupRunning = r.rushing or r.routing or r.charging
	local cavalry = r.def.visual == "Cavalry"
	local artillery = r.def.visual == "Artillery"

	for i, soldier in r.soldiers do
		local target = soldier.netPos + soldier.netVel * math.min(now - soldier.netTime, 0.25)
		local desiredYaw = soldier.netYaw or soldier.yaw
		if artillery and not r.routing then
			local roleSlot, roleYaw = SoldierAnimationService.crewSlot(r, i, now)
			if roleSlot then
				target = (base * CFrame.new(roleSlot.X, 0, roleSlot.Z)).Position
				desiredYaw = r.yaw + roleYaw
			end
		end
		local before = soldier.pos
		local flatX = lerp(soldier.pos.X, target.X, follow)
		local flatZ = lerp(soldier.pos.Z, target.Z, follow)
		if near and now >= soldier.nextGround then
			soldier.nextGround = now + 0.35 + math.random() * 0.3
			local hit =
				Workspace:Raycast(Vector3.new(flatX, soldier.pos.Y + 8, flatZ), Vector3.new(0, -24, 0), groundParams)
			soldier.groundY = if hit then hit.Position.Y else nil
		end
		local groundY = if near and soldier.groundY then soldier.groundY else r.pos.Y
		soldier.pos = Vector3.new(flatX, lerp(soldier.pos.Y, groundY, math.min(1, dt * 8)), flatZ)
		local velocity = Vector3.new(soldier.pos.X - before.X, 0, soldier.pos.Z - before.Z) / math.max(dt, 1e-3)
		soldier.vel = velocity
		soldier.yaw = MathUtil.normalizeAngle(soldier.yaw + MathUtil.angleDiff(soldier.yaw, desiredYaw) * poseAlpha)

		-- legs follow the real speed
		local speed = velocity.Magnitude
		local walking = speed > 0.8
		local running = speed > 13 or (groupRunning and walking) or soldier.charging
		soldier.phase += dt * speed * (if cavalry then 0.55 else 0.8)
		local amplitude = if not walking then 0 elseif running then 0.9 else 0.6
		soldier.legSwing = lerp(soldier.legSwing, amplitude, poseAlpha)

		local feet = CFrame.new(soldier.pos) * CFrame.Angles(0, soldier.yaw, 0)
		table.insert(bulkParts, soldier.rig.root)
		table.insert(
			bulkCFrames,
			SoldierAnimationService.update(r, soldier, i, feet, dt, now, walking, running, detail)
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

-- One man fired (VFX "Shots"): his shooting pose restarts; returns where the shot leaves
-- (bow hand / muzzle), or nil when this man isn't drawn
function SquadRenderer.soldierFired(squadId: number, sid: number): Vector3?
	local r = renders[squadId]
	local soldier = r and r.bySid[sid]
	if not soldier then
		return nil
	end
	local now = os.clock()
	soldier.lastFire = now
	r.aimUntil = now + r.def.attackCooldown + 2
	local torso = CFrame.new(soldier.pos)
		* CFrame.Angles(0, soldier.yaw, 0)
		* CFrame.new(0, SoldierModels.TORSO_HEIGHT, 0)
	return (torso * SoldierAnimationService.GUN_AIM * SoldierAnimationService.MUZZLE).Position
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
