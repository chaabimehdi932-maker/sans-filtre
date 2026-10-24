'use strict';
// =====================================================================
// You are one squad in a big war. Both generals are AI; this file is
// everything about your squad: deploying, taking over squads in the
// field, reinforcements, missions from command, and your score.
// =====================================================================

function newMe() {
  return {
    units: [], group: null, prod: null, alive: false, respawnT: 0, follow: true, drone: null,
    score: 0, kills: 0, vkills: 0, captures: 0, missions: 0, lost: 0, dmg: 0,
    mission: null, missionT: 3, reinforceT: 0, src: null, firstDeploy: true,
  };
}
const squadRole = (prod) => {
  const k = prod.unit;
  if (['howitzer', 'mlrs', 'missile', 'radioop'].includes(k)) return 'fire';
  if (['antitank', 'droneop'].includes(k)) return 'hunt';
  if (k === 'sniper') return 'snipe';
  if (['scout', 'radar'].includes(k)) return 'recon';
  if (['medic', 'supply', 'engineer', 'jammer', 'aa', 'officer'].includes(k)) return 'support';
  return 'capture';
};
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
// infantry can deploy on any point you hold that isn't under fire; vehicles roll out of the HQ
function spawnPoints(prod) {
  const T = G.teams[0];
  const list = [{ id: 'hq', label: 'HQ', x: T.hq.x + 150, y: T.hq.y }];
  if (UNITS[prod.unit].cls !== 'inf') return list;
  for (const p of G.points) {
    if (p.owner !== 0 || enemiesNear(p.x, p.y, 520, 0)) continue;
    list.push({ id: p.letter, label: p.letter, x: p.x - 60, y: p.y });
  }
  return list;
}
function deployMe(prod, spawnId) {
  const me = G.me;
  const sp = spawnPoints(prod).find((s) => s.id === spawnId) || spawnPoints(prod)[0];
  releaseMe();
  const units = [];
  for (let i = 0; i < prod.n; i++) {
    const a = rand(0, TAU), r = prod.n > 1 ? rand(12, 42) : 0;
    let x = sp.x + Math.cos(a) * r, y = sp.y + Math.sin(a) * r;
    if (blockedAt(x, y)) { x = sp.x; y = sp.y; }
    const u = spawnUnit(prod.unit, 0, x, y);
    u.ang = u.tang = 0;
    units.push(u);
  }
  const g = { id: NEXT_ID++, prod, units, team: 0 };
  for (const u of units) u.group = g;
  setMe(g, units);
  for (let i = 0; i < 10; i++) dust(sp.x + rand(-40, 40), sp.y + rand(-40, 40), 1.2, 1.2);
  Sound.play('build', 0.5);
  if (me.firstDeploy) me.firstDeploy = false;
}
function setMe(g, units) {
  const me = G.me;
  for (const u of units) {
    u.player = true; u.auto = false; u.autoArty = false;
    u.order = null; u.path = null; u.override = null; u.focus = null; u.guard = { x: u.x, y: u.y };
  }
  me.group = g; me.units = units; me.prod = g.prod; me.alive = true; me.follow = true;
  me.mission = null; me.missionT = 1.5; me.reinforceT = 0; me.drone = null;
  G.sel = new Set(units);
  const c = myCenter(); G.cam.x = c.x; G.cam.y = c.y;
}
// your current squad goes back to the allied general
function releaseMe() {
  const me = G.me;
  const alive = me.units.filter((u) => !u.dead);
  for (const u of alive) { u.player = false; u.auto = true; u.autoArty = false; for (const w of u.weapons) w.manual = null; }
  if (alive.length && G.ai[0]) G.ai[0].adopt(alive);
  me.units = []; me.group = null; me.alive = false; me.drone = null;
}
function takeCommand(g) {
  const alive = g.units.filter((u) => !u.dead);
  if (!alive.length || alive[0].player) return;
  releaseMe();
  G.ai[0].release(alive);
  setMe(g, alive);
  notify(`You now lead this ${g.prod.name.toLowerCase()}`, 'good');
  Sound.play('build', 0.5);
}
// squads in the field you could take over, nearest the front first
function fieldSquads() {
  const seen = new Set(), out = [];
  for (const u of G.units) {
    if (u.team !== 0 || u.dead || !u.group || u.player || seen.has(u.group)) continue;
    seen.add(u.group);
    const live = u.group.units.filter((o) => !o.dead);
    if (!live.length) continue;
    let x = 0, y = 0, hp = 0, max = 0; for (const o of live) { x += o.x; y += o.y; hp += o.hp; max += o.maxHp; }
    x /= live.length; y /= live.length;
    let near = null, nd = 1e9; for (const p of G.points) { const d = dist(p.x, p.y, x, y); if (d < nd) { nd = d; near = p; } }
    out.push({ g: u.group, n: live.length, x, y, hp: hp / max, near: near.letter, front: x });
  }
  return out.sort((a, b) => b.front - a.front);
}

