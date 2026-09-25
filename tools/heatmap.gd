## heatmap.gd
## LD-08 (docs/research/03_level_design.md §2.8, dépend de FUN-05) : première
## moitié de l'outil de heatmap — "Bungie calculait les heatmaps de kills et
## de morts de Halo 3... la recherche compare aussi kills, morts et leur
## différence". Pur calcul + IO fichier (comme tools/balance_table.gd),
## AUCUNE scène chargée, aucun rendu ici — la rasterisation PNG est déléguée à
## tools/heatmap_render.py (numpy/Pillow, plus adapté qu'Image.gd pour les
## dégradés de couleur et le texte des légendes).
##
## Rôle : lire un JSONL d'événements Telemetry (scripts/core/Telemetry.gd),
## isoler les `kill` d'UN match (killer_pos/victim_pos, cf.
## `_REQUIRED_FIELDS[EVENT_KILL]`), récupérer les bounds RÉELS de la map
## jouée (Layouts.data_for / CargoShipLayout.data / WastelandLayout.data —
## même repli que tools/map_shots.gd `_poses_for`, AUCUNE géométrie inventée),
## puis compter les kills et les morts dans une grille de `cell` mètres
## (2 m par défaut, critère d'acceptation LD-08) calée sur ces bounds.
## Écrit un manifeste JSON (bounds, grille, compteurs) que
## `tools/heatmap_render.py` transforme en 3 PNG top-down (kills, morts,
## kills − morts).
##
## Convention de grille (partagée avec heatmap_render.py, à ne pas changer
## sans mettre à jour les deux fichiers) : `bounds.min`/`bounds.max` sont
## [x, z] (Vector2.y des Layouts == Z monde, cf. Layouts.gd `_aerial_poses`
## dans tools/map_shots.gd). `grid[row][col]` : `col` croît avec X, `row`
## croît avec Z — row 0 = bounds.min.z, col 0 = bounds.min.x. Un point hors
## bounds (recul, ragdoll...) est BORNÉ à la cellule de bord la plus proche
## plutôt qu'ignoré, pour que kill_count == nombre de `kill` retenus.
##
## Usage :
##   godot --headless --path . -s res://tools/heatmap.gd -- \
##       --in=<events.jsonl> [--map=<map_id>] [--match=<match_id>] \
##       [--out=<grid.json>] [--cell=2.0]
##
## `--map`/`--match` sont optionnels : à défaut, le dernier événement
## `match_start` du fichier fournit `map_id` ET sert de filtre `match_id`
## (un fichier de session peut contenir plusieurs matchs — voir
## `start_session`, "un fichier par PROCESS" — seul le dernier est traité).
## `--map` sans `--match` traite alors TOUS les `kill` du fichier (pas de
## filtre de match), utile pour un fichier qui ne contient qu'un seul match
## sans son `match_start` (ex. log tronqué au démarrage).
##
## Imprime `HEATMAP_GRID <map_id> <chemin>` puis `HEATMAP_GRID_DONE
## kills=<n> morts=<n> événements=<n>` et quitte (0), ou `HEATMAP_GRID_FAIL
## <raison>` (1) sans jamais lever d'exception (fichier absent, JSONL
## corrompu, map_id inconnu : tous couverts par un message clair).
extends SceneTree

const DEFAULT_CELL_SIZE := 2.0


func _initialize() -> void:
	var args := _parse_args()
	var in_path: String = args.get("in", "")
	if in_path == "":
		_fail("--in=<events.jsonl> est requis")
		return
	var events := _read_jsonl(in_path)
	if events.is_empty():
		_fail("aucun événement JSONL valide dans %s" % in_path)
		return
	var resolved := _resolve_match_and_map(events, args.get("match", ""), args.get("map", ""))
	if resolved.is_empty():
		_fail("impossible de déterminer map_id (aucun match_start dans %s et --map non fourni)" % in_path)
		return
	var map_id: String = resolved["map_id"]
	var match_id: String = resolved["match_id"]
	var bounds := _bounds_for_map(map_id)
	if bounds.is_empty():
		_fail("map_id inconnu (sans bounds déclarés) : %s" % map_id)
		return
	var cell_size := DEFAULT_CELL_SIZE
	if args.has("cell"):
		cell_size = float(args["cell"])
		if cell_size <= 0.0:
			_fail("--cell doit être > 0 (reçu %s)" % args["cell"])
			return
	var grid := _build_grid(events, match_id, bounds, cell_size)
	if grid["event_count"] == 0:
		_fail("aucun événement kill exploitable pour match_id=%s map_id=%s" % [match_id, map_id])
		return
	var out_path: String = args.get("out", "")
	if out_path == "":
		out_path = _default_out_path(in_path)
	var mn: Vector2 = bounds["min"]
	var mx: Vector2 = bounds["max"]
	var payload := {
		"map_id": map_id,
		"match_id": match_id,
		"cell_size": cell_size,
		"bounds": {"min": [mn.x, mn.y], "max": [mx.x, mx.y]},
		"grid_w": grid["grid_w"],
		"grid_h": grid["grid_h"],
		"kills": grid["kills"],
		"deaths": grid["deaths"],
		"kill_count": grid["kill_count"],
		"death_count": grid["death_count"],
		"event_count": grid["event_count"],
	}
	if not _write_json(out_path, payload):
		return
	print("HEATMAP_GRID ", map_id, " ", out_path)
	print("HEATMAP_GRID_DONE kills=%d morts=%d événements=%d" % [grid["kill_count"], grid["death_count"], grid["event_count"]])
	quit(0)


