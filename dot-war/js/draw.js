'use strict';
// =====================================================================
// Unit artwork. Local space: +x is forward, +y is the unit's right.
// Infantry are dots carrying their gear; vehicles are outlined boxes.
// =====================================================================

function bar(ctx, x0, x1, yc, w) { ctx.fillRect(x0, yc - w / 2, x1 - x0, w); }
function rrect(ctx, x, y, w, h, r) {
  ctx.beginPath(); ctx.moveTo(x + r, y); ctx.lineTo(x + w - r, y); ctx.quadraticCurveTo(x + w, y, x + w, y + r);
  ctx.lineTo(x + w, y + h - r); ctx.quadraticCurveTo(x + w, y + h, x + w - r, y + h); ctx.lineTo(x + r, y + h);
  ctx.quadraticCurveTo(x, y + h, x, y + h - r); ctx.lineTo(x, y + r); ctx.quadraticCurveTo(x, y, x + r, y); ctx.closePath();
}
function star(ctx, x, y, r, rot) {
  ctx.beginPath();
  for (let i = 0; i < 10; i++) { const a = rot + (i * Math.PI) / 5; const rr = i % 2 ? r * 0.45 : r; ctx.lineTo(x + Math.cos(a) * rr, y + Math.sin(a) * rr); }
  ctx.closePath();
}
function poly(ctx, x, y, r, n, rot) {
  ctx.beginPath();
  for (let i = 0; i < n; i++) { const a = rot + (i * TAU) / n; ctx.lineTo(x + Math.cos(a) * r, y + Math.sin(a) * r); }
  ctx.closePath();
}

function drawMiniDrone(ctx, x, y, s, spin, color) {
  ctx.save(); ctx.translate(x, y);
  ctx.strokeStyle = INK; ctx.lineWidth = s * 0.16; ctx.lineCap = 'round';
  ctx.beginPath(); ctx.moveTo(-s * 0.55, -s * 0.55); ctx.lineTo(s * 0.55, s * 0.55); ctx.moveTo(s * 0.55, -s * 0.55); ctx.lineTo(-s * 0.55, s * 0.55); ctx.stroke();
  for (const [dx, dy] of [[-1, -1], [1, -1], [1, 1], [-1, 1]]) {
    const rx = dx * s * 0.55, ry = dy * s * 0.55;
    ctx.fillStyle = 'rgba(200,205,210,0.55)'; ctx.beginPath(); ctx.arc(rx, ry, s * 0.34, 0, TAU); ctx.fill();
    ctx.strokeStyle = INK; ctx.lineWidth = s * 0.07; ctx.stroke();
    ctx.beginPath(); const a = spin * (dx * dy); ctx.moveTo(rx + Math.cos(a) * s * 0.3, ry + Math.sin(a) * s * 0.3); ctx.lineTo(rx - Math.cos(a) * s * 0.3, ry - Math.sin(a) * s * 0.3); ctx.stroke();
  }
  ctx.fillStyle = INK; ctx.fillRect(-s * 0.2, -s * 0.2, s * 0.4, s * 0.4);
  if (color) { ctx.fillStyle = color; ctx.beginPath(); ctx.arc(0, 0, s * 0.11, 0, TAU); ctx.fill(); }
  ctx.restore();
}
function grenadeIcon(ctx, x, y, R) {
  ctx.fillStyle = INK; ctx.beginPath(); ctx.ellipse(x, y, R * 0.24, R * 0.17, 0, 0, TAU); ctx.fill();
  ctx.strokeStyle = 'rgba(200,200,200,0.7)'; ctx.lineWidth = R * 0.035;
  ctx.beginPath(); ctx.moveTo(x - R * 0.08, y - R * 0.15); ctx.lineTo(x - R * 0.08, y + R * 0.15); ctx.moveTo(x + R * 0.08, y - R * 0.15); ctx.lineTo(x + R * 0.08, y + R * 0.15); ctx.moveTo(x - R * 0.2, y); ctx.lineTo(x + R * 0.2, y); ctx.stroke();
  ctx.fillStyle = INK; ctx.fillRect(x - R * 0.34, y - R * 0.05, R * 0.12, R * 0.1);
}

