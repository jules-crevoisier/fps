## test_throw_velocity.gd
## Spec (contrat lead 2026-09-27, "short throw on RIGHT click") :
## - lancer long (short=false) : vitesse inchangée, pleine `throw_speed` le
##   long du regard ;
## - lancer court (short=true) : direction relevée de +12° (bornée à 85°),
##   vitesse = throw_speed * short_throw_speed_factor ;
## - UNE SEULE fonction pure (`UtilityThrower.throw_velocity`) fait autorité
##   pour la prédiction propriétaire, le serveur ET le rejeu distant.
extends GdUnitTestSuite


func _cfg() -> UtilityConfig:
	return UtilityDatabase.get_by_id(UtilityDatabase.FRAG)


func test_long_throw_is_unchanged() -> void:
	var cfg := _cfg()
	var dir := Vector3(0, 0, -1)
	var vel := UtilityThrower.throw_velocity(dir, cfg, false)
	assert_vector(vel).is_equal_approx(dir * cfg.throw_speed, Vector3.ONE * 0.001)


func test_short_throw_scales_by_the_configured_factor() -> void:
	var cfg := _cfg()
	var vel := UtilityThrower.throw_velocity(Vector3(0, 0, -1), cfg, true)
	assert_float(vel.length()).append_failure_message(
		"la vitesse du lob court doit être throw_speed * short_throw_speed_factor"
	).is_equal_approx(cfg.throw_speed * cfg.short_throw_speed_factor, 0.01)


func test_short_throw_pitches_the_direction_up() -> void:
	var cfg := _cfg()
	var vel := UtilityThrower.throw_velocity(Vector3(0, 0, -1), cfg, true)
	assert_float(vel.y).append_failure_message(
		"un regard parfaitement à l'horizontale doit finir relevé (composante Y positive)"
	).is_greater(0.0)


func test_short_throw_pitch_is_exactly_twelve_degrees_from_horizontal_look() -> void:
	var cfg := _cfg()
	var vel := UtilityThrower.throw_velocity(Vector3(0, 0, -1), cfg, true)
	var pitch_rad := atan2(vel.y, Vector3(vel.x, 0, vel.z).length())
	assert_float(rad_to_deg(pitch_rad)).is_equal_approx(12.0, 0.01)


func test_pitch_up_is_clamped_to_the_max_pitch() -> void:
	# Un regard déjà bien relevé (78°) + 12° = 90° dépasserait 85° sans le clamp.
	var dir := Vector3(0, sin(deg_to_rad(78.0)), -cos(deg_to_rad(78.0)))
	var pitched := UtilityThrower.pitch_up(dir, 12.0, 85.0)
	var pitch_rad := atan2(pitched.y, Vector3(pitched.x, 0, pitched.z).length())
	assert_float(rad_to_deg(pitch_rad)).is_equal_approx(85.0, 0.01)


func test_pitch_up_preserves_yaw() -> void:
	var dir := Vector3(-1, 0, 0)  # regarde vers -X à l'horizontale.
	var pitched := UtilityThrower.pitch_up(dir, 12.0, 85.0)
	assert_float(pitched.x).append_failure_message(
		"le relèvement ne doit jamais tourner le lacet (direction horizontale conservée)"
	).is_less(0.0)
	assert_float(absf(pitched.z)).is_less(0.001)


func test_pitch_up_falls_back_to_a_horizontal_axis_when_dir_is_straight_up() -> void:
	var pitched := UtilityThrower.pitch_up(Vector3(0, 1, 0), 12.0, 85.0)
	assert_bool(pitched.is_finite()).is_true()
	assert_float(pitched.length()).is_equal_approx(1.0, 0.001)
