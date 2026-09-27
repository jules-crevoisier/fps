## ThrownUtility.gd
## Objet volant (frag/flash/smoke) — présentation + intégration déterministe
## PARTAGÉES par TOUS les pairs (UtilityIntegrator.gd, fixed timestep via
## `_physics_process`, contrat lead). SEULE l'instance AUTORITAIRE (celle du
## SERVEUR, `is_authority = true`, voir UtilityThrower._broadcast_spawn) décide
## du moment de la détonation et applique les effets de jeu (via son
## UtilityThrower propriétaire) ; toutes les autres copies (clients) volent
## pour de vrai mais attendent la diffusion `_broadcast_detonate` avant de
## disparaître — jamais de double-résolution des effets.
class_name ThrownUtility
extends Node3D

## Registre statique uid -> instance (une par pair, jamais partagé entre eux)
## — même patron que WorldWeapon._registry.
static var _by_uid: Dictionary = {}

var uid: int = -1
var kind: int = UtilityDatabase.FRAG
var cfg: UtilityConfig
var thrower_id: int = -1
var thrower_team: int = 0
var is_authority: bool = false
## Nœud UtilityThrower du LANCEUR — SEULEMENT posé sur l'instance autoritaire
## (voir spawn_local) : c'est lui qui reçoit `server_on_thrown_detonate`.
var _owner_thrower: UtilityThrower

var _vel: Vector3 = Vector3.ZERO
## Amorce restante (s) au moment du lancer — voir UtilityThrower._server_throw
## (fuse_left = cfg.fuse_time pour flash/smoke, cfg.fuse_time - held_duration
## pour une frag relâchée avant l'amorce complète).
var _fuse_left: float = 0.0
var _elapsed: float = 0.0
var _touched_ground: bool = false
## Normale minimale (composante Y) d'une surface comptée comme SOL pour le fumigène.
const _FLOOR_NORMAL_MIN_Y := 0.6
var _detonated: bool = false
var _mesh_root: Node3D

## Tâche "son" 2026-09-27 (point 5) : secondes écoulées depuis le DERNIER son
## de rebond joué par CETTE instance (voir GrenadeAudio.can_play_bounce,
## anti-rafale) -- assez grand au départ pour que le tout premier rebond
## joue toujours.
var _since_last_bounce: float = 999.0

## Instancie et enregistre localement l'objet volant (appelé par
## UtilityThrower._broadcast_spawn, reçu sur CHAQUE pair — y compris le
## serveur via call_local, exactement comme WorldWeapon.spawn_local).
static func spawn_local(new_uid: int, new_kind: int, origin: Vector3, vel: Vector3, fuse_left: float,
		new_thrower_id: int, new_thrower_team: int, scene: Node, authority: bool, owner_thrower: UtilityThrower) -> void:
	if scene == null or new_uid < 0 or _by_uid.has(new_uid):
		return
	var inst := ThrownUtility.new()
	inst.uid = new_uid
	inst.kind = new_kind
	inst.cfg = UtilityDatabase.get_by_id(new_kind)
	inst._vel = vel
	inst._fuse_left = fuse_left
	inst.thrower_id = new_thrower_id
	inst.thrower_team = new_thrower_team
	inst.is_authority = authority
	inst._owner_thrower = owner_thrower
	scene.add_child(inst)
	inst.global_position = origin
	_by_uid[new_uid] = inst

func _ready() -> void:
	_build_mesh()

func _physics_process(delta: float) -> void:
	if _detonated:
		return
	_since_last_bounce += delta
	var speed_before := _vel.length()  # vitesse D'IMPACT (avant rebond) pour GrenadeAudio.bounce_volume_db.
	var space := get_world_3d().direct_space_state if is_inside_tree() else null
	var res := UtilityIntegrator.step(global_position, _vel, delta, cfg, space, [])
	global_position = res["position"]
	_vel = res["velocity"]
	if res["bounced"]:
		# Tâche "son" (point 5) : rebond joué sur TOUT rebond (mur ou sol) --
		# chaque pair simule le MÊME vol déterministe (UtilityIntegrator, voir
		# docstring de classe), donc chacun détecte ce rebond au MÊME instant et
		# joue le son localement sans RPC dédié. Anti-rafale (GrenadeAudio.
		# can_play_bounce) : un objet qui se stabilise en fin de course peut
		# rebondir plusieurs fois par seconde sans que chaque contact mérite un son.
		if GrenadeAudio.can_play_bounce(_since_last_bounce):
			_since_last_bounce = 0.0
			var scene := get_parent()
			if scene:
				_play_sfx(scene, "grenade_bounce", global_position, GrenadeAudio.bounce_volume_db(speed_before))
		# SOL seulement (demande utilisateur 2026-09-27 : le fumigène « descend
		# par gravité jusqu'en bas » et se déploie au premier contact) : un
		# rebond sur un mur ne compte pas pour l'amorce anticipée du fumigène.
		if (res.get("normal", Vector3.UP) as Vector3).y > _FLOOR_NORMAL_MIN_Y:
			_touched_ground = true
	_elapsed += delta

	if not is_authority:
		return
	var should_detonate: bool
	if kind == UtilityDatabase.SMOKE:
		should_detonate = SmokeMath.should_detonate(_elapsed, _touched_ground, cfg)
	else:
		should_detonate = _elapsed >= _fuse_left
	if should_detonate:
		_detonated = true
		var pos := _ground_snap(global_position) if kind == UtilityDatabase.SMOKE else global_position
		if _owner_thrower and is_instance_valid(_owner_thrower):
			_owner_thrower.server_on_thrown_detonate(kind, uid, pos, cfg, thrower_id, thrower_team)