// ---------------------------------------------------------------------
// per-frame upkeep
// ---------------------------------------------------------------------
function updateMe(dt) {
  const me = G.me;
  if (me.drone && me.drone.dead) me.drone = null;
  if (!me.alive) { me.respawnT = Math.max(0, me.respawnT - dt); return; }
  me.units = me.units.filter((u) => !u.dead);
  G.sel = new Set(me.units);
  if (!me.units.length) {
    me.alive = false; me.lost++;
    me.respawnT = 4 + me.prod.cost / 90;
    notify('Your squad was wiped out', 'bad');
    Sound.play('lost', 0.6);
    setTimeout(() => { if (!G.over && G.mode === 'play' && !G.me.alive) openPicker('dead'); }, 1200);
    return;
  }
  reinforceTick(dt);
  missionTick(dt);
}

// reinforcements trickle in while your squad rests near the HQ, a point you hold or a supply truck
function reinforceSource() {
  const c = myCenter(), T = G.teams[0];
  if (dist(c.x, c.y, T.hq.x, T.hq.y) < 480) return { x: T.hq.x + 140, y: T.hq.y, name: 'HQ' };
  for (const u of G.units) if (u.team === 0 && u.type === 'supply' && !u.dead && dist(u.x, u.y, c.x, c.y) < 260) return { x: u.x, y: u.y, name: 'supply truck' };
  for (const p of G.points) if (p.owner === 0 && dist(p.x, p.y, c.x, c.y) < p.r + 80) return { x: p.x, y: p.y, name: `point ${p.letter}` };
  return null;
}
function reinforceTick(dt) {
  const me = G.me;
  const need = me.prod.n - me.units.length;
  me.src = need > 0 ? reinforceSource() : null;
  me.calm = me.units.every((u) => G.time - u.lastHit > 4);
  if (!me.src || !me.calm) { me.reinforceT = 0; return; }
  me.reinforceT += dt;
  if (me.reinforceT < 3) return;
  me.reinforceT = 0;
  const s = me.src;
  const u = spawnUnit(me.prod.unit, 0, s.x + rand(-20, 20), s.y + rand(-20, 20));
  u.player = true; u.auto = me.units[0] ? me.units[0].auto : false; u.group = me.group;
  me.group.units.push(u); me.units.push(u);
  const c = myCenter();
  issueMove([u], c.x + rand(-20, 20), c.y + rand(-20, 20), false);
  floatText(u.x, u.y - 16, '+1 REINFORCEMENT', '#9be7ff');
}

