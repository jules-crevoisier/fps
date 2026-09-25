## test_kit.gd
## Spec (.orchestrator/maps-spec.md §4) : chaque pièce du kit pose sa
## COLLISION individuellement (StaticBody3D + CollisionShape3D, tailles
## correctes) SAUF `visual_only` (aucune collision), le GeoBatcher fusionne
## les visuels de MÊME couleur en un seul MeshInstance3D, `stairs()` ne pose
## qu'UNE collision en rampe (+ marches visuelles seules — §4.2, "players
## have no step-up"), `container()` gère `axis`/`ends_open` (§4.3),
## `building2()` construit une coque à étages avec portes/fenêtres/trémie/
## rampe/toit (§4.1), `invisible_wall()` est collision seule (§4.4), et les
## fonctions géométriques PURES (`piece_footprint`/`piece_blocks_sight`/
## `segment_intersects_rect2`) utilisées par test_layouts.gd sont correctes,
## y compris les fixes §4.5 (AABB tournée exacte, hauteur réelle des
## clôtures, murs invisibles/visual_only jamais bloquants).
extends GdUnitTestSuite


func _parent() -> Node3D:
	return auto_free(Node3D.new())


# ---- box() / visual_only ----

func test_box_creates_one_static_body_with_matching_collision() -> void:
	var parent := _parent()
	var batcher := Kit.GeoBatcher.new()
	Kit.box(parent, batcher, Vector3(1, 2, 3), Vector3(4, 5, 6), Color.RED, "Test")
	assert_int(parent.get_child_count()).is_equal(1)
	var body := parent.get_child(0) as StaticBody3D
	assert_that(body).is_not_null()
	var col := body.get_child(0) as CollisionShape3D
	var shape := col.shape as BoxShape3D
	assert_vector(shape.size).is_equal_approx(Vector3(4, 5, 6), Vector3.ONE * 0.001)


func test_box_visual_only_has_no_collision_body() -> void:
	var parent := _parent()
	var batcher := Kit.GeoBatcher.new()
	Kit.box(parent, batcher, Vector3.ZERO, Vector3.ONE, Color.BLUE, "Water", 0.0, true)
	assert_int(parent.get_child_count()).is_equal(0)
	var n := batcher.flush(parent)
	assert_int(n).is_equal(1)  # le visuel existe quand même


func test_geobatcher_merges_same_color_into_one_mesh_instance() -> void:
	var parent := _parent()
	var batcher := Kit.GeoBatcher.new()
	batcher.add_box(Transform3D(Basis(), Vector3(0, 0, 0)), Vector3.ONE, Color.RED)
	batcher.add_box(Transform3D(Basis(), Vector3(2, 0, 0)), Vector3.ONE, Color.RED)
	var n := batcher.flush(parent)
	assert_int(n).is_equal(1)


func test_geobatcher_box_count_tracks_every_add_box_call() -> void:
	var batcher := Kit.GeoBatcher.new()
	batcher.add_box(Transform3D(Basis(), Vector3(0, 0, 0)), Vector3.ONE, Color.RED)
	batcher.add_box(Transform3D(Basis(), Vector3(2, 0, 0)), Vector3.ONE, Color.BLUE)
	assert_int(batcher.box_count).is_equal(2)


func test_geobatcher_has_color_reflects_what_was_added() -> void:
	var batcher := Kit.GeoBatcher.new()
	assert_bool(batcher.has_color(Color.RED)).is_false()
	batcher.add_box(Transform3D(Basis(), Vector3.ZERO), Vector3.ONE, Color.RED, "sand_dirt")
	assert_bool(batcher.has_color(Color.RED, "sand_dirt")).is_true()
	assert_bool(batcher.has_color(Color.RED)).is_false()  # kind différent -> clé différente


# ---- ramp() / stairs() ----

func test_ramp_collision_size_matches_length_thickness_width() -> void:
	var parent := _parent()
	var batcher := Kit.GeoBatcher.new()
	Kit.ramp(parent, batcher, Vector3(0, 0, 10), Vector3(0, 2, 6), 6.0, Color.GRAY, 1.0, "R")
	var body := parent.get_child(0) as StaticBody3D
	var shape := (body.get_child(0) as CollisionShape3D).shape as BoxShape3D
	var expected_length := Vector3(0, 0, 10).distance_to(Vector3(0, 2, 6))
	assert_float(shape.size.x).is_equal_approx(expected_length, 0.01)
	assert_float(shape.size.z).is_equal_approx(6.0, 0.01)


## §4.2 : les joueurs n'ont pas de step-up -> UNE seule collision en rampe,
## pas une collision par marche.
func test_stairs_pose_a_single_ramp_collision_not_one_per_step() -> void:
	var parent := _parent()
	var batcher := Kit.GeoBatcher.new()
	Kit.stairs(parent, batcher, Vector3(0, 0, 0), Vector3(4, 3, 0), 3.0, 6, Color.GRAY, "St")
	assert_int(parent.get_child_count()).is_equal(1)
	var shape := (parent.get_child(0).get_child(0) as CollisionShape3D).shape as BoxShape3D
	var expected_length := Vector3(0, 0, 0).distance_to(Vector3(4, 3, 0))
	assert_float(shape.size.x).is_equal_approx(expected_length, 0.01)


func test_stairs_still_draw_visual_treads() -> void:
	var parent := _parent()
	var batcher := Kit.GeoBatcher.new()
	Kit.stairs(parent, batcher, Vector3(0, 0, 0), Vector3(4, 3, 0), 3.0, 6, Color.GRAY, "St")
	var n := batcher.flush(parent)
	assert_int(n).is_greater_equal(1)  # marches + rampe fusionnées (même couleur)


