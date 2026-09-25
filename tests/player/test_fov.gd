## test_fov.gd
## Spec (UX-02, docs/research/04_ui_ux.md §2.7/§3.1) : le FOV est désormais
## exprimé en HORIZONTAL à 16:9 (`Settings.fov`, défaut 103°, curseur Options
## 80-120°, comme Valorant/Overwatch 2), converti en VERTICAL pour
## `Camera3D.fov` (`keep_aspect = KEEP_HEIGHT`, défaut Godot — docs Camera3D
## "fov"/"keep_aspect") via la fonction pure `Settings.hfov_to_vfov`. Les
## effets de FOV dynamique (sprint/slide/survitesse, `PlayerCamera._update_fov`)
## sont plafonnés en cumul à `PlayerCamera.MAX_DYNAMIC_FOV_BONUS` (5°) et
## désactivables via `Settings.fov_effects_enabled`. Les anciens réglages
## sauvegardés (FOV vertical, défaut v1 = 90°) sont migrés vers le défaut v2
## horizontal (103°), voir `Settings.migrate_fov` — même principe que
## `Settings.migrate_enemy_color` (tests/ui/test_settings_migration.gd).
extends GdUnitTestSuite

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const REF_ASPECT := 16.0 / 9.0

var _next_offset_index := 0


func _offset() -> Vector3:
	var o := Vector3(float(_next_offset_index) * 60.0, 0.0, 0.0)
	_next_offset_index += 1
	return o


## Instance réelle du joueur, spawnée comme un BOT (autorité serveur — même
## méthode que tests/player/test_capsule_per_player.gd::_bot_player) : c'est
## la façon la plus simple d'obtenir un `PlayerController` complet (donc un
## `%Camera3D` porté par `PlayerCamera.gd`) sans dépendre d'un pair réseau.
func _bot_player(pos: Vector3) -> PlayerController:
	var player: PlayerController = PLAYER_SCENE.instantiate()
	player.name = str(PlayerController.BOT_ID_START + _next_offset_index)
	player.set("is_bot", true)
	player.position = pos
	player.set("spawn_point", pos)
	add_child(player)
	auto_free(player)
	return player


# --------------------------------------------------------- hfov_to_vfov (pure)

func test_hfov_to_vfov_103_at_16_9_is_about_70_5() -> void:
	# Critère d'acceptation UX-02 : hfov_to_vfov(103, 16/9) = 70,5 ± 0,1.
	assert_float(Settings.hfov_to_vfov(103.0, REF_ASPECT)).is_equal_approx(70.5, 0.1)


func test_hfov_to_vfov_narrower_aspect_gives_a_larger_vertical_fov() -> void:
	# Hor+ (KEEP_HEIGHT) : à FOV horizontal fixé, un écran moins large (4:3)
	# doit donner un FOV vertical PLUS GRAND qu'à 16:9 (la hauteur "gagne"
	# quand la largeur diminue, docs Godot Camera3D "keep_aspect").
	var v_16_9 := Settings.hfov_to_vfov(103.0, REF_ASPECT)
	var v_4_3 := Settings.hfov_to_vfov(103.0, 4.0 / 3.0)
	assert_float(v_4_3).is_greater(v_16_9)


func test_hfov_to_vfov_is_the_inverse_of_vfov_to_hfov_relation() -> void:
	# Aller-retour : convertir un FOV horizontal en vertical puis reformer le
	# FOV horizontal via la même relation (tan(h/2) = tan(v/2) * aspect) doit
	# redonner la valeur de départ — garde contre un signe/inversion d'aspect.
	var vfov := Settings.hfov_to_vfov(103.0, REF_ASPECT)
	var rebuilt_hfov := rad_to_deg(2.0 * atan(tan(deg_to_rad(vfov) * 0.5) * REF_ASPECT))
	assert_float(rebuilt_hfov).is_equal_approx(103.0, 0.01)


# ------------------------------------------------------------- défauts Settings

func test_default_fov_is_103_horizontal() -> void:
	assert_float(Settings.fov).is_equal_approx(103.0, 0.01)


func test_default_fov_effects_enabled_is_true() -> void:
	assert_bool(Settings.fov_effects_enabled).is_true()


# ----------------------------------------------------------- migration v1 -> v2

func test_migrate_fov_without_h_key_resets_to_103_even_from_the_old_90_default() -> void:
	# Un fichier v1 stockait le FOV VERTICAL (défaut 90°) sans la clé
	# `fov_unit_version` : 90 "vertical" ne veut plus rien dire dans le nouveau
	# système horizontal (ce n'est pas 90° horizontal) — migration vers le
	# défaut v2 (103° horizontal), jamais une réinterprétation silencieuse.
	assert_float(Settings.migrate_fov(90.0, false)).is_equal_approx(103.0, 0.01)


func test_migrate_fov_without_h_key_resets_to_103_for_any_stored_value() -> void:
	assert_float(Settings.migrate_fov(70.0, false)).is_equal_approx(103.0, 0.01)
	assert_float(Settings.migrate_fov(120.0, false)).is_equal_approx(103.0, 0.01)


func test_migrate_fov_with_h_key_keeps_the_stored_value_clamped() -> void:
	assert_float(Settings.migrate_fov(95.0, true)).is_equal_approx(95.0, 0.01)
	assert_float(Settings.migrate_fov(-40.0, true)).is_equal_approx(70.0, 0.01)
	assert_float(Settings.migrate_fov(1000.0, true)).is_equal_approx(120.0, 0.01)


# --------------------------------------------------- dynamic_fov_bonus (pure)

