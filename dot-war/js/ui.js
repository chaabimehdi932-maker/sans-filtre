'use strict';
// =====================================================================
// Input, HUD, class picker, menus. You are one soldier; the war around
// you is fought by the two AI generals.
// =====================================================================

// ---------------------------------------------------------------------
// input
// ---------------------------------------------------------------------
function unitAt(wx, wy, preferTeam) {
  let best = null, bd = 1e9;
  for (const u of G.grid.query(wx, wy, 34)) {
    if (u.dead || u.cls === 'air' || !G.seen(u)) continue;
    const r = u.cls === 'veh' ? u.def.len * 0.55 : u.cls === 'bld' ? u.r : u.r + 7;
    const d = dist(wx, wy, u.x, u.y);
    if (d > r) continue;
    const s = d - (u.team === preferTeam ? 20 : 0);
    if (s < bd) { bd = s; best = u; }
  }
  return best;
}
const playing = () => G.mode === 'play' && G.me && G.me.alive && !G.paused;

function setupInput() {
  const cv = canvas, m = G.mouse;
  cv.addEventListener('contextmenu', (e) => e.preventDefault());
  cv.addEventListener('mousemove', (e) => {
    const r = cv.getBoundingClientRect();
    m.x = e.clientX - r.left; m.y = e.clientY - r.top; m.in = true; m.overHud = false;
    const w = screenToWorld(m.x, m.y); m.wx = w.x; m.wy = w.y;
    if (G.drag) { G.cam.x -= e.movementX / G.cam.zoom; G.cam.y -= e.movementY / G.cam.zoom; G.autoCam = false; }
  });
  cv.addEventListener('mouseleave', () => { m.in = false; m.down = false; m.right = false; });
  cv.addEventListener('mousedown', (e) => {
    Sound.init();
    if (G.mode === 'spectate') { if (e.button === 0 || e.button === 1) { G.drag = true; G.autoCam = false; syncSpectate(); } return; }
    if (!playing()) return;
    const me = G.me;
    if (e.button === 0) {
      if (me.drone && !me.drone.dead) { droneHit(me.drone, null); me.drone = null; return; }
      if (G.aim) { castAim(m.wx, m.wy); return; }
      m.down = true;
    } else if (e.button === 2) {
      if (G.aim) { G.aim = null; return; }
      if (me.vehicle) m.right = true; else throwGrenade();
    }
  });
  window.addEventListener('mouseup', (e) => {
    G.drag = false;
    if (e.button === 0) m.down = false;
    if (e.button === 2) m.right = false;
  });
  cv.addEventListener('wheel', (e) => {
    e.preventDefault();
    if (G.mode === 'boot') return;
    if (G.mode === 'play' && G.me) { G.me.zoomMul = clamp(G.me.zoomMul * Math.pow(1.0012, -e.deltaY), 0.55, 1.7); return; }
    const before = screenToWorld(m.x, m.y);
    G.cam.zoom = clamp(G.cam.zoom * Math.pow(1.0015, -e.deltaY), fitZoom() * 0.98, 2.4);
    const after = screenToWorld(m.x, m.y);
    G.cam.x += before.x - after.x; G.cam.y += before.y - after.y;
  }, { passive: false });

  window.addEventListener('keydown', (e) => {
    if (e.target && (e.target.tagName === 'INPUT' || e.target.tagName === 'SELECT')) return;
    keys[e.code] = true;
    if (G.mode === 'menu' || G.mode === 'boot') return;
    if (!$('picker').hidden) { if (e.code === 'Escape' || e.code === 'Tab') { e.preventDefault(); closePicker(); } return; }
    if (e.code === 'Escape') { if (G.aim) G.aim = null; else togglePause(); return; }
    if (e.code === 'KeyP') { togglePause(); return; }
    if (e.code === 'KeyM') { toggleSound(); return; }
    if (e.code === 'F1') { e.preventDefault(); showHelp(true); return; }
    if (G.mode !== 'play') { if (e.code === 'Space') { e.preventDefault(); G.autoCam = !G.autoCam; syncSpectate(); } return; }
    if (e.code === 'Tab') { e.preventDefault(); openPicker(G.me.alive ? 'switch' : 'dead'); return; }
    if (e.code === 'Space' || e.code.startsWith('Arrow')) e.preventDefault();
    if (!playing() || e.repeat) return;
    if (e.code === 'KeyE') { toggleVehicle(); return; }
    if (e.code === 'KeyR') { if (!G.me.vehicle) startReload(); return; }
    if (e.code === 'KeyG') { throwGrenade(); return; }
    if (e.code === 'KeyQ') { useAbility(); return; }
  });
  window.addEventListener('keyup', (e) => { keys[e.code] = false; });
  window.addEventListener('blur', () => { for (const k in keys) keys[k] = false; m.down = false; m.right = false; });

  // minimap: in the spectator view, click to look somewhere
  const mm = $('minimap');
  const mmPos = (e) => { const r = mm.getBoundingClientRect(); return { x: ((e.clientX - r.left) / r.width) * W, y: ((e.clientY - r.top) / r.height) * H }; };
  let mmDrag = false;
  mm.addEventListener('contextmenu', (e) => e.preventDefault());
  mm.addEventListener('mousedown', (e) => { if (G.mode !== 'spectate') return; const p = mmPos(e); mmDrag = true; G.cam.x = p.x; G.cam.y = p.y; G.autoCam = false; syncSpectate(); });
  window.addEventListener('mousemove', (e) => { if (mmDrag) { const p = mmPos(e); G.cam.x = p.x; G.cam.y = p.y; } });
  window.addEventListener('mouseup', () => { mmDrag = false; });

  setupTouch(cv);
}
function toggleVehicle() {
  const me = G.me;
  if (me.drone) return;
  if (me.vehicle) { exitVehicle(); return; }
  const v = nearestVehicle();
  if (v) enterVehicle(v);
  else notify('No vehicle close enough. Walk up to a jeep or a friendly vehicle.', 'info');
}

