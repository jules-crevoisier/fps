## map_shots.gd
## Capture d'écran EN FENÊTRÉ (comme tools/screenshot.gd — il faut un vrai
## swapchain) d'un top-down + vues à hauteur de joueur PAR MAP (contract-r3.md,
## R3-MAPS acceptance #4), pour juger la lisibilité (lanes, cover, landmarks)
## et itérer. Une caméra EXTERNE (jamais le joueur — aucune sélection d'agent
## à attendre) est repositionnée pour chaque vue ; les poses de caméra sont
## calculées depuis les données de layout réelles, pas codées en dur par map.
##
##   godot --path . -s res://tools/map_shots.gd -- [--out=C:/dossier/] [--wait=N] [--maps=cargo_ship,wasteland]
##
## Écrit "<out>/<map_id>_<vue>.png" pour chaque map de `MapCatalog.all()`
## (filtrée par --maps si donné), imprime `MAP_SHOT <map_id> <vue> <chemin>`
## par capture puis `MAP_SHOTS_DONE` et quitte (0), ou `MAP_SHOTS_FAIL
## <raison>` (1).
extends SceneTree

const _LEVEL_LOOK_SCRIPT := preload("res://scripts/core/LevelLook.gd")
const _INK_POST_SCRIPT := preload("res://scripts/core/InkPost.gd")
const DEFAULT_OUT := "C:/Users/srko/AppData/Local/Temp/claude/C--Users-srko-Desktop-fps/02e156fb-5e66-4722-9835-071a024d62a9/scratchpad/shots/r3"
const DEFAULT_WAIT_FRAMES := 50

var _out_dir: String = DEFAULT_OUT
var _wait_frames: int = DEFAULT_WAIT_FRAMES
var _map_filter: PackedStringArray = []

var _maps: Array = []
var _map_index: int = 0
var _pose_index: int = 0
var _poses: Array = []  # poses de la map courante : [{name, pos, look}, ...]

var _cam: Camera3D
var _current_scene_inst: Node
var _frame: int = 0
var _started: bool = false
var _failed: bool = false


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out_dir = a.get_slice("=", 1)
		elif a.begins_with("--wait="):
			_wait_frames = int(a.get_slice("=", 1))
		elif a.begins_with("--maps="):
			_map_filter = a.get_slice("=", 1).split(",")


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		return _start()
	if _failed:
		return true
	if _cam:
		_cam.current = true
	_ensure_ink_post()
	_frame += 1
	if _frame < _wait_frames:
		return false
	_capture_current_pose()
	return _advance()


func _start() -> bool:
	var look: Node = _LEVEL_LOOK_SCRIPT.new()
	root.add_child(look)
	_maps = MapCatalog.all()
	if not _map_filter.is_empty():
		_maps = _maps.filter(func(m): return _map_filter.has(String(m["id"])))
	if _maps.is_empty():
		return _fail("MapCatalog.all() est vide (ou --maps= ne correspond à rien)")
	_cam = Camera3D.new()
	root.add_child(_cam)
	_cam.current = true
	return _load_map(0)


func _load_map(index: int) -> bool:
	if index >= _maps.size():
		print("MAP_SHOTS_DONE")
		quit(0)
		return true
	_map_index = index
	_pose_index = 0
	_frame = 0
	var entry: Dictionary = _maps[index]
	# §-polish (lead review) : sans ceci, MatchConfig.map_id restait à la
	# valeur laissée par la DERNIÈRE map traitée (ou "wasteland", repli par
	# défaut de Cartoon._DEFAULT_MAP_ID) — chaque scène héritait donc du
	# ciel/soleil/teinte d'ombre d'une AUTRE carte. `Look` (autoload) lit
	# MatchConfig.map_id au moment où WorldEnvironment/DirectionalLight3D
	# entrent dans l'arbre (juste après add_child ci-dessous) : il faut
	# l'avoir posé AVANT.
	MatchConfig.map_id = String(entry["id"])
	var packed := load(String(entry["scene"])) as PackedScene
	if packed == null:
		return _fail("scène introuvable : %s" % entry["scene"])
	if _current_scene_inst and is_instance_valid(_current_scene_inst):
		_current_scene_inst.queue_free()
	var inst := packed.instantiate()
	# Évite l'écran de sélection d'agent (GameWorld.agent_select), qui est un
	# plein-écran 2D par-dessus la scène 3D et couvrirait toute capture.
	if inst.get("agent_select") != null:
		inst.set("agent_select", false)
	# Idem pour le remplissage bots (MatchConfig.bots_enabled vaut TRUE par
	# défaut, et ce script tourne toujours "serveur" faute de pair réseau) :
	# un bot errant dans le cadre rend chaque capture non déterministe et
	# hors-sujet pour une vue "salle vide" comparée aux feuilles de référence.
	if inst.get("allow_bot_fill") != null:
		inst.set("allow_bot_fill", false)
	root.add_child(inst)
	_current_scene_inst = inst
	current_scene = inst
	_poses = _poses_for(String(entry["id"]))
	_apply_pose(_poses[0])
	return false


