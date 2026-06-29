## WorldWeapon.gd
## Arme posée/lancée au sol, ramassable. Physique simple de lancer (hérite de la
## vitesse/saut du joueur) puis retombe au sol. Ramassage façon CoD :
##  - si un slot est LIBRE → ramassage automatique en marchant dessus,
##  - sinon → touche "pickup" (F) pour ÉCHANGER avec l'arme en main.
## Local (training/solo) ; réplication réseau à venir.
class_name WorldWeapon
extends Area3D

@export var weapon_id: int = 0
@export var arm_delay: float = 0.5
var launch_velocity: Vector3 = Vector3.ZERO

var _cfg: WeaponConfig
var _armed: bool = false
var _t: float = 0.0
var _vel: Vector3 = Vector3.ZERO
var _grounded: bool = false
var _spin: float = 0.0
var _label: Label3D

func _ready() -> void:
	var db: Array = WeaponDatabase.all()
	if weapon_id >= 0 and weapon_id < db.size():
		_cfg = db[weapon_id]
	_vel = launch_velocity

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.3, 1.0, 1.3)
	col.shape = shape
	col.position.y = 0.4
	add_child(col)

	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.7, 0.16, 0.16)
	mesh.mesh = bm
	mesh.position.y = 0.15
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.7, 0.25)
	mat.emission_enabled = true
	mat.emission = Color(0.5, 0.4, 0.1)
	mesh.material_override = mat
	add_child(mesh)

	_label = Label3D.new()
	_label.text = _cfg.weapon_name if _cfg else "?"
	_label.position.y = 0.8
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.font_size = 36
	_label.pixel_size = 0.004
	_label.outline_size = 6
	add_child(_label)

func _physics_process(delta: float) -> void:
	if not _grounded:
		_vel.y -= 20.0 * delta
		global_position += _vel * delta
		_spin += delta * 7.0
		rotation = Vector3(_spin * 0.6, _spin, 0.0)
		_check_ground()
	else:
		_spin += delta * 1.5
		rotation = Vector3(0.0, _spin, 0.0)

	if not _armed:
		_t += delta
		if _t >= arm_delay:
			_armed = true
		return

	_try_pickup()

func _check_ground() -> void:
	if _vel.y > 0.0:
		return
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3(0, 0.4, 0)
	var to := global_position - Vector3(0, 0.25, 0)
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collide_with_areas = false
	var hit := space.intersect_ray(q)
	if not hit.is_empty():
		global_position.y = hit.position.y
		_vel = Vector3.ZERO
		_grounded = true

func _try_pickup() -> void:
	var base_name: String = _cfg.weapon_name if _cfg else "?"
	var prompt := false
	for b in get_overlapping_bodies():
		if b is PlayerController and b.is_multiplayer_authority():
			var w := b.get_node_or_null("Weapon") as Weapon
			if w == null:
				continue
			if w.has_free_slot():
				w.pickup_into_free(_cfg)
				queue_free()
				return
			else:
				prompt = true  # inventaire plein → échange manuel
				if Input.is_action_just_pressed("pickup"):
					w.swap_for_ground(_cfg, global_position)
					queue_free()
					return
	if _label:
		_label.text = "%s\n[F] échanger" % base_name if prompt else base_name
