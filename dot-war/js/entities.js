'use strict';
// =====================================================================
// Simulation: units, movement, weapons, projectiles, drones, missiles,
// mines, barrages, vision, capture points and economy
// =====================================================================

let NEXT_ID = 1;

class Unit {
  constructor(type, team, x, y) {
    const d = UNITS[type];
    this.id = NEXT_ID++;
    this.type = type; this.def = d; this.team = team; this.cls = d.cls;
    this.x = x; this.y = y; this.r = d.r;
    this.hp = this.maxHp = d.hp;
    this.ang = team === 0 ? 0 : Math.PI; this.tang = this.ang;
    this.order = null; this.path = null; this.pi = 0;
    this.guard = { x, y };
    this.weapons = d.weapons.map((w) => ({ id: w, def: WEAPONS[w], cd: rand(0, 0.8), burst: 0, target: null, retarget: rand(0, 0.4), salvo: 0, salvoT: 0, aim: null }));
    this.stillT = 0; this.revealT = 0; this.spotT = 0; this.sup = 0;
    this.xp = 0; this.rank = 0; this.kills = 0;
    this.vis = [team === 0, team === 1];
    this.abilityCd = d.ability === 'missile' ? 20 : 0;
    this.auto = !(d.ability === 'missile' && team === G.playerTeam); // your missiles wait for your order
    this.drone = null; this.squad = null; this.override = null; this.focus = null;
    this.dead = false; this.hitFlash = 0; this.recoil = 0; this.anim = rand(0, 10);
    this.trackAcc = 0; this.lastHit = -99; this.moving = false; this.speedNow = 0;
    this.repathT = 0; this.healT = 0; this.mineTarget = null;
  }
  get alive() { return !this.dead; }
}

function spawnUnit(type, team, x, y) {
  const u = new Unit(type, team, x, y);
  G.units.push(u);
  return u;
}

// ---------------------------------------------------------------------
// orders
// ---------------------------------------------------------------------
function formationSlots(units, x, y, ang, spacing) {
  // vehicles in front rows, infantry behind; rows perpendicular to the move direction
  const sorted = units.slice().sort((a, b) => formationRank(a) - formationRank(b));
  const n = sorted.length;
  const cols = Math.max(1, Math.ceil(Math.sqrt(n * 2.2)));
  const fx = Math.cos(ang), fy = Math.sin(ang), rx = -fy, ry = fx;
  const out = new Map();
  let row = 0, col = 0, rowY = 0;
  for (const u of sorted) {
    const sp = (u.cls === 'veh' ? 52 : 24) * spacing;
    const inRow = Math.min(cols, n - row * cols);
    const ox = (col - (inRow - 1) / 2) * sp;
    const oy = -rowY;
    let px = x + rx * ox + fx * oy, py = y + ry * ox + fy * oy;
    if (blockedAt(px, py)) { px = x + rand(-20, 20); py = y + rand(-20, 20); }
    out.set(u, { x: px, y: py });
    col++;
    if (col >= cols) { col = 0; row++; rowY += sp; }
  }
  return out;
}

// shared path for a group; units far from the group get their own
function issueMove(units, x, y, amove, opts = {}) {
  units = units.filter((u) => !u.dead && u.def.speed > 0);
  if (!units.length) return;
  let cx = 0, cy = 0; for (const u of units) { cx += u.x; cy += u.y; } cx /= units.length; cy /= units.length;
  const ang = Math.atan2(y - cy, x - cx);
  const slots = units.length > 1 ? formationSlots(units, x, y, ang, opts.spacing || 1) : new Map([[units[0], { x, y }]]);
  const shared = { inf: null, veh: null };
  for (const u of units) {
    const s = slots.get(u);
    let path;
    if (dist(u.x, u.y, cx, cy) < 380) {
      const k = u.cls === 'veh' ? 'veh' : 'inf';
      if (!shared[k]) shared[k] = findPath(cx, cy, x, y, k);
      path = shared[k].slice(0, -1).concat([{ x: s.x, y: s.y }]);
      // skip waypoints that are behind this unit
      while (path.length > 1 && dist(u.x, u.y, path[1].x, path[1].y) < dist(path[0].x, path[0].y, path[1].x, path[1].y)) path.shift();
    } else path = findPath(u.x, u.y, s.x, s.y, u.cls === 'veh' ? 'veh' : 'inf');
    u.order = { type: amove ? 'amove' : 'move', x: s.x, y: s.y };
    u.path = path; u.pi = 0;
    u.guard = { x: s.x, y: s.y };
    u.focus = null;
    if (!opts.keepOverride) u.override = null;
  }
}
function issueAttack(units, target) {
  for (const u of units) {
    if (u.dead) continue;
    if (!u.weapons.length) { issueMove([u], target.x, target.y, false); continue; }
    u.order = { type: 'attack', target, x: target.x, y: target.y };
    u.path = null; u.pi = 0; u.repathT = 0; u.override = null;
  }
}
function issueStop(units) { for (const u of units) { u.order = null; u.path = null; u.guard = { x: u.x, y: u.y }; u.override = null; } }
function issueHold(units) { for (const u of units) { u.order = { type: 'hold' }; u.path = null; u.guard = { x: u.x, y: u.y }; u.override = null; } }

// ---------------------------------------------------------------------
// per-frame unit update
// ---------------------------------------------------------------------
function auraAt(u) {
  // officer aura: cached per vision tick
  return u.aura ? 1 : 0;
}

function updateUnit(u, dt) {
  const d = u.def;
  u.anim += dt;
  u.hitFlash = Math.max(0, u.hitFlash - dt);
  u.recoil = Math.max(0, u.recoil - dt * 3);
  u.revealT = Math.max(0, u.revealT - dt);
  u.spotT = Math.max(0, u.spotT - dt);
  u.sup = Math.max(0, u.sup - dt * (u.aura ? 30 : 16));
  if (u.abilityCd > 0) u.abilityCd -= dt * (u.supplied ? 1.4 : 1);

  if (d.speed > 0) moveUnit(u, dt);
  updateWeapons(u, dt);
  if (d.heal || d.repair || d.repairAura) supportTick(u, dt);
  if (d.ability) abilityTick(u, dt);
}

function terrainSpeed(u) {
  const t = MAP.terr[cellOf(u.x, u.y)];
  return (u.cls === 'veh' ? SPEED.veh : SPEED.inf)[t];
}

function currentGoal(u, dt) {
  if (u.override) {
    u.override.t -= dt;
    if (u.override.t <= 0 || dist(u.x, u.y, u.override.x, u.override.y) < 10) u.override = null;
    else return u.override;
  }
  const o = u.order;
  if (!o) return null;
  if (o.type === 'hold') return null;
  if (o.type === 'attack' || o.type === 'ability') {
    const t = o.target;
    if (o.type === 'attack') {
      if (!t || t.dead || !t.vis[u.team]) { u.order = null; u.path = null; u.guard = { x: u.x, y: u.y }; return null; }
      const w = u.weapons[0]; const rng = (t.cls === 'air' ? w.def.airRange || w.def.range : w.def.range) + (t.r || 0) - 12;
      if (dist(u.x, u.y, t.x, t.y) <= rng) { u.path = null; return null; }
    }
    const tx = t ? t.x : o.x, ty = t ? t.y : o.y;
    if (o.type === 'ability') {
      if (t && (t.dead || !t.vis[u.team])) { u.order = null; u.path = null; return null; }
      const ab = u.def.ability;
      const rr = ab === 'mine' ? 18 : ABILITIES[ab].range * 0.95;
      if (dist(u.x, u.y, tx, ty) <= rr) { u.path = null; return null; }
    }
    u.repathT -= dt;
    if (!u.path || u.repathT <= 0) { u.path = findPath(u.x, u.y, tx, ty, u.cls === 'veh' ? 'veh' : 'inf'); u.pi = 0; u.repathT = 1.6; }
  }
  if (!u.path || u.pi >= u.path.length) {
    if (o.type === 'move' || o.type === 'amove') { u.order = null; u.path = null; }
    return null;
  }
  const wp = u.path[u.pi];
  const last = u.pi === u.path.length - 1;
  const dd = dist(u.x, u.y, wp.x, wp.y);
  if (dd < (last ? 6 : u.cls === 'veh' ? 34 : 22)) {
    u.pi++;
    if (u.pi >= u.path.length) { if (o.type === 'move' || o.type === 'amove') { u.order = null; u.path = null; } return null; }
    return u.path[u.pi];
  }
  return wp;
}

