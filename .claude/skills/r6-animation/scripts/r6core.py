"""
r6core - R6 rig data, CFrame math, animation-spec parsing and sampling.

Pure Python, no dependencies, so it runs anywhere.

Character space (same as Roblox): +X = the character's right, +Y = up, -Z = forward.
The HumanoidRootPart sits 3 studs above the ground (legs 2 + half torso 1).

The whole point of this module: you describe poses in body terms
("RightArm forward 90" = arm points straight ahead) and it produces the exact
Pose.CFrame (= Motor6D.Transform) Roblox needs, hiding R6's rotated joint frames.

    Transform = C0.Rotation^-1 * (Offset * R_body) * C0.Rotation

R_body is the rotation you want, expressed in the parent part's axes, applied at the
joint pivot. Derivation: Part1 = Part0 * C0 * T * C1^-1 must equal
Part0 * Pivot * R_body * Pivot^-1 * (C0 * C1^-1), which solves to the line above.
"""

from __future__ import annotations

import copy
import json
import math
from dataclasses import dataclass, field

# --------------------------------------------------------------------------- CFrame


class CF:
    """Minimal Roblox-style CFrame: position + row-major 3x3 rotation (R00..R22)."""

    __slots__ = ("x", "y", "z", "r")

    def __init__(self, x=0.0, y=0.0, z=0.0, r=(1, 0, 0, 0, 1, 0, 0, 0, 1)):
        self.x, self.y, self.z = float(x), float(y), float(z)
        self.r = tuple(float(v) for v in r)

    @classmethod
    def new(cls, *c):
        """CF.new(x, y, z) or CF.new(x, y, z, R00, R01, ..., R22) - same order as Luau."""
        if len(c) == 3:
            return cls(*c)
        if len(c) == 12:
            return cls(c[0], c[1], c[2], c[3:12])
        raise ValueError("CF.new takes 3 or 12 numbers")

    def components(self):
        return (self.x, self.y, self.z) + self.r

    @property
    def pos(self):
        return (self.x, self.y, self.z)

    def rotation(self):
        return CF(0, 0, 0, self.r)

    def __mul__(self, o: "CF") -> "CF":
        a, b = self.r, o.r
        r = (
            a[0] * b[0] + a[1] * b[3] + a[2] * b[6],
            a[0] * b[1] + a[1] * b[4] + a[2] * b[7],
            a[0] * b[2] + a[1] * b[5] + a[2] * b[8],
            a[3] * b[0] + a[4] * b[3] + a[5] * b[6],
            a[3] * b[1] + a[4] * b[4] + a[5] * b[7],
            a[3] * b[2] + a[4] * b[5] + a[5] * b[8],
            a[6] * b[0] + a[7] * b[3] + a[8] * b[6],
            a[6] * b[1] + a[7] * b[4] + a[8] * b[7],
            a[6] * b[2] + a[7] * b[5] + a[8] * b[8],
        )
        px, py, pz = self.point(o.pos)
        return CF(px, py, pz, r)

    def point(self, v):
        r = self.r
        x, y, z = v
        return (
            r[0] * x + r[1] * y + r[2] * z + self.x,
            r[3] * x + r[4] * y + r[5] * z + self.y,
            r[6] * x + r[7] * y + r[8] * z + self.z,
        )

    def vector(self, v):
        r = self.r
        x, y, z = v
        return (
            r[0] * x + r[1] * y + r[2] * z,
            r[3] * x + r[4] * y + r[5] * z,
            r[6] * x + r[7] * y + r[8] * z,
        )

    def inverse(self) -> "CF":
        r = self.r
        rt = (r[0], r[3], r[6], r[1], r[4], r[7], r[2], r[5], r[8])
        inv = CF(0, 0, 0, rt)
        px, py, pz = inv.vector(self.pos)
        return CF(-px, -py, -pz, rt)

    def almost(self, o: "CF", eps=1e-6) -> bool:
        return all(abs(a - b) <= eps for a, b in zip(self.components(), o.components()))

    def __repr__(self):
        return "CF.new(" + ", ".join(fmt_num(v) for v in self.components()) + ")"


IDENTITY = CF()


def rx(a):
    c, s = math.cos(a), math.sin(a)
    return CF(0, 0, 0, (1, 0, 0, 0, c, -s, 0, s, c))


def ry(a):
    c, s = math.cos(a), math.sin(a)
    return CF(0, 0, 0, (c, 0, s, 0, 1, 0, -s, 0, c))


def rz(a):
    c, s = math.cos(a), math.sin(a)
    return CF(0, 0, 0, (c, -s, 0, s, c, 0, 0, 0, 1))


def fmt_num(v: float) -> str:
    """Short, stable number formatting (no -0, no 1e-17 noise)."""
    if abs(v) < 5e-7:
        return "0"
    s = f"{v:.6f}".rstrip("0").rstrip(".")
    return "0" if s in ("-0", "") else s


# --------------------------------------------------------------- quaternions / lerp


