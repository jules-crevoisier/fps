## ViewModel.gd
## Arme + gants vus par le joueur LOCAL uniquement — enfant de Head/Camera3D
## (voir scenes/player/player.tscn).
##
## Lead call (tâche "fp gloves", après 3 échecs successifs sur le rig
## fp_arms.glb squeletté — un bras plein réutilisant le rig corps entier des
## agents, posé "FP_Hold" puis résolu vers la main gauche via
## `solve_grip_transform`/`shortest_arc_basis` : le résultat rendait
## systématiquement un bras qui traverse l'écran de travers avec une arme
## illisible, voir scratchpad/shots/fp_final/fp_ravage.png) : plus de
## squelette, plus de pose, plus de solveur d'orientation main-cible. À la
## place, deux gants FLOTTANTS façon Rayman (assets/models/characters/
## fp_gloves.glb, tools/blender/make_gloves.py — pas d'avant-bras, juste une
## manchette courte) dont l'ORIGINE de chaque maillage est DÉJÀ le point de
## contact avec l'arme : le gant droit ("GloveR") se rattache tel quel
## (transform IDENTITÉ) à l'origine de l'arme (= la poignée, cf.
## tools/blender/make_weapons.py) et le gant gauche ("GloveL") vers son empty
## "Foregrip" — PAS de solveur d'orientation générique comme avant, juste un
## repositionnement dans l'arbre de scène (`_load_gloves`/`_attach_gloves`) et
## une seule petite correction locale (`_left_glove_anchor`, voir sa doc :
## "Foregrip" tombe à l'intérieur de la géométrie de l'arme sur les 7
## modèles, donc on le pousse vers "Muzzle" d'une fraction fixe). Robuste :
## chaque arme porte déjà ses propres points d'ancrage, un gant générique un
## peu plus gros que le gabarit réel (style "chunky") les enveloppe quelle
## que soit l'arme, sans réglage par arme.
##
## L'arme (assets/models/weapons/*.glb, voir tools/blender/make_weapons.py et
## Weapon.model_path_for) est posée directement en enfant de CE nœud
## (`_place_weapon`) : une légère rotation lacet (`_MODEL_YAW_DEG`) tourne le
## canon vers le centre de l'écran (cadrage FPS classique : arme parallèle à
## la vue, entrant en bas à droite, canon pointant vers le viseur, côté droit
## visible) plutôt que de pointer bras tendu droit devant ; une échelle et un
## petit décalage par catégorie (`_WEAPON_SCALE`/`_WEAPON_NUDGE`) ajustent le
## cadrage à l'œil (voir tools/fp_shots.gd) pour les armes très longues
## (sniper/lourde) sans dénaturer les courtes.
##
## Matériaux : arme = `Cartoon.character(...)` (inchangé, contour fin — voir
## `_THIN_OUTLINE_PX`), gants = `Cartoon.character_surface(...)` (gant = cuir
## moyen, couleur exportée par make_gloves.py, jamais quasi noir ; manchette =
## couleur d'équipe, toujours alliée depuis sa propre vue — design.md v2,
## « glove = mid-tone leather, cuff = team colour »).
##
## Pilote une animation procédurale (sway souris, bob, recul-ressort, dip de
## rechargement, montée d'équipement, visée, tilt de slide) appliquée à CE
## nœud (`position`/`rotation`) — la racine arme+gants, donc les deux en
## héritent ensemble. En plus, un petit geste de rechargement DÉDIÉ au gant
## gauche seul (`AnimState.reload_glove_offset`) : il plonge vers la zone du
## chargeur puis revient, synchronisé sur le même minuteur que le dip
## d'ensemble (`reload_t`/`reload_dur`) mais avec sa propre trajectoire
## locale (relative à sa position de repos sur le Foregrip), pour lire comme
## un vrai geste de main plutôt qu'un simple déplacement de caméra.
## Modèle tenu PETIT et PRÈS de la caméra (jamais dans le champ de la capsule
## du joueur, rayon 0.4 m, cf. acceptance R-A2 #2) : c'est ce qui évite le
## clipping dans les murs (pas de near-plane dédié, juste la proximité —
## "the small/near trick").
## Toute la PHYSIQUE/anim est dans `AnimState` (RefCounted, sans arbre de
## scène) pour rester testable sans instancier de Node3D — voir
## tests/combat/test_weapon_fx.gd (recul/sway/bob/reload/equip/muzzle/blends)
## et tests/player/test_viewmodel_pose_math.gd (`reload_glove_offset`).
class_name ViewModel
extends Node3D

