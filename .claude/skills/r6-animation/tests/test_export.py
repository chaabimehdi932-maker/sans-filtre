"""Exporter checks: .rbxmx structure, import round trip, and the generated Command Bar
Luau executed against a tiny mock of the Roblox API (needs `pip install lupa`; skipped
otherwise) to prove it builds the same KeyframeSequence as the .rbxmx.

Run:  python tests/test_export.py
"""

import math
import os
import sys
import xml.etree.ElementTree as ET

HERE = os.path.dirname(__file__)
sys.path.insert(0, os.path.join(HERE, "..", "scripts"))

from r6core import JOINT_KEYS, angle_between, load_spec, sample  # noqa: E402
from r6export import ease_to_enums, from_rbxmx, to_luau, to_rbxmx  # noqa: E402
from r6core import parse_ease  # noqa: E402

SPEC = {
    "name": "ExportTest", "loop": False, "priority": "Action2", "fps": 60,
    "keyframes": [
        {"f": 0, "Torso": {"lean": 5, "up": -0.2}, "RightArm": {"forward": 30}, "LeftLeg": {"forward": 10}},
        {"f": 6, "RightArm": {"forward": 120, "out": 20, "ease": "constant"}, "ease": "out"},
        {"f": 12, "name": "hit", "Head": {"nod": 10}, "RightArm": {"forward": 90}, "ease": "elastic.out"},
        {"f": 30, "Torso": {}, "RightArm": {}, "Head": {}, "LeftLeg": {}},
    ],
    "markers": [{"f": 12, "name": "Hit", "value": "heavy"}, {"f": 20, "name": "Sfx"}],
}


def _xml_tree():
    anim = load_spec(SPEC)
    return anim, ET.fromstring(to_rbxmx(anim))


def _props(item):
    out = {}
    for el in item.find("Properties"):
        if el.tag == "CoordinateFrame":
            out[el.get("name")] = tuple(float(el.find(n).text) for n in
                                        ("X", "Y", "Z", "R00", "R01", "R02", "R10", "R11", "R12", "R20", "R21", "R22"))
        else:
            out[el.get("name")] = el.text
    return out


def _flatten_xml(item, depth=0):
    rows = []
    for child in item.findall("Item"):
        p = _props(child)
        rows.append((depth, child.get("class"), p.get("Name"), p))
        rows += _flatten_xml(child, depth + 1)
    return rows


def test_rbxmx_structure():
    anim, root = _xml_tree()
    kfs = root.find("Item")
    assert kfs.get("class") == "KeyframeSequence"
    p = _props(kfs)
    assert p["Priority"] == "3" and p["Loop"] == "false" and p["Name"] == "ExportTest"
    kfs_items = kfs.findall("Item")
    times = [float(_props(k)["Time"]) for k in kfs_items]
    assert times == sorted(times)
    assert any(abs(t - 20 / 60) < 1e-4 for t in times)  # marker-only keyframe was created
    # keyframe f6 keys only the right arm: HRP and Torso must be Weight-0 placeholders
    k6 = kfs_items[1]
    hrp = k6.find("Item")
    torso = hrp.find("Item")
    assert _props(hrp)["Name"] == "HumanoidRootPart" and _props(hrp)["Weight"] == "0"
    assert _props(torso)["Name"] == "Torso" and _props(torso)["Weight"] == "0"
    kids = [_props(c)["Name"] for c in torso.findall("Item")]
    assert kids == ["Right Arm"]
    arm = _props(torso.find("Item"))
    assert arm["Weight"] == "1" and arm["EasingStyle"] == "1" and arm["EasingDirection"] == "1"  # Constant/Out


def test_ease_mapping():
    assert ease_to_enums(parse_ease("out")) == (5, 1)  # CubicV2 Out = decelerate (TweenService meaning)
    assert ease_to_enums(parse_ease("in")) == (5, 0)
    assert ease_to_enums(parse_ease("inout")) == (5, 2)
    assert ease_to_enums(parse_ease("constant")) == (1, 1)  # Constant must be Out to hold-then-snap
    assert ease_to_enums(parse_ease("linear"))[0] == 0
    assert ease_to_enums(parse_ease("elastic.out")) == (2, 1)
    assert ease_to_enums(parse_ease("bounce.in")) == (4, 0)


def test_import_round_trip():
    anim = load_spec(SPEC)
    back = load_spec(from_rbxmx(to_rbxmx(anim)))
    assert [m.name for m in back.markers] == ["Hit", "Sfx"]
    ta, tb = anim.tracks(), back.tracks()
    for i in range(0, 31):
        t = i / 60
        sa, sb = sample(anim, t, ta), sample(back, t, tb)
        for j in JOINT_KEYS:
            assert angle_between(sa[j], sb[j]) < 0.05 and math.dist(sa[j].pos, sb[j].pos) < 1e-3, (t, j)


