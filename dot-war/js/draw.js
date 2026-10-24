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

function truckBase(ctx, L, Wd, tc, grille) {
  const cabLen = 0.24 * L, front = L / 2, back = -L / 2;
  ctx.fillStyle = INK;
  for (const x of [0.3 * L, 0.06 * L, -0.2 * L, -0.38 * L]) { ctx.fillRect(x - 0.06 * L, -Wd / 2 - 1.6, 0.12 * L, 3.2); ctx.fillRect(x - 0.06 * L, Wd / 2 - 1.6, 0.12 * L, 3.2); }
  if (grille) {
    ctx.fillStyle = tc.main; ctx.fillRect(back - 0.1 * L, -0.33 * Wd, 0.12 * L, 0.66 * Wd);
    ctx.strokeStyle = INK; ctx.lineWidth = 1.5; ctx.strokeRect(back - 0.1 * L, -0.33 * Wd, 0.12 * L, 0.66 * Wd);
    ctx.beginPath(); for (let k = 1; k < 4; k++) { const x = back - 0.1 * L + k * 0.03 * L; ctx.moveTo(x, -0.3 * Wd); ctx.lineTo(x, 0.3 * Wd); } ctx.stroke();
  }
  ctx.fillStyle = tc.main; ctx.strokeStyle = INK; ctx.lineWidth = 2;
  ctx.fillRect(back, -Wd / 2, L - cabLen, Wd); ctx.strokeRect(back, -Wd / 2, L - cabLen, Wd);
  const c0 = front - cabLen, ch = 0.12 * Wd;
  ctx.beginPath(); ctx.moveTo(c0, -Wd / 2); ctx.lineTo(front - ch, -Wd / 2); ctx.lineTo(front, -Wd / 2 + ch); ctx.lineTo(front, Wd / 2 - ch); ctx.lineTo(front - ch, Wd / 2); ctx.lineTo(c0, Wd / 2); ctx.closePath();
  ctx.fill(); ctx.stroke();
  ctx.fillStyle = INK; ctx.fillRect(front - 0.13 * L, -Wd / 2 - 2.5, 2.5, 2.5); ctx.fillRect(front - 0.13 * L, Wd / 2, 2.5, 2.5);
  ctx.fillStyle = '#d3d7db';
  ctx.fillRect(front - 0.095 * L, -0.4 * Wd, 0.07 * L, 0.36 * Wd); ctx.fillRect(front - 0.095 * L, 0.04 * Wd, 0.07 * L, 0.36 * Wd);
}

