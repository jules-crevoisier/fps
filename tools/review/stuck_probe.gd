## stuck_probe.gd
## LD-45 — sonde de blocage joueur (Wasteland v4, docs/research/
## 11_wasteland_v4_layout.md). Retour de playtest utilisateur 2026-09-25 :
## « certains espaces pas bien définis, on peut rester bloqué ».
##
## Une capsule joueur RÉELLE (le vrai `scenes/player/player.tscn` : même
## `CapsuleShape3D` 0.4 x 1.8 m, même `PlayerController` — gravité, friction
## sol, `StairStep.try_step_up/try_step_down` (§ART-71, "arêtes de 5-30 cm"),
## `floor_max_angle` 52°, exactement le corps qui joue en vrai — voir la note
## d'en-tête de `tools/review/gameplay_probe.gd` pour la technique de
## pilotage headless : le joueur hôte bascule en `is_bot = true` juste après
## le spawn, puis on écrit nous-mêmes `player.input.move`/`rotation.y`, comme
## le ferait `BotBrain.gd`) parcourt en HEADLESS des centaines de trajets
## réels entre paires de points de la navmesh de Wasteland, couvrant les 3
## couloirs (Grand-Rue, Intérieurs, Canyon) et les escaliers (les 8 volées
## extérieures + les 4 rampes intérieures des bâtiments à étage).
##
## Détection de blocage (contrat de tâche, littéral) : la vitesse (distance
## 3D parcourue / temps, même convention que `scripts/ai/BotStuck.gd`) tombe
## sous 0,5 m/s pendant plus de 0,75 s alors qu'on pousse continûment vers la
## cible (`player.input.move = Vector2(0,-1)`, jamais relâché, jamais de
## saut : on veut mesurer le blocage MARCHÉ, pas ce qu'un saut pourrait
## contourner). Une seule marque par épisode de blocage continu (pas une par
## tick) — voir `_StuckWindow` ci-dessous.
##
## Usage (le `--fixed-fps 60` est OBLIGATOIRE, pas cosmétique : sans lui, la
## boucle principale de Godot se cale sur l'horloge RÉELLE, environ 1 s réelle
## par seconde simulée — un plein passage (>= 500 trajets) prendrait alors
## des heures ; avec `--fixed-fps 60` la simulation tourne aussi vite que le
## CPU le permet, MÊME granularité physique que d'habitude (60 Hz, celle de
## `Engine.physics_ticks_per_second`, jamais changée) donc AUCUNE perte de
## précision de collision. Mesuré : 12 trajets courts en 10,9 s réelles avec
## `--fixed-fps 60`, contre >90 s sans l'option — voir aussi
## `docs/COLLISION_LAYERS.md`/`tests/maps/*.gd` pour la même contrainte
## d'attente physique (`await get_tree().physics_frame`) ; un `--fixed-fps`
## plus haut que 60 est PLUS LENT (plus de petits pas = plus de surcoût par
## tick, mesuré), jamais plus rapide : NE PAS l'augmenter en pensant accélérer) :
##   godot --headless --fixed-fps 60 --path . -s res://tools/review/stuck_probe.gd -- --out=DIR
##     [--map=wasteland] [--per_bucket=20] [--min_trajectories=500] [--time_budget=2400]
##
## Écrit dans `<out>/` : `stuck_probe.json` (résultat complet : trajets,
## grappes de blocage, résumé par couloir), `map.jpg` (vue de dessus, pièces
## + grappes) et `clusters/cluster_NNN.jpg` (un gros plan par grappe,
## §"1 capture par grappe" du contrat). Imprime un résumé puis quitte 0 si le
## parcours s'est terminé (le verdict "carte jouable" se lit dans le JSON/les
## captures, pas dans le code de sortie — sonde de diagnostic, comme
## `tools/map_shots.gd`, pas une passe/échoue automatique).
extends SceneTree

