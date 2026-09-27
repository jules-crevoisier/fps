## test_thrown_utility_models.gd
## Spec (checkpoint modèles réels, 2026-09-27) : chaque type d'utilitaire
## charge son .glb réel (assets/models/utilities/{frag,flash,smoke}.glb,
## livrés par le lead) via ThrownUtility.build_held_mesh — utilisé aussi bien
## pour l'objet volant que pour la grenade tenue en main (FPArmsRig.
## attach_grenade) — et lui applique le style toon (ToonStyle.apply_to :
## chaque MeshInstance3D doit porter un ShaderMaterial après coup, jamais le
## StandardMaterial3D importé brut du glTF).
extends GdUnitTestSuite


## Cherche récursivement le premier MeshInstance3D sous `node` — "" absent de
## la recherche, jamais un accès direct à un index d'enfant fixe (le glb peut
## nicher le mesh sous un nœud intermédiaire selon l'export).
static func _find_mesh_instance(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
	for child in node.get_children():
		var found := _find_mesh_instance(child)
		if found:
			return found
	return null


func _built_and_freed(kind: int) -> Node3D:
	var built: Node3D = auto_free(ThrownUtility.build_held_mesh(kind))
	return built


## Matériau EFFECTIF d'un MeshInstance3D après ToonStyle.apply_to — même
## priorité que ToonStyle._swap_mesh_materials : `material_override` (surtout
## utilisé par les placeholders de repli) sinon le matériau de la PREMIÈRE
## surface (glTF importé, chemin réel de frag/flash/smoke.glb) — JAMAIS
## `mesh.surface_get_material` (ressource `Mesh` partagée, jamais réécrite :
## ToonStyle pose le remplacement sur l'INSTANCE via
## `set_surface_override_material`, voir ToonStyle.gd).
static func _effective_material(mi: MeshInstance3D) -> Material:
	if mi.material_override:
		return mi.material_override
	if mi.mesh and mi.mesh.get_surface_count() > 0:
		var over := mi.get_surface_override_material(0)
		return over if over else mi.mesh.surface_get_material(0)
	return null


func test_frag_model_loads_a_real_mesh_with_toon_material() -> void:
	var built := _built_and_freed(UtilityDatabase.FRAG)
	var mi := _find_mesh_instance(built)
	assert_object(mi).append_failure_message(
		"assets/models/utilities/frag.glb doit produire au moins un MeshInstance3D"
	).is_not_null()
	var mat := _effective_material(mi)
	assert_object(mat).append_failure_message(
		"ToonStyle.apply_to doit remplacer le matériau importé par un ShaderMaterial (toon_bd.gdshader)"
	).is_instanceof(ShaderMaterial)


func test_flash_model_loads_a_real_mesh_with_toon_material() -> void:
	var built := _built_and_freed(UtilityDatabase.FLASH)
	var mi := _find_mesh_instance(built)
	assert_object(mi).is_not_null()
	var mat := _effective_material(mi)
	assert_object(mat).is_instanceof(ShaderMaterial)


func test_smoke_model_loads_a_real_mesh_with_toon_material() -> void:
	var built := _built_and_freed(UtilityDatabase.SMOKE)
	var mi := _find_mesh_instance(built)
	assert_object(mi).is_not_null()
	var mat := _effective_material(mi)
	assert_object(mat).is_instanceof(ShaderMaterial)


func test_unknown_kind_falls_back_to_a_placeholder_without_crashing() -> void:
	var built := _built_and_freed(99)
	var mi := _find_mesh_instance(built)
	assert_object(mi).append_failure_message(
		"un kind inconnu doit retomber sur le cube de repli, jamais planter"
	).is_not_null()
