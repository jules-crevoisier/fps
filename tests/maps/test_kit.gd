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
