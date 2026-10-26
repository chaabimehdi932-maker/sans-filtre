# Getting animations into Studio, publishing, and playing them

Read this when handing the user their files, writing the Luau that plays the animation,
replacing default animations, or debugging "my animation doesn't play".

## Contents
1. Into Studio (3 ways)
2. Publishing and permissions
3. Playing animations (Animator API essentials)
4. Priorities and blending
5. Replication: who must play what
6. Markers: hitboxes, SFX, VFX
7. Replacing the default R6 animations
8. Debug checklist
9. Studio helper scripts (inspect the rig, fetch an animation, check contact, preview)

## 1. Into Studio

**A. Command Bar (fastest, opens in the Animation Editor)**
1. In Studio, select the R6 rig (e.g. a dummy from Avatar → Rig Builder → Block/R6).
2. View → Command Bar, paste the generated `<Name>.luau`, Enter.
3. The KeyframeSequence lands in `ServerStorage.RBX_ANIMSAVES.<RigName>` (linked from
   `rig.AnimSaves`), which is where the Animation Editor looks. Without a selected rig it
   goes to `ServerStorage.R6Generated`. The script leaves the rig selected, so several
   scripts can be pasted in a row; for a set, `InstallAll.luau` does it in one paste.
4. Animation Editor → select the rig → ⋯ → **Load** → pick the name. Tweak if desired.

