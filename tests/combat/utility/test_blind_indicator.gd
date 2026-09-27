## test_blind_indicator.gd
## Spec (contrat lead 2026-09-27, point 4 "visual tell on a flashed player") :
## - un nouveau blind sur une cible déjà indiquée ÉTEND le minuteur (jamais un
##   remplacement qui raccourcirait, jamais un empilement) ;
## - expiration dès que le temps restant tombe à 0 ;
## - pop-in sur 0.1 s, pop-out sur les 0.2 dernières secondes, quelle que soit
##   la durée totale (une extension ne rejoue jamais le pop-in).
## Logique PURE uniquement (voir la docstring de classe de BlindIndicator.gd) :
## aucun nœud/scène nécessaire.
extends GdUnitTestSuite

const _BI := preload("res://scripts/combat/utility/vfx/BlindIndicator.gd")


# ---------------------------------------------------------------- extend/expiry

func test_extend_replaces_with_the_longer_duration() -> void:
	assert_float(_BI.extended_remaining(0.5, 2.0)).is_equal_approx(2.0, 0.001)


func test_extend_never_shortens_a_longer_remaining() -> void:
	assert_float(_BI.extended_remaining(2.0, 0.5)).append_failure_message(
		"une nouvelle flash plus courte ne doit jamais RACCOURCIR le minuteur en cours"
	).is_equal_approx(2.0, 0.001)


func test_is_expired_at_zero_or_below() -> void:
	assert_bool(_BI.is_expired(0.0)).is_true()
	assert_bool(_BI.is_expired(-0.1)).is_true()
	assert_bool(_BI.is_expired(0.01)).is_false()


# ---------------------------------------------------------------- pop-in/out curve

func test_pop_in_starts_at_zero() -> void:
	assert_float(_BI.pop_in_progress(0.0)).is_equal_approx(0.0, 0.001)


func test_pop_in_reaches_one_at_the_threshold() -> void:
	assert_float(_BI.pop_in_progress(_BI.POP_IN_S)).is_equal_approx(1.0, 0.001)


func test_pop_in_stays_at_one_past_the_threshold() -> void:
	assert_float(_BI.pop_in_progress(10.0)).is_equal_approx(1.0, 0.001)


func test_pop_in_midpoint_matches_smoothstep() -> void:
	# smoothstep(0.5) == 0.5 exactement (fonction symétrique).
	assert_float(_BI.pop_in_progress(_BI.POP_IN_S * 0.5)).is_equal_approx(0.5, 0.001)


func test_pop_out_is_one_while_far_from_expiry() -> void:
	assert_float(_BI.pop_out_progress(5.0)).is_equal_approx(1.0, 0.001)


func test_pop_out_reaches_zero_at_expiry() -> void:
	assert_float(_BI.pop_out_progress(0.0)).is_equal_approx(0.0, 0.001)


func test_pop_out_midpoint_matches_smoothstep() -> void:
	assert_float(_BI.pop_out_progress(_BI.POP_OUT_S * 0.5)).is_equal_approx(0.5, 0.001)


func test_scale_factor_is_limited_by_pop_in_at_the_very_start() -> void:
	# Juste créé (elapsed=0) mais avec plein de temps restant : le pop-in DOIT dominer.
	assert_float(_BI.scale_factor(0.0, 5.0)).is_equal_approx(0.0, 0.001)


func test_scale_factor_is_limited_by_pop_out_near_expiry() -> void:
	# Bien après le pop-in, mais presque expiré : le pop-out DOIT dominer.
	assert_float(_BI.scale_factor(5.0, 0.0)).is_equal_approx(0.0, 0.001)


func test_scale_factor_is_full_scale_in_the_steady_hold() -> void:
	assert_float(_BI.scale_factor(1.0, 1.0)).is_equal_approx(1.0, 0.001)


func test_an_extension_restores_full_scale_without_replaying_pop_in() -> void:
	# Une cible dont le minuteur a été étendu longtemps après la création
	# (elapsed grand) doit repasser à l'échelle PLEINE dès que `remaining`
	# redevient grand — jamais un second pop-in depuis 0 (`elapsed` ne bouge
	# jamais en arrière).
	var extended := _BI.extended_remaining(0.05, 3.0)
	assert_float(_BI.scale_factor(4.0, extended)).is_equal_approx(1.0, 0.001)


# ---------------------------------------------------------------- orbit

func test_orbit_offset_horizontal_radius_matches_configured_radius() -> void:
	# Bob nul à cet instant précis (evite le terme sin(bob) qui ne touche que Y) :
	# on vérifie seulement la composante horizontale (X/Z), qui ne dépend pas du bob.
	var offset := _BI.orbit_offset(0.0, 0, 3, 0.35, 1.2, 0.0, 0.6)
	var horiz := Vector2(offset.x, offset.z)
	assert_float(horiz.length()).is_equal_approx(0.35, 0.001)


func test_orbit_offset_spaces_three_stars_evenly() -> void:
	var a := _BI.orbit_offset(0.0, 0, 3, 0.35, 0.0, 0.0, 0.6)
	var b := _BI.orbit_offset(0.0, 1, 3, 0.35, 0.0, 0.0, 0.6)
	var c := _BI.orbit_offset(0.0, 2, 3, 0.35, 0.0, 0.0, 0.6)
	# Turns_per_sec=0 : seul l'écart de PHASE entre étoiles reste (120° chacune) —
	# trois points distincts sur le même cercle.
	assert_bool(a.distance_to(b) > 0.01).is_true()
	assert_bool(b.distance_to(c) > 0.01).is_true()
	assert_bool(a.distance_to(c) > 0.01).is_true()


func test_orbit_offset_bob_moves_only_vertically() -> void:
	var no_bob := _BI.orbit_offset(0.0, 0, 3, 0.35, 0.0, 0.05, 0.6)
	var quarter_period := _BI.orbit_offset(0.15, 0, 3, 0.35, 0.0, 0.05, 0.6)
	assert_float(no_bob.x).is_equal_approx(quarter_period.x, 0.001)
	assert_float(no_bob.z).is_equal_approx(quarter_period.z, 0.001)


## Revue lead 2026-09-27 : lisibles de loin -> taille réelle de près, grossies
## avec la distance, plafonnées.
func test_distance_scale_is_one_up_close_and_grows_then_caps() -> void:
	assert_float(_BI.distance_scale(2.0)).is_equal_approx(1.0, 0.001)
	assert_float(_BI.distance_scale(_BI.DIST_SCALE_REF_M)).is_equal_approx(1.0, 0.001)
	assert_float(_BI.distance_scale(12.0)).is_equal_approx(2.0, 0.001)
	assert_float(_BI.distance_scale(100.0)).is_equal_approx(_BI.DIST_SCALE_MAX, 0.001)
