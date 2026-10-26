# Animation spec format (JSON)

Everything in this skill starts from one JSON spec. `scripts/r6anim.py` turns it into a
lint report, preview images, a `.rbxmx` KeyframeSequence and a Command Bar `.luau` script.
You never write raw Pose CFrames: you write body-language angles and the converter
produces the exact `Pose.CFrame` (= `Motor6D.Transform`) for R6's rotated joint frames.

## Contents
- Top-level fields
- Keyframes
- Joints and channels (the table you'll use most)
- Easing
- Helpers: `from`, `hold`, `poses`, `plant`, `ground`, `airborne`, `derive`, markers
- Contact and weight: `support`, `pivot`, `breakdown`, `balance`, `unbalanced`, `clearance`
- Worked example
- CLI

## Top-level fields

| Field | Default | Meaning |
|---|---|---|
| `name` | `"Animation"` | KeyframeSequence name (also output file name). Suffix `_R`/`_L` lets `mirror` rename it. |
| `loop` | `false` | Looped animation. The last keyframe must equal the first (use `"from": 0`). |
| `priority` | `"Action"` | `Core`, `Idle`, `Movement`, `Action`, `Action2`, `Action3`, `Action4`. |
| `fps` | `60` | Only used to convert `"f"` (frame) times to seconds. |
| `ease` | `"inout"` | Default easing for every keyframe that doesn't set one. |
| `speed` | none | Locomotion speed in studs/s the cycle must match. Enables the foot-sliding check. |
| `ground` | `false` | Snap every non-airborne keyframe so the lowest foot touches the floor (see below). |
| `balance` | `false` | Every planted key nudges the hips until the centre of mass is ≥ 0.15 studs inside the feet. |
| `clearance` | `0.2` | Studs a free (non-supporting) leg's lowest corner stays above the floor on planted keys. 0.3 for walks. |
| `rig` | default R6 | Joint overrides from `studio/inspect_rig.luau` when the user's rig has non-default C0/C1. |
| `grounded` | `true` | Lint expects feet on the floor between non-airborne keys. Set `false` for swimming/flying. |
| `poses` | `{}` | Named pose library, referenced by `"from"`. |
| `derive` | `[]` | Copy one joint's keys onto another with a time shift (cycles). |
| `markers` | `[]` | `{"t" or "f", "name", "value"}` KeyframeMarkers → `GetMarkerReachedSignal(name)`. |
| `note` | | Free text, ignored. |

## Keyframes

```json
{"f": 6, "name": "contact", "ease": "linear", "plant": true,
 "Torso": {"twist": 32, "lean": 10, "forward": 0.2},
 "LeftArm": {"forward": 90, "out": -6, "twist": -25, "reach": 0.2}}
```

- Time: `"t"` in seconds or `"f"` in frames at the spec's `fps`. First keyframe must be at 0.
  The animation length is the last keyframe's time.
- Only the joints you list are **keyed** at that time. Unlisted joints keep interpolating
  between their own keys (that is how overlap/offset timing works), exactly like Roblox.
- A keyed joint is a **full** pose for that joint: channels you omit are 0 (rest), not
  carried over. Use `"from"` to start from another pose and override a few channels.
- `"name"` labels the keyframe (shows in previews, becomes the Keyframe name). The exporter
  always names the **last** keyframe `End` (the default Animate script listens for it).

## Joints and channels

Character space: the rig faces forward; "right" means the character's right.
All angles in **degrees**, Torso translations in **studs**. 0 everywhere = the default
standing R6 pose. Left and right limbs use the **same** sign meaning (mirror-symmetric),
so `"out": 30` spreads either arm away from the body.

| Joint key | Motor6D | Channel | Positive value means | Typical range |
|---|---|---|---|---|
| `Torso` | RootJoint | `lean` | top of body tips **forward** (bow) | -95..95 (±90 = lying) |
| | | `twist` | chest turns to the character's **right** | -90..90 |
| | | `tilt` | top of body tips to the character's **right** | -60..60 |
| | | `up` | whole body **up** (studs) | -2.6..4 |
| | | `forward` | whole body **forward** (studs) | -3.5..3.5 |
| | | `right` | whole body to the **right** (studs) | -3.5..3.5 |
| `Head` | Neck | `nod` | look **down** | -60..70 |
| | | `turn` | look to the character's **right** | -85..85 |
| | | `tilt` | ear toward the **right** shoulder | -45..45 |
| | | `offset_right/up/forward` | head slides (studs; rare: bobs, stretch) | -1..1 |
| `RightArm` / `LeftArm` | R/L Shoulder | `forward` | arm swings **forward/up** (90 = pointing ahead, 180 = straight up) | -100..200 |
| | | `out` | arm raises **sideways away** from the body (90 = T-pose) | -40..180 |
| | | `twist` | arm rolls **outward** about its own length | -120..120 |
| `RightLeg` / `LeftLeg` | R/L Hip | `forward` | leg swings **forward** (kick) | -70..130 |
| | | `out` | leg spreads **sideways away** | -25..90 |
| | | `twist` | toes turn **outward** | -60..60 |
| arms & legs | | `reach` | limb slides **along its own length** out of the socket (studs); negative slides it into the body | arm -0.8..0.6, leg -1..0.3 |
| | | `offset_right/up/forward` | limb slides in the torso's axes (studs) | -1..1 |

`reach` is how R6 fakes the joints it doesn't have: a straight punch pulls the arm into the
shoulder (`reach` −0.3) on the wind-up and shoots it out (+0.2) on contact; legs slide up
into the torso (negative `reach`) to fake a knee bend. `plant` sets leg `reach` for you.

Rotation order (matters only when several channels are large at once):
- Limbs: swing `forward` first, then `out` in the swung frame, then `twist` about the limb.
  So `forward 90, out 30` = arm pointing ahead and angled 30° outward, still horizontal.
- Torso/Head: `twist`/`turn` first, then `lean`/`nod`, then `tilt` (yaw-pitch-roll).

Aliases accepted: `Root`/`Body` → Torso; `Right Arm`, `rarm` …; channels `pitch`, `yaw`,
`roll`, `raise`, `swing`, `spread`, `abduct`, `side` map to the obvious canonical names.

**Torso moves the whole body.** R6 has no waist: RootJoint rotates the torso *and*
everything attached to it (head, arms, legs) about the torso centre. Leaning the torso
swings the legs back. Use `plant` (below) when the feet should stay put.

## Easing

`ease` on a keyframe shapes the segment **from that keyframe to the next** (Roblox
semantics: the easing stored on a Pose describes how to reach the next pose).
Names use the TweenService meaning; the exporter maps them to the Roblox enums that
actually play that way at runtime (CubicV2; Constant+Out), so preview = game.

| `ease` | Motion from this key to the next | Use for |
|---|---|---|
| `inout` (default) | slow → fast → slow | most organic moves, extremes, arm swings |
| `out` | fast start, **decelerates into** the next key | strikes arriving, settles, rises |
| `in` | slow start, **accelerates into** the next key | wind-up → impact, falls, things building speed |
| `linear` | constant speed | stance legs, loop seams of continuous motion, mechanical |
| `constant` | **holds** this pose, snaps at the next key | stepped/anime look, pops, impact frames |
| `elastic.out` / `bounce.out` | overshoot-wobble / bounce settling into the next key | cartoony settles, landings (sparingly) |

Per-joint override: put `"ease"` inside the joint: `"RightLeg": {"forward": 37, "ease": "linear"}`.
Avoid `bounce.inout` (Roblox's runtime curve differs from the standard one).

## Helpers

- **`"from": <keyframe name | index | pose name>`** starts this keyframe from that pose
  (all its joints, plus its `plant`/`airborne` flags and per-joint eases), then applies the
  joints you list on top, **channel by channel**. `{"t": END, "from": 0}` closes a loop.
- **`"hold": true`** = `from` the previous keyframe. Combine with small overrides for a
  *moving hold* (drift 2–5% so a held pose stays alive).
- **`"poses": {"guard": {...joints...}}`** at top level: a reusable pose library.
- **`"plant": true`** on a keyframe — **feet locked to the floor**. The leg channels (as if
  the torso were upright) decide where each foot stands; then the Torso rotates about the
  **hips** and shifts by its `right/forward`, and each leg re-aims at its foot and slides
  along its length (`reach`) to reach it. On plant keys Torso `up` is **relative to the
  natural standing height** for those leg angles, so `"up": -0.4` = crouch 0.4 studs with
  the legs sliding into the torso (the R6 "fake knee"). The body is lowered automatically if
  a tilt would make a leg stretch. Put it on every grounded key of anything that isn't
  locomotion; feet then only move where you change the leg angles (a step). On `airborne`
  keys plant just keeps the legs' world angles.
  Contact = the leg's lowest world-space corner exactly on the floor: feet touch, never sink.
  Joints a planted key doesn't list (Torso, legs) continue their curve; they don't reset.
- **`"ground": true`** on a keyframe (or the whole spec): slide the body up/down so the
  lowest point of either leg touches the floor (plant keys already do this). Use it on
  keys that aren't planted.
- **`"airborne": true`**: this key is in the air (jumps, flight phase of a run, bounces);
  ground snapping and the floor lint skip it. `from` copies it.
- **`"support"`**: what holds the body up at this key — `double`, `left`, `right`,
  `transition` (weight moving between the feet: both touch, only the weight foot must be
  flat), `air`, `hands`, `body` (sitting/lying), `fall` (deliberately off balance). On planted
  keys `left`/`right` lock only that foot; the other leg is free (keeps its angle, lifted clear
  of the floor by `clearance` — pulled into the hip like R6's knee). `air` = `airborne`. The
  lint checks every label against the geometry. `from` copies it.
- **`"pivot": "left" | "right" | "hips"`** (planted keys): where torso rotations pivot. Default:
  the support hip on one-foot keys, the hips' middle otherwise. Use the front hip on strike
  keys with big twist (`"support": "transition", "pivot": "left"`): the weight leg stays
  straight under the body while the other hip swings and its foot pivots.
- **`"breakdown": true`**: an in-between key that starts as the pose the curves already pass
  through at its time (override any channel on it). Its contact flags default to what both
  neighbours share (a foot planted on both sides stays planted), so `plant` re-locks the feet
  where plain interpolation would let them dip or slide. An eased segment it splits keeps its
  feel (inout → in + out) unless you give it an `ease`. Can't be the first key or use `from`.
- **`"balance": true`** (key or spec): nudge the hips over the feet. **`"unbalanced": true`**:
  a deliberate lunge/fall key — exempt from balance and flat-foot checks.
- **`"derive"`** (cycles): `{"joint": "LeftLeg", "from": "RightLeg", "phase": 0.5}` copies
  the right leg's keys onto the left leg half a loop later — a perfect, mirror-symmetric
  gait from one leg's keys. Also `"shift"` (seconds) or `"shiftFrames"`. For Torso/Head
  add `"mirror": true` to negate twist/tilt/turn/right. The derived joint must not be keyed
  directly.
- **`markers`**: `[{"f": 7, "name": "Hit", "value": "heavy"}]`. Markers at a time with no
  keyframe get an empty keyframe of their own. Scripts use
  `track:GetMarkerReachedSignal("Hit"):Connect(function(value) ... end)`.

## Worked example (jab)

(The recipes/m1_1_jab.json version adds `support` labels, a guard fitted with `stance` and
`"balance": true`; this is the minimal shape.)

```json
{
  "name": "Jab_L", "priority": "Action", "fps": 60, "ground": true,
  "poses": {"guard": {"Torso": {"twist": 25, "lean": 7, "up": -0.35}, "Head": {"turn": -20, "nod": 6},
            "LeftArm": {"forward": 82, "out": -6, "twist": -12}, "RightArm": {"forward": 64, "out": -12, "twist": -12},
            "LeftLeg": {"forward": 13, "out": 3}, "RightLeg": {"forward": -13, "out": 3, "twist": 5}}},
  "keyframes": [
    {"f": 0,  "name": "guard", "from": "guard", "plant": true, "ease": "out"},
    {"f": 3,  "name": "anticipation", "from": "guard", "plant": true, "ease": "in",
     "Torso": {"twist": 18, "lean": 5, "up": -0.38}, "LeftArm": {"forward": 80, "out": 0, "reach": -0.45}},
    {"f": 6,  "name": "contact", "from": "guard", "plant": true, "ease": "linear",
     "Torso": {"twist": 34, "lean": 12, "forward": 0.1, "up": -0.32}, "LeftArm": {"forward": 90, "out": -6, "twist": -25, "reach": 0.42}},
    {"f": 10, "name": "hold", "from": "contact", "LeftArm": {"forward": 89, "out": -6, "twist": -25, "reach": 0.44}},
    {"f": 21, "name": "recover", "from": "guard", "plant": true}
  ],
  "markers": [{"f": 6, "name": "Hit"}]
}
```

## CLI

```bash
python scripts/r6anim.py build spec.json -o out/     # lint + previews + .rbxmx + .luau (use this)
python scripts/r6anim.py build a.json b.json c.json -o out/   # a set: also InstallAll.luau (one paste)
python scripts/r6anim.py lint spec.json              # findings only
python scripts/r6anim.py report spec.json            # per-key support / foot low / sole on floor / balance + contact phases
python scripts/r6anim.py stance spec.json -o fixed.json   # stand planted legs under the hips across each stance
python scripts/r6anim.py exaggerate spec.json --amount 1.15 --joints Torso,LeftArm -o v2.json
python scripts/r6anim.py compare spec.json v2.json -o out/   # same views/times side by side + what changed
python scripts/r6anim.py render spec.json --every 0.05 --views side,front   # denser contact sheet
python scripts/r6anim.py mirror punch_R.json -o punch_L.json
python scripts/r6anim.py import Existing.rbxmx -o existing.json             # edit/critique an existing anim
python scripts/r6anim.py pose '{"RightArm":{"forward":90,"out":20}}' -o pose.png   # sanity-check one pose
```

Outputs of `build` (named after `name`): `<Name>.rbxmx`, `<Name>.luau`, `<Name>_sheet.png`
(rows = front/side/three-quarter/game camera, columns = keyframes), `<Name>_onion.png` (key-pose
ghosts + hand/foot trails, one dot per 1/30 s), `<Name>.gif`, `<Name>_slow.gif` (quarter speed,
every frame) and `<Name>_report.md` (lint + per-key table + contact phases). Nothing under the
floor is hidden in the renders. Rendering needs Pillow
(`pip install pillow`); `--no-render` skips it.