## Position de repos du modèle par rapport à la caméra (arme+gants tenus en
## bas à droite, un peu vers l'avant — jamais dans le champ de la capsule du
## joueur, rayon 0.4 m, cf. acceptance R-A2 #2). Ces valeurs supposent que la
## poignée de l'arme (son origine) est à la racine LOCALE de ce nœud (0,0,0) —
## vrai maintenant que l'arme est un enfant direct sans décalage caché (voir
## `_place_weapon` : nudge/échelle par catégorie, mais jamais de gros offset
## de compensation comme l'ancien `_ARMS_ROOT_OFFSET` du rig squeletté).
const REST_POS := Vector3(0.16, -0.17, -0.50)
const ADS_POS := Vector3(0.0, -0.02, -1.15)

## Contour d'encre pour l'arme ET les gants du viewmodel (design.md §5
## « Viewmodel et pickups : 2 px d'encre ») — plus fin que le contour
## PERSONNAGE par défaut (3 px, `Cartoon.character()` sans argument), jamais
## atténué par la distance puisque le viewmodel est toujours à quelques
## centimètres de la caméra.
const _THIN_OUTLINE_PX := 2.0

const GLOVES_PATH := "res://assets/models/characters/fp_gloves.glb"
## Repli si un gant "GloveR"/"GloveL" est introuvable dans fp_gloves.glb (ne
## devrait jamais arriver hors développement du modèle) ou si l'arme n'a pas
## d'empty "Foregrip" valide.
const _DEFAULT_FOREGRIP_LOCAL := Vector3(0.0, 0.05, -0.3)

## Légère rotation lacet (autour de Y) appliquée à l'arme (et donc aux deux
## gants, enfants d'elle) : PAS nécessaire pour la convergence canon->viseur
## (elle est déjà automatique — un canon -Z strictement parallèle à l'axe
## caméra, tiré depuis une position décalée à droite, converge tout seul vers
## le centre écran par simple perspective, vérifié via `Camera3D.
## unproject_position` pendant le réglage de cette tâche). Son seul rôle est
## de révéler le FLANC droit de l'arme (silhouette lisible en volume plutôt
## qu'un profil plat vu de dos) ; réglé à l'œil via tools/fp_shots.gd.
const _MODEL_YAW_DEG := 9.0

## Échelle/décalage par catégorie (WeaponConfig.Category) : les armes très
## longues (sniper/lourde) occuperaient sinon une part disproportionnée du
## cadrage bas-droit une fois la rotation/le "small-near trick" appliqués ;
## une petite réduction d'échelle les ramène à un gabarit apparent proche des
## armes courtes SANS avoir besoin de résoudre une distance poignée<->main
## comme l'ancien système squeletté. Réglé à l'œil via tools/fp_shots.gd.
const _WEAPON_SCALE := {
	WeaponConfig.Category.SNIPER: 0.8,
	WeaponConfig.Category.HEAVY: 0.85,
	WeaponConfig.Category.SHOTGUN: 0.92,
}
const _DEFAULT_WEAPON_SCALE := 1.0
const _WEAPON_NUDGE := {
	WeaponConfig.Category.SNIPER: Vector3(0.0, 0.01, 0.08),
	WeaponConfig.Category.HEAVY: Vector3(0.0, -0.01, 0.04),
}
const _DEFAULT_WEAPON_NUDGE := Vector3.ZERO

