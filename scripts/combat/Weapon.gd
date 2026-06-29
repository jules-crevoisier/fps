## Weapon.gd
## Inventaire d'armes + tir serveur-autoritaire. Le joueur porte plusieurs armes
## (loadout), en change (1/2/3, molette), et tire selon le TYPE de l'arme
## courante (hitscan / shotgun multi-plombs / sniper). Munitions suivies par arme.
## Tir validé côté serveur (raycast autoritaire, falloff, headshot).
class_name Weapon
extends Node

signal ammo_changed(ammo: int, reserve: int)
signal weapon_changed(cfg: WeaponConfig)

@export var config: WeaponConfig  # fallback optionnel (sinon loadout par défaut)

var player: PlayerController
var camera: Camera3D

var weapons: Array = []     # Array[WeaponConfig]
var mag: Array = []         # munitions dans le chargeur, par arme
var reserve_a: Array = []   # munitions en réserve, par arme
var current: int = 0

var _cooldown: float = 0.0
var _reload_timer: float = 0.0
var _reloading: bool = false
var _pending_shots: Array = []

func _ready() -> void:
	player = get_parent() as PlayerController
	_setup_loadout()

const SLOTS := 2  # 2 emplacements façon CoD (n'importe quelle arme dans chacun)

func _setup_loadout() -> void:
	weapons = WeaponDatabase.default_loadout()
	while weapons.size() < SLOTS:
		weapons.append(null)
	mag.clear()
	reserve_a.clear()
	for w in weapons:
		mag.append(w.mag_size if w else 0)
		reserve_a.append(w.reserve_ammo if w else 0)
	current = 0
	_emit()

func cfg() -> WeaponConfig:
	return weapons[current] if current < weapons.size() else null

func current_aim_fov() -> float:
	var c := cfg()
	return c.aim_fov if c else 60.0

func is_scoped() -> bool:
	var c := cfg()
	return c != null and c.scoped

## Y a-t-il un emplacement vide ?
func has_free_slot() -> bool:
	for w in weapons:
		if w == null:
			return true
	return false

## Range une arme dans le premier slot libre (ramassage auto). Garde l'arme en main.
func pickup_into_free(c: WeaponConfig) -> void:
	if c == null:
		return
	for i in weapons.size():
		if weapons[i] == null:
			weapons[i] = c
			mag[i] = c.mag_size
			reserve_a[i] = c.reserve_ammo
			# Si on n'avait rien en main, on équipe la nouvelle.
			if cfg() == null:
				current = i
			_emit()
			return

## Échange l'arme EN MAIN avec celle du sol : l'ancienne est lâchée à `pos`.
func swap_for_ground(c: WeaponConfig, pos: Vector3) -> void:
	if c == null:
		return
	var old := cfg()
	weapons[current] = c
	mag[current] = c.mag_size
	reserve_a[current] = c.reserve_ammo
	_cooldown = 0.25
	_reloading = false
	if old:
		_place_world_weapon(WeaponDatabase.all().find(old), pos)
	_emit()

## Lâche l'arme courante (touche G) avec une physique qui hérite de la vitesse/saut.
func drop_current() -> void:
	var c := cfg()
	if c == null:
		return
	var id: int = WeaponDatabase.all().find(c)
	var fwd := -player.global_transform.basis.z
	var vel := player.velocity * 0.6 + fwd * 4.0 + Vector3(0, 3.0, 0)
	_spawn_world_weapon(id, player.global_position + Vector3(0, 1.1, 0) + fwd * 0.4, vel)
	weapons[current] = null
	mag[current] = 0
	reserve_a[current] = 0
	_reloading = false
	for i in weapons.size():
		if weapons[i] != null:
			current = i
			break
	_emit()

func _place_world_weapon(id: int, pos: Vector3) -> void:
	_spawn_world_weapon(id, pos, Vector3.ZERO)

func _spawn_world_weapon(id: int, pos: Vector3, vel: Vector3) -> void:
	if id < 0:
		return
	var scene := player.get_tree().current_scene
	if scene == null:
		return
	var ww := WorldWeapon.new()
	ww.weapon_id = id
	ww.launch_velocity = vel
	scene.add_child(ww)
	ww.global_position = pos