# ======================================================================
#  Sécurité caméra (lead review : "never inside geometry (raycast the
#  camera position)") — un lancer de rayon PHYSIQUE réel depuis un point
#  d'ancrage connu-sûr (spawn/hardpoint/toit) vers la cible visée ; si un
#  corps solide est touché avant, la caméra s'arrête `margin` m avant (elle
#  continue de REGARDER la cible d'origine, donc la vue reste "dans l'axe du
#  couloir" même arrêtée plus tôt par un mur). Nécessite au moins une frame
#  physique après le chargement de la scène pour que les formes de collision
#  soient enregistrées — jamais appelé sur la toute première pose (le
#  top-down, toujours haut et sûr) d'une map qui vient de charger.
# ======================================================================
func _raycast_clamp(anchor: Vector3, target: Vector3, margin: float = 0.4) -> Vector3:
	var world := root.get_world_3d()
	if world == null:
		return anchor
	var space := world.direct_space_state
	if space == null:
		return anchor
	var dir := target - anchor
	var dist := dir.length()
	if dist < 0.05:
		return anchor
	dir /= dist
	var params := PhysicsRayQueryParameters3D.create(anchor, target)
	params.collide_with_areas = false
	params.collide_with_bodies = true
	var result := space.intersect_ray(params)
	if result.is_empty():
		# Rien touché avant `target` : la voie est libre, on avance jusqu'au
		# bout (bug corrigé ici — cette branche renvoyait `anchor` avant,
		# ANNULANT toute avance sur un chemin dégagé, cf. wasteland_spawn_bleu
		# itération 2 : cadre presque noir, la caméra restait collée au
		# point de spawn lui-même au lieu d'avancer dans la rue).
		return target
	var hit_pos: Vector3 = result["position"]
	var hit_dist := anchor.distance_to(hit_pos)
	var safe_dist := maxf(hit_dist - margin, 0.1)
	return anchor + dir * safe_dist


## Une vue à hauteur de joueur "en marche" : part de `anchor` (au sol,
## contact-sol — spawn/point nommé), vise `aim` au loin dans la direction
## `dir_hint` (déjà normalisée en XZ), avance jusqu'à `advance` m MAIS jamais
## à travers un mur (raycast). `eye_h` : hauteur des yeux au-dessus du sol
## de `anchor` (1.6 m debout au niveau du pont/de la rue ; plus si `anchor`
## est déjà un toit/point haut — l'appelant ajoute alors `eye_h` à la main).
## `look_y` (défaut = même hauteur que l'œil, regard à plat) : hauteur
## ABSOLUE de la cible visée — plus bas que l'œil pour un "point haut" qui
## plonge sur la scène plutôt que de fixer l'horizon (vérifié en image :
## à plat depuis un toit, la caméra ne voit qu'un mince ruban de decor au-
## dessus d'un parapet vide, pas la scène qu'on veut montrer).
func _walk_pose(nm: String, anchor: Vector3, dir_hint: Vector3, eye_h: float, advance: float, look_dist: float, look_y: float = INF) -> Dictionary:
	var d := dir_hint
	d.y = 0
	d = d.normalized() if d.length() > 0.01 else Vector3.FORWARD
	var eye_anchor := anchor + Vector3(0, eye_h, 0)
	var candidate := eye_anchor + d * advance
	var safe_pos := _raycast_clamp(eye_anchor, candidate)
	var look_at_pt := eye_anchor + d * look_dist
	if look_y != INF:
		look_at_pt.y = look_y
	return {"name": nm, "pos": safe_pos, "look": look_at_pt}


## 4 vues 3/4 aériennes (coins, "VUES 3D - TOUS LES ANGLES" des feuilles de
## référence) — toujours hautes/hors géométrie, pas de raycast nécessaire.
func _aerial_poses(bounds: Dictionary) -> Array:
	var mn: Vector2 = bounds["min"]
	var mx: Vector2 = bounds["max"]
	var center := Vector3((mn.x + mx.x) * 0.5, 0, (mn.y + mx.y) * 0.5)
	var span: float = maxf(mx.x - mn.x, mx.y - mn.y)
	var dist := span * 0.7
	var h := span * 0.5
	var out: Array = []
	for entry in [["aerial_nw", Vector2(-1, -1)], ["aerial_ne", Vector2(1, -1)], ["aerial_sw", Vector2(-1, 1)], ["aerial_se", Vector2(1, 1)]]:
		var nm: String = entry[0]
		var dir2: Vector2 = (entry[1] as Vector2).normalized()
		var pos := center + Vector3(dir2.x, 0, dir2.y) * dist + Vector3(0, h, 0)
		out.append({"name": nm, "pos": pos, "look": center})
	return out