# ======================================================================
#  Arguments
# ======================================================================
func _parse_args() -> Dictionary:
	var out := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--in="):
			out["in"] = a.get_slice("=", 1)
		elif a.begins_with("--map="):
			out["map"] = a.get_slice("=", 1)
		elif a.begins_with("--match="):
			out["match"] = a.get_slice("=", 1)
		elif a.begins_with("--out="):
			out["out"] = a.get_slice("=", 1)
		elif a.begins_with("--cell="):
			out["cell"] = a.get_slice("=", 1)
	return out


# ======================================================================
#  Lecture JSONL — une Dictionary par ligne valide, les lignes vides ou
#  non-JSON (fichier tronqué en pleine écriture, cf. Telemetry.close_log)
#  sont silencieusement ignorées plutôt que de faire échouer tout l'outil.
# ======================================================================
func _read_jsonl(path: String) -> Array:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return []
	var out: Array = []
	while not f.eof_reached():
		var line := f.get_line()
		if line.strip_edges() == "":
			continue
		var json := JSON.new()
		if json.parse(line) != OK:
			continue
		var parsed = json.get_data()
		if parsed is Dictionary:
			out.append(parsed)
	f.close()
	return out


# ======================================================================
#  Résolution map_id/match_id — voir la doc d'en-tête.
# ======================================================================
func _resolve_match_and_map(events: Array, match_arg: String, map_arg: String) -> Dictionary:
	if map_arg != "" and match_arg != "":
		return {"map_id": map_arg, "match_id": match_arg}
	var match_starts: Array = []
	for e in events:
		if e is Dictionary and String(e.get("event", "")) == "match_start":
			match_starts.append(e)
	if match_starts.is_empty():
		if map_arg != "":
			return {"map_id": map_arg, "match_id": match_arg}
		return {}
	var chosen: Dictionary = {}
	if match_arg != "":
		for e in match_starts:
			if String(e.get("match_id", "")) == match_arg:
				chosen = e
				break
		if chosen.is_empty():
			return {}
	else:
		chosen = match_starts[match_starts.size() - 1]
	var map_id := map_arg if map_arg != "" else String(chosen.get("map_id", ""))
	if map_id == "":
		return {}
	return {"map_id": map_id, "match_id": String(chosen.get("match_id", ""))}


# ======================================================================
#  Bounds réels de la map — même repli que tools/map_shots.gd `_poses_for`
#  (Layouts.data_for couvre les 6 maps v1, Cargo Ship/Wasteland vivent hors
#  Layouts.gd, cf. leurs docstrings "maps-spec-v2.md").
# ======================================================================
func _bounds_for_map(map_id: String) -> Dictionary:
	var data: Dictionary = Layouts.data_for(map_id)
	if data.is_empty():
		match map_id:
			"cargo_ship":
				data = CargoShipLayout.data()
			"wasteland":
				data = WastelandLayout.data()
	if not data.has("bounds"):
		return {}
	return data["bounds"]


# ======================================================================
#  Grille — voir la doc d'en-tête pour la convention row/col.
# ======================================================================
func _build_grid(events: Array, match_id: String, bounds: Dictionary, cell_size: float) -> Dictionary:
	var mn: Vector2 = bounds["min"]
	var mx: Vector2 = bounds["max"]
	var grid_w: int = maxi(1, int(ceil((mx.x - mn.x) / cell_size)))
	var grid_h: int = maxi(1, int(ceil((mx.y - mn.y) / cell_size)))
	var kills := _zero_grid(grid_w, grid_h)
	var deaths := _zero_grid(grid_w, grid_h)
	var kill_count := 0
	var death_count := 0
	var event_count := 0
	for e in events:
		if not (e is Dictionary) or String(e.get("event", "")) != "kill":
			continue
		if match_id != "" and String(e.get("match_id", "")) != match_id:
			continue
		var kp = e.get("killer_pos")
		var vp = e.get("victim_pos")
		if not (kp is Array and kp.size() >= 3) or not (vp is Array and vp.size() >= 3):
			continue
		event_count += 1
		var kcol := _bucket(float(kp[0]), mn.x, cell_size, grid_w)
		var krow := _bucket(float(kp[2]), mn.y, cell_size, grid_h)
		kills[krow][kcol] += 1
		kill_count += 1
		var dcol := _bucket(float(vp[0]), mn.x, cell_size, grid_w)
		var drow := _bucket(float(vp[2]), mn.y, cell_size, grid_h)
		deaths[drow][dcol] += 1
		death_count += 1
	return {
		"grid_w": grid_w, "grid_h": grid_h,
		"kills": kills, "deaths": deaths,
		"kill_count": kill_count, "death_count": death_count, "event_count": event_count,
	}


func _bucket(coord: float, min_v: float, cell_size: float, count: int) -> int:
	var idx := int(floor((coord - min_v) / cell_size))
	return clampi(idx, 0, count - 1)


func _zero_grid(w: int, h: int) -> Array:
	var grid: Array = []
	for _r in h:
		var row: Array = []
		row.resize(w)
		row.fill(0)
		grid.append(row)
	return grid


# ======================================================================
#  Sortie
# ======================================================================
func _default_out_path(in_path: String) -> String:
	var dir := in_path.get_base_dir()
	var stem := in_path.get_file().get_basename()
	return "%s/%s_grid.json" % [dir, stem]


func _write_json(out_path: String, payload: Dictionary) -> bool:
	var dir := out_path.get_base_dir()
	if dir != "" and not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	if f == null:
		_fail("impossible d'écrire %s (err=%s)" % [out_path, FileAccess.get_open_error()])
		return false
	f.store_string(JSON.stringify(payload))
	f.close()
	return true


func _fail(reason: String) -> void:
	print("HEATMAP_GRID_FAIL ", reason)
	quit(1)
