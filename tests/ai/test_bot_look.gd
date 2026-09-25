## test_bot_look.gd
## Spec (BOT-25, docs/research/08_bots_humanlike.md §3.1, règles L1-L6,
## absorbe BOTFIX-01) : BotLook est le regard HORS COMBAT, PUR (aucun accès à
## l'arbre de scène) — voir l'en-tête de BotLook.gd pour le détail de la
## priorité de sélection (mémoire ennemie/ouïe/coin en signaux de sécurité
## réévalués chaque tick, puis angle K/point du chemin sur une minuterie
## U(1;2) s ou U(5;10) s en tenue d'angle), le ressort quasi critique
## PLAFONNÉ en vitesse (360°/s) et en accélération (3000°/s²), et le balayage
## des angles connus une fois le but de navigation atteint (L5, remplace
## BOTFIX-01).
##
## §1-§5 : fonctions STATIQUES pures (géométrie, coin, repli, ressort).
## §6 : scénarios d'instance (`tick()`) — coin, priorité, minuterie/tenue
## d'angle, but atteint (balayage), tangage plat vs point d'intérêt.
extends GdUnitTestSuite

const DT := 1.0 / 60.0   ## Pas physique de référence (BotBrain._physics_process tourne à 60 Hz).


# ======================================================================
#  §1 — Géométrie de visée (desired_yaw_pitch_deg / yaw_forward_dir).
# ======================================================================

func test_desired_yaw_pitch_straight_ahead_is_zero() -> void:
	var yp := BotLook.desired_yaw_pitch_deg(Vector3.ZERO, Vector3(0, 0, -5))
	assert_float(yp.yaw).is_equal_approx(0.0, 0.01)
	assert_float(yp.pitch).is_equal_approx(0.0, 0.01)


func test_desired_yaw_to_the_right_is_minus_90() -> void:
	var yp := BotLook.desired_yaw_pitch_deg(Vector3.ZERO, Vector3(5, 0, 0))
	assert_float(yp.yaw).is_equal_approx(-90.0, 0.01)
	assert_float(yp.pitch).is_equal_approx(0.0, 0.01)


func test_desired_pitch_up_towards_elevated_point() -> void:
	# Cible à 45° au-dessus de l'horizon (10 m plus haut, 10 m devant) : "il
	# lève les yeux vers les toits, le derrick, la grue" (L3, bulle 1).
	var yp := BotLook.desired_yaw_pitch_deg(Vector3.ZERO, Vector3(0, 10, -10))
	assert_float(yp.yaw).is_equal_approx(0.0, 0.01)
	assert_float(yp.pitch).is_equal_approx(45.0, 0.1)


func test_desired_pitch_clamped_to_89_deg_directly_overhead() -> void:
	var yp := BotLook.desired_yaw_pitch_deg(Vector3.ZERO, Vector3(0, 1000, 0))
	assert_float(yp.pitch).is_less_equal(89.0001)


func test_yaw_forward_dir_is_inverse_of_desired_yaw() -> void:
	# atan2(-x,-z) puis sa réciproque doivent se recomposer (aller-retour).
	for yaw_deg in [0.0, 45.0, -90.0, 135.0, -179.0]:
		var dir := BotLook.yaw_forward_dir(yaw_deg)
		var yp := BotLook.desired_yaw_pitch_deg(Vector3.ZERO, dir * 5.0)
		assert_float(yp.yaw).append_failure_message(
			"yaw %f -> dir -> yaw : aller-retour" % yaw_deg).is_equal_approx(yaw_deg, 0.05)


# ======================================================================
#  §2 — L6 : écart regard / déplacement -> marche au-delà de 70°.
# ======================================================================

func test_gaze_gap_is_zero_when_aligned_with_heading() -> void:
	var move_dir := BotLook.yaw_forward_dir(30.0)
	assert_float(BotLook.gaze_move_gap_deg(30.0, move_dir)).is_equal_approx(0.0, 0.05)


func test_gaze_gap_is_zero_when_not_moving() -> void:
	assert_float(BotLook.gaze_move_gap_deg(170.0, Vector3.ZERO)).is_equal_approx(0.0, 0.001)


