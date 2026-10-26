# The R6 rig: anatomy, joint math, and the quirks that shape every pose

Read this when you need to reason about *why* a pose looks the way it does, write raw
CFrames by hand (Luau that edits Poses directly), or debug a rig. The spec format hides
all of this, but the quirks below decide what is even possible on R6.

Sources: four independent R6 rig dumps on GitHub (Adonis, RigConverter, Fleasion, a 2018
Roblox avatar-editor model) agree to the digit; Roblox's own `AdaptInstance.lua`
(avatar unification code) gives the same values; official docs (creator-docs repo) for
Motor6D/Pose semantics.

## Parts

| Part | Size (studs) | Notes |
|---|---|---|
| HumanoidRootPart | 2×2×1 | Invisible, not animated (no root motion on R6). Centre 3 studs above the soles. |
| Torso | 2×2×1 | Moved by RootJoint. Centre coincides with HRP at rest. |
| Head | 2×1×1 | Has a SpecialMesh (Head, scale 1.25) so it *looks* like a ~1.2 stud block. |
| Left/Right Arm | 1×2×1 | Centre at x = ±1.5, same height as torso centre. |
| Left/Right Leg | 1×2×1 | Centre at x = ±0.5, y = −2 relative to torso centre. |

Humanoid.HipHeight is 0 on R6 (legs set the height). Default WalkSpeed 16, JumpPower 50.

## Joints (Motor6D) — exact defaults

`Part1.CFrame = Part0.CFrame * C0 * Transform * C1:Inverse()`. Animations write
**Transform** (= `Pose.CFrame`); C0/C1 never change. RootJoint lives in HumanoidRootPart,
the other five in Torso (Part0 = Torso).

| Motor6D | Part0 → Part1 | C0 | C1 |
|---|---|---|---|
| RootJoint | HRP → Torso | `0,0,0, -1,0,0, 0,0,1, 0,1,0` | same as C0 |
| Neck | Torso → Head | `0,1,0, -1,0,0, 0,0,1, 0,1,0` | `0,-0.5,0, -1,0,0, 0,0,1, 0,1,0` |
| Right Shoulder | Torso → Right Arm | `1,0.5,0, 0,0,1, 0,1,0, -1,0,0` | `-0.5,0.5,0, 0,0,1, 0,1,0, -1,0,0` |
| Left Shoulder | Torso → Left Arm | `-1,0.5,0, 0,0,-1, 0,1,0, 1,0,0` | `0.5,0.5,0, 0,0,-1, 0,1,0, 1,0,0` |
| Right Hip | Torso → Right Leg | `1,-1,0, 0,0,1, 0,1,0, -1,0,0` | `0.5,1,0, 0,0,1, 0,1,0, -1,0,0` |
| Left Hip | Torso → Left Leg | `-1,-1,0, 0,0,-1, 0,1,0, 1,0,0` | `-0.5,1,0, 0,0,-1, 0,1,0, 1,0,0` |

(Format: `CFrame.new(x,y,z, R00,R01,R02, R10,R11,R12, R20,R21,R22)`.) Naming wrinkle: rigs built by Studio's importer may call the root motor `Root Hip` instead of `RootJoint`. Animations don't care (poses match joints by *part* names), but scripts that look joints up by name do. Readable forms:
shoulders/hips = translation × `CFrame.Angles(0, ±π/2, 0)`; Neck/RootJoint = translation ×
`CFrame.Angles(-π/2, 0, π)`.

## Raw Pose.CFrame axes (only if you write CFrames by hand)

Because the joint frames are rotated, a raw `CFrame.Angles` on a Pose does **not** rotate
about the character's axes. Derived from the C0 matrices and cross-checked against the
legacy Animate script (which held tools with `RightShoulder:SetDesiredAngle(1.57)` and
walked with the *same* angle on both shoulders, giving opposite swings):

