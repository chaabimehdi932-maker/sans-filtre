'use strict';
// =====================================================================
// Visual effects: particles, tracers, explosions, ground decals, lights
// =====================================================================

const FX = {
  parts: [], tracers: [], rings: [], lights: [], texts: [], emitters: [],
  max: 4200, shake: 0, flash: 0, wind: { x: 9, y: -4 },
  spr: {},
};

function makeFxSprites() {
  const mk = (size, fn) => { const c = document.createElement('canvas'); c.width = c.height = size; fn(c.getContext('2d'), size / 2); return c; };
  const radial = (stops) => (g, r) => { const gr = g.createRadialGradient(r, r, 0, r, r, r); for (const [o, c] of stops) gr.addColorStop(o, c); g.fillStyle = gr; g.fillRect(0, 0, r * 2, r * 2); };
  FX.spr.glow = mk(64, radial([[0, 'rgba(255,255,255,1)'], [0.25, 'rgba(255,255,255,0.55)'], [1, 'rgba(255,255,255,0)']]));
  FX.spr.fire = mk(64, radial([[0, 'rgba(255,250,215,1)'], [0.2, 'rgba(255,214,110,0.95)'], [0.5, 'rgba(255,120,30,0.6)'], [1, 'rgba(200,40,10,0)']]));
  FX.spr.flash = mk(128, radial([[0, 'rgba(255,255,240,1)'], [0.15, 'rgba(255,230,160,0.9)'], [0.45, 'rgba(255,150,60,0.35)'], [1, 'rgba(255,100,30,0)']]));
  const puff = (r, g0, b0, a0) => (g, h) => {
    for (let i = 0; i < 9; i++) {
      const x = h + rand(-h * 0.35, h * 0.35), y = h + rand(-h * 0.35, h * 0.35), rr = rand(h * 0.35, h * 0.62);
      const gr = g.createRadialGradient(x, y, 0, x, y, rr);
      const s = rand(-14, 14);
      gr.addColorStop(0, `rgba(${r + s},${g0 + s},${b0 + s},${a0})`); gr.addColorStop(1, `rgba(${r + s},${g0 + s},${b0 + s},0)`);
      g.fillStyle = gr; g.beginPath(); g.arc(x, y, rr, 0, TAU); g.fill();
    }
  };
  FX.spr.smoke = mk(96, puff(120, 120, 118, 0.5));
  FX.spr.dark = mk(96, puff(40, 38, 36, 0.6));
  FX.spr.dust = mk(96, puff(150, 130, 92, 0.45));
  FX.spr.white = mk(96, puff(225, 225, 220, 0.45));
  FX.spr.water = mk(64, radial([[0, 'rgba(210,235,255,0.9)'], [0.5, 'rgba(150,200,235,0.5)'], [1, 'rgba(120,180,220,0)']]));
}

// ---------------------------------------------------------------------
// particles
// kind: sprite name. add: additive blend. z/vz: height for debris
// ---------------------------------------------------------------------
function part(o) {
  if (FX.parts.length >= FX.max) { if (!o.important) return; FX.parts.splice(0, 1); }
  o.t = 0;
  o.vx = o.vx || 0; o.vy = o.vy || 0; o.z = o.z || 0; o.vz = o.vz || 0;
  o.a0 = o.a0 == null ? 1 : o.a0;
  o.s1 = o.s1 == null ? o.s0 : o.s1;
  o.drag = o.drag == null ? 1 : o.drag;
  FX.parts.push(o);
  return o;
}
function tracer(x0, y0, x1, y1, color, width, speed, len) {
  const d = dist(x0, y0, x1, y1) || 1;
  FX.tracers.push({ x0, y0, x1, y1, d, p: 0, speed: speed || 2600, len: Math.min(len || 70, d), color, width: width || 1.6 });
}
function ring(x, y, r0, r1, life, color, width) { FX.rings.push({ x, y, r0, r1, t: 0, life, color, width: width || 3 }); }
function light(x, y, r, life, intensity, color) { FX.lights.push({ x, y, r, t: 0, life, i: intensity == null ? 1 : intensity, color: color || '255,200,120' }); }
function floatText(x, y, text, color) { FX.texts.push({ x, y, text, color: color || '#fff', t: 0, life: 1.4 }); }
function shake(x, y, amt) {
  if (G.reduceMotion) return;
  const cam = G.cam; const vw = G.viewW / cam.zoom;
  const d = dist(x, y, cam.x, cam.y) / vw;
  FX.shake = Math.min(26, FX.shake + amt * clamp(1.2 - d, 0, 1));
}

