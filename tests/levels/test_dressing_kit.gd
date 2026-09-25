## test_dressing_kit.gd (ART-87)
## Spec de `scripts/levels/dressing/DressingKit.gd` — critères d'acceptation
## du contrat :
##   1. déterminisme par seed (`scatter_transforms`/`cluster_transforms`) ;
##   2. contact au sol (toutes les fonctions de calcul de transformes) ;
##   3. flèche des câbles (`cable_points`/`poles_and_cables`) ;
##   4. aucune intersection avec une boîte interdite (`exclude`) ;
##   5. MultiMesh <= 1 draw call par type (`scatter`).
##
## Probe autonome (hors dépôt, `mm_probe.gd` : MultiMesh.new(), set_instance_
## transform() puis get_instance_transform() en `--headless`) : sous le
## driver de rendu factice headless, `MultiMesh.get_instance_transform()`
## renvoie TOUJOURS l'identité, quoi que `set_instance_transform()` ait posé
## -- `buffer` aussi revient vide. Godot 4.7 ne conserve donc PAS les données
## MultiMesh côté CPU une fois posées sans RenderingServer réel. Les critères
## 1/2/4 (déterminisme, contact au sol, exclusion) portent donc sur les
## fonctions PURES de calcul de transformes (`fence_transforms`,
## `cluster_transforms`, `scatter_transforms`, `cable_points`), jamais sur
## `MultiMesh.get_instance_transform()` -- exactement le même choix que
## `tests/levels/test_backdrop.gd` (teste `build_skirt_mesh`/
## `directional_landmarks`, jamais un rendu). Les fonctions qui posent des
## nœuds (`fence_run`, `cluster_against_wall`, `scatter`, `poles_and_cables`)
## restent couvertes, mais STRUCTURELLEMENT (présence/nom/nombre de nœuds,
## `instance_count`, chemin < 3 -> individuel qui, lui, reste un vrai
## Node3D.position lisible).
extends GdUnitTestSuite

const _EPS := 0.001


func _make_root() -> Node3D:
	var root := Node3D.new()
	add_child(root)
	auto_free(root)
	return root


## Les fonctions qui posent < 3 instances retombent sur `PropCatalog.place`
## (un vrai Node3D par instance) -- son `.position` est une propriété
## ordinaire, lisible sans réserve en headless (contrairement à
## `MultiMesh.get_instance_transform()`, voir l'en-tête du fichier).
## Filtre par TYPE, jamais par nom "Prop_<prop>" : `Node.add_child()` sans
## `force_readable_name` (le défaut, utilisé partout dans ce dépôt) ne rend
## PAS un nom unique lisible en cas de collision entre deux frères de même
## nom (probe autonome hors dépôt : `Foo`/`Foo` posés côte à côte donnent
## `Foo`/`@Node3D@3`, jamais `Foo`/`Foo2`) -- au moins 2 poteaux/panneaux/
## caisses posés individuellement partagent tous le même nom de départ
## ("Prop_power_pole", etc.) et perdraient donc ce nom au-delà du premier.
## Les seuls autres enfants directs possibles ici sont "Cable"
## (MeshInstance3D, poles_and_cables) et un MultiMeshInstance3D (chemin
## batché) -- les exclure suffit à isoler les racines individuelles.
func _collect_individual_positions(root: Node3D) -> Array:
	var out: Array = []
	for child in root.get_children():
		if child is Node3D and not (child is MeshInstance3D) and not (child is MultiMeshInstance3D):
			out.append((child as Node3D).position)
	return out


func _flatten_transforms(by_key: Dictionary) -> Array:
	var out: Array = []
	for key in by_key.keys():
		for xf in (by_key[key] as Array):
			out.append(xf)
	return out


# =====================================================================
#  1. Déterminisme par seed
# =====================================================================

func test_scatter_transforms_is_deterministic_for_the_same_seed() -> void:
	var area := Rect2(0.0, 0.0, 12.0, 12.0)
	var a := DressingKit.scatter_transforms(area, ["rock", "tuft"], 1.5, 42)
	var b := DressingKit.scatter_transforms(area, ["rock", "tuft"], 1.5, 42)
	var xforms_a := _flatten_transforms(a)
	var xforms_b := _flatten_transforms(b)
	assert_int(xforms_a.size()).append_failure_message(
		"deux appels au même seed ne produisent pas le même nombre d'instances"
	).is_equal(xforms_b.size())
	assert_bool(xforms_a.is_empty()).is_false()
	for i in xforms_a.size():
		var ta: Transform3D = xforms_a[i]
		var tb: Transform3D = xforms_b[i]
		assert_vector(ta.origin).append_failure_message(
			"scatter_transforms() n'est pas déterministe à l'instance %d pour le même seed" % i
		).is_equal_approx(tb.origin, Vector3.ONE * _EPS)