def to_quat(cf: CF):
    m = cf.r
    m00, m01, m02, m10, m11, m12, m20, m21, m22 = m
    tr = m00 + m11 + m22
    if tr > 0:
        s = math.sqrt(tr + 1.0) * 2
        w, x, y, z = 0.25 * s, (m21 - m12) / s, (m02 - m20) / s, (m10 - m01) / s
    elif m00 > m11 and m00 > m22:
        s = math.sqrt(1.0 + m00 - m11 - m22) * 2
        w, x, y, z = (m21 - m12) / s, 0.25 * s, (m01 + m10) / s, (m02 + m20) / s
    elif m11 > m22:
        s = math.sqrt(1.0 + m11 - m00 - m22) * 2
        w, x, y, z = (m02 - m20) / s, (m01 + m10) / s, 0.25 * s, (m12 + m21) / s
    else:
        s = math.sqrt(1.0 + m22 - m00 - m11) * 2
        w, x, y, z = (m10 - m01) / s, (m02 + m20) / s, (m12 + m21) / s, 0.25 * s
    n = math.sqrt(w * w + x * x + y * y + z * z)
    return (w / n, x / n, y / n, z / n)


def from_quat(q, pos=(0, 0, 0)) -> CF:
    w, x, y, z = q
    r = (
        1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w),
        2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w),
        2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y),
    )
    return CF(pos[0], pos[1], pos[2], r)


def slerp(q0, q1, t):
    dot = sum(a * b for a, b in zip(q0, q1))
    if dot < 0:
        q1 = tuple(-v for v in q1)
        dot = -dot
    if dot > 0.9995:
        q = tuple(a + (b - a) * t for a, b in zip(q0, q1))
        n = math.sqrt(sum(v * v for v in q))
        return tuple(v / n for v in q)
    th = math.acos(max(-1.0, min(1.0, dot)))
    s = math.sin(th)
    a, b = math.sin((1 - t) * th) / s, math.sin(t * th) / s
    return tuple(a * p + b * r for p, r in zip(q0, q1))


def cf_lerp(a: CF, b: CF, t: float) -> CF:
    """Like Roblox CFrame:Lerp - linear position, spherical rotation."""
    q = slerp(to_quat(a), to_quat(b), t)
    pos = tuple(pa + (pb - pa) * t for pa, pb in zip(a.pos, b.pos))
    return from_quat(q, pos)


def angle_between(a: CF, b: CF) -> float:
    """Rotation angle (degrees) between two orientations."""
    q0, q1 = to_quat(a), to_quat(b)
    dot = abs(sum(x * y for x, y in zip(q0, q1)))
    return math.degrees(2 * math.acos(min(1.0, dot)))


# ------------------------------------------------------------------------ R6 rig

# Part sizes in studs. The Head part is 2x1x1 but its SpecialMesh makes it look like a
# ~1.2 stud cube; RENDER_SIZE is what the previews draw.
PART_SIZE = {
    "HumanoidRootPart": (2, 2, 1),
    "Torso": (2, 2, 1),
    "Head": (2, 1, 1),
    "Right Arm": (1, 2, 1),
    "Left Arm": (1, 2, 1),
    "Right Leg": (1, 2, 1),
    "Left Leg": (1, 2, 1),
}
RENDER_SIZE = dict(PART_SIZE, Head=(1.2, 1.2, 1.2))

HRP_HEIGHT = 3.0  # HumanoidRootPart centre above the ground for a standing R6 rig


@dataclass(frozen=True)
class Joint:
    key: str  # spec name
    motor: str  # Motor6D name in the rig
    part0: str
    part1: str
    c0: CF
    c1: CF
    channels: tuple


_ROOT_ROT = (-1, 0, 0, 0, 0, 1, 0, 1, 0)
# Translations (studs). Limbs: 'reach' slides the limb along its own length (+ out of the
# socket = stretch/smear, - into the body = R6 "fake knee" leg retraction); offset_* move it
# in the torso's axes. Animators use these sparingly; 'plant' sets leg reach for you.
OFFSETS = ("offset_right", "offset_up", "offset_forward")
LIMB_CHANNELS = ("forward", "out", "twist", "reach") + OFFSETS
_R_ROT = (0, 0, 1, 0, 1, 0, -1, 0, 0)
_L_ROT = (0, 0, -1, 0, 1, 0, 1, 0, 0)

