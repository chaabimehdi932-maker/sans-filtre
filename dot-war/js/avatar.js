'use strict';
// =====================================================================
// You are one soldier in a big war. Both armies are run by AI generals;
// you walk, shoot, throw grenades, jump into jeeps and tanks and drive
// them. This file: spawning, direct control, vehicles, orders, score.
// =====================================================================

function newMe() {
  return {
    soldier: null, vehicle: null, cls: null, alive: false, respawnT: 0, drone: null,
    score: 0, kills: 0, vkills: 0, captures: 0, missions: 0, lost: 0, dmg: 0,
    mission: null, missionT: 3, hurtT: -99, hitT: -99, abilityCd: 0, nadeT: 0, firstDeploy: true,
    units: [], kit: { role: 'capture' }, zoom: 1.35,
  };
}
// the thing you control right now: your soldier, or the vehicle you drive
const avatar = () => (G.me.vehicle && !G.me.vehicle.dead ? G.me.vehicle : G.me.soldier);
function myCenter() { const a = G.me && G.me.alive && avatar(); return a ? { x: a.x, y: a.y } : { x: G.teams[0].hq.x, y: G.teams[0].hq.y }; }

// ---------------------------------------------------------------------
// spawning
// ---------------------------------------------------------------------
function enemiesNear(x, y, r, team) {
  for (const e of G.grid.query(x, y, r)) if (e.team !== team && !e.dead && e.cls !== 'air' && e.cls !== 'bld' && e.vis[team]) return true;
  return false;
}
function spawnPoints() {
  const T = G.teams[0];
  const list = [{ id: 'hq', label: 'HQ', x: T.hq.x + 170, y: T.hq.y + 40 }];
  for (const p of G.points) {
    if (p.owner !== 0 || enemiesNear(p.x, p.y, 520, 0)) continue;
    list.push({ id: p.letter, label: p.letter, x: p.x - 50, y: p.y + 20 });
  }
  return list;
}
function deployMe(cls, spawnId) {
  const me = G.me;
  if (me.soldier && !me.soldier.dead) removeSoldier();
  const sps = spawnPoints();
  const sp = sps.find((s) => s.id === spawnId) || sps[0];
  const u = spawnUnit(cls.unit, 0, sp.x, sp.y);
  u.avatar = true; u.player = true; u.direct = true; u.auto = false;
  u.hp = u.maxHp = cls.hp; u.ang = 0;
  const g = PLAYER_GUNS[cls.gun];
  u.gun = { id: cls.gun, def: g, mag: g.mag, reloadT: 0, cd: 0 };
  u.nades = cls.nades;
  me.soldier = u; me.vehicle = null; me.cls = cls; me.alive = true;
  me.kit = { role: cls.role, cls: 'inf' };
  me.units = [u];
  me.mission = null; me.missionT = 2; me.abilityCd = 0; me.nadeT = 0;
  G.sel = new Set([u]);
  G.cam.x = u.x; G.cam.y = u.y;
  for (let k = 0; k < 8; k++) dust(sp.x + rand(-30, 30), sp.y + rand(-30, 30), 1, 1);
  Sound.play('build', 0.5);
  me.firstDeploy = false;
}
// switching class without dying: your soldier walks off the field
function removeSoldier() {
  const me = G.me;
  if (me.vehicle) exitVehicle(true);
  me.soldier.dead = true; me.soldier.hp = 0;
  me.alive = false;
}

