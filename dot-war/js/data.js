'use strict';
// =====================================================================
// DOT WAR — static data: world size, teams, weapons, units, products
// =====================================================================

const W = 7200, H = 4400;          // world size (px = metres)
const CELL = 40;                   // terrain / fog / nav cell
const GW = W / CELL, GH = H / CELL;
const GS = 0.5;                    // ground canvas scale (terrain + decals)
const POP_CAP = 200;

const TEAM = [
  { id: 0, name: 'BLUE', main: '#33a8ff', dark: '#1b78c4', deep: '#0c3a63', light: '#a6dcff', rgb: '51,168,255' },
  { id: 1, name: 'RED', main: '#ff4f3f', dark: '#c4281c', deep: '#5c120c', light: '#ffb0a6', rgb: '255,79,63' },
];
const INK = '#101010';
const GUN = '#2a2a2a';

// vs: damage multiplier by target class. air: accuracy multiplier against drones (0 = cannot target air)
const WEAPONS = {
  rifle:    { range: 270, dmg: 12, cd: 1.15, acc: 0.56, kind: 'bullet', tracer: 0, air: 0.22, sup: 3, vs: { inf: 1, veh: 0.05, bld: 0.05, air: 1 }, snd: 'rifle', moveFire: true, muzzle: 1.2 },
  carbine:  { range: 240, dmg: 10, cd: 0.85, acc: 0.55, kind: 'bullet', tracer: 0, air: 0.22, sup: 3, vs: { inf: 1, veh: 0.04, bld: 0.04, air: 1 }, snd: 'rifle', moveFire: true, muzzle: 1.0 },
  pistol:   { range: 170, dmg: 9, cd: 0.9, acc: 0.5, kind: 'bullet', tracer: 0, air: 0, sup: 2, vs: { inf: 1, veh: 0.02, bld: 0.02 }, snd: 'pistol', moveFire: true, muzzle: 0.8 },
  smg:      { range: 185, dmg: 7, cd: 0.2, acc: 0.42, kind: 'bullet', tracer: 0, air: 0.15, sup: 3, vs: { inf: 1, veh: 0.03, bld: 0.03, air: 1 }, snd: 'pistol', moveFire: true, muzzle: 1.0 },
  mg:       { range: 345, dmg: 8, cd: 0.095, burst: 11, rest: 1.25, acc: 0.42, kind: 'bullet', tracer: 1, air: 0.3, sup: 10, deploy: 1.0, vs: { inf: 1, veh: 0.06, bld: 0.06, air: 1 }, snd: 'mg', muzzle: 1.7 },
  sniper:   { range: 590, dmg: 96, cd: 4.2, acc: 0.9, kind: 'bullet', tracer: 2, air: 0, sup: 40, deploy: 0.5, vs: { inf: 1, veh: 0.03, bld: 0.02 }, snd: 'sniper', muzzle: 2.1 },
  atrocket: { range: 365, dmg: 270, cd: 6.5, acc: 0.86, kind: 'rocket', speed: 480, splash: 26, sup: 20, air: 0, vs: { inf: 0.35, veh: 1, bld: 0.85 }, prefer: 'veh', snd: 'rocket', muzzle: 1.3 },
  satchel:  { range: 75, dmg: 460, cd: 14, acc: 1, kind: 'throw', splash: 42, air: 0, vs: { inf: 0.45, veh: 1, bld: 1.3 }, only: ['veh', 'bld'], snd: 'throw', moveFire: true, muzzle: 0.5 },
  grenade:  { range: 215, dmg: 58, cd: 7, acc: 0.82, kind: 'grenade', splash: 52, sup: 35, air: 0, vs: { inf: 1, veh: 0.3, bld: 0.35 }, snd: 'throw', moveFire: true, muzzle: 0.5 },
  cannonL:  { range: 405, dmg: 125, cd: 2.4, acc: 0.86, kind: 'shell', speed: 1150, splash: 30, sup: 25, air: 0, vs: { inf: 0.7, veh: 1, bld: 0.9 }, snd: 'cannon', moveFire: true, turret: true },
  cannonH:  { range: 455, dmg: 255, cd: 3.6, acc: 0.88, kind: 'shell', speed: 1250, splash: 42, sup: 35, air: 0, vs: { inf: 0.6, veh: 1, bld: 1 }, snd: 'cannonH', moveFire: true, turret: true },
  coax:     { range: 300, dmg: 7, cd: 0.12, burst: 8, rest: 1.1, acc: 0.4, kind: 'bullet', tracer: 1, air: 0.3, sup: 7, vs: { inf: 1, veh: 0.03, bld: 0.03, air: 1 }, snd: 'mg', moveFire: true },
  aa:       { range: 400, airRange: 620, dmg: 16, cd: 0.075, burst: 12, rest: 0.8, acc: 0.5, air: 0.75, kind: 'bullet', tracer: 3, sup: 14, preferAir: true, intercept: true, vs: { inf: 1, veh: 0.18, bld: 0.12, air: 1.6 }, snd: 'aa', moveFire: true, turret: true },
  howitzer: { range: 1650, min: 320, dmg: 190, cd: 6.5, acc: 1, kind: 'arty', splash: 85, sup: 50, scatter: 0.05, deploy: 2, air: 0, vs: { inf: 1, veh: 0.8, bld: 1.1 }, snd: 'howitzer', arty: true },
  mlrs:     { range: 1450, min: 380, dmg: 62, cd: 24, salvo: 12, salvoGap: 0.2, acc: 1, kind: 'mrocket', splash: 56, sup: 35, scatter: 0.085, deploy: 1.5, air: 0, vs: { inf: 1, veh: 0.7, bld: 0.8 }, snd: 'mlrs', arty: true },
  sponson:  { range: 380, dmg: 100, cd: 2.4, acc: 0.8, kind: 'shell', speed: 900, splash: 36, sup: 30, air: 0, vs: { inf: 0.85, veh: 0.9, bld: 1.1 }, snd: 'cannon', moveFire: true, turret: true },
  armgun:   { range: 340, dmg: 22, cd: 0.45, acc: 0.55, kind: 'bullet', tracer: 1, air: 0.3, sup: 12, vs: { inf: 1, veh: 0.3, bld: 0.15, air: 1 }, snd: 'aa', moveFire: true, turret: true },
  tcannon:  { range: 470, dmg: 150, cd: 2.8, acc: 0.85, kind: 'shell', speed: 1200, splash: 34, sup: 25, air: 0, vs: { inf: 0.7, veh: 1, bld: 0.5 }, snd: 'cannon', turret: true },
  jeepmg:   { range: 330, dmg: 8, cd: 0.1, acc: 0.45, kind: 'bullet', tracer: 1, air: 0.35, sup: 8, vs: { inf: 1, veh: 0.05, bld: 0.03, air: 1 }, snd: 'mg', moveFire: true, turret: true },
  hallmg:   { range: 380, dmg: 8, cd: 0.11, burst: 10, rest: 1.2, acc: 0.42, kind: 'bullet', tracer: 1, air: 0.3, sup: 9, vs: { inf: 1, veh: 0.04, bld: 0.03, air: 1 }, snd: 'mg' },
  tmg:      { range: 360, dmg: 8, cd: 0.1, burst: 10, rest: 0.9, acc: 0.45, kind: 'bullet', tracer: 1, air: 0.35, sup: 9, vs: { inf: 1, veh: 0.04, bld: 0.03, air: 1 }, snd: 'mg' },
};