# Default R6 Motor6D values (Part0 -> Part1). RootJoint lives in HumanoidRootPart,
# the other five in Torso. Order matters: parents before children.
JOINTS = [
    Joint("Torso", "RootJoint", "HumanoidRootPart", "Torso",
          CF(0, 0, 0, _ROOT_ROT), CF(0, 0, 0, _ROOT_ROT),
          ("lean", "twist", "tilt", "right", "up", "forward")),
    Joint("Head", "Neck", "Torso", "Head",
          CF(0, 1, 0, _ROOT_ROT), CF(0, -0.5, 0, _ROOT_ROT),
          ("nod", "turn", "tilt") + OFFSETS),
    Joint("RightArm", "Right Shoulder", "Torso", "Right Arm",
          CF(1, 0.5, 0, _R_ROT), CF(-0.5, 0.5, 0, _R_ROT),
          LIMB_CHANNELS),
    Joint("LeftArm", "Left Shoulder", "Torso", "Left Arm",
          CF(-1, 0.5, 0, _L_ROT), CF(0.5, 0.5, 0, _L_ROT),
          LIMB_CHANNELS),
    Joint("RightLeg", "Right Hip", "Torso", "Right Leg",
          CF(1, -1, 0, _R_ROT), CF(0.5, 1, 0, _R_ROT),
          LIMB_CHANNELS),
    Joint("LeftLeg", "Left Hip", "Torso", "Left Leg",
          CF(-1, -1, 0, _L_ROT), CF(-0.5, 1, 0, _L_ROT),
          LIMB_CHANNELS),
]
JOINT = {j.key: j for j in JOINTS}
JOINT_KEYS = [j.key for j in JOINTS]
BY_PART = {j.part1: j for j in JOINTS}

TRANSLATION_CHANNELS = ("right", "up", "forward")

JOINT_ALIASES = {
    "torso": "Torso", "root": "Torso", "rootjoint": "Torso", "body": "Torso",
    "head": "Head", "neck": "Head",
    "rightarm": "RightArm", "rarm": "RightArm", "rightshoulder": "RightArm",
    "leftarm": "LeftArm", "larm": "LeftArm", "leftshoulder": "LeftArm",
    "rightleg": "RightLeg", "rleg": "RightLeg", "righthip": "RightLeg",
    "leftleg": "LeftLeg", "lleg": "LeftLeg", "lefthip": "LeftLeg",
}
CHANNEL_ALIASES = {
    "Torso": {"pitch": "lean", "bend": "lean", "yaw": "twist", "turn": "twist",
              "roll": "tilt", "side": "tilt", "x": "right", "y": "up"},
    "Head": {"pitch": "nod", "yaw": "turn", "twist": "turn", "roll": "tilt"},
    "limb": {"raise": "forward", "swing": "forward", "pitch": "forward", "flex": "forward",
             "abduct": "out", "spread": "out", "side": "out", "roll": "twist", "rotate": "twist",
             "extend": "reach", "stretch": "reach"},
}

# Sensible ranges (degrees / studs). Outside = probably a mistake or a broken-looking pose.
RANGES = {
    "Torso": {"lean": (-95, 95), "twist": (-90, 90), "tilt": (-60, 60),  # +-90 lean = lying down
              "right": (-3.5, 3.5), "up": (-2.6, 4), "forward": (-3.5, 3.5)},
    "Head": {"nod": (-60, 70), "turn": (-85, 85), "tilt": (-45, 45)},
    "arm": {"forward": (-100, 200), "out": (-40, 180), "twist": (-120, 120), "reach": (-0.8, 0.6)},
    "leg": {"forward": (-70, 130), "out": (-25, 90), "twist": (-60, 60), "reach": (-1.0, 0.3)},
}

PRIORITIES = ("Core", "Idle", "Movement", "Action", "Action2", "Action3", "Action4")


def range_for(joint: str, channel: str):
    if channel in OFFSETS:
        return (-1.0, 1.0)
    if joint in ("Torso", "Head"):
        return RANGES[joint][channel]
    return RANGES["arm" if joint.endswith("Arm") else "leg"][channel]


def normalize_joint(name: str) -> str:
    k = name.replace(" ", "").replace("_", "").lower()
    if k not in JOINT_ALIASES:
        raise SpecError(f"unknown joint '{name}' (use one of {', '.join(JOINT_KEYS)})")
    return JOINT_ALIASES[k]


def normalize_channel(joint: str, name: str) -> str:
    n = name.lower()
    if n in JOINT[joint].channels:
        return n
    table = CHANNEL_ALIASES[joint if joint in ("Torso", "Head") else "limb"]
    if n in table:
        return table[n]
    raise SpecError(f"unknown channel '{name}' for {joint} (use {', '.join(JOINT[joint].channels)})")


# ------------------------------------------------------- body pose <-> Transform


def side_of(joint: str) -> int:
    return 1 if joint.startswith("Right") else -1


def body_cf(joint: str, ch: dict) -> CF:
    """Channels (degrees/studs) -> rotation (+offset) in the parent part's axes."""
    g = lambda k: float(ch.get(k, 0.0))
    d = math.radians
    if joint == "Torso":
        rot = ry(-d(g("twist"))) * rx(-d(g("lean"))) * rz(-d(g("tilt")))
        return CF(g("right"), g("up"), -g("forward")) * rot
    off = (g("offset_right"), g("offset_up"), -g("offset_forward"))
    if joint == "Head":
        return CF(*off) * ry(-d(g("turn"))) * rx(-d(g("nod"))) * rz(-d(g("tilt")))
    s = side_of(joint)
    rot = rx(d(g("forward"))) * rz(s * d(g("out"))) * ry(-s * d(g("twist")))
    ax = rot.vector((0, -g("reach"), 0))
    return CF(ax[0] + off[0], ax[1] + off[1], ax[2] + off[2]) * rot


