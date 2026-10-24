'use strict';
// =====================================================================
// The Foxhole layer: towns and their town halls, the supply chain
// (scrap fields, base stockpiles, cargo trucks, ammo), cover, and the
// structures soldiers hammer up (trenches, sandbags, wire, tank traps,
// bunkers, watchtowers, forward bases)
// =====================================================================

// ---------------------------------------------------------------------
// towns
// ---------------------------------------------------------------------
function initTowns() {
  G.points = MAP.points.map((p) => ({ ...p, name: TOWN_NAMES[p.letter], r: 230, owner: -1, hall: null, flash: 0, contested: false, sabotage: false, str: [0, 0], plan: [null, null], ai: [{ enemy: 0, own: 0 }, { enemy: 0, own: 0 }] }));
  const start = { A: 0, B: 0, C: 0, G: 1, H: 1, I: 1 };
  for (const p of G.points) {
    const t = start[p.letter];
    if (t == null) continue;
    const h = placeHall(p, t, true);
    h.stock.bmats = LOGI.townStart.bmats; h.stock.supplies = LOGI.townStart.supplies;
    for (const s of fortPlan(p, t).slice(0, 5)) placeStruct(s.type, t, s.x, s.y, s.ang, true);
  }
}
function placeHall(p, team, built) {
  const h = spawnUnit('townhall', team, p.hx, p.hy);
  h.town = p; h.ang = h.tang = team ? Math.PI : 0;
  p.hall = h;
  if (built) setOwner(p, team); else makeBlueprint(h);
  return h;
}
function townAt(x, y, pad) { for (const p of G.points) if (dist2(p.x, p.y, x, y) < (p.r + (pad || 0)) ** 2) return p; return null; }

let sabotageNoteT = -99;
function updateTowns(dt) {
  const held = [0, 0];
  for (const p of G.points) {
    if (p.hall && p.hall.dead) { p.hall = null; if (p.owner >= 0) setOwner(p, -1); }
    const str = [0, 0];
    for (const u of G.grid.query(p.x, p.y, p.r)) {
      if (u.dead || u.cls === 'air' || u.cls === 'bld' || u.empty) continue;
      str[u.team] += u.cls === 'veh' ? 2 : 1;
    }
    p.str = str; p.contested = str[0] > 0 && str[1] > 0;
    // enemy soldiers inside an undefended town wreck its hall
    const h = p.hall;
    p.sabotage = false;
    if (h && h.built && p.owner >= 0 && str[1 - p.owner] > 0 && str[p.owner] === 0) {
      p.sabotage = true;
      damage(h, Math.min(6, str[1 - p.owner]) * 18 * dt, null, 0);
      if (G.frame % 8 === 0) sparks(h.x + rand(-20, 20), h.y + rand(-20, 20), 2, 90, null, 0, '255,200,120');
      if (p.owner === G.playerTeam && G.time - sabotageNoteT > 20) { sabotageNoteT = G.time; notify(`Enemy soldiers are wrecking the ${p.name} town hall!`, 'warn', p.x, p.y); }
    }
    if (p.owner >= 0) held[p.owner]++;
    if (p.flash > 0) p.flash = Math.max(0, p.flash - dt);
  }
  // victory: hold LOGI.winTowns towns for LOGI.winTime seconds in a row
  for (let t = 0; t < 2; t++) {
    const T = G.teams[t];
    T.held = held[t];
    T.winT = held[t] >= LOGI.winTowns ? T.winT + dt : 0;
    if (T.winT >= LOGI.winTime && !G.over && G.mode !== 'boot') endGame(t, 'towns');
  }
}
function setOwner(p, team) {
  const prev = p.owner;
  p.owner = team;
  if (team >= 0) {
    p.flash = 1;
    ring(p.x, p.y, 20, p.r + 40, 0.9, TEAM[team].rgb, 5);
    if (G.playerTeam >= 0) {
      if (team === G.playerTeam) { notify(`${p.name} is ours: the town hall is up`, 'good', p.x, p.y); Sound.play('capture', 0.7); if (G.me) playerCapture(p); }
      else notify(`The enemy built a town hall in ${p.name}`, 'bad', p.x, p.y);
    }
  } else if (prev >= 0 && G.playerTeam >= 0) {
    if (prev === G.playerTeam) notify(`The ${p.name} town hall was destroyed`, 'bad', p.x, p.y);
    else notify(`Enemy town hall in ${p.name} destroyed. Build ours!`, 'good', p.x, p.y);
  }
}

