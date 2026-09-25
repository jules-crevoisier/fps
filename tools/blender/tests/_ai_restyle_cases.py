## tools/blender/tests/_ai_restyle_cases.py
## Script Blender (bpy) qui construit une fixture synthetique PAR critere
## d'acceptation A3D-12 et verifie tools/blender/ai_restyle.py dessus — jamais
## importe par pytest directement (bpy n'existe pas hors du process Blender) :
## voir test_ai_restyle.py, qui relance CE fichier via un sous-process
## `blender -b --factory-startup --python-exit-code 1 -P _ai_restyle_cases.py
## -- --out-dir DIR`, puis lit la ligne `AI_RESTYLE_CASES_RESULT <json>`
## qu'il imprime en dernier (un objet `{"cases": {nom: {"ok": bool, "error":
## str|None, "detail": {...}}}}`) pour transformer chaque cas en assertion
## pytest normale.
##
## Un cas ne leve JAMAIS d'exception non attrapee : `_run_case` capture tout
## et range `{"ok": False, "error": repr(exc)}` — un cas qui plante est un
## echec de TEST comme un autre, jamais un crash du harnais.
import bmesh
import json
import os
import sys
import traceback

import bpy
from mathutils import Vector

_HERE = os.path.dirname(os.path.abspath(__file__))
_TOOLS_BLENDER = os.path.dirname(_HERE)
sys.path.insert(0, _TOOLS_BLENDER)
sys.path.insert(0, os.path.join(_TOOLS_BLENDER, "lib"))
import ai_restyle  # noqa: E402
import check_asset  # noqa: E402
import toonkit  # noqa: E402


def _make_box(name: str, dims, loc) -> "bpy.types.Object":
	"""Boite mesh nommee `name`, dimensions `dims` (X,Y,Z, metres), centree en
	`loc` — transform applique tout de suite (echelle/position bakees dans la
	geometrie) pour que les coordonnees ecrites ensuite (boites de pieces,
	positions de marqueurs) soient dans le MEME repere local que celui lu par
	`ai_restyle` (voir `_bbox_diagonal`/`separate_parts`)."""
	bpy.ops.mesh.primitive_cube_add(size=1.0, location=loc)
	obj = bpy.context.active_object
	obj.name = name
	obj.scale = dims
	with bpy.context.temp_override(object=obj, active_object=obj, selected_editable_objects=[obj]):
		bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
	return obj


def _set_single_material(obj, mat) -> None:
	"""Assigne `mat` comme UNIQUE materiau de `obj` et force TOUS les polygones
	a le referencer explicitement (slot 0) — un modificateur BOOLEAN applique
	peut laisser un slot 0 fantome (`None`) devant un materiau ajoute apres
	coup, avec des `material_index` restes a 0 (verifie par sondage, voir
	rapport de tache) : sans cette remise a plat, la texture/couleur de sortie
	ne serait JAMAIS celle qu'on croit avoir posee."""
	me = obj.data
	me.materials.clear()
	me.materials.append(mat)
	for p in me.polygons:
		p.material_index = 0
	me.update()


def _welded_boundary_edges(me) -> int:
	"""Nombre d'aretes de bord sur une COPIE ressoudee de `me` (memes raisons
	que check_asset.py::check_object : un export/reimport glTF duplique les
	sommets a chaque arete dure/frontiere de materiau, ce qui ferait passer un
	maillage plat mais REELLEMENT ferme pour "troue" si on comptait les bords
	sur la mesh telle quelle)."""
	bm = bmesh.new()
	bm.from_mesh(me)
	bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-4)
	boundary = sum(1 for e in bm.edges if len(e.link_faces) == 1)
	bm.free()
	return boundary


def _welded_nonmanifold_edges(me) -> int:
	"""Nombre d'aretes partagees par >= 3 faces (non-manifold) sur une COPIE
	ressoudee de `me` — meme raison de resoudre d'abord que
	`_welded_boundary_edges` (doublons de sommets a l'export/reimport glTF),
	meme mesure que check_asset.py::CHK (bad_nonmanifold_edges) et que le
	garde-fou de `ai_restyle._fill_holes` (A3D-15)."""
	bm = bmesh.new()
	bm.from_mesh(me)
	bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-4)
	bad = sum(1 for e in bm.edges if len(e.link_faces) >= 3)
	bm.free()
	return bad


# ============================================================================
# Cas 1 — quantification Lab PAR FACE + COLOR_0 + aucune image + check_asset PASS
# ============================================================================

_KINDS_ORDER = ["wood_planks", "rust", "painted_metal", "dirty_glass"]
_FACE_KIND_BY_AXIS = {
	(1, 0, 0): "wood_planks",
	(-1, 0, 0): "rust",
	(0, 1, 0): "painted_metal",
	(0, -1, 0): "dirty_glass",
	(0, 0, 1): "wood_planks",
	(0, 0, -1): "rust",
}


def _closest_axis(normal) -> tuple:
	ax = max(range(3), key=lambda i: abs(normal[i]))
	sign = 1 if normal[ax] > 0 else -1
	v = [0, 0, 0]
	v[ax] = sign
	return tuple(v)


