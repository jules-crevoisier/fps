## test_bot_stuck.gd
## Spec (BOT-09, docs/research/02_bots_ai.md §2.1/§4#13/§5, tasks/backlog.yaml) :
## BotStuck est une machine à états PURE — vitesse moyenne glissante sur 1 s
## (SPEED_WINDOW) ; sous 0.5 m/s (STUCK_SPEED_THRESHOLD) avec un chemin actif,
## déclenche wiggle latéral 0.3 s (oscillation, les deux sens), puis un saut
## (édge d'un seul tick), puis UN tick plus tard une demande de repath vers un
## point intermédiaire ALTERNATIF (perpendiculaire à la direction de blocage,
## côté alterné, projeté sur la navmesh), puis un cooldown avant de pouvoir se
## rejuger "bloqué". `project_strafe_to_navmesh` (utilisé aussi par BotBrain
## pour le strafe de combat) et `alternate_repath_point` s'appuient sur
## `NavigationServer3D.map_get_closest_point` — testés avec une navmesh RÉELLE
## bakée (StaticBody3D ajoutés à l'arbre, comme tests/ai/test_bot_spots.gd),
## et avec une RID invalide pour la partie purement vectorielle.
extends GdUnitTestSuite

const DT := 1.0 / 60.0   ## Pas physique de référence (BotBrain._physics_process tourne à 60 Hz).

# ======================================================================
#  Fenêtre de vitesse moyenne — pas de déclenchement prématuré ni manqué.
# ======================================================================

func test_initial_average_speed_is_zero() -> void:
	var stuck := BotStuck.new()
	assert_float(stuck.current_average_speed()).is_equal_approx(0.0, 0.0001)


func test_no_trigger_without_active_path_even_stationary_for_long() -> void:
	var stuck := BotStuck.new()
	var pos := Vector3(5, 0, 5)
	for i in range(180):  # 3 s immobile, mais SANS chemin actif.
		var out := stuck.update(DT, pos, false)
		assert_int(out.phase).append_failure_message(
			"tick %d : sans chemin actif, ne doit jamais quitter IDLE" % i).is_equal(BotStuck.Phase.IDLE)
		assert_bool(out.blocked).is_false()


func test_no_trigger_when_moving_fast_enough() -> void:
	var stuck := BotStuck.new()
	var pos := Vector3.ZERO
	var step := Vector3(2.0, 0.0, 0.0) * DT   # ~2 m/s, bien au-dessus du seuil (0.5 m/s).
	for i in range(180):
		pos += step
		var out := stuck.update(DT, pos, true)
		assert_int(out.phase).append_failure_message(
			"tick %d : vitesse ~2 m/s, chemin actif : ne doit pas se déclencher" % i).is_equal(BotStuck.Phase.IDLE)
		assert_bool(out.blocked).is_false()


func test_does_not_trigger_before_full_1s_window() -> void:
	var stuck := BotStuck.new()
	var pos := Vector3(1, 0, 1)
	for i in range(30):  # 0.5 s immobile, chemin actif : fenêtre encore incomplète.
		var out := stuck.update(DT, pos, true)
		assert_int(out.phase).append_failure_message(
			"tick %d : fenêtre de 1 s pas encore pleine" % i).is_equal(BotStuck.Phase.IDLE)


func test_triggers_wiggle_once_1s_window_confirms_low_speed() -> void:
	var stuck := BotStuck.new()
	var pos := Vector3(1, 0, 1)
	var triggered_tick := -1
	for i in range(90):  # jusqu'à 1.5 s, large marge après la fenêtre de 1 s.
		var out := stuck.update(DT, pos, true)
		if out.phase == BotStuck.Phase.WIGGLE:
			triggered_tick = i
			break
	assert_int(triggered_tick).append_failure_message("aucun déclenchement en 1.5 s simulées").is_greater_equal(0)
	# Doit se déclencher près de la fenêtre de 1 s (55-65 ticks à 60 Hz), ni
	# immédiatement ni beaucoup plus tard (marge pour l'arrondi flottant).
	assert_int(triggered_tick).is_between(55, 65)


func test_average_speed_reported_correctly_for_known_motion() -> void:
	# 1 m/s constant pendant 2 s : la fenêtre glissante doit converger vers 1.0.
	var stuck := BotStuck.new()
	var pos := Vector3.ZERO
	var step := Vector3(1.0, 0.0, 0.0) * DT
	for i in range(120):
		pos += step
		stuck.update(DT, pos, true)
	assert_float(stuck.current_average_speed()).append_failure_message(
		"vitesse moyenne attendue ~1.0 m/s après 2 s à vitesse constante").is_equal_approx(1.0, 0.05)


