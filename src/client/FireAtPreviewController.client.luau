--[[
	Fire-at aiming (T). A red ring marks the enemy squad under your cursor (shooters will focus
	it, guns shell it); off any squad an orange ring marks the spot on the ground (guns bombard
	it, shooters take the enemy nearest to it). Thin lines run from each selected squad to the
	target. A prompt on the right shows  [LMB] Fire · [RMB] Cancel.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("GameConfig"))

local AimTargets = require(script.Parent:WaitForChild("AimTargets"))
local ClientActions = require(script.Parent:WaitForChild("ClientActions"))
local ClientState = require(script.Parent:WaitForChild("ClientState"))
local ActionPrompt = require(script.Parent:WaitForChild("UI"):WaitForChild("ActionPrompt"))

local player = Players.LocalPlayer
local MAX_DISTANCE = GameConfig.Orders.FireAtMaxDistance
local SQUAD_COLOR = Color3.fromRGB(255, 70, 60)
local GROUND_COLOR = Color3.fromRGB(255, 170, 60)

local folder = Instance.new("Folder")
folder.Name = "FireAtPreview"
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

local screen = player:WaitForChild("PlayerGui"):WaitForChild("MainHUD")
local prompt = ActionPrompt.new(screen, "FireAtPrompt", {
	{ ActionPrompt.Confirm, "Fire" },
	{ ActionPrompt.Cancel, "Cancel" },
})

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if not ClientActions.fireState().aiming then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		ClientActions.cancelFireAt()
	elseif not gameProcessed and (input.KeyCode == Enum.KeyCode.Backspace or input.KeyCode == Enum.KeyCode.Escape) then
		ClientActions.cancelFireAt()
	end
end)

local function cursorPoint(): Vector3?
	local camera = Workspace.CurrentCamera
	if not camera then
		return nil
	end
	local screenPoint = if UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter
		then camera.ViewportSize / 2
		else UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(screenPoint.X, screenPoint.Y)
	local hit = Workspace:Raycast(ray.Origin, ray.Direction * 2000, rayParams)
	return if hit then hit.Position else nil
end

-- A flat ring of short segments on the ground
local function ring(center: Vector3, radius: number, color: Color3, spin: number)
	local segments = 20
	for i = 1, segments do
		local angle = spin + i / segments * math.pi * 2
		local p = center + Vector3.new(math.cos(angle) * radius, 0.3, math.sin(angle) * radius)
		local part = piece()
		part.Color = color
		part.Transparency = 0.15
		part.Size = Vector3.new(0.5, 0.2, radius * 0.22)
		part.CFrame = CFrame.lookAt(p, p + Vector3.new(-math.sin(angle), 0, math.cos(angle)))
	end
end

local function line(from: Vector3, to: Vector3, color: Color3)
	local offset = Vector3.new(to.X - from.X, 0, to.Z - from.Z)
	if offset.Magnitude < 1 then
		return
	end
	local mid = (from + to) / 2
	local part = piece()
	part.Color = color
	part.Transparency = 0.55
	part.Size = Vector3.new(0.25, 0.15, offset.Magnitude)
	part.CFrame = CFrame.lookAt(Vector3.new(mid.X, mid.Y + 0.35, mid.Z), Vector3.new(to.X, mid.Y + 0.35, to.Z))
end

local spin = 0
RunService.RenderStepped:Connect(function(dt)
	used = 0
	local fire = ClientActions.fireState()
	prompt.Visible = fire.aiming and ClientState.phaseName() == "Battle"
	if not prompt.Visible then
		fire.target = nil
		fire.targetId = nil
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

	local point = cursorPoint()
	fire.target = point
	fire.targetId = nil
	if not point then
		hideUnused()
		return
	end
	spin += dt * 1.5
	local enemy = AimTargets.enemyAt(point)
	local center, radius, color
	if enemy then
		fire.targetId = enemy.id
		center = AimTargets.position(enemy)
		center = Vector3.new(center.X, point.Y, center.Z)
		radius = (enemy.radius or 8) + 3
		color = SQUAD_COLOR
	else
		center = point
		radius = GameConfig.Orders.FireAtPointRadius * 0.5
		color = GROUND_COLOR
	end
	ring(center, radius, color, spin)
	for _, id in ClientActions.controlledIds() do
		local squad = ClientState.squadsById[id]
		if squad then
			local from = AimTargets.position(squad)
			if Vector2.new(from.X - center.X, from.Z - center.Z).Magnitude <= MAX_DISTANCE then
				line(from, center, color)
			end
		end
	end
	hideUnused()
end)
