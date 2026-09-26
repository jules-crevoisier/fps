"""toon_bd_nodes.py -- groupe de nœuds "ToonBD" (EEVEE) qui reproduit dans
Blender la formule de art/style/toon_style.json v2 déjà implémentée côté moteur
par assets/shaders/toon_bd.gdshader (voir sa docstring pour la recherche/le
contrat) : sharpened_lambert (Shader to RGB d'un Diffuse BSDF -> Map Range
smoothstep terminator/sharpness), ombre teintée (Hue/Saturation), rim chaud
(Layer Weight, côté éclairé), spéculaire doux (Emission), + configuration de
scène (soleil, ambiance monde, étalonnage saturation/contraste). Contour fin :
Line Art (Grease Pencil), crease = normal_threshold_deg.

Usage direct (rarement -- voir plutôt bd_style_addon.py, qui expose ce module
via un panneau) :
	blender -b --factory-startup --python-exit-code 1 -P art/style/blender/toon_bd_nodes.py

Ce fichier n'a d'effet, seul, que sur la scène par défaut (cube témoin) -- il
existe pour être IMPORTÉ (`from toon_bd_nodes import ...`) par
bd_style_addon.py et par n'importe quel script Blender du pipeline (ex.
render_parity.py, qui a besoin de la même scène "parity_scene" que Godot).
"""
from __future__ import annotations

import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _style import hex_to_rgb, load_style, repo_root  # noqa: E402

import bpy  # noqa: E402

NODE_GROUP_NAME = "ToonBD"


# ============================================================================
#  Groupe de nœuds "ToonBD"
# ============================================================================

def _get_or_create_group() -> "bpy.types.ShaderNodeTree":
	group = bpy.data.node_groups.get(NODE_GROUP_NAME)
	if group is None:
		group = bpy.data.node_groups.new(NODE_GROUP_NAME, "ShaderNodeTree")
	return group


def _clear_group(group: "bpy.types.ShaderNodeTree") -> None:
	group.nodes.clear()
	# API interface de groupe (Blender 4.x+ : `interface`, plus l'ancien
	# `inputs`/`outputs` direct sur le NodeTree) -- vidée avant reconstruction
	# pour rester idempotent (rappelable sans accumuler des sockets en double).
	group.interface.clear()


