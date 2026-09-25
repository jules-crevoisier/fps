## ImpactFx.gd
## Effet d'impact cel-shadé, cosmétique et prédit LOCALEMENT (jamais de
## conséquence de jeu — voir docs/research/01_game_feel.md, « Séparation
## standard » : on prédit ce qui est certain — tir, muzzle flash, impact
## décoratif — on attend le serveur pour ce qui compte — hitmarker, PV,
## kill). Posé par Weapon.gd (GF-06) au point où le raycast LOCAL du
## traceur s'arrête, dans la même frame que le tir.
##
## Deux couches immédiates, même esprit que le flash au canon (ViewModel/
## ThirdPersonWeapon._spawn_muzzle_flash) : un ÉCLAT bref (quad non éclairé,
## billboard caméra, teinte chaude, ~80 ms, POOL STATIQUE MAX_POOL = 64 —
## voir _acquire), PUIS (ART-40, STYLE_BIBLE.md §9.3) le rendu qui persiste,
## routé selon ce qui a été touché :
##  - PERSONNAGE (un `PlayerController` trouvé au point d'impact — voir
##    `_character_hit_at`) : rembourrage + confettis couleur-clé de l'agent
##    (+ anneau CLONK/étoiles si headshot cosmétique local) via
##    `ComicFx.character_hit_specs` — JAMAIS de décalque (on ne tache pas un
##    personnage qui bouge), jamais de rouge sang (CHK-45).
##  - MONDE générique (tout le reste) : décalque d'étoile d'impact (déjà
##    encré, `DecalPool`/atlas ART-04) + bouffée de poussière + éclats
##    (`ComicFx.dust_puff_spec`/`debris_shards_spec`).
##
## Weapon.gd (GF-06, hors périmètre de cette tâche) ne transmet que
## `pos`/`normal` à `spawn()` — jamais la matière de la surface touchée — donc
## seules ces deux lignes du tableau §9.3 sont routées ici ; voir l'en-tête de
## ComicFx.gd et le rendu de tâche (`blocked_on`) pour les variantes par
## matière (métal/bois/sable/verre) qui resteraient à câbler.
##
## POOL STATIQUE (MAX_POOL = 64) partagé par TOUS les joueurs/armes de la
## partie courante, pour l'éclat instantané SEULEMENT (le décalque persistant
## a son propre pool, `DecalPool`, séparé) : `spawn()` réutilise l'instance la
## plus ancienne dès que le pool est plein plutôt que de laisser une rafale
## (LMG, spray, plusieurs tireurs) empiler des nœuds sans limite. Chaque
## instance du pool vit tant que la partie tourne — jamais détruite entre deux
## tirs, seulement masquée — et se réattache d'elle-même si la scène courante
## a changé (nouvelle partie, retour au menu) au lieu d'être perdue avec
## l'ancienne.
class_name ImpactFx
extends Node3D

const MAX_POOL := 64
## Durée (s) de l'éclat instantané — même ordre de grandeur que le flash au
## canon (ViewModel.AnimState.MUZZLE_DUR).
const SPARK_DUR := 0.08
## Hauteur (m) au-dessus des pieds du `PlayerController` touché à partir de
## laquelle un impact est traité comme un headshot COSMÉTIQUE LOCAL (ART-40) —
## choisit juste entre les deux rendus du §9.3 ("Personnage (corps)" vs
## "(tête)") ; le flag qui compte pour le jeu (dégâts, confirmation de kill)
## reste calculé par le serveur (`Health.gd`), voir la docstring de fichier.
const HEAD_HEIGHT_THRESHOLD_M := 1.5
const _WORLD_DECAL_NAMES: Array[String] = ["impact_star_small", "impact_star_large"]
const _WORLD_DECAL_SIZE_M := 0.12

static var _pool: Array[ImpactFx] = []
static var _next_slot: int = 0

var _spark: MeshInstance3D
var _spark_mat: StandardMaterial3D
var _spark_tween: Tween

func _ready() -> void:
	visible = false
	_build_spark()

# ======================================================================
#  API STATIQUE — pool partagé
# ======================================================================

