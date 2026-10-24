'use strict';
// =====================================================================
// AI commander
//  - Intel: remembers every enemy it has seen (no map hacks), estimates
//    local strength and the enemy's army composition
//  - Economy: opening build order, then counter-builds against what it saw
//  - Command: forms task forces, scores capture points, attacks with
//    enough force, pincers from two sides, detaches garrisons, retreats
//    from losing fights, runs an artillery battery behind the front,
//    posts scouts and snipers on observation posts, lays mines
//  - Micro: dodges incoming strikes, focuses fire, kites, pulls back
//    wounded units to medics / supply trucks
// =====================================================================

const ROLE_RANK = { armor: 0, aa: 0.5, line: 1, at: 1, recon: 1.5, support: 2, arty: 4 };
function formationRank(u) { if (u.type === 'supply' || u.type === 'radar') return 3; return ROLE_RANK[u.def.role] ?? 2; }
const unitPower = (u) => (u.def.power || 50) * (u.hp / u.maxHp) * (u.type === 'hq' ? 0 : 1);

class AICommander {
  constructor(team, diffKey) {
    this.team = team; this.enemy = 1 - team;
    this.p = DIFFS[diffKey] || DIFFS.veteran;
    this.mem = new Map();
    this.squads = []; this.reserve = new Set(); this.battery = new Set(); this.recon = []; this.garrisons = [];
    this.thinkT = rand(0.3, 0.8); this.microT = 0.2;
    this.sqId = 1; this.ops = [];
    this.hqPush = false;
    this.dir = team === 0 ? 1 : -1;
    this.bo = [['rifle', 'rifle', 'scout', 'rifle', 'mg', 'at', 'rifle', 'medic', 'gren'], ['ltank', 'sup', 'aa']];
    this.boI = [0, 0];
    this.saving = null;
    this.lastArtyT = -99;
  }
  get T() { return G.teams[this.team]; }
  get hq() { return G.teams[this.team].hq; }

  update(dt) {
    this.microT -= dt; this.thinkT -= dt;
    if (this.microT <= 0) { this.microT = 0.35; this.micro(); }
    if (this.thinkT <= 0) {
      this.thinkT = this.p.think * rand(0.85, 1.15);
      this.updateIntel(); this.economy(); this.organize(); this.strategy();
      for (const s of this.squads.slice()) this.runSquad(s);
      this.manageGarrisons(); this.manageBattery(); this.manageRecon();
    }
  }

  // ---------------------------------------------------------------- intel
  updateIntel() {
    const now = G.time;
    for (const u of G.units) if (u.team === this.enemy && !u.dead && u.vis[this.team]) this.mem.set(u.id, { u, x: u.x, y: u.y, t: now });
    for (const [id, m] of this.mem) {
      if (m.u.dead || now - m.t > 55) { this.mem.delete(id); continue; }
      // we are looking at where it was and it's gone: forget the stale position
      if (m.t < now && !m.u.vis[this.team] && cellVisible(this.team, m.x, m.y) && now - m.t > 4) this.mem.delete(id);
    }
    for (const p of G.points) {
      p.ai = p.ai || [{}, {}];
      p.ai[this.team] = { enemy: this.enemyPower(p.x, p.y, 650), own: this.ownPower(p.x, p.y, 650) };
    }
    // enemy composition (value share by category)
    const c = { armor: 0, inf: 0, arty: 0, drones: 0, aa: 0, missile: 0, total: 1 };
    for (const m of this.mem.values()) {
      const d = m.u.def; const v = d.value || 50;
      if (d.cls === 'bld') continue;
      c.total += v;
      if (d.role === 'armor') c.armor += v;
      else if (d.role === 'arty') { c.arty += v; if (m.u.type === 'missile') c.missile++; }
      else if (d.cls === 'inf') c.inf += v;
      if (m.u.type === 'droneop') c.drones++;
      if (m.u.type === 'aa' || m.u.type === 'jammer') c.aa++;
    }
    this.comp = c;
    // remember enemy artillery activity near us
    this.enemyArtyActive = G.impacts.some((i) => i.team === this.enemy && now - i.t < 15);
  }
  enemyPower(x, y, r) {
    const now = G.time, r2 = r * r; let s = 0;
    for (const m of this.mem.values()) {
      if (dist2(m.x, m.y, x, y) > r2) continue;
      const age = now - m.t; const w = age < 8 ? 1 : Math.max(0.25, 1 - (age - 8) / 40);
      s += unitPower(m.u) * w;
    }
    return s;
  }
  ownPower(x, y, r) {
    const r2 = r * r; let s = 0;
    for (const u of G.units) if (u.team === this.team && !u.dead && u.cls !== 'bld' && dist2(u.x, u.y, x, y) < r2) s += unitPower(u);
    return s;
  }
  totalPower(team) { let s = 0; for (const u of G.units) if (u.team === team && !u.dead && u.cls !== 'bld') s += unitPower(u); return s; }

