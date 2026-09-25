## tools/blender/fp_camera.py -- FP-10 (voir docs/research/12_viewmodel_v2.md §3.2)
## Camera Blender = camera du jeu : sondee et verifiee par calcul (voir rapport
## de tache) -- avec `sensor_fit='VERTICAL'` et `lens_unit='FOV'`, la propriete
## `angle` fixe DIRECTEMENT le FOV VERTICAL (`angle_y` la relit a l'identique,
## confirme sur bpy 5.2.0). `angle_x` (propriete calculee) suit en revanche le
## ratio sensor_width/sensor_height du bloc camera -- PAS la resolution de
## rendu -- donc RIEN d'utile pour la projection monde->ecran reelle (mesure :
## sensor 36x24mm/54 deg vertical donnait angle_x=74.78 deg au lieu de 84.4 deg
## attendus pour un cadre 16:9). Cause : Blender ne recalcule `angle_x` qu'a
## partir des dimensions du capteur, jamais de `scene.render.resolution_*`.
## Deux consequences :
##   - `setup_camera` pose quand meme `sensor_width`/`sensor_height` a un
##     ratio 16:9 (36 x 20.25mm) : purement cosmetique/lisible dans l'UI
##     Blender, sans incidence sur le rendu (VERTICAL ignore sensor_width) ;
##   - la projection monde->ecran ci-dessous (section pure) recalcule TOUJOURS
##     elle-meme la demi-largeur a partir de `aspect` (le VRAI ratio de rendu,
##     16/9 par defaut), jamais de `angle_x`/`sensor_width`.
##
## Axes (doc 12 §3.2) : Blender X=droite, Y=AVANT (camera a l'origine, regarde
## +Y), Z=haut. Cote Godot (apres export glTF Y-up standard, verifie sur la
## pose de repos par make_characters.py -- meme convention reprise ici SANS
## la re-sonder) : Godot.x = Blender.x, Godot.y = Blender.z, Godot.z =
## -Blender.y -- la camera Godot regarde -Z, ce qui correspond bien a
## Blender +Y. C'est DANS L'ESPACE GODOT (X droite, Y haut, Z arriere-camera)
## que sont exprimees les cibles de prise du contrat FP-10 (ex. grip a
## (0.20, -0.20, -0.42)) : `project_point`/`is_outside_frame` travaillent
## directement dans cet espace -- aucune conversion a faire pour les tester
## avec un point deja "espace camera Godot". `blender_to_godot`/
## `godot_to_blender` ne servent qu'a faire le pont avec des positions
## mesurees en espace ARMATURE Blender (ex. os du rig avant export).
##
## Usage CLI (planche de controle "tenue" -- utilisee par FP-10 et rejouee
## telle quelle par FP-13..18, un GLB de bras/arme par appel) :
##   blender -b -P tools/blender/fp_camera.py -- --in assets/models/fp/fp_arms.glb
##       [--in-b assets/models/fp/fp_arms_floating.glb] [--out DIR] [--size 640]
## Rend chaque GLB tenant un cylindre de reference (r=1.8cm, meme gabarit que
## le test pytest d'auto-prise) sous la camera FP 54 deg/16:9, pose par
## `fp_rig.pose_hold_cylinder` (bras + doigts, memes solveurs que le contrat
## pytest -- CE QU'ON VOIT EST CE QU'ON EXPORTE, doc 12 §3.1), colonnes
## cote a cote sur une seule image PNG.
from __future__ import annotations

import argparse
import math
import os
import sys

try:
	import bpy
except ImportError:  # pragma: no cover - permet de tester la logique pure hors Blender
	bpy = None

HERE = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.dirname(os.path.dirname(HERE))

# ---------------------------------------------------------------------------
# Contrat cameras (doc 12 §3.2) -- aucune dependance bpy.
# ---------------------------------------------------------------------------
FOV_Y_DEG = 54.0
ASPECT = 16.0 / 9.0            # largeur / hauteur
RENDER_W = 1920
RENDER_H = 1080


