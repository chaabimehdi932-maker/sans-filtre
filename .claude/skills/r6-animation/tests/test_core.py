"""Checks the R6 math against geometry we can reason about by hand.

Run:  python tests/test_core.py      (or: python -m pytest tests)
"""

import math
import os
import random
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "scripts"))

from r6core import (CF, HRP_HEIGHT, JOINT, OFFSETS, PART_SIZE, body_cf, body_to_channels, body_to_transform,  # noqa: E402
                    box_corners, channels_to_transform, ease_alpha, forward_kinematics, limb_tip,
                    load_spec, mirror_raw, parse_ease, rz, sample, sole_top, transform_to_body)


def close(a, b, eps=1e-4):
    return all(abs(x - y) <= eps for x, y in zip(a, b))


def fk(pose):
    return forward_kinematics({j: channels_to_transform(j, ch) for j, ch in pose.items()})


def look(cf):  # Roblox LookVector = -Z column
    return (-cf.r[2], -cf.r[5], -cf.r[8])


def up(cf):
    return (cf.r[1], cf.r[4], cf.r[7])


def test_rest_pose_matches_default_rig():
    p = fk({})
    assert close(p["Torso"].pos, (0, 3, 0))
    assert close(p["Head"].pos, (0, 4.5, 0))
    assert close(p["Right Arm"].pos, (1.5, 3, 0))
    assert close(p["Left Arm"].pos, (-1.5, 3, 0))
    assert close(p["Right Leg"].pos, (0.5, 1, 0))
    assert close(p["Left Leg"].pos, (-0.5, 1, 0))
    for part in ("Torso", "Head", "Right Arm", "Left Arm", "Right Leg", "Left Leg"):
        assert close(p[part].r, CF().r), part  # all parts axis-aligned at rest
    assert abs(limb_tip(p, "Right Leg")[1]) < 1e-9  # feet on the ground
    assert HRP_HEIGHT == 3


def test_arm_forward_points_ahead():
    for side, x in (("Right", 1.5), ("Left", -1.5)):
        p = fk({side + "Arm": {"forward": 90}})
        assert close(limb_tip(p, side + " Arm"), (x, 3.5, -1.5)), side


def test_arm_forward_180_is_overhead():
    p = fk({"RightArm": {"forward": 180}})
    tip = limb_tip(p, "Right Arm")
    assert abs(tip[1] - 5.0) < 1e-6 and abs(tip[2]) < 1e-6  # pivot 3.5 + 1.5


def test_arm_out_is_t_pose():
    p = fk({"RightArm": {"out": 90}, "LeftArm": {"out": 90}})
    assert close(limb_tip(p, "Right Arm"), (2.5, 4.0, 0))
    assert close(limb_tip(p, "Left Arm"), (-2.5, 4.0, 0))


def test_arm_twist_external_turns_front_outward():
    p = fk({"RightArm": {"twist": 90}, "LeftArm": {"twist": 90}})
    assert look(p["Right Arm"])[0] > 0.99  # right arm's front face now faces +X (outward)
    assert look(p["Left Arm"])[0] < -0.99


def test_leg_forward_kicks_ahead_and_out_spreads():
    p = fk({"RightLeg": {"forward": 90}})
    assert limb_tip(p, "Right Leg")[2] < -1.5
    p = fk({"LeftLeg": {"out": 30}})
    assert limb_tip(p, "Left Leg")[0] < -1.0


def test_head_channels():
    assert look(fk({"Head": {"nod": 30}})["Head"])[1] < -0.45  # looks down
    assert look(fk({"Head": {"turn": 45}})["Head"])[0] > 0.7  # looks to its right
    assert up(fk({"Head": {"tilt": 20}})["Head"])[0] > 0.3  # top of head toward right shoulder


def test_torso_channels():
    assert up(fk({"Torso": {"lean": 20}})["Torso"])[2] < -0.3  # top leans forward (-Z)
    assert look(fk({"Torso": {"twist": 30}})["Torso"])[0] > 0.45  # chest turns right
    assert up(fk({"Torso": {"tilt": 20}})["Torso"])[0] > 0.3
    assert close(fk({"Torso": {"up": 1, "forward": 0.5, "right": -0.25}})["Torso"].pos, (-0.25, 4, -0.5))


def test_root_joint_up_is_pose_space_z():
    # The famous R6 quirk: in raw Pose.CFrame space, the Torso's "up" is +Z.
    t = channels_to_transform("Torso", {"up": 1})
    assert close(t.pos, (0, 0, 1))


def test_matches_legacy_motor_desired_angle():
    # Legacy R6 Animate: RightShoulder:SetDesiredAngle(1.57) = arm held forward (tool pose),
    # and walking set the SAME angle on both shoulders, giving opposite swings.
    angle_tf = rz(math.pi / 2)
    p = forward_kinematics({"RightArm": angle_tf, "LeftArm": angle_tf})
    assert limb_tip(p, "Right Arm")[2] < -1.4  # forward
    assert limb_tip(p, "Left Arm")[2] > 1.4  # backward
    assert channels_to_transform("RightArm", {"forward": 90}).almost(angle_tf)