**B. File (.rbxmx)**: right-click `ServerStorage` (or the rig's `AnimSaves`) → *Insert from
File…* → pick `<Name>.rbxmx`. For the editor's Load menu, move it under
`ServerStorage.RBX_ANIMSAVES.<RigName>` (save any animation once on that rig to create the
folder) or into the rig's legacy `AnimSaves`.

**C. Quick test without publishing** (Studio only, temporary id):
```lua
local KSP = game:GetService("KeyframeSequenceProvider")
local id = KSP:RegisterKeyframeSequence(game.ServerStorage.R6Generated.MyAnim)  -- returns a temp id
-- In a Play Solo session, use it as Animation.AnimationId on the character's Animator.
```

The Animation Editor defaults to 30 fps; keys made at 60 fps land between visible frames
(fine, times are stored in seconds). Opening the **Curve Editor** converts the clip to a
CurveAnimation irreversibly — don't, unless intended. If an R6 Torso refuses to move in the
editor, disable the Studio beta "Adaptive Animations".

## 2. Publishing and permissions

- Animation Editor → ⋯ → **Publish to Roblox**. If the game is group-owned, choose the group
  as Creator. Copy the asset id: `rbxassetid://<id>`.
- Since 31 July 2025 animations are *Restricted* assets: they load in experiences owned by
  the same creator, or in experiences explicitly granted on the animation's **Permissions**
  page (Creator Dashboard → Development Items → Animations → Permissions; grants by universe
  id are permanent). Collaborators need the *game* to have permission too.
- "Failed to load animation (sanitized ID)" = the experience can't access that animation
  (wrong owner, no grant, a catalog/bundle id instead of the animation asset id, a temp
  id used outside Studio, or moderation pending).

## 3. Playing animations

```lua
-- LocalScript in StarterCharacterScripts (player character: play from the owning client)
local character = script.Parent
local animator = character:WaitForChild("Humanoid"):WaitForChild("Animator")

local anim = Instance.new("Animation")
anim.AnimationId = "rbxassetid://YOUR_ID"
local track = animator:LoadAnimation(anim)   -- load ONCE, keep the track
track.Priority = Enum.AnimationPriority.Action  -- optional: overrides the authored priority

track:Play(0.1)          -- fadeTime, weight=1, speed=1
-- track:Stop(0.1); track:AdjustSpeed(1.2); track:AdjustWeight(0.5, 0.1)
```

- Use `Animator:LoadAnimation` (Humanoid/AnimationController `:LoadAnimation` are deprecated).
  The Animator must be server-created (characters already have one) and in Workspace.
- `LoadAnimation` always creates a **new** track: cache it, or use
  `animator:GetTrackByAnimationId(id)`. ~256 tracks per Animator is the reported limit.
- `track.Length` is 0 until loaded; preload with
  `ContentProvider:PreloadAsync({anim1, anim2})` (Animation *instances*).
- `TimePosition` can only be set after `Play()`. Freeze: `track:AdjustSpeed(0)`.
- `Stopped` = stopped (may still fade); `Ended` = fully faded out.
- Re-load tracks after respawn (new character = new Animator).

## 4. Priorities and blending

Order: **Action4 > Action3 > Action2 > Action > Movement > Idle > Core**. Blending is
**per joint**: higher priority tracks use up weight first; a full-weight track fully
overrides only the joints it keys. Same-priority tracks **blend by weight (50/50 at equal
weight)** — stop the old one or use a higher priority. Roblox's default animations play
at **Core**, so any custom track at Idle or above overrides them on the joints it keys; a
custom track left at Core blends half-strength with them.

Guidelines: idle → Idle; walk/run/jump/fall → Movement; attacks, emotes, tool holds →
Action; hit reacts → Action2; stuns/grabs → Action3; deaths/cutscenes → Action4.
Partial-body animation: only key the joints you want (e.g. arms only for an attack you
can do while running) — unkeyed joints are left to lower priorities.

## 5. Replication

- A player's **own client** playing on its **own character** replicates to everyone.
- **NPCs / AnimationController rigs**: load and play on the **server**, or the animation is
  only visible to the client that played it.
- Client-created Animators never replicate.
- Big crowds: replicate only state (an attribute) and let each client play the tracks
  locally (deliberately unreplicated), with distance culling; leave `PreferLodEnabled` on.

```lua
-- Server Script inside an R6 NPC
local humanoid = script.Parent:WaitForChild("Humanoid")
local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator", humanoid)
local function load(id, priority, looped)
	local a = Instance.new("Animation"); a.AnimationId = id
	local t = animator:LoadAnimation(a); t.Priority = priority; t.Looped = looped
	return t
end
local idle = load("rbxassetid://IDLE", Enum.AnimationPriority.Idle, true)
local walk = load("rbxassetid://WALK", Enum.AnimationPriority.Movement, true)
idle:Play()
humanoid.Running:Connect(function(speed)
	if speed > 0.5 then
		if not walk.IsPlaying then walk:Play(0.2) end
		walk:AdjustSpeed(speed / 8)  -- 8 = the studs/s the walk was authored for ("speed" in the spec)
	elseif walk.IsPlaying then
		walk:Stop(0.2)
	end
end)
```

## 6. Markers

```lua
local attack = animator:LoadAnimation(attackAnim)
attack:GetMarkerReachedSignal("Hit"):Connect(function(value)   -- value = marker "value" string
	-- hitbox window, SFX, VFX, hit-stop, camera shake: all from this one moment
end)
attack:Play(0.05)
```
Connect before `Play()`. Authoritative damage should be validated on the server (server
timer from the known marker time, or client report + server validation). Keyframe names
also fire `GetMarkerReachedSignal`. Death "freeze": put a marker on the last key and call
`track:AdjustSpeed(0)` in it.

M1 chain pattern: keep the 4 tracks cached; on click, if within the combo window play the
next index with `Play(0.1)` after `Stop(0.1)` on the current one; reset the index after
~1 s idle.

## 7. Replacing the default R6 animations

R6 Animate reads folders under the character's `Animate` script: `idle` (Animation1,
Animation2 with child `Weight` NumberValues), `walk.WalkAnim`, `jump.JumpAnim`,
`fall.FallAnim`, `climb.ClimbAnim`, `sit.SitAnim`, `toolnone`, `toolslash`, `toollunge`,
plus emotes. **Editing `run` does nothing on R6, and R6 has no swim.**