var player: PlayerController
var weapon: Weapon
var _anim := AnimState.new()
var _current_id: int = Inventory.EMPTY
var _model: Node3D
var _muzzle: Node3D
var _muzzle_mesh: MeshInstance3D
## Les deux gants, chargés UNE FOIS (voir `_load_gloves`) et reparentés sous
## l'arme courante à chaque changement (`_attach_gloves`) — jamais recréés,
## contrairement à `_model` qui est détruit/reconstruit par arme.
var _glove_r: Node3D
var _glove_l: Node3D
## Position de repos locale du gant gauche (celle de l'empty "Foregrip" de
## l'arme courante) : le geste de rechargement (`AnimState.
## reload_glove_offset`) s'ajoute PAR-DESSUS cette valeur chaque frame plutôt
## que de la modifier directement, pour ne jamais dériver au fil des
## rechargements.
var _glove_l_rest: Vector3 = Vector3.ZERO
var _last_mouse_delta: Vector2 = Vector2.ZERO
var _ads_t: float = 1.0        # 1 = hanche, 0 = visée
var _sprint_t: float = 0.0
var _slide_t: float = 0.0

func _ready() -> void:
	player = get_parent().get_parent().get_parent() as PlayerController
	if player == null or not player.is_local_human():
		set_process(false)
		set_process_input(false)
		visible = false
		return
	weapon = player.get_node_or_null("Weapon") as Weapon
	if weapon:
		weapon.fired.connect(_on_fired)
		weapon.reload_started.connect(_on_reload_started)
		weapon.weapon_changed.connect(_on_weapon_changed)
	position = REST_POS
	_load_gloves()
	_refresh_model()

## Charge fp_gloves.glb UNE FOIS (les gants eux-mêmes ne changent jamais,
## contrairement à l'arme) : extrait "GloveR"/"GloveL" de la scène importée et
## jette le reste (l'empty racine "Gloves" de tools/blender/make_gloves.py,
## qui ne sert qu'à donner à l'export un unique nœud racine). Les deux gants
## restent SANS PARENT jusqu'à la première `_attach_gloves` (appelée par
## `_refresh_model` juste après).
func _load_gloves() -> void:
	if not ResourceLoader.exists(GLOVES_PATH):
		push_warning("ViewModel : fp_gloves introuvable (%s)" % GLOVES_PATH)
		return
	var packed := load(GLOVES_PATH) as PackedScene
	if packed == null:
		return
	var gloves := packed.instantiate() as Node3D
	if gloves == null:
		return
	_glove_r = gloves.find_child("GloveR", true, false) as Node3D
	_glove_l = gloves.find_child("GloveL", true, false) as Node3D
	for g in [_glove_r, _glove_l]:
		if g == null:
			continue
		g.get_parent().remove_child(g)
		# Efface l'owner hérité de la scène importée (le "Gloves" temporaire) :
		# sans ça, chaque réattache sous une nouvelle arme (`_attach_gloves`)
		# avertit "will make owner inconsistent" (l'owner d'origine n'existe
		# plus une fois `gloves.queue_free()` appelé ci-dessous).
		_clear_owner(g)
		_apply_glove_materials(g)
	gloves.queue_free()
	if _glove_r == null or _glove_l == null:
		push_warning("ViewModel : GloveR/GloveL introuvables dans fp_gloves.glb")

func _clear_owner(n: Node) -> void:
	n.owner = null
	for c in n.get_children():
		_clear_owner(c)

func _apply_glove_materials(glove: Node3D) -> void:
	for mesh in _find_mesh_instances(glove):
		if mesh.mesh == null:
			continue
		mesh.extra_cull_margin = 2.0
		for i in mesh.mesh.get_surface_count():
			var mat: Material = mesh.mesh.surface_get_material(i)
			var mat_name: String = mat.resource_name if mat else ""
			if mat_name.ends_with("_cuff"):
				mesh.set_surface_override_material(i, Cartoon.character_surface("cloth", Cartoon.ally_color()))
			elif mat_name.ends_with("_glove"):
				var src := mat as BaseMaterial3D
				var color: Color = src.albedo_color if src else Color(0.42, 0.29, 0.20)
				mesh.set_surface_override_material(i, Cartoon.character_surface("gear", color))
		# Contour fin dédié viewmodel (voir `_apply_cartoon_materials`, même
		# traitement pour l'arme) : `next_pass` déjà fabriqué par l'API
		# publique `Cartoon.character(color, outline_px)`.
		var thin_outline := Cartoon.character(Color.WHITE, _THIN_OUTLINE_PX).next_pass
		for i in mesh.mesh.get_surface_count():
			var applied: Material = mesh.get_surface_override_material(i)
			if applied:
				applied.next_pass = thin_outline

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_last_mouse_delta += event.relative