def build_toon_bd_node_group(style: dict | None = None, force_rebuild: bool = False) -> "bpy.types.ShaderNodeTree":
	"""(Re)construit le groupe "ToonBD" depuis `style` (art/style/toon_style.json
	v2 par défaut). Entrées : Base Color / Alpha. Sortie : Shader (BSDF/Emission
	combinés, prêt à brancher sur un Material Output).

	`force_rebuild=False` (défaut) : si le groupe existe DÉJÀ (nœuds non vides),
	il est renvoyé TEL QUEL, jamais reconstruit -- `apply_toon_bd_to_material`
	appelle cette fonction UNE FOIS PAR MATÉRIAU, et `interface.clear()` +
	reconstruction invalide les sockets d'entrée de tout `ShaderNodeGroup` posé
	PAR UN MATÉRIAU PRÉCÉDENT (leurs `default_value` -- ex. la couleur de base
	d'une sphère -- retombent au défaut du NOUVEAU socket, jamais réappliqués) :
	constaté à l'exécution ("Appliquer à la sélection" sur plusieurs objets ne
	laissait couleur/texture QUE sur le DERNIER matériau traité, noir pour tous
	les précédents). `force_rebuild=True` (rechargement du JSON en cours de
	session éditeur, ex. bd_style_addon.py après une édition manuelle du
	fichier) reconstruit malgré tout -- accepte alors de devoir aussi rappeler
	`apply_toon_bd_to_material` sur chaque matériau déjà traité."""
	group = _get_or_create_group()
	if not force_rebuild and len(group.nodes) > 0:
		return group
	style = style or load_style()
	shading = style.get("shading", {})
	tint = style.get("shadow_tint", {})
	rim = style.get("rim", {})
	spec = style.get("specular", {})

	_clear_group(group)

	group.interface.new_socket("Base Color", in_out="INPUT", socket_type="NodeSocketColor")
	group.interface.new_socket("Alpha", in_out="INPUT", socket_type="NodeSocketFloat")
	group.interface.items_tree["Alpha"].default_value = 1.0
	group.interface.new_socket("Shader", in_out="OUTPUT", socket_type="NodeSocketShader")

	nodes = group.nodes
	links = group.links

	n_in = nodes.new("NodeGroupInput")
	n_in.location = (-1000, 0)
	n_out = nodes.new("NodeGroupOutput")
	n_out.location = (900, 0)

	# -- sharpened_lambert : Diffuse BSDF -> Shader to RGB (lecture N.L + ombre
	# portée EEVEE) -> Map Range resserré autour de `terminator`. ------------
	n_diffuse = nodes.new("ShaderNodeBsdfDiffuse")
	n_diffuse.location = (-800, 200)
	n_diffuse.inputs["Color"].default_value = (1.0, 1.0, 1.0, 1.0)  # neutre : la teinte vient du mix final.

	n_shader_to_rgb = nodes.new("ShaderNodeShaderToRGB")
	n_shader_to_rgb.location = (-600, 200)
	links.new(n_diffuse.outputs["BSDF"], n_shader_to_rgb.inputs["Shader"])

	n_map_range = nodes.new("ShaderNodeMapRange")
	n_map_range.location = (-400, 200)
	n_map_range.clamp = True
	half = float(shading.get("sharpness", 0.12)) * 0.5
	term = float(shading.get("terminator", 0.45))
	n_map_range.inputs["From Min"].default_value = term - half
	n_map_range.inputs["From Max"].default_value = term + half
	n_map_range.inputs["To Min"].default_value = 0.0
	n_map_range.inputs["To Max"].default_value = 1.0
	links.new(n_shader_to_rgb.outputs["Color"], n_map_range.inputs["Value"])

	# -- ombre teintée : Hue/Saturation sur l'albédo, mélangée par le facteur
	# ci-dessus (0 = ombre teintée x shadow_value, 1 = albédo plein). ---------
	n_hsv = nodes.new("ShaderNodeHueSaturation")
	n_hsv.location = (-800, -150)
	hue_deg = float(tint.get("hue_shift_deg", -18.0))
	# Hue/Saturation Blender : 0.5 = teinte inchangée (0 et 1 = ±180°), donc
	# décalage de -18° -> 0.5 - 0.05. `(deg/360) % 1` donnait 0.95 = +162°
	# (rouge -> sarcelle dans les ombres).
	n_hsv.inputs["Hue"].default_value = 0.5 + hue_deg / 360.0
	n_hsv.inputs["Saturation"].default_value = float(tint.get("saturation_mult", 1.25))
	n_hsv.inputs["Value"].default_value = float(shading.get("shadow_value", 0.42))
	links.new(n_in.outputs["Base Color"], n_hsv.inputs["Color"])

	n_ramp_mix = nodes.new("ShaderNodeMix")
	n_ramp_mix.location = (-200, 50)
	n_ramp_mix.data_type = "RGBA"
	links.new(n_map_range.outputs["Result"], n_ramp_mix.inputs["Factor"])
	links.new(n_hsv.outputs["Color"], n_ramp_mix.inputs["A"])
	links.new(n_in.outputs["Base Color"], n_ramp_mix.inputs["B"])

	# Emission (PAS Diffuse BSDF) : un Diffuse BSDF dépend de la GI/des sondes
	# de lumière d'EEVEE pour tout ce qui n'est pas éclairé en direct -- vérifié
	# à l'exécution (rendu de scène réelle : faces hors soleil direct rendues
	# NOIRES malgré `shadow_value`/l'ambiance monde configurés). Le shader Godot
	# (toon_bd.gdshader) ne dépend pas non plus de l'ambiance du moteur pour sa
	# rampe -- `shadow_col` y est une couleur directement AJOUTÉE à DIFFUSE_LIGHT,
	# jamais un BSDF qui attend un rebond indirect. Emission reproduit ça : la
	# rampe se suffit à elle-même, indépendante de tout GI/sonde à configurer.
	n_ramp_bsdf = nodes.new("ShaderNodeEmission")
	n_ramp_bsdf.location = (0, 50)
	links.new(n_ramp_mix.outputs["Result"], n_ramp_bsdf.inputs["Color"])

	# -- rim chaud, côté éclairé seulement : Layer Weight (Fresnel) x le même
	# facteur de terminator (lit_side_only), ajouté en Emission. -------------
	n_fresnel = nodes.new("ShaderNodeLayerWeight")
	n_fresnel.location = (-400, -400)
	n_fresnel.inputs["Blend"].default_value = 1.0 - min(max(float(rim.get("power", 4.0)) / 8.0, 0.0), 0.95)

	n_rim_ramp = nodes.new("ShaderNodeMapRange")
	n_rim_ramp.location = (-200, -400)
	n_rim_ramp.clamp = True
	rim_half = float(rim.get("softness", 0.08)) * 0.5
	rim_th = float(rim.get("threshold", 0.55))
	n_rim_ramp.inputs["From Min"].default_value = rim_th - rim_half
	n_rim_ramp.inputs["From Max"].default_value = rim_th + rim_half
	links.new(n_fresnel.outputs["Fresnel"], n_rim_ramp.inputs["Value"])

	n_rim_gate = nodes.new("ShaderNodeMath")
	n_rim_gate.location = (0, -400)
	n_rim_gate.operation = "MULTIPLY"
	links.new(n_rim_ramp.outputs["Result"], n_rim_gate.inputs[0])
	if rim.get("lit_side_only", True):
		links.new(n_map_range.outputs["Result"], n_rim_gate.inputs[1])
	else:
		n_rim_gate.inputs[1].default_value = 1.0

	n_rim_emission = nodes.new("ShaderNodeEmission")
	n_rim_emission.location = (200, -400)
	n_rim_emission.inputs["Color"].default_value = hex_to_rgb(rim.get("color", "#FFE9B8"))
	links.new(n_rim_gate.outputs["Value"], n_rim_emission.inputs["Strength"])
	rim_strength_val = float(rim.get("intensity", 0.25)) if rim.get("enabled", True) else 0.0
	n_rim_mul = nodes.new("ShaderNodeMath")
	n_rim_mul.location = (350, -400)
	n_rim_mul.operation = "MULTIPLY"
	n_rim_mul.inputs[1].default_value = rim_strength_val

	# -- spéculaire doux fixe : Glossy BSDF ajouté par-dessus. ---------------
	n_glossy = nodes.new("ShaderNodeBsdfGlossy")
	n_glossy.location = (0, -700)
	n_glossy.inputs["Color"].default_value = hex_to_rgb(spec.get("color", "#FFFFFF"))
	n_glossy.inputs["Roughness"].default_value = max(float(spec.get("softness", 0.12)), 0.01)

	n_add_rim = nodes.new("ShaderNodeAddShader")
	n_add_rim.location = (500, 0)
	links.new(n_ramp_bsdf.outputs["Emission"], n_add_rim.inputs[0])
	links.new(n_rim_emission.outputs["Emission"], n_add_rim.inputs[1])

	n_glossy_mix = nodes.new("ShaderNodeMixShader")
	n_glossy_mix.location = (650, 0)
	spec_fac = float(spec.get("intensity", 0.25)) if spec.get("enabled", True) else 0.0
	n_glossy_mix.inputs["Fac"].default_value = min(max(spec_fac, 0.0), 1.0)
	links.new(n_add_rim.outputs["Shader"], n_glossy_mix.inputs[1])
	links.new(n_glossy.outputs["BSDF"], n_glossy_mix.inputs[2])

	links.new(n_glossy_mix.outputs["Shader"], n_out.inputs["Shader"])
	return group