// Every unit. Infantry are dots (r), vehicles are boxes (len x wid), facing +x in local space.
const UNITS = {
  rifleman:  { name: 'Rifleman', cls: 'inf', hp: 100, speed: 52, vision: 330, r: 9, weapons: ['rifle'], role: 'line' },
  mgunner:   { name: 'Machine Gunner', cls: 'inf', hp: 115, speed: 43, vision: 350, r: 9, weapons: ['mg'], role: 'line' },
  medic:     { name: 'Medic', cls: 'inf', hp: 90, speed: 54, vision: 300, r: 9, weapons: ['pistol'], role: 'support', heal: { rate: 11, range: 150 } },
  officer:   { name: 'Officer', cls: 'inf', hp: 150, speed: 52, vision: 390, r: 9, weapons: ['rifle'], role: 'support', aura: 230, capture: 3 },
  scout:     { name: 'Scout', cls: 'inf', hp: 80, speed: 69, vision: 590, r: 9, weapons: ['carbine'], role: 'recon', camo: true, detect: 260 },
  sniper:    { name: 'Sniper', cls: 'inf', hp: 80, speed: 45, vision: 560, r: 9, weapons: ['sniper'], role: 'recon', camo: true, detect: 180 },
  droneop:   { name: 'Drone Operator', cls: 'inf', hp: 90, speed: 49, vision: 330, r: 9, weapons: ['pistol'], role: 'at', ability: 'drone' },
  antitank:  { name: 'Anti-Tank', cls: 'inf', hp: 100, speed: 47, vision: 330, r: 9, weapons: ['atrocket', 'pistol'], role: 'at' },
  engineer:  { name: 'Engineer', cls: 'inf', hp: 100, speed: 49, vision: 320, r: 9, weapons: ['smg', 'satchel'], role: 'at', repair: { rate: 18, range: 95 }, ability: 'mine' },
  radioop:   { name: 'Radio Operator', cls: 'inf', hp: 100, speed: 49, vision: 370, r: 9, weapons: ['pistol'], role: 'support', ability: 'barrage' },
  jammer:    { name: 'EW Jammer', cls: 'inf', hp: 100, speed: 49, vision: 340, r: 9, weapons: ['carbine'], role: 'support', jam: 230 },
  grenadier: { name: 'Grenadier', cls: 'inf', hp: 105, speed: 49, vision: 320, r: 9, weapons: ['rifle', 'grenade'], role: 'line' },

  // vehicle keys are historical: radar = armoured car, aa = flak half-track, howitzer = SP gun,
  // missile = V-2, mlrs = Katyusha, supply = cargo lorry
  lighttank: { name: 'Light Tank', cls: 'veh', hp: 950, speed: 92, vision: 410, len: 48, wid: 26, turn: 2.3, tturn: 3.2, weapons: ['cannonL', 'coax'], role: 'armor', pop: 4 },
  heavytank: { name: 'Heavy Tank', cls: 'veh', hp: 2100, speed: 58, vision: 430, len: 60, wid: 34, turn: 1.45, tturn: 1.7, weapons: ['cannonH', 'coax'], role: 'armor', pop: 6 },
  radar:     { name: 'Armored Car', cls: 'veh', hp: 620, speed: 125, vision: 720, len: 46, wid: 24, turn: 2.4, tturn: 4, weapons: ['armgun'], role: 'support', detect: 500, pop: 3 },
  aa:        { name: 'Flak Half-track', cls: 'veh', hp: 760, speed: 82, vision: 540, len: 52, wid: 24, turn: 2.0, tturn: 4.5, weapons: ['aa'], role: 'aa', pop: 4 },
  howitzer:  { name: 'SP Gun', cls: 'veh', hp: 700, speed: 62, vision: 360, len: 58, wid: 28, turn: 1.6, weapons: ['howitzer'], role: 'arty', pop: 5 },
  missile:   { name: 'V-2 Launcher', cls: 'veh', hp: 560, speed: 58, vision: 360, len: 76, wid: 26, turn: 1.5, weapons: [], role: 'arty', ability: 'missile', pop: 6, truck: true },
  mlrs:      { name: 'Katyusha', cls: 'veh', hp: 520, speed: 80, vision: 360, len: 58, wid: 26, turn: 1.9, weapons: ['mlrs'], role: 'arty', pop: 5, truck: true },
  supply:    { name: 'Cargo Truck', cls: 'veh', hp: 600, speed: 105, vision: 340, len: 56, wid: 26, turn: 2.3, weapons: [], role: 'logi', pop: 2, truck: true, repairAura: { range: 170, veh: 22, inf: 7 }, cargoCap: 240 },
  landship:  { name: 'Landship', cls: 'veh', hp: 2600, speed: 34, vision: 380, len: 64, wid: 42, turn: 1.0, tturn: 2.2, weapons: ['sponson', 'coax'], role: 'armor', pop: 6 },

  jeep:      { name: 'Jeep', cls: 'veh', hp: 380, speed: 160, vision: 380, len: 36, wid: 20, turn: 2.8, tturn: 6, weapons: ['jeepmg'], role: 'support', pop: 0, truck: true, value: 120 },

  hq:        { name: 'Headquarters', cls: 'bld', hp: 9000, speed: 0, vision: 560, r: 92, weapons: [], role: 'bld', base: true },
  turret:    { name: 'Bunker Turret', cls: 'bld', hp: 1800, speed: 0, vision: 500, r: 26, weapons: ['tcannon', 'tmg'], role: 'bld' },
  townhall:  { name: 'Town Hall', cls: 'bld', hp: 2400, speed: 0, vision: 520, r: 36, weapons: ['hallmg'], role: 'bld', base: true },
  // things you build with a hammer (see STRUCTS). line: trench, sandbags and wire lie along the
  // ground; you walk over them and direct fire can't target them, only explosions hurt them
  trench:    { name: 'Trench', cls: 'bld', hp: 1600, speed: 0, vision: 0, r: 60, weapons: [], role: 'bld', struct: true, line: true },
  sandbag:   { name: 'Sandbags', cls: 'bld', hp: 700, speed: 0, vision: 0, r: 30, weapons: [], role: 'bld', struct: true, line: true },
  wire:      { name: 'Barbed Wire', cls: 'bld', hp: 300, speed: 0, vision: 0, r: 40, weapons: [], role: 'bld', struct: true, line: true },
  trap:      { name: 'Tank Trap', cls: 'bld', hp: 1200, speed: 0, vision: 0, r: 12, weapons: [], role: 'bld', struct: true },
  bunker:    { name: 'MG Bunker', cls: 'bld', hp: 2400, speed: 0, vision: 420, r: 20, weapons: ['tmg'], role: 'bld', struct: true },
  tower:     { name: 'Watchtower', cls: 'bld', hp: 800, speed: 0, vision: 680, r: 14, weapons: [], role: 'bld', struct: true, detect: 260 },
  fob:       { name: 'Forward Base', cls: 'bld', hp: 3000, speed: 0, vision: 420, r: 30, weapons: [], role: 'bld', struct: true, base: true },
};

