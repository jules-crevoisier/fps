## test_camera_shake_wiring.gd
## Spec GF-29 (docs/research/01_game_feel.md §2.1/§3, branchement en jeu) :
## GF-08 a livré `CameraShake` + 4 méthodes publiques de `PlayerCamera`
## (`add_shot_trauma`/`add_damage_trauma`/`add_explosion_trauma`/
## `punch_fov_heavy`) que PERSONNE n'appelait — aucun effet en jeu. MV-03 a
## livré `MovementConfig.stun_fire_spread_add`/`GameMode.fall_stun_enabled`
## que PERSONNE ne lisait. Ce fichier teste le CÂBLAGE, joueur LOCAL
## uniquement pour la caméra (jamais un bot ni un pair distant) :
##  1. tir -> `add_shot_trauma` (montant PAR ARME, borné [0.08, 0.25] —
##     `WeaponFeel.shot_trauma_amount`, dérivé de `WeaponConfig.recoil_vertical`
##     existant plutôt qu'un nouveau champ dédié, WeaponConfig.gd étant hors de
##     mon périmètre de fichiers pour cette tâche) ;
##  2. dégâts reçus -> `add_damage_trauma` (0.3 fixe), câblé sur
##     `Health.hit_reaction` du joueur LOCAL (PlayerController._ready) ;
##  3. kill confirmé par le joueur local -> `punch_fov_heavy` ;
##  4. `Weapon._can_act()` n'exclut plus "Stun" (tir/visée permis, +3° de
##     dispersion via `WeaponFeel.total_spread_deg`) — Dive/Roll restent exclus ;
##  5. les réglages de confort (`Settings.camera_shake_enabled`/
##     `reduced_motion`, déjà livrés par GF-08 — `CameraShake.
##     effective_intensity`) continuent de supprimer TOUTE rotation même une
##     fois ce câblage en place.
## Le gating `GameMode.fall_stun_enabled` (déclenchement du stun lui-même,
## PlayerController._maybe_stun) est testé dans tests/player/test_fall_stun.gd
## (fichier possédé par cette même tâche).
##
## Style des doubles : joueur RÉEL (scenes/player/player.tscn, autorité
## SERVEUR sans réseau réel), méthode `_human_player`/`_bot_player` reprise de
## tests/agents/test_vanne_kit.gd::_human_player (id "1" = même autorité que
## le process de test headless, donc `is_local_human()` vrai) et de
## tests/player/test_fov.gd::_bot_player (`is_bot = true`, `is_local_human()`
## faux). Appels DIRECTS aux méthodes contractuelles privées
## (`Weapon._fire_local`/`_spawn_damage_number`/`_can_act`) plutôt qu'un
## déclenchement organique par `player.input` — même choix que
## tests/player/test_fov.gd (`cam._update_fov`) pour rester déterministe : le
## rendu-frame (`_process`, PlayerCamera) tournerait sinon de façon
## non-déterministe entre l'action et l'assertion en tête headless et
## ferait dériver le trauma par la décroissance (`CameraShake.
## decayed_trauma`), rendant les bornes numériques fragiles.
extends GdUnitTestSuite

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")

var _next_offset_index := 0


## Effets cosmétiques de `Weapon._fire_local`/`_spawn_damage_number`
## (traceur, chiffre de dégâts) posent leurs nœuds sur `get_tree().
## current_scene` — jamais nul en vrai match, mais nul par défaut en tête
## headless — même garde que tests/combat/test_fire_while_sprinting.gd.
func before_test() -> void:
	get_tree().current_scene = self


func _offset() -> Vector3:
	var o := Vector3(float(_next_offset_index) * 60.0, 0.0, 0.0)
	_next_offset_index += 1
	return o


## Joueur RÉEL non-bot, avec l'id de pair 1 -- "l'hôte" (PlayerController.
## _enter_tree : `authority_id := 1 if owner_id >= BOT_ID_START else owner_id`,
## donc id 1 = authority 1 = le même pair que le process de test headless) :
## `is_local_human()` renvoie vrai -- même méthode que
## tests/agents/test_vanne_kit.gd::_human_player. Au plus UN par test (les
## noms de nœuds doivent rester uniques).
func _human_player(pos: Vector3) -> PlayerController:
	var player: PlayerController = PLAYER_SCENE.instantiate()
	player.name = "1"
	player.position = pos
	player.set("spawn_point", pos)
	add_child(player)
	auto_free(player)
	return player


