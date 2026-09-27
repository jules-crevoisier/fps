## impact_capture.gd
## Vérification visuelle (tâche "impacts sur les murs", 2026-09-27) : héberge
## Shipment SANS bot (comme tools/audio/audio_capture.gd -- même pilotage
## direct de `player.input.*`, jamais `Input.action_press`, plus fiable en
## fenêtre NO_FOCUS/tête), place le joueur devant le conteneur C01 (métal,
## `metadata/surface = "metal"`, voir shipment.tscn) à ~3 m et tire ~10 coups
## de Ravage (fire_rate=10/s -- tenir LMB ~1,05 s), rapproche pour un plan
## serré, capture juste après (bouffée/étincelle visibles) puis ~1 s plus tard
## (décalques seuls) ; répète sur le mur périphérique EST (béton, aucune méta
## -- repli `SurfaceSound.CONCRETE`).
##
## Usage :
##   "%GODOT%" --path . -s res://tools/vfx/impact_capture.gd --screen 1 --resolution 1920x1080
## Images : reports/checkpoints/2026-09-27_vfx/impact_*.png
extends SceneTree

const SHIPMENT := "res://scenes/levels/maps/shipment.tscn"
const OUT_DIR := "res://reports/checkpoints/2026-09-27_vfx"

## Conteneur C01 (voir shipment.tscn) : boîte AXE-ALIGNÉE (rotation identité),
## centre monde, demi-tailles locales (BoxMesh "mesh_short" = 6x2.6x2.5).
const _C01_CENTER := Vector3(-13.0, 1.3, -12.0)
const _C01_HALF := Vector3(3.0, 1.3, 1.25)
## Mur périphérique NORD (WallNorth, shipment.tscn, plan vertical à z=20.2).
## x=4 : corridor Nord-Sud VIDE de tout conteneur -- tous (C01..C13, voir
## shipment.tscn) ont une emprise en X dans [-18.25,-15.75], [-16,-10],
## [-9.25,-6.75], [-3,3], [6.75,9.25] ou [10,16] ; x=4 n'est dans AUCUNE
## d'entre elles, quel que soit Z -- ligne de vue garantie dégagée jusqu'au
## mur (contrairement à x=17, qui tombe DANS l'emprise de C12 -- constaté en
## capture, voir le rapport de tâche).
const _WALL_NORTH_Z := 20.2
const _CLEAR_CORRIDOR_X := 4.0

var _world: Node = null
var _player: PlayerController = null
var _started: bool = false

func _initialize() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true, DisplayServer.MAIN_WINDOW_ID)

func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
	return false  # `_run()` appelle `quit()` lui-même à la fin.

# ==========================================================================
#  ORCHESTRATION
# ==========================================================================
func _run() -> void:
	await _boot()
	if _player == null:
		push_error("impact_capture: le joueur hôte n'a jamais spawné sur Shipment")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))

	# Conteneur C01 : approche par sa face -Z (côté ouvert, loin de WallSouth,
	# voir la docstring de `_shoot_and_capture`) -- direction FIXE, jamais
	# déduite du point de spawn (imprévisible selon l'équipe), pour une
	# composition d'image reproductible d'un run à l'autre.
	await _shoot_and_capture(
		_C01_CENTER, Vector2(0.0, -1.0), _C01_HALF.z + 3.0, _C01_HALF.z + 2.0,
		"impact_metal_puff.png", "impact_metal_decal.png")
	# Mur périphérique NORD : approche par -Z, dans le corridor x=4 (VIDE de
	# tout conteneur -- voir la docstring de `_CLEAR_CORRIDOR_X`).
	await _shoot_and_capture(
		Vector3(_CLEAR_CORRIDOR_X, 1.3, _WALL_NORTH_Z), Vector2(0.0, -1.0), 3.2, 2.0,
		"impact_concrete_puff.png", "impact_concrete_decal.png")

	# Compléments (hors consigne stricte, utiles à la vérification visuelle) :
	# UN SEUL coup sur un point FRAIS de chaque surface -- les captures
	# "~10 coups" ci-dessus empilent aussi TOUT le VFX déjà existant
	# d'ImpactFx (éclat + poussière + éclats, une salve par coup, voir
	# ImpactFx._spawn_world_hit_fx) sur une zone de quelques cm : à cette
	# densité, même le rendu EXISTANT (hors périmètre de cette tâche) devient
	# difficile à lire. Un coup isolé montre le décalque/la FX de CETTE tâche
	# sans ce bruit, pour juger sa propre lisibilité séparément.
	await _shoot_single_and_capture(
		_C01_CENTER + Vector3(0.8, 0.3, 0.0), Vector2(0.0, -1.0), _C01_HALF.z + 3.0, _C01_HALF.z + 1.2,
		"impact_metal_single_puff.png", "impact_metal_single_decal.png")
	await _shoot_single_and_capture(
		Vector3(_CLEAR_CORRIDOR_X + 0.8, 1.3, _WALL_NORTH_Z), Vector2(0.0, -1.0), 3.2, 1.6,
		"impact_concrete_single_puff.png", "impact_concrete_single_decal.png")

	quit(0)