// ---------------------------------------------------------------------
// bases, stockpiles and trucks
// ---------------------------------------------------------------------

function baseLabel(b) { return b.type === 'hq' ? 'HQ' : b.type === 'townhall' ? b.town.name : 'Forward base'; }
function nearestBase(team, x, y, r, pred) {
  let best = null, bd = (r || 1e9) ** 2;
  for (const b of G.bases[team]) { if (b.dead || (pred && !pred(b))) continue; const d = dist2(b.x, b.y, x, y); if (d < bd) { bd = d; best = b; } }
  return best;
}
// the base a truck at x,y is parked next to
function dockBase(team, x, y) { return nearestBase(team, x, y, 460, (b) => dist(b.x, b.y, x, y) < b.r + 220); }
function scrapAt(x, y) { for (const f of MAP.scrap) if (dist2(f.x, f.y, x, y) < f.r * f.r) return f; return null; }
const cargoTotal = (c) => c.scrap + c.bmats + c.supplies;

// rearm units around a base or a truck, paying from its supplies
function resupplyAround(src, store, r, step) {
  for (const o of G.grid.query(src.x, src.y, r)) {
    if (o.team !== src.team || o.dead || o === src || o.cls === 'air' || o.cls === 'bld' || o.avatar) continue;
    if (o.cls === 'inf' && src.type !== 'supply' && G.time - o.lastHit > 6 && o.hp < o.maxHp) o.hp = Math.min(o.maxHp, o.hp + 3 * step);
    if (!(o.maxAmmo < Infinity) || o.ammo >= o.maxAmmo * 0.9) continue;
    const cost = (1 - o.ammo / o.maxAmmo) * (o.cls === 'inf' ? LOGI.resupplyInf : LOGI.resupplyVeh);
    if (store.supplies < cost) continue;
    store.supplies -= cost; o.ammo = o.maxAmmo;
    if (G.seen(o) && G.frame % 3 === 0) part({ kind: 'glow', add: true, x: o.x, y: o.y - 8, vy: -24, life: 0.5, s0: 4, s1: 2, a0: 0.7 });
  }
}

let logiAcc = 0;
function logisticsTick(dt) {
  logiAcc += dt;
  if (logiAcc < 0.5) return;
  const st = logiAcc; logiAcc = 0;
  G.bases = [[], []];
  for (const u of G.units) if (!u.dead && u.stock && u.built) G.bases[u.team].push(u);
  for (let t = 0; t < 2; t++) {
    const T = G.teams[t], hq = T.hq;
    const mult = G.ai[t] ? G.ai[t].p.income : 1;
    if (hq && !hq.dead) hq.stock.scrap += (LOGI.hqScrap + T.held * LOGI.townScrap) * mult * st;
    for (const b of G.bases[t]) {
      const s = b.stock;
      const r = Math.min(s.scrap, (b === hq ? LOGI.refineHQ : LOGI.refineBase) * st);
      s.scrap -= r; s.bmats += r;
      if (b === hq && s.bmats > 40 && s.supplies < 700) { const f = Math.min(LOGI.factory * mult * st, s.bmats - 40); s.bmats -= f; s.supplies += f; }
      if (s.supplies >= 1) resupplyAround(b, s, b === hq ? 420 : LOGI.baseRange, st);
    }
  }
  // cargo trucks: load scrap while parked in a field, rearm troops around them
  for (const u of G.units) {
    if (u.type !== 'supply' || u.dead || !u.cargo) continue;
    const c = u.cargo;
    if (!u.moving && !u.empty && cargoTotal(c) < u.def.cargoCap && scrapAt(u.x, u.y)) {
      c.scrap = Math.min(u.def.cargoCap - c.bmats - c.supplies, c.scrap + LOGI.gather * st);
      u.gathering = G.time;
      if (G.seen(u)) for (let i = 0; i < 2; i++) sparks(u.x + rand(-20, 20), u.y + rand(-20, 20), 1, 60, null, 0, '255,210,140');
    }
    if (c.supplies >= 1) resupplyAround(u, c, u.def.repairAura.range, st);
  }
}
// truck at a base: unload everything it carries; at the HQ it then loads supplies and bmats
function truckDock(u, b, take) {
  const c = u.cargo, s = b.stock;
  const moved = { scrap: c.scrap, bmats: 0, supplies: 0 };
  s.scrap += c.scrap; c.scrap = 0;
  if (b.type !== 'hq') { moved.bmats = c.bmats; moved.supplies = c.supplies; s.bmats += c.bmats; s.supplies += c.supplies; c.bmats = 0; c.supplies = 0; }
  let loaded = 0;
  if (take) {
    const room = u.def.cargoCap - cargoTotal(c);
    const want = take === true ? { supplies: room * 0.6, bmats: room * 0.4 } : take;
    const sp = Math.max(0, Math.min(want.supplies || 0, s.supplies - 20, room));
    c.supplies += sp; s.supplies -= sp;
    const bm = Math.max(0, Math.min(want.bmats || 0, s.bmats - 30, room - sp));
    c.bmats += bm; s.bmats -= bm;
    loaded = sp + bm;
    // whatever room is left takes more of the other
    const left = u.def.cargoCap - cargoTotal(c);
    if (left > 5 && take === true) { const more = Math.max(0, Math.min(left, s.supplies - 20)); c.supplies += more; s.supplies -= more; loaded += more; }
  }
  return { moved, loaded };
}

