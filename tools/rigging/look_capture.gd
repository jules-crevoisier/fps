## look_capture.gd
## Captures de comparaison du rendu (avant/après un réglage de style) : vue FPS, portrait du bot
## en 3e personne, vue d'ensemble de la carte. Temps piloté par la physique ; le bot est figé ;
## la fenêtre ne prend pas le focus (la souris de l'utilisateur ne change rien).
##   "%GODOT%" --screen 1 --path . -s res://tools/rigging/look_capture.gd -- --tag=avant
## Images : reports/checkpoints/look/<tag>_{fps,portrait,overview}.png
##
## `--map=<id>` (MapCatalog, 2026-09-28, Canyon Express) : charge la scène de
## `id` au lieu de Shipment -- AJOUTÉ, comportement de tout appelant existant
## INCHANGÉ (aucun ne le passe, `_SHIPMENT` reste le repli par défaut/pour un
## id inconnu ou sans scène).
##
## `--shot=<nom>@px,py,pz@lx,ly,lz` (répétable) : bascule sur un flux SANS
## joueur/bot/arme -- une caméra libre posée successivement à chaque position/
## cible donnée (coordonnées MONDE), fond nettoyé par `--out=`/`--nohud` comme
## le flux historique. Le `Driver` ci-dessous (couplé au duo joueur/bot de
## Shipment -- viser, portrait 3e personne) reste RÉSERVÉ au cas SANS
## `--shot=` : ces captures d'architecture (matériaux/éclairage/ciel d'une
## carte, Canyon Express en particulier) n'ont besoin d'aucun des deux.
##   "%GODOT%" --screen 1 --path . -s res://tools/rigging/look_capture.gd -- \
##       --map=canyon_express --tag=canyon --nohud \
##       --out=res://reports/checkpoints/2026-09-28_canyon \
##       --shot=aerial@46,40,52@0,-3,0 --shot=north_spawn@10,1.7,-29.5@1,0.5,0
extends SceneTree

const _SHIPMENT := "res://scenes/levels/maps/shipment.tscn"
const OUT_DIR := "res://reports/checkpoints/look"
const _MAP_CATALOG_SCRIPT := preload("res://scripts/levels/maps/MapCatalog.gd")


## Caméra libre séquentielle (voir la doc de tête, "--shot=") -- coroutine
## simple (une seule fonction `await`e en boucle) plutôt qu'une machine à
## tick façon `Driver` : chaque prise attend son propre settle DEPUIS la
## position qu'elle vient de recevoir, jamais une avance en parallèle d'une
## sauvegarde encore en vol (`Driver._save` est appelée en `call_deferred`
## SANS attendre car son seul appelant, `_physics_process`, ne repositionne
## plus jamais la caméra APRÈS -- un `--shot=` répété le ferait, donc ici
## chaque étape est explicitement attendue avant la suivante).
class ShotDriver extends Node:
	var tree: SceneTree
	var tag := "look"
	var out_dir := OUT_DIR
	var shots: Array = []

	## `out_dir`/`tag` déjà posés par l'appelant avant `begin()` -- démarre la
	## coroutine en tâche de fond (jamais attendue ici : `_initialize()` n'est
	## lui-même pas une coroutine).
	func begin() -> void:
		_run()

	func _run() -> void:
		for i in 90:   # laisse Look/ToonStyle styler l'Environment + la physique se stabiliser.
			await tree.process_frame
		_hide_players()
		var cam := Camera3D.new()
		tree.get_root().add_child(cam)
		cam.current = true
		for shot in shots:
			var s: Dictionary = shot
			cam.global_position = s["pos"]
			cam.look_at(s["look_at"], Vector3.UP)
			for i in 12:
				await tree.process_frame
			await _save(String(s["name"]))
		print("LOOK_SHOTS_DONE ", tag)
		tree.quit()

	## Les captures d'architecture n'ont besoin d'aucun personnage dans le
	## cadre -- `_spawn_local()` (scripts/networking/GameWorld.gd) pose
	## toujours un joueur local, `bots_enabled=false` n'empêche que le
	## remplissage bot -- cachées plutôt que libérées (jamais de risque de
	## dépendance rompue pendant que le reste de la scène tourne encore).
	func _hide_players() -> void:
		for p in tree.get_root().find_children("*", "PlayerController", true, false):
			(p as Node3D).visible = false

	func _save(name: String) -> void:
		if "--nohud" in OS.get_cmdline_user_args():
			for layer in tree.get_root().find_children("*", "CanvasLayer", true, false):
				(layer as CanvasLayer).visible = false
		await RenderingServer.frame_post_draw
		var img := tree.get_root().get_texture().get_image()
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
		img.save_png(ProjectSettings.globalize_path(out_dir.path_join("%s_%s.png" % [tag, name])))
		print("LOOK_SAVED ", tag, "_", name)