const _nb = [];
function moveUnit(u, dt) {
  const d = u.def;
  let goal = currentGoal(u, dt);
  // amove: stop to fight anything in range
  if (goal && u.order && u.order.type === 'amove' && !u.override) {
    const w = u.weapons[0];
    if (w && w.target && !w.target.dead && !w.def.moveFire) goal = null;
    else if (w && w.target && !w.target.dead && u.cls === 'inf' && dist(u.x, u.y, w.target.x, w.target.y) < w.def.range * 0.8) goal = null;
  }
  // idle guard: chase visible enemies a short way, then come back
  if (!goal && !u.order && !u.override && u.weapons.length && !d.weapons.some((w) => WEAPONS[w].arty)) {
    const w = u.weapons[0];
    if (w.target && !w.target.dead) {
      const r = w.def.range + (w.target.r || 0) - 10;
      if (dist(u.x, u.y, w.target.x, w.target.y) > r && dist(w.target.x, w.target.y, u.guard.x, u.guard.y) < 420) goal = { x: w.target.x, y: w.target.y };
    } else if (u.chase && !u.chase.dead && u.chase.vis[u.team] && dist(u.chase.x, u.chase.y, u.guard.x, u.guard.y) < 420) {
      goal = { x: u.chase.x, y: u.chase.y };
    } else if (dist(u.x, u.y, u.guard.x, u.guard.y) > 30) goal = u.guard;
  }

  let spd = d.speed * terrainSpeed(u);
  if (u.aura) spd *= 1.12;
  if (u.cls === 'inf' && u.sup > 50) spd *= 0.45;
  if (u.cls === 'veh' && u.hp < u.maxHp * 0.3) spd *= 0.75;

  let vx = 0, vy = 0;
  if (goal) {
    const dx = goal.x - u.x, dy = goal.y - u.y, dd = Math.hypot(dx, dy) || 1;
    const want = Math.atan2(dy, dx);
    if (u.cls === 'veh') {
      u.ang = rotTo(u.ang, want, d.turn * dt);
      const al = Math.cos(angDiff(u.ang, want));
      const s = spd * clamp(al, 0.15, 1) * clamp(dd / 40, 0.3, 1);
      vx = Math.cos(u.ang) * s; vy = Math.sin(u.ang) * s;
    } else {
      const s = Math.min(spd, dd / dt);
      vx = (dx / dd) * s; vy = (dy / dd) * s;
      if (!u.weapons.length || !u.weapons[0].target) u.ang = rotTo(u.ang, want, 8 * dt);
    }
  }
  // separation
  _nb.length = 0;
  const nb = G.grid.query(u.x, u.y, u.r + 26, _nb);
  let px = 0, py = 0;
  for (const o of nb) {
    if (o === u || o.dead || o.cls === 'air') continue;
    const dx = u.x - o.x, dy = u.y - o.y; let dd = Math.hypot(dx, dy);
    const min = (u.r + o.r) * (u.cls === 'inf' && o.cls === 'inf' ? 1.25 : 1.05);
    if (dd >= min) continue;
    if (dd < 0.01) { dd = 0.01; }
    let k = (min - dd) / min;
    if (o.cls === 'bld') k *= 3;
    else if (u.cls === 'veh' && o.cls === 'inf') k *= 0.15;
    else if (u.cls === 'inf' && o.cls === 'veh') k *= 2.2;
    px += (dx / dd) * k; py += (dy / dd) * k;
  }
  vx += px * 90; vy += py * 90;

  const nx = u.x + vx * dt, ny = u.y + vy * dt;
  if (!blockedAt(nx, ny)) { u.x = nx; u.y = ny; }
  else if (!blockedAt(nx, u.y)) u.x = nx;
  else if (!blockedAt(u.x, ny)) u.y = ny;
  else if (goal) u.path = null; // stuck against water: drop the path, it will be rebuilt
  u.x = clamp(u.x, 8, W - 8); u.y = clamp(u.y, 8, H - 8);

  const sp = Math.hypot(vx, vy);
  u.speedNow = sp;
  u.moving = goal != null && sp > 4;
  if (u.moving) u.stillT = 0; else u.stillT += dt;
  if (u.cls === 'veh' && u.moving) {
    u.trackAcc += sp * dt;
    if (u.trackAcc > 9) { u.trackAcc = 0; decalTrack(u); if (Math.random() < 0.25 && terrAt(u.x, u.y) !== T_ROAD) dust(u.x - Math.cos(u.ang) * u.def.len * 0.5, u.y - Math.sin(u.ang) * u.def.len * 0.5, 0.7, 1); }
  }
}

// ---------------------------------------------------------------------
// targeting & weapons
// ---------------------------------------------------------------------
function canTarget(w, t) {
  const d = w.def;
  if (t.cls === 'air') { if (t.isMissile) return !!d.intercept; return d.air > 0; }
  if (d.only && !d.only.includes(t.cls)) return false;
  return (d.vs[t.cls] || 0) > 0;
}
function weaponRange(w, t) { return t && t.cls === 'air' ? w.def.airRange || w.def.range : w.def.range; }

const _cands = [];
function pickTarget(u, w) {
  const d = w.def;
  const maxR = Math.max(d.range, d.airRange || 0);
  const pref = u.order && u.order.type === 'attack' ? u.order.target : u.focus;
  if (pref && !pref.dead && pref.vis[u.team] && canTarget(w, pref)) {
    const dd = dist(u.x, u.y, pref.x, pref.y);
    if (dd <= weaponRange(w, pref) + (pref.r || 0) && (!d.min || dd > d.min)) return pref;
  }
  _cands.length = 0;
  G.grid.query(u.x, u.y, d.arty ? maxR : maxR + 40, _cands);
  let best = null, bs = 0;
  let chase = null, cs = 1e9;
  const n = d.arty && _cands.length > 60 ? 60 : _cands.length;
  for (let i = 0; i < n; i++) {
    const e = d.arty && _cands.length > 60 ? _cands[(Math.random() * _cands.length) | 0] : _cands[i];
    if (e.team === u.team || e.dead || !e.vis[u.team] || !canTarget(w, e)) continue;
    const dd = dist(u.x, u.y, e.x, e.y);
    const rng = weaponRange(w, e) + (e.r || 0);
    if (dd > rng) { if (dd < cs && e.cls !== 'air') { cs = dd; chase = e; } continue; }
    if (d.min && dd < d.min) continue;
    let s = (d.vs[e.cls] || 0.1) * (1.6 - dd / rng * 0.6);
    s *= 1 + (1 - e.hp / e.maxHp) * 0.8;
    if (d.prefer && e.cls === d.prefer) s *= 3;
    if (d.preferAir && e.cls === 'air') s *= e.isMissile ? 12 : 5;
    if (e.isMissile) s *= 3;
    if (e.def && (e.def.role === 'arty' || e.type === 'droneop' || e.type === 'officer' || e.type === 'mgunner' || e.type === 'radioop')) s *= 1.35;
    if (d.arty) s *= clusterValue(e.x, e.y, d.splash, u.team);
    if (e.cls === 'bld') s *= 0.6;
    if (s > bs) { bs = s; best = e; }
  }
  if (!best) u.chase = chase;
  return best;
}
function clusterValue(x, y, r, team) {
  let v = 0;
  for (const e of G.grid.query(x, y, r)) {
    if (e.dead || e.cls === 'air') continue;
    if (e.team === team) v -= (e.def.value || 50) * 2.5;
    else if (e.vis[team]) v += e.def.value || 50;
  }
  return Math.max(0.1, v / 100);
}

function aimAngle(u) { return u.def.weapons.length && WEAPONS[u.def.weapons[0]].turret ? u.tang : u.ang; }

