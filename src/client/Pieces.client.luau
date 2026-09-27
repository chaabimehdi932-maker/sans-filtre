-- Fait tourner les pièces sur elles-mêmes (seulement à l'écran du joueur, pas sur le serveur).

local RunService = game:GetService("RunService")

local dossier = workspace:WaitForChild("Pieces")

local angle = 0
RunService.RenderStepped:Connect(function(dt)
	angle += dt * 2
	for _, piece in dossier:GetChildren() do
		if piece:IsA("BasePart") then
			piece.CFrame = CFrame.new(piece.Position) * CFrame.Angles(0, angle, 0)
		end
	end
end)
