'use strict';
// =====================================================================
// Input, HUD, squad picker, menus. You command one squad; the rest of
// the war is fought by the two AI generals.
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
const isArtillery = (prod) => prod && ['howitzer', 'mlrs'].includes(prod.unit);

function setupInput() {
  const cv = canvas;
  cv.addEventListener('contextmenu', (e) => e.preventDefault());
  cv.addEventListener('mousemove', (e) => {
    const r = cv.getBoundingClientRect();
    const m = G.mouse; m.x = e.clientX - r.left; m.y = e.clientY - r.top; m.in = true; m.overHud = false;
    const w = screenToWorld(m.x, m.y); m.wx = w.x; m.wy = w.y;
    const d = G.drag;
    if (d) {
      if (!d.moved && Math.abs(m.x - d.sx) + Math.abs(m.y - d.sy) > 6) d.moved = true;
      if (d.moved || d.pan) { G.cam.x -= e.movementX / G.cam.zoom; G.cam.y -= e.movementY / G.cam.zoom; if (G.me) G.me.follow = false; G.autoCam = false; }
    }
    if (G.mode !== 'boot' && G.grid) G.hover = unitAt(m.wx, m.wy, G.playerTeam);
    const enemyHover = G.hover && G.hover.team !== G.playerTeam && G.playerTeam >= 0;
    cv.style.cursor = G.drag && G.drag.moved ? 'grabbing' : G.aim || G.amove || enemyHover || (G.me && G.me.alive && hasManualFire(G.me.prod)) ? 'crosshair' : 'default';
  });
  cv.addEventListener('mouseleave', () => { G.mouse.in = false; });
  cv.addEventListener('mousedown', (e) => {
    Sound.init();
    if (G.mode !== 'play' && G.mode !== 'spectate') return;
    const m = G.mouse; m.shift = e.shiftKey;
    if (e.button === 1) { G.drag = { pan: true, sx: m.x, sy: m.y }; e.preventDefault(); return; }
    if (e.button === 0) {
      // flying a drone: click detonates it wherever it is
      if (G.me && G.me.drone && !G.me.drone.dead) { droneHit(G.me.drone, null); G.me.drone = null; return; }
      G.drag = { sx: m.x, sy: m.y, moved: false };
    }
    if (e.button === 2 && G.mode === 'play') {
      if (G.aim) { G.aim = null; return; }
      if (G.amove) { G.amove = false; return; }
      squadCommand(m.wx, m.wy, e.ctrlKey);
    }
  });
  window.addEventListener('mouseup', (e) => {
    const d = G.drag; if (!d) return;
    G.drag = null;
    if (d.pan || d.moved || e.button !== 0) return;
    if (G.mode === 'play') leftClick(G.mouse.wx, G.mouse.wy);
  });
  cv.addEventListener('wheel', (e) => {
    e.preventDefault();
    if (G.mode === 'boot') return;
    const before = screenToWorld(G.mouse.x, G.mouse.y);
    G.cam.zoom = clamp(G.cam.zoom * Math.pow(1.0015, -e.deltaY), fitZoom() * 0.98, 2.4);
    const after = screenToWorld(G.mouse.x, G.mouse.y);
    if (!(G.me && G.me.follow && G.me.alive)) { G.cam.x += before.x - after.x; G.cam.y += before.y - after.y; }
  }, { passive: false });

  window.addEventListener('keydown', (e) => {
    if (e.target && (e.target.tagName === 'INPUT' || e.target.tagName === 'SELECT')) return;
    keys[e.code] = true;
    if (G.mode === 'menu' || G.mode === 'boot') return;
    if (!$('picker').hidden) { if (e.code === 'Escape' || e.code === 'Tab') { e.preventDefault(); closePicker(); } return; }
    if (e.code === 'Escape') { if (G.aim || G.amove) { G.aim = null; G.amove = false; } else if (G.inspect) G.inspect = null; else togglePause(); return; }
    if (e.code === 'KeyP') { togglePause(); return; }
    if (e.code === 'KeyM') { toggleSound(); return; }
    if (e.code === 'F1') { e.preventDefault(); showHelp(true); return; }
    if (G.mode !== 'play') { if (e.code === 'Space') { e.preventDefault(); G.autoCam = !G.autoCam; syncSpectate(); } return; }
    const me = G.me;
    if (e.code === 'Tab') { e.preventDefault(); openPicker(me.alive ? 'switch' : 'dead'); return; }
    if (e.code === 'Space') { e.preventDefault(); me.follow = true; return; }
    if (e.code === 'KeyT' && G.inspect) { takeCommand(G.inspect); G.inspect = null; return; }
    if (!me.alive) return;
    if (e.code === 'KeyA') { G.amove = true; return; }
    if (e.code === 'KeyS') { issueStop(me.units); for (const u of me.units) for (const w of u.weapons) w.manual = null; return; }
    if (e.code === 'KeyH') { issueHold(me.units); return; }
    if (e.code === 'KeyQ') { squadAbility(); return; }
    if (e.code === 'KeyE') { toggleAuto(); return; }
  });
  window.addEventListener('keyup', (e) => { keys[e.code] = false; });
  window.addEventListener('blur', () => { for (const k in keys) keys[k] = false; });

  // minimap: click to look, right-click to send your squad
  const mm = $('minimap');
  const mmPos = (e) => { const r = mm.getBoundingClientRect(); return { x: ((e.clientX - r.left) / r.width) * W, y: ((e.clientY - r.top) / r.height) * H }; };
  let mmDrag = false;
  mm.addEventListener('contextmenu', (e) => e.preventDefault());
  mm.addEventListener('mousedown', (e) => {
    Sound.init();
    const p = mmPos(e);
    if (e.button === 2 && G.mode === 'play') { squadCommand(p.x, p.y, e.ctrlKey); return; }
    mmDrag = true; G.cam.x = p.x; G.cam.y = p.y; G.autoCam = false; if (G.me) G.me.follow = false; syncSpectate();
  });
  window.addEventListener('mousemove', (e) => { if (mmDrag) { const p = mmPos(e); G.cam.x = p.x; G.cam.y = p.y; } });
  window.addEventListener('mouseup', () => { mmDrag = false; });

  setupTouch(cv);
}