// t: animation time, u: unit (optional) for state like drone-ready
function drawInfantry(ctx, type, tc, R, t, u) {
  ctx.fillStyle = tc.main;
  ctx.beginPath(); ctx.arc(0, 0, R, 0, TAU); ctx.fill();
  ctx.strokeStyle = 'rgba(0,0,0,0.32)'; ctx.lineWidth = R * 0.1; ctx.stroke();
  ctx.fillStyle = GUN;
  switch (type) {
    case 'rifleman':
      bar(ctx, -0.33 * R, 1.15 * R, 0.68 * R, 0.22 * R); break;
    case 'mgunner':
      bar(ctx, -0.33 * R, 1.65 * R, 0.68 * R, 0.22 * R);
      ctx.fillRect(-0.14 * R, 0.31 * R, 0.46 * R, 0.27 * R);
      ctx.strokeStyle = GUN; ctx.lineWidth = 0.13 * R; ctx.lineCap = 'round';
      ctx.beginPath(); ctx.moveTo(0.95 * R, 0.68 * R); ctx.lineTo(0.62 * R, 0.4 * R); ctx.moveTo(0.95 * R, 0.68 * R); ctx.lineTo(0.62 * R, 0.98 * R); ctx.stroke();
      break;
    case 'medic':
      ctx.fillStyle = '#fff'; ctx.beginPath(); ctx.arc(0, 0, 0.5 * R, 0, TAU); ctx.fill();
      ctx.fillStyle = '#e0202a'; ctx.fillRect(-0.3 * R, -0.085 * R, 0.6 * R, 0.17 * R); ctx.fillRect(-0.085 * R, -0.3 * R, 0.17 * R, 0.6 * R);
      break;
    case 'officer':
      bar(ctx, -0.4 * R, 1.4 * R, 0.7 * R, 0.22 * R);
      ctx.fillStyle = '#f7d54a'; star(ctx, -0.32 * R, -0.05 * R, 0.4 * R, Math.PI); ctx.fill();
      break;
    case 'scout':
      bar(ctx, -0.33 * R, 0.9 * R, 0.68 * R, 0.22 * R);
      rrect(ctx, 0.3 * R, -0.84 * R, 0.4 * R, 0.24 * R, 0.08 * R); ctx.fill();
      rrect(ctx, 0.3 * R, -0.52 * R, 0.4 * R, 0.24 * R, 0.08 * R); ctx.fill();
      ctx.fillRect(0.42 * R, -0.62 * R, 0.16 * R, 0.14 * R);
      break;
    case 'sniper':
      bar(ctx, -0.3 * R, 2.1 * R, 0.7 * R, 0.2 * R);
      ctx.fillStyle = '#c9cec8'; ctx.fillRect(0.72 * R, 0.5 * R, 0.48 * R, 0.16 * R);
      break;
    case 'droneop':
      ctx.fillStyle = INK; rrect(ctx, 0.82 * R, 0.18 * R, 0.36 * R, 0.66 * R, 0.08 * R); ctx.fill();
      ctx.strokeStyle = '#e9ecef'; ctx.lineWidth = 0.05 * R; ctx.strokeRect(0.9 * R, 0.28 * R, 0.2 * R, 0.46 * R);
      if (!u || u.abilityCd <= 0) drawMiniDrone(ctx, 0.88 * R, -0.72 * R, 0.62 * R, t * 40, null);
      break;
    case 'antitank':
      ctx.fillStyle = GUN; ctx.fillRect(-1.4 * R, 0.17 * R, 2.75 * R, 0.58 * R);
      ctx.fillStyle = '#1b1b1b'; ctx.fillRect(1.2 * R, 0.12 * R, 0.25 * R, 0.68 * R); ctx.fillRect(-1.48 * R, 0.14 * R, 0.18 * R, 0.64 * R);
      break;
    case 'engineer':
      bar(ctx, -0.4 * R, 1.1 * R, 0.78 * R, 0.22 * R);
      ctx.fillRect(0.25 * R, 0.86 * R, 0.55 * R, 0.14 * R);
      ctx.save(); ctx.translate(0.6 * R, -0.95 * R); ctx.rotate(0.6);
      ctx.fillStyle = INK; ctx.fillRect(-0.24 * R, -0.18 * R, 0.48 * R, 0.36 * R);
      ctx.fillStyle = '#c5a332'; ctx.fillRect(-0.06 * R, -0.18 * R, 0.12 * R, 0.36 * R);
      ctx.restore();
      break;
    case 'radioop': {
      ctx.strokeStyle = GUN; ctx.lineWidth = 0.17 * R; ctx.lineCap = 'round';
      ctx.beginPath(); ctx.moveTo(-0.12 * R, 1.05 * R); ctx.quadraticCurveTo(-0.85 * R, 0, -0.12 * R, -1.05 * R); ctx.stroke();
      ctx.lineWidth = 0.13 * R;
      ctx.beginPath(); ctx.moveTo(-0.08 * R, 1.08 * R); ctx.quadraticCurveTo(0.7 * R, 1.3 * R, 1.0 * R, 0.85 * R); ctx.stroke();
      ctx.fillStyle = GUN;
      ctx.beginPath(); ctx.arc(-0.12 * R, 1.05 * R, 0.24 * R, 0, TAU); ctx.fill();
      ctx.beginPath(); ctx.arc(-0.12 * R, -1.05 * R, 0.24 * R, 0, TAU); ctx.fill();
      ctx.fillRect(0.95 * R, 0.76 * R, 0.16 * R, 0.18 * R);
      ctx.fillStyle = INK; rrect(ctx, 0.62 * R, -0.92 * R, 0.56 * R, 0.3 * R, 0.06 * R); ctx.fill();
      ctx.fillStyle = '#9fe0a0'; ctx.fillRect(0.68 * R, -0.86 * R, 0.14 * R, 0.18 * R);
      ctx.strokeStyle = INK; ctx.lineWidth = 0.06 * R; ctx.beginPath(); ctx.moveTo(0.62 * R, -0.85 * R); ctx.lineTo(0.38 * R, -0.88 * R); ctx.stroke();
      break;
    }
    case 'jammer':
      ctx.fillStyle = INK; ctx.beginPath(); ctx.ellipse(1.0 * R, 0, 0.28 * R, 0.82 * R, 0, 0, TAU); ctx.fill();
      ctx.strokeStyle = INK; ctx.lineWidth = 0.15 * R; ctx.lineCap = 'round';
      ctx.beginPath(); ctx.moveTo(0.95 * R, 0.7 * R); ctx.lineTo(0.05 * R, 0.95 * R); ctx.moveTo(0.95 * R, -0.7 * R); ctx.lineTo(0.1 * R, -1.15 * R); ctx.stroke();
      ctx.fillStyle = 'rgba(140,255,200,' + (0.5 + 0.5 * Math.sin(t * 9)) + ')'; ctx.beginPath(); ctx.arc(1.0 * R, 0, 0.12 * R, 0, TAU); ctx.fill();
      drawMiniDrone(ctx, 0.5 * R, -1.3 * R, 0.5 * R, t * 10, null);
      break;
    case 'grenadier':
      bar(ctx, -0.33 * R, 1.15 * R, 0.68 * R, 0.22 * R);
      grenadeIcon(ctx, 0.5 * R, -1.0 * R, R); grenadeIcon(ctx, 0.95 * R, -0.72 * R, R);
      break;
  }
}

// ---------------------------------------------------------------------
// WW1 / WW2 vehicles. Same flat look as the dots: team colour, black outline.
// ---------------------------------------------------------------------
// tracks on both sides; links scroll as the vehicle moves
function tracks(ctx, x0, x1, Wd, w, u) {
  const off = u ? (u.trackAcc || 0) % 5 : 0;
  for (const side of [-1, 1]) {
    const y = side * (Wd / 2 - w / 2 + 1.5);
    ctx.fillStyle = '#1e1e1c'; rrect(ctx, x0, y - w / 2, x1 - x0, w, w / 3); ctx.fill();
    ctx.strokeStyle = '#4a4a44'; ctx.lineWidth = 1; ctx.beginPath();
    for (let x = x0 + 2 + off; x < x1 - 1; x += 5) { ctx.moveTo(x, y - w / 2 + 1); ctx.lineTo(x, y + w / 2 - 1); }
    ctx.stroke();
  }
}
function wheels(ctx, xs, Wd, ww, wl) {
  ctx.fillStyle = INK;
  for (const x of xs) for (const side of [-1, 1]) { rrect(ctx, x - wl / 2, side * Wd / 2 - ww / 2, wl, ww, 2); ctx.fill(); }
}
function outlined(ctx, tc, fill) { ctx.fillStyle = fill || tc.main; ctx.strokeStyle = INK; ctx.lineWidth = 2; ctx.fill(); ctx.stroke(); }
// WW2 lorry cab: long rounded bonnet, mudguards, flat windscreen
function lorryCab(ctx, L, Wd, tc, cabStart) {
  const front = L / 2;
  ctx.beginPath(); ctx.moveTo(cabStart, -Wd / 2 + 1); ctx.lineTo(front - 0.16 * L, -Wd / 2 + 1); ctx.quadraticCurveTo(front - 0.05 * L, -Wd * 0.42, front, -Wd * 0.28); ctx.lineTo(front, Wd * 0.28); ctx.quadraticCurveTo(front - 0.05 * L, Wd * 0.42, front - 0.16 * L, Wd / 2 - 1); ctx.lineTo(cabStart, Wd / 2 - 1); ctx.closePath();
  outlined(ctx, tc);
  ctx.fillStyle = tc.dark; ctx.fillRect(front - 0.15 * L, -Wd * 0.2, 0.13 * L, Wd * 0.4);
  ctx.strokeStyle = 'rgba(0,0,0,0.35)'; ctx.lineWidth = 1; ctx.beginPath();
  for (let k = -2; k <= 2; k++) { ctx.moveTo(front - 0.14 * L, k * Wd * 0.07); ctx.lineTo(front - 0.03 * L, k * Wd * 0.07); }
  ctx.stroke();
  ctx.fillStyle = '#c9cdc4'; ctx.fillRect(cabStart + 0.02 * L, -Wd * 0.4, 0.03 * L, Wd * 0.8);
  ctx.fillStyle = INK; ctx.fillRect(cabStart + 0.06 * L, -Wd / 2 + 2, 0.12 * L, Wd - 4);
}
function lorryBed(ctx, L, Wd, tc, x0, x1, canvas) {
  ctx.beginPath(); ctx.rect(x0, -Wd / 2, x1 - x0, Wd);
  outlined(ctx, tc, canvas ? tc.dark : tc.main);
  if (canvas) {
    ctx.strokeStyle = 'rgba(0,0,0,0.4)'; ctx.lineWidth = 1.2; ctx.beginPath();
    for (let x = x0 + (x1 - x0) / 5; x < x1 - 1; x += (x1 - x0) / 5) { ctx.moveTo(x, -Wd / 2 + 1); ctx.lineTo(x, Wd / 2 - 1); }
    ctx.stroke();
    ctx.fillStyle = 'rgba(255,255,255,0.12)'; ctx.fillRect(x0 + 2, -Wd * 0.08, x1 - x0 - 4, Wd * 0.16);
  }
}

