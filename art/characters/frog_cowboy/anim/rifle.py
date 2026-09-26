"""Tenue du fusil (couche haut du corps) + os WeaponGrip.

Repères du Ravage mesurés sur assets/models/weapons/ravage.glb (unités de l'arme,
repère Blender de l'arme : canon +Y, haut +Z, droite +X). L'arme est à l'échelle
réelle dans le jeu ; dans le rig (1 unité = 1,8 m) elle mesure donc 1/1,8.
"""
import math

import bpy
from mathutils import Matrix, Vector

from clips import FPS, GAME_SCALE, _frames
from rigkit import AX_X, AX_Y, AX_Z, Rig, lerp, smooth

GUN_SCALE = 1.0 / GAME_SCALE
BUTT = Vector((0.0, -0.31, 0.22))          # talon de crosse
MAG = Vector((0.0, 0.14, 0.10))            # milieu du chargeur
BOLT = Vector((-0.045, 0.03, 0.27))        # armement pris par le côté gauche (la main ne passe plus par-dessus)
SHOULDER_POCKET = Vector((-0.068, -0.035, 0.735))  # creux de l'épaule droite (rig)

# Mains dans le repère de l'arme : poignet + axes (Y = vers les doigts, X = pouce).
# Main droite : poignet derrière le haut de la poignée, doigts vers le bas autour de la poignée
# (vers l'avant, ils finissaient sur le chargeur), pouce par-dessus.
R_WRIST, R_Y, R_X = Vector((0.03, -0.085, 0.215)), Vector((0.0, 0.45, -0.89)), Vector((0.0, 0.89, 0.45))
L_WRIST, L_Y, L_X = Vector((-0.035, 0.20, 0.19)), Vector((0.7, 0.7, 0.0)), Vector((-0.7, 0.7, 0.0))


def _frame_in(parent: Matrix, wrist, y, x) -> Matrix:
    y = Vector(y).normalized()
    x = Vector(x)
    x = (x - y * x.dot(y)).normalized()
    z = x.cross(y)
    m = Matrix((x, y, z)).transposed().to_4x4()
    m.translation = Vector(wrist) * GUN_SCALE
    return parent @ m


T_R = _frame_in(Matrix.Identity(4), R_WRIST, R_Y, R_X)  # main droite dans le repère arme


def gun_frame(pitch_up=0.0, roll=0.0, back=0.0, lift=0.0, yaw=0.0, side=0.0) -> Matrix:
    """Repère de l'arme dans l'espace armature. Tourne autour du creux de l'épaule."""
    rot = (Matrix.Rotation(math.radians(-pitch_up), 4, "X")
           @ Matrix.Rotation(math.radians(yaw), 4, "Z")
           @ Matrix.Rotation(math.pi, 4, "Z")
           @ Matrix.Rotation(math.radians(roll), 4, "Y"))
    pocket = SHOULDER_POCKET + Vector((side, back, lift))
    m = rot.copy()
    m.translation = pocket - rot.to_3x3() @ (BUTT * GUN_SCALE)
    return m


def add_weapon_grip(arm_obj):
    """Os WeaponGrip (enfant de la main droite) = repère de l'arme quand la main tient la poignée."""
    if "WeaponGrip" in arm_obj.data.bones:
        return
    bpy.context.view_layer.objects.active = arm_obj
    bpy.ops.object.mode_set(mode="EDIT")
    ebs = arm_obj.data.edit_bones
    hand = ebs["mixamorig:RightHand"]
    eb = ebs.new("WeaponGrip")
    eb.head = (0.0, 0.0, 0.0)
    eb.tail = (0.0, 0.05, 0.0)
    eb.parent = hand
    eb.use_deform = False
    hand_rest = arm_obj.data.bones["mixamorig:RightHand"].matrix_local.copy()
    # Godot garde les axes locaux Blender de l'os (+Y os = +Y nœud). Contrat du jeu : -Z = canon,
    # +Y = haut -> os : Y = haut de l'arme, Z = arrière (rotation +90° autour de X du repère arme).
    eb.matrix = hand_rest @ T_R.inverted() @ Matrix.Rotation(math.radians(90.0), 4, "X")
    eb.length = 0.05
    bpy.ops.object.mode_set(mode="OBJECT")


