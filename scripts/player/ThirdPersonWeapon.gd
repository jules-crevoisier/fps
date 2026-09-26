## ThirdPersonWeapon.gd
## Affiche l'arme en main sur un joueur DISTANT — attachée à la main droite du
## CORPS 3D (BoneAttachment3D sur l'os "DEF-hand.R" du squelette de
## CharacterBody.gd, voir scenes/player/player.tscn) avec un décalage de prise
## par CATÉGORIE d'arme (WeaponConfig.category — SIDEARM/SMG/RIFLE/SHOTGUN/
## SNIPER/HEAVY/MELEE n'ont pas la même taille, voir `_GRIP_OFFSETS`, réglé
## par capture in-game — tools/char_ingame_shots.gd). Inerte pour le joueur
## LOCAL (qui voit son ViewModel à la place, comme le corps caché par
## PlayerLook — voir contract-r2.md).
## Source de vérité réseau : `Weapon.current_id_changed` (diffusé à TOUS les
## pairs, contrairement à la synchro d'inventaire complète qui ne part que
## vers le propriétaire) pour savoir quel modèle afficher, et
## `Weapon.remote_fired` pour le recul/flash cosmétique au tir des autres.
class_name ThirdPersonWeapon
extends Node3D

## Décalage de prise (position locale + rotation) par catégorie, appliqué au
## modèle une fois attaché au BoneAttachment3D de la main droite — les armes
## n'ont pas de marqueur "Grip" (voir tools/blender/make_weapons.py, seul
## "Muzzle" existe) donc ce sont des valeurs réglées à l'œil via les captures
## in-game (tools/char_ingame_shots.gd), pas une donnée déduite du modèle.
const _GRIP_OFFSETS := {
	WeaponConfig.Category.SIDEARM: {"pos": Vector3(0.02, -0.03, 0.05), "rot_deg": Vector3(0, 90, 0)},
	WeaponConfig.Category.SMG: {"pos": Vector3(0.0, -0.04, 0.02), "rot_deg": Vector3(0, 90, 0)},
	WeaponConfig.Category.RIFLE: {"pos": Vector3(0.0, -0.05, -0.02), "rot_deg": Vector3(0, 90, 0)},
	WeaponConfig.Category.SHOTGUN: {"pos": Vector3(0.0, -0.05, -0.06), "rot_deg": Vector3(0, 90, 0)},
	WeaponConfig.Category.SNIPER: {"pos": Vector3(0.0, -0.05, -0.1), "rot_deg": Vector3(0, 90, 0)},
	WeaponConfig.Category.HEAVY: {"pos": Vector3(0.0, -0.06, -0.12), "rot_deg": Vector3(0, 90, 0)},
	WeaponConfig.Category.MELEE: {"pos": Vector3(0.02, -0.02, 0.03), "rot_deg": Vector3(0, 90, 0)},
}
const _DEFAULT_GRIP := {"pos": Vector3(0.0, -0.04, 0.0), "rot_deg": Vector3(0, 90, 0)}
const _HAND_BONE := "DEF-hand.R"
## Nom du nœud que scenes/characters/<agent>.tscn peut exposer (BoneAttachment3D
## sur "RightHand" -> Node3D "WeaponSocket", ex. frog_cowboy.tscn) : le point
## d'attache vient alors du PERSONNAGE (transform de ce nœud, réglable par
## l'utilisateur dans l'éditeur), plus jamais d'un nom d'os codé en dur ici --
## repli sur `_HAND_BONE`/`_GRIP_OFFSETS` (BoneAttachment3D créé en code, comme
## avant) pour tout agent qui n'a pas encore ce nœud (les 5 autres glb Tripo).
const _WEAPON_SOCKET_NAME := "WeaponSocket"

var player: PlayerController
var weapon: Weapon
var _character_body: CharacterBody
var _bone_attach: BoneAttachment3D
var _weapon_socket: Node3D
var _model: Node3D
var _muzzle: Node3D
var _muzzle_mesh: MeshInstance3D
var _current_id: int = Inventory.EMPTY
var _muzzle_t: float = 0.0

const MUZZLE_DUR := 0.05

func _ready() -> void:
	player = get_parent() as PlayerController
	if player == null:
		return
	# Rien à afficher chez SOI (on voit le ViewModel à la place) : la vérité
	# d'autorité n'est connue qu'après le spawn réseau, donc on ré-essaie
	# jusqu'à ce que l'autorité soit tranchée (même stratégie que PlayerLook).
	if player.is_multiplayer_authority():
		visible = false
		set_process(false)
		return
	_character_body = player.get_node_or_null("%CharacterModel") as CharacterBody
	if _character_body:
		if _character_body.is_model_ready():
			_on_body_ready()
		else:
			_character_body.model_ready.connect(_on_body_ready)
	weapon = player.get_node_or_null("Weapon") as Weapon
	if weapon:
		weapon.current_id_changed.connect(_on_current_id_changed)
		weapon.remote_fired.connect(_on_remote_fired)
		_on_current_id_changed(WeaponDatabase.id_of(weapon.cfg()))

