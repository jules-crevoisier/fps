## test_bot_combat_style.gd
## Spec (BOT-04, docs/research/02_bots_ai.md §2.5/§4#5/§4#11, tasks/backlog.yaml ;
## BOT-21, docs/research/08_bots_humanlike.md §3.2 A7/A8) :
## BotCombatStyle est une table de discipline de combat PURE — armes de
## précision (Marqueur/Percuteur/Faucheur) qui exigent une vitesse < 30 % du
## sprint pour tirer, distance préférée par catégorie d'arme (pompe < 6 m,
## SMG 5-15, fusil 10-35, sniper > 25), rafales des armes automatiques
## au-delà de 25 m (3-5 tirs puis pause 150-250 ms), intervalle de strafe
## réactif (0.25-0.6 s si le bot est pris pour cible, 0.8-1.8 s sinon), rythme
## de tir semi-auto (un appui toutes les 0.15-0.40 s sous 20 m, 0.30-0.70 s
## au-delà, plafonné par la cadence de l'arme), hystérésis de l'ADS (maintenu
## 0.5-0.9 s après la dernière vue, au plus 1 bascule par 1.5 s), et marche
## (walk_held) en enquête/fin de round. Aucun état de scène : chaque fonction
## ne dépend que de ses arguments (sauf `burst_step`/`strafe_interval`/
## `ads_hold`, qui prennent un état/rng explicites, jamais un champ caché).
##
## Statut du critère verrouillé "Sur le banc Wasteland : B7, B8 et B14
## respectés" (B3 déplacé vers BOT-25 par décision du lead du 2026-09-25, voir
## BotCombatStyle.gd) : les tests ci-dessous couvrent la règle PURE de chaque
## fonction de style (bornes B7/B8, voir docs/research/08_bots_humanlike.md
## §3) ; `ads_hold`/`semi_auto_interval` elles-mêmes n'ont jamais été en cause.
## tools/bot_bench.gd (propriété BOT-20) mesure B7/B8/B14 en vif sur Wasteland.
## Vérifié par QA indépendant au 2026-09-25 sur 2 runs réels (hp_veteran +
## tdm_veteran, reports/bot_bench/qa_verify_BOT21.json et _ts1.json) :
## - B7 propre les 2 fois (p99 bascules ADS/engagement 1.0 puis 2.0, seuil
##   > 2.0) — le fix vivait dans BotBrain._tick_combat (`_ads_state` ne se
##   réinitialise plus à chaque changement de cible interne, pas dans
##   `ads_hold` elle-même, voir "BOT-21 (B7 fix)" dans BotBrain.gd).
## - B8 sans avertissement les 2 fois, mais par absence de données
##   (`b8_semi_auto_interval_cv`/`b8_semi_auto_max_rate_ratio` = -1.0, "pas
##   assez de tirs semi-auto échantillonnés") : pas une confirmation positive.
## - B14 EN AVERTISSEMENT les 2 fois (`b14_random_jumps` = 50 puis 222, jamais
##   0) : cause identifiée (le banc lit la phase BotStuck déjà transitionnée
##   au tick du saut légitime de déblocage, comptant chaque saut comme
##   "aléatoire") mais la correction vit dans tools/bot_bench.gd/BotStuck.gd,
##   hors de la liste de fichiers de BOT-21 — voir le commentaire correspondant
##   dans BotBrain.gd et le `blocked_on` du rendu de BOT-21.
extends GdUnitTestSuite

const CAT := WeaponConfig.Category

# ======================================================================
#  Armes de précision — nommées explicitement, jamais déduites de `automatic`.
# ======================================================================

func test_precision_weapons_are_named_explicitly() -> void:
	assert_bool(BotCombatStyle.is_precision_weapon("Marqueur")).is_true()
	assert_bool(BotCombatStyle.is_precision_weapon("Percuteur")).is_true()
	assert_bool(BotCombatStyle.is_precision_weapon("Faucheur")).is_true()


func test_other_semi_auto_weapons_are_not_precision() -> void:
	# Magnum/Pistolet/Fracas sont AUSSI semi-auto (automatic=false) sans pour
	# autant exiger l'arrêt — la liste est nommée, pas déduite du champ.
	assert_bool(BotCombatStyle.is_precision_weapon("Magnum")).is_false()
	assert_bool(BotCombatStyle.is_precision_weapon("Pistolet")).is_false()
	assert_bool(BotCombatStyle.is_precision_weapon("Fracas")).is_false()
	assert_bool(BotCombatStyle.is_precision_weapon("Ravage")).is_false()
	assert_bool(BotCombatStyle.is_precision_weapon("")).is_false()