func test_dynamic_fov_bonus_is_zero_when_effects_disabled_even_during_sprint() -> void:
	var cfg := MovementConfig.new()
	assert_float(PlayerCamera.dynamic_fov_bonus("Sprint", 0.0, cfg, false)).is_equal_approx(0.0, 0.001)


func test_dynamic_fov_bonus_is_zero_when_idle_with_no_overspeed() -> void:
	var cfg := MovementConfig.new()
	assert_float(PlayerCamera.dynamic_fov_bonus("Idle", -3.0, cfg, true)).is_equal_approx(0.0, 0.001)


func test_dynamic_fov_bonus_sprint_slide_and_overspeed_combined_never_exceed_5_degrees() -> void:
	# Valeurs par défaut de MovementConfig (sprint_fov_add=5, slide_fov_add=9,
	# speed_fov_add=6) dépasseraient largement 5° une fois cumulées avec une
	# grosse survitesse : le plafond DOIT s'appliquer, quel que soit l'état.
	var cfg := MovementConfig.new()
	assert_float(PlayerCamera.dynamic_fov_bonus("Sprint", 999.0, cfg, true)).is_less_equal(5.0)
	assert_float(PlayerCamera.dynamic_fov_bonus("Slide", 999.0, cfg, true)).is_less_equal(5.0)


func test_dynamic_fov_bonus_sprint_alone_stays_within_the_5_degree_cap() -> void:
	var cfg := MovementConfig.new()
	var bonus := PlayerCamera.dynamic_fov_bonus("Sprint", 0.0, cfg, true)
	assert_float(bonus).is_greater(0.0)
	assert_float(bonus).is_less_equal(5.0)


# -------------------------------------------------- caméra réelle (intégration)

func test_camera_fov_at_launch_is_about_70_5_vertical_keep_height() -> void:
	# Critère d'acceptation UX-02 : au lancement (Settings.fov par défaut =
	# 103° horizontal), la Camera3D du joueur a un fov ≈ 70,5° (vertical,
	# keep_aspect = KEEP_HEIGHT est le défaut Godot, jamais changé ici).
	var player := _bot_player(_offset())
	await get_tree().physics_frame

	assert_int(player.camera.keep_aspect).append_failure_message(
		"KEEP_HEIGHT attendu (défaut Godot) : Camera3D.fov doit rester vertical"
	).is_equal(Camera3D.KEEP_HEIGHT)
	assert_float(player.camera.fov).append_failure_message(
		"fov = %.3f, attendu ≈ 70,5° (hfov_to_vfov(103, 16/9))" % player.camera.fov
	).is_equal_approx(70.5, 0.1)


func test_update_fov_converges_to_base_plus_bonus_during_sprint_when_effects_enabled() -> void:
	var player := _bot_player(_offset())
	await get_tree().physics_frame
	# Cast explicite : `player.camera` est typé `Camera3D` (PlayerController.gd) ;
	# `_update_fov` n'existe que sur le script `PlayerCamera` qu'il porte.
	var cam := player.camera as PlayerCamera
	var original_effects := Settings.fov_effects_enabled
	Settings.fov_effects_enabled = true
	player.state_machine.current_name = "Sprint"

	var dt := 1.0 / 60.0
	for i in range(90):  # largement assez pour que le lerp exponentiel converge
		cam._update_fov(dt)

	var expected := Settings.hfov_to_vfov(Settings.fov, REF_ASPECT) + player.config.sprint_fov_add
	assert_float(cam.fov).append_failure_message(
		"fov = %.3f, attendu ≈ base + sprint_fov_add = %.3f" % [cam.fov, expected]
	).is_equal_approx(expected, 0.05)

	Settings.fov_effects_enabled = original_effects


func test_update_fov_ignores_sprint_bonus_when_effects_disabled() -> void:
	var player := _bot_player(_offset())
	await get_tree().physics_frame
	var cam := player.camera as PlayerCamera
	var original_effects := Settings.fov_effects_enabled
	Settings.fov_effects_enabled = false
	player.state_machine.current_name = "Sprint"

	var dt := 1.0 / 60.0
	for i in range(90):
		cam._update_fov(dt)

	var base := Settings.hfov_to_vfov(Settings.fov, REF_ASPECT)
	assert_float(cam.fov).append_failure_message(
		"« Effets de FOV » à off doit supprimer le bonus de sprint : fov = %.3f, attendu ≈ base = %.3f"
			% [cam.fov, base]
	).is_equal_approx(base, 0.05)

	Settings.fov_effects_enabled = original_effects


func test_update_fov_caps_sprint_plus_overspeed_bonus_at_5_degrees() -> void:
	var player := _bot_player(_offset())
	await get_tree().physics_frame
	var cam := player.camera as PlayerCamera
	var original_effects := Settings.fov_effects_enabled
	Settings.fov_effects_enabled = true
	player.state_machine.current_name = "Sprint"
	player.velocity = Vector3(200.0, 0.0, 0.0)  # survitesse énorme, avec le sprint

	var dt := 1.0 / 60.0
	for i in range(90):
		cam._update_fov(dt)

	var base := Settings.hfov_to_vfov(Settings.fov, REF_ASPECT)
	assert_float(cam.fov).append_failure_message(
		"sprint + slide + survitesse ne doivent jamais ajouter plus de 5° : fov = %.3f, base = %.3f, delta = %.3f"
			% [cam.fov, base, cam.fov - base]
	).is_less_equal(base + 5.05)  # petite marge pour la convergence du lerp

	Settings.fov_effects_enabled = original_effects
