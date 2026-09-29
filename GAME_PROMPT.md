Build a Roblox mass-battle game with a mercenary campaign, inspired by Mount & Blade: Bannerlord. Use Rojo and Luau with strict typing.

Setting: MEDIEVAL. The units are listed in section 4; replace them with your own list if you prefer.

Ground rules for you (the AI building this):
- Build systems first. Models can be simple placeholder rigs (full-size R6 soldiers, block horses, block castles).
- Every balance number is a clearly labelled PLACEHOLDER in a config module (GameConfig, CampaignConfig, UnitDefinitions). Ask me before choosing exact numbers; until then use sensible placeholders and list them.
- Flag anything that conflicts between systems instead of silently changing it.
- The server is authoritative: clients only send intent through RemoteEvents, and the server validates everything.
- Keep a README with the controls, the systems and a tuning guide. Show the version (GameConfig.Version) in the Output window and on the HUD.
- Windows helper scripts:
  - INSTALLER.bat installs Rojo via rokit.
  - DEMARRER.bat starts `rojo serve`.
  - METTRE_A_JOUR.bat (+ .ps1) downloads the latest branch zip from GitHub, replaces the src folder, and restarts Rojo.
- Write headless tests (Lune, with a harness that mocks the Roblox services) for the server logic.

====================================================================
1. PROJECT LAYOUT
====================================================================
- src/shared → ReplicatedStorage.Modules: GameConfig, CampaignConfig, UnitDefinitions, FormationDefinitions, MathUtil, Remotes, Icons, SoldierAnimationIds.
- src/server → ServerScriptService:
  - GameManager: the battle state machine.
  - CampaignService: the overworld.
  - QuestService: contracts.
  - TownService.
  - ReputationService.
  - RecruitmentService: roster, deployment, XP.
  - SquadService: groups.
  - SoldierService: individual men.
  - SquadController: one decision path per squad.
  - CommandService: player orders.
  - SquadAI: shared by EnemyAIController and AllyAIController.
  - BattlePlan: per-side teamwork.
  - PlayerCombatService: the commander's own combat.
  - ZoneService: capture zones.
  - MapService: battlefields, walls, gates.
  - DataService: DataStore.
- src/client → StarterPlayerScripts:
  - Controllers for the player's combat, army commands, camera, UI, VFX, overworld, the Rush / Hold / Fire-at aim previews, and squad selection.
  - ClientState and ClientActions.
  - SquadRenderer, SoldierModels, SoldierAnimationService.
  - UI modules: Hud, UnitCard, RecruitPanel, SummaryPanel, CampaignPanels, Markers, Theme.
- RemoteEvents are declared in default.project.json.
- Snapshots of squads and zones go to clients about 5 times a second, and clients interpolate.
- Throttle expensive systems: soldiers 10 Hz, combat/targets 0.2 s, AI 0.5 s, player orders 0.3 s, zones 0.5 s, paths 2 s.

====================================================================
2. THE PLAYER COMMANDER (third person)
====================================================================
- The player fights in person, on foot or on horseback.
- Combat actions:
  - Attack with left click. A mounted charge hits harder the faster you ride.
  - Block by holding F (a shield: −80% frontal damage).
  - Roll with Q (a dodge with a short invulnerability window, on foot only).
  - Heal with H (+40% HP, and a morale boost to your squads nearby).
  - Mount / dismount with G.
- Commander level and XP. Units unlock with wins.
- Gear slots (weapon, armour, horse) change the commander's stats. Gear is bought in town or looted.
- Enemy soldiers can fight the commander, who takes a fraction of squad damage. On death he respawns after a delay.

====================================================================
3. SOLDIERS AND SQUADS (Mount & Blade style)
====================================================================
- EVERY SOLDIER IS HIS OWN UNIT, simulated on the server (SoldierService, 10 Hz). Each man has his own:
  - id,
  - position,
  - facing,
  - HP (squad HP ÷ number of men),
  - foe,
  - swing timer and shot timer.