// ---------------------------------------------------------------------
// vehicles
// ---------------------------------------------------------------------
function nearestVehicle() {
  const s = G.me.soldier; let best = null, bd = 1e9;
  for (const v of G.grid.query(s.x, s.y, 90)) {
    if (v.team !== 0 || v.dead || v.cls !== 'veh' || v.player) continue;
    const d = dist(s.x, s.y, v.x, v.y) - v.r;
    if (d < 40 && d < bd) { bd = d; best = v; }
  }
  return best;
}
function enterVehicle(v) {
  const me = G.me, s = me.soldier;
  if (!v.empty && G.ai[0]) G.ai[0].release([v]);
  v.empty = false; v.player = true; v.direct = true; v.auto = false;
  v.order = null; v.path = null; v.override = null; v.vel = 0; v.speedCap = 0;
  for (const w of v.weapons) { w.target = null; w.manual = null; }
  s.inside = v;
  me.vehicle = v; me.units = [s, v];
  G.sel = new Set([v]);
  Sound.play('ui', 0.4);
  notify(`You're driving the ${v.def.name.toLowerCase()}. E to get out.`, 'info');
}
function exitVehicle(silent) {
  const me = G.me, v = me.vehicle, s = me.soldier;
  if (!v) return;
  s.inside = null;
  // step out on whichever side is free
  for (const side of [1, -1, 2]) {
    const a = v.ang + (side === 2 ? Math.PI : (Math.PI / 2) * side), r = v.def.wid / 2 + 16;
    const x = v.x + Math.cos(a) * r, y = v.y + Math.sin(a) * r;
    if (!blockedAt(x, y)) { s.x = x; s.y = y; break; }
  }
  if (!v.dead) { v.player = false; v.direct = false; v.empty = true; v.emptyT = 0; v.vel = 0; v.speedNow = 0; v.moving = false; }
  me.vehicle = null; me.units = [s];
  G.sel = new Set([s]);
  if (!silent) Sound.play('ui', 0.3);
}
// your vehicle blew up with you inside
function vehicleLost() {
  const me = G.me, s = me.soldier;
  me.vehicle = null; s.inside = null; me.units = [s];
  G.sel = new Set([s]);
  s.hp -= s.maxHp * 0.45;
  notify('Your vehicle was destroyed. You bailed out!', 'bad');
  if (s.hp <= 0) killUnit(s, null);
}

// ---------------------------------------------------------------------
// direct control (called every step)
// ---------------------------------------------------------------------
function updateMe(dt) {
  const me = G.me;
  tickParkedVehicles(dt);
  tickJeepDepot(dt);
  if (me.drone && me.drone.dead) me.drone = null;
  if (!me.alive) { me.respawnT = Math.max(0, me.respawnT - dt); return; }
  const s = me.soldier;
  if (!s || s.dead) return;
  me.abilityCd = Math.max(0, me.abilityCd - dt);
  // grenades come back slowly
  if (s.nades < me.cls.nades) { me.nadeT += dt; if (me.nadeT > 25) { me.nadeT = 0; s.nades++; } }
  // health comes back when you stay out of the fight
  if (G.time - s.lastHit > 6 && s.hp < s.maxHp) s.hp = Math.min(s.maxHp, s.hp + 7 * dt);
  const v = me.vehicle;
  if (v && !v.dead) { driveVehicle(v, dt); if (me.cls.id === 'engineer' && G.time - v.lastHit > 3) v.hp = Math.min(v.maxHp, v.hp + 12 * dt); }
  else if (!me.drone) walk(s, dt);
  else { s.moving = false; s.speedNow = 0; s.stillT += dt; }
  if (!me.drone) aimAndFire(dt);
  missionTick(dt);
}

