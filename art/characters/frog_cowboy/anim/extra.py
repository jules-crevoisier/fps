"""Clips ponctuels : saut, roulade, touché, interaction, mort."""
import math

from mathutils import Vector

from clips import ANKLE_Z, _frames, arms_relaxed, plant_feet, rest_ankle
from rigkit import AX_X, AX_Y, AX_Z, Rig, lerp, smooth


def _keyed(rig: Rig, name, duration, pose_fn):
    rig.new_action(name)
    n = _frames(duration)
    for f in range(n + 1):
        rig.reset()
        pose_fn(f / n)
        rig.key(f)


def _track(keys, t):
    """Interpolation douce entre (t, valeur) triés."""
    if t <= keys[0][0]:
        return keys[0][1]
    for (t0, v0), (t1, v1) in zip(keys, keys[1:]):
        if t <= t1:
            return lerp(v0, v1, smooth((t - t0) / (t1 - t0)))
    return keys[-1][1]


def jump_start(rig: Rig):
    def pose(t):
        crouch = _track([(0.0, 0.0), (0.55, 1.0), (1.0, -0.4)], t)
        rig.hips_offset((0.0, 0.0, -0.07 * crouch))
        rig.rot("Spine", AX_X, 12.0 * crouch)
        rig.rot("Spine1", AX_X, 6.0 * crouch)
        rig.rot("Neck", AX_X, -10.0 * crouch)
        swing = _track([(0.0, 0.0), (0.55, 35.0), (1.0, -40.0)], t)
        arms_relaxed(rig, down=30.0, elbow=25.0, curl=40.0)
        rig.rot("LeftArm", AX_X, swing)
        rig.rot("RightArm", AX_X, swing)
        rig.update()
        toe = max(0.0, -crouch) * 45.0
        lift = max(0.0, -crouch) * 0.02
        plant_feet(rig, rest_ankle("Left", 0.01) + Vector((0, 0, lift)), rest_ankle("Right", 0.01) + Vector((0, 0, lift)),
                   toe, toe, (True, True))
    _keyed(rig, "Jump_Start", 0.2, pose)


def jump_air(rig: Rig):
    def pose(t):
        w = math.sin(2.0 * math.pi * t)
        rig.hips_offset((0.0, 0.0, 0.0))
        rig.rot("Spine", AX_X, 6.0)
        rig.rot("Spine1", AX_X, 3.0 + 1.5 * w)
        rig.rot("Neck", AX_X, -6.0)
        arms_relaxed(rig, down=8.0, elbow=45.0, curl=35.0)
        rig.rot("LeftArm", AX_X, -25.0 + 6.0 * w)
        rig.rot("RightArm", AX_X, -25.0 - 6.0 * w)
        rig.update()
        plant_feet(rig, Vector((0.085, -0.06 + 0.02 * w, 0.20)), Vector((-0.085, 0.05 - 0.02 * w, 0.16)), 25.0, 30.0)
    _keyed(rig, "Jump", 0.6, pose)


def jump_land(rig: Rig):
    def pose(t):
        squash = _track([(0.0, -0.2), (0.25, 1.0), (1.0, 0.0)], t)
        rig.hips_offset((0.0, 0.0, -0.085 * max(0.0, squash) - 0.012))
        rig.rot("Spine", AX_X, 16.0 * max(0.0, squash))
        rig.rot("Spine1", AX_X, 8.0 * max(0.0, squash))
        rig.rot("Neck", AX_X, -14.0 * max(0.0, squash))
        arms_relaxed(rig, down=lerp(10.0, 33.0, smooth(t)), elbow=lerp(40.0, 12.0, smooth(t)), curl=30.0)
        rig.rot("LeftArm", AX_Y, -12.0 * max(0.0, squash))
        rig.rot("RightArm", AX_Y, 12.0 * max(0.0, squash))
        rig.update()
        plant_feet(rig, rest_ankle("Left", 0.03), rest_ankle("Right", 0.03))
    _keyed(rig, "Jump_Land", 0.3, pose)


