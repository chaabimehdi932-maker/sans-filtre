# Napoleonic Commander

Roblox mass-battle game (Mount & Blade / UEBS feel): you are the commander, on horseback in
third person, fighting alongside your squads while giving them orders. Win rounds by capturing
zones and breaking the enemy army. The code is managed with [Rojo](https://rojo.space).

> **Systems-first pass.** Soldiers, horses and the map are placeholder blocks.
> **Every balance number is a `PLACEHOLDER`**: see "Tuning" below.

## Controls

| Key | Action |
|---|---|
| WASD / Space | Move · jump (on foot) |
| **Right mouse drag** | Rotate the camera · **Left Alt** toggles mouse-look (locked cursor) |
| Left click | Attack (a mounted charge hits harder the faster you ride) |
| F (hold) | Block: raise your shield (frontal damage −80%) |
| Q | Roll: dodge with a short invulnerability window (on foot) |
| H | Heal: restores 40% HP and boosts the morale of your squads nearby |
| G | Mount / dismount |
| **X / C / V / B** | Orders for the **selected** squads: **Hold / Follow / Attack / Rush** |
| **X → 1 / 2 / 3 → X** | Hold: glowing markers preview where every soldier will stand in front of you, 1/2/3 pick Line / Column / Square, X again confirms (Backspace cancels) |
| 1 – 9 | Select squad n · **Shift + number** adds/removes it from the selection |
| 0 or ` | Select all your squads · T = next squad |
| **Ctrl + drag** (left mouse) | Box-select squads on screen (Ctrl + click = pick one) |
| F1 · M | Controls panel · minimap |

The squad panel (right) is clickable too (Shift + click = add). The whole army is selected at
the start of every battle.

## How a round plays

1. **Recruitment** (40 s): spend points on squads in the shop. Surviving veterans stay in your army.
2. **Battle**: the big banner gives your objective (`ATTACKER — CAPTURE PLAINS`).
   - *Attacker* (odd rounds): capture **and hold** every zone for 20 s, or destroy the enemy.
   - *Defender* (even rounds): destroy the attackers before they take every zone.
3. **Summary**: kills, losses, zones held, points and XP earned → next round.
   A defeat sends you back to round 1. Your level, best round and unlocked units are saved.

Difficulty rises every round (more squads, cavalry from round 3, artillery from round 4,
reinforcement waves). Every 5th round is a boss round with a named general's squad.

## Systems

- **Squads**: one logical object with pooled HP, simulated on the server. Every client draws
  full-size R6 soldiers and animates their joints itself (`client/SquadRenderer`,
  `client/SoldierModels`): marching,
  aiming, volley recoil, reloading, bayonet thrusts, routing, falling casualties, galloping
  cavalry with sabres, recoiling cannons.
- **Formations**: Line (firepower, weak flanks), Column (fast, fragile), Square (stops cavalry,
  weak against cannons). Changing formation takes 3 s, during which the squad is vulnerable.
- **Morale**: drops from casualties, flanking, charges and isolation. At 0 the squad routs, flees
  and ignores orders until it rallies.
- **Combat**: musket volleys, bayonets up close, cavalry charge bonus (then disengage and
  re-charge), artillery shells with splash damage. All of it runs server-side.
- **Zones**: capture progress based on the presence weight of squads inside; frozen when
  contested. Held zones give a bonus: *Income* (points), *Morale* (regen), *ArtilleryRange* (+25%).
- **Enemy AI**: state machine Idle → Advancing → Engaging → Routing → Regrouping. It takes
  objectives, flanks Lines, sends cavalry at guns and exposed squads, forms square against
  cavalry, and falls back when morale is low.

## Architecture

```
ServerScriptService/                    (src/server)
  GameManager (Script)                  round state machine, win/lose, service wiring, Heartbeat
  SquadService                          squads, movement/pathfinding, combat, morale, visuals
  EnemyAIController                     enemy squad AI
  CommandService                        player orders / formations / selection
  PlayerCombatService                   commander combat (attack, block, roll, heal, horse)
  ZoneService                           capture zones and bonuses
  RecruitmentService                    points, validated purchases, deployment
  DataService                           DataStoreService (level, best round, unlocks)
  MapService                            CollectionService tags + placeholder map
ReplicatedStorage/
  Modules/                              (src/shared) UnitDefinitions, FormationDefinitions,
                                        GameConfig, MathUtil, Remotes
  RemoteEvents/                         declared in default.project.json
StarterPlayerScripts/                   (src/client)
  PlayerCombatController, ArmyCommandController, CameraController, UIController, VFXController,
  CharacterAnimator (rider pose, horse gait, sabre swing, block, roll), SquadRenderController
  ClientState, ClientActions, SquadRenderer, SoldierModels, UI/*   (shared client modules)
StarterGui/MainHUD                      single ScreenGui; UIController builds its frames
```

Clients only send intent (RemoteEvents). The server validates everything and pushes state back
4 times per second. Expensive systems are throttled: combat 0.2 s, orders 0.3 s, AI 0.5 s,
zones 0.5 s, paths 2 s.

## Tuning

- `src/shared/UnitDefinitions.luau`: HP, speed, damage, range, reload, cost, morale for each unit
- `src/shared/FormationDefinitions.luau`: formation bonuses and penalties
- `src/shared/GameConfig.luau`: rounds and difficulty (`getRound`), commander, morale, zones, AI,
  rewards, sounds (`GameConfig.Sounds`: put real asset ids there, including `Music`)

## Building your own map in Studio

With no tagged Parts, a placeholder battlefield is generated (grass terrain, hills, road, village,
woods, 3 zones: Plains, Village, Ridge) with its own lighting.
To use your map, tag Parts with the **Tag Editor** (View → Tags):

| Tag | Part | Attributes |
|---|---|---|
| `CaptureZone` | a flat block or cylinder | `ZoneName` (text), `Bonus` = `Income` / `Morale` / `ArtilleryRange`, `Order` (number), `Radius` (optional) |
| `PlayerDeployZone` | the area where your army deploys | — |
| `EnemyDeployZone` | the area where the enemy spawns | — |

Set **`CanCollide = false`** on these Parts. Scripts only read the tags.

## Development setup (Windows)

1. Double-click **`DEMARRER.bat`** (installs the right Rojo version, then starts it).
2. Roblox Studio → **Plugins → Rojo → Connect** (Script Injection must be allowed in *Manage Plugins*).
3. To get the latest changes: double-click **`METTRE_A_JOUR.bat`**.

For saving to work in Studio: *Game Settings → Security → Enable Studio Access to API Services*.

## Stretch goals noted in the code

- Command-radius orders (every squad near the commander) instead of the selected squad
- Click-to-place deployment in the deployment zone
- Real models, animations and sounds
