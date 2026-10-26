"""
r6pose - read a pose the way an R6 animator does.

For any instant of an animation: what holds the body up (support), where the soles really
are (lowest corners of the rigid leg blocks, not the joints), where the weight is (centre of
mass over the support area), how big the stance is, how far the body dropped, and how the
head and arms sit relative to the torso. Used by the linter, `r6anim.py report` and
`r6anim.py compare`.
"""

from __future__ import annotations

import math

from r6core import (PART_SIZE, RENDER_SIZE, Anim, body_to_channels, box_corners, forward_kinematics,
                    limb_tip, sample, sole_top, transform_to_body)

# Relative masses ~ visible volume (the Head mesh is ~1.2 studs cubed).
MASS = {"Torso": 4.0, "Head": 1.7, "Right Arm": 2.0, "Left Arm": 2.0, "Right Leg": 2.0, "Left Leg": 2.0}
CONTACT = 0.12  # a corner within this height of the floor is touching it
LEGS = (("Left Leg", "left"), ("Right Leg", "right"))


def center_of_mass(parts):
    total = sum(MASS.values())
    return tuple(sum(MASS[p] * parts[p].pos[i] for p in MASS) / total for i in range(3))


def lowest(parts, part):
    size = PART_SIZE[part] if part != "Head" else RENDER_SIZE["Head"]
    return min(c[1] for c in box_corners(parts[part], size))


def contacts(parts, part):
    """Floor-touching corners of a part as (x, z)."""
    return [(c[0], c[2]) for c in box_corners(parts[part], PART_SIZE[part]) if c[1] <= CONTACT]


def edge_lift(parts, part):
    """How high the lifted edge of a tilted sole sits (its highest corner). 0 = the sole is
    level; a leg splayed out A degrees lifts it about sin(A) studs while the other edge touches."""
    return sole_top(parts[part])


TOUCH = 0.15  # sole points within this height of the floor count as touching it


def sole_contact(parts, part, n=11):
    """Fraction of the sole (0..1) within TOUCH of the floor. A rigid R6 leg has no ankle, so the
    more it tilts the less of its sole touches: standing/crouching feet should be >= 0.5."""
    cf = parts[part]
    ys = [cf.point((i / (n - 1) - 0.5, -1.0, j / (n - 1) - 0.5))[1] for i in range(n) for j in range(n)]
    return sum(1 for y in ys if y <= TOUCH) / len(ys)


def leg_tilt(parts, part):
    """Angle (deg) between a leg's length and straight down."""
    return math.degrees(math.acos(max(-1.0, min(1.0, parts[part].r[4]))))  # part's up axis vs world up


def foot_channels(leg: str, target_xz, twist: float = 0.0, reach: float = 0.0):
    """(forward, out) for a leg whose sole centre should land at target (x, z) when the body
    stands at rest height - the reference 'plant' uses to lock a foot. Solved numerically so the
    leg's own twist (which swings the foot around the off-centre hip pivot) is accounted for."""
    from r6core import channels_to_transform
    s = 1 if leg == "RightLeg" else -1
    part = "Right Leg" if s == 1 else "Left Leg"
    tx, tz = target_xz
    o = math.asin(max(-1.0, min(1.0, (s * tx - 0.5) / 2.0)))
    f = math.asin(max(-1.0, min(1.0, -tz / 2.0)))
    for _ in range(12):
        ch = {"forward": math.degrees(f), "out": math.degrees(o), "twist": twist, "reach": reach}
        tip = limb_tip(forward_kinematics({leg: channels_to_transform(leg, ch)}), part)
        ex, ez = tx - tip[0], tz - tip[2]
        if abs(ex) < 1e-4 and abs(ez) < 1e-4:
            break
        o += s * ex / 2.0
        f += -ez / 2.0
    return round(math.degrees(f)), round(math.degrees(o))


def hip_target(parts, part):
    """Where a vertical leg's sole centre would be under this pose's hip pivot (x, z)."""
    from r6core import BY_PART
    s = 1 if part.startswith("Right") else -1
    hip = parts["Torso"].point(BY_PART[part].c0.pos)
    return hip[0] - s * 0.5, hip[2]  # a vertical leg's foot sits 0.5 inside its pivot


def under_hip(parts, part, twist: float = 0.0):
    """Leg channels (forward, out) that would stand this leg straight under its hip pivot, given
    where the hips are in this pose (torso twist/shift/lean move them while planted feet stay).
    Use the same values on every planted key of the stance so the foot doesn't slide."""
    return foot_channels("RightLeg" if part.startswith("Right") else "LeftLeg", hip_target(parts, part), twist)


def detect_support(parts):
    if lowest(parts, "Torso") <= CONTACT:
        return "body"  # sitting / lying: the torso is on the floor
    grounded = [label for part, label in LEGS if lowest(parts, part) <= CONTACT]
    if len(grounded) == 2:
        return "double"
    if grounded:
        return grounded[0]
    if any(lowest(parts, a) <= CONTACT for a in ("Right Arm", "Left Arm")):
        return "hands"
    return "air"