func test_can_fire_at_speed_ignores_speed_for_non_precision_weapons() -> void:
	assert_bool(BotCombatStyle.can_fire_at_speed("Ravage", 0.0)).is_true()
	assert_bool(BotCombatStyle.can_fire_at_speed("Ravage", 1.0)).is_true()
	assert_bool(BotCombatStyle.can_fire_at_speed("Pistolet", 0.99)).is_true()


func test_precision_weapon_can_fire_under_30_percent_sprint() -> void:
	assert_bool(BotCombatStyle.can_fire_at_speed("Marqueur", 0.0)).is_true()
	assert_bool(BotCombatStyle.can_fire_at_speed("Faucheur", 0.29)).is_true()


func test_precision_weapon_cannot_fire_at_or_above_30_percent_sprint() -> void:
	assert_bool(BotCombatStyle.can_fire_at_speed("Marqueur", 0.30)).is_false()
	assert_bool(BotCombatStyle.can_fire_at_speed("Percuteur", 0.5)).is_false()
	assert_bool(BotCombatStyle.can_fire_at_speed("Faucheur", 1.0)).is_false()

# ======================================================================
#  Distance préférée par catégorie — pompe < 6 m, SMG 5-15, fusil 10-35,
#  sniper > 25 ; catégories non listées (poing/lourde/mêlée) : aucune
#  préférence.
# ======================================================================

func test_preferred_distance_band_matches_contract_per_category() -> void:
	var shotgun := BotCombatStyle.preferred_distance_band(CAT.SHOTGUN)
	assert_float(shotgun.min).is_equal_approx(0.0, 0.0001)
	assert_float(shotgun.max).is_equal_approx(6.0, 0.0001)

	var smg := BotCombatStyle.preferred_distance_band(CAT.SMG)
	assert_float(smg.min).is_equal_approx(5.0, 0.0001)
	assert_float(smg.max).is_equal_approx(15.0, 0.0001)

	var rifle := BotCombatStyle.preferred_distance_band(CAT.RIFLE)
	assert_float(rifle.min).is_equal_approx(10.0, 0.0001)
	assert_float(rifle.max).is_equal_approx(35.0, 0.0001)

	var sniper := BotCombatStyle.preferred_distance_band(CAT.SNIPER)
	assert_float(sniper.min).is_equal_approx(25.0, 0.0001)
	assert_bool(is_inf(sniper.max)).is_true()


func test_categories_without_a_documented_preference_have_no_band() -> void:
	for c in [CAT.SIDEARM, CAT.HEAVY, CAT.MELEE]:
		var band := BotCombatStyle.preferred_distance_band(c)
		assert_float(band.min).append_failure_message("catégorie %d : min devrait être 0" % c).is_equal_approx(0.0, 0.0001)
		assert_bool(is_inf(band.max)).append_failure_message("catégorie %d : max devrait être sans borne" % c).is_true()


func test_should_retreat_below_category_minimum() -> void:
	assert_bool(BotCombatStyle.should_retreat(CAT.SHOTGUN, 0.5)).is_false()  # pompe : jamais de recul (min = 0).
	assert_bool(BotCombatStyle.should_retreat(CAT.SMG, 4.9)).is_true()
	assert_bool(BotCombatStyle.should_retreat(CAT.SMG, 5.0)).is_false()
	assert_bool(BotCombatStyle.should_retreat(CAT.RIFLE, 9.9)).is_true()
	assert_bool(BotCombatStyle.should_retreat(CAT.RIFLE, 10.0)).is_false()
	assert_bool(BotCombatStyle.should_retreat(CAT.SNIPER, 24.9)).is_true()
	assert_bool(BotCombatStyle.should_retreat(CAT.SNIPER, 25.0)).is_false()