// touch: tap an enemy to attack, tap the ground to move, hold to fire there, drag to look around
function setupTouch(cv) {
  let t0 = null, pinch = null, moved = false, longT = null;
  cv.addEventListener('touchstart', (e) => {
    Sound.init(); e.preventDefault();
    if (e.touches.length === 2) {
      clearTimeout(longT);
      const [a, b] = e.touches; pinch = { d: Math.hypot(a.clientX - b.clientX, a.clientY - b.clientY), z: G.cam.zoom, cx: (a.clientX + b.clientX) / 2, cy: (a.clientY + b.clientY) / 2 };
      t0 = null; return;
    }
    const t = e.touches[0]; const r = cv.getBoundingClientRect();
    t0 = { x: t.clientX - r.left, y: t.clientY - r.top, lx: t.clientX, ly: t.clientY, long: false }; moved = false;
    G.mouse.x = t0.x; G.mouse.y = t0.y; const w = screenToWorld(t0.x, t0.y); G.mouse.wx = w.x; G.mouse.wy = w.y;
    clearTimeout(longT);
    if (G.mode === 'play') longT = setTimeout(() => { if (t0 && !moved) { t0.long = true; leftClick(G.mouse.wx, G.mouse.wy, true); } }, 420);
  }, { passive: false });
  cv.addEventListener('touchmove', (e) => {
    e.preventDefault();
    if (pinch && e.touches.length === 2) {
      const [a, b] = e.touches; const d = Math.hypot(a.clientX - b.clientX, a.clientY - b.clientY);
      const cx = (a.clientX + b.clientX) / 2, cy = (a.clientY + b.clientY) / 2;
      G.cam.zoom = clamp(pinch.z * d / pinch.d, fitZoom() * 0.98, 2.4);
      G.cam.x -= (cx - pinch.cx) / G.cam.zoom; G.cam.y -= (cy - pinch.cy) / G.cam.zoom; pinch.cx = cx; pinch.cy = cy;
      if (G.me) G.me.follow = false;
      return;
    }
    if (!t0) return;
    const t = e.touches[0]; const r = cv.getBoundingClientRect();
    const x = t.clientX - r.left, y = t.clientY - r.top;
    G.mouse.x = x; G.mouse.y = y;
    if (Math.abs(x - t0.x) + Math.abs(y - t0.y) > 10) { moved = true; clearTimeout(longT); G.autoCam = false; }
    if (moved && !(G.me && G.me.drone)) { G.cam.x -= (t.clientX - t0.lx) / G.cam.zoom; G.cam.y -= (t.clientY - t0.ly) / G.cam.zoom; if (G.me) G.me.follow = false; }
    t0.lx = t.clientX; t0.ly = t.clientY;
  }, { passive: false });
  cv.addEventListener('touchend', (e) => {
    e.preventDefault(); clearTimeout(longT);
    if (pinch) { if (e.touches.length < 2) pinch = null; return; }
    if (!t0) return;
    if (!moved && !t0.long && G.mode === 'play') {
      const { wx, wy } = G.mouse;
      if (G.me.drone && !G.me.drone.dead) { droneHit(G.me.drone, null); G.me.drone = null; }
      else if (G.aim) castAim(wx, wy);
      else {
        const u = unitAt(wx, wy, 1);
        if (u && u.team === 1) leftClick(wx, wy);
        else if (u && u.team === 0 && !u.player && u.group) G.inspect = u.group;
        else squadCommand(wx, wy, false);
      }
    }
    t0 = null;
  }, { passive: false });
}

