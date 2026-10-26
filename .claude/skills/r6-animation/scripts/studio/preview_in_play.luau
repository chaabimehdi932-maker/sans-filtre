-- preview_in_play.luau - watch a generated KeyframeSequence on the REAL character without publishing.
-- 1. Press Play (or Run) in Studio.  2. In the Explorer, select the KeyframeSequence (it lives in
-- ServerStorage.RBX_ANIMSAVES.<Rig> after the generated install script).  3. Run this in the Command Bar.
-- Plays it on the first player's character (or a selected rig) at Action4, looping LOOPS times, so you
-- can check the start, middle, end, interruption and blending with the default animations.
local LOOPS = 3
local SPEED = 1

local Selection = game:GetService("Selection")
local kfs = Selection:Get()[1]
assert(kfs and kfs:IsA("KeyframeSequence"), "Select a KeyframeSequence first")
local id = game:GetService("KeyframeSequenceProvider"):RegisterKeyframeSequence(kfs)
local player = game:GetService("Players"):GetPlayers()[1]
local character = player and player.Character
assert(character, "Press Play first (no player character yet)")
local humanoid = character:FindFirstChildOfClass("Humanoid")
local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator", humanoid)
local anim = Instance.new("Animation")
anim.AnimationId = id
local track = animator:LoadAnimation(anim)
track.Priority = Enum.AnimationPriority.Action4
track.Looped = kfs.Loop
for i = 1, LOOPS do
	track:Play(0.1, 1, SPEED)
	task.wait(track.Length / SPEED + 0.3)
end
print("Previewed " .. kfs.Name .. " (" .. string.format("%.2f", track.Length) .. "s)")