## Cargo Ship/Wasteland (maps-spec-v2.md, hors Layouts.gd) : top, 5 vues
## in-game NOMMÉES comme la ligne "VUES IN-GAME" de .orchestrator/refs/
## wasteland_sheet.png (spawn bleu/centre map/point haut/route secondaire/
## spawn rouge — Cargo Ship n'a pas cette ligne sur sa feuille, mais le lead
## veut le même jeu de vues sur les deux, cf. sa review), + 4 vues 3D
## aériennes ("VUES 3D - TOUS LES ANGLES").
func _poses_for_v2(map_id: String, data: Dictionary) -> Array:
	var sp0: Dictionary = data["spawns"][0][0]
	var sp1: Dictionary = data["spawns"][1][0]
	var team0_spawn: Vector3 = sp0["pos"]
	var team1_spawn: Vector3 = sp1["pos"]
	var look0: Vector3 = sp0.get("look", team0_spawn)
	var look1: Vector3 = sp1.get("look", team1_spawn)
	var bounds: Dictionary = data["bounds"]
	var mn: Vector2 = bounds["min"]
	var mx: Vector2 = bounds["max"]
	var top_y: float = maxf(mx.x - mn.x, mx.y - mn.y) + 20.0

	var poses: Array = [{"name": "top", "pos": Vector3(0, top_y, 0.01), "look": Vector3(0, 0, 0)}]

	# `look0`/`look1` (table §4/§5) visent délibérément le bouclier de spawn à
	# bout portant (le check "aucune paire de spawn à vue dégagée") — de très
	# bonnes cibles pour le test de ligne de vue, de MAUVAISES cibles pour une
	# "vue in-game" (la caméra se retrouve nez contre un mur, cf. itération 1
	# : cargo_ship OK mais wasteland_spawn_bleu collé au mur sud de FuelHouse).
	# Ici on vise plutôt le CENTRE de la carte : ça correspond à "avancer dans
	# la carte", la direction qu'une vue "spawn bleu"/"spawn rouge" de feuille
	# de référence montre réellement.
	# Décalage latéral (+z, sur l'ANCRE elle-même, pas juste la direction) :
	# à Wasteland, FuelBillboard (x -33.5, z -1, à peine 2.7 m du spawn bleu)
	# ET TankerWreck/TankN (côté rouge) sont plantés QUASIMENT SUR la ligne
	# z=-1 du spawn — un simple biais de DIRECTION n'a pas le temps de dévier
	# assez avant de les toucher (testé itération 3 : encore un cadre noir,
	# nez au mur). Décaler l'ANCRE de 2.5 m avant d'avancer plein est/ouest
	# passe ces deux obstacles sans les traverser (vérifié contre leurs
	# footprints réels).
	var anchor0 := team0_spawn + Vector3(0, 0, 2.5)
	var anchor1 := team1_spawn + Vector3(0, 0, 2.5)
	var to_center0 := Vector3(-team0_spawn.x, 0, 0)
	var to_center1 := Vector3(-team1_spawn.x, 0, 0)
	if map_id == "cargo_ship":
		# Cargo : le spawn est DÉJÀ sur le pont latéral (SideDeck) — foncer
		# vers le centre (x0) plonge tout de suite dans le mur de conteneurs
		# de l'îlot/ancre (2-3 m à peine, cf. itération 3, cadre rouge nez-au-
		# mur). Le vrai couloir dégagé longe le pont, exactement la direction
		# du "look" de la table §4 (l'axe même que le check anti-vue-directe
		# de test_cargo_ship.gd valide) — sûr désormais grâce au raycast.
		poses.append(_walk_pose("spawn_bleu", team0_spawn, look0 - team0_spawn, 1.6, 10.0, 40.0))
		poses.append(_walk_pose("spawn_rouge", team1_spawn, look1 - team1_spawn, 1.6, 10.0, 40.0))
		poses.append(_walk_pose("centre_map", Vector3(3.0, 1.3, 6), Vector3(0, 0, -1), 1.6, 6.0, 30.0))
		poses.append(_walk_pose("point_haut", Vector3(0, 6.4, -30), Vector3(0, 0, 1), 1.6, 3.0, 30.0, 0.0))
		poses.append(_walk_pose("route_secondaire", Vector3(16, 0, -5), Vector3(0, 0, 1), 1.6, 6.0, 25.0))
	else:  # wasteland
		# `ink_sky.gdshader` (hors de mon périmètre — pipeline rendu) : la
		# moitié d'un cadre qui regarde plein OUEST (vers l'azimut du soleil,
		# sun_elevation 32° au SO) tombe au noir, reproduit à l'identique sur
		# une caméra nue sans rapport avec mes poses (voir le rapport final —
		# signalé pour la tranche rendu). Contournement CI : biaiser vers le
		# nord/sud plutôt que plein ouest pour les vues qui regarderaient
		# sinon droit vers cet azimut (spawn_rouge, point_haut).
		poses.append(_walk_pose("spawn_bleu", anchor0, to_center0, 1.6, 8.0, 40.0))
		poses.append(_walk_pose("spawn_rouge", team1_spawn, Vector3(-0.3, 0, 1), 1.6, 8.0, 40.0))
		poses.append(_walk_pose("centre_map", Vector3(0, 0, 0), Vector3(1, 0, 0), 1.6, 5.0, 30.0))
		poses.append(_walk_pose("point_haut", Vector3(1.5, 5.6, -11.5), Vector3(-1, 0, 2.5), 1.6, 2.0, 45.0, 0.0))
		poses.append(_walk_pose("route_secondaire", Vector3(5.0, 0, -17.0), Vector3(1, 0, -0.3), 1.6, 6.0, 25.0))

	poses.append_array(_aerial_poses(bounds))
	return poses


