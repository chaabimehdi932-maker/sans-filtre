# Body Mechanics and Locomotion for Blocky Rigs (Roblox R6)

Method note for the report writer: in this research environment WebFetch could not resolve any host, and the proxy blocked devforum.roblox.com, create.roblox.com, Wikipedia, gist raw URLs and most blogs. So:
- **Roblox engine facts were read directly from primary files** on raw.githubusercontent.com / git: the official `Roblox/creator-docs` source, Roblox's own Studio R6 rig-builder (bytecode disassembly in `MaximumADHD/Roblox-Client-Tracker`), and verbatim copies of the legacy Roblox `Animate` scripts.
- **Classical and game-animation material (Williams, Game Anim, school blogs) came only from search-engine summaries** of those pages. These are secondary and were not read in full. Where a summary did not clearly say which result a claim came from, the note says so.
- Labels used below: **[S]** = number taken from a source; **[D]** = number I derived (formula shown); **[R]** = my recommended default (inference, tune in testing).

---

## Q1. Walk and run cycles: key poses, frame counts, body bob, arm opposition, counter-rotation, head

### Takeaway
A step has four keys: contact, down, passing and up. A natural walk is "on 12s" at 24 fps, which is 0.5 s per step and 1.0 s per two-step cycle. Runs are about 4–8 frames per step (0.17–0.33 s) and include a flight phase. In a walk the body is lowest on the down pose and highest on the up pose. In a run the down pose is lowest and the airborne pose is highest. Arms swing opposite the legs and reach their extremes at contact. The chest counter-rotates against the hips, and the head counters the chest.

