## MapSetup.gd
## Construit une map à partir de `Layouts.data_for(map_id)` (contract-r3.md,
## interface croisée "Map scenes (R3-MAPS)") : géométrie + collision (Kit),
## marqueurs (SpawnPoints, HardpointPoints, SiteA/SiteB, DuelZone, Hardpoint),
## la NavigationRegion3D bakée (groupe "nav_region"), et le nœud de mode
## "GameMode" instancié depuis `MatchConfig.mode_id` et câblé à ces marqueurs.
## Tout se passe en `_enter_tree`, donc AVANT `GameWorld._ready` (qui spawn les
## joueurs/bots) : le contrat l'exige explicitement pour ce nœud.
##
## Les nœuds construits sont ajoutés comme ENFANTS DE `MapSetup` LUI-MÊME
## (pas de la racine GameWorld) : au moment où `_enter_tree` tourne, la racine
## est encore en train d'ajouter SES PROPRES enfants déclarés dans la scène
## (dont ce nœud) et refuse tout `add_child()` supplémentaire pendant ce
## temps ("Parent node is busy setting up children" — vérifié en headless).
## `GameMode` et ses marqueurs (SiteA/../Hardpoint...) restent frères entre
## eux (les `NodePath` relatifs type `../SiteA` marchent donc à l'identique),
## et chaque scène pointe l'export `GameWorld.spawn_points_root` vers
## `"MapSetup/SpawnPoints"` (au lieu du défaut `"SpawnPoints"`) pour que
## `GameWorld.gd` (inchangé, propriété R3-IN) les retrouve. `nav_region` est
## retrouvé par groupe ("nav_region", cf `scripts/ai/BotNavMesh.gd`), donc
## sa position dans l'arbre importe peu.
class_name MapSetup
extends Node3D

@export var map_id: String = ""

## Capsule joueur (scenes/player/player.tscn) : radius 0.4, height 1.8.
const AGENT_RADIUS := 0.4
const AGENT_HEIGHT := 1.8
const AGENT_MAX_CLIMB := 0.5
const AGENT_MAX_SLOPE := 46.0

var nav_region: NavigationRegion3D

## Repeint optionnel (maps-spec-v2.md §7) : un autre chantier livre CE fichier
## (scripts/levels/maps/dressing/MapDressing.gd, hors de mon périmètre cette
## manche) pour les six maps v1. Absent => comportement 100% inchangé (aucune
## des deux fonctions n'est appelée). `for_map(map_id) -> Array` : entrées à
## poser via PropCatalog. `surface_kinds(map_id) -> Dictionary` (rôle ->
## kind peint Cartoon.painted) : fusionné dans la palette AVANT `_build_geometry`
## sous la clé "<rôle>_kind", lue par Kit.build_piece (voir Kit.gd §GeoBatcher).
const _DRESSING_PATH := "res://scripts/levels/maps/dressing/MapDressing.gd"

## Cargo Ship / Wasteland (maps-spec-v2.md) vivent HORS `Layouts.gd`/
## `Layouts.MAP_IDS` (fichiers séparés, "layouts/cargo_ship.gd"/"wasteland.gd" —
## Layouts.gd reste au six maps v1, hors de mon périmètre cette manche).
static func _data_for(id: String) -> Dictionary:
	match id:
		"cargo_ship":
			return CargoShipLayout.data()
		"wasteland":
			return WastelandLayout.data()
	return Layouts.data_for(id)

func _enter_tree() -> void:
	if nav_region != null:
		return  # déjà construit (garde-fou anti double appel)
	var data := _data_for(map_id)
	if data.is_empty():
		push_error("MapSetup : layout introuvable pour map_id=\"%s\"" % map_id)
		return

	var dressing: Variant = _load_dressing()
	if dressing != null:
		_merge_surface_kinds(data, dressing)

	_build_geometry(data)
	_build_kill_volumes(data)
	_build_perimeter(data)
	_build_markers(data)
	_build_game_mode(data)

	if dressing != null:
		_build_dressing(dressing)

# ----------------------------------------------------------------------
#  Repeint des maps v1 (MapDressing, optionnel — voir _DRESSING_PATH)
# ----------------------------------------------------------------------
func _load_dressing() -> Variant:
	if not ResourceLoader.exists(_DRESSING_PATH):
		return null
	return load(_DRESSING_PATH)

func _merge_surface_kinds(data: Dictionary, dressing) -> void:
	if not dressing.has_method("surface_kinds"):
		return
	var kinds: Dictionary = dressing.surface_kinds(map_id)
	if kinds.is_empty():
		return
	var palette: Dictionary = data["palette"]
	for role in kinds.keys():
		palette["%s_kind" % String(role)] = String(kinds[role])

func _build_dressing(dressing) -> void:
	if not dressing.has_method("for_map"):
		return
	for entry in (dressing.for_map(map_id) as Array):
		var d: Dictionary = entry
		var rot_y_deg: float = float(d.get("rot_y_deg", rad_to_deg(float(d.get("rot_y", 0.0)))))
		var tint: Color = d.get("tint", Color.WHITE)
		PropCatalog.place(self, String(d["prop"]), d["pos"], rot_y_deg, tint, bool(d.get("collide", true)))

