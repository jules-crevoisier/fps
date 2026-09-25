## make_weapons.py
## Génère les 7 modèles d'armes (glTF binaire) façon BD/graphic-novel : formes
## chunky, biseautées, silhouette lisible (récepteur, canon, chargeur,
## crosse/lunette selon le type). Déterministe (aucun random). Slots matériau
## fixes "body"/"grip"/"metal"/"accent" (recolorés au runtime par Cartoon.gd).
## Origine = la poignée (grip), canon le long de -Z, empty "Muzzle" au bout du
## canon. Lancer : blender --background --python tools/blender/make_weapons.py
##
## API bpy 5.2 vérifiée par sondage avant écriture (voir rapport de la tâche) :
## bmesh.ops.{create_cube,create_cone,scale,rotate,translate} (créent/déplacent
## la géométrie dans un bmesh partagé, matériau par face via
## face.material_index), modifier BEVEL appliqué via
## `bpy.ops.object.modifier_apply` sous `temp_override(object=obj)`,
## export_scene.gltf(export_format='GLB', export_apply=True, export_yup=True)
## (Y-up par défaut, identique à Godot).
##
## A3D-03 (migration stylekit) : remise à zéro de scène, bevel, lissage
## "hard-surface" (normales pondérées), normale moyenne par sommet pour la
## coque de contour (`_smooth_normal`, corrige le contour fendu aux arêtes
## vives — docs/research/06_ai_3d_pipeline.md §B3, lu par assets/shaders/
## ink_outline.gdshader en CUSTOM0) et AO/courbure en couleurs de sommet
## viennent de `tools/blender/lib/toonkit.py` (A3D-02). `add_box`/`add_cyl`
## (bmesh partagé + `material_index` posé immédiatement, pas couvert par
## toonkit qui ne fabrique que des objets uniques) restent ICI : c'est la
## copie CANONIQUE, importée telle quelle par make_gloves.py (mêmes gabarits
## d'arme) au lieu d'être dupliquée. L'export reste un appel manuel à
## `export_scene.gltf` (pas `toonkit.export_glb`, qui suppose que TOUS les
## objets passés sont des mesh — ici "Muzzle"/"Foregrip" sont des empties),
## avec les mêmes réglages `export_vertex_color`/`export_attributes` que
## `toonkit.export_glb` pour que l'AO/courbure/normale lissée sortent bien
## dans le .glb.
import bpy
import bmesh
import math
import os
import sys
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "lib"))
import toonkit  # noqa: E402

BODY, GRIP, METAL, ACCENT = 0, 1, 2, 3
SLOT_NAMES = ["body", "grip", "metal", "accent"]

# Couleurs de base (recolorées au runtime par Cartoon.character/prop — ce sont
# juste des teintes plates pour que le .glb soit lisible tel quel, ex. import-check).
SLOT_COLORS = {
	BODY: (0.55, 0.52, 0.47, 1.0),
	GRIP: (0.18, 0.17, 0.16, 1.0),
	METAL: (0.62, 0.63, 0.66, 1.0),
	ACCENT: (0.85, 0.25, 0.18, 1.0),
}

OUT_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))),
	"assets", "models", "weapons")


def add_box(bm: bmesh.types.BMesh, size: tuple, center: tuple, mat_idx: int, rot=None) -> list:
	"""Ajoute une boîte (taille pleine sx,sy,sz) centrée en `center`. `rot` =
	(axe:str, degrés) optionnel, appliqué autour de l'origine locale de la boîte."""
	# On travaille sur les sommets RENVOYÉS par l'opérateur : découper
	# `bm.faces[start:]` ne renvoie rien de fiable (les pièces restaient alors
	# des cubes unité empilés à l'origine).
	verts = list(bmesh.ops.create_cube(bm, size=1.0)["verts"])
	new_faces = list({f for v in verts for f in v.link_faces})
	bmesh.ops.scale(bm, vec=Vector(size), verts=verts)
	if rot:
		axis, deg = rot
		bmesh.ops.rotate(bm, cent=(0, 0, 0), matrix=Matrix.Rotation(math.radians(deg), 3, axis), verts=verts)
	bmesh.ops.translate(bm, vec=Vector(center), verts=verts)
	for f in new_faces:
		f.material_index = mat_idx
	return new_faces


