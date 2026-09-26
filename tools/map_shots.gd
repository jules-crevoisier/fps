## map_shots.gd
## Capture d'écran EN FENÊTRÉ (comme tools/screenshot.gd — il faut un vrai
## swapchain) d'un top-down + vues à hauteur de joueur PAR MAP (contract-r3.md,
## R3-MAPS acceptance #4), pour juger la lisibilité (lanes, cover, landmarks)
## et itérer. Une caméra EXTERNE (jamais le joueur — aucune sélection d'agent
## à attendre) est repositionnée pour chaque vue ; les poses de caméra sont
## calculées depuis les données de layout réelles, pas codées en dur par map.
##
## Wasteland (LD-26, docs/research/09_wasteland_vertical_slice.md §f ; recalé
## sur le blockout v4 par LD-43, docs/research/11_wasteland_v4_layout.md) :
## 16 vues nommées imposées — 2 plans du dessus ORTHOGONAUX (`top_ortho` sans
## toits, `top_ortho_roofs`), 4 aériennes, 2 spawns, 3 lanes, 4 positions/zones
## (dont 3 zones Hardpoint) et 1 ligne longue. Le HUD (CanvasLayer "HUD" de
## GameHUD.gd, + PauseMenu/BuyMenu par prudence) est masqué avant toute
## capture : les captures existantes (reports/review/20260924-193722/
## map_shots/wasteland_top.png) montrent minuteries, vie, capacités et
## réticule incrustés sur CHAQUE vue (audit V13). Après chaque capture, une
## garde anti-caméra-dans-la-géométrie (`_dominant_hue_ratio`, cf. L10 —
## `wasteland_route_secondaire.png` était 100 % roche orange) recule et
## surélève la caméra puis relance la capture si une seule teinte dépasse 60 %
## des pixels, jusqu'à `MAX_POSE_RETRIES` tentatives.
##
##   godot --path . -s res://tools/map_shots.gd -- [--out=C:/dossier/] [--wait=N] [--maps=cargo_ship,wasteland]
##
## Écrit "<out>/<map_id>_<vue>.png" pour chaque map de `MapCatalog.all()`
## (filtrée par --maps si donné), imprime `MAP_SHOT <map_id> <vue> <chemin>`
## par capture (+ `MAP_SHOT_HUE_WARN <map_id> <vue> ratio=... retry=.../.. .`
## si la garde anti-teinte-unique a dû corriger ou a échoué) puis
## `MAP_SHOTS_DONE` et quitte (0), ou `MAP_SHOTS_FAIL <raison>` (1).
extends SceneTree

const _LEVEL_LOOK_SCRIPT := preload("res://scripts/core/LevelLook.gd")
const _INK_POST_SCRIPT := preload("res://scripts/core/InkPost.gd")
const DEFAULT_OUT := "C:/Users/srko/AppData/Local/Temp/claude/C--Users-srko-Desktop-fps/02e156fb-5e66-4722-9835-071a024d62a9/scratchpad/shots/r3"
const DEFAULT_WAIT_FRAMES := 50

## Hauteur (monde, sol = 0, convention `building2`/`box` du Kit) sous laquelle
## `top_ortho` coupe la scène (plan de coupe "near" d'une caméra orthogonale
## droit au-dessus = coupe par HAUTEUR, pas par distance à un sujet) : sous la
## quasi-totalité des toits à un étage (9 bâtiments sur 10 à 3,2 m, audit L4)
## et au-dessus des personnages/du mobilier de rue.
const ROOFLESS_CUTOFF_Y := 3.0

## Garde anti-caméra-dans-la-géométrie (LD-26 acceptance) : aucune vue ne doit
## dépasser cette fraction de pixels d'une seule teinte (nez dans un mur/une
## roche = quasi-monochrome). `HUE_BINS`/`HUE_WINDOW` : histogramme à 5°
## regroupé par fenêtres glissantes de 15° (une même surface peinte s'étale
## sur 2-3 bacs à cause de l'éclairage, sans quoi un bac isolé sous-compte une
## teinte réellement dominante).
const HUE_FAIL_RATIO := 0.60
const HUE_BINS := 72
const HUE_WINDOW := 3
const HUE_SAMPLE_STEP := 6 ## échantillonnage (perf) : 1 pixel sur 6x6
const HUE_MIN_SATURATION := 0.08 ## sous ce seuil, pixel quasi gris : pas de "teinte"
const MAX_POSE_RETRIES := 3

