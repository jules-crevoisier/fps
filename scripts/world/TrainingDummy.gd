## TrainingDummy.gd
## Mannequin d'entraînement : prend des dégâts (montre les chiffres), affiche ses
## PV au-dessus, et se réinitialise après sa "mort". À placer dans le terrain
## d'entraînement. Construit sa collision / son mesh / sa vie par code.
class_name TrainingDummy
extends StaticBody3D

@export var max_health: float = 100.0
@export var reset_delay: float = 1.5

var health: Health
var _label: Label3D

func _ready() -> void:
	# Collision + mesh (capsule type joueur).
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.height = 1.8
	cap.radius = 0.4
	col.shape = cap
	col.position.y = 0.9
	add_child(col)

	var mesh := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.height = 1.8
	cm.radius = 0.4
	mesh.mesh = cm
	mesh.position.y = 0.9
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.3, 0.3)
	mesh.material_override = mat
	add_child(mesh)

	# Vie (serveur-autoritaire) — sans régénération pour voir les dégâts cumulés.
	health = Health.new()
	health.name = "Health"
	health.max_health = max_health
	health.regen_rate = 0.0
	add_child(health)
	health.set_multiplayer_authority(1)
	health.health_changed.connect(_on_hp_changed)
	health.died.connect(_on_died)

	# Étiquette PV au-dessus.
	_label = Label3D.new()
	_label.position.y = 2.15
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.font_size = 48
	_label.pixel_size = 0.005
	_label.outline_size = 8
	add_child(_label)
	_on_hp_changed(health.current_health, health.max_health)

func _on_hp_changed(current: float, _maximum: float) -> void:
	if _label:
		_label.text = "%d" % int(ceil(current))
		_label.modulate = Color(0.4, 1.0, 0.4) if current > max_health * 0.5 else Color(1.0, 0.6, 0.3)

func _on_died(_killer_id: int) -> void:
	if _label:
		_label.text = "✗"
	await get_tree().create_timer(reset_delay).timeout
	if is_instance_valid(health):
		health.reset()