func test_gaze_gap_handles_wraparound() -> void:
	var move_dir := BotLook.yaw_forward_dir(-170.0)
	assert_float(BotLook.gaze_move_gap_deg(170.0, move_dir)).is_equal_approx(20.0, 0.05)


func test_should_walk_false_at_60_deg_gap_true_at_90() -> void:
	assert_bool(BotLook.should_walk(60.0, BotLook.yaw_forward_dir(0.0))).is_false()
	assert_bool(BotLook.should_walk(90.0, BotLook.yaw_forward_dir(0.0))).is_true()


func test_should_walk_never_true_while_stationary() -> void:
	assert_bool(BotLook.should_walk(180.0, Vector3.ZERO)).is_false()


# ======================================================================
#  §3 — L2 : pré-visée des coins (> 30°, < 4 m).
# ======================================================================

func test_sharp_corner_within_range_is_found_and_looks_past_the_turn() -> void:
	var path := [Vector3(2, 0, 0), Vector3(2, 0, -2)]  # virage à 90°, 2 m devant.
	var corner := BotLook.find_sharp_corner(path, Vector3.ZERO)
	assert_bool(corner.found).is_true()
	assert_float(corner.turn_deg).is_equal_approx(90.0, 0.1)
	# Point regardé : CORNER_LOOK_AHEAD_M (3 m) après le sommet, dans la
	# direction de SORTIE du virage (0,0,-2) normalisée -> (2,0,-3).
	assert_vector(corner.pos).is_equal_approx(Vector3(2, 0, -3), Vector3(0.01, 0.01, 0.01))


func test_shallow_turn_is_not_a_corner() -> void:
	var path := [Vector3(2, 0, 0), Vector3(4, 0, 0.2)]  # quasiment tout droit.
	assert_bool(BotLook.find_sharp_corner(path, Vector3.ZERO).found).is_false()


func test_sharp_corner_beyond_4m_is_not_pre_aimed() -> void:
	var path := [Vector3(10, 0, 0), Vector3(10, 0, -2)]  # virage à 90°, mais à 10 m.
	assert_bool(BotLook.find_sharp_corner(path, Vector3.ZERO).found).is_false()


func test_too_few_path_points_is_not_a_corner() -> void:
	assert_bool(BotLook.find_sharp_corner([], Vector3.ZERO).found).is_false()
	assert_bool(BotLook.find_sharp_corner([Vector3(2, 0, 0)], Vector3.ZERO).found).is_false()


func test_degenerate_segments_are_not_a_corner() -> void:
	# Le bot EST déjà sur p0 (segment d'entrée nul) : direction indéfinie.
	var path := [Vector3.ZERO, Vector3(2, 0, -2)]
	assert_bool(BotLook.find_sharp_corner(path, Vector3.ZERO).found).is_false()


# ======================================================================
#  §4 — L1 repli : point du chemin 4 m devant.
# ======================================================================

func test_point_ahead_interpolates_across_a_segment_boundary() -> void:
	var path := [Vector3(0, 0, -2), Vector3(0, 0, -6)]
	var p := BotLook.point_ahead_on_path(path, Vector3.ZERO, 4.0)
	assert_vector(p).is_equal_approx(Vector3(0, 0, -4), Vector3(0.001, 0.001, 0.001))


func test_point_ahead_clamps_to_last_point_if_path_shorter() -> void:
	var path := [Vector3(0, 0, -1)]
	var p := BotLook.point_ahead_on_path(path, Vector3.ZERO, 4.0)
	assert_vector(p).is_equal(Vector3(0, 0, -1))


func test_point_ahead_is_bot_pos_when_path_is_empty() -> void:
	var p := BotLook.point_ahead_on_path([], Vector3(3, 0, 3), 4.0)
	assert_vector(p).is_equal(Vector3(3, 0, 3))


# ======================================================================
#  §5 — L4 : ressort quasi critique PLAFONNÉ (vitesse ≤ 360°/s, accélération
#  ≤ 3000°/s²), quasiment aucun dépassement (ζ 0.85-1.0).
# ======================================================================