function smoke(x, y, s, dark, life) {
  part({ kind: dark ? 'dark' : 'smoke', x: x + rand(-4, 4) * s, y: y + rand(-4, 4) * s, vx: rand(-8, 8) + FX.wind.x * 0.4, vy: rand(-8, 8) + FX.wind.y * 0.4, life: life || rand(2, 4), s0: 10 * s, s1: rand(30, 46) * s, a0: rand(0.35, 0.6), drag: 0.985, rot: rand(0, TAU), vr: rand(-0.5, 0.5) });
}
function fire(x, y, s, life) {
  part({ kind: 'fire', add: true, x, y, vx: rand(-18, 18) * s, vy: rand(-18, 18) * s, life: life || rand(0.25, 0.6), s0: rand(10, 18) * s, s1: rand(2, 6) * s, a0: 1, drag: 0.94 });
}
function sparks(x, y, n, spd, ang, spread, color) {
  for (let i = 0; i < n; i++) {
    const a = ang == null ? rand(0, TAU) : ang + rand(-spread, spread);
    const v = rand(0.3, 1) * spd;
    part({ kind: 'spark', add: true, x, y, vx: Math.cos(a) * v, vy: Math.sin(a) * v, life: rand(0.15, 0.5), s0: rand(1, 2.2), color: color || '255,210,120', drag: 0.9 });
  }
}
function debris(x, y, n, spd, color) {
  for (let i = 0; i < n; i++) {
    const a = rand(0, TAU), v = rand(0.3, 1) * spd;
    part({ kind: 'chunk', x, y, vx: Math.cos(a) * v, vy: Math.sin(a) * v, vz: rand(80, 260) * (spd / 200), life: rand(0.8, 1.6), s0: rand(2, 4.5), color: color || '#2a2620', drag: 0.985, rot: rand(0, TAU), vr: rand(-10, 10) });
  }
}
function dust(x, y, s, life) {
  part({ kind: 'dust', x: x + rand(-3, 3), y: y + rand(-3, 3), vx: rand(-12, 12) * s, vy: rand(-12, 12) * s, life: life || rand(0.6, 1.4), s0: 6 * s, s1: rand(18, 26) * s, a0: rand(0.3, 0.5), drag: 0.96, rot: rand(0, TAU) });
}
function muzzle(x, y, ang, size) {
  part({ kind: 'flash', add: true, x: x + Math.cos(ang) * 3 * size, y: y + Math.sin(ang) * 3 * size, life: 0.06, s0: 16 * size, s1: 10 * size });
  for (let i = 0; i < 2; i++) {
    const a = ang + rand(-0.25, 0.25);
    part({ kind: 'fire', add: true, x, y, vx: Math.cos(a) * 160 * size, vy: Math.sin(a) * 160 * size, life: 0.07, s0: 7 * size, s1: 3 * size, drag: 0.8 });
  }
  if (G.night > 0) light(x, y, 50 * size, 0.08, 0.9);
}

// splash of water when something lands in the river
function waterSplash(x, y, s) {
  for (let i = 0; i < 10 * s; i++) part({ kind: 'water', x, y, vx: rand(-60, 60) * s, vy: rand(-60, 60) * s, life: rand(0.4, 0.9), s0: 8 * s, s1: 26 * s, a0: 0.8, drag: 0.93 });
  ring(x, y, 4, 40 * s, 0.7, '200,230,255', 2);
  part({ kind: 'white', x, y, life: 1.6, s0: 14 * s, s1: 40 * s, a0: 0.5 });
}

