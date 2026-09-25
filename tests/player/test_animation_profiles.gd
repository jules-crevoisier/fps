## test_animation_profiles.gd
## Spec (ART-15, docs/STYLE_BIBLE.md §4.6/§4.8/§12) : couche additive
## d'animation par agent — logique PURE de CharacterAnimator (aucun
## AnimationTree/arbre de scène requis, même esprit que
## tests/player/test_character_animator.gd) :
##   - standing_eye_height_m / standing_chin_height_m : les repères debout
##     (yeux 1,62 m, menton 1,49 m) une fois l'inclinaison ET le rebond du
##     profil appliqués (pire cas) ;
##   - profile_respects_hitbox_floor : garde-fou du §4.6 (yeux ≥ 1,56 m,
##     menton ≥ 1,43 m debout, inclinaison ≤ 8°) ;
##   - body_squash_scale : squash cosmétique du CORPS à l'atterrissage (§12
##     ART-15), 0,97 à 1,03, jamais plus de 80 ms ;
## et une régression sur les 6 profils LIVRÉS (resources/agents/anim/*.tres,
## un par agent de AgentDatabase.all()) : chacun se charge, reste dans les
## bornes du §4.6 et a un idle_style distinct des cinq autres (§4.4, "idle
## unique").
extends GdUnitTestSuite


# ============================================================================
# standing_eye_height_m
# ============================================================================

func test_standing_eye_height_neutral_profile_matches_the_base_constant() -> void:
	var profile := AgentAnimProfile.new()
	assert_float(CharacterAnimator.standing_eye_height_m(profile)) \
		.is_equal_approx(CharacterAnimator.STANDING_EYE_HEIGHT_M, 0.0001)


func test_standing_eye_height_decreases_with_torso_tilt() -> void:
	var profile := AgentAnimProfile.new()
	profile.torso_tilt_deg = CharacterAnimator.MAX_TORSO_TILT_DEG
	var expected := CharacterAnimator.STANDING_EYE_HEIGHT_M * cos(deg_to_rad(CharacterAnimator.MAX_TORSO_TILT_DEG))
	assert_float(CharacterAnimator.standing_eye_height_m(profile)).append_failure_message(
		"buste penché au maximum (%.0f°) : les yeux doivent baisser à h·cos(θ)" % CharacterAnimator.MAX_TORSO_TILT_DEG
	).is_equal_approx(expected, 0.0001)


func test_standing_eye_height_subtracts_the_bounce_amplitude() -> void:
	var profile := AgentAnimProfile.new()
	profile.bounce_amplitude_m = 0.05
	assert_float(CharacterAnimator.standing_eye_height_m(profile)).append_failure_message(
		"le pire cas du rebond (bas du cycle) doit être soustrait de la ligne des yeux"
	).is_equal_approx(CharacterAnimator.STANDING_EYE_HEIGHT_M - 0.05, 0.0001)


## Un profil malformé (inclinaison hors [0, 8°]) ne peut jamais faire sortir
## le calcul de la plage garde-fou : `standing_eye_height_m` clampe en interne
## avant de calculer (même repli défensif que `effective_cadence_scale`).
func test_standing_eye_height_clamps_torso_tilt_beyond_the_max() -> void:
	var profile := AgentAnimProfile.new()
	profile.torso_tilt_deg = CharacterAnimator.MAX_TORSO_TILT_DEG + 50.0
	var expected := CharacterAnimator.STANDING_EYE_HEIGHT_M * cos(deg_to_rad(CharacterAnimator.MAX_TORSO_TILT_DEG))
	assert_float(CharacterAnimator.standing_eye_height_m(profile)).append_failure_message(
		"une inclinaison hors bornes doit être clampée à MAX_TORSO_TILT_DEG avant le calcul géométrique"
	).is_equal_approx(expected, 0.0001)


# ============================================================================
# standing_chin_height_m
# ============================================================================

func test_standing_chin_height_neutral_profile_matches_the_base_constant() -> void:
	var profile := AgentAnimProfile.new()
	assert_float(CharacterAnimator.standing_chin_height_m(profile)) \
		.is_equal_approx(CharacterAnimator.STANDING_CHIN_HEIGHT_M, 0.0001)


