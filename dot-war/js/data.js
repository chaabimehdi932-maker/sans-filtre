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

// The squads you can lead. Every one is a team of several units built around one job.
// members: [unit type, count]. role picks the kind of orders command gives you.
const SQUADS = [
  { id: 'rifle', name: 'Rifle Squad', members: [['officer', 1], ['rifleman', 5], ['mgunner', 1], ['medic', 1]], role: 'capture',
    desc: 'A squad leader, five riflemen, a machine gunner and a medic. The all-rounder of the war.', good: 'Taking and holding points', bad: 'Tanks, artillery',
    hint: 'Right-click to move or attack. Right-click a capture point to spread out on it; your officer captures 3× faster.' },
  { id: 'assault', name: 'Assault Squad', members: [['officer', 1], ['grenadier', 4], ['engineer', 2]], role: 'capture',
    desc: 'Grenadiers and satchel-carrying engineers. Clears forests and blows up armor that gets too close.', good: 'Troops in cover, armor up close', bad: 'Long-range fire',
    hint: 'Left-click a spot to throw grenades there. Engineers throw satchels at nearby armor. Q lays an AT mine.' },
  { id: 'mg', name: 'Heavy Weapons Squad', members: [['mgunner', 3], ['rifleman', 2], ['medic', 1]], role: 'capture',
    desc: 'Three machine guns with riflemen and a medic. Hold a point and nothing on foot gets through.', good: 'Infantry attacks', bad: 'Tanks, artillery',
    hint: 'Machine guns stop for a second to set up, then shred and pin infantry. Dig in on a point and let them come.' },
  { id: 'at', name: 'Anti-Tank Squad', members: [['antitank', 4], ['engineer', 1], ['rifleman', 2]], role: 'hunt',
    desc: 'Four rocket launchers, an engineer and two riflemen for cover. Built to kill tanks.', good: 'Tanks and trucks', bad: 'Infantry swarms',
    hint: 'Left-click a spot or an enemy to fire every rocket. Hit tanks from the side or rear for more damage. Q lays an AT mine.' },
  { id: 'sniper', name: 'Sniper Team', members: [['sniper', 3], ['scout', 1]], role: 'snipe',
    desc: 'Three snipers and a spotter. Hidden while still, deadly at 590 m.', good: 'Officers, MGs, specialists', bad: 'Vehicles, artillery',
    hint: 'Stand still to hide. Left-click an enemy and all three snipers take the shot. The scout sees far ahead.' },
  { id: 'recon', name: 'Recon Team', members: [['scout', 3], ['radioop', 1]], role: 'recon',
    desc: 'Three scouts and a radio operator. Find the enemy, then drop a barrage on them.', good: 'Vision, calling artillery', bad: 'Direct fights',
    hint: 'Scouts hide when still and see 590 m. Q calls a 9-shell barrage on anything your side can see.' },
  { id: 'drone', name: 'Drone Team', members: [['droneop', 3], ['jammer', 1], ['rifleman', 2]], role: 'hunt',
    desc: 'Three FPV drone pilots, a jammer to keep enemy drones off them and two riflemen.', good: 'Tanks, artillery', bad: 'Jammers, AA guns',
    hint: 'Q launches a drone: steer it with the mouse, left-click to detonate. With three pilots another drone is usually ready.' },
  { id: 'fires', name: 'Fire Support Team', members: [['radioop', 2], ['scout', 1], ['rifleman', 2]], role: 'fire',
    desc: 'Two radio operators with a spotter and an escort. Calls barrage after barrage.', good: 'Dug-in groups', bad: 'Fast movers',
    hint: 'Q calls a 9-shell barrage on anything your side can see. Two radios: two barrages before the cooldown.' },
  { id: 'eng', name: 'Combat Engineers', members: [['engineer', 4], ['rifleman', 2], ['medic', 1]], role: 'support',
    desc: 'Four engineers, two riflemen and a medic. Repairs tanks, mines roads, blows up armor.', good: 'Repairs, ambushes', bad: 'Infantry at range',
    hint: 'Engineers repair friendly vehicles nearby on their own. Q lays an AT mine on a road the enemy uses.' },
  { id: 'tanks', name: 'Tank Platoon', members: [['heavytank', 2], ['lighttank', 1]], role: 'capture',
    desc: 'Two battle tanks and a light tank. The hammer of the army.', good: 'Everything up front', bad: 'Drones, mines, flanking AT',
    hint: 'Left-click to fire every cannon at a spot. Keep your front toward the enemy: hits from behind deal 1.5× damage.' },
  { id: 'cav', name: 'Light Armor Platoon', members: [['lighttank', 3], ['aa', 1]], role: 'capture',
    desc: 'Three fast light tanks with an AA gun riding along to swat drones.', good: 'Flanks, raids, infantry', bad: 'Battle tanks, AT squads',
    hint: 'Left-click to fire the cannons at a spot. You are fast: go around and hit them from the side.' },
  { id: 'arty', name: 'Artillery Battery', members: [['howitzer', 3], ['radar', 1], ['supply', 1]], role: 'fire',
    desc: 'Three 155 mm howitzers, a radar truck to find targets and a supply truck to keep them running.', good: 'Static targets, clusters', bad: 'Drones, raids',
    hint: 'Park, then left-click anywhere 320–1650 m away: all three guns fire. Spotted targets are hit more accurately.' },
  { id: 'rockets', name: 'Rocket Battery', members: [['mlrs', 2], ['radar', 1]], role: 'fire',
    desc: 'Two rocket launchers and a radar truck. 24 rockets in one click.', good: 'Infantry, area denial', bad: 'Drones, raids',
    hint: 'Park, then left-click a spot 380–1450 m away for a 24-rocket salvo. 24 s reload.' },
  { id: 'missile', name: 'Missile Battery', members: [['missile', 2], ['aa', 1]], role: 'fire',
    desc: 'Two tactical missile launchers guarded by an AA gun.', good: 'Big groups, the enemy HQ', bad: 'AA guns, the 70 s reload',
    hint: 'Q or left-click a spot your side can see to launch a missile. Each launcher reloads in 70 s.' },
  { id: 'aa', name: 'Air Defense Platoon', members: [['aa', 2], ['radar', 1], ['supply', 1]], role: 'support',
    desc: 'Two AA guns, a radar and a supply truck. No drone or missile gets through.', good: 'Drones, missiles, infantry', bad: 'Tanks, AT',
    hint: 'Your guns shoot down drones and missiles on their own. Escort the tanks and the artillery.' },
];
for (const k of SQUADS) {
  k.size = k.members.reduce((a, [, n]) => a + n, 0);
  k.cost = k.members.reduce((a, [t, n]) => a + UNITS[t].value * n, 0);
  k.cls = k.members.every(([t]) => UNITS[t].cls === 'inf') ? 'inf' : 'veh';
  k.lead = k.members[0][0];
}
const SQUAD_BY_ID = {};
for (const k of SQUADS) SQUAD_BY_ID[k.id] = k;
