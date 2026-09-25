## test_bot_memory.gd
## Spec (BOT-03, docs/research/02_bots_ai.md §2.2/§3, tâche BOT-03) : BotMemory
## est PUR (aucun accès à l'arbre de scène) — voir l'en-tête de BotMemory.gd :
##  - §1 : décroissance de la confiance (LINÉAIRE, nulle à 6 s pile) ;
##  - §2 : extrapolation "à l'estime" (dead reckoning, pos + vel × âge) ;
##  - §3 : fusion PONDÉRÉE de deux observations (jamais une simple
##    substitution "la plus récente écrase l'autre") ;
##  - §4 : API d'instance (`observe`/`confidence`/`has_memory`/
##    `predicted_position`/`clear`), telle qu'utilisée par
##    scripts/ai/BotBrain.gd (`_enemy_memory`).
extends GdUnitTestSuite

const DECAY_S := BotMemory.CONFIDENCE_DECAY_S  ## 6.0 s (BOT-03 : "confiance qui décroît sur 6 s").


# ======================================================================
#  §1 — Décroissance de la confiance (statique, `confidence_at`).
# ======================================================================

func test_confidence_at_zero_age_is_full() -> void:
	assert_float(BotMemory.confidence_at(0.0)).is_equal_approx(1.0, 0.0001)


func test_confidence_at_half_decay_is_half() -> void:
	assert_float(BotMemory.confidence_at(DECAY_S * 0.5)).is_equal_approx(0.5, 0.0001)


func test_confidence_decreases_linearly() -> void:
	# Décroissance LINÉAIRE (pas exponentielle) : la confiance à 1/4 et 3/4 de
	# la fenêtre est exactement 0.75 et 0.25 — une exponentielle ne donnerait
	# pas ces valeurs rondes.
	assert_float(BotMemory.confidence_at(DECAY_S * 0.25)).is_equal_approx(0.75, 0.0001)
	assert_float(BotMemory.confidence_at(DECAY_S * 0.75)).is_equal_approx(0.25, 0.0001)


func test_confidence_at_exactly_decay_window_is_zero() -> void:
	assert_float(BotMemory.confidence_at(DECAY_S)).is_equal_approx(0.0, 0.0001)


func test_confidence_beyond_decay_window_stays_zero_never_negative() -> void:
	assert_float(BotMemory.confidence_at(DECAY_S * 10.0)).is_equal_approx(0.0, 0.0001)


func test_confidence_negative_age_clamped_to_full() -> void:
	# Un âge négatif (horloge légèrement désynchronisée) ne doit jamais
	# produire une confiance > 1.0.
	assert_float(BotMemory.confidence_at(-1.0)).is_equal_approx(1.0, 0.0001)


# ======================================================================
#  §2 — Extrapolation "à l'estime" (statique, `extrapolated_position`).
# ======================================================================

func test_extrapolated_position_static_target_never_moves() -> void:
	var pos := Vector3(5, 0, 10)
	var result := BotMemory.extrapolated_position(pos, Vector3.ZERO, 3.0)
	assert_vector(result).is_equal_approx(pos, Vector3(0.001, 0.001, 0.001))


func test_extrapolated_position_moving_target_advances_along_velocity() -> void:
	var pos := Vector3.ZERO
	var vel := Vector3(2.0, 0.0, 0.0)  # 2 m/s le long de X.
	var result := BotMemory.extrapolated_position(pos, vel, 1.5)
	assert_vector(result).is_equal_approx(Vector3(3.0, 0.0, 0.0), Vector3(0.001, 0.001, 0.001))


func test_extrapolated_position_negative_age_clamped_to_zero() -> void:
	var pos := Vector3(1, 0, 1)
	var result := BotMemory.extrapolated_position(pos, Vector3(5, 0, 0), -2.0)
	assert_vector(result).is_equal_approx(pos, Vector3(0.001, 0.001, 0.001))


# ======================================================================
#  §3 — Fusion PONDÉRÉE (statique, `fuse`) : le cœur de "fusion d'observations".
# ======================================================================

func test_fuse_empty_a_returns_b_unchanged() -> void:
	var b := {"pos": Vector3(1, 0, 1), "vel": Vector3.ZERO, "time": 10.0}
	var fused := BotMemory.fuse({}, b, 10.0)
	assert_vector(fused.pos).is_equal_approx(b.pos, Vector3(0.001, 0.001, 0.001))
	assert_float(fused.time).is_equal_approx(10.0, 0.0001)


func test_fuse_empty_b_returns_a_unchanged() -> void:
	var a := {"pos": Vector3(2, 0, 3), "vel": Vector3.ZERO, "time": 5.0}
	var fused := BotMemory.fuse(a, {}, 5.0)
	assert_vector(fused.pos).is_equal_approx(a.pos, Vector3(0.001, 0.001, 0.001))


