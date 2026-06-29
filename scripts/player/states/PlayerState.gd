## PlayerState.gd
## Classe de base pour tous les états de mouvement du joueur.
## Chaque état est un Node enfant du PlayerStateMachine.
class_name PlayerState
extends Node

## Référence injectée par la state machine au démarrage.
var player: PlayerController
var config: MovementConfig

## Appelé une fois quand on entre dans l'état. `from` = nom de l'état précédent.
func enter(_from: String, _msg: Dictionary = {}) -> void:
	pass

## Appelé quand on quitte l'état.
func exit() -> void:
	pass

## Logique de mouvement, appelée depuis _physics_process.
func physics_update(_delta: float) -> void:
	pass

## Entrées non liées à la physique (ex: ouvrir un menu). Optionnel.
func handle_input(_event: InputEvent) -> void:
	pass

## Raccourci pour changer d'état.
func transition_to(state_name: String, msg: Dictionary = {}) -> void:
	player.state_machine.transition_to(state_name, msg)