| Pose | Raw rotation | Effect |
|---|---|---|
| Right Arm / Right Leg | `Angles(0,0,+a)` | swings **forward** |
| Left Arm / Left Leg | `Angles(0,0,+a)` | swings **backward** (mirrored frame) |
| either arm/leg | `Angles(-a,0,0)` | raises sideways (out) |
| Right limb `Angles(0,+a,0)` / Left limb `Angles(0,+a,0)` | | twists inward / outward |
| Head (Neck) | `Angles(+a,0,0)` / `(0,0,+a)` / `(0,+a,0)` | nod down / turn left / tilt left |
| Torso (RootJoint) | `Angles(+a,0,0)` / `(0,0,+a)` / `(0,+a,0)` | bow forward / turn left / tilt left |
| Torso translation | `CFrame.new(x,y,z)` | +x = left, +y = **back**, +z = **up** |

That last row is the famous one: in raw R6 Pose space the Torso's "up" is **+Z**, so a
crouch is `CFrame.new(0, 0, -d)`. The general formula the converter uses:
`Pose.CFrame = C0.Rotation:Inverse() * (Offset * R_body) * C0.Rotation`, where `R_body`
is the rotation you want expressed in the parent part's (character) axes.

## Pivot quirks → what's possible

These are geometry facts of the default rig, and every R6 animator works around them:

1. **No waist.** RootJoint rotates the torso *and* everything attached (head, arms, legs)
   around the torso centre. Leaning forward swings the legs backward and lifts a foot.
   → Counter-rotate the hips (the spec's `plant: true` does it exactly and pivots at the hips).
2. **Shoulder pivot is at the arm's inner edge, 0.5 studs below its top.** Any sideways
   raise (`out`) rotates the top 0.5 studs of the arm *into* the torso — unavoidable and
   accepted in R6. Worse: raising an arm overhead with `out` (~150–180) swings it **into
   the head**. → To raise an arm overhead, use `forward` (≈160–180) with a little `out`;
   the arm stays beside the head.
3. **Arms are rigid 2-stud blocks.** Crossing arms in front of the chest or clapping
   requires inward `out` that sinks the upper arm into the torso. → Keep inward `out` small
   (≥ −15°) and let torso twist carry "across the body" motion; hands meeting in front of
   the chest is not cleanly possible.
4. **Hip pivot is at the leg's outer top corner** (x = ±1, y = −1). Forward/back swings are
   clean; spreading (`out`) rotates around the outer edge. Raising a leg ~90° sinks its top
   into the torso slightly — normal.
5. **Rigid legs can't shorten.** A leg at angle A from vertical has its foot 2·(1−cos A)
   studs higher. To keep feet on the floor the body must drop at contact (0.12 studs at
   ±20°, 0.27 at ±30°, 0.59 at ±45°). This is the R6 walk "bob" and also the only way to
   crouch: **splay legs + drop the body** (spec: `ground: true`).
6. **The swing leg can't clear the floor.** At passing, a straight swinging leg reaches
   below the floor when the stance leg is angled. Accept it (floors hide it) or add
   5–10° of `out` to the swing leg around passing.
7. **HumanoidRootPart is not animated.** Dashes, lunges and knockbacks need the script to
   move the character; the animation only moves the body relative to the HRP
   (Torso `forward/up/right`, a few studs at most).

## Tool grip

R6 tools attach with a `RightGrip` Weld: Part0 = Right Arm, Part1 = Handle,
C0 = `CFrame.new(0,-1,0, 1,0,0, 0,0,1, 0,-1,0)` (bottom of the arm, rotated −90° about X),
C1 = `Tool.Grip`. The default "tool hold" pose is the right arm at `forward: 90`.
Attachments: `RightGripAttachment` / `LeftGripAttachment` at (0,−1,0) on the arms.

## Other facts

- Death: `Humanoid.BreakJointsOnDeath` (default true) and `RequiresNeck` (true) — a
  death animation needs `BreakJointsOnDeath = false` to play, or play it before the
  Humanoid dies.
- Body-scale values are R15-only. Whether `Model:ScaleTo` scales animation translations on
  an R6 Humanoid is undocumented — test if you scale characters.
- R15 "Avatar Joint Upgrade" (AnimationConstraint joints) is R15-only; R6 still uses Motor6D.
- R15 animation ids do nothing on R6 (poses are keyed by part names: R15 `UpperTorso`,
  `LeftUpperArm`… vs R6 `Torso`, `Left Arm`…). The reverse also fails.
