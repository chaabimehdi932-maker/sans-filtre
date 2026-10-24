'use strict';
// =====================================================================
// Game state, main loop, camera, rendering, input, HUD and menus
// =====================================================================

const G = {
  units: [], drones: [], missiles: [], projs: [], mines: [], strikes: [], warnings: [], wrecks: [], impacts: [], points: [], jammers: [],
  teams: [], ai: [null, null], grid: null, bases: [[], []],
  time: 0, frame: 0, speed: 1, paused: false, mode: 'boot', playerTeam: 0, over: false,
  cam: { x: W / 2, y: H / 2, zoom: 0.4, vx: 0, vy: 0 }, viewW: 800, viewH: 600, dpr: 1,
  sel: new Set(), groups: {}, night: 0, markers: [], pings: [], me: null,
  mouse: { x: 0, y: 0, wx: 0, wy: 0, in: false }, drag: null, hover: null, aim: null,
  settings: { diff: 'veteran', tod: 'day', seed: 0 },
  seen(u) { return G.playerTeam < 0 || u.team === G.playerTeam || u.vis[G.playerTeam]; },
  lossFeed(u) { lossFeed(u); }, hqDestroyed(team) { endGame(1 - team, 'hq'); },
};

const $ = (id) => document.getElementById(id);

// ---------------------------------------------------------------------
// new game
// ---------------------------------------------------------------------
function newGame(o) {
  G.units = []; G.drones = []; G.missiles = []; G.projs = []; G.mines = []; G.strikes = []; G.warnings = []; G.wrecks = []; G.impacts = []; G.jammers = [];
  G.markers = []; G.pings = []; G.sel = new Set(); G.groups = {}; G.over = false; G.time = 0; G.frame = 0; G.aim = null;
  FX.parts.length = 0; FX.tracers.length = 0; FX.rings.length = 0; FX.lights.length = 0; FX.texts.length = 0; FX.emitters.length = 0; FX.shake = 0; FX.flash = 0;
  NEXT_ID = 1;
  G.mode = o.mode;
  G.playerTeam = o.mode === 'play' ? 0 : -1;
  G.night = { day: 0, dusk: 0.4, night: 0.72 }[o.tod] || 0;
  G.speed = 1; G.paused = false;
  generateMap(o.seed);
  G.grid = new SpatialGrid(128);
  initVision();
  G.teams = [];
  for (let t = 0; t < 2; t++) {
    const h = MAP.hq[t];
    const hq = spawnUnit('hq', t, h.x, h.y);
    hq.ang = t ? Math.PI : 0;
    markRect(h.x - 100, h.y - 100, h.x + 100, h.y + 100, (i, x, y) => { if (Math.abs(x - h.x) < 85 && Math.abs(y - h.y) < 70) MAP.block[i] = 1; });
    for (const tp of MAP.turrets[t]) { const tu = spawnUnit('turret', t, tp.x, tp.y); tu.tang = hq.ang; MAP.block[cellOf(tp.x, tp.y)] = 1; }
    Object.assign(hq.stock, LOGI.hqStart);
    const dir = t === 0 ? 1 : -1;
    G.teams.push({ id: t, queues: [[], []], rally: { x: h.x + dir * 430, y: h.y }, hq, stats: { built: 0, lost: 0, kills: 0, spent: 0 }, radars: 0, held: 0, winT: 0, lastHitT: -99 });
  }
  NAV.cache.clear();
  // jeeps and a cargo truck waiting at your HQ
  if (o.mode === 'play') { for (let k = 0; k < 2; k++) spawnJeep(MAP.hq[0].x + 110 + k * 55, MAP.hq[0].y + 150, 0); spawnDepotTruck(); }
  // both armies are run by AI generals; in a real battle you are one soldier on the blue side
  G.ai = [new AICommander(0, o.mode === 'play' ? 'veteran' : o.blueDiff || 'elite'), new AICommander(1, o.mode === 'play' ? o.diff : o.redDiff || 'elite')];
  G.me = o.mode === 'play' ? newMe() : null;
  G.quiet = true;
  initTowns();
  // opening forces
  for (let t = 0; t < 2; t++) for (const id of ['rifle', 'rifle', 'mg', 'scout', 'sup']) deploy(t, PRODUCT_BY_ID[id]);
  G.quiet = false;
  G.bases = [[], []]; logiAcc = 1; logisticsTick(0);
  for (const u of G.units) if (u.cls !== 'bld' && !u.empty) { const dir = u.team ? -1 : 1; u.x += dir * rand(60, 240); u.y += rand(-140, 140); }
  updateVision();
  // camera
  const c = G.cam;
  if (G.playerTeam === 0) { c.x = MAP.hq[0].x + 560; c.y = MAP.hq[0].y; c.zoom = 0.95; }
  else { c.x = W / 2; c.y = H / 2; c.zoom = fitZoom(); }
  minimapBase = null;
  $('feed').innerHTML = '';
  G.fogA = new Float32Array(GW * GH).fill(1);
  G.director = { t: 0, x: c.x, y: c.y };
  updateHudNow();
}
function fitZoom() { return Math.max(G.viewW / W, G.viewH / H) * 1.02; }

// ---------------------------------------------------------------------
// simulation step
// ---------------------------------------------------------------------
let visT = 0, hudT = 0, miniT = 0, aiLate = 0;
function step(dt) {
  G.time += dt; G.frame++;
  G.grid.clear();
  for (const u of G.units) if (!u.dead && !u.inside) G.grid.insert(u);
  for (const d of G.drones) if (!d.dead) G.grid.insert(d);
  for (const m of G.missiles) if (!m.dead) G.grid.insert(m);
  visT -= dt;
  if (visT <= 0) { visT = 0.2; updateVision(); updateCover(); }
  for (let i = 0; i < G.units.length; i++) { const u = G.units[i]; if (!u.dead) updateUnit(u, dt); }
  if (G.me) updateMe(dt);
  updateProjectiles(dt); updateDrones(dt); updateMissiles(dt); updateStrikes(dt); updateMines(dt);
  updateTowns(dt); logisticsTick(dt); updateProduction(dt);
  for (const ai of G.ai) if (ai) ai.update(dt);
  // field hospital: slow repairs next to your own HQ
  for (const T of G.teams) {
    const h = T.hq; if (!h || h.dead) continue;
    if (G.frame % 15 === 0) for (const u of G.grid.query(h.x, h.y, 380)) if (u.team === T.id && !u.dead && u.cls !== 'air' && u.hp < u.maxHp && G.time - u.lastHit > 5) u.hp = Math.min(u.maxHp, u.hp + (u.cls === 'veh' ? 12 : u.cls === 'bld' ? 8 : 4) * dt * 15);
  }
  for (let i = G.wrecks.length - 1; i >= 0; i--) { const w = G.wrecks[i]; w.t += dt; if (w.t > w.life) { decalWreck({ x: w.x, y: w.y, ang: w.ang, def: UNITS[w.type] }); G.wrecks.splice(i, 1); } }
  // cleanup
  let j = 0;
  for (let i = 0; i < G.units.length; i++) { const u = G.units[i]; if (u.dead) { G.sel.delete(u); continue; } G.units[j++] = u; }
  G.units.length = j;
  for (let i = G.markers.length - 1; i >= 0; i--) { G.markers[i].t += dt; if (G.markers[i].t > 0.8) G.markers.splice(i, 1); }
  for (let i = G.pings.length - 1; i >= 0; i--) { G.pings[i].t += dt; if (G.pings[i].t > 3) G.pings.splice(i, 1); }
  updateFx(dt);
  // wind drifts slowly
  FX.wind.x = 10 * Math.cos(G.time * 0.03); FX.wind.y = -5 + 4 * Math.sin(G.time * 0.05);
}

// ---------------------------------------------------------------------
// main loop
// ---------------------------------------------------------------------
let lastTs = 0, fpsAcc = 0, fpsN = 0;
function frame(ts) {
  const dtReal = Math.min(0.05, (ts - lastTs) / 1000 || 0.016);
  lastTs = ts;
  if (G.mode !== 'boot') {
    if (!G.paused) {
      const steps = Math.max(1, Math.floor(G.speed)), sdt = dtReal * Math.min(1, G.speed);
      for (let i = 0; i < steps; i++) step(sdt);
    }
    updateCamera(dtReal);
    render(dtReal);
    hudT -= dtReal; if (hudT <= 0) { hudT = 0.12; updateHud(); }
    miniT -= dtReal; if (miniT <= 0) { miniT = 0.1; drawMinimap(); }
  }
  requestAnimationFrame(frame);
}