// u carries turret angle (tang relative), recoil, ability state, time
function drawVehicle(ctx, type, tc, L, Wd, rel, recoil, t, u) {
  ctx.lineJoin = 'round'; ctx.lineCap = 'butt';
  switch (type) {
    case 'jeep': { // Willys jeep with a pintle machine gun
      wheels(ctx, [0.3 * L, -0.28 * L], Wd, 6, 9);
      ctx.beginPath(); ctx.moveTo(-L / 2, -Wd / 2 + 2); ctx.lineTo(0.22 * L, -Wd / 2 + 2); ctx.lineTo(0.5 * L, -Wd * 0.34); ctx.lineTo(0.5 * L, Wd * 0.34); ctx.lineTo(0.22 * L, Wd / 2 - 2); ctx.lineTo(-L / 2, Wd / 2 - 2); ctx.closePath();
      outlined(ctx, tc);
      ctx.fillStyle = tc.dark; ctx.fillRect(0.2 * L, -Wd * 0.3, 0.28 * L, Wd * 0.6);
      ctx.fillStyle = '#c9cdc4'; ctx.fillRect(0.13 * L, -Wd * 0.4, 0.04 * L, Wd * 0.8);
      ctx.fillStyle = 'rgba(0,0,0,0.3)'; ctx.fillRect(-0.4 * L, -Wd * 0.34, 0.5 * L, Wd * 0.68);
      ctx.fillStyle = INK; ctx.beginPath(); ctx.arc(-L / 2 - 2, 0, 4.5, 0, TAU); ctx.fill();
      ctx.save(); ctx.translate(-0.16 * L, 0); ctx.rotate(rel);
      ctx.strokeStyle = INK; ctx.lineWidth = 2.4; ctx.beginPath(); ctx.moveTo(-3, 0); ctx.lineTo(15 - recoil * 3, 0); ctx.stroke();
      ctx.fillStyle = INK; ctx.fillRect(-4, -3, 6, 6);
      ctx.restore();
      break;
    }
    case 'lighttank': { // M3/M5 Stuart: sloped glacis, small turret well forward
      tracks(ctx, -L / 2, L / 2, Wd, 6, u);
      ctx.beginPath(); ctx.moveTo(-L * 0.47, -Wd / 2 + 4); ctx.lineTo(L * 0.3, -Wd / 2 + 4); ctx.lineTo(L * 0.47, -Wd * 0.26); ctx.lineTo(L * 0.47, Wd * 0.26); ctx.lineTo(L * 0.3, Wd / 2 - 4); ctx.lineTo(-L * 0.47, Wd / 2 - 4); ctx.closePath();
      outlined(ctx, tc);
      ctx.fillStyle = INK; ctx.fillRect(L * 0.36, Wd * 0.12, 4, 2);
      ctx.save(); ctx.translate(0.02 * L, 0); ctx.rotate(rel);
      ctx.strokeStyle = INK; ctx.lineWidth = 2.6; ctx.beginPath(); ctx.moveTo(0.2 * L - recoil * 4, 0); ctx.lineTo(0.6 * L - recoil * 4, 0); ctx.stroke();
      rrect(ctx, -0.22 * L, -0.34 * Wd, 0.42 * L, 0.68 * Wd, 0.14 * L); outlined(ctx, tc);
      ctx.fillStyle = INK; ctx.fillRect(0.16 * L, -0.12 * Wd, 0.06 * L, 0.24 * Wd);
      ctx.fillStyle = tc.dark; ctx.beginPath(); ctx.arc(-0.08 * L, 0.1 * Wd, 0.07 * L, 0, TAU); ctx.fill();
      ctx.restore();
      break;
    }
    case 'heavytank': { // Tiger: slab-sided hull, big box turret, long 88 with a muzzle brake
      tracks(ctx, -L / 2, L / 2, Wd, 8, u);
      ctx.beginPath(); ctx.rect(-L * 0.48, -Wd / 2 + 5, L * 0.96, Wd - 10); outlined(ctx, tc);
      ctx.fillStyle = tc.dark; ctx.fillRect(-L * 0.46, -Wd * 0.18, L * 0.18, Wd * 0.36);
      ctx.strokeStyle = 'rgba(0,0,0,0.4)'; ctx.lineWidth = 1; ctx.beginPath();
      for (let k = 0; k < 4; k++) { ctx.moveTo(-L * 0.44 + k * 4, -Wd * 0.16); ctx.lineTo(-L * 0.44 + k * 4, Wd * 0.16); }
      ctx.stroke();
      ctx.save(); ctx.translate(-0.02 * L, 0); ctx.rotate(rel);
      ctx.strokeStyle = INK; ctx.lineWidth = 3.2; ctx.beginPath(); ctx.moveTo(0.2 * L - recoil * 5, 0); ctx.lineTo(0.78 * L - recoil * 5, 0); ctx.stroke();
      ctx.fillStyle = INK; ctx.fillRect(0.72 * L - recoil * 5, -3, 0.07 * L, 6);
      rrect(ctx, -0.24 * L, -0.38 * Wd, 0.46 * L, 0.76 * Wd, 4); outlined(ctx, tc);
      ctx.fillStyle = INK; ctx.fillRect(0.18 * L, -0.16 * Wd, 0.06 * L, 0.32 * Wd);
      ctx.fillStyle = tc.dark; ctx.beginPath(); ctx.arc(-0.12 * L, -0.16 * Wd, 0.06 * L, 0, TAU); ctx.fill(); ctx.strokeStyle = INK; ctx.lineWidth = 1.2; ctx.stroke();
      ctx.restore();
      break;
    }
    case 'landship': { // WW1 Mark IV rhomboid: tracks run round the whole hull, guns in side sponsons
      for (const side of [-1, 1]) {
        const y = side * Wd * 0.3;
        ctx.beginPath(); ctx.moveTo(-L / 2, y - Wd * 0.16); ctx.lineTo(L * 0.42, y - Wd * 0.16); ctx.quadraticCurveTo(L / 2 + 3, y, L * 0.42, y + Wd * 0.16); ctx.lineTo(-L / 2, y + Wd * 0.16); ctx.closePath();
        ctx.fillStyle = '#1e1e1c'; ctx.fill();
        ctx.strokeStyle = '#4a4a44'; ctx.lineWidth = 1; ctx.beginPath();
        const off = u ? (u.trackAcc || 0) % 6 : 0;
        for (let x = -L / 2 + 2 + off; x < L * 0.44; x += 6) { ctx.moveTo(x, y - Wd * 0.15); ctx.lineTo(x, y + Wd * 0.15); }
        ctx.stroke();
      }
      ctx.beginPath(); ctx.rect(-L * 0.46, -Wd * 0.24, L * 0.84, Wd * 0.48); outlined(ctx, tc);
      ctx.beginPath(); ctx.rect(L * 0.18, -Wd * 0.12, L * 0.16, Wd * 0.24); outlined(ctx, tc, tc.dark);
      ctx.fillStyle = INK; ctx.fillRect(L * 0.3, -Wd * 0.08, 3, 3); ctx.fillRect(L * 0.3, Wd * 0.05, 3, 3);
      // sponsons: each gun covers its own side
      for (const side of [-1, 1]) {
        const sy = side * (Wd / 2 + 2);
        ctx.beginPath(); ctx.moveTo(-L * 0.08, side * Wd * 0.42); ctx.lineTo(L * 0.12, side * Wd * 0.42); ctx.lineTo(L * 0.08, sy); ctx.lineTo(-L * 0.04, sy); ctx.closePath(); outlined(ctx, tc);
        const want = clamp(angDiff(side * Math.PI / 2, rel), -1.2, 1.2) + side * Math.PI / 2;
        ctx.strokeStyle = INK; ctx.lineWidth = 2.4; ctx.beginPath(); ctx.moveTo(L * 0.02, sy - side * 2); ctx.lineTo(L * 0.02 + Math.cos(want) * (14 - recoil * 3), sy - side * 2 + Math.sin(want) * (14 - recoil * 3)); ctx.stroke();
      }
      ctx.strokeStyle = INK; ctx.lineWidth = 1.5; ctx.beginPath(); ctx.moveTo(-L * 0.46, -Wd * 0.1); ctx.lineTo(-L * 0.6, -Wd * 0.06); ctx.moveTo(-L * 0.46, Wd * 0.1); ctx.lineTo(-L * 0.6, Wd * 0.06); ctx.stroke();
      break;
    }
    case 'radar': { // armoured car (Puma / Greyhound): six wheels, small open turret
      wheels(ctx, [0.3 * L, 0, -0.3 * L], Wd, 6, 10);
      ctx.beginPath(); ctx.moveTo(-L * 0.38, -Wd / 2 + 2); ctx.lineTo(L * 0.32, -Wd / 2 + 2); ctx.lineTo(L / 2, -Wd * 0.2); ctx.lineTo(L / 2, Wd * 0.2); ctx.lineTo(L * 0.32, Wd / 2 - 2); ctx.lineTo(-L * 0.38, Wd / 2 - 2); ctx.lineTo(-L / 2, Wd * 0.2); ctx.lineTo(-L / 2, -Wd * 0.2); ctx.closePath();
      outlined(ctx, tc);
      ctx.fillStyle = tc.dark; ctx.fillRect(L * 0.32, -Wd * 0.12, L * 0.1, Wd * 0.24);
      ctx.save(); ctx.translate(-0.04 * L, 0); ctx.rotate(rel);
      ctx.strokeStyle = INK; ctx.lineWidth = 2.2; ctx.beginPath(); ctx.moveTo(0.1 * L - recoil * 3, 0); ctx.lineTo(0.42 * L - recoil * 3, 0); ctx.stroke();
      ctx.beginPath(); ctx.arc(0, 0, 0.32 * Wd, 0, TAU); outlined(ctx, tc);
      ctx.fillStyle = 'rgba(0,0,0,0.45)'; ctx.beginPath(); ctx.arc(0, 0, 0.2 * Wd, 0, TAU); ctx.fill();
      ctx.restore();
      break;
    }
    case 'aa': { // flak half-track: wheels up front, tracks behind, quad 20 mm in the bed
      wheels(ctx, [0.36 * L], Wd, 6, 10);
      tracks(ctx, -L / 2, 0.12 * L, Wd, 6, u);
      lorryCab(ctx, L, Wd - 6, tc, 0.04 * L);
      ctx.beginPath(); ctx.rect(-L / 2 + 1, -Wd / 2 + 3, 0.56 * L, Wd - 6); outlined(ctx, tc, tc.dark);
      ctx.save(); ctx.translate(-0.2 * L, 0); ctx.rotate(rel);
      const rk = recoil * 3;
      ctx.fillStyle = INK;
      for (const y of [-0.22, -0.08, 0.08, 0.22]) ctx.fillRect(-0.02 * L - rk, y * Wd - 1.2, 0.42 * L, 2.4);
      ctx.beginPath(); ctx.arc(0, 0, 0.2 * Wd, 0, TAU); outlined(ctx, tc);
      ctx.fillStyle = tc.main; ctx.strokeStyle = INK; ctx.lineWidth = 1.6; ctx.beginPath(); ctx.moveTo(0.1 * L, -0.34 * Wd); ctx.lineTo(0.14 * L, 0); ctx.lineTo(0.1 * L, 0.34 * Wd); ctx.stroke();
      ctx.restore();
      break;
    }
    case 'howitzer': { // self-propelled gun (M7 Priest): open fighting compartment, big gun forward
      tracks(ctx, -L / 2, L / 2, Wd, 6, u);
      ctx.beginPath(); ctx.moveTo(-L * 0.47, -Wd / 2 + 4); ctx.lineTo(L * 0.34, -Wd / 2 + 4); ctx.lineTo(L * 0.47, -Wd * 0.22); ctx.lineTo(L * 0.47, Wd * 0.22); ctx.lineTo(L * 0.34, Wd / 2 - 4); ctx.lineTo(-L * 0.47, Wd / 2 - 4); ctx.closePath();
      outlined(ctx, tc);
      ctx.fillStyle = 'rgba(0,0,0,0.35)'; ctx.fillRect(-L * 0.4, -Wd * 0.3, L * 0.62, Wd * 0.6);
      const rk = recoil * 6;
      ctx.fillStyle = tc.main; ctx.strokeStyle = INK; ctx.lineWidth = 1.6;
      ctx.fillRect(-0.12 * L - rk, -0.08 * Wd, 0.72 * L, 0.16 * Wd); ctx.strokeRect(-0.12 * L - rk, -0.08 * Wd, 0.72 * L, 0.16 * Wd);
      ctx.fillStyle = INK; ctx.fillRect(-0.18 * L, -0.2 * Wd, 0.14 * L, 0.4 * Wd);
      ctx.beginPath(); ctx.arc(L * 0.24, Wd * 0.3, 0.1 * Wd, 0, TAU); outlined(ctx, tc, tc.dark);
      break;
    }
    case 'missile': { // V-2 on its Meillerwagen trailer, pulled by a half-track
      wheels(ctx, [0.42 * L], Wd * 0.7, 5, 8);
      tracks(ctx, 0.16 * L, 0.34 * L, Wd * 0.72, 5, u);
      ctx.beginPath(); ctx.rect(0.18 * L, -Wd * 0.3, 0.32 * L, Wd * 0.6); outlined(ctx, tc);
      ctx.fillStyle = '#c9cdc4'; ctx.fillRect(0.32 * L, -Wd * 0.26, 0.03 * L, Wd * 0.52);
      ctx.strokeStyle = INK; ctx.lineWidth = 1.5; ctx.beginPath(); ctx.moveTo(0.18 * L, 0); ctx.lineTo(0.08 * L, 0); ctx.stroke();
      wheels(ctx, [-0.38 * L, -0.22 * L], Wd * 0.8, 5, 8);
      ctx.strokeStyle = INK; ctx.lineWidth = 2;
      ctx.beginPath(); ctx.moveTo(0.08 * L, -Wd * 0.34); ctx.lineTo(-0.48 * L, -Wd * 0.34); ctx.moveTo(0.08 * L, Wd * 0.34); ctx.lineTo(-0.48 * L, Wd * 0.34); ctx.stroke();
      ctx.lineWidth = 1.2; ctx.beginPath(); for (let x = -0.4; x < 0.08; x += 0.12) { ctx.moveTo(x * L, -Wd * 0.34); ctx.lineTo(x * L, Wd * 0.34); } ctx.stroke();
      const ready = !u || u.abilityCd <= 0 ? 1 : clamp(1 - u.abilityCd / ABILITIES.missile.cd, 0, 1);
      if (ready > 0.15) {
        ctx.globalAlpha = ready < 1 ? 0.45 : 1;
        const x0 = -0.5 * L, x1 = 0.1 * L, r = Wd * 0.17;
        ctx.beginPath(); ctx.moveTo(x0, -r); ctx.lineTo(x1 - r * 2, -r); ctx.quadraticCurveTo(x1, -r * 0.6, x1 + 2, 0); ctx.quadraticCurveTo(x1, r * 0.6, x1 - r * 2, r); ctx.lineTo(x0, r); ctx.closePath();
        outlined(ctx, tc, '#ecece4');
        ctx.fillStyle = INK; for (let k = 0; k < 4; k++) ctx.fillRect(x0 + 4 + k * 0.12 * L, k % 2 ? 0 : -r, 0.06 * L, r);
        ctx.beginPath(); ctx.moveTo(x0, -r); ctx.lineTo(x0 + 6, -r); ctx.lineTo(x0 - 2, -r * 2.2); ctx.closePath(); ctx.fill();
        ctx.beginPath(); ctx.moveTo(x0, r); ctx.lineTo(x0 + 6, r); ctx.lineTo(x0 - 2, r * 2.2); ctx.closePath(); ctx.fill();
        ctx.globalAlpha = 1;
      }
      break;
    }
    case 'mlrs': { // Katyusha: lorry with a rack of launch rails over the bed
      wheels(ctx, [0.3 * L, -0.14 * L, -0.34 * L], Wd, 5, 10);
      lorryBed(ctx, L, Wd, tc, -L / 2, 0.08 * L, false);
      lorryCab(ctx, L, Wd, tc, 0.08 * L);
      ctx.save(); ctx.translate(-0.2 * L, 0); ctx.rotate(rel);
      ctx.fillStyle = tc.dark; ctx.strokeStyle = INK; ctx.lineWidth = 1.6;
      ctx.fillRect(-0.3 * L, -0.4 * Wd, 0.62 * L, 0.8 * Wd); ctx.strokeRect(-0.3 * L, -0.4 * Wd, 0.62 * L, 0.8 * Wd);
      ctx.lineWidth = 1.4; ctx.beginPath();
      for (let k = 0; k < 7; k++) { const y = -0.34 * Wd + k * 0.113 * Wd; ctx.moveTo(-0.3 * L, y); ctx.lineTo(0.32 * L, y); }
      ctx.stroke();
      ctx.fillStyle = INK; ctx.fillRect(-0.06 * L, -0.42 * Wd, 0.05 * L, 0.84 * Wd);
      if (u && u.weapons[0] && u.weapons[0].salvo > 0) { ctx.fillStyle = 'rgba(255,200,90,0.85)'; for (let k = 0; k < 7; k++) { ctx.beginPath(); ctx.arc(0.3 * L, -0.34 * Wd + k * 0.113 * Wd, 1.5, 0, TAU); ctx.fill(); } }
      ctx.restore();
      break;
    }
    case 'supply': { // cargo lorry with a canvas tilt; shows its load
      wheels(ctx, [0.3 * L, -0.14 * L, -0.34 * L], Wd, 5, 10);
      lorryBed(ctx, L, Wd, tc, -L / 2, 0.08 * L, true);
      lorryCab(ctx, L, Wd, tc, 0.08 * L);
      if (u && u.cargo) {
        const n = Math.min(6, Math.ceil(((u.cargo.scrap || 0) + (u.cargo.bmats || 0) + (u.cargo.supplies || 0)) / 40));
        for (let k = 0; k < n; k++) { ctx.fillStyle = k % 2 ? '#a88a52' : '#8f733f'; ctx.strokeStyle = INK; ctx.lineWidth = 1; ctx.fillRect(-0.46 * L + (k % 3) * 0.17 * L, (k < 3 ? -0.42 : 0.04) * Wd, 0.14 * L, 0.36 * Wd); ctx.strokeRect(-0.46 * L + (k % 3) * 0.17 * L, (k < 3 ? -0.42 : 0.04) * Wd, 0.14 * L, 0.36 * Wd); }
      }
      break;
    }
  }
}

