## test_dressing_lod.gd
## Validation TECH-08 (docs/research/07_godot_tech.md §C3, backlog acceptance
## verbatim: "PropCatalog marque chaque prop « cover » ou « decor » ; seuls
## les « decor » reçoivent une visibility range (fade Disabled + hystérésis) ;
## les répétitions de plus de 8 exemplaires passent en MultiMesh ; les draw
## calls du benchmark baissent ; le test échoue si un prop « cover » a une
## visibility range").
##
## Pure/quasi-pure : `PropCatalog.role()`/`info()` sont des lectures de
## manifeste (headless-safe, comme test_propcatalog.gd) ; `place()`/
## `place_many()` n'ont besoin que d'un Node3D parent (pas de scène complète,
## comme test_propcatalog.gd le documente déjà) ; `MapDressing.group_entries`
## est une fonction pure sur des dictionnaires.
##
## Double garde vérifiée explicitement (voir `PropCatalog._apply_decor_fade`
## et `place()`/`place_many()`) : un prop catalogué "decor" posé avec
## `collide=true` (le cas réel de La Fosse — `LaFosseDressing.entries()` pose
## `tyre_stack` en `collide=true` comme couvert de coin, alors que
## `tyre_stack` est catalogué "decor" au sens de maps-spec-v2.md §3.1 "visual,
## thin") NE reçoit JAMAIS de visibility range — seul le rôle catalogue ET
## l'absence de collision pour CETTE pose autorisent le fade.
##
## Relance après échec QA : les sections précédentes valident `MapDressing`/
## `PropCatalog` PRIS ISOLÉMENT, mais l'intégration réelle vit dans
## `MapSetup._build_dressing()` — c'était le morceau manquant (la fonction
## appelait encore `PropCatalog.place()` par entrée, jamais `place_many()`,
## même quand un groupe dépassait `MapDressing.MULTIMESH_THRESHOLD`). La
## dernière section (« MapSetup._build_dressing() ») exerce donc CETTE
## fonction directement (juste un `Node3D` frais, pas besoin de l'ajouter à
## l'arbre : `_build_dressing` ne lit que `self`/`map_id`, jamais `nav_region`
## ni les autres nœuds construits par `_enter_tree`), avec une sonde
## `_StubDressing` (mêmes méthodes que `MapDressing`, 9 répétitions
## synthétiques) pour prouver le branchement MultiMesh SANS dépendre des
## données réelles des six cartes repeintes (qui ne dépassent pas encore le
## seuil aujourd'hui — voir `test_batches_for_map_is_currently_empty_for_
## the_six_repaint_maps` plus haut), puis avec le VRAI `MapDressing.gd` pour
## verrouiller l'absence de régression sur les cartes réelles actuelles.
extends GdUnitTestSuite

const MapSetupScript := preload("res://scripts/levels/maps/MapSetup.gd")
const _EPS := 0.001


## Sonde minimale (RefCounted, mêmes méthodes que `MapDressing`) : 9 "bollard"
## identiques (decor, collide=false — au-delà de `MULTIMESH_THRESHOLD`) pour
## vérifier que `MapSetup._build_dressing()` emprunte RÉELLEMENT le chemin
## MultiMesh, indépendamment des données réelles des six cartes repeintes.
class _StubDressing:
	extends RefCounted

	var _count: int

	func _init(count: int = 9) -> void:
		_count = count

	func for_map(_map_id: String) -> Array:
		var out: Array = []
		for i in _count:
			out.append({"prop": "bollard", "pos": Vector3(float(i) * 2.0, 0.0, 0.0), "rot_y": 0.0, "collide": false})
		return out

	func batches_for_map(map_id: String) -> Dictionary:
		return MapDressing.group_entries(for_map(map_id))


# ======================================================================
#  Helpers
# ======================================================================
static func _mesh_instances(node: Node, out: Array) -> void:
	for child in node.get_children():
		if child is MeshInstance3D:
			out.append(child)
		_mesh_instances(child, out)


## Toutes les instances visuelles (`GeometryInstance3D`) sous `root` : les
## `MeshInstance3D` du `.glb`/repli boîte, ET `root` lui-même s'il est déjà un
## `MultiMeshInstance3D` (place_many()).
static func _geometry_instances(root: Node) -> Array:
	var out: Array = []
	if root is GeometryInstance3D:
		out.append(root)
	_mesh_instances(root, out)
	return out


