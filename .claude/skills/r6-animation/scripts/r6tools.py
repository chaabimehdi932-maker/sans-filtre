"""
r6tools - iteration helpers: flatten a spec, exaggerate it in a controlled step, and
compare two versions (before/after) at the same camera angles and times.
"""

from __future__ import annotations

import copy
import math

from r6core import (JOINT, JOINT_KEYS, TRANSLATION_CHANNELS, Anim, angle_between, sample)

ANGLE_CHANNELS = {"lean", "twist", "tilt", "nod", "turn", "forward", "out"}


def flatten(anim: Anim) -> dict:
    """Spec with every keyframe written out explicitly (no from/hold/poses/derive)."""
    raw = anim.raw
    out = {k: raw[k] for k in ("name", "note", "loop", "priority", "fps", "speed", "grounded", "rig") if k in raw}
    out["name"], out["loop"], out["priority"], out["fps"] = anim.name, anim.loop, anim.priority, anim.fps
    keys = []
    for k in anim.keys:
        d = {"t": round(k.time, 6)}
        if k.name:
            d["name"] = k.name
        d["ease"] = str(k.ease)
        for flag in ("plant", "airborne", "ground", "unbalanced", "balance"):
            if getattr(k, flag):
                d[flag] = True
        if k.support:
            d["support"] = k.support
        if k.pivot:
            d["pivot"] = k.pivot
        for j in JOINT_KEYS:
            if j in k.channels:
                ch = {c: round(v, 4) for c, v in k.channels[j].items()}
                if j in k.joint_ease:
                    ch["ease"] = str(k.joint_ease[j])
                d[j] = ch
        keys.append(d)
    out["keyframes"] = keys
    if anim.markers:
        out["markers"] = [{"t": round(m.time, 6), "name": m.name, **({"value": m.value} if m.value else {})}
                          for m in anim.markers]
    return out


def exaggerate(anim: Anim, amount: float = 1.15, about: str = "first", joints=None, translations=True) -> dict:
    """Push every pose further from its base by `amount` (1.15 = +15%).
    about="first": relative to each joint's first key (the stance the motion starts from);
    about="rest": relative to the default standing pose. Torso translations scale too unless
    translations=False. Contacts (plant/ground/balance) are re-solved when the result is loaded."""
    flat = flatten(anim)
    joints = set(joints) if joints else set(JOINT_KEYS)
    base = {}
    if about == "first":
        for k in flat["keyframes"]:
            for j in JOINT_KEYS:
                if j in k and j not in base:
                    base[j] = {c: v for c, v in k[j].items() if c != "ease"}
    for k in flat["keyframes"]:
        for j in joints:
            if j not in k:
                continue
            b = base.get(j, {})
            for c, v in list(k[j].items()):
                if c == "ease":
                    continue
                if c in ANGLE_CHANNELS or (translations and j == "Torso" and c in TRANSLATION_CHANNELS):
                    k[j][c] = round(b.get(c, 0.0) + amount * (v - b.get(c, 0.0)), 4)
    flat["name"] = f"{anim.name}_x{amount:g}".replace(".", "_")
    flat["note"] = (f"Exaggerated x{amount:g} about the {about} pose from '{anim.name}'. "
                    + str(anim.raw.get("note", "")))
    return flat


def motion_range(anim: Anim) -> dict:
    """Largest rotation (deg) each joint reaches away from its pose at t=0 - a simple
    'how big is the action' number to compare versions."""
    tracks = anim.tracks()
    n = max(2, int(anim.length * 60))
    start = sample(anim, 0.0, tracks)
    out = {}
    for j in JOINT_KEYS:
        out[j] = round(max(angle_between(start[j], sample(anim, anim.length * i / n, tracks)[j]) for i in range(n + 1)), 1)
    return out