## Fait apparaître un impact à `pos`, orienté selon `normal` (surface
## touchée) — réutilise une instance du pool statique (voir doc de classe)
## pour l'éclat instantané, puis route le rendu qui persiste (ART-40, §9.3) :
## personnage (rembourrage + confettis) si un `PlayerController` occupe ce
## point, sinon monde générique (décalque + poussière + éclats). Sans effet
## si `scene` est nul (pas de scène courante, ex. tests headless ou appel
## avant que le joueur ait rejoint une partie).
static func spawn(scene: Node, pos: Vector3, normal: Vector3) -> void:
	if scene == null:
		return
	var inst := _acquire(scene)
	if inst == null:
		return
	var n := normal.normalized() if normal.length_squared() > 0.0001 else Vector3.UP
	inst.global_transform = Transform3D(basis_for_normal(n), pos + n * 0.01)
	inst._trigger()
	var player := _character_hit_at(scene, pos, n)
	if player != null:
		_spawn_character_hit_fx(scene, pos, n, player)
	else:
		_spawn_world_hit_fx(scene, pos, n)

## Base orthonormée dont l'axe Z LOCAL pointe selon `n` (la normale de la
## surface touchée) — sert à coller la tache d'encre à plat contre le mur
## (QuadMesh par défaut dans le plan XY, face vers +Z). Fonction PURE
## (aucun accès à l'arbre de scène), testable directement sans instancier
## de Node3D.
static func basis_for_normal(n: Vector3) -> Basis:
	var up := Vector3.UP if absf(n.dot(Vector3.UP)) < 0.999 else Vector3.RIGHT
	var x := up.cross(n)
	if x.length_squared() < 0.0001:
		x = Vector3.RIGHT.cross(n)
	x = x.normalized()
	var y := n.cross(x).normalized()
	return Basis(x, y, n)

## Renvoie une instance prête à recevoir `_trigger()` : en crée une nouvelle
## tant que MAX_POOL n'est pas atteint, sinon réutilise la plus ancienne
## (round-robin sur `_next_slot`). Réattache l'instance à `scene` si elle
## appartenait à une scène désormais quittée (fin de partie).
static func _acquire(scene: Node) -> ImpactFx:
	if _pool.size() < MAX_POOL:
		var inst := ImpactFx.new()
		scene.add_child(inst)
		_pool.append(inst)
		return inst
	var idx := _next_slot % _pool.size()
	_next_slot = (_next_slot + 1) % _pool.size()
	var inst: ImpactFx = _pool[idx]
	if not is_instance_valid(inst):
		inst = ImpactFx.new()
		scene.add_child(inst)
		_pool[idx] = inst
	elif inst.get_parent() != scene:
		if inst.get_parent():
			inst.get_parent().remove_child(inst)
		scene.add_child(inst)
	return inst

# ======================================================================
#  INSTANCE — construction des deux couches, déclenchement
# ======================================================================

func _build_spark() -> void:
	_spark = MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(0.3, 0.3)
	_spark.mesh = qm
	_spark_mat = StandardMaterial3D.new()
	_spark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_spark_mat.albedo_color = Color(1.0, 0.85, 0.45)
	_spark_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_spark_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_spark.material_override = _spark_mat
	_spark.visible = false
	add_child(_spark)

## Rejoue l'éclat depuis le début (position/orientation déjà posées par
## `spawn`) — tue le tween d'un déclenchement précédent au cas où cette
## instance du pool serait réutilisée avant la fin de son cycle (rafale sur
## une arme rapide une fois le pool plein).
func _trigger() -> void:
	if _spark_tween:
		_spark_tween.kill()
	visible = true
	# Légère variation de taille (façon Borderlands : pas deux impacts
	# identiques au pixel près) — dérivée de la position pour rester
	# déterministe sans dépendance à un RNG partagé.
	var jitter := 0.85 + fmod(absf(global_position.x + global_position.z) * 7.0, 0.3)
	_spark.visible = true
	_spark.scale = Vector3.ONE * jitter
	_spark_mat.albedo_color.a = 1.0
	_spark_tween = create_tween()
	_spark_tween.tween_property(_spark_mat, "albedo_color:a", 0.0, SPARK_DUR)
	_spark_tween.tween_callback(_hide_spark)

func _hide_spark() -> void:
	if _spark:
		_spark.visible = false
		visible = false