const MAP_ID_DEFAULT := "wasteland"
const DEFAULT_OUT := "res://reports/stuck_probe/latest"

## §BotStuck.gd (même seuil, fenêtre différente — 0,75 s ici, littéral du
## contrat, contre 1,0 s pour l'anti-blocage de jeu) : vitesse en dessous de
## laquelle on juge qu'"on n'avance plus".
const STUCK_SPEED_THRESHOLD := 0.5
const STUCK_WINDOW_S := 0.75

## Rayon (m, XZ) sous lequel on considère un coin de chemin "atteint" et on
## vise le suivant — assez large pour ne jamais osciller sur un coin de
## funnel Recast tout proche d'un mur, assez court pour ne pas couper les
## virages serrés des escaliers/ruelles (2 m de large, §5 du doc).
const CORNER_ARRIVE_RADIUS := 1.0
const FINAL_ARRIVE_RADIUS := 1.4

## Rayon (m) de fusion des points de blocage en une seule "grappe" — assez
## large pour regrouper les points d'un même défaut de géométrie (arête,
## poteau, coin) mesurés par plusieurs trajets différents qui le traversent,
## assez court pour ne jamais fusionner deux positions fortes voisines.
const CLUSTER_RADIUS := 2.5

## Grille brute (m) avant filtrage par la navmesh RÉELLE (`_snap` ci-dessous) —
## volontairement plus fine que la cible finale par couloir : la plupart des
## points tombent dans un bâtiment/un rocher et sont éliminés par le filtre
## de distance de snap, jamais comptés.
const GRID_STEP := 2.5
## Un point de grille est gardé seulement si son point navmesh le plus proche
## est à moins de cette distance HORIZONTALE (m) — même tolérance que
## `tests/maps/test_wasteland_markers.gd::test_tdm_and_team_spawns_are_on_the_navmesh`.
const SNAP_TOLERANCE := 1.0

## Bornes des 3 couloirs (docs/research/11_wasteland_v4_layout.md §5) — z
## croît vers le sud (canyon), décroît vers le nord (Grand-Rue). "Intérieurs"
## inclut l'arrière-cour (§5, transition ②->③).
const LANE_BOUNDS := {
	"grand_rue": {"z0": -19.0, "z1": -11.0, "y": 1.0},
	"interieurs": {"z0": -9.0, "z1": 12.0, "y": 1.0},
	"canyon": {"z0": 12.0, "z1": 20.0, "y": -1.0},
}
const MAP_X0 := -43.0
const MAP_X1 := 43.0

var _out_dir: String = DEFAULT_OUT
var _map_id: String = MAP_ID_DEFAULT
var _per_bucket: int = 20
var _min_trajectories: int = 500
var _time_budget_s: float = 900.0

var _t0_msec: int = 0
var _started: bool = false
var _world: Node = null
var _player: PlayerController = null
var _map_rid: RID

var _trajectories: Array = []   ## {"id","category","from","to","completed","stuck_events":[{pos,duration}],"path_len_m","seconds"}
var _all_stuck: Array = []      ## {"pos":Vector3,"category":String,"trajectory_id":int,"duration_s":float}


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out_dir = a.get_slice("=", 1)
		elif a.begins_with("--map="):
			_map_id = a.get_slice("=", 1)
		elif a.begins_with("--per_bucket="):
			_per_bucket = int(a.get_slice("=", 1))
		elif a.begins_with("--min_trajectories="):
			_min_trajectories = int(a.get_slice("=", 1))
		elif a.begins_with("--time_budget="):
			_time_budget_s = float(a.get_slice("=", 1))


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_t0_msec = Time.get_ticks_msec()
		_run()
		return false
	return false


func _budget_left() -> bool:
	return (Time.get_ticks_msec() - _t0_msec) / 1000.0 < _time_budget_s


