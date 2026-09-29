--[[
	Army orders for the squad under your direct command (see SquadSelectionController):
	  X Hold · C Follow · V Attack · B Rush (aim, click: 2× sprint; on an enemy squad: charge it)
	  T Fire at (click an enemy squad: shooters focus it · click the ground: guns bombard it)
	  X opens the Hold preview on the ground: 1 Line · 2 Column · 3 Square,
	  Left click (or Enter) confirms, right click / X / Backspace cancel.
	Selection (orders go to the selected squads; you command your whole army):
	  1-9 select that squad · Shift+1-9 add/remove it · 0 select all · Tab / Shift+Tab cycle.
	  While the Hold preview is open, 1/2/3 pick its formation instead.
]]

local UserInputService = game:GetService("UserInputService")

local ClientActions = require(script.Parent:WaitForChild("ClientActions"))
local ClientState = require(script.Parent:WaitForChild("ClientState"))

local ORDER_KEYS = {
	[Enum.KeyCode.X] = "Hold",
	[Enum.KeyCode.C] = "Follow",
	[Enum.KeyCode.V] = "Attack",
	[Enum.KeyCode.B] = "Rush",
	[Enum.KeyCode.T] = "FireAt",
}
local SQUAD_KEYS = {
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
	local shift = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
		or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
	if key == Enum.KeyCode.Tab then
		ClientActions.selectSquad(if shift then "prev" else "next")
		return
	end
	if not ClientActions.holdState().active then
		if key == Enum.KeyCode.Zero then
			ClientActions.selectSquad("all")
			return
		end
		local number = SQUAD_KEYS[key]
		if number then
			local id = ClientActions.commandedIds()[number]
			if id then
				if shift then
					ClientActions.togglePin(id)
				else
					ClientActions.selectSquad(id)
				end
			end
			return
		end
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
