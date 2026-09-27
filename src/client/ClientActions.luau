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
local selectRemote = Remotes.get("SelectSquads")

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

local selection: { [number]: boolean } = {}

local function parseSelection(): { [number]: boolean }
	local set = {}
	local text = player:GetAttribute("SelectedSquads")
	if typeof(text) == "string" then
		for id in string.gmatch(text, "%d+") do
			set[tonumber(id) :: number] = true
		end
	end
	return set
end
selection = parseSelection()
-- the server echoes the (validated) selection back through this attribute
player:GetAttributeChangedSignal("SelectedSquads"):Connect(function()
	selection = parseSelection()
	changed:Fire("Selection")
end)

function ClientActions.isSelected(squadId: number): boolean
	return selection[squadId] == true
end

function ClientActions.selectedIds(): { number }
	local ids = {}
	for id in selection do
		table.insert(ids, id)
	end
	table.sort(ids)
	return ids
end

function ClientActions.setSelection(ids: { number })
	local set = {}
	for _, id in ids do
		set[id] = true
	end
	selection = set -- optimistic: the HUD updates right away
	changed:Fire("Selection")
	selectRemote:FireServer(ids)
end

function ClientActions.toggleSelected(squadId: number)
	local ids = {}
	for id in selection do
		if id ~= squadId then
			table.insert(ids, id)
		end
	end
	if not selection[squadId] then
		table.insert(ids, squadId)
	end
	ClientActions.setSelection(ids)
end

---------------------------------------------------------------------------
-- Hold mode: X shows where the selected squads will stand (HoldPreviewController),
-- 1/2/3 pick the formation, X again (or Enter) confirms, Backspace cancels.
---------------------------------------------------------------------------

local hold = { active = false, formation = "Line" }

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

function ClientActions.order(order: string)
	if order == "Hold" then
		if hold.active then
			ClientActions.confirmHold()
		else
			ClientActions.beginHold()
		end
		return
	end
	ClientActions.cancelHold()
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
