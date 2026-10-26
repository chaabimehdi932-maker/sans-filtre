# R6 animation craft: making it look good

How experienced R6 animators think, translated into spec-level decisions. Sources are the
Roblox DevForum community (feedback threads, Jespone's guide), commercial R6 combat packs,
battlegrounds-game wikis, Mariel Cartwright's GDC talk (Skullgirls), classical animation
(Illusion of Life's 12 principles, Williams), and the derived rigid-limb geometry in
`rig.md`. Labels: **[community]** widely repeated Roblox advice, **[transfer]** general
game-animation practice, **[derived]** follows from R6 geometry, **[default]** this skill's
recommended starting value (no single authoritative source).

## Contents
1. The R6 mindset
2. Timing and spacing
3. Easing map
4. Posing
5. Combat (M1 strings, strikes, blocks, hit reacts, finishers, dashes)
6. Idles
7. Emotes and dances
8. Deaths and knockdowns
9. Beginner mistakes → fixes
10. Workflow

## 1. The R6 mindset

- **Exaggerate.** Six rigid parts carry less information than a human, so push poses
  well past anatomy — about 1.3–1.5× realistic angles. [community][transfer]
- **The torso does the acting.** No elbows, knees or spine: reach, power and weight come
  from Torso `twist`/`lean`/`tilt` and body translation (`up`/`forward`), not from the arm.
  A punch "extends" because the torso rotates through, the body shifts forward and the arm
  slides out of the shoulder (`reach`). [community][derived]
- **Strike twist direction (get this right):** the chest turns *away from the punching arm's
  side* through contact, driving that shoulder forward. **Left-hand strikes: twist goes UP
  (+, chest turns right). Right-hand strikes: twist goes DOWN (−).** The anticipation loads
  the opposite way first. Twisting the wrong way drags the fist backward. Check it: the
  lint prints where the hand travels into every marker ("forward +0.9 …").
- **Feet stay planted** unless the character steps: `plant: true` on grounded keys, and keep
  the leg angles the same across keys (changing them moves the feet).
- **Snappy beats smooth** for action: fast acceleration/deceleration, few strong keys,
  holds. The battlegrounds look is effectively *limited animation*. [community]
- **Arcs come for free on limbs** (rigid limbs about fixed pivots move on circles of
  radius 1.5/2 studs). Add body translation so the *whole body* path arcs too. [derived]
- **Squash & stretch has no scale** on R6. Substitute: squash = body dip 0.2–0.6 studs
  (plant + negative `up`: legs slide into the torso; or splayed legs + ground) + torso
  pitched + arms in; stretch = body rise + legs straight + arms overhead + limbs `reach`ing
  0.1–0.3 out of their sockets for 1–3 frames. Exaggerate the speed contrast. [derived][default]

## 2. Timing and spacing

All times in seconds (frame-rate independent). At 60 fps 1 frame = 0.0167 s;
the Animation Editor defaults to 30 fps (1 frame = 0.033 s).

| Thing | Duration | Note |
|---|---|---|
| Anticipation before a player attack | 0.03–0.1 s (2–6 f @60) | Tiny but *extreme* pose contrast. Even 1 frame reads. [transfer] |
| Anticipation for heavy / enemy attacks | 0.15–0.4 s | Players need time to react. [transfer] |
| Strike (anticipation → contact) | 0.03–0.07 s | Snap. Overshoot by ~1 frame, then settle. [community] |
| Hold on contact (hit-stop look) | 0.05–0.1 s | Moving hold. 2–4 f @60 light, ~0.09 s heavy. [community][transfer] |
| Recovery back to stance | 0.15–0.35 s | Slower than the strike, shows effort. Weak recovery reads as "a light tap". [community] |
| Whole M1 hit | 0.3–0.45 s | Finisher 0.5–0.8 s. [default] |
| Blend between chained attacks | ~0.1 s fade | Fast enough to not notice, slow enough to not pop. [community] |
| Light hit react | 0.3–0.5 s | Stagger 0.8–1.5 s. [derived from 10–25 f charts] |
| Death fall (authored) | 0.4–0.8 s + 0.3–0.6 s settle | Game gravity makes physics collapses look too fast. [derived] |
| Idle loop | 2–4 s (simple), 8–12 s (with weight shift) | Breath period 3–4 s. [transfer] |
| Emote loop | 2–8 s, seam on a strong beat | [transfer] |

Spacing rules:
- **Contrast**: vary segment lengths. Evenly spaced keys with identical easing look
  metronomic (the linter flags this).
- **Favouring**: a breakdown at 1/3 or 2/3 of the way between two keys (not 1/2)
  produces ease without curve fiddling. Favour the destination for decelerating moves.
- **Moving holds**: never hold a character dead still for more than ~0.2–0.3 s in play.
  Drift 2–5% further in the same direction (`"hold": true` + small overrides).
- **Overshoot & settle** for a move of size A: overshoot +10–20% of A about 2–4 frames
  (@30) after arrival, undershoot −5–10% 2–3 frames later, settle by ~0.2–0.33 s.
- **Overlap**: the torso leads; the head lags 1–3 frames (@30), arms 2–4 frames; each
  overshoots 5–15% before settling. Put the lagging joint's key a few frames later.

## 3. Easing map

(Spec names; the exporter writes the Roblox enums that play this way at runtime.)

| Segment | `ease` |
|---|---|
| Into an anticipation / wind-up pose | `out` (settle into it) or `inout` |
| Wind-up → contact (the strike) | `in` (accelerate into impact) or `linear`, 1–4 frames |
| Contact → overshoot/hold | `linear` (moving hold) |
| Hold → recovery to stance | `inout` (or `out`) |
| Walk/run swing leg, arms, body bob | `inout` (pendulum) |
| Stance leg (contact → toe-off) | `linear` (constant ground speed = no slide) |
| Loop seam of continuous motion | `linear` on both sides of the seam |
| Takeoff / launch | `out` |
| Falling, toppling | `in` (gravity accelerates) |
| Landing impact → recovery | impact key `out` |
| Stepped "anime / low-FPS" look, impact frames | `constant` |
| Cartoon settle, bouncy prop | `elastic.out` / `bounce.out`, sparingly |

Never leave everything `linear` — it reads robotic. [community, widely repeated]

## 4. Posing

- **Silhouette first**: key poses must read from the actual game camera (usually behind
  and above the character, third person). Separate arms from the torso by ≥ 15–20°. Check
  the three-quarter view in the contact sheet. [transfer][derived]
- **Line of action**: align torso `lean`/`tilt` with the limb arcs of the action.
- **Contrapposto / weight**: twist or tilt the torso one way, counter with the legs (`plant`)
  and offset the arms the other way. Keep the centre of mass over the support foot.
- **No twinning**: never give both arms (or both legs) identical angles and timing. Break
  symmetry by 5–15° and offset timing 1–3 frames. Mirroring a move creates twinning; vary
  it afterward. [community]
- **Don't fight the rig** (see `rig.md` pivot quirks): raise arms overhead with `forward`,
  not `out`; keep inward `out` ≥ −15°; crouch by splaying legs + `ground`.
- **Fighting stance (right-handed, "orthodox")** [default]: Torso twist +20..30, lean 5–8;
  lead (left) arm forward 75–85, rear arm forward 55–65 with small inward `out`; lead leg
  forward 15–20, rear leg −12..−16, both `out` 4–8; head `turn` ≈ −twist so the eyes stay
  on target. All grounded keys `plant: true`, spec `ground: true`.

## 5. Combat

**M1 string (battlegrounds standard)** [community]: 4 hits. Hits 1–3 apply light
hitstun (~0.2 s reported); hit 4 is a knockback or downslam that usually hands off to
ragdoll. Many games add an uptilt and a downslam. **Every hit starts and ends on the
same fighting stance** so hits chain with a ~0.1 s blend; alternate arms across hits
1–3 and give hit 4 a bigger whole-body commitment (step, hop, full twist).
Scripts: stop the previous M1 before playing the next, or two same-priority tracks blend
50/50.

**Anatomy of a strike** (the "5 key poses": anticipation, wind-up, contact,
follow-through, recovery) [community][transfer]:
1. Stance (key 0).
2. Anticipation: pull back *against* the direction of the strike — torso twists away,
   striking arm drops/pulls back, body dips slightly. 2–4 frames @60, ease `in` on it
   toward contact.
3. Contact: arm at full extension (~90 forward for straight punches), torso rotated
   *through* the strike (past neutral), body shifted forward 0.15–0.3 studs, head follows.
   `Hit` marker here. Optionally overshoot one frame past the final contact pose.
4. Hold/follow-through: 3–6 frames, `linear`, drifting 1–3° further.
5. Recovery to stance: 10–15 frames, `inout`. Show effort (slower than the strike).

Type-specific notes [default]:
- **Jab (lead/left)**: guard twist +25 → load +20 with the arm pulled in (`reach` −0.35) →
  contact twist +32, arm forward 90, `reach` +0.2, body forward 0.2. Small twist, big reach.
- **Cross (rear/right)**: more rotation (+40 → −18) and a forward weight shift; the lead hand
  pulls back to the chin (opposition).
- **Hook (lead/left)**: arm stays horizontal (forward ~85–90) with the elbow wide (`out` +50)
  on the load while the chest turns left (+10), then the chest whips right (+48..+54) and the
  arm sweeps to `out` ≈ −8. A right hook mirrors this (twist goes down). Don't push the arm
  more inward — the torso rotation does the "across".
- **Uppercut / launcher**: deep crouch (splayed legs + `ground`), explosive rise (body
  `up` +0.3–0.4, key `airborne`), arm forward 160–175, lean back −10, head up. Hang at the
  top briefly so the knockback reads.
- **Weapon slash (right-hand tool)**: start/end in the tool-hold pose (right arm forward
  90). Wind-up high over the shoulder (forward ~160, out ~45, twist ~35, torso twist +30);
  swing in 3 frames `linear`; follow-through low across (forward ~40, out −15, torso twist
  −40) with `out` ease; `Hit` marker mid-swing.
- **Block**: both arms up in front of the face, nearly parallel (forward 100–120,
  out ≈ −10, twist ≈ −45), torso lean 10–15, head down. Loop as a held pose with a moving
  hold; script plays/stops it with ~0.08 s fades.
- **Hit react**: Action2 (overrides attacks); play with fadeTime 0 — frame 0 *is* the
  impact pose (thrown away from the force: torso lean 10–25° away, body shifted 0.2–0.5
  studs, head whipping 1.3–1.5× further and 1 frame later, arms flung 20–60°). 3–5 frames of
  overshoot, slow settle (`out`/`inout`), end at rest so the fade-out is clean. Make
  front/back/left/right variants.
- **Dash**: no root motion on R6 — the script moves the character between `DashStart` and
  `DashEnd` markers. Crouch → launch into a long leaning stride with arms swept back
  (moving hold while gliding) → brake by leaning back on the front leg → recover.

**Impact = animation + game feel** [community]: fire hitbox, SFX, VFX, hit-stop
(freeze both characters 2–4 frames on heavy hits, ~0.05 s light / ~0.09 s heavy) and
camera shake from the `Hit` marker, never from a timer guessed separately. Impact frames
(1 frame, big hits only). Readability comes from pose contrast and silhouette, not from
long wind-ups.

## 6. Idles

- Breathing: torso `up` +0.03–0.05 studs and lean −1° on the inhale, 3–4 s period.
  Arms drift `out` +2–3° and head `nod` −2° a beat later (overlap). Feet a little apart
  (`out` 3–4, slight toe-out `twist`). [transfer][default]
- Loop must be seamless: last key `from: 0`.
- Variety: Roblox's R6 idle picks between two variants 9:1. A single loop becomes
  noticeable after ~90 s; add a rarer variant (look around, shift weight).
- Combat idle = the fighting stance with breathing and a subtle bounce.

## 7. Emotes and dances

- Frames per beat = fps × 60 / BPM (120 BPM @60 fps = 30 frames = 0.5 s). Put keys at
  exact beat times; non-integer frame intervals drift if rounded.
- Down on the beat (body dip via splayed legs + `ground`), up on the off-beat; ease `in`
  into the beat, `out` out of it. Head nods on the beat. Arms alternate.
- Seam on a strong beat; match *speed* (not just pose) across the seam.
- Loops 2–8 s. Waves/gestures: raise the arm with `forward` (not `out`) and wave with
  small `out` swings in the frontal plane.

## 8. Deaths and knockdowns

- Fast in, slow settle: 0.1–0.2 s reaction → 0.4–0.8 s fall (`in`, accelerating) →
  impact → small bounce (≈ half height, 70% duration) → settle with the head rolling to
  the side.
- Falling backward on R6: RootJoint pivots at the torso centre, so to tip over the heels
  move the body back by 3·sin(lean) studs (`forward` negative) while `ground` keeps the
  lowest point on the floor. Lying flat = lean ±90, `forward` ∓3.
- Hold the last frame from the script (`AdjustSpeed(0)` on a final marker) or the track
  ends and blends back to idle. Set `Humanoid.BreakJointsOnDeath = false` or the joints
  break before the animation can play.

## 9. Beginner mistakes → fixes

| Mistake | Fix |
|---|---|
| Everything linear | Ease per section 3 |
| Keying every frame / too many keys | Key the extremes; let easing interpolate |
| Twinning (symmetric limbs, same timing) | Offset 1–3 frames, vary angles 5–15° |
| No torso bob / dead torso | Torso up/down + twist; it's the R6 spine |
| Punch feels like a tap | Bigger anticipation contrast, snap strike, effortful recovery |
| Walk legs too wide / lifted above waist | Keep legs under the body, ±25–45° |
| Same-side arm and leg swinging together | Arm opposes the same-side leg |
| Feet sink or float | `ground: true`, `plant: true` when leaning |
| Foot sliding in locomotion | Set `speed` and match stride (see `locomotion.md`) |
| Torso lean drags the legs | `plant: true` |
| Arm overhead clips the head | Raise with `forward`, not `out` |
| Loop pops | Last key `from: 0`; linear seam for continuous motion |
| Animation half-strength in game | Priority too low (Core blends 50/50 with Animate) |

## 10. Workflow

1. Block the extremes (pose-to-pose), check the contact sheet.
2. Add breakdowns/favouring and overlap (offset head/arms).
3. Easing pass. Check the onion image (arcs + spacing dots).
4. Polish: moving holds, overshoot/settle, asymmetry.
5. Test in game with the real camera, priority, markers and blends.
