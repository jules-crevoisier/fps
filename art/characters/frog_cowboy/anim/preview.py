"""Planches de contrôle des clips (vue de profil + vue 3/4), sans toucher au .blend.

    blender -b art/characters/frog_cowboy/<fichier>.blend -P art/characters/frog_cowboy/anim/preview.py -- \
        --clips Idle,Walk --frames 8 --out reports/checkpoints/<dossier>
"""
import argparse
import math
import os
import sys

import bpy
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from library import build_library  # noqa: E402

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
ap = argparse.ArgumentParser()
ap.add_argument("--clips", default="")
ap.add_argument("--frames", type=int, default=8)
ap.add_argument("--out", required=True)
ap.add_argument("--gun", default="")
ap.add_argument("--views", default="side,q34")
args = ap.parse_args(argv)
out_dir = os.path.abspath(args.out)
os.makedirs(out_dir, exist_ok=True)

arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
mesh = next(o for o in bpy.data.objects if o.type == "MESH" and o.parent is arm)
for o in bpy.data.objects:
    if o.type == "MESH" and o is not mesh:
        o.hide_render = True
    if o.type in ("CAMERA", "LIGHT"):
        o.hide_render = True
arm.hide_viewport = False
arm.hide_set(False)
bpy.context.view_layer.objects.active = mesh
if mesh.mode != "OBJECT":
    bpy.ops.object.mode_set(mode="OBJECT")
bpy.context.view_layer.objects.active = arm

only = [c for c in args.clips.split(",") if c] or None
names = build_library(arm, only)

if args.gun:
    bpy.ops.import_scene.gltf(filepath=args.gun)
    gun = next(o for o in bpy.context.selected_objects if o.type == "MESH")
    for o in bpy.context.selected_objects:
        if o.type == "EMPTY":
            o.hide_render = True
    grip = arm.pose.bones.get("WeaponGrip")
    if grip:
        gun.parent = arm
        gun.parent_type = "BONE"
        gun.parent_bone = "WeaponGrip"
        gun.location = (0.0, -grip.bone.length, 0.0)
        gun.rotation_euler = (-math.pi / 2.0, 0.0, 0.0)  # os : Y = haut de l'arme
        gun.scale = (1.0 / 1.8,) * 3

scene = bpy.context.scene
scene.render.engine = "BLENDER_WORKBENCH"
scene.display.shading.light = "STUDIO"
scene.display.shading.color_type = "TEXTURE"
scene.display.shading.show_object_outline = True
scene.render.resolution_x = 260
scene.render.resolution_y = 340
scene.render.film_transparent = False
scene.render.image_settings.file_format = "PNG"
cam = bpy.data.objects.new("PrevCam", bpy.data.cameras.new("PrevCam"))
scene.collection.objects.link(cam)
scene.camera = cam
cam.data.type = "ORTHO"
cam.data.ortho_scale = 1.25
views = {
    "side": ((math.radians(90), 0.0, math.radians(90)), (0.0, 0.0, 0.52), 1.25),
    "q34": ((math.radians(90), 0.0, math.radians(-35)), (0.0, 0.0, 0.52), 1.25),
    "close": ((math.radians(75), 0.0, math.radians(-50)), (-0.05, -0.12, 0.68), 0.55),
    "top": ((math.radians(20), 0.0, math.radians(-20)), (-0.05, -0.12, 0.68), 0.6),
}
tmp = os.path.join(out_dir, "_tmp.png")


def render_view(view):
    rot, center, scale = views[view]
    cam.rotation_euler = rot
    cam.data.ortho_scale = scale
    bpy.context.view_layer.update()
    d = cam.matrix_world.to_3x3() @ __import__("mathutils").Vector((0, 0, 1))
    cam.location = __import__("mathutils").Vector(center) + d * 3.0
    scene.render.filepath = tmp
    bpy.ops.render.render(write_still=True)
    img = bpy.data.images.load(tmp, check_existing=False)
    px = np.array(img.pixels[:], dtype=np.float32).reshape(img.size[1], img.size[0], 4)
    bpy.data.images.remove(img)
    return px


render_view("side")  # 1er rendu Workbench parfois vide : chauffe
for name in names:
    act = bpy.data.actions[name]
    arm.animation_data.action = act
    f0, f1 = act.frame_range
    rows = []
    for view in args.views.split(","):
        tiles = []
        for i in range(args.frames):
            f = f0 + (f1 - f0) * i / max(1, args.frames - (0 if f1 - f0 < 2 else 1))
            scene.frame_set(int(round(f)))
            tiles.append(render_view(view))
        rows.append(np.concatenate(tiles, axis=1))
    sheet = np.concatenate(rows[::-1], axis=0)
    h, w = sheet.shape[:2]
    out = bpy.data.images.new(name + "_sheet", w, h, alpha=True)
    out.pixels.foreach_set(sheet.ravel())
    out.filepath_raw = os.path.join(out_dir, f"anim_{name}.png")
    out.file_format = "PNG"
    out.save()
    print("SHEET", out.filepath_raw)
if os.path.exists(tmp):
    os.remove(tmp)
