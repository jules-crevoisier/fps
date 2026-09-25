## tools/blender/turntable.py
## Auto-review d'un asset (.glb ou .blend) : importe, cadre automatiquement,
## rend N vues en orbite + 1 vue de dessus + 1 gros plan avec un rendu "toon-
## like" façon BD (2 tons de lumière francs, lumière/ombre teintée #5B6CA6 —
## §7.2 de la bible — + contour à l'encre), une silhouette humaine de 1,8 m
## posée à côté pour l'échelle et une pastille de calibration (§7.5, CHK-01),
## puis compose TOUT ça en une seule planche-contact PNG (grille + légendes +
## tri count/dimensions/matériaux) — pour qu'un agent IA en terminal puisse
## VOIR le résultat (Read sur l'image) avant de l'importer dans Godot. Voir
## docs/3D_PIPELINE.md pour la boucle complète.
##
##   blender -b -P tools/blender/turntable.py -- --in PATH.glb|.blend
##       [--out DIR] [--views 8] [--size 512]
##
## Le chemin de la planche-contact est imprimé SEUL sur la toute dernière
## ligne de sortie (`print(path)`), pour qu'un script appelant puisse la
## capturer sans parser le reste du log.
##
## Ce fichier ne modifie AUCUN asset existant : il importe une COPIE en
## mémoire (session Blender jetable), ne réécrit jamais le .glb/.blend source.
##
## Correctif TOOL-01 (2026-09-25) : un matériau dont la Base Color est liée
## à une image (`_find_albedo_image` -- directement, comme tout matériau
## "<id>_painted" de tools/blender/paint_bake.py, ou via le montage vertex-
## color x albédo de bake_vertex_ao/curvature_edge_mask) affiche désormais
## SA VRAIE TEXTURE dans l'aperçu 2 tons, au lieu de l'aplat bleu-gris
## constaté avant ce correctif (`_read_albedo` seule ne reconnaissait que le
## second montage, jamais une image liée directement).
##
## Technique de rendu (API bpy 5.2 vérifiée par sondage avant écriture, voir
## rapport de tâche) :
## - "2 tons" : Shader to RGB -> Color Ramp (interpolation CONSTANT, donc un
##   PALIER franc, pas un dégradé) -> multiplié par l'albédo d'origine ->
##   Emission (contourne tout le pipeline PBR de l'Eevee 5.2 "next", qui
##   ignore Shader-to-RGB s'il reste raccordé à une BSDF affichée telle
##   quelle — vérifié par rendu : sans ce détour, aucun palier n'apparaît).
##   Le point du ramp qui fixe le seuil lumière/ombre doit être créé via
##   `elements.new()`, jamais obtenu en repositionnant un point déjà existant
##   (voir `_build_toon_preview` : sondage bpy, un repositionnement direct ne
##   se propage pas de façon fiable au shader compilé).
## - Couleur WYSIWYG : toute couleur qui vient de `toonkit.palette()` (un hex
##   de la bible) passe par `_srgb_to_linear_color` avant d'être posée sur un
##   socket, et la scène est en transfert de vue Standard
##   (`_apply_wysiwyg_view_transform`) — sans les deux, la palette rendait
##   plus claire et désaturée que son hex (le "voile gris", OPS-07).
## - Contour à l'encre : Freestyle (silhouette + bordure + arêtes vives +
##   frontière de matériau), pas de coque inversée par objet — beaucoup plus
##   simple à appliquer uniformément à un asset importé arbitraire, et
##   Freestyle fonctionne bien en Eevee 5.2 (vérifié par sondage).
import argparse
import math
import os
import sys

import bpy
from mathutils import Vector

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "lib"))
import toonkit  # noqa: E402

# ---------------------------------------------------------------------------
# Constantes de mise en scène
# ---------------------------------------------------------------------------
HUMAN_HEIGHT_M = 1.8
HUMAN_BODY_RADIUS = 0.22
HUMAN_HEAD_RADIUS = 0.11
CAM_FOV_DEG = 45.0
ORBIT_ELEVATION_DEG = 22.0
CLOSEUP_ELEVATION_DEG = 26.0
CLOSEUP_AZIMUTH_DEG = 35.0
FRAME_MARGIN = 1.4  # marge autour du sujet cadré (1.0 = pile calé au bord)

# Mise en page planche-contact (pixels, canevas = 1 unité Blender = 1 pixel).
HEADER_H = 120
LABEL_H = 40
GUTTER = 18
OUTER_MARGIN = 24
BG_COLOR = (0.098, 0.098, 0.106, 1.0)     # graphite sombre (chrome de la planche, PAS le fond du rendu)
TEXT_COLOR = (0.92, 0.90, 0.86, 1.0)      # quasi-papier, lisible sur fond sombre

# Pastille de calibration CHK-01 (§7.5) : angle qui montre à la fois la face
# éclairée et la face à l'ombre de la sphère-témoin (sondage OPS-07, voir
# rapport de tâche -- balayage azimut x élévation sous ce même rig KeySun/
# FillSun, ~44 %/56 % lit/ombre à cet angle, donc les deux tons bien visibles
# côte à côte pour une relecture à l'œil).
CALIBRATION_ALBEDO_TOKEN = "sand_dirt"   # #D2A46C -- tokens.json calibration_probe.albedo
CALIBRATION_ELEVATION_DEG = -5.0
CALIBRATION_AZIMUTH_DEG = 270.0
CALIBRATION_RADIUS = 0.4