// ---------------------------------------------------------------------
// camera
// ---------------------------------------------------------------------
const keys = {};
function updateCamera(dt) {
  const c = G.cam;
  const sp = 900 / c.zoom * dt;
  let mx = 0, my = 0;
  const play = G.mode === 'play';
  if (!play) {
    if (keys.ArrowUp || keys.KeyW) my -= 1;
    if (keys.ArrowDown || keys.KeyS) my += 1;
    if (keys.ArrowLeft || keys.KeyA) mx -= 1;
    if (keys.ArrowRight || keys.KeyD) mx += 1;
  }
  c.x += mx * sp; c.y += my * sp;
  // follow you (or the drone you are flying), leaning toward where you aim
  if (play && G.me && !G.over) {
    const me = G.me;
    let tgt = null, zt = null;
    if (me.drone && !me.drone.dead) { tgt = { x: me.drone.x, y: me.drone.y }; zt = 1.15 * me.zoomMul; }
    else if (me.alive) {
      const a = avatar(), m = G.mouse;
      // lean toward where you aim; further while aiming, much further through binoculars
      const k = me.look ? 0.9 : me.aiming ? 0.55 : 0.35, cap = me.look ? 2.2 : me.aiming ? 1.5 : 1;
      const lx = m.in ? clamp((m.x - G.viewW / 2) / c.zoom * k, -240 * cap, 240 * cap) : 0, ly = m.in ? clamp((m.y - G.viewH / 2) / c.zoom * k, -170 * cap, 170 * cap) : 0;
      tgt = { x: a.x + lx, y: a.y + ly };
      const v = me.vehicle, far = v && (v.type === 'missile' || (v.weapons[0] && v.weapons[0].def.arty));
      zt = (v ? (far ? 0.7 : 1.0) : me.look ? 0.8 : 1.35) * me.zoomMul;
    }
    if (tgt) { const k = 1 - Math.pow(me.drone ? 0.02 : 0.03, dt); c.x = lerp(c.x, tgt.x, k); c.y = lerp(c.y, tgt.y, k); }
    if (zt) c.zoom = lerp(c.zoom, zt, 1 - Math.pow(0.25, dt));
  }
  // menu / spectator director camera follows the action
  if ((G.mode === 'menu' || (G.mode === 'spectate' && G.autoCam)) && !G.over) {
    const d = G.director; d.t -= dt;
    if (d.t <= 0) { d.t = 5; const hot = hotSpot(); if (hot) { d.x = hot.x; d.y = hot.y; } }
    c.x = lerp(c.x, d.x, 1 - Math.pow(0.4, dt)); c.y = lerp(c.y, d.y, 1 - Math.pow(0.4, dt));
    if (G.mode === 'menu') c.zoom = lerp(c.zoom, 0.72, 1 - Math.pow(0.5, dt));
  }
  const minZ = fitZoom() * 0.98;
  c.zoom = clamp(c.zoom, minZ, 2.4);
  const hw = G.viewW / 2 / c.zoom, hh = G.viewH / 2 / c.zoom;
  c.x = W < hw * 2 ? W / 2 : clamp(c.x, hw - 100, W - hw + 100);
  c.y = H < hh * 2 ? H / 2 : clamp(c.y, hh - 100, H - hh + 160);
  // the cursor's world position moves with the camera even when the mouse doesn't
  const w = screenToWorld(G.mouse.x, G.mouse.y); G.mouse.wx = w.x; G.mouse.wy = w.y;
}
function hotSpot() {
  let best = null, bs = 0;
  const cand = [];
  for (const i of G.impacts) cand.push(i);
  for (let k = 0; k < 40 && G.units.length; k++) { const u = G.units[(Math.random() * G.units.length) | 0]; if (u.weapons.length && u.weapons[0].target) cand.push(u); }
  for (const c of cand) {
    let s = 0;
    for (const u of G.grid.query(c.x, c.y, 500)) if (!u.dead) s += u.cls === 'veh' ? 4 : 1;
    if (s > bs) { bs = s; best = { x: c.x, y: c.y }; }
  }
  return best;
}
function screenToWorld(sx, sy) { const c = G.cam; return { x: c.x + (sx - G.viewW / 2) / c.zoom, y: c.y + (sy - G.viewH / 2) / c.zoom }; }
function worldToScreen(x, y) { const c = G.cam; return { x: (x - c.x) * c.zoom + G.viewW / 2, y: (y - c.y) * c.zoom + G.viewH / 2 }; }

// ---------------------------------------------------------------------
// rendering
// ---------------------------------------------------------------------
let canvas, ctx, detailPat, fogCv, fogCtx, fogImg, lightCv, lightCtx, fogBlur, fogBlurCtx;
function setupCanvas() {
  canvas = $('view'); ctx = canvas.getContext('2d', { alpha: false });
  fogCv = document.createElement('canvas'); fogCv.width = GW; fogCv.height = GH;
  fogCtx = fogCv.getContext('2d'); fogImg = fogCtx.createImageData(GW, GH);
  lightCv = document.createElement('canvas'); lightCtx = lightCv.getContext('2d');
  fogBlur = document.createElement('canvas'); fogBlur.width = GW * 4; fogBlur.height = GH * 4;
  fogBlurCtx = fogBlur.getContext('2d');
  if ('filter' in fogBlurCtx) fogBlurCtx.filter = 'blur(5px)'; else fogBlurCtx = null;
  detailPat = makeDetailPattern(ctx);
  resize();
  window.addEventListener('resize', resize);
}
function resize() {
  const r = canvas.getBoundingClientRect();
  G.dpr = Math.min(1.5, window.devicePixelRatio || 1);
  G.viewW = Math.max(1, r.width); G.viewH = Math.max(1, r.height);
  canvas.width = Math.round(G.viewW * G.dpr); canvas.height = Math.round(G.viewH * G.dpr);
  lightCv.width = Math.ceil(G.viewW / 2); lightCv.height = Math.ceil(G.viewH / 2);
}

function render(dt) {
  const c = G.cam, z = c.zoom, dpr = G.dpr;
  const shx = (Math.random() - 0.5) * FX.shake, shy = (Math.random() - 0.5) * FX.shake;
  const view = { x0: c.x - G.viewW / 2 / z, y0: c.y - G.viewH / 2 / z, x1: c.x + G.viewW / 2 / z, y1: c.y + G.viewH / 2 / z };
  G.view = view;
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  ctx.fillStyle = '#23261a'; ctx.fillRect(0, 0, G.viewW, G.viewH);
  ctx.setTransform(dpr * z, 0, 0, dpr * z, dpr * (G.viewW / 2 - c.x * z + shx), dpr * (G.viewH / 2 - c.y * z + shy));

  // ground
  const sx0 = clamp(view.x0, 0, W), sy0 = clamp(view.y0, 0, H), sx1 = clamp(view.x1, 0, W), sy1 = clamp(view.y1, 0, H);
  if (sx1 > sx0 && sy1 > sy0) {
    ctx.imageSmoothingEnabled = true;
    ctx.drawImage(MAP.ground, sx0 * GS, sy0 * GS, (sx1 - sx0) * GS, (sy1 - sy0) * GS, sx0, sy0, sx1 - sx0, sy1 - sy0);
    if (z > 0.55) { ctx.globalAlpha = clamp((z - 0.55) * 2, 0, 0.8); ctx.fillStyle = detailPat; ctx.fillRect(sx0, sy0, sx1 - sx0, sy1 - sy0); ctx.globalAlpha = 1; }
  }
  drawWaterShimmer(view);
  drawBridges(view);
  drawTownsGround(view);
  drawMines(view);
  drawWrecks(view);
  drawGroundStructs(view, z);
  drawUnits(view, z);
  drawLowProjectiles(view);
  drawParticles(ctx, view, 0);
  drawTrees(view, z);
  drawParticles(ctx, view, 1);
  drawDrones(view);
  // night darkness, then everything that glows
  if (G.night > 0) drawNight(view);
  drawParticles(ctx, view, 2);
  drawTracers(ctx);
  drawGlows(ctx, view);
  drawFog(view);
  drawAir(view);
  drawWarnings(view);
  drawOverlays(view, z);
  drawTexts(ctx);
  // screen space
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  if (G.me && G.me.alive) {
    const m = G.me.mission, tg = m && missionTarget(m);
    if (tg) edgeArrow(tg.x, tg.y, '#f7d54a', m.p ? m.p.letter : '!');
  }
  if (G.me) drawCrosshair();
  if (FX.flash > 0.01) { ctx.fillStyle = `rgba(255,244,220,${FX.flash * 0.6})`; ctx.fillRect(0, 0, G.viewW, G.viewH); }
  if (G.drag && G.drag.box) {
    const d = G.drag; const x = Math.min(d.sx, d.ex), y = Math.min(d.sy, d.ey), w = Math.abs(d.ex - d.sx), h = Math.abs(d.ey - d.sy);
    ctx.fillStyle = 'rgba(160,255,140,0.08)'; ctx.fillRect(x, y, w, h);
    ctx.strokeStyle = 'rgba(170,255,150,0.9)'; ctx.lineWidth = 1; ctx.strokeRect(x + 0.5, y + 0.5, w, h);
  }
  // vignette
  if (!G.vig || G.vig.w !== G.viewW || G.vig.h !== G.viewH) {
    const g = ctx.createRadialGradient(G.viewW / 2, G.viewH / 2, Math.min(G.viewW, G.viewH) * 0.45, G.viewW / 2, G.viewH / 2, Math.max(G.viewW, G.viewH) * 0.75);
    g.addColorStop(0, 'rgba(0,0,0,0)'); g.addColorStop(1, 'rgba(0,0,0,0.38)');
    G.vig = { w: G.viewW, h: G.viewH, g };
  }
  ctx.fillStyle = G.vig.g; ctx.fillRect(0, 0, G.viewW, G.viewH);
}

