"""Atelier de poses FPS : une pose clé à la fois, vue depuis l'œil (comme dans le jeu) + gros
plans des mains, pour régler doigts et paumes avant d'animer.

    blender -b art/characters/frog_cowboy/Untitled.blend -P art/characters/frog_cowboy/anim/pose_lab.py -- \
        --out DIR --poses idle,open,...

Les poses sont définies par fp_pistol.lab_pose(rig, nom) : elle pose le rig et renvoie les
réglages des pièces du revolver pour cette pose ({os: (axe, degrés, position)}).
"""
import argparse
import math
import os
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Quaternion, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", "..", ".."))
sys.path.insert(0, HERE)
from fp import FP_EYE, add_fp_camera  # noqa: E402
from fp_pistol import lab_pose, lab_setup  # noqa: E402
from pistol import add_pistol_grip  # noqa: E402
from rigkit import Rig  # noqa: E402

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
ap = argparse.ArgumentParser()
ap.add_argument("--out", required=True)
ap.add_argument("--poses", default="idle")
ap.add_argument("--eye-only", action="store_true", help="planche : vue depuis l'œil seulement, 6 par ligne")
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
add_fp_camera(arm)
rig = Rig(arm)

# corps invisible en vue FPS : comme export_frog_fp.py, on ne garde que les sommets des bras
arm_idx = {vg.index for vg in mesh.vertex_groups
           if vg.name.startswith("mixamorig:") and any(k in vg.name for k in ("LeftArm", "RightArm", "LeftForeArm",
                                                                             "RightForeArm", "LeftHand", "RightHand"))}
bm = bmesh.new()
bm.from_mesh(mesh.data)
deform = bm.verts.layers.deform.active
bmesh.ops.delete(bm, geom=[v for v in bm.verts if sum(w for g, w in v[deform].items() if g in arm_idx) < 0.5],
                 context="VERTS")
bm.to_mesh(mesh.data)
bm.free()

before = set(bpy.data.objects)
bpy.ops.import_scene.gltf(filepath=os.path.join(ROOT, "assets/models/weapons/revolver.glb"))
new = [o for o in bpy.data.objects if o not in before]
rev = next(o for o in new if o.type == "ARMATURE")
for o in new:
    if o.type == "EMPTY" or (o.type == "MESH" and o.parent is None):
        o.hide_render = True
rev.parent = arm
rev.parent_type = "BONE"
rev.parent_bone = "PistolGrip"
rev.location = (0.0, -arm.data.bones["PistolGrip"].length, 0.0)
rev.rotation_mode = "XYZ"
rev.rotation_euler = (-math.pi / 2.0, 0.0, 0.0)
rev.scale = (1.0 / 1.8,) * 3
if rev.animation_data:
    rev.animation_data.action = None
for pb in rev.pose.bones:
    pb.rotation_mode = "QUATERNION"

scene = bpy.context.scene
scene.render.engine = "BLENDER_WORKBENCH"
scene.display.shading.light = "STUDIO"
scene.display.shading.color_type = "TEXTURE"
scene.display.shading.show_object_outline = True
cam = bpy.data.objects.new("LabCam", bpy.data.cameras.new("LabCam"))
scene.collection.objects.link(cam)
scene.camera = cam
cam.data.clip_start = 0.005
tmp = os.path.join(out_dir, "_tmp.png")
AXES = {"X": Vector((1, 0, 0)), "Y": Vector((0, 1, 0)), "Z": Vector((0, 0, 1))}


def render(w, h):
    scene.render.resolution_x, scene.render.resolution_y = w, h
    scene.render.filepath = tmp
    bpy.ops.render.render(write_still=True)
    img = bpy.data.images.load(tmp, check_existing=False)
    px = np.array(img.pixels[:], np.float32).reshape(img.size[1], img.size[0], 4)
    bpy.data.images.remove(img)
    return px


def eye_view():
    cam.data.type = "PERSP"
    cam.data.sensor_fit = "VERTICAL"
    cam.data.angle_y = math.radians(54.0)
    cam.location = FP_EYE
    cam.rotation_euler = Vector((0.0, -1.0, 0.0)).to_track_quat("-Z", "Y").to_euler()
    return render(960, 540)


def close_view(target, d, scale):
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = scale
    d = Vector(d).normalized()
    cam.location = target + d * 1.0
    cam.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
    return render(480, 540)


def save(name, px):
    out = bpy.data.images.new(name, px.shape[1], px.shape[0], alpha=True)
    out.pixels.foreach_set(px.ravel())
    out.filepath_raw = os.path.join(out_dir, name + ".png")
    out.file_format = "PNG"
    out.save()
    print("LAB", out.filepath_raw)


eye_view()  # chauffe
eye_tiles = []
def rebuild_grip():
    """Recrée l'os PistolGrip (il dépend de l'orientation de la main droite) et y raccroche le revolver."""
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="EDIT")
    eb = arm.data.edit_bones.get("PistolGrip")
    if eb:
        arm.data.edit_bones.remove(eb)
    bpy.ops.object.mode_set(mode="OBJECT")
    add_pistol_grip(arm)
    for p in arm.pose.bones:
        p.rotation_mode = "QUATERNION"
    rev.parent = arm
    rev.parent_type = "BONE"
    rev.parent_bone = "PistolGrip"
    rev.location = (0.0, -arm.data.bones["PistolGrip"].length, 0.0)


for name in [p for p in args.poses.split(",") if p]:
    lab_setup(name)
    rebuild_grip()
    rig.reset()
    rev_pose = lab_pose(rig, name) or {}
    for pb in rev.pose.bones:
        spec = rev_pose.get(pb.name, ("X", 0.0, (0.0, 0.0, 0.0)))
        axis, deg, loc = spec[:3]
        pb.rotation_quaternion = Quaternion(AXES[axis], math.radians(deg))
        pb.location = loc
        pb.scale = (spec[3] if len(spec) > 3 else 1.0,) * 3
    bpy.context.view_layer.update()
    grip = arm.matrix_world @ arm.pose.bones["PistolGrip"].head
    if args.eye_only:
        eye_tiles.append(eye_view()[::2, ::2])
        continue
    tiles = [eye_view(),
             close_view(grip, (1.0, -0.6, 0.35), 0.24),     # côté gauche de l'arme
             close_view(grip, (-1.0, -0.4, 0.2), 0.24)]     # côté droit
    save(f"lab_{name}", np.concatenate(tiles, axis=1))
if args.eye_only and eye_tiles:
    while len(eye_tiles) % 6:
        eye_tiles.append(np.zeros_like(eye_tiles[0]))
    rows = [np.concatenate(eye_tiles[k:k + 6], axis=1) for k in range(0, len(eye_tiles), 6)]
    save("lab_sequence", np.concatenate(rows[::-1], axis=0))
if os.path.exists(tmp):
    os.remove(tmp)
