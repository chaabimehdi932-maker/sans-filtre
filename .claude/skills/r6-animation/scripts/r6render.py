"""
r6render - draw an R6 animation so you can actually look at it.

  contact sheet : rows = camera views, columns = keyframes (or evenly spaced samples)
  gif           : the animation playing, several views side by side, with a timeline
  onion         : ghosts of the key poses + hand/foot trails with one dot per 1/30 s
                  (dots bunched up = slow, spread out = fast) to judge arcs and spacing

Needs Pillow. Colours: classic R6 (yellow head/arms, blue torso, green legs). The
character's RIGHT arm/leg are drawn darker than the left ones. Eyes mark the face.
"""

from __future__ import annotations

import math

from PIL import Image, ImageDraw, ImageFont

from r6core import (CF, JOINT_KEYS, RENDER_SIZE, Anim, box_corners, forward_kinematics, limb_tip,
                    sample, sample_times)

DRAW_PARTS = ("Torso", "Head", "Right Arm", "Left Arm", "Right Leg", "Left Leg")
COLORS = {
    "Head": (245, 205, 48),
    "Torso": (40, 110, 190),
    "Right Arm": (222, 160, 30),
    "Left Arm": (250, 222, 110),
    "Right Leg": (105, 150, 50),
    "Left Leg": (170, 205, 105),
}
BG = (247, 247, 244)
INK = (40, 40, 40)
GRID = (214, 214, 206)

VIEWS = {  # name: (yaw from the front toward the character's right, elevation) in degrees
    "front": (0, 8),
    "side": (90, 8),  # camera on the character's right; the character faces screen-right
    "back": (180, 8),
    "three_quarter": (35, 18),
    "game": (160, 22),  # the Roblox gameplay camera: behind the character, slightly right, above
    "top": (0, 80),
}
DEFAULT_VIEWS = ("front", "side", "three_quarter", "game")


def _font(size):
    try:
        return ImageFont.load_default(size=size)
    except TypeError:  # very old Pillow
        return ImageFont.load_default()


def _norm(v):
    n = math.sqrt(sum(c * c for c in v)) or 1.0
    return tuple(c / n for c in v)


def _cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def _dot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


class Camera:
    def __init__(self, view: str):
        yaw, elev = VIEWS[view]
        y, e = math.radians(yaw), math.radians(elev)
        # c = direction from the character toward the camera (character faces -Z)
        self.c = _norm((math.sin(y) * math.cos(e), math.sin(e), -math.cos(y) * math.cos(e)))
        f = tuple(-v for v in self.c)
        world_up = (0, 1, 0) if abs(self.c[1]) < 0.99 else (0, 0, 1)
        self.right = _norm(_cross(f, world_up))
        self.up = _cross(self.right, f)
        self.light = _norm(tuple(self.c[i] * 0.7 + self.up[i] * 0.6 - self.right[i] * 0.35 for i in range(3)))
        self.name = view

    def project(self, p):
        return (_dot(p, self.right), _dot(p, self.up), _dot(p, self.c))


_FACES = (  # (axis index, sign, corner indices) using box_corners ordering sx,sy,sz in (-1,1)
    (0, -1, (0, 1, 3, 2)), (0, 1, (4, 6, 7, 5)),
    (1, -1, (0, 4, 5, 1)), (1, 1, (2, 3, 7, 6)),
    (2, -1, (0, 2, 6, 4)), (2, 1, (1, 5, 7, 3)),
)


def _shade(color, k):
    return tuple(max(0, min(255, int(c * k))) for c in color)


def _clip_floor(poly):
    """Keep the part of a 3D polygon at or above the floor (y >= 0): what the game shows."""
    out = []
    for i, a in enumerate(poly):
        b = poly[(i + 1) % len(poly)]
        if a[1] >= 0:
            out.append(a)
        if (a[1] >= 0) != (b[1] >= 0):
            u = a[1] / (a[1] - b[1])
            out.append(tuple(a[j] + (b[j] - a[j]) * u for j in range(3)))
    return out