## Le nuage de fumée se pose SUR le sol : après le rebond de contact, le fumigène est quelques
## centimètres au-dessus -- on redescend le point de détonation au sol (<= 3 m, décor seul).
func _ground_snap(pos: Vector3) -> Vector3:
	if not is_inside_tree():
		return pos
	var q := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 0.2, pos + Vector3.DOWN * 3.0, PhysicsLayers.WORLD)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return hit.position if not hit.is_empty() else pos

## Reçu sur TOUS les pairs (UtilityThrower._broadcast_detonate, authority/
## call_local) : fait disparaître la copie locale de l'objet volant (si elle
## existe encore — `uid = -1` pour une frag qui a explosé EN MAIN, jamais
## d'objet volant créé) et joue le VFX/l'audio à `pos`.
static func on_detonate_broadcast(uid: int, kind: int, pos: Vector3, owner_thrower: UtilityThrower) -> void:
	var scene: Node = null
	var inst: ThrownUtility = _by_uid.get(uid, null)
	if inst and is_instance_valid(inst):
		scene = inst.get_parent()
		_by_uid.erase(uid)
		inst.queue_free()
	if scene == null and owner_thrower and owner_thrower.player and owner_thrower.player.is_inside_tree():
		# Même repli que UtilityThrower._attach_root (current_scene nul dans un
		# outil de capture -s SceneTree, voir sa docstring).
		var tree := owner_thrower.player.get_tree()
		scene = tree.current_scene if tree.current_scene else tree.root
	# `multiplayer` (SceneMultiplayer) n'est accessible que sur une INSTANCE de
	# nœud — jamais depuis une fonction statique de CETTE classe (pas de
	# `self`) : on le lit sur `owner_thrower` (nœud réel, toujours dans
	# l'arbre à cet instant, voir UtilityThrower._broadcast_detonate).
	var is_server := owner_thrower.multiplayer.is_server() if owner_thrower else false
	_spawn_detonation_vfx(kind, pos, scene, is_server)

# ======================================================================
#  Mesh volant — modèles réels livrés par le lead (BD, texturés), stylisés
#  toon via ToonStyle.apply_to (même traitement que Ravage/Verrou : la
#  texture peinte reste, seul le SHADING passe par toon_bd.gdshader).
# ======================================================================
## Un .glb PAR TYPE (assets/models/utilities/), même convention que
## Weapon.model_path_for — un seul mesh, +Y haut, origine au centre de la
## boîte englobante (le lanceur ET la grenade tenue en main tournent/pivotent
## donc autour de leur propre centre, jamais un coin).
const _MODEL_PATHS := {
	UtilityDatabase.FRAG: "res://assets/models/utilities/frag.glb",
	UtilityDatabase.FLASH: "res://assets/models/utilities/flash.glb",
	UtilityDatabase.SMOKE: "res://assets/models/utilities/smoke.glb",
}

func _build_mesh() -> void:
	_mesh_root = build_held_mesh(kind)
	add_child(_mesh_root)

## Instancie le .glb réel de `kind` et lui applique le style toon — utilisé
## aussi bien pour l'objet VOLANT (`_build_mesh`) que pour la grenade TENUE en
## main (FPArmsRig.attach_grenade/ViewModel.gd) : un `Node3D` prêt à être
## attaché/ajouté à l'arbre, jamais ajouté lui-même ici. Repli sur un cube
## minuscule non éclairé si le modèle est introuvable/invalide (jamais
## d'exception — même discipline défensive que FPArmsRig.load()).
static func build_held_mesh(kind: int) -> Node3D:
	var path: String = _MODEL_PATHS.get(kind, "")
	if path != "" and ResourceLoader.exists(path):
		var packed := ResourceLoader.load(path) as PackedScene
		if packed:
			var inst := packed.instantiate() as Node3D
			if inst:
				ToonStyle.apply_to(inst)
				return inst
	push_warning("ThrownUtility : modèle introuvable pour kind=%d (%s), repli cube" % [kind, path])
	return _fallback_mesh()

