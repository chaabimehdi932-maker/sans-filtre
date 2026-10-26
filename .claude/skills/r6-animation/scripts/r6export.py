"""
r6export - turn a parsed spec into something Roblox Studio can load, and back.

  to_rbxmx(anim)  -> KeyframeSequence as .rbxmx XML (drag the file into Studio, or
                     right-click ServerStorage > Insert from File)
  to_luau(anim)   -> a Command Bar script that builds the same KeyframeSequence
  from_rbxmx(xml) -> spec dict (to inspect, lint, render or edit an existing animation)

Pose tree per keyframe: HumanoidRootPart > Torso > {Head, Right Arm, Left Arm,
Right Leg, Left Leg}. Only joints keyed at that keyframe get a real Pose (Weight 1);
parents that are needed only to hold the hierarchy are written with Weight 0 and the
value the curve already has at that time, so they are harmless either way.
"""

from __future__ import annotations

import uuid
import xml.etree.ElementTree as ET
from collections import Counter

from r6core import (BY_PART, CF, JOINT, JOINTS, Anim, Ease, body_to_channels, fmt_num, sample,
                    transform_to_body)

PRIORITY_ENUM = {"Idle": 0, "Movement": 1, "Action": 2, "Action2": 3, "Action3": 4, "Action4": 5, "Core": 1000}
STYLE_ENUM = {"linear": 0, "constant": 1, "elastic": 2, "cubic_legacy": 3, "bounce": 4, "cubic": 5}  # cubic -> CubicV2
STYLE_FROM_ENUM = {0: "linear", 1: "constant", 2: "elastic", 3: "cubic_legacy", 4: "bounce", 5: "cubic"}
DIR_ENUM = {"in": 0, "out": 1, "inout": 2}

# Our ease names use the TweenService meaning ("out" = decelerate into the next key).
# At runtime CubicV2, Elastic and Bounce follow that meaning; legacy Cubic (token 3) is
# reversed, which is why we always write CubicV2. Constant must be written with direction
# Out: Out = hold the pose then snap at the next key (what the editor previews), In = snap
# to the next pose immediately, InOut = snap halfway. See references/formats.md "Easing".
DIRECTION_SWAPPED = {"cubic": False, "elastic": False, "bounce": False, "cubic_legacy": True}


def ease_to_enums(e: Ease):
    style = STYLE_ENUM[e.style]
    if e.style == "constant":
        return style, DIR_ENUM["out"]
    if e.style == "linear":
        return style, DIR_ENUM["in"]
    d = e.direction
    if DIRECTION_SWAPPED.get(e.style) and d != "inout":
        d = "out" if d == "in" else "in"
    return style, DIR_ENUM[d]


def enums_to_ease(style: int, direction: int) -> Ease:
    """Roblox tokens -> our Ease. Constant In/InOut (snap early) are approximated as a hold."""
    s = STYLE_FROM_ENUM.get(style, "linear")
    d = {0: "in", 1: "out", 2: "inout"}.get(direction, "inout")
    if DIRECTION_SWAPPED.get(s) and d != "inout":
        d = "out" if d == "in" else "in"
    if s == "cubic_legacy":
        s = "cubic"
    if s in ("linear", "constant"):
        d = "in"
    return Ease(s, d)


# ------------------------------------------------------------------ tree build


def _pose_tree(anim: Anim, key, tracks):
    """-> nested list [(part, transform, weight, ease, children)] for one keyframe."""
    keyed = set(key.transforms)
    if not keyed:
        return None
    sampled = sample(anim, key.time, tracks)

    def node(joint_key, part):
        kids = [node(j.key, j.part1) for j in JOINTS if j.part0 == part]
        kids = [k for k in kids if k]
        if joint_key in keyed:
            return (part, key.transforms[joint_key], 1.0, key.joint_ease.get(joint_key, key.ease), kids)
        if kids:
            tf = sampled[joint_key] if joint_key else CF()
            return (part, tf, 0.0, key.ease, kids)
        return None

    torso = node("Torso", "Torso")
    return ("HumanoidRootPart", CF(), 0.0, key.ease, [torso] if torso else [])