def hold(rig: Rig, g: Matrix, pitch_up=0.0, left=None, left_x=None, left_y=None, chest=(0.0, 0.0),
         head_follow=0.5, right_curl=78.0, left_curl=65.0, base_twist=(-12.0, -14.0), clav=(-24.0, 4.0),
         base_lean=0.0):
    """Pose du haut du corps tenant l'arme `g`. `left` : cible du poignet gauche (rig),
    sinon la main gauche reste sous le garde-main."""
    twist, lean = chest
    rig.rot("Spine1", AX_Z, base_twist[0] + twist * 0.5)
    rig.rot("Spine2", AX_Z, base_twist[1] + twist * 0.5)
    rig.rot("Spine1", AX_X, -pitch_up * 0.12 + (lean + base_lean) * 0.5)
    rig.rot("Spine2", AX_X, -pitch_up * 0.18 + (lean + base_lean) * 0.5)
    rig.rot("Neck", AX_Z, 11.0)
    rig.rot("Head", AX_Z, 14.0)
    rig.rot("Neck", AX_X, -pitch_up * head_follow * 0.4 + 4.0)
    rig.rot("Head", AX_X, -pitch_up * head_follow * 0.6 + 6.0)
    rig.rot("LeftShoulder", AX_Z, clav[0])
    rig.rot("RightShoulder", AX_Z, clav[1])
    rig.update()
    gr = g.to_3x3()
    errs = []
    # Main droite : poignée.
    rw = g @ (R_WRIST * GUN_SCALE)
    sh = rig.posed("RightArm").translation
    errs.append(rig.ik2("RightArm", "RightForeArm", rw, sh + Vector((-0.30, 0.12, -0.30))))
    rig.orient("RightHand", gr @ R_Y, gr @ R_X)
    # Main gauche : garde-main (ou cible libre pendant le rechargement).
    lw = left if left is not None else g @ (L_WRIST * GUN_SCALE)
    ly = left_y if left_y is not None else gr @ L_Y
    lx = left_x if left_x is not None else gr @ L_X
    sh = rig.posed("LeftArm").translation
    errs.append(rig.ik2("LeftArm", "LeftForeArm", lw, sh + Vector((0.12, -0.10, -0.35))))
    rig.orient("LeftHand", ly, lx)
    rig.spread_twist("RightForeArm", "RightHand")
    rig.spread_twist("LeftForeArm", "LeftHand")
    rig.curl("Right", right_curl, thumb_deg=30.0, index_deg=62.0)  # index replié sur la détente (tendu, il dépassait sous l'arme)
    rig.curl("Left", left_curl, thumb_deg=20.0)
    return errs


REACH_LOG = []


def _pose_clip(rig, name, pitch_up):
    rig.new_action(name)
    for f in (0, 1):
        rig.reset()
        errs = hold(rig, gun_frame(pitch_up=pitch_up), pitch_up=pitch_up)
        rig.key(f)
    REACH_LOG.append((name, [round(e, 3) for e in errs]))


def build_aims(rig):
    _pose_clip(rig, "Rifle_Aim_Down", -45.0)
    _pose_clip(rig, "Rifle_Aim_Neutral", 0.0)
    _pose_clip(rig, "Rifle_Aim_Up", 50.0)


def build_idle_breath(rig, duration=2.4):
    """ADDITIF dans le jeu (Add2 sur la visée) : seulement de petits écarts au repos."""
    rig.new_action("Rifle_Idle")
    n = _frames(duration)
    for f in range(n + 1):
        rig.reset()
        b = math.sin(2.0 * math.pi * f / n)
        rig.rot("Spine1", AX_X, 0.8 * b)
        rig.rot("Spine2", AX_X, 1.0 * b)
        rig.rot("LeftShoulder", AX_Y, 1.2 * b)
        rig.rot("RightShoulder", AX_Y, -1.2 * b)
        rig.key(f)


def build_shoot(rig):
    rig.new_action("Rifle_Shoot")
    keys = [(0, 0.0), (1, 1.0), (2, 0.7), (4, 0.0)]
    for f, k in keys:
        rig.reset()
        hold(rig, gun_frame(pitch_up=5.0 * k, back=0.014 * k), chest=(0.0, -2.5 * k))
        rig.key(f)


