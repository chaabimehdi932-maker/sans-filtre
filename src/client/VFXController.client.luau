--[[
	Client-side effects. The server only says "a volley happened here" through the VFX remote;
	all the particles, projectiles, sounds and screen shake are made locally (cheap for the server,
	one effect per squad rather than per soldier).
	Kinds: Volley · Cannon · ChargeImpact · Clash · Hit · Heal
	(Swing / Roll are animated by CharacterAnimator; soldier poses by SquadRenderer)
	Optional battle music: set GameConfig.Sounds.Music to an asset id.
]]

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local GameConfig = require(Modules:WaitForChild("GameConfig"))
local Remotes = require(Modules:WaitForChild("Remotes"))

local ClientState = require(script.Parent:WaitForChild("ClientState"))
local SquadRenderer = require(script.Parent:WaitForChild("SquadRenderer"))

local Sounds = GameConfig.Sounds
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local SPARKLES = "rbxasset://textures/particles/sparkles_main.dds"

local effectsFolder = Instance.new("Folder")
effectsFolder.Name = "ClientEffects"
effectsFolder.Parent = Workspace

local shake = 0

local function attachmentAt(position: Vector3, lifetime: number): Attachment
	local attachment = Instance.new("Attachment")
	attachment.WorldPosition = position
	attachment.Parent = Workspace.Terrain
	Debris:AddItem(attachment, lifetime)
	return attachment
end

local function playSound(id: string, position: Vector3, volume: number?, pitch: number?)
	if id == "" then
		return
	end
	local attachment = attachmentAt(position, 5)
	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.Volume = volume or 1
	sound.PlaybackSpeed = pitch or 1
	sound.RollOffMaxDistance = 400
	sound.Parent = attachment
	sound:Play()
end

local function emit(position: Vector3, props: { [string]: any }, count: number)
	local attachment = attachmentAt(position, 4)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Enabled = false
	for key, value in props do
		(emitter :: any)[key] = value
	end
	emitter.Parent = attachment
	emitter:Emit(count)
end

local function smokePuff(position: Vector3, size: number, color: Color3?)
	emit(position, {
		Texture = SMOKE,
		Color = ColorSequence.new(color or Color3.fromRGB(225, 225, 225)),
		Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, size * 0.5),
			NumberSequenceKeypoint.new(1, size * 1.6),
		}),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(1.5, 2.5),
		Speed = NumberRange.new(1, 3),
		SpreadAngle = Vector2.new(40, 40),
		Drag = 2,
	}, 3)
end

local function flash(position: Vector3, size: number)
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.one * size
	part.Material = Enum.Material.Neon
	part.Color = Color3.fromRGB(255, 200, 90)
	part.Position = position
	part.Parent = effectsFolder
	TweenService:Create(part, TweenInfo.new(0.12), { Transparency = 1, Size = Vector3.one * size * 1.6 }):Play()
	Debris:AddItem(part, 0.15)
end

local function addShake(position: Vector3, strength: number, radius: number)
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local distance = (camera.CFrame.Position - position).Magnitude
	if distance < radius then
		shake = math.max(shake, strength * (1 - distance / radius))
	end
end

local handlers = {}

function handlers.Volley(data)
	local positions = SquadRenderer.fire(data.squadId)
	for _, position in positions do
		flash(position, 0.7)
		smokePuff(position + data.direction * 1.5, 2.5)
	end
	if positions[1] then
		playSound(Sounds.Volley, positions[1], 0.8, 0.9 + math.random() * 0.2)
	end
end

function handlers.Cannon(data)
	local from, to, flight = data.from, data.to, math.max(0.1, data.flight)
	SquadRenderer.cannonFire(data.squadId)
	flash(from, 1.6)
	smokePuff(from, 5)
	playSound(Sounds.CannonFire, from, 1.2, 0.6)
	addShake(from, 0.15, 60)

	local ball = Instance.new("Part")
	ball.Anchored = true
	ball.CanCollide = false
	ball.CanQuery = false
	ball.CanTouch = false
	ball.Shape = Enum.PartType.Ball
	ball.Size = Vector3.one * 0.9
	ball.Color = Color3.fromRGB(30, 30, 30)
	ball.Material = Enum.Material.Metal
	ball.Parent = effectsFolder
	-- howitzer shells go up high and come down steeply
	local arcHeight = if data.arc
		then math.clamp((to - from).Magnitude * 0.45, 25, 140)
		else math.clamp((to - from).Magnitude * 0.15, 5, 40)
	local started = os.clock()
	local connection
	connection = RunService.RenderStepped:Connect(function()
		local t = math.min(1, (os.clock() - started) / flight)
		local position = from:Lerp(to, t) + Vector3.new(0, math.sin(t * math.pi) * arcHeight, 0)
		ball.Position = position
		if t >= 1 then
			connection:Disconnect()
			ball:Destroy()
			local explosion = Instance.new("Explosion")
			explosion.Position = to
			explosion.BlastPressure = 0
			explosion.BlastRadius = 8 -- visual size only: no pressure, no broken joints
			explosion.DestroyJointRadiusPercent = 0
			explosion.ExplosionType = Enum.ExplosionType.NoCraters
			explosion.Parent = Workspace
			smokePuff(to, 7, Color3.fromRGB(120, 105, 85))
			addShake(to, 0.9, 80)
		end
	end)