// explosion. size: 1 grenade .. 3 artillery .. 5 vehicle .. 10 missile
function explode(x, y, size, opts = {}) {
  const t = terrAt(x, y);
  if (t === T_WATER && size < 8) { waterSplash(x, y, size * 0.7); Sound.at(size > 2 ? 'boom' : 'small', x, y, 0.6 * Math.min(1, size / 3)); shake(x, y, size * 1.2); return; }
  const s = size;
  part({ kind: 'flash', add: true, x, y, life: 0.12 + s * 0.02, s0: 50 * s, s1: 70 * s, important: true });
  light(x, y, 90 + s * 55, 0.35 + s * 0.05, 1);
  for (let i = 0; i < 6 + s * 5; i++) {
    const a = rand(0, TAU), v = rand(10, 70) * Math.sqrt(s);
    part({ kind: 'fire', add: true, x: x + Math.cos(a) * rand(0, 6) * s, y: y + Math.sin(a) * rand(0, 6) * s, vx: Math.cos(a) * v, vy: Math.sin(a) * v, life: rand(0.3, 0.7) + s * 0.04, s0: rand(14, 26) * Math.sqrt(s), s1: rand(4, 8), drag: 0.93 });
  }
  for (let i = 0; i < 4 + s * 3; i++) {
    const a = rand(0, TAU), v = rand(10, 40) * Math.sqrt(s);
    part({ kind: i % 3 === 0 ? 'dark' : 'smoke', x: x + Math.cos(a) * 8 * s, y: y + Math.sin(a) * 8 * s, vx: Math.cos(a) * v + FX.wind.x, vy: Math.sin(a) * v + FX.wind.y, life: rand(2.2, 4.5) + s * 0.25, s0: 14 * Math.sqrt(s), s1: rand(40, 70) * Math.sqrt(s), a0: rand(0.45, 0.7), drag: 0.975, rot: rand(0, TAU), vr: rand(-0.4, 0.4) });
  }
  for (let i = 0; i < 3 + s * 2; i++) dust(x + rand(-10, 10) * s, y + rand(-10, 10) * s, Math.sqrt(s) * 1.4, rand(1, 2));
  sparks(x, y, 8 + s * 5, 260 + s * 40);
  debris(x, y, 3 + s * 2, 120 + s * 25, t === T_FOREST ? '#1b3a14' : '#2c2416');
  ring(x, y, 6, 26 * s + 20, 0.32 + s * 0.03, '255,240,210', 2 + s * 0.6);
  if (s >= 4) ring(x, y, 10, 50 * s, 0.6 + s * 0.04, '255,255,255', 4);
  if (!opts.noCrater) decalCrater(x, y, 8 + s * 7, s);
  shake(x, y, s * (s >= 6 ? 3.2 : 1.6));
  if (s >= 8) FX.flash = Math.max(FX.flash, 0.75);
  if (!opts.silent) Sound.at(s >= 8 ? 'huge' : s >= 2 ? 'boom' : 'small', x, y, clamp(0.45 + s * 0.12, 0.4, 1.2));
}

// burning wreck / long fire source
function emitter(x, y, life, size, opts = {}) { FX.emitters.push({ x, y, t: 0, life, size, acc: 0, fireOnly: opts.fireOnly, follow: opts.follow }); }