  // ---------------------------------------------------------------- economy
  economy() {
    const T = this.T;
    // a share of income is ring-fenced for the motor pool so vehicles keep coming
    const now = G.time, dt = now - (this.ecoT || now); this.ecoT = now;
    const behind = this.totalPower(this.team) < (this.enemyEst || 0) * 0.8 || this.homeThreat > 200;
    const frac = G.time < 100 ? 0.25 : G.time < 300 ? 0.45 : 0.55;
    this.vehFund = Math.min(1100, (this.vehFund || 0) + T.income * frac * dt);
    for (const line of [1, 0]) {
      if (T.queues[line].length >= 2) continue;
      const id = this.chooseProduct(line);
      if (!id) continue;
      const prod = PRODUCT_BY_ID[id];
      const opening = this.boI[line] < this.bo[line].length;
      const spendable = line === 1 || opening || behind ? T.supply : T.supply - Math.min(this.vehFund, T.supply);
      if (spendable < prod.cost) continue;
      if (!queueProduct(this.team, prod)) {
        if (line === 1) this.vehFund = Math.max(0, this.vehFund - prod.cost);
        if (opening && this.bo[line][this.boI[line]] === id) this.boI[line]++;
      }
    }
  }
  chooseProduct(line) {
    const T = this.T;
    if (this.boI[line] < this.bo[line].length) return this.bo[line][this.boI[line]];
    // home under attack: cheap, fast infantry
    if (line === 0 && this.homeThreat > 200) return pick(['rifle', 'at', 'gren', 'mg']);
    const c = this.comp || { armor: 0, inf: 0, arty: 0, drones: 0, aa: 0, missile: 0, total: 1 };
    const eArmor = c.armor / c.total, eInf = c.inf / c.total, eArty = c.arty / c.total;
    const w = { rifle: 11, mg: 6, medic: 3, officer: 2.5, scout: 2.5, sniper: 2.5, drone: 3.5, at: 6, eng: 3, radio: 3.5, jammer: 1, gren: 5, ltank: 9, htank: 10, radar: 2, aa: 2.5, how: 4.5, msl: 2.5, mlrs: 5, sup: 3 };
    w.at += 22 * eArmor; w.drone += 12 * eArmor; w.htank += 6 * eArmor; w.eng += 4 * eArmor;
    w.mg += 10 * eInf; w.gren += 8 * eInf; w.mlrs += 6 * eInf; w.how += 3 * eInf; w.aa += 3 * eInf;
    w.jammer += 3 * c.drones; w.aa += 2.5 * c.drones + 4 * c.missile;
    if (eArty > 0.1) { w.radar += 4; w.drone += 4; w.ltank += 3; }
    if (G.time < 240) { w.msl = 0; w.htank *= 0.5; w.how *= 0.5; w.mlrs *= 0.5; }
    else if (G.time > 380) w.msl = 6;
    // counts and caps
    const have = {}, value = {}; let total = 1;
    for (const u of G.units) if (u.team === this.team && !u.dead && u.def.product) { const id = u.def.product; have[id] = (have[id] || 0) + 1; value[id] = (value[id] || 0) + u.def.value; total += u.def.value; }
    for (const q of T.queues) for (const it of q) { const id = it.p.id; have[id] = (have[id] || 0) + it.p.n; value[id] = (value[id] || 0) + it.p.cost; total += it.p.cost; }
    const caps = { radar: 2, sup: 3, msl: this.p === DIFFS.general ? 2 : 1, officer: 3, medic: 8, jammer: 3, radio: 3, aa: 3, sniper: 4, scout: 6, drone: 5, how: 4, mlrs: 3, ltank: 8 };
    let sumW = 0; for (const k in w) sumW += w[k];
    let best = null, bn = -1e9;
    for (const p of PRODUCTS) {
      if (p.line !== line) continue;
      if (caps[p.id] != null && (have[p.id] || 0) + p.n > caps[p.id]) continue;
      const need = w[p.id] / sumW - (value[p.id] || 0) / total + rand(0, 0.025);
      if (need > bn) { bn = need; best = p; }
    }
    if (!best) return null;
    // saving up: wait if it will be affordable soon, otherwise take the best thing we can afford now
    if (T.supply < best.cost && T.supply + T.income * (line ? 28 : 10) < best.cost) {
      let alt = null, an = -1e9;
      for (const p of PRODUCTS) { if (p.line !== line || p.cost > T.supply) continue; if (caps[p.id] != null && (have[p.id] || 0) + p.n > caps[p.id]) continue; const need = w[p.id] / sumW - (value[p.id] || 0) / total; if (need > an) { an = need; alt = p; } }
      if (alt) return alt.id;
    }
    return best.id;
  }

