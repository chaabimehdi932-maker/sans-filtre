--[[
	Army orders for the squad under your direct command (see SquadSelectionController):
	  X Hold · C Follow · V Attack · B Rush
	  X opens the Hold preview on the ground: 1 Line · 2 Column · 3 Square,
	  Left click (or Enter) confirms, right click / X / Backspace cancel.
]]

local UserInputService = game:GetService("UserInputService")

local ClientActions = require(script.Parent:WaitForChild("ClientActions"))
local ClientState = require(script.Parent:WaitForChild("ClientState"))

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

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed or ClientState.phaseName() ~= "Battle" or ClientState.view() == "Overworld" then
		return -- battle controls only on the battlefield
	end
	local key = input.KeyCode
	if key == Enum.KeyCode.Tab then
		local shift = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
			or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
		ClientActions.selectSquad(if shift then "prev" else "next")
		return
	elseif key == Enum.KeyCode.T then
		ClientActions.pinNext()
		return
	end
	local order = ORDER_KEYS[key]
	if order then
		ClientActions.order(order)
		return
	end
	local hold = ClientActions.holdState()
	if not hold.active then
		return
	end
	local formation = FORMATION_KEYS[key]
	if formation then
		ClientActions.setHoldFormation(formation)
	elseif key == Enum.KeyCode.Return or key == Enum.KeyCode.KeypadEnter then
		ClientActions.confirmHold()
	elseif key == Enum.KeyCode.Backspace then
		ClientActions.cancelHold()
	end
end)