def _build_fake_tripo_cube():
	"""Cube UNIQUE materiau texture (simule un bake Tripo) dont CHAQUE face
	pointe (via son UV, un texel par face) vers une couleur EXACTEMENT egale a
	la palette d'un kind connu different — le cas que la quantification par
	MATERIAU (A3D-07) ne pouvait pas resoudre (un seul materiau -> un seul
	kind pour tout l'objet) et que la quantification PAR FACE (A3D-12) doit
	resoudre en 4 kinds distincts (2 faces partagees en double, pour verifier
	le dedoublonnage). Renvoie (obj, face_kind_by_axis)."""
	bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0))
	obj = bpy.context.active_object
	obj.name = "FakeTripoProp"
	me = obj.data
	# `primitive_cube_add` genere DEJA une UV par defaut (deroule "boite"
	# standard, `calc_uvs=True` implicite) : creer une DEUXIEME UV layer ici
	# la renommerait en "UVMap.001" et laisserait la premiere (le deroule
	# standard, sans rapport avec nos blocs de texel) ACTIVE — `_face_uv_
	# centroid`/`restyle_materials` echantillonnent tous deux `uv_layers.
	# active` : reutiliser puis rendre explicitement ACTIVE la couche
	# existante evite cette UV fantome (verifie par sondage, voir rapport de
	# tache).
	uv_layer = me.uv_layers.active or me.uv_layers.new(name="UVMap")
	me.uv_layers.active = uv_layer

	w = len(_KINDS_ORDER)
	img = bpy.data.images.new("FakeTripoBake", width=w, height=1, alpha=False)
	pixels = []
	for kind in _KINDS_ORDER:
		c = toonkit.palette(kind)
		pixels.extend([c[0], c[1], c[2], 1.0])
	img.pixels = pixels

	mat = bpy.data.materials.new("TripoBakedMaterial")
	mat.use_nodes = True
	bsdf = mat.node_tree.nodes.get("Principled BSDF")
	tex_node = mat.node_tree.nodes.new("ShaderNodeTexImage")
	tex_node.image = img
	mat.node_tree.links.new(tex_node.outputs["Color"], bsdf.inputs["Base Color"])
	_set_single_material(obj, mat)

	for poly in me.polygons:
		axis = _closest_axis(poly.normal)
		kind = _FACE_KIND_BY_AXIS[axis]
		col = _KINDS_ORDER.index(kind)
		u, v = (col + 0.5) / w, 0.5
		for li in poly.loop_indices:
			uv_layer.data[li].uv = (u, v)
	me.update()
	return obj, dict(_FACE_KIND_BY_AXIS)


def case_face_quantization_unit(out_dir: str) -> dict:
	"""Teste `ai_restyle.restyle_materials` DIRECTEMENT (avant biseau/decimation,
	qui redistribueraient les material_index de facon non triviale) : un SEUL
	materiau texture d'entree doit ressortir en 4 materiaux de sortie distincts
	(un par kind reellement present), chaque face assignee au kind attendu par
	son axe, et jamais a la texture/couleur d'origine."""
	toonkit.reset_scene()
	obj, expected_by_axis = _build_fake_tripo_cube()
	report_slots = []
	ai_restyle.restyle_materials(obj, report_slots)

	out_kinds = sorted(m.name for m in obj.data.materials if m is not None)
	expected_kinds = sorted(set(expected_by_axis.values()))
	assert out_kinds == expected_kinds, f"kinds obtenus {out_kinds} != attendus {expected_kinds}"

	mismatches = []
	for poly in obj.data.polygons:
		axis = _closest_axis(poly.normal)
		expected_kind = expected_by_axis[axis]
		mat = obj.data.materials[poly.material_index]
		if mat is None or mat.name != expected_kind:
			mismatches.append((axis, expected_kind, mat.name if mat else None))
	assert not mismatches, f"face(s) mal classee(s) : {mismatches}"

	counts = {s["assigned_kind"]: s["face_count"] for s in report_slots}
	assert counts == {"wood_planks": 2, "rust": 2, "painted_metal": 1, "dirty_glass": 1}, counts
	max_delta_e = max(s["avg_delta_e_sample_to_kind"] for s in report_slots)
	assert max_delta_e < 0.5, f"delta E inattendu (texel != palette exacte ?) : {max_delta_e}"

	return {"out_kinds": out_kinds, "report_slots": report_slots}


def case_full_pipeline_no_images_color0_check_asset(out_dir: str) -> dict:
	"""Pipeline complet (`ai_restyle.restyle`) sur la meme fixture que
	ci-dessus, exportee comme un vrai .glb "brut" d'entree : verifie qu'aucune
	image ne survit dans la sortie, que COLOR_0 (masque unifie) est present,
	et que check_asset.py PASSE (budget de la famille)."""
	toonkit.reset_scene()
	obj, expected_by_axis = _build_fake_tripo_cube()
	raw_path = os.path.join(out_dir, "case1_raw.glb")
	toonkit.export_glb(raw_path, obj, write_report=False)

	out_path = os.path.join(out_dir, "case1_out.glb")
	budget = ai_restyle.FAMILY_BUDGETS["props_small"]
	report = ai_restyle.restyle(raw_path, out_path, budget, "props_small", skip_turntable=True)

	expected_kinds = sorted(set(expected_by_axis.values()))
	assert sorted(report["assigned_kinds"]) == expected_kinds, report["assigned_kinds"]
	for kind in report["assigned_kinds"]:
		assert kind in ai_restyle.CANDIDATE_KINDS
		assert not ai_restyle._in_reserved_band(toonkit.palette(kind)), (
			f"kind {kind!r} dans une bande de teinte reservee")

	toonkit.reset_scene()
	bpy.ops.import_scene.gltf(filepath=out_path)
	# "Render Result"/"Viewer Node" sont des data-blocks Image INTERNES a
	# Blender (toujours presents, quoi qu'on importe/exporte — rien a voir
	# avec une texture Tripo) : seule une image en plus de ces deux-la
	# prouverait une fuite reelle.
	leaked_images = [i.name for i in bpy.data.images if i.name not in ("Render Result", "Viewer Node")]
	assert not leaked_images, f"image(s) qui fuient dans la sortie : {leaked_images}"
	mesh_objs = [o for o in bpy.context.scene.objects if o.type == 'MESH']
	assert len(mesh_objs) == 1
	color0_present = len(mesh_objs[0].data.color_attributes) > 0
	assert color0_present, "COLOR_0 (masque unifie) absent apres reimport"

	check_report = check_asset.run(out_path, budget_tris=budget, asset_class=None)
	assert check_report["ok"], f"check_asset ECHEC : {check_report['failures']}"

	return {
		"assigned_kinds": report["assigned_kinds"],
		"color0_present": color0_present,
		"check_asset_ok": check_report["ok"],
		"check_asset_failures": check_report["failures"],
	}


