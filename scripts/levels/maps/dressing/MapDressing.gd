## MapDressing.gd
## Repaint set-dressing for the six ORIGINAL 4v4/duel maps — Port-Ferraille,
## Val-Poussière, Saint-Ombre, Col du Vautour, La Fosse, Le Belvédère — in the
## v2 "Peint au soleil, encré gras" style (.orchestrator/design.md,
## .orchestrator/maps-spec-v2.md §6 "Repaint of the six existing maps").
##
## Pure data, no nodes, no `Layouts.gd`/`Kit.gd`/`MapSetup.gd` edits (those
## three plus `PropCatalog.gd` stay read-only/owned by the concurrent map-
## builder slice — P2.7 brief "you may ONLY write scripts/levels/maps/
## dressing/**"). `MapSetup`'s dressing hook calls `for_map(map_id)` for extra
## `PropCatalog.place()`/`place_many()` calls layered on top of the UNCHANGED
## collision layout, and `surface_kinds(map_id)` to pick a `Cartoon.painted()`
## kind per palette role instead of the flat v1 tint.
##
## Collision discipline (brief "Rules: dressing must not break the validated
## layouts"): every entry here defaults to `collide = false` — either a visual
## skin layered on Kit geometry that ALREADY owns its collision (Kit's `box`/
## `building2`/etc. always collide unless `visual_only`, so a second body
## would only be redundant StaticBody3D count against §8.17's 400 cap), or
## pure atmosphere (signs, poles, pipes, fenders) kept off the geometry
## entirely. The one exception is La Fosse's pit-corner tyre stacks
## (`collide = true`, see `LaFosseDressing.entries()`), verified by hand
## against `Layouts.la_fosse()`'s own spawns/duel_zone — the brief's rule
## ("collide=true only where there's already cover of similar footprint, or
## out of the playable lanes") is enforced by `tests/maps/test_dressing.gd`,
## which treats every hardpoint/site/duel_zone as a generous exclusion box
## (there is no pure "lane centreline" data to check against directly — the
## real path validation for the untouched base layout already lives in
## `test_navmesh.gd`; dressing never moves or removes a single Kit piece).
class_name MapDressing
extends RefCounted

const MAP_IDS := ["port_ferraille", "val_poussiere", "saint_ombre", "col_du_vautour", "la_fosse", "le_belvedere"]

## `role -> painted kind` per map (maps-spec-v2.md §6 "Materials:"), folded
## onto the 11 kinds `Cartoon.painted()`/`Cartoon._KIND_ALIASES` actually ship
## (design.md §6 describes materials — "steel_plate", "grating", "cobbles",
## "slate", "stone", "snow", "adobe", "zinc", "plaster", "tile" — that have no
## `tools/textures/gen_textures.py` entry of their own; each below is folded
## onto its closest available kind, reasoned per map in the comment).
const _SURFACE_KINDS: Dictionary = {
	# Port-Ferraille (docks): floor concrete(=); wall stone->concrete; cover
	# steel_plate->container (the yard's "cover" pieces ARE mostly containers:
	# Tube0/C1/PerchLow/PerchHigh/Step/ShieldLow/ShieldHigh); platform
	# grating->painted_metal (rail deck); accent steel_plate->painted_metal
	# (gantry beam/cab/jib).
	"port_ferraille": {"floor": "concrete", "wall": "concrete", "cover": "container", "platform": "painted_metal", "accent": "painted_metal"},
	# Val-Poussière (frontier town): floor sand(=); wall/cover planks->wood
	# (false-front buildings, crates); platform adobe->sand (plastered earth
	# reads closer to sand's warm grain than cracked concrete); accent
	# planks->wood.
	"val_poussiere": {"floor": "sand", "wall": "wood", "cover": "wood", "platform": "sand", "accent": "wood"},
	# Saint-Ombre (rainy industrial old town): floor cobbles->concrete; wall
	# slate->corrugated (the mill/atelier sheds read as industrial cladding);
	# cover/accent steel_plate->painted_metal; platform stone->concrete
	# (tribune/balcony/viaduct decks).
	"saint_ombre": {"floor": "concrete", "wall": "corrugated", "cover": "painted_metal", "platform": "concrete", "accent": "painted_metal"},
	# Col du Vautour (alpine outpost): floor snow->concrete (cracked-concrete
	# detail reads as packed/broken snow once tinted near-white); wall/
	# platform rock->asphalt (dark, fine-grained, closest to basalt outcrop);
	# cover planks->wood; accent steel_plate->painted_metal.
	"col_du_vautour": {"floor": "concrete", "wall": "asphalt", "cover": "wood", "platform": "asphalt", "accent": "painted_metal"},
	# La Fosse (quarry): same stone/rock family as Col du Vautour.
	"la_fosse": {"floor": "concrete", "wall": "asphalt", "cover": "wood", "platform": "asphalt", "accent": "painted_metal"},
	# Le Belvédère (rooftops): floor/platform zinc->corrugated (zinc roofing
	# IS a corrugated sheet); wall plaster->sand (warm plaster grain); cover
	# tile->concrete; accent steel_plate->painted_metal.
	"le_belvedere": {"floor": "corrugated", "wall": "sand", "cover": "concrete", "platform": "corrugated", "accent": "painted_metal"},
}

