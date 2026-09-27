# sans-filtre

Jeu Roblox géré avec [Rojo](https://rojo.space) : le code vit dans ce dépôt Git
et se synchronise automatiquement dans Roblox Studio.

## Installation (une seule fois)

1. Installe [Rokit](https://github.com/rojo-rbx/rokit) (gestionnaire d'outils Roblox).
2. Dans le dossier du projet :
   ```
   rokit install
   ```
   Ça installe les versions de Rojo, Selene et StyLua indiquées dans `rokit.toml`.
3. Installe le **plugin Rojo** dans Roblox Studio :
   ```
   rojo plugin install
   ```
   (ou depuis la boutique de plugins Roblox : « Rojo »).
4. Recommandé : [VS Code](https://code.visualstudio.com) avec les extensions proposées
   dans `.vscode/extensions.json` (Rojo, Luau LSP, StyLua, Selene).

## Travailler au quotidien

1. Lance le serveur Rojo :
   ```
   rojo serve
   ```
2. Ouvre ton jeu dans Roblox Studio → onglet **Plugins** → **Rojo** → **Connect**.
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

## Scripts d'exemple

- `src/server/Leaderstats.server.luau` : classement « Pieces », +10 pièces par minute, sauvegarde DataStore.
- `src/client/Bienvenue.client.luau` : message de bienvenue à l'écran.
- `src/shared/Config.luau` : réglages partagés.
