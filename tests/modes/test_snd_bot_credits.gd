## test_snd_bot_credits.gd
## Spec (BUG-25, tasks/backlog.yaml, docs/audit/bugs.md) : en SnD, un joueur
## BOT (id >= PlayerController.BOT_ID_START = 9001) ne correspond à AUCUN pair
## réseau réel — l'hôte et les bots sont simulés côté SERVEUR (contract-r3.md,
## "Cross-slice interfaces"). `_push_credits`/`_ensure_economy` tentaient un
## `rpc_id` vers cet id pour n'importe quel joueur ≠ soi-même, ce qui échouait
## avec "Attempt to call RPC with unknown peer ID" pour un bot (gameplay_probe
## round_flow:snd / round_flow:snd:full_match, `on_kill` -> `_push_credits`
## d'un bot tueur). Le correctif gère ce cas LOCALEMENT, comme le reste du jeu
## pour ce même motif (Weapon.gd._push_server_sync, AbilityController.gd.
## _push_state) : plus aucun `rpc_id` vers un id de bot.
##
## Garde-fou supplémentaire : `my_credits` ne représente QUE le HUD du joueur
## humain LOCAL de cette machine (jamais un bot, qui n'a pas de HUD — voir
## PlayerController.is_local_human) ; un correctif naïf qui pousserait le
## solde d'un bot directement dans `my_credits` corromprait l'affichage de
## crédits de l'hôte-joueur s'il joue en même temps que des bots (ex. un bot
## tue quelqu'un juste après un achat de l'hôte : son HUD afficherait alors le
## solde du BOT). Ce fichier vérifie donc aussi que `my_credits` reste celui
## du joueur local, jamais celui d'un bot.
extends GdUnitTestSuite


const BOT_ID := PlayerController.BOT_ID_START  # 9001, voir PlayerController.gd.


func _new_mode() -> SnDMode:
	var mode := SnDMode.new()
	add_child(mode)
	auto_free(mode)
	return mode


# ======================================================================
#  Plus aucun rpc_id vers un id de bot (le bug tel que rapporté).
# ======================================================================
func test_ensure_economy_for_a_bot_never_triggers_an_rpc_error() -> void:
	var mode := _new_mode()
	await assert_error(func(): mode._ensure_economy(BOT_ID)).append_failure_message(
		"_ensure_economy(bot) ne doit plus tenter de rpc_id vers un pair inexistant"
	).is_success()


func test_push_credits_for_a_bot_never_triggers_an_rpc_error() -> void:
	var mode := _new_mode()
	mode._ensure_economy(BOT_ID)
	mode.economy.award_kill(BOT_ID)
	await assert_error(func(): mode._push_credits(BOT_ID)).append_failure_message(
		"_push_credits(bot) ne doit plus tenter de rpc_id vers un pair inexistant"
	).is_success()


## Chemin réel du bug : un BOT tueur (voir gameplay_probe round_flow:snd).
func test_on_kill_credits_a_bot_killer_without_an_rpc_error() -> void:
	var mode := _new_mode()
	mode.round_state.start_live()  # on_kill n'agit qu'en phase LIVE.

	await assert_error(func(): mode.on_kill(BOT_ID, 2, 0, 1)).append_failure_message(
		"on_kill avec un tueur BOT ne doit déclencher aucune erreur moteur (RPC vers un pair inexistant)"
	).is_success()

	assert_int(mode.economy.get_credits(BOT_ID)).append_failure_message(
		"le bot tueur doit quand même toucher la récompense de kill malgré l'absence de pair réel"
	).is_equal(Economy.START + Economy.KILL_REWARD)


# ======================================================================
#  L'économie du bot est bien tenue à jour LOCALEMENT (source de vérité).
# ======================================================================
func test_ensure_economy_grants_a_bot_the_starting_balance() -> void:
	var mode := _new_mode()
	mode._ensure_economy(BOT_ID)

	assert_bool(mode.economy.credits.has(BOT_ID)).is_true()
	assert_int(mode.economy.get_credits(BOT_ID)).is_equal(Economy.START)


func test_ensure_economy_does_not_reset_an_already_tracked_bot() -> void:
	var mode := _new_mode()
	mode._ensure_economy(BOT_ID)
	mode.economy.award_kill(BOT_ID)

	mode._ensure_economy(BOT_ID)  # rejoué (ex. un autre appelant) : pas de remise à zéro.

	assert_int(mode.economy.get_credits(BOT_ID)).is_equal(Economy.START + Economy.KILL_REWARD)


func test_push_credits_updates_the_bot_balance_after_a_purchase() -> void:
	var mode := _new_mode()
	mode._ensure_economy(BOT_ID)
	mode.economy.spend(BOT_ID, 500)

	mode._push_credits(BOT_ID)  # ne doit ni planter ni empêcher la mise à jour locale.

	assert_int(mode.economy.get_credits(BOT_ID)).is_equal(Economy.START - 500)


# ======================================================================
#  Garde-fou : le solde d'un bot ne doit jamais écraser le HUD local (my_credits).
# ======================================================================
func test_push_credits_for_a_bot_does_not_corrupt_the_local_hud_balance() -> void:
	var mode := _new_mode()
	# Simule l'hôte-joueur : son propre solde est déjà affiché (my_credits),
	# comme le ferait un vrai `_push_credits(host_id)` (id == get_unique_id()).
	var host_id := multiplayer.get_unique_id()
	mode._ensure_economy(host_id)
	mode._push_credits(host_id)
	var host_balance := mode.my_credits

	mode._ensure_economy(BOT_ID)
	mode.economy.award_kill(BOT_ID)  # solde du bot désormais DIFFÉRENT de celui de l'hôte.
	mode._push_credits(BOT_ID)

	assert_int(mode.my_credits).append_failure_message(
		"le solde d'un BOT ne doit jamais écraser my_credits (HUD du joueur humain local uniquement)"
	).is_equal(host_balance)