function drawHQ(ctx, tc, t, hp) {
  // sandbag ring
  for (let i = 0; i < 44; i++) {
    const a = (i / 44) * TAU; if (Math.abs(angDiff(a, 0)) < 0.22) continue;
    ctx.save(); ctx.translate(Math.cos(a) * 112, Math.sin(a) * 92); ctx.rotate(a + Math.PI / 2);
    ctx.fillStyle = '#b5a77a'; rrect(ctx, -8, -4, 16, 8, 3); ctx.fill(); ctx.strokeStyle = '#6f6447'; ctx.lineWidth = 1; ctx.stroke(); ctx.restore();
  }
  ctx.fillStyle = 'rgba(0,0,0,0.3)'; rrect(ctx, -76, -52, 160, 116, 10); ctx.fill();
  ctx.fillStyle = '#3b4037'; rrect(ctx, -82, -60, 160, 116, 10); ctx.fill();
  ctx.strokeStyle = INK; ctx.lineWidth = 3; ctx.stroke();
  ctx.fillStyle = tc.main; rrect(ctx, -70, -48, 136, 92, 6); ctx.fill(); ctx.strokeStyle = INK; ctx.lineWidth = 2; ctx.stroke();
  ctx.fillStyle = tc.dark; ctx.fillRect(-60, -38, 40, 30); ctx.fillRect(-60, 2, 40, 32);
  ctx.strokeStyle = 'rgba(0,0,0,0.4)'; ctx.lineWidth = 1.5;
  for (let k = 0; k < 4; k++) { ctx.beginPath(); ctx.moveTo(-56, -32 + k * 7); ctx.lineTo(-24, -32 + k * 7); ctx.stroke(); }
  ctx.fillStyle = '#fff'; ctx.beginPath(); ctx.arc(22, -2, 26, 0, TAU); ctx.fill();
  ctx.fillStyle = tc.main; star(ctx, 22, -2, 20, -Math.PI / 2); ctx.fill();
  // radar
  ctx.save(); ctx.translate(-40, 30); ctx.fillStyle = '#222'; ctx.beginPath(); ctx.arc(0, 0, 7, 0, TAU); ctx.fill();
  ctx.rotate(t * 1.5); ctx.fillStyle = '#1a1a1a'; ctx.beginPath(); ctx.ellipse(0, 0, 4, 16, 0, 0, TAU); ctx.fill(); ctx.restore();
  // antenna with blinking light
  ctx.fillStyle = INK; ctx.fillRect(56, -54, 4, 24);
  ctx.fillStyle = Math.sin(t * 4) > 0 ? '#ff3b30' : '#5a1512'; ctx.beginPath(); ctx.arc(58, -56, 3.5, 0, TAU); ctx.fill();
  // flag
  ctx.fillStyle = '#ccc'; ctx.fillRect(68, 26, 3, -70);
  ctx.fillStyle = tc.main; ctx.strokeStyle = INK; ctx.lineWidth = 1.5;
  ctx.beginPath(); ctx.moveTo(71, -44);
  for (let k = 0; k <= 6; k++) ctx.lineTo(71 + k * 6, -44 + Math.sin(t * 5 + k * 0.9) * 2.5 * (k / 6));
  for (let k = 6; k >= 0; k--) ctx.lineTo(71 + k * 6, -26 + Math.sin(t * 5 + k * 0.9) * 2.5 * (k / 6));
  ctx.closePath(); ctx.fill(); ctx.stroke();
  if (hp < 0.6) { ctx.fillStyle = 'rgba(20,15,10,0.45)'; ctx.beginPath(); ctx.arc(-20, 10, 30 * (1 - hp), 0, TAU); ctx.fill(); }
}
function drawTurretBld(ctx, tc, rel, recoil) {
  ctx.fillStyle = '#5a5e55'; poly(ctx, 0, 0, 28, 8, Math.PI / 8); ctx.fill(); ctx.strokeStyle = INK; ctx.lineWidth = 2; ctx.stroke();
  ctx.fillStyle = '#6c7066'; poly(ctx, 0, 0, 22, 8, Math.PI / 8); ctx.fill();
  ctx.save(); ctx.rotate(rel);
  ctx.fillStyle = INK; ctx.fillRect(4 - recoil * 4, -2.5, 30, 5);
  ctx.fillRect(4, 7, 18, 3);
  ctx.fillStyle = tc.main; ctx.beginPath(); ctx.arc(0, 0, 14, 0, TAU); ctx.fill(); ctx.lineWidth = 2; ctx.stroke();
  ctx.fillStyle = tc.dark; ctx.fillRect(-8, -5, 7, 10);
  ctx.restore();
}