# ============================================================================
#  Application à un matériau/objet -- garde la texture peinte (Image Texture)
#  si le matériau en a déjà une, exactement comme ToonStyle.apply_to côté Godot.
# ============================================================================

def apply_toon_bd_to_material(mat: "bpy.types.Material", style: dict | None = None) -> None:
	if mat is None or mat.node_tree is None:
		return
	style = style or load_style()
	group_tree = build_toon_bd_node_group(style)

	nt = mat.node_tree
	existing_image_node = None
	existing_flat_color = None
	for node in list(nt.nodes):
		if node.bl_idname == "ShaderNodeTexImage" and node.image is not None:
			existing_image_node = node
			break
		# Repli couleur plate (sphère/cube de parity_scene, pas de texture) :
		# lu AVANT `nt.nodes.clear()` -- jamais `mat.diffuse_color` (propriété
		# héritée/legacy séparée, jamais synchronisée avec le Principled BSDF
		# posé par l'appelant -- vérifié à l'exécution : restait au gris par
		# défaut (0.8) quelle que soit la couleur réellement posée sur le nœud).
		if node.bl_idname == "ShaderNodeBsdfPrincipled":
			existing_flat_color = tuple(node.inputs["Base Color"].default_value)

	nt.nodes.clear()
	n_group = nt.nodes.new("ShaderNodeGroup")
	n_group.node_tree = group_tree
	n_group.location = (0, 0)

	n_output = nt.nodes.new("ShaderNodeOutputMaterial")
	n_output.location = (400, 0)
	nt.links.new(n_group.outputs["Shader"], n_output.inputs["Surface"])

	if existing_image_node is not None:
		n_tex = nt.nodes.new("ShaderNodeTexImage")
		n_tex.image = existing_image_node.image
		n_tex.location = (-400, 0)
		nt.links.new(n_tex.outputs["Color"], n_group.inputs["Base Color"])
		nt.links.new(n_tex.outputs["Alpha"], n_group.inputs["Alpha"])
	else:
		albedo = existing_flat_color if existing_flat_color is not None else (1.0, 1.0, 1.0, 1.0)
		n_group.inputs["Base Color"].default_value = tuple(albedo)


