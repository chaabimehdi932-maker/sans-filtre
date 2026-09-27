# sans-filtre

Jeu Roblox géré avec [Rojo](https://rojo.space) : le code vit dans ce dépôt Git
et se synchronise automatiquement dans Roblox Studio.

## Installation automatique (une seule fois)

1. Télécharge le projet : sur GitHub, choisis la branche `claude/roblox-studio-c4irid`,
   puis **Code → Download ZIP** et décompresse-le (ou `git clone`).
2. **Windows** : double-clic sur **`INSTALLER.bat`**.
   **Mac** : ouvre un terminal dans le dossier et lance `./installer.sh`.

   Le script installe Rokit, Rojo, Selene, StyLua et le plugin Rojo pour Studio,
   puis lance `rojo serve`.
3. Ouvre (ou redémarre) Roblox Studio → ouvre ton jeu → onglet **Plugins** → **Rojo** → **Connect**.

Recommandé : [VS Code](https://code.visualstudio.com) avec les extensions proposées
dans `.vscode/extensions.json` (Rojo, Luau LSP, StyLua, Selene).

## Travailler au quotidien

1. **Windows** : double-clic sur **`DEMARRER.bat`** (Mac : `rojo serve` dans un terminal).
2. Dans Studio : **Plugins** → **Rojo** → **Connect**.
3. Modifie les fichiers dans `src/` : les changements apparaissent **instantanément** dans Studio.

Pour générer un fichier de jeu complet sans Studio :
```
rojo build -o sans-filtre.rbxl
```

## Où va quoi

| Dossier        | Dans Roblox Studio                              |
|----------------|-------------------------------------------------|
| `src/server/`  | `ServerScriptService.Server`                    |
| `src/client/`  | `StarterPlayer.StarterPlayerScripts.Client`     |
| `src/shared/`  | `ReplicatedStorage.Shared`                      |

Le type de script dépend du nom du fichier :

| Nom de fichier       | Type dans Studio |
|----------------------|------------------|
| `Nom.server.luau`    | Script           |
| `Nom.client.luau`    | LocalScript      |
| `Nom.luau`           | ModuleScript     |

> Les parties, modèles et décors se construisent toujours dans Studio (Rojo gère le code).
> Pense à sauvegarder ta place dans Studio / publier sur Roblox comme d'habitude.

## Automatisation (GitHub Actions)

À chaque push, `.github/workflows/ci.yml` :
- vérifie le formatage (StyLua) ;
- analyse le code (Selene) ;
- construit `sans-filtre.rbxl` et le met à disposition dans l'onglet **Actions** de GitHub.

## Ce que fait le jeu

- **Pièces sur la carte** (`src/server/Pieces.server.luau`) : 25 pièces dorées apparaissent au sol,
  les toucher donne 5 pièces, elles réapparaissent ailleurs 10 s plus tard.
- **Boutique** (`src/server/Boutique.server.luau` + `src/client/Boutique.client.luau`) : bouton
  « Boutique » en bas à gauche pour acheter vitesse et saut. Les achats sont vérifiés par le serveur.
- **Données** (`src/server/Donnees.luau`) : pièces et achats sauvegardés avec DataStore.
- **Revenu passif** (`src/server/Joueurs.server.luau`) : +10 pièces par minute.
- **Réglages** (`src/shared/Config.luau`) : prix, nombre de pièces, vitesse… tout se change ici.

## Récupérer les dernières modifications

**Windows** : double-clic sur **`METTRE_A_JOUR.bat`**. Si `rojo serve` tourne,
les changements arrivent directement dans Studio.