// arrow on the screen edge pointing at something off screen
function edgeArrow(x, y, color, label) {
  const s = worldToScreen(x, y), W2 = G.viewW, H2 = G.viewH, pad = 40;
  if (s.x > pad && s.y > 80 && s.x < W2 - pad && s.y < H2 - 190) return;
  const cx = W2 / 2, cy = H2 / 2, a = Math.atan2(s.y - cy, s.x - cx);
  const k = Math.min((W2 / 2 - pad) / Math.abs(Math.cos(a) || 1e-6), (H2 / 2 - 110) / Math.abs(Math.sin(a) || 1e-6));
  const px = cx + Math.cos(a) * k, py = cy + Math.sin(a) * k;
  ctx.save(); ctx.translate(px, py); ctx.rotate(a);
  ctx.fillStyle = color; ctx.strokeStyle = 'rgba(0,0,0,0.6)'; ctx.lineWidth = 2;
  ctx.beginPath(); ctx.moveTo(16, 0); ctx.lineTo(-6, -11); ctx.lineTo(-2, 0); ctx.lineTo(-6, 11); ctx.closePath(); ctx.fill(); ctx.stroke();
  ctx.restore();
  ctx.font = '700 12px "Barlow Condensed", "Arial Narrow", sans-serif'; ctx.textAlign = 'center';
  ctx.fillStyle = 'rgba(0,0,0,0.7)'; ctx.fillText(label, px - Math.cos(a) * 22 + 1, py - Math.sin(a) * 22 + 5);
  ctx.fillStyle = color; ctx.fillText(label, px - Math.cos(a) * 22, py - Math.sin(a) * 22 + 4);
}
function drawWaterShimmer(view) {
  const t = G.time;
  ctx.strokeStyle = 'rgba(190,205,195,0.12)'; ctx.lineWidth = 2;
  ctx.beginPath();
  const y0 = Math.max(0, view.y0 - 40), y1 = Math.min(H, view.y1 + 40);
  for (let y = Math.floor(y0 / 60) * 60; y < y1; y += 60) {
    const rx = MAP.riverX(y), hw = MAP.riverHW(y);
    if (rx + hw < view.x0 || rx - hw > view.x1) continue;
    for (let k = -1; k <= 1; k++) {
      const yy = y + ((t * 26 + k * 20 + y * 0.37) % 60);
      const xx = MAP.riverX(yy) + k * hw * 0.45 + Math.sin(t + y) * 6;
      ctx.moveTo(xx, yy); ctx.lineTo(xx + 2, yy + 14);
    }
  }
  ctx.stroke();
}
function drawBridges(view) {
  for (const b of MAP.bridges) {
    if (b.x1 < view.x0 || b.x0 > view.x1 || b.y + 50 < view.y0 || b.y - 50 > view.y1) continue;
    ctx.fillStyle = 'rgba(0,0,0,0.3)'; ctx.fillRect(b.x0 + 6, b.y - 30, b.x1 - b.x0, 72);
    ctx.fillStyle = '#7b776b'; ctx.fillRect(b.x0, b.y - 36, b.x1 - b.x0, 72);
    ctx.fillStyle = '#8f8b7e'; ctx.fillRect(b.x0, b.y - 30, b.x1 - b.x0, 60);
    ctx.strokeStyle = 'rgba(0,0,0,0.18)'; ctx.lineWidth = 2; ctx.beginPath();
    for (let x = b.x0 + 20; x < b.x1; x += 22) { ctx.moveTo(x, b.y - 30); ctx.lineTo(x, b.y + 30); }
    ctx.stroke();
    ctx.fillStyle = '#3b3a35'; ctx.fillRect(b.x0, b.y - 38, b.x1 - b.x0, 5); ctx.fillRect(b.x0, b.y + 33, b.x1 - b.x0, 5);
    ctx.fillStyle = '#26251f'; for (let x = b.x0; x <= b.x1; x += 30) { ctx.fillRect(x - 3, b.y - 40, 6, 9); ctx.fillRect(x - 3, b.y + 31, 6, 9); }
  }
}
function teamRGB(t) { return t === 0 ? TEAM[0].rgb : t === 1 ? TEAM[1].rgb : '230,230,220'; }
function drawTownsGround(view) {
  for (const p of G.points) {
    if (p.x + 260 < view.x0 || p.x - 260 > view.x1 || p.y + 260 < view.y0 || p.y - 260 > view.y1) continue;
    const rgb = teamRGB(p.owner);
    ctx.setLineDash([18, 14]); ctx.lineDashOffset = -G.time * 6;
    ctx.strokeStyle = `rgba(${rgb},${p.owner >= 0 ? 0.4 : 0.28})`; ctx.lineWidth = 3; ctx.beginPath(); ctx.arc(p.x, p.y, p.r, 0, TAU); ctx.stroke();
    ctx.setLineDash([]);
    if (p.contested || p.sabotage) { ctx.strokeStyle = `rgba(255,220,90,${0.45 + 0.45 * Math.sin(G.time * 8)})`; ctx.lineWidth = 3; ctx.beginPath(); ctx.arc(p.x, p.y, p.r + 8, 0, TAU); ctx.stroke(); }
    if (p.flash > 0) { ctx.fillStyle = `rgba(${rgb},${p.flash * 0.15})`; ctx.beginPath(); ctx.arc(p.x, p.y, p.r, 0, TAU); ctx.fill(); }
    // an empty plot where a new hall can go
    if (!p.hall) {
      ctx.strokeStyle = 'rgba(240,235,215,0.55)'; ctx.lineWidth = 2; ctx.setLineDash([6, 6]);
      ctx.strokeRect(p.hx - 34, p.hy - 28, 66, 56); ctx.setLineDash([]);
    }
  }
}
// trenches, sandbags, wire and tank traps lie under the soldiers standing in them
function drawGroundStructs(view, z) {
  for (const u of G.units) {
    if ((!u.def.line && u.type !== 'trap') || u.dead) continue;
    if (u.x < view.x0 - 90 || u.x > view.x1 + 90 || u.y < view.y0 - 90 || u.y > view.y1 + 90 || !G.seen(u)) continue;
    ctx.save(); ctx.translate(u.x, u.y); ctx.rotate(u.ang);
    drawStruct(ctx, u, TEAM[u.team], G.time);
    ctx.restore();
  }
}
function drawMines(view) {
  for (const m of G.mines) {
    const own = G.playerTeam < 0 || m.team === G.playerTeam;
    if (!own) {
      let seen = false;
      for (const u of G.grid.query(m.x, m.y, 70)) if (u.team === G.playerTeam && !u.dead && (dist(u.x, u.y, m.x, m.y) < 60 || u.type === 'engineer')) { seen = true; break; }
      if (!seen) continue;
    }
    ctx.fillStyle = '#2a2a24'; ctx.beginPath(); ctx.arc(m.x, m.y, 7, 0, TAU); ctx.fill();
    ctx.strokeStyle = m.team === 0 ? TEAM[0].main : TEAM[1].main; ctx.lineWidth = 2; ctx.stroke();
    ctx.fillStyle = m.armT > 0 ? '#888' : `rgba(255,60,40,${0.5 + 0.5 * Math.sin(G.time * 6)})`; ctx.beginPath(); ctx.arc(m.x, m.y, 2, 0, TAU); ctx.fill();
  }
}
const WRECK_TC = { main: '#34302b', dark: '#1d1b18', light: '#444' };
function drawWrecks(view) {
  for (const w of G.wrecks) {
    if (w.x < view.x0 - 60 || w.x > view.x1 + 60 || w.y < view.y0 - 60 || w.y > view.y1 + 60) continue;
    const d = UNITS[w.type];
    ctx.save(); ctx.translate(w.x, w.y); ctx.rotate(w.ang);
    drawVehicle(ctx, w.type, WRECK_TC, d.len, d.wid, angDiff(w.ang, w.tang), 0, 0, null);
    ctx.restore();
  }
}
function drawUnits(view, z) {
  const lod = z < 0.3;
  const t = G.time;
  // shadows first
  ctx.fillStyle = 'rgba(0,0,0,0.26)';
  for (const u of G.units) {
    if (u.x < view.x0 - 120 || u.x > view.x1 + 120 || u.y < view.y0 - 120 || u.y > view.y1 + 120 || !G.seen(u) || u.inside) continue;
    if (u.cls === 'inf') { ctx.beginPath(); ctx.ellipse(u.x + 2.5, u.y + 3.5, u.r, u.r * 0.85, 0, 0, TAU); ctx.fill(); }
    else if (u.cls === 'veh') { ctx.save(); ctx.translate(u.x + 4, u.y + 5); ctx.rotate(u.ang); ctx.fillRect(-u.def.len / 2, -u.def.wid / 2, u.def.len, u.def.wid); ctx.restore(); }
  }
  for (const u of G.units) {
    if (u.x < view.x0 - 120 || u.x > view.x1 + 120 || u.y < view.y0 - 120 || u.y > view.y1 + 120 || !G.seen(u) || u.inside) continue;
    const tc = TEAM[u.team];
    ctx.save(); ctx.translate(u.x, u.y);
    if (u.cls === 'bld') {
      if (u.def.line || u.type === 'trap') { ctx.restore(); continue; } // drawn in the ground pass
      if (u.type === 'hq') { ctx.rotate(u.team ? Math.PI : 0); drawHQ(ctx, tc, t + u.team, u.hp / u.maxHp); }
      else if (u.type === 'turret') drawTurretBld(ctx, tc, u.tang, u.recoil);
      else { ctx.rotate(u.ang); drawStruct(ctx, u, tc, t + u.id); }
      if (u.built && u.hp < u.maxHp * 0.5 && G.frame % 6 === 0) smoke(u.x + rand(-20, 20), u.y + rand(-20, 20), 0.8, true, 2);
      ctx.restore();
      continue;
    }
    ctx.rotate(u.ang);
    const concealedOwn = G.playerTeam >= 0 && u.team === G.playerTeam && isConcealed(u);
    if (concealedOwn) ctx.globalAlpha = 0.55;
    if (lod) {
      ctx.fillStyle = tc.main;
      if (u.cls === 'inf') { ctx.beginPath(); ctx.arc(0, 0, u.r * 1.3, 0, TAU); ctx.fill(); }
      else { ctx.fillRect(-u.def.len / 2, -u.def.wid / 2, u.def.len, u.def.wid); ctx.strokeStyle = INK; ctx.lineWidth = 3; ctx.strokeRect(-u.def.len / 2, -u.def.wid / 2, u.def.len, u.def.wid); }
    } else if (u.cls === 'inf') {
      const bob = u.moving ? 1 + Math.sin(u.anim * 15) * 0.05 : 1;
      if (bob !== 1) ctx.scale(bob, bob);
      const tool = u.avatar && G.me ? (G.me.tool === 'gun' ? null : G.me.tool) : u.working ? 'hammer' : null;
      if (tool) drawTool(ctx, tool, u.r, u.avatar ? (G.me.working ? t : 0) : t + u.id);
      else drawInfantry(ctx, u.type, tc, u.r, u.anim, u);
      if (tool) { ctx.fillStyle = tc.main; ctx.strokeStyle = INK; ctx.lineWidth = 2; ctx.beginPath(); ctx.arc(0, 0, u.r, 0, TAU); ctx.fill(); ctx.stroke(); }
      if (u.sup > 50) { ctx.fillStyle = 'rgba(0,0,0,0.28)'; ctx.beginPath(); ctx.arc(0, 0, u.r, 0, TAU); ctx.fill(); }
    } else {
      drawVehicle(ctx, u.type, tc, u.def.len, u.def.wid, angDiff(u.ang, u.tang), u.recoil, u.anim, u);
      if (u.hp < u.maxHp * 0.4 && G.frame % 5 === 0) smoke(u.x + rand(-6, 6), u.y + rand(-6, 6), 0.5, true, 1.6);
      if (u.hp < u.maxHp * 0.2 && G.frame % 3 === 0) fire(u.x + rand(-6, 6), u.y + rand(-6, 6), 0.6, 0.4);
    }
    if (u.hitFlash > 0) {
      ctx.globalAlpha = u.hitFlash * 5; ctx.fillStyle = '#fff';
      if (u.cls === 'inf') { ctx.beginPath(); ctx.arc(0, 0, u.r, 0, TAU); ctx.fill(); } else ctx.fillRect(-u.def.len / 2, -u.def.wid / 2, u.def.len, u.def.wid);
    }
    ctx.globalAlpha = 1;
    ctx.restore();
    // jammer bubble
    if (u.type === 'jammer' && !lod) {
      ctx.strokeStyle = `rgba(120,255,190,${0.12 + 0.08 * Math.sin(t * 3 + u.id)})`; ctx.lineWidth = 2; ctx.setLineDash([6, 8]);
      ctx.beginPath(); ctx.arc(u.x, u.y, u.def.jam, 0, TAU); ctx.stroke(); ctx.setLineDash([]);
    }
    if (u.healing && u.healing.x != null && !lod) {
      ctx.strokeStyle = u.type === 'medic' ? 'rgba(255,90,90,0.5)' : 'rgba(255,230,120,0.5)'; ctx.lineWidth = 1.5;
      ctx.setLineDash([3, 4]); ctx.beginPath(); ctx.moveTo(u.x, u.y); ctx.lineTo(u.healing.x, u.healing.y); ctx.stroke(); ctx.setLineDash([]);
    }
  }
}
function drawLowProjectiles(view) {
  for (const p of G.projs) {
    if (p.kind === 'shell') {
      const a = Math.atan2(p.ty - p.sy, p.tx - p.sx);
      ctx.globalCompositeOperation = 'lighter';
      ctx.strokeStyle = 'rgba(255,220,150,0.9)'; ctx.lineWidth = 2.5; ctx.lineCap = 'round';
      ctx.beginPath(); ctx.moveTo(p.x, p.y); ctx.lineTo(p.x - Math.cos(a) * 22, p.y - Math.sin(a) * 22); ctx.stroke();
      ctx.globalCompositeOperation = 'source-over';
    } else if (p.kind === 'rocket') {
      ctx.save(); ctx.translate(p.x, p.y); ctx.rotate(p.ang);
      ctx.fillStyle = '#2b2b2b'; ctx.fillRect(-6, -2, 12, 4); ctx.fillStyle = '#c33'; ctx.fillRect(4, -2, 3, 4);
      ctx.restore();
    } else if (p.kind === 'lob') {
      ctx.fillStyle = 'rgba(0,0,0,0.3)'; ctx.beginPath(); ctx.arc(p.x, p.y, 3, 0, TAU); ctx.fill();
      ctx.save(); ctx.translate(p.x, p.y - (p.z || 0) * 0.55); ctx.rotate(p.spin);
      ctx.fillStyle = p.satchel ? '#3a3220' : '#2b2b2b'; if (p.satchel) ctx.fillRect(-4, -3, 8, 6); else { ctx.beginPath(); ctx.ellipse(0, 0, 3.5, 2.6, 0, 0, TAU); ctx.fill(); }
      ctx.restore();
    }
  }
}
function drawTrees(view, z) {
  if (z < 0.32) {
    const sc = 0.125;
    const sx0 = clamp(view.x0, 0, W), sy0 = clamp(view.y0, 0, H), sx1 = clamp(view.x1, 0, W), sy1 = clamp(view.y1, 0, H);
    ctx.globalAlpha = 0.92;
    ctx.drawImage(MAP.canopyLow, sx0 * sc, sy0 * sc, (sx1 - sx0) * sc, (sy1 - sy0) * sc, sx0, sy0, sx1 - sx0, sy1 - sy0);
    ctx.globalAlpha = 1;
    return;
  }
  const TS = TREE_TILE;
  const tx0 = Math.max(0, Math.floor(view.x0 / TS)), tx1 = Math.min(MAP.treeCols - 1, Math.floor(view.x1 / TS));
  const ty0 = Math.max(0, Math.floor(view.y0 / TS)), ty1 = Math.min(MAP.treeRows - 1, Math.floor(view.y1 / TS));
  ctx.globalAlpha = 0.93;
  for (let ty = ty0; ty <= ty1; ty++) for (let tx = tx0; tx <= tx1; tx++) {
    const tile = MAP.treeTiles[ty * MAP.treeCols + tx];
    if (tile) ctx.drawImage(tile, tx * TS - TREE_PAD, ty * TS - TREE_PAD, TS + TREE_PAD * 2, TS + TREE_PAD * 2);
  }
  ctx.globalAlpha = 1;
}
function drawDrones(view) {
  for (const d of G.drones) {
    if (d.dead || !G.seen(d)) continue;
    const zy = d.y - d.z * 0.55;
    ctx.fillStyle = 'rgba(0,0,0,0.25)'; ctx.beginPath(); ctx.ellipse(d.x, d.y, 7, 5, 0, 0, TAU); ctx.fill();
    ctx.save(); ctx.translate(d.x, zy); ctx.rotate(d.ang);
    drawMiniDrone(ctx, 0, 0, 9, d.spin, TEAM[d.team].main);
    ctx.restore();
    if (d.jammed) { ctx.strokeStyle = 'rgba(140,255,200,0.7)'; ctx.lineWidth = 1.5; ctx.beginPath(); ctx.arc(d.x, zy, 12 + Math.sin(G.time * 30) * 3, 0, TAU); ctx.stroke(); }
  }
}
function drawAir(view) {
  for (const p of G.projs) {
    if (p.kind !== 'arty' && p.kind !== 'mrocket' && p.kind !== 'barrage') continue;
    const zy = p.y - p.z * 0.55;
    const k = p.t / p.T;
    ctx.fillStyle = `rgba(0,0,0,${0.12 + k * 0.25})`; ctx.beginPath(); ctx.ellipse(p.x, p.y, 4, 3, 0, 0, TAU); ctx.fill();
    const a = p.kind === 'barrage' ? Math.atan2(700 * 0.55 / p.T, (p.tx - p.sx) / p.T) : Math.atan2((p.ty - p.sy) / p.T - (4 * p.h * (1 - 2 * k) / p.T) * 0.55, (p.tx - p.sx) / p.T);
    const sc = 1 + p.z / 900;
    ctx.save(); ctx.translate(p.x, zy); ctx.rotate(a); ctx.scale(sc, sc);
    if (p.kind === 'mrocket') {
      ctx.fillStyle = '#d9dcd5'; ctx.fillRect(-7, -1.6, 14, 3.2); ctx.fillStyle = TEAM[p.team].main; ctx.fillRect(5, -1.6, 3, 3.2);
    } else {
      ctx.globalCompositeOperation = 'lighter';
      ctx.strokeStyle = 'rgba(255,200,120,0.5)'; ctx.lineWidth = 2; ctx.beginPath(); ctx.moveTo(-14, 0); ctx.lineTo(0, 0); ctx.stroke();
      ctx.globalCompositeOperation = 'source-over';
      ctx.fillStyle = '#2b2b26'; ctx.beginPath(); ctx.ellipse(0, 0, 4.5, 2.2, 0, 0, TAU); ctx.fill();
    }
    ctx.restore();
  }
  for (const m of G.missiles) {
    if (m.dead) continue;
    const zy = m.y - m.z * 0.55;
    const k = m.t / m.T;
    ctx.fillStyle = `rgba(0,0,0,${0.15 + k * 0.3})`; ctx.beginPath(); ctx.ellipse(m.x, m.y, 10, 6, 0, 0, TAU); ctx.fill();
    const s = 1 + m.z / 700;
    const k2 = Math.min(1, k + 0.01);
    const nx = lerp(m.sx, m.tx, k2 * k2 * (3 - 2 * k2)), ny = lerp(m.sy, m.ty, k2 * k2 * (3 - 2 * k2)) - (4 * m.h * k2 * (1 - k2)) * 0.55;
    const a = Math.atan2(ny - zy, nx - m.x);
    ctx.save(); ctx.translate(m.x, zy); ctx.rotate(a); ctx.scale(s, s);
    ctx.fillStyle = '#eef0f2'; ctx.strokeStyle = INK; ctx.lineWidth = 1;
    ctx.beginPath(); ctx.moveTo(-14, -3); ctx.lineTo(9, -3); ctx.lineTo(15, 0); ctx.lineTo(9, 3); ctx.lineTo(-14, 3); ctx.closePath(); ctx.fill(); ctx.stroke();
    ctx.fillStyle = TEAM[m.team].main; ctx.fillRect(4, -3, 3, 6);
    ctx.fillStyle = INK; ctx.beginPath(); ctx.moveTo(-14, -3); ctx.lineTo(-9, -3); ctx.lineTo(-15, -8); ctx.closePath(); ctx.fill();
    ctx.beginPath(); ctx.moveTo(-14, 3); ctx.lineTo(-9, 3); ctx.lineTo(-15, 8); ctx.closePath(); ctx.fill();
    ctx.restore();
  }
}
function drawFog(view) {
  if (G.playerTeam < 0) return;
  const S = VIS_STAMP[G.playerTeam], E = EXPLORED[G.playerTeam], A = G.fogA, d = fogImg.data;
  if (G.frame !== G.fogFrame) {
    G.fogFrame = G.frame;
    for (let i = 0; i < A.length; i++) {
      const target = S[i] === visGen ? 0 : E[i] ? 0.5 : 0.86;
      A[i] += (target - A[i]) * 0.12;
      const o = i * 4; d[o] = 14; d[o + 1] = 15; d[o + 2] = 10; d[o + 3] = A[i] * 255;
    }
    fogCtx.putImageData(fogImg, 0, 0);
    if (fogBlurCtx) { fogBlurCtx.clearRect(0, 0, fogBlur.width, fogBlur.height); fogBlurCtx.drawImage(fogCv, 0, 0, fogBlur.width, fogBlur.height); }
  }
  ctx.imageSmoothingEnabled = true;
  ctx.drawImage(fogBlurCtx ? fogBlur : fogCv, 0, 0, W, H);
  // outside the map
  ctx.fillStyle = 'rgba(14,15,10,0.92)';
  if (view.x0 < 0) ctx.fillRect(view.x0 - 10, view.y0 - 10, -view.x0 + 10, view.y1 - view.y0 + 20);
  if (view.x1 > W) ctx.fillRect(W, view.y0 - 10, view.x1 - W + 10, view.y1 - view.y0 + 20);
  if (view.y0 < 0) ctx.fillRect(Math.max(0, view.x0), view.y0 - 10, Math.min(W, view.x1) - Math.max(0, view.x0), -view.y0 + 10);
  if (view.y1 > H) ctx.fillRect(Math.max(0, view.x0), H, Math.min(W, view.x1) - Math.max(0, view.x0), view.y1 - H + 10);
}
function drawNight(view) {
  const lg = lightCtx, z = G.cam.zoom, c = G.cam;
  const lw = lightCv.width, lh = lightCv.height;
  lg.setTransform(1, 0, 0, 1, 0, 0);
  lg.globalCompositeOperation = 'source-over';
  lg.fillStyle = G.night > 0.6 ? `rgba(4,9,26,${G.night})` : `rgba(40,22,40,${G.night})`;
  lg.fillRect(0, 0, lw, lh);
  lg.globalCompositeOperation = 'destination-out';
  lg.setTransform(z / 2, 0, 0, z / 2, (G.viewW / 2 - c.x * z) / 2, (G.viewH / 2 - c.y * z) / 2);
  const glow = FX.spr.glow;
  const L = (x, y, r, a) => { if (x + r < view.x0 || x - r > view.x1 || y + r < view.y0 || y - r > view.y1) return; lg.globalAlpha = a; lg.drawImage(glow, x - r, y - r, r * 2, r * 2); };
  for (const l of FX.lights) L(l.x, l.y, l.r * 1.4, l.i * (1 - l.t / l.life));
  for (const u of G.units) {
    if (!G.seen(u)) continue;
    if (u.cls === 'inf') L(u.x, u.y, 70, 0.55);
    else if (u.cls === 'veh') { L(u.x, u.y, 95, 0.7); L(u.x + Math.cos(u.ang) * 90, u.y + Math.sin(u.ang) * 90, 95, 0.8); }
    else L(u.x, u.y, u.type === 'hq' ? 340 : 120, 0.9);
  }
  for (const p of G.points) if (p.hall) L(p.x, p.y, 160, 0.6);
  for (const m of G.missiles) L(m.x, m.y - m.z * 0.55, 160, 1);
  lg.globalAlpha = 1;
  ctx.save(); ctx.setTransform(G.dpr, 0, 0, G.dpr, 0, 0);
  ctx.drawImage(lightCv, 0, 0, lw, lh, 0, 0, G.viewW, G.viewH);
  ctx.restore();
}
function drawWarnings(view) {
  for (const w of G.warnings) {
    const left = Math.max(0, w.T - w.t);
    const pulse = 0.5 + 0.5 * Math.sin(G.time * (w.kind === 'missile' ? 14 : 9));
    ctx.fillStyle = `rgba(255,40,30,${0.08 + pulse * 0.08})`; ctx.beginPath(); ctx.arc(w.x, w.y, w.r, 0, TAU); ctx.fill();
    ctx.strokeStyle = `rgba(255,70,50,${0.6 + pulse * 0.4})`; ctx.lineWidth = w.kind === 'missile' ? 4 : 2.5;
    ctx.setLineDash([16, 10]); ctx.lineDashOffset = G.time * 30;
    ctx.beginPath(); ctx.arc(w.x, w.y, w.r, 0, TAU); ctx.stroke(); ctx.setLineDash([]);
    const sweep = (1 - left / w.T) * TAU;
    ctx.lineWidth = 6; ctx.strokeStyle = 'rgba(255,200,60,0.85)'; ctx.beginPath(); ctx.arc(w.x, w.y, w.r + 10, -Math.PI / 2, -Math.PI / 2 + sweep); ctx.stroke();
    ctx.lineWidth = 2; ctx.strokeStyle = 'rgba(255,90,60,0.8)';
    ctx.beginPath(); ctx.moveTo(w.x - 20, w.y); ctx.lineTo(w.x + 20, w.y); ctx.moveTo(w.x, w.y - 20); ctx.lineTo(w.x, w.y + 20); ctx.stroke();
    if (w.kind === 'missile') {
      ctx.font = `700 ${Math.round(16 / G.cam.zoom)}px "Barlow Condensed", "Arial Narrow", sans-serif`; ctx.textAlign = 'center';
      ctx.fillStyle = '#ffdd55'; ctx.fillText(`⚠ IMPACT ${left.toFixed(1)}s`, w.x, w.y - w.r - 18 / G.cam.zoom);
    }
  }
}
// vehicles you can take, gun ranges, your marker and the mission waypoint
function drawAvatarAids(view, z) {
  const iz = 1 / z, me = G.me, t = G.time, a = avatar();
  // parked vehicles waiting for a driver
  for (const v of G.units) {
    if (!v.empty || v.dead || v.team !== 0 || v.x < view.x0 - 60 || v.x > view.x1 + 60 || v.y < view.y0 - 60 || v.y > view.y1 + 60) continue;
    ctx.strokeStyle = `rgba(255,255,255,${0.35 + 0.2 * Math.sin(t * 3)})`; ctx.lineWidth = 1.5 * iz; ctx.setLineDash([5 * iz, 5 * iz]);
    ctx.beginPath(); ctx.arc(v.x, v.y, v.def.len * 0.62, 0, TAU); ctx.stroke(); ctx.setLineDash([]);
  }
  if (!me.vehicle && !me.drone) {
    const v = nearestVehicle();
    if (v) {
      ctx.strokeStyle = '#f7d54a'; ctx.lineWidth = 2 * iz; ctx.beginPath(); ctx.arc(v.x, v.y, v.def.len * 0.66, 0, TAU); ctx.stroke();
      ctx.font = `700 ${Math.round(14 * iz)}px "Barlow Condensed", "Arial Narrow", sans-serif`; ctx.textAlign = 'center';
      const label = `E  ${v.empty ? 'Drive' : 'Take over'} ${v.def.name.toLowerCase()}`;
      ctx.fillStyle = 'rgba(0,0,0,0.7)'; ctx.fillText(label, v.x + 1 * iz, v.y - v.def.len * 0.7 - 6 * iz + 1 * iz);
      ctx.fillStyle = '#f7d54a'; ctx.fillText(label, v.x, v.y - v.def.len * 0.7 - 6 * iz);
    }
  }
  // the structure you're about to place
  const gs = !me.vehicle && ghostState();
  if (gs) {
    ctx.save(); ctx.translate(gs.x, gs.y);
    ctx.rotate(gs.st.len ? gs.ang : gs.st.id === 'bunker' ? gs.ang - Math.PI / 2 : 0);
    ctx.globalAlpha = 0.55;
    drawStruct(ctx, { type: gs.st.id, built: true, ang: 0, tang: 0, recoil: 0, r: UNITS[gs.st.id].r, stock: null }, gs.err ? { main: '#ff5040', dark: '#a02010' } : TEAM[0], t);
    ctx.globalAlpha = 1;
    ctx.strokeStyle = gs.err ? 'rgba(255,80,60,0.9)' : 'rgba(247,213,74,0.95)'; ctx.lineWidth = 2 * iz; ctx.setLineDash([6 * iz, 5 * iz]);
    if (gs.st.len) ctx.strokeRect(-gs.st.len / 2 - 6, -20, gs.st.len + 12, 40); else { ctx.beginPath(); ctx.arc(0, 0, UNITS[gs.st.id].r + 8, 0, TAU); ctx.stroke(); }
    ctx.setLineDash([]);
    if (gs.st.len) { ctx.fillStyle = 'rgba(255,90,60,0.8)'; ctx.beginPath(); ctx.moveTo(0, -28); ctx.lineTo(-6, -20); ctx.lineTo(6, -20); ctx.closePath(); ctx.fill(); } // the side that faces the enemy
    ctx.restore();
    ctx.font = `700 ${Math.round(13 * iz)}px "Barlow Condensed", "Arial Narrow", sans-serif`; ctx.textAlign = 'center';
    const lbl = gs.err || `${gs.st.name} · ${gs.st.cost} bmats from ${gs.pay.label} · click to place, R to turn`;
    ctx.fillStyle = 'rgba(0,0,0,0.75)'; ctx.fillText(lbl, gs.x + iz, gs.y + 44 * iz + iz);
    ctx.fillStyle = gs.err ? '#ffb0a6' : '#f7d54a'; ctx.fillText(lbl, gs.x, gs.y + 44 * iz);
  }
  if (me.look) {
    ctx.strokeStyle = 'rgba(255,230,160,0.6)'; ctx.lineWidth = 2 * iz;
    ctx.beginPath(); ctx.arc(me.look.x, me.look.y, 200, 0, TAU); ctx.stroke();
  }
  // artillery ranges when you drive a gun truck
  const v = me.vehicle;
  if (v && v.weapons[0] && v.weapons[0].def.arty) {
    const w = v.weapons[0].def;
    ctx.strokeStyle = 'rgba(247,213,74,0.25)'; ctx.lineWidth = 1.5 * iz; ctx.setLineDash([10 * iz, 8 * iz]);
    ctx.beginPath(); ctx.arc(v.x, v.y, w.range, 0, TAU); ctx.stroke();
    ctx.strokeStyle = 'rgba(255,90,60,0.25)'; ctx.beginPath(); ctx.arc(v.x, v.y, w.min, 0, TAU); ctx.stroke(); ctx.setLineDash([]);
    const m = G.mouse, d = dist(v.x, v.y, m.wx, m.wy), rr = d * w.scatter + w.splash;
    ctx.strokeStyle = d <= w.range && d >= w.min ? 'rgba(255,210,90,0.85)' : 'rgba(255,80,60,0.6)';
    ctx.beginPath(); ctx.arc(m.wx, m.wy, rr, 0, TAU); ctx.stroke();
  }
  // your marker
  const top = a.y - (a.cls === 'veh' ? a.def.wid * 0.5 + 22 : 30);
  ctx.fillStyle = '#f7d54a'; ctx.strokeStyle = 'rgba(0,0,0,0.6)'; ctx.lineWidth = 1.5 * iz;
  const s = 6 * iz, by = top + Math.sin(t * 4) * 2 * iz;
  ctx.beginPath(); ctx.moveTo(a.x - s, by - s); ctx.lineTo(a.x + s, by - s); ctx.lineTo(a.x, by + s * 0.4); ctx.closePath(); ctx.fill(); ctx.stroke();
  // mission waypoint
  const m = me.mission;
  if (m) {
    const tg = missionTarget(m);
    if (tg) {
      const pr = 0.5 + 0.5 * Math.sin(t * 3);
      ctx.strokeStyle = `rgba(247,213,74,${0.5 + pr * 0.4})`; ctx.lineWidth = 3 * iz;
      const r = (tg.r && !tg.def ? tg.r + 30 : 40) + pr * 6;
      ctx.beginPath(); ctx.arc(tg.x, tg.y, r, 0, TAU); ctx.stroke();
      for (let k = 0; k < 4; k++) { const an = k * Math.PI / 2 + t * 0.6; ctx.beginPath(); ctx.moveTo(tg.x + Math.cos(an) * (r + 6), tg.y + Math.sin(an) * (r + 6)); ctx.lineTo(tg.x + Math.cos(an) * (r + 22 * iz), tg.y + Math.sin(an) * (r + 22 * iz)); ctx.stroke(); }
    }
  }
}
// crosshair, hit marker and the red edge when you get hurt (screen space)
function drawCrosshair() {
  const me = G.me, m = G.mouse;
  const hurt = clamp(1 - (G.time - me.hurtT) / 0.6, 0, 1);
  if (hurt > 0 && me.alive) {
    const g = ctx.createRadialGradient(G.viewW / 2, G.viewH / 2, Math.min(G.viewW, G.viewH) * 0.35, G.viewW / 2, G.viewH / 2, Math.max(G.viewW, G.viewH) * 0.7);
    g.addColorStop(0, 'rgba(200,0,0,0)'); g.addColorStop(1, `rgba(200,0,0,${0.35 * hurt})`);
    ctx.fillStyle = g; ctx.fillRect(0, 0, G.viewW, G.viewH);
  }
  const st = G.touch && G.touch.stick;
  if (st) {
    ctx.fillStyle = 'rgba(255,255,255,0.08)'; ctx.strokeStyle = 'rgba(255,255,255,0.35)'; ctx.lineWidth = 2;
    ctx.beginPath(); ctx.arc(st.x, st.y, 50, 0, TAU); ctx.fill(); ctx.stroke();
    ctx.fillStyle = 'rgba(247,213,74,0.6)'; ctx.beginPath(); ctx.arc(st.x + st.dx, st.y + st.dy, 20, 0, TAU); ctx.fill();
  }
  if (!me.alive || !m.in || m.overHud || G.mode !== 'play') return;
  const s = me.soldier, gun = s && s.gun;
  let gap = 6, col = '#f2f2ea';
  if (!me.vehicle && gun && me.tool === 'gun') {
    gap = 3 + mySpread() * 150;
    if (gun.reloadT > 0) col = 'rgba(255,255,255,0.4)';
    else if (me.aiming && me.aimT > 0.95) col = '#f7d54a';
  } else if (!me.vehicle) { gap = 4; col = me.tool === 'hammer' ? '#f7d54a' : '#ffe6a0'; }
  ctx.strokeStyle = 'rgba(0,0,0,0.6)'; ctx.lineWidth = 3.5;
  const cross = () => { ctx.beginPath(); for (const [dx, dy] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) { ctx.moveTo(m.x + dx * gap, m.y + dy * gap); ctx.lineTo(m.x + dx * (gap + 7), m.y + dy * (gap + 7)); } ctx.stroke(); };
  cross(); ctx.strokeStyle = col; ctx.lineWidth = 1.6; cross();
  if (!me.vehicle && gun && gun.reloadT > 0) {
    ctx.strokeStyle = '#f7d54a'; ctx.lineWidth = 2.5; ctx.beginPath(); ctx.arc(m.x, m.y, gap + 12, -Math.PI / 2, -Math.PI / 2 + TAU * (1 - gun.reloadT / gun.def.reload)); ctx.stroke();
  }
  const hit = clamp(1 - (G.time - me.hitT) / 0.25, 0, 1);
  if (hit > 0) {
    ctx.strokeStyle = `rgba(255,90,60,${hit})`; ctx.lineWidth = 2.2; ctx.beginPath();
    for (const [dx, dy] of [[1, 1], [-1, 1], [1, -1], [-1, -1]]) { ctx.moveTo(m.x + dx * 4, m.y + dy * 4); ctx.lineTo(m.x + dx * 10, m.y + dy * 10); }
    ctx.stroke();
  }
}
function drawOverlays(view, z) {
  const iz = 1 / z;
  const pt = G.playerTeam;
  // your squad
  ctx.lineWidth = 1.6 * iz;
  if (G.me && G.me.alive) drawAvatarAids(view, z);
  for (const u of G.sel) {
    if (u.dead) continue;
    const r = (u.cls === 'veh' ? u.def.len * 0.62 : u.cls === 'bld' ? u.r + 12 : u.r + 4);
    ctx.strokeStyle = 'rgba(247,213,74,0.95)';
    ctx.beginPath(); ctx.arc(u.x, u.y, r, 0, TAU); ctx.stroke();
    if (u.order && u.path && u.path.length && z > 0.3 && G.sel.size <= 6) {
      ctx.strokeStyle = u.order.type === 'amove' ? 'rgba(255,140,90,0.35)' : 'rgba(170,255,140,0.3)'; ctx.setLineDash([4 * iz, 6 * iz]);
      ctx.beginPath(); ctx.moveTo(u.x, u.y); for (let i = u.pi; i < u.path.length; i++) ctx.lineTo(u.path[i].x, u.path[i].y); ctx.stroke(); ctx.setLineDash([]);
    }
    if (u.order && u.order.type === 'attack' && u.order.target && !u.order.target.dead && G.sel.size <= 6) {
      ctx.strokeStyle = 'rgba(255,80,60,0.45)'; ctx.setLineDash([4 * iz, 6 * iz]); ctx.beginPath(); ctx.moveTo(u.x, u.y); ctx.lineTo(u.order.target.x, u.order.target.y); ctx.stroke(); ctx.setLineDash([]);
    }
  }
  // health bars
  if (z > 0.38) {
    for (const u of G.units) {
      if (u.x < view.x0 - 60 || u.x > view.x1 + 60 || u.y < view.y0 - 60 || u.y > view.y1 + 60 || !G.seen(u) || u.inside) continue;
      const st = u.def.struct;
      const show = G.sel.has(u) || u === G.hover || (u.hp < u.maxHp && (u.cls !== 'inf' || z > 1.15)) || (u.cls === 'bld' && !st) || !u.built;
      if (!show || (st && u.built && z < 0.7)) continue;
      const w = u.cls === 'inf' ? 18 : u.cls === 'bld' ? (u.type === 'hq' ? 150 : st ? 34 : 56) : u.def.len * 0.9;
      const y = u.y - (u.cls === 'inf' ? u.r + 7 : u.def.line ? 26 : u.cls === 'bld' ? u.r + 16 : u.def.wid * 0.5 + 10);
      const k = u.built ? u.hp / u.maxHp : u.bp / u.bpNeed;
      ctx.fillStyle = 'rgba(0,0,0,0.6)'; ctx.fillRect(u.x - w / 2 - 1, y - 1, w + 2, u.cls === 'bld' ? 6 : 4);
      ctx.fillStyle = !u.built ? '#f7d54a' : k > 0.6 ? '#7be35a' : k > 0.3 ? '#f2c53d' : '#ef4b3a';
      ctx.fillRect(u.x - w / 2, y, w * k, u.cls === 'bld' ? 4 : 2);
      if (u.rank) { ctx.fillStyle = '#f7d54a'; for (let i = 0; i < u.rank; i++) { ctx.beginPath(); const cx = u.x + w / 2 + 4 + i * 5, cy = y + 1; ctx.moveTo(cx - 2, cy - 2); ctx.lineTo(cx, cy); ctx.lineTo(cx + 2, cy - 2); ctx.lineTo(cx + 2, cy); ctx.lineTo(cx, cy + 2); ctx.lineTo(cx - 2, cy); ctx.closePath(); ctx.fill(); } }
      if (u.def.ability && u.team === pt && (G.sel.has(u)) && u.abilityCd > 0) {
        const cd = ABILITIES[u.def.ability].cd;
        ctx.fillStyle = 'rgba(120,200,255,0.9)'; ctx.fillRect(u.x - w / 2, y + 3, w * (1 - u.abilityCd / cd), 1.5);
      }
    }
  }
  // hovered enemy
  if (G.hover && G.hover.team !== pt && pt >= 0) {
    const u = G.hover; const r = (u.cls === 'veh' ? u.def.len * 0.62 : u.r + 5);
    ctx.strokeStyle = 'rgba(255,80,60,0.9)'; ctx.lineWidth = 1.6 * iz; ctx.beginPath(); ctx.arc(u.x, u.y, r, 0, TAU); ctx.stroke();
  }
  // order markers
  for (const m of G.markers) {
    const k = m.t / 0.8;
    ctx.strokeStyle = m.color.replace('A', String(1 - k)); ctx.lineWidth = 2 * iz;
    ctx.beginPath(); ctx.arc(m.x, m.y, (6 + k * 18) * iz, 0, TAU); ctx.stroke();
    ctx.beginPath(); ctx.arc(m.x, m.y, 3 * iz * (1 - k), 0, TAU); ctx.stroke();
  }
  // ability aiming
  if (G.aim) {
    const A = ABILITIES[G.aim.ab];
    const casters = [...G.sel].filter((u) => !u.dead && u.def.ability === G.aim.ab);
    ctx.lineWidth = 1.5 * iz; ctx.setLineDash([8 * iz, 8 * iz]);
    for (const u of casters) { ctx.strokeStyle = u.abilityCd > 0 ? 'rgba(255,255,255,0.18)' : 'rgba(120,200,255,0.5)'; ctx.beginPath(); ctx.arc(u.x, u.y, A.range, 0, TAU); ctx.stroke(); }
    ctx.setLineDash([]);
    const m = G.mouse;
    if (A.radius) { ctx.fillStyle = 'rgba(255,90,60,0.15)'; ctx.strokeStyle = 'rgba(255,120,80,0.9)'; ctx.beginPath(); ctx.arc(m.wx, m.wy, A.radius, 0, TAU); ctx.fill(); ctx.stroke(); }
    else { ctx.strokeStyle = 'rgba(120,200,255,0.9)'; ctx.beginPath(); ctx.arc(m.wx, m.wy, 14 * iz, 0, TAU); ctx.moveTo(m.wx - 20 * iz, m.wy); ctx.lineTo(m.wx + 20 * iz, m.wy); ctx.moveTo(m.wx, m.wy - 20 * iz); ctx.lineTo(m.wx, m.wy + 20 * iz); ctx.stroke(); }
  }
  // town names (always readable)
  ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
  const fs = clamp(17 * iz, 17, 56);
  ctx.font = `700 ${fs}px "Saira Stencil One", Impact, sans-serif`;
  for (const p of G.points) {
    const y = p.y + p.r + fs * 0.8;
    const label = z < 0.3 ? p.letter : p.name.toUpperCase();
    ctx.fillStyle = 'rgba(0,0,0,0.55)'; ctx.fillText(label, p.x + 2 * iz, y + 2 * iz);
    ctx.fillStyle = p.owner === 0 ? TEAM[0].light : p.owner === 1 ? TEAM[1].light : '#f0efe6';
    ctx.fillText(label, p.x, y);
    if (!p.hall && z >= 0.3) {
      ctx.font = `600 ${Math.round(fs * 0.62)}px "Barlow Condensed", "Arial Narrow", sans-serif`;
      ctx.fillStyle = 'rgba(240,235,215,0.8)'; ctx.fillText('NO TOWN HALL', p.x, y + fs * 0.85);
      ctx.font = `700 ${fs}px "Saira Stencil One", Impact, sans-serif`;
    }
  }
  ctx.textBaseline = 'alphabetic';
}

