# Dot War

A 2D war game in the browser, in the spirit of Foxhole. Two AI generals fight over nine ruined
towns on a 7.2 km battlefield cut in half by a river. The war runs on supplies: scrap is
hammered out of scrap fields, turned into building materials and then into ammo, and cargo
trucks haul it all to the front. **You are one soldier in the blue army.** Fight from the
trenches, hammer up defences, or drive the trucks that keep the front supplied. Blue and red
dots fight it out with WW1 and WW2 vehicles.

**Play:** open `index.html` in a browser. No build step and no install; everything (art,
effects, sound) is generated in code.

## How the war is won

- **Towns.** A town belongs to whoever has a town hall in it. Wreck the enemy's hall (tanks,
  rockets, satchels and artillery do it fast; soldiers standing in an undefended town wreck it
  slowly), then hammer up your own hall in the empty town.
- Hold **7 of the 9 towns for 90 seconds** in a row, or destroy the enemy HQ, to win.
- Blue starts with Ashford, Brenmoor and Calloway; red with Greywater, Halden and Ironvale.
  Dunmore, Easton Crossing and Fallow sit on the river and start empty.

## The supply chain

| Step | Where |
|---|---|
| **Gather** scrap | Scrap fields: hammer it on foot, or park a cargo truck in one and it loads itself. The HQ also salvages a little on its own, more for every town you hold. |
| **Refine** scrap into building materials (bmats) | Any base: fast at the HQ, slowly at town halls and forward bases |
| **Make** supplies (ammo, grenades, bandages) | The HQ only, from bmats |
| **Deliver** | Cargo trucks carry scrap home and supplies and bmats out to the towns and forward bases |

What supplies pay for:

- The generals buy infantry with supplies and vehicles with bmats. New infantry walks out of a
  supplied town near the front; with no supplies forward, it has to march from the HQ.
- Every soldier and vehicle carries limited ammo and **stops shooting when it runs out**. Units
  rearm near a base or a cargo truck that has supplies. Squads that run dry pull back to rearm.
- Respawning at a town or forward base costs that base supplies. A base with none can't take you.
- Structures cost bmats from your pockets or a base next to you.

Both generals run their own trucks (hauling scrap home, delivering supplies where they are
short) and fortify the towns they hold, so the front moves with the supply lines.

## You

Pick a class; everyone also carries a hammer, binoculars, bandages and spare magazines.

| Class | Gun | Extra |
|---|---|---|
| Rifleman | assault rifle, 3 grenades | |
| Machine Gunner | 100-round machine gun that pins infantry | |
| Sniper | 700 m sniper rifle, hidden while still | |
| Anti-Tank | rocket launcher that homes on vehicles and buildings near the cursor | |
| Medic | SMG, heals soldiers around you | Q: medkit |
| Engineer | SMG; builds twice as fast and carries more | Q: AT mine |
| Radio Operator | carbine | Q: 9-shell artillery barrage |
| Drone Operator | carbine | Q: kamikaze FPV drone you fly with the mouse |
| Logistics | carbine; carries more | starts by a cargo truck at the HQ |

- **Shooting:** hip fire is wild. Hold right click to aim: your shots tighten the longer you
  hold still. Reloading uses a spare magazine; rearm with F at a base or truck.
- **Wounds** bleed until you bandage them (H). A base's medics patch you up; there is no
  health regeneration in the field.
- **Stamina:** sprinting (Shift) drains it; run dry and you have to catch your breath.
- **Cover:** soldiers in a trench take a third of the damage and are much harder to hit;
  behind sandbags, about half.
- **Hammer (2):** hold left click to build blueprints, repair structures and vehicles, or
  hammer scrap out of a scrap field. With the hammer out, 4–0 picks a structure, R turns it
  (the red arrow is the side facing the enemy) and a click places the blueprint.
- **Binoculars (3):** hold right click to look 1000 m out. Whatever you see is spotted for the
  whole army, so the artillery can fire on it.
- **Vehicles:** walk up to a jeep, cargo truck or any friendly vehicle and press E. The turret
  follows the mouse; left click fires the main gun, right click the machine gun. Vehicles
  carry limited ammo too.