def roll(rig: Rig):
    def pose(t):
        spin = 360.0 * smooth(t)
        tuck = math.sin(math.pi * min(1.0, t * 1.15))
        rig.hips_offset((0.0, 0.0, -0.24 * tuck))
        rig.rot("Hips", AX_X, spin)
        for n in ("Spine", "Spine1", "Spine2"):
            rig.rot(n, AX_X, 28.0 * tuck)
        rig.rot("Neck", AX_X, 30.0 * tuck)
        rig.rot("Head", AX_X, 15.0 * tuck)
        for side in ("Left", "Right"):
            rig.rot(f"{side}UpLeg", AX_X, -115.0 * tuck)
            rig.rot(f"{side}Leg", AX_X, 125.0 * tuck)
            rig.rot(f"{side}Foot", AX_X, 20.0 * tuck)
        arms_relaxed(rig, down=33.0, elbow=12.0 + 80.0 * tuck, curl=30.0 + 30.0 * tuck)
        rig.rot("LeftArm", AX_X, -70.0 * tuck)
        rig.rot("RightArm", AX_X, -70.0 * tuck)
    _keyed(rig, "Roll", 0.6, pose)


def hit_head(rig: Rig):
    def pose(t):
        k = _track([(0.0, 0.0), (0.2, 1.0), (1.0, 0.0)], t)
        rig.hips_offset((0.0, 0.004 * k, -0.012 - 0.01 * k))
        rig.rot("Spine1", AX_X, -6.0 * k)
        rig.rot("Spine2", AX_X, -8.0 * k)
        rig.rot("Neck", AX_X, -12.0 * k)
        rig.rot("Head", AX_X, -22.0 * k)
        rig.rot("Head", AX_Z, 8.0 * k)
        arms_relaxed(rig, down=33.0 - 14.0 * k, elbow=12.0 + 25.0 * k, curl=25.0 + 20.0 * k)
        rig.update()
        plant_feet(rig, rest_ankle("Left", 0.02), rest_ankle("Right", 0.02))
    _keyed(rig, "Hit_Head", 0.35, pose)


def interact(rig: Rig):
    def pose(t):
        k = _track([(0.0, 0.0), (0.4, 1.0), (0.6, 1.0), (1.0, 0.0)], t)
        rig.hips_offset((0.0, 0.0, -0.012))
        rig.rot("Spine1", AX_X, 6.0 * k)
        rig.rot("Spine2", AX_Z, -8.0 * k)
        arms_relaxed(rig)
        rig.update()
        if k > 0.001:
            sh = rig.posed("RightArm").translation
            rest_hand = rig.posed("RightHand").translation
            target = rest_hand.lerp(Vector((-0.08, -0.26, 0.62)), k)
            rig.ik2("RightArm", "RightForeArm", target, sh + Vector((-0.3, 0.1, -0.2)))
        rig.update()
        plant_feet(rig, rest_ankle("Left", 0.02), rest_ankle("Right", 0.02))
    _keyed(rig, "Interact", 0.8, pose)


def death(rig: Rig):
    def pose(t):
        fall = _track([(0.0, 0.0), (0.18, 0.08), (0.8, 1.0), (0.88, 0.97), (1.0, 1.0)], t)
        recoil = _track([(0.0, 0.0), (0.15, 1.0), (0.4, 0.3), (1.0, 0.0)], t)
        rig.hips_offset((0.0, 0.16 * fall, -0.38 * fall))
        rig.rot("Hips", AX_X, -82.0 * fall)
        rig.rot("Spine1", AX_X, -10.0 * recoil + 6.0 * fall)
        rig.rot("Spine2", AX_X, -12.0 * recoil)
        rig.rot("Neck", AX_X, -18.0 * recoil + 12.0 * fall)
        rig.rot("Head", AX_Z, 25.0 * fall)
        for side, s in (("Left", 1.0), ("Right", -1.0)):
            rig.rot(f"{side}UpLeg", AX_X, -55.0 * fall + 8.0 * s * fall)
            rig.rot(f"{side}Leg", AX_X, 70.0 * fall - 20.0 * s * fall)
            rig.rot(f"{side}UpLeg", AX_Y, 10.0 * s * fall)
            rig.rot(f"{side}Arm", AX_Y, s * (33.0 - 50.0 * fall))
            rig.rot(f"{side}Arm", AX_X, -30.0 * recoil - 20.0 * fall)
            rig.rot(f"{side}ForeArm", AX_X, -35.0 * fall)
        rig.curl("Left", 30.0 * fall)
        rig.curl("Right", 45.0 * fall)
    _keyed(rig, "Death01", 1.2, pose)


EXTRA = {
    "Jump_Start": jump_start, "Jump": jump_air, "Jump_Land": jump_land, "Roll": roll,
    "Hit_Head": hit_head, "Interact": interact, "Death01": death,
}
