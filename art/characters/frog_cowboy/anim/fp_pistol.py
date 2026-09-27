"""Clips de la vue FPS avec le revolver (bras seuls de la grenouille), noms FPP_*.

Même repère que fp.py : œil FP_EYE, regard -Y ; le jeu cale l'os FPCamera sur sa caméra.
Pas de visée avec le revolver (mode « Classic » : clic droit = éventail).

Mains posées explicitement (retour utilisateur 2026-09-27 : « les doigts sont pas bien placés,
la main fait n'importe quoi ») : chaque clé dit où va le CENTRE DE LA PAUME gauche, vers où
pointent ses doigts, vers où regarde sa paume, et plie chaque doigt ; la main droite garde sa
prise (poignet dans l'axe de l'avant-bras, doigts refermés autour de la crosse). Les points qui
bougent (baguette d'éjection, chargeur rapide) suivent pistol.py, comme les pièces du revolver
(art/weapons/revolver/animate_revolver.py) : la main tient vraiment le chargeur.
Contrôle : pose_lab.py (« FPP_Reload@0.26 » = cet instant du clip, depuis l'œil + gros plans).
"""
import math

from mathutils import Matrix, Vector

import pistol as P
from clips import _frames
from fp import FP_EYE, _with, fp_gun
from rifle import GUN_SCALE
from rigkit import AX_X, AX_Y, AX_Z, Rig, lerp, smooth

IDLE_P = dict(right=0.075, down=0.004, fwd=0.23, pitch_up=1.0, roll=-8.0, yaw=9.0)

# -- mains -------------------------------------------------------------------------------------
GRIP_R = {"Index": (20.0, 25.0, 15.0), "Middle": (85.0, 95.0, 55.0), "Ring": (88.0, 95.0, 55.0),
          "Pinky": (85.0, 90.0, 50.0), "Thumb": (15.0, 20.0, 10.0)}
FIRE_R = dict(GRIP_R, Index=(38.0, 42.0, 25.0))          # index pressé sur la détente

# Main gauche : paume (repère de l'arme, m) ou point mobile, direction des doigts, de la paume.
SUPPORT = dict(palm=Vector((-0.004, -0.01, -0.058)), palm_dir=Vector((0.1, 0.1, 1.0)),
               fingers_dir=Vector((1.0, 0.35, 0.0)),
               fingers={"Index": (40.0, 45.0, 25.0), "Middle": (45.0, 50.0, 25.0), "Ring": (45.0, 50.0, 25.0),
                        "Pinky": (40.0, 45.0, 20.0), "Thumb": (35.0, 30.0, 15.0)})
HOLD = {"Index": (55.0, 60.0, 35.0), "Middle": (60.0, 65.0, 35.0), "Ring": (60.0, 65.0, 35.0),
        "Pinky": (55.0, 60.0, 30.0), "Thumb": (30.0, 25.0, 10.0)}
RELAX = {"Index": (25.0, 25.0, 15.0), "Middle": (30.0, 30.0, 15.0), "Ring": (32.0, 30.0, 15.0),
         "Pinky": (35.0, 30.0, 15.0), "Thumb": (10.0, 10.0, 5.0)}


def fpp_gun(**prm):
    """Repère du revolver en vue FPS : le cran de mire est placé par rapport à l'œil."""
    return fp_gun(anchor=P.REAR_SIGHT, **prm)


def _hand_rot(side, fingers_dir, palm_dir) -> Matrix:
    y = Vector(fingers_dir).normalized()
    pd = Vector(palm_dir)
    pd = (pd - y * pd.dot(y)).normalized()
    z = pd if side == "Right" else -pd
    return Matrix((y.cross(z), y, z)).transposed()


def resolve_left(spec, g, t):
    """spec (None = soutien) -> (paume, doigts, dir. paume : espace armature ; doigts pliés)."""
    spec = SUPPORT if spec is None else spec
    gr = g.to_3x3()
    palm = spec["palm"]
    if isinstance(palm, tuple):
        kind, off = palm
        if kind == "rig":
            palm_w = Vector(off)
        else:
            pt = P.cyl_to_gun(P.loader_pose(t)[0] + off, t) if kind == "load" else \
                P.crane_point(P.EJECTOR_TIP, P.crane_deg(t)) + off
            palm_w = g @ (pt * GUN_SCALE)
    else:
        palm_w = g @ (Vector(palm) * GUN_SCALE)
    conv = (lambda v: Vector(v)) if spec.get("dirs_rig") else (lambda v: gr @ Vector(v))
    return palm_w, conv(spec["fingers_dir"]).normalized(), conv(spec["palm_dir"]).normalized(), spec["fingers"]