def apply_toon_bd_to_selection(style: dict | None = None) -> int:
	"""Applique le style BD à chaque matériau de chaque objet sélectionné --
	utilisé par le bouton "Appliquer le style BD à la sélection" de
	bd_style_addon.py. Renvoie le nombre de matériaux touchés."""
	style = style or load_style()
	count = 0
	for obj in bpy.context.selected_objects:
		if obj.type != "MESH":
			continue
		for slot in obj.material_slots:
			if slot.material is not None:
				apply_toon_bd_to_material(slot.material, style)
				count += 1
	return count


# ============================================================================
#  Scène : soleil, ambiance, étalonnage saturation/contraste.
# ============================================================================

def setup_scene(scene: "bpy.types.Scene | None" = None, style: dict | None = None) -> None:
	scene = scene or bpy.context.scene
	style = style or load_style()
	light_cfg = style.get("light", {})
	grading = style.get("grading", {})

	sun_obj = None
	for obj in scene.objects:
		if obj.type == "LIGHT" and obj.data.type == "SUN":
			sun_obj = obj
			break
	if sun_obj is None:
		sun_data = bpy.data.lights.new("BD_Sun", type="SUN")
		sun_obj = bpy.data.objects.new("BD_Sun", sun_data)
		scene.collection.objects.link(sun_obj)

	sun_obj.data.color = hex_to_rgb(light_cfg.get("sun_color", "#FFF1DC"))[:3]
	sun_obj.data.energy = float(light_cfg.get("sun_energy", 1.2)) * 3.0  # W/m^2 Blender vs facteur Godot.
	az = math.radians(float(light_cfg.get("sun_azimuth_deg", 135.0)))
	el = math.radians(float(light_cfg.get("sun_elevation_deg", 50.0)))
	# Blender : rotation X = élévation depuis le zénith (0 = pointe vers le bas
	# le long de -Z), Z = azimut -- même convention "vers le bas" que Godot
	# (`ToonStyle._sun_direction`), juste un jeu d'angles différent.
	sun_obj.rotation_euler = (math.pi / 2.0 - el, 0.0, az)
	sun_obj.data.use_shadow = bool(light_cfg.get("shadows", True))

	world = scene.world
	if world is None:
		world = bpy.data.worlds.new("BD_World")
		scene.world = world
	# `World.use_nodes` est dépréciée (les nœuds sont toujours actifs depuis
	# Blender 4.x, retrait prévu en 6.0, vérifié empiriquement sur ce build) --
	# `world.node_tree` existe donc déjà sans l'assigner.
	# Même partage que Godot (ToonStyle.setup_environment) : la caméra voit le
	# ciel `palette.sky_blue` (BG_COLOR), l'éclairage d'ambiance vient de
	# `ambient_color` x `ambient_strength` (AMBIENT_SOURCE_COLOR) -- d'où le
	# Light Path « Is Camera Ray » entre deux fonds.
	wnt = world.node_tree
	wnt.nodes.clear()
	n_amb = wnt.nodes.new("ShaderNodeBackground")
	n_amb.inputs["Color"].default_value = hex_to_rgb(light_cfg.get("ambient_color", "#5A6FA8"))
	n_amb.inputs["Strength"].default_value = float(light_cfg.get("ambient_strength", 0.35))
	n_sky = wnt.nodes.new("ShaderNodeBackground")
	n_sky.inputs["Color"].default_value = hex_to_rgb(style.get("palette", {}).get("sky_blue", "#6FB6FF"))
	n_sky.inputs["Strength"].default_value = 1.0
	n_path = wnt.nodes.new("ShaderNodeLightPath")
	n_mix = wnt.nodes.new("ShaderNodeMixShader")
	n_wout = wnt.nodes.new("ShaderNodeOutputWorld")
	wnt.links.new(n_path.outputs["Is Camera Ray"], n_mix.inputs["Fac"])
	wnt.links.new(n_amb.outputs["Background"], n_mix.inputs[1])
	wnt.links.new(n_sky.outputs["Background"], n_mix.inputs[2])
	wnt.links.new(n_mix.outputs["Shader"], n_wout.inputs["Surface"])

	scene.view_settings.view_transform = "Standard"
	# "Filmic/Standard" (contrat) : le JSON pousse déjà sa propre saturation
	# via le compositeur ci-dessous -- Filmic désaturerait/compresserait avant
	# ce grading, contredisant "couleurs qui crient" (même choix que
	# ToonStyle.environment() côté Godot, TONE_MAPPER_LINEAR plutôt que Filmic).
	engines = bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items.keys()
	scene.render.engine = "BLENDER_EEVEE_NEXT" if "BLENDER_EEVEE_NEXT" in engines else "BLENDER_EEVEE"
	_setup_grading_compositor(scene, grading)


