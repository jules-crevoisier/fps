## test_armory_format.gd
## Spec (brief lead 2026-09-27, ArmoryScreen/armory.html) : les stats affichées
## viennent des VRAIES ressources WeaponConfig/UtilityConfig (WeaponDatabase/
## UtilityDatabase), formatées en FR — jamais un nombre recopié à la main.
## Vérifié directement contre resources/weapons/revolver.tres (mêmes valeurs
## que la maquette : 55 / 35 au-delà de 45 m / tête ×2 / 3 par s / 7,5 en
## éventail / 1,2° / 6 sur 36 / 2,4 s).
extends GdUnitTestSuite

const ArmoryFormat := preload("res://scripts/ui/menu/ArmoryFormat.gd")


func _revolver() -> WeaponConfig:
	return WeaponDatabase.get_by_name("Revolver")


func _ravage() -> WeaponConfig:
	return WeaponDatabase.get_by_name("Ravage")


func test_revolver_damage_matches_mockup() -> void:
	var d := ArmoryFormat.format_damage(_revolver())
	assert_str(d["value"]).is_equal("55")
	assert_str(d["note"]).is_equal("35 au-delà de 45 m · tête ×2")


func test_revolver_fire_rate_matches_mockup() -> void:
	var f := ArmoryFormat.format_fire_rate(_revolver())
	assert_str(f["value"]).is_equal("3 / s")
	assert_str(f["note"]).is_equal("7,5 / s en éventail")


func test_revolver_spread_matches_mockup() -> void:
	var s := ArmoryFormat.format_spread(_revolver())
	assert_str(s["value"]).is_equal("1,2°")
	assert_str(s["note"]).is_equal("+4° en éventail")


func test_revolver_magazine_matches_mockup() -> void:
	var m := ArmoryFormat.format_magazine(_revolver())
	assert_str(m["value"]).is_equal("6 / 36")
	assert_str(m["note"]).is_equal("Rechargement 2,4 s")


func test_ravage_has_no_fan_note() -> void:
	var f := ArmoryFormat.format_fire_rate(_ravage())
	assert_str(f["note"]).is_equal("")
	var s := ArmoryFormat.format_spread(_ravage())
	assert_str(s["note"]).is_equal("")


func test_fire_mode_hints_differ_between_fan_and_normal_weapons() -> void:
	var revolver_hints := ArmoryFormat.fire_mode_hints(_revolver())
	assert_str(revolver_hints[1]["label"]).is_equal("Maintenir : éventail")
	var ravage_hints := ArmoryFormat.fire_mode_hints(_ravage())
	assert_str(ravage_hints[1]["label"]).is_equal("Viser")


func test_bars_are_clamped_between_0_and_10() -> void:
	assert_int(ArmoryFormat.damage_bars(_revolver())).is_between(0, 10)
	assert_int(ArmoryFormat.fire_rate_bars(_revolver())).is_between(0, 10)
	assert_int(ArmoryFormat.precision_bars(_revolver())).is_between(0, 10)
	assert_int(ArmoryFormat.range_bars(_revolver())).is_between(0, 10)
	assert_int(ArmoryFormat.mobility_bars(_revolver())).is_between(0, 10)


## Contrat lead 2026-09-28 ("4 simple stat bars: Dégâts, Cadence, Portée,
## Mobilité") : Portée vient de `falloff_end` (déjà vérifié contre le
## Revolver par `test_revolver_damage_matches_mockup` -- "35 au-delà de 45 m").
func test_revolver_range_matches_falloff_end() -> void:
	var r := ArmoryFormat.format_range(_revolver())
	assert_str(r["value"]).is_equal("45 m")


func test_ravage_range_matches_falloff_end() -> void:
	var r := ArmoryFormat.format_range(_ravage())
	assert_str(r["value"]).is_equal("55 m")


func test_mobility_label_is_one_of_the_locked_buckets() -> void:
	var m := ArmoryFormat.format_mobility(_revolver())
	assert_array(["Très lourde", "Lourde", "Standard", "Agile", "Très agile"]).contains([m["value"]])


func test_frag_stats() -> void:
	var rows := ArmoryFormat.format_utility(UtilityDatabase.get_by_id(UtilityDatabase.FRAG))
	assert_int(rows.size()).is_greater(0)
	assert_str(rows[0]["label"]).is_equal("Dégâts")


func test_flash_stats() -> void:
	var rows := ArmoryFormat.format_utility(UtilityDatabase.get_by_id(UtilityDatabase.FLASH))
	assert_str(rows[0]["label"]).is_equal("Éblouissement")


func test_smoke_stats() -> void:
	var rows := ArmoryFormat.format_utility(UtilityDatabase.get_by_id(UtilityDatabase.SMOKE))
	assert_str(rows[0]["label"]).is_equal("Rayon")