  onDeploy(units, prod) {
    for (const u of units) {
      if (u.def.role === 'arty') this.battery.add(u);
      else if (u.type === 'scout' || u.type === 'sniper') this.recon.push({ u, post: null, t: 0 });
      else this.reserve.add(u);
    }
  }

  // ---------------------------------------------------------------- organisation
  organize() {
    const T = this.T;
    const hq = this.hq; if (!hq) return;
    T.rally = { x: hq.x + this.dir * 480, y: hq.y };
    for (const u of this.reserve) if (u.dead) this.reserve.delete(u);
    for (const u of this.battery) if (u.dead) this.battery.delete(u);
    this.recon = this.recon.filter((r) => !r.u.dead);
    this.homeThreat = this.enemyPower(hq.x, hq.y, 900);
    let rp = 0; for (const u of this.reserve) rp += unitPower(u);
    const minPow = clamp(110 + G.time * 1.3, 110, 1500);
    const urgent = this.homeThreat > 120 || G.points.some((p) => p.owner === this.team && p.ai[this.team].enemy > p.ai[this.team].own);
    if (rp >= minPow || (urgent && rp >= 120)) {
      const units = [...this.reserve].filter((u) => dist(u.x, u.y, T.rally.x, T.rally.y) < 700 || urgent);
      if (units.length) {
        const s = { id: this.sqId++, units: new Set(units), state: 'idle', obj: null, initPower: 0, t: 0, orderT: -99 };
        for (const u of units) { this.reserve.delete(u); u.squad = s; }
        s.initPower = units.reduce((a, u) => a + unitPower(u), 0);
        this.squads.push(s);
      }
    }
  }

  squadInfo(s) {
    let x = 0, y = 0, n = 0, pow = 0, spread = 0;
    for (const u of s.units) { if (u.dead) { s.units.delete(u); continue; } x += u.x; y += u.y; n++; pow += unitPower(u); }
    if (!n) return null;
    x /= n; y /= n;
    for (const u of s.units) spread = Math.max(spread, dist(u.x, u.y, x, y));
    s.x = x; s.y = y; s.n = n; s.power = pow; s.spread = spread;
    return s;
  }

