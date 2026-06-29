## HealZone.gd
## Zone (Area3D) qui soigne les joueurs à l'intérieur. Soin CÔTÉ SERVEUR.
class_name HealZone
extends Area3D

## PV par seconde rendus tant qu'on reste dans la zone.
@export var heal_per_second: float = 40.0

func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	for body in get_overlapping_bodies():
		var hp := body.get_node_or_null("Health") as Health
		if hp:
			hp.heal(heal_per_second * delta)
