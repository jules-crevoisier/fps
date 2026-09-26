"""Bras FPS de la grenouille : maillage réduit aux bras, même rig, clips FP_*.

    blender -b art/characters/frog_cowboy/<fichier>.blend -P art/characters/frog_cowboy/export_frog_fp.py [-- --preview <dossier>]

Lance d'abord export_frog.py (il produit la texture débordée frog_cowboy_albedo.png réutilisée ici).
Le .blend n'est jamais réenregistré.
"""
import math
import os
import sys
from pathlib import Path

import bmesh
import bpy
import numpy as np
from mathutils import Vector

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.path.insert(0, str(HERE / "anim"))
from fp import FP_EYE, add_fp_camera, build_fp  # noqa: E402
from rifle import add_weapon_grip  # noqa: E402
from rigkit import Rig  # noqa: E402

ALBEDO = HERE / "frog_cowboy_albedo.png"
GLB = ROOT / "assets/models/characters/frog_cowboy_fp.glb"
ARM_GROUPS = ("Arm", "ForeArm", "Hand")  # + doigts (…Hand<Doigt>N)

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
preview_dir = argv[argv.index("--preview") + 1] if "--preview" in argv else ""

skinned = [o for o in bpy.data.objects if o.type == "MESH" and o.parent and o.parent.type == "ARMATURE"]
mesh = max(skinned, key=lambda o: len(o.data.polygons))
arm = mesh.parent
for ob in (mesh, arm):
    ob.hide_viewport = False
    ob.hide_set(False)
bpy.context.view_layer.objects.active = mesh
if mesh.mode != "OBJECT":
    bpy.ops.object.mode_set(mode="OBJECT")

# -- Maillage : on garde les sommets pesant surtout sur les bras/mains. --------------
arm_idx = {vg.index for vg in mesh.vertex_groups
           if vg.name.startswith("mixamorig:") and any(k in vg.name for k in ("LeftArm", "RightArm", "LeftForeArm",
                                                                             "RightForeArm", "LeftHand", "RightHand"))}
bm = bmesh.new()
bm.from_mesh(mesh.data)
deform = bm.verts.layers.deform.active
drop = [v for v in bm.verts if sum(w for g, w in v[deform].items() if g in arm_idx) < 0.5]
bmesh.ops.delete(bm, geom=drop, context="VERTS")
bm.to_mesh(mesh.data)
bm.free()
mesh.data.update()
print("FP_MESH verts", len(mesh.data.vertices), "polys", len(mesh.data.polygons))

# Texture débordée (produite par export_frog.py).
mat = mesh.active_material
bsdf = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
tex_node = bsdf.inputs["Base Color"].links[0].from_node
if ALBEDO.exists():
    tex_node.image = bpy.data.images.load(str(ALBEDO))

add_weapon_grip(arm)
add_fp_camera(arm)
rig = Rig(arm)
clips = build_fp(rig)
rig.reset()
arm.animation_data.action = None

for ob in bpy.data.objects:
    ob.select_set(ob in (mesh, arm))
bpy.context.view_layer.objects.active = arm
bpy.ops.export_scene.gltf(filepath=str(GLB), export_format="GLB", use_selection=True, export_skins=True,
                          export_apply=False, export_animations=True, export_animation_mode="ACTIONS",
                          export_force_sampling=True)
print("FROG_FP_EXPORT_OK clips", clips, "->", GLB)

# -- Aperçu depuis l'œil (54° vertical, 16:9), arme accrochée à WeaponGrip. ----------
if preview_dir:
    out_dir = os.path.abspath(preview_dir)
    os.makedirs(out_dir, exist_ok=True)
    bpy.ops.import_scene.gltf(filepath=str(ROOT / "assets/models/weapons/ravage.glb"))
    gun = next(o for o in bpy.context.selected_objects if o.type == "MESH")
    for o in bpy.context.selected_objects:
        if o.type == "EMPTY":
            o.hide_render = True
    gun.parent = arm
    gun.parent_type = "BONE"
    gun.parent_bone = "WeaponGrip"
    gun.location = (0.0, -arm.data.bones["WeaponGrip"].length, 0.0)
    gun.rotation_euler = (-math.pi / 2.0, 0.0, 0.0)  # os : Y = haut de l'arme
    gun.scale = (1.0 / 1.8,) * 3
    for o in bpy.data.objects:
        if o.type in ("CAMERA", "LIGHT") or (o.type == "MESH" and o not in (mesh, gun)):
            o.hide_render = True
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "TEXTURE"
    scene.display.shading.show_object_outline = True
    scene.render.resolution_x, scene.render.resolution_y = 480, 270
    cam = bpy.data.objects.new("FPCam", bpy.data.cameras.new("FPCam"))
    scene.collection.objects.link(cam)
    scene.camera = cam
    cam.data.sensor_fit = "VERTICAL"
    cam.data.angle_y = math.radians(54.0)
    cam.data.clip_start = 0.005
    cam.location = FP_EYE
    cam.rotation_euler = Vector((0.0, -1.0, 0.0)).to_track_quat("-Z", "Y").to_euler()  # regard -Y, haut +Z
    tmp = os.path.join(out_dir, "_tmp.png")

    def shot():
        scene.render.filepath = tmp
        bpy.ops.render.render(write_still=True)
        im = bpy.data.images.load(tmp, check_existing=False)
        px = np.array(im.pixels[:], np.float32).reshape(im.size[1], im.size[0], 4)
        bpy.data.images.remove(im)
        return px

    shot()
    for name in clips:
        act = bpy.data.actions[name]
        arm.animation_data.action = act
        f0, f1 = act.frame_range
        k = 1 if f1 - f0 < 2 else 6
        tiles = []
        for i in range(k):
            scene.frame_set(int(round(f0 + (f1 - f0) * i / max(1, k - 1))))
            tiles.append(shot())
        rows = [np.concatenate(tiles[r:r + 3], axis=1) for r in range(0, len(tiles), 3)]
        if len(rows) > 1 and rows[-1].shape != rows[0].shape:
            pad = np.zeros_like(rows[0])
            pad[:, : rows[-1].shape[1]] = rows[-1]
            rows[-1] = pad
        sheet = np.concatenate(rows[::-1], axis=0)
        img = bpy.data.images.new(name, sheet.shape[1], sheet.shape[0], alpha=True)
        img.pixels.foreach_set(sheet.ravel())
        img.filepath_raw = os.path.join(out_dir, f"fp_{name}.png")
        img.file_format = "PNG"
        img.save()
        print("FP_SHEET", img.filepath_raw)
    os.remove(tmp)
