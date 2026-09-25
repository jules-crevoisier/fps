## test_camera_shake.gd
## Spec (GF-08, Squirrel Eiserloh « Juicing Your Cameras With Math », GDC 2016 —
## docs/research/01_game_feel.md §2.1/§3) : `CameraShake` (classe PURE, sans
## Node ni Settings) modélise un trauma dans [0,1] qui décroît LINÉAIREMENT
## (défaut 1.5/s), une amplitude de secousse en `trauma²` (jamais linéaire),
## une rotation SEULE (yaw/pitch/roll via `FastNoiseLite`, jamais de
## translation) plafonnée à `MAX_ANGLE_DEG` (1.2°), des déclencheurs de trauma
## fixes (dégât reçu 0.3, explosion proche 0.6) ou bornés par arme (tir,
## 0.08-0.25 — le champ dédié de `WeaponConfig` est hors du périmètre de cette
## tâche, voir le rendu), un punch FOV (-1.5° en 60 ms pour les armes lourdes)
## et une intensité effective qui tombe à 0 en mouvement réduit ou secousses
## désactivées (`CameraShake.effective_intensity`, consommée par
## `PlayerCamera._process`/`_apply_interpolated_transform`).
##
## Volontairement SANS scène (pas de `preload` de `player.tscn`) : tests
## PURS uniquement sur la classe `CameraShake` et son instance, sans aucune
## dépendance à l'arbre de scène ni aux autres systèmes du joueur — voir
## `PlayerCamera.gd` pour le câblage (`_shake`, `add_shot_trauma`/
## `add_damage_trauma`/`add_explosion_trauma`/`punch_fov_heavy`,
## `_apply_interpolated_transform`), revu manuellement et hors du périmètre de
## ce fichier de test.
extends GdUnitTestSuite


# ================================================================ CameraShake
# --------------------------------------------------- constantes d'acceptance

func test_default_decay_per_second_is_1_5() -> void:
	assert_float(CameraShake.DEFAULT_DECAY_PER_SECOND).is_equal_approx(1.5, 0.001)


func test_max_angle_deg_is_1_2() -> void:
	assert_float(CameraShake.MAX_ANGLE_DEG).is_equal_approx(1.2, 0.001)


func test_shot_trauma_bounds_are_0_08_and_0_25() -> void:
	assert_float(CameraShake.SHOT_TRAUMA_MIN).is_equal_approx(0.08, 0.001)
	assert_float(CameraShake.SHOT_TRAUMA_MAX).is_equal_approx(0.25, 0.001)


func test_damage_and_explosion_trauma_are_0_3_and_0_6() -> void:
	assert_float(CameraShake.TRAUMA_DAMAGE_TAKEN).is_equal_approx(0.3, 0.001)
	assert_float(CameraShake.TRAUMA_EXPLOSION_NEAR).is_equal_approx(0.6, 0.001)


func test_punch_fov_heavy_is_minus_1_5_deg_over_60_ms() -> void:
	assert_float(CameraShake.PUNCH_FOV_HEAVY_DEG).is_equal_approx(-1.5, 0.001)
	assert_float(CameraShake.PUNCH_FOV_HEAVY_DURATION).is_equal_approx(0.06, 0.001)


# ------------------------------------------------------- clamp_trauma (pure)

func test_clamp_trauma_within_range_is_unchanged() -> void:
	assert_float(CameraShake.clamp_trauma(0.42)).is_equal_approx(0.42, 0.001)


func test_clamp_trauma_out_of_range_is_clamped_to_0_1() -> void:
	assert_float(CameraShake.clamp_trauma(-1.0)).is_equal_approx(0.0, 0.001)
	assert_float(CameraShake.clamp_trauma(3.0)).is_equal_approx(1.0, 0.001)


# ----------------------------------------------- decayed_trauma (pure, courbe)

func test_decayed_trauma_is_linear_at_the_default_rate() -> void:
	# Décroissance LINÉAIRE (GF-08) : 0.6 de trauma, 1.5/s, 0.1 s -> 0.6 - 0.15 = 0.45.
	assert_float(CameraShake.decayed_trauma(0.6, 1.5, 0.1)).is_equal_approx(0.45, 0.001)