# ============================================================================
# Cas 2 — arme de test : pieces mobiles separees sans trou visible + Muzzle
# ============================================================================

def _build_fake_weapon():
	"""Corps + chargeur : DEUX boites unies (`bpy.ops.object.modifier_apply`
	BOOLEAN 'EXACT', deja verifie etanche/manifold par sondage) — le chargeur
	depasse sous le corps, boite bien separee dans l'espace pour que
	`separate_parts` (boite locale) le decoupe sans ambiguite."""
	body = _make_box("Body", (0.6, 0.15, 0.15), (0, 0, 0))
	mag = _make_box("Mag", (0.15, 0.08, 0.2), (0.1, 0, -0.175))
	mod = body.modifiers.new("union", type='BOOLEAN')
	mod.operation = 'UNION'
	mod.object = mag
	mod.solver = 'EXACT'
	with bpy.context.temp_override(object=body, active_object=body, selected_editable_objects=[body]):
		bpy.ops.object.modifier_apply(modifier=mod.name)
	bpy.data.objects.remove(mag, do_unlink=True)
	mat = toonkit.toon_material("painted_metal", toonkit.palette("painted_metal"), kind="painted_metal")
	_set_single_material(body, mat)
	return body


_WEAPON_PARTS_SPEC = {
	"parts": [{"name": "magazine", "box_min": [0.0, -0.05, -0.3], "box_max": [0.2, 0.05, -0.08]}],
	"markers": [
		{"name": "Muzzle", "position": [0.3, 0.0, 0.0]},
		{"name": "Foregrip", "position": [0.05, 0.0, 0.09]},
	],
}


def case_weapon_parts_and_markers(out_dir: str) -> dict:
	toonkit.reset_scene()
	body = _build_fake_weapon()
	raw_path = os.path.join(out_dir, "case2_raw.glb")
	toonkit.export_glb(raw_path, body, write_report=False)

	out_path = os.path.join(out_dir, "case2_weapon.glb")
	budget = ai_restyle.FAMILY_BUDGETS["weapons"]
	report = ai_restyle.restyle(
		raw_path, out_path, budget, "weapons", skip_turntable=True,
		parts_spec=_WEAPON_PARTS_SPEC,
	)
	assert report["parts"] == ["magazine"], report["parts"]
	assert sorted(report["markers"]) == ["Foregrip", "Muzzle"], report["markers"]

	toonkit.reset_scene()
	bpy.ops.import_scene.gltf(filepath=out_path)
	objs_by_type = {}
	for o in bpy.context.scene.objects:
		objs_by_type.setdefault(o.type, []).append(o.name)

	assert "magazine" in objs_by_type.get("MESH", []), objs_by_type
	assert len(objs_by_type.get("MESH", [])) == 2, objs_by_type  # corps + chargeur, JAMAIS fondus en un seul
	assert "Muzzle" in objs_by_type.get("EMPTY", []), objs_by_type
	assert "Foregrip" in objs_by_type.get("EMPTY", []), objs_by_type

	holes = {}
	for o in bpy.context.scene.objects:
		if o.type == 'MESH':
			holes[o.name] = _welded_boundary_edges(o.data)
	assert all(n == 0 for n in holes.values()), f"trou(s) visible(s) apres separation : {holes}"

	check_report = check_asset.run(out_path, budget_tris=budget, asset_class=None)
	assert check_report["ok"], f"check_asset ECHEC sur l'arme separee : {check_report['failures']}"

	return {"nodes_by_type": objs_by_type, "boundary_edges": holes, "check_asset_ok": check_report["ok"]}


# ============================================================================
# Cas 2bis — A3D-15 : separer une piece decoupee dans une surface COURBE (donc
# un contour de coupe NON PLANAIRE, et ici en plus DEUX boucles de bord
# distinctes de chaque cote, un tore traverse deux fois par la meme boite) ne
# doit produire NI trou visible NI arete non-manifold — releve concret de
# tache (wpn_magnum : barillet/chien, wpn_marqueur : capuchon, wpn_pistolet :
# chargeur/culasse, toutes des pieces decoupees dans une surface courbe).
# ============================================================================

def _build_fake_curved_weapon():
	"""Tore (surface a courbure variable, jamais plane) traverse par une boite
	fine qui coupe l'anneau en DEUX endroits a la fois (deux boucles de bord
	distinctes de chaque cote de la coupe) — le contour le plus difficile a
	reboucher proprement avec un simple n-gon (`holes_fill`), largement plus
	exigeant que le corps+chargeur en boites planes de `_build_fake_weapon`."""
	bpy.ops.mesh.primitive_torus_add(
		major_radius=0.08, minor_radius=0.03, major_segments=24, minor_segments=12, location=(0, 0, 0.03))
	torus = bpy.context.active_object
	torus.name = "Body"
	with bpy.context.temp_override(object=torus, active_object=torus, selected_editable_objects=[torus]):
		bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
	mat = toonkit.toon_material("painted_metal", toonkit.palette("painted_metal"), kind="painted_metal")
	_set_single_material(torus, mat)
	return torus


