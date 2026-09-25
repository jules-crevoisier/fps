## test_outline_normals.gd
## Spec (docs/research/07_godot_tech.md C1 "Coque inversée", tâche TECH-03) :
## ink_outline.gdshader extrude selon la normale LISSÉE quand l'attribut
## existe (CUSTOM0 pour un mesh statique, TANGENT pour un mesh skinné —
## Godot skinne NORMAL et TANGENT selon la pose AVANT vertex(), jamais les
## attributs CUSTOM, voir l'en-tête du shader), sinon selon NORMAL (facettée,
## l'ancien comportement — jamais un crash/un contour manquant sur un mesh
## qui n'a pas encore été reconstruit par stylekit).
##
## Comme test_outline_widths.gd (même limite, voir sa docstring) : gdUnit4 ne
## peut pas mesurer un rendu réel en headless ici. Ce test (a) vérifie par
## regex que le GLSL lit bien CUSTOM0/TANGENT avec un repli sur NORMAL par
## seuil de longueur (pas juste un uniform déclaré et mort), (b) vérifie que
## `Cartoon.gd` bascule `use_smooth_normal_tangent` selon que le mesh porte
## réellement des poids d'os (Mesh.ARRAY_FORMAT_BONES), pas selon son
## appelant, et (c) charge le GLB stylekit de test (A3D-02, même fixture que
## test_stylekit_assets.gd) pour prouver qu'un prop stylekit RÉEL expose bien
## l'attribut `_smooth_normal` -> CUSTOM0, ET que sa valeur diffère
## réellement de la normale facettée `NORMAL` à au moins une arête vive du
## bevel — la preuve concrète qu'il existe une fente à corriger, et que
## l'attribut lu par (a) n'est pas une coïncidence (mêmes valeurs que NORMAL).
extends GdUnitTestSuite

const _SHADER_PATH := "res://assets/shaders/ink_outline.gdshader"
const FIXTURE_GLB := "res://tools/blender/lib/fixtures/stylekit_test_prop.glb"
const SMOOTH_NORMAL_GLTF_ATTR := "_SMOOTH_NORMAL"


func _source() -> String:
	return FileAccess.get_file_as_string(_SHADER_PATH)


# --------------------------------------------------------- structure du GLSL

func test_shader_declares_smooth_normal_tangent_uniform() -> void:
	var re := RegEx.new()
	re.compile("uniform\\s+bool\\s+use_smooth_normal_tangent\\s*=\\s*false\\s*;")
	assert_that(re.search(_source())).append_failure_message(
		"uniform bool use_smooth_normal_tangent = false; introuvable dans %s" % _SHADER_PATH
	).is_not_null()


func test_vertex_reads_custom0_when_not_tangent_mode() -> void:
	var source := _source()
	var re := RegEx.new()
	re.compile("use_smooth_normal_tangent\\s*\\?\\s*TANGENT\\s*:\\s*CUSTOM0\\.xyz")
	assert_that(re.search(source)).append_failure_message(
		"vertex() ne choisit pas entre TANGENT (skinné) et CUSTOM0.xyz (statique) selon use_smooth_normal_tangent"
	).is_not_null()


func test_vertex_falls_back_to_normal_when_smooth_attribute_absent() -> void:
	var source := _source()
	# Le repli doit être conditionné à une longueur significative (attribut
	# absent = lu à zéro par Godot), jamais un aveugle `normalize(...)` d'un
	# vecteur potentiellement nul (NaN garanti).
	var re_guard := RegEx.new()
	re_guard.compile("length\\(smooth_normal_candidate\\)\\s*>\\s*0\\.5")
	assert_that(re_guard.search(source)).append_failure_message(
		"vertex() ne teste pas la longueur du candidat avant de l'utiliser (repli NORMAL manquant ou inconditionnel)"
	).is_not_null()
	var re_default := RegEx.new()
	re_default.compile("vec3\\s+extrude_source\\s*=\\s*NORMAL\\s*;")
	assert_that(re_default.search(source)).append_failure_message(
		"extrude_source ne part pas de NORMAL par défaut (repli manquant si l'attribut est absent)"
	).is_not_null()