func _boot() -> void:
	MatchConfig.mode_id = "tdm"
	MatchConfig.map_id = "shipment"
	MatchConfig.bots_enabled = false  # consigne : bots OFF.
	MatchConfig.team_size = 1
	var packed := load(SHIPMENT) as PackedScene
	if packed == null:
		push_error("impact_capture: scène introuvable : %s" % SHIPMENT)
		return
	_world = packed.instantiate()
	# "map ajoutée DEFERRED" (consigne) : jamais un add_child() direct pendant
	# que _initialize()/le tout premier _process() tourne encore.
	root.call_deferred("add_child", _world)
	await process_frame
	await process_frame
	current_scene = _world
	_player = await _wait_for_local_player(10.0)
	if _player:
		# Pilotage direct de `input.*`, même convention qu'audio_capture.gd --
		# `is_bot = true` fait sortir `PlayerInput._physics_process` tout de
		# suite (`if is_bot: return`, AVANT même le calcul de `reads_devices` :
		# lire ce dernier "manuellement" au préalable, comme un essai précédent
		# le faisait, ne sert donc à rien et n'empêche pas le vrai piège --
		# `reads_devices` se recalcule de toute façon `player.is_local_human()
		# and Input.mouse_mode == CAPTURED` À CHAQUE tick tant qu'`is_bot` est
		# faux, écrasant `fire_held` avec l'état RÉEL de la souris (jamais
		# pressée ici) une frame physique après l'autre). Avec `is_bot = true`,
		# PlayerInput ne touche plus JAMAIS `.fire_held` -- exactement ce qu'il
		# faut pour le tenir manuellement.
		#
		# Contrepartie (voir Weapon.gd, commentaire sur `origin`/BUG-26,
		# et PlayerCamera.gd, tête de fichier) : `PlayerCamera._process`/
		# `_apply_interpolated_transform` (recomposition AUTOMATIQUE de la
		# caméra depuis %Head, chaque frame) ne tourne QUE pour
		# `is_local_human()`, donc plus du tout une fois `is_bot` posé -- MAIS
		# `top_level` a déjà été mis à `true` par `PlayerCamera._ready()` AVANT
		# que ce script n'existe (le joueur a spawné en VRAI humain local), ce
		# qui reste vrai pour toujours : la caméra ne sera donc plus JAMAIS
		# recomposée depuis son parent tant qu'on ne touche pas nous-mêmes à
		# `global_transform` -- exactement ce qu'il faut pour la piloter "à la
		# main", sans qu'aucun autre système ne vienne écraser notre écriture
		# entre deux frames (voir `_place_player_facing`, qui écrit directement
		# `_player.camera.global_transform`, jamais `head.rotation.x`/
		# `player.rotation.y` seuls -- ceux-ci ne suffiraient plus à orienter
		# une caméra devenue indépendante de la hiérarchie de scène).
		_player.is_bot = true
		_player.input.reads_devices = false
		_player.input.weapon_slot_pressed = 0  # id 0 = Ravage (démarre déjà dessus, mais explicite).
		await _wait_physics(3)
		_player.input.weapon_slot_pressed = -1
		await _wait_sim(0.4)

func _wait_for_local_player(timeout: float) -> PlayerController:
	var t := 0.0
	while t < timeout:
		for n in get_nodes_in_group("local_player"):
			if is_instance_valid(n) and not (n as Node).is_queued_for_deletion():
				return n as PlayerController
		await physics_frame
		t += 1.0 / 60.0
	return null