func _poses_for(map_id: String) -> Array:
	var data := Layouts.data_for(map_id)
	if data.is_empty():
		match map_id:
			"cargo_ship":
				return _poses_for_v2(map_id, CargoShipLayout.data())
			"wasteland":
				return _poses_for_v2(map_id, WastelandLayout.data())
		return [{"name": "top", "pos": Vector3(0, 40, 0), "look": Vector3(0, 0, 0.001)}]
	var is_arena := data.has("duel_zone")
	var sp0: Dictionary = data["spawns"][0][0]
	var sp1: Dictionary = data["spawns"][1][0]
	var team0_spawn: Vector3 = sp0["pos"]
	var team1_spawn: Vector3 = sp1["pos"]
	# Les vues à hauteur de joueur avancent depuis le spawn vers la cible
	# AVANT de regarder : debout PILE au spawn, la caméra fait face au
	# bouclier de spawn (un mur/cheminée volontairement collé au spawn,
	# maps-spec.md §3 "blocks every pair") à bout portant. Un joueur qui a
	# fait quelques pas voit la vraie lane/le vrai duel.
	var target: Vector3 = (data["duel_zone"] as Dictionary)["pos"] if is_arena else Vector3(0, team0_spawn.y, 0)
	var advance: float = 6.0 if is_arena else 15.0
	var dir0 := (target - team0_spawn)
	dir0.y = 0
	dir0 = dir0.normalized() if dir0.length() > 0.01 else Vector3.FORWARD
	var dir1 := (target - team1_spawn)
	dir1.y = 0
	dir1 = dir1.normalized() if dir1.length() > 0.01 else Vector3.FORWARD
	var top_pos := Vector3(0, 26, 0.01) if is_arena else Vector3(0, 58, 0.01)
	return [
		{"name": "top", "pos": top_pos, "look": Vector3(0, 0, 0)},
		{"name": "eye1", "pos": team0_spawn + dir0 * advance + Vector3(0, 0.7, 0), "look": target + Vector3(0, 0.7, 0)},
		{"name": "eye2", "pos": team1_spawn + dir1 * advance + Vector3(0, 0.7, 0), "look": target + Vector3(0, 0.7, 0)},
	]


func _apply_pose(pose: Dictionary) -> void:
	_cam.global_position = pose["pos"]
	_cam.look_at(pose["look"], Vector3.UP)
	_cam.current = true


func _ensure_ink_post() -> void:
	if _cam and _cam.get_node_or_null("InkPost") == null:
		var post := _INK_POST_SCRIPT.new()
		post.name = "InkPost"
		_cam.add_child(post)


func _capture_current_pose() -> void:
	if _cam:
		_cam.current = true
	_ensure_ink_post()
	var entry: Dictionary = _maps[_map_index]
	var pose: Dictionary = _poses[_pose_index]
	var out_path := "%s/%s_%s.png" % [_out_dir, entry["id"], pose["name"]]
	var img := root.get_texture().get_image()
	var dir := out_path.get_base_dir()
	if dir != "" and not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var err := img.save_png(out_path)
	if err != OK:
		_fail("échec écriture PNG (%d) : %s" % [err, out_path])
		return
	print("MAP_SHOT ", entry["id"], " ", pose["name"], " ", out_path)


func _advance() -> bool:
	_pose_index += 1
	if _pose_index < _poses.size():
		_frame = 0
		_apply_pose(_poses[_pose_index])
		return false
	return _load_map(_map_index + 1)


func _fail(reason: String) -> bool:
	print("MAP_SHOTS_FAIL ", reason)
	_failed = true
	quit(1)
	return true