  // ---------------------------------------------------------------- strategy
  strategy() {
    this.squads = this.squads.filter((s) => this.squadInfo(s));
    // fold splintered squads into the nearest healthy one
    for (const s of this.squads.slice()) {
      if (s.n > 3 || s.state === 'stage') continue;
      let best = null, bd = 1100;
      for (const o of this.squads) { if (o === s || o.state === 'retreat' || o.n <= 3) continue; const d = dist(o.x, o.y, s.x, s.y); if (d < bd) { bd = d; best = o; } }
      if (!best && s.state !== 'retreat') continue;
      const units = [...s.units];
      this.squads.splice(this.squads.indexOf(s), 1);
      if (best) {
        for (const u of units) { best.units.add(u); u.squad = best; }
        best.initPower += s.power;
        issueMove(units, best.x, best.y, true);
        this.squadInfo(best);
      } else {
        for (const u of units) { u.squad = null; this.reserve.add(u); }
      }
    }
    // reserves top up the most worn squad that is still in the fight
    let rp = 0; for (const u of this.reserve) rp += unitPower(u);
    if (rp > 150) {
      let weak = null, wk = 0.65;
      for (const s of this.squads) { if (s.state !== 'attack' && s.state !== 'hold') continue; const k = s.power / Math.max(1, s.initPower); if (k < wk) { wk = k; weak = s; } }
      if (weak) {
        const T = this.T;
        const units = [...this.reserve].filter((u) => dist(u.x, u.y, T.rally.x, T.rally.y) < 600);
        if (units.length) {
          for (const u of units) { this.reserve.delete(u); weak.units.add(u); u.squad = weak; }
          issueMove(units, weak.x, weak.y, true);
          this.squadInfo(weak);
          weak.initPower = Math.max(weak.initPower, weak.power);
        }
      }
    }
    const ehq = G.teams[this.enemy].hq;
    const held = G.points.filter((p) => p.owner === this.team).length;
    const myPow = this.totalPower(this.team);
    let enemyEst = 0; for (const m of this.mem.values()) enemyEst += unitPower(m.u);
    this.enemyEst = enemyEst;
    this.hqPush = !!ehq && !ehq.dead && (held >= 7 || (G.teams[this.enemy].tickets < 260 && myPow > enemyEst * 1.3) || (G.time > 900 && myPow > enemyEst * 2.2 && held >= 5));

    // objectives
    const objs = [];
    const home = this.hq;
    for (const p of G.points) {
      const info = p.ai[this.team];
      const dHome = home ? dist(home.x, home.y, p.x, p.y) : 0;
      if (p.owner !== this.team) {
        const v = 100 + (p.owner === -1 ? 55 : 35) + (p.letter === 'E' ? 25 : 0) - dHome / 55;
        objs.push({ kind: 'attack', p, x: p.x, y: p.y, value: v, need: info.enemy * 1.3 + 70, got: 0 });
      } else if (info.enemy > 30) {
        objs.push({ kind: 'defend', p, x: p.x, y: p.y, value: 170 + info.enemy / 6, need: info.enemy * 1.15, got: 0 });
      }
    }
    if (this.homeThreat > 100 && home) objs.push({ kind: 'defend', p: null, x: home.x + this.dir * 250, y: home.y, value: 400, need: this.homeThreat * 1.2, got: 0 });
    if (this.hqPush) objs.push({ kind: 'hq', p: null, x: ehq.x, y: ehq.y, value: 260, need: 0, got: 0 });
    this.objs = objs;

    // squads already committed count towards their objective
    for (const s of this.squads) {
      if (!s.obj || s.state === 'retreat') continue;
      const o = objs.find((o) => o.kind === s.obj.kind && o.p === s.obj.p && (o.p || o.kind !== 'defend' || dist(o.x, o.y, s.obj.x, s.obj.y) < 50));
      if (o) o.got += s.power; else if (s.state !== 'hold') { s.obj = null; s.state = 'idle'; }
    }
    // assign free squads
    const free = this.squads.filter((s) => s.state === 'idle' || (s.state === 'hold' && this.holdIsSafe(s)));
    free.sort((a, b) => b.power - a.power);
    for (const s of free) {
      let best = null, bs = -1e9;
      for (const o of objs) {
        if (s.state === 'hold' && s.obj && o.p === s.obj.p) continue;
        const short = o.need - o.got;
        let sc = o.value - dist(s.x, s.y, o.x, o.y) / 28;
        if (short <= 0 && o.kind !== 'hq') sc -= 120; // already handled
        else if (s.power + o.got < o.need) sc -= 70 * Math.min(2, (o.need - o.got - s.power) / Math.max(60, s.power));
        if (sc > bs) { bs = sc; best = o; }
      }
      if (!best) continue;
      if (s.state === 'hold' && bs < 40) continue; // not worth leaving the point
      if (s.state === 'hold') this.detachGarrison(s);
      // pincer: borrow a second free squad and come from two sides
      if (this.p.pincer && best.kind === 'attack' && best.need > s.power * 0.9 && !this.ops.some((op) => op.obj.p === best.p)) {
        const partner = free.find((o) => o !== s && o.state === 'idle' && dist(o.x, o.y, s.x, s.y) < 1800);
        if (partner && s.power + partner.power > best.need * 0.9) {
          this.startPincer([s, partner], best);
          best.got += s.power + partner.power;
          continue;
        }
      }
      best.got += s.power;
      s.obj = { kind: best.kind, p: best.p, x: best.x, y: best.y };
      s.state = best.kind === 'hq' ? 'hq' : 'attack';
      s.orderT = -99;
    }
    // pincer ops
    for (const op of this.ops.slice()) {
      op.squads = op.squads.filter((s) => this.squads.includes(s) && s.state === 'stage');
      op.t += this.p.think;
      const ready = op.squads.every((s) => dist(s.x, s.y, s.stage.x, s.stage.y) < 260 && s.spread < 300);
      if (!op.squads.length || ready || op.t > 40) {
        for (const s of op.squads) { s.state = 'attack'; s.orderT = -99; }
        this.ops.splice(this.ops.indexOf(op), 1);
      }
    }
  }
  startPincer(squads, obj) {
    const hq = this.hq;
    const base = Math.atan2(obj.y - hq.y, obj.x - hq.x) + Math.PI;
    const op = { obj, squads, t: 0 };
    squads.forEach((s, i) => {
      const a = base + (i ? 0.95 : -0.95);
      let sx = clamp(obj.x + Math.cos(a) * 700, 80, W - 80), sy = clamp(obj.y + Math.sin(a) * 700, 80, H - 80);
      const c = nearestOpen(cellOf(sx, sy)); sx = (c % GW + 0.5) * CELL; sy = (((c / GW) | 0) + 0.5) * CELL;
      s.stage = { x: sx, y: sy };
      s.obj = { kind: 'attack', p: obj.p, x: obj.x, y: obj.y };
      s.state = 'stage';
      issueMove([...s.units], sx, sy, true, { spacing: 1.2 });
    });
    this.ops.push(op);
  }
  holdIsSafe(s) { return s.obj && s.obj.p && s.obj.p.ai[this.team].enemy < 40 && G.time - (s.holdSince || 0) > 12; }
  detachGarrison(s) {
    const p = s.obj && s.obj.p; if (!p) return;
    if (this.garrisons.some((g) => g.p === p && g.units.some((u) => !u.dead))) return;
    const inf = [...s.units].filter((u) => u.type === 'rifleman' || u.type === 'mgunner').sort((a, b) => a.def.value - b.def.value).slice(0, s.n > 8 ? 3 : 0);
    if (!inf.length) return;
    for (const u of inf) { s.units.delete(u); u.squad = null; }
    const g = { p, units: inf };
    this.garrisons.push(g);
    this.positionAround(inf, p, 150, true);
  }
  manageGarrisons() {
    this.garrisons = this.garrisons.filter((g) => (g.units = g.units.filter((u) => !u.dead)).length && g.p.owner !== this.enemy);
  }

