# Posing R6: support first, then the body

How R6 animators build a pose that stands, reads and moves well with only six rigid parts.
Read this before posing anything that touches the floor. Every number here is measured with
the skill's own geometry (`scripts/r6pose.py`), not guessed.

Contents: 1 the body in studs · 2 the posing order · 3 ground contact · 4 why planted legs
tilt · 5 contact phases · 6 weight transfer · 7 compression without knees · 8 dynamic
actions · 9 composition tricks · 10 the pose library

## 1. The body you are posing, in studs

| Part | Size | Pivot | What it means for posing |
|---|---|---|---|
| Torso | 2 × 2 × 1 | RootJoint at its centre | moves the WHOLE body (legs hang off it); no waist |
| Head | mesh ~1.2 cube | neck, top of torso | lead or follow the action by 2-4 frames |
| Arm | 1 × 2 × 1 | shoulder: inner edge, 0.5 below the arm's top | raise overhead with `forward`; a raised arm only reaches head-top height |
| Leg | 1 × 2 × 1 | hip: the leg's top OUTER corner | rigid: no knee, no ankle; a tilted leg tilts its sole |

- Standing: torso centre 3 studs above the floor (HumanoidRootPart centre, hip pivots at 2).
- Leg length 2; feet 1 × 1. At rest the two feet are 1 stud apart (centre to centre).
- Crouch depth = how far the legs sink into the torso: guard −0.3..−0.45, combat crouch −0.6..−0.8,
  deep crouch −0.95..−1.0. Past ~−1.2 the legs vanish into the torso.