class Driver extends Node:
	var tree: SceneTree
	var tag := "look"
	var tick := -1
	var player: PlayerController
	var bot: PlayerController
	var cam: Camera3D

	func _physics_process(_delta: float) -> void:
		tick += 1
		if tick == 120:
			for p in _players(tree.get_root()):
				if p.is_local_human():
					player = p
				elif bot == null:
					bot = p
			if player:
				player.set_process_unhandled_input(false)
				player.set_process_input(false)
			for n in tree.get_root().find_children("*", "DirectionalLight3D", true, false):
				var sun := n as DirectionalLight3D
				print("LOOK_SUN dir=", -sun.global_transform.basis.z, " energy=", sun.light_energy,
					" shadows=", sun.shadow_enabled, " color=", sun.light_color)
				if "--noshadow" in OS.get_cmdline_user_args():
					sun.shadow_enabled = false
		if tick == 125 and player:
			Input.action_press("weapon_2")
		if tick == 128:
			Input.action_release("weapon_2")
		if tick == 200 and bot:
			bot.process_mode = Node.PROCESS_MODE_DISABLED   # figé pour des vues comparables
			# le bot face au joueur, à 6 m devant lui
			var fwd := -player.global_transform.basis.z
			fwd.y = 0.0
			bot.global_position = player.global_position + fwd.normalized() * 6.0
			bot.look_at(player.global_position, Vector3.UP)
			bot.rotate_y(PI)
		if tick == 230:
			_save.call_deferred("fps")
		if tick == 250 and bot:
			cam = Camera3D.new()
			cam.fov = 40.0
			tree.get_root().add_child(cam)
			var head: Vector3 = bot.global_position + Vector3(0, 1.45, 0)
			var front := bot.global_transform.basis.z  # le bot regarde -Z ; on se place devant
			front.y = 0.0
			cam.global_position = head + front.normalized() * 2.4 + bot.global_transform.basis.x * 0.9 + Vector3(0, 0.1, 0)
			cam.look_at(head - Vector3(0, 0.35, 0), Vector3.UP)
			cam.make_current()
		if tick == 262:
			_save.call_deferred("portrait")
		if tick == 270 and cam:
			cam.fov = 60.0
			cam.global_position = Vector3(18.0, 14.0, 18.0)
			cam.look_at(Vector3.ZERO, Vector3.UP)
		if tick == 282:
			_save.call_deferred("overview")
		if tick == 290 and cam:   # vue du dessus orthographique (minimap des maquettes)
			cam.projection = Camera3D.PROJECTION_ORTHOGONAL
			cam.size = 46.0
			cam.look_at_from_position(Vector3(0.0, 40.0, 0.0), Vector3.ZERO, Vector3.FORWARD)
		if tick == 298:
			_save.call_deferred("top")
		if tick == 310:
			tree.quit()

	func _save(view: String) -> void:
		if "--nohud" in OS.get_cmdline_user_args():   # fond propre pour les maquettes d'interface
			for layer in tree.get_root().find_children("*", "CanvasLayer", true, false):
				(layer as CanvasLayer).visible = false
		await RenderingServer.frame_post_draw
		var img := tree.get_root().get_texture().get_image()
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
		img.save_png(ProjectSettings.globalize_path(OUT_DIR.path_join("%s_%s.png" % [tag, view])))
		print("LOOK_SAVED ", tag, "_", view)

	func _players(n: Node) -> Array:
		var out: Array = []
		if n is PlayerController:
			out.append(n)
		for c in n.get_children():
			out.append_array(_players(c))
		return out


