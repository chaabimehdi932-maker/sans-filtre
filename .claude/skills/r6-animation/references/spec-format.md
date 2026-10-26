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
| `grounded` | `true` | Lint expects feet on the floor between non-airborne keys. Set `false` for swimming/flying. |
| `poses` | `{}` | Named pose library, referenced by `"from"`. |
| `derive` | `[]` | Copy one joint's keys onto another with a time shift (cycles). |
| `markers` | `[]` | `{"t" or "f", "name", "value"}` KeyframeMarkers → `GetMarkerReachedSignal(name)`. |
| `note` | | Free text, ignored. |

## Keyframes

```json
{"f": 6, "name": "contact", "ease": "out", "plant": true,
 "Torso": {"twist": 8, "lean": 11, "forward": 0.15},
 "LeftArm": {"forward": 92, "out": -14, "twist": -20}}
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
| `RightArm` / `LeftArm` | R/L Shoulder | `forward` | arm swings **forward/up** (90 = pointing ahead, 180 = straight up) | -100..200 |
| | | `out` | arm raises **sideways away** from the body (90 = T-pose) | -40..180 |
| | | `twist` | arm rolls **outward** about its own length | -120..120 |
| `RightLeg` / `LeftLeg` | R/L Hip | `forward` | leg swings **forward** (kick) | -70..130 |
| | | `out` | leg spreads **sideways away** | -25..90 |
| | | `twist` | toes turn **outward** | -60..60 |

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
- **`"plant": true`** on a keyframe: Torso rotations pivot at the **hips** and the legs keep
  their world angles, so leaning/twisting the torso doesn't swing the feet. Leg channels
  in that key are then world-relative (as if the torso were upright). Use it on almost
  every grounded key that rotates the Torso.
- **`"ground": true`** on a keyframe (or the whole spec): after everything else, slide the
  body up/down so the lowest point of either leg touches the floor. This is how you get
  R6 "squash": splay the legs (`forward`/`out`) and ground drops the body for you.
  Rigid legs swung by A° lift the foot 2·(1−cos A) studs — ground does that math.
- **`"airborne": true`**: this key is in the air (jumps, flight phase of a run, bounces);
  ground snapping and the floor lint skip it. `from` copies it.
- **`"derive"`** (cycles): `{"joint": "LeftLeg", "from": "RightLeg", "phase": 0.5}` copies
  the right leg's keys onto the left leg half a loop later — a perfect, mirror-symmetric
  gait from one leg's keys. Also `"shift"` (seconds) or `"shiftFrames"`. For Torso/Head
  add `"mirror": true` to negate twist/tilt/turn/right. The derived joint must not be keyed
  directly.
- **`markers`**: `[{"f": 7, "name": "Hit", "value": "heavy"}]`. Markers at a time with no
  keyframe get an empty keyframe of their own. Scripts use
  `track:GetMarkerReachedSignal("Hit"):Connect(function(value) ... end)`.

## Worked example (jab)

```json
{
  "name": "Jab_L", "priority": "Action", "fps": 60, "ground": true,
  "poses": {"guard": {"Torso": {"twist": 25, "lean": 6}, "Head": {"turn": -20, "nod": 4},
            "LeftArm": {"forward": 80, "out": -8, "twist": -10}, "RightArm": {"forward": 62, "out": -14, "twist": -10},
            "LeftLeg": {"forward": 18, "out": 4}, "RightLeg": {"forward": -14, "out": 6}}},
  "keyframes": [
    {"f": 0,  "name": "guard", "from": "guard", "plant": true, "ease": "out"},
    {"f": 3,  "name": "anticipation", "from": "guard", "plant": true, "ease": "in",
     "Torso": {"twist": 32, "lean": 4}, "LeftArm": {"forward": 68, "out": 6}},
    {"f": 6,  "name": "contact", "from": "guard", "plant": true, "ease": "linear",
     "Torso": {"twist": 8, "lean": 11, "forward": 0.15}, "LeftArm": {"forward": 92, "out": -14, "twist": -20}},
    {"f": 10, "name": "hold", "from": "contact", "LeftArm": {"forward": 90, "out": -13, "twist": -20}},
    {"f": 21, "name": "recover", "from": "guard", "plant": true}
  ],
  "markers": [{"f": 6, "name": "Hit"}]
}
```

## CLI

```bash
python scripts/r6anim.py build spec.json -o out/     # lint + previews + .rbxmx + .luau (use this)
python scripts/r6anim.py lint spec.json              # findings only
python scripts/r6anim.py render spec.json --every 0.05 --views side,front   # denser contact sheet
python scripts/r6anim.py mirror punch_R.json -o punch_L.json
python scripts/r6anim.py import Existing.rbxmx -o existing.json             # edit/critique an existing anim
python scripts/r6anim.py pose '{"RightArm":{"forward":90,"out":20}}' -o pose.png   # sanity-check one pose
```

Outputs of `build` (named after `name`): `<Name>.rbxmx`, `<Name>.luau`, `<Name>_sheet.png`
(rows = front/side/three-quarter, columns = keyframes), `<Name>_onion.png` (key-pose ghosts +
hand/foot trails, one dot per 1/30 s), `<Name>.gif`. Rendering needs Pillow
(`pip install pillow`); `--no-render` skips it.