## Joueur RÉEL simulé en BOT (autorité SERVEUR, `is_bot = true` ->
## `is_local_human()` faux malgré l'autorité partagée) -- même méthode que
## tests/player/test_fov.gd::_bot_player.
func _bot_player(pos: Vector3) -> PlayerController:
	var player: PlayerController = PLAYER_SCENE.instantiate()
	player.name = str(PlayerController.BOT_ID_START + _next_offset_index)
	_next_offset_index += 1
	player.set("is_bot", true)
	player.position = pos
	player.set("spawn_point", pos)
	add_child(player)
	auto_free(player)
	return player


# ======================================================================
#  WeaponFeel.shot_trauma_amount (pure) -- trauma de tir borné PAR ARME
# ======================================================================

func test_shot_trauma_amount_stays_within_camera_shake_bounds() -> void:
	var cfg := WeaponConfig.new()
	cfg.recoil_vertical = 0.9  # Marqueur (resources/weapons/marqueur.tres)
	var t := WeaponFeel.shot_trauma_amount(cfg)
	assert_float(t).append_failure_message(
		"le trauma de tir doit rester dans [%.2f, %.2f] (contrat GF-08) -- obtenu %.4f"
			% [CameraShake.SHOT_TRAUMA_MIN, CameraShake.SHOT_TRAUMA_MAX, t]
	).is_greater_equal(CameraShake.SHOT_TRAUMA_MIN)
	assert_float(t).is_less_equal(CameraShake.SHOT_TRAUMA_MAX)


func test_shot_trauma_amount_extremes_clamp_to_the_camera_shake_bounds() -> void:
	var low_cfg := WeaponConfig.new()
	low_cfg.recoil_vertical = 0.01  # bien en-dessous de la plage de référence
	var high_cfg := WeaponConfig.new()
	high_cfg.recoil_vertical = 50.0  # bien au-dessus (sniper extrême)

	assert_float(WeaponFeel.shot_trauma_amount(low_cfg)).append_failure_message(
		"un recul très faible doit reborner au minimum (0.08), jamais en dessous"
	).is_equal_approx(CameraShake.SHOT_TRAUMA_MIN, 0.001)
	assert_float(WeaponFeel.shot_trauma_amount(high_cfg)).append_failure_message(
		"un recul très fort doit reborner au maximum (0.25), jamais au-dessus"
	).is_equal_approx(CameraShake.SHOT_TRAUMA_MAX, 0.001)


func test_shot_trauma_amount_grows_with_the_weapon_recoil() -> void:
	var soft_cfg := WeaponConfig.new()
	soft_cfg.recoil_vertical = 0.35  # Pistolet/Éclair (SMG)
	var heavy_cfg := WeaponConfig.new()
	heavy_cfg.recoil_vertical = 2.2  # Faucheur (sniper)

	assert_float(WeaponFeel.shot_trauma_amount(heavy_cfg)).append_failure_message(
		"une arme au recul plus fort doit secouer davantage la caméra qu'une arme légère"
	).is_greater(WeaponFeel.shot_trauma_amount(soft_cfg))


# ======================================================================
#  WeaponFeel.total_spread_deg -- dispersion additionnelle pendant le Stun
# ======================================================================

func test_total_spread_deg_adds_the_stun_spread_bonus() -> void:
	var t := WeaponFeel.total_spread_deg(2.0, 0.0, 0.0, 1.0, 3.0)
	assert_float(t).append_failure_message(
		"MV-03 : le stun doit ajouter stun_fire_spread_add (3°) à la dispersion totale"
	).is_equal_approx(5.0, 0.001)


func test_total_spread_deg_stun_bonus_defaults_to_zero_no_regression() -> void:
	# Non-régression : tout appelant existant (GameHUD.gd, tests/combat/
	# test_weapon_feel.gd, tests/agents/test_verrou_kit.gd) qui ne précise pas
	# `stun_spread` doit obtenir EXACTEMENT le même résultat qu'avant GF-29.
	var t := WeaponFeel.total_spread_deg(2.0, 1.5, 3.0)
	assert_float(t).is_equal_approx(6.5, 0.001)


# ======================================================================
#  Weapon._can_act() -- Stun débloqué (MV-03), Dive/Roll toujours exclus
# ======================================================================

func test_can_act_allows_firing_during_stun() -> void:
	var player := _bot_player(_offset())
	await get_tree().physics_frame
	var weapon := player.get_node("Weapon") as Weapon
	player.state_machine.current_name = "Stun"

	assert_bool(weapon._can_act()).append_failure_message(
		"MV-03 : le stun de chute adouci doit laisser tirer/viser (avec +dispersion), jamais un freeze total du tir"
	).is_true()