# ---- stair_support_boxes() : limons et contremarches (§ART-71) ----
# STYLE_BIBLE l.36/1468 : « les marches d'escalier sont décollées de leurs
# limons » est l'anti-patron visé — « aucune marche sans appui », tolérance
# d'écart ≤ 1 cm.

func test_stair_support_boxes_returns_one_stringer_plus_one_riser_per_step() -> void:
	var boxes := Kit.stair_support_boxes(Vector3(0, 0, 0), Vector3(4, 3, 0), 3.0, 6, 0.2)
	assert_int(boxes.size()).is_equal(1 + 6)


func test_stair_support_stringer_matches_the_ramp_collision_shape() -> void:
	var start := Vector3(0, 0, 0)
	var end := Vector3(4, 3, 0)
	var boxes := Kit.stair_support_boxes(start, end, 3.0, 6, 0.2)
	var stringer: Dictionary = boxes[0]
	var size: Vector3 = stringer["size"]
	assert_float(size.x).is_equal_approx(start.distance_to(end), 0.01)
	assert_float(size.z).is_equal_approx(3.0, 0.01)  # même largeur que la volée


func test_stair_support_first_riser_reaches_the_foot_of_the_flight() -> void:
	var boxes := Kit.stair_support_boxes(Vector3(0, 0, 0), Vector3(4, 3, 0), 3.0, 6, 0.2)
	var riser0: Dictionary = boxes[1]
	var xf: Transform3D = riser0["xform"]
	var size: Vector3 = riser0["size"]
	assert_float(xf.origin.y - size.y * 0.5).is_equal_approx(0.0, 0.001)


func test_stair_support_risers_touch_the_tread_above_with_no_gap() -> void:
	# Chaque contremarche i doit toucher le DESSOUS de sa marche (même
	# formule -0.09 que la marche visuelle de `_ramp_with_treads`) : aucune
	# marche ne doit flotter au-dessus du vide (STYLE_BIBLE l.1468, tolérance
	# ≤ 1 cm).
	var start := Vector3(0, 0, 0)
	var end := Vector3(4, 3, 0)
	var steps := 6
	var boxes := Kit.stair_support_boxes(start, end, 3.0, steps, 0.2)
	var step_rise := (end.y - start.y) / float(steps)
	for i in steps:
		var riser: Dictionary = boxes[1 + i]
		var xf: Transform3D = riser["xform"]
		var size: Vector3 = riser["size"]
		var riser_top: float = xf.origin.y + size.y * 0.5
		var tread_bottom: float = step_rise * float(i + 1) - 0.09
		assert_float(absf(riser_top - tread_bottom)).is_less_equal(0.01)


func test_stair_support_risers_are_narrower_than_the_flight_width() -> void:
	var boxes := Kit.stair_support_boxes(Vector3(0, 0, 0), Vector3(4, 3, 0), 3.0, 6, 0.2)
	for i in range(1, boxes.size()):
		var size: Vector3 = boxes[i]["size"]
		assert_float(size.z).is_equal_approx(3.0 * 0.94, 0.01)


## Test d'invariance Kit (§ART-71, contrat) : le limon et les contremarches
## sont versés au batcher, mais AUCUN corps de collision de plus n'apparaît —
## la collision de l'escalier reste l'unique boîte de rampe.
func test_ramp_with_treads_adds_support_geometry_with_collision_unchanged() -> void:
	var parent := _parent()
	var batcher := Kit.GeoBatcher.new()
	Kit.stairs(parent, batcher, Vector3(0, 0, 0), Vector3(4, 3, 0), 3.0, 6, Color.GRAY, "St")
	assert_int(parent.get_child_count()).is_equal(1)  # inchangé : une seule rampe de collision
	assert_int(batcher.box_count).is_equal(6 + 6 + 1)  # marches + contremarches + limon


# ---- catwalk() / fence() ----

func test_catwalk_creates_deck_plus_two_rails() -> void:
	var parent := _parent()
	var batcher := Kit.GeoBatcher.new()
	Kit.catwalk(parent, batcher, Vector3(-10, 3, 0), Vector3(10, 3, 0), 3.0, Color.GRAY, "Cw")
	assert_int(parent.get_child_count()).is_equal(3)


func test_fence_creates_single_thin_collision_body() -> void:
	var parent := _parent()
	var batcher := Kit.GeoBatcher.new()
	Kit.fence(parent, batcher, Vector3(0, 0, 0), Vector3(10, 0, 0), 1.6, Color.GRAY, "Fc")
	assert_int(parent.get_child_count()).is_equal(1)
	var shape := (parent.get_child(0).get_child(0) as CollisionShape3D).shape as BoxShape3D
	assert_float(shape.size.y).is_equal_approx(1.6, 0.001)


# ---- invisible_wall() (§4.4) ----

func test_invisible_wall_has_collision_but_no_visual() -> void:
	var parent := _parent()
	var batcher := Kit.GeoBatcher.new()
	Kit.invisible_wall(parent, Vector3(-10, 0, 0), Vector3(10, 0, 0), 8.0, "Edge")
	assert_int(parent.get_child_count()).is_equal(1)
	var n := batcher.flush(parent)
	assert_int(n).is_equal(0)  # jamais ajouté au batcher : invisible


# ---- container() : axis / ends_open (§4.3) ----

func test_container_axis_z_ends_open_0_is_fully_closed() -> void:
	var parent := _parent()
	var batcher := Kit.GeoBatcher.new()
	Kit.container(parent, batcher, Vector3.ZERO, Vector3(2.44, 2.6, 12.2), Color.GRAY, "z", 0, "Ct")
	# sol+toit+2 côtés+2 bouts fermés = 6 (nervures visual_only, comptées via le batcher).
	assert_int(parent.get_child_count()).is_equal(6)


