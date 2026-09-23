## test_propcatalog.gd
## Spec (.orchestrator/maps-spec-v2.md §3.1/§7.1/§8.15) : validation PURE de
## PropCatalog (aucune scène nécessaire pour `names()`/`info()`/`footprint()` —
## `place()`/`place_many()` ont juste besoin d'un Node3D parent, pas d'une
## scène complète). §8.15 : "Every name is in PropCatalog; skin scale is
## 0.8-1.25 per axis; cover collision equals the catalogue size."
extends GdUnitTestSuite


func test_names_is_not_empty() -> void:
	assert_int(PropCatalog.names().size()).is_greater(0)


func test_info_on_known_alias_resolves_manifest_size() -> void:
	# container_20 -> container_20ft (assets/models/props/manifest.json,
	# vérifié en amont : 2.44 x 2.59 x 6.06).
	var d := PropCatalog.info("container_20")
	assert_str(String(d["manifest_name"])).is_equal("container_20ft")
	var size: Vector3 = d["size"]
	assert_float(size.x).is_greater(0.0)
	assert_float(size.y).is_greater(0.0)
	assert_float(size.z).is_greater(0.0)


func test_info_on_unknown_name_falls_back_safely() -> void:
	# "windlass" (§9 : pas d'équivalent construit) -> repli, jamais une erreur.
	var d := PropCatalog.info("windlass")
	assert_str(String(d["manifest_name"])).is_equal("")
	assert_str(String(d["path"])).is_equal("")
	var size: Vector3 = d["size"]
	assert_vector(size).is_equal(Vector3.ONE)


func test_footprint_matches_info_size() -> void:
	for prop in ["container_20", "crate_2", "barrel", "windlass"]:
		assert_vector(PropCatalog.footprint(prop)).is_equal((PropCatalog.info(prop) as Dictionary)["size"])


func test_place_on_unknown_prop_creates_flat_painted_box_no_crash() -> void:
	var parent := Node3D.new()
	auto_free(parent)
	var root := PropCatalog.place(parent, "windlass", Vector3(1, 2, 3), 45.0, Color.RED, true)
	assert_object(root).is_not_null()
	assert_vector(root.position).is_equal(Vector3(1, 2, 3))
	assert_int(root.get_child_count()).is_greater(0)


func test_place_fallback_size_overrides_generic_one_for_skin_use() -> void:
	# La régression corrigée cette manche (Kit.gd "skin") : un prop non
	# catalogué doit utiliser fallback_size (la boîte Kit appelante), pas le
	# Vector3.ONE générique de info() -- sinon le visuel de repli est un cube
	# minuscule flottant à côté de sa vraie collision (b_size).
	var parent := Node3D.new()
	auto_free(parent)
	var root := PropCatalog.place(parent, "windlass", Vector3.ZERO, 0.0, Color.WHITE, true, Vector3(2.5, 1.4, 2.5))
	var mesh := root.get_child(0) as MeshInstance3D
	assert_object(mesh).is_not_null()
	var bm := mesh.mesh as BoxMesh
	assert_vector(bm.size).is_equal(Vector3(2.5, 1.4, 2.5))


func test_place_collide_false_adds_no_collision_body() -> void:
	var parent := Node3D.new()
	auto_free(parent)
	var root := PropCatalog.place(parent, "windlass", Vector3.ZERO, 0.0, Color.WHITE, false)
	for child in root.get_children():
		assert_bool(child is StaticBody3D).append_failure_message("visual-only place() must not add a StaticBody3D").is_false()


func test_place_many_below_three_transforms_does_not_batch() -> void:
	var parent := Node3D.new()
	auto_free(parent)
	PropCatalog.place_many(parent, "windlass", [Transform3D(Basis(), Vector3.ZERO), Transform3D(Basis(), Vector3.ONE)], Color.WHITE, true)
	for child in parent.get_children():
		assert_bool(child is MultiMeshInstance3D).append_failure_message("< 3 transforms must never batch into a MultiMesh").is_false()


func test_place_many_at_three_or_more_with_no_glb_falls_back_per_transform() -> void:
	# "windlass" n'a pas de .glb (repli boîte) -> _mesh_for() renvoie null ->
	# place_many() retombe sur place() par transform (pas de MultiMesh),
	# comportement identique à place() individuel, juste pas fusionné.
	var parent := Node3D.new()
	auto_free(parent)
	var xf: Array = [Transform3D(Basis(), Vector3.ZERO), Transform3D(Basis(), Vector3(2, 0, 0)), Transform3D(Basis(), Vector3(4, 0, 0))]
	PropCatalog.place_many(parent, "windlass", xf, Color.WHITE, true)
	assert_int(parent.get_child_count()).is_equal(3)
	for child in parent.get_children():
		assert_bool(child is MultiMeshInstance3D).append_failure_message("no .glb -> never a MultiMesh").is_false()
