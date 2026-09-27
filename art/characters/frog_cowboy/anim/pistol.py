"""Tenue du revolver (arme 2) : os PistolGrip + clips 3e personne Pistol_*.

Repères du revolver mesurés sur assets/models/weapons/revolver.glb (art/weapons/revolver/
build_revolver.py) : mètres, avant = +Y, haut = +Z, droite = +X, origine au centre de la
crosse (là où tombe le creux de la paume). Dans le rig (1 unité = 1,8 m) : x GUN_SCALE.
"""
import math

import bpy
from mathutils import Matrix, Vector

from clips import _frames
from rifle import GUN_SCALE
from rigkit import AX_X, AX_Y, AX_Z, Rig, lerp, smooth

# -- repères du revolver (mètres, repère de l'arme) ------------------------------------------
# Mesurés sur le modèle à 0,26 m, mis à l'échelle de REVOLVER_LENGTH_M (même valeur que
# LENGTH_M dans art/weapons/revolver/build_revolver.py).
REVOLVER_LENGTH_M = 0.32
_K = REVOLVER_LENGTH_M / 0.26
REAR_SIGHT = Vector((0.0, 0.050, 0.117)) * _K
FRONT_SIGHT = Vector((0.0, 0.197, 0.1215)) * _K
MUZZLE = Vector((0.0, 0.220, 0.0966)) * _K
CYLINDER = Vector((0.0, 0.088, 0.081)) * _K
HAMMER_SPUR = Vector((0.0, 0.012, 0.112)) * _K
TRIGGER = Vector((0.0, 0.069, 0.016)) * _K
GUARD_FRONT = Vector((0.0, 0.125, 0.020)) * _K

# -- main droite sur la crosse ---------------------------------------------------------------
# Axes de la main (os Mixamo) dans le repère de l'arme : Y = vers les doigts (métacarpes en
# diagonale vers l'avant-bas le long du flanc droit de la crosse), X = côté pouce (vers le haut
# et l'avant, le long de la carcasse). Paume (+Z local) tournée vers la crosse (-X arme).
# Doigts vers l'avant-HAUT : le poignet passe sous la crosse et l'avant-bras arrive par en
# dessous (retour utilisateur 2026-09-27 : « le bras est au-dessus et la main descend attraper »).
PR_Y = Vector((0.0, 1.0, 0.35)).normalized()
PR_X = Vector((0.0, -0.35, 1.0)).normalized()
PALM_DEPTH = 0.012   # du plan des os à la surface de la paume (rig)
PALM_ALONG = 0.45    # centre de la paume : fraction poignet -> base du majeur
# La main droite est accrochée par la BASE DE L'INDEX (mètres, repère de l'arme) : juste derrière
# la détente, à sa hauteur, sur le flanc droit -- comme une vraie prise ; les autres doigts
# tombent dessous, autour de la crosse (paume centrée sur la crosse, l'index passait sous le
# pontet et ne pouvait pas atteindre la détente).
# Les doigts de la grenouille sont énormes (1re phalange de l'index : 5,6 cm) : la base de l'index
# est au milieu de la crosse, l'index s'allonge le long de la carcasse jusqu'à la détente.
GRIP_INDEX_MCP = Vector((0.02, -0.02, 0.028))


def palm_local(arm_obj, side="Right"):
    """Centre de la paume dans le repère local (repos) de l'os de la main (unités rig)."""
    bones = arm_obj.data.bones
    hand = bones[f"mixamorig:{side}Hand"]
    mid = bones[f"mixamorig:{side}HandMiddle1"]
    local = hand.matrix_local.inverted() @ mid.head_local
    z = 1.0 if side == "Right" else -1.0   # paume droite = +Z local, gauche = -Z
    return local * PALM_ALONG + Vector((0.0, 0.0, z * PALM_DEPTH))