# ==========================================================================
#  ORCHESTRATION
# ==========================================================================
func _run() -> void:
	var entry := _catalog_entry(_map_id)
	if entry.is_empty():
		push_error("stuck_probe : map \"%s\" introuvable dans MapCatalog" % _map_id)
		quit(1)
		return
	await _boot_map(entry)
	if _player == null:
		push_error("stuck_probe : le joueur hôte n'a jamais spawné sur \"%s\"" % _map_id)
		quit(1)
		return

	var buckets := _build_waypoint_buckets()
	var pairs := _build_trajectory_pairs(buckets)
	print("STUCK_PROBE trajets=%d (cible >= %d) couverture=%s" % [
		pairs.size(), _min_trajectories,
		JSON.stringify({"grand_rue": buckets.get("grand_rue", []).size(), "interieurs": buckets.get("interieurs", []).size(),
			"canyon": buckets.get("canyon", []).size(), "escaliers": buckets.get("escaliers", []).size()}),
	])

	var tid := 0
	var skipped := 0
	for pair in pairs:
		if not _budget_left():
			skipped += 1
			continue
		await _run_trajectory(tid, pair)
		tid += 1
		if tid % 25 == 0:
			var elapsed_s := (Time.get_ticks_msec() - _t0_msec) / 1000.0
			print("STUCK_PROBE progres %d/%d trajets (%.0f s ecoulees, %d points de blocage jusqu'ici)" % [tid, pairs.size(), elapsed_s, _all_stuck.size()])

	var clusters := _cluster_stuck_points(_all_stuck)
	_report(clusters, skipped)

	if _world and is_instance_valid(_world):
		_world.free()
	quit(0)


func _catalog_entry(id: String) -> Dictionary:
	for m in MapCatalog.all():
		if String((m as Dictionary).get("id", "")) == id:
			return m as Dictionary
	return {}


# ==========================================================================
#  BOOT — carte réelle, un seul joueur (l'hôte), pas de bot (même patron que
#  gameplay_probe.gd::_check_spawn_on_map, voir sa note d'en-tête pour le
#  détail du pilotage `is_bot = true`).
# ==========================================================================
func _boot_map(entry: Dictionary) -> void:
	MatchConfig.set_mode(String((entry["modes"] as Array)[0]) if not (entry["modes"] as Array).is_empty() else "tdm")
	MatchConfig.map_id = String(entry["id"])
	MatchConfig.bots_enabled = false
	MatchConfig.team_size = 1
	var packed := load(String(entry["scene"])) as PackedScene
	if packed == null:
		return
	_world = packed.instantiate()
	if _world.get("agent_select") != null:
		_world.set("agent_select", false)
	if _world.get("allow_bot_fill") != null:
		_world.set("allow_bot_fill", false)
	root.add_child(_world)
	current_scene = _world
	_player = await _wait_for_local_player(10.0)
	if _player == null:
		return
	_player.is_bot = true
	_player.movement_locked = false
	var nav := get_first_node_in_group("nav_region") as NavigationRegion3D
	if nav:
		_map_rid = nav.get_navigation_map()
	# Amorce la synchro serveur de navigation (comme tests/maps/*.gd) avant
	# le premier vrai `map_get_path`.
	await _wait_path(_player.global_position, _player.global_position + Vector3(1, 0, 0))


func _wait_for_local_player(timeout: float) -> PlayerController:
	var t := 0.0
	while t < timeout:
		for n in get_nodes_in_group("local_player"):
			if is_instance_valid(n) and not (n as Node).is_queued_for_deletion():
				return n as PlayerController
		await physics_frame
		t += 1.0 / 60.0
	return null


func _wait_path(from: Vector3, to: Vector3) -> PackedVector3Array:
	var path: PackedVector3Array = []
	for i in 40:
		path = NavigationServer3D.map_get_path(_map_rid, from, to, true)
		if path.size() >= 2:
			return path
		await physics_frame
	return path