## Résout le point d'attache une fois le squelette du corps chargé — si
## l'arme était déjà instanciée (résolue avant le corps), on la rattache
## immédiatement au lieu d'attendre le prochain changement d'arme.
## Priorité au nœud "WeaponSocket" du personnage (scenes/characters/<agent>.tscn,
## ex. frog_cowboy.tscn — déjà un BoneAttachment3D sur la main droite retargetée,
## voir sa doc de classe) ; repli sur l'ancien BoneAttachment3D codé en dur
## (`_HAND_BONE`) pour un agent qui n'a pas encore ce nœud.
func _on_body_ready() -> void:
	_weapon_socket = _character_body.find_child(_WEAPON_SOCKET_NAME, true, false) as Node3D
	if _weapon_socket == null:
		var skeleton := _character_body.get_skeleton()
		if skeleton == null:
			return
		_bone_attach = BoneAttachment3D.new()
		_bone_attach.bone_name = _HAND_BONE
		skeleton.add_child(_bone_attach)
	if _model:
		_reparent_model_to_hand()

func _process(delta: float) -> void:
	if _muzzle_mesh and _muzzle_t > 0.0:
		_muzzle_t -= delta
		_muzzle_mesh.visible = _muzzle_t > 0.0

func _on_current_id_changed(id: int) -> void:
	if id == _current_id and _model:
		return
	var weapon_id := id
	_current_id = id
	if _model:
		_model.queue_free()
		_model = null
		_muzzle = null
		_muzzle_mesh = null
	if id == Inventory.EMPTY:
		return
	var path := Weapon.model_path_for(id)
	if path.is_empty() or not ResourceLoader.exists(path):
		return
	var scene := load(path) as PackedScene
	if scene == null:
		return
	_model = scene.instantiate() as Node3D
	if _weapon_socket or _bone_attach:
		_reparent_model_to_hand(weapon_id)
	else:
		# Squelette pas encore prêt (course de chargement) : on affiche l'arme
		# à la racine en attendant `_on_body_ready` (voir `_reparent_model_to_hand`,
		# rappelé une fois le BoneAttachment3D créé).
		add_child(_model)
	_apply_cartoon_materials(_model)
	_muzzle = _model.find_child("Muzzle", true, false) as Node3D
	_spawn_muzzle_flash()

## Rattache `_model` (déjà instancié) au BoneAttachment3D de la main droite,
## avec le décalage de prise de SA catégorie (`_GRIP_OFFSETS`). `category` :
## par défaut, relit `weapon.cfg()` (cas rappelé depuis `_on_body_ready`, où
## l'id courant n'est plus dans la pile d'appel) — sinon reçoit l'id qui vient
## d'être posé (évite un aller-retour `WeaponDatabase.get_by_id` redondant).
func _reparent_model_to_hand(weapon_id: int = -1) -> void:
	if _model.get_parent():
		_model.get_parent().remove_child(_model)
	if _weapon_socket:
		# Point d'attache venant du PERSONNAGE (scenes/characters/<agent>.tscn,
		# transform de "WeaponSocket" réglable par l'utilisateur dans l'éditeur --
		# requirement "the attach point coming from the character, not hard-coded") :
		# identité locale, aucun décalage par catégorie d'arme ici, contrairement au
		# repli _bone_attach ci-dessous.
		_weapon_socket.add_child(_model)
		_model.transform = Transform3D.IDENTITY
		_apply_scale_correction(_model)
		return
	_bone_attach.add_child(_model)
	var cfg: WeaponConfig = WeaponDatabase.get_by_id(weapon_id) if weapon_id >= 0 else (weapon.cfg() if weapon else null)
	var grip: Dictionary = _GRIP_OFFSETS.get(cfg.category, _DEFAULT_GRIP) if cfg else _DEFAULT_GRIP
	var pos: Vector3 = grip["pos"]
	var rot_deg: Vector3 = grip["rot_deg"]
	_model.transform = Transform3D(Basis.from_euler(Vector3(deg_to_rad(rot_deg.x), deg_to_rad(rot_deg.y), deg_to_rad(rot_deg.z))), pos)
	_apply_scale_correction(_model)