func test_acceleration_never_exceeds_hard_cap_on_a_huge_jump() -> void:
	var params := BotLook.spring_params()
	var step := BotLook.spring_step_capped(0.0, 0.0, 1000.0, params.k, params.d, DT)
	var accel: float = float(step.speed) / DT  # vitesse partie de 0.0 : accel = Δv / Δt.
	assert_float(absf(accel)).is_less_equal(BotLook.MAX_ACCEL_DEG + 0.01)


func test_speed_never_exceeds_hard_cap_across_many_ticks() -> void:
	var params := BotLook.spring_params()
	var angle := 0.0
	var speed := 0.0
	for i in range(600):  # 10 s simulées.
		var step := BotLook.spring_step_capped(angle, speed, 180.0, params.k, params.d, DT)
		angle = step.angle
		speed = step.speed
		assert_float(absf(speed)).append_failure_message(
			"tick %d : vitesse %f > plafond %f" % [i, speed, BotLook.MAX_SPEED_DEG]).is_less_equal(BotLook.MAX_SPEED_DEG + 0.01)


func test_never_more_than_45_deg_in_60ms() -> void:
	# Conséquence directe de MAX_SPEED_DEG (L4) : à 360°/s, 60 ms ne peuvent
	# jamais couvrir plus de 21.6° — bien en-deçà de 45°, quel que soit le
	# pas d'intégration.
	assert_float(BotLook.MAX_SPEED_DEG * 0.06).is_less(45.0)
	var params := BotLook.spring_params()
	var angle := 0.0
	var speed := 0.0
	var window: Array = []  # {"t": float, "angle": float}
	var t := 0.0
	for i in range(6):  # 100 ms simulées, largement au-delà de la fenêtre de 60 ms.
		var step := BotLook.spring_step_capped(angle, speed, 100000.0, params.k, params.d, DT)
		angle = step.angle
		speed = step.speed
		t += DT
		window.append({"t": t, "angle": angle})
	for a in window:
		for b in window:
			if absf(float(b.t) - float(a.t)) <= 0.06:
				assert_float(absf(float(b.angle) - float(a.angle))).append_failure_message(
					"plus de 45° parcourus en 60 ms ou moins").is_less(45.0)


func test_near_critical_spring_has_negligible_overshoot() -> void:
	var params := BotLook.spring_params()
	assert_float(BotLook.SPRING_ZETA).is_between(0.85, 1.0)
	var angle := 0.0
	var speed := 0.0
	var target := 90.0
	var max_angle := 0.0
	for i in range(600):
		var step := BotLook.spring_step_capped(angle, speed, target, params.k, params.d, DT)
		angle = step.angle
		speed = step.speed
		max_angle = maxf(max_angle, angle)
	assert_float(angle).is_equal_approx(target, 0.05)
	assert_float(max_angle - target).append_failure_message(
		"dépassement %f° au-delà de la cible : pas 'quasi critique'" % (max_angle - target)).is_less(0.5)


# ======================================================================
#  §6 — Scénarios d'instance (tick()).
# ======================================================================

static func _base_ctx(rng: RandomNumberGenerator) -> Dictionary:
	return {
		"bot_pos": Vector3.ZERO,
		"eye_pos": Vector3(0, 1.6, 0),
		"cur_yaw_deg": 0.0,
		"cur_pitch_deg": 0.0,
		"move_dir": Vector3.ZERO,
		"path_points": [],
		"has_enemy_memory": false,
		"enemy_pos": Vector3.ZERO,
		"has_heard": false,
		"heard_pos": Vector3.ZERO,
		"map_knowledge": null,
		"holding_angle": false,
		"goal_reached": false,
		"rng": rng,
	}


func test_corner_scenario_takes_priority_over_plain_path_point() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var look := BotLook.new()
	var ctx := _base_ctx(rng)
	ctx.path_points = [Vector3(2, 0, 0), Vector3(2, 0, -2)]  # virage à 90°, 2 m devant.
	var r := look.tick(DT, ctx)
	assert_str(r.target_kind).is_equal("corner")
	assert_vector(r.target_pos).is_equal_approx(Vector3(2, 0, -3), Vector3(0.01, 0.01, 0.01))
	# L3 : point au sol -> +1.5 m de hauteur ajoutés pour le regard réel.
	assert_vector(r.gaze_point).is_equal_approx(Vector3(2, 1.5, -3), Vector3(0.01, 0.01, 0.01))