# ==========================================================================
#  POINTS DE PASSAGE — grille filtrée par la navmesh réelle (3 couloirs) +
#  points explicites sur les 8 volées d'escalier extérieures et les 4 rampes
#  intérieures (Hotel/Banque/SaloonW/SaloonE).
# ==========================================================================
func _snap(query: Vector3) -> Variant:
	var snapped := NavigationServer3D.map_get_closest_point(_map_rid, query)
	var flat := Vector2(snapped.x - query.x, snapped.z - query.z).length()
	if flat > SNAP_TOLERANCE:
		return null
	return snapped


func _build_waypoint_buckets() -> Dictionary:
	var out := {"grand_rue": [], "interieurs": [], "canyon": [], "escaliers": []}

	for lane in LANE_BOUNDS.keys():
		var b: Dictionary = LANE_BOUNDS[lane]
		var pts: Array = []
		var x := MAP_X0
		while x <= MAP_X1:
			var z: float = b["z0"]
			while z <= b["z1"]:
				var snapped: Variant = _snap(Vector3(x, b["y"], z))
				if snapped != null:
					pts.append(snapped)
				z += GRID_STEP
			x += GRID_STEP
		out[lane] = _subsample(pts, _per_bucket)

	var stair_pts: Array = []
	var pieces: Array = WastelandLayout.data()["pieces"]
	for p in pieces:
		var d: Dictionary = p
		if String(d.get("type", "")) == "stairs":
			var s: Vector3 = d["start"]
			var e: Vector3 = d["end"]
			for t in [0.15, 0.35, 0.5, 0.65, 0.85]:
				var snapped: Variant = _snap(s.lerp(e, t))
				if snapped != null:
					stair_pts.append(snapped)
		elif String(d.get("type", "")) == "building2" and int(d.get("floors", 1)) >= 2:
			for ramp_pt in _building_ramp_points(d):
				var snapped2: Variant = _snap(ramp_pt)
				if snapped2 != null:
					stair_pts.append(snapped2)
	out["escaliers"] = _subsample(stair_pts, _per_bucket)
	return out


## Points ground/gallery approximatifs près de la rampe intérieure d'un
## `building2` à 2 étages, déduits de `stair_side` (§9 du doc, `_bld_ramp_
## endpoints`/`_bld_ramp_span` de Kit.gd restent privés — approximation
## volontairement large, corrigée par `_snap` sur la vraie navmesh).
func _building_ramp_points(piece: Dictionary) -> Array:
	var pos: Vector3 = piece["pos"]
	var size: Vector3 = piece["size"]
	var side := String(piece.get("stair_side", "N"))
	var ground: Vector3
	var gallery: Vector3
	match side:
		"S":
			ground = Vector3(pos.x, 1.0, pos.z + size.z * 0.5 - 1.0)
			gallery = Vector3(pos.x, pos.y, pos.z + size.z * 0.5 - 3.0)
		"E":
			ground = Vector3(pos.x + size.x * 0.5 - 1.0, 1.0, pos.z)
			gallery = Vector3(pos.x + size.x * 0.5 - 3.0, pos.y, pos.z)
		"W":
			ground = Vector3(pos.x - size.x * 0.5 + 1.0, 1.0, pos.z)
			gallery = Vector3(pos.x - size.x * 0.5 + 3.0, pos.y, pos.z)
		_:
			ground = Vector3(pos.x, 1.0, pos.z - size.z * 0.5 + 1.0)
			gallery = Vector3(pos.x, pos.y, pos.z - size.z * 0.5 + 3.0)
	return [ground, gallery]


## Sous-échantillonnage déterministe (pas d'aléatoire : deux lancers sur la
## même carte donnent EXACTEMENT les mêmes trajets, condition nécessaire pour
## comparer un "avant/avant" — la comparaison "avant/après" du contrat porte
## sur la géométrie, pas sur le tirage) — foulée régulière dans la liste
## triée par (x, z), qui garde une bonne répartition spatiale.
func _subsample(pts: Array, target: int) -> Array:
	if pts.size() <= target:
		return pts
	var sorted_pts: Array = pts.duplicate()
	sorted_pts.sort_custom(func(a, b):
		var av: Vector3 = a
		var bv: Vector3 = b
		if not is_equal_approx(av.x, bv.x):
			return av.x < bv.x
		return av.z < bv.z)
	var out: Array = []
	var stride := float(sorted_pts.size()) / float(target)
	var i := 0.0
	while out.size() < target:
		out.append(sorted_pts[int(i)])
		i += stride
	return out


