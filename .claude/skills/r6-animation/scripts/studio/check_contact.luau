-- check_contact.luau - measure an animation's ground contact ON THE REAL RIG, against the REAL floor.
-- Edit mode, no Play needed. In the Explorer select the rig Model AND the KeyframeSequence (Ctrl-click
-- both; an Animation object with an AnimationId you own works too), then paste this into the Command Bar.
--
-- It steps the animation frame by frame (Animator:StepAnimations), takes the 8 world-space corners of
-- each Leg part, and raycasts straight down from that leg to the floor actually under it (terrain or
-- parts, the rig excluded) - so stairs, slopes and raised platforms are measured, not assumed at Y = 0.
-- Reports: feet pushed into the floor, both feet off the floor, and how far each planted foot's
-- contact point slides (on the ground: set SPEED for walk/run cycles). If the rig itself floats or sinks in the scene at rest, that offset is printed
-- and removed (in game the Humanoid places the root so the rest pose stands on the floor).
local FPS = 60
local TOL = 0.1 -- studs of penetration/float ignored (invisible at play speed)
local CONTACT = 0.12 -- a leg whose lowest corner is this close to the floor touches it
local PLANTED = 0.05 -- ...and this close, it is planted (lifting/landing frames don't count as sliding)
local SLIDE = 0.25 -- studs a planted foot may drift before it reads as sliding
local SPEED = 0 -- walk/run cycles: the WalkSpeed it plays at (the body moves forward, so a planted foot
-- sweeping back at that speed stands still on the ground). 0 for everything else.

local Selection = game:GetService("Selection")
local rig, source
for _, inst in ipairs(Selection:Get()) do
	if inst:IsA("KeyframeSequence") or inst:IsA("Animation") then
		source = inst
	elseif inst:IsA("Model") then
		rig = inst
	elseif inst:FindFirstAncestorOfClass("Model") and not rig then
		rig = inst:FindFirstAncestorOfClass("Model")
	end
end
assert(rig and source, "Select the rig Model and the KeyframeSequence (or Animation) together")
local humanoid = rig:FindFirstChildOfClass("Humanoid")
local controller = humanoid or rig:FindFirstChildOfClass("AnimationController")
assert(controller, "The rig needs a Humanoid or an AnimationController")
local animator = controller:FindFirstChildOfClass("Animator") or Instance.new("Animator", controller)
local legs = { rig:FindFirstChild("Right Leg"), rig:FindFirstChild("Left Leg") }
local root = rig:FindFirstChild("HumanoidRootPart") or rig.PrimaryPart or rig:FindFirstChild("Torso")
assert(legs[1] and legs[2], "No 'Right Leg' / 'Left Leg' parts: this is not a classic R6 rig")

local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude
params.FilterDescendantsInstances = { rig }

local function corners(part)
	local out, h = {}, part.Size / 2
	for _, sx in ipairs({ -1, 1 }) do
		for _, sy in ipairs({ -1, 1 }) do
			for _, sz in ipairs({ -1, 1 }) do
				table.insert(out, part.CFrame:PointToWorldSpace(Vector3.new(sx * h.X, sy * h.Y, sz * h.Z)))
			end
		end
	end
	return out
end

local function measure(part)
	-- lowest corner, the floor under the leg, and the sole centre
	local low = math.huge
	for _, c in ipairs(corners(part)) do
		low = math.min(low, c.Y)
	end
	local origin = part.Position + Vector3.new(0, 4, 0)
	local hit = workspace:Raycast(origin, Vector3.new(0, -60, 0), params)
	local floor = hit and hit.Position.Y or nil
	local sole = part.CFrame:PointToWorldSpace(Vector3.new(0, -part.Size.Y / 2, 0))
	return low, floor, sole
end

for _, t in ipairs(animator:GetPlayingAnimationTracks()) do
	t:Stop(0)
end
animator:StepAnimations(0)
local restOffset = math.huge
for _, leg in ipairs(legs) do
	local low, floor = measure(leg)
	assert(floor, "No floor under " .. leg.Name .. ": put a part or terrain under the rig")
	restOffset = math.min(restOffset, low - floor)
end
if math.abs(restOffset) > 0.02 then
	print(("Rig rest pose stands %.2f studs %s the floor here; measuring relative to the rest pose."):format(
		math.abs(restOffset), restOffset > 0 and "above" or "into"))
end

local anim = source
if source:IsA("KeyframeSequence") then
	anim = Instance.new("Animation")
	anim.AnimationId = game:GetService("KeyframeSequenceProvider"):RegisterKeyframeSequence(source)
end
local track = animator:LoadAnimation(anim)
track.Priority = Enum.AnimationPriority.Action4
track:Play(0, 1, 1)
animator:StepAnimations(0)
local length = track.Length
if length <= 0 then
	animator:StepAnimations(1 / FPS)
	length = track.Length
end
assert(length > 0, "Animation did not load (check you own/can access it)")

local sinks, floats, slides = {}, {}, {}
local airborne -- current run of frames with both feet off the floor
local runs = { {}, {} }
local frames = math.floor(length * FPS + 0.5)
local function note(list, key, t, v)
	local e = list[key]
	if not e then
		e = { t0 = t, t1 = t, worst = v, at = t }
		list[key] = e
	end
	e.t1 = t
	if v > e.worst then
		e.worst, e.at = v, t
	end
end
for f = 0, frames do
	local t = f / FPS
	if f > 0 then
		animator:StepAnimations(1 / FPS)
	end
	local touching = 0
	for i, leg in ipairs(legs) do
		local low, floor, sole = measure(leg)
		local h = (floor and (low - floor) or (low - 0)) - restOffset
		if h < -TOL then
			note(sinks, leg.Name, t, -h)
		end
		if h <= CONTACT then
			touching = touching + 1
		end
		if h <= PLANTED then
			local run = runs[i]
			if not run.start then
				run.start, run.t0 = sole, t
			end
			-- where the foot is on the ground: the character has moved SPEED * time along its facing
			local look = root.CFrame.LookVector
			local moved = SPEED * (t - run.t0)
			local d = Vector2.new(sole.X - run.start.X + look.X * moved, sole.Z - run.start.Z + look.Z * moved).Magnitude
			if d > SLIDE then
				note(slides, leg.Name .. " (planted from " .. string.format("%.2f", run.t0) .. "s)", t, d)
			end
		else
			runs[i] = {}
		end
	end
	if touching == 0 then
		if not airborne then
			airborne = { t0 = t, t1 = t }
			table.insert(floats, airborne)
		end
		airborne.t1 = t
	else
		airborne = nil
	end
end
track:Stop(0)
animator:StepAnimations(0)
if anim ~= source then
	anim:Destroy()
end

print(("check_contact: %s on %s, %.2fs, %d frames"):format(source.Name, rig.Name, length, frames + 1))
local clean = true
for name, e in pairs(sinks) do
	clean = false
	warn(("%s goes %.2f studs INTO the floor (worst at %.2fs; %.2f-%.2fs). Plant the key, lift the free leg, "
		.. "or add a breakdown where interpolation dips it."):format(name, e.worst, e.at, e.t0, e.t1))
end
for name, e in pairs(slides) do
	clean = false
	warn(("%s slides %.2f studs while touching the floor (worst at %.2fs). Keep the planted foot's leg "
		.. "values identical across the stance, or lift it for a step."):format(name, e.worst, e.at))
end
for _, e in ipairs(floats) do
	print(("Both feet are off the floor %.2f-%.2fs - fine for a jump/dash/flight phase, a bug for a "
		.. "standing pose."):format(e.t0, e.t1))
end
if clean then
	print("No feet into the floor, no planted foot sliding.")
end
