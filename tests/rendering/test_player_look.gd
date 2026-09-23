## test_player_look.gd
## Spec (contrat R2, "PlayerLook (R-A)") : relation allié/ennemi RELATIVE au
## joueur local (même équipe => allié) et couleur de rim correspondante —
## logique pure, extraite de la résolution du nœud pour rester testable sans
## arbre de scène / réseau. Couleurs mises à jour pour design.md v2 §9 :
## Cartoon.enemy_color() rend Magenta/Citron (plus rouge/jaune/magenta v1).
extends GdUnitTestSuite


func test_same_team_is_ally() -> void:
	assert_bool(PlayerLook.is_ally(0, 0)).is_true()
	assert_bool(PlayerLook.is_ally(1, 1)).is_true()


func test_different_team_is_not_ally() -> void:
	assert_bool(PlayerLook.is_ally(0, 1)).is_false()
	assert_bool(PlayerLook.is_ally(1, 0)).is_false()


func test_rim_color_for_ally_is_ally_color() -> void:
	assert_that(PlayerLook.rim_color_for(true)).is_equal(Cartoon.ally_color())


func test_rim_color_for_enemy_follows_settings_enemy_color() -> void:
	var orig := Settings.enemy_color
	Settings.enemy_color = 1
	assert_that(PlayerLook.rim_color_for(false)).is_equal(Color("c8ff1f"))
	Settings.enemy_color = orig


func test_rim_color_ally_and_enemy_are_always_distinct() -> void:
	var orig := Settings.enemy_color
	for i in range(2):
		Settings.enemy_color = i
		assert_bool(PlayerLook.rim_color_for(true) == PlayerLook.rim_color_for(false)).is_false()
	Settings.enemy_color = orig


## Accessibilité (design.md §12) : le contour ennemi est 50% plus épais que
## l'allié, indépendamment de la couleur choisie — un repère qui marche aussi
## pour les daltoniens.
func test_enemy_outline_is_fifty_percent_thicker_than_ally() -> void:
	var ally_px := PlayerLook.outline_px_for(true)
	var enemy_px := PlayerLook.outline_px_for(false)
	assert_float(enemy_px).is_equal_approx(ally_px * 1.5, 0.001)