function updateWeapons(u, dt) {
  const d = u.def;
  for (let wi = 0; wi < u.weapons.length; wi++) {
    const w = u.weapons[wi]; const wd = w.def;
    w.cd -= dt;
    // MLRS salvo in progress
    if (w.salvo > 0) {
      w.salvoT -= dt;
      if (w.salvoT <= 0 && w.aim) { w.salvoT = wd.salvoGap; w.salvo--; fireMRocket(u, w); }
      continue;
    }
    w.retarget -= dt;
    if (w.retarget <= 0 || (w.target && (w.target.dead || !w.target.vis[u.team]))) {
      w.retarget = wd.arty ? rand(0.8, 1.2) : rand(0.3, 0.45);
      w.target = pickTarget(u, w);
    }
    const t = w.target;
    if (!t) { if (wi === 0 && wd.turret && d.cls !== 'bld') u.tang = rotTo(u.tang, u.ang, (d.tturn || 2) * dt); continue; }
    const dd = dist(u.x, u.y, t.x, t.y);
    if (dd > weaponRange(w, t) + (t.r || 0) + 8 || (wd.min && dd < wd.min)) { w.target = null; continue; }
    const want = Math.atan2(t.y - u.y, t.x - u.x);
    let aligned = true;
    if (wi === 0) {
      if (wd.turret) { u.tang = rotTo(u.tang, want, (d.tturn || 3) * dt); aligned = Math.abs(angDiff(u.tang, want)) < 0.12; }
      else if (u.cls === 'inf') { u.ang = rotTo(u.ang, want, 10 * dt); aligned = Math.abs(angDiff(u.ang, want)) < 0.3; }
      else if (u.cls === 'veh') {
        // fixed guns (howitzer): the truck turns to face the target when parked
        if (!u.moving) u.ang = rotTo(u.ang, want, d.turn * 0.7 * dt);
        aligned = Math.abs(angDiff(u.ang, want)) < 0.25;
      }
    } else if (u.cls === 'inf' && !u.weapons[0].target) u.ang = rotTo(u.ang, want, 10 * dt);
    if (w.cd > 0 || !aligned) continue;
    if (wd.deploy && (u.moving || u.stillT < wd.deploy)) continue;
    if (!wd.moveFire && u.moving && !wd.deploy) continue;
    if (wd.arty && !t.vis[u.team]) continue;
    // fire
    if (wd.burst) {
      w.burst++;
      if (w.burst >= wd.burst) { w.burst = 0; w.cd = wd.rest + rand(0, 0.3); } else w.cd = wd.cd;
    } else w.cd = wd.cd * rand(0.92, 1.1);
    fireWeapon(u, w, t, dd);
  }
}

function muzzlePos(u, w) {
  const d = u.def; const wd = w.def;
  if (u.cls === 'inf') {
    const a = u.ang, len = (wd.muzzle || 1.2) * u.r;
    return { x: u.x + Math.cos(a) * len - Math.sin(a) * u.r * 0.68, y: u.y + Math.sin(a) * len + Math.cos(a) * u.r * 0.68, a };
  }
  if (u.cls === 'bld') { const a = u.tang; return { x: u.x + Math.cos(a) * 32, y: u.y + Math.sin(a) * 32, a }; }
  const a = wd.turret ? u.tang : u.ang;
  const len = u.type === 'howitzer' ? d.len * 0.6 : u.type === 'mlrs' ? d.len * 0.12 : d.len * 0.62;
  const base = u.type === 'lighttank' ? -0.12 * d.len : u.type === 'heavytank' ? 0.08 * d.len : u.type === 'mlrs' ? -0.17 * d.len : 0;
  const bx = u.x + Math.cos(u.ang) * base, by = u.y + Math.sin(u.ang) * base;
  return { x: bx + Math.cos(a) * len, y: by + Math.sin(a) * len, a };
}

function hitChance(u, w, t, dd) {
  const wd = w.def;
  let acc = wd.acc;
  if (t.cls === 'air') acc *= wd.air || 0;
  if (u.moving) acc *= u.cls === 'inf' ? 0.7 : 0.85;
  if (u.sup > 50) acc *= 0.5;
  if (u.aura) acc *= 1.25;
  acc *= 1 + u.rank * 0.1;
  if (t.cls === 'inf' && MAP.terr[cellOf(t.x, t.y)] === T_FOREST) acc *= 0.65;
  if (t.cls === 'inf' && t.sup > 50) acc *= 0.8; // prone
  if (t.cls === 'veh' || t.cls === 'bld') acc = Math.min(0.97, acc * 1.4);
  if (t.moving && t.cls === 'inf') acc *= 0.9;
  acc *= 1.1 - (dd / (weaponRange(w, t) + 1)) * 0.3;
  return clamp(acc, 0.02, 0.98);
}

function fireWeapon(u, w, t, dd) {
  const wd = w.def;
  const m = muzzlePos(u, w);
  if (u.def.camo || u.cls === 'inf') u.revealT = Math.max(u.revealT, wd.kind === 'bullet' && wd.dmg < 20 ? 1.5 : 3);
  if (wd.arty) u.revealT = 4;
  const vol = { rifle: 0.35, pistol: 0.25, mg: 0.4, sniper: 0.9, aa: 0.6, cannon: 1, cannonH: 1, rocket: 0.8, throw: 0.5, howitzer: 1.1, mlrs: 1 }[wd.snd] || 0.5;
  switch (wd.kind) {
    case 'bullet': {
      const hit = Math.random() < hitChance(u, w, t, dd);
      let ex = t.x, ey = t.y;
      if (!hit) { const a = rand(0, TAU), r = rand(8, 26); ex += Math.cos(a) * r; ey += Math.sin(a) * r; }
      const col = wd.tracer === 1 ? '255,190,90' : wd.tracer === 2 ? '255,255,235' : wd.tracer === 3 ? '255,120,80' : '255,225,150';
      if (wd.tracer || Math.random() < 0.55) tracer(m.x, m.y, ex, ey, col, wd.tracer === 2 ? 1.8 : wd.tracer ? 1.5 : 1, wd.tracer === 2 ? 4200 : 2800, wd.tracer === 2 ? 160 : 60);
      muzzle(m.x, m.y, m.a, wd.tracer === 3 ? 1.2 : wd.dmg > 50 ? 1 : 0.55);
      if (hit) {
        const mult = wd.vs[t.cls] || 0.05;
        damage(t, wd.dmg * mult * (1 + u.rank * 0.1), u, wd.sup || 0);
        if (t.cls === 'veh' || t.cls === 'bld') sparks(ex, ey, 2, 140); else if (t.cls === 'inf') part({ kind: 'dust', x: ex, y: ey, life: 0.3, s0: 2, s1: 7, a0: 0.5 });
      } else {
        if (MAP.terr[cellOf(ex, ey)] === T_WATER) part({ kind: 'water', x: ex, y: ey, life: 0.4, s0: 2, s1: 6, a0: 0.7 });
        else part({ kind: 'dust', x: ex, y: ey, life: 0.4, s0: 2, s1: 8, a0: 0.45 });
        if (t.cls === 'inf') t.sup = Math.min(100, t.sup + (wd.sup || 0) * 0.5 * (t.aura ? 0.5 : 1));
      }
      break;
    }
    case 'shell': {
      const sc = (1 - wd.acc) * dd * 0.25 * (u.moving ? 1.6 : 1) / (1 + u.rank * 0.2);
      const lead = t.moving ? dd / wd.speed : 0;
      const tx = t.x + (t.speedNow || 0) * Math.cos(t.ang) * lead * 0.8 + rand(-sc, sc), ty = t.y + (t.speedNow || 0) * Math.sin(t.ang) * lead * 0.8 + rand(-sc, sc);
      G.projs.push({ kind: 'shell', team: u.team, src: u, x: m.x, y: m.y, sx: m.x, sy: m.y, tx, ty, target: t, speed: wd.speed, dmg: wd.dmg, splash: wd.splash, vs: wd.vs, sup: wd.sup, t: 0, T: dist(m.x, m.y, tx, ty) / wd.speed });
      muzzle(m.x, m.y, m.a, 1.8);
      for (let i = 0; i < 4; i++) smoke(m.x + Math.cos(m.a) * 6, m.y + Math.sin(m.a) * 6, 0.45, false, rand(0.8, 1.5));
      u.recoil = 1;
      if (G.night > 0) light(m.x, m.y, 120, 0.12, 1);
      break;
    }
    case 'rocket': {
      G.projs.push({ kind: 'rocket', team: u.team, src: u, x: m.x, y: m.y, ang: m.a, target: t, speed: wd.speed, dmg: wd.dmg, splash: wd.splash, vs: wd.vs, sup: wd.sup, t: 0, life: 2.2, acc: wd.acc * (u.aura ? 1.1 : 1), wob: rand(0, TAU) });
      // backblast
      const ba = m.a + Math.PI;
      for (let i = 0; i < 6; i++) part({ kind: 'smoke', x: u.x + Math.cos(ba) * 14, y: u.y + Math.sin(ba) * 14, vx: Math.cos(ba + rand(-0.4, 0.4)) * rand(60, 140), vy: Math.sin(ba + rand(-0.4, 0.4)) * rand(60, 140), life: rand(0.8, 1.6), s0: 6, s1: 22, a0: 0.5, drag: 0.9 });
      muzzle(m.x, m.y, m.a, 1.2);
      break;
    }
    case 'grenade': case 'throw': {
      const sc = (1 - wd.acc) * dd * 0.35 + (wd.scatter || 0);
      const tx = t.x + rand(-sc, sc), ty = t.y + rand(-sc, sc);
      const T = 0.55 + dd / 340;
      G.projs.push({ kind: 'lob', team: u.team, src: u, x: m.x, y: m.y, sx: m.x, sy: m.y, tx, ty, target: wd.kind === 'throw' ? t : null, t: 0, T, h: 30 + dd * 0.18, dmg: wd.dmg, splash: wd.splash, vs: wd.vs, sup: wd.sup, satchel: wd.kind === 'throw', spin: rand(0, TAU) });
      break;
    }
    case 'arty': {
      const sc = dd * wd.scatter / (1 + u.rank * 0.25);
      const tx = t.x + rand(-sc, sc), ty = t.y + rand(-sc, sc);
      const T = 1.4 + dd / 650;
      G.projs.push({ kind: 'arty', team: u.team, src: u, x: m.x, y: m.y, sx: m.x, sy: m.y, tx, ty, t: 0, T, h: 260 + dd * 0.35, dmg: wd.dmg, splash: wd.splash, vs: wd.vs, sup: wd.sup, whistled: false, size: 3.2 });
      muzzle(m.x, m.y, m.a, 3);
      for (let i = 0; i < 10; i++) smoke(m.x + rand(-10, 10), m.y + rand(-10, 10), 0.8, false, rand(1.5, 3));
      for (let i = 0; i < 8; i++) dust(u.x + rand(-20, 20), u.y + rand(-20, 20), 1.2, rand(0.8, 1.6));
      light(m.x, m.y, 200, 0.18, 1);
      shake(m.x, m.y, 2);
      u.recoil = 1;
      counterBattery(u);
      break;
    }
    case 'mrocket': {
      w.salvo = wd.salvo; w.salvoT = 0; w.aim = { x: t.x, y: t.y, d: dd };
      counterBattery(u);
      return;
    }
  }
  Sound.at(wd.snd, m.x, m.y, vol);
}