## Extra `PropCatalog` placements for `map_id` — `[]` for any id this slice
## doesn't cover (e.g. "wasteland"/"cargo_ship", or an unknown id). Each
## entry: `{prop: String, pos: Vector3, rot_y: float (degrees), collide: bool,
## tint: Color (optional)}`. Pure data: same input always yields an
## `==`-identical array (no RNG, no engine/singleton reads).
static func for_map(map_id: String) -> Array:
	match map_id:
		"port_ferraille":
			return PortFerrailleDressing.entries()
		"val_poussiere":
			return ValPoussiereDressing.entries()
		"saint_ombre":
			return SaintOmbreDressing.entries()
		"col_du_vautour":
			return ColDuVautourDressing.entries()
		"la_fosse":
			return LaFosseDressing.entries()
		"le_belvedere":
			return LeBelvedereDressing.entries()
	return []

## `role ("floor"/"wall"/"cover"/"platform"/"accent") -> painted kind` for
## `map_id`, or `{}` for any id this slice doesn't cover.
static func surface_kinds(map_id: String) -> Dictionary:
	return _SURFACE_KINDS.get(map_id, {})

## TECH-08 (docs/research/07_godot_tech.md §C3, backlog acceptance "les
## répétitions de plus de 8 exemplaires passent en MultiMesh") : seuil
## STRICTEMENT au-dessus duquel un groupe d'entrées identiques (même prop,
## même teinte, même `collide`) doit fusionner en UN `PropCatalog.place_many`
## plutôt que N appels `PropCatalog.place` isolés. Volontairement distinct du
## seuil générique de `PropCatalog.place_many()` (>= 3, verrouillé par
## `tests/maps/test_propcatalog.gd` pour le groupage des cartes DE BASE
## Wasteland/Cargo Ship dans `MapSetup._build_props`) : le dressing des six
## cartes repeintes reste en entrées isolées jusqu'à 8 répétitions du même
## prop — la lisibilité par entrée prime tant que le nombre de draws reste
## modeste — et ne fusionne qu'au-delà.
const MULTIMESH_THRESHOLD := 8

## Regroupe `entries` (le format `for_map()` : {prop, pos, rot_y, collide,
## tint?}) par (prop, teinte, collide). Renvoie {"singles": Array[entrée
## d'origine], "batches": Array[{prop, tint, collide, transforms:
## Array[Transform3D]}]} : un groupe de plus de `MULTIMESH_THRESHOLD`
## exemplaires part en "batches" (prêt pour `PropCatalog.place_many`), le
## reste (petits groupes ET singletons) reste en "singles", INCHANGÉ (mêmes
## dictionnaires que `for_map()`, jamais reconstruits) pour ne rien perdre du
## contrat existant consommé par `MapSetup._build_dressing`. Fonction PURE :
## une entrée sans "tint" vaut `Color.WHITE` (même repli que
## `MapSetup._build_dressing`/`PropCatalog.place`), une entrée sans "collide"
## vaut `true` (même repli que `for_map()`'s propre contrat, voir
## `tests/maps/test_dressing.gd`).
static func group_entries(entries: Array) -> Dictionary:
	var keys: Array = []
	var counts: Dictionary = {}
	for entry in entries:
		var e: Dictionary = entry
		var tint: Color = e.get("tint", Color.WHITE)
		var collide := bool(e.get("collide", true))
		var key := "%s|%s|%s" % [String(e["prop"]), tint.to_html(), collide]
		keys.append(key)
		counts[key] = int(counts.get(key, 0)) + 1

	var batch_meta: Dictionary = {}       # key -> {prop, tint, collide}
	var batch_transforms: Dictionary = {} # key -> Array[Transform3D]
	var batch_order: Array = []
	var singles: Array = []
	for i in entries.size():
		var e: Dictionary = entries[i]
		var key: String = keys[i]
		if int(counts[key]) > MULTIMESH_THRESHOLD:
			if not batch_meta.has(key):
				batch_meta[key] = {"prop": String(e["prop"]), "tint": e.get("tint", Color.WHITE), "collide": bool(e.get("collide", true))}
				batch_transforms[key] = []
				batch_order.append(key)
			var rot_y: float = float(e.get("rot_y", 0.0))
			(batch_transforms[key] as Array).append(Transform3D(Basis(Vector3.UP, deg_to_rad(rot_y)), e["pos"] as Vector3))
		else:
			singles.append(e)

	var batches: Array = []
	for key in batch_order:
		var meta: Dictionary = (batch_meta[key] as Dictionary).duplicate()
		meta["transforms"] = batch_transforms[key]
		batches.append(meta)
	return {"singles": singles, "batches": batches}

## Raccourci pour `group_entries(for_map(map_id))` — voir sa doc.
static func batches_for_map(map_id: String) -> Dictionary:
	return group_entries(for_map(map_id))
