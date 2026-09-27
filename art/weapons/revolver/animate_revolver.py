"""Animations des pièces du revolver (Rev_*), synchronisées avec les bras (FPP_*/Pistol_*).

Chronologie partagée : art/characters/frog_cowboy/anim/pistol.py (durées, bras du barillet,
douilles, chargeur rapide, rotation autour de l'index) -- les mains des clips de bras suivent
les MÊMES fonctions, donc la main tient vraiment le chargeur. Ouvre revolver_rig.blend
(produit par build_revolver.py), ajoute les actions, réexporte assets/models/weapons/revolver.glb.

  blender -b --factory-startup --python art/weapons/revolver/animate_revolver.py

Os (voir build_revolver.py) : Crane/Cylinder tournent autour de leur Y (avant) ; Hammer
autour de X (+ = armé) ; Trigger autour de X (- = pressée) ; Casings et Loader (enfants du
barillet) : douilles et chargeur rapide, rangés dans le barillet au repos.
"""
import math
import os
import sys

import bpy
from mathutils import Quaternion, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "art", "characters", "frog_cowboy", "anim"))
from pistol import (DRAW_S, FAN_S, FIRE_S, INSPECT_S, RELOAD_S, RELOAD_T, casings_pose,  # noqa: E402
                    crane_deg, inspect_crane_deg, inspect_cyl_deg, loader_pose)

FPS = 30
BLEND = os.path.join(HERE, "revolver_rig.blend")
OUT_GLB = os.path.join(ROOT, "assets", "models", "weapons", "revolver.glb")
BONES = ("Root", "Crane", "Cylinder", "Hammer", "Trigger", "Casings", "Loader")
TRIGGER_PULL = -22.0
HAMMER_COCK = 38.0
AXES = {"X": Vector((1, 0, 0)), "Y": Vector((0, 1, 0)), "Z": Vector((0, 0, 1))}


def smooth(u):
    u = min(max(u, 0.0), 1.0)
    return u * u * (3.0 - 2.0 * u)


def ramp(t, t0, t1, a, b):
    """a avant t0, b après t1, transition douce entre les deux."""
    if t1 <= t0:
        return b if t >= t1 else a
    return a + (b - a) * smooth((t - t0) / (t1 - t0))


def frames(duration):
    return max(2, int(round(duration * FPS)))


def P(deg=0.0, axis="X", loc=None, scale=1.0):
    return {"deg": deg, "axis": axis, "loc": loc if loc is not None else Vector(), "scale": scale}


def key_clip(arm, name, duration, pose_at):
    """pose_at(t) -> {os: P(...)} ; les os absents restent au repos (échelle 1)."""
    act = bpy.data.actions.new(name)
    act.use_fake_user = True
    arm.animation_data.action = act
    n = frames(duration)
    prev = {}
    for f in range(n + 1):
        pose = pose_at(f / n)
        for b in BONES:
            pb = arm.pose.bones[b]
            p = pose.get(b, P())
            q = Quaternion(AXES[p["axis"]], math.radians(p["deg"]))
            if b in prev and prev[b].dot(q) < 0.0:
                q.negate()
            prev[b] = q
            pb.rotation_quaternion = q
            pb.location = p["loc"]
            pb.scale = (p["scale"],) * 3
            for path in ("rotation_quaternion", "location", "scale"):
                pb.keyframe_insert(path, frame=f)
    return act


def rest(_t):
    return {}


def fire(t):
    return {"Trigger": P(ramp(t, 0.0, 0.4, TRIGGER_PULL, 0.0)),
            "Cylinder": P(ramp(t, 0.15, 0.6, 0.0, 60.0), "Y")}


def fan(t):
    # Au coup (t=0) le chien vient de tomber ; la paume le rabat à la fin du cycle (t=0,95),
    # il retombe au coup suivant. Le barillet avance d'un cran pendant l'armement.
    hammer = ramp(t, 0.5, 0.95, 0.0, HAMMER_COCK) if t < 0.97 else 0.0
    return {"Trigger": P(TRIGGER_PULL), "Hammer": P(hammer),
            "Cylinder": P(ramp(t, 0.5, 0.95, 0.0, 60.0), "Y")}


def reload(t):
    r = RELOAD_T
    c_loc, c_rot, c_scale = casings_pose(t)
    l_loc, l_rot, l_scale = loader_pose(t)
    # barillet : tour complet après le claquement de fermeture (flourish)
    spin = 360.0 * (1.0 - (1.0 - min(max((t - r["close1"]) / (r["spin1"] - r["close1"]), 0.0), 1.0)) ** 2) \
        if t >= r["close1"] else 0.0
    return {"Crane": P(crane_deg(t), "Y"), "Cylinder": P(spin, "Y"),
            "Casings": P(c_rot, "X", c_loc, c_scale), "Loader": P(l_rot, "Y", l_loc, l_scale)}


def draw(t):
    return {"Cylinder": P(ramp(t, 0.3, 1.0, 0.0, 120.0), "Y")}


def inspect(t):
    # barillet ouvert d'un coup de poignet, lancé par la paume, refermé d'un coup sec
    return {"Crane": P(inspect_crane_deg(t), "Y"), "Cylinder": P(inspect_cyl_deg(t), "Y")}


def main():
    bpy.ops.wm.open_mainfile(filepath=BLEND)
    scene = bpy.context.scene
    scene.render.fps = FPS
    scene.render.fps_base = 1.0
    arm = bpy.data.objects["RevolverRig"]
    if arm.animation_data is None:
        arm.animation_data_create()
    for b in BONES:
        arm.pose.bones[b].rotation_mode = "QUATERNION"
    clips = (("Rev_Idle", 1.0 / FPS, rest), ("Rev_Fire", FIRE_S, fire), ("Rev_Fan", FAN_S, fan),
             ("Rev_Reload", RELOAD_S, reload), ("Rev_Draw", DRAW_S, draw), ("Rev_Inspect", INSPECT_S, inspect))
    for name, dur, fn in clips:
        key_clip(arm, name, dur, fn)
    arm.animation_data.action = None
    for pb in arm.pose.bones:
        pb.rotation_quaternion = (1.0, 0.0, 0.0, 0.0)
        pb.location = (0.0, 0.0, 0.0)
        pb.scale = (1.0, 1.0, 1.0)
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(filepath=OUT_GLB, export_format="GLB", use_selection=True, export_yup=True,
                              export_skins=True, export_animations=True, export_animation_mode="ACTIONS",
                              export_force_sampling=True, export_image_format="AUTO")
    print("REVOLVER_ANIM_OK", [c[0] for c in clips], "->", OUT_GLB)


main()
