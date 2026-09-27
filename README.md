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
| **X / C / V** | Orders for the unit **you command**: **Hold / Follow / Attack** |
| **B → aim → left click** | **Rush**: a striped path shows where your unit will sprint; left click charges, right click cancels. Cavalry ride straight through every enemy squad on the way. 15 s cooldown |
| **X → 1 / 2 / 3 → Left click** | Hold: glowing markers preview where every soldier will stand in front of you, 1/2/3 pick Line / Column / Square, left click confirms (right click or X cancels) |
| F1 · M | Controls panel · minimap |

Before each battle you **choose one unit for free** — that is the squad you command. The rest
of your army is led by allied officers (ally AI): they take objectives, engage enemies and fall
back when their morale breaks. If your unit is wiped out, reinforcements bring a fresh one
(3 per battle). Your unit earns a veteran star for every battle it survives.

## How a round plays

1. **Choose your unit** (40 s): pick one unit card (free). Allied squads are added automatically.
2. **Battle**: the big banner gives your objective (`ATTACKER — CAPTURE PLAINS`).
   - *Attacker* (odd rounds): capture **and hold** every zone for 20 s, or destroy the enemy.
   - *Defender* (even rounds): destroy the attackers before they take every zone.
3. **Summary**: kills, losses, zones held and XP earned → next round.
   A defeat sends you back to round 1. Your level, best round and unlocked units are saved.

Difficulty rises every round (more squads, cavalry from round 3, artillery from round 4,
reinforcement waves). Every 5th round is a boss round with a named general's squad.

## Systems

- **Squads**: one logical object with pooled HP, simulated on the server. Every client draws
  full-size R6 soldiers and animates their joints itself (`client/SquadRenderer`,
  `client/SoldierModels`): marching,
  aiming, volley recoil, reloading, bayonet thrusts, routing, physics ragdoll casualties
  (capped by `Rendering.MaxRagdolls`, scripted fall beyond it), galloping cavalry with sabres,
  recoiling cannons.
- **Army size**: weaker, cheaper units field more men (Line 20, Skirmishers 14, Cavalry 10,
  Guard 12, Artillery 4 crew). Armies are mostly line infantry; artillery is always the rarest.
- **Formations**: Line (firepower, weak flanks), Column (fast, fragile), Square (stops cavalry,
  weak against cannons). Changing formation takes 3 s, during which the squad is vulnerable.
- **Morale**: drops from casualties, flanking, charges and isolation. At 0 the squad routs, flees
  and ignores orders until it rallies.
- **Combat**: musket volleys, bayonets up close, cavalry charge bonus (then disengage and
  re-charge), artillery shells with splash damage. All of it runs server-side.
- **Zones**: capture progress based on the presence weight of squads inside; frozen when
  contested. Held zones give a bonus: *Reinforcements* (faster), *Morale* (regen), *ArtilleryRange* (+25%).
- **Enemy AI**: state machine Idle → Advancing → Engaging → Routing → Regrouping. It takes
  objectives, flanks Lines, sends cavalry at guns and exposed squads, forms square against
  cavalry, and falls back when morale is low.

## Architecture

```
ServerScriptService/                    (src/server)
  GameManager (Script)                  round state machine, win/lose, service wiring, Heartbeat
  SquadService                          squads, movement/pathfinding, combat, morale, visuals
  EnemyAIController                     enemy squad AI
  SquadController                       one decision path per squad: player orders OR AI
  CommandService                        the commanded squad (IsPlayerControlled), hotkey orders
  AllyAIController / EnemyAIController  your other squads / the enemy, both on SquadAI
  SquadAI                               shared tactics + state machine (team-agnostic)
  PlayerCombatService                   commander combat (attack, block, roll, heal, horse)
  ZoneService                           capture zones and bonuses
  RecruitmentService                    points, validated purchases, deployment
  DataService                           DataStoreService (level, best round, unlocks)
  MapService                            CollectionService tags + placeholder map
ReplicatedStorage/
  Modules/                              (src/shared) UnitDefinitions, FormationDefinitions,
                                        SoldierAnimationIds, GameConfig, MathUtil, Remotes
  RemoteEvents/                         declared in default.project.json
StarterPlayerScripts/                   (src/client)
  PlayerCombatController, ArmyCommandController, CameraController, UIController, VFXController,
  CharacterAnimator (rider pose, horse gait, sabre swing, block, roll), SquadRenderController,
  SquadSelectionController (Tab / click), HoldPreviewController
  ClientState, ClientActions, SquadRenderer, SoldierModels, SoldierAnimationService,
  UI/* (Hud, UnitCard, RecruitPanel, SummaryPanel, Markers, Effects, Theme)   (client modules)
StarterGui/MainHUD                      single ScreenGui; UIController builds its frames
```

Clients only send intent (RemoteEvents). The server validates everything and pushes state back
4 times per second. Expensive systems are throttled: combat 0.2 s, orders 0.3 s, AI 0.5 s,
zones 0.5 s, paths 2 s.

## Tuning

- `src/shared/SoldierAnimationIds.luau`: animation ids per soldier state (empty = procedural
  pose). Soldiers are R6 rigs with standard R6 joints, so use **R6** animations.
- `GameConfig.Rendering`: soldier cap (`MaxActiveSoldiers`) and LOD distances

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