func test_scatter_transforms_with_a_different_seed_moves_at_least_one_instance() -> void:
	var area := Rect2(0.0, 0.0, 12.0, 12.0)
	var a := _flatten_transforms(DressingKit.scatter_transforms(area, ["rock"], 1.5, 1))
	var b := _flatten_transforms(DressingKit.scatter_transforms(area, ["rock"], 1.5, 2))
	var identical := a.size() == b.size()
	if identical:
		for i in a.size():
			var ta: Transform3D = a[i]
			var tb: Transform3D = b[i]
			if ta.origin.distance_to(tb.origin) > _EPS:
				identical = false
				break
	assert_bool(identical).append_failure_message(
		"deux seeds différents (1 et 2) produisent exactement le même semis -- le seed n'est pas utilisé"
	).is_false()


func test_cluster_transforms_is_deterministic_for_the_same_seed() -> void:
	var a := DressingKit.cluster_transforms(Vector3(2.0, 0.0, 5.0), Vector3(0.0, 0.0, 1.0), "junk", 3.0, 7)
	var b := DressingKit.cluster_transforms(Vector3(2.0, 0.0, 5.0), Vector3(0.0, 0.0, 1.0), "junk", 3.0, 7)
	var xforms_a := _flatten_transforms(a)
	var xforms_b := _flatten_transforms(b)
	assert_int(xforms_a.size()).is_equal(xforms_b.size())
	assert_bool(xforms_a.is_empty()).is_false()
	for i in xforms_a.size():
		var ta: Transform3D = xforms_a[i]
		var tb: Transform3D = xforms_b[i]
		assert_vector(ta.origin).append_failure_message(
			"cluster_transforms() n'est pas déterministe à l'instance %d pour le même seed" % i
		).is_equal_approx(tb.origin, Vector3.ONE * _EPS)


func test_cluster_transforms_with_a_different_seed_moves_at_least_one_instance() -> void:
	var a := _flatten_transforms(DressingKit.cluster_transforms(Vector3.ZERO, Vector3(0, 0, 1), "junk", 3.0, 1))
	var b := _flatten_transforms(DressingKit.cluster_transforms(Vector3.ZERO, Vector3(0, 0, 1), "junk", 3.0, 2))
	var identical := a.size() == b.size()
	if identical:
		for i in a.size():
			var ta: Transform3D = a[i]
			var tb: Transform3D = b[i]
			if ta.origin.distance_to(tb.origin) > _EPS:
				identical = false
				break
	assert_bool(identical).append_failure_message(
		"deux seeds différents (1 et 2) produisent exactement la même grappe -- le seed n'est pas utilisé"
	).is_false()


func test_cable_points_is_a_pure_deterministic_function() -> void:
	var a := DressingKit.cable_points(Vector3(0, 5, 0), Vector3(10, 5, 0), 1.2, 8)
	var b := DressingKit.cable_points(Vector3(0, 5, 0), Vector3(10, 5, 0), 1.2, 8)
	assert_int(a.size()).is_equal(b.size())
	for i in a.size():
		assert_vector(a[i]).is_equal_approx(b[i], Vector3.ONE * _EPS)


func test_fence_transforms_is_a_pure_deterministic_function() -> void:
	var points := [Vector3(0, 0, 0), Vector3(8.8, 0, 0)]
	var a := DressingKit.fence_transforms(points, "wood")
	var b := DressingKit.fence_transforms(points, "wood")
	assert_int(a.size()).is_equal(b.size())
	for i in a.size():
		var ta: Transform3D = a[i]
		var tb: Transform3D = b[i]
		assert_vector(ta.origin).is_equal_approx(tb.origin, Vector3.ONE * _EPS)


# =====================================================================
#  2. Contact au sol
# =====================================================================

func test_fence_transforms_panels_sit_at_the_given_floor_height() -> void:
	var xforms := DressingKit.fence_transforms([Vector3(0, 2.0, 0), Vector3(8.8, 2.0, 0)], "wood")
	assert_bool(xforms.is_empty()).is_false()
	for xf in xforms:
		var t3: Transform3D = xf
		assert_float(t3.origin.y).append_failure_message(
			"un panneau de clôture ne touche pas le sol du tronçon (2.0 attendu) : %s" % t3.origin
		).is_equal_approx(2.0, _EPS)


func test_cluster_transforms_items_sit_at_the_anchor_height() -> void:
	var anchor := Vector3(4.0, 1.5, -2.0)
	var by_name := DressingKit.cluster_transforms(anchor, Vector3(0, 0, 1), "crates", 4.0, 11)
	var xforms := _flatten_transforms(by_name)
	assert_bool(xforms.is_empty()).is_false()
	for xf in xforms:
		var t3: Transform3D = xf
		assert_float(t3.origin.y).append_failure_message(
			"une caisse de la grappe ne touche pas le sol de l'ancre (%.3f attendu) : %s" % [anchor.y, t3.origin]
		).is_equal_approx(anchor.y, _EPS)