// touch: left thumb moves, right thumb aims and fires, buttons for the rest
function setupTouch(cv) {
  G.touch = { move: null };
  let stickId = null, stick0 = null, fireId = null;
  const pos = (t) => { const r = cv.getBoundingClientRect(); return { x: t.clientX - r.left, y: t.clientY - r.top }; };
  cv.addEventListener('touchstart', (e) => {
    Sound.init(); e.preventDefault();
    if (G.mode !== 'play') return;
    for (const t of e.changedTouches) {
      const p = pos(t);
      if (p.x < G.viewW * 0.42 && stickId === null) { stickId = t.identifier; stick0 = p; G.touch.move = { x: 0, y: 0 }; G.touch.stick = { x: p.x, y: p.y, dx: 0, dy: 0 }; }
      else if (fireId === null) {
        fireId = t.identifier;
        G.mouse.x = p.x; G.mouse.y = p.y; G.mouse.in = true;
        const w = screenToWorld(p.x, p.y); G.mouse.wx = w.x; G.mouse.wy = w.y;
        if (G.me.drone && !G.me.drone.dead) { droneHit(G.me.drone, null); G.me.drone = null; }
        else if (G.aim) castAim(w.x, w.y);
        else G.mouse.down = true;
      }
    }
  }, { passive: false });
  cv.addEventListener('touchmove', (e) => {
    e.preventDefault();
    for (const t of e.changedTouches) {
      const p = pos(t);
      if (t.identifier === stickId) {
        const dx = p.x - stick0.x, dy = p.y - stick0.y, l = Math.hypot(dx, dy), k = Math.min(1, l / 50) / (l || 1);
        G.touch.move = { x: dx * k, y: dy * k }; G.touch.stick = { x: stick0.x, y: stick0.y, dx: dx * k * 50, dy: dy * k * 50 };
      } else if (t.identifier === fireId) { G.mouse.x = p.x; G.mouse.y = p.y; }
    }
  }, { passive: false });
  const end = (e) => {
    for (const t of e.changedTouches) {
      if (t.identifier === stickId) { stickId = null; G.touch.move = null; G.touch.stick = null; }
      if (t.identifier === fireId) { fireId = null; G.mouse.down = false; }
    }
  };
  cv.addEventListener('touchend', end, { passive: false });
  cv.addEventListener('touchcancel', end, { passive: false });
  const bind = (id, fn) => { const b = $(id); if (b) b.addEventListener('touchstart', (e) => { e.preventDefault(); if (playing()) fn(); }, { passive: false }); };
  bind('tE', toggleVehicle); bind('tG', throwGrenade); bind('tQ', useAbility); bind('tR', () => { if (!G.me.vehicle) startReload(); });
  const tm = $('tM'); if (tm) { tm.addEventListener('touchstart', (e) => { e.preventDefault(); G.mouse.right = true; }, { passive: false }); tm.addEventListener('touchend', () => { G.mouse.right = false; }); }
}

