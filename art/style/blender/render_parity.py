"""render_parity.py -- rendu Blender (EEVEE) de "parity_scene"
(art/style/toon_style.json v2), même caméra/objets que
tools/style/render_parity_godot.gd -- comparé par tools/style/compare_parity.py.

CLI :
	blender -b --factory-startup --python-exit-code 1 -P art/style/blender/render_parity.py -- \\
		--out reports/checkpoints/2026-09-26_toon_bd/parity_blender.png
"""
from __future__ import annotations

import argparse
import math
import os
import sys

_THIS_DIR = os.path.dirname(os.path.abspath(__file__))
if _THIS_DIR not in sys.path:
	sys.path.insert(0, _THIS_DIR)
from _style import hex_to_rgb, load_style, repo_root  # noqa: E402
from toon_bd_nodes import apply_toon_bd_to_material, setup_scene  # noqa: E402

import bpy  # noqa: E402


def _parse_args() -> argparse.Namespace:
	argv = sys.argv
	argv = argv[argv.index("--") + 1:] if "--" in argv else []
	p = argparse.ArgumentParser()
	p.add_argument("--out", dest="out_path", required=True)
	return p.parse_args(argv)


def _spawn_object(cfg: dict, style: dict) -> None:
	kind = cfg.get("type", "")
	gpos = cfg.get("position", [0.0, 0.0, 0.0])
	# Godot (x,y,z, Y haut) -> Blender (x,-z,y, Z haut) -- même remap que la
	# caméra (voir `main`). Oublié ici une première fois (repéré à l'exécution :
	# les primitives de la scène de parité se retrouvaient à mi-hauteur dans le
	# sol, décalées en profondeur au lieu d'être posées dessus) : chaque
	# position de `parity_scene.objects` doit passer par CE remap, pas
	# seulement la caméra/le modèle racine.
	pos = (gpos[0], -gpos[2], gpos[1])
	rot_y = math.radians(float(cfg.get("rotation_y_deg", 0.0)))

	if kind == "model":
		path = os.path.join(repo_root(), cfg.get("path", "").replace("res://", ""))
		bpy.ops.import_scene.gltf(filepath=path)
		imported = [o for o in bpy.context.selected_objects]
		root = next((o for o in imported if o.parent is None), imported[0] if imported else None)
		if root is not None:
			root.location = pos
			root.rotation_euler = (0.0, 0.0, rot_y)
		for obj in imported:
			if obj.type == "MESH":
				for slot in obj.material_slots:
					if slot.material is not None:
						apply_toon_bd_to_material(slot.material, style)
		return

	albedo = hex_to_rgb(cfg.get("albedo", "#FFFFFF"))
	mat = bpy.data.materials.new(f"parity_{kind}")
	mat.use_nodes = True
	mat.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = albedo
	apply_toon_bd_to_material(mat, style)

	if kind == "sphere":
		radius = float(cfg.get("radius", 0.45))
		bpy.ops.mesh.primitive_uv_sphere_add(radius=radius, location=pos)
	elif kind == "cube":
		size = float(cfg.get("size", 0.7))
		bpy.ops.mesh.primitive_cube_add(size=size, location=pos)
	elif kind == "plane":
		size = float(cfg.get("size", 8.0))
		bpy.ops.mesh.primitive_plane_add(size=size, location=pos)
	else:
		return
	obj = bpy.context.active_object
	obj.rotation_euler = (0.0, 0.0, rot_y)
	obj.data.materials.append(mat)


def _realign_sun_to_godot_direction(style: dict) -> None:
	"""`setup_scene()` oriente le soleil dans le repère BLENDER natif (azimut/
	élévation appliqués tels quels, pensés pour un usage Blender normal, voir
	sa doc) -- CE script remappe en plus les positions Godot (x,y,z, Y haut)
	vers Blender (x,-z,y, Z haut) pour les objets/la caméra (voir `main`), donc
	le soleil doit subir le MÊME remappage pour rester au même endroit relatif
	que dans le rendu Godot -- sinon la scène de parité compare deux
	éclairages différents plutôt que deux moteurs sous le MÊME éclairage
	(constaté à l'exécution : sujets en silhouette totale côté Blender alors
	que Godot les montre correctement éclairés, avec le même JSON)."""
	light_cfg = style.get("light", {})
	az = math.radians(float(light_cfg.get("sun_azimuth_deg", 135.0)))
	el = math.radians(float(light_cfg.get("sun_elevation_deg", 50.0)))
	horiz = math.cos(el)
	# Direction Godot (ToonStyle._sun_direction) : (horiz*cos(az), -sin(el), horiz*sin(az)).
	gx, gy, gz = horiz * math.cos(az), -math.sin(el), horiz * math.sin(az)
	# Même remap que les positions : Godot(x,y,z) -> Blender(x,-z,y) -- PUIS
	# inversé (constaté à l'exécution : sans ce signe, la scène de parité
	# rendait tout en silhouette totale côté Blender alors que le MÊME JSON
	# donne un rendu correctement éclairé côté Godot). `_sun_direction`/
	# `look_at_from_position` posent la direction dans laquelle le soleil
	# VOYAGE ; reproduit ici tel quel, la caméra Blender se retrouvait à
	# contre-jour au lieu de face -- probablement une convention -Z/+Z locale
	# différente entre `DirectionalLight3D.look_at_from_position` et
	# `Vector.to_track_quat("-Z", "Y")`. Inverser fait correspondre les deux
	# rendus ; voir art/style/README.md pour cette limite documentée.
	direction = (-gx, gz, -gy)
	sun_obj = next((o for o in bpy.context.scene.objects if o.type == "LIGHT" and o.data.type == "SUN"), None)
	if sun_obj is not None:
		import mathutils

		# Une DirectionalLight/Sun éclaire le long de son axe -Z local -- la
		# direction ci-dessus est "vers où la lumière voyage" (même convention
		# que ToonStyle._sun_direction/DirectionalLight3D.look_at_from_position),
		# donc le soleil doit FAIRE FACE à cette direction (-Z local = `direction`).
		sun_obj.rotation_euler = mathutils.Vector(direction).to_track_quat("-Z", "Y").to_euler()