def body_to_transform(joint: str, body: CF) -> CF:
    c0r = JOINT[joint].c0.rotation()
    return c0r.inverse() * body * c0r


def transform_to_body(joint: str, transform: CF) -> CF:
    c0r = JOINT[joint].c0.rotation()
    return c0r * transform * c0r.inverse()


def channels_to_transform(joint: str, ch: dict) -> CF:
    return body_to_transform(joint, body_cf(joint, ch))


def body_to_channels(joint: str, body: CF) -> dict:
    """Inverse of body_cf (Euler extraction in the same orders)."""
    m = body.r
    deg = math.degrees
    clamp = lambda v: max(-1.0, min(1.0, v))
    if joint in ("Torso", "Head"):
        # R = Ry(a) Rx(b) Rz(c);  a=-yaw, b=-pitch, c=-roll
        b = math.asin(clamp(-m[5]))
        a = math.atan2(m[2], m[8])
        c = math.atan2(m[3], m[4])
        if joint == "Torso":
            out = {"lean": -deg(b), "twist": -deg(a), "tilt": -deg(c),
                   "right": body.x, "up": body.y, "forward": -body.z}
        else:
            out = {"nod": -deg(b), "turn": -deg(a), "tilt": -deg(c),
                   "offset_right": body.x, "offset_up": body.y, "offset_forward": -body.z}
    else:
        # R = Rx(f) Rz(s*o) Ry(-s*t); translation = reach along the limb + offsets
        s = side_of(joint)
        o = math.asin(clamp(-m[1]))
        f = math.atan2(m[7], m[4])
        t = math.atan2(m[2], m[0])
        out = {"forward": deg(f), "out": s * deg(o), "twist": -s * deg(t)}
        axis = (-m[1], -m[4], -m[7])  # limb's down direction
        dvec = body.pos
        reach = sum(p * q for p, q in zip(dvec, axis))
        rem = tuple(p - q * reach for p, q in zip(dvec, axis))
        out.update({"reach": reach, "offset_right": rem[0], "offset_up": rem[1], "offset_forward": -rem[2]})
    return {k: round(v, 3) + 0.0 for k, v in out.items() if abs(v) > 1e-4}


# --------------------------------------------------------------------- easing


@dataclass(frozen=True)
class Ease:
    style: str = "cubic"  # linear | constant | cubic | elastic | bounce
    direction: str = "inout"  # in | out | inout  (TweenService meaning: "out" = decelerate)

    def __str__(self):
        if self.style in ("linear", "constant"):
            return self.style
        if self.style == "cubic":
            return self.direction
        return f"{self.style}.{self.direction}"


EASE_STYLES = ("linear", "constant", "cubic", "elastic", "bounce")
EASE_DIRS = ("in", "out", "inout")


def parse_ease(s) -> Ease:
    if isinstance(s, Ease):
        return s
    t = str(s).strip().lower().replace("-", "").replace("_", "").replace(" ", "")
    if t in ("linear", "constant", "step", "snap", "hold"):
        return Ease("constant" if t in ("constant", "step", "snap", "hold") else "linear", "in")
    if t in EASE_DIRS:
        return Ease("cubic", t)
    parts = t.split(".")
    style = parts[0]
    direction = parts[1] if len(parts) > 1 else ("out" if style in ("elastic", "bounce") else "inout")
    if style == "cubicv2":
        style = "cubic"
    if style not in EASE_STYLES or direction not in EASE_DIRS:
        raise SpecError(f"unknown ease '{s}' (use linear, constant, in, out, inout, "
                        "cubic.<dir>, elastic.<dir>, bounce.<dir>)")
    return Ease(style, direction)


def _bounce_out(u):
    n, d = 7.5625, 2.75
    if u < 1 / d:
        return n * u * u
    if u < 2 / d:
        u -= 1.5 / d
        return n * u * u + 0.75
    if u < 2.5 / d:
        u -= 2.25 / d
        return n * u * u + 0.9375
    u -= 2.625 / d
    return n * u * u + 0.984375


def _elastic_out(u):
    if u in (0.0, 1.0):
        return u
    return 2 ** (-10 * u) * math.sin((u * 10 - 0.75) * (2 * math.pi / 3)) + 1


_OUT = {"cubic": lambda u: 1 - (1 - u) ** 3, "elastic": _elastic_out, "bounce": _bounce_out}


def ease_alpha(e: Ease, u: float) -> float:
    u = max(0.0, min(1.0, u))
    if e.style == "linear":
        return u
    if e.style == "constant":
        return 1.0 if u >= 1.0 else 0.0
    out = _OUT[e.style]
    if e.direction == "out":
        return out(u)
    if e.direction == "in":
        return 1 - out(1 - u)
    return (1 - out(1 - 2 * u)) / 2 if u < 0.5 else (1 + out(2 * u - 1)) / 2


# ------------------------------------------------------------------------ spec


class SpecError(ValueError):
    pass


