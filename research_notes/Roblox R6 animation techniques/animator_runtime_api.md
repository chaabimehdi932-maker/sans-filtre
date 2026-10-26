# Roblox Animation Playback Runtime (Animator / AnimationTrack) for R6 Characters and NPCs

Research date: 2026-10-26. Primary sources: the official Roblox Creator Docs API reference (read from its source repo `Roblox/creator-docs`, files `content/en-us/reference/engine/...yaml` and `content/en-us/animation/*.md`, which back create.roblox.com pages), two independent GitHub mirrors of the default R6 `Animate` script, the datamined Roblox Client Tracker (`MaximumADHD/Roblox-Client-Tracker`, Studio 0.744.0.7441077: install manifest, engine flag names, binary strings), and DevForum threads. **Method note:** DevForum pages and Pastebin could not be opened directly from this environment (DNS/proxy block), so DevForum claims below come from search-result excerpts of those threads. They are labelled "(search excerpt)" and should be treated as slightly weaker than the docs.

---

## 1. Animator, Animator:LoadAnimation vs deprecated Humanoid:LoadAnimation, track caching, per-Animator track limit

### Takeaway
Always load through an `Animator` (child of `Humanoid` or `AnimationController`) that was **created on the server**. Treat `Humanoid:LoadAnimation` / `AnimationController:LoadAnimation` as deprecated. `LoadAnimation()` **always creates a new track**, so load each animation once per Animator and reuse the track (or look it up with the newer `Animator:GetTrackByAnimationId()`). Creating tracks without limit runs into the community-reported limit of 256 tracks per Animator.

