"""Clips de la vue FPS (bras seuls de la grenouille + Ravage).

Repère caméra : l'œil FP_EYE (espace armature), regard vers -Y. Le jeu cale l'os FPCamera
sur sa caméra ; le corps n'est pas rendu, donc buste et clavicules servent librement à
amener les mains dans le champ (54° vertical, voir ViewModel.TARGET_FOV_DEG).
"""
import math

import bpy
from mathutils import Matrix, Vector

from clips import _frames
from rifle import BOLT, GUN_SCALE, L_WRIST, MAG, hold
from rigkit import AX_Y, Rig, lerp, smooth

FP_EYE = Vector((0.0, -0.06, 0.93))
ANCHOR = Vector((0.0, 0.0, 0.25))     # arrière de la carcasse (repère arme)
SIGHT = Vector((0.0, 0.19, 0.355))    # œilleton arrière (repère arme)
FRONT_POST = Vector((0.0, 0.529, 0.348))
HANDLE_TOP = Vector((0.0, 0.10, 0.366))  # dessus de la poignée de transport  # pointe du guidon : point visé, au centre de l'écran

IDLE = dict(right=0.08, down=0.062, fwd=0.15, pitch_up=1.5, roll=-3.0, yaw=6.0)


def fp_gun(right=0.0, down=0.0, fwd=0.0, pitch_up=0.0, roll=0.0, yaw=0.0, anchor=None) -> Matrix:
    anchor = ANCHOR if anchor is None else anchor
    rot = (Matrix.Rotation(math.radians(-pitch_up), 4, "X")
           @ Matrix.Rotation(math.radians(yaw), 4, "Z")
           @ Matrix.Rotation(math.pi, 4, "Z")
           @ Matrix.Rotation(math.radians(roll), 4, "Y"))
    m = rot.copy()
    m.translation = FP_EYE + Vector((-right, -fwd, -down)) - rot.to_3x3() @ (anchor * GUN_SCALE)
    return m


def add_fp_camera(arm_obj):
    """Os FPCamera (enfant de Hips) à l'œil ; dans Godot : -Z = regard, +Y = haut."""
    if "FPCamera" in arm_obj.data.bones:
        return
    bpy.context.view_layer.objects.active = arm_obj
    bpy.ops.object.mode_set(mode="EDIT")
    ebs = arm_obj.data.edit_bones
    eb = ebs.new("FPCamera")
    eb.head = FP_EYE
    eb.tail = FP_EYE + Vector((0.0, 0.0, 0.05))
    # Godot garde les axes locaux Blender : -Z = regard (-Y armature), +Y = haut, X = Y x Z.
    m = Matrix(((-1.0, 0.0, 0.0), (0.0, 0.0, 1.0), (0.0, 1.0, 0.0))).transposed().to_4x4()
    m.translation = FP_EYE
    eb.matrix = m
    eb.length = 0.05
    eb.parent = ebs["mixamorig:Hips"]
    eb.use_deform = False
    bpy.ops.object.mode_set(mode="OBJECT")


def fp_hold(rig: Rig, g: Matrix, left=None, left_curl=65.0):
    # Épaules remontées et avancées : le corps est invisible, seules les mains comptent.
    rig.rot("LeftShoulder", AX_Y, -16.0)
    rig.rot("RightShoulder", AX_Y, 14.0)
    return hold(rig, g, left=left, head_follow=0.0, base_twist=(-10.0, -12.0), clav=(-30.0, 8.0),
                base_lean=22.0, left_curl=left_curl)


REACH_FP = []


def _gun_clip(rig: Rig, name, duration, keys, loop=False):
    """keys : (t, paramètres fp_gun, main gauche : None | ('gun', point) | ('rig', point))."""
    rig.new_action(name)
    n = _frames(duration)

    def resolve(spec, g):
        if spec is None:
            return g @ (L_WRIST * GUN_SCALE)
        kind, pt = spec
        return g @ (pt * GUN_SCALE) if kind == "gun" else Vector(pt)

    worst = [0.0, 0.0]
    for f in range(n + 1):
        t = f / n
        i = max(j for j in range(len(keys)) if keys[j][0] <= t + 1e-9)
        j = min(i + 1, len(keys) - 1)
        t0, p0, l0 = keys[i]
        t1, p1, l1 = keys[j]
        u = 0.0 if j == i else smooth((t - t0) / (t1 - t0))
        prm = {k: lerp(p0.get(k, 0.0), p1.get(k, 0.0), u) for k in set(p0) | set(p1)}
        g = fp_gun(**prm)
        free = (l0 is not None) or (l1 is not None)
        target = resolve(l0, g).lerp(resolve(l1, g), u)
        rig.reset()
        errs = fp_hold(rig, g, left=target if free else None, left_curl=40.0 if free else 65.0)
        worst = [max(worst[0], errs[0]), max(worst[1], errs[1])]
        rig.key(f)
    REACH_FP.append((name, [round(w, 3) for w in worst]))


def _lerp_frame(a: Matrix, b: Matrix, u: float) -> Matrix:
    loc = a.translation.lerp(b.translation, u)
    rot = a.to_quaternion().slerp(b.to_quaternion(), u).to_matrix().to_4x4()
    rot.translation = loc
    return rot


def _static_clip(rig: Rig, name, g: Matrix):
    rig.new_action(name)
    for f in (0, 1):
        rig.reset()
        fp_hold(rig, g)
        rig.key(f)


def _with(base, **kw):
    d = dict(base)
    d.update(kw)
    return d