- Body bob of a walk/run stride with both feet planted at ±A: 10-20° → the body RISES 0.05
  (the sole's corner swings lower first), 30° → 0, 37° → −0.10, 45° → −0.23. The plant solver
  does this; you never key it by hand.
- Torso twist moves each hip pivot: 10° → 0.17 studs, 20° → 0.35, 25° → 0.43, 30° → 0.52, 40° → 0.68.

## 2. The posing order (do it in this order, every key)

1. **Support.** What holds the body up at this key? `double`, `left`, `right`, `transition`
   (weight moving from one foot to the other), `air`, `hands`, `body` (sitting/lying), `fall`
   (deliberately off balance). Write it on the key: `"support": "right"`. It drives the solver
   (which feet are locked, which leg is free) and the checks.
2. **Feet.** Place the planted feet: leg channels on planted keys (`"plant": true`), the SAME
   values on every key of one stance (that is what keeps the foot still). Standing/crouching:
   each leg within ~15° of vertical (|forward| + |out| ≤ 15, twist ≤ 10). No foot trailing
   behind the torso. Run `python scripts/r6anim.py stance spec.json` to get leg values that
   stand under the hips across the whole stance.
3. **Height.** Torso `up` (negative = crouch). With `plant`, the legs slide into the torso:
   R6's knee. Never lower the body by splaying or tilting the legs.
4. **Weight.** The centre of mass must sit inside the feet (`"balance": true` nudges the hips
   until it does; the report prints the margin). One leg: see section 6.
5. **Line of action.** Torso lean (free: it pivots at the hips, the feet don't care), twist
   (moves the hips: budget it, section 4), tilt, small shifts. This is where R6 power lives.
6. **Arms and head.** Silhouette first: from the game camera, can you tell the action with
   the colours turned off? Asymmetric arms, the off arm doing something deliberate (down, back,
   guarding), head leading or following.
7. **Check.** `build` → lint (fix every WARN), report table (support, foot low, sole on floor,
   balance), contact sheet from front/side/three-quarter/game camera, slow-motion GIF.
8. **Push.** Exaggerate along the primary direction in 10-20% steps (`exaggerate --joints
   Torso,RightArm --amount 1.15`), `compare` before/after, keep it only if it reads better and
   adds no WARN.

## 3. Ground contact: touch, never sink, mostly flat when standing

- **Touch** = the leg's lowest world-space corner is on the floor (y = 0, within 0.05). The
  solver measures the 8 rotated corners of the leg block, never "centre minus half height".
- **Never sink.** No part of a foot goes under the floor, in any phase, on any frame (the lint
  samples every 1/60 s, not just keys; tolerance 0.1 stud). Renders don't hide anything under
  the floor, so a buried foot is visible in the preview.
- **No floating** while the character stands: if neither foot is within 0.12 of the floor
  outside an `air`/`fall`/`body` phase, that's a bug.
- **Mostly flat when standing or crouching** (one or both feet, not stepping, not lunging off
  balance): at least 50% of each supporting sole within 0.15 studs of the floor. R6 has no
  ankle, so the sole tilts with the leg:

| leg tilt (one direction) | 8° | 10° | 12° | 14° | 16° |
|---|---|---|---|---|---|
| sole on floor | 100% | 82% | 73% | 64% | 55% |
| same with twist 15 | 93% | 74% | 60% | 51% | 44% |

  Tilting both ways at once costs more: forward 12 + out 4 → 55%, forward 10 + out 8 → 47%.
  Twist turns a tilted sole onto its corner, so keep twist ≤ 10 on tilted legs.
- Running, jumping, kicking, stepping and the pivoting back foot of a strike may stand on an
  edge: the flat rule is for standing and crouching only.

## 4. Why planted legs tilt when you didn't touch them

Feet are locked; the hips are not. Every Torso twist, shift (`right`/`forward`) and crouch moves
the hip pivots, and a locked foot then tilts its leg. A 25° guard twist moves each hip 0.43
studs; crouching makes it worse (a shorter visible leg tilts more for the same offset).

- Stand the feet under the hips of the stance, not under the rest pose: `stance` computes it
  (it aims each foot at the middle of where its hip goes across the stance's keys).
- Budget the twist range inside one planted stance at ~40° and the shifts at ~0.1 studs;
  take the extra power from lean (free), arm `reach`, head and timing.
- Big rotations (hook, cross, sword follow-through): the body turns around the FRONT leg. Mark
  those keys `"support": "transition", "pivot": "left"` (or right): the rotation pivots at that
  hip, so the weight leg stays straight and flat while the back hip swings and the back foot
  pivots on its edge. The lint then requires only the weight foot to be flat.
- The lint's sole-contact WARN prints the leg values that put that foot straight under its hip
  for that key (`RightLeg forward ~-12, out ~3`): use them on every key of the stance.

## 5. Contact phases

For every leg: **contact** (touches down) → **plant** (carries weight, doesn't slide) →
**release** (leaves the floor deliberately) → **swing** (moves while the other leg supports) /
**air** (neither foot down) → **landing** (touch-down after air; the body reacts). Not every
action uses all of them. The report prints each leg's phase strip, sampled every frame:

    Left Leg: plant 0.00-0.02 | release 0.02 | swing 0.03-0.27 | contact 0.28 | plant 0.28-0.60

How you author each phase:

| Phase | In the spec |
|---|---|
| plant | `"plant": true` keys with the support label; same leg values across the stance |
| release | the next key labels the other foot as support (`"support": "right"`): the left leg becomes free |
| swing | free leg: keeps its angle; if it would touch the floor it is pulled up into the hip (spec `"clearance"`, default 0.2 studs; 0.3 reads well in walks) |
| air | `"support": "air"` (or `"airborne": true`); with `plant` the legs keep their world angles |
| landing | `plant` key after air; give the legs their landing angles early (per-joint `"ease": "out"` on the legs of the key before) so the feet don't touch down early and skid |

Between two solved keys, interpolation can still dip a foot under the floor or let it slide (two
poses blend through a lower one). Fix it where it happens: a **breakdown** key
(`{"f": 4, "breakdown": true}`) starts as the in-between pose, takes the contact flags both
neighbours share and re-plants the feet at that time. Override any channel on it. Splitting an
eased segment keeps its feel (inout → in + out); `"ease": "linear"` on stance breakdowns of walks.

## 6. Weight transfer and one-leg poses

- Shift the body over the new support foot BEFORE the other foot leaves (Torso `right` 0.05-0.1
  toward it on the last two-foot key or a breakdown). The lint's INFO line checks it.
- Release the old contact deliberately: label the key where it lifts.
- The free leg travels a clear path above the floor (clearance), then the new foot is placed
  (`plant`) before the pose relies on it.
- Standing on one leg: an R6 leg hangs off the side of the torso, so a vertical support leg
  ALWAYS leaves the centre of mass ~0.55 studs inside its foot — it can't balance by itself.
  Roll the torso over the support hip (Torso `tilt` ~10° toward the support side; single-support
  keys pivot at that hip automatically) and angle the support leg slightly inward (`out` −6).
  Knee raise example: support left, Torso `tilt` −10, LeftLeg `out` −6 → sole 100%, balance +0.36.
- Never fake a transfer by sliding a planted foot sideways (the lint flags sideways drift).

## 7. Compression without knees

R6 has no knees: do not imitate an R15 squat by rotating the whole leg into the ground.
Compression = the legs sink into the torso (`plant` + Torso `up` < 0) + forward lean + head
nod + arms. For a landing: the legs arrive at their landing angles first, the body drops on the
contact frame (`out` ease into the deepest key), then recovers slower. For an impact: lean and
head snap, a 2-4 frame overshoot, settle.

## 8. Dynamic actions: contrast, not more keys

Build every major action from: **preparation** (move opposite the action: twist back, pull the
fist in with `reach` −0.4, dip) → **acceleration** (2-4 frames, `in` ease) → **main pose**
(direction unmistakable from the game camera, past the target) → **reaction** (body compression
on contact/impact) → **follow-through** (momentum continues 2-6 frames, moving hold) →
**recovery** (slower than the strike, no snap, back to the exact stance it started from).

- Choose the primary direction first, then coordinate torso, shoulders, hips, legs and head
  around it. Don't exaggerate every joint at once; push the 1-2 joints that carry the action.
- Contrast in timing (fast strike, slow recovery) and in silhouette (anticipation opposite the
  contact). The lint flags low-contrast one-shots and body-height pops.
- Not every move needs a big preparation or recovery: a jab is 3 frames of anticipation.

## 9. Composition tricks R6 animators use

- **Legs sunk into the torso** for low, powerful stances (crouch via `up`, legs stay near
  vertical, soles flat).
- **Leg forward**: the front foot ahead under the front hip (forward 8-14), never a leg
  trailing behind the torso in a stance; the back foot under the back hip.
- **Arm downward**: the off arm hanging low or slightly back (forward −10..20, out 10-30) gives a
  readable, asymmetric silhouette and keeps the attacking arm clear.
- **Twist the torso, not the legs**: legs stay planted under the hips, the torso carries the
  aim; the head turns back toward the target (counter-turn).
- **Lean is free**: it pivots at the hips, so it adds power without moving the feet.
- **No twinning**: offset left/right by 1-3 frames or vary the angles.

## 10. The pose library

`recipes/poses.json` — 16 poses built with these rules (rendered in `references/pose-library.png`):
neutral_stance, contrapposto, boxer_guard, wide_combat_stance, greatsword_ready, power_punch_R,
double_fist_forward, low_weapon_guard_R, high_block, sprint_flight (air), knee_raise_R (one leg),
low_crouch, sit_ground (body), victory_fist_up_R, point_forward_R, hurt_hunched. Copy one into
your spec's `"poses"`, start keys `"from"` it, and keep the flags its showcase key uses.