# Bande "ombre" du ramp 2 tons (§7.2 band_count=2 : "un ton de lumière, un
# ton d'ombre"). Teinte = shadow_tint de la bible (#5B6CA6), normalisée en
# luminance (on ne garde que sa TEINTE) puis mélangée à l'identité à
# SHADOW_TINT_MIX (= shadow_tint_mix de tokens.json, 0,40), enfin mise à
# l'échelle par SHADOW_LINEAR_SCALE. Sondage OPS-07 (voir rapport de tâche) :
# ce facteur linéaire restitue un ratio de L OKLab ombre/éclairé de 0,6597
# sur la pastille #D2A46C -- dans la fourchette 0,62-0,70 visée par
# `calibration_probe.shadow_ratio` (shadow_value cible 0,66).
SHADOW_TINT_MIX = 0.40
SHADOW_LINEAR_SCALE = 0.30



# ---------------------------------------------------------------------------
# Couleur -- décodage sRGB -> linéaire (correctif du "voile gris", OPS-07)
# ---------------------------------------------------------------------------
#
# Sondage bpy 5.2 (voir rapport de tâche) : un socket Color de node (Base
# Color, Emission...) réglé depuis Python via `default_value` est utilisé
# TEL QUEL comme une valeur LINÉAIRE -- contrairement au sélecteur de couleur
# de l'UI, qui convertit sRGB -> linéaire pour vous, `default_value` n'
# applique AUCUNE conversion. `toonkit.palette()`/`toonkit._hex_to_rgba` ne
# renvoient que hex/255 (donc du sRGB brut) : tout appelant qui pose cette
# valeur directement sur un socket obtient un rendu plus clair et désaturé
# que l'hex voulu. Mesuré au sondage : la pastille `#D2A46C` posée brute
# restitue (0.918, 0.820, 0.682) sous le transfert de vue Standard, au lieu
# de (0.824, 0.643, 0.424) une fois ce décodage appliqué avant assignation
# (et Standard lui-même remplace le défaut "AgX" d'une scène fraîche -- voir
# `_apply_wysiwyg_view_transform` -- qui recompressait/désaturait une
# deuxième fois : à eux deux, c'était le "voile gris" du contrat).
def _srgb_to_linear(c: float) -> float:
	"""Un canal sRGB (0..1, tel que renvoyé par `toonkit._hex_to_rgba`) vers
	sa valeur linéaire -- décodage sRGB exact (portion linéaire + loi de
	puissance 2.4), pas une simple gamma 2.2."""
	return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def _srgb_to_linear_color(rgba) -> tuple:
	"""Applique `_srgb_to_linear` aux 3 canaux couleur d'un RGBA (alpha
	inchangé) -- à utiliser sur TOUTE couleur qui vient de
	`toonkit.palette()` (donc d'un hex de la bible) avant de la poser sur un
	socket Base Color/Emission, pour que ce socket reproduise fidèlement cet
	hex à l'écran (WYSIWYG, §1.1/§7.5). Ne s'applique PAS à un albédo relu
	depuis un matériau importé (`_read_albedo`) : un baseColorFactor glTF est
	déjà en linéaire par la spec, une deuxième conversion l'assombrirait à
	tort."""
	a = rgba[3] if len(rgba) > 3 else 1.0
	return tuple(_srgb_to_linear(c) for c in rgba[:3]) + (a,)


def _apply_wysiwyg_view_transform(scene) -> None:
	"""Transfert de vue Standard -- pendant, côté Godot, le tonemap LINEAR/
	exposition 1.0 de `LevelLook` (§7.5, « le filmique compressait puis
	assombrissait : les hex ne voulaient plus rien dire »). Sondage bpy 5.2
	(voir rapport de tâche) : une scène fraîche démarre en couleur AgX, qui
	recompresse/désature la palette même une fois `_srgb_to_linear_color`
	appliqué -- sans ce réglage, la pastille de calibration ne restitue PAS
	son hex à ±5 %."""
	scene.view_settings.view_transform = 'Standard'
	scene.view_settings.exposure = 0.0
	scene.view_settings.gamma = 1.0


def _shadow_band_multiplier() -> tuple:
	"""Vecteur RGB linéaire à multiplier à l'albédo pour la bande "ombre" du
	ramp 2 tons de `_build_toon_preview` (voir constantes SHADOW_* et leur
	commentaire). Ne dépend que de la teinte d'ombre de la bible -- appelé
	une fois par matériau construit."""
	tint = _srgb_to_linear_color(toonkit.palette("shadow_tint"))[:3]
	luma = 0.2126 * tint[0] + 0.7152 * tint[1] + 0.0722 * tint[2]
	tint_norm = tuple(c / max(luma, 0.0001) for c in tint)
	return tuple((1.0 * (1.0 - SHADOW_TINT_MIX) + t * SHADOW_TINT_MIX) * SHADOW_LINEAR_SCALE
		for t in tint_norm)