_CURVED_WEAPON_PARTS_SPEC = {
	"parts": [{"name": "barillet", "box_min": [-0.02, -0.11, -0.11], "box_max": [0.02, 0.11, 0.11]}],
	"markers": [{"name": "Muzzle", "position": [0.1, 0.0, 0.03]}],
}


def case_curved_part_separation_stays_manifold(out_dir: str) -> dict:
	"""A3D-15 : separer une piece dont le contour de coupe est NON PLANAIRE et
	forme PLUSIEURS boucles de bord distinctes (voir `_build_fake_curved_weapon`)
	ne doit laisser NI trou (bord ouvert) NI arete non-manifold sur le corps
	restant NI sur la piece detachee, apres reboucher+trianguler
	(`ai_restyle._fill_holes`)."""
	toonkit.reset_scene()
	body = _build_fake_curved_weapon()
	raw_path = os.path.join(out_dir, "case2bis_raw.glb")
	toonkit.export_glb(raw_path, body, write_report=False)

	out_path = os.path.join(out_dir, "case2bis_curved.glb")
	budget = ai_restyle.FAMILY_BUDGETS["weapons"]
	report = ai_restyle.restyle(
		raw_path, out_path, budget, "weapons", skip_turntable=True,
		parts_spec=_CURVED_WEAPON_PARTS_SPEC,
	)
	assert report["parts"] == ["barillet"], report["parts"]

	toonkit.reset_scene()
	bpy.ops.import_scene.gltf(filepath=out_path)
	mesh_objs = [o for o in bpy.context.scene.objects if o.type == 'MESH']
	assert len(mesh_objs) == 2, [o.name for o in mesh_objs]  # corps + barillet, jamais fondus

	boundary = {o.name: _welded_boundary_edges(o.data) for o in mesh_objs}
	nonmanifold = {o.name: _welded_nonmanifold_edges(o.data) for o in mesh_objs}
	assert all(n == 0 for n in boundary.values()), f"trou(s) visible(s) apres separation : {boundary}"
	assert all(n == 0 for n in nonmanifold.values()), (
		f"arete(s) non-manifold apres reboucher+trianguler : {nonmanifold}")

	check_report = check_asset.run(out_path, budget_tris=budget, asset_class=None)
	assert check_report["ok"], f"check_asset ECHEC sur la piece courbe separee : {check_report['failures']}"

	return {"boundary_edges": boundary, "nonmanifold_edges": nonmanifold, "check_asset_ok": check_report["ok"]}


# ============================================================================
# Cas 3 — garde-fou volume : rejet > 10 % de perte de volume clos
# ============================================================================

def _cube_mesh(name: str, size: float) -> "bpy.types.Mesh":
	bpy.ops.mesh.primitive_cube_add(size=size, location=(0, 0, 0))
	obj = bpy.context.active_object
	me = obj.data.copy()
	bpy.data.objects.remove(obj, do_unlink=True)
	return me


def case_volume_guard_unit(out_dir: str) -> dict:
	"""Teste `ai_restyle._remesh_result_acceptable` ISOLEMENT (avant/apres
	synthetiques, tous deux REELLEMENT etanches/manifold/un seul ilot — seul
	le VOLUME change) : un cube retreci de 10 % par axe (perte de volume
	~27,1 %, > 10 %) doit etre REJETE ; retreci de 3 % par axe (perte
	~8,7 %, < 10 %) doit etre ACCEPTE. Isole la condition de volume (A3D-12)
	des conditions d'etendue/ilots deja existantes (toutes deux passent dans
	les deux sous-cas ici, ratio d'etendue 0.9 et 0.97 > 0.5)."""
	toonkit.reset_scene()
	before = _cube_mesh("Before", 1.0)
	before_extent = ai_restyle._mesh_bbox_diagonal(before)
	volume_before = ai_restyle._mesh_volume(before)

	after_reject = _cube_mesh("AfterReject", 0.9)  # perte de volume ~27,1 %
	after_accept = _cube_mesh("AfterAccept", 0.97)  # perte de volume ~8,7 %

	volume_reject = ai_restyle._mesh_volume(after_reject)
	volume_accept = ai_restyle._mesh_volume(after_accept)
	loss_reject = 1.0 - volume_reject / volume_before
	loss_accept = 1.0 - volume_accept / volume_before

	rejected = ai_restyle._remesh_result_acceptable(1, before_extent, volume_before, after_reject)
	accepted = ai_restyle._remesh_result_acceptable(1, before_extent, volume_before, after_accept)

	assert loss_reject > 0.10, f"fixture invalide : perte {loss_reject} devrait depasser 10 %"
	assert loss_accept < 0.10, f"fixture invalide : perte {loss_accept} devrait rester sous 10 %"
	assert rejected is False, f"une perte de volume de {loss_reject:.3f} (> 10 %) aurait du etre rejetee"
	assert accepted is True, f"une perte de volume de {loss_accept:.3f} (< 10 %) n'aurait pas du etre rejetee"

	return {
		"volume_before": volume_before,
		"loss_reject": loss_reject, "loss_accept": loss_accept,
		"rejected": rejected, "accepted": accepted,
	}


