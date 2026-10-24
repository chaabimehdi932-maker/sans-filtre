'use strict';
// =====================================================================
// Math helpers, seeded RNG, spatial hash, procedural audio
// =====================================================================

const TAU = Math.PI * 2;
const clamp = (v, a, b) => (v < a ? a : v > b ? b : v);
const lerp = (a, b, t) => a + (b - a) * t;
const rand = (a, b) => a + Math.random() * (b - a);
const randi = (a, b) => Math.floor(rand(a, b + 1));
const pick = (arr) => arr[(Math.random() * arr.length) | 0];
const dist = (ax, ay, bx, by) => Math.hypot(ax - bx, ay - by);
const dist2 = (ax, ay, bx, by) => { const dx = ax - bx, dy = ay - by; return dx * dx + dy * dy; };
function angDiff(a, b) { let d = (b - a) % TAU; if (d > Math.PI) d -= TAU; if (d < -Math.PI) d += TAU; return d; }
function rotTo(a, target, max) { const d = angDiff(a, target); return Math.abs(d) <= max ? target : a + Math.sign(d) * max; }

// mulberry32 — used for map generation so a seed always gives the same battlefield
function makeRng(seed) {
  let s = seed >>> 0;
  const r = () => { s = (s + 0x6D2B79F5) >>> 0; let t = s; t = Math.imul(t ^ (t >>> 15), t | 1); t ^= t + Math.imul(t ^ (t >>> 7), t | 61); return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
  r.range = (a, b) => a + r() * (b - a);
  return r;
}

// ---------------------------------------------------------------------
// Spatial hash for neighbour / target queries
// ---------------------------------------------------------------------
class SpatialGrid {
  constructor(cs) {
    this.cs = cs;
    this.cols = Math.ceil(W / cs);
    this.rows = Math.ceil(H / cs);
    this.cells = [];
    for (let i = 0; i < this.cols * this.rows; i++) this.cells.push([]);
  }
  clear() { for (const c of this.cells) c.length = 0; }
  insert(o) {
    const cx = clamp((o.x / this.cs) | 0, 0, this.cols - 1);
    const cy = clamp((o.y / this.cs) | 0, 0, this.rows - 1);
    this.cells[cy * this.cols + cx].push(o);
  }
  // all objects whose centre lies within r (+ their radius) of x,y
  query(x, y, r, out) {
    out = out || [];
    const cs = this.cs;
    const x0 = clamp(((x - r - 60) / cs) | 0, 0, this.cols - 1), x1 = clamp(((x + r + 60) / cs) | 0, 0, this.cols - 1);
    const y0 = clamp(((y - r - 60) / cs) | 0, 0, this.rows - 1), y1 = clamp(((y + r + 60) / cs) | 0, 0, this.rows - 1);
    for (let cy = y0; cy <= y1; cy++) {
      for (let cx = x0; cx <= x1; cx++) {
        const cell = this.cells[cy * this.cols + cx];
        for (let i = 0; i < cell.length; i++) {
          const o = cell[i];
          const rr = r + (o.r || 0);
          const dx = o.x - x, dy = o.y - y;
          if (dx * dx + dy * dy <= rr * rr) out.push(o);
        }
      }
    }
    return out;
  }
}

// Binary min-heap keyed by a Float64Array of scores (used by A*)
class Heap {
  constructor(score) { this.a = []; this.s = score; }
  get size() { return this.a.length; }
  push(v) {
    const a = this.a, s = this.s; a.push(v); let i = a.length - 1;
    while (i > 0) { const p = (i - 1) >> 1; if (s[a[p]] <= s[v]) break; a[i] = a[p]; i = p; }
    a[i] = v;
  }
  pop() {
    const a = this.a, s = this.s; const top = a[0]; const last = a.pop();
    if (a.length) {
      let i = 0; const n = a.length;
      while (true) {
        let l = i * 2 + 1, r = l + 1, m = i;
        let mv = last;
        if (l < n && s[a[l]] < s[mv]) { m = l; mv = a[l]; }
        if (r < n && s[a[r]] < s[mv]) { m = r; mv = a[r]; }
        if (m === i) break;
        a[i] = a[m]; i = m;
      }
      a[i] = last;
    }
    return top;
  }
}

// ---------------------------------------------------------------------
// Procedural audio — every sound is synthesised, no files
// ---------------------------------------------------------------------
const Sound = {
  ctx: null, master: null, verb: null, noise: null, muted: false, vol: 0.7, last: {}, count: 0,
  init() {
    if (this.ctx) { if (this.ctx.state === 'suspended') this.ctx.resume(); return; }
    try {
      const AC = window.AudioContext || window.webkitAudioContext;
      if (!AC) return;
      const c = this.ctx = new AC();
      this.master = c.createGain(); this.master.gain.value = this.muted ? 0 : this.vol;
      const comp = c.createDynamicsCompressor(); comp.threshold.value = -16; comp.ratio.value = 6; comp.attack.value = 0.003; comp.release.value = 0.25;
      this.master.connect(comp); comp.connect(c.destination);
      // white noise buffer
      const len = c.sampleRate * 2; const buf = c.createBuffer(1, len, c.sampleRate); const d = buf.getChannelData(0);
      for (let i = 0; i < len; i++) d[i] = Math.random() * 2 - 1;
      this.noise = buf;
      // cheap reverb for the big booms
      const ir = c.createBuffer(2, c.sampleRate * 2.2, c.sampleRate);
      for (let ch = 0; ch < 2; ch++) { const x = ir.getChannelData(ch); for (let i = 0; i < x.length; i++) x[i] = (Math.random() * 2 - 1) * Math.pow(1 - i / x.length, 3.2); }
      this.verb = c.createConvolver(); this.verb.buffer = ir;
      const vg = c.createGain(); vg.gain.value = 0.32; this.verb.connect(vg); vg.connect(this.master);
    } catch (e) { this.ctx = null; }
  },
  setMuted(m) { this.muted = m; if (this.master) this.master.gain.value = m ? 0 : this.vol; },
  // world-positioned sound: volume and pan follow the camera
  at(name, x, y, v = 1) {
    if (!this.ctx || this.muted) return;
    const cam = G.cam;
    const vw = G.viewW / cam.zoom, vh = G.viewH / cam.zoom;
    const dx = x - cam.x, dy = y - cam.y;
    const d = Math.hypot(dx / (vw * 0.5), dy / (vh * 0.5));
    let gain = v * clamp(1.35 - d * 0.55, 0, 1);
    if (gain < 0.03) return;
    gain *= clamp(0.45 + cam.zoom * 0.55, 0.35, 1.1);
    this.play(name, gain, clamp(dx / (vw * 0.6), -0.9, 0.9));
  },
  play(name, gain = 1, pan = 0) {
    if (!this.ctx || this.muted) return;
    const now = this.ctx.currentTime;
    const gap = { rifle: 0.03, pistol: 0.04, mg: 0.05, aa: 0.06, cannon: 0.05, rocket: 0.06, boom: 0.04, small: 0.03, throw: 0.08, drone: 0.15, whistle: 0.12, ui: 0.03 }[name] || 0.02;
    if (this.last[name] && now - this.last[name] < gap) return;
    this.last[name] = now;
    const fn = this.lib[name]; if (!fn) return;
    const out = this.ctx.createGain(); out.gain.value = gain;
    let node = out;
    if (this.ctx.createStereoPanner) { const p = this.ctx.createStereoPanner(); p.pan.value = pan; out.connect(p); node = p; }
    node.connect(this.master);
    fn.call(this, out, now);
  },
  nz(dest, t, dur, type, f0, f1, q, g0, verb) {
    const c = this.ctx; const src = c.createBufferSource(); src.buffer = this.noise; src.playbackRate.value = 0.8 + Math.random() * 0.4;
    const f = c.createBiquadFilter(); f.type = type; f.frequency.setValueAtTime(f0, t); f.frequency.exponentialRampToValueAtTime(Math.max(20, f1), t + dur); f.Q.value = q;
    const g = c.createGain(); g.gain.setValueAtTime(0.0001, t); g.gain.exponentialRampToValueAtTime(g0, t + 0.004); g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
    src.connect(f); f.connect(g); g.connect(dest); if (verb && this.verb) g.connect(this.verb);
    src.start(t, Math.random() * 1.5); src.stop(t + dur + 0.05);
  },
  osc(dest, t, dur, type, f0, f1, g0, verb) {
    const c = this.ctx; const o = c.createOscillator(); o.type = type; o.frequency.setValueAtTime(f0, t); o.frequency.exponentialRampToValueAtTime(Math.max(10, f1), t + dur);
    const g = c.createGain(); g.gain.setValueAtTime(0.0001, t); g.gain.exponentialRampToValueAtTime(g0, t + 0.006); g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
    o.connect(g); g.connect(dest); if (verb && this.verb) g.connect(this.verb);
    o.start(t); o.stop(t + dur + 0.05);
  },
  lib: {
    rifle(d, t) { this.nz(d, t, 0.09, 'bandpass', 2400, 900, 0.9, 0.55); this.osc(d, t, 0.06, 'triangle', 180, 60, 0.25); },
    pistol(d, t) { this.nz(d, t, 0.06, 'bandpass', 3000, 1400, 1.2, 0.35); },
    mg(d, t) { this.nz(d, t, 0.07, 'bandpass', 1900, 700, 0.8, 0.6); this.osc(d, t, 0.05, 'square', 120, 50, 0.12); },
    aa(d, t) { this.nz(d, t, 0.11, 'lowpass', 2600, 500, 0.7, 0.7); this.osc(d, t, 0.08, 'triangle', 140, 45, 0.35); },
    sniper(d, t) { this.nz(d, t, 0.05, 'highpass', 3000, 2000, 0.7, 0.8); this.nz(d, t, 0.6, 'lowpass', 1600, 200, 0.5, 0.35, true); },
    cannon(d, t) { this.nz(d, t, 0.55, 'lowpass', 1400, 120, 0.8, 0.9, true); this.osc(d, t, 0.35, 'sine', 95, 35, 0.8); },
    cannonH(d, t) { this.nz(d, t, 0.8, 'lowpass', 1100, 90, 0.8, 1, true); this.osc(d, t, 0.5, 'sine', 70, 28, 1); },
    howitzer(d, t) { this.nz(d, t, 1.2, 'lowpass', 900, 60, 0.7, 1, true); this.osc(d, t, 0.7, 'sine', 55, 22, 1); },
    rocket(d, t) { this.nz(d, t, 0.55, 'bandpass', 700, 3200, 1.4, 0.5); this.nz(d, t, 0.2, 'lowpass', 800, 200, 0.6, 0.4); },
    mlrs(d, t) { this.nz(d, t, 0.8, 'bandpass', 500, 2800, 1.1, 0.55, true); },
    throw(d, t) { this.nz(d, t, 0.18, 'bandpass', 900, 1800, 2, 0.12); },
    small(d, t) { this.nz(d, t, 0.5, 'lowpass', 1800, 150, 0.6, 0.7, true); this.osc(d, t, 0.25, 'sine', 110, 40, 0.5); },
    boom(d, t) { this.nz(d, t, 1.3, 'lowpass', 1500, 50, 0.6, 1, true); this.osc(d, t, 0.9, 'sine', 60, 22, 1); this.nz(d, t + 0.02, 0.25, 'highpass', 2500, 1200, 0.5, 0.25); },
    huge(d, t) { this.nz(d, t, 3.2, 'lowpass', 1200, 30, 0.5, 1, true); this.osc(d, t, 2.2, 'sine', 48, 16, 1, true); this.nz(d, t + 0.05, 0.6, 'highpass', 2000, 600, 0.5, 0.5); },
    missile(d, t) { this.nz(d, t, 2.6, 'bandpass', 300, 1800, 0.6, 0.8, true); this.osc(d, t, 2.4, 'sawtooth', 60, 140, 0.12); },
    whistle(d, t) { this.osc(d, t, 0.7, 'sine', 2400, 700, 0.12); },
    drone(d, t) {
      const c = this.ctx; const o = c.createOscillator(); o.type = 'sawtooth'; o.frequency.setValueAtTime(190, t); o.frequency.linearRampToValueAtTime(260, t + 0.6);
      const g = c.createGain(); g.gain.setValueAtTime(0.0001, t); g.gain.exponentialRampToValueAtTime(0.09, t + 0.05); g.gain.exponentialRampToValueAtTime(0.0001, t + 0.8);
      const f = c.createBiquadFilter(); f.type = 'lowpass'; f.frequency.value = 1400;
      o.connect(f); f.connect(g); g.connect(d); o.start(t); o.stop(t + 0.85);
    },
    jam(d, t) { this.osc(d, t, 0.25, 'square', 1800, 300, 0.05); this.osc(d, t + 0.08, 0.25, 'square', 900, 2400, 0.04); },
    ui(d, t) { this.osc(d, t, 0.07, 'sine', 880, 660, 0.12); },
    build(d, t) { this.osc(d, t, 0.12, 'triangle', 520, 520, 0.14); this.osc(d, t + 0.09, 0.16, 'triangle', 780, 780, 0.14); },
    capture(d, t) { this.osc(d, t, 0.18, 'triangle', 660, 660, 0.2); this.osc(d, t + 0.14, 0.18, 'triangle', 880, 880, 0.2); this.osc(d, t + 0.28, 0.35, 'triangle', 1320, 1320, 0.16); },
    lost(d, t) { this.osc(d, t, 0.22, 'triangle', 520, 520, 0.18); this.osc(d, t + 0.18, 0.35, 'triangle', 390, 390, 0.18); },
    alert(d, t) { for (let i = 0; i < 3; i++) this.osc(d, t + i * 0.22, 0.14, 'square', 1250, 1250, 0.07); },
    error(d, t) { this.osc(d, t, 0.12, 'square', 180, 160, 0.08); },
  },
};