  // where should a squad fall back to
  retreatPoint(s) {
    const hq = this.hq;
    let best = null, bd = 1e9;
    for (const p of G.points) {
      if (p.owner !== this.team) continue;
      const info = p.ai[this.team];
      if (info.enemy > info.own * 0.8) continue;
      if (dist(p.x, p.y, hq.x, hq.y) > dist(s.x, s.y, hq.x, hq.y) - 150) continue;
      const d = dist(p.x, p.y, s.x, s.y); if (d < bd) { bd = d; best = p; }
    }
    return best ? { x: best.x - this.dir * 120, y: best.y } : this.T.rally;
  }

  runSquad(s) {
    if (!this.squadInfo(s)) { this.squads.splice(this.squads.indexOf(s), 1); return; }
    const units = [...s.units];
    const now = G.time;
    const localE = this.enemyPower(s.x, s.y, 650);
    const localO = this.ownPower(s.x, s.y, 650);
    // retreat from fights we're losing, or when worn down
    if (s.state !== 'retreat' && s.state !== 'idle') {
      const losing = localE > 60 && localO / localE < this.p.retreatRatio;
      const worn = s.power < s.initPower * 0.3 && localE > 30;
      if ((losing || worn) && s.state !== 'hq') {
        s.state = 'retreat'; s.worn = worn || s.power < s.initPower * 0.45;
        const rp = this.retreatPoint(s);
        s.retreatTo = rp;
        issueMove(units, rp.x, rp.y, false);
        s.orderT = now;
        return;
      }
    }
    const spacing = this.enemyArtyActive ? 1.8 : 1.25;
    switch (s.state) {
      case 'idle': {
        if (now - s.orderT > 15 && dist(s.x, s.y, this.T.rally.x, this.T.rally.y) > 400 && !s.obj) { issueMove(units, this.T.rally.x, this.T.rally.y, true); s.orderT = now; }
        break;
      }
      case 'stage': break;
      case 'attack': case 'hq': {
        const o = s.obj; if (!o) { s.state = 'idle'; break; }
        if (s.state === 'attack' && o.p && o.p.owner === this.team && dist(s.x, s.y, o.p.x, o.p.y) < 260) {
          s.state = 'hold'; s.holdSince = now; this.positionAround(units, o.p, 200, false); s.orderT = now; break;
        }
        if (s.state === 'hq') { const ehq = G.teams[this.enemy].hq; if (!ehq || ehq.dead) { s.state = 'idle'; s.obj = null; break; } }
        // engage the nearest known enemy cluster near our path
        const fight = this.nearestEnemy(s.x, s.y, 520);
        if (fight) {
          if (now - s.orderT > 3.5) { issueMove(units, fight.x, fight.y, true, { spacing }); s.orderT = now; }
          this.focusFire(s);
        } else if (now - s.orderT > 7 || s.lastGoal !== o) {
          // gather up stragglers before rolling in
          let gx = o.x, gy = o.y;
          if (s.spread > 520 && dist(s.x, s.y, o.x, o.y) > 900) { gx = s.x; gy = s.y; }
          issueMove(units, gx, gy, true, { spacing });
          s.orderT = now; s.lastGoal = o;
        }
        break;
      }
      case 'hold': {
        const p = s.obj && s.obj.p; if (!p) { s.state = 'idle'; break; }
        if (p.owner !== this.team && p.owner !== -1) { s.state = 'attack'; s.orderT = -99; break; }
        const fight = this.nearestEnemy(p.x, p.y, 560);
        if (fight) { if (now - s.orderT > 4) { issueMove(units, fight.x, fight.y, true, { spacing }); s.orderT = now; s.engaged = true; } this.focusFire(s); }
        else if (s.engaged || now - s.orderT > 30) { s.engaged = false; this.positionAround(units, p, 200, false); s.orderT = now; }
        break;
      }
      case 'retreat': {
        const rp = s.retreatTo || this.T.rally;
        if (dist(s.x, s.y, rp.x, rp.y) < 250 || now - s.orderT > 40) {
          if (s.worn) { for (const u of units) { u.squad = null; this.reserve.add(u); } this.squads.splice(this.squads.indexOf(s), 1); }
          else { s.state = 'idle'; s.obj = null; s.initPower = Math.max(s.power, s.initPower * 0.8); }
        }
        break;
      }
    }
  }
  nearestEnemy(x, y, r) {
    let best = null, bd = r * r; const now = G.time;
    for (const m of this.mem.values()) {
      if (now - m.t > 6 || m.u.cls === 'bld' && m.u.type === 'hq' && !this.hqPush) continue;
      const d = dist2(m.x, m.y, x, y); if (d < bd) { bd = d; best = m; }
    }
    return best;
  }
  focusFire(s) {
    if (!this.p.focus) return;
    let best = null, bs = 0;
    for (const e of G.grid.query(s.x, s.y, 480)) {
      if (e.team !== this.enemy || e.dead || !e.vis[this.team] || e.cls === 'air') continue;
      const hp = Math.max(30, e.hp);
      const sc = ((e.def.value || 50) + (e.def.dps || 5) * 3) / hp * (e.cls === 'bld' ? 0.3 : 1);
      if (sc > bs) { bs = sc; best = e; }
    }
    for (const u of s.units) {
      if (!best || !u.weapons.length) { u.focus = null; continue; }
      const w = u.weapons[0];
      u.focus = (w.def.vs[best.cls] || 0) >= 0.5 ? best : null;
    }
  }
  // spread units around a point, infantry hugging forest cover where there is some
  positionAround(units, p, r, preferCover) {
    const forest = [];
    markRect(p.x - r - 60, p.y - r - 60, p.x + r + 60, p.y + r + 60, (i, x, y) => { if (MAP.terr[i] === T_FOREST && dist(x, y, p.x, p.y) < r + 60) forest.push({ x, y }); });
    const n = units.length;
    units.forEach((u, i) => {
      let tx, ty;
      if (u.cls === 'inf' && forest.length && (preferCover || i % 2 === 0)) { const f = forest[(i * 7) % forest.length]; tx = f.x + rand(-10, 10); ty = f.y + rand(-10, 10); }
      else {
        const front = Math.atan2(0, -this.dir) + Math.PI; // facing the enemy side
        const a = front + ((i / Math.max(1, n - 1)) - 0.5) * 2.4 + rand(-0.1, 0.1);
        const rr = u.cls === 'veh' ? r * 0.65 : rand(r * 0.35, r * 0.9);
        tx = p.x + Math.cos(a) * rr; ty = p.y + Math.sin(a) * rr;
        if (u.def.role === 'support' || u.def.role === 'arty') { tx = p.x - this.dir * rand(40, 110); ty = p.y + rand(-80, 80); }
      }
      if (blockedAt(tx, ty)) { tx = p.x + rand(-40, 40); ty = p.y + rand(-40, 40); }
      issueMove([u], tx, ty, true);
    });
  }