def right_hand_frame(arm_obj) -> Matrix:
    """Repère (unités rig) de la main droite dans le repère de l'arme mis à l'échelle du rig :
    axes PR_X/PR_Y, placé pour que la base de l'index tombe sur GRIP_INDEX_MCP."""
    y = PR_Y.normalized()
    x = (PR_X - y * PR_X.dot(y)).normalized()
    z = x.cross(y)
    rot = Matrix((x, y, z)).transposed()
    m = rot.to_4x4()
    bones = arm_obj.data.bones
    mcp = bones["mixamorig:RightHand"].matrix_local.inverted() @ bones["mixamorig:RightHandIndex1"].head_local
    m.translation = GRIP_INDEX_MCP * GUN_SCALE - rot @ mcp
    return m


def add_pistol_grip(arm_obj):
    """Os PistolGrip (enfant de la main droite) = repère du revolver tenu (même construction que
    WeaponGrip : dans Godot, -Z = canon, +Y = haut)."""
    if "PistolGrip" in arm_obj.data.bones:
        return
    t = right_hand_frame(arm_obj)
    bpy.context.view_layer.objects.active = arm_obj
    bpy.ops.object.mode_set(mode="EDIT")
    ebs = arm_obj.data.edit_bones
    eb = ebs.new("PistolGrip")
    eb.head = (0.0, 0.0, 0.0)
    eb.tail = (0.0, 0.05, 0.0)
    eb.parent = ebs["mixamorig:RightHand"]
    eb.use_deform = False
    hand_rest = arm_obj.data.bones["mixamorig:RightHand"].matrix_local.copy()
    eb.matrix = hand_rest @ t.inverted() @ Matrix.Rotation(math.radians(90.0), 4, "X")
    eb.length = 0.05
    bpy.ops.object.mode_set(mode="OBJECT")


# -- main gauche en soutien (elle enveloppe les doigts droits) -------------------------------
# Poignet gauche sous l'avant-gauche de la crosse, doigts qui remontent sur les doigts droits
# (vers +X et le haut), pouce vers l'avant le long du flanc gauche de la carcasse.
PL_WRIST = Vector((-0.045, -0.015, -0.055)) * _K
PL_Y = Vector((0.75, 0.25, 0.62)).normalized()
PL_X = Vector((0.0, 1.0, 0.1)).normalized()

# -- repère du revolver en 3e personne --------------------------------------------------------
AIM_PIVOT = Vector((0.0, -0.02, 0.80))      # milieu des épaules (rig)
GRIP_REST = Vector((-0.035, -0.235, 0.75))  # crosse bras tendus (bras courts de la grenouille : ~0,24 devant le buste)


def pistol_frame(pitch_up=0.0, roll=0.0, yaw=0.0, back=0.0, lift=0.0, side=0.0) -> Matrix:
    """Repère du revolver dans l'espace armature (avant du corps = -Y). La visée tourne tout
    le bloc bras + arme autour du milieu des épaules."""
    aim = Matrix.Rotation(math.radians(-pitch_up), 4, "X") @ Matrix.Rotation(math.radians(yaw), 4, "Z")
    rot = aim @ Matrix.Rotation(math.pi, 4, "Z") @ Matrix.Rotation(math.radians(roll), 4, "Y")
    pos = AIM_PIVOT + aim.to_3x3() @ (GRIP_REST + Vector((side, back, lift)) - AIM_PIVOT)
    m = rot.copy()
    m.translation = pos
    return m


