## test_minimap_hud.gd
## Spec (contrat lead 2026-09-27, HUD en jeu, point 6 "MinimapHUD") : plaque
## 244x244 NON inclinée, haut-gauche, étiquette de nom de carte dessous ;
## nord fixe ; soi = triangle jaune orienté au lacet, alliés = points bleus,
## ennemis = losanges (enemy_color) visibles SEULEMENT 1.5 s après un tir.
extends GdUnitTestSuite

const MinimapHUD := preload("res://scripts/ui/hud/MinimapHUD.gd")


func _hud() -> MinimapHUD:
	var hud: MinimapHUD = auto_free(MinimapHUD.new())
	add_child(hud)
	return hud


# ---- bounds_from_vertices (pure) ----

func test_bounds_from_vertices_encloses_all_points() -> void:
	var verts := PackedVector3Array([Vector3(-10, 0, -5), Vector3(20, 3, 8), Vector3(0, 0, 0)])
	var aabb := MinimapHUD.bounds_from_vertices(verts)
	assert_float(aabb.position.x).is_equal_approx(-10.0, 0.01)
	assert_float(aabb.position.z).is_equal_approx(-5.0, 0.01)
	assert_float(aabb.size.x).is_equal_approx(30.0, 0.01)
	assert_float(aabb.size.z).is_equal_approx(13.0, 0.01)


func test_bounds_from_vertices_empty_is_empty_aabb() -> void:
	var aabb := MinimapHUD.bounds_from_vertices(PackedVector3Array())
	assert_float(aabb.size.length()).is_equal_approx(0.0, 0.01)


# ---- world_to_map (pure) : nord fixe (jamais de rotation caméra) ----

func test_world_to_map_center_of_bounds_is_center_of_map() -> void:
	var bounds := AABB(Vector3(-20, 0, -20), Vector3(40, 0, 40))
	var p := MinimapHUD.world_to_map(Vector3(0, 0, 0), bounds, Vector2(244, 244))
	assert_float(p.x).is_equal_approx(122.0, 0.5)
	assert_float(p.y).is_equal_approx(122.0, 0.5)


func test_world_to_map_corners() -> void:
	var bounds := AABB(Vector3(-20, 0, -20), Vector3(40, 0, 40))
	var top_left := MinimapHUD.world_to_map(Vector3(-20, 0, -20), bounds, Vector2(244, 244))
	assert_float(top_left.x).is_equal_approx(0.0, 0.5)
	assert_float(top_left.y).is_equal_approx(0.0, 0.5)
	var bottom_right := MinimapHUD.world_to_map(Vector3(20, 0, 20), bounds, Vector2(244, 244))
	assert_float(bottom_right.x).is_equal_approx(244.0, 0.5)
	assert_float(bottom_right.y).is_equal_approx(244.0, 0.5)


# ---- marker_visible (pure) ----

func test_marker_visible_within_window() -> void:
	assert_bool(MinimapHUD.marker_visible(10.0, 9.0)).is_true()
	assert_bool(MinimapHUD.marker_visible(10.0, 8.0)).is_false()


func test_marker_visible_never_fired_is_false() -> void:
	assert_bool(MinimapHUD.marker_visible(10.0, -INF)).is_false()


# ---- nœuds ----

func test_plate_is_not_skewed() -> void:
	var hud := _hud()
	var sb: StyleBoxComic = hud._plate.get_theme_stylebox("panel")
	assert_float(sb.skew_deg).is_equal_approx(0.0, 0.001)


func test_set_map_name_uppercases() -> void:
	var hud := _hud()
	hud.set_map_name("shipment")
	assert_str(hud._map_name_label.text).is_equal("SHIPMENT")


func test_update_self_sets_yaw() -> void:
	var hud := _hud()
	hud.update_self(Vector3(1, 0, 2), PI * 0.5)
	assert_float(hud._self_yaw).is_equal_approx(PI * 0.5, 0.001)
	assert_float(hud._self_pos.distance_to(Vector3(1, 0, 2))).is_equal_approx(0.0, 0.01)


func test_update_allies_and_enemies_store_snapshots() -> void:
	var hud := _hud()
	hud.update_allies([Vector3(1, 0, 1)])
	hud.update_enemies([{"pos": Vector3(2, 0, 2), "last_fire": 0.0}])
	assert_int(hud._allies.size()).is_equal(1)
	assert_int(hud._enemies.size()).is_equal(1)


# ---------------------------------------------------------------------------
#  Repérage au bruit (demande utilisateur 2026-09-27 : point rouge si on voit l'ennemi OU s'il
#  fait du bruit). La vue (champ caméra + ligne de vue) est testée en jeu (tools/ui/hud_capture.gd).
# ---------------------------------------------------------------------------

func test_heard_a_shot_within_range() -> void:
	assert_bool(MinimapHUD.heard(40.0, 0.0, true)).is_true()


func test_a_shot_too_far_is_not_heard() -> void:
	assert_bool(MinimapHUD.heard(MinimapHUD.FIRE_HEAR_M + 5.0, 0.0, true)).is_false()


func test_running_nearby_is_heard() -> void:
	assert_bool(MinimapHUD.heard(10.0, MinimapHUD.RUN_NOISE_SPEED + 1.0, false)).is_true()


func test_running_far_away_is_not_heard() -> void:
	assert_bool(MinimapHUD.heard(MinimapHUD.STEP_HEAR_M + 5.0, MinimapHUD.RUN_NOISE_SPEED + 1.0, false)).is_false()


func test_walking_stays_silent_even_close() -> void:
	assert_bool(MinimapHUD.heard(3.0, MinimapHUD.RUN_NOISE_SPEED - 1.0, false)).is_false()