  // ---------------------------------------------------------------- artillery
  frontLine() {
    // average of where our fighting squads are, else the most contested point
    let x = 0, y = 0, n = 0;
    for (const s of this.squads) if (s.state === 'attack' || s.state === 'hold' || s.state === 'hq') { x += s.x; y += s.y; n++; }
    if (n) return { x: x / n, y: y / n };
    const hq = this.hq; return { x: hq.x + this.dir * 1600, y: hq.y };
  }
  manageBattery() {
    if (!this.battery.size) return;
    const hq = this.hq; const front = this.frontLine();
    let k = 0;
    for (const u of this.battery) {
      if (u.dead) continue;
      k++;
      const threat = this.enemyPower(u.x, u.y, 600);
      let tx, ty;
      if (u.type === 'missile') { tx = hq.x + this.dir * 380; ty = hq.y + (k % 2 ? -220 : 220); }
      else {
        const rng = u.weapons[0].def.range;
        const back = rng * 0.55;
        const ang = Math.atan2(hq.y - front.y, hq.x - front.x);
        tx = front.x + Math.cos(ang) * back + rand(-40, 40); ty = front.y + Math.sin(ang) * back + (k % 3 - 1) * 140;
        if (threat > 80) { tx = u.x + (hq.x - u.x) * 0.35; ty = u.y + (hq.y - u.y) * 0.35; }
      }
      tx = clamp(tx, 100, W - 100); ty = clamp(ty, 100, H - 100);
      const c = nearestOpen(cellOf(tx, ty)); tx = (c % GW + 0.5) * CELL; ty = (((c / GW) | 0) + 0.5) * CELL;
      if (dist(u.x, u.y, tx, ty) > (threat > 80 ? 60 : 320) && (!u.order || G.time - (u.batT || 0) > 12)) { issueMove([u], tx, ty, false); u.batT = G.time; }
    }
  }