def hold_pistol(rig: Rig, g: Matrix, pitch_up=0.0, left=None, left_y=None, left_x=None,
                chest=(0.0, 0.0), head_follow=0.5, right_curl=74.0, index_deg=38.0, left_curl=70.0,
                clav=(-10.0, 6.0), base_lean=0.0, twist=(-4.0, -5.0)):
    """Pose du haut du corps tenant le revolver `g` à deux mains (buste de face, isocèle).
    `left` : cible libre du poignet gauche, sinon soutien sous la main droite."""
    ch_twist, lean = chest
    rig.rot("Spine1", AX_Z, twist[0] + ch_twist * 0.5)
    rig.rot("Spine2", AX_Z, twist[1] + ch_twist * 0.5)
    rig.rot("Spine1", AX_X, -pitch_up * 0.12 + (lean + base_lean) * 0.5)
    rig.rot("Spine2", AX_X, -pitch_up * 0.18 + (lean + base_lean) * 0.5)
    rig.rot("Neck", AX_Z, 4.0)
    rig.rot("Head", AX_Z, 5.0)
    rig.rot("Neck", AX_X, -pitch_up * head_follow * 0.4 + 4.0)
    rig.rot("Head", AX_X, -pitch_up * head_follow * 0.6 + 8.0)
    rig.rot("LeftShoulder", AX_Z, clav[0])
    rig.rot("RightShoulder", AX_Z, clav[1])
    rig.update()
    gr = g.to_3x3()
    hand = g @ right_hand_frame(rig.arm)   # main droite : centre de paume sur la crosse
    errs = []
    sh = rig.posed("RightArm").translation
    errs.append(rig.ik2("RightArm", "RightForeArm", hand.translation, sh + Vector((-0.30, 0.10, -0.32))))
    rig.orient("RightHand", gr @ PR_Y, gr @ PR_X)
    lw = left if left is not None else g @ (PL_WRIST * GUN_SCALE)
    ly = left_y if left_y is not None else gr @ PL_Y
    lx = left_x if left_x is not None else gr @ PL_X
    sh = rig.posed("LeftArm").translation
    errs.append(rig.ik2("LeftArm", "LeftForeArm", lw, sh + Vector((0.30, 0.10, -0.32))))
    rig.orient("LeftHand", ly, lx)
    rig.spread_twist("RightForeArm", "RightHand")
    rig.spread_twist("LeftForeArm", "LeftHand")
    rig.curl("Right", right_curl, thumb_deg=25.0, index_deg=index_deg)
    rig.curl("Left", left_curl, thumb_deg=15.0)
    return errs


# -- géométrie du barillet (mêmes pivots que build_revolver.py, échelle _K) --------------------
HINGE = Vector((-0.0136, 0.088, 0.0555)) * _K          # axe du bras du barillet
CRANE_OPEN_DEG = -100.0                                # rotation Y du bras : barillet sorti à gauche
EJECTOR_TIP = Vector((0.0, 0.194, 0.075)) * _K         # bout de la baguette d'éjection (bras fermé)


def crane_point(p: Vector, crane_deg: float) -> Vector:
    """Point porté par le bras du barillet (barillet, baguette), bras tourné de `crane_deg`."""
    return HINGE + Matrix.Rotation(math.radians(crane_deg), 3, "Y") @ (p - HINGE)


def swung(p: Vector) -> Vector:
    """Point du barillet (ou de la baguette) une fois le bras ouvert."""
    return crane_point(p, CRANE_OPEN_DEG)


SWUNG_CYL = swung(CYLINDER)
SWUNG_EJECTOR = swung(EJECTOR_TIP)

# -- chronologie partagée avec les pièces du revolver (art/weapons/revolver/animate_revolver.py)
FIRE_S = 0.25
FAN_S = 0.13          # 7,5 coups/s en éventail
RELOAD_S = 2.4
DRAW_S = 0.45
INSPECT_S = 2.5
# Rechargement façon Sheriff : coup de poignet qui fait jaillir le barillet, canon levé et
# paume sur la baguette (les douilles tombent), chargeur rapide enfoncé, coup de poignet
# qui referme, barillet qui tourne.
RELOAD_T = dict(open0=0.09, open1=0.14, settle=0.20, eject=0.26, out=0.30, fall=0.42,
                appear=0.42, align=0.52, insert=0.57, release=0.63, close0=0.72, close1=0.765,
                spin1=0.95)
# Inspection (retour utilisateur 2026-09-27 : la rotation autour du doigt décalait l'arme) :
# flanc droit, flanc gauche, coup de poignet qui ouvre le barillet, la paume gauche le fait
# tourner, coup sec qui referme. L'arme ne bouge jamais dans la main.
INSPECT_T = dict(right=0.12, left=0.40, open0=0.47, open1=0.52, spin0=0.56, spin1=0.84, close0=0.86,
                 close1=0.90)


def _ease(u):
    u = min(max(u, 0.0), 1.0)
    return u * u * (3.0 - 2.0 * u)


def _out(u):
    """Départ sec, arrivée douce (coup de poignet)."""
    u = min(max(u, 0.0), 1.0)
    return 1.0 - (1.0 - u) ** 3