def add_cyl(bm: bmesh.types.BMesh, radius: float, depth: float, center: tuple, mat_idx: int,
		segments: int = 12, rot=None, radius2=None) -> list:
	"""Ajoute un cylindre (axe local Z) centré en `center`. `radius2` permet un
	tronc de cône (ex. canon légèrement fuselé)."""
	verts = list(bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segments,
		radius1=radius, radius2=radius2 if radius2 is not None else radius, depth=depth)["verts"])
	new_faces = list({f for v in verts for f in v.link_faces})
	if rot:
		axis, deg = rot
		bmesh.ops.rotate(bm, cent=(0, 0, 0), matrix=Matrix.Rotation(math.radians(deg), 3, axis), verts=verts)
	bmesh.ops.translate(bm, vec=Vector(center), verts=verts)
	for f in new_faces:
		f.material_index = mat_idx
	return new_faces


# ---------------------------------------------------------------------------
# Gabarits (dimensions en mètres, monde réel — le ViewModel se charge du
# placement/échelle à l'écran). Origine (0,0,0) = poignée. -Z = vers l'avant.
# ---------------------------------------------------------------------------

def parts_pistolet() -> tuple:
	parts = [
		("box", (0.075, 0.150, 0.070), (0, -0.070, 0.015), GRIP, None),
		("box", (0.075, 0.080, 0.205), (0, 0.045, -0.090), BODY, None),
		("cyl", (0.013, 0.095, 10, None), (0, 0.052, -0.235), METAL, None),
		("box", (0.012, 0.018, 0.014), (0, 0.093, -0.190), ACCENT, None),  # hausse avant
		("box", (0.014, 0.020, 0.012), (0, 0.095, -0.010), ACCENT, None),  # hausse arrière
	]
	muzzle = (0, 0.052, -0.283)
	return parts, muzzle


def parts_magnum() -> tuple:
	parts = [
		("box", (0.082, 0.165, 0.078), (0, -0.075, 0.025), GRIP, None),
		("box", (0.082, 0.090, 0.095), (0, 0.050, -0.015), BODY, None),
		("cyl", (0.046, 0.052, 12, None), (0, 0.052, -0.070), METAL, ("X", 90)),  # barillet
		("cyl", (0.015, 0.170, 10, None), (0, 0.052, -0.175), METAL, None),  # canon long
		("box", (0.012, 0.016, 0.012), (0, 0.088, -0.250), ACCENT, None),
	]
	muzzle = (0, 0.052, -0.260)
	return parts, muzzle


def parts_rafale() -> tuple:
	parts = [
		("box", (0.072, 0.150, 0.070), (0, -0.070, 0.070), GRIP, None),
		("box", (0.085, 0.095, 0.360), (0, 0.050, -0.120), BODY, None),
		("box", (0.045, 0.150, 0.050), (0, -0.140, 0.015), METAL, None),  # chargeur long
		("cyl", (0.015, 0.130, 10, None), (0, 0.058, -0.360), METAL, None),
		("box", (0.055, 0.045, 0.060), (0, 0.045, 0.185), BODY, None),  # crosse repliée
		("box", (0.012, 0.014, 0.012), (0, 0.100, -0.300), ACCENT, None),
	]
	muzzle = (0, 0.058, -0.425)
	return parts, muzzle


def parts_marqueur() -> tuple:
	parts = [
		("box", (0.075, 0.155, 0.072), (0, -0.078, 0.030), GRIP, None),
		("box", (0.088, 0.100, 0.480), (0, 0.055, -0.140), BODY, None),
		("box", (0.048, 0.140, 0.060), (0, -0.130, -0.070), METAL, None),  # chargeur
		("cyl", (0.016, 0.320, 10, None), (0, 0.060, -0.540), METAL, None),
		("box", (0.075, 0.075, 0.150), (0, 0.055, 0.290), BODY, None),  # crosse
		("box", (0.020, 0.022, 0.070), (0, 0.108, -0.150), ACCENT, None),  # rail de visée
	]
	muzzle = (0, 0.060, -0.700)
	return parts, muzzle


def parts_ravage() -> tuple:
	parts = [
		("box", (0.078, 0.155, 0.072), (0, -0.078, 0.020), GRIP, None),
		("box", (0.090, 0.105, 0.430), (0, 0.055, -0.130), BODY, None),
		("box", (0.046, 0.190, 0.058), (0, -0.170, -0.055), METAL, ("X", -8)),  # chargeur courbe
		("cyl", (0.017, 0.280, 10, None), (0, 0.060, -0.485), METAL, None),
		("box", (0.070, 0.070, 0.140), (0, 0.058, 0.250), BODY, None),  # crosse
		("box", (0.014, 0.024, 0.014), (0, 0.112, -0.330), ACCENT, None),  # hausse avant
		("box", (0.014, 0.020, 0.012), (0, 0.108, -0.010), ACCENT, None),  # hausse arrière
	]
	muzzle = (0, 0.060, -0.625)
	return parts, muzzle