RESERVED_KEY_FIELDS = {"t", "f", "time", "frame", "name", "ease", "from", "plant",
                       "airborne", "ground", "hold", "note", "comment"}


@dataclass
class Key:
    time: float
    name: str
    ease: Ease
    channels: dict  # joint -> {channel: value} (only keyed joints)
    joint_ease: dict  # joint -> Ease override
    plant: bool
    airborne: bool
    ground: bool = False
    bodies: dict = field(default_factory=dict)  # joint -> body CF (after plant)
    transforms: dict = field(default_factory=dict)  # joint -> Transform CF


@dataclass
class Marker:
    time: float
    name: str
    value: str = ""


@dataclass
class Anim:
    name: str
    loop: bool
    priority: str
    keys: list
    markers: list
    fps: float
    speed: float | None  # locomotion speed in studs/s this cycle should match
    grounded: bool
    raw: dict

    @property
    def length(self) -> float:
        return self.keys[-1].time if self.keys else 0.0

    def tracks(self):
        """joint -> [(time, transform, ease)] for keyframes where that joint is keyed."""
        out = {k: [] for k in JOINT_KEYS}
        for key in self.keys:
            for j, tf in key.transforms.items():
                out[j].append((key.time, tf, key.joint_ease.get(j, key.ease)))
        return out


def load_spec(path_or_dict) -> Anim:
    if isinstance(path_or_dict, dict):
        raw = path_or_dict
    else:
        with open(path_or_dict, encoding="utf-8") as fh:
            raw = json.load(fh)
    return parse_spec(raw)


def _norm_joint_dict(jd: dict, where: str) -> tuple[dict, Ease | None]:
    if not isinstance(jd, dict):
        raise SpecError(f"{where}: joint value must be an object of channels")
    ease = None
    out = {}
    for ck, cv in jd.items():
        if ck == "ease":
            ease = parse_ease(cv)
            continue
        joint = where.split(".")[-1]
        ch = normalize_channel(joint, ck)
        try:
            out[ch] = float(cv)
        except (TypeError, ValueError):
            raise SpecError(f"{where}.{ck}: expected a number, got {cv!r}")
    return out, ease


def _pose_from_obj(obj: dict, where: str):
    """Pull joint dicts out of a keyframe/pose object."""
    chans, eases = {}, {}
    for k, v in obj.items():
        if k in RESERVED_KEY_FIELDS:
            continue
        j = normalize_joint(k)
        c, e = _norm_joint_dict(v, f"{where}.{j}")
        chans[j] = c
        if e:
            eases[j] = e
    return chans, eases


def parse_spec(raw: dict) -> Anim:
    if not isinstance(raw, dict):
        raise SpecError("spec must be a JSON object")
    fps = float(raw.get("fps", 60))
    name = str(raw.get("name", "Animation"))
    loop = bool(raw.get("loop", False))
    priority = str(raw.get("priority", "Action"))
    match = [p for p in PRIORITIES if p.lower() == priority.lower()]
    if not match:
        raise SpecError(f"unknown priority '{priority}' (use {', '.join(PRIORITIES)})")
    priority = match[0]
    default_ease = parse_ease(raw.get("ease", "inout"))
    auto_ground = bool(raw.get("ground", False))

    library = {}
    for pname, pobj in (raw.get("poses") or {}).items():
        library[pname] = _pose_from_obj(pobj, f"poses.{pname}")[0]

    def time_of(obj, where):
        if "t" in obj or "time" in obj:
            return float(obj.get("t", obj.get("time")))
        if "f" in obj or "frame" in obj:
            return float(obj.get("f", obj.get("frame"))) / fps
        raise SpecError(f"{where}: needs 't' (seconds) or 'f' (frame at {fps:g} fps)")

    raw_keys = raw.get("keyframes")
    if not isinstance(raw_keys, list) or not raw_keys:
        raise SpecError("spec needs a non-empty 'keyframes' list")

    keys: list[Key] = []
    by_name: dict[str, Key] = {}
    for i, kobj in enumerate(raw_keys):
        where = f"keyframes[{i}]"
        if not isinstance(kobj, dict):
            raise SpecError(f"{where}: must be an object")
        t = time_of(kobj, where)
        chans, jeases = _pose_from_obj(kobj, where)
        base = None
        src_key = None  # a keyframe we copy from also lends its plant/airborne flags
        if kobj.get("hold"):
            if not keys:
                raise SpecError(f"{where}: 'hold' needs a previous keyframe")
            src_key = keys[-1]
            base = src_key.channels
        if "from" in kobj:
            ref = kobj["from"]
            if isinstance(ref, int):
                if not 0 <= ref < len(keys):
                    raise SpecError(f"{where}: 'from' index {ref} must point to an earlier keyframe")
                src_key = keys[ref]
                base = src_key.channels
            elif ref in by_name:
                src_key = by_name[ref]
                base = src_key.channels
            elif ref in library:
                base = library[ref]
            else:
                raise SpecError(f"{where}: 'from' = {ref!r} is not an earlier keyframe name or a pose in 'poses'")
        if base is not None:
            merged = copy.deepcopy(base)
            for j, c in chans.items():
                merged.setdefault(j, {}).update(c)
            chans = merged
        ease = parse_ease(kobj["ease"]) if "ease" in kobj else default_ease
        if src_key is not None:
            jeases = {**src_key.joint_ease, **jeases}
            if "ease" not in kobj:
                ease = src_key.ease
        airborne = bool(kobj.get("airborne", src_key.airborne if src_key else False))
        plant = bool(kobj.get("plant", src_key.plant if src_key else False))
        key = Key(time=t, name=str(kobj.get("name", "")), ease=ease, channels=chans,
                  joint_ease=jeases, plant=plant, airborne=airborne,
                  ground=bool(kobj.get("ground", auto_ground and not airborne)))
        keys.append(key)
        if key.name:
            by_name[key.name] = key

    for a, b in zip(keys, keys[1:]):
        if b.time <= a.time:
            raise SpecError(f"keyframe times must increase (t={b.time:g} after t={a.time:g})")
    if abs(keys[0].time) > 1e-9:
        raise SpecError("the first keyframe must be at t=0")

    for i, d in enumerate(raw.get("derive") or []):
        keys = _derive(keys, d, loop, f"derive[{i}]", fps)

    for key in keys:
        _solve_key(key)
    _apply_ground(keys)

    markers = []
    for i, m in enumerate(raw.get("markers") or []):
        markers.append(Marker(time_of(m, f"markers[{i}]"), str(m.get("name", "Marker")), str(m.get("value", ""))))

    speed = raw.get("speed")
    return Anim(name=name, loop=loop, priority=priority, keys=keys, markers=markers, fps=fps,
                speed=float(speed) if speed is not None else None,
                grounded=bool(raw.get("grounded", True)), raw=raw)


