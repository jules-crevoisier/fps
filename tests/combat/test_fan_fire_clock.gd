## test_fan_fire_clock.gd
## Spec (design verrouillé utilisateur, tâche "revolver", révisé 2026-09-27
## après playtest — pivot "Valorant Classic") :
## - LMB (tap_trigger) = tir précis, au plus tap_rate tirs/s. Le maintenir NE
##   fanne PLUS ("Holding LMB does NOT fan anymore; it fires nothing more
##   until release").
## - RMB (fan_trigger) TENU = "fan the hammer" à fan_rate tirs/s, premier tir
##   immédiat.
## - Un tir de L'UN des deux déclencheurs retarde le PROCHAIN tir de L'AUTRE
##   (cadence partagée) — jamais de double-tir en alternant LMB/RMB.
## Voir scripts/combat/FanFireClock.gd.
extends GdUnitTestSuite

## preload() : le script est tout neuf, le cache global de classes n'est pas
## régénéré en tête (voir la note du contrat de tâche) -- `FanFireClock.new(...)`
## resterait "type introuvable" sans ça.
const FanFireClock := preload("res://scripts/combat/FanFireClock.gd")

const DT := 1.0 / 60.0


func _hold_fan_for_seconds(c: FanFireClock, seconds: float) -> int:
	var total := 0
	var ticks := int(round(seconds / DT))
	for i in ticks:
		var shots: Dictionary = c.tick(DT, false, true)
		total += int(shots["fan"])
		assert_int(shots["tap"]).append_failure_message(
			"tenir RMB seul ne doit jamais produire de tir TAP"
		).is_equal(0)
	return total


# ======================================================================
#  LMB (tap_trigger) — précis, jamais fan, même tenu.
# ======================================================================

func test_lmb_tap_fires_immediately_on_first_press() -> void:
	var c := FanFireClock.new(3.0, 7.5)
	var shots := c.tick(DT, true, false)
	assert_int(shots["tap"]).is_equal(1)
	assert_int(shots["fan"]).is_equal(0)


func test_holding_lmb_continuously_never_escalates_to_fan_fire() -> void:
	# Contrat : "Holding LMB does NOT fan anymore; it fires nothing more
	# until release" -- tenir LMB en continu doit rester borné à tap_rate
	# (3/s), jamais 7.5/s, et JAMAIS un seul tir marqué "fan".
	var c := FanFireClock.new(3.0, 7.5)
	var total_tap := 0
	var total_fan := 0
	for i in 60:
		var shots: Dictionary = c.tick(DT, true, false)
		total_tap += int(shots["tap"])
		total_fan += int(shots["fan"])
	assert_int(total_fan).append_failure_message(
		"maintenir LMB ne doit JAMAIS produire de tir fan"
	).is_equal(0)
	assert_int(total_tap).append_failure_message(
		"maintenir LMB doit rester à la cadence tap (~3/s), jamais 7.5/s"
	).is_between(2, 4)


func test_releasing_and_pressing_lmb_again_stays_capped_at_the_tap_rate() -> void:
	# Tape-relâche-tape en boucle plus vite que l'intervalle tap (1/3 s) :
	# jamais plus de tap_rate tirs/s, quel que soit le rythme de clic (même
	# garantie que FireClock.tick seul).
	var c := FanFireClock.new(3.0, 7.5)
	var total := 0
	var held := false
	for i in 60:
		held = not held  # alterne appui/relâchement à 30 Hz : plus vite que 3/s.
		var shots: Dictionary = c.tick(DT, held, false)
		total += int(shots["tap"])
		assert_int(shots["fan"]).is_equal(0)
	assert_int(total).append_failure_message(
		"tapoter plus vite que tap_rate ne doit jamais dépasser %d tirs/s (obtenu %d)" % [3, total]
	).is_less_equal(4)  # tolérance d'1 tir (marge de phase), jamais 30.


# ======================================================================
#  RMB (fan_trigger) — fan the hammer, premier tir immédiat, puis 7.5/s.
# ======================================================================

