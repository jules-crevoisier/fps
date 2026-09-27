## ImpactVfx.gd
## Tâche "impacts sur les murs" (2026-09-27) : trou de balle + poussière/
## étincelle par SURFACE au point d'impact du raycast local (`Weapon._fire_
## visuals`, GF-06 -- même donnée pos/normal/collider que `ImpactFx.spawn`,
## déjà utilisée par `SurfaceSound.surface_of` pour choisir le SON d'impact,
## voir Weapon.gd `_spawn_impact`/`_play_impact_sound`). Complète ImpactFx.gd
## (qui pose déjà l'éclat instantané + le routage personnage/monde générique,
## STYLE_BIBLE.md §9.3) sans le remplacer : ImpactVfx AJOUTE le décalque de
## balle PROJETÉ (Godot `Decal`, jamais posé par ImpactFx faute de connaître
## la matière touchée -- voir son "blocked_on") et une bouffée/étincelle
## dédiée par matière, en réutilisant `SurfaceSound.surface_of(collider)`.
##
## Deux pools STATIQUES séparés (même idiome FIFO round-robin que
## `ImpactFx._acquire`/`DecalPool._acquire` -- plafond MAX_POOL = 64, la plus
## ancienne instance est recyclée dès que le pool est plein plutôt que de
## laisser une rafale/fusil à pompe (`WeaponConfig.pellets`, voir Weapon.gd
## `_fire_local`) empiler des nœuds sans limite) :
##  - `_decal_pool` : les trous de balle (`Decal`), durée de vie
##    DECAL_LIFETIME_S puis fondu DECAL_FADE_S (`decal_fade_alpha`, pure).
##  - `_fx_pool` : les billboards poussière/étincelle, cosmétiques et courts
##    (PUFF_POP_DUR_S/SPARK_POP_DUR_S), partagé entre les deux textures
##    (structurellement identiques : un seul QuadMesh + StandardMaterial3D
##    non éclairé, seule la texture/l'anim changent).
##
## Contour d'encre (Sobel/`ink_edges.gdshader`) : ce post-passe lit UNIQUEMENT
## les buffers profondeur + normale/rugosité capturés pendant le pré-passe
## opaque (voir l'en-tête de ce shader) -- un matériau `TRANSPARENCY_ALPHA`
## (déf. `depth_draw_mode` = OPAQUE_ONLY, donc AUCUNE écriture de profondeur
## pour un objet qui n'est jamais "opaque") reste invisible à ces deux
## buffers, donc jamais contourné par erreur. Même convention EXACTE que
## `DecalPool._build_instance`/`ComicFx.shape_material` (billboards non
## éclairés, alpha, aucun `depth_draw_always`) -- pas une nouvelle astuce.
## Le `Decal` natif, lui, ne pose pas ce risque : il peint l'albédo de la
## géométrie MONDE déjà existante (qui écrit déjà sa PROPRE profondeur
## normalement), sans ajouter de silhouette.
class_name ImpactVfx
extends Node

const MAX_POOL := 64

## Nombre de variantes peintes par matière (bullet_hole_concrete_{1,2,3}.png,
## bullet_hole_metal_{1,2,3}.png, assets/vfx/impact/, voir make_impact_decals.py).
const _VARIANT_COUNT := 3

const _CONCRETE_TEXTURES: Array[Texture2D] = [
	preload("res://assets/vfx/impact/bullet_hole_concrete_1.png"),
	preload("res://assets/vfx/impact/bullet_hole_concrete_2.png"),
	preload("res://assets/vfx/impact/bullet_hole_concrete_3.png"),
]
const _METAL_TEXTURES: Array[Texture2D] = [
	preload("res://assets/vfx/impact/bullet_hole_metal_1.png"),
	preload("res://assets/vfx/impact/bullet_hole_metal_2.png"),
	preload("res://assets/vfx/impact/bullet_hole_metal_3.png"),
]
const _PUFF_TEXTURE := preload("res://assets/vfx/impact/impact_puff.png")
const _SPARK_TEXTURE := preload("res://assets/vfx/impact/impact_spark.png")

