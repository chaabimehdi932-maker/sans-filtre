'use strict';
// =====================================================================
// You lead one squad in a big war. Both generals are AI; this file is
// everything about your squad: deploying, reinforcements, orders from
// command, and your score. A squad is a team of several units (see
// SQUADS in data.js).
// =====================================================================

function newMe() {
  return {
    units: [], kit: null, group: null, alive: false, respawnT: 0, follow: true, drone: null,
    score: 0, kills: 0, vkills: 0, captures: 0, missions: 0, lost: 0, dmg: 0,
    mission: null, missionT: 3, reinforceT: 0, src: null, firstDeploy: true,
  };
}
const kitHas = (kit, type) => kit.members.some(([t]) => t === type);
const kitAbilities = (kit) => ['missile', 'barrage', 'drone', 'mine'].filter((a) => kit.members.some(([t]) => UNITS[t].ability === a));
function myCenter() {
  const us = G.me.units; let x = 0, y = 0;
  for (const u of us) { x += u.x; y += u.y; }
  return us.length ? { x: x / us.length, y: y / us.length } : { x: G.teams[0].hq.x, y: G.teams[0].hq.y };
}

// ---------------------------------------------------------------------
// deploying
// ---------------------------------------------------------------------
function enemiesNear(x, y, r, team) {
  for (const e of G.grid.query(x, y, r)) if (e.team !== team && !e.dead && e.cls !== 'air' && e.cls !== 'bld' && e.vis[team]) return true;
  return false;
}
// infantry squads can deploy on any point you hold that isn't under fire; vehicles roll out of the HQ
function spawnPoints(kit) {
  const T = G.teams[0];
  const list = [{ id: 'hq', label: 'HQ', x: T.hq.x + 160, y: T.hq.y }];
  if (kit.cls !== 'inf') return list;
  for (const p of G.points) {
    if (p.owner !== 0 || enemiesNear(p.x, p.y, 520, 0)) continue;
    list.push({ id: p.letter, label: p.letter, x: p.x - 60, y: p.y });
  }
  return list;
}
function spawnMember(type, x, y) {
  const u = spawnUnit(type, 0, x, y);
  u.ang = u.tang = 0;
  u.player = true; u.auto = G.me.auto; u.autoArty = G.me.auto;
  u.group = G.me.group;
  return u;
}
function deployMe(kit, spawnId) {
  const me = G.me;
  const sps = spawnPoints(kit);
  const sp = sps.find((s) => s.id === spawnId) || sps[0];
  releaseMe();
  me.kit = kit; me.auto = false;
  me.group = { id: NEXT_ID++, kit, units: [], team: 0 };
  const units = [];
  let i = 0;
  for (const [type, n] of kit.members) {
    for (let k = 0; k < n; k++, i++) {
      const veh = UNITS[type].cls === 'veh';
      const a = (i / kit.size) * TAU, r = kit.size > 1 ? (veh ? 70 : 34) : 0;
      let x = sp.x + Math.cos(a) * r, y = sp.y + Math.sin(a) * r;
      if (blockedAt(x, y)) { x = sp.x + rand(-10, 10); y = sp.y + rand(-10, 10); }
      units.push(spawnMember(type, x, y));
    }
  }
  me.group.units = units;
  setMe(units);
  for (let k = 0; k < 12; k++) dust(sp.x + rand(-60, 60), sp.y + rand(-60, 60), 1.2, 1.2);
  Sound.play('build', 0.5);
  me.firstDeploy = false;
}
function setMe(units) {
  const me = G.me;
  for (const u of units) { u.order = null; u.path = null; u.override = null; u.focus = null; u.guard = { x: u.x, y: u.y }; }
  me.units = units; me.alive = true; me.follow = true;
  me.mission = null; me.missionT = 1.5; me.reinforceT = 0; me.drone = null;
  syncSpeedCap();
  G.sel = new Set(units);
  const c = myCenter(); G.cam.x = c.x; G.cam.y = c.y;
}
// the squad moves at the pace of its slowest member so it stays together
function syncSpeedCap() {
  const us = G.me.units; if (!us.length) return;
  const cap = Math.min(...us.map((u) => u.def.speed));
  for (const u of us) u.speedCap = cap;
}
// switching squads: the old one goes back to the allied general
function releaseMe() {
  const me = G.me;
  const alive = me.units.filter((u) => !u.dead);
  for (const u of alive) { u.player = false; u.auto = true; u.autoArty = false; u.speedCap = 0; for (const w of u.weapons) w.manual = null; }
  if (alive.length && G.ai[0]) G.ai[0].adopt(alive);
  me.units = []; me.group = null; me.alive = false; me.drone = null;
}

