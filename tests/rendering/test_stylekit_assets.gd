## test_stylekit_assets.gd
## Spec (A3D-02, docs/research/06_ai_3d_pipeline.md §B3) : preuve bout-en-bout
## que `tools/blender/lib/toonkit.py` complété (biseau + normales pondérées
## déjà en place ; normale lissée pour contour, AO, courbure, export glTF +
## rapport JSON ajoutés cette manche) tient ses 3 critères d'acceptation :
##   1. le rapport JSON généré par `toonkit.export_glb()` liste les attributs
##      smooth_normal/ao/curvature et le nombre de tris ;
##   2. le .glb produit expose bien AO/Curvature en couleurs de sommet
##      (COLOR) une fois importé — Godot les prend en charge nativement ;
##   3. la normale lissée survit dans le .glb en tant qu'attribut glTF
##      personnalisé (`_SMOOTH_NORMAL`, préfixe requis par
##      `export_attributes=True`, voir toonkit.export_glb) et peut être
##      exposée côté Godot en canal CUSTOM (`Mesh.ARRAY_CUSTOM0`) via un
##      `GLTFDocumentExtension` — le mécanisme officiel de Godot pour les
##      attributs de mesh non standard (aucun canal CUSTOM n'est peuplé par
##      défaut par `GLTFDocument`, vérifié par sondage : un attribut préfixé
##      "_" qui n'est reconnu par AUCUNE extension enregistrée est purement
##      et simplement ignoré au parsing). Ce mapping custom -> ARRAY_CUSTOM0
##      est écrit ICI (dans le test) comme preuve du mécanisme ; le brancher
##      dans le pipeline d'import RÉEL du jeu (pour qu'un shader consomme
##      `_smooth_normal` par défaut) est un travail d'intégration séparé, hors
##      des 2 fichiers possédés par cette tâche (voir rapport de tâche).
##
## Fixture : `tools/blender/lib/fixtures/stylekit_test_prop.glb` (+ son
## `.json` à côté), construite par `build_stylekit_test_prop.py` (même
## dossier) — regénérer avec :
##   blender -b --factory-startup --python-exit-code 1 \
##       -P tools/blender/lib/fixtures/build_stylekit_test_prop.py
extends GdUnitTestSuite

const FIXTURE_GLB := "res://tools/blender/lib/fixtures/stylekit_test_prop.glb"
const FIXTURE_REPORT := "res://tools/blender/lib/fixtures/stylekit_test_prop.json"

## Nom de l'attribut glTF personnalisé (voir toonkit.SMOOTH_NORMAL_ATTR côté
## Python — Blender met le nom en MAJUSCULES à l'export, convention glTF pour
## les attributs applicatifs "_xxx").
const SMOOTH_NORMAL_GLTF_ATTR := "_SMOOTH_NORMAL"