// a soldier holding a hammer (swinging while t moves) or binoculars, facing +x
function drawTool(ctx, tool, R, t) {
  if (tool === 'hammer') {
    ctx.save(); ctx.translate(R * 0.5, R * 0.75); ctx.rotate(-0.6 + Math.abs(Math.sin(t * 9)) * 1.2);
    ctx.fillStyle = '#6b4a2a'; ctx.fillRect(0, -1.3, R * 1.5, 2.6);
    ctx.fillStyle = '#3a3a38'; ctx.fillRect(R * 1.3, -R * 0.38, R * 0.42, R * 0.76);
    ctx.restore();
  } else {
    ctx.fillStyle = '#2b2b2b'; ctx.fillRect(R * 0.55, -R * 0.5, R * 0.7, R * 0.42); ctx.fillRect(R * 0.55, R * 0.08, R * 0.7, R * 0.42);
  }
}
// ---------------------------------------------------------------------
// structures (drawn translated to the structure and rotated to u.ang;
// lines run along local x, their front is local -y)
// ---------------------------------------------------------------------
function sandbagRow(ctx, x0, x1, y, h, col, edge) {
  const n = Math.max(1, Math.round((x1 - x0) / 11)), w = (x1 - x0) / n;
  for (let i = 0; i < n; i++) {
    rrect(ctx, x0 + i * w + 0.5, y - h / 2, w - 1, h, h * 0.45);
    ctx.fillStyle = col; ctx.fill(); ctx.strokeStyle = edge; ctx.lineWidth = 1; ctx.stroke();
  }
}
function drawStruct(ctx, u, tc, t) {
  const type = u.type;
  const L = (STRUCT_BY_ID[type] && STRUCT_BY_ID[type].len) || 0;
  const bp = !u.built;
  if (bp) ctx.globalAlpha = 0.42;
  switch (type) {
    case 'trench': {
      // dirt berm, the dug channel, duckboards, a sandbag parapet on the front
      ctx.fillStyle = 'rgba(62,50,32,0.85)'; rrect(ctx, -L / 2 - 10, -22, L + 20, 44, 16); ctx.fill();
      ctx.fillStyle = 'rgba(96,80,54,0.7)'; rrect(ctx, -L / 2 - 6, 9, L + 12, 9, 4); ctx.fill();
      ctx.fillStyle = '#211910'; ctx.beginPath();
      const n = 8, step = L / n;
      ctx.moveTo(-L / 2, -9);
      for (let i = 0; i <= n; i++) ctx.lineTo(-L / 2 + i * step, (i % 2 ? -11 : -8));
      for (let i = n; i >= 0; i--) ctx.lineTo(-L / 2 + i * step, (i % 2 ? 8 : 11));
      ctx.closePath(); ctx.fill();
      ctx.fillStyle = '#5f4b30';
      for (let x = -L / 2 + 4; x < L / 2 - 4; x += 9) ctx.fillRect(x, -2.5, 6, 5);
      sandbagRow(ctx, -L / 2 + 2, L / 2 - 2, -14, 7, '#9a8a62', '#5e5238');
      ctx.fillStyle = tc.main; ctx.fillRect(-L / 2 - 4, -3, 4, 6); ctx.fillRect(L / 2, -3, 4, 6);
      break;
    }
    case 'sandbag':
      ctx.fillStyle = 'rgba(0,0,0,0.25)'; rrect(ctx, -L / 2, -6, L + 4, 16, 6); ctx.fill();
      sandbagRow(ctx, -L / 2, L / 2, 3, 8, '#8f8058', '#5b4f36');
      sandbagRow(ctx, -L / 2 + 5, L / 2 - 5, -4, 8, '#ad9c6f', '#5b4f36');
      ctx.fillStyle = tc.main; ctx.fillRect(-2, 7, 4, 3);
      break;
    case 'wire': {
      ctx.strokeStyle = '#3a2a1a'; ctx.lineWidth = 3;
      for (const x of [-L / 2, 0, L / 2]) { ctx.beginPath(); ctx.moveTo(x - 5, -6); ctx.lineTo(x + 5, 6); ctx.moveTo(x + 5, -6); ctx.lineTo(x - 5, 6); ctx.stroke(); }
      ctx.lineWidth = 1.1;
      for (const [col, off] of [['rgba(30,30,28,0.9)', 0], ['rgba(170,170,160,0.55)', -0.8]]) {
        ctx.strokeStyle = col; ctx.beginPath();
        for (let x = -L / 2; x <= L / 2; x += 7) { ctx.moveTo(x + 6 + off, off); ctx.arc(x + off, off, 6, 0, TAU); }
        ctx.stroke();
      }
      ctx.fillStyle = tc.main; ctx.fillRect(-L / 2 - 2, -9, 3, 3);
      break;
    }
    case 'trap':
      ctx.strokeStyle = '#1d1e1c'; ctx.lineWidth = 6; ctx.lineCap = 'round';
      ctx.beginPath(); ctx.moveTo(-11, -11); ctx.lineTo(11, 11); ctx.moveTo(11, -11); ctx.lineTo(-11, 11); ctx.moveTo(0, -13); ctx.lineTo(0, 13); ctx.stroke();
      ctx.strokeStyle = '#5b5e58'; ctx.lineWidth = 3;
      ctx.beginPath(); ctx.moveTo(-11, -11); ctx.lineTo(11, 11); ctx.moveTo(11, -11); ctx.lineTo(-11, 11); ctx.moveTo(0, -13); ctx.lineTo(0, 13); ctx.stroke();
      ctx.lineCap = 'butt';
      break;
    case 'bunker': {
      ctx.fillStyle = 'rgba(0,0,0,0.3)'; poly(ctx, 3, 4, 26, 6, 0); ctx.fill();
      ctx.fillStyle = '#6f7066'; poly(ctx, 0, 0, 26, 6, 0); ctx.fill(); ctx.strokeStyle = INK; ctx.lineWidth = 2; ctx.stroke();
      ctx.fillStyle = '#85867b'; poly(ctx, 0, 0, 18, 6, 0); ctx.fill();
      ctx.fillStyle = tc.dark; ctx.fillRect(-14, -3, 8, 6);
      ctx.save(); ctx.rotate(angDiff(u.ang, u.tang));
      ctx.fillStyle = '#181816'; ctx.fillRect(14, -5, 9, 10);
      ctx.fillStyle = INK; ctx.fillRect(16 - u.recoil * 2, -1.5, 16, 3);
      ctx.restore();
      break;
    }
    case 'tower': {
      ctx.fillStyle = 'rgba(0,0,0,0.3)'; ctx.fillRect(-12, -10, 30, 30);
      ctx.strokeStyle = '#3d2c1a'; ctx.lineWidth = 3;
      ctx.beginPath(); ctx.moveTo(-15, -15); ctx.lineTo(15, 15); ctx.moveTo(15, -15); ctx.lineTo(-15, 15); ctx.stroke();
      ctx.fillStyle = '#7c6242'; ctx.fillRect(-11, -11, 22, 22); ctx.strokeStyle = INK; ctx.lineWidth = 2; ctx.strokeRect(-11, -11, 22, 22);
      ctx.strokeStyle = 'rgba(0,0,0,0.3)'; ctx.lineWidth = 1; for (let y = -7; y < 11; y += 5) { ctx.beginPath(); ctx.moveTo(-11, y); ctx.lineTo(11, y); ctx.stroke(); }
      ctx.fillStyle = tc.main; ctx.beginPath(); ctx.arc(0, 0, 4.5, 0, TAU); ctx.fill(); ctx.strokeStyle = INK; ctx.lineWidth = 1.2; ctx.stroke();
      break;
    }
    case 'fob': {
      ctx.fillStyle = 'rgba(0,0,0,0.3)'; rrect(ctx, -26, -18, 56, 42, 6); ctx.fill();
      ctx.fillStyle = tc.dark; ctx.beginPath(); ctx.moveTo(-28, -20); ctx.lineTo(14, -20); ctx.lineTo(18, 0); ctx.lineTo(14, 20); ctx.lineTo(-28, 20); ctx.closePath(); ctx.fill(); ctx.strokeStyle = INK; ctx.lineWidth = 2; ctx.stroke();
      ctx.strokeStyle = 'rgba(0,0,0,0.35)'; ctx.beginPath(); ctx.moveTo(-28, 0); ctx.lineTo(18, 0); ctx.stroke();
      crates(ctx, u, 22, -14);
      flag(ctx, tc, -24, -16, t);
      break;
    }
    case 'townhall':
      drawTownHall(ctx, tc, t, u);
      break;
  }
  ctx.globalAlpha = 1;
  if (bp) {
    ctx.strokeStyle = 'rgba(255,255,255,0.75)'; ctx.lineWidth = 1.5; ctx.setLineDash([5, 4]);
    if (L) ctx.strokeRect(-L / 2 - 4, -16, L + 8, 32); else { ctx.beginPath(); ctx.arc(0, 0, u.r + 4, 0, TAU); ctx.stroke(); }
    ctx.setLineDash([]);
  }
}
function crates(ctx, u, x, y) {
  const s = u && u.stock; if (!s) return;
  const n = Math.min(6, Math.ceil(s.supplies / 40)), m = Math.min(4, Math.ceil(s.bmats / 50));
  for (let i = 0; i < n; i++) { ctx.fillStyle = '#6b7f3a'; ctx.fillRect(x + (i % 2) * 9, y + ((i / 2) | 0) * 9, 8, 8); ctx.strokeStyle = INK; ctx.lineWidth = 1; ctx.strokeRect(x + (i % 2) * 9, y + ((i / 2) | 0) * 9, 8, 8); }
  for (let i = 0; i < m; i++) { ctx.fillStyle = '#8a8d90'; ctx.fillRect(x - 11, y + i * 7, 9, 6); ctx.strokeStyle = INK; ctx.lineWidth = 1; ctx.strokeRect(x - 11, y + i * 7, 9, 6); }
}
function flag(ctx, tc, x, y, t) {
  ctx.fillStyle = '#ccc'; ctx.fillRect(x - 1, y - 30, 2.5, 34);
  ctx.fillStyle = tc.main; ctx.strokeStyle = INK; ctx.lineWidth = 1.2;
  ctx.beginPath(); ctx.moveTo(x + 1.5, y - 30);
  for (let k = 0; k <= 5; k++) ctx.lineTo(x + 1.5 + k * 4.5, y - 30 + Math.sin(t * 5 + k * 0.9) * 2 * (k / 5));
  for (let k = 5; k >= 0; k--) ctx.lineTo(x + 1.5 + k * 4.5, y - 18 + Math.sin(t * 5 + k * 0.9) * 2 * (k / 5));
  ctx.closePath(); ctx.fill(); ctx.stroke();
}
// a stone town hall with a tiled roof in the team colour; it crumbles as it takes damage
function drawTownHall(ctx, tc, t, u) {
  const hp = u ? u.hp / u.maxHp : 1;
  ctx.fillStyle = 'rgba(0,0,0,0.32)'; ctx.fillRect(-30, -24, 66, 56);
  ctx.fillStyle = '#8b8473'; ctx.fillRect(-34, -28, 66, 56); ctx.strokeStyle = INK; ctx.lineWidth = 2.5; ctx.strokeRect(-34, -28, 66, 56);
  // a pitched roof: two slopes in the team colour, a ridge and rows of tiles
  ctx.fillStyle = tc.dark; ctx.fillRect(-30, -24, 58, 24);
  ctx.fillStyle = tc.main; ctx.globalAlpha *= 0.75; ctx.fillRect(-30, 0, 58, 24); ctx.globalAlpha /= 0.75;
  ctx.fillStyle = 'rgba(0,0,0,0.25)'; ctx.fillRect(-30, -24, 58, 24);
  ctx.strokeStyle = 'rgba(0,0,0,0.3)'; ctx.lineWidth = 1; ctx.beginPath();
  for (let y = -18; y < 24; y += 6) { if (y === 0) continue; ctx.moveTo(-30, y); ctx.lineTo(28, y); }
  ctx.stroke();
  ctx.strokeStyle = '#3d362c'; ctx.lineWidth = 3; ctx.beginPath(); ctx.moveTo(-30, 0); ctx.lineTo(28, 0); ctx.stroke();
  // shell holes in the roof
  if (hp < 0.75) { ctx.fillStyle = '#2a241c'; ctx.beginPath(); ctx.arc(-14, -10, 7 * (1 - hp) + 3, 0, TAU); ctx.fill(); }
  if (hp < 0.45) { ctx.fillStyle = '#2a241c'; ctx.beginPath(); ctx.arc(12, 9, 9 * (1 - hp) + 3, 0, TAU); ctx.fill(); ctx.fillStyle = '#6d6556'; ctx.fillRect(4, 2, 8, 5); }
  // clock tower
  ctx.fillStyle = '#9c9583'; ctx.fillRect(18, -14, 18, 18); ctx.strokeStyle = INK; ctx.lineWidth = 2; ctx.strokeRect(18, -14, 18, 18);
  ctx.fillStyle = '#ece6d2'; ctx.beginPath(); ctx.arc(27, -5, 5, 0, TAU); ctx.fill(); ctx.strokeStyle = INK; ctx.lineWidth = 1; ctx.stroke();
  ctx.beginPath(); ctx.moveTo(27, -5); ctx.lineTo(27 + Math.cos(t * 0.3) * 4, -5 + Math.sin(t * 0.3) * 4); ctx.stroke();
  crates(ctx, u, -22, 31);
  flag(ctx, tc, -38, -24, t);
}

