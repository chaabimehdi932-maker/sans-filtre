# Roblox animation asset formats and authoring tools (R6 focus)

Research date: 2026-10-26. Network note: create.roblox.com, devforum.roblox.com and github.com (web UI) were blocked from this environment. Primary sources were therefore read as **raw source files**: the official docs repo `Roblox/creator-docs` (the source of create.roblox.com), the `rojo-rbx/rbx-dom` reflection database and XML spec, and decompiled Studio built-in plugin bytecode from `MaximumADHD/Roblox-Client-Tracker` (`roblox` branch, current build). DevForum content is cited from search-engine summaries of the threads. Where that is the only evidence, the finding says so.

Abbreviations: ACE = Animation Clip Editor, Studio's built-in Animation Editor (internal plugin name `AnimationClipEditor`). KS = KeyframeSequence.

---

## 1. KeyframeSequence / Keyframe / Pose / NumberPose / KeyframeMarker: properties, types, defaults

### Takeaway
A KS is `KeyframeSequence (Loop, Priority, AuthoredHipHeight)` > `Keyframe (Time)` > nested `Pose (CFrame, EasingStyle, EasingDirection, Weight)`, plus optional `KeyframeMarker (Name, Value)` children of a Keyframe. Default values from Studio itself (rbx-dom reflection, Roblox v0.741) are: KS `Loop=true`, `Priority=Action(2)`, `AuthoredHipHeight=2`. Pose defaults are `CFrame=identity`, `EasingStyle=Linear(0)`, `EasingDirection=In(0)`, `Weight=1`. `MaskWeight` and `Weight` are deprecated, and `MaskWeight` is not saved.

### Cited Findings
**Class tree**
- `AnimationClip` (NotCreatable, inherits Instance) is the abstract base. `KeyframeSequence` and `CurveAnimation` both inherit from it — [AnimationClip.yaml](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/classes/AnimationClip.yaml)
- `PoseBase` (NotCreatable) is the base of `Pose` and `NumberPose`. It holds `EasingDirection`, `EasingStyle` and `Weight` — [PoseBase.yaml](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/classes/PoseBase.yaml)