func test_container_ends_open_2_has_no_end_caps() -> void:
	var parent := _parent()
	var batcher := Kit.GeoBatcher.new()
	Kit.container(parent, batcher, Vector3.ZERO, Vector3(2.44, 2.6, 12.2), Color.GRAY, "z", 2, "Ct")
	# sol+toit+2 côtés (pas de bouts) = 4.
	assert_int(parent.get_child_count()).is_equal(4)


func test_container_ends_open_1_has_one_end_cap() -> void:
	var parent := _parent()
	var batcher := Kit.GeoBatcher.new()
	Kit.container(parent, batcher, Vector3.ZERO, Vector3(2.44, 2.6, 12.2), Color.GRAY, "z", 1, "Ct")
	assert_int(parent.get_child_count()).is_equal(5)


func test_container_axis_x_swaps_which_faces_are_the_ends() -> void:
	var parent := _parent()
	var batcher := Kit.GeoBatcher.new()
	Kit.container(parent, batcher, Vector3.ZERO, Vector3(12.2, 2.6, 2.44), Color.GRAY, "x", 2, "Ct")
	assert_int(parent.get_child_count()).is_equal(4)  # sol+toit+2 côtés le long de X, bouts (Z) ouverts


func test_container_ribs_are_visual_only_no_extra_collision() -> void:
	var parent := _parent()
	var batcher := Kit.GeoBatcher.new()
	Kit.container(parent, batcher, Vector3.ZERO, Vector3(2.44, 2.6, 12.2), Color.GRAY, "z", 0, "Ct")
	var closed_body_count := parent.get_child_count()
	# Les nervures (6 boîtes) n'ajoutent AUCUN corps de collision.
	assert_int(closed_body_count).is_equal(6)


# ---- building2() (§4.1) ----

func test_building2_single_floor_has_floor_walls_and_roof() -> void:
	var parent := _parent()
	var batcher := Kit.GeoBatcher.new()
	Kit.building2(parent, batcher, Vector3(0, 1.6, 0), Vector3(9, 3.2, 10), Color.GRAY, 1,
		[{"side": "S", "floor": 0}, {"side": "N", "floor": 0}], [], false, 0.0, false, "N", "Saloon")
	assert_int(parent.get_child_count()).is_greater(5)  # sol + toit + 4 côtés (perforés) >= plusieurs boîtes


func test_building2_door_creates_a_walkable_gap_no_wall_spans_it() -> void:
	var parent := _parent()
	var batcher := Kit.GeoBatcher.new()
	Kit.building2(parent, batcher, Vector3(0, 1.6, 0), Vector3(9, 3.2, 10), Color.GRAY, 1,
		[{"side": "S", "floor": 0}], [], false, 0.0, false, "N", "Bld")
	# Aucun corps de mur sud ne doit couvrir x=[-0.8,0.8] (largeur de porte par défaut 1.6) au ras du sol.
	var south_wall_bodies := 0
	for c in parent.get_children():
		if c is StaticBody3D and String(c.name).begins_with("BldW0S"):
			south_wall_bodies += 1
	assert_int(south_wall_bodies).is_greater(0)  # les 2 piliers de porte existent bien


func test_building2_two_floors_has_a_slab_and_internal_ramp() -> void:
	var parent := _parent()
	var batcher := Kit.GeoBatcher.new()
	Kit.building2(parent, batcher, Vector3(0, 3.2, 0), Vector3(10, 6.4, 10), Color.GRAY, 2,
		[{"side": "S", "floor": 0}, {"side": "N", "floor": 0}], [], true, 1.0, false, "E", "Hotel")
	var has_ramp := false
	var has_slab := false
	for c in parent.get_children():
		var n := String(c.name)
		if n.begins_with("HotelRamp"):
			has_ramp = true
		if n.begins_with("HotelSlab"):
			has_slab = true
	assert_bool(has_ramp).is_true()
	assert_bool(has_slab).is_true()


func test_building2_roof_access_adds_a_roof_ramp() -> void:
	var parent := _parent()
	var batcher := Kit.GeoBatcher.new()
	Kit.building2(parent, batcher, Vector3(0, 3.2, 0), Vector3(10, 6.4, 10), Color.GRAY, 2,
		[{"side": "S", "floor": 0}], [], true, 1.0, false, "E", "Hotel")
	var has_roof_ramp := false
	for c in parent.get_children():
		if String(c.name).begins_with("HotelRampRoof"):
			has_roof_ramp = true
	assert_bool(has_roof_ramp).is_true()


## LD-24 (contrat, régression) : sans `roof_access`, `building2` ne construit
## toujours AUCUNE rampe vers le toit (comportement déjà correct côté code —
## `if roof_access:` entoure déjà tout l'appel `_ramp_with_treads` de la
## rampe de toit — verrouillé ici pour ne jamais régresser, symétrique du
## test ci-dessus).
func test_building2_without_roof_access_adds_no_roof_ramp() -> void:
	var parent := _parent()
	var batcher := Kit.GeoBatcher.new()
	Kit.building2(parent, batcher, Vector3(0, 3.2, 0), Vector3(10, 6.4, 10), Color.GRAY, 2,
		[{"side": "S", "floor": 0}], [], false, 0.0, false, "E", "Barn")
	var has_roof_ramp := false
	for c in parent.get_children():
		if String(c.name).begins_with("BarnRampRoof"):
			has_roof_ramp = true
	assert_bool(has_roof_ramp).is_false()


