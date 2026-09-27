"""Gros plans de contrôle de la tenue du revolver (sans toucher au .blend).

    blender -b art/characters/frog_cowboy/Untitled.blend -P art/characters/frog_cowboy/anim/preview_pistol.py -- \
        --out DIR [--clips Pistol_Aim_Neutral,...] [--frames 6] [--fp]
Sans --clips : pose de tenue statique (visée neutre), 4 vues rapprochées des mains.
"""
import argparse
import math
import os
import sys

import bpy
import numpy as np
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", "..", ".."))
sys.path.insert(0, HERE)
from pistol import add_pistol_grip, hold_pistol, pistol_frame  # noqa: E402
from rigkit import Rig  # noqa: E402

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
ap = argparse.ArgumentParser()
ap.add_argument("--out", required=True)
ap.add_argument("--clips", default="")
ap.add_argument("--frames", type=int, default=6)
args = ap.parse_args(argv)
out_dir = os.path.abspath(args.out)
os.makedirs(out_dir, exist_ok=True)

arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
mesh = next(o for o in bpy.data.objects if o.type == "MESH" and o.parent is arm)
for o in bpy.data.objects:
    if (o.type == "MESH" and o is not mesh) or o.type in ("CAMERA", "LIGHT"):
        o.hide_render = True
arm.hide_viewport = False
arm.hide_set(False)
bpy.context.view_layer.objects.active = arm
add_pistol_grip(arm)
rig = Rig(arm)

clips = [c for c in args.clips.split(",") if c]
if clips:
    from pistol import build_pistol  # noqa: E402
    build_pistol(rig, clips)
else:
    rig.reset()
    errs = hold_pistol(rig, pistol_frame())
    print("PISTOL_REACH", [round(e, 3) for e in errs])

before = set(bpy.data.objects)
bpy.ops.import_scene.gltf(filepath=os.path.join(ROOT, "assets/models/weapons/revolver.glb"))
new = [o for o in bpy.data.objects if o not in before]
gun_rig = next(o for o in new if o.type == "ARMATURE")
for o in new:
    if o.type == "EMPTY":
        o.hide_render = True
grip = arm.pose.bones["PistolGrip"]
gun_rig.parent = arm
gun_rig.parent_type = "BONE"
gun_rig.parent_bone = "PistolGrip"
gun_rig.location = (0.0, -grip.bone.length, 0.0)
gun_rig.rotation_mode = "XYZ"   # l'importeur glTF pose des quaternions : l'Euler serait ignoré
gun_rig.rotation_euler = (-math.pi / 2.0, 0.0, 0.0)   # os : Y = haut de l'arme
gun_rig.scale = (1.0 / 1.8,) * 3
for o in new:
    if o.type == "MESH" and o.parent is None:
        o.hide_render = True   # « Icosphere » : forme d'affichage des os créée par l'importeur
bpy.context.view_layer.update()
_mz = next(o for o in new if o.name.startswith("Muzzle"))
print("PISTOL_DBG grip", tuple(round(c, 3) for c in (arm.matrix_world @ grip.head)),
      "muzzle", tuple(round(c, 3) for c in _mz.matrix_world.translation),
      "arm_obj_rot", tuple(round(c, 3) for c in arm.rotation_euler), "arm_scale", tuple(round(c, 3) for c in arm.scale))

scene = bpy.context.scene
scene.render.engine = "BLENDER_WORKBENCH"
scene.display.shading.light = "STUDIO"
scene.display.shading.color_type = "TEXTURE"
scene.display.shading.show_object_outline = True
scene.render.resolution_x, scene.render.resolution_y = 420, 420
cam = bpy.data.objects.new("PrevCam", bpy.data.cameras.new("PrevCam"))
scene.collection.objects.link(cam)
scene.camera = cam
cam.data.type = "ORTHO"
bpy.context.view_layer.update()
center = (arm.matrix_world @ grip.head) if not clips else Vector((0.0, -0.3, 0.75))
VIEWS = {"droite": Vector((-1, 0, 0.15)), "gauche": Vector((1, -0.3, 0.2)),
         "dessus": Vector((-0.3, -0.4, 1)), "face": Vector((-0.35, -1, 0.25)), "corps": Vector((-0.8, -1, 0.35))}
tmp = os.path.join(out_dir, "_tmp.png")


def shot(view, scale):
    d = VIEWS[view].normalized()
    cam.data.ortho_scale = scale
    c = center if view != "corps" else Vector((0.0, -0.15, 0.62))
    cam.location = c + d * 3.0
    cam.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
    scene.render.filepath = tmp
    bpy.ops.render.render(write_still=True)
    img = bpy.data.images.load(tmp, check_existing=False)
    px = np.array(img.pixels[:], np.float32).reshape(img.size[1], img.size[0], 4)
    bpy.data.images.remove(img)
    return px


def save(name, px):
    out = bpy.data.images.new(name, px.shape[1], px.shape[0], alpha=True)
    out.pixels.foreach_set(px.ravel())
    out.filepath_raw = os.path.join(out_dir, name + ".png")
    out.file_format = "PNG"
    out.save()
    print("PREVIEW", out.filepath_raw)


shot("droite", 0.3)  # chauffe
if not clips:
    tiles = [shot(v, 0.22 if v != "corps" else 1.2) for v in ("droite", "gauche", "dessus", "face", "corps")]
    save("pistol_hold", np.concatenate(tiles, axis=1))
else:
    for name in clips:
        act = bpy.data.actions[name]
        arm.animation_data.action = act
        f0, f1 = act.frame_range
        rows = []
        for view in ("corps", "droite"):
            tiles = []
            for i in range(args.frames):
                scene.frame_set(int(round(f0 + (f1 - f0) * i / max(1, args.frames - 1))))
                bpy.context.view_layer.update()
                center = arm.matrix_world @ grip.head
                tiles.append(shot(view, 1.2 if view == "corps" else 0.3))
            rows.append(np.concatenate(tiles, axis=1))
        save(f"pistol_{name}", np.concatenate(rows[::-1], axis=0))
if os.path.exists(tmp):
    os.remove(tmp)
