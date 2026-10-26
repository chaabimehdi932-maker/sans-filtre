"""Runs the Studio helper scripts against a small mock of the Roblox API (needs `pip install lupa`).

check_contact.luau is fed frames computed by r6core, on a rig standing on a raised platform,
and must find the same contact problems the offline lint finds.

Run:  python tests/test_studio.py
"""

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "scripts"))

from r6core import CF, load_spec, forward_kinematics, sample  # noqa: E402

try:
    import lupa  # noqa: F401
except ImportError:  # pragma: no cover
    lupa = None

MOCK = r"""
local CFMT = {}
CFMT.__index = function(t, k)
  if k == "Position" then return Vector3.new(t.x, t.y, t.z) end
  if k == "LookVector" then return Vector3.new(-t.r[3], -t.r[6], -t.r[9]) end
  return CFMT[k]
end
function CFMT.PointToWorldSpace(a, v)
  local r = a.r
  return Vector3.new(r[1]*v.X + r[2]*v.Y + r[3]*v.Z + a.x, r[4]*v.X + r[5]*v.Y + r[6]*v.Z + a.y,
                     r[7]*v.X + r[8]*v.Y + r[9]*v.Z + a.z)
end
function makeCF(x, y, z, r) return setmetatable({x = x, y = y, z = z, r = r}, CFMT) end
local VMT = {}
VMT.__index = VMT
VMT.__add = function(a, b) return Vector3.new(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
VMT.__div = function(a, n) return Vector3.new(a.X / n, a.Y / n, a.Z / n) end
Vector3 = {new = function(x, y, z) return setmetatable({X = x or 0, Y = y or 0, Z = z or 0}, VMT) end}
Vector2 = {new = function(x, y) return {X = x, Y = y, Magnitude = math.sqrt(x * x + y * y)} end}
Enum = {RaycastFilterType = {Exclude = "Exclude"}, AnimationPriority = {Action4 = "Action4"}}
RaycastParams = {new = function() return {} end}
OUT = {}
print = function(s) table.insert(OUT, "PRINT " .. s) end
warn = function(s) table.insert(OUT, "WARN " .. s) end

local function inst(class, name)
  local o = {ClassName = class, Name = name or class, children = {}}
  function o:IsA(c) return self.ClassName == c end
  function o:FindFirstChild(n) for _, c in ipairs(self.children) do if c.Name == n then return c end end end
  function o:FindFirstChildOfClass(c) for _, ch in ipairs(self.children) do if ch.ClassName == c then return ch end end end
  function o:FindFirstAncestorOfClass(c) local p = self.Parent while p do if p.ClassName == c then return p end p = p.Parent end end
  function o:Destroy() end
  return o
end
local function add(parent, child) child.Parent = parent table.insert(parent.children, child) return child end

-- FRAMES[i] = {right = {x,y,z,r}, left = {...}} at 60 fps; REST likewise; FLOOR = y of the platform
rig = inst("Model", "Dummy")
local hum = add(rig, inst("Humanoid"))
local hrp = add(rig, inst("Part", "HumanoidRootPart"))
hrp.CFrame = makeCF(0, FLOOR + 3, 0, {1, 0, 0, 0, 1, 0, 0, 0, 1})
local legs = {}
for _, n in ipairs({"Right Leg", "Left Leg"}) do
  local p = add(rig, inst("Part", n))
  p.Size = Vector3.new(1, 2, 1)
  legs[n] = p
end
local function pose(f)
  for n, key in pairs({["Right Leg"] = "right", ["Left Leg"] = "left"}) do
    local d = f[key]
    legs[n].CFrame = makeCF(d[1], d[2], d[3], d[4])
    legs[n].Position = Vector3.new(d[1], d[2], d[3])
  end
end
pose(REST)
local track = {Length = LENGTH, playing = false, time = 0}
function track:Play() self.playing = true self.time = 0 end
function track:Stop() self.playing = false end
local animator = add(hum, inst("Animator"))
function animator:GetPlayingAnimationTracks() return {} end
function animator:LoadAnimation() return track end
function animator:StepAnimations(dt)
  if track.playing then
    track.time = track.time + dt
    local i = math.min(#FRAMES, math.floor(track.time * 60 + 0.5) + 1)
    pose(FRAMES[i])
  else
    pose(REST)
  end
end
kfs = inst("KeyframeSequence", "Anim")
local services = {
  Selection = {Get = function() return {rig, kfs} end},
  KeyframeSequenceProvider = {RegisterKeyframeSequence = function() return "rbxassetid://0" end},
}
game = {GetService = function(_, n) return services[n] end}
Instance = {new = function(c, parent) local o = inst(c) if parent then add(parent, o) end return o end}
workspace = {Raycast = function(_, origin, dir, params)
  if origin.Y > FLOOR then return {Position = Vector3.new(origin.X, FLOOR, origin.Z)} end
end}
"""