- A SQUAD is only the group he belongs to. It holds:
  - the orders,
  - a formation anchor (its position) and a facing,
  - one morale,
  - the group's target.
  squad.health = sum of its men's HP; squad.soldierCount = living men.
- Loose formation, "good enough":
  - Each man walks to his own spot around the anchor (about 1.3× spacing plus a small random offset). He doesn't shuffle once he's close.
  - The formation turns only when it marches or is given a facing, NEVER to stare at an enemy. Single men turn to face their own foe or target.
- Melee: each man picks his own enemy soldier nearby, with at most 2 attackers on one man, so the fight spreads along the front. He walks up and swings on his own timer.
  - Melee units look further for a foe when their group charges or is in contact.
  - Archers and siege crews only defend themselves.
  - Men keep personal space from friends and foes alike, so lines don't walk through each other.
- Shooting: each archer fires on his own reload at one of the nearest men of the group's target.
  - Hit chance = formation accuracy × range falloff.
  - The damage lands when the arrow arrives.
  - Arrows fly in a VISIBLE ARC on the client (batched shot events: shooter id, landing point, flight time).
- Cavalry: a rider moving fast long enough has his charge armed (his first hit × chargeMultiplier). Rushing riders hit every man they gallop through, once each.
- Lethality: a man falls in about 4 melee hits or 3 arrow hits (placeholder multipliers).
- Damage function applyDamage(squad, amount, info). It applies these modifiers:
  - formation damage-taken,
  - flank and rear bonus,
  - a malus while forming up or rushing,
  - routing.
  The blow lands on info.soldier if given, otherwise on the men nearest to where it came from. Men die one by one, and the kill / casualty hooks fire per man.
- Network: each snapshot carries every living man, 8 bytes per man (u16 id, i16 x×8, i16 z×8, u8 facing, u8 flags: swinging / hit / charge armed).
- Client rendering:
  - One animated R6 rig per man, smoothly following HIS server position.
  - A dead man ragdolls (physics ragdolls are capped; beyond that, a scripted fall).
  - Performance cap of about 260 drawn men (past it, draw every 2nd or 3rd man).
  - Distance LOD.
  - BulkMoveTo on the anchored roots.
- No mounted officers, no health bars over squads, no "20/20" counts. Only a small name tag over the player's own groups ("★ name", plus the order and CHARGE! / ROUTING!).
- Formations: Line (firepower, weak flanks), Column (fast, fragile), Square / shield wall (stops cavalry, weak to siege shots). Changing formation takes about 3 s, during which the squad is vulnerable.
- Morale:
  - Drops from casualties, flanking, charges and isolation.
  - At 0 the squad ROUTS: it flees home, ignores orders and rallies later.
  - It regenerates out of combat, and faster near friends or the commander.
- Terrain: high ground hits harder; woods slow cavalry, give cover and spoil archery; rivers slow everyone.

====================================================================
4. UNITS (UnitDefinitions — all numbers PLACEHOLDER)
====================================================================
- Each unit has these fields: health / damage / meleeDamage for the WHOLE squad, attackRange, attackCooldown, meleeCooldown, chargeMultiplier, moveSpeed, morale, soldiers (men per squad), cost, formations, visual, projectile ("Arrow" for bows), and tier.
- Starting roster:
  - Levy (cheap spearmen, many men),
  - Spearmen (strong vs cavalry),
  - Men-at-Arms (heavy melee),
  - Archers (projectile "Arrow"),
  - Knights (heavy cavalry, big charge),
  - Horse Archers,
  - Catapult (siege gun, few crew),
  - Trebuchet (long-range, high-arc siege gun; breaks gates; slow reload; fragile; costs more than a catapult),
  - Elite Guard (unlocked by wins).
- Bandits have their own units: Bandit Swordsmen (rush in and brawl) and Bandit Archers.
- Archer-type units (bows, horse archers) can't Rush and keep out of melee.
- Branching evolution at ★★ (examples):
  - Spearmen → Pikemen or Shield Wall,
  - Archers → Longbowmen or Crossbowmen,
  - Knights → Heavy Knights or Light Lancers.