function togglePause() {
  if (G.over || G.mode === 'menu') return;
  if (G.mode === 'play' && G.me && !G.me.alive && G.me.firstDeploy) return;
  G.paused = !G.paused;
  $('pause').hidden = !G.paused;
  G.mouse.down = false;
}
function toggleSound() {
  Sound.init(); Sound.setMuted(!Sound.muted);
  $('btnSound').textContent = Sound.muted ? 'Sound off' : 'Sound on';
  $('btnSound').setAttribute('aria-pressed', String(!Sound.muted));
  try { localStorage.setItem('dotwar.muted', Sound.muted ? '1' : '0'); } catch (e) {}
}
function setSpeed(s) { G.speed = s; for (const b of document.querySelectorAll('[data-speed]')) b.classList.toggle('on', +b.dataset.speed === s); }

// ---------------------------------------------------------------------
// HUD
// ---------------------------------------------------------------------
const ICONS = {};
function iconOf(key, make) { if (!ICONS[key]) ICONS[key] = make(); const c = ICONS[key].cloneNode(); c.getContext('2d').drawImage(ICONS[key], 0, 0); return c; }
const unitIc = (type, size) => iconOf('u' + type + size, () => unitIcon(type, size));
function fmtTime(t) { const m = Math.floor(t / 60), s = Math.floor(t % 60); return `${m}:${String(s).padStart(2, '0')}`; }
let hudKey = '';
function updateHudNow() { hudT = 0; }