// ---------------------------------------------------------------------
// per-frame upkeep
// ---------------------------------------------------------------------
function updateMe(dt) {
  const me = G.me;
  if (me.drone && me.drone.dead) me.drone = null;
  if (!me.alive) { me.respawnT = Math.max(0, me.respawnT - dt); return; }
  const before = me.units.length;
  me.units = me.units.filter((u) => !u.dead);
  if (me.units.length !== before) syncSpeedCap();
  G.sel = new Set(me.units);
  if (!me.units.length) {
    me.alive = false; me.lost++;
    me.respawnT = 4 + me.kit.cost / 150;
    notify('Your squad was wiped out', 'bad');
    Sound.play('lost', 0.6);
    setTimeout(() => { if (!G.over && G.mode === 'play' && !G.me.alive) openPicker('dead'); }, 1200);
    return;
  }
  reinforceTick(dt);
  missionTick(dt);
}

// missing members by type, in squad order
function missingMembers() {
  const me = G.me, have = {};
  for (const u of me.units) have[u.type] = (have[u.type] || 0) + 1;
  const out = [];
  for (const [t, n] of me.kit.members) for (let k = have[t] || 0; k < n; k++) out.push(t);
  return out;
}
// reinforcements arrive while your squad rests near the HQ, a point you hold or a supply truck
function reinforceSource(type) {
  const c = myCenter(), T = G.teams[0];
  if (dist(c.x, c.y, T.hq.x, T.hq.y) < 520) return { x: T.hq.x + 150, y: T.hq.y, name: 'the HQ' };
  if (UNITS[type].cls === 'veh') return null; // new vehicles only come from the HQ
  for (const u of G.units) if (u.team === 0 && u.type === 'supply' && !u.dead && dist(u.x, u.y, c.x, c.y) < 280) return { x: u.x, y: u.y, name: 'the supply truck' };
  for (const p of G.points) if (p.owner === 0 && dist(p.x, p.y, c.x, c.y) < p.r + 90) return { x: p.x, y: p.y, name: `point ${p.letter}` };
  return null;
}
function reinforceTick(dt) {
  const me = G.me;
  const missing = missingMembers();
  me.missing = missing.length;
  me.src = null;
  if (!missing.length) { me.reinforceT = 0; return; }
  // infantry first: they are quicker to bring up
  const type = missing.find((t) => UNITS[t].cls === 'inf' && reinforceSource(t)) || missing.find((t) => reinforceSource(t));
  me.src = type ? reinforceSource(type) : null;
  me.nextType = type;
  me.calm = me.units.every((u) => G.time - u.lastHit > 4);
  if (!me.src || !me.calm) { me.reinforceT = 0; return; }
  me.reinforceT += dt;
  me.reinforceNeed = UNITS[type].cls === 'veh' ? 9 : 3;
  if (me.reinforceT < me.reinforceNeed) return;
  me.reinforceT = 0;
  const s = me.src;
  const u = spawnMember(type, s.x + rand(-20, 20), s.y + rand(-20, 20));
  me.group.units.push(u); me.units.push(u);
  syncSpeedCap();
  const c = myCenter();
  issueMove([u], c.x + rand(-25, 25), c.y + rand(-25, 25), false);
  floatText(u.x, u.y - 16, `+ ${UNITS[type].name.toUpperCase()}`, '#9be7ff');
}