func _assert_no_visibility_range(gi: GeometryInstance3D, msg: String) -> void:
	if not (gi.visibility_range_end == 0.0 and gi.visibility_range_end_margin == 0.0):
		fail("%s: visibility_range_end=%.2f margin=%.2f (attendu 0/0, aucune range)" % [msg, gi.visibility_range_end, gi.visibility_range_end_margin])


func _assert_decor_visibility_range(gi: GeometryInstance3D, msg: String) -> void:
	if gi.visibility_range_end <= 0.0:
		fail("%s: visibility_range_end=%.2f (attendu > 0, fade decor manquant)" % [msg, gi.visibility_range_end])
	if gi.visibility_range_end_margin <= 0.0:
		fail("%s: visibility_range_end_margin=%.2f (attendu > 0, pas d'hystérésis)" % [msg, gi.visibility_range_end_margin])
	if gi.visibility_range_fade_mode != GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED:
		fail("%s: visibility_range_fade_mode=%d (attendu Disabled, pas de fondu alpha — §C3)" % [msg, gi.visibility_range_fade_mode])


# ======================================================================
#  PropCatalog.role() / info()["role"] — classification cover/decor
# ======================================================================
func test_role_marks_known_cover_props() -> void:
	for prop in ["container_20", "container_40", "wooden_crate", "crate_2", "crate_stack", "sandbags", "pallet", "gantry_crane", "water_tower", "oil_drum", "barrel", "barrel_cluster"]:
		assert_str(PropCatalog.role(prop)).append_failure_message("%s devrait être \"cover\"" % prop).is_equal("cover")


func test_role_marks_known_decor_props() -> void:
	for prop in ["tyre_stack", "bollard", "power_pole", "pipe_straight", "pipe_valve", "shop_sign", "life_ring", "lashing_bar", "junk_pile", "scrap_sheets", "cable_spool", "bottle_crates", "tyre_ground", "fence_broken", "street_lamp", "wires_catenary", "rock_small"]:
		assert_str(PropCatalog.role(prop)).append_failure_message("%s devrait être \"decor\"" % prop).is_equal("decor")


func test_role_unknown_or_uncatalogued_prop_defaults_to_cover() -> void:
	# "windlass" (repli boîte, §7.1/§9) : aucune raison de disparaître au loin.
	assert_str(PropCatalog.role("windlass")).is_equal("cover")
	assert_str(PropCatalog.role("not_a_real_prop_at_all")).is_equal("cover")


func test_info_role_matches_role_and_cover_bool_is_derived() -> void:
	for prop in ["container_20", "tyre_stack", "bollard", "windlass"]:
		var d := PropCatalog.info(prop)
		assert_str(String(d["role"])).is_equal(PropCatalog.role(prop))
		assert_bool(bool(d["cover"])).is_equal(String(d["role"]) != "decor")


# ======================================================================
#  place() — visibility range seulement pour "decor" ET collide=false
# ======================================================================
func test_place_decor_without_collision_gets_a_visibility_range_with_hysteresis() -> void:
	var parent := Node3D.new()
	auto_free(parent)
	var root := PropCatalog.place(parent, "bollard", Vector3.ZERO, 0.0, Color.WHITE, false)
	var vis: Array = _geometry_instances(root)
	assert_int(vis.size()).append_failure_message("bollard: aucune GeometryInstance3D trouvée").is_greater(0)
	for gi in vis:
		_assert_decor_visibility_range(gi as GeometryInstance3D, "bollard (decor, collide=false)")


func test_place_decor_with_collision_never_gets_a_visibility_range() -> void:
	# Le cas réel de La Fosse : `tyre_stack` (catalogué "decor") posé
	# `collide=true` comme couvert de coin — voir LaFosseDressing.entries().
	var parent := Node3D.new()
	auto_free(parent)
	var root := PropCatalog.place(parent, "tyre_stack", Vector3.ZERO, 45.0, Color.WHITE, true)
	var vis: Array = _geometry_instances(root)
	assert_int(vis.size()).append_failure_message("tyre_stack: aucune GeometryInstance3D trouvée").is_greater(0)
	for gi in vis:
		_assert_no_visibility_range(gi as GeometryInstance3D, "tyre_stack (decor MAIS collide=true, couvert réel)")


