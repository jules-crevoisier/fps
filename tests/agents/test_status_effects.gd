## test_status_effects.gd
## Spec AGT-01 (docs/research/10_ammo_kits_input.md §3.5, "Socle commun à
## construire") : StatusEffects (multiplicateur de vitesse, verrou de saut,
## multiplicateur de contrôle subi -- chacun expirant en compte à rebours),
## et son intégration dans AbilityController/PlayerController.
##
## Critère d'acceptation "Statuts poussés au propriétaire en <= 1 tick, y
## compris pour un bot en appel direct" : couvert par les tests
## `test_server_apply_*_pushes_to_the_owner_immediately` ci-dessous -- pour un
## bot/hôte (autorité serveur partagée, voir PlayerController.is_local_human),
## `_push_status` fait un appel DIRECT et synchrone (pas de RPC, pas d'attente
## d'un tick réseau) : `_owner_status` reflète donc la correction dès le retour
## de l'appel `server_apply_*`, dans le MÊME tick que l'application côté serveur.
##
## Style des doubles : bot réel (`scenes/player/player.tscn`, autorité SERVEUR
## sans réseau réel), comme tests/agents/test_round_props_cleanup.gd::_bot_player.
extends GdUnitTestSuite

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")

var _next_offset_index := 0


func _offset() -> Vector3:
	var o := Vector3(float(_next_offset_index) * 60.0, 0.0, 0.0)
	_next_offset_index += 1
	return o


func _bot_player(pos: Vector3) -> PlayerController:
	var player: PlayerController = PLAYER_SCENE.instantiate()
	player.name = str(PlayerController.BOT_ID_START + _next_offset_index)
	player.set("is_bot", true)
	player.position = pos
	player.set("spawn_point", pos)
	add_child(player)
	auto_free(player)
	return player


func _abilities(player: PlayerController) -> AbilityController:
	return player.get_node("Abilities") as AbilityController


# ===================================================== StatusEffects (pur)

func test_speed_mult_is_neutral_by_default() -> void:
	var st := StatusEffects.new()
	assert_float(st.speed_mult()).is_equal_approx(1.0, 0.001)


func test_speed_mult_applies_while_the_duration_has_not_elapsed() -> void:
	var st := StatusEffects.new()
	st.apply_speed_mult(0.5, 1.5)
	assert_float(st.speed_mult()).is_equal_approx(0.5, 0.001)

	st.tick(1.4)
	assert_float(st.speed_mult()).is_equal_approx(0.5, 0.001)


func test_speed_mult_reverts_to_neutral_after_the_duration_elapses() -> void:
	var st := StatusEffects.new()
	st.apply_speed_mult(0.5, 1.5)
	st.tick(1.5)
	assert_float(st.speed_mult()).append_failure_message(
		"Glu de Verrou : -50% doit s'arrêter net après 1.5 s, pas continuer"
	).is_equal_approx(1.0, 0.001)


func test_speed_mult_reapplication_replaces_the_current_effect() -> void:
	var st := StatusEffects.new()
	st.apply_speed_mult(0.5, 1.5)
	st.tick(1.0)
	st.apply_speed_mult(1.1, 2.0)  # ex. Mèche courte de Vif, +10% pendant 2 s
	assert_float(st.speed_mult()).is_equal_approx(1.1, 0.001)
	st.tick(1.9)
	assert_float(st.speed_mult()).is_equal_approx(1.1, 0.001)
	st.tick(0.2)
	assert_float(st.speed_mult()).is_equal_approx(1.0, 0.001)


func test_jump_lock_is_false_by_default() -> void:
	var st := StatusEffects.new()
	assert_bool(st.is_jump_locked()).is_false()


func test_jump_lock_applies_then_expires() -> void:
	var st := StatusEffects.new()
	st.apply_jump_lock(1.0)
	assert_bool(st.is_jump_locked()).is_true()
	st.tick(0.9)
	assert_bool(st.is_jump_locked()).is_true()
	st.tick(0.2)
	assert_bool(st.is_jump_locked()).is_false()


func test_jump_lock_keeps_the_longer_remaining_window() -> void:
	var st := StatusEffects.new()
	st.apply_jump_lock(2.0)
	st.tick(1.0)  # il reste 1.0 s
	st.apply_jump_lock(0.3)  # plus court : ne doit PAS raccourcir le verrou en cours
	st.tick(0.9)
	assert_bool(st.is_jump_locked()).append_failure_message(
		"un second verrou plus court ne doit jamais raccourcir celui déjà en cours"
	).is_true()


func test_cc_mult_is_neutral_by_default() -> void:
	var st := StatusEffects.new()
	assert_float(st.cc_mult()).is_equal_approx(1.0, 0.001)


func test_cc_mult_applies_then_expires() -> void:
	var st := StatusEffects.new()
	st.apply_cc_mult(0.5, 3.0)
	assert_float(st.cc_mult()).is_equal_approx(0.5, 0.001)
	st.tick(3.0)
	assert_float(st.cc_mult()).is_equal_approx(1.0, 0.001)


