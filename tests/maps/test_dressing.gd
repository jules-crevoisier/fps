## test_dressing.gd
## Validation for the repaint set-dressing slice (P2.7 brief, "Tests first"):
## `scripts/levels/maps/dressing/MapDressing.gd` and its six per-map data
## files. Pure data, no nodes/engine needed beyond `PropCatalog`'s manifest
## read (headless-safe: `PropCatalog._ensure_loaded()` just parses JSON) and
## `Kit`'s pure geometry helpers (`piece_footprint`/`piece_blocks_sight`,
## already exercised by `test_layouts.gd`).
##
## Brief acceptance, verbatim:
##   "every entry names a real prop, positions inside bounds (or explicitly
##   decorative outside), no collide=true prop overlapping spawn areas/
##   objective zones/lane centrelines from the layout data, deterministic
##   output."
## The fourth item ("lane centrelines") has no pure-data representation in
## `Layouts.gd` — these six maps' actual walkable paths bend around ramps and
## multi-tier cover, so a straight spawn-to-spawn or spawn-to-objective
## segment is NOT a faithful stand-in (§5.3 of test_layouts.gd proves spawn
## pairs never even have a clear LINE OF SIGHT, let alone a straight path).
## Per the brief's own rule ("collide=true may only sit where the layout
## already has cover of similar footprint, OR out of the playable lanes"),
## this suite enforces "out of the playable lanes" via generous exclusion
## boxes around every spawn and every hardpoint/site/duel_zone — the concrete
## places a lane must pass through or terminate at — and offers the
## "adjacent to existing cover" branch as an alternative pass condition. The
## real navmesh-path validation for the (untouched) base layout stays in
## `test_navmesh.gd`.
extends GdUnitTestSuite

const MAP_IDS := ["port_ferraille", "val_poussiere", "saint_ombre", "col_du_vautour", "la_fosse", "le_belvedere"]
const PAINTED_KINDS := ["painted_metal", "rust", "corrugated", "container", "wood", "sand", "concrete", "asphalt", "ship_deck", "rubber", "glass"]
const PALETTE_ROLES := ["floor", "wall", "cover", "platform", "accent"]

## Generous, hand-reasoned margins (see file header) — not a precise path
## model, a conservative "clearly nowhere near" check.
const SPAWN_MARGIN := 2.5
const OBJECTIVE_MARGIN := 1.0
const COVER_ADJACENCY := 2.0


# ======================================================================
#  Pure geometry helpers
# ======================================================================
static func _pos2(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)


static func _in_bounds(p: Vector2, bounds: Dictionary) -> bool:
	var mn: Vector2 = bounds["min"]
	var mx: Vector2 = bounds["max"]
	return p.x >= mn.x and p.x <= mx.x and p.y >= mn.y and p.y <= mx.y


static func _all_spawn_points_xz(data: Dictionary) -> Array:
	var out: Array = []
	for team in (data["spawns"] as Dictionary).keys():
		for entry in (data["spawns"][team] as Array):
			out.append(_pos2((entry as Dictionary)["pos"] as Vector3))
	return out


## Every hardpoint/site/duel_zone as an XZ box, half-extents padded by
## `OBJECTIVE_MARGIN`. Hardpoint zones are 10x4x10 (`MapSetup._make_zone`,
## `Vector3(10, 4, 10)`) centred on the marker; site/duel_zone use their own
## declared `size`.
static func _objective_boxes(data: Dictionary) -> Array:
	var out: Array = []
	if data.has("hardpoints"):
		for p in (data["hardpoints"] as Array):
			var c := _pos2(p as Vector3)
			out.append({"min": c - Vector2(5.0, 5.0) - Vector2.ONE * OBJECTIVE_MARGIN, "max": c + Vector2(5.0, 5.0) + Vector2.ONE * OBJECTIVE_MARGIN})
	for key in ["site_a", "site_b", "duel_zone"]:
		if not data.has(key):
			continue
		var d: Dictionary = data[key]
		var c2 := _pos2(d["pos"] as Vector3)
		var size: Vector3 = d["size"]
		var half := Vector2(size.x, size.z) * 0.5 + Vector2.ONE * OBJECTIVE_MARGIN
		out.append({"min": c2 - half, "max": c2 + half})
	return out


static func _dist_point_box(p: Vector2, box: Dictionary) -> float:
	var mn: Vector2 = box["min"]
	var mx: Vector2 = box["max"]
	var dx := maxf(mn.x - p.x, maxf(0.0, p.x - mx.x))
	var dz := maxf(mn.y - p.y, maxf(0.0, p.y - mx.y))
	return Vector2(dx, dz).length()


## Nearest distance from `p` to any EXISTING layout piece that actually
## blocks sight (`Kit.piece_blocks_sight` — real solid cover, not an
## invisible wall or a visual-only piece), i.e. "cover of similar footprint"
## the brief allows a colliding prop to sit next to.
static func _nearest_cover_distance(data: Dictionary, p: Vector2) -> float:
	var best := INF
	for piece in (data["pieces"] as Array):
		if not Kit.piece_blocks_sight(piece):
			continue
		var fp := Kit.piece_footprint(piece)
		best = minf(best, _dist_point_box(p, {"min": fp["min"], "max": fp["max"]}))
	return best


static func _prop_radius(prop: String) -> float:
	var fp := PropCatalog.footprint(prop)
	return maxf(fp.x, fp.z) * 0.5


# ======================================================================
#  Every entry names a real prop
# ======================================================================
func test_every_entry_names_a_real_prop() -> void:
	var known := PropCatalog.names()
	for id in MAP_IDS:
		for entry in MapDressing.for_map(id):
			var e: Dictionary = entry
			var prop := String(e["prop"])
			assert_bool(known.has(prop)).append_failure_message("%s: unknown prop \"%s\"" % [id, prop]).is_true()