# ----------------------------------------------------------------------
#  Volumes de mise à mort serveur (§7.3) + périmètre invisible (§7.4)
# ----------------------------------------------------------------------
func _build_kill_volumes(data: Dictionary) -> void:
	if not data.has("kill_volumes"):
		return
	var i := 0
	for entry in (data["kill_volumes"] as Array):
		var d: Dictionary = entry
		var pos: Vector3 = d["pos"]
		var size: Vector3 = d["size"]
		var vol := KillVolume.new()
		vol.name = "KillVolume%d" % i
		vol.position = pos
		vol.bottom_y = pos.y - size.y * 0.5
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		col.shape = shape
		vol.add_child(col)
		add_child(vol)
		i += 1

## Murs invisibles 20 m le long de `perimeter` (Array[Vector2], boucle fermée
## implicite : le dernier point revient au premier).
func _build_perimeter(data: Dictionary) -> void:
	if not data.has("perimeter"):
		return
	var pts: Array = data["perimeter"]
	if pts.size() < 2:
		return
	for i in pts.size():
		var a2: Vector2 = pts[i]
		var b2: Vector2 = pts[(i + 1) % pts.size()]
		Kit.invisible_wall(self, Vector3(a2.x, 0.0, a2.y), Vector3(b2.x, 0.0, b2.y), 20.0, "Perimeter%d" % i)

# ----------------------------------------------------------------------
#  Géométrie + collision + bake du navmesh
# ----------------------------------------------------------------------
func _build_geometry(data: Dictionary) -> void:
	nav_region = NavigationRegion3D.new()
	nav_region.name = "NavRegion"
	nav_region.add_to_group("nav_region")
	add_child(nav_region)

	var batcher := Kit.GeoBatcher.new()
	var palette: Dictionary = data["palette"]
	for piece in (data["pieces"] as Array):
		if String((piece as Dictionary).get("type", "")) == "prop":
			continue  # posées à part, groupées/fusionnées — voir _build_props
		Kit.build_piece(nav_region, batcher, piece as Dictionary, palette)
	batcher.flush(nav_region)
	_build_props(nav_region, data["pieces"] as Array, palette)

	var nmesh := NavigationMesh.new()
	# Colliders statiques seulement : évite l'avertissement "parse RenderingServer
	# meshes at runtime" (lecture GPU->CPU coûteuse) — chaque pièce Kit pose déjà
	# sa collision, inutile de reparser les meshes visuels fusionnés.
	nmesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nmesh.agent_radius = AGENT_RADIUS
	nmesh.agent_height = AGENT_HEIGHT
	nmesh.agent_max_climb = AGENT_MAX_CLIMB
	nmesh.agent_max_slope = AGENT_MAX_SLOPE
	# Alignées sur le cell_size/cell_height PAR DÉFAUT de la carte de navigation
	# du projet (0.25, non redéfini dans project.godot) : évite l'avertissement
	# de "mismatch" entre le navmesh et la NavigationMap.
	nmesh.cell_size = 0.25
	nmesh.cell_height = 0.25
	nav_region.navigation_mesh = nmesh
	# Bake SYNCHRONE (pas de thread) : le contrat exige le navmesh prêt avant
	# GameWorld._ready (qui peut faire spawn des bots la même frame).
	nav_region.bake_navigation_mesh(false)

## Pièces `type:"prop"` (dress pur — toujours `cover:false` dans les tables
## actuelles, jamais dans la navmesh, l'ordre par rapport au bake n'importe
## donc pas) : groupées par (nom, teinte, collide) puis fusionnées en UN
## SEUL MultiMeshInstance3D par groupe de >= 3 via `PropCatalog.place_many`
## (§8.17 "every prop used 3+ times is a MultiMesh" — un décor répété posé
## un par un, ex. les garde-corps le long de tout un bastingage, dépasse vite
## le budget de draw calls). `Kit.build_piece`'s propre branche "prop" pose
## toujours une instance isolée correctement (tests/maps/test_kit.gd) — elle
## reste juste inutilisée ici pour CE type de pièce, au profit du groupage.
func _build_props(parent: Node3D, pieces: Array, palette: Dictionary) -> void:
	var groups: Dictionary = {}
	for piece in pieces:
		var p: Dictionary = piece
		if String(p.get("type", "")) != "prop":
			continue
		var prop_name := String(p["prop"])
		var color_key := String(p.get("mat", p.get("color_key", "wall")))
		var base_color: Color = palette.get(color_key, Color.GRAY)
		var tint: Color = p.get("tint", base_color)
		var collide := bool(p.get("cover", true))
		var key := "%s|%s|%s" % [prop_name, tint.to_html(), collide]
		if not groups.has(key):
			groups[key] = {"prop": prop_name, "tint": tint, "collide": collide, "transforms": []}
		var pos: Vector3 = p["pos"]
		var rot: float = float(p.get("rot_y", 0.0))
		(groups[key]["transforms"] as Array).append(Transform3D(Basis(Vector3.UP, rot), pos))
	for key in groups.keys():
		var g: Dictionary = groups[key]
		var transforms: Array = g["transforms"]
		if transforms.size() >= 3:
			PropCatalog.place_many(parent, String(g["prop"]), transforms, g["tint"] as Color, bool(g["collide"]))
		else:
			for t in transforms:
				var xf: Transform3D = t
				PropCatalog.place(parent, String(g["prop"]), xf.origin, rad_to_deg(xf.basis.get_euler().y), g["tint"] as Color, bool(g["collide"]))