def parse_args():
	argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
	p = argparse.ArgumentParser()
	p.add_argument("--in", dest="in_path", required=True)
	p.add_argument("--out", dest="out_dir", default=None)
	p.add_argument("--views", type=int, default=8)
	p.add_argument("--size", type=int, default=512)
	return p.parse_args(argv)


# ---------------------------------------------------------------------------
# Import
# ---------------------------------------------------------------------------

def import_asset(path: str) -> list:
	"""Importe `path` (.glb/.gltf ou .blend) dans la scène courante (déjà
	réinitialisée par l'appelant) et renvoie la liste des MeshInstance
	importées. Pour un .blend, ouvre le fichier tel quel (remplace toute la
	session — c'est voulu, on ne fait tourner qu'un seul asset par appel de
	ce script) et ramène les objets mesh de sa scène active."""
	ext = os.path.splitext(path)[1].lower()
	if ext in (".glb", ".gltf"):
		bpy.ops.import_scene.gltf(filepath=path)
	elif ext == ".blend":
		bpy.ops.wm.open_mainfile(filepath=path)
	else:
		raise ValueError(f"turntable: extension non supportée: {ext!r} (attendu .glb/.gltf/.blend)")
	return [o for o in bpy.context.scene.objects if o.type == 'MESH']


# ---------------------------------------------------------------------------
# Matériaux d'aperçu "2 tons + encre" (remplace, en mémoire, les matériaux
# importés — ne touche jamais le fichier source).
# ---------------------------------------------------------------------------

def _read_albedo(mat: "bpy.types.Material"):
	"""Couleur plate d'origine d'un matériau importé. Piège rencontré en
	écrivant ce script (voir rapport de tâche) : un asset qui a des vertex
	colors bakées (`toonkit.bake_vertex_ao`/`curvature_edge_mask`) revient de
	l'aller-retour export/import avec sa "Base Color" RACCORDÉE (par un nœud
	Mix "vertex_color x albédo d'origine", conforme au comportement standard
	glTF "COLOR_0 multiplie baseColorFactor") — dans ce cas `default_value`
	de l'entrée "Base Color" est un simple PLACEHOLDER ignoré au rendu
	(souvent gris 0.8), PAS la vraie couleur. On retrouve la vraie couleur en
	remontant jusqu'à l'entrée NON raccordée du nœud Mix (l'autre entrée, elle,
	vient du nœud "Color Attribute")."""
	if mat is None:
		return (0.7, 0.7, 0.7, 1.0)
	if mat.use_nodes and mat.node_tree is not None:
		bsdf = mat.node_tree.nodes.get("Principled BSDF")
		if bsdf is not None and "Base Color" in bsdf.inputs:
			socket = bsdf.inputs["Base Color"]
			if not socket.is_linked:
				c = socket.default_value
				return (c[0], c[1], c[2], c[3])
			src = socket.links[0].from_node
			if src.type == 'MIX':
				# Le nœud "Mix" unifié (5.x) porte PLUSIEURS sockets nommés "A"/
				# "B" (un jeu par type de donnée : float/vector/couleur) —
				# `inputs.get("A")` est ambigu (renvoie le premier, pas
				# forcément le socket couleur). On filtre par `.type == 'RGBA'`
				# pour ne garder que les deux sockets couleur, puis on prend
				# celui qui n'est PAS raccordé (l'autre vient du nœud "Color
				# Attribute" — voir docstring).
				for inp in src.inputs:
					if inp.type == 'RGBA' and not inp.is_linked:
						c = inp.default_value
						return (c[0], c[1], c[2], c[3])
	return tuple(mat.diffuse_color)


def _find_albedo_image(mat: "bpy.types.Material"):
	"""Image REELLEMENT liee sur la Base Color de `mat` (directement, ou via
	le meme montage "Mix vertex-color x albedo" que `_read_albedo` -- voir sa
	docstring), ou `None` si ce slot est une couleur plate. Corrige TOOL-01
	(constate par tools/blender/ai_import_painted.py::render_textured_preview,
	voir sa docstring) : sans cette fonction, `_read_albedo` seule ne reconnait
	QUE le montage Mix (vertex color + albedo) -- un materiau dont la Base
	Color est liee DIRECTEMENT a une image (le cas de tout materiau "<id>_
	painted" produit par tools/blender/paint_bake.py, et de tout import Tripo
	Studio conserve par ai_import_painted.py/fit_weapon_painted.py) tombait
	dans aucune des deux branches et retombait sur `mat.diffuse_color` -- un
	aplat gris-bleu qui ignore toute la texture peinte. `_read_albedo` reste
	la couleur de REPLI (utilisee quand cette fonction renvoie `None`) :
	`apply_preview_materials` appelle les deux."""
	if mat is None or not mat.use_nodes or mat.node_tree is None:
		return None
	bsdf = mat.node_tree.nodes.get("Principled BSDF")
	if bsdf is None or "Base Color" not in bsdf.inputs:
		return None
	socket = bsdf.inputs["Base Color"]
	if not socket.is_linked:
		return None
	src = socket.links[0].from_node
	if src.type == 'TEX_IMAGE' and src.image is not None:
		return src.image
	if src.type == 'MIX':
		for inp in src.inputs:
			if inp.type == 'RGBA' and inp.is_linked:
				upstream = inp.links[0].from_node
				if upstream.type == 'TEX_IMAGE' and upstream.image is not None:
					return upstream.image
	return None