const ABILITIES = {
  drone:   { name: 'FPV Drone', key: 'Q', cd: 11, range: 1100, target: 'unit', desc: 'Fly a kamikaze drone into a target.' },
  barrage: { name: 'Artillery Barrage', key: 'Q', cd: 32, range: 950, radius: 125, shells: 9, dmg: 72, splash: 56, delay: 2.6, target: 'ground', desc: '9 shells hit the area after 2.6 s.' },
  missile: { name: 'V-2 Rocket', key: 'Q', cd: 70, range: 4400, radius: 215, dmg: 1150, target: 'ground', desc: 'Huge warhead. Flak can shoot it down.' },
  mine:    { name: 'Lay AT Mine', key: 'Q', cd: 16, range: 400, target: 'ground', desc: 'Hidden mine that wrecks enemy vehicles.' },
};

// What the player buys. line 0 = barracks, 1 = motor pool
const PRODUCTS = [
  { id: 'rifle', unit: 'rifleman', n: 6, cost: 120, time: 5, line: 0, name: 'Rifle Squad', desc: 'Six riflemen. Cheap, steady, and good at taking and holding points.', good: 'Infantry', bad: 'MG, grenades, artillery' },
  { id: 'mg', unit: 'mgunner', n: 2, cost: 150, time: 6, line: 0, name: 'MG Team', desc: 'Sets up before firing, then shreds and pins down infantry. Pinned troops crawl and miss.', good: 'Infantry blobs', bad: 'Tanks, snipers, artillery' },
  { id: 'medic', unit: 'medic', n: 2, cost: 90, time: 4, line: 0, name: 'Medics', desc: 'Two medics who patch up wounded infantry nearby.', good: 'Keeping squads alive', bad: 'Anything that shoots' },
  { id: 'officer', unit: 'officer', n: 1, cost: 110, time: 5, line: 0, name: 'Officer', desc: 'Units near him aim better, move faster and shrug off suppression. Captures points 3× faster.', good: 'Buffing a push', bad: 'Snipers' },
  { id: 'scout', unit: 'scout', n: 2, cost: 80, time: 4, line: 0, name: 'Scouts', desc: 'Huge sight range and hidden while standing still. Spots targets for your artillery.', good: 'Vision, finding snipers', bad: 'Direct fights' },
  { id: 'sniper', unit: 'sniper', n: 1, cost: 130, time: 6, line: 0, name: 'Sniper', desc: 'One shot, one kill from 590 m. Hidden while standing still.', good: 'Officers, MGs, specialists', bad: 'Vehicles, scouts' },
  { id: 'drone', unit: 'droneop', n: 1, cost: 170, time: 6, line: 0, name: 'Drone Operator', desc: 'Flies kamikaze FPV drones into targets up to 1100 m away. Automatic, or aim with Q.', good: 'Tanks, artillery', bad: 'Jammers, AA guns' },
  { id: 'at', unit: 'antitank', n: 2, cost: 150, time: 6, line: 0, name: 'Anti-Tank Team', desc: 'Shoulder rockets that crack armor. Hits from behind deal 1.5× damage.', good: 'Tanks and trucks', bad: 'Infantry' },
  { id: 'eng', unit: 'engineer', n: 2, cost: 130, time: 5, line: 0, name: 'Engineers', desc: 'Repair vehicles, throw satchel charges at armor, and lay hidden AT mines with Q.', good: 'Repairs, ambushes', bad: 'Infantry at range' },
  { id: 'radio', unit: 'radioop', n: 1, cost: 150, time: 6, line: 0, name: 'Radio Operator', desc: 'Calls a 9-shell barrage on anything your army can see, 950 m away. Automatic, or aim with Q.', good: 'Dug-in groups', bad: 'Fast movers' },
  { id: 'jammer', unit: 'jammer', n: 1, cost: 110, time: 5, line: 0, name: 'EW Jammer', desc: 'Jams enemy drones within 230 m. They spin out and crash.', good: 'Drones', bad: 'Everything else' },
  { id: 'gren', unit: 'grenadier', n: 4, cost: 140, time: 6, line: 0, name: 'Grenadiers', desc: 'Riflemen with grenades that blast infantry out of cover and forests.', good: 'Infantry in cover', bad: 'Tanks' },

  { id: 'ltank', unit: 'lighttank', n: 1, cost: 380, time: 12, line: 1, name: 'Light Tank', desc: 'A Stuart-style light tank: fast, with a 37 mm gun and a machine gun. Good for flanks and raids.', good: 'Infantry, trucks', bad: 'AT teams, heavy tanks' },
  { id: 'htank', unit: 'heavytank', n: 1, cost: 680, time: 18, line: 1, name: 'Heavy Tank', desc: 'A Tiger-style heavy tank with a long 88 mm gun. Thick in front, weaker from the sides and rear.', good: 'Everything up front', bad: 'Mines, flanking AT, artillery' },
  { id: 'land', unit: 'landship', n: 1, cost: 560, time: 18, line: 1, name: 'Landship', desc: 'A WW1 rhomboid tank. Crawls along, soaks up fire, and its side guns shoot both ways. Crushes barbed wire.', good: 'Trenches, wire, infantry', bad: 'Faster tanks, AT teams' },
  { id: 'radar', unit: 'radar', n: 1, cost: 300, time: 10, line: 1, name: 'Armored Car', desc: 'Six wheels and a 20 mm gun. Fast scout that sees 720 m, reveals hidden units and exposes enemy artillery when it fires.', good: 'Scouting, infantry', bad: 'Tanks, AT' },
  { id: 'aa', unit: 'aa', n: 1, cost: 340, time: 11, line: 1, name: 'Flak Half-track', desc: 'Quad 20 mm guns on a half-track. Shreds infantry and shoots down drones and V-2s.', good: 'Infantry, drones, V-2s', bad: 'Tanks, AT' },
  { id: 'how', unit: 'howitzer', n: 1, cost: 480, time: 15, line: 1, name: 'SP Gun', desc: 'A Priest-style self-propelled 105 mm gun, 1650 m range. Needs a spotter to see the target.', good: 'Trenches, clusters', bad: 'Raids' },
  { id: 'msl', unit: 'missile', n: 1, cost: 900, time: 25, line: 1, name: 'V-2 Launcher', desc: 'A V-2 rocket on its trailer. Hits anywhere your side can see; both sides see the warning.', good: 'Big groups, the enemy HQ', bad: 'Flak, its 70 s reload' },
  { id: 'mlrs', unit: 'mlrs', n: 1, cost: 600, time: 18, line: 1, name: 'Katyusha', desc: 'Rocket rails on a lorry: a 12-rocket salvo over a wide area, then 24 s to reload.', good: 'Infantry, area denial', bad: 'Raids' },
  { id: 'sup', unit: 'supply', n: 1, cost: 220, time: 8, line: 1, name: 'Cargo Truck', desc: 'Hauls scrap, building materials and supply crates. Resupplies and repairs troops around it.', good: 'Keeping the front supplied', bad: 'Everything' },
];
const PRODUCT_BY_ID = {};
for (const p of PRODUCTS) PRODUCT_BY_ID[p.id] = p;