function fireMRocket(u, w) {
  const wd = w.def; const a = w.aim;
  const m = muzzlePos(u, w);
  const sc = a.d * wd.scatter;
  const ang = rand(0, TAU), r = Math.sqrt(Math.random()) * sc;
  const tx = a.x + Math.cos(ang) * r, ty = a.y + Math.sin(ang) * r;
  const T = 1.6 + a.d / 750;
  G.projs.push({ kind: 'mrocket', team: u.team, src: u, x: m.x, y: m.y, sx: m.x, sy: m.y, tx, ty, t: 0, T, h: 180 + a.d * 0.22, dmg: wd.dmg, splash: wd.splash, vs: wd.vs, sup: wd.sup, size: 2.2, trail: 0 });
  muzzle(m.x, m.y, m.a, 1.6);
  for (let i = 0; i < 3; i++) smoke(m.x + rand(-8, 8), m.y + rand(-8, 8), 0.7, false, rand(1.5, 3));
  light(m.x, m.y, 110, 0.12, 0.9);
  Sound.at('mlrs', m.x, m.y, 0.5);
  u.revealT = 4;
}

function counterBattery(u) {
  const enemy = G.teams[1 - u.team];
  if (enemy.radars > 0) {
    if (u.spotT <= 0 && u.team !== G.playerTeam && G.playerTeam === 1 - u.team) notify(`Enemy ${u.def.name.toLowerCase()} spotted by radar`, 'warn', u.x, u.y);
    u.spotT = 8;
  }
}

// ---------------------------------------------------------------------
// damage & death
// ---------------------------------------------------------------------
function damage(t, amount, src, sup, fromX, fromY) {
  if (t.dead) return;
  if (t.cls === 'veh' && src) {
    const ax = fromX != null ? fromX : src.x, ay = fromY != null ? fromY : src.y;
    const hit = Math.abs(angDiff(t.ang, Math.atan2(ay - t.y, ax - t.x)));
    if (hit > 2.2) { amount *= 1.5; if (amount > 60 && G.seen(t)) floatText(t.x, t.y - 26, 'REAR HIT', '#ffd27a'); }
    else if (hit > 1.1) amount *= 1.2;
  }
  if (t.cls === 'inf') {
    if (MAP.terr[cellOf(t.x, t.y)] === T_FOREST) amount *= 0.78;
    if (sup) t.sup = Math.min(100, t.sup + sup * (t.aura ? 0.5 : 1));
  }
  if (t.isDrone || t.isMissile) { t.hp -= amount; if (t.hp <= 0) t.kill(src); return; }
  t.hp -= amount;
  t.hitFlash = 0.1;
  t.lastHit = G.time;
  if (src && src.team !== t.team) {
    t.lastAttacker = src;
    G.teams[t.team].lastHitT = G.time;
    if (t.team === G.playerTeam) underAttack(t);
  }
  if (t.hp <= 0) killUnit(t, src);
}

function splash(x, y, p) {
  // p: { team, dmg, splash, vs, sup, src, direct }
  const list = G.grid.query(x, y, p.splash);
  for (const e of list) {
    if (e.dead || e.team === p.team || e.cls === 'air') continue;
    const dd = dist(x, y, e.x, e.y) - (e.r || 0) * 0.5;
    if (dd > p.splash) continue;
    if (e === p.direct) continue;
    const k = 1 - clamp(dd / p.splash, 0, 1) * 0.7;
    damage(e, p.dmg * k * (p.vs[e.cls] || 0.1), p.src && !p.src.dead ? p.src : null, p.sup, x, y);
  }
  // suppression even on near misses
  if (p.sup) for (const e of G.grid.query(x, y, p.splash * 1.8)) if (!e.dead && e.team !== p.team && e.cls === 'inf') e.sup = Math.min(100, e.sup + p.sup * 0.4 * (e.aura ? 0.5 : 1));
}

function killUnit(u, src) {
  if (u.dead) return;
  u.dead = true; u.hp = 0;
  const T = G.teams[u.team];
  T.tickets = Math.max(0, T.tickets - u.def.tickets);
  T.stats.lost++;
  if (src && src.team !== u.team && !src.dead) {
    src.kills++;
    src.xp += u.def.value || 50;
    const base = src.def.value || 60;
    const nr = src.xp >= base * 4 ? 2 : src.xp >= base * 1.5 ? 1 : 0;
    if (nr > src.rank) { src.rank = nr; if (G.seen(src)) floatText(src.x, src.y - 20, nr === 2 ? 'VETERAN ★★' : 'VETERAN ★', '#f7d54a'); src.hp = Math.min(src.maxHp, src.hp + src.maxHp * 0.25); }
  }
  if (src) G.teams[1 - u.team].stats.kills++;
  if (u.drone && !u.drone.dead) u.drone.lost = true;
  if (u.cls === 'inf') {
    decalBody(u);
    for (let i = 0; i < 3; i++) dust(u.x, u.y, 0.6, 0.8);
    if (u.team === G.playerTeam && u.type !== 'rifleman' && u.type !== 'grenadier') G.lossFeed(u);
  } else if (u.cls === 'veh') {
    explode(u.x, u.y, 5);
    sparks(u.x, u.y, 30, 400);
    debris(u.x, u.y, 14, 260, '#222');
    u.wreck = true;
    G.wrecks.push({ x: u.x, y: u.y, ang: u.ang, type: u.type, team: u.team, t: 0, life: 22, tang: u.tang });
    emitter(u.x, u.y, 22, 1.1);
    if (u.team === G.playerTeam) G.lossFeed(u);
  } else if (u.cls === 'bld') {
    explode(u.x, u.y, u.type === 'hq' ? 10 : 6);
    for (let i = 0; i < (u.type === 'hq' ? 8 : 2); i++) setTimeout(() => explode(u.x + rand(-80, 80), u.y + rand(-70, 70), rand(3, 6)), i * 260);
    emitter(u.x, u.y, 60, u.type === 'hq' ? 3 : 1.5);
    decalScorch(u.x, u.y, u.type === 'hq' ? 200 : 70);
    if (u.type === 'hq') G.hqDestroyed(u.team);
  }
}

