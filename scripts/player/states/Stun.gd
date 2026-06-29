## Stun — étourdissement cartoon après une grosse chute (pas de dégâts).
## Le perso est figé sur place, des étoiles tournent au-dessus de sa tête.
## La durée (reçue dans `msg.duration`) dépend de la hauteur de chute.
extends PlayerState

var _timer: float = 0.0
var _duration: float = 1.0

func enter(_from: String, msg: Dictionary = {}) -> void:
	_duration = msg.get("duration", config.stun_min_time)
	_timer = 0.0
	player.set_crouching(false)
	if player.stun_stars and player.stun_stars.has_method("show_stars"):
		player.stun_stars.show_stars()

func exit() -> void:
	if player.stun_stars and player.stun_stars.has_method("hide_stars"):
		player.stun_stars.hide_stars()

func physics_update(delta: float) -> void:
	_timer += delta
	player.apply_gravity(delta)
	player.apply_friction(config.ground_friction, delta)  # figé sur place

	# Aucune action possible pendant le stun (saut/slide/dive ignorés).
	if _timer >= _duration:
		_recover()

func _recover() -> void:
	if player.input_vector == Vector2.ZERO:
		transition_to("Idle")
	elif Input.is_action_pressed("walk"):
		transition_to("Walk")
	else:
		transition_to("Sprint")