## ---- LD-44 (remplace LD-40) : pitched_roof_boxes() / pitched_roof() /
## roof_ridge_rise() / roof_clip_boxes() / roof_clip_volumes() /
## building2(roof_pitch_deg) ----
## Wasteland v4 (§12.3 RÉVISÉ le 2026-09-25, décision utilisateur) : les
## toits à 60° (LD-40, historique) faisaient monter le faîtage des Saloons à
## 20,3 m et cachaient le château d'eau (12 m) et la silhouette de la ville
## (docs/art/WASTELAND_V4_ART_PLAN.md §1 « B0 »). Remplacés par des toits
## BAS (25-30°, `Kit.ROOF_PITCH_DEG`), faîte plafonnée à la corniche + 3 m
## (`Kit.ROOF_MAX_RISE`) — SOUS `MapSetup.AGENT_MAX_SLOPE` (46°), donc la
## pente seule ne suffit plus à exclure le toit du bake Recast. C'est
## pourquoi `building2()` pose maintenant AUSSI, automatiquement, un volume
## invisible « player_clip » au-dessus de chaque pan (`Kit.roof_clip_boxes`/
## `roof_clip_volumes`) : heurté par les joueurs/bots (calque DÉDIÉ
## `PhysicsLayers.PLAYER_CLIP`, inclus dans le `collision_mask` par défaut du
## corps joueur/bot, `scenes/player/player.tscn`), traversé par tout rayon
## `PhysicsLayers.SHOT_MASK` (tirs, grenades à mèche, capacités de lancer —
## `PLAYER_CLIP` en est exclu, `scripts/core/PhysicsLayers.gd`) — jamais un
## minuteur « Retour au combat ». Voir aussi docs/COLLISION_LAYERS.md et
## tests/maps/test_wasteland.gd (vraie navmesh, corps physique réel, rayon
## réel).

func test_roof_ridge_rise_uses_the_nominal_pitch_when_the_building_is_shallow_enough() -> void:
	# Bâtiment peu profond (hz=3 m, comme MagasinW/Hotel, cf. wasteland.gd) :
	# 3 * tan(27°) = 1,53 m, bien SOUS le plafond de 3 m -> angle nominal
	# gardé tel quel, jamais réduit sans raison.
	var hz := 3.0
	var expected := hz * tan(deg_to_rad(Kit.ROOF_PITCH_DEG))
	assert_float(expected).append_failure_message("ce cas de test doit rester sous le plafond de %.1f m pour être significatif" % Kit.ROOF_MAX_RISE).is_less(Kit.ROOF_MAX_RISE)
	assert_float(Kit.roof_ridge_rise(hz, Kit.ROOF_PITCH_DEG)).is_equal_approx(expected, 0.001)


## Décision utilisateur : « faîte <= 3 m au-dessus de la corniche » — un
## bâtiment profond (hz=8 m, comme SaloonW/E, 16 m de profondeur) dépasserait
## ce plafond à l'angle nominal (8 * tan(27°) = 3,73 m) : la montée doit donc
## être RÉDUITE au plafond, jamais l'inverse (jamais le plafond assoupli).
func test_roof_ridge_rise_is_capped_at_3m_for_a_deep_building() -> void:
	var hz := 8.0
	var uncapped := hz * tan(deg_to_rad(Kit.ROOF_PITCH_DEG))
	assert_float(uncapped).append_failure_message("ce cas de test doit dépasser le plafond de %.1f m pour être significatif" % Kit.ROOF_MAX_RISE).is_greater(Kit.ROOF_MAX_RISE)
	assert_float(Kit.roof_ridge_rise(hz, Kit.ROOF_PITCH_DEG)).is_equal_approx(Kit.ROOF_MAX_RISE, 0.001)


## Les 11 `building2` réels de la v4 (docs/art/WASTELAND_V4_ART_PLAN.md,
## ART-91 : « toutes les pièces ... des 11 building2 ») ne dépassent JAMAIS
## le plafond, quelle que soit leur profondeur réelle (3 à 8 m de demi-
## profondeur, §9 du doc de recherche) — géométrie pure, aucun bake requis
## (complète `tests/maps/test_wasteland.gd::test_every_pitched_roof_ridge_
## stays_within_3m_of_its_cornice`, qui relit les VRAIES pièces de
## `WastelandLayout.data()` plutôt que ces cas synthétiques).
func test_roof_ridge_rise_never_exceeds_the_cap_across_realistic_depths() -> void:
	for hz in [1.5, 3.0, 5.0, 6.0, 7.0, 8.0, 20.0]:
		var rise := Kit.roof_ridge_rise(hz, Kit.ROOF_PITCH_DEG)
		assert_float(rise).append_failure_message("hz=%.1f : faîte à +%.3fm (plafond %.1fm)" % [hz, rise, Kit.ROOF_MAX_RISE]).is_less_equal(Kit.ROOF_MAX_RISE + 0.001)


func test_pitched_roof_boxes_returns_two_panels_using_roof_ridge_rise() -> void:
	var panels := Kit.pitched_roof_boxes(Vector3(0, 3.2, 0), Vector3(9, 3.2, 10), 3.2, Kit.ROOF_PITCH_DEG)
	assert_int(panels.size()).is_equal(2)
	var hz := 10.0 * 0.5
	var expected_rise := Kit.roof_ridge_rise(hz, Kit.ROOF_PITCH_DEG)
	for panel in panels:
		var size: Vector3 = panel["size"]
		var xform: Transform3D = panel["xform"]
		# `size.x` = longueur du pan (hypoténuse rise/hz) ; `size.z` = largeur
		# (le faîtage, `size.x` du bâtiment) — voir `_ramp_shape` (fwd=pente,
		# side=largeur).
		assert_float(size.z).is_equal_approx(9.0, 0.01)  # largeur = le faîtage, toute la longueur du bâtiment
		assert_bool(xform.origin.y > 3.2).append_failure_message("panel must rise above roof_y").is_true()
		assert_bool(xform.origin.y <= 3.2 + expected_rise + 0.01).append_failure_message("panel rises above the ridge (%.2f > roof_y+rise=%.2f)" % [xform.origin.y, 3.2 + expected_rise]).is_true()