var _out_dir: String = DEFAULT_OUT
var _wait_frames: int = DEFAULT_WAIT_FRAMES
var _map_filter: PackedStringArray = []

var _maps: Array = []
var _map_index: int = 0
var _pose_index: int = 0
var _poses: Array = []  # poses de la map courante : [{name, pos, look}, ...]
var _pose_retry: int = 0

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
	var needs_retry := _capture_current_pose()
	if needs_retry:
		_pose_retry += 1
		_correct_current_pose()
		_frame = 0
		return false
	_pose_retry = 0
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
	_hide_hud(inst)
	_poses = _poses_for(String(entry["id"]))
	_pose_retry = 0
	_apply_pose(_poses[0])
	return false


## "aucun HUD" (LD-26 acceptance) : le CanvasLayer "HUD" (GameHUD.gd, ajouté
## par toutes les scènes de niveau) dessine minuteries/vie/capacités/réticule
## dès `_ready()`, sans dépendre d'un joueur local réel — confirmé par les
## captures existantes (wasteland_top.png, wasteland_route_secondaire.png),
## toutes incrustées. PauseMenu/BuyMenu par prudence (autres CanvasLayer de
## `scenes/levels/maps/wasteland.tscn`) : masqués plutôt que supprimés, pour
## ne dépendre d'aucun détail interne de GameHUD (masquer le CanvasLayer
## suffit à cacher tous ses enfants, quel que soit leur état).
func _hide_hud(inst: Node) -> void:
	for nm in ["HUD", "PauseMenu", "BuyMenu"]:
		var n := inst.get_node_or_null(nm)
		if n is CanvasLayer:
			(n as CanvasLayer).visible = false


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


## Cargo Ship (maps-spec-v2.md, hors Layouts.gd) : top, 5 vues in-game NOMMÉES
## comme la ligne "VUES IN-GAME" de .orchestrator/refs/wasteland_sheet.png
## (spawn bleu/centre map/point haut/route secondaire/spawn rouge — cf. review
## du lead), + 4 vues 3D aériennes ("VUES 3D - TOUS LES ANGLES"). Wasteland a
## son propre jeu de 16 vues depuis LD-26 (`_wasteland_poses`, ci-dessous).
func _poses_for_v2(data: Dictionary) -> Array:
	var sp0: Dictionary = data["spawns"][0][0]
	var sp1: Dictionary = data["spawns"][1][0]
	var look0: Vector3 = sp0.get("look", sp0["pos"])
	var look1: Vector3 = sp1.get("look", sp1["pos"])
	var team0_spawn: Vector3 = sp0["pos"]
	var team1_spawn: Vector3 = sp1["pos"]
	var bounds: Dictionary = data["bounds"]
	var mn: Vector2 = bounds["min"]
	var mx: Vector2 = bounds["max"]
	var top_y: float = maxf(mx.x - mn.x, mx.y - mn.y) + 20.0

	var poses: Array = [{"name": "top", "pos": Vector3(0, top_y, 0.01), "look": Vector3(0, 0, 0)}]

	# Cargo : le spawn est DÉJÀ sur le pont latéral (SideDeck) — foncer vers
	# le centre (x0) plonge tout de suite dans le mur de conteneurs de l'îlot/
	# ancre (2-3 m à peine, cf. itération 3, cadre rouge nez-au-mur). Le vrai
	# couloir dégagé longe le pont, exactement la direction du "look" de la
	# table §4 (l'axe même que le check anti-vue-directe de test_cargo_ship.gd
	# valide) — sûr désormais grâce au raycast.
	poses.append(_walk_pose("spawn_bleu", team0_spawn, look0 - team0_spawn, 1.6, 10.0, 40.0))
	poses.append(_walk_pose("spawn_rouge", team1_spawn, look1 - team1_spawn, 1.6, 10.0, 40.0))
	poses.append(_walk_pose("centre_map", Vector3(3.0, 1.3, 6), Vector3(0, 0, -1), 1.6, 6.0, 30.0))
	poses.append(_walk_pose("point_haut", Vector3(0, 6.4, -30), Vector3(0, 0, 1), 1.6, 3.0, 30.0, 0.0))
	poses.append(_walk_pose("route_secondaire", Vector3(16, 0, -5), Vector3(0, 0, 1), 1.6, 6.0, 25.0))

	poses.append_array(_aerial_poses(bounds))
	return poses


