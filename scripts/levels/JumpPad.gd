## JumpPad.gd
## Zone qui propulse le joueur vers le haut au contact. Posée par l'ArenaBuilder.
class_name JumpPad
extends Area3D

## Vitesse verticale imposée au contact (m/s).
@export var boost: float = 18.0

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node) -> void:
	if body is PlayerController and body.is_multiplayer_authority():
		body.velocity.y = max(body.velocity.y, boost)