## `_point_in_obb` : petit oracle indépendant (même algèbre que `Transform3D.
## affine_inverse()`, aucun accès aux privés de Kit) pour vérifier qu'un
## point donné tombe dans une boîte orientée — utilisé par les tests
## `roof_clip_boxes` ci-dessous.
static func _point_in_obb(xform: Transform3D, size: Vector3, p: Vector3, margin: float = 0.02) -> bool:
	var local: Vector3 = xform.affine_inverse() * p
	return absf(local.x) <= size.x * 0.5 + margin and absf(local.y) <= size.y * 0.5 + margin and absf(local.z) <= size.z * 0.5 + margin


## Le volume `player_clip` colle exactement à la surface du toit (mêmes
## points `start`/`ridge` que `pitched_roof_boxes`, jamais recalculés) et
## couvre toute la hauteur demandée : l'avant-toit, le milieu de pente, le
## faîtage, et un point `clip_height` plus haut le long de la MÊME pente
## (§`ROOF_CLIP_HEIGHT`, mesuré perpendiculairement à la pente) doivent tous
## être recouverts par l'un des deux pans.
func test_roof_clip_boxes_cover_the_roof_surface_up_to_clip_height() -> void:
	var center := Vector3(0, 0, 0)
	var size := Vector3(8.0, 6.4, 16.0)  # comme SaloonW/E (docs/research/11..., §9)
	var roof_y := 6.4
	var pitch := Kit.ROOF_PITCH_DEG
	var clip_h := Kit.ROOF_CLIP_HEIGHT
	var hz := size.z * 0.5
	var rise := Kit.roof_ridge_rise(hz, pitch)
	var boxes := Kit.roof_clip_boxes(center, size, roof_y, pitch, clip_h)
	assert_int(boxes.size()).is_equal(2)

	var south_eave := Vector3(0, roof_y, hz)
	var south_mid := Vector3(0, roof_y + rise * 0.5, hz * 0.5)
	var ridge := Vector3(0, roof_y + rise, 0.0)
	for p in [south_eave, south_mid, ridge]:
		var covered := false
		for b in boxes:
			if _point_in_obb(b["xform"], b["size"], p):
				covered = true
		assert_bool(covered).append_failure_message("point %s not covered by any player_clip box" % p).is_true()

	# `clip_height` plus haut le long de la pente sud (repère local, pas une
	# approximation verticale) : reste couvert jusqu'au bout du volume.
	var dir := (ridge - Vector3(0, roof_y, hz)).normalized()
	var side := dir.cross(Vector3.UP)
	if side.length() < 0.001:
		side = Vector3.RIGHT
	side = side.normalized()
	var up := side.cross(dir).normalized()
	var south_top := south_mid + up * (clip_h * 0.95)
	var covered_top := false
	for b in boxes:
		if _point_in_obb(b["xform"], b["size"], south_top):
			covered_top = true
	assert_bool(covered_top).append_failure_message("point %s (haut du volume) not covered" % south_top).is_true()


## LD-44 (résout le blocage initial documenté dans l'historique de
## `docs/COLLISION_LAYERS.md` §"Limite connue") : `PhysicsLayers.PLAYER_CLIP`
## sur les DEUX (layer et mask), JAMAIS `PhysicsLayers.WORLD` — un calque
## dédié, exclu de `PhysicsLayers.SHOT_MASK` (`scripts/core/PhysicsLayers.
## gd`), qui rend le volume traversé par tout tir/grenade/grappin. Il reste
## heurté par le corps du joueur/bot PARCE QUE `scenes/player/player.tscn`
## inclut désormais ce bit dans son `collision_mask` par défaut (`WORLD |
## PLAYER_CLIP`, prouvé sur une vraie scène bakée par
## `tests/maps/test_wasteland.gd::test_no_roof_point_is_physically_
## reachable_by_a_moving_player_body`). `PLAYER_CLIP` n'est exclu de rien
## d'autre : seul un rayon/corps dont le masque omet ce bit (les rayons
## `SHOT_MASK`, précisément) le traverse.
func test_roof_clip_volumes_pose_collision_on_the_player_clip_layer_so_shots_pass_through() -> void:
	var parent := _parent()
	Kit.roof_clip_volumes(parent, Vector3(0, 3.2, 0), Vector3(9, 3.2, 10), 3.2, Kit.ROOF_PITCH_DEG, Kit.ROOF_CLIP_HEIGHT, "Clip")
	assert_int(parent.get_child_count()).is_equal(2)
	for c in parent.get_children():
		assert_bool(c is StaticBody3D).append_failure_message("player_clip volume %s has no collision" % c.name).is_true()
		var body := c as StaticBody3D
		assert_int(body.collision_layer).append_failure_message("player_clip must be on PhysicsLayers.PLAYER_CLIP, a dedicated layer excluded from SHOT_MASK").is_equal(PhysicsLayers.PLAYER_CLIP)
		assert_int(body.collision_mask).is_equal(PhysicsLayers.PLAYER_CLIP)
	assert_int(PhysicsLayers.SHOT_MASK & PhysicsLayers.PLAYER_CLIP).append_failure_message("PhysicsLayers.SHOT_MASK must exclude PLAYER_CLIP so shots/grenades pass through the roof clip volume").is_equal(0)