def frame_half_extents(minus_z: float, fov_y_deg: float = FOV_Y_DEG, aspect: float = ASPECT) -> tuple:
	"""Demi-hauteur/demi-largeur (metres) du cadre camera au plan Z = -`minus_z`
	(donc `minus_z` > 0, un point DEVANT la camera), pour une camera a
	l'origine qui regarde -Z (convention Godot ; voir en-tete pour le lien
	avec la camera Blender +Y). `minus_z` <= 0 -- point derriere ou sur la
	camera -- renvoie (0.0, 0.0) : jamais de tangente negative."""
	if minus_z <= 0.0:
		return 0.0, 0.0
	half_h = minus_z * math.tan(math.radians(fov_y_deg / 2.0))
	return half_h * aspect, half_h


def project_point(p, fov_y_deg: float = FOV_Y_DEG, aspect: float = ASPECT):
	"""Projection monde (espace camera Godot, camera a l'origine regardant
	-Z, +Y haut) -> ecran, fraction [0,1] x [0,1] (u=0 gauche/1 droite,
	v=0 bas/1 haut -- convention mathematique Y-vers-le-haut, PAS celle des
	pixels image). `None` si `p` est derriere ou sur le plan de la camera
	(z >= 0) : indefini, jamais une fausse coordonnee."""
	x, y, z = p
	if z >= 0.0:
		return None
	half_w, half_h = frame_half_extents(-z, fov_y_deg, aspect)
	if half_w <= 0.0 or half_h <= 0.0:
		return None
	return (0.5 + 0.5 * (x / half_w), 0.5 + 0.5 * (y / half_h))


def is_outside_frame(p, fov_y_deg: float = FOV_Y_DEG, aspect: float = ASPECT) -> bool:
	"""True si `p` (espace camera Godot) tombe hors du cadre 16:9 a `fov_y_deg`
	vertical -- derriere la camera, ou en dehors de la demi-largeur/demi-
	hauteur du cadre a sa profondeur. Utilise par fp_rig.py pour verifier que
	les coudes du solveur d'epaules restent hors champ (doc 12 §3.2)."""
	x, y, z = p
	if z >= 0.0:
		return True
	half_w, half_h = frame_half_extents(-z, fov_y_deg, aspect)
	return abs(x) > half_w or abs(y) > half_h


def blender_to_godot(p) -> tuple:
	"""Espace armature Blender (X droite, Y avant, Z haut) -> espace camera
	Godot (X droite, Y haut, Z arriere-camera) -- meme conversion que
	l'exporteur glTF Y-up (voir en-tete ; deja documentee/verifiee par
	make_characters.py, non re-sondee ici)."""
	x, y, z = p
	return (x, z, -y)


def godot_to_blender(p) -> tuple:
	"""Inverse de `blender_to_godot`."""
	x, y, z = p
	return (x, -z, y)