def build_fp(rig: Rig):
    # Torsion de référence : celle de la pose de repos (tous les clips partent de cette branche).
    rig.reset()
    rig._twist_prev = {}
    fp_hold(rig, fp_gun(**IDLE))
    rig.set_twist_reference()
    add = _gun_clip
    breath = [(t, _with(IDLE, down=IDLE["down"] + 0.003 * math.sin(2 * math.pi * t),
                        pitch_up=IDLE["pitch_up"] + 0.6 * math.sin(2 * math.pi * t + 0.6)), None)
              for t in (0.0, 0.25, 0.5, 0.75, 1.0)]
    add(rig, "FP_Idle", 2.4, breath, loop=True)
    # Visée : le bloc arrière de la poignée de transport masquait le centre (« caméra dans
    # l'arme »). Le réticule reste affiché en visée : l'arme se centre juste SOUS lui, dessus de
    # la poignée à ~9° sous l'œil, guidon visible un peu plus bas ; le centre reste dégagé.
    ads = dict(right=0.0, down=0.024, fwd=0.14, pitch_up=0.0, anchor=HANDLE_TOP)
    add(rig, "FP_ADS", 1.0 / 30.0, [(0.0, ads, None), (1.0, ads, None)])
    # Poses intermédiaires hanche -> visée, mains sur l'arme (IK) : le jeu passe de l'une à
    # l'autre (BlendSpace1D) ; mélanger directement hanche et visée faisait partir les bras.
    # FP_ADS_In : passage hanche -> visée sur 1 s (30 images), chaque image résolue mains sur
    # l'arme. Le jeu ne la « joue » pas : il se place à l'instant = avancement de la visée.
    g_idle, g_ads = fp_gun(**IDLE), fp_gun(**ads)
    rig.new_action("FP_ADS_In")
    for f in range(31):
        rig.reset()
        fp_hold(rig, _lerp_frame(g_idle, g_ads, smooth(f / 30.0)))
        rig.key(f)
    add(rig, "FP_Fire", 4.0 / 30.0, [(0.0, IDLE, None),
                                     (0.25, _with(IDLE, fwd=IDLE["fwd"] - 0.022, pitch_up=IDLE["pitch_up"] + 5.0, down=IDLE["down"] - 0.004), None),
                                     (1.0, IDLE, None)])
    low = _with(IDLE, right=0.068, down=0.05, fwd=0.13, pitch_up=8.0, roll=-32.0, yaw=12.0)
    add(rig, "FP_Reload", 2.5, [
        (0.00, IDLE, None),
        (0.10, low, None),
        (0.20, low, ("gun", MAG + Vector((-0.02, 0.0, -0.05)))),
        (0.32, _with(low, pitch_up=-10.0), ("gun", MAG + Vector((-0.06, 0.0, -0.22)))),
        (0.46, _with(low, pitch_up=-10.0), ("rig", FP_EYE + Vector((0.03, -0.12, -0.16)))),
        (0.62, low, ("gun", MAG + Vector((-0.03, 0.0, -0.18)))),
        (0.70, _with(low, pitch_up=-14.0), ("gun", MAG + Vector((-0.02, 0.0, -0.06)))),
        (0.74, _with(low, pitch_up=-8.0, roll=-26.0), ("gun", MAG + Vector((-0.02, 0.0, -0.07)))),
        # Plus de tirage du levier : la grosse main traversait l'arme. Claque sous le chargeur,
        # puis retour au garde-main par le côté gauche (jamais par-dessus l'arme).
        (0.80, _with(low, pitch_up=-6.0, roll=-24.0), ("gun", MAG + Vector((-0.02, 0.0, -0.13)))),
        (0.84, _with(low, pitch_up=-3.0, roll=-20.0, down=low["down"] - 0.006), ("gun", MAG + Vector((-0.02, 0.0, -0.075)))),
        (0.90, _with(IDLE, roll=-8.0), ("gun", Vector((-0.09, 0.16, 0.16)))),
        (1.00, IDLE, None),
    ])
    add(rig, "FP_Draw", 0.45, [(0.0, _with(IDLE, down=0.26, pitch_up=-55.0, roll=-40.0, yaw=20.0), None),
                               (0.7, _with(IDLE, pitch_up=IDLE["pitch_up"] + 4.0), None),
                               (1.0, IDLE, None)])
    run = _with(IDLE, right=0.08, down=0.07, fwd=0.12, pitch_up=-20.0, roll=-36.0, yaw=26.0)
    add(rig, "FP_Sprint", 0.42, [(t, _with(run, down=run["down"] + 0.012 * math.sin(4 * math.pi * t),
                                           roll=run["roll"] + 4.0 * math.sin(2 * math.pi * t)), None)
                                 for t in (0.0, 0.25, 0.5, 0.75, 1.0)], loop=True)
    add(rig, "FP_Inspect", 2.8, [
        (0.00, IDLE, None),
        (0.18, _with(IDLE, right=0.02, down=0.07, fwd=0.12, yaw=55.0, roll=35.0, pitch_up=8.0), None),
        (0.45, _with(IDLE, right=0.02, down=0.075, fwd=0.12, yaw=60.0, roll=38.0, pitch_up=6.0), None),
        (0.62, _with(IDLE, right=0.03, down=0.08, fwd=0.12, yaw=-35.0, roll=-55.0, pitch_up=4.0), None),
        (0.84, _with(IDLE, right=0.03, down=0.085, fwd=0.12, yaw=-38.0, roll=-58.0, pitch_up=2.0), None),
        (1.00, IDLE, None),
    ])
    for e in REACH_FP:
        print("REACH_FP", e)
    return ["FP_Idle", "FP_ADS", "FP_ADS_In", "FP_Fire", "FP_Reload", "FP_Draw", "FP_Sprint", "FP_Inspect"]


FP_LOOPS = ("FP_Idle", "FP_ADS", "FP_Sprint")
