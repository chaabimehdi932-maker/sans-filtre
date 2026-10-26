# Roblox R6 rig anatomy and joint math

Research date: 2026-10-26. Network note: create.roblox.com and devforum.roblox.com were blocked for direct fetch in this session. Official docs were therefore read from their source repo (`Roblox/creator-docs`, the auto-generated YAML that create.roblox.com renders) through raw.githubusercontent.com. Rig values were read straight from four independent `.rbxmx` R6 rig dumps on GitHub. A parser and a pure-Python CFrame verifier were run over them. DevForum content is cited only from search-result snippets, and is marked that way.

Source key (each one fetched raw; the create.roblox.com equivalent is in brackets):
- DOC-Motor6D = https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/classes/Motor6D.yaml [https://create.roblox.com/docs/reference/engine/classes/Motor6D]
- DOC-Joint = https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/classes/JointInstance.yaml
- DOC-Weld = https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/classes/Weld.yaml
- DOC-Motor = https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/classes/Motor.yaml
- DOC-Pose = https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/classes/Pose.yaml
- DOC-Humanoid = https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/classes/Humanoid.yaml
- DOC-Animator = https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/classes/Animator.yaml
- DOC-AnimConstraint = https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/classes/AnimationConstraint.yaml
- DOC-StarterPlayer = https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/classes/StarterPlayer.yaml
- DOC-Model = https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/classes/Model.yaml
- DOC-Tool = https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/classes/Tool.yaml
- DOC-CFrame = https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/datatypes/CFrame.yaml
- DOC-AvatarUnif = https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/enums/AvatarUnificationMode.yaml
- DOC-Characters = https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/characters/index.md
- DUMP-Adonis = https://raw.githubusercontent.com/Epix-Incorporated/Adonis/HEAD/MainModule/Server/Dependencies/Assets/RigR6.rbxmx
- DUMP-RigConverter = https://raw.githubusercontent.com/RadiatedExodus/RigConverter/HEAD/src/RigConverter/R6_Rig.rbxmx
- DUMP-Fleasion = https://raw.githubusercontent.com/fleasion/Fleasion/HEAD/src/fleasion/cache/tools/animpreview/R6RIG.rbxmx
- DUMP-Morpher2018 = https://raw.githubusercontent.com/suscersal/roblox-studio-web/HEAD/content/avatar/morpherEditorR6.rbxmx (a Roblox-authored avatar-editor preview model, from a mirrored ~2018 client `content/` folder)
- GEAR-Animate2 = https://raw.githubusercontent.com/Roblox/gear/HEAD/src/gear/85879465/src/LocalScript/Animate2.client.luau (official `Roblox` GitHub org; legacy R6 joint-angle Animate script)
- GEAR-Grip = https://raw.githubusercontent.com/Roblox/gear/HEAD/src/gear/127506257/src/EventsAndAnims/MotorizeRightGrip.server.luau; https://raw.githubusercontent.com/Roblox/gear/HEAD/src/gear/86494914/src/SwordScript.server.luau; https://raw.githubusercontent.com/Roblox/gear/HEAD/src/gear/302502491/src/SwordScript/DeathEffect/Functions.luau
- CORE-EmoteUtility = https://raw.githubusercontent.com/EliCauvert/Roblox-Datamining/HEAD/InExperience/PatchRoot/DataModelInstances/CorePackages/Packages/_Index/Thumbnailing/Thumbnailing/EmoteUtility.luau (Roblox's own CorePackages Thumbnailing code, decompiled by a third-party datamining repo: the logic is Roblox's, the variable names are the decompiler's)
- HEADFOLLOW = https://raw.githubusercontent.com/CarlDV/InfiniteYieldPluginStore/HEAD/plugins/1301938690775580746/mfly.lua (a copy of the widely shared "head follows camera" snippet with R6 and R15 branches)

---

## 1. Part names, sizes, and HRP height / HipHeight

### Takeaway
A default R6 rig has 7 BaseParts. Torso and HumanoidRootPart are 2×2×1. Head is 2×1×1 with a SpecialMesh (Head type, scale 1.25). Each arm and leg is 1×2×1. HumanoidRootPart (HRP) sits on Torso's exact CFrame, with its centre 3 studs above the soles. That follows from the docs' R6 formula Height = LeftLeg.Size.Y + 0.5·RootPart.Size.Y + HipHeight = 2 + 1 + 0, and default R6 HipHeight is 0.

### Cited Findings
- Part table. The same values appear in DUMP-Adonis, DUMP-RigConverter, DUMP-Fleasion and DUMP-Morpher2018 ([Adonis](https://raw.githubusercontent.com/Epix-Incorporated/Adonis/HEAD/MainModule/Server/Dependencies/Assets/RigR6.rbxmx), [RigConverter](https://raw.githubusercontent.com/RadiatedExodus/RigConverter/HEAD/src/RigConverter/R6_Rig.rbxmx), [Fleasion](https://raw.githubusercontent.com/fleasion/Fleasion/HEAD/src/fleasion/cache/tools/animpreview/R6RIG.rbxmx), [Morpher2018](https://raw.githubusercontent.com/suscersal/roblox-studio-web/HEAD/content/avatar/morpherEditorR6.rbxmx)):

  | Part (exact Name) | Size (X,Y,Z) | Centre relative to Torso, rest pose | Rig-builder flags (Adonis/RigConverter/Fleasion) |
  |---|---|---|---|
  | `HumanoidRootPart` | 2, 2, 1 | (0, 0, 0), same CFrame as Torso | Transparency 1, CanCollide false |
  | `Torso` | 2, 2, 1 | (0, 0, 0) | CanCollide true; Decal "roblox" (Adonis) |
  | `Head` | 2, 1, 1 | (0, 1.5, 0) | CanCollide true; SpecialMesh "Mesh" MeshType=Head(0), Scale 1.25,1.25,1.25; Decal "face" |
  | `Right Arm` | 1, 2, 1 | (+1.5, 0, 0) | CanCollide false |
  | `Left Arm` | 1, 2, 1 | (−1.5, 0, 0) | CanCollide false |
  | `Right Leg` | 1, 2, 1 | (+0.5, −2, 0) | CanCollide false |
  | `Left Leg` | 1, 2, 1 | (−0.5, −2, 0) | CanCollide false |

  The part names contain spaces ("Right Arm", "Left Leg"). The Torso-relative offsets were computed from C0·C1⁻¹ by the verification script (see §2) and match the world positions in DUMP-Fleasion.
- Absolute placement check: in DUMP-Fleasion the rig is at the origin with identity rotation. Legs are centred at y=1 (soles at y=0), Torso and HRP at y=3, Head at y=4.5. Right Arm is at world x=+1.5 and Left Arm at x=−1.5. With identity rotation and the character facing −Z, +X is the character's right ([Fleasion dump](https://raw.githubusercontent.com/fleasion/Fleasion/HEAD/src/fleasion/cache/tools/animpreview/R6RIG.rbxmx)).
- Humanoid in every dump: `HipHeight=0`, `RigType=0` (R6), `BreakJointsOnDeath=true`, `RequiresNeck=true`, `AutomaticScalingEnabled=true`, WalkSpeed 16, JumpPower 50, with an `Animator` child ([Adonis](https://raw.githubusercontent.com/Epix-Incorporated/Adonis/HEAD/MainModule/Server/Dependencies/Assets/RigR6.rbxmx), [RigConverter](https://raw.githubusercontent.com/RadiatedExodus/RigConverter/HEAD/src/RigConverter/R6_Rig.rbxmx), [Fleasion](https://raw.githubusercontent.com/fleasion/Fleasion/HEAD/src/fleasion/cache/tools/animpreview/R6RIG.rbxmx)).
- Official HipHeight semantics: "For R15 rigs, a suitable hip height is preset… The height of the legs is not used… `Height = (0.5 * RootPart.Size.Y) + HipHeight`. For R6 rigs, HipHeight instead describes a relative offset… `Height = LeftLeg.Size.Y + (0.5 * RootPart.Size.Y) + HipHeight`" ([DOC-Humanoid](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/classes/Humanoid.yaml)).
- Humanoid rules for R6: "A basic character rig that uses 6 parts for limbs. The Head part must be attached to a part named Torso, or the Humanoid will die immediately. BodyPart appearances are applied using CharacterMesh objects. Certain properties, such as Humanoid.LeftLeg and Humanoid.RightLeg, only work with R6" ([DOC-Humanoid](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/classes/Humanoid.yaml)). The `Humanoid.LeftLeg`/`RightLeg`/`Torso` properties are tagged Deprecated: "only works with the old R6 rig" (same source).
- The docs state: "While R6 characters also include a HumanoidRootPart, the R6 characters, Model.PrimaryPart is set to the Head part" ([DOC-Humanoid](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/classes/Humanoid.yaml)).
- Modern R6 `Animate` LocalScript default animation IDs, as stored in DUMP-Adonis: idle Animation1 = 180435571, idle Animation2 = 180435792, walk = 180426354, run = 180426354, jump = 125750702, climb = 180436334, toolnone = 182393478, fall = 180436148, sit = 178130996 ([Adonis dump](https://raw.githubusercontent.com/Epix-Incorporated/Adonis/HEAD/MainModule/Server/Dependencies/Assets/RigR6.rbxmx)).

### Inferences
- Standing R6 dimensions (part boxes, not counting the 1.25× head mesh): soles at 0, hip line and Torso bottom at 2, HRP and Torso centre at 3, shoulder pivots at 3.5, Torso top and neck pivot at 4, Head centre at 4.5, top of the Head part at 5. A converter can place a standing R6 by setting HRP.CFrame = CFrame.new(groundPoint + Vector3.new(0, 3, 0)) * yaw.
- Changing HipHeight on R6 offsets the stand height relative to the 3-stud baseline, per the doc formula. Default 0 means legs exactly touch the ground.

### Gaps
- The docs say R6 PrimaryPart = Head. Live R6 player characters were not tested here. Treat it as doc-stated but unverified for current spawns.
- No official Roblox-hosted `.rbxm` of the default R6 character was retrievable. The four dumps come from third-party repos (one is a Roblox-authored 2018 client content file). They agree exactly on sizes and joints, so confidence is high.

---

## 2. Default Motor6D C0/C1, Part0/Part1, and parent of each joint

### Takeaway
All six Motor6Ds have C0 and C1 with the same rotation. Torso is parented to HRP via RootJoint; every other joint is a child of Torso. The values below were read from the XML in three rig-builder-style dumps plus the 2018 Roblox morpher model, and all four agree to the digit (signed zeros "-0" ignored).

### Cited Findings
- Exact values (x, y, z, R00, R01, R02, R10, R11, R12, R20, R21, R22), identical in [Adonis](https://raw.githubusercontent.com/Epix-Incorporated/Adonis/HEAD/MainModule/Server/Dependencies/Assets/RigR6.rbxmx), [RigConverter](https://raw.githubusercontent.com/RadiatedExodus/RigConverter/HEAD/src/RigConverter/R6_Rig.rbxmx), [Fleasion](https://raw.githubusercontent.com/fleasion/Fleasion/HEAD/src/fleasion/cache/tools/animpreview/R6RIG.rbxmx) and [Morpher2018](https://raw.githubusercontent.com/suscersal/roblox-studio-web/HEAD/content/avatar/morpherEditorR6.rbxmx):

  | Motor6D Name | Parent instance | Part0 | Part1 | C0 | C1 |
  |---|---|---|---|---|---|
  | `RootJoint` | HumanoidRootPart | HumanoidRootPart | Torso | 0, 0, 0, −1, 0, 0, 0, 0, 1, 0, 1, 0 | 0, 0, 0, −1, 0, 0, 0, 0, 1, 0, 1, 0 |
  | `Neck` | Torso | Torso | Head | 0, 1, 0, −1, 0, 0, 0, 0, 1, 0, 1, 0 | 0, −0.5, 0, −1, 0, 0, 0, 0, 1, 0, 1, 0 |
  | `Right Shoulder` | Torso | Torso | Right Arm | 1, 0.5, 0, 0, 0, 1, 0, 1, 0, −1, 0, 0 | −0.5, 0.5, 0, 0, 0, 1, 0, 1, 0, −1, 0, 0 |
  | `Left Shoulder` | Torso | Torso | Left Arm | −1, 0.5, 0, 0, 0, −1, 0, 1, 0, 1, 0, 0 | 0.5, 0.5, 0, 0, 0, −1, 0, 1, 0, 1, 0, 0 |
  | `Right Hip` | Torso | Torso | Right Leg | 1, −1, 0, 0, 0, 1, 0, 1, 0, −1, 0, 0 | 0.5, 1, 0, 0, 0, 1, 0, 1, 0, −1, 0, 0 |
  | `Left Hip` | Torso | Torso | Left Leg | −1, −1, 0, 0, 0, −1, 0, 1, 0, 1, 0, 0 | −0.5, 1, 0, 0, 0, −1, 0, 1, 0, 1, 0, 0 |

  All have `DesiredAngle=0` and `MaxVelocity=0.100000001` (float32 0.1).
- The legacy Animate script finds the joints by these exact names under Torso: `waitForChild(Torso, "Right Shoulder")`, `"Left Shoulder"`, `"Right Hip"`, `"Left Hip"`, `"Neck"` ([GEAR-Animate2](https://raw.githubusercontent.com/Roblox/gear/HEAD/src/gear/85879465/src/LocalScript/Animate2.client.luau)).
- Roblox's own R15Migrator plugin keeps an R6 name table containing "Right Shoulder", "Left Shoulder", "Right Hip", "Left Hip", "Neck", "HumanoidRootPart", "Left Arm", "Right Arm", "Left Leg", "Right Leg", plus the R6 attachment names ([R6Info.luac.s, MaximumADHD/Roblox-Client-Tracker](https://raw.githubusercontent.com/MaximumADHD/Roblox-Client-Tracker/HEAD/BuiltInPlugins/R15Migrator/Src/Util/ScriptAnalysis/R6Info.luac.s)).
- The R15 counterpart for comparison: "The LowerTorso is connected to the HumanoidRootPart by a motor named 'Root'" ([DOC-Pose](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/classes/Pose.yaml)). R6's root motor is named `RootJoint`, not `Root` (dumps above).

### Inferences
These were checked numerically with `/tmp/claude-0/-home-user-sans-filtre/a3833fc5-4745-5ce5-9172-4208dc86a930/scratchpad/scripts/verify_r6.py` (a session scratch script, not a web source), which does Roblox-convention CFrame algebra (CFrame.Angles = Rx·Ry·Rz, per DOC-CFrame):
- The rotation parts decompose exactly as follows. They are handy for writing the defaults readably:
  - RootJoint C0 = C1 = `CFrame.Angles(-math.pi/2, 0, math.pi)`. This equals `CFrame.Angles(math.pi/2, math.pi, 0)` and the community form `CFrame.Angles(3*math.pi/2, 0, math.pi)`. The matrix [[−1,0,0],[0,0,1],[0,1,0]] is its own inverse.
  - Neck C0 = `CFrame.new(0,1,0) * CFrame.Angles(-math.pi/2, 0, math.pi)`. C1 = `CFrame.new(0,-0.5,0) * CFrame.Angles(-math.pi/2, 0, math.pi)`.
  - Right Shoulder C0 = `CFrame.new(1,0.5,0) * CFrame.Angles(0, math.pi/2, 0)`. C1 = `CFrame.new(-0.5,0.5,0) * CFrame.Angles(0, math.pi/2, 0)`.
  - Left Shoulder C0 = `CFrame.new(-1,0.5,0) * CFrame.Angles(0, -math.pi/2, 0)`. C1 = `CFrame.new(0.5,0.5,0) * CFrame.Angles(0, -math.pi/2, 0)`.
  - Right Hip C0 = `CFrame.new(1,-1,0) * CFrame.Angles(0, math.pi/2, 0)`. C1 = `CFrame.new(0.5,1,0) * CFrame.Angles(0, math.pi/2, 0)`.
  - Left Hip C0 = `CFrame.new(-1,-1,0) * CFrame.Angles(0, -math.pi/2, 0)`. C1 = `CFrame.new(-0.5,1,0) * CFrame.Angles(0, -math.pi/2, 0)`.
- Because C0.Rotation == C1.Rotation for every joint, an identity Transform leaves Part1 with the same orientation as Part0. Rest positions (Part1 centre in Part0 space) come out as: Torso (0,0,0) in HRP; Head (0,1.5,0); Right Arm (1.5,0,0); Left Arm (−1.5,0,0); Right Leg (0.5,−2,0); Left Leg (−0.5,−2,0). These match the dumps.
- Pivot points, i.e. the C0 origin in Part0 space, which is the same physical point as the C1 origin in Part1 space:
  - RootJoint: centre of HRP, which is also the centre of Torso.
  - Neck: Torso (0,1,0), the top centre of Torso. In the Head it is (0,−0.5,0), the bottom centre.
  - Right Shoulder: Torso (1,0.5,0), on Torso's right side face, 0.5 below its top. In the arm it is (−0.5,0.5,0), on the arm's inner face, 0.5 below the arm's top. The pivot is therefore on the inner edge of the arm, not its centreline.
  - Left Shoulder: Torso (−1,0.5,0). In the arm it is (0.5,0.5,0).
  - Right Hip: Torso (1,−1,0), Torso's bottom-right edge. In the leg it is (0.5,1,0), the leg's outer top edge.
  - Left Hip: Torso (−1,−1,0). In the leg it is (−0.5,1,0), the outer top edge.
- Copy-paste Lua defaults (exact, from the table above):
  ```lua
  local R6 = {
    RootJoint          = {Part0="HumanoidRootPart", Part1="Torso",     Parent="HumanoidRootPart",
      C0=CFrame.new(0,0,0, -1,0,0, 0,0,1, 0,1,0),   C1=CFrame.new(0,0,0, -1,0,0, 0,0,1, 0,1,0)},
    Neck               = {Part0="Torso", Part1="Head",      Parent="Torso",
      C0=CFrame.new(0,1,0, -1,0,0, 0,0,1, 0,1,0),   C1=CFrame.new(0,-0.5,0, -1,0,0, 0,0,1, 0,1,0)},
    ["Right Shoulder"] = {Part0="Torso", Part1="Right Arm", Parent="Torso",
      C0=CFrame.new(1,0.5,0, 0,0,1, 0,1,0, -1,0,0), C1=CFrame.new(-0.5,0.5,0, 0,0,1, 0,1,0, -1,0,0)},
    ["Left Shoulder"]  = {Part0="Torso", Part1="Left Arm",  Parent="Torso",
      C0=CFrame.new(-1,0.5,0, 0,0,-1, 0,1,0, 1,0,0), C1=CFrame.new(0.5,0.5,0, 0,0,-1, 0,1,0, 1,0,0)},
    ["Right Hip"]      = {Part0="Torso", Part1="Right Leg", Parent="Torso",
      C0=CFrame.new(1,-1,0, 0,0,1, 0,1,0, -1,0,0),  C1=CFrame.new(0.5,1,0, 0,0,1, 0,1,0, -1,0,0)},
    ["Left Hip"]       = {Part0="Torso", Part1="Left Leg",  Parent="Torso",
      C0=CFrame.new(-1,-1,0, 0,0,-1, 0,1,0, 1,0,0), C1=CFrame.new(-0.5,1,0, 0,0,-1, 0,1,0, 1,0,0)},
  }
  ```

### Gaps
- Not checked against a live Roblox Studio session in Oct 2026, because Studio was not available. Four independent files agree, including a Roblox-authored one, so the risk is low. The dumps contain float noise only in attachment positions (0.600000024) and signed zeros (−0), and none in C0/C1.

---

## 3. Motor6D composition formula, Transform, Animator, and Pose.CFrame

### Takeaway
The working relation is `Part1.CFrame = Part0.CFrame * C0 * Transform * C1:Inverse()`. Equivalently, `Part0.CFrame * C0 * Transform == Part1.CFrame * C1`. Transform is a hidden, non-replicated CFrame. The Animator overwrites it every frame with the blended Pose.CFrame of each playing track, and C0/C1 are never changed by animation. Legacy Motor angles add a further `CFrame.Angles(0,0,CurrentAngle)` after Transform. The official docs state only the static weld form (`part1.CFrame * C1 == Part0.CFrame * C0`) and the Transform semantics. The full formula with Transform is confirmed by Roblox's own CorePackages code and by DevForum answers.

### Cited Findings
- Weld base relation, official: "While the weld is Active, it maintains the part positions such that: `part1.CFrame * C1 == Part0.CFrame * C0`" ([DOC-Weld](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/classes/Weld.yaml)).
- C0/C1 doc text: C0 "Determines how the offset point is attached to Part0"; C1 is "Subtracted from the C0 property to create an offset point for Part1"; "When animating a Motor6D, it's recommended to tween its Transform property instead of C0/C1" ([DOC-Joint](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/classes/JointInstance.yaml)). On root behaviour: "when C0/C1 of a JointInstance is modified, the root part will stay where it was" (same source).
- Motor6D.Transform, official: "The internal CFrame that is manipulated when a Motor6D is being animated. It is recommended to use this property for custom animations rather than C0 and C1." On timing: "Motor6D transforms are not applied immediately, unlike updating C0 and C1, but rather as a batch in a parallel job after RunService.PreSimulation, immediately before physics steps." On the Animator: "If the Motor6D is part of an animated model with an Animator, then Motor6D.Transform will usually be overwritten every frame by the Animator after RunService.PreAnimation and before RunService.PreSimulation." The tags are Hidden and NotReplicated, and serialization is can_save: false ([DOC-Motor6D](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/classes/Motor6D.yaml)).
- Motor6D.ChildName/ParentName are read-only mirrors of Part1.Name/Part0.Name. "The animation system uses this name to match the joint against the corresponding pose channel in an animation, so a rig's part names must line up with the names authored in its animations" ([DOC-Motor6D](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/classes/Motor6D.yaml)).
- Pose mapping, official: "Although a Pose is assigned to a BasePart by name, the object manipulated during animation playback is actually the Motor6D connected to this part… the Pose's CFrame is applied to the motor connecting the part associated with the pose to the part associated with the pose's parent… The Roblox animation system applies Pose.CFrame to the corresponding Motor6D by manipulating the relative transformation of the motor, the Motor6D.Transform property. The original C0 and C1 values are not changed" ([DOC-Pose](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/classes/Pose.yaml)).
- Roblox's own code (CorePackages Thumbnailing/EmoteUtility, decompiled) applies a keyframe statically like this. It recurses over poses, finds `GetJointBetween(parentPosePart, posePart)`, then sets `JointBetween.Transform = Pose.CFrame`. It solves Part1 as `Part1.CFrame = Part.CFrame * Weld.C0 * p6 * Weld.C1:Inverse()`, where `p6 = getJointPose(Motor)`, which returns `Motor.Transform` and, `if Motor.CurrentAngle ~= 0`, `Transform *= CFrame.Angles(0, 0, Motor.CurrentAngle)`. For AnimationConstraint it uses `Part.CFrame * Attachment0.CFrame * p6 * Attachment1.CFrame:Inverse()` ([CORE-EmoteUtility](https://raw.githubusercontent.com/EliCauvert/Roblox-Datamining/HEAD/InExperience/PatchRoot/DataModelInstances/CorePackages/Packages/_Index/Thumbnailing/Thumbnailing/EmoteUtility.luau)).
- DevForum answer (search snippet, not opened): "A motor6D satisfies the following equation: Part0.CFrame * Motor6D.C0 * Motor6D.Transform = Part1.CFrame * Motor6D.C1" ([DevForum t/2415565](https://devforum.roblox.com/t/2415565)). Another thread warns that Transform must be accounted for when doing C0 math on animated rigs ([DevForum t/2564060](https://devforum.roblox.com/t/2564060)).
- Community forward kinematics uses the same chain. For example, `tor = RJ.C0 * RJ.Transform * RJ.C1:Inverse(); armR = tor * RS.C0 * RS.Transform * RS.C1:Inverse()` on R6 RootJoint/Right Shoulder after `animator:StepAnimations` ([gat516/martial-world polearm_guard.luau](https://raw.githubusercontent.com/gat516/martial-world/HEAD/art/player/guard/polearm_guard.luau)). The pattern `j.Part1.CFrame = j.Part0.CFrame * j.C0 * j.Transform * j.C1:Inverse()` also appears in [Indosaram/roblox_forge DinosaurRig.spec.luau](https://raw.githubusercontent.com/Indosaram/roblox_forge/HEAD/genres/survival-coop/module/DinosaurRig.spec.luau).
- Layering procedural motion, official example: "Layer procedural animations by multiplying into Transform during RunService.PreSimulation, which stacks with active animation tracks without breaking retargeting", with `RunService.PreSimulation:Connect(function() if not animator.EvaluationThrottled then neck.Transform = computeNeckRotation() * neck.Transform end end)` ([DOC-AnimConstraint](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/classes/AnimationConstraint.yaml)). `Animator.EvaluationThrottled` "indicates whether animation evaluation was throttled (skipped) on this frame… the Animator reused the pose from the previous frame" ([DOC-Animator](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/classes/Animator.yaml)).
- Legacy Motor API: Motor.DesiredAngle is "The desired angle to turn the motor to in radians". MaxVelocity is "measured in radians per physics frame (1/60th of a second)". CurrentAngle "Displays the current rotation of the motor in radians". `SetDesiredAngle(value)` exists. Motor6D inherits Motor. The docs carry no deprecation message on Motor or on these members as of this fetch ([DOC-Motor](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/classes/Motor.yaml), [DOC-Motor6D](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/classes/Motor6D.yaml)).
- `Humanoid:LoadAnimation` is officially deprecated: "This function is deprecated in favor of using Animator:LoadAnimation() directly (the Animator may be created while editing or at runtime)" ([DOC-Humanoid](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/classes/Humanoid.yaml)). `Animator:LoadAnimation` requires the Animator to be in Workspace, always creates a new track (use `GetTrackByAnimationId` to look one up), and the Animator must be created on the server for replication ([DOC-Animator](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/classes/Animator.yaml)).

### Inferences
- Full effective formula for an R6 Motor6D: `Part1.CFrame = Part0.CFrame * C0 * Transform * CFrame.Angles(0, 0, CurrentAngle) * C1:Inverse()`. CurrentAngle is 0 unless legacy DesiredAngle code moves it. This is taken from CORE-EmoteUtility, which reproduces engine pose evaluation for thumbnails.
- Transform is expressed in the joint frame, the C0 frame. Translations and rotations in Pose.CFrame/Transform use the joint's local axes listed in §4, not the Torso's or the world's.
- R6 KeyframeSequence pose tree, inferred from DOC-Pose's parent-pose rule and the R6 joint graph: `Keyframe > Pose "HumanoidRootPart" > Pose "Torso" > {Pose "Head", "Right Arm", "Left Arm", "Right Leg", "Left Leg"}`. Pose "Torso".CFrame drives `RootJoint`, "Head" drives `Neck`, "Right Arm" drives `Right Shoulder`, and so on. The HumanoidRootPart pose has no joint above it, so its CFrame does nothing.
- For a code generator writing keyframes: Pose.CFrame = the desired Transform (§4 sign table). For one writing C0 directly at runtime: `C0 = DEFAULT_C0 * desiredTransform`. This gives the same pose as Transform when no animation is playing, because C0·T·C1⁻¹ = (C0·T)·I·C1⁻¹.
- Left-multiplying a delta into Transform (`delta * T`, as in the doc example) applies the delta in the joint's base frame. Right-multiplying (`T * delta`) applies it in the already-animated limb frame.

### Gaps
- The full formula with Transform is not written verbatim on any official reference page I could reach. It rests on CORE-EmoteUtility (Roblox code via a third-party decompile), DevForum answers, and consistent community use. The Weld relation and the Transform/Pose descriptions are official.
- Whether the Animator resets Transform to identity on joints that no playing track touches ("usually overwritten") is not specified in the docs.

---

## 4. Joint-frame axes and the sign of each anatomical motion

### Takeaway
Shoulders and hips share one frame layout: joint X = forward (right side) or backward (left side), Y = up along the limb, Z = outward toward the limb's side. Rotating about Z swings the limb forward or back. Positive Z moves the right limb forward and the left limb backward. Rotating about −X raises either limb sideways, with the same sign on both sides. Neck and RootJoint share a different layout: X = character-left, Y = backward, Z = up. +X pitches the head or torso down/forward, +Z turns left, +Y tilts toward the left. Two pieces of evidence back this. The legacy Animate script's sit, jump and walk angles only make sense if positive Right Shoulder angles move the arm forward. The R6 "head follows camera" snippet uses −asin(y) for pitch and Z for yaw, the reverse of R15. An independent numeric check agrees with both.

### Cited Findings
- Legacy R6 Animate (official Roblox gear repo), `moveSit()`: `RightShoulder:SetDesiredAngle(3.14 /2)`, `LeftShoulder:SetDesiredAngle(-3.14 /2)`, `RightHip:SetDesiredAngle(3.14 /2)`, `LeftHip:SetDesiredAngle(-3.14 /2)`. The R6 sit pose has both arms and both legs forward ([GEAR-Animate2](https://raw.githubusercontent.com/Roblox/gear/HEAD/src/gear/85879465/src/LocalScript/Animate2.client.luau)).
- Same script, `moveJump()`/`moveFreeFall()`: `RightShoulder:SetDesiredAngle(3.14)`, `LeftShoulder:SetDesiredAngle(-3.14)`, both hips 0, which puts both arms straight overhead ([GEAR-Animate2](https://raw.githubusercontent.com/Roblox/gear/HEAD/src/gear/85879465/src/LocalScript/Animate2.client.luau)).
- Same script, walk/run: `desiredAngle = amplitude * math.sin(time*frequency)`, then `RightShoulder:SetDesiredAngle(desiredAngle + climbFudge)`, `LeftShoulder:SetDesiredAngle(desiredAngle - climbFudge)`, `RightHip:SetDesiredAngle(-desiredAngle)`, `LeftHip:SetDesiredAngle(-desiredAngle)`. Running uses amplitude 1, frequency 9, MaxVelocity 0.15. Climbing uses climbFudge = 3.14. Idle uses amplitude 0.1, frequency 1 ([GEAR-Animate2](https://raw.githubusercontent.com/Roblox/gear/HEAD/src/gear/85879465/src/LocalScript/Animate2.client.luau)).
- Same script, tool "Lunge": `RightShoulder 1.57, LeftShoulder 1.0, RightHip 1.57, LeftHip 1.0`. Tool "Slash": `RightShoulder 0`. Tool "None" has a commented-out `--RightShoulder:SetDesiredAngle(1.57)`, the classic arm-out-forward tool hold ([GEAR-Animate2](https://raw.githubusercontent.com/Roblox/gear/HEAD/src/gear/85879465/src/LocalScript/Animate2.client.luau)).
- CurrentAngle is applied as `CFrame.Angles(0, 0, CurrentAngle)`, a rotation about the joint frame's Z axis ([CORE-EmoteUtility](https://raw.githubusercontent.com/EliCauvert/Roblox-Datamining/HEAD/InExperience/PatchRoot/DataModelInstances/CorePackages/Packages/_Index/Thumbnailing/Thumbnailing/EmoteUtility.luau)).
- The widely copied head-follow snippet has separate R6 and R15 branches:
  - R15: `Neck.C0 = CFrame.new(0, YOffset, 0) * CFrame.Angles(0, -math.asin(CameraDirection.x), 0) * CFrame.Angles(math.asin(CameraDirection.y), 0, 0)`.
  - R6: `Neck.C0 = CFrame.new(0, YOffset, 0) * CFrame.Angles(3 * math.pi/2, 0, math.pi) * CFrame.Angles(0, 0, -math.asin(CameraDirection.x)) * CFrame.Angles(-math.asin(CameraDirection.y), 0, 0)`.
  - In both, `CameraDirection = HumanoidRootPart.CFrame:toObjectSpace(Camera.CFrame).lookVector` and `YOffset = Neck.C0.Y` ([HEADFOLLOW](https://raw.githubusercontent.com/CarlDV/InfiniteYieldPluginStore/HEAD/plugins/1301938690775580746/mfly.lua)). R6 yaws about Z and pitches with a negated sign; R15 yaws about Y and pitches with a positive sign.
- Roblox CFrame conventions: `CFrame.Angles` ≡ `fromEulerAnglesXYZ` ≡ `fromEulerAngles(rx,0,0) * fromEulerAngles(0,ry,0) * fromEulerAngles(0,0,rz)`. `fromEulerAnglesYXZ` ≡ `fromOrientation` ≡ `Y * X * Z` ([DOC-CFrame](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/datatypes/CFrame.yaml)).

### Inferences
These come from a numeric check (`/tmp/claude-0/-home-user-sans-filtre/a3833fc5-4745-5ce5-9172-4208dc86a930/scratchpad/scripts/verify_r6.py`, Roblox CFrame math on the exact §2 values). The Part0-space convention is +X = character right, +Y = up, −Z = forward (LookVector).

**Joint frame axes, as columns of C0.Rotation expressed in Part0 space:**

| Joint | joint +X | joint +Y | joint +Z |
|---|---|---|---|
| RootJoint (in HRP) | character LEFT (−X) | BACKWARD (+Z) | UP (+Y) |
| Neck (in Torso) | LEFT | BACKWARD | UP |
| Right Shoulder / Right Hip | FORWARD (−Z) | UP | RIGHT/outward (+X) |
| Left Shoulder / Left Hip | BACKWARD (+Z) | UP | LEFT/outward (−X) |

**Numeric results (Transform = rotation about the joint-local axis; points and directions in Part0 space):**
- Right Shoulder, +90° Z: hand end goes from (1.5,−1,0) to (1.5,0.5,−1.5), so the arm points forward and horizontal. Left Shoulder, +90° Z: hand end goes to (−1.5,0.5,+1.5), pointing backward.
- Right Shoulder, +90° X: hand end goes to (−0.5,0,0), across or into the chest. Left Shoulder, +90° X: (0.5,0,0), also across. So −X is outward abduction for both.
- Right Shoulder, +90° Y: front face turns to −X (inward) and the arm centre orbits to (1,·,−0.5). Left Shoulder, +90° Y: front face turns to −X (outward) and the arm orbits backward to (−1,·,+0.5).
- Hips behave the same way. Right Hip +30° Z: foot from (0.5,−3,0) to (0.5,−2.73,−1.0), forward. Left Hip +30° Z: foot to (−0.5,−2.73,+1.0), backward.
- Neck +30° X: face direction (0,−0.5,−0.866), looking down. Neck +30° Z: face (−0.5,0,−0.866), turned left. Neck +30° Y: head top tilts toward −X (left).
- RootJoint +30° X: chest direction (0,−0.5,−0.866) and torso top tilts forward. +30° Z: chest turns left. +30° Y: top tilts left.
- RootJoint Transform translation: Transform.Position (1,0,0) moves the torso to HRP (−1,0,0), left. (0,1,0) moves it to (0,0,+1), backward. (0,0,1) moves it to (0,1,0), up.
- Head-follow snippet check: camera looking up gives face direction (0,+0.5,−0.866), up. Camera looking right gives (+0.5,0,−0.866), right. This confirms the R6 neck signs.

**Converter sign table (Pose.CFrame / Transform; θ in radians, θ > 0):**

| Body part (pose name → joint) | Motion | Transform |
|---|---|---|
| Right Arm → Right Shoulder | swing forward / raise forward (θ=π/2 horizontal, π overhead) | `CFrame.Angles(0, 0, θ)` |
| Right Arm | swing backward | `CFrame.Angles(0, 0, -θ)` |
| Right Arm | raise sideways outward (abduction) | `CFrame.Angles(-θ, 0, 0)` |
| Right Arm | across the chest (adduction) | `CFrame.Angles(θ, 0, 0)` |
| Right Arm | twist: front face turns inward (internal rotation) | `CFrame.Angles(0, θ, 0)` |
| Left Arm → Left Shoulder | swing forward / raise forward | `CFrame.Angles(0, 0, -θ)` |
| Left Arm | swing backward | `CFrame.Angles(0, 0, θ)` |
| Left Arm | raise sideways outward | `CFrame.Angles(-θ, 0, 0)` |
| Left Arm | across the chest | `CFrame.Angles(θ, 0, 0)` |
| Left Arm | twist: front face turns outward (external rotation) | `CFrame.Angles(0, θ, 0)` |
| Right Leg → Right Hip | kick forward (hip flexion) | `CFrame.Angles(0, 0, θ)` |
| Right Leg | swing back | `CFrame.Angles(0, 0, -θ)` |
| Right Leg | leg out to the side | `CFrame.Angles(-θ, 0, 0)` |
| Right Leg | toes turn inward | `CFrame.Angles(0, θ, 0)` |
| Left Leg → Left Hip | kick forward | `CFrame.Angles(0, 0, -θ)` |
| Left Leg | swing back | `CFrame.Angles(0, 0, θ)` |
| Left Leg | leg out to the side | `CFrame.Angles(-θ, 0, 0)` |
| Left Leg | toes turn outward | `CFrame.Angles(0, θ, 0)` |
| Head → Neck | nod down / look down | `CFrame.Angles(θ, 0, 0)` |
| Head | look up | `CFrame.Angles(-θ, 0, 0)` |
| Head | turn to character's left | `CFrame.Angles(0, 0, θ)` |
| Head | turn to character's right | `CFrame.Angles(0, 0, -θ)` |
| Head | tilt (ear toward left shoulder) | `CFrame.Angles(0, θ, 0)` |
| Head | tilt toward right shoulder | `CFrame.Angles(0, -θ, 0)` |
| Torso → RootJoint | bow / lean forward | `CFrame.Angles(θ, 0, 0)` |
| Torso | lean back | `CFrame.Angles(-θ, 0, 0)` |
| Torso | twist / turn to the left | `CFrame.Angles(0, 0, θ)` |
| Torso | twist to the right | `CFrame.Angles(0, 0, -θ)` |
| Torso | side-bend to the left | `CFrame.Angles(0, θ, 0)` |
| Torso | side-bend to the right | `CFrame.Angles(0, -θ, 0)` |
| Torso | move down d studs (crouch) | `CFrame.new(0, 0, -d)` |
| Torso | move forward d | `CFrame.new(0, -d, 0)` |
| Torso | move to character's right d | `CFrame.new(-d, 0, 0)` (`CFrame.new(d,0,0)` moves LEFT) |

- Legacy-script cross-check. Sit (+π/2 R, −π/2 L on both shoulders and hips) gives all four limbs forward. Jump gives both arms overhead (R +π, L −π). Walk gives the right arm forward while the left arm goes back and the right leg goes back (contralateral gait). Lunge gives the right arm and right leg forward 90° and the left arm and left leg back 57°. Each matches the table.
- Mirror rule: for limbs, the Z (pitch) and Y (twist) signs flip between left and right for the same anatomical motion. The X (abduction) sign does not flip.
- R15 contrast (from HEADFOLLOW): the R15 neck frame is axis-aligned with the part, so +X looks up and yaw is about Y. Code ported between rigs inverts pitch and swaps the yaw axis.
- RootJoint rotates about the Torso centre, which is 1 stud above the hips. Legs hang off the Torso via the hips, so a torso bow swings the legs backward and lifts the feet. Grounded poses need compensating hip rotation (hips: opposite Z on the right side) and/or RootJoint translation (−z to lower).

### Gaps
- No official doc states the R6 joint axis conventions in words. The table is derived from exact default CFrames plus math, and corroborated by Roblox's legacy Animate script and a widely used community snippet. Both are behavioural evidence, so confidence is high.
- Whether Studio's Animation Editor shows R6 rotation gizmo values in these same joint-local axes was not verified.

---

## 5. Tool grip (RightGrip, RightGripAttachment) and other default R6 attachments

### Takeaway
R6 attachments all have identity rotation in the default rigs. RightGripAttachment and LeftGripAttachment sit at (0,−1,0), the bottom of each arm. When a Tool is equipped, a Weld named `RightGrip` joins Right Arm (Part0) to the tool's Handle (Part1). Its C0 is `CFrame.new(0, -1, 0, 1, 0, 0, 0, 0, 1, 0, -1, 0)`, which is `CFrame.new(0,-1,0) * CFrame.Angles(-math.pi/2, 0, 0)`, and its C1 is `Tool.Grip`.

### Cited Findings
- Attachment positions are Part-local, with identity rotation in all three rig-builder dumps ([Adonis](https://raw.githubusercontent.com/Epix-Incorporated/Adonis/HEAD/MainModule/Server/Dependencies/Assets/RigR6.rbxmx), [RigConverter](https://raw.githubusercontent.com/RadiatedExodus/RigConverter/HEAD/src/RigConverter/R6_Rig.rbxmx), [Fleasion](https://raw.githubusercontent.com/fleasion/Fleasion/HEAD/src/fleasion/cache/tools/animpreview/R6RIG.rbxmx)):
  - Head: `FaceCenterAttachment` (0,0,0); `FaceFrontAttachment` (0,0,−0.6); `HairAttachment` (0,0.6,0); `HatAttachment` (0,0.6,0). The stored value is 0.600000024, the float32 of 0.6.
  - Torso: `NeckAttachment` (0,1,0); `BodyFrontAttachment` (0,0,−0.5); `BodyBackAttachment` (0,0,0.5); `LeftCollarAttachment` (−1,1,0); `RightCollarAttachment` (1,1,0); `WaistFrontAttachment` (0,−1,−0.5); `WaistCenterAttachment` (0,−1,0); `WaistBackAttachment` (0,−1,0.5).
  - Left Arm: `LeftShoulderAttachment` (0,1,0); `LeftGripAttachment` (0,−1,0).
  - Right Arm: `RightShoulderAttachment` (0,1,0); `RightGripAttachment` (0,−1,0).
  - Left Leg: `LeftFootAttachment` (0,−1,0). Right Leg: `RightFootAttachment` (0,−1,0).
  - HumanoidRootPart: `RootAttachment` (0,0,0).
- Discrepancy: the 2018 Roblox avatar-editor model (DUMP-Morpher2018) puts `RightShoulderAttachment`/`LeftShoulderAttachment` at (0,0.5,0) and has no Grip or Foot attachments. Its HRP is also Anchored and CanCollide, and its limbs are CanCollide true. It is an editor preview model, not a spawn rig ([Morpher2018](https://raw.githubusercontent.com/suscersal/roblox-studio-web/HEAD/content/avatar/morpherEditorR6.rbxmx)). The three newer rig-builder dumps agree with each other on (0,1,0), so they are the ones to trust for current rigs.
- RightGrip values in official Roblox gear code:
  - `Weld.Name = "RightGrip"; Weld.Part0 = rightarm; Weld.Part1 = <Handle>; Weld.C0 = CFrame.new(0, -1, 0, 1, 0, -0, 0, 0, 1, 0, -1, -0); Weld.C1 = v.Grip` (DeathEffect/Functions.luau).
  - A Motor6D replacement grip with `C0 = CFrame.new(0, -1, 0, 1, 0, -0, 0, 0, 1, 0, -1, -0); -- from original right grip` (MotorizeRightGrip.server.luau).
  - A sword script that reads `vCharacter:FindFirstChild('Right Arm'):FindFirstChild('RightGrip')` and sets that same C0 (SwordScript.server.luau), which shows the weld is parented to Right Arm.
  - Sources: [GEAR-Grip ×3](https://raw.githubusercontent.com/Roblox/gear/HEAD/src/gear/302502491/src/SwordScript/DeathEffect/Functions.luau), [MotorizeRightGrip](https://raw.githubusercontent.com/Roblox/gear/HEAD/src/gear/127506257/src/EventsAndAnims/MotorizeRightGrip.server.luau), [SwordScript](https://raw.githubusercontent.com/Roblox/gear/HEAD/src/gear/86494914/src/SwordScript.server.luau).
- `Tool.Grip` "stores the tool's grip properties as a single CFrame… GripUp, GripRight, GripForward, and GripPos" ([DOC-Tool](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/classes/Tool.yaml)).
- Roblox's thumbnail code places a held tool as `Handle.CFrame = RightGripAttachment.Parent.CFrame * RightGripAttachment.CFrame * Grip:Inverse()`. This is a generic, rig-agnostic path ([CORE-EmoteUtility](https://raw.githubusercontent.com/EliCauvert/Roblox-Datamining/HEAD/InExperience/PatchRoot/DataModelInstances/CorePackages/Packages/_Index/Thumbnailing/Thumbnailing/EmoteUtility.luau)).

### Inferences
- The verify script confirms that the RightGrip C0 rotation equals `CFrame.Angles(-math.pi/2, 0, 0)`. On R6 the grip frame is therefore the bottom-centre of the Right Arm, rotated −90° about the arm's X. The handle's Grip frame then hangs off that.
- On R6 the RightGripAttachment has identity rotation, but the engine weld has −90° X. So on R6 the engine evidently does not use `RightGripAttachment.CFrame` alone as C0. CORE-EmoteUtility's attachment formula would give a different handle orientation on an R6 rig with identity-rotated grip attachments. For R6 tool poses, use the RightGrip weld C0 above, not the attachment.

### Gaps
- No official doc lists the RightGrip C0 value. It is consistently hard-coded across many Roblox-authored gear scripts ("from original right grip"), which is strong but indirect evidence.
- It was not determined whether the engine derives the R6 grip from RightGripAttachment plus a fixed rotation or uses a hard-coded constant.

---

## 6. Death, scaling, and R6 vs R15 differences that affect animation

### Takeaway
BreakJointsOnDeath (default true) breaks an R6 character's joints on death, so the rig falls apart. Ragdolls set it to false and swap Motor6Ds for BallSocketConstraints, usually with RequiresNeck=false. R6 has no NumberValue body scaling, which is R15-only. Model:ScaleTo scales geometry and joints, but the docs promise animation joint-offset scaling only for AnimationController rigs. Since 2025–26 the Avatar Joint Upgrade replaces Motor6D with AnimationConstraint on R15 player characters only. R6 avatars "always load as R6 rigs", with Motor6Ds.

### Cited Findings
- BreakJointsOnDeath "Determines whether the humanoid's joints break when in the Dead state. Defaults to true." RequiresNeck: "Allows developers to disable the behavior where a player character dies if the Neck Motor6D is removed or disconnected even momentarily. This property defaults to true" ([DOC-Humanoid](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/classes/Humanoid.yaml)).
- Model:BreakJoints on a player character kills the Humanoid "as it relies on the Neck joint" ([DOC-Model](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/classes/Model.yaml)). RigType mismatch: "if a R15 humanoid's RigType is set to R6, the Humanoid will die as there is no BasePart called Torso connected to a BasePart called Head" ([DOC-Humanoid](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/classes/Humanoid.yaml)).
- DevForum ragdoll practice (search snippets, threads not opened): the accepted answer recommends turning off RequiresNeck and, "instead of entirely destroying your Motor6Ds, just set their enabled properties to false, then enabling the sockets" ([DevForum t/2622110](https://devforum.roblox.com/t/2622110)). Because BreakJointsOnDeath=false, "when we reparent the humanoid, it tries to repair the joints we just destroyed" ([DevForum t/1282308 p2](https://devforum.roblox.com/t/ragdoll-on-death-isnt-working/1282308?page=2)).
- `Animator:ApplyJointVelocities(motors)` "computes relative velocities between the parts and applies them to Motor6D.Part1… doesn't disable or remove the joints for you", which is useful for carrying animated momentum into a ragdoll ([DOC-Animator](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/classes/Animator.yaml)).
- Model:ScaleTo "scales the model, around the pivot location… All geometric properties of descendant Instances will be scaled", including "The length of joints like WeldConstraints, and RopeConstraint". On animation: "The scale factor of a model will be applied to joint offsets of Animations played on an AnimationController under that model, so that animated rigs will correctly play back animations even when scaled". `ScaleTo(x)` then `ScaleTo(1)` restores exactly ([DOC-Model](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/classes/Model.yaml)).
- R15-only scaling: R15 "Can be dynamically rescaled by using special NumberValue objects parented inside of the Humanoid" ([DOC-Humanoid](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/classes/Humanoid.yaml)). `AutomaticScalingEnabled` responds to BodyDepthScale, BodyHeightScale, BodyProportionScale, BodyTypeScale, BodyWidthScale and HeadScale (same source). Community R6 threads describe scaling by hand: multiply Part sizes and Motor6D C0/C1 offsets, then resize accessories (search snippets; [DevForum t/2158226](https://devforum.roblox.com/t/how-do-i-scale-a-r6-character/2158226), [DevForum t/2223049](https://devforum.roblox.com/t/body-scaling-effect-with-r6/2223049)).
- Avatar Joint Upgrade (AJU): "R15 player characters spawn with AnimationConstraints instead of Motor6Ds when StarterPlayer.AvatarJointUpgrade is enabled (the default for new experiences). Code that assumes character joints are Motor6Ds — such as `character:FindFirstChildOfClass("Motor6D")` or `joint:IsA("Motor6D")` — will not find joints on upgraded characters" ([DOC-Motor6D](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/classes/Motor6D.yaml)).
  - AnimationConstraint keeps C0/C1/Part0/Part1 as read-only aliases of Attachment0.CFrame, Attachment1.CFrame, Attachment0.Parent and Attachment1.Parent. Its Transform "works identically to Motor6D.Transform". `IsA("Motor6D")` returns false ([DOC-AnimConstraint](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/classes/AnimationConstraint.yaml)).
  - StarterPlayer.AvatarJointUpgrade: "When disabled, avatars spawn with legacy Motor6Ds… When enabled, avatars spawn with AnimationConstraints and BallSocketConstraints" ([DOC-StarterPlayer](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/classes/StarterPlayer.yaml)).
  - The characters guide says it replaces Motor6D "in every character's joints" without naming the rig type ([DOC-Characters](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/characters/index.md)).
  - A DevForum poster in the AJU beta thread said Roblox has no plan to stop supporting Motor6D-animated rigs (search snippet; [DevForum AJU beta p10](https://devforum.roblox.com/t/studio-beta-avatar-joint-upgrade-enabling-physically-simulated-characters/3266099?page=10)).
- Avatar unification for R6 is retired: every `AvatarUnificationMode` item carries the deprecation "Workspace.AvatarUnificationMode no longer has an effect; R6 avatars always load as R6 rigs." When it was enabled, it had welded invisible R15 adapter MeshParts to R6-named parts ([DOC-AvatarUnif](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/enums/AvatarUnificationMode.yaml)).
- R6 vs R15 joint basics: R6 uses 6 visible parts and R15 uses 15. "R15 rigs have more joints than R6 rigs, making them much more versatile when being animated" ([DOC-Humanoid](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/classes/Humanoid.yaml)). Pose and channel matching is by part name via Motor6D.ChildName/ParentName ([DOC-Motor6D](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/classes/Motor6D.yaml)).

### Inferences
- R6-specific consequences for a pose generator:
  - There are no elbows, knees, wrists or waist. Each limb is one rigid 1×2×1 block, so "bend elbow" requests must map to whole-arm shoulder rotation or be refused.
  - Animations are not interchangeable between rigs, because part names ("Right Arm" vs "RightUpperArm") and joint frames differ.
  - R6 code should still target Motor6D. R6 is not covered by AJU per the docs' wording ("R15 player characters"), and R6 avatars always load as R6 rigs. Defensive code should accept both `Motor6D` and `AnimationConstraint`.
- ScaleTo on an R6 Humanoid model most likely scales part sizes and C0/C1 positions ("all geometric properties"). However, the docs only promise animation-offset scaling for AnimationController rigs. Animation translations, such as RootJoint Transform positions for a crouch, may not scale on a Humanoid-driven R6, so test before relying on it.

### Gaps
- No official statement was found on whether AJU ever applies to R6 characters. The docs consistently say R15, and the official AJU DevForum post (t/4298561) could not be fetched.
- Not verified: whether Model:ScaleTo scales Humanoid-played animation translations on R6, and exactly how it scales Motor6D C0/C1. Docs list WeldConstraint and RopeConstraint as examples, not JointInstance C0/C1.
- The exact death sequence (which joints break, and whether Neck breaks first) was not documented beyond "joints break".

---

## 7. Common gotchas when manipulating R6 joints by code

### Takeaway
Most R6 posing bugs come from six mistakes: replacing C0 instead of composing onto the default; assuming R15 axes (the R6 neck/root X points left, Z is up, and root Y is backward); missing the left/right sign flip on pitch and twist; ignoring off-centre pivots; mis-ordering Euler angles; and fighting the Animator, which overwrites Transform every frame.

### Cited Findings
- Compose, don't replace. The official pattern caches and multiplies (`local originalC0 = neck.C0 … neck.C0 = originalC0 * computeNeckRotation()`) and, on new rigs, multiplies into Transform in PreSimulation ([DOC-AnimConstraint](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/classes/AnimationConstraint.yaml)). Docs recommend Transform over C0/C1 for animation ([DOC-Joint](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/classes/JointInstance.yaml), [DOC-Motor6D](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/classes/Motor6D.yaml)).
- Animator overwrite timing: Transform is "overwritten every frame by the Animator after PreAnimation and before PreSimulation", and Motor6D transforms are applied in a batch after PreSimulation ([DOC-Motor6D](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/classes/Motor6D.yaml)). Skip procedural layering when `animator.EvaluationThrottled` is true ([DOC-Animator](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/classes/Animator.yaml)).
- Replication: Transform is tagged NotReplicated ([DOC-Motor6D](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/classes/Motor6D.yaml)). For character joints Roblox advises: "Instead of setting C0 on the server, use client-side animation evaluation and synchronize data through custom Attributes or UnreliableRemoteEvent" ([DOC-AnimConstraint](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/classes/AnimationConstraint.yaml)).
- Euler order: `CFrame.Angles(rx,ry,rz)` = X·Y·Z product, while `fromEulerAnglesYXZ`/`fromOrientation` = Y·X·Z. `ToEulerAnglesXYZ` angles "are approximate and subject to gimbal lock near pitch angles of ±90 degrees" ([DOC-CFrame](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/datatypes/CFrame.yaml)). The verify script confirms that `Angles(.5,.7,.3) ≠ fromEulerAnglesYXZ(.5,.7,.3)`.
- R6 vs R15 neck code differs in both the yaw axis and the pitch sign ([HEADFOLLOW](https://raw.githubusercontent.com/CarlDV/InfiniteYieldPluginStore/HEAD/plugins/1301938690775580746/mfly.lua)). The community R6 form `CFrame.Angles(3*math.pi/2, 0, math.pi)` is just the default Neck/RootJoint base rotation (verified equal to the dump matrix).
- The "90°-rotated shoulder frame": shoulder and hip C0 = translation × `CFrame.Angles(0, ±math.pi/2, 0)` (§2). Naively writing `C0 = CFrame.new(1,0.5,0) * CFrame.Angles(math.rad(90),0,0)` to "raise the arm forward" therefore rotates about the joint's forward axis and produces sideways or adduction motion. The correct form is `DEFAULT_C0 * CFrame.Angles(0,0,math.rad(90))` (derived in §4).
- Legacy Motor leftovers: DesiredAngle/MaxVelocity still exist on Motor6D (inherited; not marked deprecated) ([DOC-Motor](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/classes/Motor.yaml)). A non-zero CurrentAngle stacks `CFrame.Angles(0,0,CurrentAngle)` after Transform ([CORE-EmoteUtility](https://raw.githubusercontent.com/EliCauvert/Roblox-Datamining/HEAD/InExperience/PatchRoot/DataModelInstances/CorePackages/Packages/_Index/Thumbnailing/Thumbnailing/EmoteUtility.luau)). Default rigs ship with MaxVelocity 0.1 rad per 1/60 s frame ([Adonis dump](https://raw.githubusercontent.com/Epix-Incorporated/Adonis/HEAD/MainModule/Server/Dependencies/Assets/RigR6.rbxmx), [DOC-Motor](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/classes/Motor.yaml)).
- Removing or disabling Neck kills the character unless RequiresNeck=false. The R6 Head must connect to "Torso" ([DOC-Humanoid](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/classes/Humanoid.yaml)).
- Deprecated APIs to avoid in generated code: `Humanoid:LoadAnimation` (use `Animator:LoadAnimation`), `JointInstance.part1` (lowercase), `Model:breakJoints` (lowercase), the `Humanoid.LeftLeg/RightLeg/Torso` R6 properties, `Model:MakeJoints` ("SurfaceType based joining is deprecated"), and `Workspace.AvatarUnificationMode` ([DOC-Humanoid](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/classes/Humanoid.yaml), [DOC-Joint](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/classes/JointInstance.yaml), [DOC-Model](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/classes/Model.yaml), [DOC-AvatarUnif](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/enums/AvatarUnificationMode.yaml)).

### Inferences
- Off-centre pivots (derived from §2):
  - The shoulder pivot is on the arm's inner edge, 0.5 stud below the arm's top. A 90° sideways raise (`Angles(-π/2,0,0)`) therefore puts the arm's centre at Torso y=+1.0, so the arm's top surface sits 0.5 stud above the Torso top.
  - A Y-twist orbits the arm around the Torso's side edge instead of spinning it in place (verify script: arm centre moves from (1.5,·,0) to (1.0,·,−0.5) at +90° Y).
  - The hip pivot is at the leg's outer top edge, so leg abduction also shifts the leg.
- Pose composition order: with `CFrame.Angles(rx, ry, rz)` = Rx·Ry·Rz, the Z rotation is applied in the frame already rotated by X then Y. A converter should build a deterministic product of single-axis rotations in a fixed, documented order rather than packing several intuitive motions into one Angles call. A reasonable choice for limbs is `Angles(0,0,pitch) * Angles(abduct,0,0) * Angles(0,twist,0)`: pitch first in the base frame, then abduct within the pitched frame, then twist about the limb's long axis. Avoid exact ±90° on the middle axis if angles will later be read back with `ToEulerAngles*`, because of gimbal lock.
- Two safe C0 practices. Snapshot default C0s at load, or hard-code the §2 constants, and never read C0 back after your own writes. Prefer Transform plus PreSimulation layering when an Animator is present; otherwise the playing animation's Transform composes on top of your edited C0.
- R6 crouch or sit via RootJoint needs translation in joint space: `CFrame.new(0,0,-d)` lowers the torso. Writing `CFrame.new(0,-d,0)` moves it forward, a frequent R15-habit bug.

### Gaps
- None of the DevForum "R6 arm pointing at mouse" threads could be opened, so no thread-specific shoulder snippet is quoted. The shoulder sign evidence rests on the legacy Animate script and the math above.
- Studio Animation Editor or Moon Animator display conventions for R6 joints were not verified.
