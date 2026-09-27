--[[
	Commander animations (runs on every client, for every player's character):
	  • riding: your own walk/run animations are stopped and a seated pose is played while
	    mounted (animations played by the owning client replicate to everyone)
	  • horse gait: legs, body bounce, neck and tail driven by the horse's speed
	  • sabre swing (right arm arc), shield raise while blocking, forward roll
	Joint changes use Motor6D/Weld C0, which the default Animate script never touches.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local GameConfig = require(Modules:WaitForChild("GameConfig"))
local Remotes = require(Modules:WaitForChild("Remotes"))

local player = Players.LocalPlayer
local Hero = GameConfig.Hero

local SIT_R15 = "rbxassetid://2506281703"
local SIT_R6 = "rbxassetid://178130996"

---------------------------------------------------------------------------
-- Own character: riding pose
---------------------------------------------------------------------------

local sitTrack: AnimationTrack? = nil

local function setRiding(character: Model, riding: boolean)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	local animate = character:FindFirstChild("Animate")
	if riding then
		if animate and animate:IsA("BaseScript") then
			animate.Enabled = false -- no more walking legs on horseback
		end
		if animator and humanoid then
			for _, track in animator:GetPlayingAnimationTracks() do
				track:Stop(0.1)
			end
			if not sitTrack then
				local animation = Instance.new("Animation")
				animation.AnimationId = if humanoid.RigType == Enum.HumanoidRigType.R15 then SIT_R15 else SIT_R6
				local ok, track = pcall(function()
					return animator:LoadAnimation(animation)
				end)
				if ok and track then
					track.Priority = Enum.AnimationPriority.Action
					track.Looped = true
					track:Play(0.15)
					sitTrack = track
				end
			end
		end
	else
		if sitTrack then
			sitTrack:Stop(0.15)
			sitTrack = nil
		end
		if animate and animate:IsA("BaseScript") then
			animate.Enabled = true
		end
	end
end

local function watchCharacter(character: Model)
	sitTrack = nil
	character:WaitForChild("Humanoid", 10)
	local function refresh()
		setRiding(character, character:GetAttribute("Mounted") == true)
	end
	character:GetAttributeChangedSignal("Mounted"):Connect(refresh)
	refresh()
end

player.CharacterAdded:Connect(watchCharacter)
if player.Character then
	task.spawn(watchCharacter, player.Character)
end

---------------------------------------------------------------------------
-- Joint helpers (any character)
---------------------------------------------------------------------------

local baseC0: { [Instance]: CFrame } = {}
local tokens: { [Instance]: number } = {}

local function baseOf(joint: any): CFrame
	local base = baseC0[joint]
	if not base then
		base = joint.C0
		baseC0[joint] = base
	end
	return base
end

local function findMotor(character: Model, r15Part: string, r15Name: string, r6Part: string, r6Name: string): Motor6D?
	local holder = character:FindFirstChild(r15Part)
	local motor = holder and holder:FindFirstChild(r15Name)
	if not motor then
		holder = character:FindFirstChild(r6Part)
		motor = holder and holder:FindFirstChild(r6Name)
	end
	return if motor and motor:IsA("Motor6D") then motor else nil
end

-- Rotate a joint around its own position, using the parent part's axes (works for R6 and R15)
local function rotated(base: CFrame, rotation: CFrame): CFrame
	return CFrame.new(base.Position) * rotation * base.Rotation
end

-- Plays fn(t) → rotation on a joint for `duration` seconds, then restores it
local function playJoint(joint: Motor6D, duration: number, fn: (number) -> CFrame)
	local base = baseOf(joint)
	local token = (tokens[joint] or 0) + 1
	tokens[joint] = token
	local started = os.clock()
	local connection
	connection = RunService.RenderStepped:Connect(function()
		local t = (os.clock() - started) / duration
		if tokens[joint] ~= token or not joint.Parent then
			connection:Disconnect()
			return
		end
		if t >= 1 then
			joint.C0 = base
			connection:Disconnect()
			return
		end
		joint.C0 = fn(t)
	end)
end

local function swing(character: Model)
	local shoulder = findMotor(character, "RightUpperArm", "RightShoulder", "Torso", "Right Shoulder")
	if not shoulder then
		return
	end
	local base = baseOf(shoulder)
	playJoint(shoulder, 0.42, function(t)
		-- raise overhead, cut down, recover
		local angle
		if t < 0.3 then
			angle = 2.7 * (t / 0.3)
		elseif t < 0.6 then
			angle = 2.7 - 2.5 * ((t - 0.3) / 0.3)
		else
			angle = 0.2 * (1 - (t - 0.6) / 0.4)
		end
		return rotated(base, CFrame.fromEulerAnglesYXZ(angle, 0, math.rad(-15) * math.sin(t * math.pi)))
	end)
end

local function roll(character: Model)
	local rootJoint = findMotor(character, "LowerTorso", "Root", "HumanoidRootPart", "RootJoint")
	if not rootJoint then
		return
	end
	local base = baseOf(rootJoint)
	playJoint(rootJoint, 0.38, function(t)
		local drop = math.sin(t * math.pi) * 1.2
		return CFrame.new(0, -drop, 0) * CFrame.Angles(-t * math.pi * 2, 0, 0) * base
	end)
end

Remotes.get("VFX").OnClientEvent:Connect(function(data)
	if typeof(data) ~= "table" or typeof(data.character) ~= "Instance" or not data.character:IsA("Model") then
		return
	end
	if data.kind == "Swing" then
		swing(data.character)
	elseif data.kind == "Roll" then
		roll(data.character)
	end
end)

---------------------------------------------------------------------------
-- Continuous: shield arm + horse gait, for every character
---------------------------------------------------------------------------

local horses: { [Instance]: any } = {}
local blockBlend: { [Instance]: number } = {}
local LEG_OFFSETS = { LegFL = 0, LegFR = 0.6, LegBL = math.pi, LegBR = math.pi + 0.6 }

local function horseState(horse: Instance): any
	local state = horses[horse]
	if state then
		return state
	end
	state = { phase = math.random() * 6, welds = {} }
	for _, descendant in horse:GetDescendants() do
		if descendant:IsA("Weld") then
			state.welds[descendant.Name] = descendant
			baseOf(descendant)
		end
	end
	horses[horse] = state
	return state
end

local function animateHorse(horse: Instance, root: BasePart, dt: number, now: number)
	local state = horseState(horse)
	local velocity = root.AssemblyLinearVelocity
	local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	local amp = math.clamp(speed / Hero.MountedSpeed, 0, 1)
	state.phase += dt * (3 + 11 * amp)
	local phase = state.phase
	local welds = state.welds
	for name, offset in LEG_OFFSETS do
		local leg = welds[name]
		if leg then
			leg.C0 = baseOf(leg) * CFrame.Angles(math.sin(phase + offset) * 0.8 * amp, 0, 0)
		end
	end
	local body = welds.BodyWeld
	if body then
		body.C0 = baseOf(body)
			* CFrame.new(0, math.abs(math.sin(phase)) * 0.3 * amp, 0)
			* CFrame.Angles(math.sin(phase) * 0.05 * amp, 0, 0)
	end
	local neck = welds.NeckWeld
	if neck then
		local idle = math.sin(now * 0.9) * 0.06 * (1 - amp)
		neck.C0 = baseOf(neck) * CFrame.Angles(math.sin(phase * 2) * 0.14 * amp + idle, 0, 0)
	end
	local tail = welds.TailWeld
	if tail then
		tail.C0 = baseOf(tail) * CFrame.Angles(math.sin(phase) * 0.25 * amp, math.sin(now * 1.3) * 0.15, 0)
	end
end

RunService.RenderStepped:Connect(function(dt)
	local now = os.clock()
	for _, other in Players:GetPlayers() do
		local character = other.Character
		if not character then
			continue
		end
		local root = character:FindFirstChild("HumanoidRootPart")
		local horse = character:FindFirstChild("Horse")
		if horse and root and root:IsA("BasePart") then
			animateHorse(horse, root, dt, now)
		end

		-- raise the left arm (and shield) in front of the body while blocking
		local shoulder = findMotor(character, "LeftUpperArm", "LeftShoulder", "Torso", "Left Shoulder")
		if shoulder then
			local target = if character:GetAttribute("Blocking") == true then 1 else 0
			local blend = blockBlend[shoulder] or 0
			if blend ~= target or blend > 0 then
				blend += (target - blend) * math.min(1, dt * 14)
				if math.abs(blend - target) < 0.01 then
					blend = target
				end
				blockBlend[shoulder] = blend
				shoulder.C0 = rotated(baseOf(shoulder), CFrame.fromEulerAnglesYXZ(1.45 * blend, -0.6 * blend, 0))
			end
		end
	end
	for horse in horses do
		if not horse.Parent then
			horses[horse] = nil
		end
	end
end)