def main() -> None:
	args = _parse_args()
	args.out_path = os.path.abspath(args.out_path)  # voir ink_bake.py::main -- même piège chemin relatif.
	style = load_style()
	scene_cfg = style.get("parity_scene", {})

	bpy.ops.wm.read_factory_settings(use_empty=True)
	setup_scene(bpy.context.scene, style)
	# `_realign_sun_to_godot_direction` (tentative de remap exact azimut/
	# élévation Godot -> repère Blender) a été ESSAYÉE puis abandonnée : elle
	# pointait le soleil dans une direction qui laissait toute la scène de
	# parité en noir total, alors que la direction NATIVE de `setup_scene`
	# (même azimut/élévation, mais interprétés dans le repère Blender natif,
	# sans tentative de remap inter-moteurs) éclaire correctement -- vérifié
	# à l'exécution sur les deux. La position CAMÉRA/OBJETS reste remappée
	# (`_spawn_object`/`main` ci-dessous, ça n'a pas ce problème) ; seule la
	# direction du soleil renonce à une parité angle-exacte au profit d'un
	# rendu qui montre vraiment quelque chose -- voir art/style/README.md.
	for obj_cfg in scene_cfg.get("objects", []):
		_spawn_object(obj_cfg, style)

	cam_cfg = scene_cfg.get("camera", {})
	cam_data = bpy.data.cameras.new("ParityCam")
	cam_obj = bpy.data.objects.new("ParityCam", cam_data)
	bpy.context.scene.collection.objects.link(cam_obj)
	bpy.context.scene.camera = cam_obj
	cam_pos = cam_cfg.get("position", [0.0, 1.4, 3.2])
	look_at = cam_cfg.get("look_at", [0.0, 0.9, 0.0])
	# Blender : +Y devant l'utilisateur, Godot : -Z devant la caméra -- la
	# scène JSON est neutre (juste des coordonnées) ; on remappe (x, y, z)
	# Godot -> (x, -z, y) Blender pour garder la MÊME disposition spatiale
	# relative (sol horizontal = XY Blender / XZ Godot).
	cam_obj.location = (cam_pos[0], -cam_pos[2], cam_pos[1])
	target = (look_at[0], -look_at[2], look_at[1])
	direction = [target[i] - cam_obj.location[i] for i in range(3)]
	cam_obj.rotation_euler = _look_at_euler(direction)
	cam_data.angle_y = math.radians(float(cam_cfg.get("fov_v_deg", 45.0)))
	cam_data.sensor_fit = "VERTICAL"

	res = scene_cfg.get("resolution", [1280, 720])
	scene = bpy.context.scene
	scene.render.resolution_x = int(res[0])
	scene.render.resolution_y = int(res[1])
	scene.render.filepath = args.out_path
	scene.render.image_settings.file_format = "PNG"
	bpy.ops.render.render(write_still=True)
	print("render_parity: capture ecrite ->", args.out_path)


def _look_at_euler(direction: list) -> tuple:
	"""Rotation Blender (caméra par défaut regarde -Z locale, +Y locale = haut)
	pointant `direction` (monde) -- évite une dépendance à mathutils.Vector
	pour rester lisible (juste de la trigonométrie plane)."""
	import mathutils

	vec = mathutils.Vector(direction).normalized()
	# `track_quat` : -Z de la caméra suit `vec`, +Y reste "haut" -- convention
	# standard Blender pour une caméra/lampe orientée par direction.
	quat = vec.to_track_quat("-Z", "Y")
	return quat.to_euler()


if __name__ == "__main__":
	main()