func test_standing_chin_height_decreases_with_torso_tilt() -> void:
	var profile := AgentAnimProfile.new()
	profile.torso_tilt_deg = CharacterAnimator.MAX_TORSO_TILT_DEG
	var expected := CharacterAnimator.STANDING_CHIN_HEIGHT_M * cos(deg_to_rad(CharacterAnimator.MAX_TORSO_TILT_DEG))
	assert_float(CharacterAnimator.standing_chin_height_m(profile)).append_failure_message(
		"buste penché au maximum (%.0f°) : le menton doit baisser à h·cos(θ)" % CharacterAnimator.MAX_TORSO_TILT_DEG
	).is_equal_approx(expected, 0.0001)


func test_standing_chin_height_subtracts_the_bounce_amplitude() -> void:
	var profile := AgentAnimProfile.new()
	profile.bounce_amplitude_m = 0.05
	assert_float(CharacterAnimator.standing_chin_height_m(profile)).append_failure_message(
		"le pire cas du rebond (bas du cycle) doit être soustrait de la ligne du menton"
	).is_equal_approx(CharacterAnimator.STANDING_CHIN_HEIGHT_M - 0.05, 0.0001)


func test_standing_chin_height_clamps_torso_tilt_beyond_the_max() -> void:
	var profile := AgentAnimProfile.new()
	profile.torso_tilt_deg = CharacterAnimator.MAX_TORSO_TILT_DEG + 50.0
	var expected := CharacterAnimator.STANDING_CHIN_HEIGHT_M * cos(deg_to_rad(CharacterAnimator.MAX_TORSO_TILT_DEG))
	assert_float(CharacterAnimator.standing_chin_height_m(profile)).append_failure_message(
		"une inclinaison hors bornes doit être clampée à MAX_TORSO_TILT_DEG avant le calcul géométrique"
	).is_equal_approx(expected, 0.0001)


# ============================================================================
# profile_respects_hitbox_floor
# ============================================================================

func test_neutral_profile_respects_the_hitbox_floor() -> void:
	assert_bool(CharacterAnimator.profile_respects_hitbox_floor(AgentAnimProfile.new())).is_true()


## Pile à la borne du §4.6 (inclinaison = 8°, aucun rebond) : encore valide,
## la borne est inclusive (`>`, pas `>=`, voir `profile_respects_hitbox_floor`).
func test_profile_at_the_exact_tilt_boundary_still_respects_the_floor() -> void:
	var profile := AgentAnimProfile.new()
	profile.torso_tilt_deg = CharacterAnimator.MAX_TORSO_TILT_DEG
	assert_bool(CharacterAnimator.profile_respects_hitbox_floor(profile)).append_failure_message(
		"8° exactement doit encore être accepté (« buste penché de 8° au plus »)"
	).is_true()


func test_profile_fails_when_torso_tilt_exceeds_the_max() -> void:
	var profile := AgentAnimProfile.new()
	profile.torso_tilt_deg = CharacterAnimator.MAX_TORSO_TILT_DEG + 0.1
	assert_bool(CharacterAnimator.profile_respects_hitbox_floor(profile)).append_failure_message(
		"une inclinaison au-delà de %.0f° doit échouer le garde-fou" % CharacterAnimator.MAX_TORSO_TILT_DEG
	).is_false()


func test_profile_fails_when_torso_tilt_is_negative() -> void:
	var profile := AgentAnimProfile.new()
	profile.torso_tilt_deg = -0.1
	assert_bool(CharacterAnimator.profile_respects_hitbox_floor(profile)).append_failure_message(
		"une inclinaison négative n'a pas de sens (§4.6 : penchée vers l'avant uniquement) et doit échouer"
	).is_false()


func test_profile_fails_when_the_bounce_pushes_the_eyes_below_the_floor() -> void:
	var profile := AgentAnimProfile.new()
	profile.bounce_amplitude_m = 0.1
	assert_bool(CharacterAnimator.profile_respects_hitbox_floor(profile)).append_failure_message(
		"un rebond de 0,10 m fait descendre les yeux (1,62 - 0,10 = 1,52 m) sous le plancher de 1,56 m"
	).is_false()


## Debout, à inclinaison nulle, la marge yeux (1,62 - 1,56 = 0,06 m) et la
## marge menton (1,49 - 1,43 = 0,06 m) sont EXACTEMENT égales : à cette marge
## précise, les deux repères touchent leur plancher pile, sans le franchir
## (comparaison stricte `<` dans `profile_respects_hitbox_floor`) — donc
## encore valide.
func test_profile_at_the_exact_bounce_margin_still_respects_the_floor() -> void:
	var profile := AgentAnimProfile.new()
	profile.bounce_amplitude_m = CharacterAnimator.STANDING_EYE_HEIGHT_M - CharacterAnimator.MIN_STANDING_EYE_HEIGHT_M
	assert_bool(CharacterAnimator.profile_respects_hitbox_floor(profile)).append_failure_message(
		"un rebond qui amène les yeux/le menton EXACTEMENT au plancher (marge de 0,06 m) doit encore passer"
	).is_true()