function moveInput() {
  let x = 0, y = 0;
  if (keys.KeyW || keys.ArrowUp) y -= 1;
  if (keys.KeyS || keys.ArrowDown) y += 1;
  if (keys.KeyA || keys.ArrowLeft) x -= 1;
  if (keys.KeyD || keys.ArrowRight) x += 1;
  if (G.touch && G.touch.move) { x += G.touch.move.x; y += G.touch.move.y; }
  const l = Math.hypot(x, y);
  return l > 1 ? { x: x / l, y: y / l } : { x, y };
}
function walk(s, dt) {
  const inp = moveInput();
  const sprint = keys.ShiftLeft || keys.ShiftRight;
  let spd = s.def.speed * 1.35 * (G.me.cls.speed || 1) * terrainSpeed(s) * (sprint ? 1.45 : 1);
  if (s.sup > 50) spd *= 0.55;
  let vx = inp.x * spd, vy = inp.y * spd;
  // don't walk through vehicles and buildings
  for (const o of G.grid.query(s.x, s.y, s.r + 40)) {
    if (o === s || o.dead || o.cls === 'air' || o.cls === 'inf') continue;
    const dx = s.x - o.x, dy = s.y - o.y, d = Math.hypot(dx, dy) || 1, min = s.r + o.r;
    if (d < min) { s.x += (dx / d) * (min - d); s.y += (dy / d) * (min - d); }
  }
  const nx = s.x + vx * dt, ny = s.y + vy * dt;
  if (!blockedAt(nx, ny)) { s.x = nx; s.y = ny; } else if (!blockedAt(nx, s.y)) s.x = nx; else if (!blockedAt(s.x, ny)) s.y = ny;
  s.x = clamp(s.x, 8, W - 8); s.y = clamp(s.y, 8, H - 8);
  s.moving = inp.x !== 0 || inp.y !== 0; s.speedNow = s.moving ? spd : 0;
  if (s.moving) s.stillT = 0; else s.stillT += dt;
  s.ang = Math.atan2(G.mouse.wy - s.y, G.mouse.wx - s.x);
}
function driveVehicle(v, dt) {
  const d = v.def, inp = moveInput();
  const fwd = -inp.y, turn = inp.x;
  const max = d.speed * 1.1 * terrainSpeed(v) * (v.hp < v.maxHp * 0.3 ? 0.75 : 1);
  const target = fwd > 0 ? max : fwd < 0 ? -max * 0.45 : 0;
  const acc = (Math.sign(target) !== Math.sign(v.vel || 0) && target !== 0 ? 2.4 : 1.2) * d.speed;
  const cur = v.vel || 0, step = acc * dt;
  v.vel = cur < target ? Math.min(target, cur + step) : Math.max(target, cur - step);
  const car = v.type === 'jeep' || d.truck;
  const tr = d.turn * (car ? clamp(Math.abs(v.vel) / (d.speed * 0.35), 0, 1) : 1) * (v.vel < -2 ? -1 : 1);
  v.ang += turn * tr * dt;
  let nx = v.x + Math.cos(v.ang) * v.vel * dt, ny = v.y + Math.sin(v.ang) * v.vel * dt;
  // bump into buildings and vehicles, run over enemy infantry
  for (const o of G.grid.query(nx, ny, v.r + 40)) {
    if (o === v || o.dead || o.cls === 'air') continue;
    const dx = nx - o.x, dy = ny - o.y, dd = Math.hypot(dx, dy) || 1;
    if (o.cls === 'inf') {
      if (dd < v.r + o.r && Math.abs(v.vel) > 45 && o.team !== v.team && G.time - (o.ramT || 0) > 0.6) {
        o.ramT = G.time; damage(o, 30 + Math.abs(v.vel) * 0.7, v, 30, v.x, v.y);
        o.x -= (dx / dd) * 8; o.y -= (dy / dd) * 8;
      }
      continue;
    }
    const min = (v.r + o.r) * 0.85;
    if (dd < min) { nx = o.x + (dx / dd) * min; ny = o.y + (dy / dd) * min; v.vel *= 0.5; }
  }
  if (!blockedAt(nx, ny)) { v.x = nx; v.y = ny; } else v.vel *= -0.2;
  v.x = clamp(v.x, 10, W - 10); v.y = clamp(v.y, 10, H - 10);
  v.speedNow = Math.abs(v.vel); v.moving = v.speedNow > 4;
  if (v.moving) v.stillT = 0; else v.stillT += dt;
  if (v.moving) {
    v.trackAcc += v.speedNow * dt;
    if (v.trackAcc > 9) { v.trackAcc = 0; decalTrack(v); if (Math.random() < 0.3 && terrAt(v.x, v.y) !== T_ROAD) dust(v.x - Math.cos(v.ang) * d.len * 0.5, v.y - Math.sin(v.ang) * d.len * 0.5, 0.7, 1); }
  }
  const s = G.me.soldier; s.x = v.x; s.y = v.y;
  // the turret follows the mouse
  const aim = Math.atan2(G.mouse.wy - v.y, G.mouse.wx - v.x);
  if (v.weapons[0] && v.weapons[0].def.turret) v.tang = rotTo(v.tang, aim, (d.tturn || 3) * dt);
  else v.tang = v.ang;
}

