'use strict';
// =====================================================================
// Battlefield: generation (180° rotationally symmetric), navigation,
// and the pre-rendered ground canvas that also collects decals
// =====================================================================

const T_GRASS = 0, T_FOREST = 1, T_ROAD = 2, T_WATER = 3, T_FORD = 4, T_BRIDGE = 5, T_BASE = 6, T_FIELD = 7;
const COST = {
  inf: [1, 1.2, 0.9, Infinity, 2.6, 0.85, 0.95, 1.05],
  veh: [1, 2.4, 0.65, Infinity, 3.2, 0.7, 0.9, 1.15],
};
const SPEED = {
  inf: [1, 0.85, 1.08, 0.3, 0.5, 1.05, 1.05, 0.95],
  veh: [1, 0.55, 1.35, 0.3, 0.42, 1.25, 1.15, 0.9],
};

const MAP = {};

function cellOf(x, y) { return clamp((y / CELL) | 0, 0, GH - 1) * GW + clamp((x / CELL) | 0, 0, GW - 1); }
function terrAt(x, y) { return MAP.terr[cellOf(x, y)]; }
function blockedAt(x, y) { return x < 4 || y < 4 || x > W - 4 || y > H - 4 || MAP.block[cellOf(x, y)] === 1; }
const mirror = (p) => ({ x: W - p.x, y: H - p.y });