func _process(delta: float) -> void:
	if player == null or weapon == null:
		return
	var sm := player.state_machine.current_name if player.state_machine else ""
	var aiming := player.input.aim_held
	var c := weapon.cfg()
	var ads_speed := 1.0 / maxf(c.ads_time, 0.001) if c else 10.0
	_ads_t = _anim.ads_blend(aiming, _ads_t, delta, ads_speed)
	_sprint_t = _anim.sprint_pose_blend(false, _sprint_t, delta)
	_slide_t = _anim.slide_tilt_blend(sm == "Slide", _slide_t, delta)

	_anim.tick_sway(_last_mouse_delta, delta)
	_last_mouse_delta = Vector2.ZERO
	_anim.tick_recoil(delta)
	var bob := _anim.tick_bob(player.horizontal_speed(), 9.0, delta)
	var reload_off := _anim.tick_reload(delta)
	var equip_off := _anim.tick_equip(delta)

	var base := REST_POS.lerp(ADS_POS, 1.0 - _ads_t)
	var proc := Vector3(_anim.sway_offset.x, _anim.sway_offset.y, 0.0) * _ads_t \
		+ bob * _ads_t + Vector3(0, _anim.recoil_offset.y * 0.02, _anim.recoil_offset.y * 0.03) \
		+ reload_off + equip_off + Vector3(0, -_sprint_t * 0.03, _sprint_t * 0.05)
	position = position.lerp(base + proc, clampf(18.0 * delta, 0.0, 1.0))
	rotation.z = -_slide_t * deg_to_rad(6.0) - _anim.sway_offset.x * 1.5
	rotation.x = _anim.recoil_offset.y * 0.35

	# Geste de rechargement dédié au gant gauche seul (voir doc de classe) :
	# doit être lu APRÈS `tick_reload` ci-dessus, qui avance le minuteur
	# partagé `reload_t`/`reload_dur`.
	if _glove_l:
		_glove_l.position = _glove_l_rest + _anim.reload_glove_offset()

	if _muzzle_mesh:
		_muzzle_mesh.visible = _anim.is_muzzle_visible()
		if not _anim.tick_muzzle(delta):
			_muzzle_mesh.visible = false

func _on_fired(cfg: WeaponConfig) -> void:
	if cfg == null:
		return
	_anim.kick_recoil(Vector3(0, deg_to_rad(cfg.recoil_vertical) * 6.0, 0))
	_anim.trigger_muzzle_flash()

func _on_reload_started(cfg: WeaponConfig) -> void:
	if cfg:
		_anim.start_reload(cfg.reload_time)

func _on_weapon_changed(_cfg: WeaponConfig) -> void:
	_anim.start_equip()
	_refresh_model()

## (Re)charge le modèle 3D correspondant à l'arme courante, la place pour le
## cadrage FPS classique (`_place_weapon`), y rattache les deux gants
## (`_attach_gloves`) et pose les matériaux Cartoon.character(...) par slot
## (body/grip/metal/accent), avec l'accent teinté couleur d'équipe.
func _refresh_model() -> void:
	var id := WeaponDatabase.id_of(weapon.cfg()) if weapon else Inventory.EMPTY
	if id == _current_id and _model:
		return
	_current_id = id
	if _model:
		_model.queue_free()
		_model = null
	if id == Inventory.EMPTY:
		return
	var path := Weapon.model_path_for(id)
	if path.is_empty() or not ResourceLoader.exists(path):
		return
	var scene := load(path) as PackedScene
	if scene == null:
		return
	_model = scene.instantiate() as Node3D
	add_child(_model)
	_place_weapon(id)
	_attach_gloves()
	_apply_cartoon_materials(_model)
	_muzzle = _model.find_child("Muzzle", true, false) as Node3D
	_spawn_muzzle_flash()

