## test_weapon_feel.gd
## Spec (contract-r3.md, R3-IN#4 ; continu façon Valorant, MV-02) : sensation
## d'arme pure — motif de recul fixe puis aléatoire, dispersion additionnelle
## mouvement (continue, zone morte)/l'air, délai avant de pouvoir tirer après
## une glissade/un plongeon (le sprint est automatique et sans délai, voir
## BUG-K01), progression ADS, et ralentissement du déplacement en ADS. Fichier
## dédié à ces ajouts : ne modifie aucun autre test existant (test_weapon_math.gd,
## test_inventory.gd... restent intacts).
extends GdUnitTestSuite


func _cfg() -> WeaponConfig:
	var c := WeaponConfig.new()
	c.recoil_pattern = PackedVector2Array([Vector2(0.0, 0.5), Vector2(0.1, 0.6), Vector2(-0.1, 0.55)])
	c.pattern_shots = 3
	c.recoil_horizontal = 0.35
	c.recoil_vertical = 0.55
	c.move_spread_add = 1.5
	c.move_spread_deadzone = 0.3
	c.slide_spread_mult = 1.3
	c.air_spread_add = 3.0
	c.spread_hip = 2.0
	c.spread_aim = 0.3
	c.slide_to_fire = 0.38
	c.dive_to_fire = 0.46
	c.ads_time = 0.2
	return c


func test_recoil_follows_fixed_pattern_within_pattern_shots() -> void:
	var c := _cfg()
	var kick := WeaponFeel.recoil_for_shot(c, 1)
	assert_float(kick.x).is_equal_approx(0.1, 0.0001)
	assert_float(kick.y).is_equal_approx(0.6, 0.0001)


func test_recoil_falls_back_to_random_beyond_pattern_shots() -> void:
	var c := _cfg()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var kick := WeaponFeel.recoil_for_shot(c, 10, rng)
	assert_bool(absf(kick.x) <= c.recoil_horizontal + 0.0001).is_true()
	assert_float(kick.y).is_equal_approx(c.recoil_vertical, 0.0001)


func test_recoil_first_shot_uses_pattern_index_zero() -> void:
	var c := _cfg()
	var kick := WeaponFeel.recoil_for_shot(c, 0)
	assert_float(kick.x).is_equal_approx(0.0, 0.0001)
	assert_float(kick.y).is_equal_approx(0.5, 0.0001)


func test_move_spread_is_zero_below_deadzone() -> void:
	# MV-02 : à 0.25 x vitesse de sprint (< deadzone 0.3) -> 0 pénalité.
	var c := _cfg()
	var s := WeaponFeel.move_spread_deg(c, 2.0, 8.0, false)
	assert_float(s).is_equal_approx(0.0, 0.0001)


func test_move_spread_is_full_at_sprint_speed() -> void:
	# MV-02 : à 1.0 x vitesse de sprint -> pénalité pleine (move_spread_add).
	var c := _cfg()
	var s := WeaponFeel.move_spread_deg(c, 8.0, 8.0, false)
	assert_float(s).is_equal_approx(c.move_spread_add, 0.0001)


func test_move_spread_follows_smoothstep_curve_between_deadzone_and_full() -> void:
	# t = (0.475 - 0.3) / (1.0 - 0.3) = 0.25 -> smoothstep(t) = t*t*(3-2t) = 0.15625
	# (distingue d'une simple interpolation linéaire, qui donnerait 0.25).
	var c := _cfg()
	var s := WeaponFeel.move_spread_deg(c, 3.8, 8.0, false)
	assert_float(s).is_equal_approx(c.move_spread_add * 0.15625, 0.0001)


func test_move_spread_sliding_applies_slide_mult() -> void:
	# MV-02 : en glissade, la pénalité (pleine ici) est majorée x1.3.
	var c := _cfg()
	var s := WeaponFeel.move_spread_deg(c, 8.0, 8.0, true)
	assert_float(s).is_equal_approx(c.move_spread_add * c.slide_spread_mult, 0.0001)