## Un cheveu au-delà de cette même marge fait passer les DEUX repères sous
## leur plancher (les marges yeux/menton sont égales à inclinaison nulle).
func test_profile_fails_just_beyond_the_exact_bounce_margin() -> void:
	var profile := AgentAnimProfile.new()
	profile.bounce_amplitude_m = (CharacterAnimator.STANDING_EYE_HEIGHT_M - CharacterAnimator.MIN_STANDING_EYE_HEIGHT_M) + 0.001
	assert_bool(CharacterAnimator.profile_respects_hitbox_floor(profile)).append_failure_message(
		"1 mm de rebond en plus que la marge exacte doit faire échouer le garde-fou"
	).is_false()


## Les 6 profils LIVRÉS (resources/agents/anim/*.tres) ne doivent jamais
## régresser sous le plancher de hitbox, quels que soient les ajustements de
## personnalité — c'est le contrat central de la tâche ART-15.
func test_every_shipped_agent_profile_respects_the_hitbox_floor() -> void:
	for agent in AgentDatabase.all():
		var config: AgentConfig = agent
		var profile := CharacterAnimator.load_profile(config.agent_name)
		assert_bool(CharacterAnimator.profile_respects_hitbox_floor(profile)).append_failure_message(
			"le profil livré de %s ne respecte pas le plancher de hitbox du §4.6" % config.agent_name
		).is_true()


# ============================================================================
# body_squash_scale (§12 ART-15 : écrasement du CORPS, 0,97 à 1,03, ≤ 80 ms)
# ============================================================================

func test_body_squash_scale_is_neutral_at_the_very_start() -> void:
	assert_float(CharacterAnimator.body_squash_scale(0.0)).is_equal_approx(1.0, 0.0001)


func test_body_squash_scale_dips_to_the_minimum_at_the_first_quarter() -> void:
	var t := CharacterAnimator.BODY_SQUASH_DURATION_S * 0.25
	assert_float(CharacterAnimator.body_squash_scale(t)).append_failure_message(
		"au premier quart de la fenêtre, l'écrasement doit atteindre son minimum (0,97)"
	).is_equal_approx(CharacterAnimator.BODY_SQUASH_MIN_SCALE, 0.0001)


func test_body_squash_scale_returns_to_neutral_at_the_midpoint() -> void:
	var half := CharacterAnimator.BODY_SQUASH_DURATION_S * 0.5
	assert_float(CharacterAnimator.body_squash_scale(half)).append_failure_message(
		"à mi-fenêtre, la bascule entre le creux et le rebond doit repasser par 1,0 (pas d'à-coup)"
	).is_equal_approx(1.0, 0.0001)


func test_body_squash_scale_peaks_at_the_maximum_at_the_third_quarter() -> void:
	var t := CharacterAnimator.BODY_SQUASH_DURATION_S * 0.75
	assert_float(CharacterAnimator.body_squash_scale(t)).append_failure_message(
		"au troisième quart de la fenêtre, l'écrasement doit atteindre son maximum (1,03)"
	).is_equal_approx(CharacterAnimator.BODY_SQUASH_MAX_SCALE, 0.0001)


## Garde-fou (même esprit que `hit_flinch_angle_rad`) : jamais d'effet en
## dehors de `[0, BODY_SQUASH_DURATION_S[`, quel que soit l'appelant.
func test_body_squash_scale_is_neutral_outside_the_duration_window() -> void:
	assert_float(CharacterAnimator.body_squash_scale(-0.01)).is_equal(1.0)
	assert_float(CharacterAnimator.body_squash_scale(CharacterAnimator.BODY_SQUASH_DURATION_S)).is_equal(1.0)
	assert_float(CharacterAnimator.body_squash_scale(CharacterAnimator.BODY_SQUASH_DURATION_S + 1.0)).is_equal(1.0)


## Contrat §12 : jamais hors de la plage 0,97–1,03, à aucun instant de la
## fenêtre (échantillonnage fin, pas seulement les quatre points remarquables
## ci-dessus).
func test_body_squash_scale_never_exceeds_the_contract_range() -> void:
	var steps := 200
	for i in range(steps + 1):
		var t := CharacterAnimator.BODY_SQUASH_DURATION_S * (float(i) / float(steps))
		var scale := CharacterAnimator.body_squash_scale(t)
		assert_float(scale).append_failure_message(
			"t=%.4f s : l'échelle (%.4f) sort de la plage contractuelle [%.2f, %.2f]" %
				[t, scale, CharacterAnimator.BODY_SQUASH_MIN_SCALE, CharacterAnimator.BODY_SQUASH_MAX_SCALE]
		).is_between(CharacterAnimator.BODY_SQUASH_MIN_SCALE, CharacterAnimator.BODY_SQUASH_MAX_SCALE)