func test_decayed_trauma_never_goes_below_zero() -> void:
	assert_float(CameraShake.decayed_trauma(1.0, 1.5, 1.0)).is_equal_approx(0.0, 0.001)
	assert_float(CameraShake.decayed_trauma(0.1, 1.5, 10.0)).is_equal_approx(0.0, 0.001)


# --------------------------------------------- amplitude_for_trauma (pure)

func test_amplitude_is_trauma_squared_not_linear() -> void:
	assert_float(CameraShake.amplitude_for_trauma(0.5)).is_equal_approx(0.25, 0.001)
	assert_float(CameraShake.amplitude_for_trauma(1.0)).is_equal_approx(1.0, 0.001)
	assert_float(CameraShake.amplitude_for_trauma(0.0)).is_equal_approx(0.0, 0.001)


func test_amplitude_is_much_smaller_than_trauma_at_low_values() -> void:
	# La relation quadratique doit rendre les petits trauma presque invisibles
	# (Eiserloh) : à trauma = 0.2, l'amplitude (0.04) doit être largement sous
	# le trauma lui-même, pas juste légèrement.
	var amp := CameraShake.amplitude_for_trauma(0.2)
	assert_float(amp).is_equal_approx(0.04, 0.001)
	assert_float(amp).is_less(0.2 * 0.5)


# ----------------------------------------------------------- shot_trauma (pure)

func test_shot_trauma_clamps_above_max_weapon_config_value() -> void:
	assert_float(CameraShake.shot_trauma(0.9)).is_equal_approx(CameraShake.SHOT_TRAUMA_MAX, 0.001)


func test_shot_trauma_clamps_below_min_weapon_config_value() -> void:
	assert_float(CameraShake.shot_trauma(0.01)).is_equal_approx(CameraShake.SHOT_TRAUMA_MIN, 0.001)


func test_shot_trauma_within_range_is_unchanged() -> void:
	assert_float(CameraShake.shot_trauma(0.15)).is_equal_approx(0.15, 0.001)


# ------------------------------------------------------- fov_punch_value (pure)

func test_fov_punch_value_is_full_magnitude_at_impact() -> void:
	assert_float(CameraShake.fov_punch_value(0.0, 0.06, -1.5)).is_equal_approx(-1.5, 0.001)


func test_fov_punch_value_is_zero_once_the_duration_has_fully_elapsed() -> void:
	assert_float(CameraShake.fov_punch_value(0.06, 0.06, -1.5)).is_equal_approx(0.0, 0.001)
	assert_float(CameraShake.fov_punch_value(1.0, 0.06, -1.5)).is_equal_approx(0.0, 0.001)


func test_fov_punch_value_recovers_faster_than_linear_ease_out() -> void:
	# easeOutQuad : à mi-parcours, on doit déjà avoir récupéré PLUS de la
	# moitié du chemin vers 0 (pas un simple lerp linéaire -0.75).
	var mid := CameraShake.fov_punch_value(0.03, 0.06, -1.5)
	assert_float(mid).is_greater(-0.75)  # plus proche de 0 qu'un retour linéaire
	assert_float(mid).is_less(0.0)


func test_fov_punch_value_with_zero_duration_is_zero() -> void:
	assert_float(CameraShake.fov_punch_value(0.0, 0.0, -1.5)).is_equal_approx(0.0, 0.001)


# --------------------------------------------------- effective_intensity (pure)

func test_effective_intensity_is_zero_when_reduced_motion() -> void:
	assert_float(CameraShake.effective_intensity(1.0, true, true)).is_equal_approx(0.0, 0.001)


func test_effective_intensity_is_zero_when_shake_disabled() -> void:
	assert_float(CameraShake.effective_intensity(1.0, false, false)).is_equal_approx(0.0, 0.001)


func test_effective_intensity_is_zero_when_both_reasons_apply() -> void:
	assert_float(CameraShake.effective_intensity(1.0, false, true)).is_equal_approx(0.0, 0.001)


