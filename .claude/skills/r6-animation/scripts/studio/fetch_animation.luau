-- fetch_animation.luau - get an EXISTING published animation as an editable KeyframeSequence.
-- Paste the asset id below, run in the Command Bar (Edit mode). Works for animations this place/your
-- account may load (2025+ permissions: owned by you/your group or granted to this experience).
-- Then: right-click the new KeyframeSequence in ServerStorage > Save to File... > *.rbxmx and run
--   python scripts/r6anim.py import <file>.rbxmx -o original.json
-- Keep that original untouched: it is the "before" for `r6anim.py compare`.
local ID = 0 -- <- animation asset id (the number in rbxassetid://...)

assert(ID ~= 0, "Set ID to the animation's asset id first")
local KSP = game:GetService("KeyframeSequenceProvider")
local ok, kfs = pcall(function()
	return KSP:GetKeyframeSequenceAsync("rbxassetid://" .. ID)
end)
assert(ok and kfs, "Could not load animation " .. ID .. ": " .. tostring(kfs) .. " (permissions? wrong id? R15 asset?)")
kfs.Name = "Fetched_" .. ID
kfs.Parent = game:GetService("ServerStorage")
game:GetService("Selection"):Set({ kfs })
local n, poses, markers = 0, {}, {}
for _, k in ipairs(kfs:GetKeyframes()) do
	n = n + 1
	for _, d in ipairs(k:GetDescendants()) do
		if d:IsA("Pose") and d.Weight > 0 then
			poses[d.Name] = true
		elseif d:IsA("KeyframeMarker") then
			table.insert(markers, ("%s@%.3f"):format(d.Name, k.Time))
		end
	end
end
local names = {}
for k in pairs(poses) do
	table.insert(names, k)
end
print(("Fetched %s: %d keyframes, Loop=%s, Priority=%s"):format(kfs.Name, n, tostring(kfs.Loop), kfs.Priority.Name))
print("Keyed parts: " .. table.concat(names, ", "))
print("Markers (gameplay may depend on these - preserve them): " .. (#markers > 0 and table.concat(markers, ", ") or "none"))
if poses["UpperTorso"] or poses["LowerTorso"] then
	warn("This is an R15 animation: it will not play on an R6 rig.")
end