## La fenêtre livrée (docs/style/tokens.json `squash.max_ms`) est PLUS stricte
## que le plafond du contrat ART-15 (≤ 100 ms) : elle doit rester sous les
## deux bornes.
func test_body_squash_duration_stays_within_the_contract_ceiling() -> void:
	assert_float(CharacterAnimator.BODY_SQUASH_DURATION_S).append_failure_message(
		"§12 ART-15 : l'écrasement du corps ne doit jamais dépasser 100 ms"
	).is_less_equal(0.1)
	assert_float(CharacterAnimator.BODY_SQUASH_DURATION_S).append_failure_message(
		"docs/style/tokens.json .squash.max_ms = 80 : la fenêtre livrée doit matcher la valeur design"
	).is_equal_approx(0.08, 0.0001)


func test_body_squash_range_matches_the_contract_bounds() -> void:
	assert_float(CharacterAnimator.BODY_SQUASH_MIN_SCALE).is_equal_approx(0.97, 0.0001)
	assert_float(CharacterAnimator.BODY_SQUASH_MAX_SCALE).is_equal_approx(1.03, 0.0001)


# ============================================================================
# Profils livrés (resources/agents/anim/*.tres) — un par agent du roster
# actuel (AgentDatabase.all()), §4.6 : cadence ×0,9 à ×1,15, idle unique.
# ============================================================================

## `CharacterAnimator.load_profile` ne doit jamais renvoyer `null`, y compris
## pour un agent inconnu — repli défensif documenté.
func test_load_profile_never_returns_null_for_an_unknown_agent() -> void:
	assert_object(CharacterAnimator.load_profile("Agent-Inconnu-Test")).is_not_null()


func test_every_current_roster_agent_has_a_shipped_profile_file() -> void:
	for agent in AgentDatabase.all():
		var config: AgentConfig = agent
		var path := "res://resources/agents/anim/%s.tres" % config.agent_name.to_lower()
		assert_bool(ResourceLoader.exists(path)).append_failure_message(
			"aucun profil d'animation livré pour %s (attendu : %s)" % [config.agent_name, path]
		).is_true()


func test_every_shipped_profile_resolves_to_its_own_agent() -> void:
	for agent in AgentDatabase.all():
		var config: AgentConfig = agent
		var profile := CharacterAnimator.load_profile(config.agent_name)
		assert_str(profile.agent_name).append_failure_message(
			"le .tres de %s doit se déclarer lui-même (champ agent_name)" % config.agent_name
		).is_equal(config.agent_name)


func test_every_shipped_profile_cadence_stays_within_the_contract_range() -> void:
	for agent in AgentDatabase.all():
		var config: AgentConfig = agent
		var profile := CharacterAnimator.load_profile(config.agent_name)
		assert_float(profile.cadence_scale).append_failure_message(
			"%s : cadence_scale (%.3f) hors de la plage §4.6 [%.2f, %.2f]" %
				[config.agent_name, profile.cadence_scale, CharacterAnimator.MIN_CADENCE_SCALE, CharacterAnimator.MAX_CADENCE_SCALE]
		).is_between(CharacterAnimator.MIN_CADENCE_SCALE, CharacterAnimator.MAX_CADENCE_SCALE)


## §4.4 : chaque agent a un idle unique — les 6 profils livrés ne peuvent
## donc jamais partager le même `idle_style`.
func test_every_shipped_profile_has_a_distinct_idle_style() -> void:
	var seen: Dictionary = {}
	for agent in AgentDatabase.all():
		var config: AgentConfig = agent
		var profile := CharacterAnimator.load_profile(config.agent_name)
		assert_str(profile.idle_style).append_failure_message(
			"%s : idle_style vide (§4.4, « idle unique »)" % config.agent_name
		).is_not_empty()
		assert_bool(seen.has(profile.idle_style)).append_failure_message(
			"%s partage son idle_style avec %s : chaque agent doit avoir un idle unique (§4.4)" %
				[config.agent_name, seen.get(profile.idle_style, "?")]
		).is_false()
		seen[profile.idle_style] = config.agent_name