function generateMap(seed) {
  const R = makeRng(seed);
  MAP.seed = seed;
  const N = GW * GH;
  MAP.terr = new Uint8Array(N);
  MAP.block = new Uint8Array(N);

  // --- river: x = W/2 + f(y - H/2) with f odd, so the map stays symmetric under 180° rotation
  const A1 = R.range(110, 170), k1 = TAU * R.range(1.0, 1.35) / H;
  const A2 = R.range(30, 60), k2 = TAU * R.range(2.8, 3.6) / H;
  const k3 = TAU * R.range(1.5, 2.5) / H;
  MAP.riverX = (y) => { const t = y - H / 2; return W / 2 + A1 * Math.sin(k1 * t) + A2 * Math.sin(k2 * t); };
  MAP.riverHW = (y) => 50 + 10 * Math.cos(k3 * (y - H / 2));

  // --- capture points & bases
  const P = (l, x, y) => ({ letter: l, x, y });
  const pts = [
    P('A', 0.2 * W, 0.22 * H), P('B', 0.2 * W, 0.78 * H), P('C', 0.335 * W, 0.5 * H),
    P('D', MAP.riverX(0.14 * H), 0.14 * H), P('E', W / 2, H / 2), P('F', MAP.riverX(0.86 * H), 0.86 * H),
    P('G', 0.665 * W, 0.5 * H), P('H', 0.8 * W, 0.22 * H), P('I', 0.8 * W, 0.78 * H),
  ];
  MAP.points = pts;
  MAP.hq = [{ x: 0.055 * W, y: H / 2 }, { x: W - 0.055 * W, y: H / 2 }];
  MAP.turrets = [
    [{ x: MAP.hq[0].x + 250, y: H / 2 - 290 }, { x: MAP.hq[0].x + 250, y: H / 2 + 290 }],
    [{ x: MAP.hq[1].x - 250, y: H / 2 + 290 }, { x: MAP.hq[1].x - 250, y: H / 2 - 290 }],
  ];
  MAP.bridges = [0.14, 0.5, 0.86].map((f) => { const y = f * H; const x = MAP.riverX(y), hw = MAP.riverHW(y); return { y, x0: x - hw - 34, x1: x + hw + 34, x }; });
  MAP.fords = [0.32, 0.68].map((f) => { const y = f * H; return { y, x: MAP.riverX(y), hw: MAP.riverHW(y) }; });

  // --- water
  for (let cy = 0; cy < GH; cy++) {
    for (let cx = 0; cx < GW; cx++) {
      const x = (cx + 0.5) * CELL, y = (cy + 0.5) * CELL;
      if (Math.abs(x - MAP.riverX(y)) < MAP.riverHW(y)) MAP.terr[cy * GW + cx] = T_WATER;
    }
  }
  for (const b of MAP.bridges) markRect(b.x0, b.y - 36, b.x1, b.y + 36, (i) => { if (MAP.terr[i] === T_WATER) MAP.terr[i] = T_BRIDGE; });
  for (const f of MAP.fords) markRect(f.x - f.hw - 10, f.y - 60, f.x + f.hw + 10, f.y + 60, (i) => { if (MAP.terr[i] === T_WATER) MAP.terr[i] = T_FORD; });

  // --- roads (left half, mirrored)
  const hq = MAP.hq[0];
  const gate = { x: hq.x + 150, y: hq.y };
  const [a, b, c, , e] = pts; const d = pts[3], f = pts[5];
  const leftRoads = [
    [gate, a], [gate, b], [gate, c], [c, { x: e.x - 230, y: e.y }, e],
    [a, c], [b, c], [a, { x: d.x - 240, y: d.y }, d], [b, { x: f.x - 240, y: f.y }, f],
  ];
  MAP.roads = [];
  for (const r of leftRoads) {
    const line = smoothRoad(R, r);
    MAP.roads.push(line, line.map(mirror));
  }
  const nearRoad = (x, y, m) => { for (const r of MAP.roads) for (const p of r) if (dist2(p.x, p.y, x, y) < m * m) return true; return false; };

  // --- scrap fields: behind and beside the towns on the left half, a couple in no-man's land, rotated across
  MAP.scrap = [];
  const inRiver = (x, y, pad) => Math.abs(x - MAP.riverX(y)) < MAP.riverHW(y) + pad;
  const addScrap = (x, y) => {
    for (let k = 0; k < 6 && inRiver(x, y, 130); k++) x -= 90;
    const f = { x, y, r: R.range(72, 92) };
    MAP.scrap.push(f, { x: W - x, y: H - y, r: f.r });
  };
  addScrap(a.x + R.range(300, 380), a.y + R.range(240, 300));
  addScrap(b.x + R.range(300, 380), b.y - R.range(240, 300));
  addScrap(c.x - R.range(340, 420), c.y + R.range(260, 340));
  addScrap(d.x - R.range(430, 520), d.y + R.range(180, 260));
  addScrap(e.x - R.range(420, 500), e.y - R.range(360, 440));
  addScrap(0.43 * W, 0.31 * H);
  addScrap(0.43 * W, 0.69 * H);
  const avoid = pts.concat(MAP.scrap.map((f) => ({ x: f.x, y: f.y })));

  // --- lakes
  MAP.lakes = [];
  for (let tries = 0; tries < 120 && MAP.lakes.length < 6; tries++) {
    const L = { x: R.range(0.08 * W, 0.42 * W), y: R.range(0.06 * H, 0.94 * H), rx: R.range(90, 190), ry: R.range(70, 140), rot: R.range(0, Math.PI) };
    const m = Math.max(L.rx, L.ry);
    if (avoid.some((p) => dist(p.x, p.y, L.x, L.y) < m + 300 || dist(W - p.x, H - p.y, L.x, L.y) < m + 300)) continue;
    if (dist(hq.x, hq.y, L.x, L.y) < m + 650) continue;
    if (Math.abs(L.x - MAP.riverX(L.y)) < m + 300) continue;
    if (nearRoad(L.x, L.y, m + 90)) continue;
    if (MAP.lakes.some((o) => dist(o.x, o.y, L.x, L.y) < m + Math.max(o.rx, o.ry) + 200)) continue;
    MAP.lakes.push(L, { x: W - L.x, y: H - L.y, rx: L.rx, ry: L.ry, rot: L.rot });
  }
  for (const L of MAP.lakes) {
    const m = Math.max(L.rx, L.ry);
    markRect(L.x - m, L.y - m, L.x + m, L.y + m, (i, x, y) => { if (inEllipse(L, x, y, 0)) MAP.terr[i] = T_WATER; });
  }

  // --- roads into terrain
  for (const r of MAP.roads) {
    for (let i = 0; i < r.length - 1; i++) {
      const p = r[i], q = r[i + 1]; const len = dist(p.x, p.y, q.x, q.y);
      for (let s = 0; s <= len; s += 12) {
        const x = lerp(p.x, q.x, s / len), y = lerp(p.y, q.y, s / len);
        markRect(x - 22, y - 22, x + 22, y + 22, (k) => { if (MAP.terr[k] === T_GRASS) MAP.terr[k] = T_ROAD; });
      }
    }
  }

  // --- town hall plots: near the middle of each town but off the roads, bridges and water
  const clearPlot = (x, y, roads, pad) => {
    if (inRiver(x, y, 70)) return false;
    for (let dy = -pad; dy <= pad; dy += 12) for (let dx = -pad; dx <= pad; dx += 12) {
      const t = MAP.terr[cellOf(x + dx, y + dy)];
      if (t === T_WATER || t === T_BRIDGE || t === T_FORD || t === T_FOREST || (roads && t === T_ROAD)) return false;
    }
    return true;
  };
  for (const p of pts) {
    if (p.x > W / 2 + 1) continue;
    let plot = null;
    for (const [roads, pad] of [[true, 60], [true, 40], [false, 60]]) {
      for (let r = 0; r <= 200 && !plot; r += 25) for (let k = 0; k < (r ? 16 : 1); k++) {
        const an = (k / 16) * TAU + 0.2, x = p.x + Math.cos(an) * r, y = p.y + Math.sin(an) * r;
        if (clearPlot(x, y, roads, pad)) { plot = { x, y }; break; }
      }
      if (plot) break;
    }
    plot = plot || { x: p.x, y: p.y };
    p.hx = plot.x; p.hy = plot.y;
    const q = pts.find((o) => o !== p && Math.abs(o.x - (W - p.x)) < 2 && Math.abs(o.y - (H - p.y)) < 2);
    if (q) { q.hx = W - plot.x; q.hy = H - plot.y; }
    avoid.push({ x: plot.x, y: plot.y }, { x: W - plot.x, y: H - plot.y }); // keep fields and forests off it
  }

  // --- ruined houses around every town (left half, rotated across)
  MAP.ruins = [];
  for (const p of pts) {
    if (p.x > W / 2 + 1) continue;
    const n = p.letter === 'E' ? 7 : 12;
    for (let k = 0, tries = 0; k < n && tries < 80; tries++) {
      const an = R.range(0, TAU), d = R.range(75, 215);
      const x = p.x + Math.cos(an) * d, y = p.y + Math.sin(an) * d;
      if (p.letter === 'E' && x > W / 2 - 30) continue;
      const t = MAP.terr[cellOf(x, y)];
      if (t === T_WATER || t === T_BRIDGE || t === T_FORD || t === T_ROAD || inRiver(x, y, 40)) continue;
      if (pts.some((o) => dist(o.hx, o.hy, x, y) < 85 || dist(W - o.hx, H - o.hy, x, y) < 85)) continue;
      const rw = R.range(34, 60), rh = R.range(28, 46);
      if (MAP.ruins.some((o) => dist(o.x, o.y, x, y) < (Math.max(rw, rh) + Math.max(o.w, o.h)) * 0.55)) continue;
      const ru = { x, y, w: rw, h: rh, rot: R.range(-0.4, 0.4) + (R() < 0.5 ? 0 : Math.PI / 2), gaps: [R() < 0.6, R() < 0.6, R() < 0.6, R() < 0.6], seed: (R() * 1e6) | 0 };
      MAP.ruins.push(ru, { ...ru, x: W - x, y: H - y });
      k++;
    }
  }

  // --- base pads
  for (const h of MAP.hq) markRect(h.x - 320, h.y - 320, h.x + 320, h.y + 320, (i, x, y) => { if (dist(x, y, h.x, h.y) < 310 && MAP.terr[i] !== T_WATER) MAP.terr[i] = T_BASE; });

  // --- fields
  MAP.fields = [];
  for (let tries = 0; tries < 80 && MAP.fields.length < 16; tries++) {
    const F = { x: R.range(0.07 * W, 0.45 * W), y: R.range(0.05 * H, 0.95 * H), w: R.range(220, 420), h: R.range(140, 280), rot: R.range(-0.5, 0.5), kind: (R() * 3) | 0 };
    const m = Math.max(F.w, F.h) / 2;
    if (avoid.some((p) => dist(p.x, p.y, F.x, F.y) < m + 140)) continue;
    if (dist(hq.x, hq.y, F.x, F.y) < m + 380) continue;
    if (Math.abs(F.x - MAP.riverX(F.y)) < m + 120) continue;
    if (MAP.lakes.some((L) => dist(L.x, L.y, F.x, F.y) < m + Math.max(L.rx, L.ry) + 40)) continue;
    if (MAP.fields.some((o) => dist(o.x, o.y, F.x, F.y) < m + Math.max(o.w, o.h) / 2 + 30)) continue;
    MAP.fields.push(F, { ...F, x: W - F.x, y: H - F.y });
  }
  for (const F of MAP.fields) {
    const m = Math.max(F.w, F.h) / 2;
    markRect(F.x - m, F.y - m, F.x + m, F.y + m, (i, x, y) => { if (inRect(F, x, y) && MAP.terr[i] === T_GRASS) MAP.terr[i] = T_FIELD; });
  }

  // --- forests
  MAP.forests = [];
  for (let tries = 0; tries < 200 && MAP.forests.length < 40; tries++) {
    const Fo = { x: R.range(0.05 * W, 0.49 * W), y: R.range(0.03 * H, 0.97 * H), r: R.range(100, 290), p1: R.range(0, TAU), p2: R.range(0, TAU), a1: R.range(0.12, 0.3), a2: R.range(0.06, 0.16) };
    if (avoid.some((p) => dist(p.x, p.y, Fo.x, Fo.y) < Fo.r + 110 || dist(W - p.x, H - p.y, Fo.x, Fo.y) < Fo.r + 110)) continue;
    if (dist(hq.x, hq.y, Fo.x, Fo.y) < Fo.r + 430) continue;
    if (MAP.terr[cellOf(Fo.x, Fo.y)] === T_WATER) continue;
    if (MAP.fields.some((o) => dist(o.x, o.y, Fo.x, Fo.y) < Fo.r + Math.max(o.w, o.h) * 0.3)) continue;
    MAP.forests.push(Fo, { ...Fo, x: W - Fo.x, y: H - Fo.y, p1: Fo.p1 + Math.PI, p2: Fo.p2 + Math.PI });
  }
  const forestR = (Fo, ang) => Fo.r * (1 + Fo.a1 * Math.sin(3 * ang + Fo.p1) + Fo.a2 * Math.sin(5 * ang + Fo.p2));
  for (const Fo of MAP.forests) {
    const m = Fo.r * 1.5;
    markRect(Fo.x - m, Fo.y - m, Fo.x + m, Fo.y + m, (i, x, y) => {
      const ang = Math.atan2(y - Fo.y, x - Fo.x);
      if (dist(x, y, Fo.x, Fo.y) < forestR(Fo, ang) && (MAP.terr[i] === T_GRASS || MAP.terr[i] === T_FIELD)) {
        // keep a strip of open bank along the water
        if (Math.abs(x - MAP.riverX(y)) > MAP.riverHW(y) + 50) MAP.terr[i] = T_FOREST;
      }
    });
  }

  // --- trees: one per forest cell, placed on the left half and rotated across
  MAP.trees = [];
  const half = [];
  for (let cy = 0; cy < GH; cy++) {
    for (let cx = 0; cx < GW; cx++) {
      const i = cy * GW + cx;
      if (MAP.terr[i] !== T_FOREST) continue;
      const x = (cx + 0.5) * CELL, y = (cy + 0.5) * CELL;
      if (x > W / 2 || (x === W / 2 && y > H / 2)) continue;
      const n = R() < 0.55 ? 2 : 1;
      for (let k = 0; k < n; k++) half.push({ x: x + R.range(-16, 16), y: y + R.range(-16, 16), r: R.range(15, 25), v: (R() * 6) | 0, a: R.range(0, TAU) });
    }
  }
  // hedgerows around fields (decoration only)
  for (const F of MAP.fields) {
    if (F.x > W / 2) continue;
    const cs = Math.cos(F.rot), sn = Math.sin(F.rot);
    for (let side = 0; side < 4; side++) {
      if (R() < 0.45) continue;
      const len = side % 2 ? F.h : F.w;
      for (let s = -len / 2; s <= len / 2; s += R.range(22, 34)) {
        let lx, ly;
        if (side === 0) { lx = s; ly = -F.h / 2 - 10; } else if (side === 1) { lx = F.w / 2 + 10; ly = s; } else if (side === 2) { lx = s; ly = F.h / 2 + 10; } else { lx = -F.w / 2 - 10; ly = s; }
        const x = F.x + lx * cs - ly * sn, y = F.y + lx * sn + ly * cs;
        const t = MAP.terr[cellOf(x, y)];
        if (t === T_GRASS || t === T_FIELD) half.push({ x, y, r: R.range(9, 14), v: (R() * 6) | 0, a: R.range(0, TAU), deco: true });
      }
    }
  }
  for (const t of half) MAP.trees.push(t, { ...t, x: W - t.x, y: H - t.y, a: t.a + Math.PI });

  // rocks (pure decoration)
  MAP.rocks = [];
  for (let i = 0; i < 70; i++) {
    const x = R.range(200, W / 2 - 100), y = R.range(100, H - 100);
    const t = MAP.terr[cellOf(x, y)];
    if (t !== T_GRASS) continue;
    const rk = { x, y, r: R.range(6, 16), a: R.range(0, TAU), s: R.range(0.6, 1) };
    MAP.rocks.push(rk, { ...rk, x: W - x, y: H - y });
  }

  // --- navigation
  for (let i = 0; i < N; i++) MAP.block[i] = MAP.terr[i] === T_WATER ? 1 : 0;
  MAP.cost = { inf: new Float32Array(N), veh: new Float32Array(N) };
  for (let i = 0; i < N; i++) { MAP.cost.inf[i] = COST.inf[MAP.terr[i]]; MAP.cost.veh[i] = COST.veh[MAP.terr[i]]; }
  NAV.cache.clear();

  renderGround();
  buildTreeSprites();
  renderCanopyLow();
  renderTreeTiles();
}