## Paires (i<j) au sein de chaque couloir, direction alternée (i->j / j->i
## selon la parité) pour un peu de diversité d'approche sans doubler le
## nombre de trajets.
func _build_trajectory_pairs(buckets: Dictionary) -> Array:
	var out: Array = []
	for category in buckets.keys():
		var pts: Array = buckets[category]
		for i in pts.size():
			for j in range(i + 1, pts.size()):
				var a: Vector3 = pts[i]
				var b: Vector3 = pts[j]
				if (i + j) % 2 == 0:
					out.append({"category": category, "from": a, "to": b})
				else:
					out.append({"category": category, "from": b, "to": a})
	return out


# ==========================================================================
#  UN TRAJET — capsule joueur réelle poussée en continu vers la cible.
# ==========================================================================
func _reset_player_at(pos: Vector3) -> void:
	_player.input.clear()
	_player.velocity = Vector3.ZERO
	_player.global_position = pos
	_player.rotation = Vector3.ZERO
	_player.reset_physics_interpolation()
	var t := 0
	while t < 60 and not _player.is_on_floor():
		await physics_frame
		t += 1


## Yaw (rad) tel que le "-Z" local de `body` (avant, convention Godot) pointe
## vers `dir` (composante Y ignorée) — même formule que `Node3D.look_at` pour
## un yaw pur, sans dépendre de la caméra.
static func _yaw_to(dir: Vector3) -> float:
	return atan2(-dir.x, -dir.z)