# -- Décalque (trou de balle) -------------------------------------------------
const DECAL_SIZE_MIN_M := 0.10
const DECAL_SIZE_MAX_M := 0.14
## Profondeur (m) de la boîte de projection du `Decal` le long de son axe -Z
## local (voir `basis_for_normal` : posé à `pos + n*0.01`, la surface réelle
## tombe donc tout près de Z=0 dans cette boîte) -- assez pour envelopper une
## surface légèrement bosselée sans déborder sur le décor voisin, vu le petit
## gabarit (10-14 cm) du décalque lui-même.
const DECAL_DEPTH_M := 0.25
const DECAL_LIFETIME_S := 12.0
const DECAL_FADE_S := 1.0
## `Decal.normal_fade` (doc Godot 4.7, "using_decals" -- "increase Normal Fade
## to prevent projection on surfaces not facing the decal") : évite qu'un
## décalque déborde sur l'arête d'un coin (une surface presque perpendiculaire
## à la normale du point touché) -- et, à défaut d'un calque de rendu dédié
## pour l'arme premières-personnes (ViewModel._MASK_RENDER_LAYER n'existe
## QUE pendant la capture debug de tools/fp_shots.gd, jamais en jeu normal, et
## scripts/player/** est hors des fichiers possédés par cette tâche), c'est la
## meilleure protection disponible ICI contre un débordement sur le canon du
## ViewModel à bout portant : le canon n'est presque jamais orienté plein axe
## vers le mur touché, donc un normal_fade élevé l'exclut dans l'immense
## majorité des cas. Protection RÉELLE restante, géométrique : la boîte du
## décalque est petite (10-14 cm x 25 cm de profondeur) et posée AU POINT
## D'IMPACT, jamais à la position du canon.
const DECAL_NORMAL_FADE := 0.8
## `Decal.upper_fade`/`lower_fade` : adoucit la coupure aux bords haut/bas de
## la boîte de projection plutôt qu'un arrêt net (utile sur une géométrie
## légèrement irrégulière, ex. les conteneurs cabossés de Shipment).
const DECAL_EDGE_FADE_M := 0.05
## Calque de rendu (voir ViewModel.gd `_MASK_RENDER_LAYER`, "1-20") : SEUL le
## calque 1 (défaut Godot, celui de tout le décor ET de l'arme premières-
## personnes faute d'un calque dédié toujours actif -- voir `DECAL_NORMAL_FADE`
## ci-dessus) reçoit la projection -- explicite plutôt que le défaut "tous les
## calques" du nœud `Decal`, même si ça ne change rien tant qu'aucun calque
## dédié n'existe.
const DECAL_CULL_MASK := 1

# -- FX poussière/étincelle ----------------------------------------------------
const PUFF_SCALE_START_M := 0.15
const PUFF_SCALE_END_M := 0.45
const PUFF_POP_DUR_S := 0.3
const SPARK_SCALE_START_M := 0.2
const SPARK_SCALE_END_M := 0.35
const SPARK_POP_DUR_S := 0.12
## Distance (m) de dérive le long de la normale pendant le pop (§ consigne
## "drifting slightly along the normal").
const FX_DRIFT_M := 0.05

## Budget §"Performance" : au plus ce nombre d'impacts COMPLETS (décalque +
## FX) posés par frame moteur -- une rafale/fusil à pompe (plusieurs plombs
## résolus dans la MÊME frame, voir Weapon.gd `_fire_local`, boucle `for d in
## dirs`) ne crée donc jamais plus que ça d'un coup ; les plombs excédentaires
## ce tick-là restent silencieux côté VFX (le son/dégât, eux, ne sont jamais
## affectés -- ce plafond ne vit que dans ce fichier).
const MAX_SPAWNS_PER_FRAME := 8

static var _decal_pool: Array[Decal] = []
static var _decal_next_slot: int = 0
static var _fx_pool: Array[MeshInstance3D] = []
static var _fx_next_slot: int = 0

static var _frame_number_seen: int = -1
static var _spawns_this_frame: int = 0

# ======================================================================
#  PUR -- testable sans Node (tests/combat/test_impact_vfx.gd)
# ======================================================================