func test_should_advance_beyond_category_maximum() -> void:
	assert_bool(BotCombatStyle.should_advance(CAT.SHOTGUN, 6.1)).is_true()
	assert_bool(BotCombatStyle.should_advance(CAT.SHOTGUN, 6.0)).is_false()
	assert_bool(BotCombatStyle.should_advance(CAT.SMG, 15.1)).is_true()
	assert_bool(BotCombatStyle.should_advance(CAT.RIFLE, 35.1)).is_true()
	# Sniper : pas de borne haute -> jamais "trop loin", quelle que soit la distance.
	assert_bool(BotCombatStyle.should_advance(CAT.SNIPER, 1000.0)).is_false()


func test_in_preferred_band_true_only_between_retreat_and_advance() -> void:
	assert_bool(BotCombatStyle.in_preferred_band(CAT.RIFLE, 9.9)).is_false()
	assert_bool(BotCombatStyle.in_preferred_band(CAT.RIFLE, 20.0)).is_true()
	assert_bool(BotCombatStyle.in_preferred_band(CAT.RIFLE, 35.1)).is_false()
	# Pompe : bande [0, 6] -> en dessous de 6 toujours "dans la bande".
	assert_bool(BotCombatStyle.in_preferred_band(CAT.SHOTGUN, 3.0)).is_true()

# ======================================================================
#  Rafales à distance — armes automatiques au-delà de 25 m uniquement.
# ======================================================================

func test_should_burst_requires_automatic_and_beyond_range() -> void:
	assert_bool(BotCombatStyle.should_burst(true, 25.1)).is_true()
	assert_bool(BotCombatStyle.should_burst(true, 25.0)).is_false()   # "au-delà de 25 m" : strictement supérieur.
	assert_bool(BotCombatStyle.should_burst(true, 10.0)).is_false()
	assert_bool(BotCombatStyle.should_burst(false, 40.0)).is_false()  # semi-auto : jamais de rafale (un tir par appui déjà).


func test_roll_burst_shots_within_3_to_5() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260924
	for i in range(500):
		var n := BotCombatStyle.roll_burst_shots(rng)
		assert_int(n).is_greater_equal(3)
		assert_int(n).is_less_equal(5)


func test_roll_burst_pause_within_150_to_250ms() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260924
	for i in range(500):
		var p := BotCombatStyle.roll_burst_pause(rng)
		assert_float(p).is_greater_equal(0.15)
		assert_float(p).is_less_equal(0.25)


const DT := 1.0 / 60.0  ## Pas physique de référence (BotBrain._physics_process, 60 Hz).

