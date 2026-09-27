--[[
	Army orders for the squad under your direct command (see SquadSelectionController):
	  X Hold · C Follow · V Attack · B Rush
	  X opens the Hold preview on the ground: 1 Line · 2 Column · 3 Square,
	  Left click (or Enter) confirms, right click / X / Backspace cancel.
]]

local UserInputService = game:GetService("UserInputService")

local ClientActions = require(script.Parent:WaitForChild("ClientActions"))

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
	if gameProcessed then
		return
	end
	local key = input.KeyCode
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
