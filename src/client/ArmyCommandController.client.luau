--[[
	Army orders: X Hold · C Follow · V Attack · B Rush  (hold Shift = all your squads)
	Formations: 1 Line · 2 Column · 3 Square          T / Shift+T = next / previous squad
	Also outlines the selected squad (client-side Highlight).
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local ClientActions = require(script.Parent:WaitForChild("ClientActions"))
local ClientState = require(script.Parent:WaitForChild("ClientState"))

local player = Players.LocalPlayer

local ORDER_KEYS = {
	[Enum.KeyCode.X] = "Hold",
	[Enum.KeyCode.C] = "Follow",
	[Enum.KeyCode.V] = "Attack",
	[Enum.KeyCode.B] = "Rush",
}
local FORMATION_KEYS = {
	[Enum.KeyCode.One] = "Line",
	[Enum.KeyCode.Two] = "Column",
	[Enum.KeyCode.Three] = "Square",
}

local function shiftHeld(): boolean
	return UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	local order = ORDER_KEYS[input.KeyCode]
	if order then
		ClientActions.order(order, shiftHeld())
		return
	end
	local formation = FORMATION_KEYS[input.KeyCode]
	if formation then
		ClientActions.formation(formation, shiftHeld())
		return
	end
	if input.KeyCode == Enum.KeyCode.T then
		ClientActions.cycleSquad(if shiftHeld() then -1 else 1)
	end
end)

-- Selected squad outline
local highlight = Instance.new("Highlight")
highlight.Name = "SelectedSquad"
highlight.FillTransparency = 0.85
highlight.FillColor = Color3.fromRGB(255, 230, 120)
highlight.OutlineColor = Color3.fromRGB(255, 240, 160)
highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop

local function refreshHighlight()
	local folder = Workspace:FindFirstChild("Squads")
	local model = folder and folder:FindFirstChild("Squad_" .. ClientState.selectedId())
	if model ~= highlight.Parent then
		highlight.Parent = model
		highlight.Adornee = model
	end
end

player:GetAttributeChangedSignal("SelectedSquad"):Connect(refreshHighlight)
ClientState.Changed:Connect(function(key)
	if key == "Squads" then
		refreshHighlight()
	end
end)
