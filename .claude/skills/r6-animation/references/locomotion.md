# Locomotion on R6: walk, run, jump, fall, land

Read this before authoring any cycle. R6 legs are rigid 2-stud blocks pivoting at the
hip, which fixes the relationship between leg swing, cycle length, body bob and speed.
Get it wrong and the feet skate. `[S]` sourced, `[D]` derived, `[R]` recommended default.

## The two formulas

1. **Stride**: a leg swinging ±A sweeps the foot `s = 2·L·sin A` per step (L = 2 studs).
   No slide requires that sweep to happen while the foot is on the ground at the
   character's speed v: stance time = s / v. With two feet and a symmetric walk (each foot
   on the ground half the cycle), **cycle T = 2·s / v**. Runs have a flight phase: each foot
   is down only a fraction β (≈ 0.3–0.4) of the cycle, so **T = s / (β·v)**. [D]
2. **Bob**: with both feet touching (lowest corner on the floor, never below) the body height at
   contact for legs at ±A: 10-20° → +0.05 (the sole corner swings lower first), 30° → 0,
   37° → −0.10, 45° → −0.23. `plant`/`ground` compute it; the visible bob of an R6 walk comes
   mostly from the free leg lifting into the hip and the torso `up` you key. [D]

The linter's foot-slide check (`"speed": v` in the spec) measures the speed the planted
foot actually sweeps and prints the `AdjustSpeed` factor that would fix a mismatch.

## What speeds mean on R6

| WalkSpeed | Body-heights/s | Reads as | Typical cycle |
|---|---|---|---|
| 4–6 | ~1 | stroll | T ≈ 1 s, ±25–30° |
| 8 | 1.6 | brisk walk | T = 0.6 s, ±37° (recipes/walk.json) |
| 16 (default) | 3.2 | jog/run | T = 0.5 s, ±25° stance + flight phase, swing to −65/+55 (recipes/run.json) |
| 24+ | 5 | sprint | T ≈ 0.4 s, bigger flight phase, lean 18–25° |

A natural 1 s walk cycle only matches ~2–5 studs/s, so **the default WalkSpeed 16 is a
run for R6 proportions**. [S: research derivation, Froude check] Roblox's classic
procedural walk swung legs ±57° on a 0.70 s cycle (≈ 9.6 studs/s), tolerating ~40% slip. [S]

## Roblox's default Animate script and speed

- R6 Animate plays only `walk` (never `run`), at **Core** priority. [S]
- It scales the walk by `speed / 14.5` **only when the walk is the default asset
  180426354**. A custom walk id plays at speed 1 regardless of WalkSpeed. [S]
- So either author the walk for your game's actual WalkSpeed (set `speed` and make the
  lint say "Feet stay planted"), or fork Animate and call `AdjustSpeed(speed / v_authored)`.
- Jump: plays `jump` for 0.3 s, then fades into the looping `fall` over 0.3 s. There is
  **no landing animation** — play one yourself on `Humanoid.StateChanged → Landed`. [S]
- Default R6 locomotion ids (for reference/fallback): idle 180435571 (weight 9) +
  180435792 (1), walk 180426354, jump 125750702, fall 180436148, climb 180436334,
  sit 178130996. [S, from two independent mirrors of the R6 Animate script]

## Authoring a walk/run cycle (recipe)

1. Pick v (studs/s) and the leg amplitude A; compute T from the formulas (or start from
   `recipes/walk.json` / `recipes/run.json` and scale).
2. Key **one leg** only: contact (+A) → stance `linear` → toe-off (−A) → swing (`in`/`out`
   or `inout`) → contact. Then `"derive": [{"joint": "LeftLeg", "from": "RightLeg",
   "phase": 0.5}]` builds the other leg half a cycle later, perfectly mirrored.
3. Arms oppose the legs: right arm back when right leg forward. Amplitude ±20–30° walk,
   ±45–60° run; `out` 4–8° so they clear the body; `inout`.
4. Torso: lean 3–5° (walk) / 12–18° (run) forward; twist ±5–8° toward the forward arm
   (shoulders counter-rotate); shift the body over the stance foot (Torso `right` ±0.1 at
   passing, ±0.09 on the breakdown after contact) before the other foot lifts. **`plant: true`
   on every key** so torso motion doesn't swing the legs.
5. Body height and contact: label every key's support (`double` at contact, the stance foot
   on single-support keys, `air` in flight). Planted keys lock the stance foot; the free leg is
   pulled up into the hip so it never scrapes or sinks (`"clearance"`: 0.3 for walks). Where
   interpolation between two planted keys dips the stance foot into the floor, add a
   `"breakdown": true` key mid-stance with `"ease": "linear"` (walk.json has four). In a run,
   the body is higher in flight (`airborne` keys, `up` +0.1–0.15, `out`→`in` eases =
   ballistic); mark every key inside the flight phase `"support": "air"`. Check the report's
   contact-phase strip: plant → release → swing → contact for each leg, no "contact" blips
   in the middle of a swing.
6. Head: counter-turn about 80% of the torso twist so the eyes stay forward; small nod.
7. Close the loop with `{"f": END, "from": 0}`. Build; the lint must show no seam pop and
   "cycle matches ~v studs/s".

## Jump / fall / land

Game physics at defaults (JumpPower 50, gravity 196.2): rise 6.4 studs, apex at
0.255 s, back on flat ground at 0.51 s; ~31% of airtime is spent in the top 10% of the
height. [D]

- **Jump** (0.3 s, `airborne` keys): the impulse is instant, so there is **no room for a
  crouch anticipation** before takeoff — start already extended (push-off: arms up
  130–150, legs slightly back) and tuck one knee (leg forward 40–50) as it rises.
- **Fall** (loop ~0.8 s): arms up and out (forward ~140–150, out 35–45) with a slow
  asymmetric flail; legs slowly cycling. Not a frozen pose.
- **Land** (0.3–0.45 s, Action priority, played on Landed): impact pose is the squash —
  `plant` with Torso `up` −0.45..−0.6 (legs slide into the torso, soles flat; legs within ~10°
  of vertical),
  torso lean 15–22 with the head following through (nod +10–15), arms out for balance;
  deepest 3–5 frames after impact; recover with `inout`, feet never moving.