**AnimationClip / KeyframeSequence properties**
- `AnimationClip.Loop` is a `boolean` (serialized). `AnimationTrack.Looped` defaults to this value but can be overwritten — [AnimationClip.yaml](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/classes/AnimationClip.yaml)
- `AnimationClip.Priority` is an `Enum.AnimationPriority` (serialized). `AnimationTrack.Priority` defaults to it — [AnimationClip.yaml](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/classes/AnimationClip.yaml)
- `AnimationClip.Length` is a read-only, NotReplicated `float` and returns 0 until loaded. It is not serialized. `Guid` (`String`) is not serialized, while `GuidBinaryString` (BinaryString) is — [AnimationClip.yaml](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/classes/AnimationClip.yaml); [rbx-dom database.json](https://raw.githubusercontent.com/rojo-rbx/rbx-dom/master/rbx_dom_lua/src/database.json)
- `KeyframeSequence.AuthoredHipHeight` is a `float`, tagged **Hidden**, with read/write security **PluginSecurity**, and it serializes. The docs say "Default value is `1.35` since that is the hip height set for a standard R15 character" — [KeyframeSequence.yaml](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/classes/KeyframeSequence.yaml). **This conflicts with** the rbx-dom reflection default, captured from a live Studio instance: `AuthoredHipHeight = 2.0`, `Loop = true`, `Priority = Enum 2 (Action)`, `GuidBinaryString = "AAAAAAAAAAAAAAAAAAAAAA=="` — [rbx-dom database.json](https://raw.githubusercontent.com/rojo-rbx/rbx-dom/master/rbx_dom_lua/src/database.json). Real files also carry `2`: an R6 walk animation and a 2024+ viewmodel export both have `<float name="AuthoredHipHeight">2</float>` — [R6 anim_walk.rbxmx](https://raw.githubusercontent.com/workspacePWNAGE/Reboot2016/HEAD/corescript-patches/content/pwnsCorescriptPatches/rbxmx/anim_walk.rbxmx); [Karambit_Idle_retarget.rbxmx](https://raw.githubusercontent.com/ThatGuyNamedSkulls/Bot/HEAD/Karambit_Idle_retarget.rbxmx)
- Animation length is defined by "the `Keyframe` with the highest `Time` property" — [KeyframeSequence.yaml](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/classes/KeyframeSequence.yaml)
- KS methods: `AddKeyframe`, `GetKeyframes`, `RemoveKeyframe`. These are just parent/unparent operations and do not type-check — [KeyframeSequence.yaml](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/classes/KeyframeSequence.yaml)

**Keyframe**
- `Keyframe.Time` is a `float`, in seconds, with security None, and it serializes. The rbx-dom default is `0.0` — [Keyframe.yaml](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/classes/Keyframe.yaml); [rbx-dom database.json](https://raw.githubusercontent.com/rojo-rbx/rbx-dom/master/rbx_dom_lua/src/database.json)
- Keyframe names do not need to be unique. Keyframe names fire `AnimationTrack:GetMarkerReachedSignal()` (named keyframes act as events). Methods are `AddPose/GetPoses/RemovePose/AddMarker/GetMarkers/RemoveMarker` — [Keyframe.yaml](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/classes/Keyframe.yaml)
- The ACE's default keyframe name is `"Keyframe"` (`DEFAULT_KEYFRAME_NAME`) — [ACE Constants.luac.s](https://raw.githubusercontent.com/MaximumADHD/Roblox-Client-Tracker/roblox/BuiltInPlugins/AnimationClipEditor/Src/Util/Constants.luac.s). Animations that replace default character animations need the final keyframe renamed `End` (case-sensitive) — [editor.md](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/animation/editor.md)

**Pose / PoseBase**
- `Pose.CFrame` is a `CFrame`. "The Roblox animation system applies `Pose.CFrame` to the corresponding `Motor6D` by manipulating ... the `Motor6D.Transform` property. The original C0 and C1 values are not changed" — [Pose.yaml](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/classes/Pose.yaml)
- `PoseBase.EasingStyle` is a `PoseEasingStyle` and `PoseBase.EasingDirection` is a `PoseEasingDirection`. Both serialize: "The easing style/direction to use to reach the next Pose's value" — [PoseBase.yaml](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/classes/PoseBase.yaml)
- `PoseBase.Weight` is a `float` and serializes. It carries a deprecation message: "This property is deprecated. Use the `AnimationTrack:AdjustWeight()` function when blending multiple animations." It has no description — [PoseBase.yaml](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/classes/PoseBase.yaml). Weight is still written by Studio and is functionally meaningful as a "keyed / not keyed" flag (see section 2).
- `Pose.MaskWeight` is a `float`, tagged **NotReplicated, Deprecated**, with `can_load: true, can_save: false`. rbx-dom marks it `DoesNotSerialize` — [Pose.yaml](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/classes/Pose.yaml); [rbx-dom database.json](https://raw.githubusercontent.com/rojo-rbx/rbx-dom/master/rbx_dom_lua/src/database.json). Old files (pre-2017 format) contain `<float name="MaskWeight">0</float>`, while modern Studio output omits it — [roform fixture ANIMATION - Jump.rbxmx](https://raw.githubusercontent.com/Unreal-Works/roform/HEAD/fixtures/ANIMATION%20-%20Jump.rbxmx) vs [Karambit_Idle_retarget.rbxmx](https://raw.githubusercontent.com/ThatGuyNamedSkulls/Bot/HEAD/Karambit_Idle_retarget.rbxmx)
- Pose defaults (rbx-dom, from Studio): `CFrame` identity, `EasingDirection = Enum 0 (In)`, `EasingStyle = Enum 0 (Linear)`, `Weight = 1.0` — [rbx-dom database.json](https://raw.githubusercontent.com/rojo-rbx/rbx-dom/master/rbx_dom_lua/src/database.json)
- Pose methods: `AddSubPose`, `GetSubPoses` (returns *all* children, including non-Poses), `RemoveSubPose` — [Pose.yaml](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/classes/Pose.yaml)

**NumberPose (facial/FACS)**
- `NumberPose.Value` is a `double` and serializes. The rbx-dom defaults are `Value 0`, `Weight 1`, `EasingStyle 0`, `EasingDirection 0`. NumberPoses "cannot be parented together" and "all must be stored in a `Folder` named **FaceControls** that is a child of the **Head** `Pose`". Values are clamped to 0–1 — [NumberPose.yaml](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/classes/NumberPose.yaml); [rbx-dom database.json](https://raw.githubusercontent.com/rojo-rbx/rbx-dom/master/rbx_dom_lua/src/database.json). (Not relevant to classic R6 heads.)

**KeyframeMarker**
- `KeyframeMarker.Value` is a `string` (default `""`) and serializes. Markers "should always be parented to a Keyframe". Each marker fires an event identified by its **Name** when the keyframe is reached. `Value` is passed to the `GetMarkerReachedSignal(name)` callback. Duplicate names fire once per marker — [KeyframeMarker.yaml](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/classes/KeyframeMarker.yaml); [rbx-dom database.json](https://raw.githubusercontent.com/rojo-rbx/rbx-dom/master/rbx_dom_lua/src/database.json)
- When the ACE loads a KS, it converts `KeyframeMarker`s into its "Events" track and non-default Keyframe names into "NamedKeyframes" — [ACE RigSerialization.luac.s](https://raw.githubusercontent.com/MaximumADHD/Roblox-Client-Tracker/roblox/BuiltInPlugins/AnimationClipEditor/Src/Util/RigSerialization.luac.s) (constants `KeyframeMarker`, `Events`, `NamedKeyframes`, `DEFAULT_KEYFRAME_NAME` in `fromKeyframeSequence`)

**Enum numeric values (token values in XML)**
- `AnimationPriority`: Idle=0, Movement=1, Action=2, Action2=3, Action3=4, Action4=5, Core=1000. Evaluation order from highest priority is Action4 > Action3 > Action2 > Action > Movement > Idle > Core. Default Roblox and catalog animations use Core — [AnimationPriority.yaml](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/enums/AnimationPriority.yaml); [rbx-dom database.json](https://raw.githubusercontent.com/rojo-rbx/rbx-dom/master/rbx_dom_lua/src/database.json)
- `PoseEasingStyle`: Linear=0, Constant=1, Elastic=2, Cubic=3 (deprecated), Bounce=4, CubicV2=5 — [PoseEasingStyle.yaml](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/enums/PoseEasingStyle.yaml)
- `PoseEasingDirection`: In=0, Out=1, InOut=2 — [PoseEasingDirection.yaml](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/enums/PoseEasingDirection.yaml)

### Inferences
- For generated files, write `Loop` and `Priority` explicitly. If either is omitted, Studio's instance default (Loop=true, Priority=Action) applies, which is probably not what a script author expects. For example, the classic R6 jump uses `Loop=false, Priority=1000 (Core)`, and the R6 walk uses `Loop=true, Priority=1 (Movement)`.
- `AuthoredHipHeight` is only relevant for hip-height-adjusted (R15) playback. For R6, writing `2` (what Studio writes) or omitting it is safe. This is an inference, and the runtime effect on R6 is unverified.

### Gaps
- No official documentation of what the engine does with `AuthoredHipHeight` at runtime, or of whether it matters for R6.
- The docs' `1.35` default vs Studio's actual `2.0` default is unresolved. The docs text may be stale.

---

## 2. Pose hierarchy rules, omitted parts, Weight 0, and the R6 joint tree

### Takeaway
Poses must be **named after parts** and **nested along the Motor6D joint tree**. Each Pose's CFrame drives the motor whose Part0 is the parent pose's part and whose Part1 is this pose's part. Parts can be omitted. The ACE itself writes only keyed parts, plus **Weight-0 "placeholder" ancestor poses** that only carry the hierarchy. The ACE ignores Weight-0 poses when loading, so Weight 0 means "no key for this joint at this keyframe". For R6 the tree is `HumanoidRootPart > Torso > {Head, Left Arm, Right Arm, Left Leg, Right Leg}`.

### Cited Findings
- "The poses are named in accordance with the BaseParts they correspond to and are structured in terms of joint hierarchy. This means each Pose is parented to the Pose corresponding to the part it is attached to... animations require distinct part names to play correctly" — [Keyframe.yaml](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/classes/Keyframe.yaml)
- "the Pose's CFrame is applied to the motor connecting the part associated with the pose to the part associated with the pose's parent." Example for R15: a Pose named `LowerTorso` drives the motor named `Root` (HumanoidRootPart→LowerTorso), not the LowerTorso itself — [Pose.yaml](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/classes/Pose.yaml)
- **ACE writer behaviour (decompiled `toKeyframeSequence` helper).** For each keyed track value at a keyframe, the ACE walks the joint path from the root. For every ancestor part without a Pose yet, it does `Instance.new("Pose")`, sets `Weight = 0` and `Name = <part name>` (or creates a `Folder` for FaceControls). For the keyed part it creates or finds the Pose and sets `CFrame = value`, `Name`, `Weight = 1`, `EasingStyle = <style>.Name` and `EasingDirection = <direction>.Name` — [ACE RigSerialization.luac.s, PROTO_8](https://raw.githubusercontent.com/MaximumADHD/Roblox-Client-Tracker/roblox/BuiltInPlugins/AnimationClipEditor/Src/Util/RigSerialization.luac.s)
- **ACE reader behaviour (decompiled `fromKeyframeSequence`).** For each `Pose`/`NumberPose` it first checks `if Name == "HumanoidRootPart"`. That pose is skipped unless the internal flag `getFFlagRootMotion` is on. Then `if pose.Weight == 0 → skip` (no key is created). Otherwise it adds a Quaternion-type track key with `{Value = CFrame (or NumberPose.Value), EasingStyle, EasingDirection}`. Keyframe times are snapped with `getNearestTick` at `TICK_FREQUENCY` 2400 ticks per second, and the defaults used are `Enum.PoseEasingStyle.Linear` and `Enum.PoseEasingDirection.In` — [ACE RigSerialization.luac.s, PROTO_26/28](https://raw.githubusercontent.com/MaximumADHD/Roblox-Client-Tracker/roblox/BuiltInPlugins/AnimationClipEditor/Src/Util/RigSerialization.luac.s); [ACE Constants.luac.s](https://raw.githubusercontent.com/MaximumADHD/Roblox-Client-Tracker/roblox/BuiltInPlugins/AnimationClipEditor/Src/Util/Constants.luac.s) (`DEFAULT_TICK_FREQUENCY = 2400`)
- An official code sample on the KeyframeSequence page builds a `HumanoidRootPart` root pose with `rootPose.Weight = 0` and a child `LowerTorso` pose with `Weight = 1`, then nests them with `rootPose:AddSubPose(lowerTorsoPose)` — [create.roblox.com KeyframeSequence (via search summary)](https://create.roblox.com/docs/reference/engine/classes/KeyframeSequence)
- A real R6 file (Studio-saved, with random UUID referents) shows the R6 nesting `HumanoidRootPart (Weight 0, identity CFrame) > Torso (Weight 1) > Left Leg / Right Leg / Left Arm / Right Arm / Head`, with the full set of seven names in all 22 keyframes, `Priority 1`, `Loop true` — [R6 anim_walk.rbxmx](https://raw.githubusercontent.com/workspacePWNAGE/Reboot2016/HEAD/corescript-patches/content/pwnsCorescriptPatches/rbxmx/anim_walk.rbxmx)
- In the old R6 jump fixture, every keyframe (6 keyframes, times 0–0.7 s) contains all parts with `Weight 1`, including HumanoidRootPart — [roform fixture ANIMATION - Jump.rbxmx](https://raw.githubusercontent.com/Unreal-Works/roform/HEAD/fixtures/ANIMATION%20-%20Jump.rbxmx)
- Track blending is **per joint**. Tracks are evaluated from high to low priority until the weight sum reaches 1 for that joint — [AnimationPriority.yaml](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/enums/AnimationPriority.yaml)
- **R6 Motor6D names and default C0/C1** (from Roblox's own avatar unification code): joints are `RootJoint` (HumanoidRootPart→Torso), `Neck` (Torso→Head), `Right Shoulder`, `Left Shoulder`, `Right Hip`, `Left Hip`. The code comment says "orientation of r6 joints are setup slightly differently from r15 motors". Defaults in that file:
  - `centralRotation = CFrame.Angles(math.pi/2, -math.pi, 0)`, which applies to RootJoint and Neck. Neck C0 = `CFrame.new(0,1,0)*central` and C1 = `CFrame.new(0,-0.5,0)*central`.
  - Right Shoulder C0 = `CFrame.new(1,0.5,0)*Angles(0,π/2,0)` and C1 = `CFrame.new(-0.5,0.5,0)*Angles(0,π/2,0)`.
  - Right Hip C0 = `CFrame.new(1,-1,0)*Angles(0,π/2,0)` and C1 = `CFrame.new(0.5,1,0)*Angles(0,π/2,0)`.
  - The Left side uses `Angles(0,-π/2,0)`, with C0 `(-1,0.5,0)` / `(-1,-1,0)` and C1 `(0.5,0.5,0)` / `(-0.5,1,0)`.

  Source: [Roblox-Client-Tracker avatar/unification/AdaptInstance.lua](https://raw.githubusercontent.com/MaximumADHD/Roblox-Client-Tracker/roblox/avatar/unification/AdaptInstance.lua)
- Numerically, `centralRotation` = rows `[-1,0,0],[0,0,1],[0,1,0]`, which is the familiar R6 `RootJoint` C0 `CFrame.new(0,0,0,-1,0,0,0,0,1,0,1,0)`. `Angles(0,π/2,0)` = rows `[0,0,1],[0,1,0],[-1,0,0]`. These were computed locally from the AdaptInstance.lua values above.
- An R6-specific quirk was reported: the R6 Torso could not be moved in the ACE, and the cause was the **"Adaptive Animations" Studio beta feature**. Disabling it fixed the problem — [DevForum "I Can't Animate R6 Torso" (search summary)](https://devforum.roblox.com/t/i-cant-animate-r6-torso/4220245)

### Inferences
- **Weight 0 at runtime.** The ACE emits Weight-0 placeholder poses (with identity or arbitrary CFrames) for every unkeyed ancestor, for example a `Torso` placeholder when only `Right Arm` is keyed. Editor-made animations do not snap the torso to identity at such keyframes. So the runtime must also treat Weight-0 poses as "no key here" and interpolate that joint between the neighbouring keyframes where it has Weight > 0, or leave it to lower-priority tracks if it is never keyed. This is strong inference, not documented. Treat Weight as a 0/1 "is keyed" flag. Do not use fractional weights, because the property is deprecated and its blend semantics are undocumented.
- **Omitting parts is fine.** Not every keyframe needs a pose for every part, and the ACE writes sparse keyframes. However, a keyed descendant must have all of its ancestors present as Poses, as Weight-0 placeholders if they are not keyed. For R6: to key `Left Arm` you need `HumanoidRootPart > Torso > Left Arm`.
- **Joints never referenced in a track** are left to lower-priority tracks (for example the default Animate script). That is how upper-body-only R6 actions work.
- The `HumanoidRootPart` pose is the hierarchy root and has no motor of its own (no Motor6D has Part1 = HRP), so its CFrame has no effect in classic playback. The ACE skips it on load unless root-motion support is flagged on. Write it as `Weight 0`, identity, matching Studio output.
- **Joint-space axes for R6.** Because R6 shoulder and hip joint frames are rotated ±90° about Y, Pose rotations are expressed in the *rotated* joint frame. For `Right Shoulder`, the joint's local Z axis = Torso +X and its local X axis = Torso −Z. So `CFrame.Angles(0,0,θ)` on a `Right Arm` pose swings the arm forward and back (about the torso's lateral axis), and `CFrame.Angles(θ,0,0)` raises it sideways. This is derived from the C0 matrices above, so verify the sign in Studio. The classic R6 jump's `Right Arm` pose is a pure Z-rotation of ≈ +10° (R00 0.984808, R01 −0.173648, R10 0.173648) — [roform fixture](https://raw.githubusercontent.com/Unreal-Works/roform/HEAD/fixtures/ANIMATION%20-%20Jump.rbxmx)

### Gaps
- No official statement on the runtime meaning of `Weight = 0` or of fractional weights. The conclusion above is inferred from ACE source and Studio-generated files.
- The status of root motion (`getFFlagRootMotion`) for HumanoidRootPart poses in the late-2026 build was not determined.

---

## 3. Pose easing: valid values, the In/Out reversal quirk, and actual RUNTIME behaviour per style (coordinator priority question)

### Takeaway
At **runtime**, **CubicV2, Elastic and Bounce follow TweenService/standard (Penner) semantics**: `In` = accelerate out of the current key (slow start), and `Out` = decelerate into the next key (fast start, settle at the end). This matches the current editor.md wording. **Legacy `Cubic` (3) is reversed at runtime**: `In` behaves like ease-out and `Out` like ease-in, while `InOut` is unaffected. The `PoseEasingDirection.yaml` sentence saying In/Out are "backwards ... from TweenService" describes this legacy engine convention. It is accurate for `Cubic` and for `Constant`, and misleading for CubicV2, Elastic and Bounce. **Confidence: high for CubicV2 and Cubic, medium-high for Elastic/Bounce In/Out, medium for Constant and Bounce InOut.**

### Cited Findings
**Valid values and official text (current docs)**
- Styles: Linear(0), Constant(1), Elastic(2), Cubic(3, deprecated: "Use CubicV2 going forward, Cubic has a bug where the direction is reversed between the editor and runtime"), Bounce(4), CubicV2(5). Enum description: "`Enum.PoseEasingStyle.Cubic` is a legacy alias with a known direction-reversal bug between the Animation Editor and runtime; use `Enum.PoseEasingStyle.CubicV2` for all new work." Constant: "Poses do not interpolate but snap to the keyframe indicated by the `Enum.PoseEasingDirection`" — [PoseEasingStyle.yaml](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/enums/PoseEasingStyle.yaml)
- Directions: In(0) "The EasingStyle curve is reversed, with the easing becoming linear as it approaches the next keyframe". Out(1) "EasingStyle curves are applied in the forward direction, from the current keyframe to the next". InOut(2) "Two easing curves are applied back-to-back with the linear ends of the curves meeting in the middle". Enum description: "For legacy compatibility reasons, the use of In and Out are backwards from how these terms are used by most other animation tools and by TweenService" — [PoseEasingDirection.yaml](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/enums/PoseEasingDirection.yaml)
- The ACE guide lists the user-facing styles **Linear, Constant, CubicV2, Elastic, Bounce** and the directions **In** ("slower at the beginning and faster toward the end"), **Out** ("faster at the beginning and slower toward the end") and **InOut** — [editor.md](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/animation/editor.md)
- For comparison, TweenService `EasingDirection`: In = "applied in a forward direction", Out = "applied in a reverse direction" — [EasingDirection.yaml](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/enums/EasingDirection.yaml)

**How the editor previews easing (primary source: ACE bytecode)**
- The ACE's interpolation function (`KeyframeUtils`, PROTO_17) works as follows:
  - `Constant` returns the **low (current) keyframe's value** for the whole segment, regardless of direction.
  - `Linear` uses alpha directly.
  - `CubicV2` uses `TweenService:GetValue(alpha, Enum.EasingStyle[Enum.PoseEasingStyle.Cubic.Name], Enum.EasingDirection[pose.EasingDirection.Name])`.
  - All other styles (Cubic, Elastic, Bounce) use `TweenService:GetValue(alpha, Enum.EasingStyle[style.Name], Enum.EasingDirection[direction.Name])`.
  - So **the editor preview is exactly TweenService semantics, with directions mapped by name**, and CubicV2 previews identically to Cubic.

  Source: [ACE KeyframeUtils.luac.s](https://raw.githubusercontent.com/MaximumADHD/Roblox-Client-Tracker/roblox/BuiltInPlugins/AnimationClipEditor/Src/Util/KeyframeUtils.luac.s)
- The ACE's easing-style menu order is Linear, Constant, CubicV2, Elastic, Bounce, Cubic. Cubic is still present internally as a legacy entry — [ACE Constants.luac.s](https://raw.githubusercontent.com/MaximumADHD/Roblox-Client-Tracker/roblox/BuiltInPlugins/AnimationClipEditor/Src/Util/Constants.luac.s) (`EASING_STYLE_ORDER`)

**Bug history and CubicV2 introduction (DevForum, via search summaries)**
- Long-running Engine Bugs thread "Animation cubic easing direction reversed" (topic 449068): Cubic easing in the animation editor "plays in reverse on a Humanoid". The bug "affects In/Out easing directions but not 'InOut', nor does it affect Elastic and Bounce easing styles. TweenService's Cubic easing is not affected either". Staff initially decided "to preserve the reversed behavior for compatibility". In **v646** Roblox added CubicV2, which "has the same behavior as Cubic inside the ACE, but reverses the direction in the engine to match. The original 'Cubic' style is now considered deprecated, but it will remain available". Staff advice: when converting old clips, "confirm the direction in the ACE preview is what you want at runtime", and wait to use CubicV2 until third-party plugins recognize it — [DevForum 449068 (search summary)](https://devforum.roblox.com/t/animation-cubic-easing-direction-reversed/449068); [page 4](https://devforum.roblox.com/t/animation-cubic-easing-direction-reversed/449068?page=4)
- Related bug reports about the same symptom: "Easing Directions display differently between Edit Mode and Playtesting in Animations", "Keyframe easing direction is inverted", "Easing Direction Is Flipped When Playing Animation" — [504081](https://devforum.roblox.com/t/easing-directions-display-differently-between-edit-mode-and-playtesting-in-animations/504081); [2630212](https://devforum.roblox.com/t/keyframe-easing-direction-is-inverted/2630212); [3117592](https://devforum.roblox.com/t/easing-direction-is-flipped-when-playing-animation/3117592)
- An unofficial API mirror's history tags CubicV2 (value 5) with version "646" — [robloxapi ref-temp PoseEasingStyle (search summary)](https://robloxapi.github.io/ref-temp/enum/PoseEasingStyle.html)

**Measured runtime curves (independent, community).** GitHub issue #69 on the Blender-Animations-Plugin, opened 2026-10-06, is still open. It was measured in Studio via `Animator:StepAnimations` on a default R15 rig. The reporter notes AI was used in writing the issue. Values are the fraction of change at 20% / 50% / 80% of a segment:
  - Cubic **In** 0.488 / 0.875 / 0.992 ("fast start, opposite of the name"); Cubic **Out** 0.008 / 0.125 / 0.512.
  - CubicV2 **In** 0.008 / 0.125 / 0.512 (slow start); CubicV2 **Out** 0.488 / 0.875 / 0.992; CubicV2 **InOut** 0.032 / 0.5 / 0.968.
  - Bounce **In** 0.060 / 0.234 / 0.698; Bounce **Out** 0.303 / 0.766 / 0.940; Bounce **InOut** 0.114 / 0.500 / 0.545 ("bounce-in on each half", unlike TweenService).
  - Elastic **In** −0.002 / −0.016 / −0.125 (period 0.3, "dips before the end"); Elastic **Out** 1.125 / 1.016 / 1.002 (overshoots); Elastic **InOut** period 0.45.
  - **Constant**: "In jumps at the segment start, InOut jumps at the midpoint. Only Out matches Blender's CONSTANT" (hold, then jump at the next key).

  Source: [Cautioned/Blender-Animations-Plugin issue #69](https://github.com/Cautioned/Blender-Animations-Plugin/issues/69)
- That plugin's current export code (main branch) now maps Blender `CUBIC → "CubicV2"` and `BOUNCE → "Bounce"` with **direct** direction mapping (`EASE_IN→"In"`, `EASE_OUT→"Out"`, `EASE_IN_OUT→"InOut"`). Its comments say: "Verified against Animator:StepAnimations, not just enum names". For Constant it says "Constant Out holds the previous pose; In jumps to the next pose immediately", so it always writes `Constant, Out`. Bounce InOut and Elastic are baked because "Studio's Bounce InOut differs from Blender's combined bounce curve" — [roblox_animations/animation/easing.py](https://raw.githubusercontent.com/Cautioned/Blender-Animations-Plugin/main/roblox_animations/animation/easing.py)
- A DevForum reply (search summary) says that for Constant "you can instantly snap at the beginning, middle (inout) or end of the interpolation" — [DevForum add-enumeasingstyleconstant (search summary)](https://devforum.roblox.com/t/add-enumeasingstyleconstant/2629976)

### Inferences
**Runtime answer table.** "Current" = this keyframe's pose, "next" = the next keyframe that has a Weight>0 pose for this joint.

| Style (token) | `In` (0) at runtime | `Out` (1) at runtime | `InOut` (2) at runtime | Same as TweenService? |
|---|---|---|---|---|
| Linear (0) | linear | linear | linear | n/a |
| Constant (1) | **snaps to the next pose immediately** at segment start | **holds the current pose, snaps at the next key** (the usual "stepped" meaning) | snaps at segment midpoint | n/a. The ACE preview always shows the hold behaviour regardless of direction |
| Elastic (2) | ease-in: small wobble that grows, with the largest dip (≈ −12.5%) just before the target, then lands on it | ease-out: overshoots (≈ +12.5%) right after leaving and wobbles to settle into the next pose | elastic in-out (period 0.45) | yes, by name |
| Cubic (3, legacy) | behaves as **ease-out** (fast start, decelerates into the next key) | behaves as **ease-in** (slow start) | normal in-out | **no, reversed** (the ACE preview shows the TweenService meaning, so preview ≠ game) |
| Bounce (4) | ease-in: bounces at the start (hops near the current pose), then lands on the next | ease-out: arrives and bounces, settling into the next pose | **non-standard**: both halves use bounce-in (≈ 0.545 at 80%) | In/Out yes. InOut differs |
| CubicV2 (5) | **ease-in**: slow start, accelerates into the next key (t³) | **ease-out**: fast start, **decelerates into the next key** (1−(1−t)³) | standard S-curve | **yes** |

- **Direct answer to "does CubicV2 Out decelerate into the next keyframe?" Yes.** CubicV2 Out = TweenService Cubic Out = fast start, slow arrival.
- **Evidence chain for that answer:**
  1. The ACE preview evaluates CubicV2 with `TweenService:GetValue(..., Enum.EasingStyle.Cubic, Enum.EasingDirection[sameName])` (bytecode above).
  2. Roblox staff stated CubicV2 "reverses the direction in the engine to match" the ACE.
  3. Independent StepAnimations measurements match t³ and 1−(1−t)³ exactly.
  4. A maintained exporter was updated to map EASE_OUT → CubicV2 Out after verification.
- **Formula check (done locally).** Standard Penner/TweenService formulas reproduce every measured In/Out number exactly: BounceIn(0.5)=0.234, BounceOut(0.2)=0.303, ElasticOut(0.2, p=0.3)=1.125, ElasticIn(0.8)=−0.125, CubicIn(0.5)=0.125. So Elastic/Bounce In/Out at runtime are TweenService curves.
- **Reconciling the docs.** The engine's legacy rule appears to be "Out = base curve forward, In = base curve reversed". The engine's base curves are t³ for Cubic, an elastic-out shape for Elastic, a bounce-out shape for Bounce, and hold-then-step for Constant. That makes Cubic and Constant names backwards relative to TweenService, and Elastic and Bounce names coincide with it. CubicV2 flips Cubic so it also matches. The PoseEasingDirection.yaml "backwards" sentence predates CubicV2. This reconciliation is my inference from the measurements and the bug-thread statement.
- **Practical rules for code generators:**
  - Use `EasingStyle 5 (CubicV2)` with TweenService meanings.
  - Never emit `3 (Cubic)` for new work.
  - For stepped keys emit `Constant` + `Out (1)`.
  - Avoid `Bounce` + `InOut`, or bake it into dense keys.
  - Write `Linear` as `0` with any direction. The ACE defaults to `In (0)`, while the Blender plugin writes `Out`. Both are equivalent for Linear.

### Gaps
- No official Roblox document gives per-style runtime curves. The measurements come from one community report (AI-assisted writing, not independently re-run here).
- The exact release date of v646 (CubicV2) was not retrieved. Roblox ships roughly weekly versions, so v646 is estimated at about Q4 2024. **Unverified estimate.**
- I could not determine what easing direction the ACE writes when a user picks Constant. If the ACE writes Constant + In (its default direction), editor preview and runtime would differ. This is unverified.

---

## 4. .rbxmx (XML) serialization of a KeyframeSequence; rbxm vs rbxmx; Rojo

### Takeaway
A KS file is a standard Roblox XML model, format version 4. The structure is `<roblox version="4">` > `<Item class="KeyframeSequence" referent="...">` > `<Properties>` + child `<Item class="Keyframe">` > nested `<Item class="Pose">` (and `<Item class="KeyframeMarker">` under a Keyframe). Enums are `<token>` with numeric values, CFrames are `<CoordinateFrame>` with `X Y Z R00..R22` children, plus `<float>`, `<bool>` and `<string>`. Both .rbxmx and .rbxm work for Studio, Rojo and Open Cloud upload.

### Cited Findings
**XML format rules (rbx-dom spec)**
- The root element must be `roblox`, and only `version` is required ("MUST be `4`"). All other attributes are optional "including those produced by Roblox Studio" — [rbx-dom docs/xml.md](https://raw.githubusercontent.com/rojo-rbx/rbx-dom/master/docs/xml.md)
- `<External>null</External><External>nil</External>` are legacy elements that "currently do nothing" and are optional. For **model** files Roblox writes `<Meta name="ExplicitAutoJoints">true</Meta>`, which is "RECOMMENDED" — [rbx-dom docs/xml.md](https://raw.githubusercontent.com/rojo-rbx/rbx-dom/master/docs/xml.md)
- Each `Item` requires `class` and a file-unique `referent` (not `null`). "Roblox generates referents by prefixing a UUID with `RBX`, but this is not a requirement." Exactly one `Properties` element is allowed per Item, and child Items follow it — [rbx-dom docs/xml.md](https://raw.githubusercontent.com/rojo-rbx/rbx-dom/master/docs/xml.md)
- `CFrame` properties **must** be written as `CoordinateFrame` with 12 float children in order `X, Y, Z, R00, R01, R02, R10, R11, R12, R20, R21, R22`. Enums **must** be `token` with the numeric value. `bool` is `true`/`false` (lowercase by convention). `float` is XSD decimal (`INF`/`-INF`/`NAN` uppercase), "at least 7 significant figures" recommended — [rbx-dom docs/xml.md](https://raw.githubusercontent.com/rojo-rbx/rbx-dom/master/docs/xml.md)

**Real Studio-saved R6 example (2016 R6 walk, re-saved by a modern Studio).** Excerpt, verbatim:
```xml
<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" version="4">
	<Meta name="ExplicitAutoJoints">true</Meta>
	<External>null</External>
	<External>nil</External>
	<Item class="KeyframeSequence" referent="RBXD0D2E885A518468D9CFDEDA64F5AB93D">
		<Properties>
			<float name="AuthoredHipHeight">2</float>
			<BinaryString name="GuidBinaryString">AAAAAAAAAAAAAAAAAAAAAA==</BinaryString>
			<bool name="Loop">true</bool>
			<token name="Priority">1</token>
			<BinaryString name="AttributesSerialize"></BinaryString>
			<SecurityCapabilities name="Capabilities">0</SecurityCapabilities>
			<bool name="DefinesCapabilities">false</bool>
			<string name="Name">Walk</string>
			<BinaryString name="SerializedOverrides"></BinaryString>
			<int64 name="SourceAssetId">-1</int64>
			<SharedString name="Tags">GdUioiMJlztrPFsCmr0e1w==</SharedString>
		</Properties>
		<Item class="Keyframe" referent="RBX89CFFE98DAEB4D249455E0ADEAD6D937">
			<Properties>
				<float name="Time">0</float>
				...
				<string name="Name">Keyframe</string>
			</Properties>
			<Item class="Pose" referent="RBX4C79DD151BB2406D9FDC943C8877FD7E">
				<Properties>
					<CoordinateFrame name="CFrame">
						<X>0</X><Y>0</Y><Z>0</Z>
						<R00>1</R00><R01>0</R01><R02>0</R02>
						<R10>0</R10><R11>1</R11><R12>0</R12>
						<R20>0</R20><R21>0</R21><R22>1</R22>
					</CoordinateFrame>
					<token name="EasingDirection">0</token>
					<token name="EasingStyle">0</token>
					<float name="Weight">0</float>
					...
					<string name="Name">HumanoidRootPart</string>
				</Properties>
				<Item class="Pose" referent="RBXD14F1391E90B4A4293EEA62A1F28BAAF">
					<Properties> ... <float name="Weight">1</float> ... <string name="Name">Torso</string> </Properties>
					<Item class="Pose" ...> ... <string name="Name">Left Leg</string> ... </Item>
```
— [R6 anim_walk.rbxmx](https://raw.githubusercontent.com/workspacePWNAGE/Reboot2016/HEAD/corescript-patches/content/pwnsCorescriptPatches/rbxmx/anim_walk.rbxmx). Note: `SharedString` Tags here references a `<SharedStrings>` block, which is not shown.
- A newer Studio-generated KS (viewmodel, round-tripped through rbx-dom tooling, which explains the sequential `RBX000...0` referents) carries per-instance `<UniqueId name="HistoryId">`, `<UniqueId name="UniqueId">`, `<BinaryString name="Tags" />` and `<SecurityCapabilities name="Capabilities">0</SecurityCapabilities>`. It has **no** `MaskWeight`, and every Pose writes `<token name="EasingDirection">0</token><token name="EasingStyle">0</token>` and `<float name="Weight">1</float>` — [Karambit_Idle_retarget.rbxmx](https://raw.githubusercontent.com/ThatGuyNamedSkulls/Bot/HEAD/Karambit_Idle_retarget.rbxmx)
- A minimal legacy file loads without EasingStyle/EasingDirection at all: only `Loop`, `Name`, `Priority` (token 1000), `Time` (written as `0.110000`), `CFrame`, `MaskWeight`, `Weight`. It also has an extra root attribute `assettype="animation"` — [roform fixture ANIMATION - Jump.rbxmx](https://raw.githubusercontent.com/Unreal-Works/roform/HEAD/fixtures/ANIMATION%20-%20Jump.rbxmx). (The fixture is used by a parser project. Whether current Studio opens it unchanged was not tested.)
- KeyframeMarker XML, as found in a community-generated file (sequential referents, so not proven Studio output):
```xml
<Item class="KeyframeMarker" referent="RBX53">
  <Properties>
    <string name="Name">Hit</string>
    <string name="Value" />
  </Properties>
</Item>
```
It is placed as a child Item of the `Keyframe`, after that keyframe's Pose items — [slash.rbxmx (aaaditt/demon-slayer-roblox)](https://raw.githubusercontent.com/aaaditt/demon-slayer-roblox/HEAD/assets/animations/base/slash.rbxmx). Its properties match the reflection data (`KeyframeMarker.Value: String, Serializes`) — [rbx-dom database.json](https://raw.githubusercontent.com/rojo-rbx/rbx-dom/master/rbx_dom_lua/src/database.json)

**rbxm vs rbxmx; Rojo; Open Cloud**
- The official export path is AnimSaves > right-click > **Save to File**, which saves an `.RBXM`. "Insert From File" works for `.rbxm` — [sharing-animations.md](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/education/build-it-play-it-island-of-move/sharing-animations.md). (Studio's Insert from File also accepts `.rbxmx`, which is common knowledge and was not separately sourced.)
- Rojo: "Rojo supports both binary (`.rbxm`) and XML (`.rbxmx`) models generated by Roblox Studio or another tool." `.model.json` "can be used to describe simple models ... designed to be hand-written". `.meta.json` cannot add properties to `.rbxmx/.rbxm/.model.json` — [rojo.space sync-details.md](https://raw.githubusercontent.com/rojo-rbx/rojo.space/master/docs/sync-details.md)
- Open Cloud Assets API (Create/Update Asset): **Animation** is a supported asset type, with formats `.rbxm` and `.rbxmx` (content type `model/x-rbxm`) and a 20 MB limit per call. Restriction: "`.rbxm` or `.rbxmx` files edited outside of Roblox Studio might not upload or function." The API "contains beta endpoints" — [cloud/guides/usage-assets.md](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/cloud/guides/usage-assets.md)

### Inferences
- **Minimal generator template (R6).** This is derived from the spec and real files. Not tested in Studio during this research.
```xml
<roblox version="4">
  <Meta name="ExplicitAutoJoints">true</Meta>
  <Item class="KeyframeSequence" referent="RBX0">
    <Properties>
      <string name="Name">MyR6Anim</string>
      <bool name="Loop">false</bool>
      <token name="Priority">2</token>              <!-- Action -->
      <float name="AuthoredHipHeight">2</float>
    </Properties>
    <Item class="Keyframe" referent="RBX1">
      <Properties>
        <string name="Name">Keyframe</string>
        <float name="Time">0</float>
      </Properties>
      <Item class="Pose" referent="RBX2">
        <Properties>
          <string name="Name">HumanoidRootPart</string>
          <CoordinateFrame name="CFrame"><X>0</X><Y>0</Y><Z>0</Z><R00>1</R00><R01>0</R01><R02>0</R02><R10>0</R10><R11>1</R11><R12>0</R12><R20>0</R20><R21>0</R21><R22>1</R22></CoordinateFrame>
          <token name="EasingStyle">0</token>
          <token name="EasingDirection">0</token>
          <float name="Weight">0</float>                <!-- placeholder -->
        </Properties>
        <Item class="Pose" referent="RBX3">
          <Properties>
            <string name="Name">Torso</string>
            <CoordinateFrame name="CFrame">...</CoordinateFrame>
            <token name="EasingStyle">5</token>         <!-- CubicV2 -->
            <token name="EasingDirection">1</token>     <!-- Out = decelerate into next key -->
            <float name="Weight">1</float>
          </Properties>
          <!-- child Items: Head, Left Arm, Right Arm, Left Leg, Right Leg -->
        </Item>
      </Item>
      <Item class="KeyframeMarker" referent="RBX9">
        <Properties><string name="Name">Hit</string><string name="Value">heavy</string></Properties>
      </Item>
    </Item>
  </Item>
</roblox>
```
- Escape `&`, `<` and `>` in `string` values. Keep referents unique. Keyframe times should ideally land on whole frames at the intended FPS (30 by default), since the ACE snaps to 1/2400 s ticks but displays frames.
- XML (`.rbxmx`) is the practical choice for code generation. No binary encoder is needed, and Rojo, Insert from File and Open Cloud all accept it. A `.model.json` with nested `Pose` children and `CFrame` properties is possible in principle via rbx-dom's JSON property encoding, but this is unverified.

### Gaps
- No Roblox-official example `.rbxmx` of a KeyframeSequence was found in the docs repo. The examples above are real files in third-party repos.
- The Open Cloud warning about files "edited outside of Roblox Studio" was not tested against generated KS files.

---

## 5. Getting a generated KS into Studio, previewing, publishing; CurveAnimation; limits

### Takeaway
To open a KS in the ACE, put it where the ACE looks. The current layout is `ServerStorage.RBX_ANIMSAVES.<RigName>` (an ObjectValue pointing at the rig, with the KS as its child), referenced by `rig.AnimSaves` (an ObjectValue). The ACE also still reads KS children placed directly under `rig.AnimSaves` (legacy). Then use ACE ⋯ > **Load**. To play without uploading, `KeyframeSequenceProvider:RegisterKeyframeSequence(ks)` returns a temporary, Studio-only id. To ship, use ACE ⋯ > **Publish to Roblox**, or the Open Cloud Assets API, to get an `rbxassetid://` id.

### Cited Findings
- "When you save an animation, Studio saves it as a `KeyframeSequence` object in `ServerStorage` and adds a reference to your rig object... reference the value of the `ObjectValue` in your rig's `AnimSaves` folder": `local anim = rig.AnimSaves.Value.[SavedAnimation]`. ServerStorage data does not replicate. Move it to ReplicatedStorage if clients need it — [editor.md](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/animation/editor.md)
- Official path wording: "`ServerStorage` ⟩ **RBX_ANIMSAVES** ⟩ **[your rig]**" (select the saved track and enable Loop there) — [avatar/animation-packs.md](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/avatar/animation-packs.md)
- ACE source: `FOLDERS = {AnimSaves = "RBX_ANIMSAVES", Microbones = "RBX_MICROBONE_NODES", IkData = "IkData", IkTargets = "IkTargets"}` — [ACE Constants.luac.s](https://raw.githubusercontent.com/MaximumADHD/Roblox-Client-Tracker/roblox/BuiltInPlugins/AnimationClipEditor/Src/Util/Constants.luac.s). The decompiled logic of `findOrCreateServerAnimSaves`, `getAnimSavesFolder` and `getAnimSaves` is:
  - Create `Model` "RBX_ANIMSAVES" in ServerStorage if it is missing.
  - In the rig, ensure an `ObjectValue` named `AnimSaves`. A legacy non-ObjectValue `AnimSaves` folder has its children moved into the new ObjectValue and is then destroyed.
  - Its `.Value` = an `ObjectValue` named after the rig, parented to RBX_ANIMSAVES, with its own `.Value = rig`.
  - The list of loadable animations = `KeyframeSequence`/`CurveAnimation` children of that server ObjectValue (`isLegacyAnimSaves=false`) plus children of the rig's `AnimSaves` ObjectValue (`isLegacyAnimSaves=true`).

  Source: [ACE RigUtils.luac.s, PROTO_8–11](https://raw.githubusercontent.com/MaximumADHD/Roblox-Client-Tracker/roblox/BuiltInPlugins/AnimationClipEditor/Src/Util/RigUtils.luac.s)
- Official import steps: select the rig, right-click **AnimSaves** > **Insert From File** and pick the `.RBXM`, then in the ACE ⋯ > **Load** and choose the name. If the rig has no AnimSaves yet, create and save any animation first. Troubleshooting: make sure the file contains a `KeyframeSequence`, not just a `Keyframe` — [sharing-animations.md](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/education/build-it-play-it-island-of-move/sharing-animations.md)
- Other ACE names: auto-save name `"Automatic Save"`, imported name `"Imported Animation Clip"`, temp rig `"RBX_TMP_CONTROL_RIG"` — [ACE Constants.luac.s](https://raw.githubusercontent.com/MaximumADHD/Roblox-Client-Tracker/roblox/BuiltInPlugins/AnimationClipEditor/Src/Util/Constants.luac.s). Studio's bulk Asset Importer also writes imported animations to `RBX_ANIMSAVES` (`saveImportedAnimations` references the name) — [GitHub code search hit: BuiltInPlugins/AssetImporter/Src/Utility/saveImportedAnimations.luac.s](https://raw.githubusercontent.com/MaximumADHD/Roblox-Client-Tracker/roblox/BuiltInPlugins/AssetImporter/Src/Utility/saveImportedAnimations.luac.s)
- `KeyframeSequenceProvider:RegisterKeyframeSequence(ks)` "Generates a temporary asset ID ... used for localized testing", returning a hash. `RegisterActiveKeyframeSequence` returns an `active://` URL. "The asset ID generated by this function is temporary and cannot be used outside of Studio." Both have security None. `GetKeyframeSequence` and `GetKeyframeSequenceById` are Deprecated (PluginSecurity). Use `GetKeyframeSequenceAsync` (yields) or `AnimationClipProvider:GetAnimationClipAsync()` to download a published animation's KS — [KeyframeSequenceProvider.yaml](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/classes/KeyframeSequenceProvider.yaml); [KeyframeSequence.yaml](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/classes/KeyframeSequence.yaml); [AnimationClipProvider.yaml](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/classes/AnimationClipProvider.yaml)
- Publishing in the ACE: ⋯ > **Publish to Roblox** opens the Asset Configuration window. "If the animation will be used in any group-owned game, select the group from the **Creator** field." Copy the id from the Toolbox — [editor.md](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/animation/editor.md). The Open Cloud Assets API accepts `.rbxm/.rbxmx` animation uploads (see section 4) — [usage-assets.md](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/cloud/guides/usage-assets.md)
- **CurveAnimation vs KeyframeSequence.**
  - `CurveAnimation` stores per-channel curves (`Vector3Curve` named `Position`, `EulerRotationCurve` or `RotationCurve` named `Rotation`) under a Folder hierarchy mirroring Motor6Ds/Bones. It supports partial and relative hierarchy matching. Temp ids come from `AnimationClipProvider:RegisterAnimationClip()` — [CurveAnimation.yaml](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/classes/CurveAnimation.yaml)
  - Opening the Curve Editor converts a KS clip into a CurveAnimation, after a confirmation popup. Quaternion→Euler conversion is irreversible. Bounce and Elastic are not native curve interpolations (Linear/Constant/Cubic only), so Studio adds keyframes to preserve them — [curve-editor.md](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/animation/curve-editor.md)
  - The ACE also auto-optimizes keyframes when promoting to curves: "If 3 or more consecutive keyframes have the same value ... removes the intermediary keyframes" and removes tracks that hold only default values — [editor.md](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/animation/editor.md)
- **Editor limits (ACE constants):** `DEFAULT_FRAMERATE 30`, `MIN_FRAMERATE 1`, `MAX_FRAMERATE 120`, preset `FRAMERATES = {24, 30, 60, 120, CUSTOM}`, `MAX_TIME 1800`, `TICK_FREQUENCY 2400`, `MAX_ANIMATION_LENGTH = MAX_TIME * TICK_FREQUENCY`, `MAX_VISIBLE_KEYFRAMES 1000`, playback speed 0.01–10 — [ACE Constants.luac.s](https://raw.githubusercontent.com/MaximumADHD/Roblox-Client-Tracker/roblox/BuiltInPlugins/AnimationClipEditor/Src/Util/Constants.luac.s). The docs say "animations run at 30 frames per second" by default and the timeline shows 1 s initially — [editor.md](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/animation/editor.md)
- The only *official* duration limit found applies to Marketplace animation packs: "Each clip must be 10 seconds or shorter", and packs require CurveAnimation output — [animation-packs.md](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/avatar/animation-packs.md)
- Looping caveat: "A looping animation doesn't interpolate between the final keyframes and first keyframes. To make the animation loop smoothly, duplicate the first keyframes and use them as the final keyframes" — [editor.md](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/animation/editor.md)

### Inferences
- `MAX_ANIMATION_LENGTH` is in ticks (2400/s), so `MAX_TIME = 1800` implies an **editor cap of 1800 s (30 min)**. This is inferred from the constant arithmetic and is not documented.
- **Simplest scripted workflow:** a Studio command-bar or plugin script builds the KS with `Instance.new`, parents it under `rig.AnimSaves` (or `ServerStorage.RBX_ANIMSAVES.<Rig>`), and the user opens it with ACE > Load. Alternatively, build or insert a `.rbxmx` and call `RegisterKeyframeSequence` in a Play-Solo test for instant playback.
- Keyframe times not on frame boundaries will load (snapped to 1/2400 s) but will sit between visible frames in the ACE.

### Gaps
- No documented server-side limit on uploaded animation length, keyframe count or pose count, other than the 20 MB Open Cloud file limit.
- Not verified whether `RegisterKeyframeSequence` ids work in Team Test or only in Play Solo.

---

## 6. Authoring tools for R6: Animation Editor features, Moon Animator 2, Blender workflows

### Takeaway
The built-in ACE works on any Motor6D rig, including R6. Confirmed features:
- **Frame rate**: 30 default, presets 24/30/60/120, custom 1–120.
- **Easing**: per key.
- **Events/markers**, **named keyframes**, **looping**, **priority**.
- **Curve Editor**: converts to CurveAnimation.
- **Keyframe optimization**.
- **FBX import**: improved in Aug 2026.
- **IK**: `BodyPart` and `FullBody` modes.

IK and FBX import are R15-oriented, and R6 support is unconfirmed. **Onion skinning and mirroring were not found in the built-in ACE.** For R6, many animators use Moon Animator 2 (paid plugin, exports KeyframeSequences) or Blender via the open-source "Blender Animations" plugin (RBXMonkey) plus community R6 IK/FK rigs.

### Cited Findings
**Built-in Animation Editor**
- The ACE is opened from the Avatar tab or Window ⟩ Avatar. "You can only create animations using **rigs**", and the pre-built rigs come from the Rig Generator. For custom Motor6D rigs, `AssemblyRootPart` must be the part meant to stay stationary — [editor.md](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/animation/editor.md)
- Timeline settings menu: **Timeline Unit**, **Frame Rate**, Show Animation Events. Move/Rotate toggle with **R** (uses Studio snap settings). Keyframe ops: Add Keyframe Here, copy/paste, delete. **Optimize Keyframes** slider (⋯ menu) — [editor.md](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/animation/editor.md)
- Animation Events: enable with "Show Animation Events", then **Edit Animation Events** > **+ Add Event** with a name and an optional **Parameter** string. These become KeyframeMarkers, detected with `GetMarkerReachedSignal()` — [events.md](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/animation/events.md)
- Curve Editor: Default Rotation Type (Euler Angles or Quaternions) and Euler order (XYZ, XZY, YXZ, YZX, ZXY, ZYX). Interpolation modes are Linear (default), Constant and Cubic (tangents only for Cubic). "Generate Curve" emulates Bounce/Elastic In/Out/InOut — [curve-editor.md](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/animation/curve-editor.md)
- ACE constants (current build):
  - `IK_MODE = {BodyPart, FullBody}`
  - `TEMPORARY_CONSTRAINTS = "ROBLOX_R15_IK_CONSTRAINTS"`
  - `R15_PARTS` list and an R15 `PART1_TO_JOINT` map. There is no R6 equivalent in Constants.
  - `TRACK_TYPES` includes `Facs`, `IkTarget`
  - `REDUCE_KEYFRAMES_DIALOG_MODE` includes `FromImportFBX`, `FromImportLiveAnimationCreator`, `FromImportFaceRecorder`
  - `ANIMATION_FROM_VIDEO_STATUS` codes include `InputHasNoPerson`, `MultiplePeopleInFrame`
  - `EDITOR_MODE = {DopeSheet, CurveCanvas}`

  Source: [ACE Constants.luac.s](https://raw.githubusercontent.com/MaximumADHD/Roblox-Client-Tracker/roblox/BuiltInPlugins/AnimationClipEditor/Src/Util/Constants.luac.s)
- IK history: in the release-notes thread for v355 (~2018), IK was "just R15 for now", with custom-rig support planned — [DevForum Release Notes for 355 (search summary)](https://devforum.roblox.com/t/release-notes-for-355/181348/10). The track list's rig entry "Opens the **Manage IK** window" — [editor.md](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/animation/editor.md)
- FBX import update: "Animation Import Improvements" was posted **2026-08-04** (per search summary). It adds importer settings such as rig scale and track selection. Imported animations auto-save under AnimSaves. It adds the rig options "Imported Rig" and "Imported Rig (Zeroed Rotations)", plus R15 vs Custom targets. Users report the zeroed option misbehaves on mixed Bone/Motor6D rigs — [DevForum 4775593 (search summary)](https://devforum.roblox.com/t/animation-import-improvements/4775593); [page 2](https://devforum.roblox.com/t/animation-import-improvements/4775593?page=2)
- Earlier FBX complaints: an FBX "fails to load any keyframes", and "Selected" rig mode worked for one user — [DevForum 4032197 (search summary)](https://devforum.roblox.com/t/fbx-animation-file-fails-to-load-any-keyframes/4032197)
- Onion skinning and per-part moves were still being *requested* for the default editor on **2025-12-20**. The poster says they get local-rotation features from paid Moon Animator — [DevForum "Update on the default Animation Editor" 4165825 (search summary)](https://devforum.roblox.com/t/update-on-the-default-animation-editor/4165825). An older thread "Animation Editor: Onion Skinning" exists — [DevForum 2037595 (search summary)](https://devforum.roblox.com/t/animation-editor-onion-skinning/2037595)

**Moon Animator 2** (third-party, paid; weak sources)
- Exports: "Export Rig" keeps the rig with keyframe data, and "Export All" packages the timeline into a KeyframeSequence (rig `AnimSaves` or ServerStorage). Then right-click > Save to Roblox for an id. Sources conflict on the exact folder — [nilo.io guide (vendor blog)](https://nilo.io/articles/export-moon-animator-animation-roblox)
- Moon's own save data is a StringValue-based save "so that you can load them back, not an animation itself" — [DevForum 3014871 (search summary)](https://devforum.roblox.com/t/animating-1-object/3014871)
- The marketplace listing claims R6, R15 and custom skinned-mesh support — [builtbybit listing](https://builtbybit.com/resources/moonanimator-2.109718/)

**Blender → Roblox for R6**
- **RBXMonkey / "Blender Animations Plugin for Roblox"** (Cautioned) is GPL-3.0. It consists of a Blender addon plus a Studio plugin ([Creator Store 16708835782](https://create.roblox.com/store/asset/16708835782/Blender-Animations-ultimate-edition)). Features: live sync over a local server (default port 31337), import and export of animations between Blender and Studio, bone↔Motor6D sync, and "Easing transfers losslessly between Roblox and Blender where possible". It is derived from the original addon by Den_S — [README](https://raw.githubusercontent.com/Cautioned/Blender-Animations-Plugin/main/README.md); [Den_S "Blender Rig Exporter/Animation Importer" DevForum 34729](https://devforum.roblox.com/t/blender-rig-exporteranimation-importer/34729)
- The Studio plugin version was updated 2026-08-26, and Blender addon v3.0.1 was tested on Blender 5.2.2 (per issue #69) — [issue #69](https://github.com/Cautioned/Blender-Animations-Plugin/issues/69)
- The community **"R6 IK + FK Blender Rig"** (DevForum 3586405, versions up to V2.22) supports the Cautioned plugin, including v2.4.0 weapon/accessory export. Animations are exported "using the blender and roblox plugin that is needed to even export the rig" — [DevForum 3586405 (search summary)](https://devforum.roblox.com/t/r6-ik-fk-blender-rig-v222/3586405)
- Den_S's original exporter notes "Skinned meshes/bones are not supported... use the built-in .fbx animation importer instead". The Motor6D (R6-style) path goes through the plugin — [DevForum 34729 (search summary)](https://devforum.roblox.com/t/34729)

### Inferences
- For **R6**, the dependable pipelines are:
  1. Built-in ACE, with direct Motor6D posing, easing, events and frame rates. IK is likely unavailable or unreliable on R6, since IK constraints are named and configured for R15.
  2. Moon Animator 2, a widely used alternative with richer posing.
  3. Blender with the Cautioned plugin and a community R6 rig, which round-trips via a generated KeyframeSequence.
- FBX import is aimed at bone/skinned and R15 or custom rigs. R6 FBX import is undocumented, so treat it as unsupported or untested.
- All tools ultimately produce a `KeyframeSequence` (or `CurveAnimation`) under AnimSaves/RBX_ANIMSAVES. A code generator that writes the same structure is interoperable with all of them.

### Gaps
- Mirror/flip-pose and onion skin: no evidence either way for the current built-in ACE. Not present in the Constants file and not documented. The Dec 2025 feature request implies onion skin was absent then.
- No official statement on whether ACE "Manage IK" works for R6 in 2026.
- Moon Animator 2's exact save folder name and data format: unverified ("MoonAnimator2Saves" was not confirmed by any source). Moon has no public documentation reachable here.
- No official confirmation that FBX animation import supports R6 rigs.

---

## 7. Publishing, ownership and permissions; "failed to load animation" causes

### Takeaway
Historically, an animation only played in experiences owned by the **same creator** (user or group) that owned it, which is why "upload it to the group" was the standard fix. Since the **July 31, 2025** "Improving Animation Asset Permissions" change, animations are **Restricted** assets (they can never be Open Use) that can be **granted to other experiences and collaborators** via a Permissions page, added in the follow-up "Sharing Animation Assets with Connections and Groups". A granted experience lets all players load the animation, and collaborators can load it in Studio playtests. Grants to games are permanent.

### Cited Findings
- **2025-07-31 "Improving Animation Asset Permissions."**
  - The announcement says Roblox "heard your feedback on how restrictive animation permissions are and the issues you've seen loading them in" Studio.
  - "Animation assets are 'Restricted' and cannot be changed to 'Open Use' ... to protect experiences from unwanted Animation behavior."
  - Once an experience has permission, "any player will be able to load it when playing the experience and any collaborator will be able to load it during a playtest in Studio".
  - It "enables loading Animations in experiences that have a different creator ... no need for transferring Animations between accounts".
  - Sources: [DevForum 3852101 (search summary)](https://devforum.roblox.com/t/improving-animation-asset-permissions/3852101). The date comes from the DevForumReposts X post id 1950981705981960562, decoded to 2025-07-31 18:07 UTC — [X repost](https://x.com/DevForumReposts/status/1950981705981960562)
- Fallout reported in the same thread:
  - Group-uploaded animations stopped working across experiences in the same group. A staff reply: "We've made these animations open use now, please let us know if you're still seeing some as private."
  - Early on, "the animation's permission page is not ready yet".
  - A petition said the change broke animation "spoofers" (tools that re-upload others' animations).

  Sources: [DevForum 3852101 page 4](https://devforum.roblox.com/t/improving-animation-asset-permissions/3852101?page=4); [page 5](https://devforum.roblox.com/t/improving-animation-asset-permissions/3852101?page=5); [change.org petition](https://www.change.org/p/remove-roblox-improving-animation-asset-permissions)
- Follow-up **"Sharing Animation Assets with Connections and Groups"** (topic 3892540, ~Aug–Sep 2025; exact date not retrieved): adds a Creator Hub **Permissions** page for animations with **Collaborators** and **Experiences** tabs — [DevForum 3892540 (search summary)](https://devforum.roblox.com/t/sharing-animation-assets-with-connections-and-groups/3892540)
- Current docs:
  - The Creator Dashboard > Development Items > **Animations** > Permissions flow grants collaborators (friends/groups) and **experiences (by universe ID)**.
  - "Once a game has permission to use a restricted asset, you cannot revoke access."
  - "If a creator or game doesn't have permission to use an asset, it cannot load in Studio, and a clickable error message displays in the Output window."
  - A collaborator using a restricted asset in a script needs the *game* to have permission too.
  - The **Asset Privacy** toggle does not affect Animations ("these types have their own creation defaults").
  - Your own assets always work in your own games.

  Sources: [projects/assets/privacy.md](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/projects/assets/privacy.md)
- An education page carries the banner "You can now share animations with friends, groups, and games without re-uploading them" — [sharing-animations.md](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/education/build-it-play-it-island-of-move/sharing-animations.md)
- ACE publishing guidance: choose the group in **Creator** when the animation will be used in a group-owned game — [editor.md](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/animation/editor.md)
- Typical error text: "Failed to load animation with sanitized ID". Community explanations (pre-2025-07) and fixes:
  - The animation isn't owned by the experience owner; re-upload under the group.
  - Ownership or moderation lag.
  - Intermittent failures for a subset of players even when group-owned, visible in Error Reports.

  Sources: [DevForum 3111789 (search summary)](https://devforum.roblox.com/t/failed-to-load-animation-with-sanitized-id/3111789); [DevForum 2955878 (search summary)](https://devforum.roblox.com/t/sanitized-id-how-do-i-fix-this/2955878); [DevForum 2656845 (search summary)](https://devforum.roblox.com/t/animation-doesnt-save-in-roblox-studio-and-is-sanitized-even-though-i-own-the-animation/2656845)
- A July 2025 Studio bug report "Animations fail to load on Studio" appeared around the change — [DevForum 3841449 (search summary)](https://devforum.roblox.com/t/animations-fail-to-load-on-studio/3841449)

### Inferences
**Checklist when "animation doesn't load / failed to load animation":**
- The experience (universe) has not been granted the animation. Fix by uploading as the experience's owner (user or group) or granting the universe ID on the animation's Permissions page.
- The id is a `RegisterKeyframeSequence` hash or `active://` id used outside Studio.
- The id is a catalog/bundle asset id rather than the underlying Animation asset id.
- Moderation is pending.
- Non-errors that look like failure:
  - An R15 animation played on an R6 rig, or vice versa. Pose names don't match the parts or joints, so nothing moves.
  - The priority is too low (Core/Idle under the default Animate script).
  - The track is loaded on the wrong Animator.

These are inferences based on the documented mechanics above, and the last group is not error-producing.
- Post-July-2025, animation "stealing" via re-upload and cross-creator use without a grant no longer works. Developers must explicitly grant experiences.

### Gaps
- The exact date and full text of the "Sharing Animation Assets with Connections and Groups" post could not be fetched (DevForum blocked).
- No official statement on whether group-owned animations are auto-granted to every experience of that group after the 2025 change. Forum reports conflict, and staff manually set some to "open use".
- No 2026 changes to animation permissions were found beyond the docs state above.