  // ---------------------------------------------------------------- recon
  manageRecon() {
    const hq = this.hq;
    const targets = (this.objs || []).filter((o) => o.p).sort((a, b) => b.value - a.value);
    let i = 0;
    for (const r of this.recon) {
      const u = r.u;
      const threat = this.enemyPower(u.x, u.y, 300);
      if (threat > 60 && u.hp < u.maxHp * 0.6) { r.post = null; if (!u.override) issueMove([u], this.T.rally.x, this.T.rally.y, false); continue; }
      if (r.post && G.time - r.t < 45) continue;
      const o = targets[i++ % Math.max(1, targets.length)];
      if (!o) continue;
      const back = u.type === 'sniper' ? 380 : 320;
      const ang = Math.atan2(hq.y - o.y, hq.x - o.x) + rand(-0.6, 0.6);
      let px = o.x + Math.cos(ang) * back, py = o.y + Math.sin(ang) * back;
      // prefer a forest cell nearby
      let best = null, bd = 1e9;
      markRect(px - 200, py - 200, px + 200, py + 200, (ci, x, y) => { if (MAP.terr[ci] === T_FOREST) { const d = dist(x, y, px, py); if (d < bd) { bd = d; best = { x, y }; } } });
      if (best) { px = best.x; py = best.y; }
      if (blockedAt(px, py)) continue;
      r.post = { x: px, y: py }; r.t = G.time;
      issueMove([u], px, py, false);
    }
  }

  mineSpot(eng) {
    const mine = G.mines.filter((m) => m.team === this.team).length;
    if (mine >= 10 || this.enemyPower(eng.x, eng.y, 600) > 0 || (eng.order && eng.order.type === 'ability')) return;
    const cands = [];
    for (const p of G.points) {
      if (p.owner !== this.team) continue;
      for (const r of MAP.roads) for (let i = 0; i < r.length; i += 3) {
        const q = r[i]; const d = dist(q.x, q.y, p.x, p.y);
        if (d < 160 || d > 380) continue;
        if ((q.x - p.x) * this.dir < 0) continue; // enemy side of the point
        if (dist(q.x, q.y, eng.x, eng.y) > 700) continue;
        if (G.mines.some((m) => m.team === this.team && dist(m.x, m.y, q.x, q.y) < 90)) continue;
        cands.push(q);
      }
    }
    if (!cands.length) return;
    const q = pick(cands);
    eng.order = { type: 'ability', x: q.x + rand(-8, 8), y: q.y + rand(-8, 8) };
    eng.path = null; eng.repathT = 0;
  }

