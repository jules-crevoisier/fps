## test_weapon_foley.gd
## Spec (tâche "son", 2026-09-27, point 4 "foley revolver") : table PURE
## temps -> son pour le rechargement/l'inspection du revolver et le
## rechargement du Ravage, portée depuis les fractions [0,1] déjà normalisées
## de art/characters/frog_cowboy/anim/pistol.py (RELOAD_T/INSPECT_T) et
## art/characters/frog_cowboy/anim/rifle.py (build_reload) — voir les
## constantes de WeaponFoley.gd, qui pointent vers ces sources. Chaque
## fraction est multipliée par la durée RÉELLE (`WeaponConfig.reload_time`),
## jamais la durée fixe de l'animation authored (2.4/2.5 s), pour rester
## correcte si une arme future a un temps de rechargement différent.
extends GdUnitTestSuite


func test_revolver_reload_events_are_five_in_authored_order() -> void:
	var events: Array = WeaponFoley.revolver_reload_events(2.4)
	assert_int(events.size()).is_equal(5)
	var names: Array = []
	for e in events:
		names.append(e["sound"])
	assert_array(names).is_equal(["rev_crane_open", "rev_eject", "rev_load", "rev_crane_close", "rev_spin"])


func test_revolver_reload_events_scale_with_reload_time() -> void:
	var events: Array = WeaponFoley.revolver_reload_events(2.4)
	# open0 = 0.09 (pistol.py RELOAD_T) * 2.4 s.
	assert_float(events[0]["time"]).is_equal_approx(0.216, 0.005)
	# spin1 = 0.95 * 2.4 s.
	assert_float(events[4]["time"]).is_equal_approx(2.28, 0.005)


func test_revolver_reload_events_scale_proportionally_for_a_different_duration() -> void:
	var fast: Array = WeaponFoley.revolver_reload_events(1.2)
	# Deux fois plus vite -> chaque instant est deux fois plus tôt.
	assert_float(fast[0]["time"]).is_equal_approx(0.108, 0.005)
	assert_float(fast[4]["time"]).is_equal_approx(1.14, 0.005)


func test_revolver_reload_events_are_sorted_by_time() -> void:
	var events: Array = WeaponFoley.revolver_reload_events(2.4)
	for i in range(1, events.size()):
		assert_float(events[i]["time"]).is_greater(events[i - 1]["time"])


func test_revolver_inspect_events_are_three_in_authored_order() -> void:
	var events: Array = WeaponFoley.revolver_inspect_events(2.5)
	assert_int(events.size()).is_equal(3)
	var names: Array = []
	for e in events:
		names.append(e["sound"])
	assert_array(names).is_equal(["rev_crane_open", "rev_spin", "rev_crane_close"])


func test_revolver_inspect_events_scale_with_inspect_time() -> void:
	var events: Array = WeaponFoley.revolver_inspect_events(2.5)
	# open0 = 0.47 * 2.5 s.
	assert_float(events[0]["time"]).is_equal_approx(1.175, 0.005)
	# close1 = 0.90 * 2.5 s.
	assert_float(events[2]["time"]).is_equal_approx(2.25, 0.005)


func test_rifle_reload_events_are_reload_out_then_reload_in() -> void:
	var events: Array = WeaponFoley.rifle_reload_events(2.5)
	assert_int(events.size()).is_equal(2)
	assert_str(events[0]["sound"]).is_equal("reload_out")
	assert_str(events[1]["sound"]).is_equal("reload_in")
	assert_float(events[0]["time"]).is_less(events[1]["time"])


func test_rifle_reload_events_scale_with_reload_time() -> void:
	var events: Array = WeaponFoley.rifle_reload_events(1.8)
	# Fraction 0.20 (mag qui quitte l'arme, rifle.py build_reload) * 1.8 s.
	assert_float(events[0]["time"]).is_equal_approx(0.36, 0.01)
	# Fraction 0.90 (mag rentré, rifle.py build_reload) * 1.8 s.
	assert_float(events[1]["time"]).is_equal_approx(1.62, 0.01)


func test_events_never_reach_or_exceed_the_full_duration() -> void:
	for events in [WeaponFoley.revolver_reload_events(2.4), WeaponFoley.revolver_inspect_events(2.5), WeaponFoley.rifle_reload_events(2.5)]:
		for e in events:
			assert_float(e["time"]).is_less(2.5)
			assert_float(e["time"]).is_greater(0.0)
