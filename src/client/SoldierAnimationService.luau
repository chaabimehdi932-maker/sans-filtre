--[[
	SoldierAnimationService
	Drives every soldier's animation state from what its squad is doing:
	  Idle · Marching · Running · Aiming · Firing · Reloading · MeleeSwing · HitReact · Death
	  Artillery crew roles: Loader (walks to the muzzle, rams, steps back) and Gunner (aims,
	  fires with the linstock) on a timeline derived from the squad's last shot and its
	  attack cooldown, so the crew is always in sync with the real server fire event.

	Each state first looks for an animation id in SoldierAnimationIds (played through an
	Animator on the rig); when the id is "" (default) a procedural pose is written to the joints.
	Runs on the client (joint animation doesn't replicate, and LOD depends on this player's camera).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SoldierAnimationIds = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("SoldierAnimationIds"))

local SoldierModels = require(script.Parent:WaitForChild("SoldierModels"))

local SoldierAnimationService = {}

local TORSO = SoldierModels.TORSO_HEIGHT
local HORSE = SoldierModels.HORSE_HEIGHT
local pose = SoldierModels.pose

-- Musket poses, relative to the torso centre (the musket lies along +Y from its butt)
SoldierAnimationService.GUN_AIM = CFrame.new(0.8, 0.85, 0.2) * CFrame.Angles(math.rad(-90), 0, 0)
SoldierAnimationService.MUZZLE = CFrame.new(0, 4.4, 0)
SoldierAnimationService.GUN_SHOULDER = CFrame.new(1.5, -1.5, -0.6) * CFrame.Angles(math.rad(-4), 0, 0)
local GUN_SHOULDER = SoldierAnimationService.GUN_SHOULDER
local GUN_AIM = SoldierAnimationService.GUN_AIM
local GUN_RELOAD = CFrame.new(0.4, -2.3, -1.1) * CFrame.Angles(math.rad(-10), 0, 0)
local GUN_BAYONET = CFrame.new(0.6, -0.4, 0.5) * CFrame.Angles(math.rad(-95), 0, 0)
local GUN_PORT = CFrame.new(0.3, -0.6, -0.8) * CFrame.Angles(math.rad(-45), 0, math.rad(40))
local GUN_DROPPED = CFrame.new(1.8, -2.8, -1.2) * CFrame.Angles(math.rad(-90), 0, math.rad(80))

-- Arm poses: { left, right } as Vector2(forward swing, sideways spread)
local ARMS = {
	Shoulder = { Vector2.new(0, 0), Vector2.new(0.3, 0) },
	Aim = { Vector2.new(1.5, 0.9), Vector2.new(1.45, -0.35) },
	Reload = { Vector2.new(0.6, 0.4), Vector2.new(1.0, -0.3) },
	Bayonet = { Vector2.new(1.2, 0.5), Vector2.new(0.7, -0.2) },
	Port = { Vector2.new(0.9, 0.4), Vector2.new(0.9, -0.3) },
	Dead = { Vector2.new(2.8, 0.4), Vector2.new(2.8, -0.4) },
	Flinch = { Vector2.new(0.9, 0.7), Vector2.new(0.9, -0.7) },
	CoverEars = { Vector2.new(2.6, 0.9), Vector2.new(2.6, -0.9) },
	Push = { Vector2.new(1.3, 0.3), Vector2.new(1.3, -0.3) },
	Ram = { Vector2.new(1.5, 0.35), Vector2.new(1.5, -0.1) },
	GunnerAim = { Vector2.new(0.4, 0.2), Vector2.new(1.2, -0.2) },
	GunnerFire = { Vector2.new(0.3, 0.3), Vector2.new(1.6, 0) },
	Idle = { Vector2.new(0.05, 0.05), Vector2.new(0.1, -0.05) },
}

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

---------------------------------------------------------------------------
-- Animation ids (optional) — played through an Animator on the rig
---------------------------------------------------------------------------

-- Returns true when an animation track now drives this soldier (procedural pose skipped)
local function playTrack(soldier: any, state: string): boolean
	local id = SoldierAnimationIds.get(soldier.kind, state)
	if id == "" then
		if soldier.track then
			soldier.track:Stop(0.15)
			soldier.track = nil
			soldier.trackState = nil
		end
		return false
	end
	if soldier.trackState == state then
		return true
	end
	local rig = soldier.rig
	if not rig.animator then
		local controller = Instance.new("AnimationController")
		controller.Parent = rig.model
		local animator = Instance.new("Animator")
		animator.Parent = controller
		rig.animator = animator
		rig.tracks = {}
	end
	local track = rig.tracks[state]
	if not track then
		local animation = Instance.new("Animation")
		animation.AnimationId = id
		local ok, loaded = pcall(function()
			return rig.animator:LoadAnimation(animation)
		end)
		if not ok then
			return false
		end
		track = loaded
		rig.tracks[state] = track
	end
	if soldier.track then
		soldier.track:Stop(0.15)
	end
	track:Play(0.15)
	soldier.track = track
	soldier.trackState = state
	return true
end

---------------------------------------------------------------------------
-- State selection
---------------------------------------------------------------------------

-- Artillery crew timeline, in seconds since the last shot (cd = attack cooldown)
local function crewPhase(r: any, now: number): (string, number)
	local cd = r.def.attackCooldown
	local t = now - r.lastFire
	if t < 0.8 then
		return "JustFired", t
	elseif t < cd * 0.25 then
		return "ToMuzzle", t
	elseif t < cd * 0.7 then
		return "Ramming", t
	elseif t < cd * 0.8 then
		return "StepBack", t
	end
	return "Ready", t
end

-- Where each crew role stands, relative to the squad (the cannon is 4 studs in front).
-- Returns an offset and a yaw offset, or nil for assistants (normal formation slot).
function SoldierAnimationService.crewSlot(r: any, index: number, now: number): (Vector3?, number)
	if index == 1 then -- loader
		local phase = crewPhase(r, now)
		if phase == "ToMuzzle" or phase == "Ramming" then
			return Vector3.new(-1.6, 0, -7.8), -math.pi / 2 -- beside the muzzle, facing it
		end
		return Vector3.new(-2.8, 0, -2.4), 0
	elseif index == 2 then -- gunner at the breech
		return Vector3.new(1.4, 0, -1.6), 0
	end
	return nil, 0
end

-- Each man has his own fight since v0.16: s.meleeUntil (he's swinging) and s.lastFire (his
-- own shot) come from the server's per-soldier data; r.* is the group's fallback
local function meleeUntil(_r: any, s: any): number
	return s.meleeUntil or 0
end

local function firedAt(r: any, s: any): number
	return s.lastFire or (r.lastFire + s.delay)
end

local function infantryState(r: any, s: any, now: number, walking: boolean, running: boolean): string
	if now < s.hitUntil then
		return "HitReact"
	elseif r.routing then
		return "Running"
	elseif now < meleeUntil(r, s) then
		return "MeleeSwing"
	end
	local since = now - firedAt(r, s)
	if since >= 0 and since < 0.3 then
		return "Firing"
	elseif since >= 0.3 and since < math.min(r.def.attackCooldown * 0.7, 5) then
		return "Reloading"
	elseif (r.state == "Engaging" or now < r.aimUntil) and not r.moving then
		return "Aiming"
	elseif walking then
		return if running then "Running" else "Marching"
	end
	return "Idle"
end

local function crewState(r: any, s: any, index: number, now: number, walking: boolean): string
	if now < s.hitUntil then
		return "HitReact"
	elseif r.routing then
		return "Running"
	end
	local phase = crewPhase(r, now)
	if index == 1 then
		if phase == "Ramming" and not walking then
			return "Loading"
		end
	elseif index == 2 then
		if phase == "JustFired" then
			return "GunnerFire"
		elseif phase == "Ready" and (r.state == "Engaging" or now < r.aimUntil) then
			return "GunnerAim"
		end
	elseif phase == "JustFired" then
		return "CoverEars"
	end
	if walking then
		return if r.moving then "Push" else "Marching"
	end
	return "Idle"
end

---------------------------------------------------------------------------
-- Procedural poses
---------------------------------------------------------------------------

-- arms, gun, lean for a state
local function infantryPose(state: string, r: any, s: any, now: number): ({ Vector2 }, CFrame, number)
	if state == "HitReact" then
		return ARMS.Flinch, GUN_PORT, 0.3
	elseif state == "Running" then
		return ARMS.Port, GUN_PORT, -0.15
	elseif state == "MeleeSwing" then
		local thrust = math.max(0, math.sin(now * 7 + s.phase))
		return { ARMS.Bayonet[1] + Vector2.new(thrust * 0.3, 0), ARMS.Bayonet[2] + Vector2.new(thrust * 0.35, 0) },
			GUN_BAYONET * CFrame.new(0, thrust * 1.1, 0),
			-0.1 * thrust
	elseif state == "Firing" then
		local kick = 1 - math.clamp((now - firedAt(r, s)) / 0.3, 0, 1)
		return { ARMS.Aim[1], ARMS.Aim[2] + Vector2.new(kick * 0.3, 0) },
			GUN_AIM * CFrame.new(0, -0.5 * kick, 0.15 * kick),
			0.12 * kick
	elseif state == "Reloading" then
		local ram = math.sin(now * 5 + s.phase)
		return { ARMS.Reload[1], ARMS.Reload[2] + Vector2.new(ram * 0.35, 0) }, GUN_RELOAD, 0.05
	elseif state == "Aiming" then
		return ARMS.Aim, GUN_AIM, 0
	end
	return ARMS.Shoulder, GUN_SHOULDER, 0
end

local function crewPose(state: string, _r: any, s: any, now: number): ({ Vector2 }, number)
	if state == "HitReact" then
		return ARMS.Flinch, 0.3
	elseif state == "Running" then
		return ARMS.Port, -0.15
	elseif state == "Loading" then
		local ram = math.sin(now * 4 + s.phase) -- push the rammer in and out
		return { ARMS.Ram[1] + Vector2.new(ram * 0.15, 0), ARMS.Ram[2] + Vector2.new(ram * 0.15, 0) }, -0.2 - ram * 0.1
	elseif state == "GunnerAim" then
		return ARMS.GunnerAim, -0.35 -- leaning over the breech
	elseif state == "GunnerFire" then
		return ARMS.GunnerFire, -0.1
	elseif state == "CoverEars" then
		return ARMS.CoverEars, 0.1
	elseif state == "Push" then
		return ARMS.Push, -0.2
	end
	return { ARMS.Idle[1], ARMS.Idle[2] + Vector2.new(math.sin(now + s.phase) * 0.05, 0) }, 0
end

-- Bandit swordsmen: buckler up, sword swinging overhead in the brawl
local function swordPose(state: string, r: any, s: any, now: number): ({ Vector2 }, number)
	if state == "HitReact" then
		return ARMS.Flinch, 0.3
	elseif state == "MeleeSwing" then
		local cut = (math.sin(now * 8 + s.phase) + 1) * 0.5
		return { Vector2.new(1.1, 0.4), Vector2.new(0.6 + cut * 2, -0.25) }, -0.15 * cut
	elseif state == "Running" or r.charging then
		return { Vector2.new(0.9, 0.35), Vector2.new(2.3, -0.1) }, -0.2 -- sword raised, screaming
	end
	return { Vector2.new(0.55, 0.25), Vector2.new(0.35, 0.1) }, 0
end

local function sabrePose(r: any, s: any, now: number): Vector2
	if r.routing then
		return Vector2.new(0.3, 0)
	elseif now < meleeUntil(r, s) then
		return Vector2.new(1.0 + (math.sin(now * 9 + s.phase) + 1) * 0.85, -0.2) -- slashing
	elseif r.charging or s.charging then
		return Vector2.new(1.55, 0) -- sabre pointed forward
	end
	return Vector2.new(0.35, 0.1)
end

---------------------------------------------------------------------------
-- Joints
---------------------------------------------------------------------------

local function applyInfantry(soldier: any, swing: number, armSwing: number, lean: number)
	local rig = soldier.rig
	pose(rig, "root", CFrame.Angles(lean, 0, 0))
	pose(rig, "legL", CFrame.Angles(swing, 0, 0))
	pose(rig, "legR", CFrame.Angles(-swing, 0, 0))
	pose(rig, "armL", CFrame.Angles(soldier.armL.X - armSwing, 0, soldier.armL.Y))
	pose(rig, "armR", CFrame.Angles(soldier.armR.X, 0, soldier.armR.Y))
	pose(rig, "neck", CFrame.Angles(0, soldier.look, 0))
	if rig.motors.gun then
		rig.motors.gun.Transform = soldier.gun
	end
end

local function applyCavalry(soldier: any, now: number): number
	local rig = soldier.rig
	local m = rig.motors
	local gallop = soldier.legSwing
	local phase = soldier.phase
	local bob = math.abs(math.sin(phase)) * gallop * 0.5
	m.legFL.Transform = CFrame.Angles(math.sin(phase) * gallop, 0, 0)
	m.legFR.Transform = CFrame.Angles(math.sin(phase + 0.6) * gallop, 0, 0)
	m.legBL.Transform = CFrame.Angles(math.sin(phase + math.pi) * gallop, 0, 0)
	m.legBR.Transform = CFrame.Angles(math.sin(phase + math.pi + 0.6) * gallop, 0, 0)
	m.neck.Transform =
		CFrame.Angles(math.sin(phase * 2) * gallop * 0.15 + math.sin(now * 0.8 + soldier.yawJitter * 9) * 0.05, 0, 0)
	m.tail.Transform = CFrame.Angles(math.sin(phase) * gallop * 0.3, math.sin(now * 1.3 + soldier.delay * 20) * 0.2, 0)
	m.rider.Transform = CFrame.new(0, -bob * 0.4, 0) * CFrame.Angles(-gallop * 0.12, 0, 0)
	pose(rig, "armR", CFrame.Angles(soldier.armR.X, 0, soldier.armR.Y))
	return bob
end

function SoldierAnimationService.setupRider(soldier: any)
	-- the rider's legs straddle the horse, left hand holds the reins (set once)
	pose(soldier.rig, "legL", CFrame.Angles(0.55, 0, -0.6))
	pose(soldier.rig, "legR", CFrame.Angles(0.55, 0, 0.6))
	pose(soldier.rig, "armL", CFrame.Angles(0.8, 0, 0.3))
	pose(soldier.rig, "neck", CFrame.new())
end

--[[
	Animate one soldier. `detail` = false for far LOD (no limb animation, root only).
	Returns the CFrame for the rig's anchored root.
]]
function SoldierAnimationService.update(
	r: any,
	soldier: any,
	index: number,
	feet: CFrame,
	dt: number,
	now: number,
	walking: boolean,
	running: boolean,
	detail: boolean
): CFrame
	local poseAlpha = 1 - math.exp(-dt * 10)
	local kind = soldier.kind

	if kind == "Cavalry" then
		local state = if r.routing
			then "Running"
			elseif now < meleeUntil(r, soldier) then "MeleeSwing"
			elseif walking then "Running"
			else "Idle"
		soldier.state = state
		if not detail then
			return feet * CFrame.new(0, HORSE, 0)
		end
		soldier.armR = soldier.armR:Lerp(sabrePose(r, soldier, now), poseAlpha)
		local bob = applyCavalry(soldier, now)
		return feet
			* CFrame.new(0, HORSE + bob, 0)
			* CFrame.Angles(math.sin(soldier.phase) * soldier.legSwing * 0.06, 0, 0)
	end

	local state = if kind == "Crew"
		then crewState(r, soldier, index, now, walking)
		else infantryState(r, soldier, now, walking, running)
	soldier.state = state
	local swing = math.sin(soldier.phase) * soldier.legSwing
	local bob = math.abs(math.cos(soldier.phase)) * soldier.legSwing * 0.25
	local root = feet * CFrame.new(0, TORSO + bob, 0)
	if not detail or playTrack(soldier, state) then
		return root
	end

	local arms, gun, lean
	if kind == "Crew" then
		arms, lean = crewPose(state, r, soldier, now)
		gun = GUN_SHOULDER
	elseif kind == "Swordsman" then
		arms, lean = swordPose(state, r, soldier, now)
		gun = GUN_SHOULDER
	else
		arms, gun, lean = infantryPose(state, r, soldier, now)
	end
	soldier.armL = soldier.armL:Lerp(arms[1], poseAlpha)
	soldier.armR = soldier.armR:Lerp(arms[2], poseAlpha)
	soldier.gun = soldier.gun:Lerp(gun, poseAlpha)
	soldier.lean = lerp(soldier.lean or 0, lean, poseAlpha)
	-- idle soldiers glance around now and then
	soldier.look =
		lerp(soldier.look, if walking then 0 else math.sin(now * 0.3 + soldier.phase) * 0.35, poseAlpha * 0.3)
	local armSwing = if state == "Marching" or state == "Idle" then swing * 0.8 else 0
	applyInfantry(soldier, swing, armSwing, soldier.lean)
	return root
end

-- Death: fall around the feet (infantry backwards/forwards, horses sideways). t in [0, 1].
function SoldierAnimationService.death(soldier: any, deathFeet: CFrame, fall: number, dt: number, now: number): CFrame
	local alpha = math.min(1, dt * 8)
	if soldier.kind == "Cavalry" then
		soldier.legSwing = lerp(soldier.legSwing, 0, alpha)
		soldier.armR = soldier.armR:Lerp(Vector2.new(0.2, 0), alpha)
		applyCavalry(soldier, now)
		return deathFeet * CFrame.Angles(0, 0, fall * math.rad(80) * soldier.deathDir) * CFrame.new(0, HORSE, 0)
	end
	if not playTrack(soldier, "Death") then
		soldier.armL = soldier.armL:Lerp(ARMS.Dead[1], alpha)
		soldier.armR = soldier.armR:Lerp(ARMS.Dead[2], alpha)
		soldier.gun = soldier.gun:Lerp(GUN_DROPPED, alpha)
		applyInfantry(soldier, 0.3 * fall, 0, 0)
	end
	return deathFeet * CFrame.Angles(fall * math.rad(84) * soldier.deathDir, 0, 0) * CFrame.new(0, TORSO, 0)
end

return SoldierAnimationService