func test_enemy_memory_beats_heard_beats_corner() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var ctx := _base_ctx(rng)
	ctx.path_points = [Vector3(2, 0, 0), Vector3(2, 0, -2)]
	ctx.has_heard = true
	ctx.heard_pos = Vector3(-9, 0, 0)
	ctx.has_enemy_memory = true
	ctx.enemy_pos = Vector3(9, 0, 0)

	var look_enemy := BotLook.new()
	assert_str(look_enemy.tick(DT, ctx).target_kind).is_equal("enemy")

	ctx.has_enemy_memory = false
	var look_heard := BotLook.new()
	assert_str(look_heard.tick(DT, ctx).target_kind).is_equal("heard")

	ctx.has_heard = false
	var look_corner := BotLook.new()
	assert_str(look_corner.tick(DT, ctx).target_kind).is_equal("corner")


func test_map_angle_in_cone_is_chosen_when_no_safety_signal_applies() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var mk := BotMapKnowledge.new({"angles": [{"pos": Vector3(0, 0, -10), "dir": Vector3.ZERO}]})
	var ctx := _base_ctx(rng)
	ctx.map_knowledge = mk
	var look := BotLook.new()
	var r := look.tick(DT, ctx)
	assert_str(r.target_kind).is_equal("angle")
	assert_vector(r.target_pos).is_equal(Vector3(0, 0, -10))


func test_retarget_dwell_is_1_to_2s_normally_and_5_to_10s_holding_angle() -> void:
	var seen_normal: Array = []
	var seen_holding: Array = []
	for i in range(60):
		var rng := RandomNumberGenerator.new()
		rng.seed = 1000 + i
		var ctx := _base_ctx(rng)

		var normal := BotLook.new()
		var dwell_n: float = normal.tick(DT, ctx).new_yaw_deg  # force l'évaluation ; valeur ignorée.
		dwell_n = normal.dwell_left_s()
		seen_normal.append(dwell_n)
		assert_float(dwell_n).append_failure_message(
			"essai %d hors tenue d'angle : %f hors de [1;2]" % [i, dwell_n]).is_between(1.0, 2.0)

		ctx.holding_angle = true
		var holding := BotLook.new()
		holding.tick(DT, ctx)
		var dwell_h := holding.dwell_left_s()
		seen_holding.append(dwell_h)
		assert_float(dwell_h).append_failure_message(
			"essai %d en tenue d'angle : %f hors de [5;10]" % [i, dwell_h]).is_between(5.0, 10.0)

	# "jamais une valeur fixe" : au moins deux valeurs distinctes sur l'échantillon.
	assert_bool(seen_normal[0] != seen_normal[1] or seen_normal[0] != seen_normal[2]).is_true()
	assert_bool(seen_holding[0] != seen_holding[1] or seen_holding[0] != seen_holding[2]).is_true()


func test_goal_reached_sweeps_known_angles_then_falls_back_to_path_point() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var mk := BotMapKnowledge.new({"angles": [
		{"pos": Vector3(5, 0, 0), "dir": Vector3.ZERO},
		{"pos": Vector3(0, 0, 5), "dir": Vector3.ZERO},
		{"pos": Vector3(-5, 0, 0), "dir": Vector3.ZERO},
	]})
	var ctx := _base_ctx(rng)
	ctx.map_knowledge = mk
	ctx.goal_reached = true
	var look := BotLook.new()

	# Un grand `delta` force une réévaluation à CHAQUE appel (dépasse toujours
	# la minuterie U(1;2)/U(5;10) s) : ne teste que la SÉQUENCE de sélection,
	# jamais la dynamique du ressort (couverte au §5).
	var r1 := look.tick(100.0, ctx)
	var r2 := look.tick(100.0, ctx)
	var r3 := look.tick(100.0, ctx)
	var r4 := look.tick(100.0, ctx)

	assert_str(r1.target_kind).is_equal("sweep")
	assert_str(r2.target_kind).is_equal("sweep")
	assert_str(r3.target_kind).is_equal("sweep")
	assert_vector(r1.target_pos).is_equal(Vector3(5, 0, 0))
	assert_vector(r2.target_pos).is_equal(Vector3(0, 0, 5))
	assert_vector(r3.target_pos).is_equal(Vector3(-5, 0, 0))
	# Passe complète : retombe sur le choix normal (aucun angle connu dans le
	# cône ±60° du cap par défaut -> repli "point du chemin").
	assert_str(r4.target_kind).append_failure_message(
		"le balayage devrait s'arrêter après une passe complète").is_equal("path_point")