function updateHud() {
  if (!G.teams.length) return;
  const T0 = G.teams[0], T1 = G.teams[1];
  $('tk0').textContent = Math.ceil(T0.tickets); $('tk1').textContent = Math.ceil(T1.tickets);
  $('tb0').style.transform = `scaleX(${T0.tickets / START_TICKETS})`; $('tb1').style.transform = `scaleX(${T1.tickets / START_TICKETS})`;
  $('clock').textContent = fmtTime(G.time);
  const pts = $('pts');
  if (pts.children.length !== G.points.length) { pts.innerHTML = ''; for (const p of G.points) { const s = document.createElement('span'); s.textContent = p.letter; pts.append(s); } }
  G.points.forEach((p, i) => { pts.children[i].className = 'pt ' + (p.owner === 0 ? 'b' : p.owner === 1 ? 'r' : 'n') + (p.contested ? ' c' : ''); });
  const diff = T0.held - T1.held;
  $('bleed0').textContent = diff < 0 && G.time > 60 ? `−${bleedRate(diff).toFixed(1)}/s` : '';
  $('bleed1').textContent = diff > 0 && G.time > 60 ? `−${bleedRate(diff).toFixed(1)}/s` : '';
  let n0 = 0, n1 = 0; for (const u of G.units) if (u.cls !== 'bld' && !u.empty) { if (u.team) n1++; else n0++; }
  $('armies').textContent = `${n0} vs ${n1}`;
  if (G.mode === 'spectate') { $('spectInfo').textContent = `Blue ${n0} units · Red ${n1} units`; return; }
  if (!G.me) return;
  const me = G.me;
  $('score').textContent = me.score; $('kills').textContent = me.kills; $('caps').textContent = me.captures; $('miss').textContent = me.missions;
  updateMission();
  updateSoldierPanel();
  if (!$('picker').hidden) refreshPicker();
}
function updateMission() {
  const m = G.me.mission, el = $('mission');
  if (!m || !G.me.alive) { el.hidden = true; return; }
  el.hidden = false;
  $('mText').textContent = m.text;
  $('mBar').style.transform = `scaleX(${clamp(m.prog / m.need, 0, 1)})`;
  $('mInfo').textContent = `+${m.reward} · ${m.kind === 'fire' ? `${Math.round(m.prog)} / ${m.need} damage` : m.kind === 'hunt' ? `${m.prog} / ${m.need}` : m.kind === 'capture' ? 'stand on the point' : `${Math.floor(m.prog)} / ${m.need} s`} · ${Math.max(0, Math.ceil(m.limit - m.t))} s left`;
}
const VEHICLE_HINT = {
  jeep: 'WASD to drive, run over enemies. Left click: mounted machine gun. E to get out.',
  lighttank: 'WASD to drive, the turret follows the mouse. Left click: cannon, right click: machine gun.',
  heavytank: 'WASD to drive, the turret follows the mouse. Left click: 125 mm gun, right click: machine gun. Keep your front to the enemy.',
  aa: 'WASD to drive. Left click: twin autocannons, they shoot down drones and missiles too.',
  howitzer: 'Stop, then left click anywhere 320–1650 m away to fire the 155 mm gun.',
  mlrs: 'Stop, then left click a spot 380–1450 m away for a 12-rocket salvo.',
  missile: 'Left click a spot your side can see to launch the missile.',
  radar: 'You see 950 m and reveal hidden enemies around you.',
  supply: 'You repair vehicles and heal troops around you.',
};
function buildSoldierPanel() {
  const me = G.me, box = $('squad');
  if (!me.alive) {
    box.innerHTML = `<div class="sq-dead"><b>You are down</b><span>${me.respawnT > 0 ? `Back in the fight in ${Math.ceil(me.respawnT)} s` : 'Ready to deploy'}</span><button type="button" class="btn primary" data-act="pick">Choose a class <kbd>Tab</kbd></button></div>`;
    return;
  }
  const c = me.cls, v = me.vehicle;
  let h = `<div class="sq-top"><span class="sq-ic"></span><div class="sq-title"><b>${c.name}</b><span id="hpText"></span></div><button type="button" class="cmd" data-act="pick">Change class <kbd>Tab</kbd></button></div>`;
  h += `<div class="hp"><i id="hpBar"></i></div>`;
  if (v) {
    h += `<div class="veh"><span class="vic"></span><div><b>${v.def.name}</b> <span id="vhpText" class="muted"></span><div class="hp"><i id="vhpBar"></i></div></div><button type="button" class="cmd" data-act="exit">Get out <kbd>E</kbd></button></div>`;
    h += `<div class="sq-row" id="vguns"></div>`;
    h += `<div class="sq-hint">${VEHICLE_HINT[v.type] || 'WASD to drive.'}</div>`;
  } else {
    h += `<div class="sq-row"><div class="ammo"><span>${me.soldier.gun.def.name}</span><b id="ammo"></b><i><b id="rlBar"></b></i></div><div class="nades" id="nades" title="Grenades (right click or G)"></div>`;
    if (c.id !== 'rifleman' && c.id !== 'mg' && c.id !== 'sniper' && c.id !== 'at') h += `<button type="button" class="abbtn" data-act="ab">${{ medic: 'Medkit', engineer: 'AT mine', radio: 'Artillery barrage', drone: 'FPV drone' }[c.id]} <kbd>Q</kbd> <span id="abState"></span></button>`;
    h += `</div><div class="sq-status" id="sqStatus"></div><div class="sq-hint">${c.hint} WASD to move, Shift to sprint, R to reload, E to get in vehicles.</div>`;
  }
  box.innerHTML = h;
  box.querySelector('.sq-ic').append(unitIc(c.unit, 46));
  if (v) box.querySelector('.vic').append(unitIc(v.type, 40));
}
function updateSoldierPanel() {
  const me = G.me;
  const key = me.alive ? `${me.soldier.id}:${me.vehicle ? me.vehicle.id : 0}` : 'dead:' + Math.ceil(me.respawnT);
  if (key !== hudKey) { hudKey = key; buildSoldierPanel(); }
  if (!me.alive) return;
  const s = me.soldier, v = me.vehicle;
  $('hpText').textContent = `${Math.ceil(s.hp)} / ${s.maxHp} health`;
  const hb = $('hpBar'); hb.style.transform = `scaleX(${s.hp / s.maxHp})`; hb.className = s.hp < s.maxHp * 0.35 ? 'low' : '';
  if (v) {
    $('vhpText').textContent = `${Math.ceil(v.hp)} / ${v.maxHp}`;
    const vb = $('vhpBar'); vb.style.transform = `scaleX(${v.hp / v.maxHp})`; vb.className = v.hp < v.maxHp * 0.35 ? 'low' : '';
    let g = '';
    if (v.type === 'missile') g = `<span class="gun">Missile ${v.abilityCd > 0 ? `<span class="cd">${Math.ceil(v.abilityCd)} s</span>` : '<span class="ok">ready</span>'}</span>`;
    v.weapons.forEach((w, i) => {
      const ready = w.cd <= 0 && w.salvo <= 0;
      g += `<span class="gun">${i ? 'Right click' : 'Left click'}: ${wpnName(w.id)} ${ready ? '<span class="ok">ready</span>' : `<span class="cd">${w.salvo > 0 ? 'firing' : Math.max(0.1, w.cd).toFixed(1) + ' s'}</span>`}</span>`;
    });
    $('vguns').innerHTML = g;
    return;
  }
  const gun = s.gun;
  $('ammo').textContent = gun.reloadT > 0 ? 'reloading' : `${gun.mag} / ${gun.def.mag}`;
  $('rlBar').style.transform = `scaleX(${gun.reloadT > 0 ? 1 - gun.reloadT / gun.def.reload : gun.mag / gun.def.mag})`;
  $('nades').innerHTML = Array.from({ length: me.cls.nades }, (_, i) => `<i class="${i < s.nades ? 'on' : ''}"></i>`).join('');
  const ab = $('abState');
  if (ab) {
    const cd = me.cls.id === 'medic' ? me.abilityCd : s.abilityCd;
    ab.innerHTML = me.drone && !me.drone.dead ? `<span class="ok">flying · ${Math.max(0, Math.ceil(16 - me.drone.t))} s</span>` : cd > 0 ? `<span class="cd">${Math.ceil(cd)} s</span>` : '<span class="ok">ready</span>';
  }
  let st = [];
  if (s.sup > 50) st.push('<b class="warn">Pinned down</b>');
  if (isConcealed(s)) st.push('Hidden');
  if (G.time - s.lastHit > 6 && s.hp < s.maxHp) st.push('Healing');
  const near = nearestVehicle();
  if (near) st.push(`<b class="ok">E: ${near.empty ? 'drive' : 'take over'} the ${near.def.name.toLowerCase()}</b>`);
  $('sqStatus').innerHTML = st.join(' · ');
}
function wpnName(w) { return { rifle: 'Rifle', carbine: 'Carbine', pistol: 'Pistol', smg: 'SMG', mg: 'Machine gun', sniper: 'Sniper rifle', atrocket: 'AT rocket', satchel: 'Satchel', grenade: 'Grenades', cannonL: '90 mm cannon', cannonH: '125 mm cannon', coax: 'machine gun', aa: '35 mm autocannons', howitzer: '155 mm gun', mlrs: '122 mm rockets', tcannon: 'Cannon', tmg: 'MG', jeepmg: 'machine gun' }[w] || w; }