func test_scatter_transforms_instances_sit_at_the_requested_ground_height() -> void:
	var by_kind := DressingKit.scatter_transforms(Rect2(0, 0, 8.0, 8.0), ["rock"], 1.0, 3, [], 3.5)
	var xforms := _flatten_transforms(by_kind)
	assert_bool(xforms.is_empty()).is_false()
	for xf in xforms:
		var t3: Transform3D = xf
		assert_float(t3.origin.y).append_failure_message(
			"le semis ignore le paramètre `y` (sol attendu à 3.5) : %s" % t3.origin
		).is_equal_approx(3.5, _EPS)


func test_poles_and_cables_individual_fallback_sits_at_the_given_floor_height() -> void:
	# < 3 poteaux -> repli individuel (PropCatalog.place, Node3D.position réel).
	var parent := _make_root()
	var result := DressingKit.poles_and_cables(parent, [Vector3(0, 2.5, 0), Vector3(10, 2.5, 0)], 0.4, 6.0)
	var positions := _collect_individual_positions(result)
	assert_int(positions.size()).is_equal(2)
	for p in positions:
		assert_float((p as Vector3).y).append_failure_message(
			"un poteau (repli individuel) ne touche pas le sol du point d'entrée (2.5 attendu) : %s" % p
		).is_equal_approx(2.5, _EPS)


# =====================================================================
#  3. Flèche des câbles
# =====================================================================

func test_cable_points_keeps_the_exact_endpoints() -> void:
	var a := Vector3(1.0, 4.0, -2.0)
	var b := Vector3(9.0, 4.0, 3.0)
	var pts := DressingKit.cable_points(a, b, 0.8, 10)
	assert_vector(pts[0]).is_equal_approx(a, Vector3.ONE * _EPS)
	assert_vector(pts[pts.size() - 1]).is_equal_approx(b, Vector3.ONE * _EPS)


## Invariant exact de la parabole (voir le commentaire de `cable_points`) :
## le point médian descend d'EXACTEMENT `sag` sous le milieu du segment a-b,
## quel que soit `sag`.
func test_cable_points_midpoint_dips_by_exactly_sag() -> void:
	for sag in [0.2, 0.8, 2.5]:
		var a := Vector3(0.0, 6.0, 0.0)
		var b := Vector3(10.0, 6.0, 0.0)
		var pts := DressingKit.cable_points(a, b, sag, 10)
		var mid := pts[pts.size() / 2]
		var straight_mid_y: float = (a.y + b.y) * 0.5
		assert_float(straight_mid_y - mid.y).append_failure_message(
			"la flèche du câble (sag=%.2f) n'est pas exactement respectée au milieu (%.4f mesuré)" % [sag, straight_mid_y - mid.y]
		).is_equal_approx(sag, 0.01)


func test_cable_points_with_zero_sag_is_a_straight_line() -> void:
	var a := Vector3(0.0, 2.0, 0.0)
	var b := Vector3(6.0, 2.0, 0.0)
	var pts := DressingKit.cable_points(a, b, 0.0, 6)
	for p in pts:
		assert_float((p as Vector3).y).is_equal_approx(2.0, _EPS)


func test_poles_and_cables_builds_one_cable_mesh_per_gap_between_poles() -> void:
	var parent := _make_root()
	var points := [Vector3(0, 0, 0), Vector3(8, 0, 0), Vector3(16, 0, 0)]
	var result := DressingKit.poles_and_cables(parent, points, 0.5, 5.0)
	var cable_count := 0
	for child in result.get_children():
		if child is MeshInstance3D:
			cable_count += 1
	assert_int(cable_count).append_failure_message(
		"poles_and_cables() doit poser un câble par intervalle entre poteaux (%d attendus pour %d points)" % [points.size() - 1, points.size()]
	).is_equal(points.size() - 1)


# =====================================================================
#  4. Aucune intersection avec une boîte interdite
# =====================================================================

func test_scatter_transforms_never_places_an_instance_inside_an_excluded_box() -> void:
	var forbidden := AABB(Vector3(0.0, -2.0, 0.0), Vector3(6.0, 4.0, 12.0))
	var by_kind := DressingKit.scatter_transforms(Rect2(0.0, 0.0, 12.0, 12.0), ["rock"], 2.5, 9, [forbidden])
	var xforms := _flatten_transforms(by_kind)
	assert_bool(xforms.is_empty()).append_failure_message(
		"aucune instance produite -- le test ne prouve rien, augmenter la densité/la zone"
	).is_false()
	for xf in xforms:
		var t3: Transform3D = xf
		assert_bool(forbidden.has_point(t3.origin)).append_failure_message(
			"une instance du semis est tombée dans la boîte interdite : %s" % t3.origin
		).is_false()