## Pose l'arme en enfant direct de ce nœud : lacet fixe (`_MODEL_YAW_DEG`,
## cadrage FPS classique — voir sa doc) + échelle/décalage par catégorie
## (`_WEAPON_SCALE`/`_WEAPON_NUDGE`) pour les gabarits extrêmes (sniper/
## lourde). La poignée (origine de l'arme) reste le pivot de cette rotation,
## donc aussi le point où le gant droit se rattache ensuite (`_attach_gloves`).
func _place_weapon(weapon_id: int) -> void:
	var cfg := WeaponDatabase.get_by_id(weapon_id)
	var scale: float = _WEAPON_SCALE.get(cfg.category, _DEFAULT_WEAPON_SCALE) if cfg else _DEFAULT_WEAPON_SCALE
	var nudge: Vector3 = _WEAPON_NUDGE.get(cfg.category, _DEFAULT_WEAPON_NUDGE) if cfg else _DEFAULT_WEAPON_NUDGE
	var yaw := Basis(Vector3.UP, deg_to_rad(_MODEL_YAW_DEG))
	_model.transform = Transform3D(yaw.scaled(Vector3.ONE * scale), nudge)

## Rattache les deux gants (chargés une fois, voir `_load_gloves`) à l'arme
## COURANTE : le droit à son origine (= la poignée, transform identité — les
## deux origines coïncident par construction, voir tools/blender/
## make_gloves.py), le gauche vers son empty "Foregrip" — mais PAS pile
## dessus, voir `_left_glove_anchor`. Aucune résolution géométrique basée sur
## une pose de squelette mesurée (l'ancien `solve_grip_transform`, supprimé
## avec fp_arms) : juste une petite correction de point d'ancrage, dérivée
## des deux empties déjà présents sur CETTE arme (Foregrip + Muzzle).
func _attach_gloves() -> void:
	if _glove_r:
		_reparent(_glove_r, _model)
		_glove_r.transform = Transform3D.IDENTITY
	if _glove_l:
		_reparent(_glove_l, _model)
		_glove_l_rest = _left_glove_anchor()
		_glove_l.rotation = Vector3.ZERO
		_glove_l.position = _glove_l_rest

## L'empty "Foregrip" (tools/blender/make_weapons.py, `(muzzle_x, muzzle_y*
## 0.85, muzzle_z*fraction)`) a été placé comme cible de main de SQUELETTE,
## pas comme surface : sur les 7 armes, il tombe à l'INTÉRIEUR du bloc "body"
## (constaté par rendu — le gant gauche disparaissait, avalé par la
## géométrie de l'arme). Le pousser vers "Muzzle" d'une fraction FIXE de la
## distance restante (`_FOREGRIP_FORWARD_T`) le fait sortir de ce bloc quelle
## que soit la longueur de l'arme (canon court de pistolet ou long de fusil
## de précision), SANS lire la géométrie réelle de l'arme (empties seuls).
## Ça ne suffit pourtant pas à le rendre VISIBLE depuis la caméra FPS
## (constaté par rendu, itérations tools/fp_shots.gd) : la caméra est très
## proche et au-dessus de l'arme (voir REST_POS), donc un point techniquement
## hors du bloc "body" en coordonnées locales reste souvent masqué par la
## silhouette du récepteur depuis cet angle précis. `_LEFT_GLOVE_DOWN_NUDGE`
## (malgré son nom, plus vers le haut/le côté révélé par `_MODEL_YAW_DEG`
## qu'un pur "vers le bas" — ajusté à l'œil, plusieurs rendus) sort le gant
## de cette ombre pour que sa manchette d'équipe reste visible.
const _FOREGRIP_FORWARD_T := 0.4
const _LEFT_GLOVE_DOWN_NUDGE := Vector3(0.15, 0.10, 0.0)

func _left_glove_anchor() -> Vector3:
	var foregrip := _model.find_child("Foregrip", true, false) as Node3D
	var muzzle := _model.find_child("Muzzle", true, false) as Node3D
	var anchor: Vector3 = foregrip.position if foregrip else _DEFAULT_FOREGRIP_LOCAL
	if muzzle:
		anchor = anchor.lerp(muzzle.position, _FOREGRIP_FORWARD_T)
	return anchor + _LEFT_GLOVE_DOWN_NUDGE

func _reparent(node: Node3D, new_parent: Node3D) -> void:
	var old := node.get_parent()
	if old == new_parent:
		return
	if old:
		old.remove_child(node)
	new_parent.add_child(node)

