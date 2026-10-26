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