## GLTFDocumentExtension minimal : recopie l'accesseur glTF personnalisé
## `_SMOOTH_NORMAL` (VEC3/FLOAT, un par primitive qui le porte) dans le canal
## `Mesh.ARRAY_CUSTOM0` (format RGB_FLOAT) de chaque surface importée — la
## voie que Godot prévoit pour qu'un GLTFDocumentExtension enrichisse le mesh
## importé avec un attribut que le coeur du moteur ne comprend pas nativement
## (`_import_post_parse`, appelé après le parsing des meshes mais avant la
## génération de la scène — signature et classes GLTFState/GLTFAccessor/
## GLTFBufferView/ImporterMesh vérifiées par sondage, voir rapport de tâche).
class SmoothNormalImportExtension:
	extends GLTFDocumentExtension

	# `static var` et NON `var` d'instance : Godot duplique/reconstruit
	# l'objet extension utilisé pour le dispatch réel des virtuelles
	# (`_import_post_parse` s'exécute sur une AUTRE identité d'objet que
	# celle passée à `register_gltf_document_extension` — vérifié par
	# sondage, voir rapport de tâche) ; un `var` d'instance mis à jour côté
	# moteur ne serait donc jamais visible depuis l'objet que le test garde
	# en main. Un `static var` appartient à la CLASSE, pas à l'instance : il
	# reste visible quel que soit l'objet réel qui a exécuté le hook.
	static var last_import_saw_attribute := false

	func _import_post_parse(state: GLTFState) -> Error:
		var json: Dictionary = state.get_json()
		var gltf_meshes_json: Array = json.get("meshes", [])
		var accessors: Array = state.get_accessors()
		var buffer_views: Array = state.get_buffer_views()
		var state_meshes: Array = state.get_meshes()
		for mesh_idx in state_meshes.size():
			if mesh_idx >= gltf_meshes_json.size():
				continue
			var prims: Array = (gltf_meshes_json[mesh_idx] as Dictionary).get("primitives", [])
			var gltf_mesh: GLTFMesh = state_meshes[mesh_idx]
			var importer_mesh: ImporterMesh = gltf_mesh.mesh
			if importer_mesh == null:
				continue
			var rebuilt := ImporterMesh.new()
			var surface_count: int = importer_mesh.get_surface_count()
			for surf_idx in surface_count:
				var arrays: Array = importer_mesh.get_surface_arrays(surf_idx)
				var flags := 0
				if surf_idx < prims.size():
					var attrs: Dictionary = (prims[surf_idx] as Dictionary).get("attributes", {})
					if attrs.has(SMOOTH_NORMAL_GLTF_ATTR):
						var accessor: GLTFAccessor = accessors[int(attrs[SMOOTH_NORMAL_GLTF_ATTR])]
						arrays[Mesh.ARRAY_CUSTOM0] = _decode_vec3_float_accessor(state, accessor, buffer_views)
						flags = Mesh.ARRAY_CUSTOM_RGB_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
						last_import_saw_attribute = true
				rebuilt.add_surface(
					importer_mesh.get_surface_primitive_type(surf_idx),
					arrays, [], {},
					importer_mesh.get_surface_material(surf_idx),
					importer_mesh.get_surface_name(surf_idx),
					flags)
			gltf_mesh.mesh = rebuilt
		return OK

	static func _decode_vec3_float_accessor(state: GLTFState, accessor: GLTFAccessor, buffer_views: Array) -> PackedFloat32Array:
		var view: GLTFBufferView = buffer_views[accessor.get_buffer_view()]
		var raw: PackedByteArray = view.load_buffer_view_data(state)
		var count: int = accessor.get_count()
		var elem_size := 12  # VEC3 * float32
		var stride: int = view.get_byte_stride()
		var effective_stride := stride if stride > 0 else elem_size
		var byte_offset: int = accessor.get_byte_offset()
		var out := PackedFloat32Array()
		out.resize(count * 3)
		for i in count:
			var base: int = byte_offset + i * effective_stride
			var vals := raw.slice(base, base + elem_size).to_float32_array()
			out[i * 3 + 0] = vals[0]
			out[i * 3 + 1] = vals[1]
			out[i * 3 + 2] = vals[2]
		return out


func _load_scene_from_fixture(extensions: Array) -> Node:
	for ext in extensions:
		GLTFDocument.register_gltf_document_extension(ext)
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var abs_path := ProjectSettings.globalize_path(FIXTURE_GLB)
	var err := doc.append_from_file(abs_path, state)
	for ext in extensions:
		GLTFDocument.unregister_gltf_document_extension(ext)
	assert_int(err).append_failure_message("append_from_file(%s) a échoué (code %d)" % [abs_path, err]).is_equal(OK)
	var scene := doc.generate_scene(state)
	assert_object(scene).is_not_null()
	return scene