func test_place_cover_without_collision_never_gets_a_visibility_range() -> void:
	# Acceptance verbatim : "le test échoue si un prop « cover » a une
	# visibility range" — même posé SANS collision (le cas le plus permissif).
	var parent := Node3D.new()
	auto_free(parent)
	var root := PropCatalog.place(parent, "container_20", Vector3.ZERO, 0.0, Color.WHITE, false)
	var vis: Array = _geometry_instances(root)
	assert_int(vis.size()).append_failure_message("container_20: aucune GeometryInstance3D trouvée").is_greater(0)
	for gi in vis:
		_assert_no_visibility_range(gi as GeometryInstance3D, "container_20 (cover)")


func test_place_fallback_box_never_gets_a_visibility_range() -> void:
	# "windlass" (repli boîte, role() -> "cover" par défaut) : la boîte peinte
	# de repli ne doit jamais recevoir de fade non plus.
	var parent := Node3D.new()
	auto_free(parent)
	var root := PropCatalog.place(parent, "windlass", Vector3.ZERO, 0.0, Color.WHITE, false)
	var vis: Array = _geometry_instances(root)
	assert_int(vis.size()).append_failure_message("windlass: aucune GeometryInstance3D trouvée").is_greater(0)
	for gi in vis:
		_assert_no_visibility_range(gi as GeometryInstance3D, "windlass (repli boîte, cover)")


# ======================================================================
#  place_many() — même double garde sur le MultiMeshInstance3D du batch
# ======================================================================
func _nine_transforms() -> Array:
	var out: Array = []
	for i in 9:
		out.append(Transform3D(Basis(), Vector3(float(i) * 2.0, 0.0, 0.0)))
	return out


func test_place_many_batches_decor_without_collision_gets_a_visibility_range() -> void:
	var parent := Node3D.new()
	auto_free(parent)
	PropCatalog.place_many(parent, "bollard", _nine_transforms(), Color.WHITE, false)
	var mmi: MultiMeshInstance3D = null
	for child in parent.get_children():
		if child is MultiMeshInstance3D:
			mmi = child
	assert_object(mmi).append_failure_message("bollard x9, collide=false : aucun MultiMeshInstance3D").is_not_null()
	assert_int(mmi.multimesh.instance_count).is_equal(9)
	_assert_decor_visibility_range(mmi, "batch bollard (decor, collide=false)")


func test_place_many_batches_decor_with_collision_never_gets_a_visibility_range() -> void:
	var parent := Node3D.new()
	auto_free(parent)
	PropCatalog.place_many(parent, "tyre_stack", _nine_transforms(), Color.WHITE, true)
	var mmi: MultiMeshInstance3D = null
	for child in parent.get_children():
		if child is MultiMeshInstance3D:
			mmi = child
	assert_object(mmi).append_failure_message("tyre_stack x9, collide=true : aucun MultiMeshInstance3D").is_not_null()
	_assert_no_visibility_range(mmi, "batch tyre_stack (decor MAIS collide=true)")


func test_place_many_batches_cover_never_gets_a_visibility_range() -> void:
	var parent := Node3D.new()
	auto_free(parent)
	PropCatalog.place_many(parent, "container_20", _nine_transforms(), Color.WHITE, false)
	var mmi: MultiMeshInstance3D = null
	for child in parent.get_children():
		if child is MultiMeshInstance3D:
			mmi = child
	assert_object(mmi).append_failure_message("container_20 x9 : aucun MultiMeshInstance3D").is_not_null()
	_assert_no_visibility_range(mmi, "batch container_20 (cover)")


# ======================================================================
#  MapDressing.group_entries() — seuil "plus de 8 exemplaires" -> MultiMesh
# ======================================================================
static func _synthetic_entries(count: int, prop: String = "bollard", collide: bool = false, tint: Color = Color.WHITE, z: float = 0.0) -> Array:
	var out: Array = []
	for i in count:
		out.append({"prop": prop, "pos": Vector3(float(i), 0.0, z), "rot_y": 0.0, "collide": collide, "tint": tint})
	return out


