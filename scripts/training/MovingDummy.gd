## MovingDummy.gd
## Mannequin MOBILE du stand de tir (contract-r4a.md, R4-TRAIN #3 :
## "moving dummies"). Étend `TrainingDummy` (lu seul — hérite collision/vie/
## étiquette PV telles quelles) et ajoute une patrouille de va-et-vient
## (sinusoïde autour de la position de spawn) : déplacement direct du
## StaticBody3D, comme un tremplin/mur de capacité (pas de move_and_slide
## nécessaire pour un aller-retour cinématique simple).
class_name MovingDummy
extends TrainingDummy

@export var patrol_axis: Vector3 = Vector3.RIGHT
@export var patrol_distance: float = 3.0
@export var patrol_speed: float = 1.5

var _origin: Vector3
var _t: float = 0.0

func _ready() -> void:
	super._ready()
	_origin = position

func _physics_process(delta: float) -> void:
	_t += delta
	var offset := patrol_axis.normalized() * sin(_t * patrol_speed) * patrol_distance
	position = _origin + offset
