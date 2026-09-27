-- Crée le classement (leaderstats), donne des pièces chaque minute
-- et sauvegarde les pièces avec DataStoreService.
-- Pour que la sauvegarde marche dans Studio : Game Settings > Security >
-- activer "Enable Studio Access to API Services".

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local store = DataStoreService:GetDataStore(Config.NOM_DATASTORE)

local function cle(player: Player): string
	return "joueur_" .. player.UserId
end

local function charger(player: Player): number
	local ok, valeur = pcall(function()
		return store:GetAsync(cle(player))
	end)
	if ok and typeof(valeur) == "number" then
		return valeur
	end
	if not ok then
		warn("Chargement impossible pour", player.Name, valeur)
	end
	return Config.PIECES_DE_DEPART
end

local function sauvegarder(player: Player)
	local leaderstats = player:FindFirstChild("leaderstats")
	local pieces = leaderstats and leaderstats:FindFirstChild("Pieces")
	if not pieces then
		return
	end
	local ok, err = pcall(function()
		store:SetAsync(cle(player), pieces.Value)
	end)
	if not ok then
		warn("Sauvegarde impossible pour", player.Name, err)
	end
end

local function onPlayerAdded(player: Player)
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"

	local pieces = Instance.new("IntValue")
	pieces.Name = "Pieces"
	pieces.Value = charger(player)
	pieces.Parent = leaderstats

	leaderstats.Parent = player
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(sauvegarder)

-- Joueurs déjà présents avant que le script démarre
for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end

-- Sauvegarde de tout le monde quand le serveur s'arrête
game:BindToClose(function()
	for _, player in Players:GetPlayers() do
		sauvegarder(player)
	end
end)

-- Pièces gagnées chaque minute
task.spawn(function()
	while true do
		task.wait(60)
		for _, player in Players:GetPlayers() do
			local leaderstats = player:FindFirstChild("leaderstats")
			local pieces = leaderstats and leaderstats:FindFirstChild("Pieces")
			if pieces then
				pieces.Value += Config.PIECES_PAR_MINUTE
			end
		end
	end
end)