func test_cluster_transforms_never_places_an_instance_inside_an_excluded_box() -> void:
	var anchor := Vector3(0.0, 0.0, 0.0)
	# Couvre la moitié PROCHE du mur de l'empreinte de la grappe (voir
	# DressingKit._CLUSTER_DEPTH) -- ne laisse que la moitié lointaine libre.
	var forbidden := AABB(Vector3(-2.0, -2.0, 0.0), Vector3(4.0, 4.0, 0.6))
	var by_name := DressingKit.cluster_transforms(anchor, Vector3(0, 0, 1), "barrels", 6.0, 3, [forbidden])
	var xforms := _flatten_transforms(by_name)
	assert_bool(xforms.is_empty()).append_failure_message(
		"aucune instance produite -- le test ne prouve rien"
	).is_false()
	for xf in xforms:
		var t3: Transform3D = xf
		assert_bool(forbidden.has_point(t3.origin)).append_failure_message(
			"un fût de la grappe est tombé dans la boîte interdite : %s" % t3.origin
		).is_false()


# =====================================================================
#  5. MultiMesh <= 1 draw call par type
# =====================================================================

func test_scatter_creates_exactly_one_multimesh_instance_per_kind_that_got_instances() -> void:
	var parent := _make_root()
	var kinds := ["rock", "plank", "tuft", "tumbleweed"]
	var result := DressingKit.scatter(parent, Rect2(0.0, 0.0, 10.0, 10.0), kinds, 3.0, 5)
	var mmi_count := 0
	for child in result.get_children():
		if child is MultiMeshInstance3D:
			mmi_count += 1
	assert_int(mmi_count).append_failure_message(
		"densité assez haute (3/m² sur 100 m², 4 kinds) : chaque kind devrait produire exactement un MultiMeshInstance3D"
	).is_equal(kinds.size())
	for kind in kinds:
		var node_name := "Scatter_%s" % kind
		var matches := 0
		for child in result.get_children():
			if String(child.name) == node_name:
				matches += 1
		assert_int(matches).append_failure_message(
			"le kind « %s » doit produire exactement un MultiMeshInstance3D (%d trouvés)" % [kind, matches]
		).is_equal(1)


func test_scatter_multimesh_instance_uses_a_single_shared_mesh_and_its_instance_count_matches_the_pure_computation() -> void:
	var parent := _make_root()
	var result := DressingKit.scatter(parent, Rect2(0.0, 0.0, 10.0, 10.0), ["rock"], 3.0, 5)
	var mmi := result.get_node_or_null("Scatter_rock") as MultiMeshInstance3D
	assert_that(mmi).is_not_null()
	assert_that(mmi.multimesh.mesh).append_failure_message(
		"le MultiMesh du semis doit partager UN SEUL Mesh (un draw call par type)"
	).is_not_null()
	assert_int((mmi.multimesh.mesh as Mesh).get_surface_count()).is_equal(1)
	# `instance_count` (contrairement à `get_instance_transform`, voir
	# l'en-tête du fichier) reste lisible en headless : recoupe la scène avec
	# la fonction pure qui l'a calculée.
	var expected: int = (DressingKit.scatter_transforms(Rect2(0.0, 0.0, 10.0, 10.0), ["rock"], 3.0, 5)["rock"] as Array).size()
	assert_int(mmi.multimesh.instance_count).is_equal(expected)


func test_fence_run_and_cluster_against_wall_also_batch_from_three_instances_up() -> void:
	var parent := _make_root()
	var result := DressingKit.fence_run(parent, [Vector3(0, 0, 0), Vector3(6.6, 0, 0)], "wood")
	var batch := result.get_node_or_null("Batch_fence_wood") as MultiMeshInstance3D
	assert_that(batch).append_failure_message(
		"3 panneaux ou plus doivent être fusionnés en un seul MultiMeshInstance3D (Batch_fence_wood)"
	).is_not_null()
	assert_int(batch.multimesh.instance_count).is_equal(
		DressingKit.fence_transforms([Vector3(0, 0, 0), Vector3(6.6, 0, 0)], "wood").size()
	)


# =====================================================================
#  Structurel : répartition par kind, repli sous le seuil de 3 instances
# =====================================================================

func test_cluster_transforms_barrels_only_returns_oil_drum() -> void:
	var by_name := DressingKit.cluster_transforms(Vector3(0, 0, 0), Vector3(0, 0, 1), "barrels", 6.0, 4)
	assert_array(by_name.keys()).append_failure_message(
		"le kind « barrels » doit produire uniquement « oil_drum » : %s" % [by_name.keys()]
	).is_equal(["oil_drum"])


