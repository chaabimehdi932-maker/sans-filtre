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
FLUSH = 0.05  # a sole whose highest corner is this close to the floor is fully planted
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


def sole_gap(parts, part):
    """Air under the highest corner of the sole (0 = fully on the floor)."""
    return sole_top(parts[part])


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
        "gap": {label: round(sole_gap(parts, part), 3) for part, label in LEGS},
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


def report_table(anim: Anim) -> str:
    """Per-key pose table (markdown) - the numbers behind 'does this pose stand up and read'."""
    rows = ["| # | t (s) | key | support label / actual | sole gap L / R | feet L (r,f) / R (r,f) | stance w x l "
            "| balance | body drop | lean | twist / head |",
            "|---|---|---|---|---|---|---|---|---|---|---|"]
    for i, (k, a) in enumerate(key_reports(anim)):
        label = k.support or "-"
        if k.airborne and label == "-":
            label = "(airborne)"
        bal = "n/a" if a["balance"] is None else (f"{a['balance']:+.2f}" + (" OUT" if a["balance"] < 0 else ""))
        rows.append(
            f"| {i} | {k.time:.3f} | {k.name or ''} | {label} / {a['support']} | {a['gap']['left']:+.2f} / "
            f"{a['gap']['right']:+.2f} | {a['feet']['left']} / {a['feet']['right']} | "
            f"{a['stance_width']} x {a['stance_length']} | {bal} | {a['body_drop']:+.2f} | {a['torso_lean']} | "
            f"{a.get('torso_twist', 0):+.0f} / {a.get('head_turn', 0):+.0f} |")
    rows.append("")
    rows.append("sole gap = air under the highest corner of each sole (0 = foot fully on the floor; a tilted "
                "leg's lower edge goes into the floor, hidden). feet = sole centre (right, forward) "
                "in studs. balance = how far the centre of mass sits inside (+) or outside (-) the area the "
                "touching soles cover. body drop = torso height change (negative = crouched).")
    if anim.markers:
        rows.append("markers: " + ", ".join(f"{m.name}@{m.time:.3f}s" + (f"={m.value}" if m.value else "")
                                              for m in anim.markers))
    return "\n".join(rows)