func test_pitched_roof_adds_collision_and_no_flat_lid() -> void:
	var parent := _parent()
	var batcher := Kit.GeoBatcher.new()
	Kit.pitched_roof(parent, batcher, Vector3(0, 3.2, 0), Vector3(9, 3.2, 10), 3.2, Color.GRAY, "Roof")
	assert_int(parent.get_child_count()).is_equal(2)  # les deux pans, jamais un lid plat
	for c in parent.get_children():
		assert_bool(c is StaticBody3D).append_failure_message("pitched roof panel %s has no collision" % c.name).is_true()


func test_building2_roof_pitch_deg_replaces_the_flat_roof_with_two_pitched_panels() -> void:
	var parent := _parent()
	var batcher := Kit.GeoBatcher.new()
	Kit.building2(parent, batcher, Vector3(0, 1.6, 0), Vector3(9, 3.2, 10), Color.GRAY, 1,
		[{"side": "S", "floor": 0}], [], false, 0.0, false, "N", "Saloon", "", "", Kit.ROOF_PITCH_DEG)
	var flat_roof_found := false
	var pitched_panels := 0
	for c in parent.get_children():
		var n := String(c.name)
		if n == "SaloonRoof":
			flat_roof_found = true
		if n.begins_with("SaloonRoof") and n != "SaloonRoof":
			pitched_panels += 1
	assert_bool(flat_roof_found).append_failure_message("a flat SaloonRoof lid was posed despite roof_pitch_deg > 0").is_false()
	assert_int(pitched_panels).is_equal(2)


func test_building2_roof_pitch_deg_ignores_parapet_and_roof_access_ramp() -> void:
	var parent := _parent()
	var batcher := Kit.GeoBatcher.new()
	Kit.building2(parent, batcher, Vector3(0, 3.2, 0), Vector3(10, 6.4, 10), Color.GRAY, 2,
		[{"side": "S", "floor": 0}], [], true, 1.0, false, "E", "Hotel", "", "", Kit.ROOF_PITCH_DEG)
	for c in parent.get_children():
		var n := String(c.name)
		assert_bool(n.begins_with("HotelPar")).append_failure_message("parapet %s posed despite roof_pitch_deg > 0" % n).is_false()
		assert_bool(n.begins_with("HotelRampRoof")).append_failure_message("roof ramp %s posed despite roof_pitch_deg > 0" % n).is_false()
	# L'étage intermédiaire (dalle + rampe interne) reste construit normalement.
	var has_slab := false
	var has_ramp := false
	for c in parent.get_children():
		var n := String(c.name)
		if n.begins_with("HotelSlab"):
			has_slab = true
		if n.begins_with("HotelRamp1"):
			has_ramp = true
	assert_bool(has_slab).is_true()
	assert_bool(has_ramp).is_true()


func test_build_piece_reads_roof_pitch_deg_from_the_piece_dict() -> void:
	var parent := _parent()
	var batcher := Kit.GeoBatcher.new()
	var palette := {"wall": Color.GRAY}
	Kit.build_piece(parent, batcher, {"type": "building2", "name": "Wagon", "pos": Vector3(0, 1.7, 0), "size": Vector3(12, 3.4, 3), "floors": 1, "doors": [{"side": "W", "floor": 0}], "windows": [], "color_key": "wall", "roof_pitch_deg": Kit.ROOF_PITCH_DEG}, palette)
	var flat_roof_found := false
	for c in parent.get_children():
		if String(c.name) == "WagonRoof":
			flat_roof_found = true
	assert_bool(flat_roof_found).append_failure_message("build_piece did not forward roof_pitch_deg to building2").is_false()


## LD-20 (contrat, « building2 ... casse le chemin extérieur si ce côté
## porte une porte ») : une porte posée sur `stair_side` (ici au RDC) ne doit
## plus se retrouver derrière la rampe — sans le décalage de
## `_bld_hole_across_center`, la rampe (StaticBody3D solide dès le pied du
## mur, largeur `_BLD_RAMP_W` centrée par défaut comme la porte) bloquerait
## physiquement ce passage. Porte N/RDC par défaut : centrée (offset 0),
## largeur 1.6 -> gap x=[-0.8,0.8].
func test_building2_door_on_stair_side_is_not_blocked_by_the_ramp() -> void:
	var parent := _parent()
	var batcher := Kit.GeoBatcher.new()
	Kit.building2(parent, batcher, Vector3(0, 3.2, 0), Vector3(10, 6.4, 10), Color.GRAY, 2,
		[{"side": "N", "floor": 0}], [], true, 0.0, false, "N", "Keep")
	var ramp: StaticBody3D = null
	for c in parent.get_children():
		if String(c.name).begins_with("KeepRamp1"):
			ramp = c as StaticBody3D
	assert_object(ramp).append_failure_message("KeepRamp1 body introuvable").is_not_null()
	var door_half := 0.8
	var ramp_half := 0.8  # _BLD_RAMP_W / 2
	# `position` (locale, PAS `global_position` : `parent` n'est pas dans
	# l'arbre de scène ici — `auto_free` ne l'y ajoute pas — et `global_
	# position` y renvoie (0,0,0), jamais la vraie position ; même convention
	# que les autres tests de ce fichier, qui inspectent toujours les
	# propriétés LOCALES des corps).
	var ramp_x: float = ramp.position.x
	var gap := absf(ramp_x) - (door_half + ramp_half)
	assert_float(gap).append_failure_message("rampe à x=%.2f, chevauche encore le passage de la porte N/RDC [-0.8,0.8]" % ramp_x).is_greater_equal(0.0)


