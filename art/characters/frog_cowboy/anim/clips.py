"""Clips de la grenouille cowboy, générés par script sur son rig Mixamo.

Noms = contrat du jeu (scripts/player/CharacterAnimator.gd). Clips en place (pas de
déplacement racine), 30 i/s. Vitesses du jeu (MovementConfig) ramenées à l'échelle du
rig (1 unité = 1,8 m) pour que les pieds ne glissent pas.
"""
import math

from mathutils import Matrix, Vector

from rigkit import AX_X, AX_Y, AX_Z, FWD, Rig, lerp, smooth

FPS = 30
GAME_SCALE = 1.8  # hauteur de jeu / hauteur du rig

# Repères du rig au repos (mesurés).
HIP_Z = 0.49
ANKLE_Z = 0.06
FOOT_LEN = 0.07  # cheville -> base des orteils


def _frames(duration_s):
    return max(2, int(round(duration_s * FPS)))


# ----------------------------------------------------------------------------
# Poses de base
# ----------------------------------------------------------------------------
def arms_relaxed(rig: Rig, down=33.0, elbow=12.0, curl=25.0):
    rig.rot("LeftArm", AX_Y, down)
    rig.rot("RightArm", AX_Y, -down)
    rig.rot("LeftForeArm", AX_X, -elbow)
    rig.rot("RightForeArm", AX_X, -elbow)
    rig.curl("Left", curl, thumb_deg=10.0)
    rig.curl("Right", curl, thumb_deg=10.0)


def plant_feet(rig: Rig, left_target, right_target, left_pitch=0.0, right_pitch=0.0, toe_flat=(False, False)):
    for side, tgt, pitch, flat in (("Left", left_target, left_pitch, toe_flat[0]),
                                   ("Right", right_target, right_pitch, toe_flat[1])):
        hip = rig.posed(f"{side}UpLeg").translation
        pole = hip + FWD * 1.0 + Vector((0.15 if side == "Left" else -0.15, 0.0, 0.0))
        rig.ik2(f"{side}UpLeg", f"{side}Leg", tgt, pole)
        # Pied : orientation de repos (à plat) basculée de `pitch` (+ = pointe vers le bas).
        rest = rig.rest(f"{side}Foot").to_3x3()
        rot = Matrix.Rotation(math.radians(pitch), 3, AX_X)
        m = (rot @ rest).to_4x4()
        m.translation = rig.posed(f"{side}Foot").translation
        rig.set_matrix(f"{side}Foot", m)
        toe_rest = rig.rest(f"{side}ToeBase").to_3x3()
        toe_rot = Matrix.Identity(3) if flat else rot
        tm = (toe_rot @ toe_rest).to_4x4()
        tm.translation = rig.posed(f"{side}ToeBase").translation
        rig.set_matrix(f"{side}ToeBase", tm)


def rest_ankle(side, width=0.0):
    x = 0.09 + width if side == "Left" else -(0.09 + width)
    return Vector((x, 0.03, ANKLE_Z))


# ----------------------------------------------------------------------------
# Locomotion paramétrique (course en place, appuis calés sur la vitesse du jeu)
# ----------------------------------------------------------------------------
def gait_pose(rig: Rig, phase: float, p: dict):
    stance = p["stance"]
    step = p["speed"] * stance * p["T"]        # recul du pied pendant l'appui

    # Hanches : plus basses à mi-appui, rotation vers la jambe avant, bascule latérale.
    bob = -p["drop"] - p["bob"] * math.cos(4.0 * math.pi * (phase - stance * 0.5))
    rig.hips_offset((0.0, 0.0, bob))
    yaw = -p["twist"] * math.cos(2.0 * math.pi * phase)
    roll = -p["roll"] * math.cos(2.0 * math.pi * (phase - stance * 0.5))
    rig.rot("Hips", AX_Z, yaw)
    rig.rot("Hips", AX_Y, roll)

    # Buste penché vers l'avant, épaules en contre-rotation des hanches.
    lean = p["lean"]
    for name, share in (("Spine", 0.4), ("Spine1", 0.3), ("Spine2", 0.3)):
        rig.rot(name, AX_Z, -yaw * 1.6 * share)
        rig.rot(name, AX_X, lean * share)
        rig.rot(name, AX_Y, -roll * 0.8 * share)
    # Tête stabilisée : regarde droit devant.
    rig.rot("Neck", AX_X, -lean * 0.45)
    rig.rot("Head", AX_X, -lean * 0.35 + p.get("head_bob", 0.0) * math.cos(4.0 * math.pi * phase))
    rig.rot("Neck", AX_Z, yaw * 0.3)

    # Bras : balancier opposé aux jambes, coudes pliés, poings.
    swing = p["arm_swing"] * math.cos(2.0 * math.pi * phase)
    rig.rot("LeftArm", AX_Y, p["arm_down"])
    rig.rot("RightArm", AX_Y, -p["arm_down"])
    rig.rot("LeftArm", AX_X, swing)
    rig.rot("RightArm", AX_X, -swing)
    rig.rot("LeftForeArm", AX_X, -(p["elbow"] + p["elbow_var"] * max(0.0, -math.cos(2.0 * math.pi * phase))))
    rig.rot("RightForeArm", AX_X, -(p["elbow"] + p["elbow_var"] * max(0.0, math.cos(2.0 * math.pi * phase))))
    rig.curl("Left", p["fist"], thumb_deg=25.0)
    rig.curl("Right", p["fist"], thumb_deg=25.0)

    # Pieds.
    targets = {}
    for side, ph in (("Left", phase), ("Right", phase + 0.5)):
        u = ph % 1.0
        x = p["width"] if side == "Left" else -p["width"]
        if u < stance:
            w = u / stance
            y = -step * 0.5 + step * w + p["foot_back"]
            z = ANKLE_Z
            heel_strike = -p["heel"] * (1.0 - smooth(w / 0.25))
            toe_off = p["toeoff"] * smooth((w - 0.65) / 0.35)
            pitch = heel_strike + toe_off
            flat = toe_off > 0.0
        else:
            w = (u - stance) / (1.0 - stance)
            y = step * 0.5 - step * smooth(w) + p["foot_back"]
            z = ANKLE_Z + p["lift"] * math.sin(math.pi * w) + p["kick"] * math.sin(math.pi * min(1.0, w * 1.8)) * (1.0 - w)
            y += p["kick_back"] * math.sin(math.pi * min(1.0, w * 1.8)) * (1.0 - w)
            pitch = lerp(p["toeoff"], -p["heel"], smooth(w))
            flat = False
        if pitch > 0.0:  # talon levé : pivot sur la base des orteils
            a = math.radians(pitch)
            z += FOOT_LEN * math.sin(a)
            y += FOOT_LEN * (1.0 - math.cos(a))
        targets[side] = (Vector((x, y, z)), pitch, flat)
    rig.update()
    plant_feet(rig, targets["Left"][0], targets["Right"][0], targets["Left"][1], targets["Right"][1],
               (targets["Left"][2], targets["Right"][2]))