function setupHud() {
  for (const b of document.querySelectorAll('[data-speed]')) b.addEventListener('click', () => setSpeed(+b.dataset.speed));
  $('btnPause').addEventListener('click', togglePause);
  $('btnSound').addEventListener('click', toggleSound);
  $('btnHelp').addEventListener('click', () => showHelp(true));
  $('resume').addEventListener('click', togglePause);
  $('quit').addEventListener('click', () => { G.paused = false; $('pause').hidden = true; toMenu(); });
  $('squad').addEventListener('click', (e) => {
    const b = e.target.closest('button'); if (!b) return;
    const a = b.dataset.act, me = G.me;
    if (a === 'pick') openPicker(me.alive ? 'switch' : 'dead');
    else if (!me.alive) return;
    else if (a === 'ab') useAbility();
    else if (a === 'exit') exitVehicle();
  });
  for (const el of document.querySelectorAll('.hud-panel')) {
    el.addEventListener('mouseenter', () => { G.mouse.overHud = true; G.mouse.down = false; });
    el.addEventListener('mouseleave', () => { G.mouse.overHud = false; });
  }
}

// ---------------------------------------------------------------------
// class picker
// ---------------------------------------------------------------------
const PICK = { cls: CLASSES[0], spawn: 'hq', reason: 'start' };
function buildPicker() {
  const box = $('pkInf');
  for (const c of CLASSES) {
    const b = document.createElement('button');
    b.type = 'button'; b.className = 'pk'; b.dataset.id = c.id;
    b.append(unitIcon(c.unit, 44));
    const t = document.createElement('span');
    t.innerHTML = `<b>${c.name}</b><small>${PLAYER_GUNS[c.gun].name} · ${c.hp} health</small>`;
    b.append(t);
    b.addEventListener('click', () => { PICK.cls = c; Sound.play('ui', 0.25); refreshPicker(true); });
    b.addEventListener('dblclick', () => { PICK.cls = c; deployPicked(); });
    box.append(b);
  }
  $('pkGo').addEventListener('click', deployPicked);
  $('pkBack').addEventListener('click', closePicker);
}
function openPicker(reason) {
  if (G.mode !== 'play' || G.over) return;
  PICK.reason = reason;
  G.mouse.down = false;
  $('picker').hidden = false;
  $('pkTitle').textContent = reason === 'dead' ? 'You were killed' : reason === 'switch' ? 'Change class' : 'Choose your soldier';
  $('pkSub').textContent = reason === 'start' ? 'Two AI armies are about to fight a full-scale war. You are one soldier on the blue side: fight on foot, or grab a jeep or a tank and drive it into the battle.'
    : reason === 'dead' ? 'Pick how you want to go back in.'
    : 'Your soldier redeploys as the new class.';
  $('pkBack').hidden = reason !== 'switch';
  PICK.spawn = null;
  refreshPicker(true);
}
function closePicker() {
  if (PICK.reason !== 'switch' && !(G.me && G.me.alive)) return;
  $('picker').hidden = true;
}
function refreshPicker(full) {
  const me = G.me; if (!me) return;
  for (const b of document.querySelectorAll('.pk')) b.classList.toggle('on', b.dataset.id === PICK.cls.id);
  const c = PICK.cls, g = PLAYER_GUNS[c.gun];
  if (full) $('pkInfo').innerHTML = `<b>${c.name}</b><p>${c.desc}</p><p class="muted">${c.hint}</p><div class="tip-vs"><span>${g.name}: ${g.mag}-round magazine, ${g.range} m</span><span>${c.hp} health · ${c.nades} grenade${c.nades > 1 ? 's' : ''}</span></div>`;
  const sps = spawnPoints();
  if (!sps.some((s) => s.id === PICK.spawn)) PICK.spawn = sps.length > 1 ? sps[sps.length - 1].id : 'hq';
  const spBox = $('pkSpawn');
  const spKey = sps.map((s) => s.id).join(',') + PICK.spawn;
  if (full || spBox.dataset.key !== spKey) {
    spBox.dataset.key = spKey; spBox.innerHTML = '';
    for (const s of sps) {
      const b = document.createElement('button'); b.type = 'button'; b.className = 'chip' + (s.id === PICK.spawn ? ' on' : '');
      b.textContent = s.id === 'hq' ? 'HQ (jeeps and tanks)' : `Point ${s.label}`;
      b.onclick = () => { PICK.spawn = s.id; refreshPicker(true); };
      spBox.append(b);
    }
    $('pkSpawnNote').textContent = 'Jeeps wait at the HQ. You can also jump into any friendly tank or truck: walk up to it and press E.';
  }
  const go = $('pkGo');
  const wait = me.alive ? 0 : me.respawnT;
  go.disabled = wait > 0;
  go.textContent = wait > 0 ? `Deploy in ${Math.ceil(wait)} s` : `Deploy as ${c.name.toLowerCase()}`;
}
function deployPicked() {
  const me = G.me;
  if (!me.alive && me.respawnT > 0) return;
  deployMe(PICK.cls, PICK.spawn);
  try { localStorage.setItem('dotwar.class', PICK.cls.id); } catch (e) {}
  $('picker').hidden = true;
  G.paused = false;
  hudKey = '';
}