// ---------------------------------------------------------------------
// projectiles
// ---------------------------------------------------------------------
function updateProjectiles(dt) {
  const P = G.projs;
  for (let i = P.length - 1; i >= 0; i--) {
    const p = P[i];
    p.t += dt;
    let done = false;
    if (p.kind === 'shell') {
      const k = clamp(p.t / p.T, 0, 1);
      p.x = lerp(p.sx, p.tx, k); p.y = lerp(p.sy, p.ty, k);
      if (k >= 1) {
        done = true;
        const t = p.target;
        let direct = null;
        if (t && !t.dead && dist(t.x, t.y, p.tx, p.ty) < (t.r || 8) + 6) { direct = t; damage(t, p.dmg * (p.vs[t.cls] || 0.1), p.src && !p.src.dead ? p.src : null, p.sup, p.sx, p.sy); }
        splash(p.tx, p.ty, { team: p.team, dmg: p.dmg * 0.6, splash: p.splash, vs: p.vs, sup: p.sup, src: p.src, direct });
        if (direct && direct.cls !== 'inf') { sparks(p.tx, p.ty, 14, 300); part({ kind: 'flash', add: true, x: p.tx, y: p.ty, life: 0.1, s0: 40, s1: 60 }); Sound.at('small', p.tx, p.ty, 0.6); light(p.tx, p.ty, 90, 0.2, 1); }
        else explode(p.tx, p.ty, 1.6);
      }
    } else if (p.kind === 'rocket') {
      const t = p.target;
      if (t && !t.dead) {
        const want = Math.atan2(t.y - p.y, t.x - p.x);
        p.ang = rotTo(p.ang, want + Math.sin(p.t * 9 + p.wob) * 0.08, 2.4 * dt);
      }
      p.x += Math.cos(p.ang) * p.speed * dt; p.y += Math.sin(p.ang) * p.speed * dt;
      if (Math.random() < 0.9) part({ kind: 'smoke', x: p.x - Math.cos(p.ang) * 6, y: p.y - Math.sin(p.ang) * 6, vx: rand(-6, 6), vy: rand(-6, 6), life: rand(0.8, 1.4), s0: 3, s1: 12, a0: 0.45, drag: 0.98 });
      part({ kind: 'fire', add: true, x: p.x - Math.cos(p.ang) * 5, y: p.y - Math.sin(p.ang) * 5, life: 0.08, s0: 6, s1: 2 });
      if (G.night > 0) light(p.x, p.y, 45, 0.05, 0.8);
      if (t && !t.dead && dist(p.x, p.y, t.x, t.y) < (t.r || 8) + 4) {
        done = true;
        const hit = Math.random() < p.acc;
        if (hit) damage(t, p.dmg * (p.vs[t.cls] || 0.1), p.src && !p.src.dead ? p.src : null, p.sup, p.x - Math.cos(p.ang) * 50, p.y - Math.sin(p.ang) * 50);
        splash(p.x, p.y, { team: p.team, dmg: p.dmg * 0.25, splash: p.splash, vs: p.vs, sup: p.sup, src: p.src, direct: hit ? t : null });
        explode(p.x, p.y, 1.8);
        if (hit && t.cls !== 'inf') sparks(p.x, p.y, 20, 350);
      } else if (p.t > p.life || blockedAt(p.x, p.y) && terrAt(p.x, p.y) !== T_WATER) { done = true; explode(p.x, p.y, 1.4); }
      else if (p.t > p.life * 0.98) done = true;
    } else if (p.kind === 'lob') {
      const k = clamp(p.t / p.T, 0, 1);
      if (p.target && !p.target.dead && p.satchel) { p.tx = lerp(p.tx, p.target.x, 0.15); p.ty = lerp(p.ty, p.target.y, 0.15); }
      p.x = lerp(p.sx, p.tx, k); p.y = lerp(p.sy, p.ty, k); p.z = 4 * p.h * k * (1 - k);
      p.spin += dt * 12;
      if (k >= 1) {
        done = true;
        let direct = null;
        if (p.target && !p.target.dead && dist(p.target.x, p.target.y, p.tx, p.ty) < p.target.r + 10) { direct = p.target; damage(direct, p.dmg * (p.vs[direct.cls] || 0.1), p.src && !p.src.dead ? p.src : null, p.sup, p.sx, p.sy); }
        splash(p.tx, p.ty, { team: p.team, dmg: p.satchel ? p.dmg * 0.3 : p.dmg, splash: p.splash, vs: p.vs, sup: p.sup, src: p.src, direct });
        explode(p.tx, p.ty, p.satchel ? 3 : 1.3);
      }
    } else if (p.kind === 'arty' || p.kind === 'mrocket' || p.kind === 'barrage') {
      const k = clamp(p.t / p.T, 0, 1);
      p.x = lerp(p.sx, p.tx, k); p.y = lerp(p.sy, p.ty, k); p.z = p.kind === 'barrage' ? (1 - k) * 700 : 4 * p.h * k * (1 - k);
      if (p.kind === 'mrocket' && k < 0.85) {
        p.trail += dt;
        while (p.trail > 0.02) {
          p.trail -= 0.02;
          part({ kind: 'smoke', x: p.x, y: p.y - p.z * 0.55, vx: rand(-5, 5), vy: rand(-5, 5), life: rand(1, 2.2), s0: 4, s1: 16, a0: 0.4, drag: 0.98 });
        }
        part({ kind: 'fire', add: true, x: p.x, y: p.y - p.z * 0.55, life: 0.07, s0: 8, s1: 3 });
        if (G.night > 0) light(p.x, p.y - p.z * 0.55, 50, 0.05, 0.7);
      }
      if (!p.whistled && p.T - p.t < 0.75) { p.whistled = true; if (p.kind !== 'mrocket') Sound.at('whistle', p.tx, p.ty, 0.5); }
      if (k >= 1) {
        done = true;
        splash(p.tx, p.ty, { team: p.team, dmg: p.dmg, splash: p.splash, vs: p.vs, sup: p.sup, src: p.src });
        explode(p.tx, p.ty, p.size);
        G.impacts.push({ x: p.tx, y: p.ty, t: G.time, team: p.team });
      }
    }
    if (done) P.splice(i, 1);
  }
}

// ---------------------------------------------------------------------
// drones
// ---------------------------------------------------------------------
class Drone {
  constructor(op, target) {
    this.id = NEXT_ID++;
    this.op = op; this.team = op.team; this.target = target;
    this.x = op.x; this.y = op.y; this.z = 0; this.ang = Math.atan2(target.y - op.y, target.x - op.x);
    this.hp = 30; this.maxHp = 30; this.cls = 'air'; this.isDrone = true; this.r = 7;
    this.vis = [op.team === 0, op.team === 1];
    this.t = 0; this.dead = false; this.jammed = 0; this.speed = 255; this.spin = 0;
    this.def = { value: 40, name: 'FPV drone' };
  }
  kill(src) {
    if (this.dead) return; this.dead = true;
    sparks(this.x, this.y - this.z * 0.5, 14, 200); part({ kind: 'flash', add: true, x: this.x, y: this.y - this.z * 0.5, life: 0.1, s0: 18, s1: 30 });
    smoke(this.x, this.y, 0.5, true, 1.5);
    Sound.at('small', this.x, this.y, 0.3);
    if (src && this.team === G.playerTeam) {} // silent
  }
}
function launchDrone(op, target) {
  const d = new Drone(op, target);
  op.drone = d; op.abilityCd = ABILITIES.drone.cd;
  G.drones.push(d);
  Sound.at('drone', op.x, op.y, 0.8);
  if (target.team === G.playerTeam && G.playerTeam >= 0) notify('Enemy drone inbound', 'warn', target.x, target.y);
}
function updateDrones(dt) {
  for (let i = G.drones.length - 1; i >= 0; i--) {
    const d = G.drones[i];
    if (d.dead) { G.drones.splice(i, 1); if (d.op.drone === d) d.op.drone = null; continue; }
    d.t += dt; d.spin += dt * 50;
    d.z = Math.min(46, d.z + dt * 60);
    if (d.jammed > 0) {
      d.jammed += dt;
      d.ang += dt * 9; d.z = Math.max(0, d.z - dt * 60);
      d.x += Math.cos(d.ang) * 70 * dt; d.y += Math.sin(d.ang) * 70 * dt;
      if (Math.random() < 0.5) sparks(d.x, d.y - d.z * 0.5, 1, 80, null, 0, '140,255,200');
      if (d.jammed > 0.9) { d.kill(null); explode(d.x, d.y, 0.6, { silent: true }); }
      continue;
    }
    // jammers
    for (const j of G.jammers) {
      if (j.team === d.team || j.dead) continue;
      if (dist2(j.x, j.y, d.x, d.y) < j.def.jam * j.def.jam) {
        d.jammed = 0.01; ring(j.x, j.y, 10, j.def.jam, 0.6, '120,255,190', 2); Sound.at('jam', d.x, d.y, 0.5);
        if (d.team === G.playerTeam) notify('Drone jammed', 'info', d.x, d.y);
        break;
      }
    }
    if (d.jammed) continue;
    let t = d.target;
    if (!t || t.dead) {
      // pick the nearest visible enemy around the old target
      let best = null, bd = 260;
      for (const e of G.grid.query(d.x, d.y, 260)) { if (e.team !== d.team && !e.dead && e.cls !== 'air' && e.vis[d.team]) { const dd = dist(d.x, d.y, e.x, e.y); if (dd < bd) { bd = dd; best = e; } } }
      d.target = t = best;
    }
    if (!t || d.t > 14) { d.kill(null); explode(d.x, d.y, 0.6, { silent: true }); continue; }
    const want = Math.atan2(t.y - d.y, t.x - d.x);
    d.ang = rotTo(d.ang, want + Math.sin(d.t * 7) * 0.12, 4 * dt);
    d.x += Math.cos(d.ang) * d.speed * dt; d.y += Math.sin(d.ang) * d.speed * dt;
    if (dist(d.x, d.y, t.x, t.y) < (t.r || 8) + 6) {
      d.dead = true;
      damage(t, 290 * (t.cls === 'inf' ? 0.6 : 1), d.op.dead ? null : d.op, 30, d.x - Math.cos(d.ang) * 40, d.y - Math.sin(d.ang) * 40);
      splash(d.x, d.y, { team: d.team, dmg: 80, splash: 50, vs: { inf: 1, veh: 0.4, bld: 0.4 }, sup: 30, src: d.op, direct: t });
      explode(d.x, d.y, 2.2);
    }
  }
}

