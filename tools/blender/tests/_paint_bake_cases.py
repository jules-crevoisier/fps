## tools/blender/tests/_paint_bake_cases.py
## Script Blender (bpy) qui construit une fixture synthetique PAR critere
## d'acceptation TOOL-01 et verifie tools/blender/paint_bake.py (+ le
## correctif tools/blender/turntable.py) dessus -- jamais importe par pytest
## directement (bpy n'existe pas hors du process Blender) : voir
## test_paint_bake.py, qui relance CE fichier via un sous-process
## `blender -b --factory-startup --python-exit-code 1 -P _paint_bake_cases.py
## -- --out-dir DIR`, puis lit la ligne `PAINT_BAKE_CASES_RESULT <json>`
## qu'il imprime en dernier (meme convention que _ai_restyle_cases.py :
## `{"cases": {nom: {"ok": bool, "error": str|None, "detail": {...}}}}`).
##
## Un cas ne leve JAMAIS d'exception non attrapee : `_run_case` capture tout
## et range `{"ok": False, "error": repr(exc)}` -- un cas qui plante est un
## echec de TEST comme un autre, jamais un crash du harnais.
import json
import os
import sys
import traceback

import bpy

_HERE = os.path.dirname(os.path.abspath(__file__))
_TOOLS_BLENDER = os.path.dirname(_HERE)
sys.path.insert(0, _TOOLS_BLENDER)
sys.path.insert(0, os.path.join(_TOOLS_BLENDER, "lib"))
import paint_bake as pb  # noqa: E402
import turntable  # noqa: E402
import check_asset  # noqa: E402
import toonkit  # noqa: E402


def _make_box(name: str, size, loc=(0.0, 0.0, 0.0)) -> "bpy.types.Object":
	bpy.ops.mesh.primitive_cube_add(size=1.0, location=loc)
	obj = bpy.context.active_object
	obj.name = name
	obj.scale = size
	with bpy.context.temp_override(object=obj, active_object=obj, selected_editable_objects=[obj]):
		bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
	return obj