// ---------------------------------------------------------------------
// menus & flow
// ---------------------------------------------------------------------
function showHelp(v) { $('help').hidden = !v; if (v && G.mode === 'play' && !G.paused) { G.paused = true; G.helpPaused = true; } if (!v && G.helpPaused) { G.paused = false; G.helpPaused = false; } }
function setMode(m) { document.body.dataset.mode = m; }
function loading(text, fn) {
  const l = $('loading'); l.hidden = false; $('loadingText').textContent = text;
  setTimeout(() => { try { fn(); } finally { l.hidden = true; } }, 40);
}
function startGame() {
  Sound.init();
  $('menu').hidden = true; $('end').hidden = true;
  loading('Generating battlefield…', () => {
    newGame({ mode: 'play', seed: G.settings.seed, diff: G.settings.diff, tod: G.settings.tod });
    setMode('play');
    G.paused = true;
    hudKey = '';
    openPicker('start');
  });
}
function startSpectate() {
  Sound.init();
  $('menu').hidden = true; $('end').hidden = true;
  loading('Generating battlefield…', () => {
    newGame({ mode: 'spectate', seed: G.settings.seed, tod: G.settings.tod, blueDiff: 'elite', redDiff: 'elite' });
    G.autoCam = true; syncSpectate();
    setMode('spectate');
  });
}
function syncSpectate() { const b = $('btnCam'); if (b) { b.textContent = G.autoCam ? 'Auto camera on' : 'Auto camera off'; b.classList.toggle('on', !!G.autoCam); } }
function toMenu() {
  $('end').hidden = true; $('picker').hidden = true;
  loading('Loading…', () => {
    newGame({ mode: 'menu', seed: (Math.random() * 1e9) | 0, tod: G.settings.tod, blueDiff: 'elite', redDiff: 'elite' });
    G.speed = 1; setMode('menu'); $('menu').hidden = false;
  });
}
function endGame(winner, why) {
  if (G.over) return;
  G.over = true;
  if (G.mode === 'menu') { setTimeout(toMenu, 4000); return; }
  const T = G.teams;
  const won = G.playerTeam < 0 ? null : winner === G.playerTeam;
  setTimeout(() => {
    $('picker').hidden = true;
    const e = $('end');
    $('endTitle').textContent = won === null ? `${TEAM[winner].name} wins` : won ? 'Victory' : 'Defeat';
    $('endTitle').className = won === false ? 'lose' : 'win';
    $('endWhy').textContent = why === 'hq' ? (winner === 0 ? 'The red headquarters is rubble.' : 'The blue headquarters was destroyed.') : (winner === 0 ? 'The red army ran out of tickets.' : 'The blue army ran out of tickets.');
    const row = (k, a, b) => `<tr><th scope="row">${k}</th><td>${a}</td><td>${b}</td></tr>`;
    $('endStats').innerHTML = `<thead><tr><th></th><th class="team-0">Blue</th><th class="team-1">Red</th></tr></thead><tbody>` +
      row('Units lost', T[0].stats.lost, T[1].stats.lost) + row('Kills', T[0].stats.kills, T[1].stats.kills) + row('Points held', T[0].held, T[1].held) + row('Tickets left', Math.ceil(T[0].tickets), Math.ceil(T[1].tickets)) + `</tbody>`;
    const me = G.me;
    $('endMe').innerHTML = me ? `<b>Your war</b><span>${me.score} points</span><span>${me.kills} kills (${me.vkills} vehicles)</span><span>${me.captures} captures</span><span>${me.missions} missions</span><span>${me.lost} deaths</span>` : '';
    $('endMe').hidden = !me;
    $('endTime').textContent = `Battle length ${fmtTime(G.time)} · enemy general: ${DIFFS[G.settings.diff].name}`;
    e.hidden = false;
  }, 2500);
}