- **Trucks:** stop in a scrap field to load scrap. F at a base unloads; at the HQ, F also loads
  supplies and bmats. Troops around your truck rearm from its cargo.
- **Orders:** command gives you a job that fits your class (wreck a town hall, build one,
  defend a town, call fire, hunt vehicles, dig in, deliver supplies, haul scrap).

## Structures

| Structure | bmats | Does |
|---|---|---|
| Trench | 30 | Infantry inside take a third of the damage and are much harder to hit |
| Sandbags | 12 | A low wall: about half damage |
| Barbed wire | 10 | Enemy infantry crawl through it; tanks and landships crush it |
| Tank trap | 18 | Blocks vehicles; infantry walk past |
| MG bunker | 90 | A machine gun that fires on its own |
| Watchtower | 40 | Sees 680 m and spots hidden enemies |
| Forward base | 160 | A stockpile you can respawn at and rearm from |
| Town hall | 100 | Claims an empty town (F in the town) |

Trenches, sandbags and wire lie in the dirt: direct fire can't target them, only explosions.

## Vehicles

Jeep, light tank (Stuart), heavy tank (Tiger), Landship (WW1 rhomboid with side guns that fire
both ways), armored car, flak half-track (quad 20 mm, shoots down drones and V-2s), SP gun
(Priest-style 105 mm), Katyusha rocket lorry, V-2 launcher and cargo truck.

## Mechanics

- Fog of war. Artillery, barrages and V-2s need someone to see the target.
- Infantry in forests take less damage and stay hidden until enemies get close. Scouts and
  snipers also hide while standing still. Armored cars and watchtowers see through it.
- Tanks take 1.5× damage from behind and 1.2× from the side.
- Machine guns and explosions pin infantry: pinned troops crawl and miss.
- Kills promote units to veteran (★, ★★).
- Bridges and fords are the only river crossings.

## The AI

Both generals play by the same rules (no map hacks, same fog, same stockpiles). Each one
remembers what it has seen, counter-builds from 21 unit types within what its stockpiles can
pay for, runs its cargo trucks, forms task forces, wrecks enemy town halls and builds its own,
pincers from two sides, leaves garrisons that dig trenches, wire and bunkers, builds forward
bases behind long pushes, pulls squads back to rearm, retreats from losing fights, keeps
artillery behind the front, posts scouts and snipers, lays mines, dodges incoming strikes and
focuses fire. The allied general plays at Veteran; the menu sets the enemy general from
Recruit to General.

## Controls

| Input | Action |
|---|---|
| WASD, Shift | Move, sprint (in a vehicle: drive) |
| Left click | Shoot (in a vehicle: main gun) · with the hammer: build, repair, gather |
| Hold right click | Aim · with binoculars: look far · in a vehicle: machine gun |
| 1 / 2 / 3 | Gun / hammer / binoculars |
| 4 – 0, R | Pick a structure to build, turn it |
| F | Use: rearm, hand in scrap, take bmats, load and unload trucks, start a town hall |
| G / H | Grenade / bandage |
| R | Reload |
| E | Get in / out of the vehicle next to you |
| Q | Class ability; while flying a drone, click to detonate |
| Tab | Change class |
| Mouse wheel | Zoom |
| P or Esc / M | Pause / sound |

Touch: left thumb moves, right thumb aims and shoots, buttons for aim, use, vehicles, tools,
building, grenades, bandages, ability and reload.

## Code

| File | What it holds |
|---|---|
| `js/data.js` | Every number: units, weapons, classes, supply chain, structures, difficulty |
| `js/core.js` | Math, RNG, spatial hash, heap, synthesized audio |
| `js/map.js` | Symmetric map generation (towns, ruins, scrap fields), A* pathfinding, terrain rendering |
| `js/fx.js` | Particles, tracers, explosions, lights, ground decals |
| `js/draw.js` | Unit, vehicle and structure artwork |
| `js/entities.js` | Simulation: movement, combat, ammo, drones, missiles, vision, production |
| `js/towns.js` | Towns and town halls, stockpiles and trucks, cover, building |
| `js/ai.js` | The AI generals |
| `js/avatar.js` | You: classes, kit, shooting, building, vehicles, orders, score |
| `js/game.js` | Main loop, camera, rendering |
| `js/ui.js` | Input, HUD, class picker, menus |