# ======================================================================
#  Séquence complète — wiggle (oscillation, 0.3 s) -> saut (1 tick) ->
#  demande de repath (1 tick, après le saut) -> cooldown -> retour à IDLE.
# ======================================================================

## Simule `n` ticks à position FIXE (donc "bloqué") avec chemin actif, et
## renvoie la liste des sorties de `update()`.
func _run_stuck_scenario(stuck: BotStuck, n: int, pos: Vector3 = Vector3(3, 0, -2)) -> Array:
	var outs: Array = []
	for i in range(n):
		outs.append(stuck.update(DT, pos, true))
	return outs


## Comme `_run_stuck_scenario`, mais le bot se débloque avec SUCCÈS dès que
## `request_repath` est demandé (avance ensuite à ~2 m/s, très au-dessus du
## seuil) — un épisode UNIQUE et propre à observer. Un bot qui resterait
## bloqué À VIE redéclencherait indéfiniment la séquence (comportement voulu,
## voir `test_still_stuck_after_cooldown_triggers_a_second_sequence`), donc
## les tests qui veulent observer un seul cycle complet jusqu'au retour à IDLE
## ont besoin de cette variante.
func _run_stuck_then_escape_scenario(stuck: BotStuck, n: int) -> Array:
	var outs: Array = []
	var pos := Vector3(3, 0, -2)
	var escaped := false
	for i in range(n):
		var out := stuck.update(DT, pos, true)
		outs.append(out)
		if bool(out.request_repath):
			escaped = true
		if escaped:
			pos += Vector3(2.0, 0.0, 0.0) * DT
	return outs


func test_full_sequence_order_wiggle_then_jump_then_repath_then_cooldown() -> void:
	var stuck := BotStuck.new()
	var outs := _run_stuck_then_escape_scenario(stuck, 260)  # fenêtre (~1s) + wiggle (0.3s) + jump + repath + cooldown (1.5s) + marge.

	var wiggle_ticks: Array = []
	var jump_ticks: Array = []
	var repath_ticks: Array = []
	var cooldown_ticks: Array = []
	for i in outs.size():
		var out: Dictionary = outs[i]
		if out.phase == BotStuck.Phase.WIGGLE:
			wiggle_ticks.append(i)
		if bool(out.jump_pressed):
			jump_ticks.append(i)
		if bool(out.request_repath):
			repath_ticks.append(i)
		if out.phase == BotStuck.Phase.COOLDOWN:
			cooldown_ticks.append(i)

	assert_bool(wiggle_ticks.is_empty()).append_failure_message("aucune phase WIGGLE observée").is_false()
	assert_int(jump_ticks.size()).append_failure_message("jump_pressed doit être vrai EXACTEMENT un tick").is_equal(1)
	assert_int(repath_ticks.size()).append_failure_message("request_repath doit être vrai EXACTEMENT un tick").is_equal(1)
	assert_bool(cooldown_ticks.is_empty()).append_failure_message("aucune phase COOLDOWN observée").is_false()

	# Ordre strict : dernier tick WIGGLE < tick JUMP < tick REPATH < premier tick COOLDOWN.
	var last_wiggle: int = wiggle_ticks[wiggle_ticks.size() - 1]
	var jump_tick: int = jump_ticks[0]
	var repath_tick: int = repath_ticks[0]
	var first_cooldown: int = cooldown_ticks[0]
	assert_int(jump_tick).append_failure_message("le saut doit suivre le wiggle").is_greater(last_wiggle)
	assert_int(repath_tick).append_failure_message("la demande de repath doit suivre le saut").is_greater(jump_tick)
	assert_int(first_cooldown).append_failure_message("le cooldown doit suivre la demande de repath").is_greater(repath_tick)

	# Durée du wiggle ~0.3 s (tolérance de quelques ticks pour la discrétisation).
	var wiggle_duration := float(wiggle_ticks.size()) * DT
	assert_float(wiggle_duration).append_failure_message(
		"durée du wiggle observée %.3f s, attendu ~%.3f s" % [wiggle_duration, BotStuck.WIGGLE_DURATION]
	).is_between(BotStuck.WIGGLE_DURATION - 3.0 * DT, BotStuck.WIGGLE_DURATION + 3.0 * DT)

	# Le saut et la demande de repath tombent sur des ticks DIFFÉRENTS (jamais
	# le même tick — "puis" implique une séquence, pas un événement combiné).
	assert_int(jump_tick).is_not_equal(repath_tick)