function markRect(x0, y0, x1, y1, fn) {
  const cx0 = clamp(Math.floor(x0 / CELL), 0, GW - 1), cx1 = clamp(Math.floor(x1 / CELL), 0, GW - 1);
  const cy0 = clamp(Math.floor(y0 / CELL), 0, GH - 1), cy1 = clamp(Math.floor(y1 / CELL), 0, GH - 1);
  for (let cy = cy0; cy <= cy1; cy++) for (let cx = cx0; cx <= cx1; cx++) fn(cy * GW + cx, (cx + 0.5) * CELL, (cy + 0.5) * CELL);
}
function inEllipse(L, x, y, pad) {
  const c = Math.cos(-L.rot), s = Math.sin(-L.rot); const dx = x - L.x, dy = y - L.y;
  const lx = dx * c - dy * s, ly = dx * s + dy * c;
  return (lx * lx) / ((L.rx + pad) ** 2) + (ly * ly) / ((L.ry + pad) ** 2) < 1;
}
function inRect(F, x, y) {
  const c = Math.cos(-F.rot), s = Math.sin(-F.rot); const dx = x - F.x, dy = y - F.y;
  const lx = dx * c - dy * s, ly = dx * s + dy * c;
  return Math.abs(lx) < F.w / 2 && Math.abs(ly) < F.h / 2;
}
function smoothRoad(R, ctrl) {
  let pts = [ctrl[0]];
  for (let i = 0; i < ctrl.length - 1; i++) {
    const p = ctrl[i], q = ctrl[i + 1]; const len = dist(p.x, p.y, q.x, q.y);
    const nx = -(q.y - p.y) / len, ny = (q.x - p.x) / len;
    const n = Math.max(1, Math.round(len / 420));
    const last = i === ctrl.length - 2 && ctrl.length > 2;
    for (let k = 1; k < n; k++) {
      const t = k / n; const j = last ? 0 : R.range(-90, 90) * Math.sin(Math.PI * t);
      pts.push({ x: lerp(p.x, q.x, t) + nx * j, y: lerp(p.y, q.y, t) + ny * j });
    }
    pts.push(q);
  }
  for (let it = 0; it < 3; it++) {
    const out = [pts[0]];
    for (let i = 0; i < pts.length - 1; i++) {
      const p = pts[i], q = pts[i + 1];
      out.push({ x: p.x * 0.75 + q.x * 0.25, y: p.y * 0.75 + q.y * 0.25 }, { x: p.x * 0.25 + q.x * 0.75, y: p.y * 0.25 + q.y * 0.75 });
    }
    out.push(pts[pts.length - 1]);
    pts = out;
  }
  return pts;
}