### Cited Findings
- `Animator` is "the main class responsible for the playback and replication of Animations. All replication of playing AnimationTracks is handled through the Animator instance." — [Animator API](https://create.roblox.com/docs/reference/engine/classes/Animator)
- `Animator:LoadAnimation(animation)` returns a playable `AnimationTrack`. On an Animator in a model the client has network ownership of ("for example the local player's character or from `BasePart:SetNetworkOwner()`"), it "also loads the animation for the server as well." — [Animator API](https://create.roblox.com/docs/reference/engine/classes/Animator)
- The Animator "must be in the Workspace before making a call to `LoadAnimation()` or else it will be unable to retrieve the `AnimationClipProvider` service and throw an error." — [Animator API](https://create.roblox.com/docs/reference/engine/classes/Animator); there is a matching community thread titled "How do I fix the 'Cannot load the AnimationClipProvider Service' error?" — [DevForum (search excerpt)](https://devforum.roblox.com/t/2576762)
- Official warning: "Do **not** use `LoadAnimation()` in an attempt to retrieve an existing track. Calling `LoadAnimation()` always creates a **new** AnimationTrack instance which may impact game performance if overused. Instead, use `Animator:GetTrackByAnimationId()`." — [Animator API](https://create.roblox.com/docs/reference/engine/classes/Animator)
- `Animator:GetTrackByAnimationId(animationId: ContentId): AnimationTrack?` returns the **first** existing track loaded from that animation ID, or `nil`. It never creates a track. — [Animator API](https://create.roblox.com/docs/reference/engine/classes/Animator)
- Other current Animator members: `Animator.EvaluationThrottled` (read-only: true when evaluation was skipped this frame and the previous pose was reused), `Animator.PreferLodEnabled` (default true; set false to stop LOD throttling for this Animator), `Animator:ApplyJointVelocities(motors)` (gives Motor6D child parts relative velocities, e.g. when switching to ragdoll), `Animator:StepAnimations(dt)` (plugin/command-bar only), and event `Animator.AnimationPlayed(track)`. — [Animator API](https://create.roblox.com/docs/reference/engine/classes/Animator)
- **Deprecated:** `Humanoid:LoadAnimation` ("deprecated in favor of using `Animator:LoadAnimation()` directly (the Animator may be created while editing or at runtime)"). `Humanoid:GetPlayingAnimationTracks` and `Humanoid.AnimationPlayed` also carry the Deprecated tag. — [Humanoid API](https://create.roblox.com/docs/reference/engine/classes/Humanoid)
- **Deprecated:** `AnimationController:LoadAnimation`, `AnimationController:GetPlayingAnimationTracks` and `AnimationController.AnimationPlayed`. The docs say the controller "can be thought of as nothing more than an empty shell for a child Animator"; the deprecated method just auto-creates an Animator and forwards the call. — [AnimationController API](https://create.roblox.com/docs/reference/engine/classes/AnimationController)
- Deprecation announcement: Roblox deprecated these methods because they can cause hard-to-diagnose broken replication. They auto-create an Animator when none exists, which causes timing issues when called from LocalScripts. Roblox recommends creating the Animator on the server (Instance.new or placed in Studio) and having clients `WaitForChild("Animator")`. Deprecated does not mean removed. — [DevForum: Deprecating LoadAnimation on Humanoid and AnimationController (search excerpt)](https://devforum.roblox.com/t/deprecating-loadanimation-on-humanoid-and-animationcontroller/857129)
- Track limit: a DevForum thread reports the error "Animation Track Limit of 256 tracks for one animator exceeded" after months of development. Replies suggest calling `AnimationTrack:Destroy()` on tracks you no longer need, or loading fewer tracks. This is community advice; the thread does not settle it. — [DevForum: Tool Error: Animation Track Limit of 256 tracks (search excerpt)](https://devforum.roblox.com/t/tool-error-animation-track-limit-of-256-tracks-for-one-animator-exceeded/2622870)
- Roblox's own default R6 `Animate` script calls `track:Stop(...)` and then `track:Destroy()` every time it swaps the current animation (`stopAllAnimations`, `playAnimation`, `stopToolAnimations`), so it never accumulates tracks. — [R6 Animate mirror (moiez0/ReanimateTutorial)](https://github.com/moiez0/ReanimateTutorial/blob/main/Animate.lua); [R6 section of EgoMoose Animate mirror](https://github.com/EgoMooseOldProjects/Custom-Character-Controller/blob/master/characterController/Animate.lua)

### Inferences
- I found no official doc that states the 256 number. The error text is known only from DevForum reports. Treat 256 as the observed limit and do not design around getting close to it.
- Recommended caching pattern (synthesized from the docs above):

```lua
-- One cache per Animator; reuse tracks instead of calling LoadAnimation repeatedly.
local trackCache: {[Animator]: {[string]: AnimationTrack}} = setmetatable({}, { __mode = "k" }) :: any

local function getTrack(animator: Animator, anim: Animation): AnimationTrack
	local perAnimator = trackCache[animator]
	if not perAnimator then
		perAnimator = {}
		trackCache[animator] = perAnimator
	end
	local track = perAnimator[anim.AnimationId]
	if not track then
		-- Alternative (2025+ API): animator:GetTrackByAnimationId(anim.AnimationId)
		track = animator:LoadAnimation(anim)
		perAnimator[anim.AnimationId] = track
	end
	return track
end
```
- Getting the Animator safely on a player character (client): `local animator = character:WaitForChild("Humanoid"):WaitForChild("Animator")`. Use `WaitForChild` rather than `Instance.new` on the client, because a client-created Animator does not replicate (see section 4).
- Characters respawn with a fresh Humanoid/Animator. Clear any per-character cache on `CharacterAdded`/`Destroying`; the weak-keyed table above handles this automatically.

### Gaps
- No official statement of the per-Animator track limit, its exact warning text, or whether `Destroy()` (versus only `Stop()`) frees a slot. Evidence comes from forum reports.
- Release date of `GetTrackByAnimationId`, `PreferLodEnabled` and `EvaluationThrottled`: they appear in the current docs, but I found no announcement (estimated 2025–2026).

---

## 2. AnimationTrack API (Play/Stop/Adjust*, TimePosition, Length, IsPlaying, Looped, Priority, weights, events) and Animator:GetPlayingAnimationTracks / AnimationPlayed

### Takeaway
Use `Play(fadeTime=0.1, weight=1, speed=1)`, `Stop(fadeTime=0.1)`, `AdjustSpeed(speed)` and `AdjustWeight(weight, fadeTime=0.1)`. `Length` is 0 until the asset loads. Set `TimePosition` only after `Play()`. `Looped` and `Priority` can be overridden at runtime. Use `Stopped` for "the track stopped" and `Ended` for "fully faded out, back to neutral". Use `GetMarkerReachedSignal` rather than the superseded `KeyframeReached`.

### Cited Findings
All from the [AnimationTrack API](https://create.roblox.com/docs/reference/engine/classes/AnimationTrack) unless noted:
- `AnimationTrack` is NotCreatable. You get one only from `Animator:LoadAnimation()`.
- `Play(fadeTime: float = 0.1, weight: float = 1, speed: float = 1)`: weight ramps from 0 to `weight` over `fadeTime`. "If you want to start the animation at a specific point using `TimePosition`, it's important the animation is played before this is done."
- `Stop(fadeTime: float = 0.1)`: weight moves to zero over `fadeTime` "regardless of the initial weight". After `Stop()`, further `Stop()`/`AdjustWeight()` calls "will not work as expected"; call `Play()` again first. A `fadeTime` of 0 on Motor6Ds with `MaxVelocity` 0 "causes the joints to freeze in place".
- `AdjustSpeed(speed = 1)`: positive plays forward, negative plays in reverse, 0 pauses. Real duration = `Length / Speed`. `Speed` is read-only and changes only through `Play`/`AdjustSpeed`.
- `AdjustWeight(weight = 1, fadeTime = 0.1)`: blends `WeightCurrent` toward `WeightTarget`. "In most cases blending animations is not required and using `AnimationTrack.Priority` is more suitable."
- `WeightCurrent` / `WeightTarget` are read-only floats. Compare them with a tolerance, not `==`.
- `TimePosition` can be read and written, but the track "must be playing" to set it. Combine with `AdjustSpeed(0)` to freeze on a frame.
- `Length` "will return `0` until the animation has fully loaded and thus may not be immediately available."
- `IsPlaying`: read-only. Use it to avoid restarting a track by calling `Play()` again.
- `Looped`: defaults to the value authored in the Animation Editor. Can be changed at runtime, and the change "will take effect after the animation finishes" the current cycle. Also handles reverse playback.
- `Priority`: `Enum.AnimationPriority`, overridable at runtime.
- `GetTimeOfKeyframe(name)` errors if the animation has not loaded. "To check if the animation has loaded, verify that the `AnimationTrack.Length` is greater than zero."
- Events: `Stopped` fires when the track finishes playing, though it "might still animate the subject while the animation fades out". `Ended` fires when the track "is completely done moving anything in the world… the fade out is finished, and the subject is in a neutral pose". `DidLoop` fires after each loop of a looped track ("may also fire at the exact end of a non looped animation track but this behavior should not be relied upon"). `KeyframeReached(keyframeName)` fires for keyframes not named the default "Keyframe"; its deprecation message reads "superseded by `AnimationTrack:GetMarkerReachedSignal()`". `GetMarkerReachedSignal(name)` returns an RBXScriptSignal that fires for the named `KeyframeMarker`, with the marker's parameter string as its argument.
- New animation-graph methods: `SetParameter(key, value)`, `GetParameter(key)`, `GetParameterDefaults()`. These drive `AnimationGraphDefinition` graphs; `GetParameterDefaults` returns an empty dictionary for ordinary clip animations.
- `Animator:GetPlayingAnimationTracks()` "includes tracks that are fading out and does **not** depend on `IsPlaying` being true". Fading tracks are removed once their weight reaches zero. — [Animator API](https://create.roblox.com/docs/reference/engine/classes/Animator)
- `Animator.AnimationPlayed(animationTrack)` "fires for all `AnimationTrack:Play()` calls on AnimationTracks created and owned by the Animator." — [Animator API](https://create.roblox.com/docs/reference/engine/classes/Animator)
- `RunService.PreAnimation(deltaTimeSim)` fires each frame before animations are stepped and "is useful for modifying animation objects, such as adjusting their speed or priority". `PreSimulation` follows after animations are stepped. — [RunService API](https://create.roblox.com/docs/reference/engine/classes/RunService)

### Inferences
- Typical one-shot action pattern:

```lua
local track = getTrack(animator, slashAnim)      -- cached
track.Priority = Enum.AnimationPriority.Action    -- beat Core/Idle/Movement
track.Looped = false
if not track.IsPlaying then
	track:Play(0.05, 1, 1.2)                       -- fast fade-in, 20% faster
end
track.Stopped:Once(function()
	-- gameplay "attack finished" (may still be fading out)
end)
track.Ended:Once(function()
	-- fully back to neutral; safe for cleanup
end)
```
- Freeze on a pose: `track:Play(0); track.TimePosition = 0.4; track:AdjustSpeed(0)`.
- Duration actually played = `track.Length / math.abs(track.Speed)`. It is only meaningful once `Length > 0`.

### Gaps
- The docs do not describe what happens to `TimePosition` writes on a non-owner peer (e.g. whether a server-side `TimePosition` write replicates to clients). Not verified.

---

## 3. AnimationPriority levels and blending (across and within priorities, partial-body animations, weighted-blend fix)

### Takeaway
There are 7 priorities: Action4 > Action3 > Action2 > Action > Movement > Idle > Core. Blending is **per joint**. Higher-priority tracks are evaluated first and consume weight until the per-joint sum reaches 1.0, so a full-weight higher track fully overrides only the joints it keys. Same-priority tracks **blend in proportion to weight** (normalized when the sum exceeds 1). This "weighted blend" behaviour came from the 2021–2022 `Workspace.AnimationWeightedBlendFix` rollout and is now the only behaviour: the property no longer appears in the Workspace API docs.

### Cited Findings
- Official rule: "When multiple AnimationTracks are played concurrently by the same Animator and affect the same animated joints, the tracks are evaluated in order from high to low priority, per joint, while the total track weight sum remains less than 1.0. When the track weight sum reaches or exceeds 1.0 for a joint, evaluation stops and no lower-priority tracks will be evaluated for that joint. AnimationTracks with the same priority that are playing concurrently will blend proportional to their track weights (normalized if the sum exceeds 1)." — [AnimationPriority enum](https://create.roblox.com/docs/reference/engine/enums/AnimationPriority)
- Order: Action4 (1), Action3 (2), Action2 (3), Action (4), Movement (5), Idle (6), Core (7). Enum values: Idle=0, Movement=1, Action=2, Action2=3, Action3=4, Action4=5, Core=1000. "Roblox's default character animations, including catalog animation bundles, play at **Core** priority. **Idle** through **Action4** priority are for developer use." — [AnimationPriority enum](https://create.roblox.com/docs/reference/engine/enums/AnimationPriority)
- Recommended uses: Idle for idles; Movement for "walk, run, swim, climb, and other locomotion"; Action for "character actions that must override idle and locomotion"; Action2–4 each override the one below. — [AnimationPriority enum](https://create.roblox.com/docs/reference/engine/enums/AnimationPriority)
- The default R6 Animate script sets `Priority = Enum.AnimationPriority.Core` on idle, walk, jump, fall, climb, sit and emote tracks. It plays `toolnone` at `Idle` and `toolslash`/`toollunge` at `Action`. — [R6 Animate mirror](https://github.com/moiez0/ReanimateTutorial/blob/main/Animate.lua)
- Weighted blend fix announcement ("Animation Engine – Runtime Changes and Fixes", 2021–2022, search excerpts): a higher-priority track at weight 1.0 stops a lower-priority track from contributing to any joint the higher track animates, while a higher track with weight < 1.0 lets lower tracks fill the per-joint total up to 1.0. Overriding a same-priority track by playing at weight 1.0 "was not intended" and came partly from "a long-standing math bug in the weight-blending code". Under the fix, "a new track will now evenly blend between itself and an older AnimationTrack of the same priority and weight instead of overriding it completely." The rollout was opt-in through `Workspace.AnimationWeightedBlendFix`, then opt-out. `Default` was later changed to act as `Enabled`, and the property was slated for removal. Recommended fixes: use the higher priorities (Action2–Action4) or crossfade with `Stop()`/`Play()` fade times. The same thread says `AnimationTrack.Priority` was added to the track properties that replicate between server and client in both directions. — [DevForum announcement 1320674 (search excerpt)](https://devforum.roblox.com/t/animation-engine-runtime-changes-and-fixes/1320674); [post #356](https://devforum.roblox.com/t/animation-engine-runtime-changes-and-fixes/1320674/356); [post #375](https://devforum.roblox.com/t/animation-engine-runtime-changes-and-fixes/1320674/375)
- Earlier phase plan from the same announcement (March 2022 updates, search excerpt): Phase 1 opt-in for at least four weeks, Phase 2 opt-out with new places defaulting to the new code, Phase 3 TBD. — [DevForum announcement 1320674 (search excerpt)](https://devforum.roblox.com/t/animation-engine-runtime-changes-and-fixes/1320674/1)
- Community fallout (2022): developers saw a "50/50" blend where the newer same-priority animation used to fully cover the older one, which was blamed on the new Action2–4 priorities and blending changes. Some set `AnimationWeightedBlendFix = Disabled` or added a Workspace boolean attribute `RbxLegacyAnimationBlending = true` to get the old behaviour back. — [DevForum 1689233 (search excerpt)](https://devforum.roblox.com/t/new-animation-priorities-causes-serious-problems-action2-action3-action4/1689233); [DevForum 1700696 (search excerpt)](https://devforum.roblox.com/t/how-do-i-prevent-the-new-roblox-animation-blending/1700696); a separate report blamed the setting for default-animation stutter — [DevForum 1512558 (search excerpt)](https://devforum.roblox.com/t/animationweightedblendfix-causes-default-roblox-animations-to-stutter/1512558)
- Current state: the current Workspace class reference lists no `AnimationWeightedBlendFix` property. Workspace animation properties now are `ClientAnimatorThrottling`, `Retargeting`, `ImprovedAnimationConstraint` and `AvatarUnificationMode`. — [Workspace API](https://create.roblox.com/docs/reference/engine/classes/Workspace)
- Engine evidence (Studio build 0.744.0.7441077, datamined): the string `RbxLegacyAnimationBlending` is still in the Studio binary, and there is an engine flag named `DFFlagEnableAnimatorLegacyBlendingAnalytics`. — [Client Tracker DeepStrings.txt](https://raw.githubusercontent.com/MaximumADHD/Roblox-Client-Tracker/roblox/DeepStrings.txt); [Client Tracker FVariables.txt](https://raw.githubusercontent.com/MaximumADHD/Roblox-Client-Tracker/roblox/FVariables.txt); [version.txt](https://raw.githubusercontent.com/MaximumADHD/Roblox-Client-Tracker/roblox/version.txt)

### Inferences
- **Worked per-joint example (current behaviour):** say an Action track keys only the R6 arms at weight 1 while a Movement walk keys all limbs. The arms show 100% Action, and the legs, torso and head show 100% walk. If the Action track instead plays at weight 0.6, each arm joint shows 60% Action and 40% walk. If two Action tracks of weight 1 overlap on the same joint, each contributes 50% (normalized). To get "newest wins" at the same level, stop or fade the old track, or put the newer one one level higher (e.g. Action2).
- **Partial-body animations** work because evaluation is per joint: a joint the animation does not key leaves the weight budget free for lower priorities. In the Animation Editor, any joint that has keyframes counts as animated, even at its rest pose, and will override lower priorities. To make an upper-body-only R6 animation, delete the keyframes on `Left Hip`, `Right Hip` and `RootJoint` (and on `Neck` if not needed).
- Because default R6 locomotion runs at **Core**, any custom track at Idle or higher overrides the default animations on the joints it keys. A custom track left at **Core** blends 50/50 with the default animations on those joints, which is one common cause of "my animation looks weak/half-strength".
- Treat `AnimationWeightedBlendFix` as gone as of late 2026 (removed from the docs). The `RbxLegacyAnimationBlending` Workspace attribute is **probably still recognized**, since the string and a "legacy blending analytics" flag are in the current binary. It is undocumented, though, and the analytics flag suggests Roblox is measuring its use, likely ahead of removal. Do not build new work on it; author for weighted blending.

### Gaps
- I could not open the full announcement text (DevForum blocked here), so I have no exact date when the property was removed or `Default` became permanently Enabled.
- No official doc covers "additive" blending for ordinary clips (only graph-based animation), so it is not covered here.

---

## 4. Replication rules (player characters, NPCs, AnimationController rigs, what does NOT replicate)

### Takeaway
(a) A player's own client playing tracks on its own character's Animator replicates to the server and to other clients. (b) Any rig that is **not** a player character (NPCs, AnimationController rigs) must load and play on the **server** to replicate. (c) In every case the Animator must have been **created on the server**. A client-created Animator, client-only tracks on server-owned rigs, and client-side Motor6D edits are seen only by that client.

### Cited Findings
- "If an Animator is a descendant of a Humanoid or AnimationController in a player's `Player.Character`, animations started on that player's client will be replicated to the server and other clients." / "If the Animator is **not** a descendant of a player character, its animations must be loaded and started on the server to replicate." / "The Animator object must be initially created on the server and replicated to clients for animation replication to work at all. If an Animator is created locally, then AnimationTracks loaded with that Animator will not replicate." — [Animator API](https://create.roblox.com/docs/reference/engine/classes/Animator); identical text in [Animation API](https://create.roblox.com/docs/reference/engine/classes/Animation)
- `LoadAnimation` on a model the client network-owns (character, or via `BasePart:SetNetworkOwner()`) "also loads the animation for the server as well." — [Animator API](https://create.roblox.com/docs/reference/engine/classes/Animator)
- Official non-humanoid example: a **server** `Script` creates `AnimationController` + child `Animator`, then loads and plays. — [Use animations guide](https://create.roblox.com/docs/animation/using)
- `Motor6D.Transform` (the CFrame the Animator writes) is tagged `NotReplicated`/`Hidden`. "If the Motor6D is part of an animated model with an Animator, then `Motor6D.Transform` will usually be overwritten every frame by the Animator after `RunService.PreAnimation` and before `RunService.PreSimulation`." Docs recommend `Transform` over `C0`/`C1` for custom animation. — [Motor6D API](https://create.roblox.com/docs/reference/engine/classes/Motor6D)
- `AnimationTrack.Priority` replicates in both directions (per the weighted-blend announcement thread, search excerpt). — [DevForum 1320674 (search excerpt)](https://devforum.roblox.com/t/animation-engine-runtime-changes-and-fixes/1320674)
- Engine strings in the current Studio build name per-track replication fields: `ReplicateAnimationFadeTime`, `ReplicateAnimationLooping`, `ReplicateAnimationPlayState`, `ReplicateAnimationPosition`, `ReplicateAnimationPriority`, `ReplicateAnimationSpeed`, plus `AnimationRateLimiterMaxAmount`/`AnimationRateLimiterSeconds`. These are datamined identifiers whose exact semantics are undocumented. — [Client Tracker DeepStrings.txt](https://raw.githubusercontent.com/MaximumADHD/Roblox-Client-Tracker/roblox/DeepStrings.txt)
- Community confirmation: for an NPC dummy "you need to call animation in server script to play animation on all clients". Playing it in a LocalScript shows it only on that client. Firing a remote so every client plays it locally means the server never sees the animation. — [DevForum: Client Replication on NPCs (search excerpt)](https://devforum.roblox.com/t/client-replication-on-npcs/3139576)

### Inferences
- Note the doc inconsistency: one sentence implies client-network-owned non-character models (via `SetNetworkOwner`) load on the server too, but the explicit rule says non-character Animators must be driven from the server. For correctness, drive NPC animation from the server, or deliberately make it **client-only cosmetic** (see section 7).
- What does **not** replicate (consequences of the rules above plus standard client/server filtering):
  - Tracks a client plays on a server-owned NPC (visible only on that client).
  - Anything played through an Animator the client created itself.
  - `Motor6D.Transform` (NotReplicated), and `C0`/`C1` changes made by a LocalScript. Every peer must compute procedural aim/head-look itself, or the server must set `C0`. A client-side C0 change is a local property write and is not sent to the server (standard FilteringEnabled behaviour; no fetched doc states this for C0 specifically).
- The `ReplicateAnimation*` identifiers suggest that a replicated track carries fade time, looping, play state, time position, priority and speed. Runtime `Looped`/`Priority`/`AdjustSpeed`/`TimePosition` changes made by the playing peer therefore plausibly reach observers. The `AnimationRateLimiter*` names suggest a server-side rate limit on animation replication, so do not spam `Play()`/`AdjustSpeed()` every frame. Both points are inferred from names only.
- **Server-played tracks on a player's own character** also replicate (the Animator is server-created), but they add latency for the owning player. Play character actions from the owning client.
- Pattern for a server-owned R6 NPC (server Script):

```lua
-- Script inside the R6 NPC model (server)
local humanoid = script.Parent:WaitForChild("Humanoid")
local animator = humanoid:FindFirstChildOfClass("Animator")
if not animator then
	animator = Instance.new("Animator")   -- created on the server => replicates
	animator.Parent = humanoid
end
local anim = Instance.new("Animation")
anim.AnimationId = "rbxassetid://180435571" -- default R6 idle (Roblox-owned)
local idle = animator:LoadAnimation(anim)
idle.Priority = Enum.AnimationPriority.Idle
idle.Looped = true
idle:Play()
```

### Gaps
- No official doc explains replication of tracks on an AnimationController rig parented under a player character (e.g. a pet welded to the character). The docs only say "descendant of a Humanoid or AnimationController in a player's Character", which suggests owner-client playback works there.

---

## 5. Preloading (ContentProvider:PreloadAsync with Animation instances) and waiting for Length > 0

### Takeaway
Pass the `Animation` **instances** (not ID strings) to `ContentProvider:PreloadAsync`, and use the per-asset callback to detect failures. After loading, a track is not ready until `track.Length > 0`. Anything that depends on length or keyframes (`GetTimeOfKeyframe`, computing durations) must wait for that.

### Cited Findings
- `ContentProvider:PreloadAsync(contentIdList: {Instance}, callbackFunction?)` "yields until all of the assets associated with the given Instances have loaded"; the callback receives the content string and the final `Enum.AssetFetchStatus`. Failed assets print an error, but the method "will not error" and keeps going. — [ContentProvider API](https://create.roblox.com/docs/reference/engine/classes/ContentProvider)
- `AnimationTrack.Length` returns 0 until the animation has fully loaded. `GetTimeOfKeyframe` errors before load; "verify that the AnimationTrack.Length is greater than zero." — [AnimationTrack API](https://create.roblox.com/docs/reference/engine/classes/AnimationTrack)

### Inferences
```lua
local ContentProvider = game:GetService("ContentProvider")

local anims = { slashAnim, idleAnim, walkAnim }   -- Animation instances
ContentProvider:PreloadAsync(anims, function(contentId, status)
	if status ~= Enum.AssetFetchStatus.Success then
		warn("Animation failed to preload:", contentId, status)
	end
end)

local track = animator:LoadAnimation(slashAnim)
local t0 = os.clock()
while track.Length == 0 and os.clock() - t0 < 5 do  -- timeout guard
	task.wait()
end
if track.Length == 0 then
	warn("Animation never loaded (ownership? wrong ID?)")
end
```
- `Play()` can be called before `Length > 0`; the animation starts when the data arrives. Preloading removes the visible "first play does nothing / plays late" glitch.
- A `Length` that stays at 0 forever is the clearest runtime sign of a permission/ownership or bad-ID problem (see the checklist).

### Gaps
- No official statement on whether `PreloadAsync` for animations warms the cache used by both client and server, or only the calling peer. It is presumably per-peer, but unverified.

---

## 6. The default R6 Animate script: structure, asset IDs, speed scaling, emotes, replacing animations, forcing R6, why R15 IDs fail

### Takeaway
The default R6 `Animate` script reads `StringValue` folders (idle, walk, run, jump, fall, climb, sit, toolnone, toolslash, toollunge, wave, point, dance/dance2/dance3, laugh, cheer) that hold `Animation` children. If a folder is missing, it falls back to hard-coded IDs. It plays everything at **Core**, scales the walk animation by `speed / 14.5` **only when the walk ID is the default 180426354**, and **never plays "run"** (R6 has no separate run). To replace R6 animations, change `walk.WalkAnim`, `idle.Animation1/2` and so on at spawn, or fork the script into `StarterCharacterScripts`. R15 or catalog bundle IDs do nothing on R6 because they key R15 part names.

### Cited Findings
- **Default R6 asset IDs**, identical in two independent mirrors of the R6 Animate script (format `http://www.roblox.com/asset/?id=<n>`; `weight` = random-pick weight). Sources: [moiez0/ReanimateTutorial Animate.lua](https://github.com/moiez0/ReanimateTutorial/blob/main/Animate.lua) and the R6 branch of [EgoMooseOldProjects Custom-Character-Controller Animate.lua](https://github.com/EgoMooseOldProjects/Custom-Character-Controller/blob/master/characterController/Animate.lua) (that file also holds an R15 table with IDs 507766666 etc., which confirms the R6/R15 split). A DevForum post independently lists 180435571 (idle) and 180426354 (walk) — [DevForum: A very basic R6 Animate script (search excerpt)](https://devforum.roblox.com/t/a-very-basic-r6-animate-script/3118633); Pastebin R6 scripts use 129967390 for toolslash — [search result](https://pastebin.com/HP3ufNJP).

| Key | Asset ID(s) (weight) |
|---|---|
| idle | 180435571 (9), 180435792 (1) |
| walk | 180426354 (10) |
| run | `"run.xml"` placeholder (never played by R6 script) |
| jump | 125750702 |
| fall | 180436148 |
| climb | 180436334 |
| sit | 178130996 |
| toolnone | 182393478 |
| toolslash | 129967390 |
| toollunge | 129967478 |
| wave | 128777973 |
| point | 128853357 |
| dance1 | 182435998, 182491037, 182491065 |
| dance2 | 182436842, 182491248, 182491277 |
| dance3 | 182436935, 182491368, 182491423 |
| laugh | 129423131 |
| cheer | 129423030 |

- Structure/logic (same mirrors):
  - `configureAnimationSet(name, fileList)` looks for a child of `Animate` named `name`, collects its `Animation` children, and reads an optional `NumberValue` named `Weight`. It reconnects on `ChildAdded`/`ChildRemoved`/`Changed`, so editing `AnimationId`s at runtime reconfigures the set. With no config children, it creates `Animation`s from the hard-coded table.
  - `playAnimation` picks a weighted random entry. If it differs from the current one, it stops and **destroys** the old track, calls `humanoid:LoadAnimation(anim)` (deprecated API), sets `Priority = Core`, plays with the given fade, and hooks `KeyframeReached` (superseded API). On a keyframe named `"End"` it replays the animation, or returns to idle for non-looping emotes.
  - `onRunning(speed)`: if `speed > 0.01` it plays `"walk"` (0.1 fade) and, **only if** `currentAnimInstance.AnimationId == "http://www.roblox.com/asset/?id=180426354"`, calls `setAnimationSpeed(speed / 14.5)`. Otherwise it plays idle unless an emote is active.
  - `onClimbing(speed)`: plays climb, `setAnimationSpeed(speed / 12.0)`.
  - Constants: `jumpAnimDuration = 0.3` (fall waits until the jump has played 0.3 s), `fallTransitionTime = 0.3`, `toolTransitionTime = 0.1`. Seated plays `sit` with a 0.5 fade. Dead/GettingUp/FallingDown/PlatformStanding stop all tracks and fall back to legacy `Motor6D:SetDesiredAngle` sine motion.
  - The script caches the R6 joints `Torso["Right Shoulder"]`, `["Left Shoulder"]`, `["Right Hip"]`, `["Left Hip"]`, `["Neck"]`.
  - Emotes: `emoteNames = { wave=false, point=false, dance1=true, dance2=true, dance3=true, laugh=false, cheer=false }` (true = looping). Triggered by `Players.LocalPlayer.Chatted`: `"/e dance"` picks a random dance from `{"dance1","dance2","dance3"}`, and `"/e <name>"` or `"/emote <name>"` plays `<name>`, **only if `pose == "Standing"`**.
  - Tools: each frame, if the character holds a `Tool` with a `Handle`, it looks for a child `StringValue` named `"toolanim"`, reads its `Value` ("Slash"/"Lunge"), un-parents it, and plays `toolslash`/`toollunge` at **Action** priority for a 0.3 s window. Otherwise it plays `toolnone` at **Idle** priority while holding a tool.
- Official replacement method: a server `Script` on `player.CharacterAppearanceLoaded` stops all playing tracks (`animator:GetPlayingAnimationTracks()` then `:Stop(0)`) and sets e.g. `animateScript.walk.WalkAnim.AnimationId`, `animateScript.idle.Animation1/Animation2.AnimationId`, `jump.JumpAnim`, `fall.FallAnim`, `climb.ClimbAnim`, `run.RunAnim`, `swim.Swim`, `swimidle.SwimIdle`. Idle variant odds use each Animation's child `Weight.Value` ("animation weight / total weight"). — [Use animations guide](https://create.roblox.com/docs/animation/using)
- The catalog bundle IDs in that guide (Ninja run 656118852, Robot, Rthro and others) are avatar animation bundles. — [Use animations guide](https://create.roblox.com/docs/animation/using)
- Forking: developers copy the `Animate` script into `StarterCharacterScripts` and edit the IDs there (a script named `Animate` replaces the default); tool animations stay hard-coded unless you edit the script. — [DevForum: R6 Linked Sword animations thread (search excerpt)](https://devforum.roblox.com/t/how-does-the-r6-linked-sword-animations-work-and-does-anyone-have-a-port-of-the-slash-to-a-actual-animation-object/2659745)
- `StarterPlayer` can contain a `StarterCharacterScripts` folder of scripts added to each character, and a `Model` named `StarterCharacter` used as every player's character. — [StarterPlayer API](https://create.roblox.com/docs/reference/engine/classes/StarterPlayer)
- Forcing R6: per a third-party guide, open **File → Avatar Settings** (the newer Avatar Settings window; older Studio had **Game Settings → Avatar**) and pick **R6** (options R6 / R15 / R15 & R6). Inserting an R6 rig does not change the game-wide setting. — [itechguides (third-party)](https://www.itechguides.com/?p=330010)
- `Humanoid.RigType` (`Enum.HumanoidRigType.R6`/`R15`). R6 uses 6 parts, and `Head` must attach to `Torso` or the Humanoid dies. R15 uses `UpperTorso`, and setting an R15 humanoid's RigType to R6 kills it. — [Humanoid API](https://create.roblox.com/docs/reference/engine/classes/Humanoid); `Players:CreateHumanoidModelFromDescriptionAsync(desc, rigType)` builds an R6 or R15 model (non-Async version superseded). — [Players API](https://create.roblox.com/docs/reference/engine/classes/Players)
- **2025–2026 R6 adapter:** `Workspace.AvatarUnificationMode` (NotScriptable; Default currently behaves as Disabled) enables the "R6 to R15 adapter". The Workspace page says R15 avatars joining R6 experiences get invisible adapter parts with R6-compatible names welded to their R15 parts. The enum page says R6 avatars get invisible R15 adapter MeshParts welded to R6-named joints. The two descriptions conflict. — [Workspace API](https://create.roblox.com/docs/reference/engine/classes/Workspace); [AvatarUnificationMode enum](https://create.roblox.com/docs/reference/engine/enums/AvatarUnificationMode)
- `StarterPlayer.AvatarJointUpgrade` (RolloutState, Roblox-security): when enabled, avatars spawn with `AnimationConstraint` + `BallSocketConstraint` joints instead of legacy `Motor6D`s. `Workspace.Retargeting` (`AnimatorRetargetingMode`: Default/Disabled/Enabled) adapts animations to rigs of different proportions. — [StarterPlayer API](https://create.roblox.com/docs/reference/engine/classes/StarterPlayer); [Workspace API](https://create.roblox.com/docs/reference/engine/classes/Workspace); [AnimatorRetargetingMode enum](https://create.roblox.com/docs/reference/engine/enums/AnimatorRetargetingMode)
- **Current shipping default-animation files** (Studio 0.744 install manifest): `content/avatar/animations/humanoidR6AnimateChildren.rbxm` (the R6 Animate's StringValue/Animation children), `content/avatar/animations/humanoidR15AnimateChildren.rbxm`, `content/avatar/scripts/humanoidAnimateR15.lua`, `content/avatar/scripts/humanoidAnimatePlayEmote.rbxm`, `content/avatar/unification/humanoidClassicAnimate.lua`, `.../unification/humanoidClassicAnimateDefaultChildren.rbxm`, `.../unification/humanoidAnimateR6WithFace.rbxm`, `.../unification/CharacterEmulation.lua`, `.../unification/v2/R6CollisionEmulation.lua`, and a server-authority set `content/avatar/scripts/humanoidAnimateSAuth/{humanoidAnimateSAuth.lua, RunAnimate.Client.lua, RunAnimate.Server.lua}` (several `_DEPRECATED_2026MMDD` variants are dated July–September 2026). — [Client Tracker rbxManifest.txt](https://raw.githubusercontent.com/MaximumADHD/Roblox-Client-Tracker/roblox/rbxManifest.txt)
- Engine flag names related to R6 and Animate: `FFlagUserAnimateRemoveEmoteChatHook`, `DFFlagRetargetAnimationR15ToR6Rig`, `FFlagAnimationSAuthHighSlotNotifications`, `FFlagIncludeAnimationServerAuthrityFields`. — [Client Tracker FVariables.txt](https://raw.githubusercontent.com/MaximumADHD/Roblox-Client-Tracker/roblox/FVariables.txt)
- Emote APIs: `Humanoid:PlayEmote` is deprecated in favour of `Humanoid:PlayEmoteAsync`; it looks emotes up in the applied `HumanoidDescription` (catalog emotes, `SetEmotes`/`SetEquippedEmotes`, max 8 equipped). — [Humanoid API](https://create.roblox.com/docs/reference/engine/classes/Humanoid); [Emotes guide](https://create.roblox.com/docs/characters/emotes)

### Inferences
- **R6 gotcha 1, "run" is unused:** the R6 script only ever plays `walk`, so editing `run.RunAnim` (which the docs' sample shows) has **no effect on R6**. Edit `walk.WalkAnim`.
- **R6 gotcha 2, custom walk is not speed-scaled:** the speed scaling is tied to the literal default ID 180426354. A replacement walk plays at speed 1 regardless of WalkSpeed. Fix this by forking Animate and removing the ID check (`setAnimationSpeed(speed / 14.5)`, or a value matched to your animation's stride). With default WalkSpeed 16, the default walk plays at about 16/14.5 ≈ 1.10x.
- **R6 gotcha 3, no swim:** the R6 table has no `swim`/`swimidle`. The docs' sample lines `animateScript.swim.Swim...` would index nil and error on R6 (the docs' table is R15-oriented).
- **Why R15/catalog IDs fail on R6:** animation poses are keyed by part names (R15: `UpperTorso`, `LowerTorso`, `LeftUpperArm`…; R6: `Torso`, `Left Arm`, `Right Leg`… with Motor6Ds `Neck`, `Right/Left Shoulder`, `Right/Left Hip` under `Torso` and `RootJoint` under `HumanoidRootPart`). An R15 animation finds no matching R6 parts, so nothing (or almost nothing) moves. The reverse also fails. The catalog bundle IDs in the docs are R15 assets.
- **Cleanest replacement options for R6, ranked:**
  1. Server Script that edits `Animate.<folder>.<Animation>.AnimationId` on `CharacterAppearanceLoaded`/`CharacterAdded`, then stops playing tracks so the change shows immediately. This is the least code and survives engine updates to Animate.
  2. Fork: play-test, copy the character's `Animate` LocalScript, paste it into `StarterPlayer.StarterCharacterScripts` and edit the `animNames` table, the speed divisor and the priorities. This is required for walk-speed scaling of custom walks, custom tool anims, or for moving off the deprecated `Humanoid:LoadAnimation`.
  3. `StarterCharacter` model with its own Animate, for fully custom rigs.

  Example of option 1:

```lua
-- ServerScriptService Script: replace R6 defaults
local Players = game:GetService("Players")
local IDS = {
	walk = { WalkAnim = "rbxassetid://YOUR_WALK" },
	idle = { Animation1 = "rbxassetid://YOUR_IDLE_A", Animation2 = "rbxassetid://YOUR_IDLE_B" },
	jump = { JumpAnim = "rbxassetid://YOUR_JUMP" },
	fall = { FallAnim = "rbxassetid://YOUR_FALL" },
}
local function onCharacter(character)
	local humanoid = character:WaitForChild("Humanoid")
	if humanoid.RigType ~= Enum.HumanoidRigType.R6 then return end
	local animate = character:WaitForChild("Animate")
	for folderName, anims in IDS do
		local folder = animate:WaitForChild(folderName)
		for animName, id in anims do
			folder:WaitForChild(animName).AnimationId = id
		end
	end
	for _, t in humanoid:WaitForChild("Animator"):GetPlayingAnimationTracks() do
		t:Stop(0)
	end
end
Players.PlayerAdded:Connect(function(p) p.CharacterAppearanceLoaded:Connect(onCharacter) end)
```
- Triggering R6 default emotes from code: the mirrored R6 script only listens to `Chatted`. Options: fork Animate and expose a `BindableFunction`/`BindableEvent`, or just load the emote ID yourself (e.g. `128777973` wave) at Action priority on the owning client.

### Gaps
- The manifest proves the current R6 Animate's children ship as `humanoidR6AnimateChildren.rbxm`, and that a "classic" Animate (`humanoidClassicAnimate.lua`) plus a PlayEmote module exist. The Client Tracker repo does not mirror the `content/avatar` files, though (raw paths 404), and the Roblox CDN is blocked here, so their contents were not read. Flag names hint that (a) Roblox is removing the `Chatted`-based "/e" hook from Animate (`FFlagUserAnimateRemoveEmoteChatHook`; emotes would go through TextChatService/PlayEmote instead), (b) R15 animations may become retargetable onto R6 rigs (`DFFlagRetargetAnimationR15ToR6Rig`), which could change the "R15 ids fail on R6" rule, and (c) a server-authoritative Animate (`humanoidAnimateSAuth`, for Roblox's Server Authority mode) is in progress. All three are unconfirmed: flag names are not rollout states.
- The mirrors are older copies (roughly 2016–2018 era). I could not obtain the **current in-engine** R6 Animate source, so it is unverified whether the current version (a) uses `Animator:LoadAnimation` instead of `Humanoid:LoadAnimation`, (b) has a `PlayEmote` BindableFunction like R15's Animate, (c) still uses `Player.Chatted` (with TextChatService the "/e" path may be handled by the default `RBXEmoteCommand`), or (d) names its folder `dance` or `dance1`. Inspect a live character's Animate in a 2026 Studio play-test to confirm.
- How Animate and default R6 animations behave when `AvatarUnificationMode` = Enabled (adapter rigs), and whether `AvatarJointUpgrade` applies to R6 (removing the Motor6Ds that scripts look up), is not documented in detail.

---

## 7. NPC patterns for R6 (Humanoid+Animator vs AnimationController, state machines, performance, LOD/throttling)

### Takeaway
For R6 NPCs that walk with Humanoid physics, use **Humanoid + server-created Animator** and drive idle/walk from `Humanoid.Running` or velocity on the server. For non-walking props or creatures, use **AnimationController + Animator**. For large crowds, the community pattern is server-authoritative position with client-side rendering and animation (not replicated, per-client), distance culling, and reliance on the engine's built-in client animation throttling (`Workspace.ClientAnimatorThrottling`, `Animator.PreferLodEnabled`).

### Cited Findings
- Non-humanoid rigs need `AnimationController` with a child `Animator`. — [Use animations guide](https://create.roblox.com/docs/animation/using); [AnimationController API](https://create.roblox.com/docs/reference/engine/classes/AnimationController)
- `Humanoid:BuildRigFromAttachments()` builds Motor6Ds from `*RigAttachment` attachments; "Motor6D joints are required for the playback of Animations." — [Humanoid API](https://create.roblox.com/docs/reference/engine/classes/Humanoid)
- **Built-in client throttling:** `Workspace.ClientAnimatorThrottling` (`Enum.ClientAnimatorThrottlingMode`: Default/Disabled/Enabled). When enabled, "animations on remotely-simulated Model instances will begin to throttle", based on visibility relative to the camera, in-game FPS and the number of active animations. — [Workspace API](https://create.roblox.com/docs/reference/engine/classes/Workspace); [ClientAnimatorThrottlingMode enum](https://create.roblox.com/docs/reference/engine/enums/ClientAnimatorThrottlingMode)
- **Per-Animator LOD:** `Animator.PreferLodEnabled` (default true) lets the engine "reduce animation evaluation frequency for remotely-simulated characters based on distance, screen coverage, and frame budget". Set it to false for important NPCs; "disabling LOD for many animators simultaneously can impact performance." `Animator.EvaluationThrottled` tells you a frame reused the previous pose, so skip procedural offsets layered on `Transform` that frame. (The docs call the workspace setting "ClientAnimatorThrottlingMode"; the actual property is `Workspace.ClientAnimatorThrottling`.) — [Animator API](https://create.roblox.com/docs/reference/engine/classes/Animator)
- Engine flags for LOD and throttling in the current build: `DFFlagAnimatorLodOptOutPhase`, `DFFlagEnableClientAnimatorThrottlingMode`, `DFFlagDebugAnimationLodEvaluationAndUpdateThrottling`, `DFFlagAnimationThrottlingInertialization`, `FFlagSupportAnimatorInertialBlending`, `FFlagAnimationLodTelemetryEnabled`. The "LodOptOutPhase" name matches the `PreferLodEnabled` opt-out property. — [Client Tracker FVariables.txt](https://raw.githubusercontent.com/MaximumADHD/Roblox-Client-Tracker/roblox/FVariables.txt)
- Community scaling data (search excerpts): one open-source system keeps NPC position on the server and renders NPCs entirely on the client, running 352 NPCs — [NPC System – Open Source](https://devforum.roblox.com/t/npc-system-open-source/1526972). One test of 1,024 NPCs says the server degrades around 150–200 Humanoid NPCs while clients stay fine — [How bad is it using server NPCs?](https://devforum.roblox.com/t/how-bad-is-it-using-server-npcs/3145670). A "Lightweight NPCs" framework demo: 300 NPCs, 500-stud culling radius, about 13 KB/s receive, with extra updates on sudden events like jumps or animation changes — [Lightweight NPCs](https://devforum.roblox.com/t/lightweight-npcs/4224897). See also [NPC Animation Optimization](https://devforum.roblox.com/t/npc-animation-optimization/1316172).
- A Pastebin search result is titled "R6 NPC animate script server", which reflects the common practice of running a copy of the R6 Animate as a server Script in NPCs. — [Pastebin (search result title only)](https://pastebin.com/t0XSkuXS)

### Inferences
- Simple server-side R6 NPC idle/walk state machine:

```lua
-- Script inside an R6 NPC (server). Uses default R6 ids; swap for your own R6 animations.
local humanoid = script.Parent:WaitForChild("Humanoid")
local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator", humanoid)

local function load(id: string, priority: Enum.AnimationPriority): AnimationTrack
	local a = Instance.new("Animation")
	a.AnimationId = id
	local t = animator:LoadAnimation(a)
	t.Priority = priority
	t.Looped = true
	return t
end

local idle = load("rbxassetid://180435571", Enum.AnimationPriority.Idle)
local walk = load("rbxassetid://180426354", Enum.AnimationPriority.Movement)
idle:Play()

local WALK_THRESHOLD = 0.5
humanoid.Running:Connect(function(speed)
	if speed > WALK_THRESHOLD then
		if not walk.IsPlaying then walk:Play(0.2) end
		walk:AdjustSpeed(speed / 14.5)          -- same divisor as default R6 Animate
	elseif walk.IsPlaying then
		walk:Stop(0.2)                          -- idle (lower priority) shows through
	end
end)
humanoid.Died:Connect(function()
	for _, t in animator:GetPlayingAnimationTracks() do t:Stop(0.1) end
end)
```
  Idle keeps playing underneath, and walk at Movement overrides it per joint. That avoids restarting idle and gives clean fades. For NPCs moved by `CFrame` (anchored, no Humanoid physics), `Humanoid.Running` will not fire. Derive speed from position deltas in `Heartbeat` instead, and unanchor the limbs (only the root may be anchored).
- **Server vs client choice for NPCs:**
  - < ~50 NPCs, gameplay-relevant animations (hit timing on the server): play on the server, which replicates automatically.
  - Large crowds or ambient NPCs: replicate only state (e.g. an attribute `State = "Walk"`, or a compact remote), and have each client load and play the tracks locally on its copy (client-only, intentionally not replicated). Cull by distance (stop or `AdjustSpeed(0)` tracks and disconnect beyond N studs, or stream out models), and leave `PreferLodEnabled = true`.
  - Client-only tracks on a server-owned NPC are invisible to the server, so markers for server hitboxes will not fire there. Time server-side hits with a timer or with server-played tracks.
- `AnimationController` is lighter than `Humanoid` (no state machine or physics controller), so it suits stationary or scripted-movement R6 props. An R6 model with an AnimationController still needs the R6 part names and Motor6Ds for R6 animations to map.

### Gaps
- No official numbers for animation evaluation cost per Animator, the exact LOD distance tiers, or which `Default` throttling mode currently applies.
- Whether throttling ever applies to server-side Animators: the docs only mention "remotely-simulated" models on clients.

---

## 8. Tool animations on R6, animation markers for hitboxes/SFX timing, syncing VFX and camera shake

### Takeaway
The default R6 Animate plays `toolnone` (holding pose, Idle priority) whenever a tool with a `Handle` is equipped. A tool triggers `toolslash`/`toollunge` (Action priority) by parenting a `StringValue` named `"toolanim"` with `Value = "Slash"` or `"Lunge"` into itself, which is how the classic Linked Sword works. For new work, author your own animations with **KeyframeMarkers** and use `track:GetMarkerReachedSignal("Name")` to time hitboxes, SFX, VFX and camera shake.

### Cited Findings
- `"toolanim"` StringValue mechanism, priorities and 0.3 s window: see section 6. — [R6 Animate mirror](https://github.com/moiez0/ReanimateTutorial/blob/main/Animate.lua)
- Tool animation values are hard-coded in Animate ("Slash"/"Lunge"); copy Animate to `StarterCharacterScripts` to change them. — [DevForum R6 Linked Sword thread (search excerpt)](https://devforum.roblox.com/t/how-does-the-r6-linked-sword-animations-work-and-does-anyone-have-a-port-of-the-slash-to-a-actual-animation-object/2659745)
- Animation Editor events: enable "Show Animation Events", add named event markers with an optional **Parameter** string, and duplicate markers across the timeline. Detect them with `GetMarkerReachedSignal(name):Connect(function(paramString) ... end)`. — [Animation events guide](https://create.roblox.com/docs/animation/events)
- `KeyframeReached` fires only for keyframes not named "Keyframe" and is superseded by `GetMarkerReachedSignal`. Keyframe names cannot be set by script on an existing animation. — [AnimationTrack API](https://create.roblox.com/docs/reference/engine/classes/AnimationTrack)
- The official sample connects `GetMarkerReachedSignal("KickEnd")` before `Play()` in a LocalScript on the player's character. — [Use animations guide](https://create.roblox.com/docs/animation/using)
- `Animator.AnimationPlayed` fires for every `Play()` on tracks owned by that Animator. — [Animator API](https://create.roblox.com/docs/reference/engine/classes/Animator)

### Inferences
- R6 sword, classic style (inside a Tool's server or local script):

```lua
local function legacySlash(tool: Tool)
	local v = Instance.new("StringValue")
	v.Name = "toolanim"
	v.Value = "Slash"      -- or "Lunge"
	v.Parent = tool        -- default R6 Animate consumes it next frame
end
```
- Modern R6 tool pattern (LocalScript in the Tool, owning client, so it replicates):

```lua
local tool = script.Parent
local holdAnim, slashAnim = tool:WaitForChild("Hold"), tool:WaitForChild("Slash") -- Animation objects (R6!)
local hold, slash
tool.Equipped:Connect(function()
	local animator = tool.Parent:WaitForChild("Humanoid"):WaitForChild("Animator")
	hold = hold or animator:LoadAnimation(holdAnim)
	slash = slash or animator:LoadAnimation(slashAnim)
	hold.Priority, hold.Looped = Enum.AnimationPriority.Idle, true      -- beats Core toolnone/idle on arm
	slash.Priority = Enum.AnimationPriority.Action
	slash:GetMarkerReachedSignal("Hit"):Connect(function(param)
		-- enable client hitbox window / request server validation
	end)
	slash:GetMarkerReachedSignal("Swoosh"):Connect(function()
		-- play SFX / VFX at the blade
	end)
	hold:Play(0.1)
end)
tool.Unequipped:Connect(function()
	if hold then hold:Stop(0.1) end
end)
tool.Activated:Connect(function()
	if slash and not slash.IsPlaying then slash:Play(0.05) end
end)
```
  The tracks are cached per equip here. With respawns, the cache must be reset when the Animator changes (new character), otherwise the stored tracks belong to a destroyed Animator.
- Hold animations at **Idle** override the Core `toolnone` and idle on the keyed arm. If your hold animation keys only `Right Shoulder`, the legs keep walking normally (per-joint blending).
- Camera shake / VFX sync: connect markers on the client that plays the track (owner) and drive the shake from the marker callback (e.g. a decaying offset applied in `RenderStepped`). Other clients can listen on the character's Animator through `AnimationPlayed`, match `track.Animation.AnimationId`, and attach marker listeners to that replicated track for cosmetic VFX. This is a widely used pattern, but no doc confirms that marker signals fire on replicated (non-owner) tracks; test it.
- Hitboxes: authoritative hit detection should not depend only on a client marker. Either run a server timer derived from `GetTimeOfKeyframe`/known marker times (after `Length > 0`), or accept client hit reports and validate them on the server (distance, cooldown, whether the attack was actually started).

### Gaps
- No official confirmation of whether `GetMarkerReachedSignal` fires on the server for tracks played by the owning client and replicated to the server, or on other clients' replicated copies.

---

## 9. Checklist: most common reasons an animation does not play or looks wrong

### Takeaway
Most failures come from ownership/permissions, rig mismatch (R15 animation on R6), Animator or replication mistakes (client-made Animator, client-played NPC), priority problems (Core, or same-priority 50/50 blending), loop settings, or rig physics problems (anchored limbs, missing Motor6Ds).

### Cited Findings
- **Asset ownership:** "Failed to load animation (sanitized ID)" appears when the animation is not owned by the experience owner (the user, or the group for group games). Group-owned animations can fail in Studio for a tester's personal session, and some threads report intermittent group failures for a minority of players. Use the `rbxassetid://` form. — [DevForum 3111789 (search excerpt)](https://devforum.roblox.com/t/failed-to-load-animation-with-sanitized-id/3111789); [DevForum 859578 (search excerpt)](https://devforum.roblox.com/t/failed-to-load-animation/859578); [DevForum 3690182 (search excerpt)](https://devforum.roblox.com/t/failed-to-load-animation/3690182); [DevForum 4743904 (search excerpt)](https://devforum.roblox.com/t/insertserviceloadasset-returning-false-user-is-not-authorized-to-access-asset-rejects/4743904)
- **Animator created on the client / NPC played on the client:** no replication. — [Animator API](https://create.roblox.com/docs/reference/engine/classes/Animator)
- **Animator not in Workspace:** `LoadAnimation` errors (AnimationClipProvider). — [Animator API](https://create.roblox.com/docs/reference/engine/classes/Animator)
- **Priority:** default animations run at Core. Same-priority tracks blend in proportion to weight instead of overriding. — [AnimationPriority enum](https://create.roblox.com/docs/reference/engine/enums/AnimationPriority); [DevForum 1689233 (search excerpt)](https://devforum.roblox.com/t/new-animation-priorities-causes-serious-problems-action2-action3-action4/1689233)
- **Loop:** `Looped` defaults to the authored value, and a runtime change applies after the current cycle. — [AnimationTrack API](https://create.roblox.com/docs/reference/engine/classes/AnimationTrack)
- **Not loaded yet:** `Length == 0`. `TimePosition` set before `Play()` is ignored. — [AnimationTrack API](https://create.roblox.com/docs/reference/engine/classes/AnimationTrack)
- **Motor6D missing / wrong rig:** Motor6Ds are required for playback, and the R6 head must connect to `Torso`. — [Humanoid API](https://create.roblox.com/docs/reference/engine/classes/Humanoid). For custom rigs, check that `AssemblyRootPart` is the part that should stay still ("PrimaryPart does not set the assembly root"). — [Animation Editor guide](https://create.roblox.com/docs/animation/editor)
- **Stop(0) freeze:** with `Motor6D.MaxVelocity = 0`, joints freeze. — [AnimationTrack API](https://create.roblox.com/docs/reference/engine/classes/AnimationTrack)
- **Procedural code fighting the Animator:** the Animator overwrites `Motor6D.Transform` every frame between PreAnimation and PreSimulation. — [Motor6D API](https://create.roblox.com/docs/reference/engine/classes/Motor6D)
- **Too many tracks:** "Animation Track Limit of 256 tracks for one animator exceeded". — [DevForum 2622870 (search excerpt)](https://devforum.roblox.com/t/tool-error-animation-track-limit-of-256-tracks-for-one-animator-exceeded/2622870)
- **Throttled far-away NPCs look choppy:** expected LOD behaviour. Set `PreferLodEnabled = false` for hero NPCs. — [Animator API](https://create.roblox.com/docs/reference/engine/classes/Animator)

### Inferences
Debugging checklist (ordered by how often each comes up):
1. **Output shows "Failed to load animation"** → the ID is not owned by the game owner or group, is not an animation asset (e.g. you pasted a catalog/bundle item ID instead of the animation asset ID), or Studio is running under your personal account for a group asset. Re-upload under the right owner.
2. **Rig mismatch** → an R15 or catalog animation on an R6 rig (or the reverse) moves nothing. Check `humanoid.RigType` and confirm the animation was authored on an R6 rig (Torso/Left Arm/…). Check that the game's Avatar Settings is set to R6.
3. **Priority** → your track is at Core or Idle and gets overridden or half-blended by Animate's Core tracks or your own Movement track. Set `track.Priority` explicitly (Action for actions, Action2+ to sit above other actions), or set it in the Animation Editor before publishing.
4. **Same priority, two tracks** → 50/50 blend. Stop the old one or bump the priority.
5. **Plays on the owner but not for others** → wrong peer: an NPC played from a LocalScript, an Animator created by a LocalScript, or tracks played on a model that is not the player's own character.
6. **Played before the character or Animator existed** → use `player.CharacterAdded`, `character:WaitForChild("Humanoid"):WaitForChild("Animator")`, and re-load tracks after each respawn (old tracks belong to the old Animator).
7. **Plays once then stops** → `Looped` is false (set it in the editor or `track.Looped = true`), or the Animate script replaced it: the R6 Animate restarts tracks on state changes only for its own tracks, but your own `Stop()` calls or `GetPlayingAnimationTracks()` loops may kill it.
8. **Nothing moves although IsPlaying is true** → limbs are anchored (only `HumanoidRootPart` may be anchored), Motor6Ds are missing or renamed (R6 needs `Neck`, `Right/Left Shoulder`, `Right/Left Hip` in Torso and `RootJoint` in HumanoidRootPart), the part names differ from those the animation keys, the weight is 0, or the speed is 0.
9. **Snaps or jitters** → `fadeTime = 0` on Play/Stop, procedural `C0`/`Transform` writes fighting the Animator (write `Transform` after the Animator, or use `C0`), or `MaxVelocity` issues on Stop(0).
10. **Custom walk looks like moonwalking at high WalkSpeed (R6)** → the default R6 Animate only speed-scales the default walk ID. Fork Animate or `AdjustSpeed` yourself.
11. **Edited `run` on R6 and nothing changed** → R6 uses `walk` only.
12. **Hitch on first play** → not preloaded. Use `PreloadAsync` with the Animation instances.
13. **Performance or "AnimationTrack limit" warning** → `LoadAnimation` is being called every time the animation plays. Cache tracks, `Destroy()` unused ones, and use `GetTrackByAnimationId`.
14. **Far NPCs choppy** → engine LOD/throttling (`PreferLodEnabled`, `Workspace.ClientAnimatorThrottling`).
15. **2025–2026 avatar changes** → if the experience enables the R6→R15 adapter (`AvatarUnificationMode`) or joint upgrade, scripts that look up specific `Motor6D`s or part names may break. Verify the rig contents at runtime.

### Gaps
- No official list of animation-loading error strings. The exact current wording of the ownership error ("sanitized ID") comes from forum titles.
- Whether Roblox's 2024–2026 asset-permission changes (sharing animations between creators or groups) remove some ownership failures was not researched here.