// ---------------------------------------------------------------------
// minimap
// ---------------------------------------------------------------------
let minimapBase = null;
function drawMinimap() {
  const cv = $('minimap'); if (!cv || cv.offsetParent === null) return;
  const mw = cv.clientWidth, mh = cv.clientHeight; if (!mw) return;
  const dpr = G.dpr;
  if (cv.width !== Math.round(mw * dpr)) { cv.width = Math.round(mw * dpr); cv.height = Math.round(mh * dpr); minimapBase = null; }
  const g = cv.getContext('2d');
  if (!minimapBase) {
    minimapBase = document.createElement('canvas'); minimapBase.width = cv.width; minimapBase.height = cv.height;
    const b = minimapBase.getContext('2d'); b.drawImage(MAP.ground, 0, 0, cv.width, cv.height); b.drawImage(MAP.canopyLow, 0, 0, cv.width, cv.height);
  }
  if (G.frame % 50 === 0) { const b = minimapBase.getContext('2d'); b.drawImage(MAP.ground, 0, 0, cv.width, cv.height); b.globalAlpha = 0.85; b.drawImage(MAP.canopyLow, 0, 0, cv.width, cv.height); b.globalAlpha = 1; }
  g.setTransform(1, 0, 0, 1, 0, 0);
  g.drawImage(minimapBase, 0, 0);
  const sx = cv.width / W, sy = cv.height / H;
  if (G.playerTeam >= 0) { g.globalAlpha = 0.9; g.imageSmoothingEnabled = true; g.drawImage(fogBlurCtx ? fogBlur : fogCv, 0, 0, cv.width, cv.height); g.globalAlpha = 1; }
  g.fillStyle = 'rgba(200,120,60,0.8)';
  for (const f of MAP.scrap) { g.beginPath(); g.arc(f.x * sx, f.y * sy, 2.2 * dpr, 0, TAU); g.fill(); }
  for (const p of G.points) {
    g.fillStyle = p.owner === 0 ? TEAM[0].main : p.owner === 1 ? TEAM[1].main : '#e8e8e0';
    g.strokeStyle = '#000'; g.lineWidth = 1.5 * dpr;
    g.beginPath(); g.rect(p.x * sx - 5 * dpr, p.y * sy - 5 * dpr, 10 * dpr, 10 * dpr); g.fill(); g.stroke();
  }
  for (const u of G.units) {
    if (!G.seen(u) || u.inside) continue;
    g.fillStyle = u.avatar || (G.me && u === G.me.vehicle) ? '#f7d54a' : u.team === 0 ? '#5cbcff' : '#ff6455';
    if (u.def.line || u.type === 'trap') continue;
    const s = (u.cls === 'inf' ? 1.6 : u.cls === 'bld' ? (u.def.struct ? 2.5 : 5) : 3) * dpr;
    g.fillRect(u.x * sx - s / 2, u.y * sy - s / 2, s, s);
  }
  for (const w of G.warnings) { g.strokeStyle = `rgba(255,60,40,${0.5 + 0.5 * Math.sin(G.time * 10)})`; g.lineWidth = 2 * dpr; g.beginPath(); g.arc(w.x * sx, w.y * sy, Math.max(5 * dpr, w.r * sx), 0, TAU); g.stroke(); }
  for (const p of G.pings) { const k = p.t / 3; g.strokeStyle = `rgba(${p.rgb},${1 - k})`; g.lineWidth = 2 * dpr; g.beginPath(); g.arc(p.x * sx, p.y * sy, (4 + k * 18) * dpr, 0, TAU); g.stroke(); }
  const v = G.view; if (v) { g.strokeStyle = 'rgba(255,255,255,0.85)'; g.lineWidth = 1.2 * dpr; g.strokeRect(v.x0 * sx, v.y0 * sy, (v.x1 - v.x0) * sx, (v.y1 - v.y0) * sy); }
}