// ---------------------------------------------------------------------
// shooting
// ---------------------------------------------------------------------
// a bullet along a line: hits the first enemy it crosses
function shootRay(u, x0, y0, ang, range, dmg, vs, sup, tracerKind, air) {
  const c = Math.cos(ang), s = Math.sin(ang);
  let hit = null, ht = range;
  for (let d = 0; d <= range && d <= ht + 20; d += 16) {
    for (const e of G.grid.query(x0 + c * d, y0 + s * d, 18)) {
      if (e.team === u.team || e.dead) continue;
      if (e.cls === 'air' && (!air || e.isMissile)) continue;
      const ex = e.x - x0, ey = e.y - y0, along = ex * c + ey * s;
      if (along < 0 || along > ht) continue;
      const rad = (e.cls === 'veh' ? e.def.wid * 0.6 : e.cls === 'bld' ? e.r : e.r || 8) + 2;
      if (Math.abs(-ex * s + ey * c) <= rad) { ht = along; hit = e; }
    }
  }
  const ex = x0 + c * ht, ey = y0 + s * ht;
  const col = tracerKind === 1 ? '255,190,90' : tracerKind === 2 ? '255,255,235' : '255,225,150';
  tracer(x0, y0, ex, ey, col, tracerKind === 2 ? 2 : 1.4, tracerKind === 2 ? 4200 : 3000, tracerKind === 2 ? 160 : 70);
  if (hit) {
    damage(hit, dmg * ((vs && vs[hit.cls]) || 1), u, sup, x0, y0);
    G.me.hitT = G.time;
    if (hit.cls === 'veh' || hit.cls === 'bld') sparks(ex, ey, 3, 160); else part({ kind: 'dust', x: ex, y: ey, life: 0.3, s0: 2, s1: 8, a0: 0.6 });
  } else if (terrAt(ex, ey) === T_WATER) part({ kind: 'water', x: ex, y: ey, life: 0.4, s0: 2, s1: 7, a0: 0.7 });
  else part({ kind: 'dust', x: ex, y: ey, life: 0.4, s0: 2, s1: 9, a0: 0.45 });
  return hit;
}
const SOFT_VS = { inf: 1, veh: 0.05, bld: 0.05, air: 1 };
let mouseWasDown = false;
function aimAndFire(dt) {
  const me = G.me, s = me.soldier, v = me.vehicle;
  const m = G.mouse;
  const down = m.down && !m.overHud && !G.aim;
  const click = down && !mouseWasDown;
  mouseWasDown = m.down;
  if (v && !v.dead) { vehicleFire(v, down, click, m.right && !m.overHud); return; }
  const g = s.gun, gd = g.def;
  g.cd -= dt;
  if (g.reloadT > 0) { g.reloadT -= dt; if (g.reloadT <= 0) g.mag = gd.mag; return; }
  if (g.mag <= 0) { startReload(); return; }
  if (!(gd.auto ? down : click) || g.cd > 0) return;
  g.cd = gd.cd; g.mag--;
  const a = s.ang;
  const spread = gd.spread * (s.moving ? 1.8 : 1) * (keys.ShiftLeft ? 1.5 : 1) * (s.sup > 50 ? 1.6 : 1);
  const mx = s.x + Math.cos(a) * 12 - Math.sin(a) * 6, my = s.y + Math.sin(a) * 12 + Math.cos(a) * 6;
  s.revealT = Math.max(s.revealT, gd.kind === 'rocket' ? 3 : 1.5);
  if (gd.kind === 'rocket') {
    const d = Math.min(gd.range, dist(s.x, s.y, m.wx, m.wy));
    const tx = s.x + Math.cos(a) * d, ty = s.y + Math.sin(a) * d;
    // homes onto a vehicle near the cursor, like the AI's rockets
    let lock = null, ld = 50; for (const e of G.grid.query(m.wx, m.wy, 50)) if (e.team === 1 && !e.dead && e.cls === 'veh') { const dd = dist(e.x, e.y, m.wx, m.wy); if (dd < ld) { ld = dd; lock = e; } }
    G.projs.push({ kind: 'rocket', team: 0, src: s, x: mx, y: my, ang: a + rand(-gd.spread, gd.spread), target: lock, tx, ty, speed: gd.speed, dmg: gd.dmg, splash: gd.splash, vs: gd.vs, sup: 20, t: 0, life: 2.2, acc: 0.95, wob: rand(0, TAU) });
    const ba = a + Math.PI;
    for (let i = 0; i < 6; i++) part({ kind: 'smoke', x: s.x + Math.cos(ba) * 14, y: s.y + Math.sin(ba) * 14, vx: Math.cos(ba + rand(-0.4, 0.4)) * rand(60, 140), vy: Math.sin(ba + rand(-0.4, 0.4)) * rand(60, 140), life: rand(0.8, 1.6), s0: 6, s1: 22, a0: 0.5, drag: 0.9 });
    muzzle(mx, my, a, 1.3); shake(s.x, s.y, 1.5);
  } else {
    shootRay(s, mx, my, a + rand(-spread, spread), gd.range, gd.dmg, SOFT_VS, gd.sup, gd.tracer, gd.air);
    muzzle(mx, my, a, gd.dmg > 60 ? 1.1 : 0.6);
    if (gd.dmg > 60) shake(s.x, s.y, 1);
  }
  Sound.at(gd.snd, s.x, s.y, 0.55);
  if (g.mag <= 0) startReload();
}
function startReload() {
  const g = G.me.soldier.gun;
  if (g.reloadT > 0 || g.mag === g.def.mag) return;
  g.reloadT = g.def.reload;
  Sound.play('throw', 0.3);
}
function throwGrenade() {
  const me = G.me, s = me.soldier;
  if (!me.alive || me.vehicle || s.nades <= 0) return;
  s.nades--;
  const m = G.mouse;
  const d = Math.min(280, dist(s.x, s.y, m.wx, m.wy)), a = Math.atan2(m.wy - s.y, m.wx - s.x);
  const tx = s.x + Math.cos(a) * d, ty = s.y + Math.sin(a) * d;
  G.projs.push({ kind: 'lob', team: 0, src: s, x: s.x, y: s.y, sx: s.x, sy: s.y, tx, ty, target: null, t: 0, T: 0.55 + d / 340, h: 30 + d * 0.18, dmg: 75, splash: 60, vs: { inf: 1, veh: 0.35, bld: 0.4 }, sup: 35, satchel: false, spin: rand(0, TAU) });
  Sound.play('throw', 0.4);
}
// vehicle guns: left click = main gun at the cursor, right click = machine gun
function vehicleFire(v, down, click, right) {
  const m = G.mouse, w0 = v.weapons[0], w1 = v.weapons[1];
  const aim = Math.atan2(m.wy - v.y, m.wx - v.x);
  if (v.type === 'missile') { if (click) { G.aim = { ab: 'missile' }; castAim(m.wx, m.wy); } return; }
  if (w0 && down && w0.cd <= 0 && w0.salvo <= 0) {
    const wd = w0.def, dd = dist(v.x, v.y, m.wx, m.wy);
    if (wd.arty) {
      if (!click) return;
      if (v.moving || v.stillT < 0.8) { notify('Stop the truck to fire', 'info'); return; }
      if (dd > wd.range || dd < wd.min) { notify(`Out of range (${wd.min}–${wd.range} m)`, 'info'); Sound.play('error', 0.3); return; }
      v.ang = aim;
      w0.cd = wd.cd; fireWeapon(v, w0, { x: m.wx, y: m.wy, fake: true, moving: false }, dd);
    } else if (wd.kind === 'shell' || wd.kind === 'rocket') {
      if (Math.abs(angDiff(v.tang, aim)) > 0.12) return;
      const d = Math.min(wd.range, dd);
      w0.cd = wd.cd;
      fireWeapon(v, w0, { x: v.x + Math.cos(v.tang) * d, y: v.y + Math.sin(v.tang) * d, fake: true, moving: false }, d);
    } else if (wd.kind === 'bullet') {
      w0.cd = wd.cd;
      const mz = muzzlePos(v, w0);
      shootRay(v, mz.x, mz.y, mz.a + rand(-0.05, 0.05), wd.airRange || wd.range, wd.dmg * 1.4, wd.vs, wd.sup, wd.tracer || 1, true);
      muzzle(mz.x, mz.y, mz.a, 0.9);
      Sound.at(wd.snd, v.x, v.y, 0.5);
    }
  }
  if (w1 && right && w1.cd <= 0 && w1.def.kind === 'bullet') {
    const wd = w1.def; w1.cd = wd.cd;
    const mz = muzzlePos(v, w0 || w1);
    shootRay(v, mz.x, mz.y, aim + rand(-0.06, 0.06), wd.range, wd.dmg * 1.4, wd.vs, wd.sup, 1, true);
    muzzle(mz.x, mz.y, aim, 0.6);
    Sound.at('mg', v.x, v.y, 0.4);
  }
}