### Cited Findings
- **Walk tempo table (a secondary site that says it adapted it from Williams' *Animator's Survival Kit*), 24 fps, full two-step cycle:** [S]
  - 16-frame cycle (8 per step): "fast, bouncy 'cartoon' walk or slow run".
  - 24-frame cycle (12 per step): "brisk, natural walk (two steps a second)".
  - 32-frame cycle (16 per step): "relaxed stroll".
  - 40-frame cycle (20 per step): "elderly or tired person".
  - [Animation Explainers – Walk Cycle Animation](https://animationexplainers.com/walk-cycle-animation/)
- "Most people walk on 12s", meaning one step every 12 frames at 24 fps [S]. — [AnimSchool blog – Walk Cycle Animation Tips](https://blog.animschool.edu/2024/03/14/walk-cycle-animation-tips/)
- **Key-pose layout of a 24-frame walk loop** [S]:
  - Contact on frame 1, down on 4, passing on 7, up on 10.
  - The other leg repeats this on frames 13–22, and frame 25 equals frame 1, so a key falls every 3 frames.
  - [Spotlight FX walk-cycle guide](https://spotlightfx.com/blog/walk-cycle-animation-beginners-guide-to-creating-realistic-movement); [Animation Explainers – walking for beginners](https://animationexplainers.com/walking-animation-for-beginners/)
- Hips are lowest on the down pose and highest on the up pose. — [Island Class – walk cycle for games](https://islandclass.org/2026/09/26/walk-cycle-animation-for-games/). Autodesk's walk tutorial describes the passing pose as higher than contact, with the body rising through the middle of the step. — [Autodesk 3ds Max 2011 help – Freeform walk cycle](https://download.autodesk.com/us/3dsmax/2011/help/files/WS1a9193826455f5ff-e569a012180ce589112eb.htm)
- Arms swing opposite the legs, follow arcs and lag slightly behind the body. — [Island Class](https://islandclass.org/2026/09/26/walk-cycle-animation-for-games/). The arms are furthest out around the contact pose. — [Joshua Rosenstock – walk cycle notes](https://joshuarosenstock.com/teaching/GPH213/walkcycle/walk.html)
- Williams' book organises runs by drawings per cycle: "The 4 Drawing Formula Run", "The 3 Drawing Run" and "The 2 Drawing Run" (seen in the book's table of contents). — [Animator's Survival Kit text (archive.org)](https://dn721807.ca.archive.org/0/items/taskav-01/The__Animator%27s_Survival_Kit%5B1%5D_text.pdf)
- **Run timing figures from run-cycle tutorials** (search summary; I could not tell which page each figure came from):
  - A run on 8s puts contacts on frames 1 and 9, passing on 5 and 13, and down on 3 and 11.
  - A game-dev guide gives a standard run as 16–20 frames at 30 fps ("roughly 0.5 seconds per full stride") and sprints as 12–16 frames.
  - Pixel-art runs are typically 6–8 frames. Naruto-style runs are on 1s with a 3-frame cycle.
  - One timing chart lists "12 frames – A run or very fast walk (4 frames per step, 6 steps per second)" and "16 frames – Slow run or 'cartoon' walk (6 frames per step, 4 steps per second)". **These are internally inconsistent**: a 12-frame cycle is 6 frames per step, not 4. Treat this chart as unreliable.
  - Candidate sources: [MoCap Online – Run Cycle Animation](https://mocaponline.com/blogs/mocap-news/run-cycle-animation), [Rusty Animator – Run cycle](https://rustyanimator.com/run-cycle/amp/), [Sakuga wiki – Run cycle](https://sakuga.fandom.com/wiki/Run_cycle), [Sprite-AI pixel guide](https://www.sprite-ai.art/guides/how-to-animate-pixel-art)
- **Run poses** run Contact > Down > Push > Peak > Contact. The down pose is "the lowest, most squashed point" with the ground leg bent. The peak is the highest point and fully airborne. The down pose also defines "the extreme bend forward" with a flat leading foot taking the weight. — search summary of [Animation Mentor – Animating Dynamic Run Cycles](https://www.animationmentor.com/blog/animating-dynamic-run-cycles/) and [Rusty Animator](https://rustyanimator.com/run-cycle/)
- **Lean:** an extreme sprinter pushes the torso out and bends the legs low, while "a light jog" calls for "a less severe tilt". — [Animation Mentor – dynamic run cycles](https://www.animationmentor.com/blog/animating-dynamic-run-cycles/) (via search summary)
- **Counter-rotation at contact:** "Hips rotate toward the front leg, chest opposes the hips, arms oppose the legs, head opposes the chest." At passing, Y-rotation (yaw) of torso and hips is zero and Z-rotation (roll) peaks. — run-cycle tutorial quoted in search summary ([Rusty Animator](https://rustyanimator.com/run-cycle/) / [UW CSE459 run tutorial](https://courses.cs.washington.edu/courses/cse459/03wi/Projects/Adam/run/run.html); exact attribution unverified)
- **Head:** tutorials say "bob the head a little as they go up and down" and "offset the chest and head movement for a cascading effect". None of the sources found says the head should stay perfectly level. — same run-tutorial set ([Animation Mentor](https://www.animationmentor.com/blog/animating-dynamic-run-cycles/), [Rusty Animator](https://rustyanimator.com/run-cycle/))
- **Biomechanics:** in walking, the centre of mass traces "a smooth regular sinusoidal curve with two cycles for every gait cycle" vertically. — [Design Society – trajectory of the body mass centre during walking](https://www.designsociety.org/download-publication/29655/trajectory_of_the_human_body_mass_centre_during_walking_at_different_speed). Vertical CoM excursion grew from 2.74 ± 0.52 cm at the slowest walking speed to 4.83 ± 0.92 cm at the fastest. — [PubMed 15685471 – effect of walking speed on CoM displacement](https://pubmed.ncbi.nlm.nih.gov/15685471/)

### Inferences
- **Frame-rate-independent timing table** [D] (seconds = frames ÷ 24; style labels from the sources above):

| Style | Frames/step @24 fps | s/step | s/cycle (2 steps) | Frames/step @30 | Frames/step @60 |
|---|---|---|---|---|---|
| Sprint / very fast run | 4 | 0.167 | 0.333 | 5 | 10 |
| Run | 6 | 0.25 | 0.50 | 7.5 | 15 |
| Jog / slow run / cartoon walk | 8 | 0.333 | 0.667 | 10 | 20 |
| Natural brisk walk | 12 | 0.50 | 1.00 | 15 | 30 |
| Relaxed stroll | 16 | 0.667 | 1.333 | 20 | 40 |
| Elderly / tired | 20 | 0.833 | 1.667 | 25 | 50 |

- **Key-pose phase as a fraction of one step** [D, from the 1/4/7/10 layout]: contact 0, down 0.25, passing 0.5, up 0.75, next contact 1.0. Each leg's full cycle is two steps, so the second step is the mirror at phases 1.0–2.0.
- **Vertical bob** [D]: the body bobs twice per cycle, once per step. A 2.7–4.8 cm human CoM excursion converts to about 0.10–0.17 studs, using Roblox's 1 stud = 28 cm ([Roblox units doc](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/physics/units.md)). [R] Stylised blocky characters usually need more for the motion to read: about 0.1–0.25 studs for a walk and 0.3–0.6 studs for a run (see Q2 for the geometric minimum).
- **Arm extremes** [R]: line up arm extremes with leg contacts, opposite side forward. Delay the arm extreme 1–2 frames at 30 fps (0.03–0.07 s) after contact to get the "lag" the sources describe.

### Gaps
- I could not read Williams' book pages or Jonathan Cooper's *Game Anim* directly, because fetching was blocked. Williams' exact up/down offsets and Cooper's locomotion numbers are therefore unverified.
- I found no source that gives degree values for human arm swing, torso counter-rotation or pelvic tilt.
- I found no source confirming "head stays level". Head stabilisation guidance in Q2 is inference.

---

## Q2. Selling cycles without knees or elbows (R6 rigid-limb geometry)

### Takeaway
R6 legs are rigid 1×2×1 blocks that pivot at their top edge, 2 studs above the foot. A rigid leg cannot shorten, so if the planted foot is to stay on the ground the root has to drop at contact by L·(1−cos θ). That gives a geometric bob: lowest at contact and highest at passing. You sell the motion through four levers: leg swing amplitude, root (RootJoint) bob and side-to-side shift, torso pitch/roll/yaw, and shoulder-only arm swing with a forward bias.

### Cited Findings
- **Official R6 rig dimensions** [S], from Roblox Studio's built-in R6 rig builder (`AssetImporter/Src/Utility/RigSetup/R6`):
  - HumanoidRootPart is 2×2×1. Torso is 2×2×1.
  - Left/Right Arm and Left/Right Leg are each 1×2×1.
  - Head is 2×1×1, with a Head SpecialMesh scaled 1.25.
  - All Motor6Ds have MaxVelocity 0.1.
  - [Roblox-Client-Tracker R6.luac.s](https://raw.githubusercontent.com/MaximumADHD/Roblox-Client-Tracker/roblox/BuiltInPlugins/AssetImporter/Src/Utility/RigSetup/R6.luac.s)
- **R6 joint offsets** [S], same file:
  - **Right Hip:** C0 = CFrame.new(1,−1,0) rotated 90° about Y; C1 = CFrame.new(0.5,1,0) rotated 90° about Y. Left Hip mirrors this: C0 (−1,−1,0) and C1 (−0.5,1,0), rotated −90°.
  - **Right Shoulder:** C0 = (1,0.5,0); C1 = (−0.5,0.5,0). Left Shoulder: C0 (−1,0.5,0); C1 (0.5,0.5,0).
  - **Neck:** C0 = (0,1,0); C1 = (0,−0.5,0), with a rotation matrix of (−1,0,0, 0,0,1, 0,1,0).
  - **Root joint:** named "Root Hip" in this builder, with identity-position C0 and C1 and the same rotation matrix.
  - [Roblox-Client-Tracker R6.luac.s](https://raw.githubusercontent.com/MaximumADHD/Roblox-Client-Tracker/roblox/BuiltInPlugins/AssetImporter/Src/Utility/RigSetup/R6.luac.s)
- For R6, "Height = LeftLeg.Size.Y + (0.5 * RootPart.Size.Y) + HipHeight", where HipHeight is a relative offset. — [Roblox creator-docs, Humanoid.HipHeight](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/classes/Humanoid.yaml)
- Motor6D relation: Part0.CFrame · C0 · Transform = Part1.CFrame · C1. — DevForum reply cited in search summary ([Motor6D reference](https://create.roblox.com/docs/reference/engine/classes/Motor6D))
- **Roblox's own pre-2013 procedural R6 animation** [S]:
  - Running: amplitude = 1 rad, frequency = 9. The angle is `desiredAngle = amplitude * math.sin(time * frequency)`, applied as RightShoulder = +d, LeftShoulder = +d, RightHip = −d, LeftHip = −d. The left joints are mirrored, so this gives contralateral swing.
  - Shoulder MaxVelocity is 0.15. Climbing adds a π "climbFudge" to the arms.
  - All other poses (idle etc.) use amplitude 0.1, frequency 1.
  - Jump/freefall puts both arms at 3.14 rad (straight up) and both hips at 0, with `jumpMaxLimbVelocity = 0.75`. Sit puts arms and hips at ±π/2.
  - [old-roblox-animation script (raw)](https://raw.githubusercontent.com/cambam239053cam/old-roblox-animation/main/script)
- In walking, double support is where "the two limbs work against each other as the body transitions from one inverted pendulum arc to the next". — search summary of [PMC12326370](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC12326370/)

### Inferences
- **Geometry** [D]:
  - Hip pivot to foot bottom: L = 2 studs. Shoulder pivot to hand end: 1.5 studs (the pivot sits 0.5 studs below the top of the arm).
  - In standing R6 (HipHeight 0), the Torso/HRP centre is 2 + 1 = 3 studs above the floor. Total height is 2 (legs) + 2 (torso) + 1 (head) = 5 studs. At 28 cm/stud that is about 1.4 m.
  - Legs and arms swing in the sagittal plane about the torso's X axis.
- **Compass-gait bob** [D]: with a planted foot at leg angle φ from vertical, hip height = L·cos φ. To keep the foot on the floor, the root has to sit lower at contact (φ = ±θ) than at passing (φ = 0) by **Δy = L(1 − cos θ)**. With L = 2:

| ±θ | 15° | 20° | 25° | 30° | 35° | 40° | 45° | 60° |
|---|---|---|---|---|---|---|---|---|
| Δy (studs) | 0.068 | 0.121 | 0.187 | 0.268 | 0.362 | 0.468 | 0.586 | 1.0 |

- **Rigid-leg bob versus classical bob** [D/R]: rigid-leg geometry puts the low point at contact and the high point at passing. Classical animation, which relies on knee bend, puts the low at "down" (25% of the step) and the high at "up" (75%). [R] Key the root low between contact and down (about 0–25% of the step) and high between passing and up (about 50–75%). Shifting the bob about 1/8 step after the leg keys fakes knee absorption and push-off.
- **Block-corner check** [D]: the leg is 1 stud deep and its pivot is centred in depth. The lowest corner below the pivot is 2cos θ + 0.5 sin θ, which peaks at 2.06 studs at θ ≈ 14°. At small swing angles the toe/heel edge sinks at most about 0.06 studs into the floor, which is negligible.
- **Torso** [R]: R6 has one rigid torso carrying both hips and shoulders, so the classical counter-rotation of chest against pelvis cannot happen inside the body. Alternatives:
  - **Yaw:** ±3–8° following the shoulders, so the torso turns to bring the shoulder of the forward arm ahead. Keep HumanoidRootPart heading unchanged.
  - **Roll:** ±2–4°, dropping toward the unsupported, swinging-leg side at passing (the "Z apex at passing" from Q1).
  - **Lateral shift:** RootJoint X ±0.05–0.15 studs toward the stance leg.
  - **Pitch:** forward lean of about 0–5° walk, 10–15° jog, 15–25° sprint. The lean values are my inference; the sources only describe lean qualitatively.
- **Arms without elbows** [R]:
  - Walk: arms ±0.5–0.8× the leg amplitude, mirrored to the opposite leg.
  - Run: imply a bent elbow by adding a forward bias of +10–25° to both arms and swinging ±35–60°. Keep the forward swing larger than the back swing.
  - Using the legacy script's amplitude (±57° at 9 rad/s) for both arms and legs reads as the classic Roblox "toy" run.
- **Head** [R]: counter-rotate the Neck against the torso's pitch, roll and yaw at about 50–100%, so the gaze stays roughly level. Let the head lag the torso by 1–2 frames at 30 fps (overlap). The sources support a slight head bob, not a locked head.
- **Selling weight with no knees** [R]: use contact-pose spread (stride angle), root dip depth, how long the low pose is held (a longer, deeper dip reads as heavier), and arm/torso overlap delay.

### Gaps
- I did not verify that spawned R6 player characters name the root joint "RootJoint" rather than "Root Hip" as in the rig builder. Inspect in Studio.
- I found no sourced degree values for torso, arm or head rotation in walk or run cycles. All angle defaults above are [R].

---

## Q3. Avoiding foot sliding: stride, leg length, speed, and how Roblox's Animate scales playback

### Takeaway
For a rigid leg of length L swinging ±θ, the step length is s = 2L·sin θ. For no slide, a foot must stay planted for s / v seconds, so the cycle period is **T = s / (β·v)**, where β is the duty factor (the fraction of the cycle each foot spends on the ground). With a symmetric swing (β = 0.5) this is T = 2s / v. With L = 2 and Roblox's default WalkSpeed of 16 studs/s, a symmetric no-slide cycle at ±30° lasts only 0.25 s, which looks frantic. The physically consistent choice is a run with a flight phase: β ≈ 0.35, ±45°, T ≈ 0.5 s, or 0.25 s per step. That is "runs on 6s" at 24 fps.

On playback scaling: the R6 Animate script scales the walk track by speed/14.5, but **only for the default walk asset ID**. The R15 script normalises speed against 12.8 studs/s and cross-fades walk into run.

### Cited Findings
- WalkSpeed defaults to `StarterPlayer.CharacterWalkSpeed` (16), "meaning a player character can move 16 studs in any direction each second". While running, humanoids "cover, on average, their WalkSpeed in studs per second". — [creator-docs Humanoid.yaml](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/classes/Humanoid.yaml)
- 1 stud ≈ 28 cm. — [creator-docs physics/units.md](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/physics/units.md)
- *Game Anim* (Cooper) excerpt, via search summary:
  - Sliding is common when the character's in-world movement speed doesn't match the animation's speed.
  - Sliding is linked to exporting in-place animations and having code supply forward movement. A hybrid approach is suggested where precise ground contact matters.
  - [Game Anim 2nd ed. (dokumen.pub copy)](https://dokumen.pub/game-anim-video-game-animation-explained-2nbsped-9781000357806-1000357805.html)
- Matching playback to foot travel: analyse how far the foot travels from the start frame to the end frame, then play the matching number of frames for the distance covered. — [Leadwerks – Moving without foot sliding](https://www.leadwerks.com/community/blogs/entry/43-moving-without-foot-sliding). A Blender proposal uses stride length and stride duration to compute the matching walking speed, and notes that in runs only one foot, or none, is touching the ground. — [bf-animsys mailing list 2014](https://lists.blender.org/pipermail/bf-animsys/2014-August/000152.html)
- **R6 keyframe Animate script, 2015-era default, verbatim copy** [S]:
  - `onRunning(speed)`: if speed > 0.01, `playAnimation("walk", 0.1, Humanoid)`. Then, only if the current AnimationId equals the default walk `...asset/?id=180426354`, it calls `setAnimationSpeed(speed / 14.5)`. Otherwise it plays "idle" with a 0.1 s fade.
  - Climb is scaled with `speed / 12.0`.
  - The `run` entry is a placeholder ("run.xml"), so R6 has no separate run animation. One walk clip is time-scaled.
  - `setAnimationSpeed` calls `AnimationTrack:AdjustSpeed`.
  - Default IDs: idle 180435571 (weight 9) and 180435792 (weight 1); walk 180426354; jump 125750702; fall 180436148; climb 180436334; sit 178130996.
  - [MechaXYZ copy of ROBLOX Animation Script (raw)](https://raw.githubusercontent.com/MechaXYZ/VSBScripts/main/ROBLOX%20Animation%20Script). Search results show the same `speed / 14.5` line in other copies ([Scribd copy](https://www.scribd.com/document/897868165/Source)).
- **R15 Animate** (search summaries of DevForum posts that quote the official `setRunSpeed`; not read directly):
  - `normalizedWalkSpeed = 0.5`, commented as "established empirically" from the walk animation, and `normalizedRunSpeed = 1`.
  - Below 0.5 only walk plays, time-warped by runSpeed/0.5. Between 0.5 and 1, walk and run cross-fade at timewarp 1. Above 1 only run plays, time-warped by runSpeed.
  - `rootMotionCompensation` multiplies speed by 1.25 and divides by a HipHeight-derived height scale. The `onRunning` threshold is 0.75 × heightScale.
  - [DevForum – Did a roblox update break scaled animations?](https://devforum.roblox.com/t/did-a-roblox-update-break-scaled-animations/1292468); [DevForum – R15 Strafing Run/Walk Threshold Change](https://devforum.roblox.com/t/r15-strafing-runwalk-threshold-change/3020381)
- A community rewrite of Animate (MaximumADHD, 2022), read directly, encodes the same constants [S]:
  - `baseRunSpeed = 16 / 1.25` (12.8) and `baseWalkSpeed = 8 / 1.25` (6.4).
  - `runSpeed = (speed / baseRunSpeed) / heightScale`.
  - `getHeightScale()` returns HipHeight/2, or 1 if AutomaticScalingEnabled is false.
  - `defaultFadeTime = 0.3`.
  - [MaximumADHD Animate rewrite gist](https://gist.github.com/MaximumADHD/5eda577a9e0ba4611f3fe2fe6ae72790)
  - Caveat: its run-speed curve `math.max(1, math.log(fadeInRun + 1))` is the author's own variant, not the official one.
- A Creator Store user comment says "default walking speed is 16 and default running speed is 24". This is a user comment, not documentation. — [Creator Store R15 Animate asset](https://create.roblox.com/store/asset/10708027363/R15-Animate-Script-with-proper-running-walking)
- Official docs show driving a Blend1D idle→run node with `MoveDirection.Magnitude * WalkSpeed` against `MaxSpeed = WalkSpeed`. — [creator-docs animation/expressions.md](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/animation/expressions.md)
- Humans switch from walking to running at a Froude number (v²/gL) of about 0.5. — [Wikipedia – Transition from walking to running](https://en.wikipedia.org/wiki/Transition_from_walking_to_running) (search summary, citing Alexander 1977 and Hreljac 1995)

### Inferences
- **Formula** [D]:
  - Step length: `s = 2·L·sin θ`
  - Stance time: `t_stance = s / v`
  - Cycle period: `T = s / (β·v)` (β = 0.5 for a symmetric sine swing, so `T = 2s/v`). Step time is T/2.
  - Required speed for a given cycle: `v = s / (β·T)`.
- **No-slide table, L = 2 studs, v = 16 studs/s** [D]:

| ±θ | Step s (studs) | T @β=0.5 (s) | T @β=0.6 walk (s) | T @β=0.35 run (s) |
|---|---|---|---|---|
| 15° | 1.035 | 0.129 | 0.108 | 0.185 |
| 20° | 1.368 | 0.171 | 0.143 | 0.244 |
| 25° | 1.690 | 0.211 | 0.176 | 0.302 |
| 30° | 2.000 | 0.250 | 0.208 | 0.357 |
| 35° | 2.294 | 0.287 | 0.239 | 0.410 |
| 40° | 2.571 | 0.321 | 0.268 | 0.459 |
| 45° | 2.828 | 0.354 | 0.295 | **0.505** |
| 50° | 3.064 | 0.383 | 0.319 | 0.547 |
| 60° | 3.464 | 0.433 | 0.361 | 0.619 |

- **Other speeds** [D], at β = 0.5 and ±30°: 8 studs/s → T = 0.50 s; 12.8 → 0.31 s; 20 → 0.20 s; 24 → 0.167 s. At ±45°: 8 → 0.71 s; 24 → 0.24 s.
- **Matching a "natural" 1.0 s walk cycle** [D] (β = 0.6) needs only v = 2.3 studs/s at ±20°, 3.3 at ±30° and 4.7 at ±45°. That is about 0.9–1.3 m/s at 28 cm/stud. **The default 16 studs/s is a run for R6 proportions**, not a walk.
- **Froude check** [D]:
  - With game gravity 196.2: Fr = 16² / (196.2 × 2) = 0.65 (> 0.5, so a run).
  - With "real-scale" gravity (9.81 m/s² ÷ 0.28 m = 35 studs/s²): Fr = 3.65, a fast run.
  - The walk→run transition for a 2-stud leg falls at about 14.0 studs/s with game gravity, or about 5.9 studs/s at real scale.
  - [R] Author a true walk only for speeds of about 8 studs/s or less. At 16 studs/s, use a jog or run with flight.
- **Recommended default for WalkSpeed 16** [R, built on D]:
  - Run cycle T ≈ 0.5 s (0.25 s per step).
  - Legs: contact at +40–45° forward, toe-off at −40–45° back.
  - Stance lasts 35% of the cycle, about 0.175 s, with a fast backward sweep. Swing lasts 65%, about 0.33 s, coming forward.
  - Flight: 2 × 15% of the cycle.
  - Root bob 0.3–0.6 studs: low at contact/down, high in flight.
  - The resulting leg motion is asymmetric, not a pure sine.
- **Stance-leg easing** [D]: to keep the foot fixed while the hip moves at constant v, the stance-leg angle (forward positive, from +θ at contact) must follow φ(t) = asin(sin θ − v·t / L), which is close to linear. Use **Linear** easing on the stance segment (contact → toe-off). Use **Cubic InOut** on the swing segment and on the arms.
- **Roblox's own legacy run slid** [D]: ±57.3° at ω = 9 rad/s gives T = 2π/9 = 0.698 s and s = 3.37 studs. The no-slide speed at β = 0.5 is 9.6 studs/s, against the actual 16, so the feet covered about 60% of ground speed. Players accepted roughly 40% slip in the classic look.
- **R6 playback rule** [D]:
  - The default R6 walk plays at speed/14.5, so 1.10× at WalkSpeed 16. It was authored to look right at about 14.5 studs/s.
  - **Custom R6 walk IDs are NOT speed-scaled by the stock R6 Animate script**, because of the asset-ID check. A custom R6 walk/run plays at 1× at every speed. Either author it for the game's exact WalkSpeed using the table above, or modify `onRunning` to call `AdjustSpeed(speed / authoredSpeed)`.
- **R15 playback rule** [D]: with heightScale 1, the walk clip is "native" at 6.4 studs/s and the run clip at 12.8 studs/s. At WalkSpeed 16 the run plays at 1.25×.
- **Authoring rule for a skill** [R]: store each locomotion clip's authored speed, `v_authored = 2·L·sinθ / (β·T)`. Then set `track:AdjustSpeed(currentSpeed / v_authored)`, clamped to about 0.5–1.5× to avoid unnatural tempo.

### Gaps
- I could not read the current official R15 Animate source directly (DevForum and the Roblox site are blocked). The 0.75 threshold and 1.25 factor come from search summaries plus the community rewrite.
- I could not read the current (post-2015) official R6 Animate source. The speed/14.5 rule is from an archived copy and may have changed.
- I don't know the stride angle or period of default walk asset 180426354, so I could not compute its own no-slide speed.
- I found no sourced duty-factor values for human running (0.35 is my assumption). Search only confirmed that swing and stance durations become nearly equal near the walk→run transition.

---

## Q4. Jump: anticipation, takeoff, rise, apex, fall, landing, and Roblox Humanoid states

### Takeaway
The classical jump has a slow, deep crouch, a fast stretched takeoff, a parabolic rise with slow spacing at the apex, a fast fall, a deep landing compression and a slower recovery. A Roblox jump, however, applies its impulse immediately on input. At default settings the character reaches its apex in about 0.26–0.27 s and lands about 0.51–0.54 s after takeoff. The stock Animate plays a "jump" clip for 0.3 s, then fades into a looping "fall" clip, and has no landing animation. A pre-takeoff anticipation crouch therefore cannot be keyed without delaying input. Landing compression has to be added on the Landed state.

### Cited Findings
- **Classical phases** (search summaries of jump tutorials):
  - Crouch (anticipation): deep. A shallow crouch makes the jump look underpowered.
  - A longer crouch gives "more upward acceleration".
  - The takeoff frame is the most stretched pose and "the fastest moment".
  - Horizontal motion is linear. Vertical motion is "a bell curve, with gravity slowing the rise and speeding the fall".
  - Crouch and landing get more frames; takeoff and fall are quick.
  - A typical jump is about 12–18 frames (hobbyist figure, fps unspecified).
  - After landing, the character goes into a recovery that absorbs recoil.
  - [AnimStarter – How to animate a jump](https://www.animstarter.com/post/how-to-animate-a-jump); [Pixnote – animate a jump](https://pixnote.net/en/learn/animate-jump/); [Endless Reference – Jump breakdown](https://endlessreference.com/article/16); [Takuan (note.com) – jumps and landings](https://note.com/tkyhgsanimation/n/n76d130a18c60?hl=en); [Harry Jenkins – jump animation](https://harryjenkinsgamesdesign.wordpress.com/2021/03/10/jump-animation/)
- **Roblox physics** [S]:
  - JumpPower defaults to 50 (range 0–1000). JumpHeight defaults to 7.2 studs; which one applies depends on `UseJumpPower`. — [creator-docs Humanoid.yaml](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/classes/Humanoid.yaml)
  - Workspace.Gravity defaults to 196.2 studs/s². — [creator-docs Workspace.yaml](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/classes/Workspace.yaml)
- **Humanoid states** [S]:
  - `Jumping`: "The Humanoid just jumped… This state lasts only briefly", then transitions to Landed (if on the ground) or Freefall.
  - `Freefall`: "jumped from a height or fell off a ledge".
  - `Landed`: "touched the ground after a Freefall. This state lasts only briefly."
  - [creator-docs HumanoidStateType.yaml](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/enums/HumanoidStateType.yaml)
- **R6 Animate jump/fall logic** [S]:
  - `jumpAnimDuration = 0.3` and `fallTransitionTime = 0.3`.
  - `onJumping()` plays "jump" with a 0.1 s fade and sets jumpAnimTime = 0.3.
  - In FreeFall, once jumpAnimTime ≤ 0, it plays "fall" with a 0.3 s fade.
  - Defaults: jump 125750702, fall 180436148.
  - [MechaXYZ copy of Animate (raw)](https://raw.githubusercontent.com/MechaXYZ/VSBScripts/main/ROBLOX%20Animation%20Script)
  - Another copy found by search has `jumpAnimDuration = 0.175` and `fallTransitionTime = 0.2`, so versions differ. — [glot.io snippet](https://glot.io/snippets/gsyg6dx90m) (via search summary)
- The community R15-style rewrite plays "jump" if Freefall begins within 0.4 s of the Jumping event, otherwise "fall", with a 0.1 s fade. — [MaximumADHD Animate rewrite gist](https://gist.github.com/MaximumADHD/5eda577a9e0ba4611f3fe2fe6ae72790)
- Legacy procedural jump/freefall pose: both arms straight up (3.14 rad) and legs straight (0), with limb max velocity 0.75. — [old-roblox-animation script (raw)](https://raw.githubusercontent.com/cambam239053cam/old-roblox-animation/main/script)
- *Game Anim* on responsiveness:
  - Slower actions can still feel responsive "if part of the character visibly reacts to the command right away".
  - The animator should pick the frame where the player regains control, so the follow-through can finish when no new input comes.
  - [Game Anim excerpt (dokumen.pub)](https://dokumen.pub/game-anim-video-game-animation-explained-2nbsped-9781000357806-1000357805.html) (via search summary)

### Inferences
- **Default jump numbers** [D] (h = v²/2g, t_apex = v/g):
  - JumpPower 50: apex 6.37 studs, t_apex = 0.255 s, airtime on flat ground 0.510 s.
  - JumpHeight 7.2: v0 = √(2·196.2·7.2) = 53.2 studs/s, t_apex = 0.271 s, airtime 0.542 s.
- **Apex hang** [D]: on a parabola, the top 10% of the height takes 0.632·t_apex, which is ~0.16–0.17 s or about 31% of total airtime. The "apex hang" is already in the physics. The pose only needs to stay quiet (a moving hold) during that window.
- The stock 0.3 s jump clip ≈ time to apex [D]. So the jump clip should be authored as takeoff stretch → rise, arriving at the apex pose at about 0.25–0.3 s. The looping fall clip covers the apex hold and the descent.
- **Recommended R6 jump set** [R], in seconds, frame-rate independent:
  - **Anticipation:** none before the impulse, or ≤ 0.05 s on Jumping if input-delay is unacceptable. Fake it instead with a 1–2 frame squash pose at t = 0 of the jump clip: root −0.3 studs, arms back −20 to −30°, torso pitch +10°.
  - **Takeoff (0–0.06 s):** stretch. Legs straight, one leg trailing −15 to −25°, arms whip up to +120 to +170°, torso slight back-arch. Ease: **Out** (fast start).
  - **Rise (0.06–0.25 s):** tuck the leading leg forward +30 to +45°, arms start to settle. Ease: InOut.
  - **Apex / fall loop (Freefall):** arms up and out +100 to +150°, legs split ±15–25°, with a slow 0.6–1.0 s flail loop of amplitude ±5–10°.
  - **Landing (add on `Landed` via `Humanoid.StateChanged`), Action priority:**
    - Compression 0.05–0.1 s: root −0.4 to −0.6 studs (the legs can't bend, so drop the root and splay the legs ±15–20°), arms flung down/forward, torso pitch +15–25°.
    - Recovery 0.15–0.3 s with **Out** easing and a slight overshoot of the root above neutral (+0.05 studs) before settling.
    - Total 0.2–0.4 s. Make it cancellable into run or walk after about 0.1 s so control isn't lost.
- Scale the landing compression with impact speed [R]. Roughly: root dip ∝ min(1, |v_y| / 60). A fall from apex lands at about 50–53 studs/s.

### Gaps
- I found no authoritative per-phase frame split for jumps. The 12–18 frame total is from a hobbyist article with unspecified fps.
- I did not read the current official Roblox Animate (R6 or R15) to confirm today's jump/fall durations. The two archived copies conflict (0.3/0.3 versus 0.175/0.2).

---

## Q5. Idle: breathing, weight shift, secondary motion, avoiding a frozen look, seamless loops

### Takeaway
An idle needs visible breathing on a 3–4 s period with very small amplitude, plus slow lateral weight shift. Loops run 2–4 s for a simple idle and 8–12 s with weight shift. It must loop with no pop at the seam, and it needs variants or "cycle breakers" because a single loop becomes noticeable after about 90 s. Roblox's stock idle picks among weighted variants (9:1 for R6).

### Cited Findings
- **MoCap Online idle guides:**
  - Loop 2–4 s for a simple breathing idle, 8–12 s for a cycle with weight shift and subtle movement.
  - Resting breathing about 15–20 breaths/min, with 1–2 cm of vertical travel "no more".
  - A standing loop without visible breathing reads as "a frozen statue".
  - Weight shift is subtle lateral pelvis movement; without it characters look "rigidly frozen".
  - Any visible pop at the loop point "breaks immersion every time the cycle repeats".
  - A single loop is noticeable after about 90 s, so use a base loop plus alternates.
  - Idles must be interruptible at any moment, with feet kept close to other animations for clean blends.
  - [MoCap Online – Idle Animation for Games](https://mocaponline.com/blogs/mocap-news/idle-animation-game-dev-guide); [MoCap Online – Idle animation loop](https://mocaponline.com/blogs/mocap-news/idle-animation-loop)
- A hobbyist tutorial used a 2 s loop and recommends 2–4 s, with shorter loops for more energetic breathing. — [Cai Dampier – Creating an Idle Cycle](https://caidampiergamesdesign.wordpress.com/2021/02/04/creating-an-idle-cycle/). A Quora answer suggests a loop of about 2–4 breaths. — [Quora – idle length](https://www.quora.com/How-long-should-an-idle-animation-be-for-a-video-game)
- Secondary motion such as hair, cloth and blinks keeps characters alive without large movement. — [itch.io pixel idle tutorial](https://itch.io/t/2489389/pixel-tutorial-hero-idle-animation)
- Cooper describes "cycle breakers": random bursts of incidental motion during the idle loop. Don't overdo the fidgeting. — secondary source via search summary ([ResearchGate – Study of Idle Animation in Video Games](https://www.researchgate.net/publication/361309980_Making_Characters_more_Alive_Study_of_Idle_Animation_in_Video_Games))
- **Roblox:**
  - The R6 default idle has two variants, 180435571 (weight 9) and 180435792 (weight 1). — [Animate copy (raw)](https://raw.githubusercontent.com/MechaXYZ/VSBScripts/main/ROBLOX%20Animation%20Script)
  - The Animate script "randomly chooses which one to play" using weight / total weight. — [creator-docs animation/using.md](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/animation/using.md)
  - In the R6 script, when a keyframe named "End" is reached, `playAnimation(repeatAnim, 0.0)` is called again, which re-rolls the weighted choice. — [Animate copy (raw)](https://raw.githubusercontent.com/MechaXYZ/VSBScripts/main/ROBLOX%20Animation%20Script)
  - `AnimationPriority.Idle` is the recommended priority for idles. The order is Core < Idle < Movement < Action < Action2 < Action3 < Action4. — [creator-docs AnimationPriority.yaml](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/enums/AnimationPriority.yaml)
- The legacy procedural idle swung arms and legs with amplitude 0.1 rad at frequency 1 rad/s. — [old-roblox-animation script (raw)](https://raw.githubusercontent.com/cambam239053cam/old-roblox-animation/main/script)

### Inferences
- **Breath period** [D]: 60/20 to 60/15 gives 3–4 s. Real amplitude of 1–2 cm is 0.036–0.071 studs.
- **Legacy idle** [D]: ±5.7° at 1 rad/s is a 6.28 s period.
- **R6 idle defaults** [R]:
  - **Breathing:** root/torso Y +0.03 to +0.08 studs, plus torso pitch −1 to −2° (chest rises) on the inhale. Arms rotate 1–3° outward (roll) on the inhale. The head counters by about half the torso pitch.
  - **Timing:** inhale about 40% and exhale about 60% of the breath. Use Cubic InOut easing.
  - **Weight shift:** root X ±0.05–0.15 studs plus torso roll ±1–3° on a 4–8 s period. Legs counter-rotate so the feet stay planted (rigid legs: hip roll ≈ −torso roll).
  - **Loop length:** an integer multiple of every component's period, for example 8 s = 2 breaths + 1 weight shift + 3 head micro-turns. The first pose must equal the last pose.
  - **Phase offsets:** stagger the parts (torso leads, arms lag 0.1–0.3 s, head lags 0.2–0.4 s) so nothing moves in robotic unison.
  - **Variants:** at least one cycle-breaker variant of 2–5 s (look around, stretch, shrug), weighted roughly 1:5 to 1:10 against the base.
- **Seamless-loop check** [R]: compare frame 0 and the last frame for every joint, and check that tangents match. With Cubic InOut on both end keys the velocity is zero at the seam, which is acceptable for breathing but causes a visible "stall" in faster loops. Use Linear through the seam for continuously moving channels.

### Gaps
- There are no academic or primary sources for loop lengths. The numbers are blog-level and vary.
- The ~90 s repetition threshold is a single-source claim.
- I did not get the actual keyframe content of Roblox's default idle (angles and period).

---

## Q6. Hit reactions, knockdowns, deaths and get-ups

### Takeaway
Reactions snap in instantly (no blend) to an extreme pose thrown away from the force, then recover slowly ("fast in, slow out"). Standard hits run about 10–25 frames, and staggers 2–3× longer. Deaths and knockdowns either play a short authored reaction and then blend to ragdoll over about 0.1–0.3 s, or play a full authored fall. Get-ups wait until the body has settled, then blend over about 0.4–0.8 s.

### Cited Findings
- A game-dev guide (search summary; attribution likely [Combat Recall – Reaction animations](http://combatrecall.blogspot.com/2018/05/reaction-animations-reaction-animations.html), unverified) says:
  - Standard hits "commonly use 10–25 frames". Stagger/stumble reactions use "double or even triple the frame count".
  - Snap into the reaction: a standard "blend time of 3–6 frames can make responses feel sluggish".
  - Most games snap the character's facing to match the hit location on impact.
- Fighting-game reference: one knockdown hurt animation lasts 14 frames, and weak hits reset it to frame 1. A tech window after landing has its fastest option at 26 frames. — [Dragdown – RoA2 Knockdown](https://dragdown.wiki/wiki/RoA2/System_Mechanics/Knockdown); background on hitstun: [Critpoints – Stunning Detail: Hitstun in Depth](https://critpoints.net/2016/08/14/stunning-detail/)
- Indie feedback: reactions that are too fast and too short make it hard for players to read timing. — [itch.io feedback thread](https://itch.io/post/6366042) (via search summary; exact post unverified)
- Cooper: "A common game animation problem is we're afraid to push timing far enough, leaving motions weak and floaty." — [Jonathan Cooper on X (@GameAnim)](https://twitter.com/GameAnim/status/969611403584655360)
- **Ragdoll handoff:**
  - An abrupt animation-to-physics switch looks bad. Use a blend window, ramping the physics weight from 0 to 1 over about 0.1–0.3 s, then apply the death impulse to the pelvis or the hit bone. Ragdolls can react to the killing blow's direction. — [MoCap Online – Ragdoll physics](https://mocaponline.com/blogs/mocap-news/ragdoll-physics-animation-guide)
  - Play a short hit or death animation first, then blend into ragdoll. — [Rambod – UE5 ragdoll death](https://rambod.net/tutorial/ue5-ragdoll-death)
- **Get-ups:**
  - Ragdoll has no stand-up animation. Reposition the controller and pick a get-up pose, or the body snaps back. — [Opsive – Ragdoll ability](https://opsive.com/support/documentation/ultimate-character-controller/character/abilities/included-abilities/ragdoll/)
  - Wait until physics has settled, then play the get-up. — [Urho3D forum](https://discourse-urho3d.github.io/t/blend-animations-with-ragdolls/5938/)
  - Get-up blend about 0.4–0.8 s, plus a short immunity window to prevent chained knockdowns. — [raduacg – ragdoll blending notes](https://github.com/raduacg/game-mechanics-optimizations/blob/main/117_ragdoll_blending.md); [deadgamestudio issue](https://github.com/deadgamestudio/manif/issues/2)
  - One project's target is "upright within 0.5 s of coming to rest" (project-specific). — [ae3d issue #859](https://github.com/aether-lang-dev/ae3d/issues/859)
- Roblox's legacy Animate treated the poses "Dead", "GettingUp", "FallingDown", "Seated" and "PlatformStanding" by stopping all animations and applying a 0.1 rad sway. — [Animate copy (raw)](https://raw.githubusercontent.com/MechaXYZ/VSBScripts/main/ROBLOX%20Animation%20Script)
- *Game Anim*: games often return to idle too early. Add a long tail to the end of an animation and let the player exit at a set frame if new input arrives. — [Game Anim excerpt (dokumen.pub)](https://dokumen.pub/game-anim-video-game-animation-explained-2nbsped-9781000357806-1000357805.html) (via search summary)

### Inferences
- **Frame conversion** [D]: 10–25 frames is 0.33–0.83 s at 30 fps, or 0.17–0.42 s at 60 fps. The source doesn't give fps. [R] Treat a light hit as about 0.3–0.5 s and a stagger as about 0.8–1.5 s.
- **R6 hit-react template** [R], with the force direction d in torso space:
  1. **Impact (0–0.05 s, Constant or Linear easing):** snap to the extreme.
     - Torso pitches/rolls away from d by 10–25°. Root shifts 0.2–0.5 studs along d.
     - Head whips 1.3–1.5× further than the torso, lagging 1 frame.
     - Arms fly toward the side opposite the hit by 20–60°. The leg on the hit side lifts 10–20°.
  2. **Hold/hitstop:** 0.03–0.1 s (moving hold, ≤ 5% drift).
  3. **Recovery (0.25–0.6 s, Out easing):** return to neutral with a 5–10% overshoot past neutral toward the attacker, then settle.
  4. **Exit:** allow cancel into locomotion at about 60% of recovery.
- **Directional set** [R]: front, back, left and right variants (4) cover most needs. A strong hit can add a step: shift the root 0.5–1 stud and swing one leg back.
- **Knockdown** [R]:
  1. Launch 0.1–0.2 s: Action priority, or PlatformStand/Physics plus a velocity impulse.
  2. Airborne: physics.
  3. Ground impact: 1–2 bounces, each about half the previous height and about 70% of its duration.
  4. Settle 0.3–0.5 s, then lie at rest for 0.3–1.0 s.
  5. Get-up 0.6–1.2 s, ending exactly on the idle pose. Blend 0.2–0.4 s into idle.
- **Gravity for falls** [D]: a free fall of the torso centre from 3 studs takes √(2·3/196.2) = 0.175 s under game gravity, against 0.41 s at "real-scale" gravity (35 studs/s²). Physics-driven R6 collapses therefore look very fast. [R] An authored death fall should take 0.4–0.8 s (toppling plus impact), with a 0.1–0.2 s reaction before it and a 0.3–0.6 s settle after ("fast in, slow settle").

### Gaps
- I found no authoritative frame-count standard for game hit reactions. The figures are from blogs and fighting-game wikis.
- I found no source specific to R6 or Roblox for hit-react timing.
- I found no numeric guidance on bounce or settle damping for deaths.

---

## Q7. The 12 principles adapted to rigid parts

### Takeaway
The 12 principles come from Johnston and Thomas (*The Illusion of Life*, 1981). On a rigid six-part rig, squash and stretch cannot deform parts. It has to come from root dips and rises, limb splay, timing contrast, small joint translations and effects. The other principles map directly onto joint rotation, root offset, phase offsets and easing.

### Cited Findings
- The twelve principles were introduced by Ollie Johnston and Frank Thomas in *The Illusion of Life: Disney Animation* (1981). Their main purpose is to make characters appear to follow basic laws of physics, while also covering emotional timing and appeal. — [Wikipedia – Twelve basic principles of animation](https://en.wikipedia.org/wiki/Twelve_basic_principles_of_animation) (via search summary)
- Definitions found:
  - Squash and stretch gives "a sense of weight and/or flexibility".
  - Anticipation "prepares the viewer for an action".
  - Timing determines how fast or slow motions occur.
  - Straight-ahead action gives fluid, dynamic movement suited to realistic action. Pose-to-pose suits dramatic or emotional scenes.
  - Sources: [Wikipedia](https://en.wikipedia.org/wiki/Twelve_basic_principles_of_animation); paraphrases of Thomas and Johnston pp. 47–69 at [Brian Lemay – 12 basic principles](https://www.brianlemay.com/Pages/animationschool/animation/lipsyncbook/principlesindex.html), [WKU 12 principles](https://people.wku.edu/joon.sung/edu/anim/3d/animation/principles.html) and [Adobe – principles of animation](https://www.adobe.com/creativecloud/animation/discover/principles-of-animation.html)
- Overshoot holds and pushing the overshoot pose "taken up a notch". — [Animation Mentor – moving hold](https://www.animationmentor.com/blog/why-all-animators-need-to-master-the-moving-hold/)
- Push timing harder to avoid "weak and floaty" motion. — [Cooper on X](https://twitter.com/GameAnim/status/969611403584655360)
- Motor6D joints carry a CFrame `Transform` (position plus rotation) between C0 and C1. — [Motor6D reference](https://create.roblox.com/docs/reference/engine/classes/Motor6D) (via search summary); `Motor6D.Transform` is mentioned in [creator-docs task-scheduler.md](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/performance-optimization/microprofiler/task-scheduler.md)

### Inferences
Each principle below is [R] unless marked.

1. **Squash & stretch.** CFrames carry no scale, so parts can't deform through joints [D: CFrame = position plus rotation]. Substitutes:
   - Squash: root dip of 0.2–0.6 studs, legs splayed ±10–20°, torso pitched forward, arms in.
   - Stretch: root rise, legs together and straight, arms overhead.
   - Optionally offset limbs out of their sockets by 0.1–0.3 studs along the limb axis for 1–3 frames on fast actions (a "smear" stretch).
   - Exaggerate the speed contrast between squash and stretch poses.
2. **Anticipation.** A reverse move before the action, about 1/3–1/2 the size of the main move and lasting 0.1–0.3 s. For player-input actions such as jumps and attacks, keep it ≤ 0.1 s or put it into the first frames of the action (see Q4).
3. **Staging.** Silhouette matters doubly on blocky rigs. Separate the arms from the torso (≥ 15–20° away) and avoid poses where limbs overlap the torso from the main camera angle. Turn the torso 10–30° toward the camera or target in actions.
4. **Straight-ahead vs pose-to-pose.** Use pose-to-pose for authored clips (keys at extremes, then breakdowns). Use straight-ahead or procedural methods (springs, physics) for secondary motion and ragdolls.
5. **Follow-through & overlap.** With no soft parts, create overlap by offsetting the timing of child parts: torso leads, head lags 1–3 frames at 30 fps, arms lag 2–4 frames, and each overshoots 5–15% past rest before settling.
6. **Slow in/slow out.** Use Cubic InOut on extremes. Use Linear through constant-velocity phases such as the stance leg and loop seams (see Q3 and Q8).
7. **Arcs.** Rigid limbs about a fixed pivot already move on arcs. Hand and foot paths are circles of radius 1.5 and 2 studs. Add root translation so the overall body path arcs (bob plus lateral sway) instead of moving linearly.
8. **Secondary action.** Head look-arounds, breathing in the arms during idle, tool sway, accessory physics. Keep it to about 30% or less of the primary amplitude so it doesn't compete.
9. **Timing.** Use the tables in Q1 and Q3, and prefer fewer, more contrasted keys. Fast parts should be about 2–4 frames at 30 fps; holds and settles 0.2–0.6 s.
10. **Exaggeration.** Blocky proportions tolerate about 1.3–1.5× realistic angles: leg swing ±40–60° in runs, arm swing up to ±60–90°, and bigger root dips. The legacy Roblox run used ±57°.
11. **Solid drawing / posing.** Avoid "twinning", where both arms or both legs share the same angle. Always break symmetry with ±5–15° differences between left and right and some torso roll or yaw. Keep the centre of mass over the support foot in static poses.
12. **Appeal.** Clear silhouettes, strong lines of action (torso pitch and roll aligned with the limb arcs), a consistent "personality" amplitude set, and snappy timing contrast.

### Gaps
- I could not read the original *Illusion of Life* definitions directly, only paraphrases.
- I found no published source that adapts the 12 principles to rigid "block" rigs. The rigid-rig substitutes above are my inference.

---

## Q8. Timing charts and spacing: favouring keys, ease in/out, holds, moving holds, overshoot and settle; easing per action type

### Takeaway
Spacing (easing) carries the weight. Use slow-in/slow-out on extremes, linear spacing through constant-velocity phases, fast-out starts for strikes and impacts, moving holds instead of dead holds, and overshoot-and-settle with roughly halving oscillations. Roblox's Animation Editor works at 30 fps by default and offers Linear, Constant, CubicV2, Elastic and Bounce easing, each with In, Out and InOut directions.

### Cited Findings
- **Roblox Animation Editor:**
  - The timeline is "seconds:frames" and "animations run at 30 frames per second" by default (for example 0:15 = ½ s).
  - Easing styles: Linear (constant speed), Constant (no interpolation, which gives a hold or pop), CubicV2 (cubic ease), Elastic (rubber band), Bounce.
  - Easing directions:
    - **In**: slower at the beginning, faster toward the end. This is the default.
    - **Out**: faster at the beginning, slower toward the end.
    - **InOut**: In at the start, Out after halfway.
  - [creator-docs animation/editor.md](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/animation/editor.md)
- **Moving holds:** a held pose still needs life. An "overshoot hold" zips past the destination and recovers into the pose. A "long ease-in hold" is a slow, subtle approach into the key pose. The overshoot pose should be the key pose "taken up a notch". — [Animation Mentor – Master the Moving Hold](https://www.animationmentor.com/blog/why-all-animators-need-to-master-the-moving-hold/)
- **Overshoot and settle:** many actions go slightly past their final position and then settle back. — [LinkedIn Learning – Overshoot and settle](https://www.linkedin.com/learning/21-foundations-of-animation/overshoot-and-settle). Settling behaves like a decaying spring. As a rule of thumb, each stage halves in amplitude and takes a couple of frames less than the previous one (a heuristic). Flat tangents mean holds; steep slopes mean speed. — [Sunstrike Studios – Timing in Animation](https://sunstrikestudios.com/en/blog/timing_in_animation/)
- "Ease out back" starts fast and overshoots the target slightly before settling. — [Figma – easing and spring animations](https://help.figma.com/hc/en-us/articles/360051748654-Prototype-easing-and-spring-animations)
- Terminology differs between tools (per-key versus per-move easing), so it is safer to say "slow start / slow finish". — [Mixos – easing explained](https://www.mixos.io/learn/animation-easing-explained)

### Inferences
- **Easing per action type** [R], using Roblox direction semantics (In = slow start, Out = slow finish):

| Action / channel | Roblox style + direction | Notes |
|---|---|---|
| Walk/run swing leg, arms, root bob | CubicV2 InOut | Pendulum-like, close to a sine |
| Stance leg (contact → toe-off) | Linear | Keeps the foot planted at constant speed [D, Q3] |
| Loop seam on continuously moving channels | Linear (or matched tangents) | Avoids a stall at the loop point |
| Anticipation into crouch | CubicV2 InOut (or Out) | Settle into the wind-up |
| Strike, takeoff, hit impact | Out (or Linear) into the extreme, 1–3 frames @30 fps | Fast start; the "snap" |
| Recovery after a strike or hit | Out with an overshoot key, or Elastic Out for cartoony | Slow settle |
| Landing compression | Linear in, Out on recovery | Impact is abrupt; recovery decelerates |
| Pops, camera cuts, sprite-like poses | Constant | Stepped, "on twos" look |
| Bouncy props or cartoon settles | Bounce Out | Use sparingly on characters |

- **Favouring** [R]: a breakdown placed at 1/3 or 2/3 between two keys, instead of half-way, favours one key. That produces ease without curve edits and is a reliable default for a generator: favour the destination for decelerating moves and the source for accelerating moves.
- **Moving hold** [R]: during a hold of 0.3–1.0 s, drift 2–5% further along the same direction, plus a breath-sized secondary motion. Never use a zero-motion hold longer than about 0.2–0.3 s on a character in play.
- **Overshoot & settle recipe** [D/R] for a move of size A arriving at time t:
  - Overshoot +0.1–0.2·A at t + 2–4 frames (30 fps).
  - Undershoot −0.05–0.1·A about 2–3 frames later.
  - Settle at t + 6–10 frames, about 0.2–0.33 s total, with each oscillation half the previous one.
- **Converting chart frames** [D]: Roblox's editor defaults to 30 fps, so 24 fps classical charts scale by 30/24 = 1.25. Storing times in seconds (Q1 table) avoids this entirely.

### Gaps
- I found no source that gives per-action easing tables for game animation. The table above is inference built on the classical principles plus Roblox's easing semantics.
- Whether Roblox's "CubicV2" matches a standard cubic Bézier or Penner cubic is not documented in the files read.