// ---------------------------------------------------------------------
// tactical missiles
// ---------------------------------------------------------------------
class Missile {
  constructor(src, tx, ty) {
    this.id = NEXT_ID++; this.team = src.team; this.src = src;
    this.sx = src.x; this.sy = src.y; this.x = src.x; this.y = src.y; this.z = 0; this.tx = tx; this.ty = ty;
    this.cls = 'air'; this.isMissile = true; this.r = 10; this.hp = this.maxHp = 300;
    this.vis = [true, true]; this.t = 0; this.boost = 1.4;
    const d = dist(src.x, src.y, tx, ty);
    this.T = 2.4 + d / 1050; this.h = 700 + d * 0.15;
    this.dead = false; this.trail = 0; this.def = { value: 300, name: 'missile' }; this.ang = Math.atan2(ty - src.y, tx - src.x);
  }
  kill(src) {
    if (this.dead) return; this.dead = true;
    const zx = this.x, zy = this.y - this.z * 0.55;
    part({ kind: 'flash', add: true, x: zx, y: zy, life: 0.25, s0: 120, s1: 200, important: true });
    for (let i = 0; i < 30; i++) fire(zx + rand(-20, 20), zy + rand(-20, 20), 2, rand(0.4, 0.9));
    for (let i = 0; i < 16; i++) smoke(zx + rand(-30, 30), zy + rand(-30, 30), 1.6, true, rand(2.5, 4));
    sparks(zx, zy, 50, 500);
    ring(zx, zy, 10, 180, 0.6, '255,240,200', 4);
    light(zx, zy, 400, 0.5, 1);
    Sound.at('boom', zx, zy, 1);
    const w = G.warnings.find((x) => x.missile === this); if (w) w.done = true;
    notify(this.team === G.playerTeam ? 'Our missile was shot down' : 'Enemy missile intercepted!', this.team === G.playerTeam ? 'bad' : 'good', this.tx, this.ty);
  }
}
function launchMissile(src, tx, ty) {
  const m = new Missile(src, tx, ty);
  G.missiles.push(m);
  src.abilityCd = ABILITIES.missile.cd;
  src.revealT = 6; counterBattery(src);
  G.warnings.push({ x: tx, y: ty, r: ABILITIES.missile.radius, t: 0, T: m.T, team: src.team, missile: m, kind: 'missile' });
  Sound.at('missile', src.x, src.y, 1.2);
  for (let i = 0; i < 30; i++) dust(src.x + rand(-40, 40), src.y + rand(-40, 40), 2, rand(1.5, 3));
  for (let i = 0; i < 20; i++) part({ kind: 'white', x: src.x + rand(-20, 20), y: src.y + rand(-20, 20), vx: rand(-90, 90), vy: rand(-90, 90), life: rand(2, 4), s0: 20, s1: 70, a0: 0.6, drag: 0.96 });
  shake(src.x, src.y, 6);
  if (G.playerTeam >= 0) {
    if (src.team === G.playerTeam) notify('Missile away', 'good', tx, ty);
    else { notify('INCOMING MISSILE — clear the red zone!', 'bad', tx, ty); Sound.play('alert', 0.8); }
  }
}
function updateMissiles(dt) {
  for (let i = G.missiles.length - 1; i >= 0; i--) {
    const m = G.missiles[i];
    if (m.dead) { G.missiles.splice(i, 1); continue; }
    m.t += dt;
    const k = clamp(m.t / m.T, 0, 1);
    m.x = lerp(m.sx, m.tx, k * k * (3 - 2 * k)); m.y = lerp(m.sy, m.ty, k * k * (3 - 2 * k));
    m.z = 4 * m.h * k * (1 - k) + (k < 0.15 ? (1 - k / 0.15) * 0 : 0);
    const py = m.y - m.z * 0.55;
    m.trail += dt;
    while (m.trail > 0.012) {
      m.trail -= 0.012;
      part({ kind: k < 0.2 ? 'white' : 'smoke', x: m.x + rand(-3, 3), y: py + rand(-3, 3), vx: rand(-10, 10), vy: rand(-10, 10), life: rand(2.5, 5), s0: 8 + m.z * 0.01, s1: 30 + m.z * 0.03, a0: 0.55, drag: 0.99 });
    }
    fire(m.x, py, 1.4, 0.12);
    if (G.night > 0) light(m.x, py, 120, 0.05, 1);
    if (k >= 1) {
      m.dead = true;
      const A = ABILITIES.missile;
      for (const e of G.grid.query(m.tx, m.ty, A.radius)) {
        if (e.dead || e.cls === 'air') continue;
        const dd = dist(m.tx, m.ty, e.x, e.y);
        if (dd > A.radius + (e.r || 0)) continue;
        const f = 1 - clamp(dd / A.radius, 0, 1) * 0.7;
        damage(e, A.dmg * f * (e.cls === 'bld' ? 1.4 : 1), e.team !== m.team ? (m.src.dead ? null : m.src) : null, 80, m.tx, m.ty - 1);
      }
      explode(m.tx, m.ty, 10);
      for (let j = 0; j < 6; j++) { const a = rand(0, TAU), r = rand(40, 150); setTimeout(() => explode(m.tx + Math.cos(a) * r, m.ty + Math.sin(a) * r, rand(2, 4), { silent: j > 2 }), 120 + j * 110); }
      // mushroom column
      for (let j = 0; j < 40; j++) part({ kind: j % 2 ? 'dark' : 'smoke', x: m.tx + rand(-50, 50), y: m.ty + rand(-50, 50), vx: rand(-30, 30) + FX.wind.x, vy: rand(-60, -10), life: rand(5, 9), s0: 30, s1: rand(90, 150), a0: 0.6, drag: 0.99, rot: rand(0, TAU), vr: rand(-0.2, 0.2), important: true });
      for (let j = 0; j < 6; j++) emitter(m.tx + rand(-90, 90), m.ty + rand(-90, 90), rand(14, 26), rand(0.8, 1.4));
      decalScorch(m.tx, m.ty, 260);
      const w = G.warnings.find((x) => x.missile === m); if (w) w.done = true;
    }
  }
}

// ---------------------------------------------------------------------
// artillery barrages (radio operator)
// ---------------------------------------------------------------------
function callBarrage(op, x, y) {
  const A = ABILITIES.barrage;
  op.abilityCd = A.cd; op.revealT = 3;
  G.strikes.push({ team: op.team, x, y, r: A.radius, t: -A.delay, n: A.shells, acc: 0, src: op });
  G.warnings.push({ x, y, r: A.radius, t: 0, T: A.delay + 2.4, team: op.team, kind: 'barrage' });
  Sound.at('jam', op.x, op.y, 0.4);
  if (G.playerTeam >= 0 && op.team !== G.playerTeam) notify('Enemy artillery barrage incoming', 'bad', x, y);
}
function updateStrikes(dt) {
  for (let i = G.strikes.length - 1; i >= 0; i--) {
    const s = G.strikes[i]; s.t += dt;
    if (s.t < 0) continue;
    s.acc -= dt;
    while (s.acc <= 0 && s.n > 0) {
      s.acc += rand(0.15, 0.35); s.n--;
      const a = rand(0, TAU), r = Math.sqrt(Math.random()) * s.r;
      const tx = s.x + Math.cos(a) * r, ty = s.y + Math.sin(a) * r;
      const A = ABILITIES.barrage;
      const sx = s.team === 0 ? tx - 260 : tx + 260;
      G.projs.push({ kind: 'barrage', team: s.team, src: s.src, x: sx, y: ty, sx, sy: ty, tx, ty, t: 0, T: 0.9, h: 0, dmg: A.dmg, splash: A.splash, vs: { inf: 1, veh: 0.75, bld: 0.9 }, sup: 45, size: 2.8, whistled: false });
    }
    if (s.n <= 0) G.strikes.splice(i, 1);
  }
  for (let i = G.warnings.length - 1; i >= 0; i--) { const w = G.warnings[i]; w.t += dt; if (w.done || w.t > w.T + 0.3) G.warnings.splice(i, 1); }
}