func test_poles_and_cables_falls_back_to_individual_placement_under_three_poles() -> void:
	var parent := _make_root()
	var result := DressingKit.poles_and_cables(parent, [Vector3(0, 0, 0), Vector3(10, 0, 0)], 0.4, 6.0)
	assert_that(result.get_node_or_null("Batch_power_pole")).append_failure_message(
		"moins de 3 poteaux ne doit PAS créer de MultiMesh"
	).is_null()
	var pole_count := _collect_individual_positions(result).size()
	assert_int(pole_count).is_equal(2)


func test_fence_run_unknown_kind_falls_back_to_wood_without_crashing() -> void:
	var parent := _make_root()
	var result := DressingKit.fence_run(parent, [Vector3(0, 0, 0), Vector3(6.6, 0, 0)], "does_not_exist")
	assert_that(result).is_not_null()
	assert_that(result.get_node_or_null("Batch_fence_wood")).is_not_null()


func test_scatter_transforms_returns_empty_kinds_for_an_empty_kinds_list() -> void:
	var by_kind := DressingKit.scatter_transforms(Rect2(0, 0, 10, 10), [], 2.0, 1)
	assert_that(by_kind).is_not_null()
	assert_int(by_kind.keys().size()).is_equal(0)


func test_scatter_returns_an_empty_root_for_an_empty_kinds_list() -> void:
	var parent := _make_root()
	var result := DressingKit.scatter(parent, Rect2(0, 0, 10, 10), [], 2.0, 1)
	assert_that(result).is_not_null()
	assert_int(result.get_child_count()).is_equal(0)


# =====================================================================
#  6. Grappes de décor peint Tripo (ART-89)
# =====================================================================
## `tripo_row`/`load_tripo` posent de VRAIS nœuds chargés depuis
## assets/models/props/wasteland/tripo/*.glb (installés par ce contrat,
## tools/ai3d/manifests/painted_env.yaml) : leur `.position`/`.scale` sont des propriétés
## Node3D ordinaires, lisibles sans réserve en headless (même raison que
## `_collect_individual_positions` en tête de fichier -- ce n'est PAS un MultiMesh). Filtre
## par TYPE (exclut StaticBody3D, les collisions boîtes posées par instance) plutôt que par
## nom, même contrainte que `_collect_individual_positions`.
func _collect_tripo_instance_positions(root: Node3D) -> Array:
	var out: Array = []
	for child in root.get_children():
		if child is Node3D and not (child is StaticBody3D):
			out.append(child)
	return out


func test_tripo_kind_file_maps_the_four_art89_kinds_to_their_painted_tripo_files() -> void:
	assert_that(DressingKit.TRIPO_KIND_FILE).append_failure_message(
		"les 4 sortes du contrat ART-89 doivent résoudre vers leurs fichiers Tripo peints installés"
	).is_equal({
		"car_wreck": "wl_car_wreck",
		"fence_broken": "wl_fence_broken",
		"market_stall": "wl_market_stall",
		"junk_pile": "wl_junk_pile",
	})


func test_load_tripo_returns_null_for_an_unknown_kind() -> void:
	assert_that(DressingKit.load_tripo("does_not_exist")).append_failure_message(
		"load_tripo() doit renvoyer null (jamais planter) pour une sorte inconnue"
	).is_null()


func test_load_tripo_loads_a_node_for_each_of_the_four_installed_kinds() -> void:
	for kind in DressingKit.TRIPO_KIND_FILE.keys():
		var inst := DressingKit.load_tripo(String(kind))
		assert_that(inst).append_failure_message(
			"load_tripo() doit charger un nœud pour la sorte « %s » (fichier installé par ce contrat, ART-89)" % kind
		).is_not_null()
		if inst != null:
			auto_free(inst)


func test_tripo_row_positions_is_a_pure_deterministic_function() -> void:
	var points := [Vector3(0, 0, 0), Vector3(8.8, 0, 0)]
	var a := DressingKit.tripo_row_positions(points, 2.2)
	var b := DressingKit.tripo_row_positions(points, 2.2)
	assert_int(a.size()).is_equal(b.size())
	assert_bool(a.is_empty()).is_false()
	for i in a.size():
		assert_vector(a[i]).is_equal_approx(b[i], Vector3.ONE * _EPS)


func test_tripo_row_positions_sit_at_the_starting_point_floor_height() -> void:
	var positions := DressingKit.tripo_row_positions([Vector3(0, 3.0, 0), Vector3(8.8, 3.0, 0)], 2.2)
	assert_bool(positions.is_empty()).is_false()
	for p in positions:
		assert_float((p as Vector3).y).append_failure_message(
			"une instance de tripo_row_positions() ne touche pas le sol du tronçon (3.0 attendu) : %s" % p
		).is_equal_approx(3.0, _EPS)


