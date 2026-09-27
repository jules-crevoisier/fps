## test_ko_banner.gd
## Spec (contrat lead 2026-09-27, HUD en jeu, point 7 "KoBanner") : bandeau
## JAUNE incliné "K.O. !" (encre... ROUGE en display) + nom de la victime,
## centré horizontalement, haut ~780 px (sous la zone centrale) ; apparition
## en pop (UiTokens.POP_S), tenue 1.2 s, fondu 0.2 s.
extends GdUnitTestSuite

const KoBanner := preload("res://scripts/ui/hud/KoBanner.gd")


func _banner() -> KoBanner:
	var b: KoBanner = auto_free(KoBanner.new())
	add_child(b)
	return b


func test_hidden_by_default() -> void:
	var b := _banner()
	assert_bool(b.visible).is_false()


func test_show_ko_displays_victim_name() -> void:
	var b := _banner()
	b.show_ko("Crapaud")
	assert_bool(b.visible).is_true()
	assert_str(b._victim_label.text).is_equal("CRAPAUD")
	assert_bool(b._victim_label.visible).is_true()


func test_show_ko_without_victim_name_hides_the_name_label() -> void:
	var b := _banner()
	b.show_ko("")
	assert_bool(b._victim_label.visible).is_false()


func test_ko_label_text_and_color() -> void:
	var b := _banner()
	assert_str(b._ko_label.text).is_equal("K.O. !")
	assert_bool(b._ko_label.label_settings.font_color.is_equal_approx(UiTokens.RED)).is_true()


func test_plate_sits_below_the_center_zone() -> void:
	var b := _banner()
	assert_float(KoBanner.TOP_Y).is_greater(HudFormat.center_zone_rect(Vector2(1920, 1080)).end.y)