## Deux observations aussi FRAÎCHES l'une que l'autre (même confiance, 1.0 à
## `now`) se moyennent à PARTS ÉGALES — la marque d'une vraie fusion, pas une
## simple priorité "la plus récente gagne" (qui donnerait ici l'une OU
## l'autre position, jamais leur milieu).
func test_fuse_equal_confidence_averages_positions_evenly() -> void:
	var now := 10.0
	var a := {"pos": Vector3(0, 0, 0), "vel": Vector3.ZERO, "time": now}
	var b := {"pos": Vector3(10, 0, 0), "vel": Vector3.ZERO, "time": now}
	var fused := BotMemory.fuse(a, b, now)
	assert_vector(fused.pos).is_equal_approx(Vector3(5, 0, 0), Vector3(0.01, 0.01, 0.01))


## Une observation qui a déjà commencé à décroître (moins confiante) pèse
## MOINS dans la fusion qu'une observation toute fraîche — le résultat est
## tiré vers la fraîche, mais ne saute pas instantanément dessus (elle
## n'écrase pas complètement l'ancienne tant que celle-ci garde une
## confiance non nulle).
func test_fuse_fresher_observation_dominates_without_fully_overriding() -> void:
	var now := 10.0
	var stale := {"pos": Vector3(0, 0, 0), "vel": Vector3.ZERO, "time": now - DECAY_S * 0.5}  # confiance 0.5
	var fresh := {"pos": Vector3(10, 0, 0), "vel": Vector3.ZERO, "time": now}                  # confiance 1.0
	var fused := BotMemory.fuse(stale, fresh, now)
	# Pondération 0.5/1.0 -> 1/3 vers l'ancienne, 2/3 vers la fraîche.
	assert_float(fused.pos.x).append_failure_message(
		"fusion pondérée attendue proche de 6.67 (2/3 de 10), pas 10.0 (substitution) ni 5.0 (moyenne égale)"
	).is_equal_approx(6.6667, 0.01)
	assert_float(fused.pos.x).is_greater(5.0)   # tirée vers la fraîche...
	assert_float(fused.pos.x).is_less(10.0)     # ...mais ne l'atteint pas complètement.


## Fusionner une mémoire FRAÎCHE avec une mémoire totalement épuisée
## (confiance nulle, >= 6 s) équivaut à IGNORER l'épuisée : la fraîche
## l'emporte intégralement (poids nul, pas de division par zéro).
func test_fuse_expired_memory_contributes_nothing() -> void:
	var now := 100.0
	var expired := {"pos": Vector3(-50, 0, 0), "vel": Vector3.ZERO, "time": now - DECAY_S * 5.0}
	var fresh := {"pos": Vector3(3, 0, 4), "vel": Vector3.ZERO, "time": now}
	var fused := BotMemory.fuse(expired, fresh, now)
	assert_vector(fused.pos).is_equal_approx(fresh.pos, Vector3(0.01, 0.01, 0.01))


## Les DEUX observations sont épuisées (confiance nulle des deux côtés) :
## aucune pondération n'a de sens (0/0) — repli sur la moins ancienne des
## deux, jamais un crash ni une position NaN.
func test_fuse_both_expired_keeps_the_less_stale_one() -> void:
	var now := 100.0
	var older := {"pos": Vector3(1, 0, 0), "vel": Vector3.ZERO, "time": now - DECAY_S * 10.0}
	var newer_but_still_expired := {"pos": Vector3(2, 0, 0), "vel": Vector3.ZERO, "time": now - DECAY_S * 8.0}
	var fused := BotMemory.fuse(older, newer_but_still_expired, now)
	assert_bool(is_nan(fused.pos.x)).append_failure_message("la fusion de deux poids nuls ne doit jamais produire NaN").is_false()
	assert_vector(fused.pos).is_equal_approx(newer_but_still_expired.pos, Vector3(0.01, 0.01, 0.01))


func test_fuse_result_time_is_the_most_recent_of_the_two() -> void:
	var now := 10.0
	var a := {"pos": Vector3.ZERO, "vel": Vector3.ZERO, "time": now - 1.0}
	var b := {"pos": Vector3(1, 0, 0), "vel": Vector3.ZERO, "time": now}
	assert_float(BotMemory.fuse(a, b, now).time).is_equal_approx(now, 0.0001)
	assert_float(BotMemory.fuse(b, a, now).time).is_equal_approx(now, 0.0001)


func test_fuse_averages_velocity_the_same_way_as_position() -> void:
	var now := 10.0
	var a := {"pos": Vector3.ZERO, "vel": Vector3(2, 0, 0), "time": now}
	var b := {"pos": Vector3.ZERO, "vel": Vector3(6, 0, 0), "time": now}
	var fused := BotMemory.fuse(a, b, now)
	assert_vector(fused.vel).is_equal_approx(Vector3(4, 0, 0), Vector3(0.01, 0.01, 0.01))