// left-click: what it does depends on your squad
function leftClick(wx, wy, forceFire) {
  const me = G.me;
  if (G.aim) { castAim(wx, wy); return; }
  if (G.amove) { squadCommand(wx, wy, true); G.amove = false; return; }
  const u = unitAt(wx, wy, 1);
  if (u && u.team === 0 && !u.player && u.group && !forceFire) { G.inspect = u.group; Sound.play('ui', 0.25); return; }
  if (u && u.player) { G.inspect = null; return; }
  if (!me.alive) return;
  const prod = me.prod;
  if (prod.unit === 'missile') { G.aim = { ab: 'missile' }; castAim(wx, wy); return; }
  if (hasManualFire(prod) && (isArtillery(prod) || !u || u.team !== 1 || forceFire)) {
    const r = squadFireAt(u && u.team === 1 ? u.x : wx, u && u.team === 1 ? u.y : wy);
    if (r.any) { G.markers.push({ x: wx, y: wy, t: 0, color: 'rgba(255,200,80,A)' }); Sound.play('ui', 0.25); }
    else if (r.msg) { notify(r.msg, 'info'); Sound.play('error', 0.4); }
    return;
  }
  if (u && u.team === 1) {
    issueAttack(me.units, u);
    G.markers.push({ x: u.x, y: u.y, t: 0, color: 'rgba(255,90,60,A)' });
    Sound.play('ui', 0.25);
    return;
  }
  G.inspect = null;
}
// right-click: move or attack
function squadCommand(wx, wy, amove) {
  const me = G.me; if (!me || !me.alive) return;
  const target = unitAt(wx, wy, 1);
  if (target && target.team === 1) {
    issueAttack(me.units, target);
    G.markers.push({ x: target.x, y: target.y, t: 0, color: 'rgba(255,90,60,A)' });
  } else {
    const p = G.points.find((p) => dist(p.x, p.y, wx, wy) < p.r);
    issueMove(me.units, wx, wy, amove, { spacing: p ? 1.9 : 1 });
    G.markers.push({ x: wx, y: wy, t: 0, color: amove ? 'rgba(255,150,80,A)' : 'rgba(247,213,74,A)' });
  }
  for (const u of me.units) for (const w of u.weapons) w.manual = null;
  me.follow = true;
  Sound.play('ui', 0.25);
}
function squadAbility() {
  const me = G.me; if (!me.alive) return;
  const ab = me.units[0].def.ability;
  if (!ab) { notify(`${me.prod.name}: no special ability`, 'info'); return; }
  if (ab === 'drone') {
    const op = me.units.find((u) => !u.dead && !u.drone && u.abilityCd <= 0);
    if (!op) { const w = Math.min(...me.units.map((u) => u.abilityCd)); notify(me.drone ? 'Your drone is already up' : `Next drone in ${Math.ceil(w)} s`, 'info'); Sound.play('error', 0.4); return; }
    launchDrone(op, null);
    notify('Drone up: steer with the mouse, click to detonate', 'info');
    return;
  }
  G.aim = { ab };
}
function castAim(wx, wy) {
  const ab = G.aim.ab;
  const casters = G.me.units.filter((u) => !u.dead && u.def.ability === ab);
  G.aim = null;
  if (!casters.length) return;
  casters.sort((a, b) => (a.abilityCd > 0) - (b.abilityCd > 0) || dist(a.x, a.y, wx, wy) - dist(b.x, b.y, wx, wy));
  const u = casters[0];
  if ((ab === 'barrage' || ab === 'missile') && !cellVisible(0, wx, wy)) { notify('Nobody on your side can see that spot', 'info'); Sound.play('error', 0.4); return; }
  if (u.abilityCd > 0) { notify(`${ABILITIES[ab].name} ready in ${Math.ceil(u.abilityCd)} s`, 'info'); Sound.play('error', 0.4); return; }
  if (ab !== 'mine' && dist(u.x, u.y, wx, wy) > ABILITIES[ab].range) { notify(`Out of range (${ABILITIES[ab].range} m)`, 'info'); Sound.play('error', 0.4); return; }
  if (ab === 'mine') { u.order = { type: 'ability', x: wx, y: wy }; u.path = null; u.repathT = 0; }
  else castAbility(u, wx, wy, null);
  G.markers.push({ x: wx, y: wy, t: 0, color: 'rgba(120,200,255,A)' });
  Sound.play('ui', 0.3);
}
function toggleAuto() {
  const me = G.me; if (!me.alive) return;
  const has = me.units[0].def.ability || isArtillery(me.prod);
  if (!has) return;
  const v = !me.units[0].auto;
  for (const u of me.units) { u.auto = v; u.autoArty = v; }
  notify(v ? 'Auto-fire on: your squad picks its own targets' : 'Auto-fire off: you call every shot', 'info');
  sqKey = '';
}
function togglePause() {
  if (G.over || G.mode === 'menu') return;
  if (G.mode === 'play' && G.me && !G.me.alive && G.me.firstDeploy) return;
  G.paused = !G.paused;
  $('pause').hidden = !G.paused;
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
function iconCache(p, size = 34) { const k = p.id + size; if (!ICONS[k]) ICONS[k] = productIcon(p, size, 0); const c = ICONS[k].cloneNode(); c.getContext('2d').drawImage(ICONS[k], 0, 0); return c; }
function wpnName(w) { return { rifle: 'Rifle', carbine: 'Carbine', pistol: 'Pistol', smg: 'SMG', mg: 'Machine gun', sniper: 'Sniper rifle', atrocket: 'AT rocket', satchel: 'Satchel', grenade: 'Grenades', cannonL: '90 mm cannon', cannonH: '125 mm cannon', coax: 'Coax MG', aa: '35 mm AA', howitzer: '155 mm gun', mlrs: '122 mm rockets', tcannon: 'Cannon', tmg: 'MG' }[w] || w; }
function fmtTime(t) { const m = Math.floor(t / 60), s = Math.floor(t % 60); return `${m}:${String(s).padStart(2, '0')}`; }
let sqKey = '';
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
  let n0 = 0, n1 = 0; for (const u of G.units) if (u.cls !== 'bld') { if (u.team) n1++; else n0++; }
  $('armies').textContent = `${n0} vs ${n1}`;
  if (G.mode === 'spectate') { $('spectInfo').textContent = `Blue ${n0} units · Red ${n1} units`; return; }
  if (!G.me) return;
  const me = G.me;
  $('score').textContent = me.score; $('kills').textContent = me.kills; $('caps').textContent = me.captures; $('miss').textContent = me.missions;
  updateMission();
  updateSquadPanel();
  updateInspect();
  if (!$('picker').hidden) refreshPicker();
}
function updateMission() {
  const m = G.me.mission, el = $('mission');
  if (!m || !G.me.alive) { el.hidden = true; return; }
  el.hidden = false;
  $('mText').textContent = m.text;
  const k = clamp(m.prog / m.need, 0, 1);
  $('mBar').style.transform = `scaleX(${k})`;
  $('mInfo').textContent = `+${m.reward} · ${m.kind === 'fire' ? `${Math.round(m.prog)} / ${m.need} damage` : m.kind === 'hunt' ? `${m.prog} / ${m.need}` : m.kind === 'capture' ? 'stand on the point' : `${Math.floor(m.prog)} / ${m.need} s`} · ${Math.max(0, Math.ceil(m.limit - m.t))} s left`;
}
function updateInspect() {
  const g = G.inspect, el = $('inspect');
  if (!g || !g.units.some((u) => !u.dead)) { G.inspect = null; el.hidden = true; return; }
  el.hidden = false;
  const live = g.units.filter((u) => !u.dead).length;
  const key = g.id + ':' + live;
  if (el.dataset.key === key) return;
  el.dataset.key = key;
  el.innerHTML = '';
  el.append(iconCache(g.prod, 30));
  const t = document.createElement('span'); t.innerHTML = `<b>Allied ${g.prod.name}</b> ${g.prod.n > 1 ? `${live}/${g.prod.n}` : ''}`; el.append(t);
  const b = document.createElement('button'); b.type = 'button'; b.className = 'abbtn'; b.innerHTML = 'Take command <kbd>T</kbd>';
  b.onclick = () => { takeCommand(g); G.inspect = null; }; el.append(b);
  const x = document.createElement('button'); x.type = 'button'; x.className = 'cmd'; x.textContent = 'Close'; x.onclick = () => { G.inspect = null; }; el.append(x);
}
function buildSquadPanel() {
  const me = G.me, box = $('squad');
  if (!me.alive) {
    box.innerHTML = `<div class="sq-dead"><b>No squad</b><span>${me.respawnT > 0 ? `Reinforcements in ${Math.ceil(me.respawnT)} s` : 'Ready to deploy'}</span><button type="button" class="btn primary" data-act="pick">Choose a squad <kbd>Tab</kbd></button></div>`;
    return;
  }
  const u0 = me.units[0], d = u0.def, ab = d.ability ? ABILITIES[d.ability] : null;
  const canAuto = !!ab || isArtillery(me.prod);
  let h = `<div class="sq-top"><span class="sq-ic"></span><div class="sq-title"><b>${me.prod.name}</b><span id="sqCount"></span><span id="sqVet" class="vet"></span></div><button type="button" class="cmd" data-act="pick">Change squad <kbd>Tab</kbd></button></div>`;
  h += `<div class="sq-mem" id="sqMem">${me.prod.n > 1 || me.units.length > 1 ? Array.from({ length: Math.max(me.prod.n, me.units.length) }, () => '<i><b></b></i>').join('') : '<i class="wide"><b></b></i>'}</div>`;
  h += `<div class="sq-row">`;
  d.weapons.forEach((w, i) => { h += `<div class="wpn"><span>${wpnName(w)} · ${WEAPONS[w].range} m</span><i><b id="rl${i}"></b></i></div>`; });
  h += `</div><div class="sq-row">`;
  if (ab) h += `<button type="button" class="abbtn" data-act="ab">${ab.name} <kbd>Q</kbd> <span id="abState"></span></button>`;
  if (canAuto) h += `<button type="button" class="autobtn" data-act="auto" id="autoBtn"></button>`;
  h += `<button type="button" class="cmd" data-act="stop">Stop <kbd>S</kbd></button><button type="button" class="cmd" data-act="hold">Hold <kbd>H</kbd></button><button type="button" class="cmd" data-act="follow">Follow cam <kbd>Space</kbd></button></div>`;
  h += `<div class="sq-status" id="sqStatus"></div><div class="sq-hint">${ROLE_HINTS[me.prod.unit] || ''}</div>`;
  box.innerHTML = h;
  box.querySelector('.sq-ic').append(iconCache(me.prod, 46));
}
function updateSquadPanel() {
  const me = G.me;
  const key = (me.alive ? me.group.id + ':' + (me.units[0].auto ? 1 : 0) + ':' + me.units.length : 'dead:' + Math.ceil(me.respawnT));
  if (key !== sqKey) { sqKey = key; buildSquadPanel(); }
  if (!me.alive) return;
  const u0 = me.units[0];
  $('sqCount').textContent = me.prod.n > 1 ? `${me.units.length}/${me.prod.n} alive` : `${Math.ceil(u0.hp)} / ${u0.maxHp} HP`;
  const rank = Math.max(...me.units.map((u) => u.rank));
  $('sqVet').textContent = rank ? '★'.repeat(rank) : '';
  const bars = $('sqMem').children;
  for (let i = 0; i < bars.length; i++) {
    const u = me.units[i];
    const k = u ? u.hp / u.maxHp : 0;
    bars[i].firstChild.style.transform = `scaleX(${k})`;
    bars[i].className = (bars[i].classList.contains('wide') ? 'wide ' : '') + (u ? (k < 0.35 ? 'low' : '') : 'gone');
  }
  u0.weapons.forEach((w, i) => {
    const el = $('rl' + i); if (!el) return;
    const k = w.salvo > 0 ? 0 : w.burst && w.def.burst ? 1 - w.burst / w.def.burst : clamp(1 - w.cd / (w.def.rest && w.burst === 0 && w.cd > w.def.cd ? w.def.rest : w.def.cd), 0, 1);
    el.style.transform = `scaleX(${k})`;
    el.parentNode.classList.toggle('ready', k >= 1);
  });
  const abEl = $('abState');
  if (abEl) {
    const op = me.units.reduce((a, u) => (u.abilityCd < a.abilityCd ? u : a), me.units[0]);
    if (me.drone && !me.drone.dead) abEl.innerHTML = `<span class="ok">flying · ${Math.max(0, Math.ceil(16 - me.drone.t))} s battery</span>`;
    else abEl.innerHTML = op.abilityCd > 0 ? `<span class="cd">${Math.ceil(op.abilityCd)} s</span>` : '<span class="ok">ready</span>';
  }
  const ab = $('autoBtn');
  if (ab) { ab.innerHTML = `Auto-fire ${u0.auto ? 'on' : 'off'} <kbd>E</kbd>`; ab.classList.toggle('on', u0.auto); }
  // status line
  let st = '';
  const w0 = u0.weapons[0];
  if (w0 && w0.def.deploy && hasManualFire(me.prod)) st = u0.moving ? 'Moving: park to fire' : u0.stillT < w0.def.deploy ? 'Setting up…' : w0.salvo > 0 ? 'Firing salvo…' : w0.cd > 0 ? `Reloading ${Math.ceil(w0.cd)} s` : 'Ready: left-click a target';
  if (me.units.some((u) => u.sup > 50)) st = (st ? st + ' · ' : '') + '<b class="warn">Pinned down</b>';
  if (me.prod.n > me.units.length) st += (st ? ' · ' : '') + (me.src ? (me.calm ? `Reinforcing at ${me.src.name}…` : `Reinforcements wait until you're out of combat`) : 'Reinforce at the HQ, a point you hold or a supply truck');
  $('sqStatus').innerHTML = st;
}

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
    else if (a === 'ab') squadAbility();
    else if (a === 'auto') toggleAuto();
    else if (a === 'stop') issueStop(me.units);
    else if (a === 'hold') issueHold(me.units);
    else if (a === 'follow') me.follow = true;
  });
  for (const el of document.querySelectorAll('.hud-panel')) {
    el.addEventListener('mouseenter', () => { G.mouse.overHud = true; });
    el.addEventListener('mouseleave', () => { G.mouse.overHud = false; });
  }
}

