## WorldWeapon.gd
## Arme posée/lancée au sol, ramassable. RÉSEAU : l'uid est alloué par le
## SERVEUR et le spawn/despawn est DIFFUSÉ à tous les pairs par le nœud Weapon
## (autorité serveur — voir Weapon.gd `_broadcast_world_spawn/despawn`). Ce
## script ne fait QUE la présentation locale (chute/rebond façon "loot drop",
## texte de prompt) et l'ENVOI de demandes de ramassage : aucune mutation
## d'inventaire ici, l'inventaire est autoritaire côté serveur.
## Ramassage façon CoD :
##  - si un slot est LIBRE → demande de ramassage automatique en marchant dessus,
##  - sinon → touche "pickup" (F) pour demander un ÉCHANGE avec l'arme en main.
class_name WorldWeapon
extends Area3D

## Registre statique uid -> instance, alimenté uniquement par spawn_local /
## despawn_local (appelés depuis les RPC de diffusion de Weapon.gd, y compris
## sur le serveur lui-même via "call_local").
static var _registry: Dictionary = {}

## Décalage vertical au sol une fois le modèle couché sur le flanc (moitié de
## l'épaisseur type d'une arme, cf. tools/blender/make_weapons.py).
const GROUND_LIFT := 0.07

@export var arm_delay: float = 0.5

var uid: int = -1
var weapon_id: int = -1
var launch_velocity: Vector3 = Vector3.ZERO

var _cfg: WeaponConfig
var _armed: bool = false
var _t: float = 0.0
var _vel: Vector3 = Vector3.ZERO
var _grounded: bool = false
var _spin: float = 0.0
var _label: Label3D
var _pickup_cooldown: float = 0.0

const PICKUP_RETRY_DELAY := 0.4  # anti-spam : au plus une demande toutes les ~0.4s

## Registre statique : retrouve une arme au sol par son uid (validation serveur
## de distance/état armé lors d'un ramassage).
static func find(search_uid: int) -> WorldWeapon:
	return _registry.get(search_uid, null)

## Instancie et enregistre localement une arme au sol (appelé par la diffusion
## serveur, reçue sur CHAQUE pair — y compris le serveur via call_local).
static func spawn_local(new_uid: int, wid: int, pos: Vector3, vel: Vector3, scene: Node) -> void:
	if scene == null or new_uid < 0 or _registry.has(new_uid):
		return
	var ww := WorldWeapon.new()
	ww.uid = new_uid
	ww.weapon_id = wid
	ww.launch_velocity = vel
	scene.add_child(ww)
	ww.global_position = pos

## Retire localement l'arme au sol correspondant à `uid` (diffusion de ramassage).
static func despawn_local(uid_to_remove: int) -> void:
	var ww: WorldWeapon = _registry.get(uid_to_remove, null)
	if ww and is_instance_valid(ww):
		ww.queue_free()

func is_armed() -> bool:
	return _armed

func _ready() -> void:
	if uid != -1:
		_registry[uid] = self
	_cfg = WeaponDatabase.get_by_id(weapon_id)
	_vel = launch_velocity

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.3, 1.0, 1.3)
	col.shape = shape
	col.position.y = 0.4
	add_child(col)

	_spawn_model()

	_label = Label3D.new()
	_label.text = _cfg.weapon_name if _cfg else "?"
	_label.position.y = 0.8
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.font_size = 36
	_label.pixel_size = 0.004
	_label.outline_size = 6
	add_child(_label)

## Charge le modèle 3D de l'arme (tools/blender/make_weapons.py), couché sur
## le flanc (rotation Z 90°, canon toujours à l'horizontale) avec les
## matériaux Cartoon.prop(...) (contour fin, look "objet du monde" — pas de
## couleur d'équipe, c'est une arme au sol, pas un personnage). Repli sur un
## simple pavé si le modèle est introuvable (asset manquant/corrompu — pas un
## repli de direction artistique, juste une garde défensive).
func _spawn_model() -> void:
	var path := Weapon.model_path_for(weapon_id)
	var scene: PackedScene = load(path) as PackedScene if not path.is_empty() and ResourceLoader.exists(path) else null
	if scene == null:
		var mesh := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.7, 0.16, 0.16)
		mesh.mesh = bm
		mesh.position.y = 0.15
		var mat := Cartoon.mat(Color(1.0, 0.82, 0.3))
		mat.emission_enabled = true
		mat.emission = Color(0.6, 0.45, 0.12)
		mesh.material_override = mat
		add_child(mesh)
		return
	var model := scene.instantiate() as Node3D
	add_child(model)
	model.rotation.z = deg_to_rad(90.0)
	model.position.y = GROUND_LIFT
	_apply_prop_materials(model)

func _apply_prop_materials(model: Node3D) -> void:
	var palette := {
		"body": Color(0.42, 0.4, 0.36),
		"grip": Color(0.16, 0.15, 0.14),
		"metal": Color(0.6, 0.61, 0.65),
		"accent": Color(0.85, 0.68, 0.2),
	}
	for mesh in _find_mesh_instances(model):
		if mesh.mesh == null:
			continue
		# Voir ViewModel.gd : AABB exportée parfois fausse pour la surface
		# "body" (bug exporteur glTF), marge de culling en garde.
		mesh.extra_cull_margin = 2.0
		for i in mesh.mesh.get_surface_count():
			var m: Material = mesh.mesh.surface_get_material(i)
			var name: String = m.resource_name if m else ""
			for slot in palette.keys():
				if name.ends_with("_%s" % slot):
					mesh.set_surface_override_material(i, Cartoon.prop(palette[slot]))
					break

func _find_mesh_instances(root: Node) -> Array:
	var out: Array = []
	if root is MeshInstance3D:
		out.append(root)
	for c in root.get_children():
		out.append_array(_find_mesh_instances(c))
	return out

func _exit_tree() -> void:
	if uid != -1 and _registry.get(uid) == self:
		_registry.erase(uid)

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

	if _pickup_cooldown > 0.0:
		_pickup_cooldown -= delta

	if not _armed:
		_t += delta
		if _t >= arm_delay:
			_armed = true
		return

	_update_pickup_prompt()

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

## Le CLIENT n'écrit jamais l'inventaire : il ENVOIE une demande de ramassage
## au serveur (auto si un slot est libre, sur [F] sinon), limitée par
## `_pickup_cooldown` pour ne pas spammer le réseau tant qu'on reste dessus.
func _update_pickup_prompt() -> void:
	var base_name: String = _cfg.weapon_name if _cfg else "?"
	var prompt := false
	for b in get_overlapping_bodies():
		if b is PlayerController and b.is_multiplayer_authority():
			var w := b.get_node_or_null("Weapon") as Weapon
			if w == null:
				continue
			if w.has_free_slot():
				_request_pickup(w)
				return
			prompt = true
			# Lit l'entrée du JOUEUR (b.input) — jamais le singleton Input
			# directement, sinon un bot hériterait du clavier du serveur (voir
			# contract-r3.md, "Cross-slice interfaces").
			var input := b.get_node_or_null("Input") as PlayerInput
			if input and input.pickup_pressed:
				_request_pickup(w)
				return
	if _label:
		_label.text = "%s\n[F] échanger" % base_name if prompt else base_name

func _request_pickup(w: Weapon) -> void:
	if _pickup_cooldown > 0.0:
		return
	_pickup_cooldown = PICKUP_RETRY_DELAY
	w.request_world_pickup(uid)