function updateFx(dt) {
  if (G.night > 0) for (const e of FX.emitters) if (e.t < e.life * 0.8) light(e.x, e.y, 70 * e.size, dt * 1.6, 0.55);
  for (let i = FX.emitters.length - 1; i >= 0; i--) {
    const e = FX.emitters[i]; e.t += dt; e.acc += dt;
    if (e.follow && !e.follow.dead) { e.x = e.follow.x; e.y = e.follow.y; }
    const k = 1 - e.t / e.life;
    while (e.acc > 0.08) {
      e.acc -= 0.08;
      if (k > 0.25 && Math.random() < 0.9) fire(e.x + rand(-6, 6) * e.size, e.y + rand(-6, 6) * e.size, e.size * 0.8 * (0.5 + k), rand(0.3, 0.6));
      if (!e.fireOnly && Math.random() < 0.55) {
        part({ kind: Math.random() < 0.6 ? 'dark' : 'smoke', x: e.x + rand(-4, 4), y: e.y + rand(-4, 4), vx: FX.wind.x * 2 + rand(-6, 6), vy: FX.wind.y * 2 + rand(-6, 6), life: rand(2.5, 4.5), s0: 8 * e.size, s1: rand(34, 56) * e.size * (0.4 + k * 0.6), a0: 0.5 * (0.3 + k), drag: 0.995, rot: rand(0, TAU), vr: rand(-0.3, 0.3) });
      }
    }
    if (e.t >= e.life || (e.follow && e.follow.dead && !e.follow.wreck)) FX.emitters.splice(i, 1);
  }
  const P = FX.parts;
  let j = 0;
  for (let i = 0; i < P.length; i++) {
    const p = P[i];
    p.t += dt;
    if (p.t >= p.life) continue;
    p.x += p.vx * dt; p.y += p.vy * dt;
    if (p.drag !== 1) { const d = Math.pow(p.drag, dt * 60); p.vx *= d; p.vy *= d; }
    if (p.vr) p.rot += p.vr * dt;
    if (p.kind === 'chunk') {
      p.z += p.vz * dt; p.vz -= 520 * dt;
      if (p.z < 0) { p.z = 0; p.vz = -p.vz * 0.3; p.vx *= 0.5; p.vy *= 0.5; }
    }
    P[j++] = p;
  }
  P.length = j;
  for (let i = FX.tracers.length - 1; i >= 0; i--) { const t = FX.tracers[i]; t.p += t.speed * dt; if (t.p - t.len > t.d) FX.tracers.splice(i, 1); }
  for (let i = FX.rings.length - 1; i >= 0; i--) { const r = FX.rings[i]; r.t += dt; if (r.t > r.life) FX.rings.splice(i, 1); }
  for (let i = FX.lights.length - 1; i >= 0; i--) { const l = FX.lights[i]; l.t += dt; if (l.t > l.life) FX.lights.splice(i, 1); }
  for (let i = FX.texts.length - 1; i >= 0; i--) { const t = FX.texts[i]; t.t += dt; t.y -= 22 * dt; if (t.t > t.life) FX.texts.splice(i, 1); }
  FX.shake *= Math.pow(0.0025, dt);
  FX.flash *= Math.pow(0.02, dt);
}

// pass 0: ground-level normal particles (dust, debris, splashes)
// pass 1: high normal particles (smoke) — drawn above the tree canopy
// pass 2: every additive particle (fire, flashes, sparks)
function drawParticles(ctx, view, pass) {
  const P = FX.parts;
  ctx.globalCompositeOperation = pass === 2 ? 'lighter' : 'source-over';
  for (let i = 0; i < P.length; i++) {
    const p = P[i];
    if (pass === 2) { if (!p.add) continue; }
    else {
      if (p.add) continue;
      const isLow = p.kind === 'dust' || p.kind === 'chunk' || p.kind === 'water';
      if ((pass === 0) !== isLow) continue;
    }
    if (p.x < view.x0 - 90 || p.x > view.x1 + 90 || p.y < view.y0 - 90 || p.y > view.y1 + 90) continue;
    const k = p.t / p.life;
    if (p.kind === 'spark') {
      ctx.strokeStyle = `rgba(${p.color},${1 - k})`; ctx.lineWidth = p.s0;
      ctx.beginPath(); ctx.moveTo(p.x, p.y); ctx.lineTo(p.x - p.vx * 0.035, p.y - p.vy * 0.035); ctx.stroke();
      continue;
    }
    if (p.kind === 'chunk') {
      ctx.globalAlpha = 0.35 * (1 - k); ctx.fillStyle = '#000'; ctx.fillRect(p.x - p.s0 / 2 + p.z * 0.3, p.y - p.s0 / 2 + p.z * 0.4, p.s0, p.s0);
      ctx.globalAlpha = 1 - k * k; ctx.fillStyle = p.color;
      ctx.save(); ctx.translate(p.x, p.y - p.z * 0.6); ctx.rotate(p.rot); ctx.fillRect(-p.s0 / 2, -p.s0 / 2, p.s0, p.s0); ctx.restore();
      continue;
    }
    const s = lerp(p.s0, p.s1, p.kind === 'fire' || p.kind === 'flash' || p.kind === 'glow' ? k : 1 - (1 - k) * (1 - k));
    let a = p.a0;
    if (p.kind === 'smoke' || p.kind === 'dark' || p.kind === 'dust' || p.kind === 'white' || p.kind === 'water') a *= k < 0.1 ? k / 0.1 : 1 - (k - 0.1) / 0.9;
    else a *= 1 - k;
    if (a <= 0.01 || s <= 0.2) continue;
    ctx.globalAlpha = a;
    const img = FX.spr[p.kind];
    if (p.rot) { ctx.save(); ctx.translate(p.x, p.y); ctx.rotate(p.rot); ctx.drawImage(img, -s, -s, s * 2, s * 2); ctx.restore(); }
    else ctx.drawImage(img, p.x - s, p.y - s, s * 2, s * 2);
  }
  ctx.globalAlpha = 1;
  ctx.globalCompositeOperation = 'source-over';
}