====================================================================
5. ORDERS AND CONTROLS (battle)
====================================================================
- The player commands his whole army. Companion-led squads fight on their own AI.
- Selection:
  - Number keys 1-9 select a squad.
  - 0 selects all.
  - Tab / Shift+Tab cycle through squads.
  - Shift+click a squad card to add or remove it.
  - Selected squads are outlined in gold.
- Orders go to the selected squads:
  - X Hold:
    - A preview of glowing markers shows where every man will stand.
    - 1 / 2 / 3 pick the formation.
    - Left click confirms; right click or X cancels.
  - C Follow the commander.
  - V Attack the nearest enemy.
  - B Rush:
    - Aim a striped path on the ground and left click. Squads sprint there at 2× speed.
    - Aiming on an enemy squad (red path) locks onto that squad.
    - Landing next to an enemy turns into an attack.
    - Cooldown about 8 s.
    - Every unit can rush except archer-type units and siege guns.
  - T Fire at:
    - Click an enemy squad: archers and guns focus it, walking into range if needed; melee squads in the selection attack it.
    - Click the ground: siege guns bombard that spot, and archers shoot the enemy nearest to it.
    - A ring on the target and lines from each selected squad show the aim.
- HUD:
  - Order tiles with key badges.
  - A card for the selected squad ("18 men", stars).
  - An army strip with number badges.
  - Troop counts and ratio (top centre).
  - Kill feed (top right).
  - Minimap (M).
  - Controls panel (F1).
  - Terrain bonus label.
  - Commander HP and combat hotbar.

====================================================================
6. BATTLE AI
====================================================================
- A shared BattlePlan per side, so the army fights together:
  - The line of foot advances together at the slowest squad's pace.
  - Melee foot stand slightly in front; archers and siege guns stand behind; cavalry wait on the flanks.
  - The line halts at shooting range, and idle squads move up to support an engaged neighbour.
- Assault: after about 12 s of standoff, or when clearly stronger, or when the enemy's morale is low, the side goes in:
  - Melee foot and cavalry charge at a sprint.
  - Spear / line squads charge shaken or weaker enemies.
  - Archers keep shooting.
  - Cavalry hunt archers and siege guns first and avoid squares / shield walls.
  - The assault is called off when losing badly.
- The AI reacts to the player's moves: when cavalry (or a rushing squad) comes at their archers, the archers pull back behind their infantry, and nearby melee foot intercept the riders.
- Other tactics:
  - Infantry forms Square / shield wall when cavalry comes close.
  - Squads regroup when their morale is low.
- Win and loss:
  - Destroy or rout the enemy.
  - Castle battles are decided by capture zones.
  - Hopelessly outnumbered (1:8): that side breaks and loses.
  - A side whose every squad flees loses.
- Summary screen after each battle: kills, casualties (wounded / dead), XP, loot, contract result.

====================================================================
7. BATTLEFIELDS (MapService)
====================================================================
The battlefield depends on where on the overworld the fight happens:
- Open fields, forest, hills, a river crossing (with a bridge and fords), near a town, or a bandit camp.
- Field battles have no zones and no buildings; they are fights to the death.
- Castle raids and defences are sieges:
  - A curtain wall with towers and a keep.
  - The castle flies its owner's banner (colour and emblem).
  - Walls block movement, and every opening has a wooden GATE with HP.
  - Attackers stuck at a gate batter it.
  - Siege-gun shells damage gates near the impact; the Trebuchet does ×4 and prefers gates.
  - A broken gate is a breach, announced to everyone.
  - Capture zones sit inside the castle.

====================================================================
8. THE MERCENARY CAMPAIGN (overworld)
====================================================================
- Character creation: choose an employer among 3 kingdoms (same units, different colours and emblems). All kingdoms are at war with each other; bandits are hostile to everyone.
- Bannerlord-style overworld:
  - Terrain with roads, woods, hills and rivers.
  - Towns, castles, villages and bandit camps, each with a banner in its owner's colours.
  - Click to march; mouse wheel to zoom; right-drag to rotate; WASD to pan; Space to recentre.
  - Time controls: pause / play / fast. Time only passes while you march or wait.