def _keyframe_list(anim: Anim):
    """Keyframes plus marker-only keyframes, sorted. -> [(time, name, key|None, [markers])]."""
    entries = {}
    for k in anim.keys:
        entries[round(k.time, 6)] = [k.time, k.name or "Keyframe", k, []]
    for m in anim.markers:
        e = entries.setdefault(round(m.time, 6), [m.time, "Keyframe", None, []])
        e[3].append(m)
    out = [tuple(v) for _, v in sorted(entries.items())]
    if out:  # the default Animate script listens for a final keyframe named "End"
        t, _, k, m = out[-1]
        out[-1] = (t, "End", k, m)
    return out


# ------------------------------------------------------------------- rbxmx


def _ref():
    return "RBX" + uuid.uuid4().hex.upper()


def _esc(s: str) -> str:
    return (s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
            .replace('"', "&quot;"))


def _cframe_xml(cf: CF, ind: str) -> str:
    names = ("X", "Y", "Z", "R00", "R01", "R02", "R10", "R11", "R12", "R20", "R21", "R22")
    inner = "".join(f"<{n}>{fmt_num(v)}</{n}>" for n, v in zip(names, cf.components()))
    return f'{ind}<CoordinateFrame name="CFrame">{inner}</CoordinateFrame>\n'


def _pose_xml(node, ind: str) -> str:
    part, tf, weight, ease, kids = node
    style, direction = ease_to_enums(ease)
    s = f'{ind}<Item class="Pose" referent="{_ref()}">\n{ind}\t<Properties>\n'
    s += _cframe_xml(tf, ind + "\t\t")
    s += f'{ind}\t\t<token name="EasingDirection">{direction}</token>\n'
    s += f'{ind}\t\t<token name="EasingStyle">{style}</token>\n'
    s += f'{ind}\t\t<string name="Name">{_esc(part)}</string>\n'
    s += f'{ind}\t\t<float name="Weight">{fmt_num(weight)}</float>\n'
    s += f"{ind}\t</Properties>\n"
    for k in kids:
        s += _pose_xml(k, ind + "\t")
    return s + f"{ind}</Item>\n"


def to_rbxmx(anim: Anim) -> str:
    tracks = anim.tracks()
    out = ['<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" '
           'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
           'xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" version="4">\n',
           "\t<External>null</External>\n\t<External>nil</External>\n",
           f'\t<Item class="KeyframeSequence" referent="{_ref()}">\n\t\t<Properties>\n',
           '\t\t\t<float name="AuthoredHipHeight">2</float>\n',
           f'\t\t\t<bool name="Loop">{"true" if anim.loop else "false"}</bool>\n',
           f'\t\t\t<string name="Name">{_esc(anim.name)}</string>\n',
           f'\t\t\t<token name="Priority">{PRIORITY_ENUM[anim.priority]}</token>\n',
           "\t\t</Properties>\n"]
    for time, name, key, markers in _keyframe_list(anim):
        out.append(f'\t\t<Item class="Keyframe" referent="{_ref()}">\n\t\t\t<Properties>\n')
        out.append(f'\t\t\t\t<string name="Name">{_esc(name)}</string>\n')
        out.append(f'\t\t\t\t<float name="Time">{fmt_num(time)}</float>\n\t\t\t</Properties>\n')
        tree = _pose_tree(anim, key, tracks) if key else None
        if tree:
            out.append(_pose_xml(tree, "\t\t\t"))
        for m in markers:
            out.append(f'\t\t\t<Item class="KeyframeMarker" referent="{_ref()}">\n\t\t\t\t<Properties>\n'
                       f'\t\t\t\t\t<string name="Name">{_esc(m.name)}</string>\n'
                       f'\t\t\t\t\t<string name="Value">{_esc(m.value)}</string>\n'
                       "\t\t\t\t</Properties>\n\t\t\t</Item>\n")
        out.append("\t\t</Item>\n")
    out.append("\t</Item>\n</roblox>\n")
    return "".join(out)


# -------------------------------------------------------------------- luau


def _luau_str(s: str) -> str:
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'


