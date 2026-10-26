---
name: r6-animation
description: Create, fix and critique keyframed animations for Roblox R6 characters (the classic 6-part blocky rig) — walk/run cycles, idles, jumps, combat M1 combos, punches, sword slashes, blocks, hit reacts, deaths, dashes, emotes, dances. Writes a body-language animation spec, converts it to exact R6 Pose CFrames, lints it, renders preview images, and exports a KeyframeSequence (.rbxmx) plus a Studio Command Bar script that drops it straight into the Animation Editor. Use this whenever the user wants any Roblox R6 animation made, improved, reviewed, mirrored, or converted, mentions R6, KeyframeSequence, Moon Animator, the Animation Editor, battlegrounds/combat animations, or "animate my Roblox character", even if they don't say "R6" but the game uses the classic blocky avatar. Not for R15, and not for procedural (code-driven Motor6D) animation.
---

# R6 animation

You make real keyframed animations for Roblox's R6 rig. You don't pose by guessing raw
CFrames: R6 joint frames are rotated 90° (on the Torso, "up" is +Z), so hand-written
CFrames are almost always wrong. Instead you write a **JSON spec in body terms**
(`"RightArm": {"forward": 90}` = arm pointing straight ahead), and `scripts/r6anim.py`
does the math, checks the result, draws it so you can *see* it, and exports Studio files.

## Workflow

1. **Pin down the brief** (ask only if it changes the animation): what action, one-shot
   or loop, how long, what it's for (player attack, NPC, emote, default-animation
   replacement), the game's WalkSpeed for locomotion, art direction (snappy anime/
   battlegrounds, realistic, cartoony). Otherwise pick sensible defaults and say so.
2. **Read `references/spec-format.md`** (the channel table and helpers) before writing a
   spec — every time, it's short. Then skim the reference for the job:
   - locomotion (walk/run/jump/fall/land) → `references/locomotion.md`
   - combat, idles, emotes, deaths, any "make it look good" → `references/craft.md`
   - delivering to Studio, playing in game, priorities, Animate replacement → `references/studio-and-runtime.md`
   - why a pose looks odd / raw CFrame work / rig debugging → `references/rig.md`
   - editing `.rbxmx`, easing that differs in game, other tools → `references/formats.md`
   - need the sources, confidence levels or a deeper explanation of anything above →
     `references/research-report.md` (the full sourced research; long, search it with grep)
3. **Start from a recipe** in `recipes/` when one is close (list below) — copy it next to
   your output and modify. They are lint-clean and visually checked; reusing their
   proportions beats starting from zero.
4. **Write the spec** (`<name>.json`). Block the extremes first, then breakdowns, overlap
   and easing (see craft.md).