func test_blocked_flag_true_through_sequence_false_during_cooldown_and_idle() -> void:
	var stuck := BotStuck.new()
	var outs := _run_stuck_scenario(stuck, 260)
	for i in outs.size():
		var out: Dictionary = outs[i]
		var should_be_blocked: bool = out.phase == BotStuck.Phase.WIGGLE \
				or out.phase == BotStuck.Phase.JUMP \
				or out.phase == BotStuck.Phase.REQUEST_REPATH
		assert_bool(out.blocked).append_failure_message(
			"tick %d, phase %d : blocked=%s attendu %s" % [i, out.phase, out.blocked, should_be_blocked]
		).is_equal(should_be_blocked)


func test_wiggle_move_override_oscillates_both_directions() -> void:
	var stuck := BotStuck.new()
	var outs := _run_stuck_scenario(stuck, 260)
	var saw_positive := false
	var saw_negative := false
	for out in outs:
		if out.phase == BotStuck.Phase.WIGGLE:
			var mv: Vector2 = out.move_override
			if mv.x > 0.01:
				saw_positive = true
			if mv.x < -0.01:
				saw_negative = true
	assert_bool(saw_positive).append_failure_message("le wiggle ne part jamais vers le côté positif").is_true()
	assert_bool(saw_negative).append_failure_message("le wiggle ne part jamais vers le côté négatif").is_true()


func test_jump_tick_has_zero_move_override_and_no_lateral_drift() -> void:
	var stuck := BotStuck.new()
	var outs := _run_stuck_scenario(stuck, 260)
	for out in outs:
		if bool(out.jump_pressed):
			assert_vector(out.move_override as Vector2).append_failure_message(
				"le tick de saut ne doit appliquer AUCUN déplacement latéral").is_equal(Vector2.ZERO)


func test_idle_ticks_have_null_move_override() -> void:
	var stuck := BotStuck.new()
	var pos := Vector3(9, 0, 9)
	for i in range(30):  # sous la fenêtre de 1 s : reste IDLE.
		var out := stuck.update(DT, pos, true)
		assert_that(out.move_override).is_null()


func test_cooldown_duration_then_returns_to_idle() -> void:
	var stuck := BotStuck.new()
	var outs := _run_stuck_then_escape_scenario(stuck, 400)
	var cooldown_ticks := 0
	var returned_to_idle := false
	var in_cooldown_or_later := false
	for out in outs:
		if out.phase == BotStuck.Phase.COOLDOWN:
			in_cooldown_or_later = true
			cooldown_ticks += 1
		elif in_cooldown_or_later and out.phase == BotStuck.Phase.IDLE:
			returned_to_idle = true
			break
	assert_bool(returned_to_idle).append_failure_message("jamais revenu à IDLE après le cooldown (400 ticks simulés)").is_true()
	var cooldown_duration := float(cooldown_ticks) * DT
	assert_float(cooldown_duration).append_failure_message(
		"durée du cooldown observée %.3f s, attendu ~%.3f s" % [cooldown_duration, BotStuck.COOLDOWN_DURATION]
	).is_between(BotStuck.COOLDOWN_DURATION - 3.0 * DT, BotStuck.COOLDOWN_DURATION + 3.0 * DT)


func test_still_stuck_after_cooldown_triggers_a_second_sequence() -> void:
	# Le bot reste immobile pendant TOUTE la simulation (obstacle réel, pas
	# résolu par le premier repath) : une SECONDE séquence doit se déclencher
	# après le cooldown, la première n'est pas un verrou permanent.
	var stuck := BotStuck.new()
	var pos := Vector3(-4, 0, 6)
	var wiggle_episodes := 0
	var was_wiggle := false
	for i in range(500):
		var out := stuck.update(DT, pos, true)
		var is_wiggle: bool = out.phase == BotStuck.Phase.WIGGLE
		if is_wiggle and not was_wiggle:
			wiggle_episodes += 1
		was_wiggle = is_wiggle
	assert_int(wiggle_episodes).append_failure_message(
		"un bot qui reste bloqué doit redéclencher la séquence après le cooldown").is_greater_equal(2)


