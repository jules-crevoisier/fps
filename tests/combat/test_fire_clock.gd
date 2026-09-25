## test_fire_clock.gd
## Spec (contract-p0.md, FireClock): fractional-remainder shot gate ticked at a
## fixed 60 Hz physics rate. First shot after idle fires immediately; while the
## trigger is held the accumulated shots over 1 s match the configured rate
## within +/-1 shot; releasing the trigger must not bank shots for later.
extends GdUnitTestSuite

const DT := 1.0 / 60.0


func _hold_for_one_second(fc: FireClock) -> int:
	var shots := 0
	for i in range(60):
		shots += fc.tick(DT, true)
	return shots


func test_first_shot_after_idle_fires_immediately() -> void:
	var fc := FireClock.new(10.0)
	assert_int(fc.tick(DT, true)).is_equal(1)


func test_rate_10_per_second_at_60hz_matches_within_one_shot() -> void:
	var fc := FireClock.new(10.0)
	var shots := _hold_for_one_second(fc)
	assert_int(shots).is_between(9, 11)


func test_rate_13_33_per_second_at_60hz_matches_within_one_shot() -> void:
	var fc := FireClock.new(13.33)
	var shots := _hold_for_one_second(fc)
	assert_int(shots).is_between(13, 14)


func test_rate_1_2_per_second_at_60hz_matches_within_one_shot() -> void:
	var fc := FireClock.new(1.2)
	var shots := _hold_for_one_second(fc)
	assert_int(shots).is_between(1, 2)


func test_releasing_trigger_does_not_bank_shots() -> void:
	var fc := FireClock.new(10.0)
	# idle for 2 full seconds with the trigger released
	for i in range(120):
		assert_int(fc.tick(DT, false)).is_equal(0)
	# pulling the trigger now must yield exactly the immediate first shot,
	# not several shots "banked" from the idle time
	assert_int(fc.tick(DT, true)).is_equal(1)
	assert_int(fc.tick(DT, true)).is_equal(0)


func test_reset_makes_the_next_shot_immediate_again() -> void:
	var fc := FireClock.new(10.0)
	assert_int(fc.tick(DT, true)).is_equal(1)
	# mid-interval, no new shot yet
	assert_int(fc.tick(DT, true)).is_equal(0)

	fc.reset()
	assert_int(fc.tick(DT, true)).is_equal(1)


func test_set_rate_changes_subsequent_shot_rate() -> void:
	var fc := FireClock.new(1.0)
	fc.tick(DT, true)  # consume the immediate first shot at the old rate
	fc.set_rate(60.0)
	var shots := _hold_for_one_second(fc)
	assert_int(shots).is_between(59, 61)


# ==========================================================================
# GF-12 — buffer d'entrée semi-auto (docs/research/01_game_feel.md #13) :
# un fire_pressed reçu pendant le cooldown n'est plus perdu, il est mémorisé
# 120 ms (FireClock.INPUT_BUFFER_S) et déclenche le tir dès que l'intervalle
# est écoulé, même si la gâchette a été relâchée entre-temps.
# ==========================================================================

func test_click_at_90_percent_of_interval_fires_exactly_at_100_percent() -> void:
	var fc := FireClock.new(10.0)  # interval = 0.1 s
	assert_int(fc.tick(0.0, true)).is_equal(1)  # tir immédiat, l'horloge repart pile à 0
	# 90 % de l'intervalle s'écoulent, gâchette relâchée entre-temps
	assert_int(fc.tick(0.1 * 0.9, false)).is_equal(0)
	# clic MÉMORISÉ : le cooldown n'est pas terminé (10 % restants), pas de tir cette frame
	assert_int(fc.tick(0.0, true)).is_equal(0)
	# gâchette relâchée à nouveau : le tir mémorisé part PILE quand l'intervalle est atteint
	assert_int(fc.tick(0.1 * 0.1, false)).is_equal(1)
	# consommé : pas de second tir supplémentaire juste derrière (pas de rafale)
	assert_int(fc.tick(0.1, false)).is_equal(0)


func test_never_more_than_one_buffered_shot_even_with_several_clicks() -> void:
	var fc := FireClock.new(10.0)  # interval = 0.1 s
	assert_int(fc.tick(0.0, true)).is_equal(1)  # tir immédiat, horloge à 0
	# deux clics successifs pendant le MÊME cooldown (jamais prêt entre les deux)
	assert_int(fc.tick(0.03, true)).is_equal(0)
	assert_int(fc.tick(0.03, true)).is_equal(0)
	# l'intervalle se termine : UN SEUL tir part, jamais deux (un par clic bufferisé)
	assert_int(fc.tick(0.04, false)).is_equal(1)
	assert_int(fc.tick(0.1, false)).is_equal(0)  # pas de rafale de rattrapage derrière


func test_buffered_click_expires_after_120ms_without_ever_firing() -> void:
	var fc := FireClock.new(1.2)  # interval ~ 0.833 s (cooldown bien plus long que 120 ms)
	var interval := 1.0 / 1.2
	assert_int(fc.tick(0.0, true)).is_equal(1)  # tir immédiat, horloge à 0
	assert_int(fc.tick(0.0, true)).is_equal(0)  # clic mémorisé (cooldown loin d'être fini)
	# 130 ms s'écoulent SANS nouvelle pression : la fenêtre de 120 ms expire
	assert_int(fc.tick(0.13, false)).is_equal(0)
	# bien plus tard, l'intervalle finit par être atteint : le clic expiré NE tire PAS
	assert_int(fc.tick(interval - 0.13, false)).is_equal(0)


func test_reset_forgets_any_buffered_click() -> void:
	var fc := FireClock.new(10.0)  # interval = 0.1 s
	assert_int(fc.tick(0.0, true)).is_equal(1)  # tir immédiat, horloge à 0
	assert_int(fc.tick(0.05, true)).is_equal(0)  # clic mémorisé à mi-cooldown
	fc.reset()  # ex. changement d'arme : oublie le clic mémorisé
	# l'ancien cooldown aurait dû se terminer ici ; reset() l'a annulé, rien ne tire
	assert_int(fc.tick(0.05, false)).is_equal(0)
	# l'horloge est bien repassée "prête" : le prochain tir est immédiat
	assert_int(fc.tick(0.0, true)).is_equal(1)


# ==========================================================================
# GF-12 — clic à vide (docs/research/01_game_feel.md #14), Audio.should_play_dry_fire :
# fonction pure, testée directement sans passer par l'autoload Sfx.
# ==========================================================================

func test_dry_fire_plays_on_trigger_edge_with_empty_mag_and_reserve() -> void:
	assert_bool(Audio.should_play_dry_fire(true, 0, 0)).is_true()


func test_dry_fire_does_not_play_without_a_trigger_edge() -> void:
	# gâchette tenue en continu (pas un nouvel appui) : pas de second clic à vide.
	assert_bool(Audio.should_play_dry_fire(false, 0, 0)).is_false()


func test_dry_fire_does_not_play_when_reserve_ammo_remains() -> void:
	# de la réserve : Weapon recharge à la place, jamais de clic à vide.
	assert_bool(Audio.should_play_dry_fire(true, 0, 12)).is_false()


func test_dry_fire_does_not_play_when_the_magazine_still_has_rounds() -> void:
	assert_bool(Audio.should_play_dry_fire(true, 5, 0)).is_false()