// ---------------------------------------------------------------------
// class abilities (Q)
// ---------------------------------------------------------------------
function useAbility() {
  const me = G.me, s = me.soldier;
  if (!me.alive || me.vehicle) return;
  const id = me.cls.id;
  if (id === 'medic') {
    if (me.abilityCd > 0) { notify(`Medkit ready in ${Math.ceil(me.abilityCd)} s`, 'info'); return; }
    s.hp = s.maxHp; s.sup = 0; me.abilityCd = 40;
    for (let i = 0; i < 8; i++) part({ kind: 'glow', add: true, x: s.x + rand(-8, 8), y: s.y + rand(-8, 8), vy: -30, life: 0.7, s0: 6, s1: 2, a0: 0.9 });
    floatText(s.x, s.y - 20, 'HEALED', '#9be7ff'); Sound.play('build', 0.4);
    return;
  }
  if (id === 'engineer') {
    if (s.abilityCd > 0) { notify(`Next mine in ${Math.ceil(s.abilityCd)} s`, 'info'); return; }
    layMine(s, s.x, s.y); notify('AT mine planted', 'info'); return;
  }
  if (id === 'drone') {
    if (me.drone && !me.drone.dead) return;
    if (s.abilityCd > 0) { notify(`Next drone in ${Math.ceil(s.abilityCd)} s`, 'info'); return; }
    launchDrone(s, null); notify('Drone up: steer with the mouse, click to detonate', 'info'); return;
  }
  if (id === 'radio') {
    if (s.abilityCd > 0) { notify(`Barrage ready in ${Math.ceil(s.abilityCd)} s`, 'info'); return; }
    G.aim = { ab: 'barrage' }; return;
  }
  notify(`${me.cls.name}: right click throws a grenade`, 'info');
}
function castAim(wx, wy) {
  const ab = G.aim.ab; G.aim = null;
  const me = G.me, u = ab === 'missile' ? me.vehicle : me.soldier;
  if (!u) return;
  if (!cellVisible(0, wx, wy)) { notify('Nobody on your side can see that spot', 'info'); Sound.play('error', 0.4); return; }
  if (u.abilityCd > 0) { notify(`${ABILITIES[ab].name} ready in ${Math.ceil(u.abilityCd)} s`, 'info'); Sound.play('error', 0.4); return; }
  if (dist(u.x, u.y, wx, wy) > ABILITIES[ab].range) { notify(`Out of range (${ABILITIES[ab].range} m)`, 'info'); Sound.play('error', 0.4); return; }
  castAbility(u, wx, wy, null);
  G.markers.push({ x: wx, y: wy, t: 0, color: 'rgba(120,200,255,A)' });
}