GAITS = {
    # speed = vitesse jeu / 1.8 ; T = durée du cycle (2 pas).
    "Walk": dict(speed=5.2 / GAME_SCALE, T=0.50, stance=0.38, drop=0.045, bob=0.012, twist=9.0, roll=4.0,
                 lean=10.0, arm_swing=32.0, arm_down=30.0, elbow=75.0, elbow_var=20.0, fist=65.0,
                 width=0.065, lift=0.07, kick=0.05, kick_back=0.03, heel=12.0, toeoff=38.0, foot_back=0.015,
                 head_bob=1.5),
    "Jog_Fwd": dict(speed=6.0 / GAME_SCALE, T=0.46, stance=0.36, drop=0.05, bob=0.014, twist=10.0, roll=4.0,
                    lean=13.0, arm_swing=36.0, arm_down=30.0, elbow=80.0, elbow_var=20.0, fist=70.0,
                    width=0.06, lift=0.08, kick=0.06, kick_back=0.04, heel=12.0, toeoff=42.0, foot_back=0.02,
                    head_bob=1.8),
    "Sprint": dict(speed=8.2 / GAME_SCALE, T=0.42, stance=0.33, drop=0.06, bob=0.016, twist=12.0, roll=3.0,
                   lean=22.0, arm_swing=48.0, arm_down=28.0, elbow=85.0, elbow_var=25.0, fist=75.0,
                   width=0.055, lift=0.09, kick=0.09, kick_back=0.06, heel=10.0, toeoff=48.0, foot_back=0.03,
                   head_bob=2.0),
    "Crouch_Fwd": dict(speed=3.2 / GAME_SCALE, T=0.60, stance=0.55, drop=0.15, bob=0.008, twist=7.0, roll=3.0,
                       lean=28.0, arm_swing=14.0, arm_down=24.0, elbow=60.0, elbow_var=10.0, fist=55.0,
                       width=0.085, lift=0.045, kick=0.0, kick_back=0.0, heel=8.0, toeoff=25.0, foot_back=0.0,
                       head_bob=1.0),
}


def build_gait(rig: Rig, name: str):
    p = GAITS[name]
    rig.new_action(name)
    n = _frames(p["T"])
    for f in range(n + 1):
        rig.reset()
        gait_pose(rig, f / n, p)
        rig.key(f)


# ----------------------------------------------------------------------------
# Repos
# ----------------------------------------------------------------------------
def idle_pose(rig: Rig, t: float, crouch=0.0):
    breath = math.sin(2.0 * math.pi * t)
    sway = math.sin(2.0 * math.pi * t + 0.8)
    rig.hips_offset((0.004 * sway, 0.0, -0.012 - crouch * 0.16 + 0.002 * breath))
    rig.rot("Hips", AX_Z, 1.5 * sway)
    lean = crouch * 26.0
    rig.rot("Spine", AX_X, lean * 0.4 + 0.6 * breath)
    rig.rot("Spine1", AX_X, lean * 0.3 + 0.8 * breath)
    rig.rot("Spine2", AX_X, lean * 0.3 + 0.8 * breath)
    rig.rot("Neck", AX_X, -lean * 0.5 - 0.6 * breath)
    rig.rot("Head", AX_X, -lean * 0.3)
    rig.rot("Head", AX_Z, 3.0 * math.sin(2.0 * math.pi * t * 0.5))
    rig.rot("LeftShoulder", AX_Y, 1.5 * breath)
    rig.rot("RightShoulder", AX_Y, -1.5 * breath)
    arms_relaxed(rig, down=33.0 - crouch * 8.0, elbow=12.0 + crouch * 30.0 + 2.0 * breath, curl=25.0)
    rig.update()
    width = 0.02 + crouch * 0.03
    plant_feet(rig, rest_ankle("Left", width) + Vector((0, -0.01 - crouch * 0.03, 0)),
               rest_ankle("Right", width) + Vector((0, 0.02, 0)))


def build_idle(rig: Rig, name="Idle", crouch=0.0, duration=2.4):
    rig.new_action(name)
    n = _frames(duration)
    for f in range(n + 1):
        rig.reset()
        idle_pose(rig, f / n, crouch)
        rig.key(f)