func _run_trajectory(tid: int, pair: Dictionary) -> void:
	var category := String(pair["category"])
	var from_pos: Vector3 = pair["from"]
	var to_pos: Vector3 = pair["to"]
	var path := await _wait_path(from_pos, to_pos)
	if path.size() < 2:
		_trajectories.append({"id": tid, "category": category, "from": from_pos, "to": to_pos, "completed": false, "path_len_m": 0.0, "seconds": 0.0, "stuck_events": 0, "note": "aucun chemin navmesh"})
		return
	var path_len := 0.0
	for i in range(1, path.size()):
		path_len += path[i - 1].distance_to(path[i])

	await _reset_player_at(from_pos)
	_player.input.walk_held = false
	_player.input.crouch_held = false
	_player.input.crouch_pressed = false
	_player.input.jump_pressed = false
	_player.input.jump_held = false
	_player.input.move = Vector2(0, -1)

	var corner_idx := 1
	var final_target: Vector3 = path[path.size() - 1]

	# Fenêtre glissante de vitesse (même technique que BotStuck._update_speed_
	# window, fenêtre 0,75 s littérale du contrat) — voir la note d'en-tête.
	var window: Array = []   ## {"dt","dist"}
	var window_time := 0.0
	var window_dist := 0.0
	var stalled := false
	var stall_started_pos := Vector3.ZERO
	var stall_elapsed := 0.0
	var stuck_events: Array = []

	var max_seconds: float = maxf(path_len / 4.0, 6.0) * 2.5 + 4.0
	var elapsed := 0.0
	var delta := 1.0 / 60.0
	var completed := false

	while elapsed < max_seconds:
		var here := _player.global_position
		var target_corner: Vector3 = path[corner_idx]
		var flat_to_corner := Vector2(target_corner.x - here.x, target_corner.z - here.z).length()
		if corner_idx < path.size() - 1 and flat_to_corner < CORNER_ARRIVE_RADIUS:
			corner_idx += 1
			target_corner = path[corner_idx]
		var flat_to_final := Vector2(final_target.x - here.x, final_target.z - here.z).length()
		if corner_idx >= path.size() - 1 and flat_to_final < FINAL_ARRIVE_RADIUS:
			completed = true
			break

		var dir := (target_corner - here)
		dir.y = 0.0
		if dir.length() > 0.01:
			_player.rotation.y = _yaw_to(dir.normalized())

		await physics_frame
		elapsed += delta

		var now := _player.global_position
		var dist := here.distance_to(now)
		window.append({"dt": delta, "dist": dist})
		window_time += delta
		window_dist += dist
		while window.size() > 1 and (window_time - float(window[0]["dt"])) >= STUCK_WINDOW_S:
			var oldest: Dictionary = window.pop_front()
			window_time -= float(oldest["dt"])
			window_dist -= float(oldest["dist"])

		if window_time >= STUCK_WINDOW_S:
			var avg_speed := window_dist / window_time
			if avg_speed < STUCK_SPEED_THRESHOLD:
				if not stalled:
					stalled = true
					stall_started_pos = now
					stall_elapsed = window_time
				else:
					stall_elapsed += delta
			else:
				if stalled:
					stuck_events.append({"pos": stall_started_pos, "duration_s": stall_elapsed})
					_all_stuck.append({"pos": stall_started_pos, "category": category, "trajectory_id": tid, "duration_s": stall_elapsed})
				stalled = false
				stall_elapsed = 0.0

	if stalled:
		stuck_events.append({"pos": stall_started_pos, "duration_s": stall_elapsed})
		_all_stuck.append({"pos": stall_started_pos, "category": category, "trajectory_id": tid, "duration_s": stall_elapsed})

	_trajectories.append({
		"id": tid, "category": category, "from": from_pos, "to": to_pos, "completed": completed,
		"path_len_m": path_len, "seconds": elapsed, "stuck_events": stuck_events.size(),
		"max_stall_s": (stuck_events.map(func(e): return float(e["duration_s"])).max() if not stuck_events.is_empty() else 0.0),
	})


# ==========================================================================
#  GRAPPES — fusion des points de blocage à moins de CLUSTER_RADIUS.
# ==========================================================================
func _cluster_stuck_points(events: Array) -> Array:
	var clusters: Array = []
	for entry in events:
		var e: Dictionary = entry
		var pos: Vector3 = e["pos"]
		var found: Dictionary = {}
		for c in clusters:
			var cd: Dictionary = c
			if (cd["pos"] as Vector3).distance_to(pos) <= CLUSTER_RADIUS:
				found = cd
				break
		if found.is_empty():
			found = {"pos": pos, "count": 0, "max_stall_s": 0.0, "categories": {}, "trajectory_ids": []}
			clusters.append(found)
		var n: int = found["count"]
		var new_pos: Vector3 = ((found["pos"] as Vector3) * float(n) + pos) / float(n + 1)
		found["pos"] = new_pos
		found["count"] = n + 1
		found["max_stall_s"] = maxf(float(found["max_stall_s"]), float(e["duration_s"]))
		(found["categories"] as Dictionary)[String(e["category"])] = true
		(found["trajectory_ids"] as Array).append(int(e["trajectory_id"]))
	for i in clusters.size():
		clusters[i]["id"] = i
	return clusters