// derived per-unit values
for (const p of PRODUCTS) {
  const u = UNITS[p.unit];
  u.product = p.id;
  u.value = p.cost / p.n;
  if (!u.pop) u.pop = 1;
}
UNITS.hq.value = 1600; UNITS.hq.pop = 0;
UNITS.jeep.pop = 0;
UNITS.turret.value = 400; UNITS.turret.pop = 0;
UNITS.townhall.value = 900;
for (const k of ['trench', 'sandbag', 'wire', 'trap', 'bunker', 'tower', 'fob']) UNITS[k].value = 60;
for (const k in UNITS) {
  const u = UNITS[k];
  u.key = k;
  // collision radius
  if (!u.r) u.r = Math.max(u.len, u.wid) * 0.42;
  // crude combat strength for the AI
  let dps = 0;
  for (const w of u.weapons) { const d = WEAPONS[w]; const shots = d.burst ? d.burst / (d.burst * d.cd + d.rest) : 1 / d.cd; dps += d.dmg * shots * (d.salvo || 1) * (d.acc || 1); }
  u.dps = dps;
  const support = { support: 0.55, recon: 0.6, arty: 0.8, bld: 1 }[u.role] || 1;
  u.power = Math.max(8, (u.value || 50) * support);
}

const DIFFS = {
  recruit: { name: 'Recruit', think: 2.6, income: 0.85, dodge: false, kite: false, pincer: false, focus: false, retreatRatio: 0.35, minStrike: 260, raid: false },
  veteran: { name: 'Veteran', think: 1.6, income: 1.0, dodge: true, kite: false, pincer: false, focus: true, retreatRatio: 0.5, minStrike: 180, raid: true },
  elite:   { name: 'Elite', think: 1.0, income: 1.15, dodge: true, kite: true, pincer: true, focus: true, retreatRatio: 0.6, minStrike: 150, raid: true },
  general: { name: 'General', think: 0.6, income: 1.35, dodge: true, kite: true, pincer: true, focus: true, retreatRatio: 0.65, minStrike: 130, raid: true },
};