## Donne une arme (boutique) : remplit un slot libre sinon remplace l'arme en main,
## et l'équipe. (En training, c'est gratuit.)
func give_weapon(c: WeaponConfig) -> void:
	if c == null:
		return
	var slot: int = -1
	for i in weapons.size():
		if weapons[i] == null:
			slot = i
			break
	if slot == -1:
		slot = current  # plus de place : on remplace l'arme en main
	weapons[slot] = c
	mag[slot] = c.mag_size
	reserve_a[slot] = c.reserve_ammo
	current = slot
	_cooldown = 0.25
	_reloading = false
	_emit()

func equip(i: int) -> void:
	if i < 0 or i >= weapons.size() or i == current or _reloading:
		return
	current = i
	_cooldown = 0.25  # petit délai de changement d'arme
	_emit()

func _emit() -> void:
	if current < mag.size():
		ammo_changed.emit(mag[current], reserve_a[current])
	weapon_changed.emit(cfg())

func _process(delta: float) -> void:
	if player == null:
		return
	if camera == null:
		camera = player.camera
	_cooldown = maxf(_cooldown - delta, 0.0)

	if not player.is_multiplayer_authority():
		return

	_handle_switch()

	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and Input.is_action_just_pressed("drop"):
		drop_current()

	if _reloading:
		_reload_timer -= delta
		if _reload_timer <= 0.0:
			_finish_reload()
		return

	if not _can_fire():
		return

	if Input.is_action_just_pressed("reload"):
		_start_reload()
		return

	var c := cfg()
	if c == null:
		return
	var firing := Input.is_action_pressed("fire") if c.automatic else Input.is_action_just_pressed("fire")
	if firing and _cooldown <= 0.0 and mag[current] > 0:
		_fire()
	elif firing and mag[current] <= 0:
		_start_reload()

func _handle_switch() -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED or weapons.size() <= 1:
		return
	if Input.is_action_just_pressed("weapon_1"):
		equip(0)
	elif Input.is_action_just_pressed("weapon_2"):
		equip(1)
	elif Input.is_action_just_pressed("weapon_3"):
		equip(2)
	elif Input.is_action_just_pressed("weapon_next"):
		equip((current + 1) % weapons.size())
	elif Input.is_action_just_pressed("weapon_prev"):
		equip((current - 1 + weapons.size()) % weapons.size())

func _can_fire() -> bool:
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return false
	var hp := player.get_node_or_null("Health") as Health
	if hp and hp.is_dead:
		return false
	var s := player.state_machine.current_name
	return s != "Stun" and s != "Dive" and s != "Roll"

func _fire() -> void:
	var c := cfg()
	_cooldown = 1.0 / c.fire_rate
	mag[current] -= 1
	if current < mag.size():
		ammo_changed.emit(mag[current], reserve_a[current])

	var origin := camera.global_position
	var base_dir := -camera.global_transform.basis.z
	var aiming := Input.is_action_pressed("aim")
	var spread := deg_to_rad(c.spread_aim if aiming else c.spread_hip)

	var dirs: Array = []
	var n: int = maxi(1, c.pellets)
	for i in n:
		var s := spread
		if c.pellets > 1:
			s = deg_to_rad(c.pellet_spread)
		dirs.append(_apply_spread(base_dir, s))

	for d in dirs:
		_spawn_tracer(origin, origin + d * c.max_range)

	# Recul (vrai recoil : déplace la visée, récupère ensuite).
	var rmult := c.recoil_aim_mult if aiming else 1.0
	var rp := deg_to_rad(c.recoil_vertical) * rmult
	var ry := deg_to_rad(randf_range(-c.recoil_horizontal, c.recoil_horizontal)) * rmult
	player.add_recoil(rp, ry, c.recoil_recovery)

	# Tir validé serveur — on envoie l'ID d'arme (l'inventaire n'est pas répliqué).
	var wid: int = WeaponDatabase.all().find(c)
	request_fire.rpc_id(1, origin, dirs, wid)

func _apply_spread(dir: Vector3, spread: float) -> Vector3:
	if spread <= 0.0:
		return dir
	var rx := randf_range(-spread, spread)
	var ry := randf_range(-spread, spread)
	return dir.rotated(camera.global_transform.basis.x, rx).rotated(Vector3.UP, ry).normalized()

# ---- VALIDATION SERVEUR ----
@rpc("any_peer", "call_local", "reliable")
func request_fire(origin: Vector3, dirs: Array, weapon_id: int) -> void:
	if not multiplayer.is_server():
		return
	_pending_shots.append([multiplayer.get_remote_sender_id(), origin, dirs, weapon_id])

