--[[
	Army controls
	  X Hold · C Follow · V Attack · B Rush        → every selected squad
	  after X: 1 Line · 2 Column · 3 Square        (formation prompt, a few seconds)
	  1-9 select squad n · Shift+number add/remove · 0 or ` select all · T next squad
	  Ctrl + drag left mouse: box-select your squads (Ctrl + click = pick one)
	Selected squads are outlined (client-side Highlights).
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local ClientActions = require(script.Parent:WaitForChild("ClientActions"))
local ClientState = require(script.Parent:WaitForChild("ClientState"))
local SquadRenderer = require(script.Parent:WaitForChild("SquadRenderer"))

local player = Players.LocalPlayer

local ORDER_KEYS = {
	[Enum.KeyCode.X] = "Hold",
	[Enum.KeyCode.C] = "Follow",
	[Enum.KeyCode.V] = "Attack",
	[Enum.KeyCode.B] = "Rush",
}
local NUMBER_KEYS = {
	[Enum.KeyCode.One] = 1,
	[Enum.KeyCode.Two] = 2,
	[Enum.KeyCode.Three] = 3,
	[Enum.KeyCode.Four] = 4,
	[Enum.KeyCode.Five] = 5,
	[Enum.KeyCode.Six] = 6,
	[Enum.KeyCode.Seven] = 7,
	[Enum.KeyCode.Eight] = 8,
	[Enum.KeyCode.Nine] = 9,
}
local FORMATIONS = { "Line", "Column", "Square" }

local function shiftHeld(): boolean
	return UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
end

local function ctrlHeld(): boolean
	return UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)
end

local function mySquadIds(): { number }
	local ids = {}
	for _, squad in ClientState.mySquads() do
		table.insert(ids, squad.id)
	end
	return ids
end

local function selectIndex(index: number, additive: boolean)
	local id = mySquadIds()[index]
	if not id then
		return
	end
	if additive then
		ClientActions.toggleSelected(id)
	else
		ClientActions.setSelection({ id })
	end
end

local function cycle(direction: number)
	local ids = mySquadIds()
	if #ids == 0 then
		return
	end
	local current = ClientActions.selectedIds()[1]
	local index = table.find(ids, current) or 0
	ClientActions.setSelection({ ids[(index - 1 + direction) % #ids + 1] })
end

---------------------------------------------------------------------------
-- Box selection
---------------------------------------------------------------------------

local hud = player:WaitForChild("PlayerGui"):WaitForChild("MainHUD")
local box = Instance.new("Frame")
box.Name = "SelectionBox"
box.BackgroundColor3 = Color3.fromRGB(255, 225, 120)
box.BackgroundTransparency = 0.85
box.BorderSizePixel = 0
box.Visible = false
box.ZIndex = 50
local boxStroke = Instance.new("UIStroke")
boxStroke.Color = Color3.fromRGB(255, 235, 150)
boxStroke.Thickness = 1.5
boxStroke.Parent = box
box.Parent = hud

local dragStart: Vector2? = nil

local function updateBox(current: Vector2)
	local start = dragStart :: Vector2
	local minX, minY = math.min(start.X, current.X), math.min(start.Y, current.Y)
	box.Position = UDim2.fromOffset(minX, minY)
	box.Size = UDim2.fromOffset(math.abs(current.X - start.X), math.abs(current.Y - start.Y))
	box.Visible = true
end

local function finishBox(current: Vector2)
	local start = dragStart :: Vector2
	dragStart = nil
	box.Visible = false
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local minX, maxX = math.min(start.X, current.X), math.max(start.X, current.X)
	local minY, maxY = math.min(start.Y, current.Y), math.max(start.Y, current.Y)
	local isClick = maxX - minX < 8 and maxY - minY < 8
	local picked = {}
	local closest, closestDistance = nil, 90
	for _, squad in ClientState.mySquads() do
		local world = SquadRenderer.getPosition(squad.id) or Vector3.new(squad.x, squad.y, squad.z)
		local screen, onScreen = camera:WorldToViewportPoint(world + Vector3.new(0, 2, 0))
		if onScreen then
			if isClick then
				local distance = (Vector2.new(screen.X, screen.Y) - current).Magnitude
				if distance < closestDistance then
					closest, closestDistance = squad.id, distance
				end
			elseif screen.X >= minX and screen.X <= maxX and screen.Y >= minY and screen.Y <= maxY then
				table.insert(picked, squad.id)
			end
		end
	end
	if isClick and closest then
		picked = { closest }
	end
	if shiftHeld() then
		for _, id in ClientActions.selectedIds() do
			if not table.find(picked, id) then
				table.insert(picked, id)
			end
		end
	end
	if #picked > 0 or not shiftHeld() then
		ClientActions.setSelection(picked)
	end
end

---------------------------------------------------------------------------
-- Input
---------------------------------------------------------------------------

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1 and ctrlHeld() then
		dragStart = UserInputService:GetMouseLocation()
		return
	end
	local key = input.KeyCode
	local order = ORDER_KEYS[key]
	if order then
		ClientActions.order(order)
		return
	end
	local number = NUMBER_KEYS[key]
	if number then
		if ClientActions.formationPrompt() > 0 and number <= 3 then
			ClientActions.formation(FORMATIONS[number])
		else
			selectIndex(number, shiftHeld())
		end
		return
	end
	if key == Enum.KeyCode.Zero or key == Enum.KeyCode.Backquote then
		ClientActions.setSelection(mySquadIds())
	elseif key == Enum.KeyCode.T then
		cycle(if shiftHeld() then -1 else 1)
	end
end)

UserInputService.InputChanged:Connect(function(input)
	if dragStart and input.UserInputType == Enum.UserInputType.MouseMovement then
		updateBox(UserInputService:GetMouseLocation())
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if dragStart and input.UserInputType == Enum.UserInputType.MouseButton1 then
		finishBox(UserInputService:GetMouseLocation())
	end
end)

---------------------------------------------------------------------------
-- Selection outlines
---------------------------------------------------------------------------

local highlights: { [number]: Highlight } = {}

local function refreshHighlights()
	local wanted = {}
	for _, id in ClientActions.selectedIds() do
		local model = SquadRenderer.getModel(id)
		if model then
			wanted[id] = true
			local highlight = highlights[id]
			if not highlight then
				highlight = Instance.new("Highlight")
				highlight.FillColor = Color3.fromRGB(255, 225, 110)
				highlight.FillTransparency = 0.8
				highlight.OutlineColor = Color3.fromRGB(255, 240, 160)
				highlight.OutlineTransparency = 0.1
				highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
				highlights[id] = highlight
			end
			if highlight.Parent ~= model then
				highlight.Adornee = model
				highlight.Parent = model
			end
		end
	end
	for id, highlight in highlights do
		if not wanted[id] then
			highlight:Destroy()
			highlights[id] = nil
		end
	end
end

ClientActions.Changed:Connect(function(what)
	if what == "Selection" then
		refreshHighlights()
	end
end)
ClientState.Changed:Connect(function(key)
	if key == "Squads" then
		refreshHighlights()
	end
end)
