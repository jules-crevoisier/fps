## SurgeAbility — ULTIME : soin complet + bond. Se charge par points.
extends Ability

func _init() -> void:
	slot = "X"
	display_name = "Surge"
	is_ultimate = true
	ult_cost = 8

func activate(player: PlayerController) -> void:
	var hp := player.get_node_or_null("Health") as Health
	if hp:
		hp.request_heal.rpc_id(1, 999.0)  # soin complet (cappé à max côté serveur)
	player.velocity.y = 6.5