# ----------------------------------------------------------------------
#  Marqueurs (spawns, hardpoints, sites, zone de duel)
# ----------------------------------------------------------------------
func _build_markers(data: Dictionary) -> void:
	var palette: Dictionary = data["palette"]
	# Teinte de marque de la map (maps-spec.md §2 "Accent colours", C<=0.05)
	# sur les surbrillances de zone — un repli neutre si absente (arènes/tests
	# minimaux n'ont pas forcément 5 clés de palette).
	var accent: Color = palette.get("accent", Color(0.35, 0.35, 0.35))
	var spawn_root := Node3D.new()
	spawn_root.name = "SpawnPoints"
	add_child(spawn_root)
	var spawns: Dictionary = data["spawns"]
	for team in spawns.keys():
		var idx := 0
		for entry in (spawns[team] as Array):
			var s: Dictionary = entry
			var pos: Vector3 = s["pos"]
			var look: Vector3 = s.get("look", pos)
			var xf := Transform3D(Basis(), pos)
			if look.distance_to(pos) > 0.01:
				xf = xf.looking_at(look, Vector3.UP)
			var m := Marker3D.new()
			m.name = "%s%d" % ["T" if int(team) == 0 else "CT", idx + 1]
			m.transform = xf
			m.set_meta("team", int(team))
			spawn_root.add_child(m)
			idx += 1

	if data.has("hardpoints"):
		var hp_root := Node3D.new()
		hp_root.name = "HardpointPoints"
		add_child(hp_root)
		var i := 0
		for p in (data["hardpoints"] as Array):
			var m := Marker3D.new()
			m.name = "P%d" % (i + 1)
			m.position = p
			hp_root.add_child(m)
			i += 1
		_make_zone("Hardpoint", data["hardpoints"][0], Vector3(10, 4, 10), Color(0.88, 0.7, 0.25, 0.22), accent)

	if data.has("site_a"):
		var a: Dictionary = data["site_a"]
		_make_zone("SiteA", a["pos"], a["size"], Color(0.7, 0.35, 0.15, 0.22), accent)
	if data.has("site_b"):
		var b: Dictionary = data["site_b"]
		_make_zone("SiteB", b["pos"], b["size"], Color(0.7, 0.35, 0.15, 0.22), accent)
	if data.has("duel_zone"):
		var dz: Dictionary = data["duel_zone"]
		_make_zone("DuelZone", dz["pos"], dz["size"], Color(0.95, 0.75, 0.15, 0.16), accent)

func _make_zone(nm: String, pos: Vector3, size: Vector3, color: Color, accent: Color) -> Area3D:
	var area := Area3D.new()
	area.name = nm
	area.position = pos
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	area.add_child(col)
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mesh.mesh = bm
	var sm := StandardMaterial3D.new()
	sm.albedo_color = color
	sm.roughness = 0.95
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.emission_enabled = true
	sm.emission = Color(color.r, color.g, color.b).lerp(accent, 0.35)
	mesh.material_override = sm
	area.add_child(mesh)
	add_child(area)
	return area

# ----------------------------------------------------------------------
#  Mode de jeu : instancié depuis MatchConfig.mode_id, câblé aux marqueurs
#  (frères de GameMode sous MapSetup : les NodePath "../X" restent valides).
# ----------------------------------------------------------------------
func _build_game_mode(data: Dictionary) -> void:
	# Échange de côté (§5.6.2/§7.5) : TDM/Hardpoint seulement, et seulement
	# sur une map déclarée "asymmetric" (wasteland) — absent/faux sur toutes
	# les autres, comportement inchangé (v. TDMMode.gd/HardpointMode.gd).
	var asymmetric := bool(data.get("asymmetric", false))
	var mode: Node
	match MatchConfig.mode_id:
		"hardpoint":
			var hp := HardpointMode.new()
			hp.zone_path = NodePath("../Hardpoint")
			hp.points_path = NodePath("../HardpointPoints")
			hp.rotate_interval = 60.0
			hp.asymmetric_map = asymmetric
			mode = hp
		"snd":
			var snd := SnDMode.new()
			snd.site_a_path = NodePath("../SiteA")
			snd.site_b_path = NodePath("../SiteB")
			mode = snd
		"duel", "duo":
			var duel := DuelMode.new()
			duel.capture_zone_path = NodePath("../DuelZone")
			mode = duel
		_:
			var tdm := TDMMode.new()
			tdm.asymmetric_map = asymmetric
			mode = tdm
	mode.name = "GameMode"
	add_child(mode)