## Cherche une pièce par nom dans `data["pieces"]` (issues de WastelandLayout,
## chacune {"name":..., "pos":..., "size":...}) : les poses de lane restent
## calculées depuis la géométrie RÉELLE (repère du fichier, en-tête) au lieu
## de dupliquer des coordonnées à la main — si `wasteland.gd` bouge un jour
## DuneMound/BusWreck/FuelHouse/DerrickRise, ces vues suivent.
func _piece(data: Dictionary, piece_name: String) -> Dictionary:
	for piece in (data.get("pieces", []) as Array):
		if String((piece as Dictionary).get("name", "")) == piece_name:
			return piece
	return {}


func _piece_pos(data: Dictionary, piece_name: String, fallback: Vector3) -> Vector3:
	var piece := _piece(data, piece_name)
	return piece.get("pos", fallback) if not piece.is_empty() else fallback


func _piece_size(data: Dictionary, piece_name: String, fallback: Vector3) -> Vector3:
	var piece := _piece(data, piece_name)
	return piece.get("size", fallback) if not piece.is_empty() else fallback


## `top_ortho` (sans toits) / `top_ortho_roofs` : mêmes position/cadrage
## (garantit ensemble le critère LD-26 "la carte occupe >= 70 % de la hauteur
## de top_ortho"), seul le plan de coupe proche diffère. Caméra ORTHOGONALE
## droite au-dessus (`up` horizontal, pas de parallélisme avec la direction de
## vue — voir `_apply_pose`) : `keep_aspect = KEEP_HEIGHT` verrouille `size`
## sur la HAUTEUR d'écran, ici l'étendue Z de `bounds` (43 m, la plus petite
## des deux dimensions de Wasteland) — viser 80 % de remplissage garde une
## marge confortable au-dessus du plancher à 70 % mesuré sur l'image réelle.
func _ortho_top_poses(bounds: Dictionary) -> Array:
	var mn: Vector2 = bounds["min"]
	var mx: Vector2 = bounds["max"]
	var cx := (mn.x + mx.x) * 0.5
	var cz := (mn.y + mx.y) * 0.5
	var span_z: float = mx.y - mn.y
	var cam_y := 60.0
	var ortho_size: float = span_z / 0.80
	var pos := Vector3(cx, cam_y, cz)
	var look := Vector3(cx, 0.0, cz)
	var up := Vector3(0, 0, -1)  # nord en haut de l'image
	return [
		{"name": "top_ortho", "pos": pos, "look": look, "up": up, "ortho_size": ortho_size, "near": cam_y - ROOFLESS_CUTOFF_Y},
		{"name": "top_ortho_roofs", "pos": pos, "look": look, "up": up, "ortho_size": ortho_size, "near": 0.05},
	]


## Vue à hauteur d'œil d'une zone Hardpoint : recule de 6 m depuis le point HP
## en s'éloignant du CENTRE de la carte (a de bonnes chances d'être le côté
## "extérieur" de la zone, donc un couloir d'approche plutôt qu'un mur du fond)
## puis avance vers le point HP (raycast-clampé comme toute vue de marche).
func _hp_pose(nm: String, hp_pos: Vector3, center: Vector3) -> Dictionary:
	var out_dir := hp_pos - center
	out_dir.y = 0
	out_dir = out_dir.normalized() if out_dir.length() > 0.01 else Vector3.FORWARD
	var anchor := hp_pos + out_dir * 6.0
	anchor.y = hp_pos.y
	return _walk_pose(nm, anchor, -out_dir, 1.6, 4.0, 20.0, hp_pos.y)