# ======================================================================
#  ART-40 — routage par cible (monde générique vs personnage), §9.3
# ======================================================================

## Vrai si `hit_y` (position Y monde de l'impact) dépasse `origin_y` (pieds du
## personnage, `player.global_position.y`) de `HEAD_HEIGHT_THRESHOLD_M` ou
## plus. Fonction PURE (aucun Node) — voir `_character_hit_at` pour son
## usage réel et la docstring de `HEAD_HEIGHT_THRESHOLD_M` pour la nuance
## "cosmétique local, pas le flag serveur".
static func is_headshot_height(origin_y: float, hit_y: float) -> bool:
	return hit_y - origin_y >= HEAD_HEIGHT_THRESHOLD_M

## Cherche un `PlayerController` occupant le point d'impact : Weapon.gd
## (GF-06, hors périmètre de cette tâche) ne transmet à `spawn()` que
## `pos`/`normal`, jamais le collider de son propre raycast — on le retrouve
## donc nous-mêmes plutôt que de dupliquer un raycast complet. Requête
## physique PONCTUELLE, décalée de quelques cm SOUS la surface touchée le
## long de `-n` (`pos` est littéralement sur la coque du collider ;
## interroger EXACTEMENT ce point est numériquement peu fiable — le point
## peut retomber juste à l'extérieur du volume selon l'arrondi). Repli sur
## `null` (effet "monde") si `scene` n'est plus dans l'arbre (fin de partie)
## ou si rien n'est touché.
static func _character_hit_at(scene: Node, pos: Vector3, n: Vector3) -> PlayerController:
	if scene == null or not scene.is_inside_tree():
		return null
	# `scene` est typé `Node` (Weapon.gd passe `current_scene`) : `get_world_3d()`
	# n'existe que sur Node3D/Viewport, jamais sur Node en général -- on passe
	# donc par le Viewport (universel sur tout Node dans l'arbre).
	var viewport := scene.get_viewport()
	if viewport == null:
		return null
	var space := viewport.world_3d.direct_space_state
	var q := PhysicsPointQueryParameters3D.new()
	q.position = pos - n * 0.05
	q.collision_mask = PhysicsLayers.WORLD
	q.collide_with_areas = false
	q.collide_with_bodies = true
	for hit in space.intersect_point(q, 4):
		var collider = hit.get("collider")
		if collider is PlayerController:
			return collider
	return null

## Personnage (§9.3 "Personnage") : rembourrage + confettis couleur-clé de
## l'agent touché, jamais de rouge sang (CHK-45) — `ComicFx.character_hit_specs`
## garantit cette dernière propriété par construction (voir sa docstring).
## Pas de décalque ici : on ne tache pas un personnage qui bouge.
static func _spawn_character_hit_fx(scene: Node, pos: Vector3, n: Vector3, player: PlayerController) -> void:
	var key_color := AgentDatabase.get_by_index(player.agent_index).color
	var headshot := is_headshot_height(player.global_position.y, pos.y)
	for spec in ComicFx.character_hit_specs(key_color, headshot):
		ComicFx.spawn_from_spec(scene, pos, n, spec)

## Monde générique (§9.3 "Monde, générique") : décalque d'étoile d'impact
## (déjà encré, `DecalPool`/atlas ART-04 — pool de 64 FIFO partagé,
## STYLE_BIBLE.md §9.1 #6) + bouffée de poussière + éclats. Weapon.gd ne
## transmettant pas la matière de la surface touchée (hors périmètre de
## cette tâche), tout impact non-personnage utilise ici le même rendu
## "générique" plutôt qu'une variante par matière (métal/bois/sable/verre) —
## signalé dans le rendu de tâche (`blocked_on`).
static func _spawn_world_hit_fx(scene: Node, pos: Vector3, n: Vector3) -> void:
	var decal_name: String = _WORLD_DECAL_NAMES[randi() % _WORLD_DECAL_NAMES.size()]
	DecalPool.spawn(scene, pos, n, decal_name, _WORLD_DECAL_SIZE_M)
	ComicFx.spawn_from_spec(scene, pos, n, ComicFx.dust_puff_spec())
	ComicFx.spawn_from_spec(scene, pos, n, ComicFx.debris_shards_spec(Cartoon.PAPER_SHADE))