func test_sequence_is_deterministic_for_identical_inputs() -> void:
	# Aucun RNG dans BotStuck : deux instances nourries des MÊMES positions/deltas
	# produisent EXACTEMENT la même séquence (même phases, mêmes ticks de saut
	# et de repath) — jamais flaky.
	var a := BotStuck.new()
	var b := BotStuck.new()
	var outs_a := _run_stuck_scenario(a, 260, Vector3(1, 0, 1))
	var outs_b := _run_stuck_scenario(b, 260, Vector3(1, 0, 1))
	for i in outs_a.size():
		var oa: Dictionary = outs_a[i]
		var ob: Dictionary = outs_b[i]
		assert_int(oa.phase).append_failure_message("tick %d : phases divergentes" % i).is_equal(ob.phase)
		assert_bool(bool(oa.jump_pressed)).is_equal(bool(ob.jump_pressed))
		assert_bool(bool(oa.request_repath)).is_equal(bool(ob.request_repath))


# ======================================================================
#  Point intermédiaire alternatif — vecteurs purs (RID invalide : pas de
#  projection, seulement la géométrie perpendiculaire + alternance de côté).
# ======================================================================

func test_alternate_repath_point_offsets_perpendicular_to_blocked_dir() -> void:
	var stuck := BotStuck.new()
	var current := Vector3(10, 0, 10)
	var blocked_dir := Vector3(0, 0, -1)  # le bot avançait vers -Z.
	var pt := stuck.alternate_repath_point(current, blocked_dir, RID())
	# Perpendiculaire à (0,0,-1) dans le plan XZ : décalage purement latéral
	# (X), AUCUN déplacement le long de la direction bloquée (Z inchangé).
	assert_float(pt.z).append_failure_message("le décalage ne doit pas avancer le long de la direction bloquée").is_equal_approx(current.z, 0.0001)
	assert_float(absf(pt.x - current.x)).append_failure_message(
		"amplitude du décalage latéral attendue ALT_POINT_OFFSET").is_equal_approx(BotStuck.ALT_POINT_OFFSET, 0.0001)


func test_alternate_repath_point_alternates_sides_across_calls() -> void:
	var stuck := BotStuck.new()
	var current := Vector3.ZERO
	var blocked_dir := Vector3(0, 0, -1)
	var first := stuck.alternate_repath_point(current, blocked_dir, RID())
	var second := stuck.alternate_repath_point(current, blocked_dir, RID())
	assert_float(first.x).append_failure_message(
		"deux appels successifs doivent alterner de côté (x opposé)").is_equal_approx(-second.x, 0.0001)


func test_alternate_repath_point_alternation_is_stable_across_four_calls() -> void:
	var stuck := BotStuck.new()
	var current := Vector3.ZERO
	var blocked_dir := Vector3(0, 0, -1)
	var xs: Array = []
	for i in range(4):
		xs.append(stuck.alternate_repath_point(current, blocked_dir, RID()).x)
	assert_float(xs[0]).is_equal_approx(xs[2] as float, 0.0001)
	assert_float(xs[1]).is_equal_approx(xs[3] as float, 0.0001)
	assert_float(xs[0]).is_equal_approx(-(xs[1] as float), 0.0001)


func test_alternate_repath_point_falls_back_to_a_direction_when_blocked_dir_is_zero() -> void:
	var stuck := BotStuck.new()
	var current := Vector3(5, 0, 5)
	var pt := stuck.alternate_repath_point(current, Vector3.ZERO, RID())
	# Aucun crash, aucune division par zéro : un décalage de la bonne amplitude
	# est quand même produit (direction de repli documentée, peu importe laquelle).
	assert_float(current.distance_to(pt)).is_equal_approx(BotStuck.ALT_POINT_OFFSET, 0.0001)


func test_alternate_repath_point_ignores_vertical_component_of_blocked_dir() -> void:
	var stuck := BotStuck.new()
	var current := Vector3(0, 2, 0)
	var pt := stuck.alternate_repath_point(current, Vector3(0, -1, 0), RID())
	# `blocked_dir` purement vertical -> aucune composante horizontale : replié
	# sur la direction de secours (Vector3.FORWARD), jamais un décalage vertical.
	assert_float(pt.y).is_equal_approx(current.y, 0.0001)


func test_project_strafe_to_navmesh_returns_unchanged_for_invalid_map() -> void:
	var p := Vector3(3, 1, -4)
	var result := BotStuck.project_strafe_to_navmesh(p, RID())
	assert_vector(result).is_equal(p)


# ======================================================================
#  Projection sur une navmesh RÉELLE — StaticBody3D bakés (comme
#  tests/ai/test_bot_spots.gd), synchronisés avant toute requête.
# ======================================================================

const NAV_SYNC_FRAMES := 15  ## voir tools/bake_bot_spots.gd::NAV_SYNC_FRAMES / test_bot_spots.gd.

var _next_offset_index := 0


func _offset() -> Vector3:
	var o := Vector3(float(_next_offset_index) * 200.0, 0.0, 0.0)
	_next_offset_index += 1
	return o