def _build_toon_preview(name: str, albedo, image=None) -> "bpy.types.Material":
	"""Matériau d'aperçu "2 tons" (§7.2 : `band_count` cible = 2, "un ton de
	lumière, un ton d'ombre" -- remplace l'ancien ramp à 3 paliers de ce
	fichier, dont le palier médian quasi blanc délavait tout : c'était la
	moitié du "voile gris" du contrat OPS-07, voir rapport de tâche).
	Toujours Shader-to-RGB -> ColorRamp CONSTANT -> Multiply -> Emission
	(contourne le pipeline PBR de l'Eevee 5.2 "next", qui ignore
	Shader-to-RGB s'il reste raccordé à une BSDF affichée telle quelle -- cf.
	en-tête de fichier). Bande éclairée = albédo tel quel (facteur blanc
	1.0 : sous `_apply_wysiwyg_view_transform`, ça restitue l'hex d'origine
	à l'écran) ; bande ombre = albédo x `_shadow_band_multiplier()`.

	Piège bpy vérifié par sondage (voir rapport de tâche) : REPOSITIONNER un
	point de ramp déjà existant (muter `.position` sur l'élément par défaut
	de l'index 1) ne se propage PAS de façon fiable au shader Eevee compilé
	-- le rendu reste figé sur l'ancien seuil (bascule de couleur/palier
	absent selon l'angle). Il faut ajouter le nouveau point via
	`elements.new()` puis retirer l'ancien via `elements.remove()` ; muter la
	COULEUR d'un point qui ne change pas de position (ici l'élément 0, resté
	à 0.0) fonctionne en revanche sans problème."""
	mat = bpy.data.materials.new(f"{name}_toonpreview")
	mat.use_nodes = True
	nt = mat.node_tree
	for n in list(nt.nodes):
		nt.nodes.remove(n)
	out = nt.nodes.new("ShaderNodeOutputMaterial")
	bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
	bsdf.inputs["Base Color"].default_value = (1.0, 1.0, 1.0, 1.0)
	bsdf.inputs["Roughness"].default_value = 1.0
	srgb = nt.nodes.new("ShaderNodeShaderToRGB")
	ramp = nt.nodes.new("ShaderNodeValToRGB")
	ramp.color_ramp.interpolation = 'CONSTANT'
	shadow_mul = _shadow_band_multiplier()
	el0 = ramp.color_ramp.elements[0]
	el0.position = 0.0
	el0.color = (shadow_mul[0], shadow_mul[1], shadow_mul[2], 1.0)
	old_default_stop = ramp.color_ramp.elements[1]  # (pos 1.0, blanc) -- à retirer APRÈS en avoir ajouté un nouveau
	lit_stop = ramp.color_ramp.elements.new(0.5)
	lit_stop.color = (1.0, 1.0, 1.0, 1.0)
	ramp.color_ramp.elements.remove(old_default_stop)
	mul = nt.nodes.new("ShaderNodeMixRGB")
	mul.blend_type = 'MULTIPLY'
	mul.inputs['Fac'].default_value = 1.0
	if image is not None:
		# TOOL-01 : un materiau peint/texture affiche sa VRAIE texture (son
		# propre "Color" de sortie, dont Blender convertit deja sRGB->lineaire
		# via `image.colorspace_settings` -- meme conversion, par un autre
		# chemin, que `_srgb_to_linear_color` applique a la branche couleur
		# plate ci-dessous), jamais un aplat qui l'ignorerait.
		tex = nt.nodes.new("ShaderNodeTexImage")
		tex.image = image
		nt.links.new(tex.outputs["Color"], mul.inputs['Color2'])
	else:
		mul.inputs['Color2'].default_value = (albedo[0], albedo[1], albedo[2], 1.0)
	em = nt.nodes.new("ShaderNodeEmission")
	nt.links.new(bsdf.outputs["BSDF"], srgb.inputs["Shader"])
	nt.links.new(srgb.outputs["Color"], ramp.inputs["Fac"])
	nt.links.new(ramp.outputs["Color"], mul.inputs["Color1"])
	nt.links.new(mul.outputs["Color"], em.inputs["Color"])
	nt.links.new(em.outputs["Emission"], out.inputs["Surface"])
	return mat


def apply_preview_materials(mesh_objs: list) -> list:
	"""Remplace chaque matériau des objets importés par une variante "2
	tons" dérivée de sa couleur d'origine. Renvoie la liste des noms de
	matériaux ORIGINAUX rencontrés (pour la légende de la planche-contact)."""
	cache = {}
	original_names = []
	for obj in mesh_objs:
		for i, slot in enumerate(obj.material_slots):
			original = slot.material
			key = original.name if original is not None else "__none__"
			if original is not None and original.name not in original_names:
				original_names.append(original.name)
			if key not in cache:
				cache[key] = _build_toon_preview(key, _read_albedo(original), image=_find_albedo_image(original))
			obj.data.materials[i] = cache[key]
	return original_names


# ---------------------------------------------------------------------------
# Cadrage / caméra
# ---------------------------------------------------------------------------