MOCK = r"""
local function enumTable(name)
  return setmetatable({}, {__index = function(_, item) return name .. "." .. item end})
end
Enum = setmetatable({}, {__index = function(_, n) return enumTable(n) end})
CFrame = {new = function(...) return {...} end}
local Inst = {}
local function new(class)
  local o = {ClassName = class, Name = class, _children = {}, _parent = nil}
  return setmetatable(o, Inst)
end
Inst.__index = function(self, k)
  if k == "Parent" then return rawget(self, "_parent") end
  local m = Inst[k]; if m then return m end
  for _, c in ipairs(rawget(self, "_children")) do if c.Name == k then return c end end
  return nil
end
Inst.__newindex = function(self, k, v)
  if k == "Parent" then
    local old = rawget(self, "_parent")
    if old then
      local kids = rawget(old, "_children")
      for i, c in ipairs(kids) do if c == self then table.remove(kids, i) break end end
    end
    rawset(self, "_parent", v)
    if v then table.insert(rawget(v, "_children"), self) end
  else rawset(self, k, v) end
end
function Inst.IsA(self, c) return self.ClassName == c end
function Inst.FindFirstChild(self, n) for _, c in ipairs(self._children) do if c.Name == n then return c end end end
function Inst.FindFirstChildOfClass(self, n) for _, c in ipairs(self._children) do if c.ClassName == n then return c end end end
function Inst.FindFirstAncestorOfClass(self, n) local p = self.Parent while p do if p.ClassName == n then return p end p = p.Parent end end
function Inst.Destroy(self) self.Parent = nil end
function Inst.GetFullName(self) local s = self.Name local p = self.Parent while p do s = p.Name .. "." .. s p = p.Parent end return s end
function Inst.GetChildren(self) return self._children end
Instance = {new = new}
local services = {ServerStorage = new("ServerStorage"), Selection = {Get = function() return SELECTED end, Set = function() end}}
services.ServerStorage.Name = "ServerStorage"
game = {GetService = function(_, n) return services[n] end}
function warn() end
function print() end
SELECTED = {}
"""


def _flatten_lua(inst, depth=0):
    rows = []
    for child in inst._children.values():
        props = {"Name": child.Name}
        if child.ClassName == "Pose":
            props.update(Weight=child.Weight, EasingStyle=child.EasingStyle, EasingDirection=child.EasingDirection,
                         CFrame=tuple(child.CFrame.values()))
        elif child.ClassName == "Keyframe":
            props["Time"] = child.Time
        elif child.ClassName == "KeyframeMarker":
            props["Value"] = child.Value
        rows.append((depth, child.ClassName, child.Name, props))
        rows += _flatten_lua(child, depth + 1)
    return rows


def test_luau_builds_same_tree():
    try:
        import lupa
    except ImportError:
        print("     (skipped: pip install lupa to run the Luau mock test)")
        return
    anim, root = _xml_tree()
    lua = lupa.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(MOCK)
    lua.execute(to_luau(anim))
    ss = lua.eval("game:GetService('ServerStorage')")
    kfs = ss.R6Generated.ExportTest
    assert kfs.ClassName == "KeyframeSequence" and kfs.Priority == "AnimationPriority.Action2"
    lua_rows = _flatten_lua(kfs)
    xml_rows = _flatten_xml(root.find("Item"))
    assert len(lua_rows) == len(xml_rows), (len(lua_rows), len(xml_rows))
    styles = {"0": "PoseEasingStyle.Linear", "1": "PoseEasingStyle.Constant", "2": "PoseEasingStyle.Elastic",
              "4": "PoseEasingStyle.Bounce", "5": "PoseEasingStyle.CubicV2"}
    dirs = {"0": "PoseEasingDirection.In", "1": "PoseEasingDirection.Out", "2": "PoseEasingDirection.InOut"}
    for (d1, c1, n1, p1), (d2, c2, n2, p2) in zip(lua_rows, xml_rows):
        assert (d1, c1, n1) == (d2, c2, n2), ((d1, c1, n1), (d2, c2, n2))
        if c1 == "Pose":
            assert abs(float(p1["Weight"]) - float(p2["Weight"])) < 1e-9
            assert p1["EasingStyle"] == styles[p2["EasingStyle"]]
            assert p1["EasingDirection"] == dirs[p2["EasingDirection"]]
            assert all(abs(a - b) < 1e-6 for a, b in zip(p1["CFrame"], p2["CFrame"]))
        if c1 == "Keyframe":
            assert abs(float(p1["Time"]) - float(p2["Time"])) < 1e-6


def test_luau_saves_into_selected_rig():
    try:
        import lupa
    except ImportError:
        return
    lua = lupa.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(MOCK)
    lua.execute("""
      RIG = Instance.new("Model"); RIG.Name = "Dummy"; RIG.Parent = nil
      local h = Instance.new("Humanoid"); h.Parent = RIG
      local torso = Instance.new("Part"); torso.Name = "Torso"; torso.Parent = RIG
      SELECTED = {torso}
    """)
    lua.execute(to_luau(load_spec(SPEC)))
    check = lua.eval("""function()
      local holder = game:GetService("ServerStorage").RBX_ANIMSAVES.Dummy
      return holder.ClassName == "ObjectValue" and holder.Value == RIG and RIG.AnimSaves.Value == holder
        and holder.ExportTest.ClassName == "KeyframeSequence"
    end""")
    assert check()
    lua.execute(to_luau(load_spec(SPEC)))  # running it again replaces, not duplicates
    count = lua.eval("""function()
      local n = 0
      for _, c in ipairs(game:GetService("ServerStorage").RBX_ANIMSAVES.Dummy._children) do
        if c.Name == "ExportTest" then n = n + 1 end
      end
      return n
    end""")
    assert count() == 1


if __name__ == "__main__":
    fails = 0
    for name, fn in sorted(globals().items()):
        if name.startswith("test_") and callable(fn):
            try:
                fn()
                print("ok  ", name)
            except AssertionError as e:
                fails += 1
                print("FAIL", name, e)
    sys.exit(1 if fails else 0)