func test_to_dict_apply_dict_round_trip() -> void:
	var st := StatusEffects.new()
	st.apply_speed_mult(0.5, 1.5)
	st.apply_jump_lock(1.0)
	st.apply_cc_mult(0.6, 3.0)
	st.tick(0.4)

	var d := st.to_dict()
	var restored := StatusEffects.new()
	restored.apply_dict(d)

	assert_float(restored.speed_mult()).is_equal_approx(st.speed_mult(), 0.001)
	assert_bool(restored.is_jump_locked()).is_equal(st.is_jump_locked())
	assert_float(restored.cc_mult()).is_equal_approx(st.cc_mult(), 0.001)


# ================================== AbilityController : poussée <= 1 tick

func test_server_apply_speed_mult_pushes_to_the_owner_immediately() -> void:
	var player := _bot_player(_offset())
	var ctrl := _abilities(player)
	await get_tree().physics_frame

	ctrl.server_apply_speed_mult(0.5, 1.5)

	assert_float(ctrl._server_status.speed_mult()).is_equal_approx(0.5, 0.001)
	assert_float(ctrl._owner_status.speed_mult()).append_failure_message(
		"pour un bot (appel direct, pas de RPC), la copie propriétaire doit déjà refléter le changement"
	).is_equal_approx(0.5, 0.001)


func test_server_apply_jump_lock_pushes_to_the_owner_immediately() -> void:
	var player := _bot_player(_offset())
	var ctrl := _abilities(player)
	await get_tree().physics_frame

	ctrl.server_apply_jump_lock(1.0)

	assert_bool(ctrl._server_status.is_jump_locked()).is_true()
	assert_bool(ctrl._owner_status.is_jump_locked()).append_failure_message(
		"server_apply_jump_lock doit pousser la correction au propriétaire, pas seulement à l'état autoritaire"
	).is_true()


func test_server_apply_cc_mult_pushes_to_the_owner_immediately() -> void:
	var player := _bot_player(_offset())
	var ctrl := _abilities(player)
	await get_tree().physics_frame

	ctrl.server_apply_cc_mult(0.5, 3.0)

	assert_float(ctrl._server_status.cc_mult()).is_equal_approx(0.5, 0.001)
	assert_float(ctrl._owner_status.cc_mult()).is_equal_approx(0.5, 0.001)


func test_status_accessor_falls_back_to_server_copy_when_no_owner_copy_exists() -> void:
	# Repli défensif (comme slot_info()) : si jamais seule la copie autoritaire
	# existe (aucune copie propriétaire construite), status() ne doit pas planter.
	var player := _bot_player(_offset())
	var ctrl := _abilities(player)
	await get_tree().physics_frame
	ctrl._owner_status = null

	ctrl.server_apply_speed_mult(0.7, 2.0)

	assert_object(ctrl.status()).is_not_null()
	assert_float(ctrl.status().speed_mult()).is_equal_approx(0.7, 0.001)


# ============================================= PlayerController : lecture

func test_ground_move_is_slowed_by_an_active_speed_mult_status() -> void:
	var player := _bot_player(_offset())
	var ctrl := _abilities(player)
	await get_tree().physics_frame
	player.wish_dir = Vector3.FORWARD
	player.velocity = Vector3.ZERO
	ctrl.server_apply_speed_mult(0.5, 1.5)

	# accel très haute pour atteindre quasi instantanément la vitesse cible sur un seul appel.
	player.ground_move(10.0, 10000.0, 75.0, 0.02)

	assert_float(player.velocity.z).append_failure_message(
		"un ralentissement de statut (0.5) doit réduire la vitesse CIBLE (10 * 0.5 = 5), pas seulement la friction"
	).is_equal_approx(-5.0, 0.05)


func test_ground_move_is_unaffected_without_any_active_status() -> void:
	var player := _bot_player(_offset())
	player.wish_dir = Vector3.FORWARD
	player.velocity = Vector3.ZERO
	await get_tree().physics_frame

	player.ground_move(10.0, 10000.0, 75.0, 0.02)

	assert_float(player.velocity.z).is_equal_approx(-10.0, 0.05)


func test_can_jump_is_false_while_locked_by_a_status() -> void:
	var player := _bot_player(_offset())
	var ctrl := _abilities(player)
	await get_tree().physics_frame
	# Fenêtre coyote simulée (indépendante d'un vrai sol physique) : preuve que
	# SANS verrou, can_jump() serait vrai -- isole donc l'effet du verrou.
	player._coyote_timer = 1.0
	assert_bool(player.can_jump()).append_failure_message(
		"préalable du test : sans verrou, le joueur doit pouvoir sauter (fenêtre coyote simulée)"
	).is_true()

	ctrl.server_apply_jump_lock(1.0)

	assert_bool(player.can_jump()).append_failure_message(
		"un verrou de saut actif doit interdire can_jump(), même en fenêtre coyote"
	).is_false()


func test_is_jump_locked_reflects_the_status_expiry() -> void:
	var player := _bot_player(_offset())
	var ctrl := _abilities(player)
	await get_tree().physics_frame
	ctrl.server_apply_jump_lock(0.2)
	assert_bool(player.is_jump_locked()).is_true()

	ctrl._server_status.tick(0.2)
	ctrl._owner_status.tick(0.2)

	assert_bool(player.is_jump_locked()).append_failure_message(
		"le verrou doit avoir expiré après 0.2 s"
	).is_false()