func test_effective_intensity_returns_the_clamped_setting_otherwise() -> void:
	assert_float(CameraShake.effective_intensity(0.5, true, false)).is_equal_approx(0.5, 0.001)
	assert_float(CameraShake.effective_intensity(3.0, true, false)).is_equal_approx(1.0, 0.001)
	assert_float(CameraShake.effective_intensity(-2.0, true, false)).is_equal_approx(0.0, 0.001)


# ------------------------------------------------------ instance : add_trauma

func test_add_trauma_accumulates() -> void:
	var shake := CameraShake.new()
	shake.add_trauma(0.2)
	shake.add_trauma(0.3)
	assert_float(shake.trauma).is_equal_approx(0.5, 0.001)


func test_add_trauma_clamps_the_total_to_1() -> void:
	var shake := CameraShake.new()
	shake.add_trauma(0.7)
	shake.add_trauma(0.7)
	assert_float(shake.trauma).is_equal_approx(1.0, 0.001)


func test_add_shot_trauma_reborns_into_the_weapon_config_range() -> void:
	var shake := CameraShake.new()
	shake.add_shot_trauma(0.9)  # au-delà de SHOT_TRAUMA_MAX, comme une arme mal configurée
	assert_float(shake.trauma).is_equal_approx(CameraShake.SHOT_TRAUMA_MAX, 0.001)


func test_add_damage_trauma_adds_0_3() -> void:
	var shake := CameraShake.new()
	shake.add_damage_trauma()
	assert_float(shake.trauma).is_equal_approx(0.3, 0.001)


func test_add_explosion_trauma_adds_0_6() -> void:
	var shake := CameraShake.new()
	shake.add_explosion_trauma()
	assert_float(shake.trauma).is_equal_approx(0.6, 0.001)


# ---------------------------------------------------------- instance : update

func test_update_decays_trauma_linearly_over_several_steps() -> void:
	var shake := CameraShake.new()
	shake.add_trauma(1.0)
	for i in range(30):  # 30 * (1/60) = 0.5 s
		shake.update(1.0 / 60.0)
	assert_float(shake.trauma).is_equal_approx(1.0 - 1.5 * 0.5, 0.01)  # 0.25


func test_update_with_a_custom_decay_rate_uses_the_instance_field() -> void:
	var shake := CameraShake.new()
	shake.decay_per_second = 4.0
	shake.add_trauma(1.0)
	shake.update(0.1)
	assert_float(shake.trauma).is_equal_approx(0.6, 0.001)  # 1.0 - 4.0*0.1


# --------------------------------------------------- instance : rotation_offset_deg

func test_rotation_offset_is_zero_when_trauma_is_zero() -> void:
	var shake := CameraShake.new()
	shake.update(1.0 / 60.0)
	assert_vector(shake.rotation_offset_deg(1.0)).is_equal_approx(Vector3.ZERO, Vector3.ONE * 0.001)


func test_rotation_offset_is_zero_when_intensity_is_zero_even_at_full_trauma() -> void:
	var shake := CameraShake.new()
	shake.add_trauma(1.0)
	shake.update(1.0 / 60.0)
	assert_vector(shake.rotation_offset_deg(0.0)).is_equal_approx(Vector3.ZERO, Vector3.ONE * 0.001)


func test_rotation_offset_never_exceeds_max_angle_deg_at_full_trauma_and_intensity() -> void:
	var shake := CameraShake.new()
	for i in range(200):
		shake.trauma = 1.0  # trauma plein EXACT à chaque échantillon (on teste le bruit, pas la décroissance)
		var off := shake.rotation_offset_deg(1.0)
		assert_float(absf(off.x)).append_failure_message(
			"pitch = %.4f au pas %d, doit rester <= %.2f" % [off.x, i, CameraShake.MAX_ANGLE_DEG]
		).is_less_equal(CameraShake.MAX_ANGLE_DEG + 0.001)
		assert_float(absf(off.y)).is_less_equal(CameraShake.MAX_ANGLE_DEG + 0.001)
		assert_float(absf(off.z)).is_less_equal(CameraShake.MAX_ANGLE_DEG + 0.001)
		shake.update(1.0 / 60.0)  # avance seulement le bruit pour le prochain échantillon


