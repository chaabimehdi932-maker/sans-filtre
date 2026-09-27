--[[
	ClientActions
	Every player action in one place, shared by the keyboard controllers and the HUD buttons.
	Local cooldowns are only for display/prediction: the server re-validates everything.
]]

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local GameConfig = require(Modules:WaitForChild("GameConfig"))
local Remotes = require(Modules:WaitForChild("Remotes"))

local Hero = GameConfig.Hero
local player = Players.LocalPlayer

local combatRemote = Remotes.get("CombatAction")
local orderRemote = Remotes.get("OrderUnits")
local formationRemote = Remotes.get("SetFormation")
local cycleRemote = Remotes.get("CycleSquad")

local changed = Instance.new("BindableEvent")

local ClientActions: { [string]: any } = {}
ClientActions.Changed = changed.Event -- (what, value?)
ClientActions.blocking = false

local readyAt: { [string]: number } = {}
local durations: { [string]: number } = {}

local function startCooldown(action: string, duration: number)
	readyAt[action] = os.clock() + duration
	durations[action] = duration
	changed:Fire(action)
end

-- 0 = ready, 1 = just used
function ClientActions.cooldownFraction(action: string): number
	local at = readyAt[action]
	if not at then
		return 0
	end
	local remaining = at - os.clock()
	if remaining <= 0 then
		return 0
	end
	return remaining / (durations[action] or 1)
end

local function ready(action: string): boolean
	return ClientActions.cooldownFraction(action) <= 0
end

function ClientActions.isMounted(): boolean
	local character = player.Character
	return character ~= nil and character:GetAttribute("Mounted") == true
end

local function dash()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or not root:IsA("BasePart") then
		return
	end
	local direction = humanoid.MoveDirection
	if direction.Magnitude < 0.1 then
		direction = root.CFrame.LookVector
	end
	direction = Vector3.new(direction.X, 0, direction.Z)
	if direction.Magnitude < 0.01 then
		return
	end
	local attachment = Instance.new("Attachment")
	attachment.Parent = root
	local velocity = Instance.new("LinearVelocity")
	velocity.Attachment0 = attachment
	velocity.RelativeTo = Enum.ActuatorRelativeTo.World
	velocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	velocity.ForceLimitMode = Enum.ForceLimitMode.PerAxis
	velocity.MaxAxesForce = Vector3.new(200000, 0, 200000)
	velocity.VectorVelocity = direction.Unit * Hero.RollSpeed
	velocity.Parent = root
	Debris:AddItem(velocity, Hero.RollDuration)
	Debris:AddItem(attachment, Hero.RollDuration)
end

function ClientActions.attack()
	if ClientActions.blocking or not ready("Attack") then
		return
	end
	startCooldown("Attack", if ClientActions.isMounted() then Hero.MountedAttackCooldown else Hero.AttackCooldown)
	combatRemote:FireServer("Attack")
end

function ClientActions.setBlock(on: boolean)
	if ClientActions.blocking == on then
		return
	end
	ClientActions.blocking = on
	combatRemote:FireServer(if on then "BlockStart" else "BlockEnd")
	changed:Fire("Block", on)
end

function ClientActions.roll()
	if ClientActions.isMounted() or not ready("Roll") then
		return
	end
	startCooldown("Roll", Hero.RollCooldown)
	combatRemote:FireServer("Roll")
	dash()
end

function ClientActions.heal()
	if not ready("Heal") then
		return
	end
	startCooldown("Heal", Hero.HealCooldown)
	combatRemote:FireServer("Heal")
end

function ClientActions.toggleMount()
	if not ready("Mount") then
		return
	end
	startCooldown("Mount", Hero.MountCooldown)
	combatRemote:FireServer("Mount")
end

function ClientActions.order(order: string, all: boolean?)
	orderRemote:FireServer(order, all == true)
	changed:Fire("Order", order)
end

function ClientActions.formation(formation: string, all: boolean?)
	formationRemote:FireServer(formation, all == true)
	changed:Fire("Formation", formation)
end

function ClientActions.cycleSquad(direction: number)
	cycleRemote:FireServer(direction)
end

function ClientActions.selectSquad(squadId: number)
	cycleRemote:FireServer(0, squadId)
end

-- Server corrections: a rejected action tells us how long the real cooldown still is
Remotes.get("CombatFeedback").OnClientEvent:Connect(function(action, ok, remaining)
	if ok then
		return
	end
	if typeof(remaining) == "number" and remaining > 0 then
		startCooldown(action, remaining)
	else
		readyAt[action] = nil
		changed:Fire(action)
	end
end)

player.CharacterAdded:Connect(function()
	ClientActions.blocking = false
	changed:Fire("Block", false)
end)

return ClientActions