def footprint(parts, part):
    """The sole of a limb block (its far end face) projected on the floor, as (x, z)."""
    cf = parts[part]
    return [(p[0], p[2]) for p in (cf.point((sx * 0.5, -1.0, sz * 0.5)) for sx in (-1, 1) for sz in (-1, 1))]


def support_points(parts):
    """Floor support as (x, z) points: the whole sole footprint of every grounded leg (or
    hand), plus any torso/head corners resting on the floor (sitting, lying). A rigid R6 leg
    often touches with one edge only, but animators judge weight against the foot's footprint."""
    pts = []
    for part in ("Left Leg", "Right Leg", "Right Arm", "Left Arm"):
        if lowest(parts, part) <= CONTACT:
            pts += footprint(parts, part)
    pts += contacts(parts, "Torso")
    pts += [(c[0], c[2]) for c in box_corners(parts["Head"], RENDER_SIZE["Head"]) if c[1] <= CONTACT]
    return pts


def _hull(points):
    pts = sorted(set((round(x, 5), round(z, 5)) for x, z in points))
    if len(pts) <= 2:
        return pts

    def cross(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])
    lower, upper = [], []
    for p in pts:
        while len(lower) >= 2 and cross(lower[-2], lower[-1], p) <= 0:
            lower.pop()
        lower.append(p)
    for p in reversed(pts):
        while len(upper) >= 2 and cross(upper[-2], upper[-1], p) <= 0:
            upper.pop()
        upper.append(p)
    return lower[:-1] + upper[:-1]


def _seg_dist(p, a, b):
    ax, az = b[0] - a[0], b[1] - a[1]
    L = ax * ax + az * az
    u = 0.0 if L == 0 else max(0.0, min(1.0, ((p[0] - a[0]) * ax + (p[1] - a[1]) * az) / L))
    return math.hypot(p[0] - a[0] - u * ax, p[1] - a[1] - u * az)


def balance_margin(com_xz, hull):
    """Signed distance from the centre of mass to the edge of the support area
    (+ inside, - outside). None when nothing touches the floor."""
    if not hull:
        return None
    if len(hull) < 3:
        return -min(_seg_dist(com_xz, hull[i], hull[(i + 1) % len(hull)]) for i in range(len(hull))) \
            if len(hull) == 2 else -math.hypot(com_xz[0] - hull[0][0], com_xz[1] - hull[0][1])
    inside = all((b[0] - a[0]) * (com_xz[1] - a[1]) - (b[1] - a[1]) * (com_xz[0] - a[0]) >= 0
                 for a, b in zip(hull, hull[1:] + hull[:1]))
    d = min(_seg_dist(com_xz, a, b) for a, b in zip(hull, hull[1:] + hull[:1]))
    return d if inside else -d


def analyze(parts, transforms=None):
    """Everything an animator checks on one pose. Distances in studs, angles in degrees.
    Character space: +x right, +y up, -z forward."""
    com = center_of_mass(parts)
    support = detect_support(parts)
    hull = _hull(support_points(parts))
    feet = {label: limb_tip(parts, part) for part, label in LEGS}
    torso = parts["Torso"]
    up = (torso.r[1], torso.r[4], torso.r[7])
    info = {
        "support": support,
        "sole": {label: round(lowest(parts, part), 3) for part, label in LEGS},
        "edge": {label: round(edge_lift(parts, part), 3) for part, label in LEGS},
        "contact": {label: round(sole_contact(parts, part), 2) for part, label in LEGS},
        "tilt": {label: round(leg_tilt(parts, part), 1) for part, label in LEGS},
        "under_hip": {label: under_hip(parts, part) for part, label in LEGS},
        "hip_to_foot": {label: round(limb_tip(parts, part)[2] - parts["Torso"].point((0, -1, 0))[2], 2)
                        for part, label in LEGS},  # + = the foot is BEHIND the hips
        "feet": {label: (round(f[0], 2), round(-f[2], 2)) for label, f in feet.items()},  # (right, forward)
        "stance_width": round(abs(feet["left"][0] - feet["right"][0]), 2),
        "stance_length": round(abs(feet["left"][2] - feet["right"][2]), 2),
        "com": (round(com[0], 2), round(com[1], 2), round(-com[2], 2)),
        "balance": None if not hull else round(balance_margin((com[0], com[2]), hull), 2),
        "body_drop": round(torso.y - 3.0, 2),
        "torso_lean": round(math.degrees(math.acos(max(-1, min(1, up[1])))), 1),
        "hands": {a.split()[0].lower(): tuple(round(v, 2) for v in limb_tip(parts, a)) for a in ("Right Arm", "Left Arm")},
    }
    if transforms is not None:
        ch = {j: body_to_channels(j, transform_to_body(j, tf)) for j, tf in transforms.items()}
        info["torso_twist"] = round(ch["Torso"].get("twist", 0.0), 1)
        info["head_turn"] = round(ch["Head"].get("turn", 0.0), 1)
        info["arm_out"] = {"right": round(ch["RightArm"].get("out", 0.0), 1), "left": round(ch["LeftArm"].get("out", 0.0), 1)}
        info["arm_forward"] = {"right": round(ch["RightArm"].get("forward", 0.0), 1),
                               "left": round(ch["LeftArm"].get("forward", 0.0), 1)}
    return info