// ---------------------------------------------------------------------
// You: one soldier. Guns you fire by hand, and the classes you can play.
// ---------------------------------------------------------------------
const PLAYER_GUNS = {
  p_rifle:   { name: 'Assault rifle', kind: 'bullet', dmg: 20, cd: 0.13, mag: 30, reload: 2.0, spread: 0.045, range: 330, sup: 5, tracer: 0, auto: true, snd: 'rifle', air: true },
  p_mg:      { name: 'Machine gun', kind: 'bullet', dmg: 15, cd: 0.075, mag: 100, reload: 4.2, spread: 0.085, range: 380, sup: 10, tracer: 1, auto: true, snd: 'mg', air: true },
  p_sniper:  { name: 'Sniper rifle', kind: 'bullet', dmg: 135, cd: 1.1, mag: 5, reload: 2.8, spread: 0.004, range: 700, sup: 40, tracer: 2, auto: false, snd: 'sniper' },
  p_smg:     { name: 'SMG', kind: 'bullet', dmg: 12, cd: 0.07, mag: 35, reload: 1.7, spread: 0.08, range: 230, sup: 3, tracer: 0, auto: true, snd: 'pistol', air: true },
  p_carbine: { name: 'Carbine', kind: 'bullet', dmg: 17, cd: 0.15, mag: 25, reload: 1.9, spread: 0.05, range: 300, sup: 4, tracer: 0, auto: true, snd: 'rifle', air: true },
  p_pistol:  { name: 'Pistol', kind: 'bullet', dmg: 24, cd: 0.2, mag: 12, reload: 1.4, spread: 0.04, range: 220, sup: 2, tracer: 0, auto: false, snd: 'pistol' },
  p_rocket:  { name: 'Rocket launcher', kind: 'rocket', dmg: 330, cd: 0.5, mag: 1, reload: 3.0, spread: 0.01, range: 430, splash: 30, speed: 520, vs: { inf: 0.6, veh: 1, bld: 0.9 }, auto: false, snd: 'rocket' },
};
// mags: spare magazines you carry. Everyone also has a hammer, binoculars and bandages.
const CLASSES = [
  { id: 'rifleman', name: 'Rifleman', unit: 'rifleman', hp: 160, gun: 'p_rifle', mags: 5, nades: 3, role: 'capture',
    desc: 'Assault rifle and three grenades. Takes towns and holds them.', hint: 'Hold right click to aim, left click to fire.' },
  { id: 'mg', name: 'Machine Gunner', unit: 'mgunner', hp: 180, gun: 'p_mg', mags: 3, nades: 2, role: 'capture', speed: 0.9,
    desc: 'A 100-round machine gun that pins infantry down. A bit slower on foot.', hint: 'Long bursts pin enemy infantry: pinned troops crawl and miss. Fire from a trench.' },
  { id: 'sniper', name: 'Sniper', unit: 'sniper', hp: 130, gun: 'p_sniper', mags: 6, nades: 1, role: 'snipe',
    desc: 'One shot, one kill from 700 m. Hidden while standing still.', hint: 'Stand still to stay hidden. Aim fully before each shot.' },
  { id: 'at', name: 'Anti-Tank', unit: 'antitank', hp: 160, gun: 'p_rocket', mags: 6, nades: 2, role: 'hunt',
    desc: 'A rocket launcher that cracks armor and town halls. Hit tanks from behind for 1.5× damage.', hint: 'One rocket, then reload. Aim for the sides and rear of tanks.' },
  { id: 'medic', name: 'Medic', unit: 'medic', hp: 150, gun: 'p_smg', mags: 4, nades: 2, role: 'capture', bandages: 6,
    desc: 'SMG and a medkit. Heals soldiers around you; Q heals yourself to full.', hint: 'Allies near you heal on their own. Q: patch yourself up (40 s).', ability: 'medkit' },
  { id: 'engineer', name: 'Engineer', unit: 'engineer', hp: 150, gun: 'p_smg', mags: 4, nades: 2, role: 'build', carry: 1.6,
    desc: 'Builds twice as fast, carries more materials, plants AT mines and repairs vehicles.', hint: 'Q drops an AT mine. Hammer (2) builds, repairs and gathers scrap.' },
  { id: 'radio', name: 'Radio Operator', unit: 'radioop', hp: 150, gun: 'p_carbine', mags: 4, nades: 2, role: 'fire',
    desc: 'Carbine and a radio. Calls a 9-shell artillery barrage anywhere your side can see.', hint: 'Q, then click where the barrage should land (950 m). Binoculars (3) spot targets.' },
  { id: 'drone', name: 'Drone Operator', unit: 'droneop', hp: 150, gun: 'p_carbine', mags: 4, nades: 2, role: 'hunt',
    desc: 'Carbine and kamikaze FPV drones. You fly them yourself.', hint: 'Q launches a drone: steer with the mouse, click to detonate.' },
  { id: 'driver', name: 'Logistics', unit: 'rifleman', icon: 'supply', hp: 150, gun: 'p_carbine', mags: 3, nades: 1, role: 'logi', carry: 1.6,
    desc: 'Drive cargo trucks: haul scrap to the HQ and supplies to the towns. The front moves with your trucks.', hint: 'Get in a cargo truck (E). Stop in a scrap field to load scrap. F at a base loads or unloads.' },
];
const CLASS_BY_ID = {};
for (const c of CLASSES) CLASS_BY_ID[c.id] = c;