def build_reload(rig, duration=2.5):
    """Rechargement du Ravage (2,5 s) : arme inclinée, chargeur retiré, remis, armement."""
    rig.new_action("Rifle_Reload")
    # (t, arme{pitch,roll,back,lift}, main gauche : ('gun', point arme) | ('rig', point rig) | None)
    keys = [
        (0.00, dict(), None),
        (0.10, dict(pitch_up=-14.0, roll=28.0, back=0.02, lift=-0.02), None),
        (0.20, dict(pitch_up=-14.0, roll=28.0, back=0.02, lift=-0.02), ("gun", MAG + Vector((-0.02, 0.0, -0.05)))),
        (0.32, dict(pitch_up=-12.0, roll=30.0, back=0.02, lift=-0.02), ("gun", MAG + Vector((-0.06, 0.0, -0.22)))),
        (0.46, dict(pitch_up=-12.0, roll=30.0, back=0.02, lift=-0.02), ("rig", Vector((0.08, -0.02, 0.42)))),
        (0.62, dict(pitch_up=-14.0, roll=28.0, back=0.02, lift=-0.02), ("gun", MAG + Vector((-0.03, 0.0, -0.18)))),
        (0.70, dict(pitch_up=-16.0, roll=26.0, back=0.02, lift=-0.02), ("gun", MAG + Vector((-0.02, 0.0, -0.06)))),
        (0.74, dict(pitch_up=-10.0, roll=22.0, back=0.02, lift=-0.01), ("gun", MAG + Vector((-0.02, 0.0, -0.07)))),
        (0.80, dict(pitch_up=-12.0, roll=20.0, back=0.015, lift=-0.01), ("gun", MAG + Vector((-0.02, 0.0, -0.13)))),
        (0.84, dict(pitch_up=-9.0, roll=16.0, back=0.015, lift=-0.005), ("gun", MAG + Vector((-0.02, 0.0, -0.075)))),
        (0.90, dict(pitch_up=-3.0, roll=6.0, back=0.005, lift=0.0), ("gun", Vector((-0.09, 0.16, 0.16)))),
        (1.00, dict(), None),
    ]
    n = _frames(duration)

    def resolve(key, g):
        if key is None:
            return g @ (L_WRIST * GUN_SCALE)
        kind, pt = key
        return g @ (pt * GUN_SCALE) if kind == "gun" else Vector(pt)

    for f in range(n + 1):
        t = f / n
        i = max(j for j in range(len(keys)) if keys[j][0] <= t + 1e-9)
        j = min(i + 1, len(keys) - 1)
        t0, g0, l0 = keys[i]
        t1, g1, l1 = keys[j]
        u = 0.0 if j == i else smooth((t - t0) / (t1 - t0))
        params = {k: lerp(g0.get(k, 0.0), g1.get(k, 0.0), u) for k in ("pitch_up", "roll", "back", "lift")}
        g = gun_frame(**params)
        target = resolve(l0, g).lerp(resolve(l1, g), u)
        rig.reset()
        free = (l0 is not None) or (l1 is not None)
        hold(rig, g, left=target if free else None, left_curl=lerp(65.0, 40.0, 1.0 if free else 0.0))
        rig.key(f)


def build_rifle(rig, only=None):
    # Torsion de référence : celle de la visée neutre (tous les clips fusil partent de là).
    rig.reset()
    rig._twist_prev = {}
    hold(rig, gun_frame())
    rig.set_twist_reference()
    jobs = {
        "Rifle_Aim_Down": None, "Rifle_Aim_Neutral": None, "Rifle_Aim_Up": None,
        "Rifle_Idle": lambda: build_idle_breath(rig),
        "Rifle_Shoot": lambda: build_shoot(rig),
        "Rifle_Reload": lambda: build_reload(rig),
    }
    if only is None or any(n.startswith("Rifle_Aim") for n in only):
        build_aims(rig)
    for name, job in jobs.items():
        if job and (only is None or name in only):
            job()
    return list(jobs)
