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
                    foot_low, load_spec, mirror_raw, parse_ease, rz, sample, transform_to_body)


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
            assert abs(foot_low(parts[leg])) < 0.01, (torso, leg, foot_low(parts[leg]))
    # crouching with planted feet retracts the legs (R6 "fake knee")
    a = load_spec({"keyframes": [{"t": 0, "plant": True, "Torso": {"up": -0.5}}]})
    ch = body_to_channels("RightLeg", a.keys[0].bodies["RightLeg"])
    assert abs(ch.get("reach", 0) + 0.5) < 0.02, ch
    assert up(forward_kinematics(sample(a, 0))["Torso"])[1] > 0.999


def test_plant_on_splayed_legs_stands_on_floor():
    a = load_spec({"keyframes": [{"t": 0, "plant": True, "RightLeg": {"forward": 30}, "LeftLeg": {"forward": -25}}]})
    parts = forward_kinematics(sample(a, 0))
    for leg in ("Right Leg", "Left Leg"):  # no air under either sole (the lower edge sinks, hidden)
        assert abs(foot_low(parts[leg])) < 0.01, (leg, foot_low(parts[leg]))


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


def _feet_at(anim, t):
    parts = forward_kinematics(sample(anim, t))
    return {leg: limb_tip(parts, leg) for leg in ("Right Leg", "Left Leg")}, parts


def test_planted_key_continues_leg_curve():
    # a planted key that doesn't list the legs keeps their curve (no snap to the rest pose)
    a = load_spec({"name": "t", "keyframes": [
        {"t": 0, "plant": True, "RightLeg": {"out": 8}, "LeftLeg": {"out": 8}, "Torso": {"tilt": -4}},
        {"t": 0.5, "plant": True, "Torso": {"tilt": -2}},
        {"t": 1, "plant": True, "Torso": {"tilt": -4}}]})
    f0, _ = _feet_at(a, 0)
    for t in (0.25, 0.5, 0.75):
        ft, _ = _feet_at(a, t)
        for leg in f0:
            assert math.dist(f0[leg][::2], ft[leg][::2]) < 0.05, (t, leg, f0[leg], ft[leg])


def test_breakdown_fills_from_curve_and_plants():
    spec = {"name": "t", "keyframes": [
        {"t": 0, "plant": True, "support": "double", "Torso": {"twist": 30, "up": -0.4},
         "RightLeg": {"forward": -8}, "LeftLeg": {"forward": 8}},
        {"t": 0.2, "breakdown": True},
        {"t": 0.4, "plant": True, "support": "right", "Torso": {"twist": -10, "up": 0}}]}
    a = load_spec(spec)
    bd = a.keys[1]
    assert bd.plant and bd.support == "right", (bd.plant, bd.support)  # what both neighbours share
    assert 0 < bd.channels["Torso"]["twist"] < 30  # starts as the in-between
    assert str(a.keys[0].joint_ease["Torso"]) == "in" and str(bd.joint_ease["Torso"]) == "out"  # inout split
    _, parts = _feet_at(a, 0.2)
    assert abs(foot_low(parts["Right Leg"])) < 0.01  # the planted foot is on the floor at the breakdown


def test_free_leg_lifts_clear_of_floor():
    # one-foot support while crouched: the free leg would go through the floor; it is pulled up into the hip
    a = load_spec({"name": "t", "clearance": 0.2, "keyframes": [
        {"t": 0, "plant": True, "support": "left", "Torso": {"up": -0.5}, "RightLeg": {"forward": -20}},
        {"t": 1, "plant": True, "support": "left", "Torso": {"up": -0.5}, "RightLeg": {"forward": -20}}]})
    _, parts = _feet_at(a, 0)
    assert abs(foot_low(parts["Left Leg"])) < 0.01
    assert foot_low(parts["Right Leg"]) >= 0.19, foot_low(parts["Right Leg"])


def test_pivot_keeps_weight_leg_straight():
    from r6pose import leg_tilt
    spec = {"name": "t", "keyframes": [
        {"t": 0, "plant": True, "support": "transition", "pivot": "left", "Torso": {"twist": 35}},
        {"t": 1, "plant": True, "support": "transition", "pivot": "left", "Torso": {"twist": 35}}]}
    _, parts = _feet_at(load_spec(spec), 0)
    assert leg_tilt(parts, "Left Leg") < 1.0, leg_tilt(parts, "Left Leg")  # the left hip stays over its foot
    spec["keyframes"][0].pop("pivot"); spec["keyframes"][1].pop("pivot")
    _, parts = _feet_at(load_spec(spec), 0)
    assert leg_tilt(parts, "Left Leg") > 5  # pivoting at the hips' middle swings that hip away


def test_stance_fit_flattens_feet():
    from r6pose import key_reports
    from r6tools import apply_stance, fit_stance
    raw = {"name": "t", "keyframes": [
        {"t": 0, "plant": True, "Torso": {"twist": 25, "up": -0.4}, "RightLeg": {"out": 22}, "LeftLeg": {"forward": 20, "out": 15}},
        {"t": 0.2, "plant": True, "Torso": {"twist": 40, "up": -0.4}},
        {"t": 0.4, "plant": True, "Torso": {"twist": 25, "up": -0.4}}]}
    a = load_spec(raw)
    before = min(min(r["contact"].values()) for _, r in key_reports(a))
    fixed = load_spec(apply_stance(raw, a, fit_stance(a)))
    after = min(min(r["contact"].values()) for _, r in key_reports(fixed))
    assert before < 0.5 <= after, (before, after)


def test_contact_phases_of_walk():
    from r6pose import contact_phases
    walk = load_spec(os.path.join(os.path.dirname(__file__), "..", "recipes", "walk.json"))
    for leg, segs in contact_phases(walk).items():
        names = [p for p, _, _ in segs]
        for phase in ("plant", "release", "swing", "contact"):
            assert phase in names, (leg, names)


def test_lint_names_the_cause_of_floor_penetration():
    from r6lint import lint
    # key pose itself under the floor: crouch without plant
    at_key = lint(load_spec({"name": "t", "keyframes": [{"t": 0}, {"t": 0.5, "Torso": {"up": -0.5}}, {"t": 1}]}))
    assert any("into the floor" in m and "key pose itself" in m for _, m in at_key), at_key
    # standing on splayed legs: soles mostly off the floor
    splay = lint(load_spec({"name": "t", "keyframes": [
        {"t": 0, "plant": True, "RightLeg": {"out": 25}, "LeftLeg": {"out": 25}},
        {"t": 1, "plant": True, "RightLeg": {"out": 25}, "LeftLeg": {"out": 25}}]}))
    assert any("of the right sole touches the floor" in m for _, m in splay), splay


def test_feet_touch_never_sink_when_planted():
    from r6pose import sole_contact
    a = load_spec({"name": "t", "keyframes": [
        {"t": 0, "plant": True, "RightLeg": {"out": 12}, "LeftLeg": {"forward": 12}, "Torso": {"up": -0.3}},
        {"t": 1, "plant": True, "RightLeg": {"out": 12}, "LeftLeg": {"forward": 12}, "Torso": {"up": -0.3}}]})
    _, parts = _feet_at(a, 0)
    for leg in ("Right Leg", "Left Leg"):
        assert abs(foot_low(parts[leg])) < 0.01  # lowest corner exactly on the floor
        assert sole_contact(parts, leg) > 0.6  # a 12 deg leg still has most of its sole down


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
