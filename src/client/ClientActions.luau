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
local selectRemote = Remotes.get("SelectSquad")

local changed = Instance.new("BindableEvent")

local ClientActions: { [string]: any } = {}
ClientActions.Changed = changed.Event -- (what, value?)
ClientActions.blocking = false

local hold = { active = false, formation = "Line" }
local rush = { aiming = false, target = nil :: Vector3?, targetId = nil :: number? }
local fire = { aiming = false, target = nil :: Vector3?, targetId = nil :: number? }

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

function ClientActions.cooldownRemaining(action: string): number
	local at = readyAt[action]
	return if at then math.max(0, at - os.clock()) else 0
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
	if hold.active then
		ClientActions.confirmHold() -- left click places the Hold preview
		return
	end
	if ClientActions.rushState().aiming then
		ClientActions.confirmRush() -- left click confirms the rush instead of swinging
		return
	end
	if fire.aiming then
		ClientActions.confirmFireAt() -- left click picks the target
		return
	end
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

---------------------------------------------------------------------------
-- Army: orders, formations, selection
---------------------------------------------------------------------------

-- You command every squad of your army (companion-led squads fight on their own). Orders go
-- to the SELECTED squads. Player attributes: "ControlledSquad" (first selected id),
-- "ControlledSquads" ("3,5,8" = selection) and "CommandedSquads" (all squads you command).
function ClientActions.controlledId(): number
	local id = player:GetAttribute("ControlledSquad")
	return if typeof(id) == "number" then id else 0
end

local function parseIds(attribute: string): { number }
	local ids = {}
	local raw = player:GetAttribute(attribute)
	if typeof(raw) == "string" then
		for id in string.gmatch(raw, "%d+") do
			table.insert(ids, tonumber(id) :: number)
		end
	end
	return ids
end

function ClientActions.controlledIds(): { number }
	return parseIds("ControlledSquads")
end

-- every squad you command (number keys pick among these, in this order)
function ClientActions.commandedIds(): { number }
	return parseIds("CommandedSquads")
end

function ClientActions.isControlled(id: number): boolean
	return table.find(ClientActions.controlledIds(), id) ~= nil
end

for _, attribute in { "ControlledSquad", "ControlledSquads", "CommandedSquads" } do
	player:GetAttributeChangedSignal(attribute):Connect(function()
		changed:Fire("Controlled")
	end)
end

-- Select only this squad (id), cycle ("next" / "prev") or everything ("all")
function ClientActions.selectSquad(which: number | string)
	selectRemote:FireServer(which)
end

-- Add / remove a squad to the selection (Shift + click a card / Shift + number)
function ClientActions.togglePin(id: number)
	selectRemote:FireServer({ pin = id })
end

---------------------------------------------------------------------------
-- Campaign (overworld) actions — validated by CampaignService
---------------------------------------------------------------------------

local campaignRemote = Remotes.get("CampaignAction")

function ClientActions.campaign(action: string, arg: any?)
	campaignRemote:FireServer(action, arg)
end

---------------------------------------------------------------------------
-- Hold mode: X shows where the selected squads will stand (HoldPreviewController),
-- 1/2/3 pick the formation, left click (or Enter) confirms, right click / X / Backspace cancel.
---------------------------------------------------------------------------

function ClientActions.holdState(): any
	return hold
end

-- Where the Hold preview is anchored: in front of the commander, facing where he looks
function ClientActions.holdAnchor(): (Vector3?, number)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return nil, 0
	end
	local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	if look.Magnitude < 0.01 then
		look = Vector3.new(0, 0, -1)
	end
	look = look.Unit
	local yaw = math.atan2(-look.X, -look.Z)
	return root.Position + look * GameConfig.Orders.HoldAhead, yaw
end

function ClientActions.beginHold(formation: string?)
	hold.active = true
	if formation then
		hold.formation = formation
	end
	changed:Fire("Hold", true)
end

function ClientActions.setHoldFormation(formation: string)
	hold.formation = formation
	if not hold.active then
		ClientActions.beginHold()
	end
	changed:Fire("HoldFormation", formation)
end

function ClientActions.cancelHold()
	if hold.active then
		hold.active = false
		changed:Fire("Hold", false)
	end
end

function ClientActions.confirmHold()
	local anchor, yaw = ClientActions.holdAnchor()
	hold.active = false
	changed:Fire("Hold", false)
	if anchor then
		orderRemote:FireServer("Hold", { x = anchor.X, z = anchor.Z, yaw = yaw, formation = hold.formation })
	else
		orderRemote:FireServer("Hold")
	end
	changed:Fire("Order", "Hold")
end

---------------------------------------------------------------------------
-- Rush aiming: B shows a path on the ground towards where you aim (RushPreviewController),
-- left click / B confirms, right click / Backspace cancels.
---------------------------------------------------------------------------

function ClientActions.rushState(): any
	return rush
end

function ClientActions.beginRush()
	if not ready("Rush") then
		changed:Fire("RushCooldown")
		return
	end
	ClientActions.cancelHold()
	ClientActions.cancelFireAt()
	rush.aiming = true
	changed:Fire("Rush", true)
end

function ClientActions.cancelRush()
	if rush.aiming then
		rush.aiming = false
		changed:Fire("Rush", false)
	end
end

function ClientActions.confirmRush()
	if not rush.aiming then
		return
	end
	rush.aiming = false
	changed:Fire("Rush", false)
	startCooldown("Rush", GameConfig.Orders.RushCooldown)
	local target = rush.target
	if target then
		-- aimed at an enemy squad: the squads charge it wherever it goes
		orderRemote:FireServer("Rush", { x = target.X, z = target.Z, targetId = rush.targetId })
	else
		orderRemote:FireServer("Rush")
	end
	changed:Fire("Order", "Rush")
end

---------------------------------------------------------------------------
-- Fire-at aiming: T, then left click an enemy squad (shooters focus it, guns shell it) or a
-- spot on the ground (guns bombard it, shooters take the enemy nearest to it).
-- Right click / Backspace cancels.
---------------------------------------------------------------------------

function ClientActions.fireState(): any
	return fire
end

function ClientActions.beginFireAt()
	ClientActions.cancelHold()
	ClientActions.cancelRush()
	fire.aiming = true
	changed:Fire("FireAt", true)
end

function ClientActions.cancelFireAt()
	if fire.aiming then
		fire.aiming = false
		changed:Fire("FireAt", false)
	end
end

function ClientActions.confirmFireAt()
	if not fire.aiming then
		return
	end
	fire.aiming = false
	changed:Fire("FireAt", false)
	local target = fire.target
	if not target then
		return
	end
	orderRemote:FireServer("FireAt", { x = target.X, z = target.Z, targetId = fire.targetId })
	changed:Fire("Order", "FireAt")
end

function ClientActions.order(order: string)
	if order == "Hold" then
		ClientActions.cancelRush()
		if hold.active then
			ClientActions.cancelHold() -- X again cancels, left click confirms
		else
			ClientActions.beginHold()
		end
		return
	elseif order == "Rush" then
		if rush.aiming then
			ClientActions.confirmRush()
		else
			ClientActions.beginRush()
		end
		return
	elseif order == "FireAt" then
		if fire.aiming then
			ClientActions.cancelFireAt() -- T again cancels, left click confirms
		else
			ClientActions.beginFireAt()
		end
		return
	end
	ClientActions.cancelHold()
	ClientActions.cancelRush()
	ClientActions.cancelFireAt()
	orderRemote:FireServer(order)
	changed:Fire("Order", order)
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
