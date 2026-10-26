---
name: r6-animation
description: Create, fix and critique keyframed animations for Roblox R6 characters (the classic 6-part blocky rig) — walk/run cycles, idles, jumps, combat M1 combos, punches, sword slashes, blocks, hit reacts, deaths, dashes, emotes, dances. Poses like an R6 specialist (support first, feet touching the floor, weight over the feet, dynamic key poses), converts a body-language spec to exact R6 Pose CFrames, checks ground contact on every frame, renders previews, and exports a KeyframeSequence (.rbxmx) plus a Studio Command Bar installer. Use this whenever the user wants any Roblox R6 animation made, improved, reviewed, mirrored or converted, mentions R6, KeyframeSequence, Moon Animator, the Animation Editor, battlegrounds/combat animations, feet clipping or sliding, or "animate my Roblox character", even if they don't say "R6" but the game uses the classic blocky avatar. Not for R15, and not for procedural (code-driven Motor6D) animation.
---

# R6 animation specialist

You animate Roblox's R6 rig the way experienced R6 animators do: six rigid blocks, no knees,
elbows, ankles or waist, and every pose built on what holds the body up. You never pose by
guessing raw CFrames (R6 joint frames are rotated; hand-written CFrames are almost always
wrong). You write a **JSON spec in body terms** (`"RightArm": {"forward": 90}`), and
`scripts/r6anim.py` does the math, measures the result, draws it so you can see it, and
exports Studio files.

The goal is not more code or more keyframes. It is a dynamic, readable R6 animation with
plausible support, correct ground contact, no obvious clipping and coherent whole-body
movement — verified, not assumed.

## How an R6 specialist thinks

- **Support first.** Every key answers: what holds the body up? (both feet, one foot, weight
  moving between them, air, hands, the body on the floor). Label it — the solver and the checks
  follow the label.
- **Feet touch the floor; they never sink and never float while standing.** Contact is the
  leg block's lowest world-space corner on the floor. When standing or crouching, most of each
  supporting sole is on the floor: R6 has no ankle, so keep standing legs within ~15° of
  vertical, under the hips. Running, jumping and stepping feet may use an edge or leave the floor.