def _part_polys(parts: dict, cam: Camera, clip=False):
    """Visible faces of every part as (depth, screen poly, colour, part, axis, sign). Off by
    default so a foot pushed into the floor shows up in the preview; clip=True cuts away what
    is below the floor."""
    out = []
    for name in DRAW_PARTS:
        cf: CF = parts[name]
        corners = box_corners(cf, RENDER_SIZE[name])
        for axis, sign, idx in _FACES:
            col = (cf.r[axis], cf.r[axis + 3], cf.r[axis + 6])
            n = tuple(sign * v for v in col)
            if _dot(n, cam.c) <= 1e-6:
                continue
            poly = [corners[i] for i in idx]
            if clip:
                poly = _clip_floor(poly)
                if len(poly) < 3:
                    continue
            proj = [cam.project(p) for p in poly]
            depth = sum(p[2] for p in proj) / len(proj)
            k = 0.62 + 0.42 * max(0.0, _dot(n, cam.light))
            out.append((depth, [p[:2] for p in proj], _shade(COLORS[name], k), name, axis, sign))
    out.sort(key=lambda f: f[0])
    return out


def _decals(parts: dict, cam: Camera):
    """Eyes on the head's front face, a stripe on the torso's front: shows facing."""
    res = []
    head, torso = parts["Head"], parts["Torso"]
    hs = RENDER_SIZE["Head"][2] / 2 + 0.01
    head_front = (-head.r[2], -head.r[5], -head.r[8])
    if _dot(head_front, cam.c) > 0.05:
        for ex in (-0.24, 0.24):
            quad = [(ex - 0.07, 0.22), (ex + 0.07, 0.22), (ex + 0.07, 0.0), (ex - 0.07, 0.0)]
            pts = [cam.project(head.point((x, y, -hs)))[:2] for x, y in quad]
            res.append((pts, (30, 30, 30)))
    torso_front = (-torso.r[2], -torso.r[5], -torso.r[8])
    if _dot(torso_front, cam.c) > 0.05:
        quad = [(-0.12, 0.95), (0.12, 0.95), (0.12, -0.2), (-0.12, -0.2)]
        pts = [cam.project(torso.point((x, y, -0.51)))[:2] for x, y in quad]
        res.append((pts, (225, 235, 250)))
    return res


def _ground_lines(cam: Camera, cx=0.0, cz=0.0, half=3):
    lines = []
    for i in range(-half, half + 1):
        a = cam.project((cx + i, 0, cz - half))
        b = cam.project((cx + i, 0, cz + half))
        lines.append((a[:2], b[:2]))
        a = cam.project((cx - half, 0, cz + i))
        b = cam.project((cx + half, 0, cz + i))
        lines.append((a[:2], b[:2]))
    return lines


class Frame:
    """Maps world-projected 2D coords into a pixel box."""

    def __init__(self, box, bounds, scale):
        (x0, y0, x1, y1), (bx0, by0, bx1, by1) = box, bounds
        self.scale = scale
        self.ox = (x0 + x1) / 2 - (bx0 + bx1) / 2 * scale
        self.oy = (y0 + y1) / 2 + (by0 + by1) / 2 * scale

    def px(self, p):
        return (self.ox + p[0] * self.scale, self.oy - p[1] * self.scale)


def draw_rig(img: Image.Image, parts: dict, cam: Camera, fr: Frame, ground=True, label=None, clip=False):
    d = ImageDraw.Draw(img)
    if ground:
        for a, b in _ground_lines(cam):
            d.line([fr.px(a), fr.px(b)], fill=GRID, width=1)
        # shadow under the torso
        tx, _, tz = parts["Torso"].pos
        pts = [cam.project((tx + 1.1 * math.cos(a), 0, tz + 0.7 * math.sin(a)))[:2]
               for a in (i * math.pi / 12 for i in range(24))]
        d.polygon([fr.px(p) for p in pts], fill=(222, 222, 214))
    decals = _decals(parts, cam)
    faces = _part_polys(parts, cam, clip=clip and ground)
    for depth, poly, color, name, axis, sign in faces:
        d.polygon([fr.px(p) for p in poly], fill=color, outline=_shade(color, 0.55))
    for poly, color in decals:
        d.polygon([fr.px(p) for p in poly], fill=color)
    if label:
        d.text((fr.ox, 0), label, fill=INK)


def _bounds_for(anim: Anim, cam: Camera, times, pad=0.4):
    xs, ys = [], []
    tracks = anim.tracks()
    for t in times:
        parts = forward_kinematics(sample(anim, t, tracks))
        for name in DRAW_PARTS:
            for p in box_corners(parts[name], RENDER_SIZE[name]):
                x, y, _ = cam.project(p)
                xs.append(x)
                ys.append(y)
    for a, b in _ground_lines(cam, half=2):
        xs += [a[0], b[0]]
        ys += [a[1], b[1]]
    return (min(xs) - pad, min(ys) - pad, max(xs) + pad, max(ys) + pad)