// u carries turret angle (tang relative), recoil, ability state, time
function drawVehicle(ctx, type, tc, L, Wd, rel, recoil, t, u) {
  ctx.lineJoin = 'round';
  switch (type) {
    case 'lighttank': {
      ctx.fillStyle = '#1d1d1d'; ctx.fillRect(-L / 2 - 1, -Wd / 2 - 2, L + 2, 3.5); ctx.fillRect(-L / 2 - 1, Wd / 2 - 1.5, L + 2, 3.5);
      ctx.fillStyle = tc.main; ctx.strokeStyle = INK; ctx.lineWidth = 2;
      ctx.fillRect(-L / 2, -Wd / 2, L, Wd); ctx.strokeRect(-L / 2, -Wd / 2, L, Wd);
      ctx.save(); ctx.translate(-0.12 * L, 0); ctx.rotate(rel);
      ctx.strokeStyle = INK; ctx.lineWidth = 2.4; ctx.lineCap = 'butt';
      ctx.beginPath(); ctx.moveTo(0.2 * L - recoil * 4, 0); ctx.lineTo(0.74 * L - recoil * 4, 0); ctx.stroke();
      ctx.fillStyle = tc.main; ctx.lineWidth = 2;
      ctx.beginPath(); ctx.ellipse(0, 0, 0.29 * L, 0.45 * Wd, 0, 0, TAU); ctx.fill(); ctx.stroke();
      ctx.fillStyle = 'rgba(0,0,0,0.25)'; ctx.beginPath(); ctx.arc(-0.08 * L, 0.1 * Wd, 0.08 * L, 0, TAU); ctx.fill();
      ctx.restore();
      break;
    }
    case 'heavytank': {
      ctx.fillStyle = '#1d1d1d'; ctx.fillRect(-0.42 * L - 1, -Wd / 2 - 2, 0.93 * L, 4); ctx.fillRect(-0.42 * L - 1, Wd / 2 - 2, 0.93 * L, 4);
      ctx.fillStyle = tc.main; ctx.strokeStyle = INK; ctx.lineWidth = 2;
      ctx.fillRect(-0.5 * L, -0.36 * Wd, 0.1 * L, 0.72 * Wd); ctx.strokeRect(-0.5 * L, -0.36 * Wd, 0.1 * L, 0.72 * Wd);
      ctx.lineWidth = 1.3; ctx.beginPath(); for (let k = 1; k < 4; k++) { const y = -0.36 * Wd + k * 0.18 * Wd; ctx.moveTo(-0.5 * L, y); ctx.lineTo(-0.4 * L, y); } ctx.stroke();
      ctx.lineWidth = 2; ctx.fillRect(-0.42 * L, -Wd / 2, 0.92 * L, Wd); ctx.strokeRect(-0.42 * L, -Wd / 2, 0.92 * L, Wd);
      ctx.save(); ctx.translate(0.08 * L, 0); ctx.rotate(rel);
      ctx.strokeStyle = INK; ctx.lineWidth = 3;
      ctx.beginPath(); ctx.moveTo(0.2 * L - recoil * 5, 0); ctx.lineTo(0.66 * L - recoil * 5, 0); ctx.stroke();
      ctx.fillStyle = INK; ctx.fillRect(0.6 * L - recoil * 5, -2.4, 0.06 * L, 4.8);
      ctx.fillStyle = tc.main; ctx.lineWidth = 2;
      poly(ctx, 0, 0, 0.46 * Wd, 5, 0); ctx.fill(); ctx.stroke();
      ctx.fillStyle = 'rgba(0,0,0,0.25)'; ctx.beginPath(); ctx.arc(-0.12 * Wd, -0.15 * Wd, 0.09 * L, 0, TAU); ctx.fill();
      ctx.restore();
      break;
    }
    case 'radar': {
      truckBase(ctx, L, Wd, tc, true);
      ctx.save(); ctx.translate(-0.12 * L, 0);
      ctx.strokeStyle = INK; ctx.lineWidth = 1.4; ctx.beginPath(); ctx.moveTo(0, 0); ctx.quadraticCurveTo(0.1 * L, 0.3 * Wd, 0.2 * L, 0.18 * Wd); ctx.stroke();
      ctx.fillStyle = INK; ctx.fillRect(0.18 * L, 0.05 * Wd, 2.2, 0.32 * Wd);
      ctx.rotate(t * 2.4);
      ctx.fillStyle = '#222'; ctx.beginPath(); ctx.ellipse(0, 0, 0.09 * L, 0.38 * Wd, 0, 0, TAU); ctx.fill();
      ctx.strokeStyle = '#555'; ctx.lineWidth = 1; ctx.beginPath(); ctx.moveTo(0, -0.34 * Wd); ctx.lineTo(0, 0.34 * Wd); ctx.stroke();
      ctx.restore();
      break;
    }
    case 'aa': {
      ctx.fillStyle = '#1d1d1d'; ctx.fillRect(-L / 2, -Wd / 2 - 2, L, 3.5); ctx.fillRect(-L / 2, Wd / 2 - 1.5, L, 3.5);
      ctx.fillStyle = tc.main; ctx.strokeStyle = INK; ctx.lineWidth = 2;
      ctx.fillRect(-L / 2, -Wd / 2, L, Wd); ctx.strokeRect(-L / 2, -Wd / 2, L, Wd);
      ctx.save(); ctx.translate(0.04 * L, 0); ctx.rotate(rel);
      ctx.fillStyle = INK;
      const rk = recoil * 3;
      rrect(ctx, -0.05 * L - rk, -0.2 * Wd, 0.5 * L, 0.14 * Wd, 1.5); ctx.fill();
      rrect(ctx, -0.05 * L - rk, 0.06 * Wd, 0.5 * L, 0.14 * Wd, 1.5); ctx.fill();
      ctx.fillStyle = tc.main; poly(ctx, 0, 0, 0.47 * Wd, 8, Math.PI / 8); ctx.fill(); ctx.stroke();
      ctx.fillStyle = INK; rrect(ctx, -0.04 * L, -0.42 * Wd, 0.08 * L, 0.16 * Wd, 1.5); ctx.fill();
      rrect(ctx, 0.02 * L, -0.24 * Wd, 0.2 * L, 0.48 * Wd, 2); ctx.fill();
      ctx.restore();
      break;
    }
    case 'howitzer': {
      truckBase(ctx, L, Wd, tc, false);
      ctx.fillStyle = INK; ctx.fillRect(-0.48 * L, -Wd / 2 - 4, 0.06 * L, 4); ctx.fillRect(-0.48 * L, Wd / 2, 0.06 * L, 4);
      ctx.strokeStyle = INK; ctx.lineWidth = 1.3;
      ctx.strokeRect(-0.4 * L, -0.38 * Wd, 0.54 * L, 0.76 * Wd);
      ctx.save(); ctx.translate(-0.24 * L, 0);
      ctx.fillStyle = tc.main; ctx.lineWidth = 1.6;
      ctx.beginPath(); ctx.moveTo(-0.08 * L, -0.42 * Wd); ctx.lineTo(0.08 * L, -0.42 * Wd); ctx.lineTo(0.14 * L, -0.15 * Wd); ctx.lineTo(0.14 * L, 0.15 * Wd); ctx.lineTo(0.08 * L, 0.42 * Wd); ctx.lineTo(-0.08 * L, 0.42 * Wd); ctx.lineTo(-0.14 * L, 0.15 * Wd); ctx.lineTo(-0.14 * L, -0.15 * Wd); ctx.closePath();
      ctx.fill(); ctx.stroke();
      const rk = recoil * 6;
      ctx.fillStyle = tc.main; ctx.fillRect(-0.06 * L - rk, -0.07 * Wd, 0.6 * L, 0.14 * Wd); ctx.strokeRect(-0.06 * L - rk, -0.07 * Wd, 0.6 * L, 0.14 * Wd);
      ctx.fillRect(0.5 * L - rk, -0.12 * Wd, 0.06 * L, 0.24 * Wd); ctx.strokeRect(0.5 * L - rk, -0.12 * Wd, 0.06 * L, 0.24 * Wd);
      ctx.fillRect(-0.1 * L, -0.12 * Wd, 0.12 * L, 0.24 * Wd); ctx.strokeRect(-0.1 * L, -0.12 * Wd, 0.12 * L, 0.24 * Wd);
      ctx.restore();
      break;
    }
    case 'missile': {
      truckBase(ctx, L, Wd, tc, false);
      ctx.strokeStyle = INK; ctx.lineWidth = 1.3;
      ctx.beginPath(); ctx.moveTo(-0.45 * L, -0.3 * Wd); ctx.lineTo(0.18 * L, -0.3 * Wd); ctx.moveTo(-0.45 * L, 0.3 * Wd); ctx.lineTo(0.18 * L, 0.3 * Wd); ctx.stroke();
      ctx.fillStyle = INK; ctx.fillRect(0.08 * L, -0.36 * Wd, 0.05 * L, 0.12 * Wd); ctx.fillRect(0.08 * L, 0.24 * Wd, 0.05 * L, 0.12 * Wd);
      ctx.fillRect(-0.36 * L, -0.36 * Wd, 0.05 * L, 0.12 * Wd); ctx.fillRect(-0.36 * L, 0.24 * Wd, 0.05 * L, 0.12 * Wd);
      ctx.strokeRect(-0.42 * L, -0.2 * Wd, 0.3 * L, 0.4 * Wd);
      const ready = !u || u.abilityCd <= 0 ? 1 : clamp(1 - u.abilityCd / ABILITIES.missile.cd, 0, 1);
      if (ready > 0.15) {
        ctx.globalAlpha = ready < 1 ? 0.45 : 1;
        ctx.fillStyle = '#e8ebee'; ctx.strokeStyle = INK; ctx.lineWidth = 1.2;
        ctx.beginPath(); ctx.moveTo(-0.4 * L, -0.07 * Wd); ctx.lineTo(-0.02 * L, -0.07 * Wd); ctx.lineTo(0.06 * L, 0); ctx.lineTo(-0.02 * L, 0.07 * Wd); ctx.lineTo(-0.4 * L, 0.07 * Wd); ctx.closePath(); ctx.fill(); ctx.stroke();
        ctx.fillStyle = tc.main; ctx.fillRect(-0.06 * L, -0.07 * Wd, 0.04 * L, 0.14 * Wd);
        ctx.fillStyle = INK; ctx.beginPath(); ctx.moveTo(-0.4 * L, -0.07 * Wd); ctx.lineTo(-0.34 * L, -0.07 * Wd); ctx.lineTo(-0.4 * L, -0.2 * Wd); ctx.closePath(); ctx.fill();
        ctx.beginPath(); ctx.moveTo(-0.4 * L, 0.07 * Wd); ctx.lineTo(-0.34 * L, 0.07 * Wd); ctx.lineTo(-0.4 * L, 0.2 * Wd); ctx.closePath(); ctx.fill();
        ctx.globalAlpha = 1;
      }
      break;
    }
    case 'mlrs': {
      truckBase(ctx, L, Wd, tc, false);
      ctx.save(); ctx.translate(-0.17 * L, 0); ctx.rotate(rel);
      const pl = 0.56 * L, pw = 0.62 * Wd;
      ctx.fillStyle = tc.main; ctx.strokeStyle = INK; ctx.lineWidth = 2;
      rrect(ctx, -pl / 2, -pw / 2, pl, pw, 3); ctx.fill(); ctx.stroke();
      ctx.lineWidth = 1.3; ctx.beginPath();
      for (let k = 1; k < 5; k++) { const y = -pw / 2 + (k * pw) / 5; ctx.moveTo(-pl / 2 + 2, y); ctx.lineTo(pl / 2 - 2, y); }
      ctx.stroke();
      ctx.lineWidth = 2.6; ctx.beginPath(); ctx.moveTo(0.02 * L, -pw / 2 - 1); ctx.lineTo(-0.02 * L, pw / 2 + 1); ctx.moveTo(0.06 * L, -pw / 2 - 1); ctx.lineTo(0.02 * L, pw / 2 + 1); ctx.stroke();
      if (u && u.weapons[0] && u.weapons[0].salvo > 0) { ctx.fillStyle = 'rgba(255,200,90,0.8)'; for (let k = 0; k < 5; k++) { ctx.beginPath(); ctx.arc(pl / 2 - 2, -pw / 2 + ((k + 0.5) * pw) / 5, 1.6, 0, TAU); ctx.fill(); } }
      ctx.restore();
      break;
    }
    case 'supply': {
      truckBase(ctx, L, Wd, tc, false);
      ctx.strokeStyle = 'rgba(0,0,0,0.35)'; ctx.lineWidth = 1;
      ctx.beginPath(); for (let k = 1; k < 5; k++) { const x = -L / 2 + (k * (0.76 * L)) / 5; ctx.moveTo(x, -Wd / 2 + 2); ctx.lineTo(x, Wd / 2 - 2); } ctx.stroke();
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
    const R = size * 0.23;
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
