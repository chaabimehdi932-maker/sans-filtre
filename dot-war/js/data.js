'use strict';
// =====================================================================
// DOT WAR — static data: world size, teams, weapons, units, products
// =====================================================================

const W = 7200, H = 4400;          // world size (px = metres)
const CELL = 40;                   // terrain / fog / nav cell
const GW = W / CELL, GH = H / CELL;
const GS = 0.5;                    // ground canvas scale (terrain + decals)
const POP_CAP = 200;
const START_TICKETS = 1000;
const BLEED = 0.7;                 // tickets/s per point of difference
const START_SUPPLY = 900;
const BASE_INCOME = 14;            // supply per second
const POINT_INCOME = 4;            // per held capture point

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
  mlrs:     { range: 1450, min: 380, dmg: 62, cd: 24, salvo: 12, salvoGap: 0.2, acc: 1, kind: 'mrocket', splash: 56, sup: 35, scatter: 0.085, deploy: 1.5, air: 0, vs: { inf: 1, veh: 0.7, bld: 0.8 }, snd: 'mlrs', turret: true, arty: true },
  tcannon:  { range: 470, dmg: 150, cd: 2.8, acc: 0.85, kind: 'shell', speed: 1200, splash: 34, sup: 25, air: 0, vs: { inf: 0.7, veh: 1, bld: 0.5 }, snd: 'cannon', turret: true },
  jeepmg:   { range: 330, dmg: 8, cd: 0.1, acc: 0.45, kind: 'bullet', tracer: 1, air: 0.35, sup: 8, vs: { inf: 1, veh: 0.05, bld: 0.03, air: 1 }, snd: 'mg', moveFire: true, turret: true },
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

  lighttank: { name: 'Light Tank', cls: 'veh', hp: 950, speed: 92, vision: 410, len: 48, wid: 24, turn: 2.3, tturn: 3.2, weapons: ['cannonL', 'coax'], role: 'armor', pop: 4 },
  heavytank: { name: 'Battle Tank', cls: 'veh', hp: 2100, speed: 60, vision: 430, len: 58, wid: 30, turn: 1.45, tturn: 1.7, weapons: ['cannonH', 'coax'], role: 'armor', pop: 6 },
  radar:     { name: 'Radar Truck', cls: 'veh', hp: 520, speed: 88, vision: 950, len: 56, wid: 26, turn: 2.1, weapons: [], role: 'support', detect: 700, pop: 3, truck: true },
  aa:        { name: 'AA Gun', cls: 'veh', hp: 760, speed: 78, vision: 540, len: 50, wid: 25, turn: 2.0, tturn: 4.5, weapons: ['aa'], role: 'aa', pop: 4 },
  howitzer:  { name: 'Howitzer', cls: 'veh', hp: 600, speed: 70, vision: 360, len: 66, wid: 26, turn: 1.7, weapons: ['howitzer'], role: 'arty', pop: 5, truck: true },
  missile:   { name: 'Missile Launcher', cls: 'veh', hp: 560, speed: 64, vision: 360, len: 68, wid: 28, turn: 1.5, weapons: [], role: 'arty', ability: 'missile', pop: 6, truck: true },
  mlrs:      { name: 'MLRS', cls: 'veh', hp: 560, speed: 72, vision: 360, len: 58, wid: 26, turn: 1.8, tturn: 1.4, weapons: ['mlrs'], role: 'arty', pop: 5, truck: true },
  supply:    { name: 'Supply Truck', cls: 'veh', hp: 650, speed: 98, vision: 340, len: 56, wid: 26, turn: 2.3, weapons: [], role: 'support', pop: 2, truck: true, repairAura: { range: 170, veh: 22, inf: 7 }, capture: 3 },

  jeep:      { name: 'Jeep', cls: 'veh', hp: 380, speed: 165, vision: 380, len: 36, wid: 20, turn: 2.8, tturn: 6, weapons: ['jeepmg'], role: 'support', pop: 0, truck: true, value: 120 },

  hq:        { name: 'Headquarters', cls: 'bld', hp: 9000, speed: 0, vision: 560, r: 92, weapons: [], role: 'bld' },
  turret:    { name: 'Bunker Turret', cls: 'bld', hp: 1800, speed: 0, vision: 500, r: 26, weapons: ['tcannon', 'tmg'], role: 'bld' },
};