def _mix_fingers(a, b, u):
    out = {}
    for k in set(a) | set(b):
        if k.endswith("Spread") or k == "ThumbOpp":
            out[k] = lerp(float(a.get(k, 0.0)), float(b.get(k, 0.0)), u)
            continue
        va, vb = a.get(k, (0.0, 0.0, 0.0)), b.get(k, (0.0, 0.0, 0.0))
        out[k] = tuple(lerp(x, y, u) for x, y in zip(va, vb))
    return out


def fpp_pose(rig: Rig, g, left, right_fingers):
    """left = (paume, doigts, dir. paume, doigts pliés) dans l'espace armature."""
    rig.rot("LeftShoulder", AX_Y, -14.0)
    rig.rot("RightShoulder", AX_Y, 12.0)
    rig.rot("Spine1", AX_Z, -2.0)
    rig.rot("Spine2", AX_Z, -3.0)
    rig.rot("Spine1", AX_X, 11.0)
    rig.rot("Spine2", AX_X, 11.0)
    rig.rot("LeftShoulder", AX_Z, -24.0)
    rig.rot("RightShoulder", AX_Z, 14.0)
    rig.update()
    gr = g.to_3x3()
    errs = []
    hand = g @ P.right_hand_frame(rig.arm)
    sh = rig.posed("RightArm").translation
    errs.append(rig.ik2("RightArm", "RightForeArm", hand.translation, sh + Vector((-0.30, 0.10, -0.32))))
    rig.orient("RightHand", gr @ P.PR_Y, gr @ P.PR_X)
    palm_w, fdir, pdir, fingers = left
    wrist = palm_w - _hand_rot("Left", fdir, pdir) @ P.palm_local(rig.arm, "Left")
    sh = rig.posed("LeftArm").translation
    errs.append(rig.ik2("LeftArm", "LeftForeArm", wrist, sh + Vector((0.30, 0.10, -0.32))))
    rig.hand_orient("Left", fdir, pdir)
    rig.spread_twist("RightForeArm", "RightHand")
    rig.spread_twist("LeftForeArm", "LeftHand")
    rig.fingers("Right", right_fingers)
    rig.fingers("Left", fingers)
    return errs


def pose_at(rig: Rig, keys, t):
    """keys : (t, paramètres fpp_gun, main gauche (dict ou None), doigts droits (ou None)).
    Pose le rig à l'instant t (interpolation douce entre clés). Renvoie les erreurs d'IK."""
    i = max(j for j in range(len(keys)) if keys[j][0] <= t + 1e-9)
    j = min(i + 1, len(keys) - 1)
    k0, k1 = keys[i], keys[j]
    u = 0.0 if j == i else smooth((t - k0[0]) / (k1[0] - k0[0]))
    p0, p1 = k0[1], k1[1]
    g = fpp_gun(**{k: lerp(p0.get(k, 0.0), p1.get(k, 0.0), u) for k in set(p0) | set(p1)})
    a, b = resolve_left(k0[2], g, t), resolve_left(k1[2], g, t)
    left = (a[0].lerp(b[0], u), a[1].lerp(b[1], u).normalized(), a[2].lerp(b[2], u).normalized(),
            _mix_fingers(a[3], b[3], u))
    rf = _mix_fingers(k0[3] or GRIP_R, k1[3] or GRIP_R, u)
    rig.reset()
    return fpp_pose(rig, g, left, rf)


REACH_FPP = []


def _clip(rig: Rig, name, duration, keys):
    rig.new_action(name)
    n = _frames(duration)
    worst, worst_t = [0.0, 0.0], None
    for f in range(n + 1):
        errs = pose_at(rig, keys, f / n)
        if errs[1] > worst[1] + 1e-6:
            worst_t = round(f / n, 2)
        worst = [max(worst[0], errs[0]), max(worst[1], errs[1])]
        rig.key(f)
    REACH_FPP.append((name, [round(w, 3) for w in worst], "pire_gauche_t", worst_t))


def K(t, gun, left=None, right=None):
    return (t, gun, left, right)