func test_building2_windows_side_gets_openings_on_floors_without_a_door() -> void:
	var parent := _parent()
	var batcher := Kit.GeoBatcher.new()
	Kit.building2(parent, batcher, Vector3(0, 1.5, 0), Vector3(4, 3, 10), Color.GRAY, 1,
		[{"side": "W", "floor": 0}], ["E"], false, 0.0, true, "N", "Bunker")
	var east_pieces := 0
	for c in parent.get_children():
		if String(c.name).begins_with("BunkerW0E"):
			east_pieces += 1
	assert_int(east_pieces).is_greater(1)  # plusieurs segments (meurtrières perçant le mur est)


# ---- building_trim_boxes() / roof_overhang_boxes() (§ART-71) ----
# STYLE_BIBLE l.36 : « les murs sont des plans géants sans biseau, sans
# trim, sans rupture de silhouette » — l'anti-patron visé.

func test_building_trim_boxes_returns_four_corners_and_four_bands() -> void:
	var boxes := Kit.building_trim_boxes(Vector3(0, 1.6, 0), Vector3(9, 3.2, 10))
	assert_int(boxes.size()).is_equal(4 + 4)


func test_building_trim_corners_are_6cm_and_run_the_full_height() -> void:
	var boxes := Kit.building_trim_boxes(Vector3(0, 1.6, 0), Vector3(9, 3.2, 10))
	for i in range(0, 4):
		var size: Vector3 = boxes[i]["size"]
		assert_float(size.x).is_equal_approx(0.06, 0.001)
		assert_float(size.z).is_equal_approx(0.06, 0.001)
		assert_float(size.y).is_equal_approx(3.2, 0.001)  # toute la hauteur du bâtiment


func test_building_trim_corners_sit_on_the_four_vertical_edges() -> void:
	var boxes := Kit.building_trim_boxes(Vector3(0, 1.6, 0), Vector3(9, 3.2, 10))
	for i in range(0, 4):
		var pos: Vector3 = boxes[i]["pos"]
		assert_float(absf(pos.x)).is_equal_approx(4.5 - 0.03, 0.001)
		assert_float(absf(pos.z)).is_equal_approx(5.0 - 0.03, 0.001)


func test_building_trim_top_band_sits_flush_with_the_roofline() -> void:
	var center := Vector3(0, 1.6, 0)
	var size := Vector3(9, 3.2, 10)
	var boxes := Kit.building_trim_boxes(center, size)
	var top: float = center.y + size.y * 0.5
	for i in range(4, 8):
		var pos: Vector3 = boxes[i]["pos"]
		var bsize: Vector3 = boxes[i]["size"]
		assert_float(pos.y + bsize.y * 0.5).is_equal_approx(top, 0.001)  # touche le haut du mur, ne dépasse pas
		assert_float(bsize.y).is_equal_approx(0.06, 0.001)


func test_roof_overhang_boxes_extend_0_3m_beyond_the_building_footprint() -> void:
	var boxes := Kit.roof_overhang_boxes(Vector3(0, 1.6, 0), Vector3(9, 3.2, 10), 3.2)
	assert_float((boxes[0]["pos"] as Vector3).z).is_equal_approx(-5.0 - 0.15, 0.01)  # N
	assert_float((boxes[1]["pos"] as Vector3).z).is_equal_approx(5.0 + 0.15, 0.01)   # S
	assert_float((boxes[2]["pos"] as Vector3).x).is_equal_approx(-4.5 - 0.15, 0.01)  # W
	assert_float((boxes[3]["pos"] as Vector3).x).is_equal_approx(4.5 + 0.15, 0.01)   # E


## « Débords de toit [...] hors espace praticable » (contrat ART-71) : le
## débord ne dépasse jamais le dessus praticable du toit, et il est
## purement visuel (jamais posé par `_collision_box` — vérifié en b.4 via
## `test_building2_collision_body_count_is_unchanged_by_trims_and_overhang`).
func test_roof_overhang_boxes_stay_below_the_walkable_roof_top() -> void:
	var roof_y := 3.2
	var boxes := Kit.roof_overhang_boxes(Vector3(0, 1.6, 0), Vector3(9, 3.2, 10), roof_y)
	for b in boxes:
		var pos: Vector3 = b["pos"]
		var size: Vector3 = b["size"]
		assert_float(pos.y + size.y * 0.5).is_less(roof_y)


func test_building2_trims_and_overhang_are_versed_into_the_batcher() -> void:
	var parent := _parent()
	var batcher := Kit.GeoBatcher.new()
	Kit.building2(parent, batcher, Vector3(0, 1.6, 0), Vector3(9, 3.2, 10), Color.GRAY, 1,
		[{"side": "S", "floor": 0}], [], false, 0.0, false, "N", "Trimmed")
	assert_bool(batcher.has_color(Cartoon.PAPER)).is_true()  # trim crème (§ART-71)
	assert_bool(batcher.has_color(Color.GRAY)).is_true()     # débord de toit, couleur du toit


## Test d'invariance Kit (§ART-71, contrat) : même géométrie de collision
## qu'avant les trims/débords — inchangée pour `test_building2_single_floor_
## has_floor_walls_and_roof` (sol + toit + 4 pans de mur, dont 2 avec porte).
func test_building2_collision_body_count_is_unchanged_by_trims_and_overhang() -> void:
	var parent := _parent()
	var batcher := Kit.GeoBatcher.new()
	Kit.building2(parent, batcher, Vector3(0, 1.6, 0), Vector3(9, 3.2, 10), Color.GRAY, 1,
		[{"side": "S", "floor": 0}, {"side": "N", "floor": 0}], [], false, 0.0, false, "N", "Saloon")
	var body_count := 0
	for c in parent.get_children():
		if c is StaticBody3D:
			body_count += 1
	# Sol(1) + Toit(1) + murs N(3: piliers+linteau) + S(3) + E(1) + W(1) = 10.
	assert_int(body_count).is_equal(10)