def _key_label(anim: Anim, t: float):
    for i, k in enumerate(anim.keys):
        if abs(k.time - t) < 1e-6:
            return f"#{i} {t:.3f}s f{round(t * anim.fps)}" + (f" {k.name}" if k.name else "")
    return f"{t:.3f}s f{round(t * anim.fps)}"


def contact_sheet(anim: Anim, path: str, views=DEFAULT_VIEWS, times=None, cell=(190, 230), max_cols=8):
    times = list(times) if times is not None else [k.time for k in anim.keys]
    cams = [Camera(v) for v in views]
    all_bounds = [_bounds_for(anim, cam, sample_times(anim, 30)) for cam in cams]
    cw, ch = cell
    label_h, title_h, row_label_w = 30, 34, 86
    scale = min(min((cw - 12) / (b[2] - b[0]), (ch - 8) / (b[3] - b[1])) for b in all_bounds)
    blocks = [times[i:i + max_cols] for i in range(0, len(times), max_cols)]
    ncols = min(max_cols, len(times))
    block_h = label_h + ch * len(cams)
    W = row_label_w + ncols * cw
    H = title_h + block_h * len(blocks) + 26
    img = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(img)
    f_title, f_small = _font(16), _font(12)
    title = (f"{anim.name}  |  {anim.length:.3f}s  |  {'loop' if anim.loop else 'one-shot'}  |  "
             f"{anim.priority}  |  {len(anim.keys)} keys")
    d.text((10, 9), title, fill=INK, font=f_title)
    tracks = anim.tracks()
    for bi, block in enumerate(blocks):
        y0 = title_h + bi * block_h
        for ci, t in enumerate(block):
            x0 = row_label_w + ci * cw
            d.text((x0 + 6, y0 + 8), _key_label(anim, t), fill=INK, font=f_small)
            parts = forward_kinematics(sample(anim, t, tracks))
            for ri, cam in enumerate(cams):
                cy = y0 + label_h + ri * ch
                if ci == 0:
                    d.text((8, cy + ch / 2 - 6), cam.name.replace("_", " "), fill=INK, font=f_small)
                fr = Frame((x0, cy, x0 + cw, cy + ch), all_bounds[ri], scale)
                draw_rig(img, parts, cam, fr)
                d.rectangle([x0, cy, x0 + cw, cy + ch], outline=(225, 225, 218))
    d.text((10, H - 20), "Right limbs = darker. Eyes = face. Grid = 1 stud.", fill=(110, 110, 110), font=f_small)
    img.save(path)
    return path


def gif(anim: Anim, path: str, views=DEFAULT_VIEWS, fps=30, cell=(220, 260), repeats=1, slow=1.0):
    """Animated preview. slow=0.25 plays at quarter speed (every 60 fps frame shown) to inspect
    contacts, pops and in-betweens."""
    cams = [Camera(v) for v in views]
    sample_fps = min(60.0, fps / slow)
    times = sample_times(anim, sample_fps)
    bounds = [_bounds_for(anim, cam, times) for cam in cams]
    cw, ch = cell
    bar_h = 34
    scale = min(min((cw - 12) / (b[2] - b[0]), (ch - 8) / (b[3] - b[1])) for b in bounds)
    W, H = cw * len(cams), ch + bar_h
    f_small = _font(12)
    tracks = anim.tracks()
    frames = []
    seq = times[:-1] if anim.loop and len(times) > 1 else times
    for t in seq:
        img = Image.new("RGB", (W, H), BG)
        parts = forward_kinematics(sample(anim, t, tracks))
        for i, cam in enumerate(cams):
            fr = Frame((i * cw, 0, (i + 1) * cw, ch), bounds[i], scale)
            draw_rig(img, parts, cam, fr)
        d = ImageDraw.Draw(img)
        # timeline with key ticks, markers and playhead
        x0, x1, y = 10, W - 10, ch + 12
        d.line([(x0, y), (x1, y)], fill=(160, 160, 160), width=2)
        L = anim.length or 1.0
        for k in anim.keys:
            x = x0 + (x1 - x0) * k.time / L
            d.line([(x, y - 5), (x, y + 5)], fill=(90, 90, 90), width=1)
        for m in anim.markers:
            x = x0 + (x1 - x0) * m.time / L
            d.polygon([(x - 4, y - 9), (x + 4, y - 9), (x, y - 3)], fill=(200, 60, 60))
        px = x0 + (x1 - x0) * t / L
        d.ellipse([px - 4, y - 4, px + 4, y + 4], fill=(30, 110, 220))
        txt = f"{anim.name}  {t:.2f}s / {anim.length:.2f}s" + (f"   (x{slow:g} speed)" if slow != 1 else "")
        hits = [m.name for m in anim.markers if abs(m.time - t) <= 0.5 / sample_fps + 1e-9]
        if hits:
            txt += "   >> " + ", ".join(hits)
        d.text((10, ch + 18), txt, fill=INK, font=f_small)
        frames.append(img)
    durations = [round(1000 / (sample_fps * slow))] * len(frames)
    if not anim.loop:
        durations[-1] = 600
        durations[0] = 300
    frames = frames * max(1, repeats)
    durations = durations * max(1, repeats)
    frames[0].save(path, save_all=True, append_images=frames[1:], duration=durations, loop=0, disposal=2)
    return path