# -- clips -------------------------------------------------------------------------------------
def clip_keys():
    r = P.RELOAD_T
    s = P.INSPECT_T
    kick = _with(IDLE_P, pitch_up=IDLE_P["pitch_up"] + 11.0, fwd=IDLE_P["fwd"] - 0.02, down=IDLE_P["down"] - 0.008)
    # Éventail : recul sec au coup (t=0), retour, nouveau coup (t=1 = t=0 du clip suivant).
    # tir à la hanche, bas à droite : la main qui évente reste sous le centre de l'écran
    fan_p = _with(IDLE_P, roll=-12.0, pitch_up=2.0)
    fan_kick = _with(fan_p, pitch_up=fan_p["pitch_up"] + 9.0, fwd=fan_p["fwd"] - 0.018, roll=-16.0)
    # Rechargement (voir pistol.RELOAD_T) : l'arme se couche flanc gauche vers la caméra.
    tilt = _with(IDLE_P, right=0.03, down=0.035, fwd=0.20, roll=35.0, yaw=-20.0, pitch_up=8.0)
    flick = _with(tilt, roll=52.0, right=0.035)
    eject = _with(tilt, pitch_up=45.0, roll=15.0, down=0.06, fwd=0.19, yaw=-10.0)
    present = _with(tilt, pitch_up=-12.0, roll=30.0, yaw=-45.0, right=0.0, down=0.03, fwd=0.21)
    # La main gauche garde le barillet au creux de la paume (doigts le long du canon, repliés
    # autour) ; pour éjecter, c'est le POUCE tendu qui pousse la baguette (main compacte, près
    # de l'arme : paume à plat sur la baguette, elle sortait de portée et faisait « stop » à l'œil).
    wrap = {"Index": (45.0, 50.0, 30.0), "Middle": (50.0, 55.0, 30.0), "Ring": (50.0, 55.0, 30.0),
            "Pinky": (45.0, 50.0, 25.0), "Thumb": (20.0, 15.0, 10.0)}
    cradle = dict(palm=P.CYLINDER + Vector((-0.045, 0.0, -0.035)), palm_dir=Vector((0.6, 0.0, 0.8)),
                  fingers_dir=Vector((0.0, 1.0, 0.0)), fingers=wrap)
    cradle_open = dict(cradle, palm=P.SWUNG_CYL + Vector((-0.012, 0.0, -0.04)), palm_dir=Vector((0.2, 0.0, 1.0)))
    thumb_out = dict(wrap, Thumb=(0.0, 0.0, 0.0))
    eject_hit = dict(cradle_open, palm=P.SWUNG_CYL + Vector((-0.012, 0.03, -0.04)), fingers=thumb_out)
    eject_push = dict(cradle_open, palm=P.SWUNG_CYL + Vector((-0.012, 0.018, -0.04)), fingers=thumb_out)
    belt = dict(palm=("rig", FP_EYE + Vector((0.12, -0.06, -0.30))), palm_dir=Vector((-1.0, 0.0, 0.0)),
                fingers_dir=Vector((0.0, 0.0, -1.0)), fingers=HOLD, dirs_rig=True)
    loader = dict(palm=("load", Vector((0.0, -0.03, 0.0))), palm_dir=Vector((0.0, 1.0, 0.0)),
                  fingers_dir=Vector((0.0, 0.0, 1.0)), fingers=HOLD)            # derrière le chargeur, doigts autour
    let_go = dict(loader, palm=P.SWUNG_CYL + Vector((-0.03, -0.07, 0.03)), fingers=RELAX)
    # Inspection (pistol.INSPECT_T) : flanc droit, flanc gauche, barillet ouvert d'un coup de
    # poignet, la paume gauche le fait tourner, coup sec qui referme. L'arme ne bouge pas dans la main.
    show_r = _with(IDLE_P, right=0.02, down=0.035, fwd=0.17, yaw=32.0, roll=-30.0, pitch_up=12.0)
    show_l = _with(IDLE_P, right=0.03, down=0.035, fwd=0.20, yaw=-24.0, roll=42.0, pitch_up=10.0)
    low = dict(belt, palm=("rig", FP_EYE + Vector((0.12, -0.06, -0.30))), fingers=RELAX)
    brush_top = dict(palm=P.SWUNG_CYL + Vector((-0.034, -0.005, 0.03)), palm_dir=Vector((1.0, 0.0, -0.4)),
                     fingers_dir=Vector((0.0, 1.0, 0.0)), fingers=RELAX)
    brush_low = dict(brush_top, palm=P.SWUNG_CYL + Vector((-0.03, 0.005, -0.035)), palm_dir=Vector((1.0, 0.0, 0.5)))
    return {
        "FPP_Idle": (2.4, [K(t, _with(IDLE_P, down=IDLE_P["down"] + 0.003 * math.sin(2 * math.pi * t),
                                      pitch_up=IDLE_P["pitch_up"] + 0.6 * math.sin(2 * math.pi * t + 0.6)))
                           for t in (0.0, 0.25, 0.5, 0.75, 1.0)]),
        "FPP_ADS_In": (1.0, [K(0.0, IDLE_P), K(1.0, IDLE_P)]),   # pas de visée (mode Classic) : clip neutre
        "FPP_Fire": (P.FIRE_S, [K(0.0, IDLE_P, None, FIRE_R), K(0.2, kick, None, FIRE_R), K(1.0, IDLE_P)]),
        # Vue FPS : la grosse main gauche qui rabattait le chien par-dessus cachait toute l'arme
        # (gant plus gros que le revolver, vu de derrière). Elle reste en soutien ; l'éventail se
        # lit par des reculs secs à chaque coup, le chien et le barillet du revolver (Rev_Fan).
        "FPP_Fan": (P.FAN_S, [K(0.0, fan_kick, None, FIRE_R), K(0.5, fan_p, None, FIRE_R),
                              K(1.0, fan_kick, None, FIRE_R)]),
        "FPP_Reload": (P.RELOAD_S, [
            K(0.00, IDLE_P),
            K(r["open0"], tilt, cradle),
            K(r["open1"], flick, cradle_open),
            K(r["settle"], tilt, eject_hit),
            K(r["eject"], eject, eject_hit),
            K(r["out"], _with(eject, down=0.075), eject_push),
            K(r["out"] + 0.06, present, belt),
            K(r["appear"] + 0.02, present, loader),
            K(r["insert"], present, loader),
            K(r["release"], present, let_go),
            K(r["close0"], _with(tilt, roll=35.0), cradle_open),
            K(r["close1"], _with(IDLE_P, roll=-18.0, right=0.08, down=0.01), cradle),
            K(r["close1"] + 0.06, _with(IDLE_P, roll=-4.0)),
            K(1.00, IDLE_P),
        ]),
        "FPP_Draw": (P.DRAW_S, [K(0.0, _with(IDLE_P, down=0.27, pitch_up=-60.0, roll=-30.0, yaw=15.0), belt),
                                K(0.7, _with(IDLE_P, pitch_up=IDLE_P["pitch_up"] + 4.0)),
                                K(1.0, IDLE_P)]),
        "FPP_Inspect": (P.INSPECT_S, [
            K(0.00, IDLE_P),
            K(s["right"], show_r, low),
            K(s["left"] - 0.08, _with(show_r, yaw=26.0, roll=-26.0), low),
            K(s["left"], show_l, cradle),
            K(s["open0"], show_l, cradle),
            K(s["open1"], _with(show_l, roll=58.0), cradle_open),
            K(s["spin0"], show_l, brush_top),
            K(s["spin0"] + 0.06, show_l, brush_low),
            K(s["close0"], show_l, cradle_open),
            K(s["close1"], _with(IDLE_P, roll=-18.0, right=0.08, down=0.01), cradle),
            K(s["close1"] + 0.05, _with(IDLE_P, roll=-4.0)),
            K(1.00, IDLE_P),
        ]),
    }