// render a product as a UI icon, facing up
function productIcon(p, size, team) {
  const c = document.createElement('canvas');
  const dpr = Math.min(2, window.devicePixelRatio || 1);
  c.width = c.height = size * dpr; c.style.width = c.style.height = size + 'px';
  const g = c.getContext('2d'); g.scale(dpr, dpr);
  const d = UNITS[p.unit]; const tc = TEAM[team || 0];
  g.translate(size / 2, size / 2);
  g.rotate(-Math.PI / 2);
  if (d.cls === 'inf') {
    const R = size * (p.n > 2 ? 0.23 : 0.3);
    if (p.n > 2) {
      g.save(); g.translate(-R * 0.6, R * 1.5); g.globalAlpha = 0.55; drawInfantry(g, p.unit, tc, R * 0.8, 0); g.restore();
      g.save(); g.translate(-R * 0.6, -R * 1.7); g.globalAlpha = 0.55; drawInfantry(g, p.unit, tc, R * 0.8, 0); g.restore();
    }
    g.translate(-R * 0.15, 0);
    drawInfantry(g, p.unit, tc, R, 0);
  } else {
    const sc = (size * 0.86) / (d.len * 1.15);
    g.scale(sc, sc);
    drawVehicle(g, p.unit, tc, d.len, d.wid, 0, 0, 0.6, null);
  }
  return c;
}
function unitIcon(type, size, team) { return productIcon({ unit: type, n: 1 }, size, team); }
// a squad's badge: its lead unit up front, the next two member types behind it
function kitIcon(kit, size) {
  const c = document.createElement('canvas');
  const dpr = Math.min(2, window.devicePixelRatio || 1);
  c.width = c.height = size * dpr; c.style.width = c.style.height = size + 'px';
  const g = c.getContext('2d'); g.scale(dpr, dpr);
  const types = [...new Set(kit.members.map(([t]) => t))];
  const lead = types[0], rest = types.slice(1, 3);
  const put = (type, x, y, s, a) => {
    const d = UNITS[type];
    g.save(); g.translate(x, y); g.rotate(-Math.PI / 2); g.globalAlpha = a;
    if (d.cls === 'inf') drawInfantry(g, type, TEAM[0], s * 0.22, 0);
    else { const sc = (s * 0.86) / (d.len * 1.15); g.scale(sc, sc); drawVehicle(g, type, TEAM[0], d.len, d.wid, 0, 0, 0.6, null); }
    g.restore();
  };
  rest.forEach((t, i) => put(t, size * (i ? 0.76 : 0.24), size * 0.62, size * 0.62, 0.9));
  put(lead, size * 0.5, size * 0.46, size * (rest.length ? 0.86 : 1), 1);
  return c;
}
