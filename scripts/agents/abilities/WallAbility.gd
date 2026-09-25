## WallAbility — érige un mur temporaire devant le joueur (bloque tirs & passage).
## Répliqué : le mur est spawné sur TOUS les pairs (visible/bloquant pour tous).
## Construit UNIQUEMENT côté serveur, depuis SA propre vue de la transform du
## joueur (anti-triche : le client ne choisit plus ni la taille ni la position).
## Paramètres exportés pour permettre plusieurs variantes (Mur de Vanne, Mur
## d'assaut de Choc, Rempart de Verrou, Forteresse — voir AgentDatabase).
extends Ability

## Taille de la boîte du mur (largeur, hauteur, épaisseur).
@export var size: Vector3 = Vector3(4.0, 2.6, 0.4)
## Distance devant le joueur à laquelle le mur est érigé.
@export var distance: float = 3.0
## Décalage vertical du centre du mur par rapport aux pieds du joueur.
@export var height_offset: float = 1.3
## Durée de vie du mur (s).
@export var duration: float = 8.0
## Couleur (albedo + émission) du mur.
@export var color: Color = Color(0.25, 0.55, 1.0)

func _init() -> void:
	slot = "E"
	display_name = "Mur"
	description = "Érige un mur de couverture temporaire bloquant tirs et passage."
	cooldown = 16.0
	charges = 1

func activate_server(player: PlayerController, _aim_dir: Vector3) -> void:
	var ctrl := player.get_node_or_null("Abilities")
	if ctrl == null or not ctrl.has_method("cast_barrier"):
		return
	var fwd := -player.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var pos := player.global_position + fwd * distance + Vector3(0, height_offset, 0)
	ctrl.cast_barrier(pos, fwd, size, duration, color)