// ---------------------------------------------------------------------
// A* on the terrain grid, with line-of-sight smoothing and a path cache
// ---------------------------------------------------------------------
const NAV = {
  cache: new Map(),
  g: null, f: null, from: null, open: null, closed: null, gen: 0,
};
function navInit() {
  const N = GW * GH;
  NAV.g = new Float64Array(N); NAV.f = new Float64Array(N); NAV.from = new Int32Array(N);
  NAV.open = new Uint32Array(N); NAV.closed = new Uint32Array(N);
}
function nearestOpen(i) {
  if (!MAP.block[i]) return i;
  const cx = i % GW, cy = (i / GW) | 0;
  for (let r = 1; r < 20; r++) {
    let best = -1, bd = 1e9;
    for (let dy = -r; dy <= r; dy++) for (let dx = -r; dx <= r; dx++) {
      if (Math.max(Math.abs(dx), Math.abs(dy)) !== r) continue;
      const x = cx + dx, y = cy + dy; if (x < 0 || y < 0 || x >= GW || y >= GH) continue;
      const j = y * GW + x; if (MAP.block[j]) continue;
      const d = dx * dx + dy * dy; if (d < bd) { bd = d; best = j; }
    }
    if (best >= 0) return best;
  }
  return i;
}
function lineClear(ax, ay, bx, by, cost) {
  const len = dist(ax, ay, bx, by); const n = Math.ceil(len / 18);
  for (let k = 0; k <= n; k++) {
    const t = n ? k / n : 0; const i = cellOf(lerp(ax, bx, t), lerp(ay, by, t));
    if (MAP.block[i] || cost[i] > 2) return false;
  }
  return true;
}
function findPath(sx, sy, tx, ty, cls) {
  const cost = cls === 'veh' ? MAP.cost.veh : MAP.cost.inf;
  let s = nearestOpen(cellOf(sx, sy));
  let t0 = cellOf(tx, ty);
  let t = nearestOpen(t0);
  if (t !== t0) { tx = (t % GW + 0.5) * CELL; ty = (((t / GW) | 0) + 0.5) * CELL; }
  if (s === t || lineClear(sx, sy, tx, ty, cost)) return [{ x: tx, y: ty }];
  const key = s * 2 + (cls === 'veh' ? 1 : 0) + ':' + t;
  const hit = NAV.cache.get(key);
  if (hit) return hit.slice(0, -1).concat([{ x: tx, y: ty }]);

  const gen = ++NAV.gen;
  const { g, f, from, open, closed } = NAV;
  const heap = new Heap(f);
  const tcx = t % GW, tcy = (t / GW) | 0;
  const hfun = (i) => { const dx = Math.abs(i % GW - tcx), dy = Math.abs(((i / GW) | 0) - tcy); return (Math.max(dx, dy) + 0.414 * Math.min(dx, dy)) * 0.65; };
  g[s] = 0; f[s] = hfun(s); from[s] = -1; open[s] = gen; heap.push(s);
  let found = false, iter = 0;
  while (heap.size && iter++ < 40000) {
    const cur = heap.pop();
    if (closed[cur] === gen) continue;
    closed[cur] = gen;
    if (cur === t) { found = true; break; }
    const cx = cur % GW, cy = (cur / GW) | 0;
    for (let dy = -1; dy <= 1; dy++) for (let dx = -1; dx <= 1; dx++) {
      if (!dx && !dy) continue;
      const x = cx + dx, y = cy + dy; if (x < 0 || y < 0 || x >= GW || y >= GH) continue;
      const n = y * GW + x; if (MAP.block[n] || closed[n] === gen) continue;
      if (dx && dy && (MAP.block[cy * GW + x] || MAP.block[y * GW + cx])) continue;
      const step = (dx && dy ? 1.414 : 1) * (cost[n] + cost[cur]) * 0.5;
      const ng = g[cur] + step;
      if (open[n] !== gen || ng < g[n]) { open[n] = gen; g[n] = ng; f[n] = ng + hfun(n); from[n] = cur; heap.push(n); }
    }
  }
  if (!found) return [{ x: tx, y: ty }];
  const cells = [];
  for (let c = t; c !== -1; c = from[c]) cells.push(c);
  cells.reverse();
  const P = cells.map((c) => ({ x: (c % GW + 0.5) * CELL, y: (((c / GW) | 0) + 0.5) * CELL }));
  P[0] = { x: sx, y: sy };
  P[P.length - 1] = { x: tx, y: ty };
  // string pulling
  const out = [];
  let i = 0;
  while (i < P.length - 1) {
    let j = i + 1;
    while (j + 1 < P.length && lineClear(P[i].x, P[i].y, P[j + 1].x, P[j + 1].y, cost)) j++;
    out.push(P[j]); i = j;
  }
  if (NAV.cache.size > 600) NAV.cache.clear();
  NAV.cache.set(key, out);
  return out.slice();
}

