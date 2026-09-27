-- Gère les achats de la boutique et applique les bonus au personnage.
-- Toutes les vérifications (prix, déjà acheté) sont faites ici, jamais sur le client.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Donnees = require(script.Parent.Donnees)

local VITESSE_DE_BASE = 16
local SAUT_DE_BASE = 50

local articles = {}
for _, article in Config.BOUTIQUE do
	articles[article.id] = article
end

local acheter = Instance.new("RemoteFunction")
acheter.Name = "Acheter"
acheter.Parent = ReplicatedStorage

local function appliquerBonus(player: Player)
	local personnage = player.Character
	local humanoid = personnage and personnage:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local vitesse, saut = VITESSE_DE_BASE, SAUT_DE_BASE
	for _, article in Config.BOUTIQUE do
		if Donnees.possede(player, article.id) then
			vitesse = math.max(vitesse, article.vitesse or 0)
			saut = math.max(saut, article.saut or 0)
		end
	end
	humanoid.UseJumpPower = true
	humanoid.WalkSpeed = vitesse
	humanoid.JumpPower = saut
end

acheter.OnServerInvoke = function(player: Player, id: unknown): (boolean, string)
	local article = if typeof(id) == "string" then articles[id] else nil
	if not article then
		return false, "Article inconnu"
	end
	if Donnees.possede(player, article.id) then
		return false, "Tu l'as déjà !"
	end
	if not Donnees.depenserPieces(player, article.prix) then
		return false, "Pas assez de pièces"
	end
	Donnees.ajouterAchat(player, article.id)
	appliquerBonus(player)
	return true, article.nom .. " acheté !"
end

local function surPersonnage(player: Player, personnage: Model)
	personnage:WaitForChild("Humanoid")
	Donnees.attendre(player)
	appliquerBonus(player)
end

local function surJoueur(player: Player)
	player.CharacterAdded:Connect(function(personnage)
		surPersonnage(player, personnage)
	end)
	if player.Character then
		task.spawn(surPersonnage, player, player.Character)
	end
end

Players.PlayerAdded:Connect(surJoueur)
for _, player in Players:GetPlayers() do
	surJoueur(player)
end