def test_round_trip_channels():
    rnd = random.Random(7)
    for joint in JOINT:
        for _ in range(200):
            ch = {c: rnd.uniform(-60, 60) for c in JOINT[joint].channels}
            for c in ("right", "up", "forward", "reach", "offset_right", "offset_up", "offset_forward"):
                if c in ch:
                    ch[c] = rnd.uniform(-1, 1)
            tf = channels_to_transform(joint, ch)
            back = body_to_channels(joint, transform_to_body(joint, tf))
            assert channels_to_transform(joint, back).almost(tf, 1e-3), (joint, ch, back)
            # Angles come back exactly. A limb's reach and offsets may re-split (an offset along
            # the limb's axis IS reach), so for those only the transform equality above counts.
            exact = [c for c in ch if joint == "Torso" or c not in ("reach",) + OFFSETS]
            for c in exact:
                assert abs(back.get(c, 0.0) - ch[c]) < 1e-2, (joint, c, ch[c], back)


def _feet(parts):
    return {leg: limb_tip(parts, leg) for leg in ("Right Leg", "Left Leg")}


def test_plant_locks_feet_under_lean_twist_shift_and_crouch():
    rest_feet = _feet(fk({}))
    for torso in ({"lean": 30}, {"twist": 35}, {"tilt": 12}, {"forward": 0.4, "right": -0.2},
                  {"up": -0.5}, {"lean": 15, "twist": -25, "forward": 0.3, "up": -0.3}):
        a = load_spec({"keyframes": [{"t": 0, "plant": True, "Torso": torso}]})
        parts = forward_kinematics(sample(a, 0.0))
        for leg, f in _feet(parts).items():  # feet stay put, whole sole flat on the floor
            assert math.hypot(f[0] - rest_feet[leg][0], f[2] - rest_feet[leg][2]) < 0.15, (torso, leg, f)
            assert abs(sole_top(parts[leg])) < 0.01, (torso, leg, sole_top(parts[leg]))
    # crouching with planted feet retracts the legs (R6 "fake knee")
    a = load_spec({"keyframes": [{"t": 0, "plant": True, "Torso": {"up": -0.5}}]})
    ch = body_to_channels("RightLeg", a.keys[0].bodies["RightLeg"])
    assert abs(ch.get("reach", 0) + 0.5) < 0.02, ch
    assert up(forward_kinematics(sample(a, 0))["Torso"])[1] > 0.999


def test_plant_on_splayed_legs_stands_on_floor():
    a = load_spec({"keyframes": [{"t": 0, "plant": True, "RightLeg": {"forward": 30}, "LeftLeg": {"forward": -25}}]})
    parts = forward_kinematics(sample(a, 0))
    for leg in ("Right Leg", "Left Leg"):  # no air under either sole (the lower edge sinks, hidden)
        assert abs(sole_top(parts[leg])) < 0.01, (leg, sole_top(parts[leg]))


def test_plant_airborne_keeps_leg_angles():
    a = load_spec({"keyframes": [{"t": 0, "plant": True, "airborne": True, "Torso": {"lean": 30, "up": 1}}]})
    parts = forward_kinematics(sample(a, 0))
    rest = fk({})
    for leg in ("Right Leg", "Left Leg"):
        assert close(parts[leg].r, rest[leg].r)


def test_reach_and_offsets():
    p = fk({"RightArm": {"forward": 90, "reach": 0.3}})
    assert close(limb_tip(p, "Right Arm"), (1.5, 3.5, -1.8))  # 0.3 further along the arm
    p = fk({"LeftLeg": {"reach": -0.4}})
    assert close(limb_tip(p, "Left Leg"), (-0.5, 0.4, 0))  # leg slid up into the torso
    p = fk({"Head": {"offset_up": 0.2, "offset_forward": 0.1}})
    assert close(p["Head"].pos, (0, 4.7, -0.1))


def test_mirror_is_reflection():
    raw = {"name": "Punch_R", "keyframes": [{"t": 0, "RightArm": {"forward": 80, "out": 20, "twist": 10},
                                            "Torso": {"twist": 25, "tilt": 5, "lean": 10, "right": 0.3},
                                            "Head": {"turn": -15, "nod": 5, "offset_right": 0.1},
                                            "LeftLeg": {"forward": -20, "reach": -0.2, "offset_right": 0.1}}]}
    m = mirror_raw(raw)
    assert m["name"] == "Punch_L"
    p0 = forward_kinematics(sample(load_spec(raw), 0))
    p1 = forward_kinematics(sample(load_spec(m), 0))
    swap = {"Right Arm": "Left Arm", "Left Arm": "Right Arm", "Right Leg": "Left Leg", "Left Leg": "Right Leg"}
    for part, cf in p0.items():
        x, y, z = cf.pos
        assert close(p1[swap.get(part, part)].pos, (-x, y, z)), part


def test_easing():
    assert ease_alpha(parse_ease("out"), 0.5) > 0.8  # decelerates: most of the move early
    assert ease_alpha(parse_ease("in"), 0.5) < 0.2
    assert abs(ease_alpha(parse_ease("inout"), 0.5) - 0.5) < 1e-9
    assert ease_alpha(parse_ease("constant"), 0.99) == 0
    assert ease_alpha(parse_ease("elastic.out"), 0.15) > 1.0  # overshoots past the target


def test_frames_and_from():
    a = load_spec({"fps": 30, "poses": {"guard": {"RightArm": {"forward": 70}, "LeftArm": {"forward": 60}}},
                   "keyframes": [{"f": 0, "from": "guard"}, {"f": 15, "from": "guard", "RightArm": {"out": 10}}]})
    assert abs(a.length - 0.5) < 1e-9
    assert a.keys[1].channels["RightArm"] == {"forward": 70, "out": 10}
    assert a.keys[1].channels["LeftArm"] == {"forward": 60}


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