def _channel_at(track, t):
    """Interpolate channel dicts (per-channel, eased) - used only by 'derive'."""
    if t <= track[0][0]:
        return dict(track[0][1]), track[0][2]
    for (t0, a, e), (t1, b, _) in zip(track, track[1:]):
        if t0 <= t <= t1:
            u = ease_alpha(e, (t - t0) / (t1 - t0) if t1 > t0 else 1.0)
            return {c: a.get(c, 0.0) + (b.get(c, 0.0) - a.get(c, 0.0)) * u for c in set(a) | set(b)}, e
    return dict(track[-1][1]), track[-1][2]


def _derive(keys, d, loop, where, fps):
    """{"joint": "LeftLeg", "from": "RightLeg", "phase": 0.5} copies a joint's keys onto another
    joint, shifted in time (phase = fraction of the loop; or "shift" seconds, or "shiftFrames").
    Left/right limb channels are mirror-symmetric, so a copy IS the mirrored motion.
    Torso/Head get twist/tilt/turn/right negated when "mirror": true."""
    if not isinstance(d, dict) or "joint" not in d or "from" not in d:
        raise SpecError(f"{where}: needs 'joint' and 'from'")
    dst, src = normalize_joint(d["joint"]), normalize_joint(d["from"])
    L = keys[-1].time
    if any(dst in k.channels for k in keys):
        raise SpecError(f"{where}: {dst} is keyed directly AND derived; remove one")
    track = [(k.time, k.channels[src], k.joint_ease.get(src, k.ease)) for k in keys if src in k.channels]
    if not track:
        raise SpecError(f"{where}: source joint {src} has no keys")
    if "shift" in d:
        shift = float(d["shift"])
    elif "shiftFrames" in d:
        shift = float(d["shiftFrames"]) / fps
    else:
        shift = float(d.get("phase", 0.5)) * L
    opposite_limbs = src != dst and src[:-3] in ("Right", "Left") and dst[:-3] in ("Right", "Left") \
        and src[-3:] == dst[-3:] and src != dst
    negate = MIRROR_NEGATE.get(dst, ()) if (d.get("mirror") or opposite_limbs) else ()

    def conv(ch):
        return {c: (-v if c in negate else v) for c, v in ch.items()}

    entries = {}
    for t, ch, e in track:
        nt = ((t + shift) % L) if loop and L > 0 else t + shift
        if loop and abs(nt - L) < 1e-6:
            nt = 0.0
        if 0 <= nt <= L + 1e-9:
            entries[round(nt, 6)] = (nt, conv(ch), e)
    if loop:
        ch0, e0 = _channel_at(track, (-shift) % L if L > 0 else 0)
        entries.setdefault(0.0, (0.0, conv(ch0), e0))
        entries[round(L, 6)] = (L, entries[0.0][1], entries[0.0][2])
    else:
        if 0.0 not in entries:
            ch0, e0 = _channel_at(track, -shift)
            entries[0.0] = (0.0, conv(ch0), e0)
    out = list(keys)
    for nt, ch, e in sorted(entries.values(), key=lambda x: x[0]):
        hit = next((k for k in out if abs(k.time - nt) < 1e-6), None)
        if hit is None:
            prev = max((k for k in out if k.time < nt), key=lambda k: k.time, default=out[0])
            hit = Key(time=nt, name="", ease=e, channels={}, joint_ease={}, plant=False,
                      airborne=prev.airborne, ground=False)
            out.append(hit)
            out.sort(key=lambda k: k.time)
        hit.channels[dst] = dict(ch)
        hit.joint_ease[dst] = e
    return out


