#!/usr/bin/env python3
"""
r6anim - one CLI for the whole R6 keyframe workflow.

  python r6anim.py build  spec.json [-o outdir]   lint + previews + .rbxmx + .luau (the usual command)
  python r6anim.py lint   spec.json               findings only
  python r6anim.py render spec.json [-o outdir] [--views front,side] [--every 0.05] [--no-gif]
  python r6anim.py export spec.json [-o outdir]   .rbxmx + .luau only
  python r6anim.py mirror spec.json -o out.json   swap left/right (right punch -> left punch)
  python r6anim.py import anim.rbxmx -o spec.json read an existing KeyframeSequence into a spec
  python r6anim.py pose   '{"RightArm":{"forward":90}}' -o pose.png   preview one pose

Exit code 1 if the spec is invalid or lint finds an ERROR.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from r6core import (SpecError, channels_to_transform, load_spec, mirror_raw,  # noqa: E402
                    normalize_joint, normalize_channel)


def _slug(name: str) -> str:
    return re.sub(r"[^A-Za-z0-9_-]+", "_", name).strip("_") or "animation"


def _outdir(args, spec_path):
    d = args.out or os.path.join(os.path.dirname(os.path.abspath(spec_path)), "out")
    os.makedirs(d, exist_ok=True)
    return d


def _load(path):
    try:
        return load_spec(path)
    except (SpecError, json.JSONDecodeError) as e:
        print(f"SPEC ERROR in {path}: {e}")
        sys.exit(1)


def cmd_lint(args):
    from r6lint import lint, report
    anim = _load(args.spec)
    print(report(anim))
    return 1 if any(l == "ERROR" for l, _ in lint(anim)) else 0


def _render(anim, d, args):
    import r6render
    base = os.path.join(d, _slug(anim.name))
    views = tuple(v.strip() for v in (args.views or "front,side,three_quarter").split(","))
    times = None
    if getattr(args, "every", None):
        n = max(1, round(anim.length / args.every))
        times = [anim.length * i / n for i in range(n + 1)]
    made = [r6render.contact_sheet(anim, base + "_sheet.png", views=views, times=times)]
    made.append(r6render.onion(anim, base + "_onion.png"))
    if not getattr(args, "no_gif", False):
        made.append(r6render.gif(anim, base + ".gif", views=views))
    return made


def _export(anim, d):
    from r6export import to_luau, to_rbxmx
    base = os.path.join(d, _slug(anim.name))
    with open(base + ".rbxmx", "w", encoding="utf-8") as fh:
        fh.write(to_rbxmx(anim))
    with open(base + ".luau", "w", encoding="utf-8") as fh:
        fh.write(to_luau(anim))
    return [base + ".rbxmx", base + ".luau"]


def cmd_render(args):
    anim = _load(args.spec)
    for p in _render(anim, _outdir(args, args.spec), args):
        print("wrote", p)
    return 0


def cmd_export(args):
    anim = _load(args.spec)
    for p in _export(anim, _outdir(args, args.spec)):
        print("wrote", p)
    return 0


def cmd_build(args):
    from r6lint import lint, report
    anim = _load(args.spec)
    d = _outdir(args, args.spec)
    print(report(anim))
    print()
    made = _export(anim, d)
    if not args.no_render:
        made += _render(anim, d, args)
    for p in made:
        print("wrote", p)
    print("\nLook at the *_sheet.png and *_onion.png before calling it done.")
    return 1 if any(l == "ERROR" for l, _ in lint(anim)) else 0


def cmd_mirror(args):
    with open(args.spec, encoding="utf-8") as fh:
        raw = json.load(fh)
    out = mirror_raw(raw)
    path = args.out or args.spec.replace(".json", "_mirror.json")
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(out, fh, indent=2)
    print("wrote", path)
    return 0


def cmd_import(args):
    from r6export import from_rbxmx
    with open(args.file, encoding="utf-8") as fh:
        spec = from_rbxmx(fh.read(), fps=args.fps)
    path = args.out or os.path.splitext(args.file)[0] + ".json"
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(spec, fh, indent=2)
    print("wrote", path, f"({len(spec['keyframes'])} keyframes)")
    return 0


def cmd_pose(args):
    import r6render
    pose = json.loads(args.pose)
    tfs = {}
    for k, ch in pose.items():
        j = normalize_joint(k)
        tfs[j] = channels_to_transform(j, {normalize_channel(j, c): float(v) for c, v in ch.items()})
    path = args.out or "pose.png"
    r6render.pose_image(tfs, path)
    print("wrote", path)
    for j, tf in tfs.items():
        print(f"  {j:9} Pose.CFrame = {tf!r}")
    return 0


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)

    def add(name, fn, spec_arg="spec"):
        p = sub.add_parser(name)
        if spec_arg:
            p.add_argument(spec_arg)
        p.add_argument("-o", "--out")
        p.set_defaults(fn=fn)
        return p

    add("lint", cmd_lint)
    for name, fn in (("build", cmd_build), ("render", cmd_render)):
        p = add(name, fn)
        p.add_argument("--views", help="comma list: front,side,back,three_quarter,top")
        p.add_argument("--every", type=float, help="contact sheet every N seconds instead of every key")
        p.add_argument("--no-gif", action="store_true")
        if name == "build":
            p.add_argument("--no-render", action="store_true")
    add("export", cmd_export)
    add("mirror", cmd_mirror)
    p = add("import", cmd_import, spec_arg="file")
    p.add_argument("--fps", type=float, default=60)
    add("pose", cmd_pose, spec_arg="pose")
    args = ap.parse_args(argv)
    return args.fn(args)


if __name__ == "__main__":
    sys.exit(main())