## Contrepoids de l'échelle du CORPS (CharacterBody._scale_to_target_height,
## TARGET_HEIGHT / hauteur du maillage -- souvent != 1, ex. Frog Cowboy ≈1.8)
## sur l'arme rattachée sous WeaponSocket/BoneAttachment3D : les DEUX
## descendent du modèle 3D du corps, déjà mis à l'échelle, alors que l'arme est
## modélisée à sa taille RÉELLE (Blender) -- sans ce contrepoids elle
## grossit/rétrécit AVEC le personnage (constaté : crosse géante ≈x1.8 sur
## Frog Cowboy, voir capture). Neutralise l'échelle GLOBALE du parent direct
## pour ramener celle de l'arme à ~1, quel que soit `TARGET_HEIGHT` (fonction
## pure `counter_scale_for`, testée directement).
func _apply_scale_correction(model: Node3D) -> void:
	var parent := model.get_parent() as Node3D
	if parent == null:
		return
	model.scale = counter_scale_for(parent.global_transform.basis.get_scale())

## Échelle LOCALE à appliquer pour qu'un enfant direct d'un nœud à l'échelle
## GLOBALE `parent_global_scale` se retrouve avec une échelle globale de 1,
## composante par composante -- repli défensif à 1.0 sur une composante quasi
## nulle (jamais de division par zéro/valeur infinie).
static func counter_scale_for(parent_global_scale: Vector3) -> Vector3:
	return Vector3(
		1.0 / parent_global_scale.x if not is_zero_approx(parent_global_scale.x) else 1.0,
		1.0 / parent_global_scale.y if not is_zero_approx(parent_global_scale.y) else 1.0,
		1.0 / parent_global_scale.z if not is_zero_approx(parent_global_scale.z) else 1.0,
	)

## Position MONDE du canon (empty "Muzzle" du modèle 3D courant, voir
## `_on_current_id_changed`) — utilisée par Weapon.gd (GF-06) pour dessiner
## le traceur d'un tir DISTANT depuis l'arme telle que la voient les AUTRES
## joueurs (voir Weapon._muzzle_position). Repli sur la position de ce nœud
## (main droite du corps) si le modèle n'est pas encore chargé.
func muzzle_global_position() -> Vector3:
	return _muzzle.global_position if _muzzle else global_position

func _on_remote_fired(_cfg: WeaponConfig, _origin: Vector3, _dirs: Array) -> void:
	_muzzle_t = MUZZLE_DUR
	if _muzzle_mesh:
		_muzzle_mesh.visible = true

func _apply_cartoon_materials(model: Node3D) -> void:
	var palette := {
		"body": Cartoon.INK.lightened(0.35),
		"grip": Color(0.14, 0.13, 0.12),
		"metal": Color(0.55, 0.56, 0.6),
		"accent": Cartoon.enemy_color() if _is_enemy() else Cartoon.ally_color(),
	}
	for mesh in _find_mesh_instances(model):
		if mesh.mesh == null:
			continue
		# Voir ViewModel.gd : AABB exportée parfois fausse pour la surface
		# "body" (bug exporteur glTF), marge de culling en garde.
		mesh.extra_cull_margin = 2.0
		for i in mesh.mesh.get_surface_count():
			var mat: Material = mesh.mesh.surface_get_material(i)
			var name: String = mat.resource_name if mat else ""
			# Arme Tripo peinte (A3D-20) : même matériau que ViewModel.gd.
			if name.contains("_painted"):
				var tex := Cartoon.texture_from_imported_material(mat)
				mesh.set_surface_override_material(i, Cartoon.painted_texture_prop(tex))
				continue
			for slot in palette.keys():
				if name.ends_with("_%s" % slot):
					mesh.set_surface_override_material(i, Cartoon.character(palette[slot]))
					break

## Équipe locale vs celle du joueur distant : relatif au joueur LOCAL, comme
## PlayerLook (contract-r2.md). -1 tant que le local n'existe pas -> allié par
## défaut (pas d'accent alarmant avant d'avoir l'info).
func _is_enemy() -> bool:
	var me := get_tree().get_first_node_in_group("local_player") if is_inside_tree() else null
	if me == null or player == null:
		return false
	return me.get("team") != player.team

func _find_mesh_instances(root: Node) -> Array:
	var out: Array = []
	if root is MeshInstance3D:
		out.append(root)
	for c in root.get_children():
		out.append_array(_find_mesh_instances(c))
	return out

func _spawn_muzzle_flash() -> void:
	if _muzzle == null:
		return
	_muzzle_mesh = MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(0.1, 0.1)
	_muzzle_mesh.mesh = qm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.92, 0.55)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_muzzle_mesh.material_override = mat
	_muzzle_mesh.visible = false
	_muzzle.add_child(_muzzle_mesh)
