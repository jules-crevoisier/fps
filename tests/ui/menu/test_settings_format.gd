## test_settings_format.gd
## Spec (brief lead 2026-09-27, SettingsPanel/settings.html) : formatage FR
## (virgule décimale) des curseurs — sensibilité relative "1,00", multiplicateur
## ADS "×0,85", FOV "103°" — jamais de bornage ici (Settings.gd reste la seule
## source des clamps).
extends GdUnitTestSuite

const SettingsFormat := preload("res://scripts/ui/menu/SettingsFormat.gd")


func test_format_ratio_at_default_is_one() -> void:
	assert_str(SettingsFormat.format_ratio(0.001, 0.001)).is_equal("1,00")


func test_format_ratio_below_default() -> void:
	assert_str(SettingsFormat.format_ratio(0.00085, 0.001)).is_equal("0,85")


func test_format_multiplier() -> void:
	assert_str(SettingsFormat.format_multiplier(0.85)).is_equal("×0,85")
	assert_str(SettingsFormat.format_multiplier(1.0)).is_equal("×1,00")


func test_format_degrees_rounds_to_int() -> void:
	assert_str(SettingsFormat.format_degrees(103.0)).is_equal("103°")
	assert_str(SettingsFormat.format_degrees(102.6)).is_equal("103°")


func test_format_seconds() -> void:
	assert_str(SettingsFormat.format_seconds(2.4)).is_equal("2,4 s")
	assert_str(SettingsFormat.format_seconds(2.0)).is_equal("2 s")


func test_format_number_drops_trailing_zero_decimal() -> void:
	assert_str(SettingsFormat.format_number(45.0)).is_equal("45")
	assert_str(SettingsFormat.format_number(1.4)).is_equal("1,4")


func test_percent_clamped_to_unit_range() -> void:
	assert_float(SettingsFormat.percent(80.0, 80.0, 120.0)).is_equal_approx(0.0, 0.001)
	assert_float(SettingsFormat.percent(120.0, 80.0, 120.0)).is_equal_approx(1.0, 0.001)
	assert_float(SettingsFormat.percent(103.0, 80.0, 120.0)).is_equal_approx(0.575, 0.01)
	# Hors bornes : jamais un dépassement de [0,1], le curseur reste dessinable.
	assert_float(SettingsFormat.percent(200.0, 80.0, 120.0)).is_equal_approx(1.0, 0.001)
	assert_float(SettingsFormat.percent(-10.0, 80.0, 120.0)).is_equal_approx(0.0, 0.001)


func test_percent_degenerate_range_is_zero() -> void:
	assert_float(SettingsFormat.percent(5.0, 10.0, 10.0)).is_equal_approx(0.0, 0.001)