static func _find_mesh_instance(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
	for child in node.get_children():
		var found := _find_mesh_instance(child)
		if found != null:
			return found
	return null


# --------------------------------------------------------------- rapport JSON

func test_export_report_lists_smooth_normal_ao_curvature_and_tris() -> void:
	assert_bool(FileAccess.file_exists(FIXTURE_REPORT)).append_failure_message(
		"fixture manquante : régénérer avec tools/blender/lib/fixtures/build_stylekit_test_prop.py").is_true()
	var text := FileAccess.get_file_as_string(FIXTURE_REPORT)
	var report: Dictionary = JSON.parse_string(text)
	assert_object(report).is_not_null()
	assert_bool(bool(report.get("smooth_normal", false))).append_failure_message(
		"rapport JSON: 'smooth_normal' doit être true (toonkit.smooth_normal_attrs appelé)").is_true()
	assert_bool(bool(report.get("ao", false))).append_failure_message(
		"rapport JSON: 'ao' doit être true (toonkit.bake_vertex_ao appelé)").is_true()
	assert_bool(bool(report.get("curvature", false))).append_failure_message(
		"rapport JSON: 'curvature' doit être true (toonkit.curvature_edge_mask appelé)").is_true()
	assert_int(int(report.get("tris", 0))).is_greater(0)


# --------------------------------------------------------- import Godot (COLOR/TANGENT)

func test_glb_exposes_ao_and_curvature_as_vertex_color_on_import() -> void:
	var scene := _load_scene_from_fixture([])
	auto_free(scene)
	var mi := _find_mesh_instance(scene)
	assert_object(mi).append_failure_message("aucun MeshInstance3D dans la scène importée").is_not_null()
	var mesh: Mesh = mi.mesh
	var fmt: int = mesh.surface_get_format(0)
	assert_bool((fmt & Mesh.ARRAY_FORMAT_COLOR) != 0).append_failure_message(
		"le mesh importé n'a pas de canal COLOR — AO/Curvature (couleurs de sommet CORNER) non exposés").is_true()
	var arrays := mesh.surface_get_arrays(0)
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	assert_int(colors.size()).is_greater(0)


func test_glb_exposes_tangent_channel_on_import() -> void:
	# docs/research/06_ai_3d_pipeline.md §B3 : "dans les tangentes pour les
	# meshes skinnés, car Godot skinne TANGENT mais pas les attributs custom"
	# — même un prop statique en sort pourvu (Godot les régénère à l'import
	# dès que NORMAL + UV sont présents), donc la voie TANGENT est disponible
	# le jour où un générateur de personnage en a besoin.
	var scene := _load_scene_from_fixture([])
	auto_free(scene)
	var mi := _find_mesh_instance(scene)
	var mesh: Mesh = mi.mesh
	var fmt: int = mesh.surface_get_format(0)
	assert_bool((fmt & Mesh.ARRAY_FORMAT_TANGENT) != 0).append_failure_message(
		"le mesh importé n'a pas de canal TANGENT").is_true()


# --------------------------------------------------- import Godot (CUSTOM = smooth_normal)

func test_glb_without_extension_does_not_expose_smooth_normal_by_default() -> void:
	# Preuve du "pourquoi" de l'extension ci-dessus : SANS elle, l'attribut
	# personnalisé `_SMOOTH_NORMAL` est silencieusement ignoré par
	# GLTFDocument (aucun canal CUSTOM peuplé) — vérifié par sondage avant
	# d'écrire ce test, voir rapport de tâche.
	var scene := _load_scene_from_fixture([])
	auto_free(scene)
	var mi := _find_mesh_instance(scene)
	var mesh: Mesh = mi.mesh
	var fmt: int = mesh.surface_get_format(0)
	assert_bool((fmt & Mesh.ARRAY_FORMAT_CUSTOM0) != 0).append_failure_message(
		"CUSTOM0 ne devrait PAS être peuplé sans extension d'import dédiée").is_false()


func test_glb_exposes_smooth_normal_as_custom_channel_via_import_extension() -> void:
	SmoothNormalImportExtension.last_import_saw_attribute = false
	var ext := SmoothNormalImportExtension.new()
	var scene := _load_scene_from_fixture([ext])
	auto_free(scene)
	assert_bool(SmoothNormalImportExtension.last_import_saw_attribute).append_failure_message(
		"l'extension n'a trouvé aucun accesseur %s dans le .glb" % SMOOTH_NORMAL_GLTF_ATTR).is_true()
	var mi := _find_mesh_instance(scene)
	assert_object(mi).is_not_null()
	var mesh: Mesh = mi.mesh
	var fmt: int = mesh.surface_get_format(0)
	assert_bool((fmt & Mesh.ARRAY_FORMAT_CUSTOM0) != 0).append_failure_message(
		"le canal CUSTOM0 devrait porter la normale lissée une fois l'extension active").is_true()
	var arrays := mesh.surface_get_arrays(0)
	var custom: PackedFloat32Array = arrays[Mesh.ARRAY_CUSTOM0]
	var vertex_count: int = (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	assert_int(custom.size()).is_equal(vertex_count * 3)
	# Chaque triplet doit rester une normale à peu près unitaire (moyenne de
	# normales de faces déjà normalisées, voir toonkit.smooth_normal_attrs) —
	# preuve que ce ne sont pas des zéros/données non initialisées.
	var any_significant := false
	for i in vertex_count:
		var v := Vector3(custom[i * 3], custom[i * 3 + 1], custom[i * 3 + 2])
		if v.length() > 0.5:
			any_significant = true
		assert_float(v.length()).append_failure_message(
			"normale lissée #%d hors plage plausible: %s (longueur %f)" % [i, v, v.length()]).is_between(0.9, 1.1)
	assert_bool(any_significant).is_true()