func test_move_spread_clamps_above_sprint_speed() -> void:
	# Au-delà de la vitesse de sprint (survitesse en slide) -> reste pleine, pas plus.
	var c := _cfg()
	var s := WeaponFeel.move_spread_deg(c, 12.0, 8.0, false)
	assert_float(s).is_equal_approx(c.move_spread_add, 0.0001)


func test_total_spread_sums_base_move_and_air() -> void:
	var t := WeaponFeel.total_spread_deg(2.0, 1.5, 3.0)
	assert_float(t).is_equal_approx(6.5, 0.001)


func test_total_spread_with_no_penalty_returns_base_only() -> void:
	var t := WeaponFeel.total_spread_deg(2.0, 0.0, 0.0)
	assert_float(t).is_equal_approx(2.0, 0.0001)


func test_ads_move_speed_slows_while_aiming() -> void:
	# MV-02 : vitesse cible x ads_move_mult (défaut 0.7) en ADS.
	var v := WeaponFeel.ads_move_speed(5.2, true, 0.7)
	assert_float(v).is_equal_approx(3.64, 0.001)


func test_ads_move_speed_unaffected_when_not_aiming() -> void:
	var v := WeaponFeel.ads_move_speed(8.2, false, 0.7)
	assert_float(v).is_equal_approx(8.2, 0.0001)


func test_fire_delay_blocks_right_after_slide() -> void:
	var c := _cfg()
	assert_float(WeaponFeel.fire_delay_left(c, 0.0, INF)).is_equal_approx(0.38, 0.001)


func test_fire_delay_clears_after_enough_time() -> void:
	var c := _cfg()
	assert_float(WeaponFeel.fire_delay_left(c, 1.0, INF)).is_equal_approx(0.0, 0.001)


func test_fire_delay_takes_the_longest_pending_penalty() -> void:
	var c := _cfg()
	# 0.1 s après un slide (délai 0.38 s -> reste 0.28) et 0.4 s après un dive
	# (délai 0.46 s -> reste 0.06) : le slide domine.
	var left := WeaponFeel.fire_delay_left(c, 0.1, 0.4)
	assert_float(left).is_equal_approx(0.28, 0.001)


func test_ads_progress_moves_toward_aim_over_ads_time() -> void:
	var c := _cfg()
	var t := WeaponFeel.ads_progress(0.0, true, c.ads_time, c.ads_time)
	assert_float(t).is_equal_approx(1.0, 0.001)


func test_ads_progress_returns_toward_hip_when_not_aiming() -> void:
	var c := _cfg()
	var t := WeaponFeel.ads_progress(1.0, false, c.ads_time, c.ads_time)
	assert_float(t).is_equal_approx(0.0, 0.001)


func test_ads_progress_partial_step_is_proportional() -> void:
	var c := _cfg()
	var t := WeaponFeel.ads_progress(0.0, true, c.ads_time * 0.5, c.ads_time)
	assert_float(t).is_equal_approx(0.5, 0.001)


# ------------------------------------------------------------ WeaponFeel.spread_dir (GF-13, disque repère caméra)
# Remplace l'ancienne dispersion carrée de Weapon._apply_spread (deux
# randf_range indépendants, coins du carré surreprésentés) tournant autour de
# Vector3.UP MONDIAL (cône aplati près de la verticale caméra).

func _reconstruct_pitch_yaw(dir: Vector3, cam_basis: Basis) -> Vector2:
	# Inverse EXACT de la construction de spread_dir (rotation autour de
	# cam_basis.x puis cam_basis.y) : dir.dot(up) = sin(pitch),
	# dir.dot(right) = cos(pitch) * sin(yaw).
	var pitch := asin(clampf(dir.dot(cam_basis.y), -1.0, 1.0))
	var cp := cos(pitch)
	var yaw := 0.0
	if cp > 0.0001:
		yaw = asin(clampf(dir.dot(cam_basis.x) / cp, -1.0, 1.0))
	return Vector2(pitch, yaw)