## Repli défensif SEULEMENT (modèle manquant/PackedScene invalide) — jamais le
## rendu normal en jeu, voir docstring de `build_held_mesh`.
static func _fallback_mesh() -> Node3D:
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.08, 0.08, 0.08)
	mi.mesh = box
	mi.material_override = ToonStyle.toon_material(null, Color(1.0, 0.0, 1.0))
	root.add_child(mi)
	return root

# ======================================================================
#  VFX de détonation — placeholders stylisés BD, purement cosmétiques,
#  auto-libérés (contrat lead : burst toon, encre, débris / flash lumineux /
#  nuage géré séparément par SmokeCloud.gd).
# ======================================================================
## Tâche "son" 2026-09-27 : noms LOGIQUES (jamais un fichier `_<n>.wav` précis
## -- `Audio._resolve`/`sfx_path` ajoutent déjà le suffixe de variation, voir
## `_play_sfx` ci-dessous) -- avant cette tâche, ces trois constantes portaient
## un suffixe "_1" qui ne correspondait à AUCUNE clé du manifest (`_scan_manifest`
## indexe par nom SANS le "_<n>" final), donc `_resolve` renvoyait toujours
## `null` : les trois détonations étaient SILENCIEUSES en jeu. `_FRAG_SFX`
## utilisait de plus `wall_slam_1` (repli d'avant que le lead ne fournisse un
## vrai son d'explosion, voir assets/audio/sfx/PROVENANCE.md) : remplacé par
## le son dédié `explosion` (explosion_1/explosion_2, deux variations).
const _FRAG_SFX := "explosion"
const _FLASH_SFX := "flash"
const _SMOKE_SFX := "smoke"

static func _spawn_detonation_vfx(kind: int, pos: Vector3, scene: Node, is_server: bool) -> void:
	match kind:
		UtilityDatabase.FRAG:
			_spawn_frag_vfx(pos, scene)
			_play_sfx(scene, _FRAG_SFX, pos)
		UtilityDatabase.FLASH:
			_spawn_flash_vfx(pos, scene)
			_play_sfx(scene, _FLASH_SFX, pos)
		UtilityDatabase.SMOKE:
			var cfg := UtilityDatabase.get_by_id(UtilityDatabase.SMOKE)
			SmokeCloud.spawn_local(pos, cfg, is_server, scene)
			_play_sfx(scene, _SMOKE_SFX, pos)

## Joue un son positionnel via l'autoload "Sfx" (Audio.gd) SANS référencer
## l'identifiant global "Sfx" — celui-ci ne se résout pas depuis une fonction
## STATIQUE dans tous les contextes d'exécution (ex. un outil `-s script.gd`
## qui remplace la boucle principale, comme tools/rigging/utility_filmstrip.gd :
## aucun `self`/nœud d'instance dont dépend la résolution d'un singleton
## autoload par son nom nu). Recherche par chemin ABSOLU sur `scene` (un vrai
## nœud de l'arbre, toujours disponible ici) à la place — sans effet
## (silencieux, jamais d'exception) si l'autoload n'existe pas dans CET arbre.
static func _play_sfx(scene: Node, name: String, pos: Vector3, volume_offset_db: float = 0.0) -> void:
	if scene == null:
		return
	var sfx := scene.get_node_or_null("/root/Sfx")
	if sfx and sfx.has_method("play_at"):
		sfx.call("play_at", name, pos, 0.0, volume_offset_db)