def parts_fracas() -> tuple:
	parts = [
		("box", (0.080, 0.150, 0.075), (0, -0.075, 0.150), GRIP, None),
		("box", (0.095, 0.110, 0.180), (0, 0.058, 0.040), BODY, None),
		("cyl", (0.028, 0.420, 12, None), (0, 0.060, -0.300), BODY, None),  # tube canon
		("cyl", (0.018, 0.420, 10, None), (0, 0.030, -0.300), METAL, None),  # canon sous-tube
		("box", (0.070, 0.055, 0.140), (0, 0.030, -0.230), GRIP, None),  # garde-main pompe
		("box", (0.085, 0.085, 0.220), (0, 0.045, 0.330), BODY, None),  # crosse
		("box", (0.012, 0.016, 0.012), (0, 0.090, -0.500), ACCENT, None),  # guidon
	]
	muzzle = (0, 0.060, -0.510)
	return parts, muzzle


def parts_faucheur() -> tuple:
	parts = [
		("box", (0.078, 0.150, 0.072), (0, -0.075, 0.060), GRIP, None),
		("box", (0.090, 0.100, 0.360), (0, 0.058, -0.080), BODY, None),
		("box", (0.046, 0.130, 0.055), (0, -0.120, -0.060), METAL, None),  # chargeur
		("box", (0.045, 0.022, 0.020), (0.065, 0.095, -0.020), METAL, None),  # poignée de culasse
		("cyl", (0.015, 0.480, 10, None), (0, 0.060, -0.500), METAL, None),  # canon
		("cyl", (0.032, 0.220, 14, None), (0, 0.135, -0.140), METAL, None),  # lunette
		("box", (0.014, 0.055, 0.014), (0, 0.098, -0.080), ACCENT, None),  # monture avant
		("box", (0.014, 0.055, 0.014), (0, 0.098, -0.220), ACCENT, None),  # monture arrière
		("box", (0.080, 0.085, 0.260), (0, 0.055, 0.310), BODY, None),  # crosse
		("box", (0.075, 0.060, 0.060), (0, 0.020, 0.480), BODY, None),  # plaque de couche
	]
	muzzle = (0, 0.060, -0.740)
	return parts, muzzle


WEAPONS = {
	"pistolet": (parts_pistolet, 0.005),
	"magnum": (parts_magnum, 0.006),
	"rafale": (parts_rafale, 0.006),
	"marqueur": (parts_marqueur, 0.006),
	"ravage": (parts_ravage, 0.006),
	"fracas": (parts_fracas, 0.007),
	"faucheur": (parts_faucheur, 0.007),
}

## Empty "Foregrip" (viewmodel FPS — voir ViewModel.gd `solve_grip_transform`) :
## marque où la main de soutien (gauche) doit se poser, sur le garde-main/
## avant du récepteur — PAS sur le canon lui-même (`muzzle`, déjà utilisé pour
## le flash). Calculé à partir de `muzzle_pos` (déjà renvoyé par chaque
## `parts_X()`, pas besoin de dupliquer les gabarits de pièces) : une
## fraction du chemin poignée(0,0,0) -> bouche, plus proche de la poignée
## pour une arme courte tenue à une main (pistolet/magnum — prise "à deux
## mains" façon Valorant quand même, cf. .orchestrator/refs), plus loin pour
## un fusil/fusil de précision à long canon, jamais pile sur la bouche (recul
## invraisemblable si la main gauche touchait le canon chaud). Le Y suit la
## même hauteur que la bouche (légèrement réduite, x0.85 : la main empoigne
## SOUS l'axe du canon, pas dessus) : évite de coder en dur un second jeu de
## coordonnées par arme alors que `muzzle_pos` porte déjà toute l'info utile
## (position ET hauteur du canon).
FOREGRIP_FRACTION = {
	"pistolet": 0.55, "magnum": 0.55, "rafale": 0.46, "marqueur": 0.40,
	"ravage": 0.42, "fracas": 0.55, "faucheur": 0.34,
}