def crane_deg(t: float) -> float:
    """Angle du bras du barillet pendant Rev_Reload (t normalisé) : jaillit avec un léger
    rebond, reste ouvert, se referme d'un coup sec avec un petit rebond."""
    r = RELOAD_T
    if t < r["open0"]:
        return 0.0
    if t < r["open1"]:
        return -112.0 * _out((t - r["open0"]) / (r["open1"] - r["open0"]))
    if t < r["settle"]:
        return lerp(-112.0, CRANE_OPEN_DEG, _ease((t - r["open1"]) / (r["settle"] - r["open1"])))
    if t < r["close0"]:
        return CRANE_OPEN_DEG
    if t < r["close1"]:
        u = (t - r["close0"]) / (r["close1"] - r["close0"])
        return CRANE_OPEN_DEG * (1.0 - u * u)          # accélère jusqu'au claquement
    b = (t - r["close1"]) / 0.05
    return 5.0 * math.sin(math.pi * b) if b < 1.0 else 0.0


def casings_pose(t: float):
    """Douilles (repère du barillet) : (position, rotation X en degrés, échelle)."""
    r = RELOAD_T
    if t < r["eject"] or t >= 0.999:
        return Vector(), 0.0, 1.0
    if t < r["out"]:
        return Vector((0.0, -0.036 * _out((t - r["eject"]) / (r["out"] - r["eject"])), 0.0)), 0.0, 1.0
    if t < r["fall"]:
        u = (t - r["out"]) / (r["fall"] - r["out"])
        pos = Vector((-0.03 * u, -0.036 - 0.09 * u - 0.05 * u * u, -0.02 * u))
        return pos, 220.0 * u, 1.0 - _ease((u - 0.7) / 0.3)
    return Vector(), 0.0, 0.0


LOADER_FAR = Vector((-0.03, -0.11, 0.02))    # repère du barillet : chargeur qui arrive de derrière
LOADER_ALIGN = Vector((0.0, -0.045, 0.0))


def loader_pose(t: float):
    """Chargeur rapide (repère du barillet) : (position, rotation Y en degrés, échelle). Rangé
    DANS le barillet au repos ; caché de l'éjection à son arrivée dans la main."""
    r = RELOAD_T
    if t < r["eject"] or t >= r["insert"]:
        twist = 0.0
        if r["insert"] <= t < r["release"]:
            twist = 18.0 * math.sin(math.pi * (t - r["insert"]) / (r["release"] - r["insert"]))
        return Vector(), twist, 1.0
    if t < r["appear"]:
        return LOADER_FAR.copy(), 0.0, 0.0
    if t < r["align"]:
        return LOADER_FAR.lerp(LOADER_ALIGN, _ease((t - r["appear"]) / (r["align"] - r["appear"]))), 0.0, 1.0
    return LOADER_ALIGN.lerp(Vector(), _ease((t - r["align"]) / (r["insert"] - r["align"]))), 0.0, 1.0


def inspect_crane_deg(t: float) -> float:
    """Bras du barillet pendant l'inspection : jaillit, reste ouvert, claque en se refermant."""
    s = INSPECT_T
    if t < s["open0"] or t >= s["close1"] + 0.05:
        return 0.0
    if t < s["open1"]:
        return -112.0 * _out((t - s["open0"]) / (s["open1"] - s["open0"]))
    if t < s["spin0"]:
        return lerp(-112.0, CRANE_OPEN_DEG, _ease((t - s["open1"]) / (s["spin0"] - s["open1"])))
    if t < s["close0"]:
        return CRANE_OPEN_DEG
    if t < s["close1"]:
        u = (t - s["close0"]) / (s["close1"] - s["close0"])
        return CRANE_OPEN_DEG * (1.0 - u * u)
    return 5.0 * math.sin(math.pi * (t - s["close1"]) / 0.05)


def inspect_cyl_deg(t: float) -> float:
    """Rotation du barillet lancé par la paume (trois tours qui ralentissent)."""
    s = INSPECT_T
    u = min(max((t - s["spin0"]) / (s["spin1"] - s["spin0"]), 0.0), 1.0)
    return 1080.0 * (1.0 - (1.0 - u) ** 2)