def analyze_at(anim: Anim, t: float, tracks=None):
    tracks = tracks or anim.tracks()
    tfs = sample(anim, t, tracks)
    return analyze(forward_kinematics(tfs), tfs)


def key_reports(anim: Anim):
    tracks = anim.tracks()
    return [(k, analyze_at(anim, k.time, tracks)) for k in anim.keys]


def contact_phases(anim: Anim, fps: float = 60.0, times=None, frames=None):
    """Per leg, the ground-contact phases sampled frame by frame:
    contact (touches down) -> plant (carries weight) -> release (leaves the floor) -> swing (moves
    while the other leg supports) or air (neither touches); landing = touch-down after air.
    Returns {"Right Leg": [(phase, t0, t1), ...], "Left Leg": [...]}."""
    from r6core import sample_times
    if frames is None:
        tracks = anim.tracks()
        times = sample_times(anim, fps)
        frames = [forward_kinematics(sample(anim, t, tracks)) for t in times]
    touch = {leg: [lowest(p, leg) <= CONTACT for p in frames] for leg, _ in LEGS}
    out = {}
    for leg, _ in LEGS:
        other = "Right Leg" if leg == "Left Leg" else "Left Leg"
        segs, i, n = [], 0, len(times)
        while i < n:
            j = i
            while j + 1 < n and touch[leg][j + 1] == touch[leg][i]:
                j += 1
            if touch[leg][i]:
                if i > 0:
                    airborne_before = not any(touch[other][max(0, i - 3):i])
                    segs.append(("landing" if airborne_before else "contact", times[i], times[i]))
                segs.append(("plant", times[i], times[j]))
                if j < n - 1:
                    segs.append(("release", times[j], times[j]))
            else:
                supported = sum(touch[other][i:j + 1]) > (j + 1 - i) / 2
                segs.append(("swing" if supported else "air", times[i], times[j]))
            i = j + 1
        out[leg] = segs
    return out


def phases_text(anim: Anim, **kw) -> str:
    lines = []
    for leg, segs in contact_phases(anim, **kw).items():
        parts = [f"{p} {a:.2f}" if abs(b - a) < 1e-9 else f"{p} {a:.2f}-{b:.2f}" for p, a, b in segs]
        lines.append(f"{leg}: " + " | ".join(parts))
    return "\n".join(lines)


def report_table(anim: Anim) -> str:
    """Per-key pose table (markdown) - the numbers behind 'does this pose stand up and read'."""
    rows = ["| # | t (s) | key | support label / actual | foot low L / R | sole on floor L / R | feet L (r,f) / R (r,f) "
            "| stance w x l | balance | body drop | lean | twist / head |",
            "|---|---|---|---|---|---|---|---|---|---|---|---|"]
    for i, (k, a) in enumerate(key_reports(anim)):
        label = k.support or "-"
        if k.airborne and label == "-":
            label = "(airborne)"
        bal = "n/a" if a["balance"] is None else (f"{a['balance']:+.2f}" + (" OUT" if a["balance"] < 0 else ""))
        rows.append(
            f"| {i} | {k.time:.3f} | {k.name or ''} | {label} / {a['support']} | {a['sole']['left']:+.2f} / "
            f"{a['sole']['right']:+.2f} | {a['contact']['left']:.0%} / {a['contact']['right']:.0%} | "
            f"{a['feet']['left']} / {a['feet']['right']} | "
            f"{a['stance_width']} x {a['stance_length']} | {bal} | {a['body_drop']:+.2f} | {a['torso_lean']} | "
            f"{a.get('torso_twist', 0):+.0f} / {a.get('head_turn', 0):+.0f} |")
    rows.append("")
    rows.append("foot low = height of each leg's lowest corner (0 = touching the floor; + = floating; "
                "- = pushed into the floor, never wanted). sole on floor = how much of each sole is within "
                f"{TOUCH} studs of the floor (no ankle: the more a leg tilts, the less of its sole touches; standing "
                "and crouching feet need >= 50%). feet = sole centre (right, forward) "
                "in studs. balance = how far the centre of mass sits inside (+) or outside (-) the area the "
                "touching soles cover. body drop = torso height change (negative = crouched).")
    rows.append("")
    rows.append("contact phases (sampled every frame):")
    rows.append(phases_text(anim))
    if anim.markers:
        rows.append("markers: " + ", ".join(f"{m.name}@{m.time:.3f}s" + (f"={m.value}" if m.value else "")
                                              for m in anim.markers))
    return "\n".join(rows)