# ---------------------------------------------------------------------------
# Section bpy -- jamais appelee hors de Blender.
# ---------------------------------------------------------------------------
if bpy is not None:
	from mathutils import Vector  # noqa: E402 -- render_grip_closeup (cadrage du gros plan).
	sys.path.insert(0, HERE)
	import fp_rig  # noqa: E402 -- pose_hold_cylinder/solveurs (voir ce fichier)

	def setup_camera(scene, fov_y_deg: float = FOV_Y_DEG, aspect: float = ASPECT,
			render_w: int = RENDER_W) -> "bpy.types.Object":
		"""Camera FP du jeu : a l'origine, regarde +Y (rotation +90 deg autour de
		X ramene l'axe local -Z, avant par defaut d'une camera Blender, sur
		+Y monde -- verifie par calcul, voir en-tete). `sensor_fit='VERTICAL'`
		+ `angle` = `fov_y_deg` = FOV vertical exact (sonde, voir en-tete).
		Resolution de rendu posee au meme ratio (`render_w`/`aspect`, arrondi
		pair) pour que le rendu corresponde a la projection pure ci-dessus."""
		cam_data = bpy.data.cameras.new("FPCam")
		cam_data.lens_unit = 'FOV'
		cam_data.sensor_fit = 'VERTICAL'
		cam_data.angle = math.radians(fov_y_deg)
		cam_data.sensor_width = 36.0
		cam_data.sensor_height = 36.0 / aspect  # cosmetique seulement (voir en-tete) : ratio 16:9 lisible dans l'UI.
		cam_data.clip_start = 0.01
		cam_data.clip_end = 100.0
		cam = bpy.data.objects.new("FPCam", cam_data)
		cam.location = (0.0, 0.0, 0.0)
		cam.rotation_euler = (math.radians(90.0), 0.0, 0.0)
		scene.collection.objects.link(cam)
		scene.camera = cam
		render_h = int(round(render_w / aspect / 2.0)) * 2
		scene.render.resolution_x = render_w
		scene.render.resolution_y = render_h
		scene.render.pixel_aspect_x = 1.0
		scene.render.pixel_aspect_y = 1.0
		return cam

	def _reference_cylinder(radius: float, length: float, name: str = "GripCylinder"):
		"""Cylindre de reference (r=1.8cm par defaut cote appelant -- meme
		gabarit que le contrat pytest d'auto-prise), axe le long de Y-monde
		(profondeur camera), centre a `length/2` devant l'origine de l'objet
		(pour que `obj.location` place son BOUT proche, cote poignee)."""
		import bmesh
		bm = bmesh.new()
		segs = bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=24,
			radius1=radius, radius2=radius, depth=length)
		import mathutils
		bmesh.ops.rotate(bm, cent=(0, 0, 0), matrix=mathutils.Matrix.Rotation(math.radians(90.0), 3, 'X'),
			verts=segs["verts"])
		me = bpy.data.meshes.new(name)
		bm.to_mesh(me)
		bm.free()
		obj = bpy.data.objects.new(name, me)
		bpy.context.scene.collection.objects.link(obj)
		mat = bpy.data.materials.new(f"{name}_mat")
		mat.use_nodes = True
		bsdf = mat.node_tree.nodes.get("Principled BSDF")
		if bsdf:
			bsdf.inputs["Base Color"].default_value = (0.35, 0.33, 0.30, 1.0)
		me.materials.append(mat)
		return obj

	def _apply_wysiwyg_view_transform(scene) -> None:
		"""Transfert de vue Standard (meme correctif que turntable.py --
		`_apply_wysiwyg_view_transform`, duplique ici en petit plutot
		qu'importe pour ne pas dependre de `toonkit`/turntable.py, hors
		perimetre de cette tache). Sondage bpy 5.2 : une scene fraiche demarre
		en couleur AgX, qui recompresse/assombrit fortement la palette --
		SANS ce reglage, une couleur cuir #6B4A2E (deja sombre en sRGB, L
		OKLab ~0.32) tombe sous le seuil "jamais noire" du critere
		d'acceptation (revue lead 2026-09-25 : "aucune texture visible ...
		noire") meme rendue en Emission plein tube (verifie par mesure sur un
		rendu reel -- voir rapport de tache)."""
		scene.view_settings.view_transform = 'Standard'
		scene.view_settings.exposure = 0.0
		scene.view_settings.gamma = 1.0

	def _find_base_color_input(mat: "bpy.types.Material"):
		"""Renvoie `(image_ou_None, rgba_de_repli)` pour le slot Base Color de
		`mat` -- nos materiaux exportes (`_flat_image_material`/materiau cuit
		par `paint_bake.py`) portent TOUJOURS soit une image liee directement
		sur "Base Color" (jamais le montage vertex-color x albedo de
		turntable.py::_read_albedo, propre a `bake_vertex_ao` -- absent ici),
		soit (repli, si jamais aucune image) une couleur plate."""
		if not mat.use_nodes or mat.node_tree is None:
			return None, (0.7, 0.7, 0.7, 1.0)
		bsdf = mat.node_tree.nodes.get("Principled BSDF")
		if bsdf is None or "Base Color" not in bsdf.inputs:
			return None, (0.7, 0.7, 0.7, 1.0)
		socket = bsdf.inputs["Base Color"]
		if not socket.is_linked:
			c = socket.default_value
			return None, (c[0], c[1], c[2], c[3])
		src = socket.links[0].from_node
		if src.type == 'TEX_IMAGE' and src.image is not None:
			return src.image, (1.0, 1.0, 1.0, 1.0)
		return None, (0.7, 0.7, 0.7, 1.0)

	def _emissive_preview_material(name: str, mat: "bpy.types.Material"):
		"""Materiau d'apercu AUTO-ECLAIRE (Emission) qui reprend la VRAIE
		image/couleur Base Color de `mat` (voir `_find_base_color_input`) --
		garantit une capture visible sans dependre de l'eclairage de scene
		(meme principe que turntable.py::_build_toon_preview), tout en
		montrant la VRAIE texture peinte (critere d'acceptation FP-10 :
		"la texture peinte est VISIBLE (gants cuir #6B4A2E, manches #BFAE86)"
		-- jamais un aplat synthetique de substitution, comme le faisait
		l'ancienne `_flat_preview_material` ici)."""
		image, flat_rgba = _find_base_color_input(mat)
		prev = bpy.data.materials.new(name)
		prev.use_nodes = True
		nt = prev.node_tree
		for n in list(nt.nodes):
			nt.nodes.remove(n)
		out = nt.nodes.new("ShaderNodeOutputMaterial")
		emission = nt.nodes.new("ShaderNodeEmission")
		if image is not None:
			tex = nt.nodes.new("ShaderNodeTexImage")
			tex.image = image
			nt.links.new(tex.outputs["Color"], emission.inputs["Color"])
		else:
			emission.inputs["Color"].default_value = flat_rgba
		nt.links.new(emission.outputs["Emission"], out.inputs["Surface"])
		return prev

	def _apply_real_texture_preview(obj) -> None:
		"""Remplace CHAQUE slot materiau de `obj` par sa version Emission
		(`_emissive_preview_material`) -- garde le NOMBRE de slots (donc le
		`material_index` par face, et la distinction visuelle fp_sleeve/
		fp_glove en mode --skip-paint) et la VRAIE image/couleur de chacun,
		contrairement a l'ancien remplacement en bloc par un materiau plat
		unique."""
		for i, mat in enumerate(list(obj.data.materials)):
			if mat is None:
				continue
			obj.data.materials[i] = _emissive_preview_material(f"{mat.name}_preview", mat)

	def _look_at(cam_obj, target) -> None:
		"""Oriente `cam_obj` (camera Blender, -Z locale = avant) vers `target`
		(espace armature Blender) -- meme technique que turntable.py::_look_at,
		dupliquee ici en petit (pas d'import de turntable.py, hors perimetre)."""
		direction = target - cam_obj.location
		cam_obj.rotation_euler = direction.to_track_quat('-Z', 'Y').to_euler()

	def _prep_hold_scene(glb_path: str, cylinder_radius: float):
		"""Commun a `render_hold_checkpoint`/`render_grip_closeup` : importe,
		pose (memes solveurs que le contrat pytest), pose le cylindre de
		reference, applique les materiaux d'apercu reels et le transfert de
		vue WYSIWYG. Renvoie `(rig, arms_obj, scene)`."""
		fp_rig.reset_scene()
		rig, arms_obj = fp_rig.import_fp_arms(glb_path)
		fp_rig.pose_hold_cylinder(rig, cylinder_radius=cylinder_radius)

		cyl = _reference_cylinder(cylinder_radius, 0.24)
		# Le cylindre est en espace camera Godot dans le solveur (voir
		# `pose_hold_cylinder`) ; converti ici en espace armature Blender pour
		# le poser dans la MEME scene que le rig (voir `godot_to_blender`).
		cyl_center_godot = (0.0, -0.18, -0.55)
		cyl.location = godot_to_blender(cyl_center_godot)
		cyl.rotation_euler = (0.0, 0.0, 0.0)

		_apply_real_texture_preview(arms_obj)

		scene = bpy.context.scene
		scene.render.engine = 'BLENDER_EEVEE_NEXT' if 'BLENDER_EEVEE_NEXT' in (
			e.identifier for e in bpy.types.RenderSettings.bl_rna.properties['engine'].enum_items) else 'BLENDER_EEVEE'
		scene.render.film_transparent = True
		world = bpy.data.worlds.new("FPCheckWorld")
		world.use_nodes = True
		bg = world.node_tree.nodes.get("Background")
		if bg:
			bg.inputs[0].default_value = (0.10, 0.10, 0.11, 1.0)
		scene.world = world
		_apply_wysiwyg_view_transform(scene)
		return rig, arms_obj, scene

	def render_hold_checkpoint(glb_path: str, out_png: str, size: int = 640,
			cylinder_radius: float = 0.018) -> str:
		"""Importe `glb_path` (un fp_arms*.glb), pose les deux mains sur le
		cylindre de reference via `fp_rig.pose_hold_cylinder` (memes solveurs
		que le contrat pytest), rend sous la camera FP (`setup_camera`) et
		ecrit `out_png`. Renvoie `out_png`."""
		rig, arms_obj, scene = _prep_hold_scene(glb_path, cylinder_radius)
		setup_camera(scene, render_w=size * 2)

		os.makedirs(os.path.dirname(os.path.abspath(out_png)), exist_ok=True)
		scene.render.filepath = out_png
		scene.render.image_settings.file_format = 'PNG'
		bpy.ops.render.render(write_still=True)
		print(f"FP_CAMERA_RENDER_OK {out_png}")
		return out_png

	def render_grip_closeup(glb_path: str, out_png: str, size: int = 640,
			cylinder_radius: float = 0.018) -> str:
		"""Gros plan sur la main de tir (R) serrant le cylindre de reference --
		critere d'acceptation (revue lead 2026-09-25, critere 3) : "plus un
		gros plan de la main sur la poignee". Camera generique (pas la camera
		FP 54deg/16:9 du contrat -- ce gros plan est un controle visuel de la
		prise elle-meme, pas une projection WYSIWYG du jeu), cadree sur la
		cible de prise (`fp_rig.GRIP_TARGET_CAM`)."""
		rig, arms_obj, scene = _prep_hold_scene(glb_path, cylinder_radius)

		grip_b = Vector(godot_to_blender(fp_rig.GRIP_TARGET_CAM))
		cam_data = bpy.data.cameras.new("CloseupCam")
		cam_data.lens_unit = 'FOV'
		cam_data.angle = math.radians(38.0)
		cam_data.clip_start = 0.01
		cam_data.clip_end = 100.0
		cam = bpy.data.objects.new("CloseupCam", cam_data)
		# Decalage PERPENDICULAIRE a l'avant-bras (surtout X/Z, peu de Y) --
		# un decalage significatif en Y (profondeur camera FP) vise quasiment
		# DANS le tube de la manche (sondage, voir rapport de tache : premier
		# essai filmait l'interieur de la manche, plan illisible). Distance
		# generuse (~40 cm) pour ne jamais raser la surface du gant (second
		# essai, trop proche, ne montrait qu'un seul plan flou sans le
		# cylindre).
		cam.location = grip_b + Vector((0.34, -0.14, 0.18))
		scene.collection.objects.link(cam)
		scene.camera = cam
		_look_at(cam, grip_b)
		# Carre, a la MEME hauteur que les rendus `render_hold_checkpoint`
		# (`setup_camera(render_w=size*2)`, doc 12 -- meme formule que
		# `render_h` ci-dessous) pour que `_composite_side_by_side` aligne les
		# trois panneaux sans bande blanche.
		edge = int(round((size * 2) / ASPECT / 2.0)) * 2
		scene.render.resolution_x = edge
		scene.render.resolution_y = edge
		scene.render.pixel_aspect_x = 1.0
		scene.render.pixel_aspect_y = 1.0

		os.makedirs(os.path.dirname(os.path.abspath(out_png)), exist_ok=True)
		scene.render.filepath = out_png
		scene.render.image_settings.file_format = 'PNG'
		bpy.ops.render.render(write_still=True)
		print(f"FP_CAMERA_CLOSEUP_OK {out_png}")
		return out_png

	def _apply_first_image_texture_preview(obj) -> None:
		"""Variante de `_apply_real_texture_preview` pour des materiaux
		EXTERNES dont la Base Color n'est pas un lien DIRECT (armes v2,
		`ravage_painted` -- sonde reelle, voir rapport de tache : Base Color
		vient d'un noeud Mix [texture x attribut de couleur de sommet], jamais
		une image branchee directement -- `_find_base_color_input` ne la
		trouve donc pas) : cherche la PREMIERE image `ShaderNodeTexImage` du
		graphe de noeuds, ou qu'elle soit branchee."""
		for i, mat in enumerate(list(obj.data.materials)):
			if mat is None or not mat.use_nodes or mat.node_tree is None:
				continue
			image = next((n.image for n in mat.node_tree.nodes if n.type == 'TEX_IMAGE' and n.image is not None), None)
			if image is None:
				continue
			prev = bpy.data.materials.new(f"{mat.name}_preview")
			prev.use_nodes = True
			nt = prev.node_tree
			for n in list(nt.nodes):
				nt.nodes.remove(n)
			out = nt.nodes.new("ShaderNodeOutputMaterial")
			emission = nt.nodes.new("ShaderNodeEmission")
			tex = nt.nodes.new("ShaderNodeTexImage")
			tex.image = image
			nt.links.new(tex.outputs["Color"], emission.inputs["Color"])
			nt.links.new(emission.outputs["Emission"], out.inputs["Surface"])
			obj.data.materials[i] = prev

	def render_weapon_hold_checkpoint(glb_path: str, weapon_glb_path: str, out_png: str, size: int = 640,
			cylinder_radius: float = 0.018) -> str:
		"""FP-10B (critere d'acceptation : "vue FP tenant le Ravage v2 ... pour
		revue utilisateur") -- pose les bras (memes solveurs que le contrat
		pytest, `pose_hold_cylinder`) puis importe `weapon_glb_path` (contrat
		"arme v2", doc 12 §3.3 -- FP-11, DEJA livre : origine = repere `Grip`,
		a l'origine locale de l'arme) et le TRANSLATE (aucune rotation : le
		contrat v2 aligne deja l'axe Sight->Muzzle sur la camera FP, mesure
		`sight_muzzle_lateral_deg` ~0 dans le rapport FP-11) pour que son
		`Grip` coincide avec la cible de prise du contrat FP-10
		(`fp_rig.GRIP_TARGET_CAM`).

		LIMITE ASSUMEE (hors perimetre FP-10B, voir le rendu de tache) : les
		doigts restent poses sur le CYLINDRE DE REFERENCE analytique du
		contrat pytest, pas sur la surface reelle de l'arme -- l'auto-prise
		contre un maillage d'arme reel (BVH) est explicitement FP-13+
		(`make_fp_viewmodel.py`, doc 12 §3.1 : "la chorégraphie du Ravage",
		vague B, menee par le lead en parallele de cette tache). Ce rendu
		verifie donc l'ECHELLE/LA POSITION de l'arme contre la main, pas la
		prise exacte doigt par doigt."""
		rig, arms_obj, scene = _prep_hold_scene(glb_path, cylinder_radius)
		# Le cylindre de reference n'a de sens que pour poser les doigts (deja
		# fait par `_prep_hold_scene`) -- jamais visible ici, l'ARME reelle le
		# remplace a l'ecran.
		ref_cyl = bpy.data.objects.get("GripCylinder")
		if ref_cyl is not None:
			bpy.data.objects.remove(ref_cyl, do_unlink=True)

		before = set(bpy.data.objects.keys())
		bpy.ops.import_scene.gltf(filepath=weapon_glb_path)
		imported = [o for o in bpy.data.objects if o.name not in before]
		grip_empty = next((o for o in imported if o.name == "Grip"), None)
		if grip_empty is None:
			raise RuntimeError(f"fp_camera: aucun repere 'Grip' dans {weapon_glb_path} (contrat arme v2, doc 12 §3.3)")
		weapon_parts = [o for o in imported if o.type == 'MESH']
		if not weapon_parts:
			raise RuntimeError(f"fp_camera: aucune piece MESH dans {weapon_glb_path}")
		grip_target_b = Vector(godot_to_blender(fp_rig.GRIP_TARGET_CAM))
		offset = grip_target_b - grip_empty.matrix_world.translation
		for o in weapon_parts:
			o.location += offset
			_apply_first_image_texture_preview(o)
		stray = [o for o in imported if o not in weapon_parts]
		for o in stray:
			bpy.data.objects.remove(o, do_unlink=True)

		setup_camera(scene, render_w=size * 2)
		os.makedirs(os.path.dirname(os.path.abspath(out_png)), exist_ok=True)
		scene.render.filepath = out_png
		scene.render.image_settings.file_format = 'PNG'
		bpy.ops.render.render(write_still=True)
		print(f"FP_CAMERA_WEAPON_HOLD_OK {out_png}")
		return out_png

	def render_glove_comparison(fp_glb_path: str, tripo_glb_path: str, out_png: str, size: int = 640) -> str:
		"""FP-10B (critere d'acceptation : "comparaison avec les gants Tripo") --
		gros plan cote a cote : a gauche la main FP (`fp_glb_path`, ce fichier),
		a droite les gants Tripo peints existants (`tripo_glb_path`,
		`assets/models/characters/fp_gloves.glb` -- porte les DEUX gants,
		"fp_glove_grip"/"fp_glove_support", lecture seule, jamais modifie)."""
		left_png = os.path.splitext(out_png)[0] + "._fp.png"
		render_grip_closeup(fp_glb_path, left_png, size=size)

		fp_rig.reset_scene()
		bpy.ops.import_scene.gltf(filepath=tripo_glb_path)
		mesh_objs = [o for o in bpy.context.scene.objects if o.type == 'MESH']
		if not mesh_objs:
			raise RuntimeError(f"fp_camera: aucune piece MESH dans {tripo_glb_path}")
		for o in mesh_objs:
			_apply_first_image_texture_preview(o)
		center = sum((o.matrix_world.translation for o in mesh_objs), Vector()) / len(mesh_objs)
		radius = max((o.matrix_world.translation - center).length + max(o.dimensions) for o in mesh_objs)

		scene = bpy.context.scene
		scene.render.engine = 'BLENDER_EEVEE_NEXT' if 'BLENDER_EEVEE_NEXT' in (
			e.identifier for e in bpy.types.RenderSettings.bl_rna.properties['engine'].enum_items) else 'BLENDER_EEVEE'
		scene.render.film_transparent = True
		world = bpy.data.worlds.new("FPCheckWorld")
		world.use_nodes = True
		bg = world.node_tree.nodes.get("Background")
		if bg:
			bg.inputs[0].default_value = (0.10, 0.10, 0.11, 1.0)
		scene.world = world
		_apply_wysiwyg_view_transform(scene)

		cam_data = bpy.data.cameras.new("TripoCompareCam")
		cam_data.lens_unit = 'FOV'
		cam_data.angle = math.radians(38.0)
		cam_data.clip_start = 0.01
		cam_data.clip_end = 100.0
		cam = bpy.data.objects.new("TripoCompareCam", cam_data)
		cam.location = center + Vector((radius * 0.9, -radius * 1.6, radius * 0.6))
		scene.collection.objects.link(cam)
		scene.camera = cam
		_look_at(cam, center)
		edge = int(round((size * 2) / ASPECT / 2.0)) * 2
		scene.render.resolution_x = edge
		scene.render.resolution_y = edge
		scene.render.pixel_aspect_x = 1.0
		scene.render.pixel_aspect_y = 1.0

		right_png = os.path.splitext(out_png)[0] + "._tripo.png"
		os.makedirs(os.path.dirname(os.path.abspath(right_png)), exist_ok=True)
		scene.render.filepath = right_png
		scene.render.image_settings.file_format = 'PNG'
		bpy.ops.render.render(write_still=True)

		_composite_side_by_side([left_png, right_png], out_png)
		for tmp in (left_png, right_png):
			if os.path.isfile(tmp):
				os.remove(tmp)
		print(f"FP_CAMERA_GLOVE_COMPARISON_OK {out_png}")
		return out_png

	def _composite_side_by_side(paths, out_path: str) -> str:
		"""Planche unique (doc 12 -- "colonnes cote a cote sur une seule
		image PNG") : concatene horizontalement les rendus de `paths` (meme
		hauteur -- `render_hold_checkpoint` les rend tous a la meme taille),
		via `bpy.data.images`/numpy (jamais PIL, absent du Python embarque
		de Blender)."""
		import numpy as np
		imgs = [bpy.data.images.load(p) for p in paths]
		w = sum(im.size[0] for im in imgs)
		h = max(im.size[1] for im in imgs)
		canvas = np.ones((h, w, 4), dtype=np.float32)
		x0 = 0
		for im in imgs:
			iw, ih = im.size
			buf = np.empty(iw * ih * 4, dtype=np.float32)
			im.pixels.foreach_get(buf)
			canvas[0:ih, x0:x0 + iw, :] = buf.reshape(ih, iw, 4)
			x0 += iw
		out = bpy.data.images.new("fp_hold_sheet", width=w, height=h, alpha=True)
		out.pixels.foreach_set(canvas.ravel())
		out.filepath_raw = out_path
		out.file_format = 'PNG'
		out.save()
		for im in imgs:
			bpy.data.images.remove(im)
		bpy.data.images.remove(out)
		return out_path

	def parse_args(argv=None):
		p = argparse.ArgumentParser(description="Planche camera FP 54 deg -- tenue sur cylindre de reference.")
		p.add_argument("--in", dest="in_path", required=True, help="fp_arms*.glb (mode 1, ex. forearm)")
		p.add_argument("--in-b", dest="in_path_b", default=None, help="second fp_arms*.glb (mode 2, ex. floating)")
		p.add_argument("--out", dest="out_dir", default=None, help="dossier de sortie (defaut : a cote de --in)")
		p.add_argument("--size", type=int, default=640)
		p.add_argument("--weapon", dest="weapon_glb", default=None,
			help="FP-10B : arme v2 (ex. assets/models/weapons/v2/ravage.glb) -- rendu 'tenue' supplementaire")
		p.add_argument("--tripo-gloves", dest="tripo_gloves_glb", default=None,
			help="FP-10B : gants Tripo peints existants a comparer (ex. assets/models/characters/fp_gloves.glb)")
		return p.parse_args(argv)

	def main(argv=None) -> None:
		args = parse_args(argv)
		in_path = os.path.abspath(args.in_path)
		out_dir = os.path.abspath(args.out_dir) if args.out_dir else os.path.dirname(in_path)
		os.makedirs(out_dir, exist_ok=True)

		paths = []
		stem = os.path.splitext(os.path.basename(in_path))[0]
		out_a = os.path.join(out_dir, f"{stem}_hold.png")
		render_hold_checkpoint(in_path, out_a, size=args.size)
		paths.append(out_a)

		if args.in_path_b:
			in_b = os.path.abspath(args.in_path_b)
			stem_b = os.path.splitext(os.path.basename(in_b))[0]
			out_b = os.path.join(out_dir, f"{stem_b}_hold.png")
			render_hold_checkpoint(in_b, out_b, size=args.size)
			paths.append(out_b)

		# Gros plan sur la prise (main droite) -- toujours sur `--in` (le mode
		# "avant-bras" par defaut) : critere d'acceptation (revue lead
		# 2026-09-25, critere 3) : "plus un gros plan de la main sur la
		# poignee".
		out_closeup = os.path.join(out_dir, f"{stem}_closeup.png")
		render_grip_closeup(in_path, out_closeup, size=args.size)
		paths.append(out_closeup)

		if args.weapon_glb:
			weapon_glb = os.path.abspath(args.weapon_glb)
			weapon_stem = os.path.splitext(os.path.basename(weapon_glb))[0]
			out_weapon = os.path.join(out_dir, f"{stem}_hold_{weapon_stem}.png")
			render_weapon_hold_checkpoint(in_path, weapon_glb, out_weapon, size=args.size)
			paths.append(out_weapon)

		if args.tripo_gloves_glb:
			out_compare = os.path.join(out_dir, f"{stem}_vs_tripo_gloves.png")
			render_glove_comparison(in_path, os.path.abspath(args.tripo_gloves_glb), out_compare, size=args.size)
			paths.append(out_compare)

		if len(paths) > 1:
			sheet_path = os.path.join(out_dir, "fp_hold_sheet.png")
			_composite_side_by_side(paths, sheet_path)
			paths.append(sheet_path)

		print("FP_CAMERA_SHEET_OK " + " ".join(paths))

	if __name__ == "__main__":
		argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
		main(argv)