def to_luau(anim: Anim) -> str:
    """Command Bar script: builds the KeyframeSequence into the selected rig's Animation Editor saves."""
    tracks = anim.tracks()
    lines = [
        f"-- {anim.name}: generated R6 KeyframeSequence ({anim.length:.3f}s, {len(anim.keys)} keys).",
        "-- Select your R6 rig in Studio, then paste this into the Command Bar (View > Command Bar).",
        "-- Then Animation Editor > select the rig > ... > Load. Publish from the editor to get an asset id.",
        "local E, D = Enum.PoseEasingStyle, Enum.PoseEasingDirection",
        "local function P(parent, name, w, style, dir, ...)",
        "\tlocal p = Instance.new(\"Pose\")",
        "\tp.Name = name",
        "\tp.Weight = w",
        "\tp.EasingStyle = style",
        "\tp.EasingDirection = dir",
        "\tp.CFrame = CFrame.new(...)",
        "\tp.Parent = parent",
        "\treturn p",
        "end",
        "local kfs = Instance.new(\"KeyframeSequence\")",
        f"kfs.Name = {_luau_str(anim.name)}",
        f"kfs.Loop = {'true' if anim.loop else 'false'}",
        f"kfs.Priority = Enum.AnimationPriority.{anim.priority}",
    ]
    style_names = {0: "Linear", 1: "Constant", 2: "Elastic", 3: "Cubic", 4: "Bounce", 5: "CubicV2"}
    dir_names = {0: "In", 1: "Out", 2: "InOut"}

    def emit(node, parent_var, depth):
        part, tf, weight, ease, kids = node
        st, di = ease_to_enums(ease)
        var = f"p{depth}"
        nums = ", ".join(fmt_num(v) for v in tf.components())
        lines.append(f"local {var} = P({parent_var}, {_luau_str(part)}, {fmt_num(weight)}, "
                     f"E.{style_names[st]}, D.{dir_names[di]}, {nums})")
        for k in kids:
            emit(k, var, depth + 1)

    for i, (time, name, key, markers) in enumerate(_keyframe_list(anim)):
        lines.append("do")
        lines.append("\tlocal k = Instance.new(\"Keyframe\")")
        lines.append(f"\tk.Name = {_luau_str(name)}")
        lines.append(f"\tk.Time = {fmt_num(time)}")
        tree = _pose_tree(anim, key, tracks) if key else None
        if tree:
            start = len(lines)
            emit(tree, "k", 0)
            for j in range(start, len(lines)):
                lines[j] = "\t" + lines[j]
        for m in markers:
            lines.append("\tlocal m = Instance.new(\"KeyframeMarker\")")
            lines.append(f"\tm.Name = {_luau_str(m.name)}")
            lines.append(f"\tm.Value = {_luau_str(m.value)}")
            lines.append("\tm.Parent = k")
        lines.append("\tk.Parent = kfs")
        lines.append("end")
    lines += [
        "-- Where to put it: if an R6 rig is selected, into the rig's Animation Editor saves",
        "-- (ServerStorage.RBX_ANIMSAVES.<Rig>, linked from rig.AnimSaves) so Editor > ... > Load lists it.",
        "local ss = game:GetService(\"ServerStorage\")",
        "local sel = game:GetService(\"Selection\"):Get()[1]",
        "local rig = sel and (sel:IsA(\"Model\") and sel or sel:FindFirstAncestorOfClass(\"Model\"))",
        "local folder",
        "if rig and rig:FindFirstChildOfClass(\"Humanoid\") then",
        "\tlocal ref = rig:FindFirstChild(\"AnimSaves\")",
        "\tif ref and not ref:IsA(\"ObjectValue\") then",
        "\t\tfolder = ref -- legacy AnimSaves folder: the editor still reads it",
        "\telse",
        "\t\tlocal saves = ss:FindFirstChild(\"RBX_ANIMSAVES\") or Instance.new(\"Model\")",
        "\t\tsaves.Name = \"RBX_ANIMSAVES\"",
        "\t\tsaves.Parent = ss",
        "\t\tif not ref then",
        "\t\t\tref = Instance.new(\"ObjectValue\")",
        "\t\t\tref.Name = \"AnimSaves\"",
        "\t\t\tref.Parent = rig",
        "\t\tend",
        "\t\tif not ref.Value then",
        "\t\t\tlocal holder = Instance.new(\"ObjectValue\")",
        "\t\t\tholder.Name = rig.Name",
        "\t\t\tholder.Value = rig",
        "\t\t\tholder.Parent = saves",
        "\t\t\tref.Value = holder",
        "\t\tend",
        "\t\tfolder = ref.Value",
        "\tend",
        "else",
        "\tfolder = ss:FindFirstChild(\"R6Generated\") or Instance.new(\"Folder\")",
        "\tfolder.Name = \"R6Generated\"",
        "\tfolder.Parent = ss",
        "\twarn(\"No R6 rig selected: saved to ServerStorage.R6Generated. Select a rig and re-run to load it in the Animation Editor.\")",
        "end",
        "local old = folder:FindFirstChild(kfs.Name)",
        "if old then old:Destroy() end",
        "kfs.Parent = folder",
        "game:GetService(\"Selection\"):Set({ kfs })",
        "print(\"Built \" .. kfs:GetFullName() .. \" - Animation Editor: select the rig, ... > Load > \" .. kfs.Name)",
    ]
    return "\n".join(lines) + "\n"


