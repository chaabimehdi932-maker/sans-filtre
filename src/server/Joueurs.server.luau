-- Charge / sauvegarde les joueurs et donne des pièces chaque minute.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Donnees = require(script.Parent.Donnees)

Players.PlayerAdded:Connect(Donnees.charger)
Players.PlayerRemoving:Connect(Donnees.liberer)

-- Joueurs déjà présents avant que le script démarre
for _, player in Players:GetPlayers() do
	task.spawn(Donnees.charger, player)
end

-- Sauvegarde de tout le monde quand le serveur s'arrête
game:BindToClose(function()
	for _, player in Players:GetPlayers() do
		Donnees.sauvegarder(player)
	end
end)

-- Pièces gagnées chaque minute
while true do
	task.wait(60)
	for _, player in Players:GetPlayers() do
		Donnees.ajouterPieces(player, Config.PIECES_PAR_MINUTE)
	end
end
