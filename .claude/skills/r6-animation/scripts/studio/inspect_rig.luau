-- inspect_rig.luau - verify the REAL rig before animating it (R6 specialist rule: never guess).
-- Select the rig (the character Model, or any part inside it) and paste this into the Command Bar.
-- Prints: rig type, the six parts and their sizes, every Motor6D (Part0 -> Part1, C0, C1), anything
-- non-standard (custom joint values, renamed joints, AnimationConstraint "upgraded" joints, missing
-- parts, anchored limbs), and - if the joints differ from default R6 - the exact "rig" block to
-- paste into your animation spec so the converter uses YOUR rig's joints.
local HttpService = game:GetService("HttpService")
local sel = game:GetService("Selection"):Get()[1]
local rig = sel and (sel:IsA("Model") and sel or sel:FindFirstAncestorOfClass("Model"))
assert(rig, "Select the rig Model (or a part inside it) first")

local DEFAULT = {
	["RootJoint"] = { C0 = {0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0}, C1 = {0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0} },
	["Neck"] = { C0 = {0, 1, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0}, C1 = {0, -0.5, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0} },
	["Right Shoulder"] = { C0 = {1, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0}, C1 = {-0.5, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0} },
	["Left Shoulder"] = { C0 = {-1, 0.5, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0}, C1 = {0.5, 0.5, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0} },
	["Right Hip"] = { C0 = {1, -1, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0}, C1 = {0.5, 1, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0} },
	["Left Hip"] = { C0 = {-1, -1, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0}, C1 = {-0.5, 1, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0} }
}
local ALIASES = { ["Root Hip"] = "RootJoint" }
local PARTS = { "HumanoidRootPart", "Torso", "Head", "Left Arm", "Right Arm", "Left Leg", "Right Leg" }

local function comps(cf)
	return { cf:GetComponents() }
end
local function same(a, b)
	for i = 1, 12 do
		if math.abs(a[i] - b[i]) > 1e-3 then
			return false
		end
	end
	return true
end
local function r3(v)
	return math.floor(v * 1000 + 0.5) / 1000
end

local issues, overrides, joints = {}, {}, {}
local hum = rig:FindFirstChildOfClass("Humanoid")
print(("Rig '%s' - Humanoid: %s, RigType: %s, Animator: %s, AnimationController: %s"):format(
	rig.Name,
	tostring(hum ~= nil),
	hum and hum.RigType.Name or "n/a",
	tostring(hum and hum:FindFirstChildOfClass("Animator") ~= nil),
	tostring(rig:FindFirstChildOfClass("AnimationController") ~= nil)
))
if hum and hum.RigType ~= Enum.HumanoidRigType.R6 then
	table.insert(issues, "Humanoid.RigType is " .. hum.RigType.Name .. ", not R6: R6 animations will not map")
end
for _, name in ipairs(PARTS) do
	local p = rig:FindFirstChild(name)
	if not p then
		table.insert(issues, "missing part '" .. name .. "'")
	else
		print(("  part %-16s size %s%s"):format(name, tostring(p.Size), p.Anchored and "  ANCHORED" or ""))
		if p.Anchored and name ~= "HumanoidRootPart" then
			table.insert(issues, name .. " is anchored: animations cannot move it")
		end
	end
end
for _, d in ipairs(rig:GetDescendants()) do
	if d:IsA("Motor6D") then
		local key = ALIASES[d.Name] or d.Name
		local c0, c1 = comps(d.C0), comps(d.C1)
		print(("  Motor6D %-15s %s -> %s (in %s)"):format(d.Name, d.Part0 and d.Part0.Name or "nil",
			d.Part1 and d.Part1.Name or "nil", d.Parent.Name))
		joints[key] = true
		if ALIASES[d.Name] then
			table.insert(issues, ("root motor is named '%s' (fine for animations, which match PART names; scripts that look up '%s' must use this name)"):format(d.Name, key))
		end
		local def = DEFAULT[key]
		if not def then
			table.insert(issues, "non-standard Motor6D '" .. d.Name .. "' (custom rig: extra joint)")
		elseif not (same(c0, def.C0) and same(c1, def.C1)) then
			local o = { C0 = {}, C1 = {} }
			for i = 1, 12 do
				o.C0[i] = r3(c0[i])
				o.C1[i] = r3(c1[i])
			end
			overrides[key] = o
		end
	elseif d:IsA("AnimationConstraint") then
		table.insert(issues, "AnimationConstraint joint '" .. d:GetFullName() .. "' (upgraded joints): verify playback in Studio")
	end
end
for key in pairs(DEFAULT) do
	if not joints[key] then
		table.insert(issues, "missing Motor6D '" .. key .. "'")
	end
end
if #issues == 0 then
	print("OK: standard classic R6 rig.")
else
	for _, m in ipairs(issues) do
		warn("  " .. m)
	end
end
if next(overrides) then
	warn('Joint values differ from default R6. Add this to the spec so the converter uses this rig:')
	print('"rig": ' .. HttpService:JSONEncode(overrides))
else
	print("Joint C0/C1 match default R6: no \"rig\" overrides needed.")
end