func _room(offset: Vector3) -> Node3D:
	var root_node := Node3D.new()
	root_node.name = "BotStuckTestRoom"
	root_node.position = offset
	add_child(root_node)
	return root_node


func _floor(parent: Node3D, center: Vector3, size_x: float, size_z: float) -> void:
	var body := StaticBody3D.new()
	body.position = center + Vector3(0, -0.5, 0)
	body.collision_layer = PhysicsLayers.WORLD
	body.collision_mask = 0
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(size_x, 1, size_z)
	col.shape = shape
	body.add_child(col)
	parent.add_child(body)


func _bake_room(root_node: Node3D) -> RID:
	BotNavMesh.ensure_baked(root_node)
	for i in NAV_SYNC_FRAMES:
		await get_tree().physics_frame
	return root_node.get_world_3d().get_navigation_map()


func _teardown(root_node: Node3D) -> void:
	remove_child(root_node)
	root_node.free()
	await get_tree().physics_frame


func test_project_strafe_to_navmesh_snaps_far_off_mesh_point_onto_surface() -> void:
	var offset := _offset()
	var root := _room(offset)
	_floor(root, Vector3(0, 0, 0), 10, 10)  # sol carré x[-5,5] z[-5,5] (local).
	var nav_map := await _bake_room(root)

	var far_point: Vector3 = root.global_transform * Vector3(50, 0, 50)
	var projected := BotStuck.project_strafe_to_navmesh(far_point, nav_map)

	var room_center: Vector3 = root.global_transform * Vector3.ZERO
	assert_float(room_center.distance_to(projected)).append_failure_message(
		"un point à 50 m du sol devrait revenir projeté PRÈS du sol, pas laissé loin").is_less(10.0)

	# Idempotence : un point déjà SUR la navmesh reste (quasi) inchangé.
	var projected_again := BotStuck.project_strafe_to_navmesh(projected, nav_map)
	assert_vector(projected_again).append_failure_message(
		"reprojeter un point déjà sur la navmesh ne devrait presque pas le déplacer"
	).is_equal_approx(projected, Vector3.ONE * 0.05)
	await _teardown(root)


func test_project_strafe_to_navmesh_leaves_an_already_walkable_point_close_to_itself() -> void:
	var offset := _offset()
	var root := _room(offset)
	_floor(root, Vector3(0, 0, 0), 10, 10)
	var nav_map := await _bake_room(root)

	var inside: Vector3 = root.global_transform * Vector3(1, 0, 1)  # bien à l'intérieur du sol 10x10.
	var projected := BotStuck.project_strafe_to_navmesh(inside, nav_map)
	assert_float(inside.distance_to(projected)).append_failure_message(
		"un point déjà bien à l'intérieur de la navmesh ne devrait presque pas bouger").is_less(1.0)
	await _teardown(root)


func test_alternate_repath_point_off_mesh_candidate_is_snapped_back_onto_the_floor() -> void:
	var offset := _offset()
	var root := _room(offset)
	_floor(root, Vector3(0, 0, 0), 6, 6)  # sol carré x[-3,3] z[-3,3] (local).
	var nav_map := await _bake_room(root)

	var stuck := BotStuck.new()
	# `_alt_side` démarre à +1 (première utilisation d'une instance neuve) :
	# perpendiculaire à blocked_dir=(0,0,-1) -> (+1,0,0), donc le PREMIER appel
	# décale vers +X, ici délibérément HORS du sol (bot proche du bord +X).
	var bot_local := Vector3(2.5, 0, 0)
	var bot_pos: Vector3 = root.global_transform * bot_local
	var blocked_dir := Vector3(0, 0, -1)

	var raw_candidate := bot_pos + Vector3(1, 0, 0) * BotStuck.ALT_POINT_OFFSET  # (=4.5 local en X), hors du sol (bord à 3).
	var pt := stuck.alternate_repath_point(bot_pos, blocked_dir, nav_map)

	assert_float(pt.distance_to(raw_candidate)).append_failure_message(
		"le point hors navmesh devrait être RAMENÉ vers la surface, pas laissé tel quel").is_greater(0.3)
	var local_pt: Vector3 = root.global_transform.affine_inverse() * pt
	assert_float(local_pt.x).append_failure_message(
		"le point alternatif projeté devrait rester DANS (ou très près) du sol 6x6").is_less_equal(3.2)
	assert_float(local_pt.x).append_failure_message(
		"le point alternatif ne devrait pas être totalement annulé (toujours décalé vers +X)").is_greater(bot_local.x)
	await _teardown(root)
