## test_weapon_math.gd
## Spec (contract-p0.md, "Pure classes" / WeaponMath): damage falloff curve,
## headshot boundary, per-shot damage (headshot + pellets), shots-to-kill and
## time-to-kill. All configs below are built explicitly so every expected
## number is exact (no dependency on the .tres catalog values).
## GF-04 : is_headshot prend désormais `body_height` (hauteur COURANTE de la
## cible — PlayerController.current_height, répliquée serveur) au lieu d'un
## seuil fixe de 1.4 m, pour qu'une cible ACCROUPIE (0.9 m, MovementConfig.
## crouch_height) puisse aussi prendre un headshot sur SA tête, plus basse.
## GF-04B : le seuil n'est plus une proportion de `body_height` (ratio) mais
## le sommet de la capsule courante moins HEAD_SIZE = 0.40 m (taille réelle de
## la tête, décision du lead — conflit §14 de docs/STYLE_BIBLE.md). Debout,
## seuil inchangé (1.4 m) ; accroupi, seuil à 0.9 - 0.4 = 0.5 m (au lieu de
## 0.7 m avec l'ancien ratio) : la bande headshot reste haute de 0.4 m dans
## les deux postures.
extends GdUnitTestSuite

## Hauteurs réelles (MovementConfig.stand_height / crouch_height) — dupliquées
## ici en constantes littérales (WeaponMath est pur, sans dépendance à
## l'arbre de scène : cf. sa docstring) pour que les tests ne dépendent pas
## d'une ressource .tres.
const STAND_HEIGHT := 1.8
const CROUCH_HEIGHT := 0.9


func _cfg() -> WeaponConfig:
	var c := WeaponConfig.new()
	c.damage = 40.0
	c.damage_min = 10.0
	c.falloff_start = 10.0
	c.falloff_end = 30.0
	c.headshot_mult = 2.0
	c.fire_rate = 10.0
	c.pellets = 1
	return c


func test_damage_at_before_falloff_start_is_full_damage() -> void:
	var c := _cfg()
	assert_float(WeaponMath.damage_at(0.0, c)).is_equal_approx(40.0, 0.001)
	assert_float(WeaponMath.damage_at(10.0, c)).is_equal_approx(40.0, 0.001)


func test_damage_at_midpoint_is_linear_interpolation() -> void:
	var c := _cfg()
	# t = (20-10)/(30-10) = 0.5 -> 40 + (10-40) * 0.5 = 25.0
	assert_float(WeaponMath.damage_at(20.0, c)).is_equal_approx(25.0, 0.001)


func test_damage_at_after_falloff_end_is_damage_min() -> void:
	var c := _cfg()
	assert_float(WeaponMath.damage_at(30.0, c)).is_equal_approx(10.0, 0.001)
	assert_float(WeaponMath.damage_at(60.0, c)).is_equal_approx(10.0, 0.001)


func test_is_headshot_boundary_standing_at_exact_head_height_is_false() -> void:
	# Debout (1.8 m) : seuil = 1.8 - HEAD_SIZE (0.4) = 1.4 m, comme l'ancienne
	# valeur fixe — hit_y > body_origin_y + seuil (strictement) -> false pile au seuil.
	assert_bool(WeaponMath.is_headshot(1.4, 0.0, STAND_HEIGHT)).is_false()
	assert_bool(WeaponMath.is_headshot(1.399, 0.0, STAND_HEIGHT)).is_false()


func test_is_headshot_standing_just_above_head_height_is_true() -> void:
	# Critère GF-04 : « tir sur la tête debout -> headshot ».
	assert_bool(WeaponMath.is_headshot(1.401, 0.0, STAND_HEIGHT)).is_true()