def _setup_grading_compositor(scene: "bpy.types.Scene", grading: dict) -> None:
	"""Saturation/contraste (toon_style.json "grading") en post, via le
	compositeur -- Color Management n'a pas de slider saturation/contraste
	direct (seulement exposure/gamma), même intention que
	`ToonStyle.environment()` côté Godot (`adjustment_saturation/contrast`)."""
	# `Scene.use_nodes`/`Scene.node_tree` sont dépréciés sur ce build (retrait
	# prévu 6.0) -- `compositing_node_group` (un NodeTree "CompositorNodeTree"
	# comme un autre, vérifié empiriquement) est la nouvelle API.
	tree = scene.compositing_node_group
	if tree is None:
		tree = bpy.data.node_groups.new("BD_Compositing", "CompositorNodeTree")
		scene.compositing_node_group = tree
	tree.nodes.clear()
	tree.interface.clear()
	# Le compositeur est désormais un NodeTree "de groupe" comme un autre sur ce
	# build (plus de node `Composite` dédié -- vérifié empiriquement, "Node type
	# CompositorNodeComposite undefined") : la sortie se déclare via son
	# interface + un NodeGroupOutput, exactement comme un ShaderNodeTree.
	tree.interface.new_socket("Image", in_out="OUTPUT", socket_type="NodeSocketColor")
	n_out = tree.nodes.new("NodeGroupOutput")
	n_out.location = (400, 0)
	n_layers = tree.nodes.new("CompositorNodeRLayers")
	n_layers.location = (-400, 0)
	n_hsv = tree.nodes.new("CompositorNodeHueSat")
	n_hsv.location = (-100, 0)
	n_hsv.inputs["Saturation"].default_value = float(grading.get("saturation", 1.25))
	n_contrast = tree.nodes.new("CompositorNodeBrightContrast")
	n_contrast.location = (150, 0)
	# `contrast` du JSON est un facteur multiplicatif (1.0 = neutre) ; le node
	# Blender attend un delta autour de 0 -- (facteur - 1) x 100 reste dans la
	# plage utile du node pour les valeurs de ce JSON (1.0..1.5).
	n_contrast.inputs["Contrast"].default_value = (float(grading.get("contrast", 1.12)) - 1.0) * 100.0
	tree.links.new(n_layers.outputs["Image"], n_hsv.inputs["Image"])
	tree.links.new(n_hsv.outputs["Image"], n_contrast.inputs["Image"])
	tree.links.new(n_contrast.outputs["Image"], n_out.inputs["Image"])


