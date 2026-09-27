--[[
	Third-person over-the-shoulder camera.
	During battles the mouse is locked to the centre (mouse look, character faces the camera)
	like a Mount & Blade style game. Press Left Alt to free the cursor (to click HUD buttons).
	Outside battles (recruitment, summary) the cursor is always free.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local ClientState = require(script.Parent:WaitForChild("ClientState"))

local player = Players.LocalPlayer
local gameSettings = UserSettings():GetService("UserGameSettings")

local SHOULDER_OFFSET = Vector3.new(1.75, 0.6, 0)

player.CameraMaxZoomDistance = 28
player.CameraMinZoomDistance = 9 -- never first person

local cursorFreed = false

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if not gameProcessed and input.KeyCode == Enum.KeyCode.LeftAlt then
		cursorFreed = not cursorFreed
	end
end)

ClientState.Changed:Connect(function(key)
	if key == "Phase" then
		cursorFreed = false
	end
end)

RunService:BindToRenderStep("CommanderCamera", Enum.RenderPriority.Camera.Value + 1, function()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local mouseLook = ClientState.phaseName() == "Battle" and not cursorFreed and humanoid.Health > 0
	humanoid.CameraOffset = SHOULDER_OFFSET
	if mouseLook then
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		gameSettings.RotationType = Enum.RotationType.CameraRelative
	else
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		gameSettings.RotationType = Enum.RotationType.MovementRelative
	end
end)