function drawTracers(ctx) {
  ctx.globalCompositeOperation = 'lighter';
  ctx.lineCap = 'round';
  for (const t of FX.tracers) {
    const a = clamp(t.p / t.d, 0, 1), b = clamp((t.p - t.len) / t.d, 0, 1);
    const x1 = lerp(t.x0, t.x1, a), y1 = lerp(t.y0, t.y1, a), x0 = lerp(t.x0, t.x1, b), y0 = lerp(t.y0, t.y1, b);
    ctx.strokeStyle = `rgba(${t.color},0.25)`; ctx.lineWidth = t.width * 3.2;
    ctx.beginPath(); ctx.moveTo(x0, y0); ctx.lineTo(x1, y1); ctx.stroke();
    ctx.strokeStyle = `rgba(${t.color},0.95)`; ctx.lineWidth = t.width;
    ctx.beginPath(); ctx.moveTo(x0, y0); ctx.lineTo(x1, y1); ctx.stroke();
  }
  for (const r of FX.rings) {
    const k = r.t / r.life; const rr = lerp(r.r0, r.r1, 1 - (1 - k) * (1 - k));
    ctx.strokeStyle = `rgba(${r.color},${0.55 * (1 - k)})`; ctx.lineWidth = r.width * (1 - k * 0.6);
    ctx.beginPath(); ctx.arc(r.x, r.y, rr, 0, TAU); ctx.stroke();
  }
  ctx.globalCompositeOperation = 'source-over';
}

// ground-light glow (additive) — makes explosions light up the terrain, day or night
function drawGlows(ctx, view) {
  ctx.globalCompositeOperation = 'lighter';
  for (const l of FX.lights) {
    if (l.x < view.x0 - l.r || l.x > view.x1 + l.r || l.y < view.y0 - l.r || l.y > view.y1 + l.r) continue;
    const k = l.t / l.life;
    ctx.globalAlpha = 0.28 * l.i * (1 - k) * (G.night > 0 ? 1.3 : 1);
    ctx.drawImage(FX.spr.fire, l.x - l.r, l.y - l.r, l.r * 2, l.r * 2);
  }
  ctx.globalAlpha = 1;
  ctx.globalCompositeOperation = 'source-over';
}

function drawTexts(ctx) {
  ctx.textAlign = 'center';
  ctx.font = '700 13px "Barlow Condensed", "Arial Narrow", sans-serif';
  for (const t of FX.texts) {
    ctx.globalAlpha = 1 - t.t / t.life;
    ctx.fillStyle = 'rgba(0,0,0,0.6)'; ctx.fillText(t.text, t.x + 1, t.y + 1);
    ctx.fillStyle = t.color; ctx.fillText(t.text, t.x, t.y);
  }
  ctx.globalAlpha = 1;
}