func test_group_entries_keeps_eight_or_fewer_repeats_as_singles() -> void:
	var grouped := MapDressing.group_entries(_synthetic_entries(8))
	assert_array(grouped["batches"] as Array).is_empty()
	assert_int((grouped["singles"] as Array).size()).is_equal(8)


func test_group_entries_batches_strictly_more_than_eight_repeats() -> void:
	var grouped := MapDressing.group_entries(_synthetic_entries(9))
	var batches: Array = grouped["batches"]
	assert_int(batches.size()).is_equal(1)
	var batch: Dictionary = batches[0]
	assert_str(String(batch["prop"])).is_equal("bollard")
	assert_int((batch["transforms"] as Array).size()).is_equal(9)
	assert_array(grouped["singles"] as Array).is_empty()


func test_group_entries_separates_groups_by_prop_tint_and_collide() -> void:
	var entries: Array = []
	entries.append_array(_synthetic_entries(9, "bollard", false, Color.WHITE, 0.0))
	entries.append_array(_synthetic_entries(9, "bollard", true, Color.WHITE, 1.0))   # collide différent
	entries.append_array(_synthetic_entries(9, "bollard", false, Color.RED, 2.0))    # teinte différente
	entries.append_array(_synthetic_entries(5, "power_pole", false, Color.WHITE, 3.0)) # <= 8, reste single
	var grouped := MapDressing.group_entries(entries)
	var batches: Array = grouped["batches"]
	assert_int(batches.size()).append_failure_message("3 groupes distincts de 9 attendus, %d trouvé(s)" % batches.size()).is_equal(3)
	for batch in batches:
		assert_int(((batch as Dictionary)["transforms"] as Array).size()).is_equal(9)
	assert_int((grouped["singles"] as Array).size()).is_equal(5)


func test_group_entries_batch_transform_matches_pos_and_rotation() -> void:
	var entries: Array = []
	for i in 9:
		entries.append({"prop": "bollard", "pos": Vector3(1.0, 2.0, 3.0), "rot_y": 90.0, "collide": false})
	var grouped := MapDressing.group_entries(entries)
	var batch: Dictionary = (grouped["batches"] as Array)[0]
	for t in (batch["transforms"] as Array):
		var xf: Transform3D = t
		assert_vector(xf.origin).is_equal(Vector3(1.0, 2.0, 3.0))
		assert_float(rad_to_deg(xf.basis.get_euler().y)).is_equal_approx(90.0, _EPS)


func test_group_entries_is_deterministic() -> void:
	var entries := _synthetic_entries(9)
	var a := MapDressing.group_entries(entries.duplicate(true))
	var b := MapDressing.group_entries(entries.duplicate(true))
	assert_str(var_to_str(a)).is_equal(var_to_str(b))


func test_group_entries_of_empty_array_has_no_batches_or_singles() -> void:
	var grouped := MapDressing.group_entries([])
	assert_array(grouped["batches"] as Array).is_empty()
	assert_array(grouped["singles"] as Array).is_empty()


# ======================================================================
#  batches_for_map() vs les six cartes réelles — état actuel documenté :
#  aucune carte n'a encore plus de 8 répétitions d'un même prop (voir les
#  six fichiers dressing/*Dressing.gd), donc "batches" reste vide partout ;
#  ce test verrouille à la fois la cohérence avec `group_entries(for_map())`
#  ET l'absence de régression si un futur ajout fait franchir le seuil.
# ======================================================================
func test_batches_for_map_matches_group_entries_of_for_map_for_every_map() -> void:
	for id in MapDressing.MAP_IDS:
		var direct := MapDressing.batches_for_map(id)
		var via_for_map := MapDressing.group_entries(MapDressing.for_map(id))
		assert_str(var_to_str(direct)).append_failure_message(id).is_equal(var_to_str(via_for_map))


func test_batches_for_map_is_currently_empty_for_the_six_repaint_maps() -> void:
	for id in MapDressing.MAP_IDS:
		var grouped := MapDressing.batches_for_map(id)
		assert_array(grouped["batches"] as Array).append_failure_message("%s: un groupe dépasse déjà 8 exemplaires -- mettre à jour ce test" % id).is_empty()
		assert_int((grouped["singles"] as Array).size()).append_failure_message(id).is_equal((MapDressing.for_map(id) as Array).size())


