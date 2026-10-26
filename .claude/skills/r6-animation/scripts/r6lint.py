"""
r6lint - catch the mistakes that make R6 animations look broken or amateur.

Each finding is (level, message). Levels: ERROR (will break / clearly wrong),
WARN (will probably look bad), INFO (craft suggestion, use judgement).
"""

from __future__ import annotations

import math

from r6core import (CF, JOINT_KEYS, PART_SIZE, Anim, angle_between, box_corners,
                    forward_kinematics, limb_tip, range_for, sample, sample_times)

CLIP_PAIRS = (
    ("Right Arm", "Torso"), ("Left Arm", "Torso"),
    ("Right Arm", "Head"), ("Left Arm", "Head"),
    ("Right Arm", "Left Arm"), ("Right Leg", "Left Leg"),
    ("Right Arm", "Right Leg"), ("Left Arm", "Left Leg"),
)
CLIP_TOLERANCE = 0.12  # studs of overlap ignored (touching at rest is normal)

# Collision boxes (size, centre offset in the part's space). Arms/legs skip their top: the
# R6 shoulder pivot is 0.5 studs below the top of the arm (hip pivot at the leg's top outer
# corner), so ANY raise sinks the top of the limb into the torso - an unavoidable R6 look.
# What matters is the forearm/hand or shin/foot going through the body.
CLIP_BOX = {
    "Torso": ((2, 2, 1), (0, 0, 0)),
    "Head": ((1.2, 1.2, 1.2), (0, 0, 0)),
    "Right Arm": ((0.8, 1.0, 0.8), (0, -0.5, 0)),  # lower half = forearm + hand
    "Left Arm": ((0.8, 1.0, 0.8), (0, -0.5, 0)),
    "Right Leg": ((0.8, 1.2, 0.8), (0, -0.4, 0)),
    "Left Leg": ((0.8, 1.2, 0.8), (0, -0.4, 0)),
}


def _clip_cf(parts, name):
    size, off = CLIP_BOX[name]
    return parts[name] * CF(*off), size


def _axes(cf: CF):
    r = cf.r
    return [(r[0], r[3], r[6]), (r[1], r[4], r[7]), (r[2], r[5], r[8])]


def _dot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def _cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def obb_overlap(a: CF, sa, b: CF, sb) -> float:
    """Separating-axis test. Returns penetration depth along the best axis (<=0: apart)."""
    ax, bx = _axes(a), _axes(b)
    ha, hb = [s / 2 for s in sa], [s / 2 for s in sb]
    d = (b.x - a.x, b.y - a.y, b.z - a.z)
    axes = ax + bx + [_cross(u, v) for u in ax for v in bx]
    best = float("inf")
    for L in axes:
        n = math.sqrt(_dot(L, L))
        if n < 1e-6:
            continue
        L = (L[0] / n, L[1] / n, L[2] / n)
        ra = sum(h * abs(_dot(u, L)) for h, u in zip(ha, ax))
        rb = sum(h * abs(_dot(v, L)) for h, v in zip(hb, bx))
        pen = ra + rb - abs(_dot(d, L))
        if pen <= 0:
            return pen
        best = min(best, pen)
    return best


def _ranges(ts):
    """Group sorted sample times into contiguous ranges for compact reporting."""
    out = []
    for t in ts:
        if out and t - out[-1][1] < 0.034:
            out[-1][1] = t
        else:
            out.append([t, t])
    return ", ".join(f"{a:.2f}s" if abs(a - b) < 1e-9 else f"{a:.2f}-{b:.2f}s" for a, b in out)