function setupMenu() {
  const chips = (name, key) => {
    for (const b of document.querySelectorAll(`[data-${name}]`)) {
      b.addEventListener('click', () => {
        G.settings[key] = b.dataset[name];
        for (const o of document.querySelectorAll(`[data-${name}]`)) { o.classList.toggle('on', o === b); o.setAttribute('aria-checked', String(o === b)); }
        try { localStorage.setItem('dotwar.' + key, b.dataset[name]); } catch (e) {}
        Sound.init(); Sound.play('ui', 0.3);
        if (key === 'tod' && G.mode === 'menu') G.night = { day: 0, dusk: 0.4, night: 0.72 }[G.settings.tod];
      });
      if (G.settings[key] === b.dataset[name]) { b.classList.add('on'); b.setAttribute('aria-checked', 'true'); }
    }
  };
  chips('diff', 'diff'); chips('tod', 'tod');
  $('btnPlay').addEventListener('click', startGame);
  $('btnWatch').addEventListener('click', startSpectate);
  $('btnHow').addEventListener('click', () => showHelp(true));
  $('helpClose').addEventListener('click', () => showHelp(false));
  $('again').addEventListener('click', () => { G.settings.seed = (Math.random() * 1e9) | 0; startGame(); });
  $('toMenu').addEventListener('click', toMenu);
  $('btnCam').addEventListener('click', () => { G.autoCam = !G.autoCam; syncSpectate(); });
  $('btnExit').addEventListener('click', toMenu);
  const roster = $('roster');
  for (const c of CLASSES) {
    const li = document.createElement('li');
    li.append(unitIcon(c.unit, 40));
    const d = document.createElement('div');
    d.innerHTML = `<b>${c.name}</b> <span class="muted">${PLAYER_GUNS[c.gun].name}</span><br>${c.desc}`;
    li.append(d); roster.append(li);
  }
  buildPicker();
}

function boot() {
  try {
    const m = localStorage.getItem('dotwar.muted'); if (m === '1') Sound.muted = true;
    const d = localStorage.getItem('dotwar.diff'); if (d && DIFFS[d]) G.settings.diff = d;
    const t = localStorage.getItem('dotwar.tod'); if (t) G.settings.tod = t;
    const c = localStorage.getItem('dotwar.class'); if (c && CLASS_BY_ID[c]) PICK.cls = CLASS_BY_ID[c];
  } catch (e) {}
  $('btnSound').textContent = Sound.muted ? 'Sound off' : 'Sound on';
  G.settings.seed = (Math.random() * 1e9) | 0;
  try { G.reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches; } catch (e) {}
  makeFxSprites();
  navInit();
  setupCanvas();
  setupInput();
  setupHud();
  setupMenu();
  newGame({ mode: 'menu', seed: G.settings.seed + 1, tod: G.settings.tod, blueDiff: 'elite', redDiff: 'elite' });
  setMode('menu');
  $('loading').hidden = true;
  requestAnimationFrame((t) => { lastTs = t; requestAnimationFrame(frame); });
}
window.addEventListener('load', boot);
