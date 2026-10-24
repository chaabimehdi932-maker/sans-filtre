# Dot War

A 2D war game in the browser. Two AI generals fight a full-scale battle (blue dots against red
dots, with tanks, trucks, drones, artillery and tactical missiles) on a 7.2 km battlefield cut
in half by a river. **You are one soldier in the blue army.** Run, shoot and throw grenades,
then jump into a jeep, a tank or any friendly truck and drive it into the fight.

**Play:** open `index.html` in a browser. No build step and no install; everything (art,
effects, sound) is generated in code.

## You

| Class | Gun | Q ability |
|---|---|---|
| Rifleman | assault rifle, 3 grenades | |
| Machine Gunner | 100-round machine gun that pins infantry | |
| Sniper | 700 m sniper rifle, hidden while still | |
| Anti-Tank | rocket launcher that homes on vehicles near the cursor | |
| Medic | SMG, heals soldiers around you | medkit: back to full health |
| Engineer | SMG, repairs the vehicle you drive | AT mine at your feet |
| Radio Operator | carbine | 9-shell artillery barrage |
| Drone Operator | carbine | kamikaze FPV drone you fly with the mouse |

- **Vehicles:** jeeps wait at the HQ (with a mounted machine gun). Walk up to any friendly
  vehicle and press E: jeep, light or battle tank, AA gun, howitzer, MLRS, missile launcher,
  radar or supply truck. The turret follows the mouse; left click fires the main gun, right
  click the machine gun. Drive fast and you run enemy soldiers over. Leave an army vehicle and
  a crew takes it back after 20 s. If your vehicle blows up, you bail out hurt.
- **Health** comes back when you stay out of the fight for a few seconds. You are a bit tougher
  than an ordinary soldier.
- **Respawn:** when you die, pick a class and deploy at the HQ or on any point blue holds that
  is not under attack.
- **Orders:** command gives you a job that fits your class (capture or defend a point, call
  fire on the enemy, destroy a vehicle, pick off soldiers, support a push). Finish it for bonus
  points. Score: kills, vehicles destroyed, points captured, missions.

## How the war is won

- 9 capture points. Each one pays its side +4 supply/s on top of a base +14/s, which the
  generals spend on new units.
- After the first minute, the side holding fewer points bleeds 0.7 tickets/s per point behind
  (capped at 4), and every lost unit costs tickets. Run out and that side loses.
- Destroying the enemy HQ wins outright. It is guarded by two bunker turrets.

## Mechanics

- Fog of war. Artillery, barrages and missiles need someone to see the target.
- Infantry in forests take less damage and stay hidden until enemies get close. Scouts and
  snipers also hide while standing still. Radar trucks see through it.
- Tanks take 1.5× damage from behind and 1.2× from the side.
- Machine guns and explosions pin infantry: pinned troops crawl and miss.
- Kills promote units to veteran (★, ★★).
- Bridges and fords are the only river crossings; pathfinding routes around water and
  vehicles avoid forests.

## The AI

Both generals play by the same rules (no map hacks, same fog). Each one remembers what it has
seen, counter-builds against the other army from 20 unit types, forms task forces, attacks
points with enough force, pincers from two sides, leaves garrisons, retreats from losing
fights, reinforces worn squads, keeps artillery behind the front, posts scouts and snipers in
cover, lays mines on roads, dodges incoming strikes, focuses fire and pulls wounded vehicles
back for repairs. The allied general plays at Veteran; the menu sets the enemy general from
Recruit to General.

## Controls

| Input | Action |
|---|---|
| WASD, Shift | Move, sprint (in a vehicle: drive) |
| Mouse, hold left click | Aim, shoot (in a vehicle: main gun) |
| Right click or G | Grenade (in a vehicle: machine gun) |
| R | Reload |
| E | Get in / out of the vehicle next to you |
| Q | Class ability; while flying a drone, click to detonate |
| Tab | Change class |
| Mouse wheel | Zoom |
| P or Esc / M | Pause / sound |

Touch: left thumb moves, right thumb aims and shoots, buttons for get in/out, grenade,
ability, reload and the vehicle machine gun.

## Code

| File | What it holds |
|---|---|
| `js/data.js` | Every number: units, weapons, abilities, products, difficulty |
| `js/core.js` | Math, RNG, spatial hash, heap, synthesized audio |
| `js/map.js` | Symmetric map generation, A* pathfinding, terrain rendering |
| `js/fx.js` | Particles, tracers, explosions, lights, ground decals |
| `js/draw.js` | Unit artwork |
| `js/entities.js` | Simulation: movement, combat, drones, missiles, vision, capture, economy |
| `js/ai.js` | The AI generals |
| `js/avatar.js` | You: classes, walking, shooting, vehicles, orders, score |
| `js/game.js` | Main loop, camera, rendering |
| `js/ui.js` | Input, HUD, class picker, menus |
