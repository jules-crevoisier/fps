"""ink_bake.py -- encrage BAKÉ DANS LA TEXTURE (art/style/toon_style.json v2
"ink_bake", le COEUR du style Borderlands identifié par la recherche lead :
voir toon_bd.gdshader/toon_style.json -- "textures peintes qui portent DÉJÀ
l'encre", pas une hachure procédurale en shader). Étant donné un modèle avec un
albédo peint (ex. un GLB Tripo Studio), produit une NOUVELLE texture qui ajoute :
  - edge_lines   : traits d'encre sur les arêtes/plis (courbure/pointiness).
  - cavity_lines : traits dans les creux (AO/cavité).
  - hatching     : hachures 45° (croisées sous `cross_below`) dans les zones
                   occluses, avec un léger jitter pour un rendu "à la main".
Exporte un nouveau GLB (texture ré-encrée) à côté de l'original -- jamais
d'écrasement du fichier source (même règle que tools/blender/ai_import_painted.py
et turntable.py : import en mémoire, jamais de modification sur disque du .glb
d'entrée).

CLI :
	blender -b --factory-startup --python-exit-code 1 -P art/style/blender/ink_bake.py -- \\
		--in assets/models/characters/verrou.glb --out assets/models/characters/verrou_inked.glb

Bake Cycles (pointiness + AO) : GPU si possible via
tools/blender/lib/gpu_compute.use_gpu_for_cycles (HIP sur le poste de dev, voir
son docstring) -- jamais un échec si aucun GPU compatible, repli CPU plafonné.
"""
from __future__ import annotations

import argparse
import os
import sys

_THIS_DIR = os.path.dirname(os.path.abspath(__file__))
if _THIS_DIR not in sys.path:
	sys.path.insert(0, _THIS_DIR)
from _style import hex_to_rgb, load_style, repo_root  # noqa: E402

_LIB_DIR = os.path.join(repo_root(), "tools", "blender", "lib")
if _LIB_DIR not in sys.path:
	sys.path.insert(0, _LIB_DIR)
import gpu_compute  # noqa: E402

import bpy  # noqa: E402
import numpy as np  # noqa: E402


# ============================================================================
#  CLI
# ============================================================================

def _parse_args() -> argparse.Namespace:
	argv = sys.argv
	argv = argv[argv.index("--") + 1:] if "--" in argv else []
	p = argparse.ArgumentParser(description="Encrage baké dans la texture (ink_bake.py)")
	p.add_argument("--in", dest="in_path", required=True, help="GLB source (jamais modifié)")
	p.add_argument("--out", dest="out_path", required=True, help="GLB de sortie (texture ré-encrée)")
	p.add_argument("--texture-size", dest="texture_size", type=int, default=0, help="Repli sur ink_bake.texture_size du JSON si omis")
	return p.parse_args(argv)


def _reset_scene() -> None:
	bpy.ops.wm.read_factory_settings(use_empty=True)


def _import_glb(path: str) -> list:
	before = set(bpy.context.scene.objects.keys())
	bpy.ops.import_scene.gltf(filepath=path)
	imported = [o for o in bpy.context.scene.objects if o.name not in before]
	return imported if imported else list(bpy.context.scene.objects)


# ============================================================================
#  Repérage de la texture peinte (Base Color) -- même convention que
#  Cartoon.texture_from_imported_material/ai_import_painted.py "matériau peint" :
#  CHAQUE image Base Color est conservée, jamais remplacée par une couleur plate.
# ============================================================================

def _find_albedo_node(mat: "bpy.types.Material"):
	if mat is None or mat.node_tree is None:
		return None
	principled = mat.node_tree.nodes.get("Principled BSDF")
	if principled is not None:
		link = principled.inputs["Base Color"].links
		if link and link[0].from_node.bl_idname == "ShaderNodeTexImage":
			return link[0].from_node
	for node in mat.node_tree.nodes:
		if node.bl_idname == "ShaderNodeTexImage" and node.image is not None:
			return node
	return None


# ============================================================================
#  Bakes Cycles (pointiness, AO) -- dans des images JETABLES, jamais l'albédo
#  lui-même (éviterait la dépendance circulaire "on lit l'image qu'on écrit").
# ============================================================================

def _select_only(obj: "bpy.types.Object") -> None:
	for o in bpy.context.scene.objects:
		o.select_set(o is obj)
	bpy.context.view_layer.objects.active = obj