## Simule `n` pas de `burst_step` à cadence fixe `fire_rate`, renvoie la liste
## des `can_fire` (bool) tick par tick.
func _run_burst(fire_rate: float, n: int, seed: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var state := {}
	var out: Array = []
	for i in range(n):
		state = BotCombatStyle.burst_step(state, DT, fire_rate, rng)
		out.append(bool(state.can_fire))
	return out


func test_burst_step_alternates_firing_runs_with_pauses() -> void:
	var out := _run_burst(10.0, 300, 1)  # 5 s simulées à 10 tirs/s.
	var saw_fire := false
	var saw_pause := false
	for v in out:
		if v:
			saw_fire = true
		else:
			saw_pause = true
	assert_bool(saw_fire).append_failure_message("aucun tick can_fire=true observé").is_true()
	assert_bool(saw_pause).append_failure_message("aucune pause (can_fire=false) observée").is_true()


func test_burst_step_firing_runs_last_3_to_5_shots_worth_of_time() -> void:
	# À 10 tirs/s, une rafale de shots_target tirs dure shots_target/10 s —
	# donc entre 0.3 s (3 tirs) et 0.5 s (5 tirs), à la discrétisation de 60 Hz
	# près (une marge de quelques ticks, même tolérance que test_bot_stuck.gd).
	var out := _run_burst(10.0, 600, 7)
	var runs: Array = []
	var current := 0
	for v in out:
		if v:
			current += 1
		elif current > 0:
			runs.append(current)
			current = 0
	if current > 0:
		runs.append(current)
	assert_bool(runs.is_empty()).append_failure_message("aucune rafale observée en 10 s simulées").is_false()
	for ticks in runs:
		var duration := float(ticks) * DT
		assert_float(duration).append_failure_message(
			"une rafale a duré %.3f s, attendu entre ~0.3 s (3 tirs) et ~0.5 s (5 tirs)" % duration
		).is_between(0.3 - 3.0 * DT, 0.5 + 3.0 * DT)


func test_burst_step_pauses_last_150_to_250ms() -> void:
	var out := _run_burst(10.0, 600, 7)
	var pauses: Array = []
	var current := 0
	var started := false
	for v in out:
		if not v:
			current += 1
			started = true
		elif started:
			pauses.append(current)
			current = 0
			started = false
	# Ignore une éventuelle pause finale tronquée (fin de simulation) : ne
	# garder que les pauses ENTIÈREMENT observées (suivies d'un tir).
	assert_bool(pauses.is_empty()).append_failure_message("aucune pause complète observée").is_false()
	for ticks in pauses:
		var duration := float(ticks) * DT
		assert_float(duration).append_failure_message(
			"une pause a duré %.3f s, attendu entre 0.15 s et 0.25 s" % duration
		).is_between(0.15 - 3.0 * DT, 0.25 + 3.0 * DT)


func test_burst_step_is_deterministic_for_same_seed() -> void:
	var a := _run_burst(10.0, 300, 42)
	var b := _run_burst(10.0, 300, 42)
	assert_int(a.size()).is_equal(b.size())
	for i in a.size():
		assert_bool(a[i]).append_failure_message("tick %d : divergence entre deux runs de même graine" % i).is_equal(b[i])

# ======================================================================
#  Strafe réactif — 0.25-0.6 s si pris pour cible, 0.8-1.8 s sinon.
# ======================================================================

func test_strafe_interval_targeted_within_0_25_0_6() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	for i in range(500):
		var interval := BotCombatStyle.strafe_interval(rng, true)
		assert_float(interval).is_greater_equal(BotCombatStyle.STRAFE_REACTIVE_MIN)
		assert_float(interval).is_less_equal(BotCombatStyle.STRAFE_REACTIVE_MAX)


func test_strafe_interval_idle_within_0_8_1_8() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	for i in range(500):
		var interval := BotCombatStyle.strafe_interval(rng, false)
		assert_float(interval).is_greater_equal(BotCombatStyle.STRAFE_IDLE_MIN)
		assert_float(interval).is_less_equal(BotCombatStyle.STRAFE_IDLE_MAX)


func test_strafe_interval_targeted_is_never_in_the_idle_only_range() -> void:
	# Les deux fourchettes ne se chevauchent pas (0.6 < 0.8) : un intervalle
	# "pris pour cible" ne doit donc jamais dépasser 0.6 s.
	var rng := RandomNumberGenerator.new()
	rng.seed = 123
	for i in range(200):
		assert_float(BotCombatStyle.strafe_interval(rng, true)).is_less_equal(0.6)


func test_strafe_interval_is_not_a_fixed_value() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var first := BotCombatStyle.strafe_interval(rng, true)
	var distinct := false
	for i in range(20):
		if not is_equal_approx(BotCombatStyle.strafe_interval(rng, true), first):
			distinct = true
			break
	assert_bool(distinct).append_failure_message("l'intervalle de strafe ne doit jamais être une constante").is_true()

# ======================================================================
#  Marche (walk_held) — enquête ou fin de round.
# ======================================================================

func test_should_walk_true_when_investigating() -> void:
	assert_bool(BotCombatStyle.should_walk(true, false)).is_true()


func test_should_walk_true_when_round_ending() -> void:
	assert_bool(BotCombatStyle.should_walk(false, true)).is_true()


func test_should_walk_true_when_both() -> void:
	assert_bool(BotCombatStyle.should_walk(true, true)).is_true()


func test_should_walk_false_otherwise() -> void:
	assert_bool(BotCombatStyle.should_walk(false, false)).is_false()

# ======================================================================
#  Rythme de tir semi-auto (BOT-21, A7) — un appui toutes les 0.15-0.40 s
#  sous 20 m, 0.30-0.70 s au-delà, jamais plus vite que la cadence de l'arme.
# ======================================================================

func test_semi_auto_interval_close_range_within_0_15_0_40() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260924
	for i in range(500):
		var interval := BotCombatStyle.semi_auto_interval(5.0, rng)
		assert_float(interval).is_greater_equal(BotCombatStyle.SEMI_AUTO_CLOSE_MIN)
		assert_float(interval).is_less_equal(BotCombatStyle.SEMI_AUTO_CLOSE_MAX)


func test_semi_auto_interval_far_range_within_0_30_0_70() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260924
	for i in range(500):
		var interval := BotCombatStyle.semi_auto_interval(45.0, rng)
		assert_float(interval).is_greater_equal(BotCombatStyle.SEMI_AUTO_FAR_MIN)
		assert_float(interval).is_less_equal(BotCombatStyle.SEMI_AUTO_FAR_MAX)


func test_semi_auto_interval_at_20m_uses_far_bucket() -> void:
	# "sous 20 m" : distance strictement inférieure au seuil -> à 20 m pile,
	# c'est déjà la fourchette "au-delà" (jamais sous son minimum de 0.30 s).
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	for i in range(500):
		assert_float(BotCombatStyle.semi_auto_interval(20.0, rng)).is_greater_equal(BotCombatStyle.SEMI_AUTO_FAR_MIN)


func test_semi_auto_interval_just_under_20m_uses_close_bucket() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var saw_below_far_min := false
	for i in range(500):
		var interval := BotCombatStyle.semi_auto_interval(19.99, rng)
		assert_float(interval).is_less_equal(BotCombatStyle.SEMI_AUTO_CLOSE_MAX)
		if interval < BotCombatStyle.SEMI_AUTO_FAR_MIN:
			saw_below_far_min = true
	assert_bool(saw_below_far_min).append_failure_message(
		"19.99 m devrait utiliser la fourchette rapprochée (0.15-0.40 s), jamais seulement 0.30-0.40 s"
	).is_true()


func test_semi_auto_interval_never_faster_than_weapon_fire_rate() -> void:
	# Cadence lente (2 tirs/s -> 0.5 s/tir) : le plafond dépasse tout le
	# tirage rapproché (0.15-0.40 s), donc systématiquement relevé à 0.5 s.
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	for i in range(300):
		assert_float(BotCombatStyle.semi_auto_interval(5.0, rng, 2.0)).is_equal_approx(0.5, 0.0001)


func test_semi_auto_interval_fast_weapon_does_not_floor_the_draw() -> void:
	# Cadence rapide (100 tirs/s -> 0.01 s/tir) : bien en dessous du tirage,
	# le plafond n'a alors aucun effet observable.
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	for i in range(300):
		var interval := BotCombatStyle.semi_auto_interval(5.0, rng, 100.0)
		assert_float(interval).is_greater_equal(BotCombatStyle.SEMI_AUTO_CLOSE_MIN)
		assert_float(interval).is_less_equal(BotCombatStyle.SEMI_AUTO_CLOSE_MAX)


func test_semi_auto_interval_zero_fire_rate_means_no_floor() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	for i in range(300):
		var interval := BotCombatStyle.semi_auto_interval(5.0, rng, 0.0)
		assert_float(interval).is_greater_equal(BotCombatStyle.SEMI_AUTO_CLOSE_MIN)
		assert_float(interval).is_less_equal(BotCombatStyle.SEMI_AUTO_CLOSE_MAX)


func test_semi_auto_interval_is_not_a_fixed_value() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var first := BotCombatStyle.semi_auto_interval(5.0, rng)
	var distinct := false
	for i in range(20):
		if not is_equal_approx(BotCombatStyle.semi_auto_interval(5.0, rng), first):
			distinct = true
			break
	assert_bool(distinct).append_failure_message("l'intervalle semi-auto ne doit jamais être une constante").is_true()

# ======================================================================
#  ADS avec hystérésis (BOT-21, A8) — maintenu 0.5-0.9 s après la dernière
#  vue, au plus 1 bascule par 1.5 s.
# ======================================================================

## Simule `n` pas de `ads_hold` à cadence fixe (60 Hz), `wants_ads` alternant
## par blocs de 20 ticks (~0.33 s vu / ~0.33 s perdu) — renvoie la liste des
## `held` (bool) tick par tick.
func _run_ads_hold(seed: int, n: int = 300) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var state := {}
	var out: Array = []
	for i in range(n):
		var wants := (i % 40) < 20
		state = BotCombatStyle.ads_hold(state, DT, wants, rng)
		out.append(bool(state.held))
	return out


func test_ads_hold_activates_immediately_from_fresh_state() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 55
	var state := BotCombatStyle.ads_hold({}, DT, true, rng)
	assert_bool(bool(state.held)).is_true()


func test_ads_hold_stays_off_when_never_wanted() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 55
	var state := {}
	for i in range(120):
		state = BotCombatStyle.ads_hold(state, DT, false, rng)
	assert_bool(bool(state.held)).is_false()


func test_ads_hold_releases_0_5_to_0_9s_after_last_seen() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 314
	var state := {}
	# Engagement soutenu (bien plus long que 1.5 s) pour que la bascule ON
	# soit largement retombée avant qu'on cesse de vouloir l'ADS — sinon la
	# garantie "au plus 1 bascule par 1.5 s" retarderait aussi l'extinction.
	for i in range(int(3.0 / DT)):
		state = BotCombatStyle.ads_hold(state, DT, true, rng)
	assert_bool(bool(state.held)).append_failure_message("l'ADS devrait être actif après un engagement soutenu").is_true()

	var ticks_to_release := 0
	var giveup := int(2.0 / DT)
	while bool(state.held) and ticks_to_release <= giveup:
		state = BotCombatStyle.ads_hold(state, DT, false, rng)
		ticks_to_release += 1
	var duration := float(ticks_to_release) * DT
	assert_float(duration).append_failure_message(
		"l'ADS s'est éteint après %.3f s, attendu entre 0.5 et 0.9 s" % duration
	).is_between(0.5 - 3.0 * DT, 0.9 + 3.0 * DT)


func test_ads_hold_off_toggle_blocked_within_1_5s_of_activation() -> void:
	# Une seule frame "vue" (hold_left tiré <= 0.9 s), puis plus jamais : sans
	# le garde-fou de bascule, l'extinction arriverait avant 0.9 s. Avec lui,
	# elle ne peut pas intervenir avant 1.5 s depuis l'activation (A8 : "au
	# plus 1 bascule par 1,5 s").
	var rng := RandomNumberGenerator.new()
	rng.seed = 8
	var state := BotCombatStyle.ads_hold({}, DT, true, rng)
	assert_bool(bool(state.held)).is_true()
	for i in range(int(1.4 / DT)):
		state = BotCombatStyle.ads_hold(state, DT, false, rng)
		assert_bool(bool(state.held)).append_failure_message(
			"l'ADS s'est éteint avant 1.5 s depuis son activation (bascule trop rapide)"
		).is_true()


func test_ads_hold_never_toggles_more_than_once_per_1_5_seconds() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	var state := {}
	var prev_held := false
	var since_last_toggle := 0.0
	var first := true
	for i in range(int(10.0 / DT)):
		var wants := (i % 2) == 0  # signal bruité qui alterne à chaque tick.
		state = BotCombatStyle.ads_hold(state, DT, wants, rng)
		var held := bool(state.held)
		since_last_toggle += DT
		if not first and held != prev_held:
			assert_float(since_last_toggle).append_failure_message(
				"bascule ADS après seulement %.3f s (attendu >= 1.5 s)" % since_last_toggle
			).is_greater_equal(1.5 - 2.0 * DT)
			since_last_toggle = 0.0
		prev_held = held
		first = false


func test_ads_hold_hold_window_is_not_fixed() -> void:
	var release_ticks: Array = []
	for seed in [1, 2, 3, 4, 5]:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed
		var state := {}
		for i in range(int(3.0 / DT)):
			state = BotCombatStyle.ads_hold(state, DT, true, rng)
		var ticks_to_release := 0
		var giveup := int(2.0 / DT)
		while bool(state.held) and ticks_to_release <= giveup:
			state = BotCombatStyle.ads_hold(state, DT, false, rng)
			ticks_to_release += 1
		release_ticks.append(ticks_to_release)
	var distinct := false
	for i in range(1, release_ticks.size()):
		if release_ticks[i] != release_ticks[0]:
			distinct = true
			break
	assert_bool(distinct).append_failure_message("la durée de maintien ADS ne doit jamais être fixe").is_true()


func test_ads_hold_is_deterministic_for_same_seed() -> void:
	var a := _run_ads_hold(42)
	var b := _run_ads_hold(42)
	assert_int(a.size()).is_equal(b.size())
	for i in a.size():
		assert_bool(a[i]).append_failure_message("tick %d : divergence entre deux runs de même graine" % i).is_equal(b[i])