TRAIL_PARTS = {"Right Arm": (200, 60, 40), "Left Arm": (230, 150, 30),
               "Right Leg": (40, 120, 60), "Left Leg": (60, 170, 160)}


def onion(anim: Anim, path: str, views=("side", "front"), cell=(360, 380), trail_fps=30):
    cams = [Camera(v) for v in views]
    dense = sample_times(anim, trail_fps)
    bounds = [_bounds_for(anim, cam, dense) for cam in cams]
    cw, ch = cell
    scale = min(min((cw - 12) / (b[2] - b[0]), (ch - 40) / (b[3] - b[1])) for b in bounds)
    W, H = cw * len(cams), ch + 40
    base = Image.new("RGBA", (W, H), BG + (255,))
    f_small = _font(12)
    tracks = anim.tracks()
    key_parts = [forward_kinematics(sample(anim, k.time, tracks)) for k in anim.keys]
    dense_parts = [forward_kinematics(sample(anim, t, tracks)) for t in dense]
    for i, cam in enumerate(cams):
        fr = Frame((i * cw, 30, (i + 1) * cw, 30 + ch - 10), bounds[i], scale)
        layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        d = ImageDraw.Draw(layer)
        for a, b in _ground_lines(cam):
            d.line([fr.px(a), fr.px(b)], fill=GRID + (255,), width=1)
        n = len(key_parts)
        for ki, parts in enumerate(key_parts):  # ghost wireframes of key poses, blue -> red
            u = ki / max(1, n - 1)
            col = (int(60 + 180 * u), 80, int(220 - 160 * u), 95)
            for name in DRAW_PARTS:
                c = [fr.px(cam.project(p)[:2]) for p in box_corners(parts[name], RENDER_SIZE[name])]
                for a, b in ((0, 1), (1, 3), (3, 2), (2, 0), (4, 5), (5, 7), (7, 6), (6, 4),
                             (0, 4), (1, 5), (2, 6), (3, 7)):
                    d.line([c[a], c[b]], fill=col, width=1)
        for part, col in TRAIL_PARTS.items():  # trails of hands and feet
            pts = [fr.px(cam.project(limb_tip(p, part))[:2]) for p in dense_parts]
            if len(pts) > 1:
                d.line(pts, fill=col + (200,), width=2)
            for p in pts:
                d.ellipse([p[0] - 2, p[1] - 2, p[0] + 2, p[1] + 2], fill=col + (255,))
        base = Image.alpha_composite(base, layer)
        ImageDraw.Draw(base).text((i * cw + 8, 8), f"{cam.name}: key poses blue->red, dots every 1/{trail_fps}s",
                                  fill=INK, font=f_small)
    legend = "trails: R hand red, L hand orange, R foot green, L foot teal"
    ImageDraw.Draw(base).text((8, H - 18), legend, fill=INK, font=f_small)
    base.convert("RGB").save(path)
    return path


def pose_image(transforms: dict, path: str, views=DEFAULT_VIEWS, cell=(220, 260)):
    """Single static pose (dict joint -> Transform CF)."""
    from r6core import IDENTITY
    full = {j: transforms.get(j, IDENTITY) for j in JOINT_KEYS}
    parts = forward_kinematics(full)
    cams = [Camera(v) for v in views]
    W, H = cell[0] * len(cams), cell[1]
    img = Image.new("RGB", (W, H), BG)
    for i, cam in enumerate(cams):
        xs, ys = [], []
        for name in DRAW_PARTS:
            for p in box_corners(parts[name], RENDER_SIZE[name]):
                x, y, _ = cam.project(p)
                xs.append(x)
                ys.append(y)
        b = (min(xs) - 1, min(ys) - 0.5, max(xs) + 1, max(ys) + 0.5)
        s = min((cell[0] - 10) / (b[2] - b[0]), (cell[1] - 10) / (b[3] - b[1]))
        draw_rig(img, parts, cam, Frame((i * cell[0], 0, (i + 1) * cell[0], cell[1]), b, s))
    img.save(path)
    return path