def world_bbox(objs):
	corners = []
	for obj in objs:
		corners.extend(obj.matrix_world @ Vector(c) for c in obj.bound_box)
	mins = Vector((min(c.x for c in corners), min(c.y for c in corners), min(c.z for c in corners)))
	maxs = Vector((max(c.x for c in corners), max(c.y for c in corners), max(c.z for c in corners)))
	return mins, maxs


def add_human_silhouette(x: float, y_depth: float, ground_z: float) -> "bpy.types.Object":
	"""Place un mannequin (capsule + tête) DEBOUT dans le repère Z-up RÉEL de
	Blender (celui de l'asset réimporté — voir en-tête de fichier : "up" =
	Z, X/Y = horizontal). `toonkit.capsule()`/`blob()` tiennent déjà debout
	nativement sur Z (voir leur docstring) : aucune rotation à appliquer,
	juste les positionner par `location` (coordonnées monde réelles)."""
	body_h = HUMAN_HEIGHT_M - 2 * HUMAN_BODY_RADIUS - 2 * HUMAN_HEAD_RADIUS
	body = toonkit.capsule(radius=HUMAN_BODY_RADIUS, height=max(body_h, 0.05), name="ScaleHuman_Body")
	body.location = (x, y_depth, ground_z + HUMAN_BODY_RADIUS + body_h / 2.0)
	head = toonkit.blob(radius=HUMAN_HEAD_RADIUS, subdiv=2, noise_strength=0.0, name="ScaleHuman_Head")
	head.location = (x, y_depth, ground_z + 2 * HUMAN_BODY_RADIUS + body_h + HUMAN_HEAD_RADIUS)
	human = toonkit.join([body, head])
	human.name = "ScaleHuman"
	mat = toonkit.toon_material("scale_human", _srgb_to_linear_color(toonkit.palette("graphite")), kind="flat")
	human.data.materials.append(mat)
	return human


def add_ground(cx: float, cy: float, ground_z: float, radius: float) -> "bpy.types.Object":
	"""Plaque de sol plate, posée directement en coordonnées monde Z-up
	réelles (X/Y horizontaux, Z = épaisseur) — pas de rotation nécessaire :
	`rounded_box(size=(x,y,z))` sans rotation d'objet donne déjà un pavé dont
	le 3e axe (fin, 0.05 m) est bien l'axe Z du monde."""
	plane = toonkit.rounded_box(size=(radius * 2.2, radius * 2.2, 0.05), bevel_width=0.0, segments=0, name="Ground")
	plane.location = (cx, cy, ground_z - 0.025)
	mat = toonkit.toon_material("ground_preview", _srgb_to_linear_color(toonkit.palette("sand_dirt")), kind="sand_dirt")
	plane.data.materials.append(mat)
	return plane


def _look_at(cam_obj, target: Vector) -> None:
	direction = target - cam_obj.location
	cam_obj.rotation_euler = direction.to_track_quat('-Z', 'Y').to_euler()


def _orbit_position(center: Vector, radius: float, azimuth_deg: float, elevation_deg: float) -> Vector:
	"""Position sur une orbite autour de `center`, en coordonnées monde Z-up
	RÉELLES (Z = élévation/hauteur, X/Y = le cercle horizontal — voir
	en-tête de fichier). Piège déjà rencontré une fois dans ce fichier :
	NE PAS mettre le terme d'élévation sur Y (Y est horizontal dans Blender,
	pas "haut")."""
	az = math.radians(azimuth_deg)
	el = math.radians(elevation_deg)
	horiz = radius * math.cos(el)
	return center + Vector((horiz * math.sin(az), horiz * math.cos(az), radius * math.sin(el)))


def _distance_for(radius: float, fov_deg: float) -> float:
	return max(radius, 0.05) * FRAME_MARGIN / math.sin(math.radians(fov_deg) / 2.0)


# ---------------------------------------------------------------------------
# Éclairage / monde / Freestyle
# ---------------------------------------------------------------------------