func _apply_cartoon_materials(model: Node3D) -> void:
	var palette := {
		"body": Cartoon.INK.lightened(0.35),
		"grip": Color(0.14, 0.13, 0.12),
		"metal": Color(0.55, 0.56, 0.6),
		"accent": Cartoon.ally_color(),
	}
	for mesh in _find_mesh_instances(model):
		if mesh.mesh == null:
			continue
		# Le AABB exporté par Blender pour la surface "body" (fusion de
		# plusieurs blocs disjoints du même matériau) est parfois un cube
		# unité par défaut au lieu des bornes réelles (bug de l'exporteur
		# glTF constaté sur les 7 armes, vertices corrects mais AABB fausse) :
		# sans marge de culling, Godot peut couper l'arme hors champ alors
		# qu'elle est bien face caméra. Même parade que InkPost.gd.
		mesh.extra_cull_margin = 2.0
		for i in mesh.mesh.get_surface_count():
			var mat: Material = mesh.mesh.surface_get_material(i)
			var name: String = mat.resource_name if mat else ""
			for slot in palette.keys():
				if name.ends_with("_%s" % slot):
					mesh.set_surface_override_material(i, Cartoon.character(palette[slot], _THIN_OUTLINE_PX))
					break

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
	qm.size = Vector2(0.12, 0.12)
	_muzzle_mesh.mesh = qm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.92, 0.55)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_muzzle_mesh.material_override = mat
	_muzzle_mesh.visible = false
	_muzzle.add_child(_muzzle_mesh)