def compare_sheet(a: Anim, b: Anim, path: str, times_a, times_b, views=("side", "three_quarter", "game"),
                  cell=(170, 210)):
    """Before/after at the same camera angles and matching times: for each view a row for A
    and a row for B. Shared scale, so size differences are real."""
    cams = [Camera(v) for v in views]
    ba = [_bounds_for(a, cam, sample_times(a, 20)) for cam in cams]
    bb = [_bounds_for(b, cam, sample_times(b, 20)) for cam in cams]
    bounds = [(min(x[0], y[0]), min(x[1], y[1]), max(x[2], y[2]), max(x[3], y[3])) for x, y in zip(ba, bb)]
    cw, ch = cell
    label_w, title_h = 120, 30
    scale = min(min((cw - 10) / (bd[2] - bd[0]), (ch - 8) / (bd[3] - bd[1])) for bd in bounds)
    ncol = len(times_a)
    W, H = label_w + ncol * cw, title_h + 20 + 2 * len(cams) * ch
    img = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(img)
    d.text((10, 8), f"BEFORE: {a.name} ({a.length:.2f}s)   vs   AFTER: {b.name} ({b.length:.2f}s)",
           fill=INK, font=_font(15))
    ta, tb = a.tracks(), b.tracks()
    for ci in range(ncol):
        x0 = label_w + ci * cw
        d.text((x0 + 4, title_h), f"{times_a[ci]:.2f}s | {times_b[ci]:.2f}s", fill=INK, font=_font(11))
        pa = forward_kinematics(sample(a, times_a[ci], ta))
        pb = forward_kinematics(sample(b, times_b[ci], tb))
        for vi, cam in enumerate(cams):
            for k, (parts, tag) in enumerate(((pa, "before"), (pb, "after"))):
                y0 = title_h + 20 + (vi * 2 + k) * ch
                if ci == 0:
                    d.text((6, y0 + ch / 2 - 6), f"{cam.name.replace('_', ' ')}\n{tag}", fill=INK, font=_font(12))
                fr = Frame((x0, y0, x0 + cw, y0 + ch), bounds[vi], scale)
                draw_rig(img, parts, cam, fr)
                d.rectangle([x0, y0, x0 + cw, y0 + ch], outline=(200, 200, 190) if k else (225, 225, 218))
    img.save(path)
    return path


def compare_gif(a: Anim, b: Anim, path: str, view="three_quarter", fps=30, cell=(260, 300)):
    """Before | after playing side by side at the same speed (the shorter one holds its end)."""
    cam = Camera(view)
    L = max(a.length, b.length)
    n = max(1, int(round(L * fps)))
    ts = [L * i / n for i in range(n + 1)]
    bd = [_bounds_for(x, cam, sample_times(x, 20)) for x in (a, b)]
    bounds = (min(bd[0][0], bd[1][0]), min(bd[0][1], bd[1][1]), max(bd[0][2], bd[1][2]), max(bd[0][3], bd[1][3]))
    cw, ch = cell
    scale = min((cw - 10) / (bounds[2] - bounds[0]), (ch - 40) / (bounds[3] - bounds[1]))
    ta, tb = a.tracks(), b.tracks()
    frames = []
    for t in ts:
        img = Image.new("RGB", (cw * 2, ch), BG)
        for i, (x, tr, tag) in enumerate(((a, ta, "before"), (b, tb, "after"))):
            parts = forward_kinematics(sample(x, min(t, x.length), tr))
            draw_rig(img, parts, cam, Frame((i * cw, 24, (i + 1) * cw, ch), bounds, scale))
            ImageDraw.Draw(img).text((i * cw + 8, 6), f"{tag}: {x.name}  {min(t, x.length):.2f}s", fill=INK,
                                     font=_font(12))
        frames.append(img)
    durations = [round(1000 / (sample_fps * slow))] * len(frames)
    durations[-1] = 600
    frames[0].save(path, save_all=True, append_images=frames[1:], duration=durations, loop=0, disposal=2)
    return path