## `--shot=<nom>@px,py,pz@lx,ly,lz` -> {"name":String,"pos":Vector3,"look_at":Vector3},
## silencieusement ignoré si mal formé (jamais une erreur pour un outil de capture manuel).
static func _parse_shot(raw: String) -> Dictionary:
	var parts := raw.split("@")
	if parts.size() != 3:
		return {}
	var pos_parts := parts[1].split(",")
	var look_parts := parts[2].split(",")
	if pos_parts.size() != 3 or look_parts.size() != 3:
		return {}
	return {
		"name": parts[0],
		"pos": Vector3(float(pos_parts[0]), float(pos_parts[1]), float(pos_parts[2])),
		"look_at": Vector3(float(look_parts[0]), float(look_parts[1]), float(look_parts[2])),
	}


## `--map=<id>` -> chemin de scène (MapCatalog) ; repli sur Shipment si `id`
## est "shipment", inconnu, ou sans scène sur disque -- jamais une erreur.
static func _resolve_scene(map_id: String) -> String:
	if map_id == "" or map_id == "shipment":
		return _SHIPMENT
	var entry := _MAP_CATALOG_SCRIPT.get_by_id(map_id)
	if entry.is_empty() or not ResourceLoader.exists(str(entry.get("scene", ""))):
		return _SHIPMENT
	return str(entry["scene"])


func _initialize() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	MatchConfig.mode_id = "tdm"

	var map_id := "shipment"
	var tag := "look"
	var out_dir := OUT_DIR
	var shots: Array = []
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--map="):
			map_id = arg.trim_prefix("--map=")
		elif arg.begins_with("--tag="):
			tag = arg.trim_prefix("--tag=")
		elif arg.begins_with("--out="):
			out_dir = arg.trim_prefix("--out=")
		elif arg.begins_with("--shot="):
			var parsed := _parse_shot(arg.trim_prefix("--shot="))
			if not parsed.is_empty():
				shots.append(parsed)

	var scene_path := _resolve_scene(map_id)
	MatchConfig.map_id = map_id if scene_path != _SHIPMENT else "shipment"

	if not shots.is_empty():
		# Captures d'architecture (voir la doc de tête, "--shot=") : pas de
		# bot -- rien à faire viser/tirer, un bot dans le cadre ne serait
		# qu'une distraction pour une revue de matériaux/éclairage.
		MatchConfig.bots_enabled = false
		# Différé : voir le commentaire équivalent ci-dessous (legacy) -- même raison.
		get_root().add_child.call_deferred((load(scene_path) as PackedScene).instantiate())
		var sd := ShotDriver.new()
		sd.tree = self
		sd.tag = tag
		sd.out_dir = out_dir
		sd.shots = shots
		get_root().add_child(sd)
		sd.begin()
		return

	# --- flux EXISTANT, INCHANGÉ (aucun --shot= : Shipment/joueur+bot/arme) ---
	MatchConfig.bots_enabled = true
	MatchConfig.team_size = 1
	# Différé : _initialize() tourne AVANT le _ready des autoloads (racine pas encore dans l'arbre)
	# -- ajoutée tout de suite, la carte échapperait à Look (LevelLook.node_added) et garderait
	# un soleil horizontal non stylé, sans rapport avec le jeu réel.
	get_root().add_child.call_deferred((load(scene_path) as PackedScene).instantiate())
	var d := Driver.new()
	d.tree = self
	d.tag = tag
	get_root().add_child(d)
