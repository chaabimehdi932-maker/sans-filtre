-- Réglages partagés entre le serveur et le client.
-- Ce ModuleScript se retrouve dans ReplicatedStorage.Shared.Config

local Config = {}

-- Données des joueurs
Config.PIECES_DE_DEPART = 0
Config.PIECES_PAR_MINUTE = 10
Config.NOM_DATASTORE = "DonneesJoueurs_v1"

-- Pièces à ramasser sur la carte
Config.PIECES_SUR_LA_CARTE = 25
Config.VALEUR_PIECE = 5
Config.REAPPARITION_PIECE = 10 -- secondes avant qu'une pièce ramassée revienne
Config.ZONE_PIECES = 100 -- les pièces apparaissent entre -100 et +100 studs autour du centre

-- Articles de la boutique. `vitesse` et `saut` remplacent les valeurs de base (16 et 50).
Config.BOUTIQUE = {
	{ id = "Vitesse", nom = "Baskets rapides", prix = 50, vitesse = 24 },
	{ id = "Saut", nom = "Super saut", prix = 100, saut = 75 },
	{ id = "Turbo", nom = "Turbo", prix = 300, vitesse = 34 },
	{ id = "Fusee", nom = "Bottes fusée", prix = 500, saut = 110 },
}

return Config