PLATFORM = 5.0  # the rig stands on a part whose top is at y = 5


def _frames(anim):
    hrp = CF(0, 3 + PLATFORM, 0)
    tracks = anim.tracks()
    n = int(round(anim.length * 60))
    out = []
    for i in range(n + 1):
        parts = forward_kinematics(sample(anim, i / 60, tracks), hrp)
        out.append({side: [parts[p].x, parts[p].y, parts[p].z, list(parts[p].r)]
                    for side, p in (("right", "Right Leg"), ("left", "Left Leg"))})
    rest = forward_kinematics({}, hrp)
    rest = {side: [rest[p].x, rest[p].y, rest[p].z, list(rest[p].r)]
            for side, p in (("right", "Right Leg"), ("left", "Left Leg"))}
    return out, rest


def run_check(anim, speed=0):
    L = lupa.LuaRuntime(unpack_returned_tuples=True)
    frames, rest = _frames(anim)

    def lua_val(v):
        if isinstance(v, (list, tuple)):
            t = L.table()
            for i, x in enumerate(v, 1):
                t[i] = lua_val(x)
            return t
        if isinstance(v, dict):
            t = L.table()
            for k, x in v.items():
                t[k] = lua_val(x)
            return t
        return v
    g = L.globals()
    g.FRAMES = lua_val(frames)
    g.REST = lua_val(rest)
    g.LENGTH = anim.length
    g.FLOOR = PLATFORM
    L.execute(MOCK)
    with open(os.path.join(HERE, "..", "scripts", "studio", "check_contact.luau"), encoding="utf-8") as fh:
        src = fh.read()
    assert "local SPEED = 0 " in src
    L.execute(src.replace("local SPEED = 0 ", f"local SPEED = {speed} ", 1))
    return [g.OUT[i] for i in range(1, len(g.OUT) + 1)]


def test_clean_walk_on_platform():
    walk = load_spec(os.path.join(HERE, "..", "recipes", "walk.json"))
    out = run_check(walk, speed=walk.speed)
    assert any("No feet into the floor" in s for s in out), out
    # played in place (speed 0) the stance foot sweeps back 2.4 studs: that IS sliding
    assert any("slides" in s for s in run_check(walk, speed=0))
    assert not any(s.startswith("WARN") for s in out), out


def test_finds_feet_in_floor_and_sliding():
    # crouching without 'plant': the legs just go through the floor, and the twist drags the feet
    bad = load_spec({"name": "Bad", "keyframes": [
        {"t": 0, "Torso": {"up": 0}},
        {"t": 0.3, "Torso": {"up": -0.6, "twist": 40}},
        {"t": 0.6, "Torso": {"up": 0}}]})
    out = run_check(bad)
    assert any(s.startswith("WARN") and "INTO the floor" in s for s in out), out
    assert any(s.startswith("WARN") and "slides" in s for s in out), out


def test_jump_reports_air_not_error():
    out = run_check(load_spec(os.path.join(HERE, "..", "recipes", "dash.json")))
    assert any("Both feet are off the floor" in s for s in out), out
    assert not any(s.startswith("WARN") for s in out), out


if __name__ == "__main__":
    if lupa is None:
        print("skip: pip install lupa to run the Studio script tests")
        sys.exit(0)
    for name, fn in sorted(globals().items()):
        if name.startswith("test_") and callable(fn):
            fn()
            print("ok  ", name)