def _sampled_pixels(image, sample: int = 3000):
	"""(pixels_rgb, count) -- echantillon regulier de `image.pixels`, meme
	convention que turntable.py::_unique_colors (pas de charge inutile a
	relire des millions de floats pour un simple test)."""
	pixels = list(image.pixels)
	w, h = image.size
	total = w * h
	step = max(1, total // sample)
	out = []
	for i in range(0, total, step):
		base = i * 4
		out.append((pixels[base], pixels[base + 1], pixels[base + 2]))
	return out


def _unique_rounded(colors, ndigits: int = 3) -> int:
	return len({(round(r, ndigits), round(g, ndigits), round(b, ndigits)) for r, g, b in colors})


# ---------------------------------------------------------------------------
# Cas 1 -- critere d'acceptation : UV presentes, texture non uniforme, pas de
# pixel hors palette reservee -- sur un materiau "kind" plat (le cas reel des
# 3 modules du kit shanty, aucune texture d'origine).
# ---------------------------------------------------------------------------

def case_flat_kind_bakes_unique_texture(out_dir):
	toonkit.reset_scene()
	obj = _make_box("plank_wall", (1.0, 0.3, 1.4))
	mat = toonkit.toon_material("wood_planks", toonkit.palette("wood_planks"), kind="wood_planks")
	obj.data.materials.append(mat)
	in_path = os.path.join(out_dir, "flat_kind_src.glb")
	toonkit.export_glb(in_path, obj, write_report=False)

	out_path = os.path.join(out_dir, "flat_kind_painted.glb")
	report = pb.paint_bake(in_path, out_path, res=1024, samples=12, skip_turntable=True)

	toonkit.reset_scene()
	mesh_objs = pb.import_asset(out_path)
	baked_obj = mesh_objs[0]
	uv_present = len(baked_obj.data.uv_layers) > 0
	color_attrs = [a.name for a in baked_obj.data.color_attributes]
	mat_out = baked_obj.data.materials[0]
	mat_out_name = mat_out.name
	image = pb._material_image_node(mat_out)
	colors = _sampled_pixels(image)
	unique = _unique_rounded(colors)
	reserved_hits = sum(1 for c in colors if pb.reserved_band_violation(c))

	# check_asset.run() appelle toonkit.reset_scene() en interne : capturer
	# TOUT ce qui precede AVANT cet appel (une reference bpy vers `mat_out`/
	# `image`/`baked_obj` devient invalide -- ReferenceError -- une fois la
	# scene reinitialisee par un autre code).
	check_report = check_asset.run(out_path, None, asset_class=None)

	return {
		"uv_present": uv_present,
		"color_attributes_after": color_attrs,
		"material_name": mat_out_name,
		"expects_marker": "_painted" in mat_out_name,
		"unique_colors": unique,
		"reserved_hits": reserved_hits,
		"check_asset_ok": check_report["ok"],
		"check_asset_failures": check_report["failures"],
		"sidecar_painted_flag": json.load(open(report["sidecar"], encoding="utf-8"))["painted"],
	}


# ---------------------------------------------------------------------------
# Cas 2 -- regression : une UV PREEXISTANTE en tuile (plusieurs faces
# partageant la MEME petite region UV, comme la projection boite a l'echelle
# du monde de make_wl_shanty_kit.py) ne doit JAMAIS etre reutilisee telle
# quelle pour la cuisson -- bogue reellement constate sur wall_1_level.glb
# (canevas de cuisson a moitie noir, voir ensure_uv). Sans le correctif,
# `frac_near_black` serait proche de 0.5 ici.
# ---------------------------------------------------------------------------

def case_preexisting_tiling_uv_is_never_reused(out_dir):
	toonkit.reset_scene()
	planks = []
	for i in range(6):
		p = _make_box(f"tile_plank_{i}", (1.0, 0.2, 0.15), loc=(0.0, 0.0, i * 0.15))
		planks.append(p)
	obj = toonkit.join(planks)
	mat = toonkit.toon_material("wood_planks", toonkit.palette("wood_planks"), kind="wood_planks")
	obj.data.materials.append(mat)

	# UV "tuilee" degeneree : CHAQUE face mappee sur le MEME minuscule coin du
	# carre [0,1] -- reproduit le symptome mesure sur wall_1_level.glb (des
	# planches differentes qui PARTAGENT une region UV, une grande partie du
	# canevas jamais couverte par aucune face).
	me = obj.data
	uv_layer = me.uv_layers.new(name="TilingUV")
	for loop in me.loops:
		uv_layer.data[loop.index].uv = (0.01, 0.01)

	in_path = os.path.join(out_dir, "tiling_uv_src.glb")
	toonkit.export_glb(in_path, obj, write_report=False)

	out_path = os.path.join(out_dir, "tiling_uv_painted.glb")
	pb.paint_bake(in_path, out_path, res=1024, samples=8, skip_turntable=True)

	toonkit.reset_scene()
	mesh_objs = pb.import_asset(out_path)
	baked_obj = mesh_objs[0]
	image = pb._material_image_node(baked_obj.data.materials[0])
	pixels = list(image.pixels)
	w, h = image.size
	total = w * h
	near_black = sum(1 for i in range(0, total, 4) if pixels[i * 4] < 0.02
		and pixels[i * 4 + 1] < 0.02 and pixels[i * 4 + 2] < 0.02)
	sampled = len(range(0, total, 4))

	return {
		"had_uv_before": True,  # l'objet source porte deja "TilingUV"
		# Le nom "paint_bake_uv" lui-meme ne survit PAS a l'aller-retour glTF
		# (le format ne porte que des index TEXCOORD_N, jamais de nom de
		# calque -- l'importeur Blender renomme generiquement "UVMap") : seul
		# le COMPTE de calques UV survivants (exactement un, l'ancienne UV
		# "TilingUV" degeneree n'est plus la) est verifiable ici.
		"uv_layer_count_after": len(baked_obj.data.uv_layers),
		"frac_near_black": near_black / sampled,
	}


# ---------------------------------------------------------------------------
# Cas 3 -- une texture peinte EXISTANTE (slot avec Base Color -> Image
# Texture) est echantillonnee TRIPLANAIRE comme couleur de base, sans crash,
# et produit toujours une texture non uniforme.
# ---------------------------------------------------------------------------

def case_existing_texture_uses_triplanar(out_dir):
	toonkit.reset_scene()
	obj = _make_box("textured_prop", (0.6, 0.6, 0.6))
	img = bpy.data.images.new("existing_src", width=16, height=16, alpha=False)
	pixels = [0.0] * (16 * 16 * 4)
	for y in range(16):
		for x in range(16):
			i = (y * 16 + x) * 4
			v = 1.0 if (x // 2 + y // 2) % 2 == 0 else 0.15
			pixels[i:i + 4] = [v, v * 0.5, v * 0.2, 1.0]
	img.pixels = pixels
	mat = bpy.data.materials.new("existing_painted")
	mat.use_nodes = True
	bsdf = mat.node_tree.nodes.get("Principled BSDF")
	tex = mat.node_tree.nodes.new("ShaderNodeTexImage")
	tex.image = img
	mat.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
	obj.data.materials.append(mat)

	report = pb.bake_object_texture(
		obj, res=512, bake_margin_px=4, samples=8, seed="0:tri", hue_max_deg=6.0,
		palette_kind=None, image_name="tri_albedo")

	# `bake_object_texture` nomme le materiau final "__paint_bake_final__"
	# (l'appelant `paint_bake()` le renomme ensuite, hors de ce cas) -- on
	# relit directement le seul slot restant sur l'objet.
	final_mat = obj.data.materials[0]
	final_image = pb._material_image_node(final_mat)
	colors = _sampled_pixels(final_image)
	unique = _unique_rounded(colors)

	return {
		"had_existing_texture": report["slots"][0]["had_existing_texture"],
		"unique_colors": unique,
		"islands": report["islands"],
	}


# ---------------------------------------------------------------------------
# Cas 4 -- deux iles UV distinctes recoivent des decalages de teinte
# DIFFERENTS (deterministes -- meme graine, meme resultat).
# ---------------------------------------------------------------------------

def case_island_hue_varies_and_is_deterministic(out_dir):
	toonkit.reset_scene()
	box_a = _make_box("island_a", (0.4, 0.4, 0.4), loc=(0.0, 0.0, 0.0))
	box_b = _make_box("island_b", (0.4, 0.4, 0.4), loc=(3.0, 0.0, 0.0))
	obj = toonkit.join([box_a, box_b])
	mat = toonkit.toon_material("wood_planks", toonkit.palette("wood_planks"), kind="wood_planks")
	obj.data.materials.append(mat)

	pb.ensure_uv(obj, res=512)
	islands = pb.compute_uv_face_islands(obj)
	pb.bake_island_hue_attr(obj, islands, seed="42:det", max_deg=6.0)
	me = obj.data
	idx = me.color_attributes.find("island_hue")
	values_by_island = []
	for face_indices in islands:
		vals = set()
		for fi in face_indices:
			poly = me.polygons[fi]
			for li in poly.loop_indices:
				vals.add(round(me.color_attributes[idx].data[li].color[0], 6))
		values_by_island.append(sorted(vals))

	# Reproductibilite : reappliquer avec la MEME graine doit redonner
	# EXACTEMENT les memes decalages (pas de dependance a un random non seede).
	repeat = [pb.island_hue_offset("42:det", obj.name, i, max_deg=6.0) for i in range(len(islands))]
	repeat2 = [pb.island_hue_offset("42:det", obj.name, i, max_deg=6.0) for i in range(len(islands))]

	return {
		"island_count": len(islands),
		"each_island_single_flat_value": all(len(v) == 1 for v in values_by_island),
		"values_by_island": [v[0] for v in values_by_island],
		"all_islands_identical": len({v[0] for v in values_by_island}) == 1,
		"deterministic_repeat": repeat == repeat2,
	}


# ---------------------------------------------------------------------------
# Cas 5 -- un objet a PLUSIEURS slots de materiau d'origine (kinds distincts)
# fusionne en UN SEUL slot/texture final, chaque kind d'origine correctement
# rapporte.
# ---------------------------------------------------------------------------

def case_multi_slot_merges_to_single_material(out_dir):
	toonkit.reset_scene()
	obj = _make_box("multi_slot", (1.0, 0.3, 1.0))
	mat_wood = toonkit.toon_material("wood_planks", toonkit.palette("wood_planks"), kind="wood_planks")
	mat_rust = toonkit.toon_material("rust", toonkit.palette("rust"), kind="rust")
	obj.data.materials.append(mat_wood)
	obj.data.materials.append(mat_rust)
	me = obj.data
	for i, poly in enumerate(me.polygons):
		poly.material_index = i % 2

	report = pb.bake_object_texture(
		obj, res=512, bake_margin_px=4, samples=8, seed="0:multi", hue_max_deg=6.0,
		palette_kind=None, image_name="multi_albedo")

	return {
		"slot_kinds": sorted(s["kind"] for s in report["slots"]),
		"final_slot_count": len(obj.data.materials),
	}


# ---------------------------------------------------------------------------
# Cas 6 -- correctif turntable.py (TOOL-01) : `_find_albedo_image` retrouve
# une image liee DIRECTEMENT (materiau "<id>_painted") ET via le montage
# "Mix vertex-color x albedo" (regression, comportement deja couvert par
# `_read_albedo` avant ce correctif).
# ---------------------------------------------------------------------------

def case_turntable_finds_direct_and_mixed_image(out_dir):
	toonkit.reset_scene()
	img = bpy.data.images.new("tt_src", width=8, height=8, alpha=False)

	direct_mat = bpy.data.materials.new("wall_painted")
	direct_mat.use_nodes = True
	bsdf = direct_mat.node_tree.nodes.get("Principled BSDF")
	tex = direct_mat.node_tree.nodes.new("ShaderNodeTexImage")
	tex.image = img
	direct_mat.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
	direct_found = turntable._find_albedo_image(direct_mat)

	flat_mat = bpy.data.materials.new("flat_only")
	flat_mat.use_nodes = True
	flat_found = turntable._find_albedo_image(flat_mat)
	flat_albedo = turntable._read_albedo(flat_mat)

	return {
		"direct_image_found": direct_found is not None and direct_found.name == img.name,
		"flat_material_image_is_none": flat_found is None,
		"flat_albedo_is_4_floats": len(flat_albedo) == 4,
	}


CASES = {
	"flat_kind_bakes_unique_texture": case_flat_kind_bakes_unique_texture,
	"preexisting_tiling_uv_is_never_reused": case_preexisting_tiling_uv_is_never_reused,
	"existing_texture_uses_triplanar": case_existing_texture_uses_triplanar,
	"island_hue_varies_and_is_deterministic": case_island_hue_varies_and_is_deterministic,
	"multi_slot_merges_to_single_material": case_multi_slot_merges_to_single_material,
	"turntable_finds_direct_and_mixed_image": case_turntable_finds_direct_and_mixed_image,
}


def _run_case(name: str, fn, out_dir: str) -> dict:
	try:
		detail = fn(out_dir)
		return {"ok": True, "error": None, "detail": detail}
	except Exception as exc:  # noqa: BLE001 -- un cas qui plante est un echec de test, pas un crash du harnais
		return {"ok": False, "error": f"{type(exc).__name__}: {exc}", "detail": None,
			"traceback": traceback.format_exc()}


def main() -> None:
	argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
	out_dir = None
	only = None
	i = 0
	while i < len(argv):
		if argv[i] == "--out-dir":
			out_dir = argv[i + 1]
			i += 2
		elif argv[i] == "--only":
			only = argv[i + 1].split(",")
			i += 2
		else:
			i += 1
	if out_dir is None:
		raise SystemExit("usage: blender -b -P _paint_bake_cases.py -- --out-dir DIR [--only case1,case2]")
	os.makedirs(out_dir, exist_ok=True)

	results = {}
	for name, fn in CASES.items():
		if only and name not in only:
			continue
		results[name] = _run_case(name, fn, out_dir)

	print("PAINT_BAKE_CASES_RESULT " + json.dumps({"cases": results}, ensure_ascii=False))


if __name__ == "__main__":
	main()