func test_vertex_extrudes_along_extrude_source_not_raw_normal() -> void:
	var source := _source()
	var re := RegEx.new()
	re.compile("clip_normal\\s*=\\s*normalize\\(\\(PROJECTION_MATRIX\\s*\\*\\s*\\(MODELVIEW_MATRIX\\s*\\*\\s*vec4\\(extrude_source,\\s*0\\.0\\)\\)\\)\\.xyz\\)")
	assert_that(re.search(source)).append_failure_message(
		"clip_normal n'extrude plus selon extrude_source (calcul de normale lissée mort : toujours NORMAL brut ?)"
	).is_not_null()


# --------------------------------------------------- Cartoon.gd : sélection du canal

func _static_triangle_mesh() -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0)])
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3(0, 0, 1), Vector3(0, 0, 1), Vector3(0, 0, 1)])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Même triangle, mais avec des tableaux BONES/WEIGHTS peuplés -- suffit à
## faire porter `Mesh.ARRAY_FORMAT_BONES` à la surface (aucun Skeleton3D réel
## requis pour ce format, seulement pour un skinning effectif à l'exécution).
func _skinned_triangle_mesh() -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0)])
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3(0, 0, 1), Vector3(0, 0, 1), Vector3(0, 0, 1)])
	arrays[Mesh.ARRAY_BONES] = PackedInt32Array([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
	arrays[Mesh.ARRAY_WEIGHTS] = PackedFloat32Array([1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _mesh_instance_with_placeholder_material(mesh: ArrayMesh) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	auto_free(mi)
	mi.mesh = mesh
	mi.set_surface_override_material(0, StandardMaterial3D.new())
	return mi


func test_mesh_is_skinned_true_when_surface_has_bone_format() -> void:
	assert_bool(Cartoon._mesh_is_skinned(_skinned_triangle_mesh())).append_failure_message(
		"_mesh_is_skinned doit détecter Mesh.ARRAY_FORMAT_BONES"
	).is_true()


func test_mesh_is_skinned_false_for_plain_static_mesh() -> void:
	assert_bool(Cartoon._mesh_is_skinned(_static_triangle_mesh())).append_failure_message(
		"_mesh_is_skinned ne doit pas déclencher le mode skinné sur un mesh sans os"
	).is_false()


## PrimitiveMesh (BoxMesh, SphereMesh…) n'implémente pas `surface_get_format`
## (pas une valeur : "Nonexistent function", vérifié en headless) -- des
## tests existants (test_cartoon_materials.gd) et du décor procédural posent
## un BoxMesh sur `apply_team_outline` ; `_mesh_is_skinned` doit s'en accommoder
## sans planter, jamais crasher la moitié des appelants existants.
func test_mesh_is_skinned_false_for_primitive_mesh_without_surface_get_format() -> void:
	assert_bool(Cartoon._mesh_is_skinned(BoxMesh.new())).append_failure_message(
		"_mesh_is_skinned doit retomber sur 'non skinné' pour un PrimitiveMesh (BoxMesh) sans planter"
	).is_false()


func test_apply_team_outline_does_not_crash_on_primitive_mesh() -> void:
	var mi := MeshInstance3D.new()
	auto_free(mi)
	mi.mesh = BoxMesh.new()
	mi.set_surface_override_material(0, StandardMaterial3D.new())
	Cartoon.apply_team_outline(mi, false)
	var outline: ShaderMaterial = mi.get_surface_override_material(0).next_pass
	assert_object(outline).is_not_null()
	assert_bool(bool(outline.get_shader_parameter("use_smooth_normal_tangent"))).is_false()


func test_apply_team_outline_reads_custom0_smooth_normal_on_static_mesh() -> void:
	var mi := _mesh_instance_with_placeholder_material(_static_triangle_mesh())
	Cartoon.apply_team_outline(mi, false)
	var outline: ShaderMaterial = mi.get_surface_override_material(0).next_pass
	assert_object(outline).append_failure_message("apply_team_outline n'a posé aucun next_pass").is_not_null()
	assert_bool(bool(outline.get_shader_parameter("use_smooth_normal_tangent"))).append_failure_message(
		"un mesh statique (sans poids d'os) doit rester sur la lecture CUSTOM0, pas TANGENT"
	).is_false()


func test_apply_team_outline_reads_tangent_smooth_normal_on_skinned_ally() -> void:
	var mi := _mesh_instance_with_placeholder_material(_skinned_triangle_mesh())
	Cartoon.apply_team_outline(mi, false)
	var outline: ShaderMaterial = mi.get_surface_override_material(0).next_pass
	assert_object(outline).is_not_null()
	assert_bool(bool(outline.get_shader_parameter("use_smooth_normal_tangent"))).append_failure_message(
		"un mesh skinné (Mesh.ARRAY_FORMAT_BONES) doit lire la normale lissée dans TANGENT, pas CUSTOM0"
	).is_true()


## L'ennemi pose DEUX coques chaînées (surbrillance + encre, voir
## `_team_outline_pass`) : les deux doivent porter le même choix de canal,
## pas seulement la première.
func test_apply_team_outline_propagates_tangent_mode_through_enemy_double_shell() -> void:
	var mi := _mesh_instance_with_placeholder_material(_skinned_triangle_mesh())
	Cartoon.apply_team_outline(mi, true)
	var highlight: ShaderMaterial = mi.get_surface_override_material(0).next_pass
	assert_object(highlight).append_failure_message("coque de surbrillance ennemie absente").is_not_null()
	assert_bool(bool(highlight.get_shader_parameter("use_smooth_normal_tangent"))).append_failure_message(
		"la coque de surbrillance ennemie ne lit pas TANGENT sur un mesh skinné"
	).is_true()
	var ink_shell: ShaderMaterial = highlight.next_pass
	assert_object(ink_shell).append_failure_message("la coque d'encre ennemie (next_pass du highlight) est absente").is_not_null()
	assert_bool(bool(ink_shell.get_shader_parameter("use_smooth_normal_tangent"))).append_failure_message(
		"la coque d'encre ennemie ne lit pas TANGENT sur un mesh skinné"
	).is_true()


# ------------------------------------------------- Cartoon.character(mesh:)
## `character()` est l'entrée utilisée par ViewModel.gd/ThirdPersonWeapon.gd
## pour le viewmodel (arme + gants en 1re personne) -- hors périmètre de
## cette tâche (voir l'en-tête de Cartoon.gd), donc ces appelants ne sont PAS
## mis à jour ici. Mais un viewmodel skinné (Skeleton3D pour l'animation des
## mains) appelant `character()` SANS lui dire qu'il est skinné se fendrait
## exactement comme `apply_team_outline` avant TECH-03 -- d'où ce paramètre
## `mesh` optionnel (4e position, défaut `null`) : quand un appelant le
## renseigne, `character()` route sur `_mesh_is_skinned()` comme
## `apply_team_outline`. Défaut `null` => comportement IDENTIQUE à avant pour
## tous les appels positionnels existants (aucun ne dépasse 3 arguments).

func test_character_defaults_to_custom0_when_mesh_omitted() -> void:
	var m := Cartoon.character(Color.GREEN)
	assert_bool(bool(m.next_pass.get_shader_parameter("use_smooth_normal_tangent"))).append_failure_message(
		"character() sans argument mesh doit garder l'ancien comportement (CUSTOM0), pas basculer sur TANGENT"
	).is_false()


func test_character_reads_custom0_smooth_normal_when_given_static_mesh() -> void:
	var m := Cartoon.character(Color.GREEN, 3.0, Color(0.0, 0.0, 0.0, 0.0), _static_triangle_mesh())
	assert_bool(bool(m.next_pass.get_shader_parameter("use_smooth_normal_tangent"))).append_failure_message(
		"character() avec un mesh statique doit rester sur CUSTOM0, pas TANGENT"
	).is_false()


func test_character_reads_tangent_smooth_normal_when_given_skinned_mesh() -> void:
	var m := Cartoon.character(Color.GREEN, 3.0, Color(0.0, 0.0, 0.0, 0.0), _skinned_triangle_mesh())
	assert_bool(bool(m.next_pass.get_shader_parameter("use_smooth_normal_tangent"))).append_failure_message(
		"character() avec un mesh skinné (viewmodel) doit lire la normale lissée dans TANGENT, pas CUSTOM0 -- sinon le contour de l'arme/des gants se fend en jeu"
	).is_true()


func test_character_propagates_tangent_mode_to_enemy_double_shell() -> void:
	var m := Cartoon.character(Color.GREEN, 3.0, Color("ff3dc8"), _skinned_triangle_mesh())
	var highlight: ShaderMaterial = m.next_pass
	assert_object(highlight).append_failure_message("coque de surbrillance ennemie absente").is_not_null()
	assert_bool(bool(highlight.get_shader_parameter("use_smooth_normal_tangent"))).append_failure_message(
		"la coque de surbrillance ennemie de character() ne lit pas TANGENT sur un mesh skinné"
	).is_true()
	var ink_shell: ShaderMaterial = highlight.next_pass
	assert_object(ink_shell).append_failure_message("la coque d'encre ennemie (next_pass du highlight) est absente").is_not_null()
	assert_bool(bool(ink_shell.get_shader_parameter("use_smooth_normal_tangent"))).append_failure_message(
		"la coque d'encre ennemie de character() ne lit pas TANGENT sur un mesh skinné"
	).is_true()


# ----------------------------------- GLB stylekit réel : preuve de la fente

## GLTFDocumentExtension minimale : recopie l'accesseur glTF personnalisé
## `_SMOOTH_NORMAL` dans le canal `Mesh.ARRAY_CUSTOM0` de chaque surface
## importée -- même mécanisme que test_stylekit_assets.gd (A3D-02), reproduit
## ici en propre (fichiers séparés, chacun self-contained) pour prouver,
## SPÉCIFIQUEMENT pour cette tâche, qu'un GLB stylekit expose l'attribut ET
## que sa valeur diffère de NORMAL sur une arête vive réelle.
class SmoothNormalImportExtension:
	extends GLTFDocumentExtension

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


static func _find_mesh_instance(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
	for child in node.get_children():
		var found := _find_mesh_instance(child)
		if found != null:
			return found
	return null


func _load_fixture_with_smooth_normal_extension() -> MeshInstance3D:
	SmoothNormalImportExtension.last_import_saw_attribute = false
	var ext := SmoothNormalImportExtension.new()
	GLTFDocument.register_gltf_document_extension(ext)
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var abs_path := ProjectSettings.globalize_path(FIXTURE_GLB)
	var err := doc.append_from_file(abs_path, state)
	GLTFDocument.unregister_gltf_document_extension(ext)
	assert_int(err).append_failure_message(
		"append_from_file(%s) a échoué (code %d) — fixture manquante ? régénérer avec tools/blender/lib/fixtures/build_stylekit_test_prop.py" % [abs_path, err]
	).is_equal(OK)
	var scene := doc.generate_scene(state)
	assert_object(scene).is_not_null()
	auto_free(scene)
	assert_bool(SmoothNormalImportExtension.last_import_saw_attribute).append_failure_message(
		"le GLB stylekit de test n'expose aucun accesseur %s -- régénérer la fixture (A3D-02)" % SMOOTH_NORMAL_GLTF_ATTR
	).is_true()
	var mi := _find_mesh_instance(scene)
	assert_object(mi).append_failure_message("aucun MeshInstance3D dans la fixture importée").is_not_null()
	return mi


func test_stylekit_glb_exposes_smooth_normal_custom0_attribute() -> void:
	var mi := _load_fixture_with_smooth_normal_extension()
	var mesh: Mesh = mi.mesh
	var fmt: int = mesh.surface_get_format(0)
	assert_bool((fmt & Mesh.ARRAY_FORMAT_CUSTOM0) != 0).append_failure_message(
		"le canal CUSTOM0 n'est pas peuplé sur le prop stylekit de test -- l'attribut _smooth_normal n'est pas exposé"
	).is_true()


## Preuve que la normale lissée exposée n'est pas une simple copie de NORMAL
## sous un autre nom : sur le prop de test (boîte biseautée,
## build_stylekit_test_prop.py), au moins un sommet du bevel a une normale
## FACETTÉE (NORMAL) qui diverge notablement de la moyenne par position
## (CUSTOM0) -- c'est exactement la fente que ce ticket corrige.
func test_stylekit_glb_smooth_normal_differs_from_facetted_normal_at_a_hard_edge() -> void:
	var mi := _load_fixture_with_smooth_normal_extension()
	var mesh: Mesh = mi.mesh
	var arrays := mesh.surface_get_arrays(0)
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var custom: PackedFloat32Array = arrays[Mesh.ARRAY_CUSTOM0]
	assert_int(custom.size()).is_equal(normals.size() * 3)
	var max_divergence := 0.0
	for i in normals.size():
		var smooth := Vector3(custom[i * 3], custom[i * 3 + 1], custom[i * 3 + 2])
		if smooth.length() < 0.5:
			continue
		var facetted := normals[i]
		var divergence: float = 1.0 - facetted.normalized().dot(smooth.normalized())
		max_divergence = max(max_divergence, divergence)
	assert_float(max_divergence).append_failure_message(
		"aucun sommet du prop de test n'a de normale lissée notablement différente de NORMAL (max divergence %.4f) -- la fixture ne teste plus rien d'utile pour ce ticket" % max_divergence
	).is_greater(0.02)