HIP_MID = (0.0, -1.0, 0.0)  # midpoint between the two hip pivots, in Torso space


LEGS = ("RightLeg", "LeftLeg")


def axis_angle(axis, angle) -> CF:
    n = math.sqrt(sum(a * a for a in axis))
    if n < 1e-12 or abs(angle) < 1e-12:
        return CF()
    x, y, z = (a / n for a in axis)
    c, s_, t = math.cos(angle), math.sin(angle), 1 - math.cos(angle)
    return CF(0, 0, 0, (t * x * x + c, t * x * y - s_ * z, t * x * z + s_ * y,
                        t * x * y + s_ * z, t * y * y + c, t * y * z - s_ * x,
                        t * x * z - s_ * y, t * y * z + s_ * x, t * z * z + c))


def _align(u, v) -> CF:
    """Shortest rotation taking direction u onto direction v."""
    nu = math.sqrt(sum(a * a for a in u)); nv = math.sqrt(sum(a * a for a in v))
    u = tuple(a / nu for a in u); v = tuple(a / nv for a in v)
    dot = max(-1.0, min(1.0, sum(a * b for a, b in zip(u, v))))
    axis = (u[1] * v[2] - u[2] * v[1], u[2] * v[0] - u[0] * v[2], u[0] * v[1] - u[1] * v[0])
    return axis_angle(axis, math.acos(dot))


def _foot_vec(leg, reach=0.0):
    """Hip pivot -> sole centre in the (unrotated) leg frame: the hip pivots at the leg's
    top outer corner, so this is (-+0.5, -2, 0), lengthened by reach along the leg."""
    pivot = JOINT[leg].c1.pos
    return (0 - pivot[0], -1 - pivot[1] - reach, 0 - pivot[2])


def _solve_key(key: Key):
    """Channels -> body CFs -> Transforms. Applies 'plant'."""
    bodies = {j: body_cf(j, c) for j, c in key.channels.items()}
    if key.plant:
        tch = key.channels.setdefault("Torso", {})
        tb = body_cf("Torso", tch)
        rot = tb.rotation()
        legs_user = {leg: body_cf(leg, key.channels.setdefault(leg, {})) for leg in LEGS}
        # The torso pivots at the hips (bending "at the waist"), not at its own centre.
        mid_rot = rot.vector(HIP_MID)
        shift = tuple(m - mr for m, mr in zip(HIP_MID, mid_rot))
        if key.airborne:
            # In the air: legs just keep their world angles.
            bodies["Torso"] = CF(tb.x + shift[0], tb.y + shift[1], tb.z + shift[2], rot.r)
            for leg in LEGS:
                bodies[leg] = rot.inverse() * legs_user[leg]
        else:
            # On the ground: lock the feet where these leg angles would stand with an upright
            # torso, then aim each leg at its foot and slide it along its length to reach it.
            ref = forward_kinematics({leg: body_to_transform(leg, legs_user[leg]) for leg in LEGS})
            low = min(p[1] for leg in ("Right Leg", "Left Leg") for p in box_corners(ref[leg], PART_SIZE[leg]))
            feet = {leg: limb_tip(ref, JOINT[leg].part1) for leg in LEGS}
            feet = {leg: (f[0], f[1] - low, f[2]) for leg, f in feet.items()}
            y = tb.y + shift[1] - low
            for _ in range(4):  # legs can't stretch: if a hip rose too far (tilt), lower the body
                torso = CF(tb.x + shift[0], y, tb.z + shift[2], rot.r)
                torso_world = CF(0, HRP_HEIGHT, 0) * torso
                need = {}
                for leg in LEGS:
                    hip = torso_world.point(JOINT[leg].c0.pos)
                    target = tuple(f - h for f, h in zip(feet[leg], hip))
                    need[leg] = (target, math.sqrt(max(sum(t * t for t in target) - 0.25, 0.0)) - 2.0)
                worst = max(r for _, r in need.values())
                if worst <= 0.02:
                    break
                y -= worst
            bodies["Torso"] = torso
            for leg in LEGS:
                target, reach = need[leg]
                reach = max(-0.9, min(0.02, reach))
                user_world = legs_user[leg].rotation()
                cur = user_world.vector(_foot_vec(leg, reach))
                world_rot = _align(cur, target) * user_world
                rel = rot.inverse() * world_rot
                d = rel.vector((0, -reach, 0))
                bodies[leg] = CF(d[0], d[1], d[2], rel.r)
                # A tilted leg block dips a corner below its sole centre: stand on that corner.
                part = forward_kinematics({"Torso": body_to_transform("Torso", torso),
                                           leg: body_to_transform(leg, bodies[leg])})[JOINT[leg].part1]
                dip = min(p[1] for p in box_corners(part, PART_SIZE[JOINT[leg].part1]))
                if dip < -1e-4:
                    d = rel.vector((0, -(reach + dip), 0))
                    bodies[leg] = CF(d[0], d[1], d[2], rel.r)
    key.bodies = bodies
    key.transforms = {j: body_to_transform(j, b) for j, b in bodies.items()}