# ---- Silhouettes décoratives : rot_y (§4.5) ----

func test_water_tower_antenna_crane_accept_rot_y() -> void:
	var parent := _parent()
	var batcher := Kit.GeoBatcher.new()
	Kit.water_tower(parent, batcher, Vector3.ZERO, Color.GRAY, PI)
	Kit.antenna(parent, batcher, Vector3(20, 0, 0), Color.GRAY, PI * 0.5)
	Kit.crane(parent, batcher, Vector3(40, 0, 0), Color.GRAY, PI * 0.25)
	assert_int(parent.get_child_count()).is_equal(5 + 4 + 3)


# ---- build_piece dispatch ----

func test_build_piece_dispatches_all_types_without_crashing() -> void:
	var parent := _parent()
	var batcher := Kit.GeoBatcher.new()
	var palette := {"wall": Color.GRAY, "cover": Color.GREEN, "floor": Color.WHITE, "platform": Color.BLUE, "accent": Color.ORANGE}
	var pieces: Array = [
		{"type": "box", "pos": Vector3.ZERO, "size": Vector3.ONE, "color_key": "wall"},
		{"type": "box", "pos": Vector3(0, 0, 100), "size": Vector3.ONE, "color_key": "wall", "visual_only": true},
		{"type": "ramp", "start": Vector3(0, 0, 5), "end": Vector3(0, 2, 2), "width": 4.0, "color_key": "platform"},
		{"type": "stairs", "start": Vector3(10, 0, 0), "end": Vector3(13, 2, 0), "width": 2.0, "color_key": "platform"},
		{"type": "catwalk", "start": Vector3(-10, 3, 0), "end": Vector3(10, 3, 0), "width": 3.0, "color_key": "platform"},
		{"type": "fence", "start": Vector3(0, 0, 20), "end": Vector3(5, 0, 20), "color_key": "wall"},
		{"type": "invisible_wall", "start": Vector3(0, 0, 30), "end": Vector3(5, 0, 30), "height": 8.0},
		{"type": "container", "pos": Vector3(0, 1.3, 30), "size": Vector3(2.44, 2.6, 12.2), "axis": "z", "ends_open": 2, "color_key": "cover"},
		{"type": "building2", "pos": Vector3(0, 2, 40), "size": Vector3(7, 4, 6), "floors": 1, "doors": [{"side": "S", "floor": 0}], "windows": [], "color_key": "wall"},
		{"type": "crane", "pos": Vector3(0, 0, 50), "color_key": "wall"},
		{"type": "water_tower", "pos": Vector3(0, 0, 60), "color_key": "wall"},
		{"type": "antenna", "pos": Vector3(0, 0, 70), "color_key": "wall"},
	]
	for p in pieces:
		Kit.build_piece(parent, batcher, p, palette)
	batcher.flush(parent)
	assert_int(parent.get_child_count()).is_greater(len(pieces))


# ---- Géométrie pure (utilisée par test_layouts.gd) ----

func test_piece_footprint_rotated_box_uses_exact_aabb_formula() -> void:
	var piece := {"type": "box", "pos": Vector3.ZERO, "size": Vector3(4, 2, 2), "rot_y": PI * 0.5}
	var fp := Kit.piece_footprint(piece)
	# Rotation de 90° : X et Z s'échangent exactement (formule exacte, pas conservatrice).
	assert_vector(fp["min"]).is_equal_approx(Vector2(-1, -2), Vector2.ONE * 0.01)
	assert_vector(fp["max"]).is_equal_approx(Vector2(1, 2), Vector2.ONE * 0.01)


func test_piece_footprint_fence_uses_real_height_for_top() -> void:
	var piece := {"type": "fence", "start": Vector3(0, 0, 0), "end": Vector3(10, 0, 0), "height": 2.5}
	var fp := Kit.piece_footprint(piece)
	assert_float(fp["top"]).is_equal_approx(2.5, 0.01)


func test_piece_footprint_covers_building2_via_pos_size() -> void:
	var piece := {"type": "building2", "pos": Vector3(1, 2, 3), "size": Vector3(10, 6.4, 10)}
	var fp := Kit.piece_footprint(piece)
	assert_vector(fp["min"]).is_equal_approx(Vector2(-4, -2), Vector2.ONE * 0.01)
	assert_float(fp["top"]).is_equal_approx(2.0 + 3.2, 0.01)


func test_piece_blocks_sight_false_for_invisible_wall_regardless_of_height() -> void:
	var piece := {"type": "invisible_wall", "start": Vector3(0, 0, 0), "end": Vector3(10, 0, 0), "height": 8.0}
	assert_bool(Kit.piece_blocks_sight(piece)).is_false()


func test_piece_blocks_sight_false_for_visual_only_tall_piece() -> void:
	var piece := {"type": "box", "pos": Vector3.ZERO, "size": Vector3(2, 5, 2), "visual_only": true}
	assert_bool(Kit.piece_blocks_sight(piece)).is_false()


func test_piece_blocks_sight_true_for_tall_piece() -> void:
	var piece := {"type": "box", "pos": Vector3.ZERO, "size": Vector3(2, 3, 2)}
	assert_bool(Kit.piece_blocks_sight(piece)).is_true()


func test_segment_intersects_rect2_true_when_crossing() -> void:
	var hit := Kit.segment_intersects_rect2(Vector2(-10, 0), Vector2(10, 0), Vector2(-1, -1), Vector2(1, 1))
	assert_bool(hit).is_true()


func test_segment_intersects_rect2_false_when_parallel_outside() -> void:
	var hit := Kit.segment_intersects_rect2(Vector2(-10, 5), Vector2(10, 5), Vector2(-1, -1), Vector2(1, 1))
	assert_bool(hit).is_false()