## Sphère flash unshaded (blanc chaud) : agrandit 0 -> `max_radius` sur
## `duration`, jamais de fondu alpha (contrat : matériau opaque, elle
## disparaît par `queue_free` juste après son pic — pas de fade-out visible à
## sa taille max, cohérent avec un flash de détonation instantané).
static func _spawn_flash_sphere(pos: Vector3, scene: Node, max_radius: float, duration: float, color: Color) -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 16
	sm.rings = 8
	mi.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mi.material_override = mat
	scene.add_child(mi)
	mi.global_position = pos
	mi.scale = Vector3.ZERO
	var t := mi.create_tween()
	t.tween_property(mi, "scale", Vector3.ONE * max_radius, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_callback(mi.queue_free)

## Étoile BD à 12 pointes (StarburstMesh.gd) : remplissage `fill_color`
## unshaded + une étoile encre légèrement plus grande DERRIÈRE (silhouette de
## contour, même esprit que le contour post-process du reste du style —
## celui-ci ne couvre pas les éléments non-opaques/non-solides comme ce
## billboard). Pop-in (TRANS_BACK) -> tenue -> pop-out, chaque étoile se
## libère elle-même en fin de course.
static func _spawn_starburst(pos: Vector3, scene: Node, fill_color: Color, size_m: float,
		pop_in_s: float, hold_s: float, pop_out_s: float) -> void:
	var outer := size_m * 0.5
	var inner := outer * 0.45
	_spawn_star_layer(pos, scene, Color("0E0A12"), outer * 1.15, inner * 1.15, pop_in_s, hold_s, pop_out_s, Vector3(0, 0, 0.02))
	_spawn_star_layer(pos, scene, fill_color, outer, inner, pop_in_s, hold_s, pop_out_s, Vector3.ZERO)

## `preload` DIRECT (chemin, pas le nom de classe global `StarburstMesh`) —
## le cache des classes globales de Godot (`.godot/global_script_class_cache.cfg`)
## n'est reconstruit qu'à un scan de l'éditeur/projet ; un fichier `.gd` tout
## juste ajouté n'y figure pas encore lors d'un run `-s` en ligne de commande,
## ce qui ferait planter le parseur ("Identifier not declared") sur
## `StarburstMesh.build(...)` — `preload` résout par CHEMIN, jamais par ce
## cache, donc fonctionne immédiatement.
const _StarburstMesh := preload("res://scripts/combat/utility/vfx/StarburstMesh.gd")

static func _spawn_star_layer(pos: Vector3, scene: Node, color: Color, outer: float, inner: float,
		pop_in_s: float, hold_s: float, pop_out_s: float, depth_nudge: Vector3) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _StarburstMesh.build(12, outer, inner)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = mat
	scene.add_child(mi)
	mi.global_position = pos - depth_nudge
	mi.scale = Vector3.ZERO
	var t := mi.create_tween()
	t.tween_property(mi, "scale", Vector3.ONE, pop_in_s).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_interval(hold_s)
	t.tween_property(mi, "scale", Vector3.ZERO, pop_out_s).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_callback(mi.queue_free)

## Éclats de débris (boîtes étirées, non éclairées jaune-blanc) qui filent
## sous la gravité pendant 0.5 s — trajectoire analytique
## (`pos0 + vel*t + 1/2 g t² down`) posée via UN SEUL `tween_method` (pas de
## nœud pilote séparé) : plus simple que d'intégrer image par image pour un
## effet cosmétique qui se libère de toute façon dans la demi-seconde.
static func _spawn_debris_sparks(pos: Vector3, scene: Node, count: int, color: Color) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(pos.x * 1000.0) ^ int(pos.z * 1000.0) ^ int(pos.y * 733.0) ^ 0x5EED
	const GRAVITY := 9.8
	const LIFE_S := 0.5
	for i in count:
		var dir := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(0.15, 1.0), rng.randf_range(-1.0, 1.0)).normalized()
		var vel := dir * rng.randf_range(6.0, 11.0)

		var box := BoxMesh.new()
		box.size = Vector3(0.04, 0.04, 0.25)
		var mi := MeshInstance3D.new()
		mi.mesh = box
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = color
		mi.material_override = mat
		scene.add_child(mi)
		mi.global_position = pos
		if vel.length() > 0.001:
			mi.look_at(pos + vel, Vector3.UP)

		var t := mi.create_tween()
		t.tween_method(func(u: float) -> void:
			var tt := u * LIFE_S
			mi.global_position = pos + vel * tt + Vector3(0.0, -0.5 * GRAVITY * tt * tt, 0.0)
		, 0.0, 1.0, LIFE_S)
		t.tween_callback(mi.queue_free)

## Rafale frag (contrat lead 2026-09-27, "punchy comic burst") : flash blanc
## bref, 7-9 boules de feu toon qui giclent puis noircissent en fumée en
## montant, une étoile BD au centre, des débris. Tout est opaque/toon SAUF le
## flash (unshaded) — voir la docstring de fichier des consts `_FRAG_SFX` etc.
## pour le SFX/la secousse caméra, INCHANGÉS, posés par l'appelant.
static func _spawn_frag_vfx(pos: Vector3, scene: Node) -> void:
	if scene == null:
		return
	_spawn_flash_sphere(pos, scene, 1.8, 0.08, Color("FFF4E0"))
	_spawn_fireball_puffs(pos, scene)
	_spawn_starburst(pos, scene, Color("FFCE1F"), 2.5, 0.05, 0.1, 0.1)
	_spawn_debris_sparks(pos, scene, 14, Color(1.0, 0.95, 0.75))

