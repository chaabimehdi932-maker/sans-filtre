# Dot War

A 2D war game in the browser. Two AI generals fight a full-scale battle (blue dots against red
dots, with tanks, trucks, drones, artillery and tactical missiles) on a 7.2 km battlefield cut
in half by a river. **You lead one squad on the blue side.** Pick any of the 20 unit types and
fight the way that unit fights: call each howitzer shot, fly kamikaze drones by hand, snipe
officers, or take the bridges with a rifle squad.

**Play:** open `index.html` in a browser. No build step and no install; everything (art,
effects, sound) is generated in code.

## Your squad

- Pick a squad when the battle starts. Infantry can deploy on any point blue holds that is not
  under attack; vehicles roll out of the HQ.
- Command gives you orders that fit your squad (capture or defend a point, fire missions,
  hunt vehicles, pick off soldiers, scout, support a push). Finish them for bonus points.
- Lost soldiers come back while your squad rests near the HQ, a point blue holds or a supply
  truck, out of combat.
- When your squad is wiped out, pick another one, or take over any allied squad already in
  the field (Tab, or click an allied squad and press T). Your old squad goes back to the
  allied general.
- Score: kills, vehicles destroyed, points captured near you, missions.

## How the war is won

- 9 capture points. Each one pays its side +4 supply/s on top of a base +14/s, which the
  generals spend on new units.
- After the first minute, the side holding fewer points bleeds 0.7 tickets/s per point behind
  (capped at 4), and every lost unit costs tickets. Run out and that side loses.
- Destroying the enemy HQ wins outright. It is guarded by two bunker turrets.

## Units

| Infantry | | Vehicles | |
|---|---|---|---|
| Rifle Squad (×6) | all-rounder | Light Tank | fast flanker |
| MG Team (×2) | sets up, pins infantry | Battle Tank | heavy armor, weak rear |
| Medics (×2) | heal infantry | Radar Truck | 950 m sight, counter-battery |
| Officer | aura: aim, speed, morale | AA Gun | kills drones and missiles |
| Scouts (×2) | long sight, hidden when still | Howitzer | 1650 m artillery |
| Sniper | one-shot kills at 590 m | Missile Launcher | tactical missile anywhere in sight |
| Drone Operator | kamikaze FPV drones | MLRS | 12-rocket salvo |
| Anti-Tank (×2) | rockets vs armor | Supply Truck | repairs, +2 supply/s on a point |
| Engineers (×2) | repair, satchels, AT mines | | |
| Radio Operator | 9-shell barrage | | |
| EW Jammer | drones crash near him | | |
| Grenadiers (×4) | blast infantry out of cover | | |

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
seen, counter-builds against the other army, forms task forces, attacks points with enough
force, pincers from two sides (Elite and up), leaves garrisons, retreats from losing fights,
reinforces worn squads, keeps artillery behind the front, posts scouts and snipers in cover,
lays mines on roads, dodges incoming strikes, focuses fire and pulls wounded vehicles back for
repairs. The allied general plays at Veteran; the menu sets the enemy general from Recruit to
General.

## Controls

| Input | Action |
|---|---|
| Right-click | Move (right-click a capture point to spread out on it), or attack an enemy |
| Left-click enemy | Attack it |
| Left-click ground | Fire at that spot: howitzer, MLRS, tanks, AT rockets, grenades |
| Q | Ability: launch a drone, call a barrage, fire the missile, lay a mine |
| Mouse / left-click while a drone is up | Steer the drone / detonate it |
| A + click, Ctrl + right-click | Attack-move |
| E | Auto-fire: let your squad pick its own targets |
| S / H | Stop / hold position |
| Tab | Change squad |
| Click an allied squad, then T | Take it over |
| Drag, arrows, screen edge, wheel | Look around and zoom (the camera follows your squad) |
| Space | Snap the camera back to your squad |
| P or Esc / M | Pause / sound |

Touch: tap the ground to move, tap an enemy to attack, hold to fire at a spot, drag to look
around, pinch to zoom.

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
| `js/squad.js` | Your squad: deploying, taking over squads, reinforcements, missions, score |
| `js/game.js` | Main loop, camera, rendering |
| `js/ui.js` | Input, HUD, squad picker, menus |
