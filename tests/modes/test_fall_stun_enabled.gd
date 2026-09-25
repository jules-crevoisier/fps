## test_fall_stun_enabled.gd
## Spec (MV-03, tasks/backlog.yaml) : `GameMode.fall_stun_enabled` doit rester
## vrai dans les modes d'ARÈNE (TDM/Hardpoint — respawn immédiat, retombent
## tels quels sur `GameMode.respawns_immediately()`) et passer à FAUX dans les
## modes à MANCHES (SnD, Duel 1v1, Duo 2v2 — `RoundMode` et ses sous-classes
## surchargent déjà `respawns_immediately()` à faux) : une perte de contrôle
## après une chute est jugée trop punitive en compétitif à manches
## (docs/research/01_game_feel.md #16, "frustrante en compétitif").
##
## `fall_stun_enabled` est un champ CALCULÉ à partir de `respawns_immediately()`
## — même patron que `ammo_rule` (GameMode.gd) — donc aucune sous-classe de
## mode (TDMMode/HardpointMode/RoundMode/DuelMode/SnDMode, hors de ma liste de
## fichiers pour cette tâche) n'a besoin d'être modifiée pour en hériter
## correctement. Instanciation directe (`.new()`, jamais son `_ready()` livré
## à l'engine loop au-delà d'un `add_child` synchrone), même méthode que
## tests/modes/test_game_mode_tiebreak.gd et tests/modes/test_duel_stalemate.gd.
extends GdUnitTestSuite


func _new_mode(script: GDScript) -> Node:
	var mode: Node = script.new()
	add_child(mode)
	auto_free(mode)
	return mode


# --------------------------------------------------------- Arène : activé

func test_base_game_mode_has_fall_stun_enabled_true() -> void:
	var mode := _new_mode(GameMode)
	assert_bool(mode.fall_stun_enabled).append_failure_message(
		"GameMode de base (respawn immédiat par défaut) doit garder le stun de chute actif"
	).is_true()


func test_tdm_mode_has_fall_stun_enabled_true() -> void:
	var mode := _new_mode(TDMMode)
	assert_bool(mode.fall_stun_enabled).append_failure_message(
		"TDM (arène, respawn immédiat) doit garder le stun de chute actif"
	).is_true()


func test_hardpoint_mode_has_fall_stun_enabled_true() -> void:
	var mode := _new_mode(HardpointMode)
	assert_bool(mode.fall_stun_enabled).append_failure_message(
		"Hardpoint (arène, respawn immédiat) doit garder le stun de chute actif"
	).is_true()


# ------------------------------------------------------ Manches : désactivé

func test_round_mode_has_fall_stun_enabled_false() -> void:
	var mode := _new_mode(RoundMode)
	assert_bool(mode.fall_stun_enabled).append_failure_message(
		"RoundMode (base commune SnD/Duel/Duo, respawn différé à la manche suivante) doit désactiver le stun de chute — critère d'acceptation MV-03"
	).is_false()


func test_duel_mode_has_fall_stun_enabled_false() -> void:
	var mode := _new_mode(DuelMode)
	assert_bool(mode.fall_stun_enabled).append_failure_message(
		"Duel 1v1 / Duo 2v2 (DuelMode, hérite de RoundMode) doit désactiver le stun de chute — critère d'acceptation MV-03"
	).is_false()


func test_snd_mode_has_fall_stun_enabled_false() -> void:
	var mode := _new_mode(SnDMode)
	assert_bool(mode.fall_stun_enabled).append_failure_message(
		"SnD (pose/désamorçage à manches, hérite de RoundMode) doit désactiver le stun de chute — critère d'acceptation MV-03"
	).is_false()