func test_spread_dir_returns_base_dir_unchanged_when_spread_is_zero() -> void:
	var base_dir := Vector3(0, 0, -1)
	var dir := WeaponFeel.spread_dir(base_dir, Basis.IDENTITY, 0.0)
	assert_float(dir.x).is_equal_approx(base_dir.x, 0.0001)
	assert_float(dir.y).is_equal_approx(base_dir.y, 0.0001)
	assert_float(dir.z).is_equal_approx(base_dir.z, 0.0001)


func test_spread_dir_stays_within_the_cone_over_10000_draws() -> void:
	# Le rayon r = sqrt(u) * spread_rad est borné par construction (u dans
	# [0,1[) : l'angle entre le résultat et base_dir ne peut jamais dépasser r,
	# donc jamais spread_rad -- 100 % des tirages dans le cône.
	var base_dir := Vector3(0, 0, -1)
	var cam_basis := Basis.IDENTITY
	var spread_rad := deg_to_rad(5.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var max_angle := 0.0
	for i in 10000:
		var dir := WeaponFeel.spread_dir(base_dir, cam_basis, spread_rad, rng)
		var angle := acos(clampf(dir.dot(base_dir), -1.0, 1.0))
		max_angle = maxf(max_angle, angle)
	assert_bool(max_angle <= spread_rad + 0.0001).is_true()


func test_spread_dir_avoids_the_bounding_square_corners() -> void:
	# Une dispersion CARRÉE (bug d'origine) peuplerait uniformément les coins
	# (|pitch| ET |yaw| grands en même temps). Ici pitch^2 + yaw^2 <=
	# spread_rad^2 : les deux ne peuvent jamais dépasser 0.8 * spread_rad
	# simultanément (0.8 * sqrt(2) > 1) -- densité des coins EXACTEMENT nulle.
	var base_dir := Vector3(0, 0, -1)
	var cam_basis := Basis.IDENTITY
	var spread_rad := deg_to_rad(5.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var threshold := spread_rad * 0.8
	var corner_hits := 0
	for i in 10000:
		var dir := WeaponFeel.spread_dir(base_dir, cam_basis, spread_rad, rng)
		var py := _reconstruct_pitch_yaw(dir, cam_basis)
		if absf(py.x) > threshold and absf(py.y) > threshold:
			corner_hits += 1
	assert_int(corner_hits).is_equal(0)


func test_spread_dir_cone_stays_circular_at_extreme_camera_pitch() -> void:
	# Le bug d'origine tournait autour de Vector3.UP MONDIAL : à un pitch
	# caméra proche de la verticale, cet axe devient quasi parallèle à
	# base_dir et le cône s'aplatit. En tournant autour des axes X/Y de la
	# CAMÉRA (toujours perpendiculaires à base_dir), le cône reste isotrope
	# même à pitch +-80° : Variance(pitch) ~= Variance(yaw) sur 10 000
	# tirages (symétrie du disque : les deux valent E[r^2]/2).
	var cam_basis := Basis(Vector3.RIGHT, deg_to_rad(80.0))
	var base_dir := -cam_basis.z
	var spread_rad := deg_to_rad(4.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 23
	var sum_pitch_sq := 0.0
	var sum_yaw_sq := 0.0
	for i in 10000:
		var dir := WeaponFeel.spread_dir(base_dir, cam_basis, spread_rad, rng)
		var py := _reconstruct_pitch_yaw(dir, cam_basis)
		sum_pitch_sq += py.x * py.x
		sum_yaw_sq += py.y * py.y
	var ratio := sum_pitch_sq / sum_yaw_sq
	assert_bool(ratio > 0.85 and ratio < 1.15).is_true()
