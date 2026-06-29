## PlayerStateMachine.gd
## State machine finie, légère. Les états sont des Nodes enfants nommés
## (Idle, Walk, Sprint, Crouch, Air, Slide). Le nom du node = clé de transition.
class_name PlayerStateMachine
extends Node

signal state_changed(state_name: String)

@export var initial_state: NodePath

var player: PlayerController
var current: PlayerState
var current_name: String = ""
var _states: Dictionary = {}

func setup(p: PlayerController) -> void:
	player = p
	for child in get_children():
		if child is PlayerState:
			_states[child.name] = child
			child.player = p
			child.config = p.config
	var start: PlayerState = get_node(initial_state) if initial_state else null
	if start == null and _states.size() > 0:
		start = _states.values()[0]
	current = start
	current_name = current.name
	current.enter("")
	state_changed.emit(current_name)

func physics_update(delta: float) -> void:
	if current:
		current.physics_update(delta)

func handle_input(event: InputEvent) -> void:
	if current:
		current.handle_input(event)

func transition_to(state_name: String, msg: Dictionary = {}) -> void:
	if not _states.has(state_name):
		push_warning("État inconnu: %s" % state_name)
		return
	if state_name == current_name:
		return
	var previous := current_name
	if current:
		current.exit()
	current = _states[state_name]
	current_name = state_name
	current.enter(previous, msg)
	state_changed.emit(current_name)
