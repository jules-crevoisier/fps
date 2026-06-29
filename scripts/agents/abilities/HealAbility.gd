## HealAbility — soin instantané (validé côté serveur).
extends Ability

func _init() -> void:
	slot = "Q"
	display_name = "Soin"
	cooldown = 14.0
	charges = 1

func activate(player: PlayerController) -> void:
	var hp := player.get_node_or_null("Health") as Health
	if hp:
		hp.request_heal.rpc_id(1, 60.0)
