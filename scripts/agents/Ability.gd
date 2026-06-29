## Ability.gd
## Capacité de base (façon Valorant). Chaque capacité concrète hérite de cette
## classe et surcharge `activate()`. Les métadonnées (cooldown, charges, ultime)
## sont lues par l'AbilityController qui gère l'état runtime (timers, charges).
class_name Ability
extends Resource

## Emplacement / touche : "C", "Q", "E" (capacités) ou "X" (ultime).
@export var slot: String = "C"
@export var display_name: String = "Capacité"
## Cooldown entre deux usages (s).
@export var cooldown: float = 8.0
## Nombre de charges (utilisations avant cooldown global).
@export var charges: int = 1
## Ultime : se charge par points au lieu d'un cooldown.
@export var is_ultimate: bool = false
## Points nécessaires pour l'ultime.
@export var ult_cost: int = 7

## Exécuté quand la capacité est activée. `player` = le joueur qui l'utilise.
## À surcharger dans les capacités concrètes.
func activate(_player: PlayerController) -> void:
	pass