// ---------------------------------------------------------------------
// structures & blueprints
// ---------------------------------------------------------------------
function placeStruct(type, team, x, y, ang, built) {
  const u = spawnUnit(type, team, x, y);
  u.ang = u.tang = ang;
  if (!built) makeBlueprint(u);
  return u;
}
function makeBlueprint(u) {
  u.built = false; u.bp = 0; u.bpNeed = STRUCT_BY_ID[u.type].time; u.hp = u.maxHp * 0.15; u.byMe = 0;
}
// amount: worker-seconds of hammering
function progressBuild(u, amount, byMe) {
  if (u.built || u.dead) return;
  u.bp += amount;
  u.hp = Math.min(u.maxHp, u.hp + u.maxHp * 0.85 * amount / u.bpNeed);
  if (byMe) u.byMe += amount;
  if (G.seen(u) && Math.random() < 0.5) dust(u.x + rand(-u.r, u.r) * 0.5, u.y + rand(-u.r, u.r) * 0.5, 0.5, 0.6);
  if (u.bp >= u.bpNeed) completeBuild(u);
}
function completeBuild(u) {
  u.built = true; u.hp = Math.max(u.hp, u.maxHp * 0.9);
  if (G.seen(u)) { ring(u.x, u.y, 8, u.r + 30, 0.5, TEAM[u.team].rgb, 3); Sound.at('build', u.x, u.y, 0.5); }
  if (u.type === 'townhall') setOwner(u.town, u.team);
  if (u.byMe > 0 && G.me) playerBuilt(u);
}
// where p sits in a line structure's frame: lx along the line, ly across it
function lineLocal(o, x, y) { const c = Math.cos(o.ang), s = Math.sin(o.ang), dx = x - o.x, dy = y - o.y; return { lx: dx * c + dy * s, ly: -dx * s + dy * c }; }
function structDist(o, x, y) {
  if (o.def.line) { const { lx, ly } = lineLocal(o, x, y); const L = STRUCT_BY_ID[o.type].len / 2; return Math.hypot(Math.max(0, Math.abs(lx) - L), ly); }
  return Math.max(0, dist(o.x, o.y, x, y) - o.r);
}
// cover and wire, for every soldier (5 Hz)
function updateCover() {
  for (const u of G.units) {
    if (u.cls !== 'inf' || u.dead) continue;
    let cover = 1, slow = 1, trench = false;
    for (const o of G.grid.query(u.x, u.y, 10)) {
      if (!o.def.line || o.dead || !o.built) continue;
      const st = STRUCT_BY_ID[o.type], { lx, ly } = lineLocal(o, u.x, u.y);
      if (Math.abs(lx) > st.len / 2 + 8) continue;
      if (o.type === 'trench' && Math.abs(ly) < 17) { cover = Math.min(cover, st.cover); trench = true; }
      else if (o.type === 'sandbag' && Math.abs(ly) < 24) cover = Math.min(cover, st.cover);
      else if (o.type === 'wire' && Math.abs(ly) < 16 && o.team !== u.team) slow = Math.min(slow, st.slow);
    }
    u.cover = cover; u.slow = slow; u.inTrench = trench;
  }
}
// tanks and landships roll over barbed wire
function crushWire(v, w, dt) {
  if (!v.moving) return;
  const { lx, ly } = lineLocal(w, v.x, v.y);
  if (Math.abs(lx) < STRUCT_BY_ID.wire.len / 2 + 10 && Math.abs(ly) < v.def.wid / 2 + 10) damage(w, 700 * dt, null, 0);
}
// AI soldiers who are not fighting hammer on blueprints and repair structures next to them
function workTick(u, dt) {
  u.workT = (u.workT == null ? rand(0, 0.5) : u.workT) - dt;
  if (u.workT > 0) return;
  u.workT = 0.5;
  u.working = null;
  if (u.moving) return;
  const w = u.weapons[0];
  if (w && w.target && !w.target.dead) return;
  let best = null, bd = 46;
  for (const o of G.grid.query(u.x, u.y, 50)) {
    if (o.team !== u.team || o.dead || o.cls !== 'bld' || (!o.def.struct && o.type !== 'townhall')) continue;
    if (o.built && (o.hp >= o.maxHp || G.time - o.lastHit < 3)) continue;
    const d = structDist(o, u.x, u.y); if (d < bd) { bd = d; best = o; }
  }
  if (!best) return;
  const rate = u.type === 'engineer' ? 2 : 1;
  if (!best.built) progressBuild(best, 0.5 * rate);
  else best.hp = Math.min(best.maxHp, best.hp + 25 * rate);
  u.working = best; u.ang = Math.atan2(best.y - u.y, best.x - u.x);
  if (G.seen(u) && Math.random() < 0.3) Sound.at('build', u.x, u.y, 0.12);
}
// can a structure go here?
function canPlace(type, x, y, ang) {
  if (blockedAt(x, y)) return 'Can\'t build on water';
  const st = STRUCT_BY_ID[type];
  if (st.len) for (const k of [-0.5, 0.5]) if (blockedAt(x + Math.cos(ang) * st.len * k, y + Math.sin(ang) * st.len * k)) return 'Can\'t build on water';
  if (dist(x, y, G.teams[0].hq.x, G.teams[0].hq.y) < 240 || dist(x, y, G.teams[1].hq.x, G.teams[1].hq.y) < 240) return 'Too close to an HQ';
  for (const o of G.grid.query(x, y, 30)) {
    if (o.dead || o.cls !== 'bld') continue;
    if (type === 'townhall' || type === 'fob' || type === 'bunker' || type === 'tower') { if (!o.def.line && dist(o.x, o.y, x, y) < o.r + UNITS[type].r + 8) return 'Something is in the way'; }
    else if (o.type === type && dist(o.x, o.y, x, y) < 24) return 'Already built here';
  }
  if (type === 'fob') for (const b of G.bases[0].concat(G.bases[1])) if (dist(b.x, b.y, x, y) < 500) return 'Too close to another base';
  return null;
}