TRIGGER_PAD = P.TRIGGER + Vector((0.0, -0.004, 0.004))   # face avant de la détente, où se pose la pulpe


def solve_trigger_finger(rig: Rig):
    """Pose l'index droit sur la détente (retour utilisateur 2026-09-27 : « le doigt n'est pas sur
    la gâchette ») : recherche des angles des 3 phalanges + un léger écart latéral, main posée
    une fois (elle est solidaire de l'arme : un seul calcul vaut pour tous les clips). Met à jour
    GRIP_R / FIRE_R ; renvoie (angles, écart latéral, distance restante en m)."""
    from mathutils import Quaternion
    pose_at(rig, [K(0.0, IDLE_P, None, dict(GRIP_R, Index=(0.0, 0.0, 0.0)))], 0.0)
    rig.update()
    target = fpp_gun(**IDLE_P) @ (TRIGGER_PAD * GUN_SCALE)
    names = ("RightHandIndex1", "RightHandIndex2", "RightHandIndex3")
    base = {n: rig.pb(n).rotation_quaternion.copy() for n in names}
    best = None
    for spread in range(-30, 31, 5):
        for a1 in range(-15, 46, 5):
            for a2 in range(0, 61, 5):
                a3 = 0.9 * a2 + 15.0   # le dernier segment s'enroule derrière la détente
                for n, a in zip(names, (a1, a2, a3)):
                    q = base[n].copy()
                    if n == names[0] and spread:
                        q = Quaternion((0.0, 0.0, 1.0), math.radians(spread)) @ q
                    rig.pb(n).rotation_quaternion = Quaternion((1.0, 0.0, 0.0), math.radians(a)) @ q
                rig.update()
                pad = rig.pb(names[2]).head.lerp(rig.pb(names[2]).tail, 0.25)  # juste après la dernière articulation
                d = (pad - target).length
                if best is None or d < best[2]:
                    best = ((float(a1), float(a2), a3), float(spread), d)
    (a1, a2, a3), spread, d = best
    # diagnostic (repère de l'arme, m) : base de l'index, pulpe retenue, cible
    inv = fpp_gun(**IDLE_P).inverted()
    for n, a in zip(names, (a1, a2, a3)):
        q = base[n].copy()
        if n == names[0] and spread:
            q = Quaternion((0.0, 0.0, 1.0), math.radians(spread)) @ q
        rig.pb(n).rotation_quaternion = Quaternion((1.0, 0.0, 0.0), math.radians(a)) @ q
    rig.update()
    g_pt = lambda v: tuple(round(c, 3) for c in (inv @ v) / GUN_SCALE)
    print("TRIGGER_DIAG a", (a1, a2, round(a3, 1)), "mcp", g_pt(rig.pb(names[0]).head), "pip", g_pt(rig.pb(names[1]).head),
          "dip", g_pt(rig.pb(names[2]).head), "tip", g_pt(rig.pb(names[2]).tail),
          "target", tuple(round(c, 3) for c in TRIGGER_PAD))
    GRIP_R["Index"] = (a1, a2, a3)
    GRIP_R["IndexSpread"] = spread
    FIRE_R["Index"] = (a1 + 5.0, a2 + 8.0, a3 + 5.0)   # pressée
    FIRE_R["IndexSpread"] = spread
    return (a1, a2, a3), spread, d * 1.8