def setup_render(size: int) -> None:
	scene = bpy.context.scene
	scene.render.engine = 'BLENDER_EEVEE'
	scene.render.resolution_x = size
	scene.render.resolution_y = size
	scene.render.film_transparent = False
	scene.render.image_settings.file_format = 'PNG'
	_apply_wysiwyg_view_transform(scene)

	world = bpy.data.worlds.new("TurntableWorld")
	world.use_nodes = True
	bg = world.node_tree.nodes.get("Background")
	if bg is not None:
		bg.inputs[0].default_value = (0.5, 0.5, 0.52, 1.0)
		bg.inputs[1].default_value = 1.0
	scene.world = world

	key = bpy.data.objects.new("KeySun", bpy.data.lights.new("KeySun", type='SUN'))
	key.data.energy = 3.4
	key.data.angle = math.radians(3.0)
	key.rotation_euler = (math.radians(58), 0.0, math.radians(-35))
	scene.collection.objects.link(key)

	fill = bpy.data.objects.new("FillSun", bpy.data.lights.new("FillSun", type='SUN'))
	fill.data.energy = 0.5
	# Blanc neutre, PAS la teinte d'ombre (v1 de ce fichier) : sondage OPS-07
	# (voir rapport de tâche) -- un FillSun teinté est une lumière physique
	# dont la couleur entre RÉELLEMENT dans le "Shader to RGB" combiné avec
	# le KeySun ; comme sa contribution relative change avec l'orientation
	# de la surface, la teinte perçue de l'objet variait d'une vue d'orbite
	# à l'autre (la "bascule de couleur" du contrat) en plus de se
	# recombiner de façon incohérente avec la teinte DÉJÀ posée par le ramp
	# de `_build_toon_preview`. La teinte d'ombre voulue vient UNIQUEMENT du
	# ramp désormais (2 tons, constant quel que soit l'angle) ; ce fill ne
	# sert plus qu'à éclairer un peu le côté opposé au KeySun.
	fill.data.color = (1.0, 1.0, 1.0)
	fill.rotation_euler = (math.radians(-40), 0.0, math.radians(150))
	scene.collection.objects.link(fill)

	scene.render.use_freestyle = True
	vl = bpy.context.view_layer
	for ls in list(vl.freestyle_settings.linesets):  # retire le lineset par défaut du view layer
		vl.freestyle_settings.linesets.remove(ls)
	ls = vl.freestyle_settings.linesets.new("ink")
	ls.select_silhouette = True
	ls.select_border = True
	ls.select_crease = True
	ls.select_material_boundary = True
	ls.select_contour = True
	vl.freestyle_settings.crease_angle = math.radians(134.0)  # propriété du view layer, pas du lineset
	ink = _srgb_to_linear_color(toonkit.palette("ink"))
	ls.linestyle.color = (ink[0], ink[1], ink[2])
	ls.linestyle.thickness = max(1.6, size / 230.0)


def add_camera(fov_deg: float) -> "bpy.types.Object":
	cam_data = bpy.data.cameras.new("TurntableCam")
	cam_data.lens_unit = 'FOV'
	cam_data.angle = math.radians(fov_deg)
	cam = bpy.data.objects.new("TurntableCam", cam_data)
	bpy.context.scene.collection.objects.link(cam)
	bpy.context.scene.camera = cam
	return cam


def render_to(path: str) -> None:
	bpy.context.scene.render.filepath = path
	bpy.ops.render.render(write_still=True)


def render_calibration_swatch(out_dir: str, size: int) -> tuple:
	"""Rend la pastille de calibration CHK-01 (§7.5) : une sphère d'albédo
	`#D2A46C` (`toonkit.palette("sand_dirt")`, la cible de
	`calibration_probe` dans `docs/style/tokens.json`), sous le MÊME rig
	KeySun/FillSun et le même matériau 2 tons que le sujet -- rend la face
	éclairée ET la face à l'ombre visibles côte à côte (angle vérifié par
	sondage, voir constantes CALIBRATION_*), pour qu'un agent/humain qui lit
	la planche puisse vérifier À L'ŒIL, sans quitter l'image, que la palette
	v3 est restituée fidèlement (L éclairée = albédo ± 0,03, ratio d'ombre
	0,62-0,70) et que le "voile gris" a disparu.

	Repart d'une scène vide : appelée une fois que toutes les vues du sujet
	sont déjà rendues sur disque (leurs PNG n'ont plus besoin de la scène
	Blender en mémoire)."""
	toonkit.reset_scene()
	setup_render(size)
	albedo_srgb = toonkit.palette(CALIBRATION_ALBEDO_TOKEN)
	mat = _build_toon_preview("calibration_probe", _srgb_to_linear_color(albedo_srgb))
	bpy.ops.mesh.primitive_uv_sphere_add(radius=CALIBRATION_RADIUS, segments=48, ring_count=24)
	swatch = bpy.context.active_object
	swatch.name = "CalibrationSwatch"
	swatch.data.materials.append(mat)
	bpy.ops.object.shade_smooth()

	cam = add_camera(CAM_FOV_DEG)
	distance = _distance_for(CALIBRATION_RADIUS, CAM_FOV_DEG)
	center = Vector((0.0, 0.0, 0.0))
	cam.location = center + _orbit_position(Vector((0, 0, 0)), distance, CALIBRATION_AZIMUTH_DEG, CALIBRATION_ELEVATION_DEG)
	_look_at(cam, center)
	path = os.path.join(out_dir, "calibration.png")
	render_to(path)
	# Texte court à dessein : une planche à N colonnes n'alloue que `size` px
	# de large par légende (voir `build_contact_sheet`), et `_label` ne
	# retourne pas à la ligne -- un texte trop long déborde du cadre.
	label = "calibration #D2A46C (L 0.75±0.03, ombre 0.66)"
	return label, path


# ---------------------------------------------------------------------------
# Planche-contact
# ---------------------------------------------------------------------------

