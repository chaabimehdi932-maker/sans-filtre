-- Personal combat input: Left click Attack · F Block (hold) · Q Roll · H Heal · G Mount/Dismount

local UserInputService = game:GetService("UserInputService")

local ClientActions = require(script.Parent:WaitForChild("ClientActions"))

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		-- Ctrl + left mouse is box selection (ArmyCommandController)
		if
			not UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
			and not UserInputService:IsKeyDown(Enum.KeyCode.RightControl)
		then
			ClientActions.attack()
		end
	elseif input.KeyCode == Enum.KeyCode.F then
		ClientActions.setBlock(true)
	elseif input.KeyCode == Enum.KeyCode.Q then
		ClientActions.roll()
	elseif input.KeyCode == Enum.KeyCode.H then
		ClientActions.heal()
	elseif input.KeyCode == Enum.KeyCode.G then
		ClientActions.toggleMount()
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.F then
		ClientActions.setBlock(false)
	end
end)
