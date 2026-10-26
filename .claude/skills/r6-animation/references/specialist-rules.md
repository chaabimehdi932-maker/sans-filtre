# R6 specialist rules → how this skill enforces them

The user's rulesets for R6 work ("R6 Animation Specialist", "Foot placement, support,
exaggeration & pose composition", "Dynamism and ground-contact specialist"), merged into one
checklist. Each rule says what to do and which tool or check holds you to it. When a rule
and a convenience conflict, the rule wins.

## 1. Know what you are editing (before touching anything)

| Rule | Do | Enforced by |
|---|---|---|
| Inspect the actual rig; never invent joints; R6 has no knees, elbows, ankles or waist | Run `scripts/studio/inspect_rig.luau` on the user's rig; paste its `"rig"` block into the spec if joints differ from default | inspector flags RigType, renamed root ("Root Hip"), custom C0/C1, AnimationConstraints, anchored limbs |
| Know what the asset is: editable keyframes, accessible animation data, procedural transforms, or only an uploaded ID | Editable KeyframeSequence → `import` it. An ID the user owns → `studio/fetch_animation.luau` then `import`. An ID you can't fetch → say so and explain what to do in Studio. Procedural code → it's not a keyframe asset; don't pretend | `fetch_animation.luau` warns on R15 and missing permission |
| Never claim to have edited keyframes when only a playback script changed | Say exactly which file changed: spec/.rbxmx/.luau (animation data) vs. game scripts (playback) | final report wording |
| No unrequested rig redesign, no procedural foot solver in the game | The `plant` solver runs offline and writes plain keyframes; the game gets a normal KeyframeSequence | exporter output |
| Don't move HumanoidRootPart or change physics to hide a bad pose | Fix the pose; root motion only through the game's own script when the design moves the character (dash/lunge markers) | lint "no root motion" guidance, recipes |
| Preserve markers, events, loop/priority and gameplay timing unless asked | `compare` prints MARKERS CHANGED / timing / priority diffs | `r6anim.py compare` |

## 2. Feet, support and balance

| Rule | Do | Enforced by |
|---|---|---|
| Identify the support at every key | `"support"`: double / left / right / transition / air / hands / body / fall | lint checks the label against geometry |
| Feet touch the floor: never float while standing, never sink, on any frame | `"plant": true`; free legs lift clear (`"clearance"`); breakdowns where interpolation dips | lint samples every 1/60 s: "goes N studs into the floor … Cause: …", "both feet float"; `studio/check_contact.luau` on the real rig + real floor |
| Measure the lowest point from the rotated corners, not the centre | built in (`foot_low`, 8 world-space corners) | — |
| Don't assume the floor is at Y = 0 | offline: floor = where the rest pose stands; in Studio: raycast per leg | `check_contact.luau` (stairs, slopes, platforms) |
| Standing/crouching: most of each supporting sole on the floor | legs within ~15° of vertical, under the hips; `stance` fits them | lint "only N% of the sole touches", report "sole on floor" |
| Never force both feet to equal heights; single support keeps the support foot, frees the other | support labels drive which feet `plant` locks | solver |
| Planted feet don't slide (incl. sideways); weight transfers are deliberate | same leg values across a stance; shift the body before the other foot lifts | lint "skates", "slides sideways", weight-transfer INFO; Studio checker in ground space (`SPEED`) |
| No leg trailing behind the torso in a stance | front foot ahead/under, back foot under the back hip | lint "leg sits behind the torso" |
| Centre of mass over the support | `"balance": true` nudges the hips; one leg: roll over the support hip | lint balance WARN, report "balance" |
| Fix the cause of penetration, don't counter-rotate blindly | read the lint's cause: key pose (leg tilt / Torso height) vs interpolation (breakdown, spacing, easing) vs floor mismatch (Studio checker) | lint cause text |
| A tilted R6 leg can't keep a flat foot | keep leg orientation compatible with the contact; take dynamism from torso, arms, head, timing | sole-contact WARN gives under-hip leg values |
| Don't imitate an R15 squat by rotating legs into the ground | compress by sinking legs into the torso + lean | posing.md §7 |

## 3. Poses, movement and dynamism

| Rule | Do | Enforced by |
|---|---|---|
| Build actions from preparation → acceleration → main pose → reaction → follow-through → recovery (adapted to the action) | key those beats; recovery slower than the strike, back to the exact start stance | craft.md timing tables; lint low-contrast INFO |
| Choose a primary direction; don't exaggerate every joint at once | push 1-2 joints that carry the action | `exaggerate --joints` |
| Controlled exaggeration: 10-20% per iteration, compared | `exaggerate --amount 1.15`, then `compare` | compare: lint deltas, motion range, balance |
| Strong silhouettes from the gameplay camera | check the `game` view of every key | contact sheet `game` row |
| No sudden body-height changes, no mechanical uniform timing | ease choices, enough frames | lint "body height jumps", "every segment linear", "metronome" |
| No limbs merging into the body / legs crossing | keep arms off the torso line, legs apart | lint clipping pairs (forearm/shin boxes) |
| Strikes: the fist travels into the target on the hit frame | strike twist rule (left-hand +, right-hand −), `reach` | lint strike line per marker |

## 4. Verification and honesty (the iteration loop)

1. Save the original (spec / .rbxmx / imported spec) before changing it.
2. Baseline: `build` (lint + report + sheet + GIF + slow GIF) — or `import` + `render` for an
   existing animation.
3. Name the three largest visible defects (from the renders and the lint), not a list of 20.
4. Make targeted changes (one cause at a time).
5. Re-render from the same views; `compare before.json after.json` for the side-by-side.
6. Judge ground contact, support, readability and dynamism on the pictures and the numbers;
   look at in-between frames (`render --every 0.033`, the slow GIF), not only keys.
7. Repeat until the improvement is visible.
8. Verify playback in the game: `studio/preview_in_play.luau` (blending, interruption, loop),
   `studio/check_contact.luau` (real rig, real floor), markers still fire.
9. Report honestly: what changed (and in which file), what was checked and how, what you
   could not verify (e.g. "not tested on your live game"). Never say "looks good" about
   something you did not render or inspect. A script that runs is not a success criterion.
