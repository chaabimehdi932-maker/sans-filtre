-- Gère les données de chaque joueur (pièces + achats) et leur sauvegarde.
-- Les autres scripts serveur passent par ce module au lieu de toucher aux leaderstats.
-- Pour que la sauvegarde marche dans Studio : Game Settings > Security >
-- activer "Enable Studio Access to API Services".

local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local store = DataStoreService:GetDataStore(Config.NOM_DATASTORE)

type Profil = {
	Pieces: number,
	Achats: { [string]: boolean },
}

local Donnees = {}

local profils: { [Player]: Profil } = {}
-- Joueurs dont le chargement a échoué : on ne sauvegarde pas pour ne pas écraser leurs vraies données
local nePasSauvegarder: { [Player]: boolean } = {}

local function cle(player: Player): string
	return "joueur_" .. player.UserId
end

local function lire(player: Player): (Profil, boolean)
	local ok, valeur = pcall(function()
		return store:GetAsync(cle(player))
	end)
	if not ok then
		warn("Chargement impossible pour", player.Name, valeur)
		return { Pieces = Config.PIECES_DE_DEPART, Achats = {} }, false
	end
	if typeof(valeur) == "number" then
		-- Ancien format : seulement le nombre de pièces
		return { Pieces = valeur, Achats = {} }, true
	end
	if typeof(valeur) == "table" then
		local profil: Profil = {
			Pieces = tonumber(valeur.Pieces) or Config.PIECES_DE_DEPART,
			Achats = if typeof(valeur.Achats) == "table" then valeur.Achats else {},
		}
		return profil, true
	end
	return { Pieces = Config.PIECES_DE_DEPART, Achats = {} }, true
end

local function afficher(player: Player)
	local profil = profils[player]
	local leaderstats = player:FindFirstChild("leaderstats")
	local pieces = leaderstats and leaderstats:FindFirstChild("Pieces")
	if profil and pieces then
		pieces.Value = profil.Pieces
	end
end

function Donnees.charger(player: Player)
	local profil, ok = lire(player)
	if not player.Parent then
		return -- le joueur est parti pendant le chargement
	end
	profils[player] = profil
	if not ok then
		nePasSauvegarder[player] = true
	end

	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	local pieces = Instance.new("IntValue")
	pieces.Name = "Pieces"
	pieces.Parent = leaderstats
	leaderstats.Parent = player
	afficher(player)

	-- Les attributs sont visibles par le client (pour l'interface de la boutique)
	for id in profil.Achats do
		player:SetAttribute("Achat_" .. id, true)
	end
end

-- Attend que les données du joueur soient chargées. Renvoie nil si le joueur est parti.
function Donnees.attendre(player: Player): Profil?
	while player.Parent and not profils[player] do
		task.wait(0.1)
	end
	return profils[player]
end

function Donnees.ajouterPieces(player: Player, montant: number): boolean
	local profil = profils[player]
	if not profil then
		return false
	end
	profil.Pieces += montant
	afficher(player)
	return true
end

function Donnees.depenserPieces(player: Player, montant: number): boolean
	local profil = profils[player]
	if not profil or profil.Pieces < montant then
		return false
	end
	profil.Pieces -= montant
	afficher(player)
	return true
end

function Donnees.possede(player: Player, id: string): boolean
	local profil = profils[player]
	return profil ~= nil and profil.Achats[id] == true
end

function Donnees.ajouterAchat(player: Player, id: string)
	local profil = profils[player]
	if profil then
		profil.Achats[id] = true
		player:SetAttribute("Achat_" .. id, true)
	end
end

function Donnees.sauvegarder(player: Player)
	local profil = profils[player]
	if not profil or nePasSauvegarder[player] then
		return
	end
	local ok, err = pcall(function()
		store:SetAsync(cle(player), profil)
	end)
	if not ok then
		warn("Sauvegarde impossible pour", player.Name, err)
	end
end

-- À appeler quand le joueur quitte : sauvegarde puis oublie ses données.
function Donnees.liberer(player: Player)
	Donnees.sauvegarder(player)
	profils[player] = nil
	nePasSauvegarder[player] = nil
end

return Donnees