# ======================================================================
#  Entry dict shape (types match the P2.7 hook contract exactly)
# ======================================================================
func test_every_entry_has_the_contracted_keys_and_types() -> void:
	for id in MAP_IDS:
		for entry in MapDressing.for_map(id):
			var e: Dictionary = entry
			assert_bool(e.get("prop") is String).append_failure_message("%s: prop not a String (%s)" % [id, e]).is_true()
			assert_bool(e.get("pos") is Vector3).append_failure_message("%s: pos not a Vector3 (%s)" % [id, e]).is_true()
			assert_bool(typeof(e.get("rot_y")) == TYPE_FLOAT or typeof(e.get("rot_y")) == TYPE_INT).append_failure_message("%s: rot_y not numeric (%s)" % [id, e]).is_true()
			assert_bool(e.get("collide") is bool).append_failure_message("%s: collide not a bool (%s)" % [id, e]).is_true()
			if e.has("tint"):
				assert_bool(e["tint"] is Color).append_failure_message("%s: tint not a Color (%s)" % [id, e]).is_true()


# ======================================================================
#  Positions inside bounds, or explicitly decorative (collide=false) outside
# ======================================================================
func test_every_entry_is_in_bounds_or_explicitly_decorative_outside() -> void:
	for id in MAP_IDS:
		var data := Layouts.data_for(id)
		var bounds: Dictionary = data["bounds"]
		for entry in MapDressing.for_map(id):
			var e: Dictionary = entry
			var pos: Vector3 = e["pos"]
			var inside := _in_bounds(_pos2(pos), bounds)
			var ok := inside or not bool(e["collide"])
			assert_bool(ok).append_failure_message("%s: %s (%s) is outside bounds and collide=true" % [id, e["prop"], pos]).is_true()


# ======================================================================
#  collide=true never overlaps a spawn area or an objective zone, unless it
#  sits right next to cover the ORIGINAL layout already validated.
# ======================================================================
func test_no_colliding_prop_overlaps_a_spawn_area_or_objective_zone() -> void:
	for id in MAP_IDS:
		var data := Layouts.data_for(id)
		var spawns := _all_spawn_points_xz(data)
		var zones := _objective_boxes(data)
		for entry in MapDressing.for_map(id):
			var e: Dictionary = entry
			if not bool(e["collide"]):
				continue
			var p := _pos2(e["pos"] as Vector3)
			var radius := _prop_radius(String(e["prop"]))

			var near_cover := _nearest_cover_distance(data, p) <= COVER_ADJACENCY

			var clear_of_spawns := true
			for sp in spawns:
				if (sp as Vector2).distance_to(p) < SPAWN_MARGIN + radius:
					clear_of_spawns = false
					break
			var clear_of_zones := true
			for zbox in zones:
				if _dist_point_box(p, zbox as Dictionary) < radius:
					clear_of_zones = false
					break
			var out_of_lanes := clear_of_spawns and clear_of_zones

			var msg := "%s: colliding %s at %s overlaps a spawn/objective zone and isn't next to existing cover" % [id, e["prop"], e["pos"]]
			assert_bool(near_cover or out_of_lanes).append_failure_message(msg).is_true()


# ======================================================================
#  Deterministic output
# ======================================================================
func test_for_map_is_deterministic() -> void:
	for id in MAP_IDS:
		var a := MapDressing.for_map(id)
		var b := MapDressing.for_map(id)
		assert_str(var_to_str(a)).append_failure_message(id).is_equal(var_to_str(b))


func test_surface_kinds_is_deterministic() -> void:
	for id in MAP_IDS:
		assert_str(var_to_str(MapDressing.surface_kinds(id))).is_equal(var_to_str(MapDressing.surface_kinds(id)))


# ======================================================================
#  surface_kinds(): every role covered, every value a real painted kind
# ======================================================================
func test_surface_kinds_covers_all_five_roles_for_each_map() -> void:
	for id in MAP_IDS:
		var kinds := MapDressing.surface_kinds(id)
		for role in PALETTE_ROLES:
			assert_bool(kinds.has(role)).append_failure_message("%s missing surface_kinds[%s]" % [id, role]).is_true()


func test_surface_kinds_values_are_known_painted_kinds() -> void:
	for id in MAP_IDS:
		var kinds := MapDressing.surface_kinds(id)
		for role in kinds.keys():
			var kind := String(kinds[role])
			assert_bool(PAINTED_KINDS.has(kind)).append_failure_message("%s.%s = \"%s\" not a Cartoon.painted() kind" % [id, role, kind]).is_true()


# ======================================================================
#  Coverage: exactly the six repaint maps, each non-empty; anything else
#  (wasteland/cargo_ship/unknown) is untouched by this slice.
# ======================================================================
func test_for_map_is_nonempty_for_each_of_the_six_maps() -> void:
	for id in MAP_IDS:
		assert_int((MapDressing.for_map(id) as Array).size()).append_failure_message(id).is_greater(0)


func test_for_map_and_surface_kinds_are_empty_outside_this_slice() -> void:
	for id in ["wasteland", "cargo_ship", "", "not_a_map"]:
		assert_array(MapDressing.for_map(id)).append_failure_message(id).is_empty()
		assert_bool((MapDressing.surface_kinds(id) as Dictionary).is_empty()).append_failure_message(id).is_true()


func test_map_ids_match_layouts_map_ids() -> void:
	assert_array(MapDressing.MAP_IDS).contains_exactly_in_any_order(Layouts.MAP_IDS)
