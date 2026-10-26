# KeyframeSequence format reference

Read this when editing `.rbxmx` by hand, writing Luau that builds/edits Poses directly,
importing animations from other tools, or debugging easing that looks different in game.
Sources: official creator-docs YAML, rbx-dom XML spec + reflection database (captured
from Studio), the Animation Editor's own decompiled code (Roblox-Client-Tracker), real
Studio-saved R6 files, and runtime measurements of easing curves.

## Structure

```
KeyframeSequence  (Name, Loop, Priority, AuthoredHipHeight)
└─ Keyframe       (Name, Time in seconds)        one per key time; length = max Time
   ├─ Pose "HumanoidRootPart"  (Weight 0, identity)   hierarchy root, no motor
   │  └─ Pose "Torso"          (drives RootJoint)
   │     ├─ Pose "Head"        (Neck)
   │     ├─ Pose "Right Arm"   (Right Shoulder)
   │     ├─ Pose "Left Arm"    (Left Shoulder)
   │     ├─ Pose "Right Leg"   (Right Hip)
   │     └─ Pose "Left Leg"    (Left Hip)
   └─ KeyframeMarker (Name, Value)                 fires GetMarkerReachedSignal(Name)(Value)
```

- A Pose's CFrame drives the Motor6D connecting its parent pose's part (Part0) to its own
  part (Part1), written into `Motor6D.Transform`.
- Keyframes may be **sparse**: only keyed parts need Poses, but every keyed part needs its
  ancestors present. The Animation Editor writes unkeyed ancestors as **Weight 0
  placeholders** and skips Weight-0 poses when loading → treat `Weight` as a 0/1
  "is keyed" flag (fractional weights are deprecated/undefined).
- A joint never keyed in the animation is left to lower-priority tracks.
- Studio defaults when a property is omitted: `Loop = true`, `Priority = Action`,
  `AuthoredHipHeight = 2`; Pose: identity, `Linear`, `In`, `Weight 1`. Always write Loop
  and Priority explicitly.
- Looping does not interpolate last → first: duplicate the first keyframe as the last.
- The default Animate script reacts to a keyframe named `End`.

## Enum token values

| Enum | Values |
|---|---|
| AnimationPriority | Idle 0, Movement 1, Action 2, Action2 3, Action3 4, Action4 5, Core 1000 |
| PoseEasingStyle | Linear 0, Constant 1, Elastic 2, Cubic 3 (deprecated), Bounce 4, CubicV2 5 |
| PoseEasingDirection | In 0, Out 1, InOut 2 |

## Easing: what actually plays at runtime

The easing on a Pose shapes the segment **from that keyframe to the next keyframe where
the joint is keyed**.

| Style | `In` | `Out` | `InOut` |
|---|---|---|---|
| Linear | linear | linear | linear |
| Constant | snaps to the next pose **immediately** | **holds, snaps at the next key** | snaps halfway |
| CubicV2 | slow start, accelerates (t³) | fast start, **decelerates into the next key** | S-curve |
| Cubic (legacy) | **reversed**: behaves like Out | **reversed**: behaves like In | S-curve |
| Elastic | wobble growing toward the end | overshoots after leaving, settles into next | elastic in-out |
| Bounce | hops near the start | bounces on arrival | non-standard (bounce-in both halves) |

So: use **CubicV2** (never legacy Cubic), write **Constant with `Out`** for stepped keys,
avoid Bounce InOut. The Animation Editor's preview shows TweenService semantics for every
style (so legacy Cubic previews differently from how it plays, and Constant always previews
as a hold). The official `PoseEasingDirection` page's "In/Out are backwards from
TweenService" sentence predates CubicV2 and is only true for legacy Cubic and Constant.
(Confidence: high for CubicV2/Cubic, medium-high for Elastic/Bounce, medium for Constant
and Bounce InOut — based on a community `Animator:StepAnimations` measurement that standard
easing formulas reproduce exactly, Roblox staff statements about CubicV2, and a maintained
exporter verified against playback.) This skill's exporter encodes exactly this table.

## XML (.rbxmx)

```xml
<roblox version="4">
  <Item class="KeyframeSequence" referent="RBX0">
    <Properties>
      <float name="AuthoredHipHeight">2</float>
      <bool name="Loop">false</bool>
      <string name="Name">Jab_L</string>
      <token name="Priority">2</token>
    </Properties>
    <Item class="Keyframe" referent="RBX1">
      <Properties><string name="Name">Keyframe</string><float name="Time">0</float></Properties>
      <Item class="Pose" referent="RBX2">
        <Properties>
          <CoordinateFrame name="CFrame"><X>0</X><Y>0</Y><Z>0</Z><R00>1</R00><R01>0</R01><R02>0</R02><R10>0</R10><R11>1</R11><R12>0</R12><R20>0</R20><R21>0</R21><R22>1</R22></CoordinateFrame>
          <token name="EasingDirection">0</token><token name="EasingStyle">0</token>
          <string name="Name">HumanoidRootPart</string><float name="Weight">0</float>
        </Properties>
        <Item class="Pose" referent="RBX3"> ... Torso, Weight 1, children ... </Item>
      </Item>
      <Item class="KeyframeMarker" referent="RBX9">
        <Properties><string name="Name">Hit</string><string name="Value">heavy</string></Properties>
      </Item>
    </Item>
  </Item>
</roblox>
```

Rules: root `<roblox version="4">`; every `Item` needs `class` and a unique `referent`;
one `<Properties>` per Item, child Items after it; CFrames as `CoordinateFrame` with
X,Y,Z,R00..R22; enums as `<token>` numbers; escape `& < >` in strings. Both `.rbxmx` and
`.rbxm` work for Insert from File, Rojo and the Open Cloud Assets API (20 MB limit; Roblox
warns files edited outside Studio "might not upload or function" — the reliable path is
loading into Studio and publishing from the Animation Editor).

## Other tools

- **Animation Editor** (built in): 30 fps default (24/30/60/120 or custom), per-key easing,
  events (markers), keyframe optimisation, Curve Editor (converts to CurveAnimation —
  irreversible). IK is R15-oriented; no onion skin or mirror tool (this skill's renderer
  and `mirror` command fill those gaps).
- **Moon Animator 2** (paid plugin): popular for R6 combat, exports KeyframeSequences at
  60 fps, has "None" (stepped) easing and camera keyframes.
- **Blender**: the open-source "Blender Animations" plugin (Cautioned/RBXMonkey) + the
  community R6 IK/FK rig; exports KeyframeSequences.
- All of them produce a KeyframeSequence, so `r6anim.py import` can read any of their
  `.rbxmx` exports for critique, mirroring or editing.