## Base orthonormée dont l'axe Y LOCAL pointe selon `n` -- PAS Z, à la
## différence d'`ImpactFx.basis_for_normal`/`DecalPool._basis_for_normal`
## (copies volontaires entre elles, même formule, mais qui orientent un
## `QuadMesh` classique -- plan local XY face à +Z par défaut, donc Z = la
## normale). `ImpactVfx` oriente un `Decal` NATIF à la place : celui-ci
## projette le long de son axe -Y LOCAL, jamais -Z (vérifié empiriquement --
## `docs Godot 4.7 using_decals.html` ne précise pas l'axe en toutes lettres ;
## `Decal.size.y` étant la PROFONDEUR de projection, voir `spawn_bullet_hole`,
## confirme que c'est bien Y). Avec Z pour la normale (essayé d'abord, copié
## des fonctions sœurs sans revérifier pour CE type de nœud précis), le
## décalque existait bel et bien (`visible = true`) mais ne se projetait
## JAMAIS sur le mur -- sa boîte de profondeur pointait dans une direction
## quelconque du plan de la surface au lieu d'y entrer ; voir le rapport de
## tâche pour la capture qui a révélé ça (aucun impact visible malgré un
## `Decal` bien présent dans l'arbre).
static func basis_for_normal(n: Vector3) -> Basis:
	var up := Vector3.UP if absf(n.dot(Vector3.UP)) < 0.999 else Vector3.RIGHT
	var x := n.cross(up)
	if x.length_squared() < 0.0001:
		x = n.cross(Vector3.RIGHT)
	x = x.normalized()
	var z := x.cross(n)
	return Basis(x, n, z)

## `basis_for_normal(n)` fait tourner autour de son propre axe Y (`n`, jamais
## touché) de `roll_rad` -- même esprit que `ImpactFx._trigger`, "façon
## Borderlands : pas deux impacts identiques au pixel près", ici appliqué à
## l'ORIENTATION plutôt qu'à la taille : les décalques de balle portent des
## éclats/débris asymétriques peints DANS la texture (voir make_impact_decals.py,
## "cracks"/étoile déchirée) -- sans cette rotation, une rafale groupée (spread
## serré du Ravage) empilerait des décalques identiquement orientés, qui se
## liraient comme un unique motif tamponné plutôt que des impacts distincts.
## Rotation orthogonale dans le plan (x, z) -- ne change jamais `y` (`n`) ni la
## norme des axes, donc reste une base orthonormée pour tout `roll_rad`.
static func rolled_basis_for_normal(n: Vector3, roll_rad: float) -> Basis:
	var b := basis_for_normal(n)
	var c := cos(roll_rad)
	var s := sin(roll_rad)
	var rx := b.x * c + b.z * s
	var rz := b.z * c - b.x * s
	return Basis(rx, b.y, rz)

## Un décalque/FX d'impact ne se pose QUE sur un collider MONDE légitime :
## jamais sur un personnage touché (ImpactFx route déjà ce cas vers
## rembourrage+confettis, voir sa docstring -- on ne tache pas un corps qui
## bouge), même convention que `Weapon._play_impact_sound`
## (`collider.get_node_or_null("Health") != null`). Jamais non plus sur un
## corps de VISION (fumée, `PhysicsLayers.VISION`, voir SmokeCloud.gd) --
## `PhysicsLayers.SHOT_MASK` l'exclut déjà du raycast de tir lui-même (on ne
## devrait donc jamais recevoir un tel collider ici), vérifié quand même
## défensivement, comme `SurfaceSound.surface_of` le fait pour son repli sans
## méta. Repli sûr (faux) si `collider` est nul ou n'expose pas
## `collision_layer` (pas un `CollisionObject3D`).
static func is_world_collider(collider: Object) -> bool:
	if collider == null:
		return false
	if not ("collision_layer" in collider):
		return false
	if collider.get_node_or_null("Health") != null:
		return false
	var layer: int = collider.collision_layer
	return layer & PhysicsLayers.WORLD != 0