## Wasteland v4 (LD-40/LD-43, docs/research/11_wasteland_v4_layout.md §5 lanes,
## §6 positions fortes, §7 modes, §9 blockout) : les 16 vues imposées (LD-26),
## RECALÉES sur le nouveau blockout (3 lanes, plateau/canyon, PP1-PP5, HP
## P1-P3) — les anciennes ancres (DuneMound, BusWreck, CarPickup, DockCrates,
## FuelHouse, DerrickRise, CraneDeck) n'existent plus dans `WastelandLayout`
## (v4) : `_piece_pos`/`_piece_size` retombaient silencieusement sur leurs
## valeurs de repli codées pour la v3, plantant les caméras "de rue" dans les
## nouveaux bâtiments/toits (constat de tâche LD-43). Les poses de lane/
## position restent calculées depuis la géométrie RÉELLE (`_piece_pos`/
## `_piece_size`, ou `data` elle-même pour spawns/hardpoints/bounds) : si
## `wasteland.gd` bouge encore, ces vues suivent, jamais de coordonnées
## recopiées à la main.
func _wasteland_poses(data: Dictionary) -> Array:
	var sp0: Dictionary = data["spawns"][0][0]
	var sp1: Dictionary = data["spawns"][1][0]
	var team0_spawn: Vector3 = sp0["pos"]
	var team1_spawn: Vector3 = sp1["pos"]
	var bounds: Dictionary = data["bounds"]
	var mn: Vector2 = bounds["min"]
	var mx: Vector2 = bounds["max"]
	var center := Vector3((mn.x + mx.x) * 0.5, 0, (mn.y + mx.y) * 0.5)

	var poses: Array = []
	poses.append_array(_ortho_top_poses(bounds))
	poses.append_array(_aerial_poses(bounds))

	# Spawns (§7 "Départs") : la direction "look" de chaque spawn (`Layouts.
	# _spawn(pos, look)`, 5 m plus loin vers le centre, posée par
	# `_team_spawns()`) est celle qu'un joueur affronte réellement en
	# apparaissant — reprise telle quelle (comme `_poses_for_v2` pour Cargo
	# Ship) plutôt qu'une droite "vers le centre" recalculée à la main.
	# `advance` court (5 m, contre 8 m en v3) : la cour de spawn v4 est bornée
	# à l'est par EchoppesW/E (mur à 7 m du spawn, §9) — un pas plus long
	# nez-au-mur avant même le raycast-clamp.
	var look0: Vector3 = sp0.get("look", team0_spawn)
	var look1: Vector3 = sp1.get("look", team1_spawn)
	poses.append(_walk_pose("spawn_bleu", team0_spawn, look0 - team0_spawn, 1.6, 3.0, 30.0))
	poses.append(_walk_pose("spawn_rouge", team1_spawn, look1 - team1_spawn, 1.6, 3.0, 30.0))

	# Lane ① Grand-Rue (§5, z -19 à -11, "segment droit x -39 à -3") : ancre
	# juste au sud de ForgeW (façade nord-ouest de la rue), qui regarde vers
	# le "coude" central (bloc Poste/Diligence) puis la bouche de place.
	var forge_pos := _piece_pos(data, "ForgeW", Vector3(-32.5, 1.8, -20))
	var forge_size := _piece_size(data, "ForgeW", Vector3(7, 3.6, 10))
	var grand_rue_anchor := Vector3(forge_pos.x - 2.0, 0.0, forge_pos.z + forge_size.z * 0.5 + 1.0)
	poses.append(_walk_pose("grand_rue", grand_rue_anchor, Vector3(1, 0, 0), 1.6, 6.0, 40.0))

	# Lane ② Intérieurs (§5, z -9 à 5) : la Ruelle, "allée nord-sud de 4 m"
	# entre EchoppesW (mur est) et SaloonW (mur ouest) — le seul couloir de
	# cette lane assez étroit pour rester lisible en une image, plutôt qu'une
	# vue de place ouverte qui ne montrerait pas le corridor lui-même.
	var echoppes_pos := _piece_pos(data, "EchoppesW", Vector3(-27, 1.8, -2))
	var echoppes_size := _piece_size(data, "EchoppesW", Vector3(14, 3.6, 14))
	var saloon_pos := _piece_pos(data, "SaloonW", Vector3(-12, 3.2, -3))
	var saloon_size := _piece_size(data, "SaloonW", Vector3(8, 6.4, 16))
	var ruelle_x := ((echoppes_pos.x + echoppes_size.x * 0.5) + (saloon_pos.x - saloon_size.x * 0.5)) * 0.5
	var interieurs_anchor := Vector3(ruelle_x, 0.0, echoppes_pos.z - echoppes_size.z * 0.5 + 1.0)
	poses.append(_walk_pose("interieurs", interieurs_anchor, Vector3(0, 0, 1), 1.6, 5.0, 20.0))

	# Lane ③ Canyon (§5, z 12 à 20, sol -2) : le Gué central (x 0), seul
	# passage large entre RocherGueW/RocherGueE — symétrique par construction,
	# le MÊME point que `LANE_FRONTS["Canyon"]` de test_wasteland.gd.
	poses.append(_walk_pose("canyon", Vector3(0, -2, 16), Vector3(1, 0, 0), 1.6, 2.0, 20.0))

	# 3 zones Hardpoint (§7, P1 -> P2 -> P3, table "Entrées") : `_hp_pose`
	# (recul générique "loin du CENTRE de la carte") place P1/P2 nez contre le
	# toit du Wagon / la falaise nord — les 3 zones v4 sont près du bord de la
	# carte ou serrées entre du décor central, l'hypothèse "centre -> extérieur
	# = couloir d'approche" de `_hp_pose` n'y tient pas. Ancres explicites
	# reprenant les vraies entrées du §7 à la place : P1 depuis l'ouest de la
	# place (porte O du Wagon), P2 depuis la Grand-Rue au sud (portes S du
	# Magasin), P3 depuis l'arrière-cour au nord (chute vers le canyon).
	var hps: Array = data.get("hardpoints", [])
	if hps.size() >= 3:
		var p1: Vector3 = hps[0]
		poses.append(_walk_pose("hp_p1_wagon", p1 + Vector3(-6.0, 0.0, 0.0), Vector3(1, 0, 0), 1.6, 4.0, 20.0))
		var p2: Vector3 = hps[1]
		poses.append(_walk_pose("hp_p2_magasin", p2 + Vector3(0.0, 0.0, 10.0), Vector3(0, 0, -1), 1.6, 2.0, 20.0))
		var p3: Vector3 = hps[2]
		poses.append(_walk_pose("hp_p3_gue", p3 + Vector3(0.0, 1.0, -9.0), Vector3(0, 0, 1), 1.6, 2.0, 20.0))

	# 4ᵉ position forte (§6, hors zones HP) : la galerie du Saloon ouest (PP3,
	# `BalconW`, dalle extérieure à 3,2 m côté place) — "vue 37 m : place,
	# bouche de la Grand-Rue est". Choisie plutôt que l'intérieur de l'Hôtel
	# (PP1) : `BalconW` est une dalle EXTÉRIEURE déjà validée par la navmesh
	# réelle (`test_pp1_to_pp4_have_at_least_three_navmesh_accesses`), donc
	# une pose sûre par construction — jamais de risque de caméra coincée
	# dans une cage d'escalier intérieure non cartographiée ici.
	var balcon_pos := _piece_pos(data, "BalconW", Vector3(-7, 3.075, -5))
	var balcon_size := _piece_size(data, "BalconW", Vector3(2, 0.25, 8))
	var pp3_anchor := Vector3(balcon_pos.x, balcon_pos.y + balcon_size.y * 0.5, balcon_pos.z)
	poses.append(_walk_pose("pp3_galerie", pp3_anchor, Vector3(1, 0, 0.3), 1.6, 2.0, 35.0, 0.0))

	# Ligne longue (§8/R7, en hauteur uniquement) : depuis le château d'eau
	# (12 m, "repère visible de partout"), en diagonale vers le secteur
	# ForgeE/Banque à l'est — sur toute la carte, comme l'ancienne "toit FUEL
	# -> butte" v3.
	var chateau_pos := _piece_pos(data, "ChateauCuve", Vector3(0, 10, 5.5))
	var chateau_top := Vector3(chateau_pos.x, 16.0, chateau_pos.z)
	var far_target := Vector3(mx.x - 8.0, 3.2, mn.y + 4.0)
	poses.append(_walk_pose("ligne_longue", chateau_top, far_target - chateau_top, 0.0, 4.0, 55.0))

	return poses


