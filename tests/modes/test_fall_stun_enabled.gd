## test_fall_stun_enabled.gd
## Spec (MV-03, tasks/backlog.yaml) : `GameMode.fall_stun_enabled` doit rester
## vrai dans les modes d'ARÈNE (TDM — respawn immédiat, retombe tel quel sur
## `GameMode.respawns_immediately()`) : une perte de contrôle après une chute
## est jugée trop punitive en compétitif à manches (docs/research/
## 01_game_feel.md #16, "frustrante en compétitif").
##
## Nettoyage du prototype 2026-09-26 : les modes à manches/zone (Hardpoint,
## RoundMode et ses sous-classes SnD/Duel/Duo) qui désactivaient ce champ ont
## été supprimés — TDM est désormais le seul mode, les tests correspondants
## de ce fichier ont été retirés.
##
## `fall_stun_enabled` est un champ CALCULÉ à partir de `respawns_immediately()`
## — même patron que `ammo_rule` (GameMode.gd). Instanciation directe (`.new()`,
## jamais son `_ready()` livré à l'engine loop au-delà d'un `add_child`
## synchrone), même méthode que tests/modes/test_game_mode_tiebreak.gd.
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