- Parties on the map:
  - Bandit warbands roam around their camps.
  - Faction patrols travel between castles.
  - Caravans.
  - Each kingdom has a general's army that hunts enemies, raids villages, besieges castles, rests to heal when weak and rebuilds slowly.
- Hostile parties chase you, and contact means battle (an "Ambush!" / "To arms!" banner). Off-road travel raises the random encounter chance.
- Walkable town: enter on foot and talk to NPCs with E:
  - Guildmaster (contracts),
  - Recruiter,
  - Quartermaster (replenish casualties),
  - Mercenary Captain (veteran free companies at ★/★★),
  - Innkeeper (rumours, and hire named companions),
  - Arms merchant and Horse trader (gear),
  - Ransom broker (sell prisoners),
  - Gate guard (back to the map).
  Time is paused in town.
- Contracts (the quest board at the employer's town; accept or decline freely):
  - Raid:
    - Storm an enemy castle. A win gives the castle to your employer: its banner changes, you get a capture bonus, and it starts with a weak garrison.
    - You stay a mercenary and don't own it.
  - Raid Village: plunder an enemy village.
  - Bounty: hunt a named bandit warband whose leader is a boss squad.
  - Escort: the caravan leaves when you join it, bandits ambush it on the way, and it's plundered if you stray.
  - Defend:
    - When an enemy general besieges one of your employer's castles, a Defend contract for that siege is posted with a fixed assault day.
    - If you're there, you fight his army; otherwise the garrison fights alone (auto-resolved).
    - Enemy generals try to retake captured castles first.
  Success pays gold + reputation; failure (deadline, caravan lost, castle fallen, abandoned) costs reputation.
- Village raiding:
  - Takes a short time, and moving away cancels it.
  - Gives gold and sometimes loot.
  - Lowers the village's prosperity, which reduces its kingdom's recruits; it recovers slowly.
  - AI generals raid too.
- Enlisting when poor: join your employer's general, march with him, earn a daily wage and loot share, and lead one of his squads in battle (promotions: Recruit → Veteran → Sergeant → Lieutenant). Your own company stays in camp. Leave service anytime.
- Company management:
  - Wages: every squad costs a small daily wage. Unpaid troops lose morale, then desert.
  - Wounded vs dead: about 70% of the fallen are only wounded (fewer if the squad routed or was overrun). They heal over days, faster in a friendly town or castle. The wounded count shows next to the headcount. AI armies follow the same rule.
  - Squad XP and evolution: every ★ tier raises HP, damage and morale and gives better-looking kit. At ★★ the squad chooses a branch.
  - A squad wiped out is gone for good.
  - Prisoners: enemies who flee when you win are captured, up to a capacity. Recruit some as a new squad, or ransom them.
  - Named companions (officers with skills such as Drillmaster +50% XP or Surgeon: more wounded, fewer dead) lead a squad on their own AI. If they fall, they're only wounded for a few days.
  - Inventory screen (I): gear, prisoners, officers.
- Reputation with the employer earns rank titles. Losing a battle outside a contract costs no reputation.
- Defeat: lose a share of your gold and fall back to your town. With no army and no gold, a free levy joins you.
- Save everything in DataStore (profile.Campaign): faction, gold, reputation, day, castle owners, garrisons, captured castles, village prosperity, roster (each squad's unit, XP, men, wounded, companion), prisoners, gear, items, companions, unpaid days. Include "New campaign". Several players each run their own campaign; battles take turns on the one battlefield.

====================================================================
9. DELIVERY
====================================================================
- Build it in phases, commit and test each one:
  1. Squads / soldiers and battle.
  2. Orders and AI.
  3. Campaign and overworld.
  4. Town, contracts and economy.
  5. Sieges.
- After each phase, give me a short list of: what works, every PLACEHOLDER number, every conflict you flagged, and how to update and test in Studio.
