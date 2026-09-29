# Napoleonic Commander

Roblox mass-battle game (Mount & Blade / UEBS feel): you are a **mercenary commander** for hire,
on horseback in third person, fighting alongside your squads while giving them orders. Between
battles you march your company across a Bannerlord-style overworld, take contracts from the
faction you serve, get paid and grow your reputation and your army.
The code is managed with [Rojo](https://rojo.space).

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
| **X / C / V** | Orders for the squads **you command**: **Hold / Follow / Attack** |
| **Tab / Shift+Tab** | Command the next / previous squad (alone) |
| **T** · Shift+click a squad card | Add a squad to the group you command (as many as your reputation allows) |
| **B → aim → left click** | **Rush**: a striped path shows where your squads will sprint (2× speed); left click charges, right click cancels. Aim it on an enemy squad (the path turns red) to charge that squad wherever it goes. Cavalry ride straight through every enemy squad on the way. 8 s cooldown |
| **T → left click** | **Fire at**: click an enemy squad and your archers / muskets / guns focus it (walking into range if needed); melee squads attack it. Click the ground: guns bombard that spot, shooters take the enemy nearest to it. Right click cancels |
| **X → 1 / 2 / 3 → Left click** | Hold: glowing markers preview where every soldier will stand in front of you, 1/2/3 pick Line / Column / Square, left click confirms (right click or X cancels) |
| F1 · M | Controls panel · minimap |

Your whole company deploys in every battle. You command the squads outlined in gold (1 at the
start, more as your reputation grows); your other squads and allied troops are led by the ally
AI: they take objectives, engage enemies and fall back when their morale breaks.

**Overworld (map screen):** left click the ground or a banner to march · mouse wheel zoom ·
right-drag rotate · WASD pan · Space recentre · time controls ❚❚ ▶ ▶▶ at the bottom.

**In town:** walk around on foot (G to mount), walk up to people and press **E** to talk:
Master Aubert (town hall — contracts), Sergeant Dubois (barracks — hire recruits),
Quartermaster Lenoir (replenish casualties), Captain Varga (tavern — veteran free companies
already ★/★★), Old Marcel (innkeeper — rumours about bandits and your bounty),
Madame Rosalie (market — new kit and drill: gold → squad XP), the gate guard (back to the map).

**Enlisting (when you're poor):** every faction has a general's army roaming the map. Ride up
to your employer's general and press ⚑ ENLIST: you march with him, earn a daily wage and a
share of the loot, and in his battles you lead one of his squads (better ones as you get
promoted: Recruit → Veteran → Sergeant → Lieutenant). Your own company stays safe in camp.
LEAVE SERVICE whenever you have enough gold.

**Battlefields follow the map:** fight near a castle and its walls tower behind the enemy;
raids and garrison defences are real sieges with breached curtain walls; near a town you fight
in its outskirts; bandits defend their stockade; the woods, hills and rivers of the overworld
become forest, hill and river-crossing battlefields.

**Bandits** field their own troops: sword-and-buckler Bandit Swordsmen who rush in and brawl,
and Bandit Gunners with stolen muskets.

**Battle rules:** musket lines fight in a single rank — precision drops in extra ranks, in
column, in square, while forming up or moving (`GameConfig.Combat.Accuracy`). Every squad is
led by a mounted officer riding in front (he raises his sabre on orders); kill him and the
squad wavers — you are the officer of the squads you command. Hopelessly outnumbered (1:8,
`GameConfig.Battle`)? Your army breaks and it's a defeat. An army whose every squad flees
loses. Field battles are open terrain, a fight to the death; capture zones and walls only
exist in castle raids and garrison defences. High ground hits harder, woods slow cavalry,
give cover and spoil musket precision, rivers slow everyone (`GameConfig.Terrain`); the
squad you command shows its terrain bonus above its card. Top centre: troop counts and the
live ratio; top right: the kill feed.

**Your company:** every squad draws a daily wage (unpaid troops lose morale, then desert).
At ★★ a squad chooses a path (Line → Grenadiers / Light Infantry, Skirmishers → Riflemen /
Voltigeurs, Cavalry → Cuirassiers / Hussars; `CampaignConfig.Branches`). Enemies who flee
when you win become prisoners: recruit some, or ransom them to Monsieur Vautrin in town.
Your commander wears gear (weapon, armour, horse) bought from Madame Rosalie and Old Gaspard
or looted on the field. Hire named officers from the innkeeper and put them at the head of a
squad for their skill; if they fall they're only wounded for a few days.

## The mercenary campaign

1. **Choose your employer**: Francia, Albion or Borussia (same units, different colours). You
   start in their town with two squads and some gold. Every faction is at war with the other two;
   bandits are hostile to everyone.
2. **Overworld**: time passes while you march (or wait). Bandit warbands roam around their camps,
   faction patrols travel between their castles; hostile parties chase you and a contact means
   battle. Leaving the roads makes random encounters much more likely.
3. **Quest board** (your employer's town) — accept or decline freely:
   - **Raid**: storm an enemy castle (biggest pay, hardest fight). A won castle goes to your
     employer (its banner changes) and pays a capture bonus; you stay a mercenary, you don't own it.
   - **Raid village**: plunder an enemy village (🔥 RAID VILLAGE while standing in it).
   - **Bounty**: hunt a named bandit warband (its leader fights as a boss squad).
   - **Escort**: the caravan leaves when you join it; bandits ambush it on the way, stay close
     or it's plundered.
   - **Garrison / Defend**: be at one of your castles on the attack day and defend it (or it falls).
     When an enemy general besieges one of your employer's castles, a Defend contract for that
     siege is posted; if nobody defends, the garrison fights alone.
   Success pays gold + reputation; failure (deadline, caravan lost, castle fallen, abandoned)
   costs reputation. Losing a battle outside a contract costs no reputation.
4. **Battle**: deploy (READY) → fight → summary with the campaign report.
   **Defeat**: you lose a share of your gold and fall back to your town. **Any squad wiped out is
   gone for good**; survivors keep their casualties and their XP.
5. **Town** (🚶 ENTER THE TOWN when you stand in your employer's town): you walk in on foot and
   deal with its people — contracts, recruits, mercenaries, quartermaster, arms merchant, rumours.
   Time is paused while you're in town.
6. **Reputation** earns rank titles (`CampaignConfig.Reputation`). You command your whole army.
7. **Squad evolution**: each squad earns XP (kills, survival, victories). Every ★ is an evolution
   tier: more HP, damage and morale, and better kit (chevrons → gold epaulettes, brass musket and
   long bayonet / polished sabre → gold facings and tall plume). Casualties never reset the tier.
8. **Wounded vs dead**: most of the fallen are only wounded (fewer if the squad routed or was
   overrun). They heal over the days, faster in a friendly town or castle. AI generals too.
9. **Villages**: raiding one gives gold (and maybe loot) and drops its prosperity, which cuts its
   kingdom's recruits until it slowly recovers. AI generals raid your employer's villages too.
10. **Castles**: every castle and town flies its owner's banner, on the map and in siege battles.
    Captured castles start with a weak garrison that grows daily; enemy generals try to retake them.

Commander level/XP, unlocks and the whole campaign (faction, gold, reputation, day, castle
owners, roster with each squad's XP and headcount) are saved. ☰ → New campaign starts over.
For a solo experience set **Max Players = 1** (Game Settings → Places); with several players,
each runs their own campaign and battles take turns on the one battlefield.

## Systems

- **Squads**: one logical object with pooled HP, simulated on the server. Every client draws
  full-size R6 soldiers and animates their joints itself (`client/SquadRenderer`,
  `client/SoldierModels`): marching,
  aiming, volley recoil, reloading, bayonet thrusts, routing, physics ragdoll casualties
  (capped by `Rendering.MaxRagdolls`, scripted fall beyond it), galloping cavalry with sabres,
  recoiling cannons.
- **Army size**: weaker, cheaper units field more men (Line 20, Skirmishers 14, Cavalry 10,
  Guard 12, Artillery / Howitzer 4 crew). Armies are mostly line infantry; artillery is always the rarest.
- **Howitzer**: siege gun. High-arc shells, longest range, big blast, very slow reload, very
  fragile. It prefers castle gates to troops and breaks them fast.
- **Sieges**: castle walls block movement and every opening has a gate. Attackers stuck at a gate
  batter it; cannon and howitzer shells damage gates near the impact. A broken gate is a breach.
- **Formations**: Line (firepower, weak flanks), Column (fast, fragile), Square (stops cavalry,
  weak against cannons). Changing formation takes 3 s, during which the squad is vulnerable.
- **Morale**: drops from casualties, flanking, charges and isolation. At 0 the squad routs, flees
  and ignores orders until it rallies.
- **Combat**: musket volleys, bayonets up close, cavalry charge bonus (then disengage and
  re-charge), artillery shells with splash damage. All of it runs server-side.
- **Zones**: capture progress based on the presence weight of squads inside; frozen when
  contested. Held zones give a bonus: *Reinforcements* (faster), *Morale* (regen), *ArtilleryRange* (+25%).
- **Assault**: AI sides no longer trade volleys forever. After a standoff (or when clearly
  winning, or when the enemy is shaken) they go in: melee foot and cavalry charge at a sprint,
  line infantry fix bayonets against shaken or weaker squads, cavalry hunt guns and archers.
- **Enemy AI**: state machine Idle → Advancing → Engaging → Routing → Regrouping. It takes
  objectives, flanks Lines, sends cavalry at guns and exposed squads, forms square against
  cavalry, and falls back when morale is low.

## Architecture

```
ServerScriptService/                    (src/server)
  GameManager (Script)                  battle state machine (queued campaign battles), win/lose, wiring
  CampaignService                       overworld per player: travel, days, parties, encounters, battles
  QuestService                          quest board, Raid / Bounty / Escort / Garrison contracts
  TownService                           the walkable town and its people (ProximityPrompts)
  ReputationService                     reputation per faction → rank titles
  SquadService                          squads, movement/pathfinding, combat, morale, visuals
  EnemyAIController                     enemy squad AI
  SquadController                       one decision path per squad: player orders OR AI
  CommandService                        the commanded group (IsPlayerControlled on 1..N squads), orders
  AllyAIController / EnemyAIController  your other squads / the enemy, both on SquadAI
  SquadAI                               shared tactics + state machine (team-agnostic)
  PlayerCombatService                   commander combat (attack, block, roll, heal, horse)
  ZoneService                           capture zones and bonuses
  RecruitmentService                    saved roster: deployment, hiring, replenishing, squad XP/evolution
  DataService                           DataStoreService (level, unlocks, profile.Campaign)
  MapService                            CollectionService tags + placeholder map
ReplicatedStorage/
  Modules/                              (src/shared) UnitDefinitions, FormationDefinitions,
                                        SoldierAnimationIds, GameConfig, CampaignConfig, MathUtil, Remotes
  RemoteEvents/                         declared in default.project.json
StarterPlayerScripts/                   (src/client)
  PlayerCombatController, ArmyCommandController, CameraController, UIController, VFXController,
  CharacterAnimator (rider pose, horse gait, sabre swing, block, roll), SquadRenderController,
  SquadSelectionController (gold outline), HoldPreviewController, OverworldController (map + camera)
  ClientState, ClientActions, SquadRenderer, SoldierModels, SoldierAnimationService,
  UI/* (Hud, UnitCard, RecruitPanel, SummaryPanel, CampaignPanels, Markers, Effects, Theme)
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
- `src/shared/CampaignConfig.luau`: **the campaign** — travel speed and time, encounter chances,
  parties, battle strengths, gold (start, hire/replenish prices, loss penalty, loot), contract
  rewards/penalties/deadlines, **reputation → squads table**, **evolution XP curve and stat bumps**,
  and the map (locations, roads). Every number there is marked `PLACEHOLDER`.
- `src/shared/GameConfig.luau`: army composition by strength (`getRound`), commander, morale, zones, AI,
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