func test_goal_reached_edge_only_refills_once() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var mk := BotMapKnowledge.new({"angles": [{"pos": Vector3(1, 0, 0), "dir": Vector3.ZERO}]})
	var ctx := _base_ctx(rng)
	ctx.map_knowledge = mk
	ctx.goal_reached = true
	var look := BotLook.new()
	look.tick(100.0, ctx)          # front montant : balaie le seul angle connu.
	var second := look.tick(100.0, ctx)  # PAS un nouveau front (goal_reached toujours vrai) : pas de re-remplissage.
	assert_str(second.target_kind).is_not_equal("sweep")


func test_holding_angle_adds_a_slow_sweep_around_the_held_target() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 13
	var mk := BotMapKnowledge.new({"angles": [{"pos": Vector3(0, 0, -10), "dir": Vector3.ZERO}]})
	var ctx := _base_ctx(rng)
	ctx.map_knowledge = mk
	ctx.holding_angle = true
	var look := BotLook.new()

	var yaws: Array = []
	for i in range(400):  # ~6.7 s à 60 Hz : largement plus d'une demi-période du balayage (6 s).
		var r := look.tick(DT, ctx)
		yaws.append(float(r.look_target_yaw_deg))

	var lo: float = yaws[0]
	var hi: float = yaws[0]
	for y in yaws:
		lo = minf(lo, float(y))
		hi = maxf(hi, float(y))
	assert_float(hi - lo).append_failure_message(
		"balayage ±15° absent (amplitude observée %f°)" % (hi - lo)).is_greater(10.0)
	assert_float(hi).is_less_equal(15.5)
	assert_float(lo).is_greater_equal(-15.5)


func test_flat_path_point_pitch_is_clamped_to_5_deg() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	var ctx := _base_ctx(rng)
	# Point de repli très en contrebas : sans écrêtage, le tangage viserait
	# largement plus de 5° vers le bas.
	ctx.path_points = [Vector3(0, -50.0, -4)]
	var look := BotLook.new()
	var cur_pitch := 0.0
	var cur_yaw := 0.0
	var last_target_pitch := 0.0
	for i in range(300):
		ctx.cur_yaw_deg = cur_yaw
		ctx.cur_pitch_deg = cur_pitch
		var r := look.tick(DT, ctx)
		cur_yaw = float(r.new_yaw_deg)
		cur_pitch = float(r.new_pitch_deg)
		last_target_pitch = float(r.look_target_pitch_deg)
	assert_str(look.tick(DT, ctx).target_kind).is_equal("path_point")
	assert_float(absf(last_target_pitch)).append_failure_message(
		"L3 : sur repli 'point du chemin', tangage cible hors de ±5° (%f)" % last_target_pitch).is_less_equal(5.001)
	assert_float(absf(cur_pitch)).is_less_equal(5.5)


func test_angle_target_pitch_is_not_flattened_looks_up_at_tall_point() -> void:
	# L3 bulle 1 : un angle K en hauteur (grue/derrick) n'est PAS écrêté à ±5°
	# — seul le repli "point du chemin" (bulle 2, sol plat) l'est.
	var rng := RandomNumberGenerator.new()
	rng.seed = 33
	var mk := BotMapKnowledge.new({"angles": [{"pos": Vector3(0, 10, -10), "dir": Vector3.ZERO}]})
	var ctx := _base_ctx(rng)
	ctx.map_knowledge = mk
	var look := BotLook.new()
	var r := look.tick(DT, ctx)
	assert_str(r.target_kind).is_equal("angle")
	assert_float(float(r.look_target_pitch_deg)).is_greater(5.0)