func test_rotation_offset_axes_are_decorrelated() -> void:
	# Les 3 axes (pitch/yaw/roll) lisent le MÊME bruit à des décalages
	# différents (Eiserloh) : ils ne doivent pas être des triplets identiques
	# à chaque pas, sinon la secousse tournerait "en bloc" au lieu de trembler.
	var shake := CameraShake.new()
	var saw_a_difference := false
	for i in range(50):
		shake.trauma = 1.0
		var off := shake.rotation_offset_deg(1.0)
		if not (is_equal_approx(off.x, off.y) and is_equal_approx(off.y, off.z)):
			saw_a_difference = true
			break
		shake.update(1.0 / 60.0)
	assert_bool(saw_a_difference).append_failure_message(
		"les 3 axes de rotation restent identiques à chaque pas : le bruit ne semble pas décalé par axe"
	).is_true()


func test_rotation_offset_scales_linearly_with_intensity() -> void:
	# Deux instances IDENTIQUES (même graine), avancées du même pas : la seule
	# différence est l'intensité passée à `rotation_offset_deg`, donc le
	# résultat à 0.5 doit être exactement la moitié de celui à 1.0, quel que
	# soit l'échantillon de bruit tiré.
	var full := CameraShake.new(7)
	var half := CameraShake.new(7)
	full.add_trauma(1.0)
	half.add_trauma(1.0)
	full.update(1.0 / 60.0)
	half.update(1.0 / 60.0)
	var off_full := full.rotation_offset_deg(1.0)
	var off_half := half.rotation_offset_deg(0.5)
	assert_vector(off_half).is_equal_approx(off_full * 0.5, Vector3.ONE * 0.001)


# ------------------------------------------------------ instance : fov_offset_deg

func test_fov_offset_is_zero_with_no_punch_requested() -> void:
	var shake := CameraShake.new()
	assert_float(shake.fov_offset_deg(1.0)).is_equal_approx(0.0, 0.001)


func test_fov_offset_is_full_magnitude_immediately_after_add_fov_punch() -> void:
	var shake := CameraShake.new()
	shake.add_fov_punch(CameraShake.PUNCH_FOV_HEAVY_DEG, CameraShake.PUNCH_FOV_HEAVY_DURATION)
	assert_float(shake.fov_offset_deg(1.0)).is_equal_approx(-1.5, 0.001)


func test_fov_offset_returns_to_zero_once_the_punch_duration_has_elapsed() -> void:
	var shake := CameraShake.new()
	shake.add_fov_punch(CameraShake.PUNCH_FOV_HEAVY_DEG, CameraShake.PUNCH_FOV_HEAVY_DURATION)
	shake.update(CameraShake.PUNCH_FOV_HEAVY_DURATION)
	assert_float(shake.fov_offset_deg(1.0)).is_equal_approx(0.0, 0.001)


func test_fov_offset_respects_intensity() -> void:
	var shake := CameraShake.new()
	shake.add_fov_punch(CameraShake.PUNCH_FOV_HEAVY_DEG, CameraShake.PUNCH_FOV_HEAVY_DURATION)
	assert_float(shake.fov_offset_deg(0.5)).is_equal_approx(-0.75, 0.001)
	assert_float(shake.fov_offset_deg(0.0)).is_equal_approx(0.0, 0.001)


func test_a_second_fov_punch_replaces_the_first_instead_of_accumulating() -> void:
	# Un second tir rapproché relance l'impulsion (pas d'accumulation, qui
	# donnerait un FOV négatif aberrant en rafale d'armes lourdes).
	var shake := CameraShake.new()
	shake.add_fov_punch(-1.5, 0.06)
	shake.update(0.03)  # mi-parcours du premier punch
	shake.add_fov_punch(-1.5, 0.06)  # second tir : relance à plein
	assert_float(shake.fov_offset_deg(1.0)).is_equal_approx(-1.5, 0.001)
