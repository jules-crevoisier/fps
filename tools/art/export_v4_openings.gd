## export_v4_openings.gd
## ART-91 (docs/art/WASTELAND_V4_ART_PLAN.md §1 R3 "Ouvertures" : « La source
## de vérité est la collision construite. Elle est exportée en tools/art/
## data/wasteland_v4_boxes.json (ART-91), jamais recopiée à la main. ») —
## exporte, pour CHACUNE des 11 pièces `building2` de `WastelandLayout.data()`
## (5 côté ouest + leurs 5 miroirs est + le Wagon, non mirroré), sa boîte
## (pos/size/étages) et le rectangle MONDE de CHACUNE de ses ouvertures
## (portes ET fenêtres), calculés par `Kit.door_world_rect`/
## `Kit.window_world_rects` — jamais retranscrits à la main depuis
## `wasteland.gd` : un futur changement de `wasteland.gd` (portes élargies,
## etc., comme LD-43) se répercute donc ici à la prochaine exécution, sans
## toucher ce fichier.
##
##   godot --headless --path . -s res://tools/art/export_v4_openings.gd -- [--out=res://tools/art/data/wasteland_v4_boxes.json]
##
## Affiche `EXPORT_V4_OPENINGS_OK <chemin> buildings=<n> openings=<n>` puis
## quitte (0), ou `EXPORT_V4_OPENINGS_FAIL <raison>` (1).
extends SceneTree

const DEFAULT_OUT := "res://tools/art/data/wasteland_v4_boxes.json"

## Épaisseur de mur d'un `building2` — Kit.gd `_BLD_WALL_T` (constante privée,
## jamais exposée hors de Kit.gd : dupliquée ici en toute sécurité, c'est une
## valeur de MISE EN PAGE de la carte, verrouillée par le contrat de niveau
## (docs/research/11_wasteland_v4_layout.md), pas une formule qui pourrait
## diverger comme les rectangles d'ouverture (ceux-là restent calculés par
## `Kit.door_world_rect`/`Kit.window_world_rects`, jamais recopiés).
const WALL_THICKNESS := 0.25


func _initialize() -> void:
	var out_path := DEFAULT_OUT
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_path = a.get_slice("=", 1)

	var data := WastelandLayout.data()
	var pieces: Array = data.get("pieces", [])
	var buildings: Array = []
	var opening_count := 0

	for entry in pieces:
		var piece: Dictionary = entry
		if String(piece.get("type", "")) != "building2":
			continue
		var b := _export_building(piece)
		opening_count += (b["openings"] as Array).size()
		buildings.append(b)

	# R3 "toutes les pièces et les ouvertures des 11 building2" : garde-fou
	# imprimé mais non bloquant en soi (le compte réel vient de la carte
	# réelle) — `tests/maps/test_wasteland_art_parity.gd` verrouille le
	# nombre exact (11) séparément, contre `WastelandLayout.data()` en direct.
	if buildings.size() != 11:
		push_warning("export_v4_openings: %d building2 trouvés (attendu 11) — wasteland.gd a changé, ce fichier reste hors de mon périmètre." % buildings.size())

	var doc := {
		"generated_by": "tools/art/export_v4_openings.gd",
		"source": "scripts/levels/maps/layouts/wasteland.gd (WastelandLayout.data())",
		"wall_thickness": WALL_THICKNESS,
		"opening_tolerance_m": 0.02,  # R3 "l'outil perce la carte à ±2 cm"
		"buildings": buildings,
	}

	var abs_path := ProjectSettings.globalize_path(out_path)
	var dir := abs_path.get_base_dir()
	if dir != "" and not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	if f == null:
		print("EXPORT_V4_OPENINGS_FAIL impossible d'ouvrir %s (err=%s)" % [out_path, FileAccess.get_open_error()])
		quit(1)
		return
	f.store_string(JSON.stringify(doc, "  "))
	f.close()
	print("EXPORT_V4_OPENINGS_OK %s buildings=%d openings=%d" % [out_path, buildings.size(), opening_count])
	quit(0)


## Rectangle MONDE -> tableau JSON-compatible [x_lo, x_hi, z_lo, z_hi, y0, y1]
## (Vector3/Vector2 ne se sérialisent pas nativement en JSON lisible).
static func _rect_to_array(rect: Dictionary) -> Array:
	return [rect["x_lo"], rect["x_hi"], rect["z_lo"], rect["z_hi"], rect["y0"], rect["y1"]]


static func _vec3_to_array(v: Vector3) -> Array:
	return [v.x, v.y, v.z]


## Une pièce `building2` -> dictionnaire exportable, portes ET fenêtres.
## Fenêtres : uniquement les (côté, étage) SANS porte (même condition que
## `_bld_wall_side` — voir le commentaire de `Kit.window_world_rects`).
static func _export_building(piece: Dictionary) -> Dictionary:
	var name := String(piece.get("name", ""))
	var pos: Vector3 = piece["pos"]
	var size: Vector3 = piece["size"]
	var floors := maxi(int(piece.get("floors", 1)), 1)
	var doors: Array = piece.get("doors", [])
	var windows: Array = piece.get("windows", [])
	var slit := bool(piece.get("slit", false))

	var openings: Array = []
	for entry in doors:
		var d: Dictionary = entry
		var rect := Kit.door_world_rect(piece, d)
		openings.append({
			"kind": "door", "side": rect["side"], "floor": rect["floor"],
			"offset": float(d.get("offset", 0.0)), "w": float(d.get("w", 1.6)), "h": float(d.get("h", 2.4)),
			"world": _rect_to_array(rect),
		})

	var doors_by_side_floor := {}
	for entry2 in doors:
		var d2: Dictionary = entry2
		var key := "%s|%d" % [String(d2.get("side", "N")), int(d2.get("floor", 0))]
		doors_by_side_floor[key] = true

	for side in windows:
		for f in floors:
			var key2 := "%s|%d" % [String(side), f]
			if doors_by_side_floor.has(key2):
				continue
			for rect2 in Kit.window_world_rects(piece, String(side), f, slit):
				var r: Dictionary = rect2
				openings.append({
					"kind": "window", "side": r["side"], "floor": r["floor"],
					"world": _rect_to_array(r),
				})

	return {
		"name": name,
		"pos": _vec3_to_array(pos),
		"size": _vec3_to_array(size),
		"floors": floors,
		"floor_height": size.y / float(floors),
		"stair_side": String(piece.get("stair_side", "N")),
		"roof_pitch_deg": float(piece.get("roof_pitch_deg", 0.0)),
		"pp": String(piece.get("pp", "")),
		"openings": openings,
	}