// ---------------------------------------------------------------------
// orders: command gives your squad a job that fits what it is
// ---------------------------------------------------------------------
function pointScore(p, c, kind) {
  const info = p.ai[0] || { enemy: 0, own: 0 };
  const d = dist(p.x, p.y, c.x, c.y);
  // join the pushes the allied general is already making
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
  const me = G.me, kit = me.kit;
  let m = null;
  if (kit.role === 'capture') {
    const c = myCenter();
    const threatened = G.points.find((p) => p.owner === 0 && p.ai[0] && p.ai[0].enemy > 60 && dist(p.x, p.y, c.x, c.y) < 1600);
    if (threatened) m = { kind: 'defend', p: threatened, text: `Defend point ${threatened.letter}`, need: 30, prog: 0, reward: 300 };
    else { const p = bestPoint('attack'); if (p) m = { kind: 'capture', p, text: `Capture point ${p.letter}`, need: 1, prog: 0, reward: 350 }; }
  } else if (kit.role === 'fire') {
    const p = bestPoint('enemy');
    const need = kitHas(kit, 'missile') ? 1500 : kitHas(kit, 'howitzer') ? 1300 : kitHas(kit, 'mlrs') ? 1200 : 700;
    if (p) m = { kind: 'fire', p, text: `Fire mission: hit the enemy at ${p.letter}`, need, prog: 0, reward: 400, r: 480 };
  } else if (kit.role === 'hunt') {
    m = { kind: 'hunt', cls: 'veh', text: 'Destroy 2 enemy vehicles', need: 2, prog: 0, reward: 450 };
  } else if (kit.role === 'snipe') {
    m = { kind: 'hunt', cls: 'inf', text: 'Pick off 8 enemy soldiers', need: 8, prog: 0, reward: 350 };
  } else if (kit.role === 'recon') {
    const p = bestPoint('enemy');
    if (p) m = { kind: 'recon', p, text: `Scout point ${p.letter} and stay alive`, need: 18, prog: 0, reward: 300, r: 520 };
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
  else if (m.kind === 'recon') { if (near(m.r)) m.prog += dt; }
  else if (m.kind === 'support') { if (near(m.r)) m.prog += dt; }
  else if (m.kind === 'capture' && m.p.owner === 0 && !near(m.p.r + 300)) { failMission(`${m.p.letter} is already ours`); return; }
  if (m.prog >= m.need) { completeMission(); return; }
  if (m.t > m.limit) { failMission('Orders expired'); }
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
  const pts = Math.round((u.def.value || 40) * (u.cls === 'bld' ? 1 : 0.6));
  me.score += pts;
  const m = me.mission;
  if (m && m.kind === 'hunt' && u.cls === m.cls) m.prog++;
  if (u.cls === 'veh') { floatText(u.x, u.y - 30, `${u.def.name.toUpperCase()} DESTROYED +${pts}`, '#ffd27a'); Sound.play('ui', 0.4); }
}
function playerCapture(p) {
  const me = G.me; if (!me.alive) return;
  const c = myCenter();
  if (dist(c.x, c.y, p.x, p.y) > p.r + 260) return;
  me.captures++; me.score += 150;
  floatText(p.x, p.y - 60, `POINT ${p.letter} +150`, '#9be7ff');
  if (me.mission && me.mission.kind === 'capture' && me.mission.p === p) me.mission.prog = 1;
}

// ---------------------------------------------------------------------
// firing at a spot: every member with a gun that can reach it fires
// ---------------------------------------------------------------------
function squadFireAt(x, y) {
  let any = false, msg = null;
  for (const u of G.me.units) for (const w of u.weapons) {
    if (!MANUAL_KINDS[w.def.kind]) continue;
    const d = dist(u.x, u.y, x, y);
    if (d > w.def.range) { msg = msg || 'Out of range'; continue; }
    if (w.def.min && d < w.def.min) { msg = 'Too close for the guns'; continue; }
    w.manual = { x, y, t: G.time }; any = true;
  }
  return { any, msg };
}
function hasManualFire(kit) {
  return kit.members.some(([t]) => UNITS[t].weapons.some((w) => MANUAL_KINDS[WEAPONS[w].kind]));
}
// artillery squads fire at the ground under an enemy instead of chasing it
function isArtillery(kit) { return kit && (kitHas(kit, 'howitzer') || kitHas(kit, 'mlrs')); }
// the member type with the longest gun that fires by hand (for range rings)
function manualRangeUnit() {
  let best = null, br = 0;
  for (const u of G.me.units) for (const w of u.weapons) if (MANUAL_KINDS[w.def.kind] && w.def.range > br) { br = w.def.range; best = { u, w }; }
  return best;
}