# ------------------------------------------------------------------ import


def _props(item):
    p = item.find("Properties")
    return p if p is not None else ET.Element("Properties")


def _prop(props, tag, name, default=None):
    for el in props.findall(tag):
        if el.get("name") == name:
            return el
    return default


def from_rbxmx(xml_text: str, fps: float = 60.0) -> dict:
    """KeyframeSequence .rbxmx -> spec dict (channels in degrees/studs)."""
    root = ET.fromstring(xml_text)
    kfs = root.find(".//Item[@class='KeyframeSequence']")
    if kfs is None:
        raise ValueError("no KeyframeSequence in this file (save the animation as .rbxmx)")
    props = _props(kfs)
    name_el = _prop(props, "string", "Name")
    loop_el = _prop(props, "bool", "Loop")
    prio_el = _prop(props, "token", "Priority")
    prio = {v: k for k, v in PRIORITY_ENUM.items()}.get(int(prio_el.text) if prio_el is not None else 2, "Action")
    spec = {"name": name_el.text if name_el is not None else "Imported",
            "loop": (loop_el is not None and loop_el.text.strip().lower() == "true"),
            "priority": prio, "fps": fps, "keyframes": [], "markers": []}

    frames = []
    for kf in kfs.findall("Item[@class='Keyframe']"):
        kp = _props(kf)
        t = float(_prop(kp, "float", "Time").text)
        kname = _prop(kp, "string", "Name")
        poses = {}

        def walk(item):
            for pose in item.findall("Item[@class='Pose']"):
                pp = _props(pose)
                part = _prop(pp, "string", "Name").text
                w_el = _prop(pp, "float", "Weight")
                weight = float(w_el.text) if w_el is not None else 1.0
                cf_el = _prop(pp, "CoordinateFrame", "CFrame")
                st = _prop(pp, "token", "EasingStyle")
                di = _prop(pp, "token", "EasingDirection")
                if part in BY_PART and weight > 0 and cf_el is not None:
                    comps = [float(cf_el.find(n).text) for n in
                             ("X", "Y", "Z", "R00", "R01", "R02", "R10", "R11", "R12", "R20", "R21", "R22")]
                    j = BY_PART[part].key
                    ease = enums_to_ease(int(st.text) if st is not None else 0, int(di.text) if di is not None else 0)
                    poses[j] = (body_to_channels(j, transform_to_body(j, CF.new(*comps))), ease)
                walk(pose)

        walk(kf)
        markers = []
        for m in kf.findall("Item[@class='KeyframeMarker']"):
            mp = _props(m)
            mv = _prop(mp, "string", "Value")
            markers.append({"t": round(t, 4), "name": _prop(mp, "string", "Name").text or "Marker",
                            "value": (mv.text or "") if mv is not None else ""})
        frames.append((t, kname.text if kname is not None else "", poses, markers))

    frames.sort(key=lambda f: f[0])
    for t, kname, poses, markers in frames:
        spec["markers"].extend(markers)
        if not poses and t > 0:
            continue
        common = Counter(str(e) for _, e in poses.values()).most_common(1)
        key_ease = common[0][0] if common else "linear"
        k = {"t": round(t, 4)}
        if kname and kname != "Keyframe":
            k["name"] = kname
        k["ease"] = key_ease
        for j in JOINT:
            if j in poses:
                ch, e = poses[j]
                entry = dict(ch)
                if str(e) != key_ease:
                    entry["ease"] = str(e)
                k[j] = entry
        spec["keyframes"].append(k)
    if not spec["markers"]:
        del spec["markers"]
    return spec