def cyl_to_gun(p_local: Vector, t: float) -> Vector:
    """Point du repère du barillet -> repère de l'arme, bras du barillet à l'instant t."""
    return crane_point(CYLINDER + p_local, crane_deg(t))


# -- résolution des cibles de la main gauche ----------------------------------------------------
def left_target(spec, g: Matrix, t: float = 0.0):
    """(position, doigts, pouce) de la main gauche dans l'espace armature.
    spec : None (soutien sous la main droite) | ('gun', point arme) | ('rig', point rig) |
    ('gunf', point, doigts, pouce) | ('load', décalage) : suit le chargeur rapide |
    ('ej', décalage) : suit le bout de la baguette d'éjection (bras du barillet à l'instant t)."""
    gr = g.to_3x3()
    if spec is None:
        return g @ (PL_WRIST * GUN_SCALE), gr @ PL_Y, gr @ PL_X
    kind = spec[0]
    if kind == "gunf":
        return g @ (spec[1] * GUN_SCALE), gr @ spec[2], gr @ spec[3]
    if kind == "rig":
        return Vector(spec[1]), gr @ PL_Y, gr @ PL_X
    if kind == "load":
        pt = cyl_to_gun(loader_pose(t)[0] + spec[1], t)
    elif kind == "ej":
        pt = crane_point(EJECTOR_TIP, crane_deg(t)) + spec[1]
    else:
        pt = spec[1]
    return g @ (pt * GUN_SCALE), gr @ PL_Y, gr @ PL_X


# -- clips 3e personne ------------------------------------------------------------------------
REACH_PISTOL = []


def _keyed(rig: Rig, name, duration, keys, frame_fn, loop=False):
    """keys : (t, paramètres pistol_frame, main gauche (voir left_target), options)."""
    rig.new_action(name)
    n = _frames(duration)
    worst = [0.0, 0.0]
    worst_t = None
    for f in range(n + 1):
        t = f / n
        i = max(j for j in range(len(keys)) if keys[j][0] <= t + 1e-9)
        j = min(i + 1, len(keys) - 1)
        k0, k1 = keys[i], keys[j]
        u = 0.0 if j == i else smooth((t - k0[0]) / (k1[0] - k0[0]))
        p0, p1 = k0[1], k1[1]
        prm = {k: lerp(p0.get(k, 0.0), p1.get(k, 0.0), u) for k in set(p0) | set(p1)}
        g = frame_fn(**prm)
        free = (k0[2] is not None) or (k1[2] is not None)
        a0, a1 = left_target(k0[2], g, t), left_target(k1[2], g, t)
        o0 = k0[3] if len(k0) > 3 else {}
        o1 = k1[3] if len(k1) > 3 else {}
        opts = {k: lerp(o0.get(k, _OPT_DEFAULTS[k]), o1.get(k, _OPT_DEFAULTS[k]), u) for k in set(o0) | set(o1)}
        rig.reset()
        errs = frame_fn.hold(rig, g, left=a0[0].lerp(a1[0], u) if free else None,
                             left_y=a0[1].lerp(a1[1], u) if free else None,
                             left_x=a0[2].lerp(a1[2], u) if free else None,
                             left_curl=opts.pop("left_curl", 45.0 if free else 70.0), **opts)
        if errs[1] > worst[1] + 1e-6:
            worst_t = round(t, 2)
        worst = [max(worst[0], errs[0]), max(worst[1], errs[1])]
        rig.key(f)
    REACH_PISTOL.append((name, [round(w, 3) for w in worst], "pire_gauche_t", worst_t))


_OPT_DEFAULTS = dict(right_curl=74.0, index_deg=38.0, left_curl=70.0)


def _frame3p(**prm):
    return pistol_frame(**prm)


_frame3p.hold = lambda rig, g, **kw: hold_pistol(rig, g, pitch_up=0.0, **kw)


def _pose_clip(rig, name, pitch_up):
    rig.new_action(name)
    for f in (0, 1):
        rig.reset()
        errs = hold_pistol(rig, pistol_frame(pitch_up=pitch_up), pitch_up=pitch_up)
        rig.key(f)
    REACH_PISTOL.append((name, [round(e, 3) for e in errs]))