5. **Build**: `python scripts/r6anim.py build <name>.json -o <outdir>`
   (paths relative to this skill's directory). Fix every ERROR. Read each WARN and fix
   it unless it is a deliberate choice you can justify.
6. **Look at the pictures** — `<Name>_sheet.png` (front/side/three-quarter per keyframe)
   and `<Name>_onion.png` (ghosts + hand/foot trails; dots every 1/30 s: bunched = slow,
   spread = fast). Ask: does each key pose read? Facing right way (eyes mark the face,
   right limbs are drawn darker)? Arcs smooth? Contrast in spacing? Feet on the floor?
   Iterate until it looks like what was asked for. This is where quality comes from —
   don't skip it, and use `render --every 0.033` for a denser sheet when timing matters.
7. **Deliver** (see below).

If an existing animation is provided, `python scripts/r6anim.py import file.rbxmx -o spec.json`
converts it into a spec you can lint, render, critique and edit. `mirror` makes the
left/right version of any spec.

## Spec in 30 seconds

```json
{"name": "Jab_L", "priority": "Action", "fps": 60, "ground": true,
 "keyframes": [
   {"f": 0, "plant": true, "ease": "out", "Torso": {"twist": 25}, "LeftArm": {"forward": 80}},
   {"f": 6, "plant": true, "ease": "linear", "Torso": {"twist": 8, "lean": 11}, "LeftArm": {"forward": 92, "out": -14}},
   {"f": 21, "from": 0}],
 "markers": [{"f": 6, "name": "Hit"}]}
```

- Joints: `Torso` (lean fwd+, twist right+, tilt right+, up/forward/right in **studs** —
  moves the *whole* body), `Head` (nod down+, turn right+, tilt right+), `RightArm`/`LeftArm`
  and `RightLeg`/`LeftLeg` (forward+, out = away from body+, twist = outward+; same meaning
  on both sides). Degrees. 0 = default standing pose.
- Only listed joints are keyed at a keyframe; a keyed joint's missing channels are 0.
- `ease` shapes the segment *to the next key*: `inout` (default), `out` (decelerate into
  next), `in` (accelerate into next), `linear`, `constant` (hold then snap), `elastic.out`,
  `bounce.out`. TweenService meanings; the exporter handles Roblox's quirks.
- Helpers: `from` (start from a key/pose and override), `hold`, `poses` library,
  `plant` (torso rotates around the hips, feet stay), `ground` (auto-drop body so a foot
  touches the floor), `airborne`, `derive` (other leg = this leg half a cycle later),
  `markers`, `speed` (foot-slide check).

## Rules that matter (and why)

- **Never hand-write Pose CFrames.** R6 frames are rotated; the converter is verified
  against the real rig. If you must write Luau that touches Poses, generate the numbers
  with `r6anim.py pose` or the exporter.
- **Torso moves the whole body.** There's no waist; leaning or twisting the Torso swings
  the legs. Put `"plant": true` on grounded keys that rotate the Torso, and `"ground": true`
  on the spec so feet stay on the floor. Crouch = splay legs + ground (R6 has no knees).
- **Raise arms overhead with `forward` (160–180), not `out`.** The shoulder pivots at the
  arm's inner edge, so a sideways overhead raise swings into the head. Keep inward `out`
  ≥ −15° (more sinks the upper arm into the torso) and let torso twist carry "across".
- **Loops**: last keyframe `{"t": END, "from": 0}`; continuous motion crosses the seam
  with linear easing; extremes on the seam use `inout`.
- **Locomotion must match speed**: set `"speed"` to the game's WalkSpeed and make the lint
  say the feet stay planted. Default WalkSpeed 16 is a *run* for R6; Roblox's R6 Animate
  does not speed-scale custom walks.
- **No root motion**: animations can't move the HumanoidRootPart. Dashes/lunges need the
  script to move the character (put `DashStart`/`DashEnd` markers in for it).
- **Priority**: idle → Idle, locomotion → Movement, attacks/emotes/tool holds → Action,
  hit reacts → Action2, deaths → Action4. Core blends half-strength with the default Animate.
- **Markers, not timers**: put a `Hit` marker on the contact frame; damage, SFX, VFX,
  hit-stop and camera shake hang off it.
- **Style**: exaggerate, snap strikes, effortful recoveries, offset timing (no twinning),
  moving holds, torso and head always alive. Details in craft.md.

## Recipes

| File | What | Notes |
|---|---|---|
| `idle.json` | breathing idle, 3.2 s loop | Idle priority, overlap on arms/head |
| `walk.json` | brisk walk, 0.6 s loop | matched to WalkSpeed 8; `derive` legs |
| `run.json` | run with flight phase, 0.5 s loop | matched to WalkSpeed 16 (default) |
| `jump.json`, `fall.json`, `land.json` | jump (0.3 s), fall loop, landing squash | for Animate's jump/fall + a Landed handler |
| `m1_1_jab.json` … `m1_4_uppercut.json` | 4-hit battlegrounds M1 string | shared guard pose, `Hit` markers, finisher `knockback` |
| `sword_slash.json` | one-handed tool slash | starts/ends in tool-hold pose |
| `block.json` | held high guard loop | play/stop with ~0.08 s fades |
| `hit_react.json` | front hit reaction | Action2, play with fadeTime 0 |
| `death.json` | fall backward and stay down | Action4, `Freeze` marker |
| `dash.json` | forward dash | `DashStart`/`DashEnd` markers for the script |
| `wave.json`, `dance_groove.json` | wave emote, 120 BPM groove | beat-aligned keys |

## Delivering

Give the user:
1. The files: `<Name>.rbxmx`, `<Name>.luau`, and the preview `<Name>_sheet.png` /
   `<Name>.gif` so they can see it before opening Studio. Keep the spec JSON too — it's
   the editable source.
2. How to get it in (short version): select the R6 rig in Studio → paste `<Name>.luau` into
   the Command Bar → Animation Editor → ⋯ → Load → `<Name>` → Publish to Roblox (as the
   group if the game is group-owned) → copy the id. Or Insert from File with the `.rbxmx`.
3. The few lines of Luau to play it (from studio-and-runtime.md), with the right priority,
   marker hookups, and anything the animation relies on (script-driven dash movement,
   `AdjustSpeed` for walks, Animate replacement, Landed handler, freeze-on-death).
4. One line on what you checked (lint clean, feet planted at N studs/s, etc.) and any
   honest caveat (e.g. the R6 shoulder overlap that every R6 animation has).

## Requirements

Python 3 for everything; Pillow for previews (`pip install pillow`, or `--no-render`).
`tests/` (run `python tests/test_core.py` and `python tests/test_export.py`) verify the
rig math and that the generated Luau builds the same KeyframeSequence as the .rbxmx.