const ABILITIES = {
  drone:   { name: 'FPV Drone', key: 'Q', cd: 11, range: 1100, target: 'unit', desc: 'Fly a kamikaze drone into a target.' },
  barrage: { name: 'Artillery Barrage', key: 'Q', cd: 32, range: 950, radius: 125, shells: 9, dmg: 72, splash: 56, delay: 2.6, target: 'ground', desc: '9 shells hit the area after 2.6 s.' },
  missile: { name: 'Tactical Missile', key: 'Q', cd: 70, range: 4400, radius: 215, dmg: 1150, target: 'ground', desc: 'Huge warhead. AA guns can shoot it down.' },
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

  { id: 'ltank', unit: 'lighttank', n: 1, cost: 380, time: 12, line: 1, name: 'Light Tank', desc: 'Fast, with a cannon and a coaxial machine gun. Good for flanks and raids.', good: 'Infantry, trucks', bad: 'AT teams, drones, battle tanks' },
  { id: 'htank', unit: 'heavytank', n: 1, cost: 680, time: 18, line: 1, name: 'Battle Tank', desc: 'Thick armor and a 125 mm gun. Weaker from the sides and rear.', good: 'Everything up front', bad: 'Drones, mines, flanking AT' },
  { id: 'radar', unit: 'radar', n: 1, cost: 300, time: 10, line: 1, name: 'Radar Truck', desc: 'Sees 950 m, reveals hidden units within 700 m, and exposes enemy artillery whenever it fires.', good: 'Vision, counter-battery', bad: 'Anything that reaches it' },
  { id: 'aa', unit: 'aa', n: 1, cost: 340, time: 11, line: 1, name: 'AA Gun', desc: 'Twin autocannons that shoot down drones and tactical missiles. Shreds infantry too.', good: 'Drones, missiles, infantry', bad: 'Tanks, AT' },
  { id: 'how', unit: 'howitzer', n: 1, cost: 480, time: 15, line: 1, name: 'Howitzer', desc: 'Truck-mounted 155 mm gun, 1650 m range. Needs a spotter to see the target.', good: 'Static targets, clusters', bad: 'Drones, raids' },
  { id: 'msl', unit: 'missile', n: 1, cost: 900, time: 25, line: 1, name: 'Missile Launcher', desc: 'Tactical missile that can hit anywhere in sight. Q to aim (E for auto). Both sides see the warning.', good: 'Big groups, the enemy HQ', bad: 'AA guns, its 70 s reload' },
  { id: 'mlrs', unit: 'mlrs', n: 1, cost: 600, time: 18, line: 1, name: 'MLRS', desc: 'Fires a 12-rocket salvo across a wide area, then reloads for 24 s.', good: 'Infantry, area denial', bad: 'Drones, raids' },
  { id: 'sup', unit: 'supply', n: 1, cost: 220, time: 8, line: 1, name: 'Supply Truck', desc: 'Repairs vehicles and heals troops nearby. Earns +2 supply/s while parked on a point you hold.', good: 'Sustaining a push', bad: 'Everything' },
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
for (const k in UNITS) {
  const u = UNITS[k];
  u.key = k;
  u.tickets = u.cls === 'inf' ? 1 : u.cls === 'veh' ? 2 + u.pop : 0;
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
const CLASSES = [
  { id: 'rifleman', name: 'Rifleman', unit: 'rifleman', hp: 160, gun: 'p_rifle', nades: 3, role: 'capture',
    desc: 'Assault rifle and three grenades. Takes points and holds them.', hint: 'Hold left click to fire. Right click throws a grenade. Stand on points to capture them.' },
  { id: 'mg', name: 'Machine Gunner', unit: 'mgunner', hp: 180, gun: 'p_mg', nades: 2, role: 'capture', speed: 0.9,
    desc: 'A 100-round machine gun that pins infantry down. A bit slower on foot.', hint: 'Long bursts pin enemy infantry: pinned troops crawl and miss.' },
  { id: 'sniper', name: 'Sniper', unit: 'sniper', hp: 130, gun: 'p_sniper', nades: 1, role: 'snipe',
    desc: 'One shot, one kill from 700 m. Hidden while standing still.', hint: 'Stand still to stay hidden. Click once per shot; every shot is deadly.' },
  { id: 'at', name: 'Anti-Tank', unit: 'antitank', hp: 160, gun: 'p_rocket', nades: 2, role: 'hunt',
    desc: 'A rocket launcher that cracks armor. Hit tanks from behind for 1.5× damage.', hint: 'One rocket, then reload. Aim for the sides and rear of tanks.' },
  { id: 'medic', name: 'Medic', unit: 'medic', hp: 150, gun: 'p_smg', nades: 2, role: 'capture',
    desc: 'SMG and a medkit. Heals soldiers around you; Q heals yourself to full.', hint: 'Allies near you heal on their own. Q: patch yourself up (40 s).' , ability: 'medkit' },
  { id: 'engineer', name: 'Engineer', unit: 'engineer', hp: 150, gun: 'p_smg', nades: 2, role: 'support',
    desc: 'SMG, AT mines and a wrench. Repairs the vehicle you drive or stand next to.', hint: 'Q drops an AT mine at your feet. Your vehicle repairs itself while you drive it.' },
  { id: 'radio', name: 'Radio Operator', unit: 'radioop', hp: 150, gun: 'p_carbine', nades: 2, role: 'fire',
    desc: 'Carbine and a radio. Calls a 9-shell artillery barrage anywhere your side can see.', hint: 'Q, then click where the barrage should land (950 m).' },
  { id: 'drone', name: 'Drone Operator', unit: 'droneop', hp: 150, gun: 'p_carbine', nades: 2, role: 'hunt',
    desc: 'Carbine and kamikaze FPV drones. You fly them yourself.', hint: 'Q launches a drone: steer with the mouse, click to detonate. Your soldier stands still while you fly.' },
];
const CLASS_BY_ID = {};
for (const c of CLASSES) CLASS_BY_ID[c.id] = c;