def lint(anim: Anim) -> list[tuple[str, str]]:
    f: list[tuple[str, str]] = []
    add = lambda lvl, msg: f.append((lvl, msg))
    tracks = anim.tracks()
    L = anim.length

    # ---- structure / timing
    if L <= 0:
        add("ERROR", "animation has zero length: add a keyframe after t=0")
        return f
    for a, b in zip(anim.keys, anim.keys[1:]):
        if b.time - a.time < 1 / 60 - 1e-9:
            add("WARN", f"keys at {a.time:.3f}s and {b.time:.3f}s are less than one 60fps frame apart")
    for m in anim.markers:
        if not 0 <= m.time <= L + 1e-9:
            add("ERROR", f"marker '{m.name}' at {m.time:.3f}s is outside the animation (0-{L:.3f}s)")

    # ---- channel ranges / units
    for i, k in enumerate(anim.keys):
        for j, ch in k.channels.items():
            for c, v in ch.items():
                lo, hi = range_for(j, c)
                if not lo <= v <= hi:
                    unit = "studs" if j == "Torso" and c in ("right", "up", "forward") else "deg"
                    hint = " (Torso right/up/forward are STUDS, not degrees)" if unit == "studs" and abs(v) > 5 else ""
                    add("WARN", f"key #{i} @{k.time:.3f}s {j}.{c} = {v:g} {unit} is outside the usual "
                                f"range [{lo:g}, {hi:g}]{hint}")

    # ---- loop seam
    if anim.loop:
        start, end = sample(anim, 0.0, tracks), sample(anim, L, tracks)
        bad = []
        for j in JOINT_KEYS:
            ang = angle_between(start[j], end[j])
            dist = math.dist(start[j].pos, end[j].pos)
            if ang > 0.5 or dist > 0.01:
                bad.append(f"{j} ({ang:.1f} deg, {dist:.2f} studs)")
        if bad:
            add("ERROR", "loop seam pops: the last key must equal the first. Differs: " + ", ".join(bad)
                + '. Fix: make the last keyframe {"t": END, "from": 0}.')
        # velocity continuity across the seam: speed just before the end vs just after the start
        dt = 2 / 60
        if L > 4 * dt:
            a, b = sample(anim, L - dt, tracks), sample(anim, dt, tracks)
            hitches = []
            for j in JOINT_KEYS:
                d_in, d_out = angle_between(a[j], end[j]), angle_between(start[j], b[j])
                ab = angle_between(a[j], b[j])
                through = abs(ab - (d_in + d_out)) < abs(ab - abs(d_in - d_out))  # keeps going, not reversing
                v_in, v_out = d_in / dt, d_out / dt
                hi, lo = max(v_in, v_out), min(v_in, v_out)
                if through and hi > 60 and hi > 3 * lo:
                    hitches.append(f"{j} ({v_in:.0f} deg/s in, {v_out:.0f} deg/s out)")
            if hitches:
                add("WARN", "loop seam hitches: these joints are mid-motion at the seam but change speed "
                    "when it wraps: " + ", ".join(hitches) + ". Match the easing of the last and first "
                    "segments (e.g. both linear), or move the seam to an extreme pose")
    elif anim.priority in ("Idle", "Movement") and not anim.loop and any(
            w in anim.name.lower() for w in ("idle", "walk", "run")):
        add("INFO", f"priority {anim.priority} but loop=false: idles and locomotion are normally looped")

    if anim.loop and anim.priority.startswith("Action"):
        add("INFO", f"looped animation at {anim.priority} priority: fine for held poses (aim, block, carry); "
                    "idle/walk/run cycles usually use Idle/Movement so attacks can override them")

    # ---- easing / spacing
    eases = [k.ease for k in anim.keys[:-1]] + [e for k in anim.keys for e in k.joint_ease.values()]
    if len(anim.keys) >= 3 and eases and all(e.style == "linear" for e in eases):
        add("WARN", "every segment is linear: motion will look robotic. Use inout for most moves, "
                    "'in' into impacts, 'out' out of them, constant for snaps")
    gaps = [b.time - a.time for a, b in zip(anim.keys, anim.keys[1:])]
    if len(gaps) >= 4 and max(gaps) - min(gaps) < 1e-6 and len({str(e) for e in eases}) == 1:
        add("INFO", "keys are evenly spaced with identical easing (metronome timing). Real motion "
                    "has contrast: quick actions, longer holds and recoveries")

    # ---- body usage
    if L >= 0.4 and len(anim.keys) >= 3:
        moving = {j for j in JOINT_KEYS if len(tracks[j]) >= 2 and any(
            angle_between(tracks[j][0][1], tf) > 1 or math.dist(tracks[j][0][1].pos, tf.pos) > 0.02
            for _, tf, _ in tracks[j])}
        if "Torso" not in moving:
            add("INFO", "Torso never moves. R6 has no spine/elbows/knees, so torso twist/lean and a "
                        "small root bob (Torso up) carry most of the life in an R6 animation")
        if "Head" not in moving and L >= 0.8:
            add("INFO", "Head never moves: a small delayed head follow (overlap) adds a lot")

    # ---- twinning (left/right doing the identical thing)
    for a_, b_ in (("RightArm", "LeftArm"), ("RightLeg", "LeftLeg")):
        both = [k for k in anim.keys if a_ in k.channels and b_ in k.channels]
        if len(both) >= 2 and all(_same(k.channels[a_], k.channels[b_]) for k in both):
            moving = any(not _same(both[0].channels[a_], k.channels[a_]) for k in both)
            if moving:
                add("INFO", f"{a_} and {b_} mirror each other exactly on every key (twinning). "
                            "Offset one side's timing by 1-3 frames or vary the angles")

    # ---- geometry over time: clipping, ground contact, foot sliding
    times = sample_times(anim, 60)
    frames = [forward_kinematics(sample(anim, t, tracks)) for t in times]
    clips = {}
    for t, parts in zip(times, frames):
        for a_, b_ in CLIP_PAIRS:
            pen = obb_overlap(*_clip_cf(parts, a_), *_clip_cf(parts, b_))
            if pen > CLIP_TOLERANCE:
                clips.setdefault((a_, b_), []).append((t, pen))
    for (a_, b_), hits in clips.items():
        worst = max(p for _, p in hits)
        lvl = "WARN" if worst > 0.3 else "INFO"
        add(lvl, f"{a_} clips into {b_} by up to {worst:.2f} studs at {_ranges([t for t, _ in hits])}")

    if anim.grounded:
        # Every frame between two non-airborne keys should have a foot on the floor.
        air = [k.airborne for k in anim.keys]
        kt = [k.time for k in anim.keys]
        floats, sinks = [], []
        for t, parts in zip(times, frames):
            i = max(0, max(n for n, x in enumerate(kt) if x <= t + 1e-9))
            nxt = min(i + 1, len(kt) - 1)
            on_key = abs(kt[i] - t) < 1e-6
            if air[i] or (not on_key and air[nxt]):
                continue
            low = min(p[1] for leg in ("Right Leg", "Left Leg") for p in box_corners(parts[leg], PART_SIZE[leg]))
            if low > 0.12:
                floats.append((t, low))
            elif low < -0.2:
                sinks.append((t, -low))
        if floats:
            worst = max(floats, key=lambda x: x[1])
            add("WARN", f"feet float above the ground (worst {worst[1]:.2f} studs at {worst[0]:.2f}s; "
                        f"{_ranges([t for t, _ in floats])}). Add \"ground\": true to the keys (or the spec), "
                        "add an in-between key, or mark in-air keys \"airborne\": true")
        if sinks:
            worst = max(sinks, key=lambda x: x[1])
            add("WARN", f"a leg sinks into the ground (worst {worst[1]:.2f} studs at {worst[0]:.2f}s; "
                        f"{_ranges([t for t, _ in sinks])}). Use \"ground\": true, or an in-between key: a leg "
                        "swung A degrees lifts its foot 2*(1-cos A) studs")

    # ---- planted feet must not skate (one-shots / anything without a locomotion speed)
    if anim.grounded and not anim.speed:
        worst = (0.0, None, None)
        for leg in ("Right Leg", "Left Leg"):
            start = None
            for t, parts in zip(times, frames):
                tip = limb_tip(parts, leg)
                if tip[1] < 0.12 and not _in_air(anim, t):
                    if start is None:
                        start = (t, tip)
                    d = math.hypot(tip[0] - start[1][0], tip[2] - start[1][2])
                    if d > worst[0]:
                        worst = (d, leg, (start[0], t))
                else:
                    start = None
        if worst[0] > 0.25:
            d, leg, (t0, t1) = worst
            add("WARN", f"{leg}'s foot skates {d:.2f} studs while on the floor ({t0:.2f}-{t1:.2f}s). "
                        "Put \"plant\": true on the grounded keys (it locks the feet and re-aims the legs), "
                        "or move the foot deliberately with a step (lift it: airborne leg key)")

    # ---- strikes: where does the hitting hand travel into each marker?
    for m in anim.markers:
        if m.time <= 0:
            continue
        t0 = max(0.0, m.time - 0.07)
        p0 = forward_kinematics(sample(anim, t0, tracks))
        p1 = forward_kinematics(sample(anim, m.time, tracks))
        moves = {arm: [b - a for a, b in zip(limb_tip(p0, arm), limb_tip(p1, arm))] for arm in ("Right Arm", "Left Arm")}
        arm = max(moves, key=lambda k: math.hypot(*moves[k]))
        dx, dy, dz = moves[arm]
        dist = math.hypot(dx, dy, dz)
        if dist < 0.2:
            continue
        tip = limb_tip(p1, arm)
        msg = (f"marker '{m.name}' @{m.time:.3f}s: {arm.split()[0].lower()} hand travels {dist:.2f} studs in the last "
               f"{m.time - t0:.2f}s (forward {-dz:+.2f}, right {dx:+.2f}, up {dy:+.2f}); at contact it is "
               f"{-(tip[2] - p1['Torso'].z):.2f} studs in front of the torso")
        striking = any(w in m.name.lower() for w in ("hit", "strike", "impact", "contact", "punch", "slash"))
        if striking and -dz < -0.3 and dy < 0.5:
            add("WARN", msg + ". The fist is moving AWAY from the front: check the torso twist direction "
                              "(left-hand strikes twist +, right-hand strikes twist -)")
        else:
            add("INFO", msg)

    if anim.loop and anim.grounded:
        scrapes = []
        for i in range(1, len(times)):
            dt = times[i] - times[i - 1]
            for leg in ("Right Leg", "Left Leg"):
                a, b = limb_tip(frames[i - 1], leg), limb_tip(frames[i], leg)
                if b[1] < -0.06 and (a[2] - b[2]) / dt > 2:  # under the floor while swinging forward
                    scrapes.append((times[i], -b[1]))
        if scrapes:
            worst = max(d for _, d in scrapes)
            add("INFO", f"the swinging foot passes {worst:.2f} studs under the floor ({_ranges([t for t, _ in scrapes])}). "
                        "Rigid R6 legs can't bend to clear the ground: add 'out' (~5-10 deg) to the swing leg "
                        "around passing, or accept it (common in R6; the floor hides it)")

    if anim.speed and anim.loop:
        f.extend(_foot_slide(anim, times, frames))
    return f