// ---------------------------------------------------------------------
// mines
// ---------------------------------------------------------------------
function layMine(eng, x, y) {
  G.mines.push({ team: eng.team, x, y, armT: 2, dead: false, id: NEXT_ID++ });
  eng.abilityCd = ABILITIES.mine.cd;
  dust(x, y, 0.6, 1);
}
function updateMines(dt) {
  for (let i = G.mines.length - 1; i >= 0; i--) {
    const m = G.mines[i];
    if (m.armT > 0) { m.armT -= dt; continue; }
    for (const e of G.grid.query(m.x, m.y, 16)) {
      if (e.team === m.team || e.dead || e.cls !== 'veh') continue;
      damage(e, 420, null, 0, e.x, e.y);
      explode(m.x, m.y, 3.4);
      if (e.team === G.playerTeam) notify('Vehicle hit a mine!', 'bad', m.x, m.y);
      m.dead = true; break;
    }
    if (m.dead) G.mines.splice(i, 1);
  }
}

// ---------------------------------------------------------------------
// abilities (auto-cast + manual orders)
// ---------------------------------------------------------------------
function bestStrikePoint(team, ox, oy, range, radius, minScore, needVis) {
  let best = null, bs = minScore;
  const enemies = G.units;
  let checked = 0;
  for (let i = 0; i < enemies.length && checked < 70; i++) {
    const e = enemies[(i * 7 + G.frame) % enemies.length];
    if (e.team === team || e.dead || !e.vis[team]) continue;
    if (dist(ox, oy, e.x, e.y) > range) continue;
    checked++;
    let s = 0;
    for (const o of G.grid.query(e.x, e.y, radius + 20)) {
      if (o.dead || o.cls === 'air') continue;
      if (o.team === team) { s -= (o.def.value || 50) * 3; continue; }
      if (!o.vis[team]) continue;
      let v = o.def.value || 50;
      if (o.cls === 'bld') v *= 0.8;
      if (o.moving && o.cls === 'veh') v *= 0.6;
      s += v;
    }
    if (s > bs) { bs = s; best = { x: e.x, y: e.y, score: s }; }
  }
  return best;
}

function abilityTick(u, dt) {
  const ab = u.def.ability, A = ABILITIES[ab];
  const o = u.order;
  // manual ability order: walk into range, then cast
  if (o && o.type === 'ability') {
    const tx = o.target ? o.target.x : o.x, ty = o.target ? o.target.y : o.y;
    if (o.target && (o.target.dead || !o.target.vis[u.team])) { u.order = null; return; }
    if (u.abilityCd > 0) return;
    const range = ab === 'mine' ? 24 : A.range;
    if (dist(u.x, u.y, tx, ty) <= range) {
      castAbility(u, tx, ty, o.target);
      u.order = null; u.path = null; u.guard = { x: u.x, y: u.y };
    }
    return;
  }
  if (!u.auto || u.abilityCd > 0) return;
  u.abTick = (u.abTick || rand(0, 1)) - dt;
  if (u.abTick > 0) return;
  u.abTick = rand(0.9, 1.4);
  const ai = G.ai[u.team];
  if (ab === 'drone') {
    if (u.drone) return;
    let best = null, bs = 0;
    for (const e of G.grid.query(u.x, u.y, A.range)) {
      if (e.team === u.team || e.dead || !e.vis[u.team] || e.cls === 'air') continue;
      let s = e.cls === 'veh' ? e.def.value * (e.def.role === 'arty' ? 1.6 : 1) : e.cls === 'bld' ? 30 : (e.def.value || 20) * 0.5 + clusterValue(e.x, e.y, 50, u.team) * 20;
      if (ai && ai.p.dodge) for (const j of G.jammers) if (j.team !== u.team && !j.dead && j.vis[u.team] && dist(j.x, j.y, e.x, e.y) < j.def.jam + 60) s *= 0.15;
      if (s > bs) { bs = s; best = e; }
    }
    if (best && bs >= 60) launchDrone(u, best);
  } else if (ab === 'barrage') {
    const min = ai ? ai.p.minStrike : 200;
    const p = bestStrikePoint(u.team, u.x, u.y, A.range, A.radius, min, true);
    if (p) callBarrage(u, p.x + rand(-15, 15), p.y + rand(-15, 15));
  } else if (ab === 'missile') {
    const min = ai ? 900 : 1100;
    let p = bestStrikePoint(u.team, u.x, u.y, A.range, A.radius, min, true);
    const ehq = G.teams[1 - u.team].hq;
    if (!p && ai && ai.hqPush && ehq && !ehq.dead && ehq.vis[u.team]) p = { x: ehq.x, y: ehq.y };
    if (p) launchMissile(u, p.x, p.y);
  } else if (ab === 'mine' && ai) {
    ai.mineSpot(u);
  }
}
function castAbility(u, x, y, target) {
  const ab = u.def.ability;
  if (ab === 'drone') { if (!u.drone && target) launchDrone(u, target); }
  else if (ab === 'barrage') callBarrage(u, x, y);
  else if (ab === 'missile') launchMissile(u, x, y);
  else if (ab === 'mine') layMine(u, x, y);
}

// ---------------------------------------------------------------------
// medics, engineers, supply trucks
// ---------------------------------------------------------------------
function supportTick(u, dt) {
  const d = u.def;
  u.healT -= dt;
  if (u.healT > 0) return;
  u.healT = 0.5;
  const step = 0.5;
  if (d.heal) {
    let best = null, bv = 0;
    for (const o of G.grid.query(u.x, u.y, d.heal.range)) {
      if (o.team !== u.team || o.dead || o.cls !== 'inf' || o.hp >= o.maxHp) continue;
      const v = 1 - o.hp / o.maxHp; if (v > bv) { bv = v; best = o; }
    }
    if (best) {
      best.hp = Math.min(best.maxHp, best.hp + d.heal.rate * step * 2.2);
      if (G.frame % 2 === 0) part({ kind: 'glow', add: true, x: best.x, y: best.y - 10, vy: -20, life: 0.6, s0: 5, s1: 2, a0: 0.8 });
      u.healing = best;
      if (!u.moving && !u.weapons[0].target) u.ang = Math.atan2(best.y - u.y, best.x - u.x);
    } else u.healing = null;
  }
  if (d.repair) {
    let best = null, bv = 0;
    for (const o of G.grid.query(u.x, u.y, d.repair.range + 30)) {
      if (o.team !== u.team || o.dead || (o.cls !== 'veh' && o.cls !== 'bld') || o.hp >= o.maxHp) continue;
      const v = 1 - o.hp / o.maxHp; if (v > bv) { bv = v; best = o; }
    }
    if (best && (!u.weapons[0].target || u.weapons[0].target.dead)) {
      best.hp = Math.min(best.maxHp, best.hp + d.repair.rate * step);
      sparks(best.x + rand(-8, 8), best.y + rand(-8, 8), 2, 80, null, 0, '255,240,170');
      u.healing = best;
    } else u.healing = null;
  }
  if (d.repairAura) {
    let any = false;
    for (const o of G.grid.query(u.x, u.y, d.repairAura.range)) {
      if (o.team !== u.team || o.dead || o === u || o.cls === 'air') continue;
      o.supplied = 1;
      if (o.hp >= o.maxHp || G.time - o.lastHit < 4) continue;
      o.hp = Math.min(o.maxHp, o.hp + (o.cls === 'veh' ? d.repairAura.veh : o.cls === 'inf' ? d.repairAura.inf : 6) * step);
      any = true;
    }
    u.healing = any;
  }
}

