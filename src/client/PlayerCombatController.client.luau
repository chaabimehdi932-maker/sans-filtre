-- Personal combat input: Left click Attack · F Block (hold) · Q Roll · H Heal · G Mount/Dismount

local UserInputService = game:GetService("UserInputService")

local ClientActions = require(script.Parent:WaitForChild("ClientActions"))
local ClientState = require(script.Parent:WaitForChild("ClientState"))

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if ClientState.view() == "Town" and input.KeyCode == Enum.KeyCode.G then
		ClientActions.toggleMount() -- ride through town if you like
		return
	end
	if ClientState.phaseName() ~= "Battle" or ClientState.view() == "Overworld" or ClientState.view() == "Town" then
		return -- battle controls only on the battlefield
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		ClientActions.attack()
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