# ======================================================================
#  MapSetup._build_dressing() — l'intégration réelle (voir la note de tête
#  de fichier « Relance après échec QA »). `_build_dressing` ne touche que
#  `self`/`map_id` : un `Node3D` frais (jamais ajouté à l'arbre, pas de bake
#  navmesh/géométrie) suffit, comme `PropCatalog.place()`/`place_many()`
#  ailleurs dans ce fichier.
# ======================================================================
func test_build_dressing_routes_a_batch_of_nine_through_a_single_multimesh() -> void:
	var setup := MapSetupScript.new()
	setup.map_id = "port_ferraille"
	auto_free(setup)
	setup._build_dressing(_StubDressing.new())

	var batch_mmi: MultiMeshInstance3D = null
	var single_prop_count := 0
	for child in setup.get_children():
		if child is MultiMeshInstance3D and String(child.name) == "Batch_bollard":
			batch_mmi = child
		elif String(child.name) == "Prop_bollard":
			single_prop_count += 1

	assert_object(batch_mmi).append_failure_message("_build_dressing() : les 9 \"bollard\" auraient dû fusionner en un MultiMeshInstance3D \"Batch_bollard\", pas rester en place() individuels").is_not_null()
	assert_int((batch_mmi as MultiMeshInstance3D).multimesh.instance_count).is_equal(9)
	assert_int(single_prop_count).append_failure_message("les 9 \"bollard\" groupés ne doivent plus apparaître comme Prop_bollard individuels").is_equal(0)
	_assert_decor_visibility_range(batch_mmi, "MapSetup._build_dressing() : batch bollard (decor, collide=false)")


func test_build_dressing_keeps_small_groups_as_individual_place_calls() -> void:
	# Sonde à 3 "bollard" (<= MULTIMESH_THRESHOLD) : doit rester le chemin
	# `place()` existant, un enfant direct par exemplaire (jamais de
	# MultiMeshInstance3D pour ce groupe). Compter par NOM ("Prop_bollard")
	# ne marche pas ici : Godot renomme les enfants au nom déjà pris en
	# "@Node3D@N" plutôt qu'en "Prop_bollard2/3" (`add_child` sans
	# `force_readable_name`) — `get_child_count()` reste la mesure fiable,
	# chaque `place()` n'ajoutant toujours qu'UN SEUL enfant direct à `setup`.
	var setup := MapSetupScript.new()
	setup.map_id = "port_ferraille"
	auto_free(setup)
	setup._build_dressing(_StubDressing.new(3))

	for child in setup.get_children():
		assert_bool(child is MultiMeshInstance3D).append_failure_message("3 exemplaires (<= seuil) ne doivent jamais fusionner en MultiMeshInstance3D").is_false()
	assert_int(setup.get_child_count()).is_equal(3)


func test_build_dressing_with_the_real_map_dressing_matches_for_map_count_and_never_batches_today() -> void:
	# Verrou de non-régression avec le VRAI MapDressing.gd (chargé comme le
	# fait MapSetup._load_dressing()) : aucune des six cartes ne dépasse
	# encore le seuil (voir test_batches_for_map_is_currently_empty_for_the_
	# six_repaint_maps ci-dessus), donc _build_dressing() doit toujours poser
	# EXACTEMENT `for_map(id).size()` enfants directs (un par `place()`), zéro
	# MultiMeshInstance3D. Voir la note ci-dessus : compter par nom serait
	# faux (renommage `@Node3D@N` sur collision de nom entre deux `place()`
	# du même prop) — `get_child_count()` est la mesure fiable.
	var real_dressing = load("res://scripts/levels/maps/dressing/MapDressing.gd")
	for id in MapDressing.MAP_IDS:
		var setup := MapSetupScript.new()
		setup.map_id = id
		auto_free(setup)
		setup._build_dressing(real_dressing)

		var mmi_count := 0
		for child in setup.get_children():
			if child is MultiMeshInstance3D:
				mmi_count += 1
		assert_int(mmi_count).append_failure_message("%s : un MultiMeshInstance3D est apparu -- une carte a dépassé le seuil, mettre à jour les tests de seuil" % id).is_equal(0)
		assert_int(setup.get_child_count()).append_failure_message(id).is_equal((MapDressing.for_map(id) as Array).size())