// ---------------------------------------------------------------------
// permanent ground decals (painted into MAP.ground)
// ---------------------------------------------------------------------
function decalCrater(x, y, r, s) {
  const g = MAP.gctx; if (!g) return;
  const t = terrAt(x, y); if (t === T_WATER) return;
  const gr = g.createRadialGradient(x, y, 0, x, y, r * 1.6);
  gr.addColorStop(0, 'rgba(20,16,10,0.75)'); gr.addColorStop(0.45, 'rgba(45,36,22,0.55)'); gr.addColorStop(0.7, 'rgba(80,66,40,0.25)'); gr.addColorStop(1, 'rgba(60,50,30,0)');
  g.fillStyle = gr; g.beginPath(); g.arc(x, y, r * 1.6, 0, TAU); g.fill();
  if (s >= 2) {
    g.fillStyle = 'rgba(15,12,8,0.55)'; g.beginPath(); g.arc(x, y, r * 0.45, 0, TAU); g.fill();
    for (let i = 0; i < 5 + s * 2; i++) { const a = rand(0, TAU), d = rand(r * 0.8, r * 2.2); g.fillStyle = 'rgba(30,24,14,0.5)'; g.fillRect(x + Math.cos(a) * d, y + Math.sin(a) * d, 3, 3); }
  }
}
function decalScorch(x, y, r) {
  const g = MAP.gctx; const gr = g.createRadialGradient(x, y, 0, x, y, r);
  gr.addColorStop(0, 'rgba(10,8,6,0.6)'); gr.addColorStop(1, 'rgba(10,8,6,0)');
  g.fillStyle = gr; g.beginPath(); g.arc(x, y, r, 0, TAU); g.fill();
}
function decalBody(u) {
  const g = MAP.gctx; if (terrAt(u.x, u.y) === T_WATER) return;
  const tc = TEAM[u.team];
  g.save(); g.translate(u.x, u.y); g.rotate(u.ang);
  g.globalAlpha = 0.45; g.fillStyle = '#2a1a12'; g.beginPath(); g.ellipse(2, 1, 11, 8, 0, 0, TAU); g.fill();
  g.globalAlpha = 0.8; g.fillStyle = tc.dark; g.beginPath(); g.ellipse(0, 0, 8.5, 7, 0, 0, TAU); g.fill();
  g.globalAlpha = 0.5; g.fillStyle = '#222'; g.fillRect(-2, 4, 14, 2);
  g.restore(); g.globalAlpha = 1;
}
function decalTrack(u) {
  const g = MAP.gctx; const t = terrAt(u.x, u.y); if (t === T_WATER || t === T_BRIDGE) return;
  const c = Math.cos(u.ang), s = Math.sin(u.ang), w = u.def.wid * 0.36;
  g.fillStyle = t === T_BASE || t === T_ROAD ? 'rgba(30,25,15,0.07)' : 'rgba(35,30,15,0.11)';
  for (const side of [-1, 1]) g.fillRect(u.x - s * w * side - 3, u.y + c * w * side - 3, 6, 6);
}
function decalWreck(u) {
  const g = MAP.gctx; const d = u.def;
  g.save(); g.translate(u.x, u.y); g.rotate(u.ang);
  g.fillStyle = 'rgba(12,10,8,0.45)'; g.beginPath(); g.ellipse(0, 0, d.len * 0.9, d.wid * 0.95, 0, 0, TAU); g.fill();
  g.fillStyle = '#1d1b19'; g.fillRect(-d.len / 2, -d.wid / 2, d.len, d.wid);
  g.strokeStyle = '#0b0a09'; g.lineWidth = 2; g.strokeRect(-d.len / 2, -d.wid / 2, d.len, d.wid);
  g.fillStyle = '#2b2622'; g.fillRect(-d.len * 0.25, -d.wid * 0.3, d.len * 0.4, d.wid * 0.6);
  g.restore();
}