func test_rmb_fan_fires_immediately_on_first_hold() -> void:
	var c := FanFireClock.new(3.0, 7.5)
	var shots := c.tick(DT, false, true)
	assert_int(shots["fan"]).is_equal(1)
	assert_int(shots["tap"]).is_equal(0)


func test_holding_rmb_sustains_the_fan_rate() -> void:
	var c := FanFireClock.new(3.0, 7.5)
	var total := _hold_fan_for_seconds(c, 1.0)
	assert_int(total).append_failure_message(
		"tenir RMB doit sustenter ~7,5 tirs fan/s, obtenu %d" % total
	).is_between(7, 8)


func test_releasing_rmb_and_holding_again_still_fires_immediately() -> void:
	var c := FanFireClock.new(3.0, 7.5)
	assert_int((c.tick(DT, false, true) as Dictionary)["fan"]).is_equal(1)
	for i in 30:
		c.tick(DT, false, false)  # relâché largement plus d'un intervalle fan.
	var shots := c.tick(DT, false, true)
	assert_int(shots["fan"]).append_failure_message(
		"représer RMB après un relâchement complet doit refanner immédiatement"
	).is_equal(1)


# ======================================================================
#  Cadence PARTAGÉE — un tir de l'un retarde le prochain de l'autre.
# ======================================================================

func test_a_tap_shot_delays_the_next_fan_shot() -> void:
	var c := FanFireClock.new(3.0, 7.5)
	assert_int((c.tick(DT, true, false) as Dictionary)["tap"]).is_equal(1)  # LMB tire.
	# RMB pressé au tick SUIVANT (immédiatement après le tap) : ne doit PAS
	# fanner tout de suite (le tap vient de consommer la fenêtre partagée).
	var shots := c.tick(DT, false, true)
	assert_int(shots["fan"]).append_failure_message(
		"un tir fan ne doit pas partir au tick physique suivant immédiatement après un tap"
	).is_equal(0)


func test_a_fan_shot_delays_the_next_tap_shot() -> void:
	var c := FanFireClock.new(3.0, 7.5)
	assert_int((c.tick(DT, false, true) as Dictionary)["fan"]).is_equal(1)  # RMB tire.
	var shots := c.tick(DT, true, false)
	assert_int(shots["tap"]).append_failure_message(
		"un tir tap ne doit pas partir au tick physique suivant immédiatement après un fan"
	).is_equal(0)


func test_alternating_lmb_and_rmb_never_exceeds_the_faster_rate() -> void:
	# Alterne LMB/RMB à 30 Hz pendant 1 s entière : la cadence PARTAGÉE doit
	# borner le total, jamais la somme des deux cadences (3 + 7.5 = 10.5/s).
	var c := FanFireClock.new(3.0, 7.5)
	var total := 0
	var use_fan := false
	for i in 60:
		use_fan = not use_fan
		var shots: Dictionary = c.tick(DT, not use_fan, use_fan)
		total += int(shots["tap"]) + int(shots["fan"])
	assert_int(total).append_failure_message(
		"alterner LMB/RMB ne doit jamais dépasser la cadence fan (7.5/s), obtenu %d/s" % total
	).is_less_equal(9)


# ======================================================================
#  fan_rate <= 0 désactive le mode fan (contrat : "0 = no fan mode, so the
#  Ravage is unchanged").
# ======================================================================

func test_fan_fire_rate_zero_ignores_the_fan_trigger_entirely() -> void:
	var c := FanFireClock.new(10.0, 0.0)
	var total_fan := 0
	for i in 60:
		var shots: Dictionary = c.tick(DT, false, true)
		total_fan += int(shots["fan"])
	assert_int(total_fan).append_failure_message(
		"fan_fire_rate <= 0 ne doit jamais produire de tir fan (contrat : Ravage inchangé)"
	).is_equal(0)


func test_reset_makes_both_triggers_fire_immediately_again() -> void:
	var c := FanFireClock.new(3.0, 7.5)
	assert_int((c.tick(DT, true, false) as Dictionary)["tap"]).is_equal(1)
	c.reset()
	var shots := c.tick(DT, true, false)
	assert_int(shots["tap"]).append_failure_message(
		"après reset(), le prochain tap doit repartir immédiat (comme FireClock.reset())"
	).is_equal(1)