def _build_hollow_crate_with_debris():
	"""« Caisse trouee » (docs/assets/ASSET_PLAN.md, notes A3D-12) : une grande
	boite dont la face du dessus est entierement absente (grand trou beant,
	faces restantes subdivisees pour rester l'ilot dominant en NOMBRE de
	faces) + un petit debris deja etanche, DISTANT (jamais recolle par
	`merge_by_distance`, ni retire par `remove_isolated_islands` — 6 faces >=
	ISLAND_MIN_FACE_ABSOLUTE). Reproduit le mode de defaillance documente dans
	`_voxel_remesh` (point 3 de sa docstring) : a verifier par sondage reel
	(voir rapport de tache) que le Remesh Voxel global, applique a CET
	assemblage precis, ne reconstruit QUE le petit debris et fait disparaitre
	la caisse trouee — auquel cas la perte de volume mesuree depasse tres
	largement 10 % et `ensure_watertight` doit rejeter (RuntimeError), jamais
	exporter une caisse amputee en silence."""
	bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0))
	crate = bpy.context.active_object
	crate.name = "Crate"
	with bpy.context.temp_override(object=crate, active_object=crate, selected_editable_objects=[crate]):
		bpy.ops.object.mode_set(mode='EDIT')
		bm = bmesh.from_edit_mesh(crate.data)
		bm.faces.ensure_lookup_table()
		top = [f for f in bm.faces if f.normal.z > 0.9]
		bmesh.ops.delete(bm, geom=top, context='FACES')
		bmesh.update_edit_mesh(crate.data)
		bpy.ops.mesh.select_all(action='SELECT')
		bpy.ops.mesh.subdivide(number_cuts=1)
		bpy.ops.object.mode_set(mode='OBJECT')

	bpy.ops.mesh.primitive_cube_add(size=0.1, location=(5, 5, 5))
	debris = bpy.context.active_object
	debris.name = "Debris"

	joined = toonkit.join([crate, debris])
	joined.name = "HollowCrate"
	mat = toonkit.toon_material("cracked_concrete", toonkit.palette("cracked_concrete"), kind="cracked_concrete")
	_set_single_material(joined, mat)
	return joined


def case_hollow_crate_watertight_warning(out_dir: str) -> dict:
	"""A3D-15 : le meme mode de defaillance de `_voxel_remesh` que ci-dessus
	(reconstruit uniquement le petit debris deja clos, perd la majorite du
	volume de la caisse trouee, rejete a CHAQUE taille de voxel tentee) ne
	doit PLUS jamais faire lever `ensure_watertight` — releve de tache A3D-13,
	confirme sur les Smart Mesh deja propres/bas-poly de la vague 1, dont
	l'echec ne venait jamais d'un maillage reellement fragmente/ampute mais de
	ce mode de defaillance precis. `ensure_watertight` doit desormais renvoyer
	`remesh_failed=True` et conserver la geometrie D'ORIGINE de la caisse
	(meme non etanche) plutot que de bloquer tout le pipeline. Le petit debris
	DISTANT reste neanmoins retire par `_drop_floating_islands` — un nettoyage
	INDEPENDANT du remesh (un ilot loin du corps principal est jete qu'il soit
	etanche ou non), pas quelque chose que la tolerance A3D-15 doit preserver."""
	toonkit.reset_scene()
	obj = _build_hollow_crate_with_debris()
	faces_before = len(obj.data.polygons)
	volume_before = ai_restyle._mesh_volume(obj.data)
	assert not ai_restyle._is_watertight(obj.data), "fixture invalide : la caisse trouee devrait avoir un bord ouvert"

	watertight_fix = ai_restyle.ensure_watertight(obj)

	assert watertight_fix["remesh_failed"] is True, watertight_fix
	assert watertight_fix["remeshed"] is False, watertight_fix
	assert watertight_fix["collapsed_to"] is None, watertight_fix
	assert watertight_fix["dropped_kinds"] == [], watertight_fix
	assert not ai_restyle._is_watertight(obj.data), (
		"le maillage restaure devrait rester troue (jamais 'repare' en silence par un remesh rejete)")

	# Seul le petit debris DISTANT (nettoyage independant, voir docstring) a pu
	# disparaitre — la caisse elle-meme (le corps dominant, jamais la cible du
	# remesh rejete) doit ressortir INTACTE : memes faces, meme volume clos, a
	# l'exception pres du debris retire.
	dropped = watertight_fix["dropped_disconnected_faces"]
	assert dropped > 0, "le debris distant aurait du etre retire (nettoyage independant du remesh)"
	faces_after = len(obj.data.polygons)
	volume_after = ai_restyle._mesh_volume(obj.data)
	assert faces_after == faces_before - dropped, (faces_before, dropped, faces_after)
	# Le debris (cube de 0.1 m d'arete) pese pour une part negligeable du
	# volume total (cube de 1 m d'arete) : la caisse, elle, ne doit RIEN avoir
	# perdu (pas de remesh accepte = pas de perte de volume sur son corps).
	assert volume_after > volume_before * 0.99, (volume_before, volume_after)

	return {
		"watertight_fix": watertight_fix,
		"faces_before": faces_before, "faces_after": faces_after,
		"volume_before": volume_before, "volume_after": volume_after,
	}


# ============================================================================
# Cas 5 — budget TENU APRES le biseau (A3D-15) : `apply_stylekit_shading`
# ajoute des triangles sur chaque arete vive ; un maillage deja SOUS son
# budget avant le biseau (donc jamais decime a la premiere passe) ne doit
# jamais ressortir AU-DESSUS de ce budget une fois le biseau applique.
# ============================================================================