## 7-9 puffs toon (core signal_yellow / outer #FF7A1A) qui giclent 0.8-1.5 m
## en 0.12 s (ease-out), PUIS noircissent vers un brun-gris de fumée sur
## ~0.3 s, montent 1-1.5 m et rétrécissent à zéro sur le reste de la fenêtre
## (0.12-1.3 s, contrat) — jamais un fondu alpha : le matériau toon reste
## opaque du début à la fin, seule sa teinte et son échelle changent. Couleur
## et mouvement de phase B tournent sur DEUX tweens indépendants créés au même
## instant (plutôt qu'un seul enchaînement `parallel()`, qui forcerait la
## seconde étape de teinte à attendre la fin du mouvement au lieu de courir en
## même temps que lui) — voir CHK note ci-dessous.
static func _spawn_fireball_puffs(pos: Vector3, scene: Node) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(pos.x * 1000.0) ^ int(pos.z * 1000.0) ^ int(pos.y * 1000.0) ^ 99
	const BURST_S := 0.12
	const DARKEN_S := 0.3
	const SMOKE_S := 0.88  # DARKEN_S + SMOKE_S == 1.18 == fenêtre totale de phase B (0.12 -> 1.3 s).
	var count := rng.randi_range(7, 9)
	for i in count:
		var dir := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(0.3, 1.0), rng.randf_range(-1.0, 1.0)).normalized()
		var burst_dist := rng.randf_range(0.8, 1.5)
		var puff_radius := rng.randf_range(0.5, 1.1)
		var fireball_color: Color = Color("FFCE1F").lerp(Color("FF7A1A"), rng.randf())
		var mid_color := Color("5A4E4A")
		var dark_color := Color("3A3436")
		var rise := rng.randf_range(1.0, 1.5)

		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 1.0
		sm.height = 2.0
		sm.radial_segments = 10
		sm.rings = 6
		mi.mesh = sm
		var mat := ToonStyle.toon_material(null, fireball_color)
		mi.material_override = mat
		scene.add_child(mi)
		mi.global_position = pos
		mi.scale = Vector3.ZERO

		var burst_t := mi.create_tween()
		burst_t.tween_property(mi, "scale", Vector3.ONE * puff_radius, BURST_S).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		burst_t.parallel().tween_property(mi, "global_position", pos + dir * burst_dist, BURST_S).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		burst_t.tween_callback(func() -> void:
			if not is_instance_valid(mi):
				return
			var rise_target: Vector3 = mi.global_position + Vector3(0, rise, 0)

			var color_t := mi.create_tween()
			color_t.tween_method(func(c: Color) -> void: mat.set_shader_parameter("albedo_color", c), fireball_color, mid_color, DARKEN_S)
			color_t.tween_method(func(c: Color) -> void: mat.set_shader_parameter("albedo_color", c), mid_color, dark_color, SMOKE_S)

			var motion_t := mi.create_tween()
			motion_t.tween_property(mi, "global_position", rise_target, DARKEN_S + SMOKE_S).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
			motion_t.parallel().tween_property(mi, "scale", Vector3.ZERO, DARKEN_S + SMOKE_S).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
			motion_t.tween_callback(mi.queue_free)
		)

## Détonation flash (contrat : "reuse the same starburst in white/yellow plus
## a bigger white flash sphere (radius to 3 m, 0.1 s). No fireball.") — garde
## la lumière `OmniLight3D` de l'ancienne version (éclairage ponctuel de la
## pièce, jamais mentionné à retirer) mais remplace la sphère alpha-fondue
## par la même sphère unshaded opaque que la frag, agrandie.
static func _spawn_flash_vfx(pos: Vector3, scene: Node) -> void:
	if scene == null:
		return
	_spawn_flash_sphere(pos, scene, 3.0, 0.1, Color.WHITE)
	_spawn_starburst(pos, scene, Color("FFF4E0"), 2.5, 0.05, 0.1, 0.1)

	var light_holder := Node3D.new()
	scene.add_child(light_holder)
	light_holder.global_position = pos
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 1.0, 0.95)
	light.light_energy = 8.0
	light.omni_range = 25.0
	light_holder.add_child(light)
	var t := light_holder.create_tween()
	t.tween_property(light, "light_energy", 0.0, 0.3)
	t.tween_callback(light_holder.queue_free)