# ==========================================================================
#  RAPPORT — JSON + carte vue de dessus + un gros plan par grappe.
# ==========================================================================
func _report(clusters: Array, skipped: int) -> void:
	var by_lane_count := {"grand_rue": 0, "interieurs": 0, "canyon": 0, "escaliers": 0}
	for c in clusters:
		for cat in (c["categories"] as Dictionary).keys():
			if by_lane_count.has(cat):
				by_lane_count[cat] = int(by_lane_count[cat]) + 1

	var main_lanes_clusters := int(by_lane_count["grand_rue"]) + int(by_lane_count["interieurs"]) + int(by_lane_count["canyon"])

	var out := {
		"map_id": _map_id,
		"capsule": {"radius": 0.4, "height": 1.8},
		"thresholds": {"stuck_speed_mps": STUCK_SPEED_THRESHOLD, "stuck_window_s": STUCK_WINDOW_S, "cluster_radius_m": CLUSTER_RADIUS},
		"trajectories_run": _trajectories.size(),
		"trajectories_skipped_time_budget": skipped,
		"trajectories": _trajectories,
		"stuck_clusters": clusters,
		"summary": {
			"stuck_clusters_total": clusters.size(),
			"stuck_clusters_by_category": by_lane_count,
			"stuck_clusters_in_3_main_lanes": main_lanes_clusters,
			"stuck_events_total": _all_stuck.size(),
		},
	}
	_write_json(_out_dir.path_join("stuck_probe.json"), out)
	_draw_map(clusters)
	for c in clusters:
		_draw_cluster(c)

	print("STUCK_PROBE termine map=%s trajets=%d/%d(sautes) grappes=%d (3 couloirs=%d) evenements=%d" % [
		_map_id, _trajectories.size(), skipped, clusters.size(), main_lanes_clusters, _all_stuck.size(),
	])


func _write_json(path: String, data: Dictionary) -> void:
	var abs_path := ProjectSettings.globalize_path(path) if path.begins_with("res://") else path
	var dir := abs_path.get_base_dir()
	if dir != "" and not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(abs_path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "\t"))
		f.close()
	else:
		print("STUCK_PROBE_WARN impossible d'ecrire ", abs_path)


# ---- Rendu 2D vue de dessus, purement CPU (Image), sans display server ----
const IMG_W := 1400
const IMG_H := 720
const MAP_MIN := Vector2(-44.0, -25.0)
const MAP_MAX := Vector2(44.0, 20.0)

static func _to_px(p: Vector2) -> Vector2:
	var scale_x := float(IMG_W) / (MAP_MAX.x - MAP_MIN.x)
	var scale_y := float(IMG_H) / (MAP_MAX.y - MAP_MIN.y)
	var s := minf(scale_x, scale_y)
	var ox := (float(IMG_W) - (MAP_MAX.x - MAP_MIN.x) * s) * 0.5
	var oy := (float(IMG_H) - (MAP_MAX.y - MAP_MIN.y) * s) * 0.5
	return Vector2(ox + (p.x - MAP_MIN.x) * s, oy + (p.y - MAP_MIN.y) * s)

static func _piece_color(piece: Dictionary) -> Color:
	match String(piece.get("type", "")):
		"building2":
			return Color(0.55, 0.5, 0.45)
		"stairs":
			return Color(0.85, 0.65, 0.25)
		"ramp":
			return Color(0.7, 0.55, 0.35)
		"fence", "invisible_wall":
			return Color(0.4, 0.4, 0.45)
		_:
			match String(piece.get("color_key", "")):
				"rock":
					return Color(0.5, 0.35, 0.3)
				"solid":
					return Color(0.6, 0.45, 0.3)
				_:
					return Color(0.45, 0.42, 0.4)

func _fill_rect_clamped(img: Image, x0: int, y0: int, x1: int, y1: int, color: Color) -> void:
	var rx0 := clampi(mini(x0, x1), 0, IMG_W - 1)
	var rx1 := clampi(maxi(x0, x1), 0, IMG_W - 1)
	var ry0 := clampi(mini(y0, y1), 0, IMG_H - 1)
	var ry1 := clampi(maxi(y0, y1), 0, IMG_H - 1)
	if rx1 < rx0 or ry1 < ry0:
		return
	img.fill_rect(Rect2i(rx0, ry0, rx1 - rx0 + 1, ry1 - ry0 + 1), color)