def _image_plane(image_path: str, px: float, py: float, w: float, h: float, z: float = 0.0):
	img = bpy.data.images.load(image_path)
	mat = bpy.data.materials.new("tile")
	mat.use_nodes = True
	nt = mat.node_tree
	for n in list(nt.nodes):
		nt.nodes.remove(n)
	out = nt.nodes.new("ShaderNodeOutputMaterial")
	tex = nt.nodes.new("ShaderNodeTexImage")
	tex.image = img
	tex.interpolation = 'Linear'
	em = nt.nodes.new("ShaderNodeEmission")
	nt.links.new(tex.outputs["Color"], em.inputs["Color"])
	nt.links.new(em.outputs["Emission"], out.inputs["Surface"])

	import bmesh as _bmesh
	bm = _bmesh.new()
	x0, x1 = px, px + w
	y0, y1 = -py, -(py + h)  # convention canevas Y vers le bas -> monde Y vers le haut (voir en-tête caméra)
	v_tl = bm.verts.new((x0, y0, z))
	v_tr = bm.verts.new((x1, y0, z))
	v_br = bm.verts.new((x1, y1, z))
	v_bl = bm.verts.new((x0, y1, z))
	face = bm.faces.new((v_tl, v_tr, v_br, v_bl))
	uv_layer = bm.loops.layers.uv.new()
	uvs = [(0, 1), (1, 1), (1, 0), (0, 0)]
	for loop, uv in zip(face.loops, uvs):
		loop[uv_layer].uv = uv
	me = bpy.data.meshes.new("tile")
	bm.to_mesh(me)
	bm.free()
	obj = bpy.data.objects.new("tile", me)
	obj.data.materials.append(mat)
	bpy.context.scene.collection.objects.link(obj)
	return obj


def _label(text: str, px: float, py: float, w: float, size: float, align='CENTER', color=TEXT_COLOR):
	curve = bpy.data.curves.new("label", type='FONT')
	curve.body = text
	curve.size = size
	curve.align_x = align
	curve.align_y = 'TOP'
	curve.extrude = 0.0
	curve.bevel_depth = 0.0
	obj = bpy.data.objects.new("label", curve)
	x = px + (w / 2.0 if align == 'CENTER' else 0.0)
	obj.location = (x, -py, 0.01)
	mat = bpy.data.materials.new("label_mat")
	mat.use_nodes = True
	nt = mat.node_tree
	for n in list(nt.nodes):
		nt.nodes.remove(n)
	out = nt.nodes.new("ShaderNodeOutputMaterial")
	em = nt.nodes.new("ShaderNodeEmission")
	em.inputs["Color"].default_value = color
	nt.links.new(em.outputs["Emission"], out.inputs["Surface"])
	obj.data.materials.append(mat)
	bpy.context.scene.collection.objects.link(obj)
	return obj


def build_contact_sheet(out_path: str, tiles: list, size: int, header_lines: list) -> str:
	"""`tiles` : liste de (label, image_path). Compose une grille + un
	bandeau d'en-tête dans une scène dédiée (1 unité Blender = 1 pixel,
	caméra ortho au-dessus regardant droit vers le bas — voir rapport de
	tâche pour la convention de repère)."""
	toonkit.reset_scene()
	n = len(tiles)
	cols = max(1, math.ceil(math.sqrt(n)))
	rows = max(1, math.ceil(n / cols))
	tile_w = tile_h = size
	canvas_w = OUTER_MARGIN * 2 + cols * tile_w + (cols - 1) * GUTTER
	canvas_h = OUTER_MARGIN * 2 + HEADER_H + rows * (tile_h + LABEL_H) + (rows - 1) * GUTTER

	# Pas de plan de fond dédié : le monde (Background shader, voir plus bas)
	# remplit déjà tout l'arrière-plan derrière les tuiles/légendes — plus
	# simple et évite tout risque de mal orienter un pavé plat (déjà
	# rencontré ailleurs dans ce fichier, voir `add_ground`).
	_label(" | ".join(header_lines), OUTER_MARGIN, OUTER_MARGIN, canvas_w - 2 * OUTER_MARGIN,
		size=26, align='LEFT')

	for i, (label, img_path) in enumerate(tiles):
		col = i % cols
		row = i // cols
		px = OUTER_MARGIN + col * (tile_w + GUTTER)
		py = OUTER_MARGIN + HEADER_H + row * (tile_h + LABEL_H + GUTTER)
		_image_plane(img_path, px, py, tile_w, tile_h, z=0.0)
		_label(label, px, py + tile_h + 4, tile_w, size=20, align='CENTER')

	cam = bpy.data.cameras.new("SheetCam")
	cam.type = 'ORTHO'
	cam.ortho_scale = canvas_w
	# `sensor_fit` 'HORIZONTAL' explicite -- sondage bpy 5.2 (voir rapport de
	# tâche OPS-07) : en 'AUTO' (défaut), Blender ajuste `ortho_scale` sur le
	# plus GRAND des deux axes de résolution. Cette planche est plus haute
	# que large (canvas_h > canvas_w dès qu'il y a plus d'une ligne de
	# tuiles) : 'AUTO' calait donc `ortho_scale` sur la hauteur et rognait la
	# largeur réellement visible à `canvas_w × canvas_w/canvas_h` -- d'où la
	# colonne de gauche et l'en-tête absents de la planche rendue (mesuré :
	# largeur visible ~83 % de `canvas_w` sur une planche 1236×1476).
	# 'HORIZONTAL' fixe `ortho_scale` = largeur, TOUJOURS, quel que soit le
	# ratio de résolution : la hauteur qui en découle (ortho_scale ×
	# resolution_y/resolution_x) retombe exactement sur `canvas_h` puisque
	# `resolution_x`/`resolution_y` sont ci-dessous posées à `canvas_w`/
	# `canvas_h` pile.
	cam.sensor_fit = 'HORIZONTAL'
	cam_obj = bpy.data.objects.new("SheetCam", cam)
	cam_obj.location = (canvas_w / 2.0, -canvas_h / 2.0, 10.0)
	cam_obj.rotation_euler = (0.0, 0.0, 0.0)
	bpy.context.scene.collection.objects.link(cam_obj)
	bpy.context.scene.camera = cam_obj

	world = bpy.data.worlds.new("SheetWorld")
	world.use_nodes = True
	bg_node = world.node_tree.nodes.get("Background")
	if bg_node is not None:
		bg_node.inputs[0].default_value = BG_COLOR
	bpy.context.scene.world = world

	scene = bpy.context.scene
	scene.render.engine = 'BLENDER_EEVEE'
	scene.render.use_freestyle = False
	scene.render.resolution_x = int(canvas_w)
	scene.render.resolution_y = int(canvas_h)
	scene.render.film_transparent = False
	scene.render.image_settings.file_format = 'PNG'
	_apply_wysiwyg_view_transform(scene)
	render_to(out_path)
	return out_path


