## DashAbility — ruée rapide dans une direction (mouvement pur, prédiction
## propriétaire : pas d'effet serveur au-delà du décompte de charges/cooldown).
## Paramètres exportés pour permettre plusieurs variantes réutilisant la même
## logique (Ruée de Vif, Charge de Choc, Piquet de Roc — voir AgentDatabase).
extends Ability

## Vitesse horizontale imprimée (m/s).
@export var force: float = 17.0
## Vitesse verticale minimale imposée (petit décollement, franchit les rebords).
@export var hop: float = 2.5
## true = toujours vers l'avant du corps (Charge, Piquet) ; false = direction
## de déplacement si elle existe, sinon la face du corps (Ruée classique).
@export var use_facing: bool = false

func _init() -> void:
	slot = "C"
	display_name = "Ruée"
	description = "Ruée rapide dans la direction de déplacement."
	cooldown = 6.0
	charges = 2

## Prédit et exécuté uniquement côté propriétaire (pur mouvement, pas de
## validation serveur nécessaire au-delà du décompte de charges/cooldown).
func activate_local(player: PlayerController) -> void:
	var dir := -player.global_transform.basis.z
	dir.y = 0.0
	if not use_facing and player.wish_dir != Vector3.ZERO:
		dir = player.wish_dir
	dir = dir.normalized()
	player.velocity.x = dir.x * force
	player.velocity.z = dir.z * force
	if player.velocity.y < hop:
		player.velocity.y = hop