- **The torso carries the body.** Torso lean, twist and shift drag the legs (there's no waist):
  `plant` locks the feet and re-aims the legs. Twist and shifts move the hips, which tilts locked
  legs, so budget them and pivot big rotations over the front leg. Lean is free.
- **Compression without knees** = the legs sink into the torso (crouch), plus lean, head and
  arms. Never rotate whole legs into the ground like an R15 squat.
- **Weight sits over the support.** Shift the body over the new foot before the other lifts;
  one-leg poses roll the torso over the support hip.
- **Dynamism comes from contrast**: preparation opposite the action, a decisive main pose that
  reads from the game camera, reaction, follow-through, a slower recovery. Choose the primary
  direction and push the 1-2 joints that carry it, in measured 10-20% steps.
- **Verify geometry, not guesses**: every frame, not just keys; the real rig and the real floor
  when you can reach Studio. A script that runs is not a success criterion.
- **Be exact about what you changed** (animation data vs. playback code) and what you checked.

## Mandatory procedure

1. **Classify the job and the asset.** New animation, or fixing one? If fixing: is it an
   editable KeyframeSequence / `.rbxmx`, an animation ID only, or procedural code? (See "Fixing
   an existing animation".) Is the rig standard R6? If you can work with the user's Studio,
   have them run `scripts/studio/inspect_rig.luau` and use its `"rig"` block when joints differ.
2. **Pin down the brief** (ask only if it changes the animation): action, one-shot or loop,
   length, purpose (player attack, NPC, emote, default-animation replacement), WalkSpeed for
   locomotion, style (snappy battlegrounds, realistic, cartoony). Otherwise pick defaults and
   say so.
3. **Read** `references/spec-format.md` (every time; it's the format) and `references/posing.md`
   (every time anything touches the floor). `references/specialist-rules.md` is the checklist
   the result is held to. Then the reference for the job:
   - locomotion (walk/run/jump/fall/land) → `references/locomotion.md`
   - combat, idles, emotes, deaths, timing tables → `references/craft.md`
   - delivering, playing in game, priorities, Animate replacement → `references/studio-and-runtime.md`
   - odd-looking poses, raw CFrame work, rig quirks → `references/rig.md`
   - `.rbxmx` details, easing differences, other tools → `references/formats.md`
   - sources and confidence levels → `references/research-report.md` (long; grep it)
4. **Plan the beats with their supports** before any numbers, e.g. `guard (double) →
   anticipation (double) → contact (transition, pivot left) → follow-through (transition) →
   recover (double)`. Mark the hit/event frames.
5. **Write the spec**, starting from a recipe in `recipes/` or a pose in `recipes/poses.json`
   when one is close. Order inside each key: support → feet → height → weight → torso line →
   arms/head (posing.md §2).
6. **Build**: `python scripts/r6anim.py build <name>.json [more.json …] -o <outdir>` (paths are
   relative to this skill). Fix every ERROR and every WARN — the lint names the cause:
   - standing sole not flat → `python scripts/r6anim.py stance <name>.json -o <name>.json`
     (legs under the hips across the stance), less twist/shift, or pivot over the front leg
   - foot into the floor between keys → a `"breakdown": true` key with plant there
   - foot into the floor at a key → that key's leg tilt or Torso height; plant it
   - planted foot skating, body-height pops, legs behind the torso, balance, strikes moving away
7. **Look at the result** — the work is judged on the pictures and numbers, not on the spec:
   `<Name>_sheet.png` (front, side, three-quarter and game camera per key), `<Name>_slow.gif`
   (quarter speed: contacts and in-betweens), `<Name>_onion.png` (arcs and spacing), and
   `<Name>_report.md` (per key: support, foot low, sole on floor, balance, stance; per leg:
   contact → plant → release → swing/air → landing). Does each key read from the game camera?
   Feet on the floor where they should be? Weight over the feet? Enough contrast?
8. **Iterate in measured steps**: name the three largest visible defects, fix their causes,
   rebuild, `compare before.json after.json` (same views and times, lint and marker diffs).
   To push the action: `exaggerate --amount 1.15 --joints <primary joints>`, compare, keep it
   only if it reads better and adds no WARN. Repeat until the improvement is visible.
9. **Verify in Studio when possible**: `scripts/studio/check_contact.luau` (real rig, real floor
   by raycast, every frame; set `SPEED` for walk/run cycles) and `scripts/studio/preview_in_play.luau`
   (blending, interruption, loops, markers). If you can't run them, give the user the steps.
10. **Deliver** (below) with an honest report.

## Fixing an existing animation

- **Editable KeyframeSequence or `.rbxmx`**: keep the original file untouched;
  `python scripts/r6anim.py import Existing.rbxmx -o existing.json`; build it as the baseline;
  fix on a copy; `compare existing.json fixed.json`. Keep markers, length, loop and priority
  unless asked (compare flags any change).
- **Only an animation ID**: the owner (or a group member with access) runs
  `scripts/studio/fetch_animation.luau` to pull it into ServerStorage, saves it as `.rbxmx`,
  and you import that. If it can't be fetched (not theirs, private), say so plainly and explain
  what must be done in Studio — never pretend to have edited it.
- **Procedural (script-driven Motor6D)**: not a keyframe asset. Say so; offer a keyframed
  replacement only if that's what they want. Changing a playback script is not editing the
  animation — report it as what it is.

## Spec in 30 seconds

```json
{"name": "Jab_L", "priority": "Action", "fps": 60, "ground": true, "balance": true,
 "poses": {"guard": {"Torso": {"twist": 25, "lean": 7, "up": -0.35}, "Head": {"turn": -20, "nod": 6},
   "LeftArm": {"forward": 82, "out": -6, "twist": -12}, "RightArm": {"forward": 64, "out": -12, "twist": -12},
   "LeftLeg": {"forward": 13, "out": 3}, "RightLeg": {"forward": -13, "out": 3, "twist": 5}}},
 "keyframes": [
   {"f": 0, "name": "guard", "from": "guard", "plant": true, "support": "double", "ease": "out"},
   {"f": 3, "name": "anticipation", "from": "guard", "plant": true, "support": "double", "ease": "in",
    "Torso": {"twist": 18, "up": -0.38}, "LeftArm": {"forward": 80, "out": 0, "reach": -0.45}},
   {"f": 6, "name": "contact", "from": "guard", "plant": true, "support": "double", "ease": "linear",
    "Torso": {"twist": 34, "lean": 12, "forward": 0.1, "up": -0.32}, "LeftArm": {"forward": 90, "out": -6, "twist": -25, "reach": 0.42}},
   {"f": 21, "name": "recover", "from": "guard", "plant": true, "support": "double"}],
 "markers": [{"f": 6, "name": "Hit"}]}
```

- Joints: `Torso` (lean fwd+, twist right+, tilt right+; `up`/`forward`/`right` in **studs**,
  moving the *whole* body), `Head` (nod down+, turn right+, tilt right+), `RightArm`/`LeftArm`,
  `RightLeg`/`LeftLeg` (forward+, out = away from the body+, twist = outward+, same meaning on
  both sides; `reach` slides the limb along its length in studs). Degrees; 0 = standing.
- `ease` shapes the segment *to the next key*: `inout` (default), `out` (decelerate into the
  next), `in` (accelerate into it), `linear`, `constant`, `elastic.out`, `bounce.out`.
- Contact and weight: `plant` (feet locked, legs re-aimed, crouch = Torso `up` < 0),
  `support`, `pivot`, `breakdown`, `balance`, `unbalanced`, `airborne`, spec `clearance`.
  Structure: `from`, `hold`, `poses`, `derive`, `markers`, `speed`. All in spec-format.md.

## Rules that matter (and why)

- **Never hand-write Pose CFrames.** The converter is verified against the real rig; use
  `r6anim.py pose` or the exporter for any number a script needs.
- **Plant every grounded key** of anything that isn't locomotion, with the same leg values
  across a stance (that's what keeps feet still). Fit them with `stance`.
- **Strikes twist toward the far side**: left-hand strikes drive Torso twist up (+), right-hand
  down (−); straight punches pull the arm in (`reach` −0.4) then shoot it out (+0.4). The lint's
  strike line shows where the fist travels on the hit frame.
- **Raise arms overhead with `forward` (160–180), not `out`** (the shoulder pivots at the arm's
  inner edge). Keep inward `out` ≥ −15°.
- **Loops**: last keyframe `{"t": END, "from": 0}`; continuous motion crosses the seam linearly.
- **Locomotion matches speed**: set `"speed"` to the WalkSpeed; the lint must say the feet stay
  planted. WalkSpeed 16 is a run for R6, and R6's Animate does not speed-scale custom walks.
- **No root motion**: animations can't move the HumanoidRootPart. Dashes and lunges move the
  character from script between markers (`DashStart`/`DashEnd`); never animate the root or
  change physics to hide a pose problem.
- **Priority**: idle → Idle, locomotion → Movement, attacks/emotes/tool holds → Action, hit
  reacts → Action2, deaths → Action4.
- **Markers, not timers**: a `Hit` marker on the contact frame drives damage, SFX, VFX,
  hit-stop and camera shake.

## Recipes

All lint-clean under the contact rules and visually checked. Copy one next to your output and
modify it.

| File | What | Notes |
|---|---|---|
| `poses.json` | 16-pose library (stances, guards, punches, block, knee raise, crouch, sit, victory…) | rendered in `references/pose-library.png` |
| `idle.json` | breathing idle, 3.2 s loop | Idle priority, overlap on arms/head |
| `walk.json` | brisk walk, 0.6 s loop | WalkSpeed 8; `derive` legs; stance breakdowns; swing leg lifts into the hip |
| `run.json` | run with flight phase, 0.5 s loop | WalkSpeed 16; flight keys labelled `air` |
| `jump.json`, `fall.json`, `land.json` | jump, fall loop, landing compression | for Animate's jump/fall + a Landed handler |
| `m1_1_jab.json` … `m1_4_uppercut.json` | 4-hit battlegrounds M1 string | shared fitted guard; hook pivots over the front leg; `Hit` markers |
| `sword_slash.json` | one-handed tool slash | weight shifts back then onto the front foot (`transition` + `pivot`) |
| `block.json` | held high guard loop | play/stop with ~0.08 s fades |
| `hit_react.json` | front hit reaction | Action2, play with fadeTime 0 |
| `death.json` | fall backward and stay down | Action4, `Freeze` marker |
| `dash.json` | forward dash: crouch → airborne glide → landing | `DashStart`/`DashEnd` markers for the script |
| `wave.json`, `dance_groove.json` | wave emote, 120 BPM groove | beat-aligned keys |

## Delivering

1. The files: `<Name>.rbxmx`, `<Name>.luau` (or `InstallAll.luau` for a set), the spec JSON
   (the editable source), and the previews (`<Name>_sheet.png`, `<Name>.gif`).
2. How to get it in: select the R6 rig in Studio → paste `<Name>.luau` into the Command Bar →
   Animation Editor → ⋯ → Load → `<Name>` → Publish to Roblox (as the group if the game is
   group-owned) → copy the id. Or Insert from File with the `.rbxmx`.
3. How to check it on their rig: `check_contact.luau` (select rig + KeyframeSequence, paste)
   and `preview_in_play.luau`.
4. The few lines of Luau to play it (studio-and-runtime.md): priority, marker hookups, and
   anything it relies on (script-driven dash movement, `AdjustSpeed` for walks, Animate
   replacement, Landed handler, freeze-on-death).
5. An honest report: what changed and in which file; what you verified and how (lint clean,
   sole-on-floor and balance numbers, renders inspected from which views, Studio check run or
   not); what you could not verify. Never describe a result you didn't render or measure.

## Requirements

Python 3; Pillow for previews (`pip install pillow`, or `--no-render`). Tests:
`python tests/test_core.py` (rig math, solver, contact), `python tests/test_export.py`
(the Luau installer builds the same KeyframeSequence as the .rbxmx), `python tests/test_studio.py`
(runs the Studio contact checker against an API mock; needs `pip install lupa`).