def compare_text(a: Anim, b: Anim) -> str:
    """What changed between two versions: timing, markers, lint findings, poses."""
    from r6lint import lint
    from r6pose import key_reports
    lines = [f"# {a.name}  ->  {b.name}", ""]
    lines.append(f"length {a.length:.3f}s -> {b.length:.3f}s, keys {len(a.keys)} -> {len(b.keys)}, "
                 f"loop {a.loop} -> {b.loop}, priority {a.priority} -> {b.priority}")
    ma = [(m.name, round(m.time, 3), m.value) for m in a.markers]
    mb = [(m.name, round(m.time, 3), m.value) for m in b.markers]
    if ma == mb:
        lines.append(f"markers unchanged: {', '.join(f'{n}@{t}' for n, t, _ in ma) or 'none'}")
    else:
        lines.append(f"MARKERS CHANGED: {ma} -> {mb}  (gameplay code listening to them may break)")
    la, lb = lint(a), lint(b)
    for lvl in ("ERROR", "WARN"):
        lines.append(f"{lvl}: {sum(1 for l, _ in la if l == lvl)} -> {sum(1 for l, _ in lb if l == lvl)}")
    import re
    shape = lambda m: re.sub(r"[-+]?\d+(\.\d+)?", "#", m)
    old_shapes = {(l, shape(m)) for l, m in la}
    new = [m for l, m in lb if l in ("ERROR", "WARN") and (l, shape(m)) not in old_shapes]
    for m in new[:8]:
        lines.append(f"  new: {m}")
    ra, rb = motion_range(a), motion_range(b)
    lines.append("motion range (deg from start pose): " + ", ".join(
        f"{j} {ra[j]:.0f}->{rb[j]:.0f}" for j in JOINT_KEYS))
    pa, pb = key_reports(a), key_reports(b)

    def stats(reps):
        bal = [r["balance"] for _, r in reps if r["balance"] is not None]
        return (min(bal) if bal else None, min(r["body_drop"] for _, r in reps),
                max(r["stance_length"] for _, r in reps), max(r["torso_lean"] for _, r in reps))
    sa, sb = stats(pa), stats(pb)
    fmt = lambda v: "n/a" if v is None else f"{v:+.2f}"
    lines.append(f"worst balance {fmt(sa[0])} -> {fmt(sb[0])}, deepest body drop {sa[1]:+.2f} -> {sb[1]:+.2f}, "
                 f"longest stance {sa[2]:.2f} -> {sb[2]:.2f}, most lean {sa[3]:.0f} -> {sb[3]:.0f} deg")
    return "\n".join(lines)


def compare_times(a: Anim, b: Anim, n: int = 8):
    """Matching sample times for two versions: shared key times when the timing is the same,
    otherwise the same fractions of each animation's length."""
    ta = [round(k.time, 4) for k in a.keys]
    tb = [round(k.time, 4) for k in b.keys]
    if abs(a.length - b.length) < 1e-6:
        times = sorted(set(ta) | set(tb))
        if len(times) <= 12:
            return times, times
    fr = [i / (n - 1) for i in range(n)]
    return [a.length * f for f in fr], [b.length * f for f in fr]


def stance_groups(anim: Anim):
    """Runs of consecutive planted keys (on one or both feet): planted feet stay locked through each run."""
    groups, cur = [], []
    for i, k in enumerate(anim.keys):
        if k.plant and not k.airborne and k.support in (None, "double", "left", "right", "transition"):
            cur.append(i)
        else:
            if cur:
                groups.append(cur)
            cur = []
    if cur:
        groups.append(cur)
    return groups


def fit_stance(anim: Anim, spread: float = 6.0):
    """For each planted stance, the leg (forward, out) that keeps both feet as close as possible
    to straight under the hips across ALL its keys (the hips move with torso twist/shift while
    the feet stay), plus `spread` degrees of outward splay. Returns a list of dicts."""
    from r6core import forward_kinematics
    from r6pose import LEGS as POSE_LEGS, analyze, foot_channels, hip_target
    tracks = anim.tracks()
    out = []
    for g in stance_groups(anim):
        res = {"keys": g, "legs": {}}
        frames = [forward_kinematics(sample(anim, anim.keys[i].time, tracks)) for i in g]
        before = [analyze(p) for p in frames]
        res["before"] = min(min(a["contact"].values()) for a in before)
        for part, side in POSE_LEGS:
            leg = "RightLeg" if side == "right" else "LeftLeg"
            s = 1 if side == "right" else -1
            def bears(k):
                sup = k.support or "double"
                return sup in ("double", side) or (sup == "transition" and k.pivot in (None, "hips", side))
            on = [n for n, i in enumerate(g) if bears(anim.keys[i])]
            if not on:
                continue  # the free leg of a one-foot stance stays as animated
            pts = [hip_target(frames[n], part) for n in on]
            cx = (min(p[0] for p in pts) + max(p[0] for p in pts)) / 2
            cz = (min(p[1] for p in pts) + max(p[1] for p in pts)) / 2
            cx += s * 2 * math.sin(math.radians(spread))
            first = anim.keys[g[0]].channels.get(leg, {})
            twist = first.get("twist", 0.0)
            res["legs"][leg] = foot_channels(leg, (cx, cz), twist) + (twist,)
        out.append(res)
    return out


def apply_stance(raw: dict, anim: Anim, fits) -> dict:
    """Copy of the raw spec with the fitted leg forward/out written on every key of each stance."""
    new = copy.deepcopy(raw)
    fps = float(raw.get("fps", 60))
    rk = new["keyframes"]

    def t_of(k):
        if "t" in k or "time" in k:
            return float(k.get("t", k.get("time")))
        return float(k.get("f", k.get("frame", 0))) / fps
    for fit in fits:
        times = [anim.keys[i].time for i in fit["keys"]]
        for k in rk:
            if any(abs(t_of(k) - t) < 1e-6 for t in times):
                for leg, (fwd, o, _tw) in fit["legs"].items():
                    k.setdefault(leg, {})
                    k[leg]["forward"], k[leg]["out"] = fwd, o
    return new
