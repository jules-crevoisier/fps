## SurgeAbility — ULTIME de Vif ("Résurgence") : soin complet (serveur, sans la
## condition hors-combat du soin de base) + bond (propriétaire, prédit).
## Se charge par points.
extends Ability

## Vitesse verticale du bond.
const JUMP_VELOCITY := 6.5

func _init() -> void:
	slot = "X"
	display_name = "Résurgence"
	description = "Soigne entièrement et propulse vers le haut."
	is_ultimate = true
	ult_cost = 8

## Bond : mouvement, donc côté propriétaire (prédiction).
func activate_local(player: PlayerController) -> void:
	player.velocity.y = JUMP_VELOCITY

## Soin complet : effet de jeu autoritaire, donc côté serveur uniquement.
func activate_server(player: PlayerController, _aim_dir: Vector3) -> void:
	var hp := player.get_node_or_null("Health") as Health
	if hp and not hp.is_dead:
		hp.heal(hp.max_health)  # heal() cappe déjà à max_health -> équivaut à un soin complet
