# Dot War

A 2D real-time tactics game in the browser. Blue dots against red dots, with tanks, trucks,
drones, artillery and tactical missiles, on a 7.2 km battlefield cut in half by a river.

**Play:** open `index.html` in a browser. No build step and no install; everything (art,
effects, sound) is generated in code.

## How to win

- 9 capture points. Each one pays +4 supply/s on top of your base +14/s.
- After the first minute, the side holding fewer points bleeds 0.7 tickets/s per point behind
  (capped at 4), and every lost unit costs tickets.
  Run out and you lose.
- Destroying the enemy HQ wins outright. It is guarded by two bunker turrets.

## Units

| Barracks | | Motor pool | |
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

The enemy general plays by the same rules (no map hacks, same fog). It remembers what it has
seen, counter-builds against your army, forms task forces, attacks points with enough force,
pincers from two sides (Elite and up), leaves garrisons, retreats from losing fights,
reinforces worn squads, keeps artillery behind the front, posts scouts and snipers in cover,
lays mines on roads, dodges incoming strikes, focuses fire and pulls wounded vehicles back for
repairs. Recruit / Veteran / Elite / General set how fast and how cleverly it does all that.

## Controls

| Input | Action |
|---|---|
| Left-click / drag | Select (double-click: all of that type on screen) |
| Right-click | Move, or attack an enemy |
| A + click, Ctrl + right-click | Attack-move |
| Q + click | Use ability (barrage, missile, drone, mine) |
| E | Toggle auto-cast |
| S / H | Stop / hold position |
| Ctrl + 1–9, 1–9 | Save / recall group (press twice to jump to it) |
| Arrows, WASD, screen edge, middle-drag, wheel | Camera |
| HQ selected + right-click | Set rally point |
| P or Esc / M | Pause / sound |

Touch: tap to select or move, drag to pan, pinch to zoom, hold then drag to box-select.

## Code

| File | What it holds |
|---|---|
| `js/data.js` | Every number: units, weapons, abilities, products, difficulty |
| `js/core.js` | Math, RNG, spatial hash, heap, synthesized audio |
| `js/map.js` | Symmetric map generation, A* pathfinding, terrain rendering |
| `js/fx.js` | Particles, tracers, explosions, lights, ground decals |
| `js/draw.js` | Unit artwork |
| `js/entities.js` | Simulation: movement, combat, drones, missiles, vision, capture, economy |
| `js/ai.js` | The AI commander |
| `js/game.js` | Main loop, camera, rendering, input, HUD, menus |
