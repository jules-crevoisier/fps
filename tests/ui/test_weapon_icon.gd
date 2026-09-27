## test_weapon_icon.gd
## Mappage nom d'arme/grenade -> radical d'icône (assets/ui/icons/), partagé
## par AmmoHUD/InventoryHUD/KillFeed — voir scripts/ui/hud/WeaponIcon.gd.
extends GdUnitTestSuite


func test_stem_for_known_weapons() -> void:
	assert_str(WeaponIcon.stem_for("RAVAGE")).is_equal("ravage")
	assert_str(WeaponIcon.stem_for("Revolver")).is_equal("revolver")
	assert_str(WeaponIcon.stem_for("Revolver Cowboy")).is_equal("revolver")


func test_stem_for_unknown_weapon_is_empty() -> void:
	assert_str(WeaponIcon.stem_for("PETIT GUN")).is_equal("")


func test_sil_and_sticker_suffixes() -> void:
	assert_str(WeaponIcon.sil("RAVAGE")).is_equal("ravage_sil")
	assert_str(WeaponIcon.sticker("RAVAGE")).is_equal("ravage_sticker")
	assert_str(WeaponIcon.sil("PETIT GUN")).is_equal("")


func test_grenade_stem() -> void:
	assert_str(WeaponIcon.grenade_stem(UtilityDatabase.FRAG)).is_equal("frag")
	assert_str(WeaponIcon.grenade_stem(UtilityDatabase.FLASH)).is_equal("flash")
	assert_str(WeaponIcon.grenade_stem(UtilityDatabase.SMOKE)).is_equal("smoke")


func test_icon_for_kill_feed_falls_back_to_kill_picto() -> void:
	assert_str(WeaponIcon.icon_for_kill_feed("RAVAGE")).is_equal("ravage_sil")
	assert_str(WeaponIcon.icon_for_kill_feed("Une capacité future")).is_equal("kill")
