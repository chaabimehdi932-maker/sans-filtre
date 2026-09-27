--[[
	Rush aiming. While aiming (B), a striped path runs on the ground from your squad to the
	point under your cursor (or the screen centre in mouse-look), up to Orders.RushMaxDistance.
	A prompt on the right shows  [LMB] Rush · [RMB] Cancel.
	Confirming sends the point to the server: the squad sprints there; cavalry ride straight
	through every enemy squad on the way.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local GameConfig = require(Modules:WaitForChild("GameConfig"))

local ClientActions = require(script.Parent:WaitForChild("ClientActions"))
local ClientState = require(script.Parent:WaitForChild("ClientState"))
local SquadRenderer = require(script.Parent:WaitForChild("SquadRenderer"))
local ActionPrompt = require(script.Parent:WaitForChild("UI"):WaitForChild("ActionPrompt"))

local player = Players.LocalPlayer
local MAX_DISTANCE = GameConfig.Orders.RushMaxDistance
local STRIPE_STEP = 3.2

local folder = Instance.new("Folder")
folder.Name = "RushPreview"
folder.Parent = Workspace

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.RespectCanCollide = true

local pool: { Part } = {}
local used = 0

local function piece(): Part
	used += 1
	local part = pool[used]
	if not part then
		part = Instance.new("Part")
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Material = Enum.Material.Neon
		pool[used] = part
	end
	part.Parent = folder
	return part
end

local function hideUnused()
	for i = used + 1, #pool do
		pool[i].Parent = nil
	end
end

local function groundAt(position: Vector3): number
	local hit = Workspace:Raycast(position + Vector3.new(0, 20, 0), Vector3.new(0, -60, 0), rayParams)
	return if hit then hit.Position.Y else position.Y
end

-- Prompt on the right side of the screen:  [🖱] Rush / [🖱] Cancel
local screen = player:WaitForChild("PlayerGui"):WaitForChild("MainHUD")
local prompt = ActionPrompt.new(screen, "RushPrompt", {
	{ ActionPrompt.Confirm, "Rush" },
	{ ActionPrompt.Cancel, "Cancel" },
})

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if not ClientActions.rushState().aiming then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		ClientActions.cancelRush()
	elseif not gameProcessed and (input.KeyCode == Enum.KeyCode.Backspace or input.KeyCode == Enum.KeyCode.Escape) then
		ClientActions.cancelRush()
	end
end)

local function aimPoint(from: Vector3): Vector3?
	local camera = Workspace.CurrentCamera
	if not camera then
		return nil
	end
	local screenPoint = if UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter
		then camera.ViewportSize / 2
		else UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(screenPoint.X, screenPoint.Y)
	local hit = Workspace:Raycast(ray.Origin, ray.Direction * 1000, rayParams)
	local point = if hit then hit.Position else ray.Origin + ray.Direction * MAX_DISTANCE
	local offset = Vector3.new(point.X - from.X, 0, point.Z - from.Z)
	if offset.Magnitude > MAX_DISTANCE then
		offset = offset.Unit * MAX_DISTANCE
	end
	if offset.Magnitude < 5 then
		return nil
	end
	return from + offset
end

local pulse = 0
RunService.RenderStepped:Connect(function(dt)
	used = 0
	local rush = ClientActions.rushState()
	local squad = ClientState.squadsById[ClientActions.controlledId()]
	prompt.Visible = rush.aiming and ClientState.phaseName() == "Battle"
	if not prompt.Visible or not squad then
		rush.target = nil
		hideUnused()
		return
	end
	local exclude: { Instance } = { folder }
	if player.Character then
		table.insert(exclude, player.Character)
	end
	local visuals = Workspace:FindFirstChild("SquadVisuals")
	if visuals then
		table.insert(exclude, visuals)
	end
	rayParams.FilterDescendantsInstances = exclude

	local from = SquadRenderer.getPosition(squad.id) or Vector3.new(squad.x, squad.y, squad.z)
	local target = aimPoint(from)
	rush.target = target
	if not target then
		hideUnused()
		return
	end

	pulse += dt
	local direction = Vector3.new(target.X - from.X, 0, target.Z - from.Z)
	local length = direction.Magnitude
	direction = direction.Unit
	local width = math.clamp((squad.radius or 6) * 1.6, 7, 16)
	local count = math.floor(length / STRIPE_STEP)
	local scroll = (pulse * 8) % STRIPE_STEP -- stripes flow towards the target
	for i = 1, count do
		local distance = i * STRIPE_STEP - STRIPE_STEP + scroll
		local p = from + direction * distance
		local y = groundAt(p)
		local stripe = piece()
		stripe.Color = Color3.fromRGB(235, 245, 255)
		stripe.Size = Vector3.new(width, 0.15, 1.2)
		stripe.CFrame = CFrame.lookAt(Vector3.new(p.X, y + 0.25, p.Z), Vector3.new(p.X, y + 0.25, p.Z) + direction)
		-- fade in from the squad, stronger towards the goal
		stripe.Transparency = 0.75 - 0.45 * (distance / length)
	end
	-- glowing side rails
	for _, side in { -1, 1 } do
		local right = Vector3.new(-direction.Z, 0, direction.X)
		local mid = from + direction * (length / 2) + right * side * (width / 2 + 0.4)
		local y = groundAt(mid)
		local rail = piece()
		rail.Color = Color3.fromRGB(140, 205, 255)
		rail.Size = Vector3.new(0.35, 0.15, length)
		rail.Transparency = 0.35
		rail.CFrame =
			CFrame.lookAt(Vector3.new(mid.X, y + 0.28, mid.Z), Vector3.new(mid.X, y + 0.28, mid.Z) + direction)
	end
	-- arrow head
	local tipY = groundAt(target)
	for _, side in { -1, 1 } do
		local head = piece()
		head.Color = Color3.fromRGB(255, 255, 255)
		head.Transparency = 0.2
		head.Size = Vector3.new(0.9, 0.2, width * 0.36)
		local tip = Vector3.new(target.X, tipY + 0.3, target.Z)
		local back = tip
			- direction * (width * 0.25)
			+ Vector3.new(-direction.Z, 0, direction.X) * side * (width * 0.22)
		head.CFrame = CFrame.lookAt((tip + back) / 2, tip)
	end
	hideUnused()
end)
