## test_ammo_hud.gd
## Spec (contrat lead 2026-09-27, HUD en jeu, point 2 "AmmoHUD") : icône
## autocollante de l'arme, munitions du chargeur en display T_4XL + "/
## réserve" T_L, pastilles une par balle (mag_size <= 12), état de
## rechargement ("RECHARGE"), chargeur vide -> chiffre ROUGE, ligne d'indice
## avec puces de touche (Éventail pour une arme FAN uniquement + Recharger),
## visible seulement 5 s après l'équipement ou sous 1/3 du chargeur ; une
## grenade équipée affiche son autocollant + son compte à la place.
extends GdUnitTestSuite

const AmmoHUD := preload("res://scripts/ui/hud/AmmoHUD.gd")


func _hud() -> AmmoHUD:
	var hud: AmmoHUD = auto_free(AmmoHUD.new())
	add_child(hud)
	return hud


# ---- pip_states (pure) ----

func test_pip_states_matches_mockup_5_over_6() -> void:
	var pips := AmmoHUD.pip_states(5, 6)
	assert_int(pips.size()).is_equal(6)
	for i in 5:
		assert_bool(pips[i]).append_failure_message("pastille %d ne doit pas être dépensée" % i).is_false()
	assert_bool(pips[5]).append_failure_message("la dernière pastille (chargeur 5/6) doit être dépensée").is_true()


func test_pip_states_full_magazine_is_all_unspent() -> void:
	var pips := AmmoHUD.pip_states(6, 6)
	for p in pips:
		assert_bool(p).is_false()


func test_pip_states_empty_magazine_is_all_spent() -> void:
	var pips := AmmoHUD.pip_states(0, 6)
	for p in pips:
		assert_bool(p).is_true()


# ---- show_pips (pure) ----

func test_show_pips_only_under_or_equal_12() -> void:
	assert_bool(AmmoHUD.show_pips(6)).is_true()
	assert_bool(AmmoHUD.show_pips(12)).is_true()
	assert_bool(AmmoHUD.show_pips(30)).is_false()


# ---- show_hint (pure) ----

func test_show_hint_within_first_5_seconds() -> void:
	assert_bool(AmmoHUD.show_hint(0.0, 30, 30)).is_true()
	assert_bool(AmmoHUD.show_hint(4.99, 30, 30)).is_true()
	assert_bool(AmmoHUD.show_hint(5.5, 30, 30)).is_false()


func test_show_hint_when_low_on_ammo() -> void:
	# 1/3 de 30 = 10.
	assert_bool(AmmoHUD.show_hint(30.0, 10, 30)).is_true()
	assert_bool(AmmoHUD.show_hint(30.0, 11, 30)).is_false()


# ---- is_empty (pure) ----

func test_is_empty() -> void:
	assert_bool(AmmoHUD.is_empty(0)).is_true()
	assert_bool(AmmoHUD.is_empty(1)).is_false()


# ---- nœuds ----

func test_update_ammo_sets_labels() -> void:
	var hud := _hud()
	hud.update_ammo(5, 36, 6)
	assert_str(hud._ammo_label.text).is_equal("5")
	assert_str(hud._reserve_label.text).is_equal("/ 36")


func test_update_ammo_builds_pips_when_small_magazine() -> void:
	var hud := _hud()
	hud.update_ammo(5, 36, 6)
	assert_int(hud._pips.size()).is_equal(6)
	assert_bool(hud._pips_row.visible).is_true()


func test_update_ammo_hides_pips_for_large_magazine() -> void:
	var hud := _hud()
	hud.update_ammo(30, 90, 30)
	assert_bool(hud._pips_row.visible).is_false()


func test_update_ammo_empty_magazine_turns_red() -> void:
	var hud := _hud()
	hud.update_ammo(0, 36, 6)
	assert_bool(hud._ammo_label.label_settings.font_color.is_equal_approx(UiTokens.RED)).is_true()


func test_set_reloading_shows_recharge_label() -> void:
	var hud := _hud()
	hud.set_reloading(true)
	assert_bool(hud._reload_label.visible).is_true()
	hud.set_reloading(false)
	assert_bool(hud._reload_label.visible).is_false()


func test_set_weapon_shows_fan_hint_only_for_fan_weapons() -> void:
	var hud := _hud()
	var fan_cfg := WeaponConfig.new()
	fan_cfg.weapon_name = "Revolver"
	fan_cfg.alt_fire_mode = WeaponConfig.AltFireMode.FAN
	fan_cfg.fan_fire_rate = 3.0
	hud.set_weapon(fan_cfg)
	assert_bool(hud._fan_hint.visible).is_true()

	var normal_cfg := WeaponConfig.new()
	normal_cfg.weapon_name = "Ravage"
	hud.set_weapon(normal_cfg)
	assert_bool(hud._fan_hint.visible).is_false()


func test_show_grenade_switches_icon_and_count() -> void:
	var hud := _hud()
	hud.show_grenade(UtilityDatabase.FRAG, 2)
	assert_str(hud._ammo_label.text).is_equal("2")
	assert_bool(hud._reserve_label.visible).is_false()