func _poses_for(map_id: String) -> Array:
	# Nettoyage du prototype 2026-09-26 : les six maps v1 (`Layouts.gd`) et
	# Cargo Ship ont été supprimées avec leurs scènes — Wasteland est
	# désormais la seule carte (voir MapCatalog.gd).
	if map_id == "wasteland":
		return _wasteland_poses(WastelandLayout.data())
	return [{"name": "top", "pos": Vector3(0, 40, 0), "look": Vector3(0, 0, 0.001)}]


## `pose["ortho_size"]` (présent seulement pour `top_ortho`/`top_ortho_roofs`,
## cf. `_ortho_top_poses`) bascule la caméra en projection ORTHOGONALE, avec
## `pose["near"]` comme plan de coupe proche — c'est ce plan, pour une caméra
## droite au-dessus, qui coupe la scène PAR HAUTEUR (ROOFLESS_CUTOFF_Y) sans
## affecter les autres vues (perspective, plan par défaut 0,05 restauré).
## `pose["up"]` (par défaut Vector3.UP) : vecteur "haut d'écran" explicite,
## nécessaire pour `top_ortho*` (vue droit au-dessus, où l'UP par défaut est
## parallèle à la direction de vue et ferait échouer `look_at`).
func _apply_pose(pose: Dictionary) -> void:
	_cam.global_position = pose["pos"]
	_cam.look_at(pose["look"], pose.get("up", Vector3.UP))
	if pose.has("ortho_size"):
		_cam.keep_aspect = Camera3D.KEEP_HEIGHT
		_cam.set_orthogonal(float(pose["ortho_size"]), float(pose.get("near", 0.05)), 4000.0)
	else:
		_cam.set_perspective(75.0, 0.05, 4000.0)
	_cam.current = true