def case_budget_enforced_after_bevel(out_dir: str) -> dict:
	"""Releve concret de tache (cs_container_20, vague 1) : 829 tris avant
	biseau pour un budget de 2500 (largement sous budget, `decimate_to_budget`
	alors un no-op), mais 3334 apres — le budget n'etait jamais reverifie
	APRES le poste qui l'a fait deborder. Reproduit ici en miniature : une
	simple boite (12 tris, 12 aretes vives) restylee avec un budget si serre
	qu'aucun biseau ne peut le respecter sans une passe de decimation
	SUPPLEMENTAIRE apres coup (`decimate_group_to_budget`, appelee UNIQUEMENT
	si necessaire)."""
	toonkit.reset_scene()
	obj = _make_box("BudgetBox", (1.0, 0.6, 0.4), (0, 0, 0))
	mat = toonkit.toon_material("painted_metal", toonkit.palette("painted_metal"), kind="painted_metal")
	_set_single_material(obj, mat)
	raw_path = os.path.join(out_dir, "case5_raw.glb")
	toonkit.export_glb(raw_path, obj, write_report=False)

	out_path = os.path.join(out_dir, "case5_out.glb")
	# Budget largement sous le nombre de tris qu'un biseau prop_container (4
	# cm, 1 segment) ajoute a une simple boite de 12 tris — mais AU-DESSUS des
	# 12 tris bruts : `decimate_to_budget` (AVANT le biseau) serait donc un
	# no-op sans la passe A3D-15 APRES le biseau.
	budget = 20
	report = ai_restyle.restyle(
		raw_path, out_path, budget, "props", skip_turntable=True,
		bevel_class="prop_container",
	)
	assert report["final_tris"] <= budget, (
		f"budget deborde APRES le biseau : {report['final_tris']} > {budget}")

	check_report = check_asset.run(out_path, budget_tris=budget, asset_class=None)
	assert check_report["ok"], f"check_asset ECHEC : {check_report['failures']}"

	return {
		"final_tris": report["final_tris"],
		"budget": budget,
		"check_asset_ok": check_report["ok"],
	}


# ============================================================================
# Cas 6 — A3D-15 : un assemblage a 3 ilots topologiquement disjoints en
# CHAINE (jamais ressoudes par merge_by_distance, comme un mat/une cabine/une
# fleche de grue IA generes en pieces separees) doit survivre ENTIER a
# `remove_isolated_islands` — seul un vrai fragment distant doit etre retire.
# ============================================================================

def _build_disjoint_chain_with_debris():
	"""3 boites disjointes en CHAINE (A proche de B, B proche de C, mais A
	loin de C directement — gaps 0.005 m entre voisins, largement sous
	ISLAND_GAP_TOLERANCE_M=0.01 m ; gap A-C = 1.01 m, largement au-dessus) +
	un vrai debris distant (10 m). C est fortement subdivisee : le plus gros
	ilot PAR NOMBRE DE FACES n'est PAS adjacent a A directement — une
	fixture qui distingue un critere "distance au plus gros ilot seul"
	(ancien algorithme : garderait C et B, jetterait A a tort) d'un
	regroupement TRANSITIF par cluster de proximite (A3D-15 : garde les
	trois, ne jette que le debris). Reproduit un mode de defaillance concret
	de la vague 1 (wl_oil_derrick, wl_crane_lattice, cs_deck_crane,
	cs_ship_mast : assemblages multi-pieces IA jamais ressoudes)."""
	a = _make_box("ChainA", (0.4, 0.4, 1.0), (0, 0, 0.5))
	b = _make_box("ChainB", (0.4, 0.4, 1.0), (0, 0, 1.505))
	c = _make_box("ChainC", (0.4, 0.4, 1.0), (0, 0, 2.51))
	with bpy.context.temp_override(object=c, active_object=c, selected_editable_objects=[c]):
		bpy.ops.object.mode_set(mode='EDIT')
		bpy.ops.mesh.select_all(action='SELECT')
		bpy.ops.mesh.subdivide(number_cuts=3)  # C : 6 -> 96 faces, tres largement le plus gros ilot
		bpy.ops.object.mode_set(mode='OBJECT')
	debris = _make_box("ChainDebris", (0.1, 0.1, 0.1), (10, 10, 10))

	joined = toonkit.join([a, b, c, debris])
	joined.name = "DisjointChain"
	# `join` fusionne dans le repere LOCAL du premier objet (ChainA, qui porte
	# encore sa propre location non appliquee, voir `_make_box`) : sans ce
	# bake, les Z lus depuis `obj.data.vertices` seraient decales de
	# -ChainA.location.z plutot que les valeurs MONDE documentees ci-dessus.
	toonkit.apply_transforms(joined)
	mat = toonkit.toon_material("cracked_concrete", toonkit.palette("cracked_concrete"), kind="cracked_concrete")
	_set_single_material(joined, mat)
	return joined


def case_multi_part_chain_survives_island_cleanup(out_dir: str) -> dict:
	"""A3D-15 : `remove_isolated_islands` doit garder A/B/C entiers (cluster
	transitif) et ne retirer QUE le debris distant."""
	toonkit.reset_scene()
	obj = _build_disjoint_chain_with_debris()
	faces_before = len(obj.data.polygons)

	removed = ai_restyle.remove_isolated_islands(obj)

	faces_after = len(obj.data.polygons)
	zs = [v.co.z for v in obj.data.vertices]
	xs = [v.co.x for v in obj.data.vertices]
	z_min, z_max = min(zs), max(zs)
	debris_survives = any(x > 5.0 for x in xs)

	assert removed == 6, f"seul le debris (6 faces) aurait du etre retire, obtenu {removed}"
	assert faces_after == faces_before - removed, (faces_before, removed, faces_after)
	assert z_min < 0.01, f"A (base, z~0) a disparu a tort : z_min={z_min}"
	assert z_max > 3.0, f"C (sommet, z~3.01) a disparu a tort : z_max={z_max}"
	assert not debris_survives, "le debris distant (x~10) aurait du etre retire"

	return {
		"removed": removed, "faces_before": faces_before, "faces_after": faces_after,
		"z_min": z_min, "z_max": z_max, "debris_survives": debris_survives,
	}