// ---------------------------------------------------------------------
// Ground rendering (static terrain; decals are painted on top at runtime)
// ---------------------------------------------------------------------
function softBlob(ctx, x, y, r, color, alpha) {
  const g = ctx.createRadialGradient(x, y, 0, x, y, r);
  g.addColorStop(0, color); g.addColorStop(1, 'rgba(0,0,0,0)');
  ctx.globalAlpha = alpha; ctx.fillStyle = g; ctx.beginPath(); ctx.arc(x, y, r, 0, TAU); ctx.fill(); ctx.globalAlpha = 1;
}
function riverPath(ctx, pad) {
  ctx.beginPath();
  for (let y = -60; y <= H + 60; y += 16) { const x = MAP.riverX(y) - MAP.riverHW(y) - pad; y === -60 ? ctx.moveTo(x, y) : ctx.lineTo(x, y); }
  for (let y = H + 60; y >= -60; y -= 16) ctx.lineTo(MAP.riverX(y) + MAP.riverHW(y) + pad, y);
  ctx.closePath();
}
function lakePath(ctx, L, pad) { ctx.beginPath(); ctx.ellipse(L.x, L.y, L.rx + pad, L.ry + pad, L.rot, 0, TAU); }

function renderGround() {
  const R = makeRng(MAP.seed + 7);
  const cv = document.createElement('canvas');
  cv.width = Math.round(W * GS); cv.height = Math.round(H * GS);
  const g = cv.getContext('2d');
  g.scale(GS, GS);
  MAP.ground = cv; MAP.gctx = g;

  // a muddy, muted olive battlefield
  g.fillStyle = '#4f5233'; g.fillRect(0, 0, W, H);
  const greens = ['#585a37', '#4a4c2f', '#62603b', '#53532f', '#6a6240', '#45472c', '#5c5434'];
  for (let i = 0; i < 1100; i++) softBlob(g, R() * W, R() * H, R.range(60, 280), greens[(R() * greens.length) | 0], R.range(0.14, 0.32));
  // mud, thickest in the middle of the map where the fighting is
  for (let i = 0; i < 420; i++) {
    const x = W / 2 + (R() - 0.5) * W * (R() < 0.6 ? 0.55 : 1), y = R() * H;
    softBlob(g, x, y, R.range(40, 160), R() < 0.5 ? '#4a3e2a' : '#5b4a33', R.range(0.18, 0.4));
  }

  // trampled dirt around the towns
  for (const p of MAP.points) { softBlob(g, p.x, p.y, 260, '#5e5238', 0.45); softBlob(g, p.x, p.y, 150, '#6a5d42', 0.5); }

  // fields
  const fieldCols = [['#6e6e3a', '#62622f'], ['#5c6a34', '#52602d'], ['#5e4e33', '#52432c']];
  for (const F of MAP.fields) {
    g.save(); g.translate(F.x, F.y); g.rotate(F.rot);
    const [c1, c2] = fieldCols[F.kind];
    g.globalAlpha = 0.85; g.fillStyle = c1; g.fillRect(-F.w / 2, -F.h / 2, F.w, F.h);
    g.fillStyle = c2;
    for (let y = -F.h / 2; y < F.h / 2; y += 14) g.fillRect(-F.w / 2, y, F.w, 6);
    g.globalAlpha = 0.5; g.strokeStyle = '#2d4a1a'; g.lineWidth = 6; g.strokeRect(-F.w / 2, -F.h / 2, F.w, F.h);
    g.restore();
  }

  // grass tufts
  g.lineWidth = 2;
  for (const col of ['rgba(40,44,20,0.45)', 'rgba(125,128,74,0.3)']) {
    g.strokeStyle = col; g.beginPath();
    for (let i = 0; i < 23000; i++) {
      const x = R() * W, y = R() * H, a = R.range(-1, 1) - Math.PI / 2, l = R.range(4, 9);
      g.moveTo(x, y); g.lineTo(x + Math.cos(a) * l, y + Math.sin(a) * l);
    }
    g.stroke();
  }
  // flowers
  for (let i = 0; i < 700; i++) { g.fillStyle = pick(['#b8b06a', '#c8c4b0', '#a87850']); g.globalAlpha = 0.4; g.fillRect(R() * W, R() * H, 3, 3); }
  g.globalAlpha = 1;
  // old shell holes from earlier fighting
  for (let i = 0; i < 340; i++) {
    const x = W / 2 + (R() - 0.5) * W * 0.62, y = R() * H, r = R.range(6, 18);
    if (MAP.terr[cellOf(x, y)] === T_WATER) continue;
    const gr = g.createRadialGradient(x, y, 0, x, y, r * 1.7);
    gr.addColorStop(0, 'rgba(30,24,15,0.6)'); gr.addColorStop(0.55, 'rgba(50,40,26,0.4)'); gr.addColorStop(0.8, 'rgba(110,96,66,0.25)'); gr.addColorStop(1, 'rgba(80,70,45,0)');
    g.fillStyle = gr; g.beginPath(); g.arc(x, y, r * 1.7, 0, TAU); g.fill();
  }

  // forest floor
  for (let i = 0; i < GW * GH; i++) {
    if (MAP.terr[i] !== T_FOREST) continue;
    const x = (i % GW + 0.5) * CELL, y = (((i / GW) | 0) + 0.5) * CELL;
    softBlob(g, x, y, 46, '#2b3019', 0.6);
  }

  // roads
  g.lineJoin = 'round'; g.lineCap = 'round';
  const strokeRoads = (w, col, a, off) => {
    g.globalAlpha = a; g.strokeStyle = col; g.lineWidth = w;
    for (const r of MAP.roads) {
      g.beginPath();
      for (let i = 0; i < r.length; i++) {
        let { x, y } = r[i];
        if (off) { const p = r[Math.max(0, i - 1)], q = r[Math.min(r.length - 1, i + 1)]; const l = dist(p.x, p.y, q.x, q.y) || 1; x += (-(q.y - p.y) / l) * off; y += ((q.x - p.x) / l) * off; }
        i ? g.lineTo(x, y) : g.moveTo(x, y);
      }
      g.stroke();
    }
    g.globalAlpha = 1;
  };
  strokeRoads(60, '#2f2a1a', 0.35);
  strokeRoads(46, '#5a4c34', 1);
  strokeRoads(38, '#74644a', 1);
  strokeRoads(4, '#4a3e2a', 0.7, 9);
  strokeRoads(4, '#4a3e2a', 0.7, -9);
  for (const r of MAP.roads) for (const p of r) if (R() < 0.6) { g.fillStyle = 'rgba(60,50,30,0.5)'; g.fillRect(p.x + R.range(-16, 16), p.y + R.range(-16, 16), 3, 3); }

  // river + lakes: bank, shallows, deep water, ripples
  g.fillStyle = '#6a5e42'; riverPath(g, 22); g.fill();
  for (const L of MAP.lakes) { lakePath(g, L, 20); g.fill(); }
  g.fillStyle = '#4f6460'; riverPath(g, 6); g.fill();
  for (const L of MAP.lakes) { lakePath(g, L, 6); g.fill(); }
  g.fillStyle = '#3a5150'; riverPath(g, 0); g.fill();
  for (const L of MAP.lakes) { lakePath(g, L, 0); g.fill(); }
  g.fillStyle = '#2f4544'; riverPath(g, -24); g.fill();
  for (const L of MAP.lakes) { lakePath(g, L, -30); g.fill(); }
  g.strokeStyle = 'rgba(170,190,180,0.2)'; g.lineWidth = 3;
  for (let i = 0; i < 520; i++) {
    const y = R() * H, x = MAP.riverX(y) + R.range(-1, 1) * MAP.riverHW(y) * 0.8;
    g.beginPath(); g.moveTo(x, y); g.lineTo(x + R.range(-3, 3), y + R.range(12, 30)); g.stroke();
  }
  // fords: shallow sandy crossing with stones
  for (const f of MAP.fords) {
    g.fillStyle = '#5b706a'; g.beginPath(); g.ellipse(f.x, f.y, f.hw + 26, 62, 0, 0, TAU); g.fill();
    g.fillStyle = '#76806c'; g.beginPath(); g.ellipse(f.x, f.y, f.hw + 6, 40, 0, 0, TAU); g.fill();
    for (let i = 0; i < 40; i++) { g.fillStyle = R() < 0.5 ? '#8c8a7a' : '#6d6c60'; g.beginPath(); g.arc(f.x + R.range(-f.hw, f.hw), f.y + R.range(-40, 40), R.range(2, 6), 0, TAU); g.fill(); }
  }

  // base pads
  for (let ti = 0; ti < 2; ti++) {
    const h = MAP.hq[ti];
    g.fillStyle = '#48463c'; g.beginPath(); g.arc(h.x, h.y, 312, 0, TAU); g.fill();
    g.fillStyle = '#5c5a4e'; g.beginPath(); g.arc(h.x, h.y, 296, 0, TAU); g.fill();
    g.strokeStyle = 'rgba(0,0,0,0.18)'; g.lineWidth = 2;
    g.save(); g.beginPath(); g.arc(h.x, h.y, 296, 0, TAU); g.clip();
    for (let x = h.x - 300; x < h.x + 300; x += 60) { g.beginPath(); g.moveTo(x, h.y - 300); g.lineTo(x, h.y + 300); g.stroke(); }
    for (let y = h.y - 300; y < h.y + 300; y += 60) { g.beginPath(); g.moveTo(h.x - 300, y); g.lineTo(h.x + 300, y); g.stroke(); }
    for (let i = 0; i < 30; i++) softBlob(g, h.x + R.range(-260, 260), h.y + R.range(-260, 260), R.range(15, 45), '#2e2f2a', 0.25);
    g.restore();
    // painted helipad + parking stripes
    const dir = ti === 0 ? 1 : -1;
    const hx = h.x - dir * 30, hy = h.y + 190 * dir;
    g.strokeStyle = '#d8d1a0'; g.lineWidth = 5; g.beginPath(); g.arc(hx, hy, 46, 0, TAU); g.stroke();
    g.fillStyle = '#d8d1a0'; g.fillRect(hx - 18, hy - 22, 8, 44); g.fillRect(hx + 10, hy - 22, 8, 44); g.fillRect(hx - 10, hy - 4, 20, 8);
    for (let k = 0; k < 6; k++) { const px = h.x - 120 + k * 46, py = h.y - 200 * dir; g.fillRect(px, py - 30, 4, 60); }
  }
  for (const r of MAP.ruins) drawRuin(g, r);
  for (const f of MAP.scrap) drawScrapField(g, f);
}
// a shelled house: rubble floor and the stumps of its walls
function drawRuin(g, r) {
  const R = makeRng(r.seed);
  g.save(); g.translate(r.x, r.y); g.rotate(r.rot);
  const w = r.w, h = r.h;
  g.fillStyle = 'rgba(30,26,20,0.45)'; g.fillRect(-w / 2 - 3, -h / 2 + 4, w + 8, h + 4);
  g.fillStyle = '#6a6355'; g.fillRect(-w / 2, -h / 2, w, h);
  g.fillStyle = 'rgba(40,36,30,0.35)';
  for (let i = 0; i < 8; i++) g.fillRect(R.range(-w / 2, w / 2 - 8), R.range(-h / 2, h / 2 - 6), R.range(5, 12), R.range(4, 9));
  const walls = [[-w / 2, -h / 2, w / 2, -h / 2], [w / 2, -h / 2, w / 2, h / 2], [w / 2, h / 2, -w / 2, h / 2], [-w / 2, h / 2, -w / 2, -h / 2]];
  g.lineCap = 'butt';
  walls.forEach(([x0, y0, x1, y1], i) => {
    const segs = r.gaps[i] ? [[0, R.range(0.2, 0.45)], [R.range(0.6, 0.8), 1]] : [[0, 1]];
    for (const [a, b] of segs) {
      const ax = lerp(x0, x1, a), ay = lerp(y0, y1, a), bx = lerp(x0, x1, b), by = lerp(y0, y1, b);
      g.strokeStyle = '#3b372f'; g.lineWidth = 7; g.beginPath(); g.moveTo(ax, ay); g.lineTo(bx, by); g.stroke();
      g.strokeStyle = '#948d7b'; g.lineWidth = 4.5; g.beginPath(); g.moveTo(ax, ay); g.lineTo(bx, by); g.stroke();
    }
  });
  for (let i = 0; i < 12; i++) { g.fillStyle = R() < 0.5 ? '#7d7766' : '#55514a'; const s = R.range(2, 6); g.fillRect(R.range(-w / 2 - 10, w / 2 + 6), R.range(-h / 2 - 10, h / 2 + 6), s, s); }
  g.restore();
}
// rusted wreckage you can hammer into scrap
function drawScrapField(g, f) {
  const R = makeRng((f.x * 13 + f.y * 7) | 0);
  softBlob(g, f.x, f.y, f.r * 1.3, '#3b3122', 0.55);
  for (let i = 0; i < 26; i++) {
    const a = R.range(0, TAU), d = Math.sqrt(R()) * f.r * 0.85;
    const x = f.x + Math.cos(a) * d, y = f.y + Math.sin(a) * d;
    g.save(); g.translate(x, y); g.rotate(R.range(0, TAU));
    const w = R.range(8, 22), h = R.range(4, 10);
    g.fillStyle = 'rgba(0,0,0,0.35)'; g.fillRect(-w / 2 + 2, -h / 2 + 2, w, h);
    g.fillStyle = pick(['#7a4a2a', '#8c5a32', '#5e5a52', '#6f3f24', '#9a6a3a']); g.fillRect(-w / 2, -h / 2, w, h);
    g.strokeStyle = 'rgba(20,14,8,0.6)'; g.lineWidth = 1; g.strokeRect(-w / 2, -h / 2, w, h);
    g.restore();
  }
  g.strokeStyle = 'rgba(210,140,70,0.45)'; g.lineWidth = 2; g.setLineDash([8, 7]);
  g.beginPath(); g.arc(f.x, f.y, f.r, 0, TAU); g.stroke(); g.setLineDash([]);
}