def _apply_ground(keys):
    """'ground': slide the body up/down so the lowest point of either leg touches y=0.
    Legs not keyed on that keyframe use the value their curve has at that time."""
    probe = Anim("probe", False, "Action", keys, [], 60, None, True, {})
    tracks = probe.tracks()
    for key in keys:
        if not key.ground or (key.plant and not key.airborne):
            continue  # planted keys already stand on the floor
        tfs = {j: transform_at(tracks[j], key.time) for j in JOINT_KEYS}
        tb = key.bodies.get("Torso") or body_cf("Torso", key.channels.setdefault("Torso", {}))
        tfs.update({j: key.transforms[j] for j in key.transforms})
        tfs["Torso"] = body_to_transform("Torso", tb)
        parts = forward_kinematics(tfs)
        low = min(p[1] for leg in ("Right Leg", "Left Leg") for p in box_corners(parts[leg], PART_SIZE[leg]))
        key.bodies["Torso"] = CF(tb.x, tb.y - low, tb.z, tb.r)
        key.transforms["Torso"] = body_to_transform("Torso", key.bodies["Torso"])


# ------------------------------------------------------------------- sampling


def transform_at(track, t: float) -> CF:
    """track = [(time, transform, ease)]. Roblox semantics: hold before first/after last
    key; between keys the ease stored on the earlier key shapes the segment."""
    if not track:
        return IDENTITY
    if t <= track[0][0]:
        return track[0][1]
    if t >= track[-1][0]:
        return track[-1][1]
    for (t0, a, e), (t1, b, _) in zip(track, track[1:]):
        if t0 <= t <= t1:
            u = (t - t0) / (t1 - t0) if t1 > t0 else 1.0
            return cf_lerp(a, b, ease_alpha(e, u))
    return track[-1][1]


def sample(anim: Anim, t: float, tracks=None) -> dict:
    tracks = tracks or anim.tracks()
    return {j: transform_at(tracks[j], t) for j in JOINT_KEYS}


def forward_kinematics(transforms: dict, hrp: CF | None = None) -> dict:
    """Joint transforms -> world CFrame of every part (HRP at (0,3,0) facing -Z)."""
    parts = {"HumanoidRootPart": hrp or CF(0, HRP_HEIGHT, 0)}
    for j in JOINTS:
        parts[j.part1] = parts[j.part0] * j.c0 * transforms.get(j.key, IDENTITY) * j.c1.inverse()
    return parts


def box_corners(cf: CF, size):
    hx, hy, hz = (s / 2 for s in size)
    return [cf.point((sx * hx, sy * hy, sz * hz)) for sx in (-1, 1) for sy in (-1, 1) for sz in (-1, 1)]


def limb_tip(parts: dict, part: str):
    """Centre of the far end (hand/foot) of a limb part."""
    return parts[part].point((0, -1, 0))


def sample_times(anim: Anim, fps: float = 60.0):
    n = max(1, int(round(anim.length * fps)))
    return [anim.length * i / n for i in range(n + 1)]


# --------------------------------------------------------------------- mirror


MIRROR_NEGATE = {"Torso": ("twist", "tilt", "right"), "Head": ("turn", "tilt", "offset_right"),
                 "RightArm": ("offset_right",), "LeftArm": ("offset_right",),
                 "RightLeg": ("offset_right",), "LeftLeg": ("offset_right",)}
SWAP = {"RightArm": "LeftArm", "LeftArm": "RightArm", "RightLeg": "LeftLeg", "LeftLeg": "RightLeg"}


def mirror_raw(raw: dict) -> dict:
    """Mirror a spec left<->right (e.g. right punch -> left punch)."""
    out = copy.deepcopy(raw)

    def mirror_pose(obj: dict) -> dict:
        res = {}
        for k, v in obj.items():
            if k in RESERVED_KEY_FIELDS:
                res[k] = v
                continue
            j = normalize_joint(k)
            vv = dict(v)
            for ck in list(vv):
                if ck == "ease":
                    continue
                if normalize_channel(j, ck) in MIRROR_NEGATE.get(j, ()):
                    vv[ck] = -float(vv[ck])
            res[SWAP.get(j, j)] = vv
        return res

    out["keyframes"] = [mirror_pose(k) for k in raw["keyframes"]]
    if raw.get("poses"):
        out["poses"] = {n: mirror_pose(p) for n, p in raw["poses"].items()}
    name = str(raw.get("name", "Animation"))
    if name.endswith("_R"):
        out["name"] = name[:-2] + "_L"
    elif name.endswith("_L"):
        out["name"] = name[:-2] + "_R"
    else:
        out["name"] = name + "_Mirror"
    return out