func _wait_physics(n: int) -> void:
	for i in n:
		await physics_frame

func _wait_sim(seconds: float) -> void:
	await create_timer(seconds).timeout

# ==========================================================================
#  UNE SURFACE : mise en place -> ~10 tirs -> plan serré -> deux captures
# ==========================================================================
## `target` = point visé (centre de la surface touchée) ; `approach_dir` =
## direction horizontale FIXE (normalisée) depuis `target` vers le joueur ;
## `fire_dist_m` = distance de tir (consigne "~3 m" pour le conteneur) ;
## `close_dist_m` = distance resserrée pour les captures ("close-ups").
func _shoot_and_capture(target: Vector3, approach_dir: Vector2, fire_dist_m: float, close_dist_m: float, name_puff: String, name_decal: String) -> void:
	_place_player_facing(target, approach_dir, fire_dist_m)
	await _wait_physics(5)  # laisse la téléportation/l'orientation se stabiliser (collision, caméra).

	_player.input.fire_held = true
	await _wait_sim(1.05)  # fire_rate Ravage = 10/s (voir resources/weapons/ravage.tres) -> ~10 coups.
	_player.input.fire_held = false
	await _wait_physics(2)  # laisse le tout dernier impact (raycast+VFX) se poser cette frame-ci.

	_place_player_facing(target, approach_dir, close_dist_m)  # plan serré (consigne "close-ups").
	await _wait_physics(3)
	_hide_stuck_muzzle_flash()

	await _save(name_puff)   # bouffée/étincelle encore visibles (juste après les tirs).
	await _wait_sim(1.0)
	await _save(name_decal)  # ~1 s plus tard : bouffée/étincelle éteintes, décalques seuls.

## Même déroulé que `_shoot_and_capture`, mais UN SEUL coup sur un point FRAIS
## (jamais visé par la salve de 10, voir les appels ci-dessus) : sert
## uniquement à juger le rendu du décalque/de la FX de CETTE tâche sans le
## bruit visuel de 10 salves d'ImpactFx superposées sur quelques cm². Le
## Ravage est `automatic` (resources/weapons/ravage.tres) : `Weapon._owner_tick`
## lit alors `fire_held` (jamais `fire_pressed`, réservé aux armes semi-
## automatiques) -- une seule frame physique à `true` suffit, `FireClock`
## n'accordant de toute façon jamais plus d'un coup par tick.
func _shoot_single_and_capture(target: Vector3, approach_dir: Vector2, fire_dist_m: float, close_dist_m: float, name_puff: String, name_decal: String) -> void:
	_place_player_facing(target, approach_dir, fire_dist_m)
	await _wait_physics(5)

	_player.input.fire_held = true
	await _wait_physics(1)
	_player.input.fire_held = false
	await _wait_physics(2)

	_place_player_facing(target, approach_dir, close_dist_m)
	await _wait_physics(3)
	_hide_stuck_muzzle_flash()

	await _save(name_puff)
	await _wait_sim(1.0)
	await _save(name_decal)

## Place `_player` à `dist_m` de `target` le long de `approach_dir` (horizontal,
## normalisé), à hauteur du sol (le Floor de Shipment a son dessus à y=0, voir
## shipment.tscn `Floor.transform`). `origin := player.head.global_position`
## (Weapon._fire_local -- Head suit la capsule normalement, `is_bot` ou pas,
## voir sa docstring) : le décalage local de `%Head` est FIXE (0, 1.6, 0),
## voir player.tscn -- reproduit ici en dur (`_EYE_HEIGHT_M`) pour poser la
## caméra au MÊME point sans dépendre de la hiérarchie de scène (voir plus
## bas). La DIRECTION du tir, elle, vient de `camera.global_transform.basis`
## (même fichier) : on écrit donc `_player.camera.global_transform`
## DIRECTEMENT (`Basis.looking_at`, -Z vers `target`) plutôt que
## `head.rotation.x`/`player.rotation.y` -- `PlayerCamera` est `top_level`
## (posé une fois pour toutes par `_ready()`, avant que ce script n'existe,
## voir le commentaire de `_boot()`) et ne recompose plus JAMAIS sa transform
## depuis %Head une fois `is_bot` vrai : une écriture DIRECTE sur la caméra
## est donc la seule façon de l'orienter ici, et elle TIENT (rien d'autre ne
## la touche entre deux frames).
const _EYE_HEIGHT_M := 1.6