# ============================================================================
#  Contour fin -- Line Art (Grease Pencil), crease = normal_threshold_deg.
# ============================================================================

def add_line_art_outline(obj: "bpy.types.Object", style: dict | None = None, render_height_px: int = 1080) -> "bpy.types.Object":
	"""Crée (ou retrouve, idempotent) un objet Grease Pencil "<obj.name>_LineArt"
	dont le modifier Line Art vise `obj` -- crease = `normal_threshold_deg`,
	épaisseur convertie de `width_px_at_1080p` vers l'unité Blender (mm) du
	modifier à `render_height_px`."""
	style = style or load_style()
	outline = style.get("outline", {})
	name = f"{obj.name}_LineArt"
	gp_obj = bpy.data.objects.get(name)
	if gp_obj is None:
		gp_data = bpy.data.grease_pencils_v3.new(name) if hasattr(bpy.data, "grease_pencils_v3") else bpy.data.grease_pencils.new(name)
		gp_obj = bpy.data.objects.new(name, gp_data)
		bpy.context.scene.collection.objects.link(gp_obj)

	color = hex_to_rgb(outline.get("color", "#0E0A12"))
	if gp_obj.data.materials:
		gp_mat = gp_obj.data.materials[0]
		gp_mat.grease_pencil.color = color
	else:
		gp_mat = bpy.data.materials.new(f"{name}_mat")
		bpy.data.materials.create_gpencil_data(gp_mat)
		gp_mat.grease_pencil.color = color
		gp_obj.data.materials.append(gp_mat)

	# "LINEART" (jamais "GREASE_PENCIL_LINEART"/"LINEART_GPENCIL" -- vérifiés
	# invalides à l'exécution sur ce build 5.2) : le modifier n'a PAS de
	# `thickness` (remplacé par `radius`, cohérent avec les traits GPv3 à base
	# de rayon plutôt que d'épaisseur en pixels) ni de couleur propre --
	# `target_material` pointe vers le matériau GP créé juste au-dessus.
	mod = gp_obj.modifiers.get("BD_LineArt")
	if mod is None:
		mod = gp_obj.modifiers.new("BD_LineArt", "LINEART")
	mod.source_type = "OBJECT"
	mod.source_object = obj
	mod.use_crease = True
	mod.crease_threshold = math.radians(float(outline.get("normal_threshold_deg", 30.0))) / math.pi  # 0..1, voir doc du modifier.
	mod.target_material = gp_mat
	mod.radius = _outline_radius_blender_units(outline, render_height_px)
	return gp_obj


def _outline_radius_blender_units(outline: dict, render_height_px: int) -> float:
	width_px = float(outline.get("width_px_at_1080p", 1.5)) * (render_height_px / 1080.0)
	min_px = float(outline.get("min_width_px", 1.0))
	# Rayon (pas diamètre) ~ mm ; conversion grossière px->mm (calibrée par
	# parity_scene, voir render_parity.py/compare_parity.py).
	return max(width_px, min_px) * 0.0005


if __name__ == "__main__":
	_style = load_style()
	build_toon_bd_node_group(_style)
	setup_scene(bpy.context.scene, _style)
	print("ToonBD node group + scene configured from", os.path.join(repo_root(), "art", "style", "toon_style.json"))