func _physics_process(_delta: float) -> void:
	if not multiplayer.is_server() or _pending_shots.is_empty():
		return
	var space := player.get_world_3d().direct_space_state
	var db: Array = WeaponDatabase.all()
	for shot in _pending_shots:
		var wid: int = shot[3]
		if wid < 0 or wid >= db.size():
			continue
		var c: WeaponConfig = db[wid]
		for d in shot[2]:
			_resolve_ray(space, shot[0], shot[1], d, c)
	_pending_shots.clear()

func _resolve_ray(space: PhysicsDirectSpaceState3D, shooter_id: int, origin: Vector3, dir: Vector3, c: WeaponConfig) -> void:
	var q := PhysicsRayQueryParameters3D.create(origin, origin + dir.normalized() * c.max_range)
	q.exclude = [player.get_rid()]
	q.collide_with_areas = false
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return
	var collider: Node = hit.collider
	var hp := collider.get_node_or_null("Health") as Health
	if hp == null or hp.is_dead:
		return
	var dist: float = origin.distance_to(hit.position)
	var dmg := _damage_at(dist, c)
	var headshot: bool = hit.position.y > collider.global_position.y + 1.4
	if headshot:
		dmg *= c.headshot_mult
	hp.apply_damage(dmg, shooter_id)
	# Affiche le chiffre de dégâts chez le TIREUR (feedback de hit).
	if shooter_id == multiplayer.get_unique_id():
		_spawn_damage_number(hit.position, dmg, headshot)  # hôte : direct
	else:
		_show_hit.rpc_id(shooter_id, hit.position, dmg, headshot)

@rpc("any_peer", "reliable")
func _show_hit(pos: Vector3, dmg: float, headshot: bool) -> void:
	_spawn_damage_number(pos, dmg, headshot)

# Affiche un chiffre de dégâts flottant dans le monde.
func _spawn_damage_number(pos: Vector3, dmg: float, headshot: bool) -> void:
	var l := Label3D.new()
	l.text = str(int(round(dmg)))
	l.font_size = 64
	l.pixel_size = 0.007
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.modulate = Color(1.0, 0.4, 0.2) if headshot else Color(1, 1, 1)
	l.outline_modulate = Color(0, 0, 0, 0.9)
	l.outline_size = 10
	var scene := player.get_tree().current_scene
	if scene == null:
		return
	scene.add_child(l)
	l.global_position = pos + Vector3(randf_range(-0.15, 0.15), 0.25, 0.0)
	var t := l.create_tween()
	t.tween_property(l, "global_position:y", l.global_position.y + 0.9, 0.7)
	t.parallel().tween_property(l, "modulate:a", 0.0, 0.7)
	t.tween_callback(l.queue_free)

func _damage_at(dist: float, c: WeaponConfig) -> float:
	if dist <= c.falloff_start:
		return c.damage
	if dist >= c.falloff_end:
		return c.damage_min
	var t := (dist - c.falloff_start) / (c.falloff_end - c.falloff_start)
	return lerpf(c.damage, c.damage_min, t)

# ---- Rechargement ----
func _start_reload() -> void:
	var c := cfg()
	if _reloading or c == null or mag[current] >= c.mag_size or reserve_a[current] <= 0:
		return
	_reloading = true
	_reload_timer = c.reload_time

func _finish_reload() -> void:
	_reloading = false
	var c := cfg()
	var needed: int = c.mag_size - mag[current]
	var taken: int = mini(needed, reserve_a[current])
	mag[current] += taken
	reserve_a[current] -= taken
	ammo_changed.emit(mag[current], reserve_a[current])

# ---- Traceur visuel (cosmétique, local) ----
func _spawn_tracer(from: Vector3, to: Vector3) -> void:
	var mesh := MeshInstance3D.new()
	var im := ImmediateMesh.new()
	mesh.mesh = im
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.95, 0.5)
	mesh.material_override = mat
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	im.surface_add_vertex(from)
	im.surface_add_vertex(to)
	im.surface_end()
	player.get_tree().current_scene.add_child(mesh)
	var t := mesh.create_tween()
	t.tween_property(mat, "albedo_color:a", 0.0, 0.08)
	t.tween_callback(mesh.queue_free)