## Texture de décalque pour `surface` (`SurfaceSound.METAL`/`CONCRETE`) et un
## `variant` (0-based, replié par modulo -- un tirage aléatoire quelconque y
## reste valide sans clamp côté appelant).
static func texture_for_surface(surface: String, variant: int) -> Texture2D:
	var arr := _METAL_TEXTURES if surface == SurfaceSound.METAL else _CONCRETE_TEXTURES
	var idx := ((variant % _VARIANT_COUNT) + _VARIANT_COUNT) % _VARIANT_COUNT
	return arr[idx]

## `roll01` (0-1, ex. `randf()`) -> taille de décalque (m), bornes incluses,
## clampée si l'appelant dépasse [0, 1].
static func decal_size_m(roll01: float) -> float:
	return lerpf(DECAL_SIZE_MIN_M, DECAL_SIZE_MAX_M, clampf(roll01, 0.0, 1.0))

## Béton : 1 ou 2 bouffées de poussière (consigne "1-2 impact_puff") --
## alternance déterministe sur la parité du tirage plutôt qu'un second
## `randi()` séparé.
static func puff_count_for_roll(roll: int) -> int:
	return 1 + (roll % 2)

## Budget par frame (voir `MAX_SPAWNS_PER_FRAME`) -- pure, testable sans
## dépendre d'`Engine.get_process_frames()`.
static func can_spawn_more(spawned_so_far: int) -> bool:
	return spawned_so_far < MAX_SPAWNS_PER_FRAME

## Alpha du décalque à `elapsed_s` secondes depuis sa pose : 1.0 jusqu'à
## `DECAL_LIFETIME_S - DECAL_FADE_S`, puis rampe linéaire vers 0.0 à
## `DECAL_LIFETIME_S`, 0.0 au-delà (jamais négatif).
static func decal_fade_alpha(elapsed_s: float) -> float:
	var fade_start := DECAL_LIFETIME_S - DECAL_FADE_S
	if elapsed_s <= fade_start:
		return 1.0
	if elapsed_s >= DECAL_LIFETIME_S:
		return 0.0
	return 1.0 - (elapsed_s - fade_start) / DECAL_FADE_S

## Test uniquement : remet à zéro le budget par-frame -- les tests appellent
## `spawn()` de façon synchrone, potentiellement plusieurs méthodes de test
## sur la MÊME frame moteur (`Engine.get_process_frames()` n'avance pas sans
## traitement réel de frame), ce qui ferait échouer un test isolé si le
## budget d'un test précédent traînait encore. Sans effet sur le jeu réel (la
## frame avance normalement entre deux tirs).
static func reset_frame_budget_for_test() -> void:
	_frame_number_seen = -1
	_spawns_this_frame = 0

# ======================================================================
#  IMPUR -- pool + construction de nœuds (non testé en détail, comme
#  ImpactFx._acquire/_trigger et DecalPool._acquire/_trigger)
# ======================================================================