def _read_pixels(img: "bpy.types.Image") -> np.ndarray:
	w, h = img.size[0], img.size[1]
	arr = np.empty(w * h * 4, dtype=np.float32)
	img.pixels.foreach_get(arr)
	return arr.reshape(h, w, 4)


def _bake_target_image(name: str, size: int) -> "bpy.types.Image":
	img = bpy.data.images.new(name, size, size, alpha=True, float_buffer=True)
	return img


def _set_active_bake_node(mat: "bpy.types.Material", node) -> None:
	for n in mat.node_tree.nodes:
		n.select = False
	node.select = True
	mat.node_tree.nodes.active = node


def _bake_pointiness(obj: "bpy.types.Object", mat: "bpy.types.Material", size: int) -> np.ndarray:
	"""Courbure/arêtes (art/style/toon_style.json ink_bake.edge_lines.source =
	"curvature+normal_edges") : Geometry > Pointiness -> ColorRamp linéaire
	(passthrough, la ramp existe pour rester réglable depuis Blender sans
	toucher au Python) -> Emission, bakée type EMIT."""
	nt = mat.node_tree
	geo = nt.nodes.new("ShaderNodeNewGeometry")
	ramp = nt.nodes.new("ShaderNodeValToRGB")
	ramp.color_ramp.elements[0].position = 0.0
	ramp.color_ramp.elements[1].position = 1.0
	emit = nt.nodes.new("ShaderNodeEmission")
	nt.links.new(geo.outputs["Pointiness"], ramp.inputs["Fac"])
	nt.links.new(ramp.outputs["Color"], emit.inputs["Color"])
	out_node = nt.nodes.get("Material Output")
	orig_from_socket = None
	for link in list(nt.links):
		if link.to_node == out_node and link.to_socket.identifier == "Surface":
			orig_from_socket = link.from_socket
	nt.links.new(emit.outputs["Emission"], out_node.inputs["Surface"])

	target = _bake_target_image(f"{mat.name}_pointiness", size)
	bake_node = nt.nodes.new("ShaderNodeTexImage")
	bake_node.image = target
	_set_active_bake_node(mat, bake_node)
	_select_only(obj)
	bpy.ops.object.bake(type="EMIT", margin=size // 128 or 1)
	result = _read_pixels(target)

	if orig_from_socket is not None:
		nt.links.new(orig_from_socket, out_node.inputs["Surface"])
	for n in (geo, ramp, emit, bake_node):
		nt.nodes.remove(n)
	bpy.data.images.remove(target)
	return result


def _bake_ao(obj: "bpy.types.Object", mat: "bpy.types.Material", size: int) -> np.ndarray:
	"""Occlusion ambiante (ink_bake.cavity_lines.source = "cavity/AO") : bake
	Cycles natif type AO, indépendant du graphe de nœuds (ne le touche pas)."""
	nt = mat.node_tree
	target = _bake_target_image(f"{mat.name}_ao", size)
	bake_node = nt.nodes.new("ShaderNodeTexImage")
	bake_node.image = target
	_set_active_bake_node(mat, bake_node)
	_select_only(obj)
	bpy.ops.object.bake(type="AO", margin=size // 128 or 1)
	result = _read_pixels(target)
	nt.nodes.remove(bake_node)
	bpy.data.images.remove(target)
	return result


# ============================================================================
#  Compositing numpy -- pur, testable sans Blender (voir tests si besoin futur).
# ============================================================================

def _dilate(mask: np.ndarray, radius_px: int) -> np.ndarray:
	"""Dilatation max approximative (pas de SciPy) : décale et prend le max sur
	un petit voisinage carré -- suffisant pour épaissir un trait de quelques px."""
	if radius_px <= 0:
		return mask
	out = mask.copy()
	for dy in range(-radius_px, radius_px + 1):
		for dx in range(-radius_px, radius_px + 1):
			if dx == 0 and dy == 0:
				continue
			shifted = np.roll(np.roll(mask, dy, axis=0), dx, axis=1)
			out = np.maximum(out, shifted)
	return out


def _smoothstep(edge0: float, edge1: float, x: np.ndarray) -> np.ndarray:
	"""`edge1` peut être < `edge0` (rampe DESCENDANTE -- ex. `cavity_mask`/
	`hatch_strength` ci-dessous, où une valeur AO plus FAIBLE doit donner PLUS
	d'encre) : seul un dénominateur VRAIMENT nul (edge0 == edge1) est un cas
	dégénéré à traiter à part -- un `max(denom, eps)` naïf casserait
	silencieusement toute rampe descendante en forçant un dénominateur minuscule
	POSITIF (repéré à l'exécution : ça sature `t` à 1.0 pour presque tout `x`,
	inversant complètement le masque -- voir git blame / le diagnostic qui a
	trouvé ce bug avant qu'il ne parte en production)."""
	denom = edge1 - edge0
	if abs(denom) < 1e-9:
		t = np.where(x < edge0, 0.0, 1.0).astype(np.float32)
	else:
		t = np.clip((x - edge0) / denom, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


# Pointiness Blender ~0.5 = plat ; pas de seuil dans le JSON (qui ne fixe que
# largeur/couleur/opacité/jitter) -- bande resserrée choisie ici, documentée :
# une arête franche dépasse largement 0.5, un léger galbe non.
_POINTINESS_EDGE_LOW = 0.58
_POINTINESS_EDGE_HIGH = 0.75


def _composite(albedo: np.ndarray, pointiness: np.ndarray, ao: np.ndarray, style: dict, texture_size: int) -> np.ndarray:
	ink_cfg = style.get("ink_bake", {})
	edge_cfg = ink_cfg.get("edge_lines", {})
	cavity_cfg = ink_cfg.get("cavity_lines", {})
	hatch_cfg = ink_cfg.get("hatching", {})
	ink_color = np.array(hex_to_rgb(edge_cfg.get("color", style.get("palette", {}).get("ink", "#0E0A12")))[:3], dtype=np.float32)

	h, w = albedo.shape[0], albedo.shape[1]
	scale = texture_size / 2048.0

	point_val = pointiness[..., 0]
	edge_mask = _smoothstep(_POINTINESS_EDGE_LOW, _POINTINESS_EDGE_HIGH, point_val)
	edge_radius = max(int(round(float(edge_cfg.get("width_px_2k", 3)) * scale * 0.5)), 0)
	edge_mask = _dilate(edge_mask, edge_radius)

	ao_val = ao[..., 0]
	cavity_threshold = float(cavity_cfg.get("threshold", 0.35))
	cavity_mask = _smoothstep(cavity_threshold, cavity_threshold - 0.15, ao_val)

	# Hachures 45°, croisées sous `cross_below` (JSON) -- jitter basse
	# fréquence (bruit lissé en amont, pas pixel à pixel : sinon "hand-drawn"
	# devient juste du bruit) pour casser la régularité d'un motif sinusoïdal pur.
	start = float(hatch_cfg.get("start", 0.55))
	end = float(hatch_cfg.get("end", 0.25))
	cross_below = float(hatch_cfg.get("cross_below", 0.35))
	spacing = max(float(hatch_cfg.get("spacing_px_2k", 9)) * scale, 1.0)
	jitter_amount = float(hatch_cfg.get("jitter", 0.3))
	angle = np.radians(float(hatch_cfg.get("angle_deg", 45.0)))

	rng = np.random.default_rng(1234)  # graine fixe : re-bake reproductible (pas de "jitter" qui change à chaque run).
	coarse = rng.uniform(-1.0, 1.0, size=(max(h // 32, 1), max(w // 32, 1))).astype(np.float32)
	jitter_field = np.kron(coarse, np.ones((int(np.ceil(h / coarse.shape[0])), int(np.ceil(w / coarse.shape[1])), ), dtype=np.float32))[:h, :w]
	jitter_field *= jitter_amount * spacing

	yy, xx = np.meshgrid(np.arange(h, dtype=np.float32), np.arange(w, dtype=np.float32), indexing="ij")

	def _stripe_mask(theta: float) -> np.ndarray:
		coord = xx * np.cos(theta) + yy * np.sin(theta) + jitter_field
		phase = np.mod(coord, spacing) / spacing
		# Trait fin centré sur chaque période (pas un dégradé plein) : ~35% du pas.
		return _smoothstep(0.42, 0.5, phase) * (1.0 - _smoothstep(0.5, 0.58, phase))

	hatch_strength = _smoothstep(start, end, ao_val)  # 0 côté lit (start), 1 côté occlus (end).
	stripes = _stripe_mask(angle)
	cross_gate = _smoothstep(cross_below, cross_below - 0.15, ao_val)
	stripes = np.maximum(stripes, _stripe_mask(angle + np.pi / 2.0) * cross_gate)
	hatch_mask = stripes * hatch_strength

	rgb = albedo[..., :3].copy()
	rgb = rgb * (1.0 - edge_mask[..., None] * float(edge_cfg.get("opacity", 0.9))) + ink_color[None, None, :] * (edge_mask[..., None] * float(edge_cfg.get("opacity", 0.9)))
	rgb = rgb * (1.0 - cavity_mask[..., None] * float(cavity_cfg.get("opacity", 0.85))) + ink_color[None, None, :] * (cavity_mask[..., None] * float(cavity_cfg.get("opacity", 0.85)))
	rgb = rgb * (1.0 - hatch_mask[..., None] * float(hatch_cfg.get("opacity", 0.6))) + ink_color[None, None, :] * (hatch_mask[..., None] * float(hatch_cfg.get("opacity", 0.6)))

	out = albedo.copy()
	out[..., :3] = np.clip(rgb, 0.0, 1.0)
	return out


# ============================================================================
#  Orchestration
# ============================================================================

def process_material(obj: "bpy.types.Object", mat: "bpy.types.Material", style: dict, texture_size: int) -> bool:
	albedo_node = _find_albedo_node(mat)
	if albedo_node is None or albedo_node.image is None:
		return False
	src_image = albedo_node.image
	if src_image.size[0] != texture_size or src_image.size[1] != texture_size:
		src_image.scale(texture_size, texture_size)
	albedo_arr = _read_pixels(src_image)

	pointiness_arr = _bake_pointiness(obj, mat, texture_size)
	ao_arr = _bake_ao(obj, mat, texture_size)
	result = _composite(albedo_arr, pointiness_arr, ao_arr, style, texture_size)

	baked_name = f"{mat.name}_inked"
	new_image = bpy.data.images.new(baked_name, texture_size, texture_size, alpha=True)
	new_image.pixels.foreach_set(result.astype(np.float32).ravel())
	new_image.update()
	albedo_node.image = new_image
	return True


def main() -> None:
	args = _parse_args()
	# ABSOLUS dès l'entrée : `bpy.ops.import_scene.gltf`/`export_scene.gltf`
	# résolvent un chemin relatif contre le cwd du process (vérifié
	# empiriquement), mais `Image.save()` sur une scène jamais enregistrée
	# (`read_factory_settings`) le résout AILLEURS (pas le même repère) --
	# constaté ici : le fichier PNG n'apparaissait jamais malgré un `save()`
	# sans erreur. Convertir une fois ici évite cette divergence partout.
	args.in_path = os.path.abspath(args.in_path)
	args.out_path = os.path.abspath(args.out_path)
	style = load_style()
	texture_size = args.texture_size or int(style.get("ink_bake", {}).get("texture_size", 2048))

	_reset_scene()
	objs = _import_glb(args.in_path)
	backend = gpu_compute.use_gpu_for_cycles(bpy.context.scene)
	bpy.context.scene.render.engine = "CYCLES"
	bpy.context.scene.cycles.samples = 16

	baked_materials = 0
	seen_materials: set = set()
	for obj in objs:
		if obj.type != "MESH":
			continue
		for slot in obj.material_slots:
			mat = slot.material
			if mat is None or mat.name in seen_materials:
				continue
			seen_materials.add(mat.name)
			if process_material(obj, mat, style, texture_size):
				baked_materials += 1

	out_dir = os.path.dirname(os.path.abspath(args.out_path))
	if out_dir:
		os.makedirs(out_dir, exist_ok=True)
	bpy.ops.export_scene.gltf(filepath=args.out_path, export_format="GLB")

	# Texture(s) baked(es) exportée(s) aussi en PNG à côté du GLB (contrat :
	# "exports GLB + texture") -- pratique pour une inspection rapide sans
	# dégager la texture d'un binaire GLB.
	base, _ = os.path.splitext(args.out_path)
	for mat_name in seen_materials:
		img = bpy.data.images.get(f"{mat_name}_inked")
		if img is None:
			continue
		png_path = f"{base}_{mat_name}_inked.png"
		img.filepath_raw = png_path
		img.file_format = "PNG"
		img.save()

	print(
		"ink_bake: %d materiau(x) inked (backend Cycles=%s, texture_size=%d) -> %s"
		% (baked_materials, backend, texture_size, args.out_path)
	)


if __name__ == "__main__":
	main()