func test_tripo_row_positions_counts_about_one_instance_per_spacing() -> void:
	var positions := DressingKit.tripo_row_positions([Vector3(0, 0, 0), Vector3(20.0, 0, 0)], 2.0)
	assert_int(positions.size()).append_failure_message(
		"20 m espacés de 2 m devraient donner ~10 instances : %d trouvées" % positions.size()
	).is_equal(10)


func test_tripo_variants_is_deterministic_for_the_same_seed() -> void:
	var a := DressingKit.tripo_variants("fence_broken", 6, 42)
	var b := DressingKit.tripo_variants("fence_broken", 6, 42)
	assert_int(a.size()).is_equal(b.size())
	for i in a.size():
		var va: Dictionary = a[i]
		var vb: Dictionary = b[i]
		assert_float(va["yaw_deg"]).append_failure_message(
			"tripo_variants() n'est pas déterministe à l'instance %d pour le même seed" % i
		).is_equal_approx(vb["yaw_deg"], 0.001)
		assert_bool(va["mirror"]).is_equal(vb["mirror"])
		var ta: Color = va["tint"]
		var tb: Color = vb["tint"]
		assert_float(ta.r).is_equal_approx(tb.r, _EPS)
		assert_float(ta.g).is_equal_approx(tb.g, _EPS)
		assert_float(ta.b).is_equal_approx(tb.b, _EPS)


func test_tripo_variants_with_a_different_seed_changes_at_least_one_instance() -> void:
	var a := DressingKit.tripo_variants("junk_pile", 6, 1)
	var b := DressingKit.tripo_variants("junk_pile", 6, 2)
	var identical := true
	for i in a.size():
		var va: Dictionary = a[i]
		var vb: Dictionary = b[i]
		if not is_equal_approx(va["yaw_deg"], vb["yaw_deg"]) or va["mirror"] != vb["mirror"]:
			identical = false
			break
	assert_bool(identical).append_failure_message(
		"deux seeds différents (1 et 2) produisent exactement les mêmes variantes -- le seed n'est pas utilisé"
	).is_false()


## Contrat ART-89 : « jamais deux voisins identiques au même angle ». Balayé sur plusieurs
## sortes/seeds/densités pour prouver l'invariant, pas juste un seed qui s'y prête.
func test_tripo_variants_never_repeats_the_same_yaw_and_mirror_on_consecutive_neighbors() -> void:
	for kind in DressingKit.TRIPO_KIND_FILE.keys():
		for seed_value in [1, 2, 3, 4, 5, 42, 1000]:
			var variants := DressingKit.tripo_variants(String(kind), 12, seed_value)
			for i in range(1, variants.size()):
				var prev: Dictionary = variants[i - 1]
				var cur: Dictionary = variants[i]
				var same_angle := is_equal_approx(round(prev["yaw_deg"]), round(cur["yaw_deg"]))
				var same_mirror: bool = prev["mirror"] == cur["mirror"]
				assert_bool(same_angle and same_mirror).append_failure_message(
					"« %s » seed=%d : voisins %d/%d identiques (angle %.1f°, miroir %s)" % [
						kind, seed_value, i - 1, i, cur["yaw_deg"], cur["mirror"]]
				).is_false()


func test_tripo_variants_tint_varies_only_slightly_between_instances_of_the_same_kind() -> void:
	for kind in DressingKit.TRIPO_KIND_FILE.keys():
		var variants := DressingKit.tripo_variants(String(kind), 8, 23)
		var first_tint: Color = variants[0]["tint"]
		for variant in variants:
			var tint: Color = variant["tint"]
			assert_float(tint.r).is_between(0.0, 1.0)
			assert_float(tint.g).is_between(0.0, 1.0)
			assert_float(tint.b).is_between(0.0, 1.0)
			assert_float(absf(tint.r - first_tint.r)).append_failure_message(
				"la teinte de « %s » varie trop d'une instance à l'autre (canal R)" % kind
			).is_less_equal(0.13)
			assert_float(absf(tint.g - first_tint.g)).append_failure_message(
				"la teinte de « %s » varie trop d'une instance à l'autre (canal G)" % kind
			).is_less_equal(0.13)
			assert_float(absf(tint.b - first_tint.b)).append_failure_message(
				"la teinte de « %s » varie trop d'une instance à l'autre (canal B)" % kind
			).is_less_equal(0.13)