# ============================================================================
# Cas 7 — A3D-15 : un remesh ACCEPTE sur un objet a PLUSIEURS kinds ne doit
# plus collapser vers un seul kind dominant (limitation documentee du Remesh
# Voxel) mais REAFFECTER chaque kind a sa region d'origine par proximite
# (`_reassign_materials_by_nearest_face`).
# ============================================================================

def _build_two_kind_hollow_box():
	"""Boite FINEMENT subdivisee, coupee en 2 materiaux par position (X<0 ->
	matA, X>=0 -> matB) puis PERCEE d'UNE SEULE sous-face (trou reel, remesh
	necessaire dans `ensure_watertight`) — contrairement a
	`_build_hollow_crate_with_debris` (pensee pour faire ECHOUER le remesh
	avec un grand trou beant), cette fixture n'a qu'UN SEUL ilot et un trou
	PETIT DEVANT LA TAILLE DE VOXEL choisie par `_voxel_remesh` (diagonale de
	bbox / 48, voir VOXEL_RESOLUTION) : le remesh doit ABOUTIR, ce qui exerce
	la reaffectation par proximite plutot que le chemin d'echec/avertissement.
	Sondage (voir rapport de tache) : un trou dont la taille APPROCHE ou
	DEPASSE la taille de voxel (ex. une seule sous-face sur une grille 4x4,
	~1/4 du cote de la boite) fait diverger la reconstruction du Remesh
	Voxel (volume quasi nul a toutes les tailles tentees, meme comportement
	observe sur une sphere) — une subdivision fine (16x16 par face) rend le
	trou negligeable devant le premier voxel tente, comme un vrai petit trou
	de scan IA (jamais une face entiere manquante)."""
	bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0))
	obj = bpy.context.active_object
	obj.name = "TwoKindBox"
	obj.scale = (0.4, 0.4, 0.4)
	with bpy.context.temp_override(object=obj, active_object=obj, selected_editable_objects=[obj]):
		bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
		bpy.ops.object.mode_set(mode='EDIT')
		bpy.ops.mesh.select_all(action='SELECT')
		bpy.ops.mesh.subdivide(number_cuts=15)
		bpy.ops.object.mode_set(mode='OBJECT')

	mat_a = toonkit.toon_material("painted_metal", toonkit.palette("painted_metal"), kind="painted_metal")
	mat_b = toonkit.toon_material("wood_planks", toonkit.palette("wood_planks"), kind="wood_planks")
	me = obj.data
	me.materials.clear()
	me.materials.append(mat_a)
	me.materials.append(mat_b)
	for p in me.polygons:
		p.material_index = 0 if p.center.x < 0 else 1
	me.update()

	with bpy.context.temp_override(object=obj, active_object=obj, selected_editable_objects=[obj]):
		bpy.ops.object.mode_set(mode='EDIT')
		bm = bmesh.from_edit_mesh(me)
		bm.faces.ensure_lookup_table()
		hole = [f for f in bm.faces if f.normal.z > 0.9][:1]
		bmesh.ops.delete(bm, geom=hole, context='FACES')
		bmesh.update_edit_mesh(me)
		bpy.ops.object.mode_set(mode='OBJECT')
	return obj


def case_two_kind_remesh_preserves_materials(out_dir: str) -> dict:
	"""A3D-15 : sur un objet a 2 kinds troue (remesh ACCEPTE attendu), verifie
	que `ensure_watertight` ne collapse plus vers un seul kind : les DEUX
	materiaux d'origine restent presents, et chaque region garde son kind
	(faces cote X<0 majoritairement painted_metal, cote X>=0 majoritairement
	wood_planks) plutot qu'un seul kind ecrase sur tout l'objet."""
	toonkit.reset_scene()
	obj = _build_two_kind_hollow_box()
	assert not ai_restyle._is_watertight(obj.data), "fixture invalide : le trou perce devrait laisser un bord ouvert"
	assert len(obj.data.materials) == 2, "fixture invalide : 2 materiaux attendus avant remesh"

	fix = ai_restyle.ensure_watertight(obj)

	assert fix["remeshed"] is True, fix
	assert fix["remesh_failed"] is False, fix
	assert fix["collapsed_to"] is None, fix
	assert fix["dropped_kinds"] == [], fix

	out_kinds = sorted(m.name for m in obj.data.materials if m is not None)
	assert out_kinds == ["painted_metal", "wood_planks"], (
		f"un remesh accepte a multi-kind ne doit plus collapser vers un seul kind : {out_kinds}")

	left_kinds = set()
	right_kinds = set()
	for p in obj.data.polygons:
		mat = obj.data.materials[p.material_index]
		name = mat.name if mat is not None else None
		if p.center.x < -0.02:
			left_kinds.add(name)
		elif p.center.x > 0.02:
			right_kinds.add(name)
	assert left_kinds == {"painted_metal"}, f"cote X<0 aurait du rester painted_metal, obtenu {left_kinds}"
	assert right_kinds == {"wood_planks"}, f"cote X>=0 aurait du rester wood_planks, obtenu {right_kinds}"

	return {"watertight_fix": fix, "out_kinds": out_kinds,
		"left_kinds": sorted(left_kinds), "right_kinds": sorted(right_kinds)}


# ============================================================================
# Cas 8 — A3D-15 : reparation non-manifold FINALE (post-biseau/decimation),
# `_repair_nonmanifold_final` — releve concret de tache (wpn_fracas "pompe",
# wpn_percuteur "chien", wpn_pistolet "culasse", wl_water_tower, wpn_magnum) :
# un PETIT nombre d'aretes non-manifold introduites APRES `_fill_holes` doit
# etre repare en dernier recours ; un maillage qui en porte TROP (au-dela du
# plafond, ex. wl_crane_lattice) doit rester intact plutot que mutile.
# ============================================================================

