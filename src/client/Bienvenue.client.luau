-- Affiche un message de bienvenue en haut de l'écran pendant 5 secondes.

local Players = game:GetService("Players")

local player = Players.LocalPlayer

local gui = Instance.new("ScreenGui")
gui.Name = "Bienvenue"
gui.ResetOnSpawn = false

local label = Instance.new("TextLabel")
label.Size = UDim2.fromScale(0.4, 0.08)
label.Position = UDim2.fromScale(0.3, 0.05)
label.BackgroundTransparency = 0.3
label.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
label.TextColor3 = Color3.new(1, 1, 1)
label.TextScaled = true
label.Font = Enum.Font.GothamBold
label.Text = "Bienvenue, " .. player.DisplayName .. " !"
label.Parent = gui

gui.Parent = player:WaitForChild("PlayerGui")

task.delay(5, function()
	gui:Destroy()
end)