// ---------------------------------------------------------------------
// parked vehicles and the jeep depot
// ---------------------------------------------------------------------
function tickParkedVehicles(dt) {
  for (const v of G.units) {
    if (!v.empty || v.dead) continue;
    v.emptyT += dt;
    // army vehicles you leave get a new crew after a while; jeeps wait for you
    if (v.type !== 'jeep' && v.emptyT > 20 && G.ai[0]) { v.empty = false; G.ai[0].adopt([v]); }
  }
}
function spawnJeep(x, y, ang) {
  const j = spawnUnit('jeep', 0, x, y);
  j.empty = true; j.emptyT = 0; j.ang = j.tang = ang || 0;
  return j;
}
let depotT = 0;
function tickJeepDepot(dt) {
  depotT -= dt; if (depotT > 0) return;
  depotT = 15;
  const hq = G.teams[0].hq; if (!hq || hq.dead) return;
  let parked = 0, total = 0;
  for (const u of G.units) if (u.type === 'jeep' && !u.dead) { total++; if (u.empty && dist(u.x, u.y, hq.x, hq.y) < 420) parked++; }
  if (parked < 2 && total < 8) spawnJeep(hq.x + 120 + parked * 50, hq.y + 150, 0);
}

// ---------------------------------------------------------------------
// orders from command and score
// ---------------------------------------------------------------------
function pointScore(p, c, kind) {
  const info = p.ai[0] || { enemy: 0, own: 0 };
  const d = dist(p.x, p.y, c.x, c.y);
  if (kind === 'attack') return (p.owner === 0 ? -1e9 : 0) + (p.owner === -1 ? 400 : 0) - d - info.enemy * 0.4 + info.own * 0.6;
  if (kind === 'enemy') return (p.owner === 0 && info.enemy < 30 ? -1e9 : 0) + (p.owner === 1 ? 500 : 0) + (p.contested ? 300 : 0) + info.enemy * 2 - d * 0.5;
  if (kind === 'front') return (info.enemy > 0 ? 600 : 0) + info.own * 0.5 - d * 0.7;
  return -d;
}
function bestPoint(kind) {
  const c = myCenter(); let best = null, bs = -1e18;
  for (const p of G.points) { const s = pointScore(p, c, kind); if (s > bs) { bs = s; best = p; } }
  return best;
}
function pickMission() {
  const me = G.me, role = me.cls.role;
  let m = null;
  if (role === 'capture') {
    const c = myCenter();
    const threatened = G.points.find((p) => p.owner === 0 && p.ai[0] && p.ai[0].enemy > 60 && dist(p.x, p.y, c.x, c.y) < 1600);
    if (threatened) m = { kind: 'defend', p: threatened, text: `Defend point ${threatened.letter}`, need: 30, prog: 0, reward: 300 };
    else { const p = bestPoint('attack'); if (p) m = { kind: 'capture', p, text: `Capture point ${p.letter}`, need: 1, prog: 0, reward: 350 }; }
  } else if (role === 'fire') {
    const p = bestPoint('enemy');
    if (p) m = { kind: 'fire', p, text: `Call fire on the enemy at ${p.letter}`, need: 500, prog: 0, reward: 400, r: 480 };
  } else if (role === 'hunt') {
    m = { kind: 'hunt', cls: 'veh', text: 'Destroy an enemy vehicle', need: 1, prog: 0, reward: 400 };
  } else if (role === 'snipe') {
    m = { kind: 'hunt', cls: 'inf', text: 'Pick off 5 enemy soldiers', need: 5, prog: 0, reward: 350 };
  } else {
    const p = bestPoint('front');
    if (p) m = { kind: 'support', p, text: `Support the fight at ${p.letter}`, need: 40, prog: 0, reward: 300, r: 420 };
  }
  if (!m) return;
  m.t = 0; m.limit = 220;
  me.mission = m;
  notify(`New orders: ${m.text}`, 'info', m.p ? m.p.x : undefined, m.p ? m.p.y : undefined);
}
function missionTarget(m) {
  if (m.p) return m.p;
  if (m.kind === 'hunt') {
    const c = myCenter(); let best = null, bd = 1e9;
    for (const e of G.units) { if (e.team !== 1 || e.dead || e.cls !== m.cls || !e.vis[0]) continue; const d = dist(e.x, e.y, c.x, c.y); if (d < bd) { bd = d; best = e; } }
    return best;
  }
  return null;
}
function missionTick(dt) {
  const me = G.me;
  if (!me.mission) { me.missionT -= dt; if (me.missionT <= 0) pickMission(); return; }
  const m = me.mission; m.t += dt;
  const c = myCenter();
  const near = (r) => m.p && dist(c.x, c.y, m.p.x, m.p.y) < r;
  if (m.kind === 'defend') { if (near(m.p.r + 160) && m.p.owner === 0) m.prog += dt; if (m.p.owner === 1) { failMission('Point ' + m.p.letter + ' fell'); return; } }
  else if (m.kind === 'support') { if (near(m.r)) m.prog += dt; }
  else if (m.kind === 'capture' && m.p.owner === 0 && !near(m.p.r + 300)) { failMission(`${m.p.letter} is already ours`); return; }
  if (m.prog >= m.need) { completeMission(); return; }
  if (m.t > m.limit) failMission('Orders expired');
}
function completeMission() {
  const me = G.me, m = me.mission;
  me.missions++; me.score += m.reward;
  notify(`Mission complete: ${m.text}  +${m.reward}`, 'good');
  Sound.play('capture', 0.7);
  const c = myCenter(); floatText(c.x, c.y - 30, `MISSION +${m.reward}`, '#f7d54a');
  me.mission = null; me.missionT = 5;
}
function failMission(why) { G.me.mission = null; G.me.missionT = 3; notify(`New orders coming (${why})`, 'info'); }