func test_can_act_still_excludes_dive_and_roll() -> void:
	var player := _bot_player(_offset())
	await get_tree().physics_frame
	var weapon := player.get_node("Weapon") as Weapon
	for blocked_state in ["Dive", "Roll"]:
		player.state_machine.current_name = blocked_state
		assert_bool(weapon._can_act()).append_failure_message(
			"%s doit rester exclu de _can_act() -- seul \"Stun\" est débloqué par MV-03/GF-29"
				% blocked_state
		).is_false()


# ======================================================================
#  (1) Tir du joueur local -> trauma borné ; tir de bot -> aucun trauma
# ======================================================================

func test_local_human_shot_adds_bounded_camera_trauma() -> void:
	var player := _human_player(_offset())
	await get_tree().physics_frame
	var weapon := player.get_node("Weapon") as Weapon
	var cam := player.camera as PlayerCamera
	# `_fire_local` lit `camera` (champ de Weapon, posé normalement par
	# `_owner_tick` -- voir sa docstring) : appel direct et déterministe de
	# `_fire_local`, donc on le pose nous-mêmes plutôt que de dépendre du
	# nombre de tics physiques déjà écoulés pour ce joueur.
	weapon.camera = player.camera
	var cfg := weapon.cfg()
	assert_object(cfg).append_failure_message("préalable du test : aucune arme équipée").is_not_null()

	weapon._fire_local(cfg)

	assert_float(cam._shake.trauma).append_failure_message(
		"un tir du joueur local doit ajouter du trauma borné [%.2f, %.2f] (obtenu %.4f)"
			% [CameraShake.SHOT_TRAUMA_MIN, CameraShake.SHOT_TRAUMA_MAX, cam._shake.trauma]
	).is_greater_equal(CameraShake.SHOT_TRAUMA_MIN)
	assert_float(cam._shake.trauma).is_less_equal(CameraShake.SHOT_TRAUMA_MAX)


func test_bot_shot_does_not_add_camera_trauma() -> void:
	var player := _bot_player(_offset())
	await get_tree().physics_frame
	var weapon := player.get_node("Weapon") as Weapon
	var cam := player.camera as PlayerCamera
	weapon.camera = player.camera  # voir test_local_human_shot_adds_bounded_camera_trauma
	var cfg := weapon.cfg()
	assert_object(cfg).append_failure_message("préalable du test : aucune arme équipée").is_not_null()

	weapon._fire_local(cfg)

	assert_float(cam._shake.trauma).append_failure_message(
		"un tir de BOT ne doit JAMAIS ajouter de trauma caméra -- un bot n'a personne devant un écran à secouer"
	).is_equal_approx(0.0, 0.0001)


# ======================================================================
#  (2) Dégâts reçus par le joueur local -> trauma fixe de 0.3
# ======================================================================

func test_local_human_taking_damage_adds_0_3_camera_trauma() -> void:
	var player := _human_player(_offset())
	await get_tree().physics_frame
	var cam := player.camera as PlayerCamera
	var hp := player.get_node("Health") as Health

	# Appel DIRECT du handler RPC (même fonction que `Health._notify_hit_
	# reaction.rpc(headshot)` déclenche à distance -- voir sa docstring) :
	# émet le signal `hit_reaction`, câblé côté PlayerController._ready pour
	# l'humain local uniquement.
	hp._notify_hit_reaction(false)

	assert_float(cam._shake.trauma).append_failure_message(
		"des dégâts reçus par le joueur local doivent ajouter %.2f de trauma caméra (CameraShake.TRAUMA_DAMAGE_TAKEN)"
			% CameraShake.TRAUMA_DAMAGE_TAKEN
	).is_equal_approx(CameraShake.TRAUMA_DAMAGE_TAKEN, 0.001)


func test_bot_taking_damage_does_not_add_camera_trauma() -> void:
	# Non-régression : `Health.hit_reaction` est diffusé à TOUS les pairs (GF-10,
	# flash de hit visible par tout le monde) -- seul l'humain LOCAL doit s'y
	# être connecté pour la trauma caméra (voir PlayerController._ready, bloc
	# `if mine:`), jamais un bot.
	var player := _bot_player(_offset())
	await get_tree().physics_frame
	var cam := player.camera as PlayerCamera
	var hp := player.get_node("Health") as Health

	hp._notify_hit_reaction(false)

	assert_float(cam._shake.trauma).append_failure_message(
		"les dégâts encaissés par un BOT ne doivent ajouter aucun trauma caméra (aucun joueur local à secouer)"
	).is_equal_approx(0.0, 0.0001)