func test_tripo_row_places_one_instance_per_position_with_a_box_collision_each() -> void:
	var parent := _make_root()
	var points := [Vector3(0, 0, 0), Vector3(8.8, 0, 0)]
	var spacing := 2.2
	var result := DressingKit.tripo_row(parent, points, "fence_broken", spacing, 5)
	var expected_positions := DressingKit.tripo_row_positions(points, spacing)
	var instances := _collect_tripo_instance_positions(result)
	assert_int(instances.size()).append_failure_message(
		"tripo_row() doit poser une instance par position de tripo_row_positions()"
	).is_equal(expected_positions.size())
	for i in expected_positions.size():
		assert_vector((instances[i] as Node3D).position).append_failure_message(
			"l'instance %d de tripo_row() n'est pas à la position attendue" % i
		).is_equal_approx(expected_positions[i], Vector3.ONE * _EPS)
	var collision_count := 0
	for child in result.get_children():
		if child is StaticBody3D:
			collision_count += 1
	assert_int(collision_count).append_failure_message(
		"tripo_row() doit poser une StaticBody3D de collision boîte par instance"
	).is_equal(expected_positions.size())


func test_tripo_row_applies_mirror_to_local_x_scale_matching_the_variant() -> void:
	var parent := _make_root()
	var points := [Vector3(0, 0, 0), Vector3(24.0, 0, 0)]
	var spacing := 1.5
	var result := DressingKit.tripo_row(parent, points, "junk_pile", spacing, 3)
	var expected_variants := DressingKit.tripo_variants(
		"junk_pile", DressingKit.tripo_row_positions(points, spacing).size(), 3)
	var instances := _collect_tripo_instance_positions(result)
	assert_int(instances.size()).is_equal(expected_variants.size())
	var saw_mirror := false
	var saw_unmirrored := false
	for i in instances.size():
		var variant: Dictionary = expected_variants[i]
		var scale_x: float = (instances[i] as Node3D).scale.x
		if variant["mirror"]:
			saw_mirror = true
			assert_float(scale_x).append_failure_message(
				"instance %d attendue en miroir (scale.x < 0)" % i
			).is_less(0.0)
		else:
			saw_unmirrored = true
			assert_float(scale_x).append_failure_message(
				"instance %d attendue SANS miroir (scale.x > 0)" % i
			).is_greater(0.0)
	assert_bool(saw_mirror).append_failure_message(
		"aucune instance en miroir sur cet échantillon -- le test ne prouve rien, changer seed/densité"
	).is_true()
	assert_bool(saw_unmirrored).append_failure_message(
		"aucune instance SANS miroir sur cet échantillon -- le test ne prouve rien"
	).is_true()


func test_tripo_row_unknown_kind_produces_no_instances_without_crashing() -> void:
	var parent := _make_root()
	var result := DressingKit.tripo_row(parent, [Vector3(0, 0, 0), Vector3(6.0, 0, 0)], "does_not_exist", 2.0, 1)
	assert_that(result).is_not_null()
	assert_int(_collect_tripo_instance_positions(result).size()).is_equal(0)


func test_tripo_row_returns_an_empty_root_for_a_single_point_polyline() -> void:
	var parent := _make_root()
	var result := DressingKit.tripo_row(parent, [Vector3(0, 0, 0)], "car_wreck", 2.0, 1)
	assert_that(result).is_not_null()
	assert_int(result.get_child_count()).is_equal(0)


# =====================================================================
#  7. `collision` additif, vrai par défaut (ART-99)
# =====================================================================
## docs/art/WASTELAND_V4_ART_PLAN.md, tâche ART-99 : « DressingKit.gd
## (`collision` additif, vrai par défaut) » — `poles_and_cables`/`fence_run`/
## `cluster_against_wall` (`collide` de PropCatalog.place/place_many) et
## `tripo_row` (`_box_collision_from_aabb`) exposent désormais tous un
## paramètre `collision` en DERNIÈRE position (signature à N args toujours
## valide pour tout appelant existant -- aucun test ci-dessus, écrit avant ce
## paramètre, ne le passe). `collision = false` est le mode qu'un dressing
## PUREMENT VISUEL doit utiliser (`wasteland_art/ArtLandmarks.gd`/
## `ArtDressing.gd`, §1 R9 « aucun CollisionObject3D ajouté ») : aucune
## `StaticBody3D` de collision RÉELLE (calque 1, celui que lit la navmesh) ne
## doit apparaître sous la racine renvoyée, quel que soit le nombre
## d'instances posées (chemin individuel `PropCatalog.place` en dessous de 3,
## chemin `place_many` fusionné à partir de 3).
func _count_static_bodies(node: Node) -> int:
	var count := 0
	if node is StaticBody3D:
		count += 1
	for child in node.get_children():
		count += _count_static_bodies(child)
	return count