# ======================================================================
#  §4 — API d'instance : `observe`/`confidence`/`has_memory`/
#  `predicted_position`/`last_velocity`/`clear`.
# ======================================================================

func test_new_instance_has_no_memory() -> void:
	var mem := BotMemory.new()
	assert_bool(mem.has_memory(0.0)).is_false()
	assert_float(mem.confidence(0.0)).is_equal_approx(0.0, 0.0001)
	assert_vector(mem.predicted_position(0.0)).is_equal_approx(Vector3.INF, Vector3(0.001, 0.001, 0.001))
	assert_vector(mem.last_velocity()).is_equal_approx(Vector3.ZERO, Vector3(0.001, 0.001, 0.001))


func test_single_observation_is_stored_and_fully_confident_immediately() -> void:
	var mem := BotMemory.new()
	mem.observe(Vector3(4, 0, 4), Vector3(1, 0, 0), 10.0, 10.0)
	assert_bool(mem.has_memory(10.0)).is_true()
	assert_float(mem.confidence(10.0)).is_equal_approx(1.0, 0.0001)
	assert_vector(mem.predicted_position(10.0)).is_equal_approx(Vector3(4, 0, 4), Vector3(0.01, 0.01, 0.01))


func test_memory_confidence_decays_after_observation() -> void:
	var mem := BotMemory.new()
	mem.observe(Vector3(0, 0, 0), Vector3.ZERO, 0.0, 0.0)
	assert_float(mem.confidence(DECAY_S * 0.5)).is_equal_approx(0.5, 0.0001)
	assert_bool(mem.has_memory(DECAY_S)).is_false()
	assert_bool(mem.has_memory(DECAY_S * 0.9)).is_true()


func test_predicted_position_extrapolates_with_stored_velocity() -> void:
	var mem := BotMemory.new()
	mem.observe(Vector3(0, 0, 0), Vector3(0, 0, 3), 0.0, 0.0)  # 3 m/s le long de Z.
	var predicted := mem.predicted_position(2.0)
	assert_vector(predicted).is_equal_approx(Vector3(0, 0, 6), Vector3(0.01, 0.01, 0.01))


## Une SECONDE observation FUSIONNE avec la première (moyenne pondérée),
## elle ne l'ÉCRASE pas — critère explicite de la tâche ("fusion
## d'observations", pas "dernière observation gagne").
func test_second_observation_fuses_with_the_first_rather_than_overriding() -> void:
	var mem := BotMemory.new()
	mem.observe(Vector3(0, 0, 0), Vector3.ZERO, 10.0, 10.0)   # perception directe, fraîche.
	mem.observe(Vector3(10, 0, 0), Vector3.ZERO, 10.0, 10.0)  # rapport d'équipe, AUSSI fraîche (même `time`).
	var fused_pos: Vector3 = mem.to_dict().pos
	assert_float(fused_pos.x).append_failure_message(
		"deux observations aussi fraîches l'une que l'autre doivent se moyenner (x proche de 5), pas s'écraser (x = 0 ou 10)"
	).is_equal_approx(5.0, 0.01)


## Une observation qui arrive PLUS TARD (ex. rapport d'équipe retardé, `time`
## antérieur à `now`) est pondérée par SA PROPRE fraîcheur à `now` — pas par
## son ordre d'arrivée : un rapport vieux de 5 s à son arrivée ne doit PAS
## peser autant qu'une perception directe de CE tick.
func test_observe_weighs_a_delayed_team_report_by_its_own_age_not_arrival_order() -> void:
	var mem := BotMemory.new()
	mem.observe(Vector3(0, 0, 0), Vector3.ZERO, 10.0, 10.0)          # perception directe à t=10, fraîche.
	# Rapport d'équipe : l'ennemi a été vu à t=5 (déjà vieux de 5 s), reçu
	# seulement maintenant (`now = 10.75`, après le délai de partage).
	mem.observe(Vector3(100, 0, 0), Vector3.ZERO, 5.0, 10.75)
	var fused_pos: Vector3 = mem.to_dict().pos
	# Confiance directe à t=10.75 (âge 0.75 s) très proche de 1.0 ; confiance
	# du rapport (âge 5.75 s sur une fenêtre de 6 s) proche de 0.04 : le
	# résultat doit rester TRÈS proche de 0 (perception directe), pas dérivé
	# vers 100.
	assert_float(fused_pos.x).is_less(15.0)


func test_clear_forgets_everything() -> void:
	var mem := BotMemory.new()
	mem.observe(Vector3(1, 2, 3), Vector3.ONE, 0.0, 0.0)
	mem.clear()
	assert_bool(mem.has_memory(0.0)).is_false()
	assert_vector(mem.predicted_position(0.0)).is_equal_approx(Vector3.INF, Vector3(0.001, 0.001, 0.001))