## Anim procédurale PURE (aucun accès à l'arbre de scène) : recul-ressort,
## sway souris, bob marche/sprint, dip de rechargement (+ son geste de gant
## gauche dédié), montée d'équipement, flash au canon, et les blends visée/
## sprint/slide. Testée directement dans tests/combat/test_weapon_fx.gd et
## tests/player/test_viewmodel_pose_math.gd via `ViewModel.AnimState.new()`.
class AnimState extends RefCounted:
	const RECOIL_STIFFNESS := 140.0
	const RECOIL_DAMPING := 16.0
	const SWAY_MAX := 0.05
	const SWAY_FOLLOW := 8.0
	const SWAY_SENS := 0.002
	const EQUIP_DUR := 0.28
	const MUZZLE_DUR := 0.05
	## Trajectoire locale (relative à sa position de repos sur le Foregrip)
	## du gant gauche pendant le rechargement : descend et recule légèrement
	## (vers la zone du chargeur — toujours plus bas et plus proche du corps
	## que le Foregrip, cf. les gabarits "chargeur" de tools/blender/
	## make_weapons.py) puis revient. Générique (pas par arme) : le geste n'a
	## pas besoin d'atteindre le chargeur au pixel près, juste de LIRE comme
	## une main qui va chercher un chargeur.
	const RELOAD_GLOVE_REACH := Vector3(0.0, -0.10, 0.12)

	var recoil_offset: Vector3 = Vector3.ZERO
	var _recoil_vel: Vector3 = Vector3.ZERO

	var sway_offset: Vector2 = Vector2.ZERO

	var bob_time: float = 0.0

	var reload_t: float = -1.0
	var reload_dur: float = 1.0

	var equip_t: float = -1.0

	var muzzle_t: float = -1.0

	## Ressort critique-amorti simplifié (Euler semi-implicite) : impulsion,
	## puis retour naturel vers 0. `tick_recoil` doit être appelé chaque frame.
	func kick_recoil(amount: Vector3) -> void:
		_recoil_vel += amount

	func tick_recoil(delta: float) -> void:
		var accel := -recoil_offset * RECOIL_STIFFNESS - _recoil_vel * RECOIL_DAMPING
		_recoil_vel += accel * delta
		recoil_offset += _recoil_vel * delta

	## Décalage de sway (mouse-lag) : suit l'opposé du mouvement souris puis
	## décroît vers 0 dès que la souris s'arrête. Clampé à SWAY_MAX.
	func tick_sway(mouse_delta: Vector2, delta: float) -> void:
		var target := -mouse_delta * SWAY_SENS
		target.x = clampf(target.x, -SWAY_MAX, SWAY_MAX)
		target.y = clampf(target.y, -SWAY_MAX, SWAY_MAX)
		sway_offset = sway_offset.lerp(target, clampf(SWAY_FOLLOW * delta, 0.0, 1.0))

	## Bob sinusoïdal proportionnel à la vitesse horizontale ; plat à l'arrêt.
	func tick_bob(speed: float, max_speed: float, delta: float) -> Vector3:
		var ratio := clampf(speed / maxf(max_speed, 0.01), 0.0, 1.4)
		if speed > 0.1:
			bob_time += delta * lerp(6.0, 11.0, clampf(ratio, 0.0, 1.0))
		else:
			bob_time = 0.0
			return Vector3.ZERO
		var y := sin(bob_time) * 0.015 * ratio
		var x := cos(bob_time * 0.5) * 0.01 * ratio
		return Vector3(x, y, 0.0)

	## Démarre le dip de rechargement (descend puis remonte sur `dur` s).
	func start_reload(dur: float) -> void:
		reload_dur = maxf(dur, 0.05)
		reload_t = 0.0

	func tick_reload(delta: float) -> Vector3:
		if reload_t < 0.0:
			return Vector3.ZERO
		reload_t += delta
		var p := clampf(reload_t / reload_dur, 0.0, 1.0)
		var dip := sin(p * PI) * 0.12
		if p >= 1.0:
			reload_t = -1.0
			return Vector3.ZERO
		return Vector3(0.0, -dip, 0.0)

	## Décalage LOCAL (relatif à sa position de repos sur le Foregrip) du gant
	## gauche pendant le rechargement : plonge vers la zone du chargeur puis
	## revient, synchronisé sur le MÊME minuteur que le dip d'ensemble
	## (`reload_t`/`reload_dur`, avancés par `tick_reload` — à appeler APRÈS
	## lui dans la même frame, comme dans `_process`). Pure (aucun accès à
	## l'arbre de scène), testable directement : voir
	## tests/player/test_viewmodel_pose_math.gd.
	func reload_glove_offset() -> Vector3:
		if reload_t < 0.0:
			return Vector3.ZERO
		var p := clampf(reload_t / reload_dur, 0.0, 1.0)
		return RELOAD_GLOVE_REACH * sin(p * PI)

	## Montée d'équipement : l'arme remonte depuis le bas sur EQUIP_DUR s.
	func start_equip() -> void:
		equip_t = 0.0

	func tick_equip(delta: float) -> Vector3:
		if equip_t < 0.0:
			return Vector3.ZERO
		equip_t += delta
		var p := clampf(equip_t / EQUIP_DUR, 0.0, 1.0)
		var eased := 1.0 - pow(1.0 - p, 3.0)
		if p >= 1.0:
			equip_t = -1.0
			return Vector3.ZERO
		return Vector3(0.0, -(1.0 - eased) * 0.25, (1.0 - eased) * 0.08)

	func trigger_muzzle_flash() -> void:
		muzzle_t = MUZZLE_DUR

	func is_muzzle_visible() -> bool:
		return muzzle_t > 0.0

	## Renvoie faux une fois le flash éteint (permet à l'appelant de masquer
	## le mesh au tick où l'extinction se produit).
	func tick_muzzle(delta: float) -> bool:
		if muzzle_t < 0.0:
			return false
		muzzle_t -= delta
		return muzzle_t > 0.0

	## Vers 0 (visée) ou 1 (hanche) — utilisé pour mélanger sway/bob et centrer
	## le modèle en ADS.
	func ads_blend(is_aiming: bool, current: float, delta: float, speed: float = 10.0) -> float:
		return move_toward(current, 0.0 if is_aiming else 1.0, speed * delta)

	func sprint_pose_blend(is_sprinting: bool, current: float, delta: float, speed: float = 6.0) -> float:
		return move_toward(current, 1.0 if is_sprinting else 0.0, speed * delta)

	func slide_tilt_blend(is_sliding: bool, current: float, delta: float, speed: float = 8.0) -> float:
		return move_toward(current, 1.0 if is_sliding else 0.0, speed * delta)