func _fill_circle(img: Image, center: Vector2, radius: float, color: Color) -> void:
	var x0 := int(center.x - radius)
	var x1 := int(center.x + radius)
	var y0 := int(center.y - radius)
	var y1 := int(center.y + radius)
	for y in range(maxi(y0, 0), mini(y1, IMG_H - 1) + 1):
		for x in range(maxi(x0, 0), mini(x1, IMG_W - 1) + 1):
			if Vector2(x, y).distance_to(center) <= radius:
				img.set_pixel(x, y, color)

func _base_map_image() -> Image:
	var img := Image.create(IMG_W, IMG_H, false, Image.FORMAT_RGB8)
	img.fill(Color(0.12, 0.11, 0.1))
	for lane in LANE_BOUNDS.keys():
		var b: Dictionary = LANE_BOUNDS[lane]
		var p0 := _to_px(Vector2(MAP_MIN.x, b["z0"]))
		var p1 := _to_px(Vector2(MAP_MAX.x, b["z1"]))
		_fill_rect_clamped(img, int(p0.x), int(p0.y), int(p1.x), int(p1.y), Color(0.18, 0.2, 0.22))
	var pieces: Array = WastelandLayout.data()["pieces"]
	for p in pieces:
		var d: Dictionary = p
		if String(d.get("type", "")) == "prop":
			continue
		if String(d.get("name", "")).begins_with("G_") or String(d.get("name", "")).begins_with("Cliff"):
			continue  # sol/falaises : pas de silhouette, sinon la carte entière est pleine.
		var fp := Kit.piece_footprint(d)
		var p0 := _to_px(fp["min"] as Vector2)
		var p1 := _to_px(fp["max"] as Vector2)
		_fill_rect_clamped(img, int(p0.x), int(p0.y), int(p1.x), int(p1.y), _piece_color(d))
	return img

func _draw_map(clusters: Array) -> void:
	var img := _base_map_image()
	for c in clusters:
		var cd: Dictionary = c
		var pos: Vector3 = cd["pos"]
		var px := _to_px(Vector2(pos.x, pos.z))
		var severity: int = cd["count"]
		var radius := clampf(4.0 + float(severity), 4.0, 16.0)
		_fill_circle(img, px, radius + 2.0, Color(0, 0, 0))
		_fill_circle(img, px, radius, Color(1.0, 0.15, 0.1))
	var abs_path := ProjectSettings.globalize_path(_out_dir.path_join("map.jpg"))
	var dir := abs_path.get_base_dir()
	if dir != "" and not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	img.save_jpg(abs_path, 0.9)

func _draw_cluster(cluster: Dictionary) -> void:
	var img := _base_map_image()
	var pos: Vector3 = cluster["pos"]
	var px := _to_px(Vector2(pos.x, pos.z))
	_fill_circle(img, px, 8.0, Color(0, 0, 0))
	_fill_circle(img, px, 6.0, Color(1.0, 0.15, 0.1))
	# Gros plan : fenêtre de 14 x 14 m autour de la grappe, agrandie.
	var half_m := 7.0
	var lo := _to_px(Vector2(pos.x - half_m, pos.z - half_m))
	var hi := _to_px(Vector2(pos.x + half_m, pos.z + half_m))
	var rx0 := clampi(int(mini(lo.x, hi.x)), 0, IMG_W - 2)
	var ry0 := clampi(int(mini(lo.y, hi.y)), 0, IMG_H - 2)
	var rw := clampi(int(absf(hi.x - lo.x)), 4, IMG_W - rx0)
	var rh := clampi(int(absf(hi.y - lo.y)), 4, IMG_H - ry0)
	var region := img.get_region(Rect2i(rx0, ry0, rw, rh))
	region.resize(560, 560, Image.INTERPOLATE_NEAREST)
	var abs_path := ProjectSettings.globalize_path(_out_dir.path_join("clusters/cluster_%03d.jpg" % int(cluster["id"])))
	var dir := abs_path.get_base_dir()
	if dir != "" and not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	region.save_jpg(abs_path, 0.9)
