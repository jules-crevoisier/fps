## DamageZone.gd
## Zone (Area3D) qui inflige des dégâts continus aux joueurs à l'intérieur.
## Sert à tester le système de vie. Dégâts appliqués CÔTÉ SERVEUR uniquement.
class_name DamageZone
extends Area3D

## Dégâts par seconde infligés tant qu'on reste dans la zone.
@export var damage_per_second: float = 25.0

func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	for body in get_overlapping_bodies():
		var hp := _find_health(body)
		if hp:
			hp.apply_damage(damage_per_second * delta, 0)

func _find_health(body: Node) -> Health:
	var n := body.get_node_or_null("Health")
	return n as Health