## Pose un trou de balle (`Decal` natif) à `pos`, orienté selon `normal`,
## texturé selon `surface` (`SurfaceSound.METAL`/`CONCRETE`) -- réutilise
## l'instance la plus ancienne du pool une fois `MAX_POOL` atteint. `variant`/
## `size_m` < 0 tirent aléatoirement (`randi`/`randf` + `texture_for_surface`/
## `decal_size_m`) ; un appelant de test passe des valeurs explicites pour un
## résultat déterministe. Sans effet (retourne `null`) si `parent` est nul ou
## hors de l'arbre (ex. fin de partie).
static func spawn_bullet_hole(parent: Node, pos: Vector3, normal: Vector3, surface: String, variant: int = -1, size_m: float = -1.0, roll_rad: float = -1.0) -> Decal:
	if parent == null or not parent.is_inside_tree():
		return null
	var n := normal.normalized() if normal.length_squared() > 0.0001 else Vector3.UP
	var v := variant if variant >= 0 else (randi() % _VARIANT_COUNT)
	var s := size_m if size_m > 0.0 else decal_size_m(randf())
	var roll := roll_rad if roll_rad >= 0.0 else randf() * TAU
	var inst := _acquire_decal(parent)
	if inst == null:
		return null
	inst.global_transform = Transform3D(rolled_basis_for_normal(n, roll), pos + n * 0.01)
	inst.texture_albedo = texture_for_surface(surface, v)
	# `Decal.size.y` = profondeur de projection (axe -Y local, voir
	# `basis_for_normal`) ; `.x`/`.z` = l'empreinte (carrée) posée sur la
	# surface -- PAS `.z` pour la profondeur (essayé d'abord par analogie avec
	# `DecalPool`/`ImpactFx`, qui orientent un `QuadMesh` classique, jamais un
	# `Decal` natif -- voir la docstring de `basis_for_normal`).
	inst.size = Vector3(s, DECAL_DEPTH_M, s)
	inst.cull_mask = DECAL_CULL_MASK
	inst.normal_fade = DECAL_NORMAL_FADE
	inst.upper_fade = DECAL_EDGE_FADE_M
	inst.lower_fade = DECAL_EDGE_FADE_M
	inst.modulate = Color(1.0, 1.0, 1.0, 1.0)
	inst.visible = true
	# `get_meta(key, null)` ÉMET une erreur si la clé n'existe pas encore
	# (doc Godot 4.7 : "If default is null, an error is also generated"),
	# jamais un simple repli silencieux -- `has_meta()` d'abord, comme
	# `set_meta`/`has_meta` sont documentés pour ce cas.
	if inst.has_meta("_fade_tween"):
		var existing_tween: Object = inst.get_meta("_fade_tween")
		if existing_tween is Tween:
			(existing_tween as Tween).kill()
	var tw := inst.create_tween()
	inst.set_meta("_fade_tween", tw)
	tw.tween_interval(maxf(DECAL_LIFETIME_S - DECAL_FADE_S, 0.0))
	tw.tween_property(inst, "modulate:a", 0.0, DECAL_FADE_S)
	tw.tween_callback(inst.hide)
	return inst

static func _acquire_decal(parent: Node) -> Decal:
	if _decal_pool.size() < MAX_POOL:
		var inst := Decal.new()
		parent.add_child(inst)
		_decal_pool.append(inst)
		return inst
	var idx := _decal_next_slot % _decal_pool.size()
	_decal_next_slot = (_decal_next_slot + 1) % _decal_pool.size()
	var inst: Decal = _decal_pool[idx]
	if not is_instance_valid(inst):
		inst = Decal.new()
		parent.add_child(inst)
		_decal_pool[idx] = inst
	elif inst.get_parent() != parent:
		if inst.get_parent():
			inst.get_parent().remove_child(inst)
		parent.add_child(inst)
	return inst

## Bouffée de poussière (béton) -- billboard caméra qui grossit de
## `PUFF_SCALE_START_M` à `PUFF_SCALE_END_M` sur `PUFF_POP_DUR_S` (ease out) en
## s'estompant et en dérivant un peu le long de `normal`, puis se cache
## (recyclable). Sans effet si `parent` est nul ou hors de l'arbre.
static func spawn_impact_puff(parent: Node, pos: Vector3, normal: Vector3) -> MeshInstance3D:
	if parent == null or not parent.is_inside_tree():
		return null
	var n := normal.normalized() if normal.length_squared() > 0.0001 else Vector3.UP
	var inst := _acquire_fx(parent)
	if inst == null:
		return null
	_trigger_fx(inst, _PUFF_TEXTURE, pos, n, PUFF_SCALE_START_M, PUFF_SCALE_END_M, PUFF_POP_DUR_S)
	return inst

## Étincelle (métal) -- même principe, plus bref (`SPARK_POP_DUR_S`), puis
## disparaît (consigne "pop then vanish").
static func spawn_impact_spark(parent: Node, pos: Vector3, normal: Vector3) -> MeshInstance3D:
	if parent == null or not parent.is_inside_tree():
		return null
	var n := normal.normalized() if normal.length_squared() > 0.0001 else Vector3.UP
	var inst := _acquire_fx(parent)
	if inst == null:
		return null
	_trigger_fx(inst, _SPARK_TEXTURE, pos, n, SPARK_SCALE_START_M, SPARK_SCALE_END_M, SPARK_POP_DUR_S)
	return inst