```lua
-- ServerScriptService Script
local Players = game:GetService("Players")
local IDS = {
	idle = {Animation1 = "rbxassetid://IDLE", Animation2 = "rbxassetid://IDLE"},
	walk = {WalkAnim = "rbxassetid://RUN_OR_WALK"},
	jump = {JumpAnim = "rbxassetid://JUMP"},
	fall = {FallAnim = "rbxassetid://FALL"},
}
local function onCharacter(character)
	local humanoid = character:WaitForChild("Humanoid")
	if humanoid.RigType ~= Enum.HumanoidRigType.R6 then return end
	local animate = character:WaitForChild("Animate")
	for folder, anims in IDS do
		for name, id in anims do
			animate:WaitForChild(folder):WaitForChild(name).AnimationId = id
		end
	end
	for _, t in humanoid:WaitForChild("Animator"):GetPlayingAnimationTracks() do t:Stop(0) end
end
Players.PlayerAdded:Connect(function(p) p.CharacterAppearanceLoaded:Connect(onCharacter) end)
```
Custom walks are not speed-scaled by Animate (see `locomotion.md`): author the walk for the
game's WalkSpeed or fork Animate (copy it from a play-test character into
`StarterCharacterScripts`) and scale it yourself. Landing animations aren't part of
Animate: play one on `Humanoid.StateChanged` → `Enum.HumanoidStateType.Landed`. The game
must be set to R6 (File → Avatar Settings → R6).

## 8. Debug checklist

1. Output says "Failed to load animation" → permissions/owner/id (section 2).
2. Nothing moves → R15 animation on R6 (or vice versa); anchored limbs; Motor6Ds missing or
   renamed; weight or speed 0.
3. Half-strength / jittery → priority too low or two tracks at the same priority.
4. Works for me, not others → NPC played on a client, or client-made Animator.
5. Plays once then stops → `Looped` false (authored or `track.Looped = true`).
6. First play hitches → preload.
7. Moonwalking at high WalkSpeed → custom walk isn't speed-scaled.
8. Torso won't animate in the editor → "Adaptive Animations" beta, or wrong PrimaryPart.
9. A right-arm-only animation still moves the torso → the Animate `toolnone` track; raise
   your priority or key only what you need.
10. Snapping between moves → fadeTime 0; use ~0.1 s.
11. Feet sink into or float above the floor in game, or slide → run `check_contact.luau` (section 9)
    on the real rig and floor; a rig whose rest pose isn't on the floor in Edit mode is reported
    and compensated (in game the Humanoid places the root).

## 9. Studio helper scripts

All in `scripts/studio/`; the user pastes them into the Command Bar (View → Command Bar).

| Script | Select first | What it does |
|---|---|---|
| `inspect_rig.luau` | the rig Model | Prints parts, sizes and every Motor6D (C0/C1); flags non-R6 rigs, renamed root ("Root Hip"), custom joints, AnimationConstraints, anchored limbs; prints the `"rig"` block for the spec when joints differ from default |
| `fetch_animation.luau` | — (edit the `ID` line) | Loads an animation the user can access by ID (`KeyframeSequenceProvider:GetKeyframeSequenceAsync`) into ServerStorage, lists its markers, warns if it is R15. Right-click → Save to File → `.rbxmx` → `r6anim.py import` |
| `check_contact.luau` | the rig Model + the KeyframeSequence (Ctrl-click) | Edit mode. Steps the animation frame by frame (`Animator:StepAnimations`), takes the 8 world-space corners of each leg, raycasts the floor actually under it (stairs, slopes, platforms; the rig excluded) and reports feet pushed into the floor, both feet off the floor, and planted-foot sliding measured on the ground (set `SPEED` to the WalkSpeed for walk/run cycles) |
| `preview_in_play.luau` | the KeyframeSequence (during Play) | Registers it temporarily and plays it on the player's character at Action4, LOOPS times: check blending, interruption, loops and markers before publishing |