def _build_bad_edge_mesh(name: str, n_edges: int, faces_per_edge: int = 3):
	"""Construit UN SEUL objet mesh portant `n_edges` aretes non-manifold
	INDEPENDANTES (chacune partagee par `faces_per_edge` faces, >= 3 donc
	non-manifold par construction), mutuellement disjointes (aucun sommet
	partage entre deux aretes, chaque groupe son propre "eventail" de faces
	autour d'une arete commune "spine") — un maillage synthetique dont le
	nombre EXACT d'aretes non-manifold est connu d'avance, pour tester
	`_repair_nonmanifold_final` a une echelle CONTROLEE sans dependre d'une
	geometrie Tripo reelle. Bmesh construit directement (pas `bpy.ops`) : plus
	rapide et deterministe pour un grand `n_edges`."""
	bm = bmesh.new()
	for i in range(n_edges):
		va = bm.verts.new((i * 2.0, 0.0, 0.0))
		vb = bm.verts.new((i * 2.0 + 1.0, 0.0, 0.0))
		for j in range(faces_per_edge):
			vc = bm.verts.new((i * 2.0 + 0.5, 1.0 + j * 0.5, 0.1 * (j + 1)))
			bm.faces.new((va, vb, vc))
	me = bpy.data.meshes.new(name)
	bm.to_mesh(me)
	bm.free()
	me.update()
	obj = bpy.data.objects.new(name, me)
	bpy.context.scene.collection.objects.link(obj)
	mat = toonkit.toon_material("painted_metal", toonkit.palette("painted_metal"), kind="painted_metal")
	_set_single_material(obj, mat)
	return obj


def _count_bad_edges(obj) -> int:
	bm = bmesh.new()
	bm.from_mesh(obj.data)
	n = len([e for e in bm.edges if len(e.link_faces) >= 3])
	bm.free()
	return n


def case_final_nonmanifold_repair_unit(out_dir: str) -> dict:
	"""A3D-15 : `_repair_nonmanifold_final` doit reparer un PETIT nombre
	d'aretes non-manifold (sous `NONMANIFOLD_FINAL_REPAIR_MAX_EDGES`) en
	dernier recours (memes outils que `_fill_holes` : doublons exacts puis
	eclats non stricts), mais laisser INTACT un objet qui en porte TROP
	(au-dela du plafond) plutot que de mutiler sa silhouette."""
	toonkit.reset_scene()
	small = _build_bad_edge_mesh("SmallBad", n_edges=3, faces_per_edge=3)
	bad_before_small = _count_bad_edges(small)

	big = _build_bad_edge_mesh(
		"BigBad", n_edges=ai_restyle.NONMANIFOLD_FINAL_REPAIR_MAX_EDGES + 5, faces_per_edge=3)
	bad_before_big = _count_bad_edges(big)

	report = ai_restyle._repair_nonmanifold_final([small, big])

	bad_after_small = _count_bad_edges(small)
	bad_after_big = _count_bad_edges(big)

	assert bad_before_small == 3, bad_before_small
	assert bad_after_small == 0, f"les 3 aretes non-manifold auraient du etre reparees : {bad_after_small}"
	assert bad_before_big == ai_restyle.NONMANIFOLD_FINAL_REPAIR_MAX_EDGES + 5, bad_before_big
	assert bad_after_big == bad_before_big, (
		f"un objet au-dessus du plafond ne doit JAMAIS etre touche : {bad_before_big} -> {bad_after_big}")
	assert report["skipped_max_edges"] == ["BigBad"], report["skipped_max_edges"]
	assert report["remaining_nonmanifold_edges"] == bad_after_big, report

	return {
		"bad_before_small": bad_before_small, "bad_after_small": bad_after_small,
		"bad_before_big": bad_before_big, "bad_after_big": bad_after_big,
		"skipped_max_edges": report["skipped_max_edges"],
		"remaining_nonmanifold_edges": report["remaining_nonmanifold_edges"],
	}


CASES = {
	"face_quantization_unit": case_face_quantization_unit,
	"full_pipeline_no_images_color0_check_asset": case_full_pipeline_no_images_color0_check_asset,
	"weapon_parts_and_markers": case_weapon_parts_and_markers,
	"curved_part_separation_stays_manifold": case_curved_part_separation_stays_manifold,
	"volume_guard_unit": case_volume_guard_unit,
	"hollow_crate_watertight_warning": case_hollow_crate_watertight_warning,
	"budget_enforced_after_bevel": case_budget_enforced_after_bevel,
	"multi_part_chain_survives_island_cleanup": case_multi_part_chain_survives_island_cleanup,
	"two_kind_remesh_preserves_materials": case_two_kind_remesh_preserves_materials,
	"final_nonmanifold_repair_unit": case_final_nonmanifold_repair_unit,
}


def _run_case(name: str, fn, out_dir: str) -> dict:
	try:
		detail = fn(out_dir)
		return {"ok": True, "error": None, "detail": detail}
	except Exception as exc:  # noqa: BLE001 — un cas qui plante est un echec de test, pas un crash du harnais
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
		raise SystemExit("usage: blender -b -P _ai_restyle_cases.py -- --out-dir DIR [--only case1,case2]")
	os.makedirs(out_dir, exist_ok=True)

	results = {}
	for name, fn in CASES.items():
		if only and name not in only:
			continue
		results[name] = _run_case(name, fn, out_dir)

	print("AI_RESTYLE_CASES_RESULT " + json.dumps({"cases": results}, ensure_ascii=False))


if __name__ == "__main__":
	main()