// ---------------------------------------------------------------------
// vision & concealment (both teams, fog for the viewer)
// ---------------------------------------------------------------------
const VIS_STAMP = [null, null];
const EXPLORED = [null, null];
let visGen = 0;
const CIRCLES = {};
function circleCells(r) {
  const k = Math.round(r / CELL);
  if (CIRCLES[k]) return CIRCLES[k];
  const out = [];
  for (let dy = -k; dy <= k; dy++) for (let dx = -k; dx <= k; dx++) if (dx * dx + dy * dy <= k * k + k) out.push([dx, dy]);
  return (CIRCLES[k] = out);
}
function initVision() {
  for (let t = 0; t < 2; t++) { VIS_STAMP[t] = new Uint32Array(GW * GH); EXPLORED[t] = new Uint8Array(GW * GH); }
}
function stampVision(team, x, y, r) {
  const S = VIS_STAMP[team], E = EXPLORED[team];
  const cx = (x / CELL) | 0, cy = (y / CELL) | 0;
  for (const [dx, dy] of circleCells(r)) {
    const X = cx + dx, Y = cy + dy; if (X < 0 || Y < 0 || X >= GW || Y >= GH) continue;
    const i = Y * GW + X; S[i] = visGen; E[i] = 1;
  }
}
function cellVisible(team, x, y) { return VIS_STAMP[team][cellOf(x, y)] === visGen; }
function isConcealed(u) {
  if (u.cls !== 'inf') return false;
  if (u.revealT > 0) return false;
  if (MAP.terr[cellOf(u.x, u.y)] === T_FOREST) return true;
  return !!u.def.camo && u.stillT > 1.2;
}
function updateVision() {
  visGen++;
  G.jammers.length = 0;
  for (const T of G.teams) { T.radars = 0; }
  for (const u of G.units) {
    if (u.dead) continue;
    stampVision(u.team, u.x, u.y, u.def.vision);
    if (u.type === 'jammer') G.jammers.push(u);
    if (u.type === 'radar') G.teams[u.team].radars++;
    u.aura = false; u.supplied = 0;
  }
  for (const d of G.drones) if (!d.dead) stampVision(d.team, d.x, d.y, 240);
  for (const p of G.points) if (p.owner >= 0) stampVision(p.owner, p.x, p.y, 200);
  // officer aura
  for (const u of G.units) {
    if (u.dead || u.type !== 'officer') continue;
    for (const o of G.grid.query(u.x, u.y, u.def.aura)) if (o.team === u.team && !o.dead) o.aura = true;
  }
  // unit visibility per team
  for (const u of G.units) {
    if (u.dead) continue;
    const other = 1 - u.team;
    u.vis[u.team] = true;
    if (u.cls === 'bld') { u.vis[other] = cellVisible(other, u.x, u.y) || EXPLORED[other][cellOf(u.x, u.y)] === 1; continue; }
    let v = cellVisible(other, u.x, u.y) || u.spotT > 0;
    if (v && isConcealed(u) && u.spotT <= 0) {
      v = false;
      for (const e of G.grid.query(u.x, u.y, 700)) {
        if (e.team !== other || e.dead || e.cls === 'air') continue;
        const det = e.def.detect || 110;
        if (dist2(e.x, e.y, u.x, u.y) < det * det) { v = true; break; }
      }
    }
    u.vis[other] = v;
  }
  for (const d of G.drones) { d.vis[1 - d.team] = cellVisible(1 - d.team, d.x, d.y); d.vis[d.team] = true; }
}

// ---------------------------------------------------------------------
// capture points & economy (1 Hz)
// ---------------------------------------------------------------------
function updatePoints(dt) {
  for (const p of G.points) {
    const str = [0, 0];
    for (const u of G.grid.query(p.x, p.y, p.r)) {
      if (u.dead || u.cls === 'air' || u.cls === 'bld') continue;
      str[u.team] += u.def.capture || (u.cls === 'veh' ? 2 : 1);
    }
    p.contested = str[0] > 0 && str[1] > 0;
    p.str = str;
    let delta = 0;
    if (!p.contested) {
      const s = Math.min(10, str[0] || str[1]);
      const dir = str[0] ? 1 : str[1] ? -1 : 0;
      delta = dir * (5 + s * 2.2) * dt;
    }
    const before = p.prog;
    p.prog = clamp(p.prog + delta, -100, 100);
    if (before > 0 && p.prog <= 0 && p.owner === 0) { setOwner(p, -1); }
    if (before < 0 && p.prog >= 0 && p.owner === 1) { setOwner(p, -1); }
    if (p.prog >= 100 && p.owner !== 0) setOwner(p, 0);
    if (p.prog <= -100 && p.owner !== 1) setOwner(p, 1);
    // drift back to the owner when nobody is around
    if (!str[0] && !str[1]) { if (p.owner === 0) p.prog = Math.min(100, p.prog + 4 * dt); else if (p.owner === 1) p.prog = Math.max(-100, p.prog - 4 * dt); else p.prog *= Math.pow(0.9, dt); }
  }
}
function setOwner(p, team) {
  const prev = p.owner;
  p.owner = team;
  if (team >= 0) {
    p.flash = 1;
    ring(p.x, p.y, 20, p.r + 40, 0.9, team === 0 ? TEAM[0].rgb : TEAM[1].rgb, 5);
    if (G.playerTeam >= 0) {
      if (team === G.playerTeam) { notify(`Point ${p.letter} captured`, 'good', p.x, p.y); Sound.play('capture', 0.7); }
      else notify(`Point ${p.letter} lost to the enemy`, 'bad', p.x, p.y);
    }
  } else if (prev >= 0 && G.playerTeam >= 0 && prev === G.playerTeam) notify(`Point ${p.letter} is being taken`, 'warn', p.x, p.y);
}
// first minute is a grace period; the bleed caps at a 4-point lead
function bleedRate(diff) { return Math.min(4, Math.abs(diff)) * BLEED; }
function economyTick(dt) {
  const held = [0, 0];
  for (const p of G.points) if (p.owner >= 0) held[p.owner]++;
  for (let t = 0; t < 2; t++) {
    const T = G.teams[t];
    let inc = BASE_INCOME + held[t] * POINT_INCOME;
    // supply trucks parked on held points
    for (const u of G.units) {
      if (u.dead || u.team !== t || u.type !== 'supply' || u.moving) continue;
      for (const p of G.points) if (p.owner === t && dist2(p.x, p.y, u.x, u.y) < p.r * p.r) { inc += 2; break; }
    }
    if (G.ai[t]) inc *= G.ai[t].p.income;
    T.income = inc;
    T.supply += inc * dt;
    T.held = held[t];
  }
  // ticket bleed: the side holding fewer points loses the difference
  const diff = held[0] - held[1];
  if (diff !== 0 && G.time > 60) {
    const loser = diff > 0 ? 1 : 0;
    G.teams[loser].tickets = Math.max(0, G.teams[loser].tickets - bleedRate(diff) * dt);
  }
}

// ---------------------------------------------------------------------
// production
// ---------------------------------------------------------------------
function popUsed(t) {
  let p = 0;
  for (const u of G.units) if (!u.dead && u.team === t) p += u.def.pop;
  for (const q of G.teams[t].queues) for (const it of q) p += UNITS[it.p.unit].pop * it.p.n;
  return p;
}
function canQueue(t, prod) {
  const T = G.teams[t];
  if (T.supply < prod.cost) return 'Not enough supply';
  if (popUsed(t) + UNITS[prod.unit].pop * prod.n > POP_CAP) return 'Army at full strength';
  if (T.queues[prod.line].length >= 6) return 'Queue is full';
  return null;
}
function queueProduct(t, prod) {
  const err = canQueue(t, prod);
  if (err) return err;
  const T = G.teams[t];
  T.supply -= prod.cost;
  T.stats.spent += prod.cost;
  T.queues[prod.line].push({ p: prod, t: 0 });
  return null;
}
function cancelProduct(t, prod) {
  const q = G.teams[t].queues[prod.line];
  for (let i = q.length - 1; i >= 0; i--) if (q[i].p === prod) { G.teams[t].supply += prod.cost; G.teams[t].stats.spent -= prod.cost; q.splice(i, 1); return true; }
  return false;
}
function updateProduction(dt) {
  for (let t = 0; t < 2; t++) {
    const T = G.teams[t];
    if (!T.hq || T.hq.dead) continue;
    for (let l = 0; l < 2; l++) {
      const q = T.queues[l];
      if (!q.length) continue;
      const it = q[0];
      it.t += dt * (G.ai[t] ? G.ai[t].p.income : 1);
      if (it.t >= it.p.time) { q.shift(); deploy(t, it.p); }
    }
  }
}
function deploy(t, prod) {
  const T = G.teams[t]; const hq = T.hq;
  const dir = t === 0 ? 1 : -1;
  const sx = hq.x + dir * 130, sy = hq.y + (prod.line === 0 ? -50 : 50);
  const made = [];
  for (let i = 0; i < prod.n; i++) {
    const u = spawnUnit(prod.unit, t, sx + rand(-14, 14), sy + rand(-24, 24));
    u.ang = u.tang = t === 0 ? 0 : Math.PI;
    made.push(u);
  }
  T.stats.built += prod.n;
  const r = T.rally;
  issueMove(made, r.x + rand(-40, 40), r.y + rand(-40, 40), true);
  if (G.ai[t]) G.ai[t].onDeploy(made, prod);
  if (t === G.playerTeam) { Sound.play('build', 0.5); G.onDeployed(made, prod); }
  return made;
}