func _ensure_ink_post() -> void:
	if _cam and _cam.get_node_or_null("InkPost") == null:
		var post := _INK_POST_SCRIPT.new()
		post.name = "InkPost"
		_cam.add_child(post)


## Capture la vue courante, l'écrit sur disque, puis mesure la garde
## anti-caméra-dans-la-géométrie. Renvoie `true` si la vue doit être reprise
## (teinte dominante > `HUE_FAIL_RATIO` ET correction possible ET tentatives
## restantes) — l'appelant (`_process`) recule/surélève alors la caméra
## (`_correct_current_pose`) et relance une capture sur la MÊME pose, sans
## avancer `_pose_index`. `MAP_SHOT` est imprimé à CHAQUE tentative (y compris
## celles qui seront reprises) : la dernière écriture pour ce nom de vue est
## toujours celle qui reste sur disque.
func _capture_current_pose() -> bool:
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
		return false
	print("MAP_SHOT ", entry["id"], " ", pose["name"], " ", out_path)
	var hue_ratio := _dominant_hue_ratio(img)
	if hue_ratio <= HUE_FAIL_RATIO:
		return false
	# Une seule teinte > 60 % a DEUX causes très différentes, distinguées ici
	# par une requête physique au POINT EXACT de la caméra (ground truth, ne
	# dépend pas du contenu) plutôt que par le ratio de teinte seul (mesuré
	# empiriquement trop grossier pour trancher, cf. rapport LD-26) :
	#  1) la caméra est DANS un solide (L10) — `_camera_embedded_in_solid`
	#     répond `true` — corrigeable en reculant/surélevant (ci-dessous) ;
	#  2) le plan est juste PAUVRE en décor à cette distance (sol/façade
	#     uniforme, ciel qui domine) — `false` — aucune position de caméra
	#     ne changera la densité de décor de la carte : retenter ne fait
	#     qu'ÉLOIGNER la caméra (vérifié : `aerial_*` passe de 0,71 à 0,82
	#     après 3 tentatives) sans rien résoudre. Signalé pour la vague ART
	#     (hors de mon périmètre `tools/map_shots.gd`), jamais retenté.
	# `_camera_embedded_in_solid` seule rate le "nez COLLÉ à un mur, sans le
	# chevaucher" (vérifié en image, wasteland_hp_c.png/route_nord.png : rouge/
	# roche plein cadre à ~1,00/0,97, alors que `_raycast_clamp` s'arrête
	# volontairement 0,4 m AVANT tout solide — jamais littéralement dedans) :
	# `_camera_blocked_at_close_range` complète avec un lancer de rayon COURT
	# droit devant la caméra.
	var embedded := _camera_embedded_in_solid() or _camera_blocked_at_close_range()
	var correctable := embedded and _cam.projection != Camera3D.PROJECTION_ORTHOGONAL
	var will_retry := correctable and _pose_retry < MAX_POSE_RETRIES
	var cause := "camera_dans_geometrie" if embedded else "decor_clairseme_hors_perimetre"
	print("MAP_SHOT_HUE_WARN ", entry["id"], " ", pose["name"],
		" ratio=%.2f" % hue_ratio, " cause=", cause,
		" retry=", _pose_retry, "/", MAX_POSE_RETRIES,
		" action=", ("retry" if will_retry else "keep"))
	return will_retry