def _in_air(anim: Anim, t: float) -> bool:
    """True inside a segment that starts or ends on an airborne key."""
    kt = [k.time for k in anim.keys]
    i = max(n for n, x in enumerate(kt) if x <= t + 1e-9)
    nxt = min(i + 1, len(kt) - 1)
    return anim.keys[i].airborne or (abs(kt[i] - t) > 1e-6 and anim.keys[nxt].airborne)


def _same(a: dict, b: dict) -> bool:
    keys = set(a) | set(b)
    return all(abs(a.get(k, 0) - b.get(k, 0)) < 0.5 for k in keys)


def natural_speed(anim: Anim, times=None, frames=None):
    """How fast (studs/s) the character must move for the planted foot not to slide."""
    tracks = anim.tracks()
    times = times or sample_times(anim, 60)
    frames = frames or [forward_kinematics(sample(anim, t, tracks)) for t in times]
    vs = []
    for i in range(1, len(times)):
        dt = times[i] - times[i - 1]
        if dt <= 0:
            continue
        tips = {leg: (limb_tip(frames[i - 1], leg), limb_tip(frames[i], leg)) for leg in ("Right Leg", "Left Leg")}
        # +Z = backward: the planted foot is one on the floor sweeping back at character speed
        planted = [(tips[l][1][2] - tips[l][0][2]) / dt for l in tips
                   if tips[l][1][1] <= 0.15 and tips[l][1][2] > tips[l][0][2]]
        if planted:
            vs.append(max(planted))
    if not vs:
        return None, None
    vs.sort()
    n = len(vs)
    med = vs[n // 2]
    spread = (vs[min(n - 1, int(n * 0.9))] - vs[int(n * 0.1)]) / 2  # robust: ignores contact spikes
    return med, spread


def _foot_slide(anim: Anim, times, frames):
    out = []
    med, spread = natural_speed(anim, times, frames)
    if med is None:
        return [("WARN", "speed is set but no foot ever touches the ground, so foot sliding can't be checked")]
    target = anim.speed
    if med <= 0.05:
        out.append(("WARN", f"the planted foot doesn't travel backward (median {med:.2f} studs/s): at "
                            f"{target:g} studs/s the feet will skate. Legs must sweep back while on the ground"))
        return out
    ratio = target / med
    msg = (f"cycle matches {med:.1f} studs/s; character moves at {target:g}. ")
    if abs(ratio - 1) <= 0.12:
        out.append(("INFO", msg + "Feet stay planted (within 12%)."))
    else:
        out.append(("WARN", msg + f"Feet will slide. Either play it with AdjustSpeed({ratio:.2f}) "
                    f"(cycle length becomes {anim.length / ratio:.3f}s), or change stride: leg swing "
                    f"amplitude/cycle length so 2*(2*sin(A)) per {anim.length / 2:.3f}s step = {target:g} studs/s"))
    if spread > 0.6 * med:
        out.append(("INFO", f"planted-foot speed is uneven (+/-{spread:.1f} studs/s): use linear or near-linear "
                            "easing on leg swings during ground contact"))
    return out


def report(anim: Anim) -> str:
    findings = lint(anim)
    order = {"ERROR": 0, "WARN": 1, "INFO": 2}
    findings.sort(key=lambda x: order[x[0]])
    lines = [f"{anim.name}: {anim.length:.3f}s, {len(anim.keys)} keys, "
             f"{'loop' if anim.loop else 'one-shot'}, priority {anim.priority}"]
    if anim.speed is None and anim.loop:
        med, _ = natural_speed(anim)
        if med and med > 2:
            lines.append(f"  (cycle's planted foot travels at {med:.1f} studs/s; set \"speed\" to check sliding)")
    if not findings:
        lines.append("  clean: no findings")
    for lvl, msg in findings:
        lines.append(f"  {lvl:5} {msg}")
    return "\n".join(lines)
