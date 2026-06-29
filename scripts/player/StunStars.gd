## StunStars.gd
## Étoiles cartoon qui tournent au-dessus de la tête pendant un stun.
## Construites en Label3D (caractère ★) en billboard, sans texture nécessaire.
class_name StunStars
extends Node3D

@export var star_count: int = 3
@export var radius: float = 0.32
@export var spin_speed: float = 6.0  ## rad/s
@export var bob_amp: float = 0.04
@export var star_color: Color = Color(1.0, 0.85, 0.15)

var _t: float = 0.0
var _base_y: float = 0.0

func _ready() -> void:
	_base_y = position.y
	_build()
	visible = false

func _build() -> void:
	for i in star_count:
		var l := Label3D.new()
		l.text = "★"
		l.modulate = star_color
		l.outline_modulate = Color(0.35, 0.22, 0.0, 1.0)
		l.outline_size = 12
		l.font_size = 72
		l.pixel_size = 0.004
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.no_depth_test = true
		var ang := TAU * float(i) / float(star_count)
		l.position = Vector3(cos(ang) * radius, 0.0, sin(ang) * radius)
		add_child(l)

func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	rotate_y(spin_speed * delta)
	position.y = _base_y + sin(_t * 4.0) * bob_amp

func show_stars() -> void:
	_t = 0.0
	visible = true

func hide_stars() -> void:
	visible = false
	position.y = _base_y