// ---------------------------------------------------------------------
// Supply chain. Scrap is hammered out of scrap fields (or loaded into a
// cargo truck parked in one). Any base turns scrap into building materials
// (bmats); only the HQ turns bmats into supplies (ammo, grenades, bandages),
// so supplies have to be trucked to the towns and forward bases.
// Infantry costs supplies, vehicles cost bmats, structures cost bmats.
// ---------------------------------------------------------------------
const LOGI = {
  hqScrap: 4,          // scrap/s the HQ salvages on its own
  townScrap: 1,        // extra scrap/s at the HQ for every town you hold
  refineHQ: 24,        // scrap -> bmats per second at the HQ
  refineBase: 4,       // ... at a town hall or forward base
  factory: 7,          // bmats -> supplies per second, HQ only
  gather: 16,          // scrap/s a truck loads while parked in a scrap field
  hammer: 9,           // scrap/s you hammer out of a field on foot
  carry: { scrap: 100, bmats: 100 }, // what you can carry on foot
  infCost: 0.25,       // supplies per point of product cost (infantry)
  vehCost: 0.4,        // bmats per point of product cost (vehicles)
  resupplyInf: 1.5,    // supplies to fully rearm one soldier
  resupplyVeh: 5,      // ... one vehicle
  respawn: 3,          // supplies to respawn you at a base
  baseRange: 300,      // resupply / respawn radius around a base
  hqStart: { scrap: 100, bmats: 420, supplies: 260 },
  townStart: { bmats: 120, supplies: 100 },
  hallCost: 100, hallTime: 16,
  winTowns: 7, winTime: 90,
};
const prodCost = (p) => p.line ? { bmats: Math.round(p.cost * LOGI.vehCost), supplies: 0 } : { bmats: 0, supplies: Math.round(p.cost * LOGI.infCost) };
// shots each unit carries before it needs resupply, and what each weapon uses per shot
const AMMO = { rifleman: 45, mgunner: 350, medic: 30, officer: 45, scout: 60, sniper: 16, droneop: 30, antitank: 14, engineer: 160, radioop: 30, jammer: 60, grenadier: 60, lighttank: 260, heavytank: 300, landship: 320, radar: 300, aa: 700, howitzer: 30, mlrs: 36, jeep: 400 };
const AMMO_USE = { bullet: 1, shell: 6, rocket: 3, grenade: 4, throw: 4, arty: 1, mrocket: 1 };
for (const k in AMMO) UNITS[k].ammo = AMMO[k];