# ---------------------------------------------------------------------------
# Programme principal
# ---------------------------------------------------------------------------

def main() -> None:
	args = parse_args()
	in_path = os.path.abspath(args.in_path)
	if not os.path.isfile(in_path):
		print(f"TURNTABLE_FAIL fichier introuvable: {in_path}")
		sys.exit(1)
	stem = os.path.splitext(os.path.basename(in_path))[0]
	out_dir = os.path.abspath(args.out_dir) if args.out_dir else os.path.join(
		os.path.dirname(in_path), f"{stem}_turntable")
	os.makedirs(out_dir, exist_ok=True)

	toonkit.reset_scene()
	mesh_objs = import_asset(in_path)
	if not mesh_objs:
		print("TURNTABLE_FAIL aucun mesh trouvé dans l'asset importé")
		sys.exit(1)

	material_names = apply_preview_materials(mesh_objs)
	tris = toonkit.tri_count(mesh_objs)
	mins, maxs = world_bbox(mesh_objs)
	dims = maxs - mins
	asset_center = (mins + maxs) / 2.0
	asset_radius = max(dims.x, dims.y, dims.z) / 2.0
	ground_z = mins.z

	setup_render(args.size)
	cam = add_camera(CAM_FOV_DEG)

	human_x = maxs.x + HUMAN_BODY_RADIUS + 0.5 + asset_radius * 0.15
	add_human_silhouette(human_x, asset_center.y, ground_z)
	combo_min_x, combo_max_x = mins.x, max(maxs.x, human_x + HUMAN_BODY_RADIUS)
	combo_center = Vector(((combo_min_x + combo_max_x) / 2.0, (mins.y + maxs.y) / 2.0, asset_center.z))
	combo_radius = max((Vector((combo_max_x, maxs.y, maxs.z)) - combo_center).length,
		(Vector((combo_min_x, mins.y, mins.z)) - combo_center).length)
	add_ground(combo_center.x, combo_center.y, ground_z, combo_radius + asset_radius)

	tiles = []
	n_views = max(1, args.views)
	orbit_distance = _distance_for(combo_radius, CAM_FOV_DEG)
	for i in range(n_views):
		az = i * 360.0 / n_views
		cam.location = combo_center + _orbit_position(Vector((0, 0, 0)), orbit_distance, az, ORBIT_ELEVATION_DEG)
		_look_at(cam, combo_center)
		path = os.path.join(out_dir, f"view_{i:02d}.png")
		render_to(path)
		tiles.append((f"vue {i + 1}/{n_views} ({az:.0f}°)", path))

	top_distance = _distance_for(combo_radius, CAM_FOV_DEG)
	cam.location = combo_center + Vector((0.0001, 0.0, top_distance))
	_look_at(cam, combo_center)
	top_path = os.path.join(out_dir, "top.png")
	render_to(top_path)
	tiles.append(("dessus", top_path))

	closeup_distance = _distance_for(asset_radius, CAM_FOV_DEG)
	cam.location = asset_center + _orbit_position(Vector((0, 0, 0)), closeup_distance,
		CLOSEUP_AZIMUTH_DEG, CLOSEUP_ELEVATION_DEG)
	_look_at(cam, asset_center)
	closeup_path = os.path.join(out_dir, "closeup.png")
	render_to(closeup_path)
	tiles.append(("gros plan", closeup_path))

	calibration_label, calibration_path = render_calibration_swatch(out_dir, args.size)
	tiles.append((calibration_label, calibration_path))

	header = [
		os.path.basename(in_path),
		f"tris={tris}",
		f"dims={dims.x:.2f}x{dims.z:.2f}x{dims.y:.2f} m",
		f"matériaux: {', '.join(material_names) if material_names else 'aucun'}",
	]
	sheet_path = os.path.join(out_dir, f"{stem}_contact_sheet.png")
	build_contact_sheet(sheet_path, tiles, args.size, header)

	print(f"TURNTABLE_OK {len(tiles)} vues, tris={tris}")
	print(sheet_path)


if __name__ == "__main__":
	main()