func test_is_headshot_crouched_on_head_is_true() -> void:
	# Critère GF-04 : « tir sur la tête d'une cible accroupie -> headshot ».
	# Accroupi (0.9 m) : seuil = 0.9 - HEAD_SIZE (0.4) = 0.5 m (GF-04B). Un
	# point proche du sommet de la capsule accroupie (0.85 m, < 0.9 m) est bien
	# au-dessus du seuil -> headshot. Avec l'ANCIEN seuil fixe (1.4 m) ce tir
	# aurait été un corps (0.85 < 1.4) : c'était le bug GF-04 (docs/research/
	# 01_game_feel.md §1.2 : « un joueur accroupi ne peut jamais prendre de
	# headshot »).
	assert_bool(WeaponMath.is_headshot(0.85, 0.0, CROUCH_HEIGHT)).is_true()
	assert_bool(WeaponMath.is_headshot(0.85, 0.0, STAND_HEIGHT)).is_false()


func test_is_headshot_crouched_boundary_at_exact_head_height_is_false() -> void:
	# GF-04B : seuil = sommet de la capsule accroupie (0.9 m) moins HEAD_SIZE
	# (0.4 m) = 0.5 m — pas 0.7 m (ancien ratio proportionnel). Pile au seuil
	# -> false.
	assert_bool(WeaponMath.is_headshot(0.5, 0.0, CROUCH_HEIGHT)).is_false()
	assert_bool(WeaponMath.is_headshot(0.499, 0.0, CROUCH_HEIGHT)).is_false()
	assert_bool(WeaponMath.is_headshot(0.501, 0.0, CROUCH_HEIGHT)).is_true()


func test_is_headshot_body_origin_offset_is_relative() -> void:
	# `body_origin_y` non nul (cible en hauteur) : le seuil reste relatif à
	# l'origine du corps, pas au monde.
	assert_bool(WeaponMath.is_headshot(11.4, 10.0, STAND_HEIGHT)).is_false()
	assert_bool(WeaponMath.is_headshot(11.401, 10.0, STAND_HEIGHT)).is_true()


func test_shot_damage_applies_headshot_multiplier() -> void:
	var c := _cfg()
	assert_float(WeaponMath.shot_damage(c, 0.0, false)).is_equal_approx(40.0, 0.001)
	assert_float(WeaponMath.shot_damage(c, 0.0, true)).is_equal_approx(80.0, 0.001)


func test_shot_damage_multiplies_by_pellet_count() -> void:
	var c := _cfg()
	c.pellets = 8
	# all pellets hit, no headshot: 40 * 8
	assert_float(WeaponMath.shot_damage(c, 0.0, false)).is_equal_approx(320.0, 0.001)
	# headshot + pellets combine: 40 * 2.0 * 8
	assert_float(WeaponMath.shot_damage(c, 0.0, true)).is_equal_approx(640.0, 0.001)


func test_shots_to_kill_rounds_up() -> void:
	var c := _cfg()
	# shot_damage(dist=0, no headshot) = 40 -> hp 100 / 40 = 2.5 -> ceil = 3
	assert_int(WeaponMath.shots_to_kill(c, 0.0, 100.0, false)).is_equal(3)


func test_shots_to_kill_exact_division_does_not_round_up() -> void:
	var c := _cfg()
	# 80 / 40 = 2.0 exactly -> ceil = 2
	assert_int(WeaponMath.shots_to_kill(c, 0.0, 80.0, false)).is_equal(2)


func test_ttk_ms_for_one_shot_kill_is_zero() -> void:
	var c := _cfg()
	# headshot damage = 80, hp = 50 -> 1 shot to kill -> ttk = (1-1)/rate*1000 = 0
	assert_float(WeaponMath.ttk_ms(c, 0.0, 50.0, true)).is_equal_approx(0.0, 0.001)


func test_ttk_ms_for_multi_shot_kill() -> void:
	var c := _cfg()
	# 3 shots to kill (see test above), fire_rate = 10 -> (3-1)/10*1000 = 200 ms
	assert_float(WeaponMath.ttk_ms(c, 0.0, 100.0, false)).is_equal_approx(200.0, 0.001)