func test_poles_and_cables_default_collision_is_true_and_adds_a_static_body_per_pole() -> void:
	var parent := _make_root()
	var points := [Vector3(0, 0, 0), Vector3(8, 0, 0), Vector3(16, 0, 0)]
	var result := DressingKit.poles_and_cables(parent, points, 0.5, 6.0)
	assert_int(_count_static_bodies(result)).append_failure_message(
		"collision par défaut (paramètre omis) : poles_and_cables() devrait poser une StaticBody3D par poteau"
	).is_equal(points.size())


func test_poles_and_cables_with_collision_false_places_no_collision_bodies() -> void:
	var parent := _make_root()
	var points := [Vector3(0, 0, 0), Vector3(8, 0, 0), Vector3(16, 0, 0)]
	var result := DressingKit.poles_and_cables(parent, points, 0.5, 6.0, Color.WHITE, false)
	assert_int(_count_static_bodies(result)).append_failure_message(
		"collision=false : poles_and_cables() ne doit poser AUCUNE StaticBody3D (dressing purement visuel, §1 R9)"
	).is_equal(0)
	# Les câbles (visuel pur, jamais de collision) restent posés à l'identique.
	var cable_count := 0
	for child in result.get_children():
		if child is MeshInstance3D:
			cable_count += 1
	assert_int(cable_count).append_failure_message(
		"collision=false ne doit PAS retirer les câbles visuels"
	).is_equal(points.size() - 1)


func test_fence_run_default_collision_is_true_and_adds_a_static_body_per_panel() -> void:
	var parent := _make_root()
	var points := [Vector3(0, 0, 0), Vector3(6.6, 0, 0)]
	var expected := DressingKit.fence_transforms(points, "wood").size()
	var result := DressingKit.fence_run(parent, points, "wood")
	assert_int(_count_static_bodies(result)).append_failure_message(
		"collision par défaut (paramètre omis) : fence_run() devrait poser une StaticBody3D par panneau"
	).is_equal(expected)


func test_fence_run_with_collision_false_places_no_collision_bodies() -> void:
	var parent := _make_root()
	var points := [Vector3(0, 0, 0), Vector3(6.6, 0, 0)]
	var result := DressingKit.fence_run(parent, points, "wood", Color.WHITE, false)
	assert_int(_count_static_bodies(result)).append_failure_message(
		"collision=false : fence_run() ne doit poser AUCUNE StaticBody3D (dressing purement visuel, §1 R9)"
	).is_equal(0)
	# Le batch visuel (MultiMesh) reste posé à l'identique.
	assert_that(result.get_node_or_null("Batch_fence_wood")).append_failure_message(
		"collision=false ne doit PAS retirer le MultiMesh visuel des panneaux"
	).is_not_null()


func test_cluster_against_wall_default_collision_is_true_and_adds_a_static_body_per_item() -> void:
	var parent := _make_root()
	var anchor := Vector3(4.0, 1.5, -2.0)
	var expected := (DressingKit.cluster_transforms(anchor, Vector3(0, 0, 1), "crates", 4.0, 11)["wooden_crate"] as Array).size()
	var result := DressingKit.cluster_against_wall(parent, anchor, Vector3(0, 0, 1), "crates", 4.0, 11)
	assert_int(_count_static_bodies(result)).append_failure_message(
		"collision par défaut (paramètre omis) : cluster_against_wall() devrait poser une StaticBody3D par prop"
	).is_equal(expected)


func test_cluster_against_wall_with_collision_false_places_no_collision_bodies() -> void:
	var parent := _make_root()
	var anchor := Vector3(4.0, 1.5, -2.0)
	var result := DressingKit.cluster_against_wall(parent, anchor, Vector3(0, 0, 1), "crates", 4.0, 11, Color.WHITE, [], false)
	assert_int(_count_static_bodies(result)).append_failure_message(
		"collision=false : cluster_against_wall() ne doit poser AUCUNE StaticBody3D (dressing purement visuel, §1 R9)"
	).is_equal(0)


func test_tripo_row_with_collision_false_places_instances_but_no_collision_bodies() -> void:
	var parent := _make_root()
	var points := [Vector3(0, 0, 0), Vector3(8.8, 0, 0)]
	var spacing := 2.2
	var result := DressingKit.tripo_row(parent, points, "fence_broken", spacing, 5, 0.0, 20.0, false)
	var expected_positions := DressingKit.tripo_row_positions(points, spacing)
	var instances := _collect_tripo_instance_positions(result)
	assert_int(instances.size()).append_failure_message(
		"collision=false ne doit PAS retirer les instances visuelles de tripo_row()"
	).is_equal(expected_positions.size())
	assert_int(_count_static_bodies(result)).append_failure_message(
		"collision=false : tripo_row() ne doit poser AUCUNE StaticBody3D (dressing purement visuel, §1 R9 -- ex. ArtLandmarks/ArtDressing hors des bornes jouables)"
	).is_equal(0)