# ======================================================================
#  (3) Kill confirmé par le joueur local -> punch FOV lourd
# ======================================================================

func test_local_human_kill_confirmation_triggers_a_heavy_fov_punch() -> void:
	var player := _human_player(_offset())
	await get_tree().physics_frame
	var weapon := player.get_node("Weapon") as Weapon
	var cam := player.camera as PlayerCamera

	weapon._spawn_damage_number(Vector3.ZERO, 40.0, false, true, 9999)

	assert_float(cam._shake.fov_offset_deg(1.0)).append_failure_message(
		"un kill confirmé par le joueur local doit déclencher le punch FOV lourd de GF-08 (%.2f°)"
			% CameraShake.PUNCH_FOV_HEAVY_DEG
	).is_equal_approx(CameraShake.PUNCH_FOV_HEAVY_DEG, 0.01)


func test_local_human_non_kill_hit_does_not_trigger_a_fov_punch() -> void:
	var player := _human_player(_offset())
	await get_tree().physics_frame
	var weapon := player.get_node("Weapon") as Weapon
	var cam := player.camera as PlayerCamera

	weapon._spawn_damage_number(Vector3.ZERO, 10.0, false, false, 9999)

	assert_float(cam._shake.fov_offset_deg(1.0)).append_failure_message(
		"un hit SANS kill ne doit déclencher aucun punch FOV"
	).is_equal_approx(0.0, 0.001)


func test_bot_kill_confirmation_does_not_trigger_a_fov_punch() -> void:
	var player := _bot_player(_offset())
	await get_tree().physics_frame
	var weapon := player.get_node("Weapon") as Weapon
	var cam := player.camera as PlayerCamera

	weapon._spawn_damage_number(Vector3.ZERO, 40.0, false, true, 9999)

	assert_float(cam._shake.fov_offset_deg(1.0)).append_failure_message(
		"un kill confirmé par un BOT tireur ne doit déclencher aucun punch FOV (aucun écran local)"
	).is_equal_approx(0.0, 0.001)


# ======================================================================
#  (5) Confort : camera_shake_enabled=false / reduced_motion -> AUCUNE rotation
#  (CameraShake.effective_intensity, déjà livré par GF-08) même une fois ce
#  câblage GF-29 en place -- le trauma est ajouté, mais ne produit aucun effet.
# ======================================================================

func test_shot_trauma_produces_no_rotation_when_camera_shake_disabled() -> void:
	var player := _human_player(_offset())
	await get_tree().physics_frame
	var weapon := player.get_node("Weapon") as Weapon
	var cam := player.camera as PlayerCamera
	weapon.camera = player.camera  # voir test_local_human_shot_adds_bounded_camera_trauma
	var original_enabled := Settings.camera_shake_enabled
	Settings.camera_shake_enabled = false

	weapon._fire_local(weapon.cfg())

	var intensity := CameraShake.effective_intensity(
		Settings.camera_shake_intensity, Settings.camera_shake_enabled, Settings.reduced_motion)
	assert_vector(cam._shake.rotation_offset_deg(intensity)).append_failure_message(
		"secousses de caméra désactivées : le trauma de tir ne doit produire AUCUNE rotation"
	).is_equal(Vector3.ZERO)

	Settings.camera_shake_enabled = original_enabled


func test_shot_trauma_produces_no_rotation_with_reduced_motion() -> void:
	var player := _human_player(_offset())
	await get_tree().physics_frame
	var weapon := player.get_node("Weapon") as Weapon
	var cam := player.camera as PlayerCamera
	weapon.camera = player.camera  # voir test_local_human_shot_adds_bounded_camera_trauma
	var original_reduced := Settings.reduced_motion
	Settings.reduced_motion = true

	weapon._fire_local(weapon.cfg())

	var intensity := CameraShake.effective_intensity(
		Settings.camera_shake_intensity, Settings.camera_shake_enabled, Settings.reduced_motion)
	assert_vector(cam._shake.rotation_offset_deg(intensity)).append_failure_message(
		"mouvement réduit : le trauma de tir ne doit produire AUCUNE rotation"
	).is_equal(Vector3.ZERO)

	Settings.reduced_motion = original_reduced