func _place_player_facing(target: Vector3, approach_dir: Vector2, dist_m: float) -> void:
	var pos := Vector3(target.x + approach_dir.x * dist_m, 0.0, target.z + approach_dir.y * dist_m)
	_player.velocity = Vector3.ZERO
	_player.global_position = pos
	_player.reset_physics_interpolation()
	var eye_pos := pos + Vector3(0.0, _EYE_HEIGHT_M, 0.0)
	var basis := Basis.looking_at(target - eye_pos, Vector3.UP)
	_player.camera.global_transform = Transform3D(basis, eye_pos)

# ==========================================================================
#  CAPTURE D'ÉCRAN
# ==========================================================================
## Contournement de test (revue lead, captures rafale du 2026-09-27) : un
## SECOND carré translucide, sans rapport avec les impacts, restait visible
## près du canon -- traqué jusqu'au flash de bouche (`ViewModel._spawn_muzzle_
## flash`/`AnimState.muzzle_t`, quad plat non texturé `Color(1.0, 0.92, 0.55)`
## parenté sous "Muzzle", MUZZLE_DUR = 0.05 s). `scripts/player/**` est hors
## des fichiers que cette tâche autorise à modifier, et ce flash n'a de toute
## façon RIEN à voir avec les trous de balle -- il se déclenche à CHAQUE tir,
## qu'il touche un mur, un joueur ou rien. Live, avec un vrai joueur humain
## (ou un vrai bot, jamais rebasculé `is_bot` APRÈS son `_ready()` comme ici --
## voir la note sur `PlayerCamera`/`top_level` dans `_boot()`, même
## mécanisme), il s'éteint normalement au bout de 50 ms ; DANS ce script, où
## le joueur démarre humain puis devient `is_bot` en cours de route, `muzzle_t`
## ne redescend jamais à zéro tout seul, et `ViewModel._process` (qui tourne
## toujours, lui, quel que soit `is_bot`) réaffiche le quad CHAQUE frame avec
## `_muzzle_mesh.visible = _anim.is_muzzle_visible()` -- un simple
## `.visible = false` posé une fois ne tient donc pas jusqu'à la capture
## suivante (```_process``` l'écrase avant même le prochain rendu). On
## remet directement `muzzle_t` à 0 à la source (`ViewModel._anim`, un champ
## PRÉFIXÉ souligné mais PAS privé en GDScript -- même convention que
## `ut._equip.deploy_left = 0.0` dans audio_capture.gd) : `is_muzzle_visible()`
## répond alors FAUX de lui-même, et `ViewModel._process` cache le quad sans
## qu'on ait besoin de le refaire nous-mêmes à chaque frame. Pour ne pas
## fausser la vérification VISUELLE des décalques/FX de CETTE tâche (le seul
## carré qui comptait, celui d'`ImpactFx.spawn()` dupliqué, est corrigé dans
## Weapon.gd -- voir le rendu de tâche) -- aucune ligne de scripts/player/**
## n'est modifiée, seul un champ d'état est relu/réécrit depuis NOTRE outil.
func _hide_stuck_muzzle_flash() -> void:
	var weapon := _player.get_node_or_null("Weapon")
	var vm: Object = weapon.view_model if weapon and "view_model" in weapon else null
	if vm and "_anim" in vm and "muzzle_t" in vm._anim:
		vm._anim.muzzle_t = 0.0
	# Repli défensif (structure différente/pas encore trouvée) : cache aussi
	# directement le maillage, au cas où `_process` ne repasserait pas avant
	# la capture (ex. modèle sans arme animée).
	var muzzle := _world.find_child("Muzzle", true, false)
	if muzzle == null:
		return
	for c in muzzle.get_children():
		if c is MeshInstance3D:
			c.visible = false

func _save(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var path := ProjectSettings.globalize_path(OUT_DIR.path_join(file_name))
	var err := img.save_png(path)
	print("impact_capture: ", file_name, " -> ", path, " (err=", err, ")")