static func _acquire_fx(parent: Node) -> MeshInstance3D:
	if _fx_pool.size() < MAX_POOL:
		var inst := _build_fx_instance()
		parent.add_child(inst)
		_fx_pool.append(inst)
		return inst
	var idx := _fx_next_slot % _fx_pool.size()
	_fx_next_slot = (_fx_next_slot + 1) % _fx_pool.size()
	var inst: MeshInstance3D = _fx_pool[idx]
	if not is_instance_valid(inst):
		inst = _build_fx_instance()
		parent.add_child(inst)
		_fx_pool[idx] = inst
	elif inst.get_parent() != parent:
		if inst.get_parent():
			inst.get_parent().remove_child(inst)
		parent.add_child(inst)
	return inst

## Quad non éclairé, alpha, billboard caméra -- MÊME convention que
## `DecalPool._build_instance`/`ImpactFx._build_spark` (voir la note sur le
## contour d'encre en tête de fichier : `TRANSPARENCY_ALPHA` n'écrit jamais la
## profondeur, donc jamais contourné par le post-passe Sobel/`ink_edges`).
static func _build_fx_instance() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2.ONE
	mi.mesh = qm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mi.material_override = mat
	return mi

static func _trigger_fx(inst: MeshInstance3D, texture: Texture2D, pos: Vector3, normal: Vector3, scale_start_m: float, scale_end_m: float, dur_s: float) -> void:
	var mat := inst.material_override as StandardMaterial3D
	mat.albedo_texture = texture
	mat.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
	var qm := inst.mesh as QuadMesh
	qm.size = Vector2.ONE * scale_start_m
	inst.global_position = pos + normal * 0.02
	inst.visible = true
	# Voir la même note dans `spawn_bullet_hole` -- `has_meta()` avant tout
	# `get_meta()` sans repli par défaut.
	if inst.has_meta("_fx_tween"):
		var existing_tween: Object = inst.get_meta("_fx_tween")
		if existing_tween is Tween:
			(existing_tween as Tween).kill()
	var tw := inst.create_tween()
	inst.set_meta("_fx_tween", tw)
	tw.set_parallel(true)
	tw.tween_method(func(s: float) -> void: qm.size = Vector2.ONE * s, scale_start_m, scale_end_m, dur_s).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(mat, "albedo_color:a", 0.0, dur_s).set_ease(Tween.EASE_OUT)
	tw.tween_property(inst, "global_position", pos + normal * (0.02 + FX_DRIFT_M), dur_s)
	tw.chain().tween_callback(inst.hide)

# ======================================================================
#  API PUBLIQUE -- appelée par Weapon.gd (`_spawn_impact`)
# ======================================================================

## Point d'entrée unique côté Weapon.gd : pose le trou de balle + la FX de
## matière au point d'impact `pos`/`normal` du raycast LOCAL (même appel pour
## la prédiction du tireur et l'écho cosmétique d'un tir distant/bot, voir
## Weapon._fire_visuals -- tout pair rejoue donc le même rendu). Sans effet si
## `scene` est nul/hors-arbre, si `collider` n'est pas un collider MONDE
## légitime (`is_world_collider` -- jamais un personnage ni un corps de
## vision), ou si le budget par frame (`MAX_SPAWNS_PER_FRAME`) est déjà
## consommé (rafale/fusil à pompe, voir sa docstring).
static func spawn(scene: Node, pos: Vector3, normal: Vector3, collider: Object) -> void:
	if scene == null or not scene.is_inside_tree():
		return
	if not is_world_collider(collider):
		return
	_reset_frame_budget_if_new_frame()
	if not can_spawn_more(_spawns_this_frame):
		return
	_spawns_this_frame += 1
	var n := normal.normalized() if normal.length_squared() > 0.0001 else Vector3.UP
	var surface := SurfaceSound.surface_of(collider)
	spawn_bullet_hole(scene, pos, n, surface)
	if surface == SurfaceSound.METAL:
		spawn_impact_spark(scene, pos, n)
		spawn_impact_puff(scene, pos, n)
	else:
		var count := puff_count_for_roll(randi())
		for i in count:
			spawn_impact_puff(scene, pos, n)

static func _reset_frame_budget_if_new_frame() -> void:
	var f := Engine.get_process_frames()
	if f != _frame_number_seen:
		_frame_number_seen = f
		_spawns_this_frame = 0