def build_pistol_breath(rig, duration=2.4):
    """ADDITIF dans le jeu (comme Rifle_Idle) : petits écarts au repos."""
    rig.new_action("Pistol_Idle")
    n = _frames(duration)
    for f in range(n + 1):
        rig.reset()
        b = math.sin(2.0 * math.pi * f / n)
        rig.rot("Spine1", AX_X, 0.8 * b)
        rig.rot("Spine2", AX_X, 1.0 * b)
        rig.rot("LeftShoulder", AX_Y, 1.0 * b)
        rig.rot("RightShoulder", AX_Y, -1.0 * b)
        rig.key(f)


def build_pistol(rig, only=None):
    """Clips 3e personne du revolver (couche haut du corps)."""
    rig.reset()
    rig._twist_prev = {}
    hold_pistol(rig, pistol_frame())
    rig.set_twist_reference()

    def want(n):
        return only is None or n in only

    for name, pitch in (("Pistol_Aim_Down", -45.0), ("Pistol_Aim_Neutral", 0.0), ("Pistol_Aim_Up", 50.0)):
        if want(name):
            _pose_clip(rig, name, pitch)
    if want("Pistol_Idle"):
        build_pistol_breath(rig)
    if want("Pistol_Fire"):
        _keyed(rig, "Pistol_Fire", FIRE_S, [
            (0.0, dict(), None),
            (0.2, dict(pitch_up=12.0, back=0.012), None),
            (1.0, dict(), None),
        ], _frame3p)
    if want("Pistol_Reload"):
        r = RELOAD_T
        # roll > 0 : flanc gauche (côté barillet) vers le haut.
        tilt = dict(roll=50.0, pitch_up=10.0, back=0.08, lift=-0.05, yaw=-8.0)
        flick = dict(tilt, roll=68.0)
        eject = dict(tilt, pitch_up=50.0, roll=20.0, back=0.11, lift=-0.09, yaw=0.0)
        present = dict(tilt, pitch_up=-15.0, roll=45.0)
        under = ("gun", CYLINDER + Vector((-0.05, -0.03, -0.045)))
        _keyed(rig, "Pistol_Reload", RELOAD_S, [
            (0.00, dict(), None),
            (r["open0"], tilt, ("gun", CYLINDER + Vector((-0.042, 0.0, 0.0)))),
            (r["open1"], flick, ("gun", CYLINDER + Vector((-0.05, 0.0, 0.004)))),
            (r["settle"], tilt, ("ej", Vector((0.0, 0.02, 0.0)))),
            (r["eject"], eject, ("ej", Vector((0.0, 0.012, 0.0)))),
            (r["out"], dict(eject, lift=-0.1), ("ej", Vector((0.0, -0.004, 0.0)))),
            (r["out"] + 0.06, present, ("rig", Vector((0.12, -0.05, 0.60)))),  # ceinture
            (r["appear"] + 0.02, present, ("load", Vector((0.0, -0.03, 0.0)))),
            (r["insert"], present, ("load", Vector((0.0, -0.03, 0.0)))),
            (r["release"], present, ("gun", SWUNG_CYL + Vector((-0.03, -0.05, 0.02)))),
            (r["close0"], dict(tilt, roll=35.0), under),
            (r["close1"], dict(roll=-20.0, pitch_up=4.0), under),
            (r["close1"] + 0.06, dict(roll=-4.0), None),
            (1.00, dict(), None),
        ], _frame3p)
    if want("Pistol_Draw"):
        _keyed(rig, "Pistol_Draw", DRAW_S, [
            (0.0, dict(pitch_up=-70.0, back=0.10, lift=-0.20, side=-0.06, roll=-20.0), ("rig", Vector((0.12, -0.05, 0.55)))),
            (0.7, dict(pitch_up=4.0), None),
            (1.0, dict(), None),
        ], _frame3p)
    for e in REACH_PISTOL:
        print("REACH_PISTOL", e)
    return ["Pistol_Aim_Down", "Pistol_Aim_Neutral", "Pistol_Aim_Up", "Pistol_Idle", "Pistol_Fire",
            "Pistol_Reload", "Pistol_Draw"]