## Ground truth de la garde "aucune caméra dans la géométrie" (LD-26) :
## requête physique ponctuelle exactement à `_cam.global_position` — répond
## sans ambiguïté, contrairement au ratio de teinte (confondu par un décor
## clairsemé légitime, cf. `_capture_current_pose`).
func _camera_embedded_in_solid() -> bool:
	var world := root.get_world_3d()
	if world == null:
		return false
	var space := world.direct_space_state
	if space == null:
		return false
	var params := PhysicsPointQueryParameters3D.new()
	params.position = _cam.global_position
	params.collide_with_areas = false
	params.collide_with_bodies = true
	return not space.intersect_point(params, 1).is_empty()


## Second signal de la même garde : un lancer de rayon COURT droit devant la
## caméra (`-Z` local, la direction de vue de tout `Camera3D`) — attrape le
## "nez collé à un mur SANS le chevaucher", que `_raycast_clamp` produit par
## construction (arrêt `margin` = 0,4 m avant tout solide, jamais dedans).
func _camera_blocked_at_close_range(margin: float = 1.0) -> bool:
	var world := root.get_world_3d()
	if world == null:
		return false
	var space := world.direct_space_state
	if space == null:
		return false
	var origin := _cam.global_position
	var fwd := -_cam.global_transform.basis.z
	var params := PhysicsRayQueryParameters3D.create(origin, origin + fwd * margin)
	params.collide_with_areas = false
	params.collide_with_bodies = true
	return not space.intersect_ray(params).is_empty()


## Correction générique (LD-26, garde anti-caméra-dans-la-géométrie, cf. L10) :
## la cause la plus fréquente d'une vue quasi monochrome est une ANCRE déjà À
## L'INTÉRIEUR d'un solide, où `_raycast_clamp` ne détecte rien (un lancer de
## rayon qui PART d'un point déjà occupé n'enregistre pas de collision à son
## origine). Reculer sur l'axe caméra->cible tout en montant en Y augmente à
## chaque tentative les chances de ressortir de la géométrie sans changer
## l'intention de la vue (même cible visée).
func _correct_current_pose() -> void:
	var pose: Dictionary = _poses[_pose_index]
	var away: Vector3 = pose["pos"] - pose["look"]
	if away.length() < 0.01:
		away = Vector3.UP
	away = away.normalized()
	var step := 2.0 * float(_pose_retry)
	pose["pos"] = (pose["pos"] as Vector3) + away * step + Vector3(0, step, 0)
	_poses[_pose_index] = pose
	_apply_pose(pose)


## Fraction de pixels échantillonnés appartenant à la teinte (bac HSV) la plus
## représentée, regroupée par fenêtre glissante de `HUE_WINDOW` bacs pour ne
## pas sous-compter une même surface peinte étalée par l'éclairage sur 2-3
## bacs adjacents. Les pixels quasi gris (`s < HUE_MIN_SATURATION` — vide/
## ciel neutre, UI résiduelle) sont exclus : ils n'ont pas de "teinte" au sens
## de l'acceptance ("aucune vue ne contient plus de 60 % de pixels d'une seule
## teinte"). Échantillonnage tous les `HUE_SAMPLE_STEP` pixels (perf : 16
## vues * jusqu'à `MAX_POSE_RETRIES` reprises doit tenir dans le budget de
## `Step-MapShots` en CI, 180 s pour TOUTES les cartes).
func _dominant_hue_ratio(img: Image) -> float:
	var w := img.get_width()
	var h := img.get_height()
	var bins := PackedInt32Array()
	bins.resize(HUE_BINS)
	var total := 0
	var y := 0
	while y < h:
		var x := 0
		while x < w:
			var c := img.get_pixel(x, y)
			if c.s >= HUE_MIN_SATURATION:
				var b := int(c.h * HUE_BINS) % HUE_BINS
				bins[b] += 1
				total += 1
			x += HUE_SAMPLE_STEP
		y += HUE_SAMPLE_STEP
	if total == 0:
		return 0.0
	var best := 0
	for i in HUE_BINS:
		var sum := 0
		for k in HUE_WINDOW:
			sum += bins[(i + k) % HUE_BINS]
		best = maxi(best, sum)
	return float(best) / float(total)


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