// ---------------------------------------------------------------------
// Tree sprites
// ---------------------------------------------------------------------
const TREE_SPR = [];
let TREE_SHADOW = null;
function buildTreeSprites() {
  TREE_SPR.length = 0;
  const R = makeRng(99);
  const pal = [['#232a16', '#323c1e', '#465228', '#5d6a36'], ['#262c18', '#363f20', '#4b552b', '#66703c'], ['#2a2a17', '#3b3b1f', '#53512b', '#6c6838'], ['#1f2614', '#2c361b', '#3f4a25', '#55602f']];
  for (let v = 0; v < 6; v++) {
    const c = document.createElement('canvas'); c.width = c.height = 96;
    const g = c.getContext('2d'); g.translate(48, 48);
    const p = pal[v % pal.length];
    const blobs = [];
    for (let i = 0; i < 7; i++) { const a = R() * TAU, d = R() * 18; blobs.push([Math.cos(a) * d, Math.sin(a) * d, R.range(16, 26)]); }
    g.fillStyle = p[0]; for (const [x, y, r] of blobs) { g.beginPath(); g.arc(x, y, r + 3, 0, TAU); g.fill(); }
    g.fillStyle = p[1]; for (const [x, y, r] of blobs) { g.beginPath(); g.arc(x - 2, y - 2, r, 0, TAU); g.fill(); }
    g.fillStyle = p[2]; for (const [x, y, r] of blobs) { g.beginPath(); g.arc(x - 5, y - 5, r * 0.62, 0, TAU); g.fill(); }
    g.fillStyle = p[3]; for (const [x, y, r] of blobs) { g.globalAlpha = 0.7; g.beginPath(); g.arc(x - 8, y - 8, r * 0.28, 0, TAU); g.fill(); }
    g.globalAlpha = 1;
    TREE_SPR.push(c);
  }
  const s = document.createElement('canvas'); s.width = s.height = 96;
  const sg = s.getContext('2d');
  const gr = sg.createRadialGradient(48, 48, 10, 48, 48, 46); gr.addColorStop(0, 'rgba(0,0,0,0.55)'); gr.addColorStop(1, 'rgba(0,0,0,0)');
  sg.fillStyle = gr; sg.fillRect(0, 0, 96, 96);
  TREE_SHADOW = s;
}
// trees are baked into tiles once per map: one drawImage per tile instead of one per tree
const TREE_TILE = 512, TREE_PAD = 40, TREE_SC = 0.7;
function renderTreeTiles() {
  const cols = Math.ceil(W / TREE_TILE), rows = Math.ceil(H / TREE_TILE);
  MAP.treeCols = cols; MAP.treeRows = rows; MAP.treeTiles = new Array(cols * rows).fill(null);
  const buckets = Array.from({ length: cols * rows }, () => []);
  for (const t of MAP.trees) {
    const x0 = Math.floor((t.x - t.r * 2) / TREE_TILE), x1 = Math.floor((t.x + t.r * 2) / TREE_TILE);
    const y0 = Math.floor((t.y - t.r * 2) / TREE_TILE), y1 = Math.floor((t.y + t.r * 2) / TREE_TILE);
    for (let y = Math.max(0, y0); y <= Math.min(rows - 1, y1); y++) for (let x = Math.max(0, x0); x <= Math.min(cols - 1, x1); x++) buckets[y * cols + x].push(t);
  }
  const size = Math.round((TREE_TILE + TREE_PAD * 2) * TREE_SC);
  for (let i = 0; i < buckets.length; i++) {
    const list = buckets[i]; if (!list.length) continue;
    const tx = (i % cols) * TREE_TILE - TREE_PAD, ty = Math.floor(i / cols) * TREE_TILE - TREE_PAD;
    const c = document.createElement('canvas'); c.width = c.height = size;
    const g = c.getContext('2d'); g.scale(TREE_SC, TREE_SC); g.translate(-tx, -ty);
    g.globalAlpha = 0.6;
    for (const t of list) { const s = t.r * 2.3; g.drawImage(TREE_SHADOW, t.x - s / 2 + t.r * 0.4, t.y - s / 2 + t.r * 0.55, s, s); }
    g.globalAlpha = 1;
    for (const t of list) { const s = t.r * 2.3; g.drawImage(TREE_SPR[t.v], t.x - s / 2, t.y - s / 2, s, s); }
    MAP.treeTiles[i] = c;
  }
}
function renderCanopyLow() {
  const sc = 0.125;
  const c = document.createElement('canvas'); c.width = Math.round(W * sc); c.height = Math.round(H * sc);
  const g = c.getContext('2d'); g.scale(sc, sc);
  for (const t of MAP.trees) { const s = t.r * 2.3; g.globalAlpha = 0.6; g.drawImage(TREE_SHADOW, t.x - s / 2 + t.r * 0.4, t.y - s / 2 + t.r * 0.55, s, s); }
  g.globalAlpha = 1;
  for (const t of MAP.trees) { const s = t.r * 2.3; g.drawImage(TREE_SPR[t.v], t.x - s / 2, t.y - s / 2, s, s); }
  MAP.canopyLow = c;
}
// detail texture drawn at full resolution over the ground when zoomed in
function makeDetailPattern(ctx) {
  const c = document.createElement('canvas'); c.width = c.height = 256;
  const g = c.getContext('2d');
  for (let i = 0; i < 900; i++) {
    const x = Math.random() * 256, y = Math.random() * 256, a = rand(-0.9, 0.9) - Math.PI / 2, l = rand(2, 5);
    g.strokeStyle = Math.random() < 0.55 ? 'rgba(30,30,12,0.35)' : 'rgba(160,150,100,0.16)';
    g.lineWidth = 1;
    g.beginPath(); g.moveTo(x, y); g.lineTo(x + Math.cos(a) * l, y + Math.sin(a) * l); g.stroke();
  }
  return ctx.createPattern(c, 'repeat');
}