// ---------------------------------------------------------------------
// notifications
// ---------------------------------------------------------------------
let lastAttackNote = -99;
function notify(text, kind, x, y) {
  if (G.quiet || G.mode === 'menu') return;
  const feed = $('feed');
  const el = document.createElement('button');
  el.className = 'note ' + (kind || 'info');
  el.textContent = text;
  if (x != null) { el.onclick = () => { G.cam.x = x; G.cam.y = y; }; G.pings.push({ x, y, t: 0, rgb: kind === 'bad' || kind === 'warn' ? '255,80,60' : kind === 'good' ? '140,255,120' : '255,255,255' }); }
  feed.prepend(el);
  while (feed.children.length > 6) feed.lastChild.remove();
  setTimeout(() => { el.classList.add('fade'); setTimeout(() => el.remove(), 600); }, 6500);
}
function underAttack(u) {
  if (G.time - lastAttackNote < 12) return;
  const s = worldToScreen(u.x, u.y);
  if (s.x > 0 && s.y > 0 && s.x < G.viewW && s.y < G.viewH) return;
  lastAttackNote = G.time;
  notify("You're under fire!", 'warn', u.x, u.y);
  Sound.play('alert', 0.35);
}
let lossNoteT = -99;
function lossFeed(u) {
  if (G.time - lossNoteT < 3) return;
  lossNoteT = G.time;
  notify(u.cls === 'inf' ? `${u.def.name} down` : `${u.def.name} destroyed`, 'bad', u.x, u.y);
}