// ---------------------------------------------------------------------
// missions: command gives your squad a job that fits what it is
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
  const me = G.me; const role = squadRole(me.prod);
  let m = null;
  if (role === 'capture') {
    const threatened = G.points.find((p) => p.owner === 0 && p.ai[0] && p.ai[0].enemy > 60 && dist(p.x, p.y, myCenter().x, myCenter().y) < 1600);
    if (threatened) m = { kind: 'defend', p: threatened, text: `Defend point ${threatened.letter}`, need: 30, prog: 0, reward: 300 };
    else { const p = bestPoint('attack'); if (p) m = { kind: 'capture', p, text: `Capture point ${p.letter}`, need: 1, prog: 0, reward: 350 }; }
  } else if (role === 'fire') {
    const p = bestPoint('enemy');
    const big = me.prod.unit === 'missile';
    if (p) m = { kind: 'fire', p, text: `Fire mission: shell the enemy at ${p.letter}`, need: big ? 900 : me.prod.unit === 'radioop' ? 450 : 700, prog: 0, reward: 350, r: 480 };
  } else if (role === 'hunt') {
    m = { kind: 'hunt', cls: 'veh', text: 'Destroy an enemy vehicle', need: 1, prog: 0, reward: 400 };
  } else if (role === 'snipe') {
    m = { kind: 'hunt', cls: 'inf', text: 'Pick off 4 enemy soldiers', need: 4, prog: 0, reward: 300 };
  } else if (role === 'recon') {
    const p = bestPoint('enemy');
    if (p) m = { kind: 'recon', p, text: `Scout point ${p.letter} and stay alive`, need: 18, prog: 0, reward: 300, r: 520 };
  } else {
    const p = bestPoint('front');
    if (p) m = { kind: 'support', p, text: `Support the fight at ${p.letter}`, need: 40, prog: 0, reward: 300, r: 420 };
  }
  if (!m) return;
  m.t = 0; m.limit = 200;
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
  else if (m.kind === 'capture' && m.p.owner === 0 && !near(m.p.r + 300)) { failMission(`Others took ${m.p.letter} first`); return; }
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
// what left-click does depends on the squad
// ---------------------------------------------------------------------
function squadFireAt(x, y) {
  let any = false, msg = null;
  for (const u of G.me.units) for (const w of u.weapons) {
    if (!MANUAL_KINDS[w.def.kind]) continue;
    const d = dist(u.x, u.y, x, y);
    if (d > w.def.range) { msg = 'Out of range'; continue; }
    if (w.def.min && d < w.def.min) { msg = 'Too close for that gun'; continue; }
    w.manual = { x, y, t: G.time }; any = true;
  }
  return { any, msg };
}
function hasManualFire(prod) {
  return UNITS[prod.unit].weapons.some((w) => MANUAL_KINDS[WEAPONS[w].kind]);
}
const ROLE_HINTS = {
  rifleman: 'Right-click to move or attack. Right-click a capture point to spread out around it.',
  mgunner: 'Park to set up the MG (1 s), then it shreds infantry. Right-click to move.',
  medic: 'Medics heal wounded infantry nearby on their own. Stay just behind the fight.',
  officer: 'Units around you aim better and move faster. You capture points 3× faster.',
  scout: 'Stand still to hide. Everything you see, your artillery can hit.',
  sniper: 'Stand still to hide. Left-click an enemy to take the shot.',
  droneop: 'Q: launch a drone, steer it with the mouse, left-click to blow it up. It also explodes on contact.',
  antitank: 'Left-click a spot or enemy to fire a rocket. Hit tanks from behind for 1.5× damage.',
  engineer: 'Q: lay an AT mine. You repair vehicles nearby and throw satchels at armor.',
  radioop: 'Q: call a 9-shell barrage on anything your side can see, 950 m away.',
  jammer: 'Enemy drones near you crash. Stay close to friendly tanks.',
  grenadier: 'Left-click a spot to throw grenades. Great against troops in forests.',
  lighttank: 'Left-click to fire the cannon at a spot. Fast: hit them from the side.',
  heavytank: 'Left-click to fire the 125 mm at a spot. Keep your front toward the enemy.',
  radar: 'You see 950 m, reveal hidden units and expose enemy artillery when it fires.',
  aa: 'Your guns shoot down drones and missiles on their own. Escort the tanks.',
  howitzer: 'Park, then left-click anywhere 320–1650 m away to fire. Spotted targets are hit more accurately.',
  missile: 'Q or left-click a spot your side can see to launch. 70 s reload.',
  mlrs: 'Park, then left-click a spot 380–1450 m away for a 12-rocket salvo. 24 s reload.',
  supply: 'You repair vehicles and heal troops nearby. Park on a point you hold for +2 supply/s.',
};