// Towns at the nine old capture points
const TOWN_NAMES = { A: 'Ashford', B: 'Brenmoor', C: 'Calloway', D: 'Dunmore', E: 'Easton Crossing', F: 'Fallow', G: 'Greywater', H: 'Halden', I: 'Ironvale' };

// Structures you build with a hammer. len: lines (trench, sandbags, wire) lie along their facing.
// cover: damage infantry inside take (and how much harder they are to hit); slow: speed for
// enemy infantry walking through. key: the number key that picks it while you hold the hammer.
const STRUCTS = [
  { id: 'trench', key: '4', name: 'Trench', cost: 30, time: 6, len: 120, cover: 0.35, desc: 'Infantry inside take a third of the damage and are much harder to hit.' },
  { id: 'sandbag', key: '5', name: 'Sandbags', cost: 12, time: 3, len: 60, cover: 0.55, desc: 'A low wall. Infantry right behind it take about half damage.' },
  { id: 'wire', key: '6', name: 'Barbed Wire', cost: 10, time: 3, len: 80, slow: 0.3, desc: 'Enemy infantry crawl through it. Tanks and landships crush it.' },
  { id: 'trap', key: '7', name: 'Tank Trap', cost: 18, time: 3, desc: 'A steel hedgehog that blocks vehicles. Infantry walk past it.' },
  { id: 'bunker', key: '8', name: 'MG Bunker', cost: 90, time: 10, desc: 'A concrete nest with a machine gun that fires on its own.' },
  { id: 'tower', key: '9', name: 'Watchtower', cost: 40, time: 6, desc: 'Sees 680 m and spots hidden enemies.' },
  { id: 'fob', key: '0', name: 'Forward Base', cost: 160, time: 14, desc: 'A stockpile you can respawn at and resupply from. Fill it with a truck.' },
];
const STRUCT_BY_ID = {};
for (const st of STRUCTS) STRUCT_BY_ID[st.id] = st;
STRUCT_BY_ID.townhall = { id: 'townhall', name: 'Town Hall', cost: LOGI.hallCost, time: LOGI.hallTime, desc: 'Claims the town for your side.' };