def build(name: str, parts_fn, bevel_width: float) -> None:
	toonkit.reset_scene()
	bm = bmesh.new()
	parts, muzzle_pos = parts_fn()
	for kind, a, center, mat_idx, extra in parts:
		if kind == "box":
			add_box(bm, a, center, mat_idx, rot=extra)
		else:  # "cyl" -> a = (radius, depth, segments, radius2)
			radius, depth, segments, radius2 = a
			add_cyl(bm, radius, depth, center, mat_idx, segments=segments, rot=extra, radius2=radius2)

	# Toutes les coordonnées ci-dessus sont écrites dans le repère GODOT visé
	# (X=droite, Y=haut, Z=avant — canon vers -Z) pour rester lisibles. Mais
	# Blender est Z-up en interne : sans correction, le "haut" (Y) qu'on a
	# écrit finirait sur l'axe Z de Blender (profondeur) et le "avant" (Z) sur
	# son axe Y (hauteur) une fois réexporté en Y-up. Une rotation +90° autour
	# de X sur TOUT le maillage (avant export) fait le mapping inverse exact
	# (vérifié par sondage bpy + relecture du .glb, voir rapport de tâche) :
	# elle envoie notre Y-authored sur le Z de Blender et notre -Z-authored
	# sur son -Y, si bien que l'export Y-up de Blender restitue pile le
	# repère Godot voulu.
	bmesh.ops.rotate(bm, cent=(0, 0, 0), matrix=Matrix.Rotation(math.radians(90), 3, 'X'), verts=list(bm.verts))

	me = bpy.data.meshes.new(name)
	bm.to_mesh(me)
	bm.free()
	obj = bpy.data.objects.new(name, me)
	bpy.context.scene.collection.objects.link(obj)

	for slot in SLOT_NAMES:
		mat = bpy.data.materials.new(f"{name}_{slot}")
		mat.diffuse_color = SLOT_COLORS[SLOT_NAMES.index(slot)]
		if mat.node_tree:
			bsdf = mat.node_tree.nodes.get("Principled BSDF")
			if bsdf:
				bsdf.inputs["Base Color"].default_value = SLOT_COLORS[SLOT_NAMES.index(slot)]
				bsdf.inputs["Roughness"].default_value = 0.75 if slot != "metal" else 0.35
		obj.data.materials.append(mat)

	# Bevel appliqué, puis lissage "hard-surface" stylekit (remplace l'ancien
	# `p.use_smooth = False` uniforme) + normale de contour + AO/courbure —
	# voir le commentaire d'en-tête de fichier (A3D-03).
	toonkit.add_bevel(obj, width=bevel_width, segments=2, angle_limit_deg=35.0)
	toonkit.weighted_normals(obj)
	toonkit.smooth_normal_attrs(obj)
	toonkit.bake_vertex_ao(obj)
	toonkit.curvature_edge_mask(obj)

	muzzle = bpy.data.objects.new("Muzzle", None)
	muzzle.empty_display_type = 'PLAIN_AXES'
	muzzle.empty_display_size = 0.03
	# Même correction d'axes que la géométrie (voir plus haut) : l'empty n'est
	# pas dans le bmesh donc on lui applique la même rotation +90°/X à la main.
	muzzle.location = Matrix.Rotation(math.radians(90), 3, 'X') @ Vector(muzzle_pos)
	bpy.context.scene.collection.objects.link(muzzle)
	muzzle.parent = obj

	fraction = FOREGRIP_FRACTION[name]
	foregrip_pos = (muzzle_pos[0], muzzle_pos[1] * 0.85, muzzle_pos[2] * fraction)
	foregrip = bpy.data.objects.new("Foregrip", None)
	foregrip.empty_display_type = 'PLAIN_AXES'
	foregrip.empty_display_size = 0.03
	foregrip.location = Matrix.Rotation(math.radians(90), 3, 'X') @ Vector(foregrip_pos)
	bpy.context.scene.collection.objects.link(foregrip)
	foregrip.parent = obj

	os.makedirs(OUT_DIR, exist_ok=True)
	out_path = os.path.join(OUT_DIR, f"{name}.glb")
	bpy.ops.object.select_all(action='DESELECT')
	obj.select_set(True)
	muzzle.select_set(True)
	foregrip.select_set(True)
	bpy.ops.export_scene.gltf(
		filepath=out_path,
		export_format='GLB',
		use_selection=True,
		export_apply=True,
		export_yup=True,
		export_materials='EXPORT',
		export_vertex_color='ACTIVE',
		export_all_vertex_colors=True,
		export_attributes=True,
		export_cameras=False,
		export_lights=False,
		export_animations=False,
	)
	tris = toonkit.tri_count(obj)
	print(f"WEAPON_MODEL_OK {name} tris={tris} -> {out_path}")


def main() -> None:
	for name, (parts_fn, bevel_width) in WEAPONS.items():
		build(name, parts_fn, bevel_width)


if __name__ == "__main__":
	main()