// hooks called by the simulation
function playerDamage(t, amount) {
  const me = G.me; me.dmg += amount;
  const m = me.mission;
  if (m && m.kind === 'fire' && t.cls !== 'air' && dist(t.x, t.y, m.p.x, m.p.y) < m.r) m.prog += amount;
}
function playerKill(u) {
  const me = G.me;
  me.kills++; if (u.cls === 'veh') me.vkills++;
  const pts = Math.round((u.def.value || 40) * (u.cls === 'bld' ? 1 : 0.8));
  me.score += pts;
  const m = me.mission;
  if (m && m.kind === 'hunt' && u.cls === m.cls) m.prog++;
  floatText(u.x, u.y - 22, u.cls === 'veh' ? `${u.def.name.toUpperCase()} DESTROYED +${pts}` : `+${pts}`, u.cls === 'veh' ? '#ffd27a' : '#ffffff');
  Sound.play('ui', 0.35);
}
function playerCapture(p) {
  const me = G.me; if (!me.alive) return;
  const c = myCenter();
  if (dist(c.x, c.y, p.x, p.y) > p.r + 200) return;
  me.captures++; me.score += 150;
  floatText(p.x, p.y - 60, `POINT ${p.letter} +150`, '#9be7ff');
  if (me.mission && me.mission.kind === 'capture' && me.mission.p === p) me.mission.prog = 1;
}
// your soldier or your vehicle died
function onPlayerUnitDead(u) {
  const me = G.me;
  if (u === me.vehicle) { vehicleLost(); return; }
  if (u === me.soldier && me.alive) {
    if (me.vehicle && !me.vehicle.dead) { const v = me.vehicle; me.vehicle = null; v.player = false; v.direct = false; v.empty = true; v.emptyT = 0; }
    me.alive = false; me.lost++;
    me.respawnT = 6;
    notify('You were killed', 'bad');
    Sound.play('lost', 0.6);
    setTimeout(() => { if (!G.over && G.mode === 'play' && !G.me.alive) openPicker('dead'); }, 1500);
  }
}