// ---------------------------------------------------------------------
// fortification plans: where a side digs in around a town it holds
// ---------------------------------------------------------------------
function fortPlan(p, team) {
  if (p.plan[team]) return p.plan[team];
  const ehq = MAP.hq[1 - team];
  const f = Math.atan2(ehq.y - p.y, ehq.x - p.x);
  const fx = Math.cos(f), fy = Math.sin(f), rx = -fy, ry = fx;
  const at = (fwd, lat) => ({ x: p.x + fx * fwd + rx * lat, y: p.y + fy * fwd + ry * lat });
  const line = f + Math.PI / 2;
  const out = [];
  const add = (type, fwd, lat, ang) => { const q = at(fwd, lat); if (!blockedAt(q.x, q.y)) out.push({ type, x: q.x, y: q.y, ang }); };
  add('trench', 165, -70, line); add('trench', 165, 70, line);
  add('wire', 255, -95, line); add('wire', 255, 0, line); add('wire', 255, 95, line);
  add('bunker', 120, 0, f);
  add('sandbag', 105, -160, line + 0.5); add('sandbag', 105, 160, line - 0.5);
  add('tower', -90, 70, 0);
  add('trap', 320, -150, 0); add('trap', 320, 0, 0); add('trap', 320, 150, 0);
  add('trench', 70, -190, line + 0.9); add('trench', 70, 190, line - 0.9);
  return (p.plan[team] = out);
}
function planSlotDone(slot, team) {
  for (const o of G.grid.query(slot.x, slot.y, 20)) if (!o.dead && o.team === team && o.type === slot.type && dist(o.x, o.y, slot.x, slot.y) < 30) return o;
  return null;
}