  // ---------------------------------------------------------------- micro
  micro() {
    const now = G.time;
    const threats = [];
    if (this.p.dodge) {
      for (const w of G.warnings) if (w.team === this.enemy) threats.push({ x: w.x, y: w.y, r: w.r + 45 });
      for (const i of G.impacts) if (i.team === this.enemy && now - i.t < 2.5) threats.push({ x: i.x, y: i.y, r: 95 });
    }
    for (const u of G.units) {
      if (u.team !== this.team || u.dead || u.def.speed === 0 || u.player) continue;
      // dodge
      if (threats.length && !(u.override && u.override.dodge)) {
        for (const t of threats) {
          const d = dist(u.x, u.y, t.x, t.y);
          if (d < t.r) {
            const a = d > 1 ? Math.atan2(u.y - t.y, u.x - t.x) : rand(0, TAU);
            const out = t.r + 60;
            let ox = t.x + Math.cos(a) * out, oy = t.y + Math.sin(a) * out;
            if (blockedAt(ox, oy)) { ox = t.x - Math.cos(a) * out; oy = t.y - Math.sin(a) * out; }
            u.override = { x: ox, y: oy, t: 2.6, dodge: true };
            break;
          }
        }
        if (u.override) continue;
      }
      if (u.override) continue;
      // wounded: go find a medic / supply truck / engineer
      if (u.cls === 'veh' && u.hp < u.maxHp * 0.35 && u.def.role !== 'arty') {
        const fix = this.findHelper(u, (o) => o.type === 'supply' || o.type === 'engineer', 1600);
        if (fix) { u.override = { x: fix.x + rand(-30, 30), y: fix.y + rand(-30, 30), t: 6 }; continue; }
        if (u.hp < u.maxHp * 0.22) { const hq = this.hq; u.override = { x: hq.x + this.dir * 200, y: hq.y + rand(-120, 120), t: 25 }; continue; }
      }
      if (u.cls === 'inf' && u.hp < u.maxHp * 0.35 && u.type !== 'medic') {
        const med = this.findHelper(u, (o) => o.type === 'medic' || o.type === 'supply', 500);
        if (med && dist(u.x, u.y, med.x, med.y) > 60) { u.override = { x: med.x, y: med.y, t: 3 }; continue; }
      }
      // kite: long-range units step back from short-range attackers
      if (this.p.kite && u.weapons.length) {
        const w = u.weapons[0]; const R = w.def.range;
        if (R >= 350 && !w.def.arty) {
          let close = null, cd = R * 0.5;
          for (const e of G.grid.query(u.x, u.y, cd)) {
            if (e.team !== this.enemy || e.dead || !e.vis[this.team] || e.cls === 'air' || e.cls === 'bld') continue;
            const er = e.weapons && e.weapons.length ? e.weapons[0].def.range : 0;
            if (er >= R * 0.9) continue;
            const d = dist(u.x, u.y, e.x, e.y); if (d < cd) { cd = d; close = e; }
          }
          if (close) {
            const a = Math.atan2(u.y - close.y, u.x - close.x);
            const ox = u.x + Math.cos(a) * 110, oy = u.y + Math.sin(a) * 110;
            if (!blockedAt(ox, oy)) u.override = { x: ox, y: oy, t: 1.3 };
          }
        }
      }
    }
    // forget old impacts
    while (G.impacts.length && now - G.impacts[0].t > 20) G.impacts.shift();
  }
  // the player takes a squad: forget it
  release(units) {
    const set = new Set(units);
    for (const u of units) {
      if (u.squad) { u.squad.units.delete(u); u.squad = null; }
      this.reserve.delete(u); this.battery.delete(u);
      u.override = null; u.focus = null;
    }
    this.recon = this.recon.filter((r) => !set.has(r.u));
    for (const g of this.garrisons) g.units = g.units.filter((u) => !set.has(u));
  }
  // the player hands a squad back: put it straight to work
  adopt(units) {
    const line = [];
    for (const u of units) {
      if (u.dead) continue;
      if (u.def.role === 'arty') this.battery.add(u);
      else if (u.type === 'scout' || u.type === 'sniper') this.recon.push({ u, post: null, t: 0 });
      else line.push(u);
    }
    if (!line.length) return;
    const s = { id: this.sqId++, units: new Set(line), state: 'idle', obj: null, initPower: 0, t: 0, orderT: -99 };
    for (const u of line) u.squad = s;
    this.squadInfo(s); s.initPower = s.power;
    this.squads.push(s);
  }
  findHelper(u, pred, r) {
    let best = null, bd = r * r;
    for (const o of G.units) { if (o.team !== this.team || o.dead || o === u || !pred(o)) continue; const d = dist2(o.x, o.y, u.x, u.y); if (d < bd) { bd = d; best = o; } }
    return best;
  }
}
