--[[
	Third-person over-the-shoulder camera.
	  • Right mouse button drag rotates the camera (standard Roblox camera).
	  • During battles your commander faces where the camera looks (easy to aim attacks).
	  • Left Alt toggles mouse-look (cursor locked in the centre, no need to hold the right button).
	Roblox's built-in Shift Lock is disabled in default.project.json because Shift is used
	for multi-selection.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local ClientState = require(script.Parent:WaitForChild("ClientState"))

local player = Players.LocalPlayer
local gameSettings = UserSettings():GetService("UserGameSettings")

local SHOULDER_OFFSET = Vector3.new(1.75, 0.6, 0)

player.CameraMaxZoomDistance = 32
player.CameraMinZoomDistance = 8 -- never first person

local mouseLook = false
local appliedLock = false

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if not gameProcessed and input.KeyCode == Enum.KeyCode.LeftAlt then
		mouseLook = not mouseLook
	end
end)

ClientState.Changed:Connect(function(key)
	if key == "Phase" and ClientState.phaseName() ~= "Battle" then
		mouseLook = false
	end
end)

RunService:BindToRenderStep("CommanderCamera", Enum.RenderPriority.Camera.Value + 1, function()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	humanoid.CameraOffset = SHOULDER_OFFSET
	local inBattle = ClientState.phaseName() == "Battle" and humanoid.Health > 0
	local lock = inBattle and mouseLook
	if lock then
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		appliedLock = true
	elseif appliedLock then
		-- release once, then leave the mouse to Roblox's camera (right-drag keeps working)
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		appliedLock = false
	end
	gameSettings.RotationType = if inBattle
		then Enum.RotationType.CameraRelative
		else Enum.RotationType.MovementRelative
end)