end

function handlers.ChargeImpact(data)
	SquadRenderer.melee(data.squadId)
	SquadRenderer.melee(data.targetId)
	smokePuff(data.position, 6, Color3.fromRGB(165, 135, 100))
	playSound(Sounds.ChargeImpact, data.position, 1.2, 0.7)
	addShake(data.position, 0.35, 50)
end

function handlers.Clash(data)
	SquadRenderer.melee(data.squadId)
	SquadRenderer.melee(data.targetId)
	playSound(Sounds.Hit, data.position + Vector3.new(math.random() * 4 - 2, 2, math.random() * 4 - 2), 0.5)
end

function handlers.Hit(data)
	emit(data.position, {
		Texture = SPARKLES,
		Color = ColorSequence.new(Color3.fromRGB(255, 80, 60)),
		Size = NumberSequence.new(0.6, 0),
		Lifetime = NumberRange.new(0.3, 0.5),
		Speed = NumberRange.new(8, 14),
		SpreadAngle = Vector2.new(180, 180),
	}, 10)
	playSound(Sounds.Hit, data.position, 0.8)
end

function handlers.Heal(data)
	emit(data.position, {
		Texture = SPARKLES,
		Color = ColorSequence.new(Color3.fromRGB(120, 255, 140)),
		Size = NumberSequence.new(1, 0),
		Lifetime = NumberRange.new(0.8, 1.2),
		Speed = NumberRange.new(4, 8),
		SpreadAngle = Vector2.new(180, 180),
		Acceleration = Vector3.new(0, 6, 0),
	}, 30)
end

-- Floating damage numbers where the damage landed.
-- Yellow/white = damage you dealt, red = damage your side took, bigger for charges / cannons.
local numbersFolder = Instance.new("Folder")
numbersFolder.Name = "DamageNumbers"
numbersFolder.Parent = effectsFolder
local activeNumbers = 0
function handlers.DamageNumber(data)
	local camera = Workspace.CurrentCamera
	if not camera or activeNumbers > 45 or (camera.CFrame.Position - data.position).Magnitude > 350 then
		return
	end
	activeNumbers += 1
	local attachment = attachmentAt(data.position, 1.4)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(120, 50)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 350
	gui.Adornee = attachment
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.LuckiestGuy
	label.Text = tostring(data.amount)
	local ours = data.victimTeam == "Blue"
	label.TextColor3 = if data.hero
		then Color3.fromRGB(255, 70, 70)
		elseif ours then Color3.fromRGB(255, 110, 100)
		elseif data.big then Color3.fromRGB(255, 205, 60)
		else Color3.new(1, 1, 1)
	label.TextSize = if data.big or data.hero then 34 else 26
	label.Rotation = math.random(-10, 10)
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2.5
	stroke.Parent = label
	label.Parent = gui
	gui.Parent = attachment
	local rise = Vector3.new(0, 3.5, 0)
	TweenService
		:Create(
			gui,
			TweenInfo.new(1.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ StudsOffsetWorldSpace = rise }
		)
		:Play()
	TweenService:Create(
		label,
		TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0.6),
		{ TextTransparency = 1 }
	):Play()
	TweenService:Create(
		stroke,
		TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0.6),
		{ Transparency = 1 }
	):Play()
	task.delay(1.2, function()
		activeNumbers -= 1
	end)
end

Remotes.get("VFX").OnClientEvent:Connect(function(data)
	local handler = typeof(data) == "table" and handlers[data.kind]
	if handler then
		handler(data)
	end
end)

-- Screen shake (applied after the camera scripts)
RunService:BindToRenderStep("ScreenShake", Enum.RenderPriority.Camera.Value + 2, function(dt)
	if shake <= 0.001 then
		return
	end
	local camera = Workspace.CurrentCamera
	if camera then
		local angle = math.rad(shake * 2.5)
		camera.CFrame *= CFrame.Angles((math.random() - 0.5) * angle, (math.random() - 0.5) * angle, 0)
	end
	shake = math.max(0, shake - dt * 2.5)
end)

-- Optional battle music, louder while your squads are fighting
if Sounds.Music ~= "" then
	local music = Instance.new("Sound")
	music.Name = "BattleMusic"
	music.SoundId = Sounds.Music
	music.Looped = true
	music.Volume = 0.15
	music.Parent = SoundService
	music:Play()
	task.spawn(function()
		while true do
			task.wait(0.5)
			local fighting = 0
			for _, squad in ClientState.mySquads() do
				if squad.state == "Engaging" then
					fighting += 1
				end
			end
			local target = if ClientState.phaseName() == "Battle" then 0.2 + math.min(0.4, fighting * 0.1) else 0.1
			music.Volume += (target - music.Volume) * 0.3
		end
	end)
end