def build_fp_pistol(rig: Rig):
    angles, spread, gap = solve_trigger_finger(rig)
    print("TRIGGER_FINGER", [round(a, 1) for a in angles], "ecart", spread, "distance_m", round(gap, 4))
    rig.reset()
    rig._twist_prev = {}
    pose_at(rig, [K(0.0, IDLE_P)], 0.0)
    rig.set_twist_reference()
    keys = clip_keys()
    for name, (dur, k) in keys.items():
        _clip(rig, name, dur, k)
    for e in REACH_FPP:
        print("REACH_FPP", e)
    return list(keys)


FPP_LOOPS = ("FPP_Idle",)


# -- atelier -----------------------------------------------------------------------------------
LAB_WRISTS = {
    # doigts de la main droite (repère arme) : inclinaison vers le haut = poignet sous la crosse
    "wrist_a": Vector((0.0, 1.0, 0.15)),
    "wrist_b": Vector((0.0, 1.0, 0.35)),
    "wrist_c": Vector((0.0, 1.0, 0.55)),
}


def lab_setup(name):
    """Atelier : applique une variante de poignet AVANT que l'atelier reconstruise PistolGrip."""
    base = name.split("@")[0]
    if base in LAB_WRISTS:
        P.PR_Y = LAB_WRISTS[base].normalized()
        P.PR_X = Vector((0.0, -P.PR_Y.z, P.PR_Y.y)).normalized()


def lab_pose(rig: Rig, name):
    """« FPP_Reload@0.26 » : cet instant du clip ; renvoie les pièces du revolver à cet instant."""
    clip, _, at = name.partition("@")
    t = float(at) if at else 0.0
    if clip in LAB_WRISTS or clip == "trigger":
        angles, spread, gap = solve_trigger_finger(rig)
        print("TRIGGER_FINGER", name, [round(a, 1) for a in angles], "ecart", spread, "distance_m", round(gap, 4))
        clip = "FPP_Idle"
    dur, keys = clip_keys()[clip]
    errs = pose_at(rig, keys, t)
    print("LAB_REACH", name, [round(e, 3) for e in errs])
    if clip == "FPP_Inspect":
        return {"Crane": ("Y", P.inspect_crane_deg(t), (0.0, 0.0, 0.0)),
                "Cylinder": ("Y", P.inspect_cyl_deg(t), (0.0, 0.0, 0.0))}
    if clip != "FPP_Reload":
        return {}
    c_loc, c_rot, c_scale = P.casings_pose(t)
    l_loc, l_rot, l_scale = P.loader_pose(t)
    return {"Crane": ("Y", P.crane_deg(t), (0.0, 0.0, 0.0)),
            "Casings": ("X", c_rot, tuple(c_loc), c_scale), "Loader": ("Y", l_rot, tuple(l_loc), l_scale)}