// ---------------------------------------------------------------------
// squad picker
// ---------------------------------------------------------------------
const PICK = { prod: PRODUCT_BY_ID.rifle, spawn: 'hq', reason: 'start' };
function buildPicker() {
  for (const line of [0, 1]) {
    const box = $(line ? 'pkVeh' : 'pkInf');
    for (const p of PRODUCTS.filter((q) => q.line === line)) {
      const b = document.createElement('button');
      b.type = 'button'; b.className = 'pk'; b.dataset.id = p.id;
      b.append(productIcon(p, 44, 0));
      const t = document.createElement('span');
      t.innerHTML = `<b>${p.name}</b><small>${p.good}</small>`;
      b.append(t);
      b.addEventListener('click', () => { PICK.prod = p; Sound.play('ui', 0.25); refreshPicker(true); });
      b.addEventListener('dblclick', () => { PICK.prod = p; deployPicked(); });
      box.append(b);
    }
  }
  $('pkGo').addEventListener('click', deployPicked);
  $('pkBack').addEventListener('click', closePicker);
}
function openPicker(reason) {
  if (G.mode !== 'play' || G.over) return;
  PICK.reason = reason;
  $('picker').hidden = false;
  $('pkTitle').textContent = reason === 'dead' ? 'Your squad is gone' : reason === 'switch' ? 'Change squad' : 'Pick your squad';
  $('pkSub').textContent = reason === 'start' ? 'The war is about to start. Both armies are commanded by AI generals; you lead one squad on the blue side. Pick any unit.'
    : reason === 'dead' ? 'Pick what you want to fight as next, or take over a squad already in the field.'
    : 'Your current squad goes back to the allied general.';
  $('pkBack').hidden = reason !== 'switch';
  PICK.spawn = null; // default to the point nearest the front
  refreshPicker(true);
}
function closePicker() {
  if (PICK.reason !== 'switch' && !(G.me && G.me.alive)) return;
  $('picker').hidden = true;
}
let pkFieldKey = '';
function refreshPicker(full) {
  const me = G.me; if (!me) return;
  for (const b of document.querySelectorAll('.pk')) b.classList.toggle('on', b.dataset.id === PICK.prod.id);
  const p = PICK.prod, d = UNITS[p.unit];
  $('pkInfo').innerHTML = `<b>${p.name}</b>${p.n > 1 ? ` · ${p.n} soldiers` : ''}<p>${p.desc}</p><p class="muted">${ROLE_HINTS[p.unit] || ''}</p><div class="tip-vs"><span class="good">Strong vs ${p.good}</span><span class="bad">Weak vs ${p.bad}</span></div>`;
  // spawn choices
  const sps = spawnPoints(p);
  if (!sps.some((s) => s.id === PICK.spawn)) PICK.spawn = sps.length > 1 ? sps[sps.length - 1].id : 'hq';
  const spBox = $('pkSpawn');
  const spKey = sps.map((s) => s.id).join(',') + PICK.spawn;
  if (full || spBox.dataset.key !== spKey) {
    spBox.dataset.key = spKey; spBox.innerHTML = '';
    for (const s of sps) {
      const b = document.createElement('button'); b.type = 'button'; b.className = 'chip' + (s.id === PICK.spawn ? ' on' : '');
      b.textContent = s.id === 'hq' ? 'HQ' : `Point ${s.label}`;
      b.onclick = () => { PICK.spawn = s.id; refreshPicker(true); };
      spBox.append(b);
    }
    $('pkSpawnNote').textContent = d.cls === 'inf' ? 'Infantry can deploy on any point you hold that is not under attack.' : 'Vehicles roll out of the HQ.';
  }
  // squads in the field
  const list = fieldSquads().slice(0, 8);
  const fKey = list.map((f) => f.g.id + ':' + f.n).join(',');
  if (full || fKey !== pkFieldKey) {
    pkFieldKey = fKey;
    const fb = $('pkField'); fb.innerHTML = '';
    if (!list.length) fb.innerHTML = '<p class="muted">No allied squads in the field yet.</p>';
    for (const f of list) {
      const b = document.createElement('button'); b.type = 'button'; b.className = 'fld';
      b.append(iconCache(f.g.prod, 30));
      const t = document.createElement('span'); t.innerHTML = `<b>${f.g.prod.name}</b> ${f.g.prod.n > 1 ? f.n + '/' + f.g.prod.n : ''} <small>near ${f.near} · ${Math.round(f.hp * 100)}% health</small>`;
      b.append(t);
      b.onclick = () => { takeCommand(f.g); $('picker').hidden = true; G.paused = false; };
      fb.append(b);
    }
  }
  const go = $('pkGo');
  const wait = me.alive ? 0 : me.respawnT;
  go.disabled = wait > 0;
  go.textContent = wait > 0 ? `Deploy in ${Math.ceil(wait)} s` : `Deploy ${p.name}`;
}
function deployPicked() {
  const me = G.me;
  if (!me.alive && me.respawnT > 0) return;
  deployMe(PICK.prod, PICK.spawn);
  try { localStorage.setItem('dotwar.squad', PICK.prod.id); } catch (e) {}
  $('picker').hidden = true;
  G.paused = false;
  sqKey = '';
  notify(`You lead a ${PICK.prod.name.toLowerCase()}. ${PICK.prod.n > 1 ? 'Lost soldiers come back when you rest near the HQ, a point you hold or a supply truck.' : ''}`, 'info');
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
    sqKey = '';
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
    let html = `<thead><tr><th></th><th class="team-0">Blue</th><th class="team-1">Red</th></tr></thead><tbody>` +
      row('Units lost', T[0].stats.lost, T[1].stats.lost) + row('Kills', T[0].stats.kills, T[1].stats.kills) + row('Points held', T[0].held, T[1].held) + row('Tickets left', Math.ceil(T[0].tickets), Math.ceil(T[1].tickets)) + `</tbody>`;
    $('endStats').innerHTML = html;
    const me = G.me;
    $('endMe').innerHTML = me ? `<b>Your war</b><span>${me.score} points</span><span>${me.kills} kills (${me.vkills} vehicles)</span><span>${me.captures} captures</span><span>${me.missions} missions</span><span>${me.lost} squads lost</span>` : '';
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
  for (const p of PRODUCTS) {
    const li = document.createElement('li');
    li.append(productIcon(p, 40, 0));
    const d = document.createElement('div');
    d.innerHTML = `<b>${p.name}</b> <span class="muted">${p.n > 1 ? '×' + p.n : 'single'}</span><br>${ROLE_HINTS[p.unit] || p.desc}`;
    li.append(d); roster.append(li);
  }
  buildPicker();
}

function boot() {
  try {
    const m = localStorage.getItem('dotwar.muted'); if (m === '1') Sound.muted = true;
    const d = localStorage.getItem('dotwar.diff'); if (d && DIFFS[d]) G.settings.diff = d;
    const t = localStorage.getItem('dotwar.tod'); if (t) G.settings.tod = t;
    const s = localStorage.getItem('dotwar.squad'); if (s && PRODUCT_BY_ID[s]) PICK.prod = PRODUCT_BY_ID[s];
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
