-- Fait apparaître des pièces sur la carte. Les toucher donne des pièces au joueur.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Donnees = require(script.Parent.Donnees)

local dossier = Instance.new("Folder")
dossier.Name = "Pieces"
dossier.Parent = workspace

local rng = Random.new()

local rayonParams = RaycastParams.new()
rayonParams.FilterType = Enum.RaycastFilterType.Exclude

-- Cherche un point au sol au hasard dans la zone. Renvoie nil s'il n'y a pas de sol.
local function positionAleatoire(): Vector3?
	local exclus: { Instance } = { dossier }
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(exclus, player.Character)
		end
	end
	rayonParams.FilterDescendantsInstances = exclus

	for _ = 1, 10 do
		local x = rng:NextNumber(-Config.ZONE_PIECES, Config.ZONE_PIECES)
		local z = rng:NextNumber(-Config.ZONE_PIECES, Config.ZONE_PIECES)
		local resultat = workspace:Raycast(Vector3.new(x, 500, z), Vector3.new(0, -1000, 0), rayonParams)
		if resultat then
			return resultat.Position + Vector3.new(0, 3, 0)
		end
	end
	return nil
end

local function placer(piece: BasePart): boolean
	local position = positionAleatoire()
	if not position then
		return false
	end
	piece.CFrame = CFrame.new(position)
	piece.Transparency = 0
	return true
end

local function creerPiece()
	local piece = Instance.new("Part")
	piece.Name = "Piece"
	piece.Shape = Enum.PartType.Cylinder
	piece.Size = Vector3.new(0.4, 3, 3)
	piece.Color = Color3.fromRGB(255, 200, 40)
	piece.Material = Enum.Material.Neon
	piece.Anchored = true
	piece.CanCollide = false
	piece.Transparency = 1

	local active = false

	local function reapparaitre()
		while not placer(piece) do
			task.wait(Config.REAPPARITION_PIECE)
		end
		active = true
	end

	piece.Touched:Connect(function(touche)
		if not active then
			return
		end
		local personnage = touche:FindFirstAncestorOfClass("Model")
		local player = personnage and Players:GetPlayerFromCharacter(personnage)
		local humanoid = personnage and personnage:FindFirstChildOfClass("Humanoid")
		if not player or not humanoid or humanoid.Health <= 0 then
			return
		end
		if not Donnees.ajouterPieces(player, Config.VALEUR_PIECE) then
			return -- données pas encore chargées
		end
		active = false
		piece.Transparency = 1
		task.delay(Config.REAPPARITION_PIECE, reapparaitre)
	end)

	piece.Parent = dossier
	task.spawn(reapparaitre)
end

for _ = 1, Config.PIECES_SUR_LA_CARTE do
	creerPiece()
end
