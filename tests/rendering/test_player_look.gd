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


# ============================================================================
# GF-10 « Réaction visible de la cible » : flash de hit (rim blanc/rouge, 70 ms).
# ============================================================================

func test_hit_flash_color_is_white_for_a_normal_hit() -> void:
	assert_that(PlayerLook.hit_flash_color(false)).is_equal(Color.WHITE)


func test_hit_flash_color_is_red_for_a_headshot() -> void:
	assert_that(PlayerLook.hit_flash_color(true)).is_equal(Color("c8322b"))


## docs/style/tokens.json color.accents.red — même rouge que le contour/le
## chiffre de dégâts headshot (Weapon._spawn_damage_number), pas un rouge
## inventé pour ce seul flash.
func test_hit_flash_headshot_color_matches_style_token_red_accent() -> void:
	assert_that(PlayerLook.hit_flash_color(true)).is_equal(Color("c8322b"))


func test_hit_flash_duration_is_seventy_milliseconds() -> void:
	assert_float(PlayerLook.HIT_FLASH_DURATION_S).is_equal_approx(0.07, 0.0001)


func test_on_hit_reaction_sets_rim_to_flash_color_and_strength() -> void:
	var look: PlayerLook = auto_free(PlayerLook.new())
	var mesh: MeshInstance3D = auto_free(MeshInstance3D.new())
	look._mesh = mesh

	look._on_hit_reaction(false)

	assert_that(mesh.get_instance_shader_parameter("rim_color")).append_failure_message(
		"un dégât normal doit poser un rim BLANC sur le mesh de la victime"
	).is_equal(Color.WHITE)
	assert_float(mesh.get_instance_shader_parameter("rim_strength")).is_equal_approx(
		PlayerLook.HIT_FLASH_STRENGTH, 0.001
	)


func test_on_hit_reaction_headshot_sets_rim_to_red() -> void:
	var look: PlayerLook = auto_free(PlayerLook.new())
	var mesh: MeshInstance3D = auto_free(MeshInstance3D.new())
	look._mesh = mesh

	look._on_hit_reaction(true)

	assert_that(mesh.get_instance_shader_parameter("rim_color")).append_failure_message(
		"un headshot doit poser un rim ROUGE (pas la couleur du coup normal) sur le mesh de la victime"
	).is_equal(Color("c8322b"))


## Chaque hit relance le compte à rebours du flash à 70 ms pleines, même si un
## flash précédent était déjà en cours de fondu (voir `_drive_hit_flash`).
func test_on_hit_reaction_restarts_the_flash_timer_at_full_duration() -> void:
	var look: PlayerLook = auto_free(PlayerLook.new())
	var mesh: MeshInstance3D = auto_free(MeshInstance3D.new())
	look._mesh = mesh

	look._on_hit_reaction(false)
	assert_float(look._flash_time_left).is_equal_approx(PlayerLook.HIT_FLASH_DURATION_S, 0.0001)

	look._flash_time_left = 0.01  # flash presque terminé
	look._on_hit_reaction(true)

	assert_float(look._flash_time_left).append_failure_message(
		"un nouveau hit doit relancer le flash à HIT_FLASH_DURATION_S pleine, pas prolonger le fondu en cours"
	).is_equal_approx(PlayerLook.HIT_FLASH_DURATION_S, 0.0001)


## Sans mesh résolu (corps 3D pas encore chargé, voir `_resolve`) : aucun
## crash, le hit reste simplement sans effet visuel cette fois-ci.
func test_on_hit_reaction_without_a_resolved_mesh_does_not_crash() -> void:
	var look: PlayerLook = auto_free(PlayerLook.new())
	look._on_hit_reaction(false)
	assert_float(look._flash_time_left).is_equal(0.0)
