## MapSetup.gd
## Construit une map à partir de `Layouts.data_for(map_id)` (contract-r3.md,
## interface croisée "Map scenes (R3-MAPS)") : géométrie + collision (Kit),
## marqueurs (SpawnPoints), la NavigationRegion3D bakée (groupe "nav_region"),
## et le nœud de mode "GameMode" (TDMMode). Tout se passe en `_enter_tree`,
## donc AVANT `GameWorld._ready` (qui spawn les joueurs/bots) : le contrat
## l'exige explicitement pour ce nœud.
##
## Nettoyage du prototype (2026-09-26, « strip to minimal prototype ») : TDM
## est désormais le SEUL mode (MatchConfig.MODES == ["tdm"]) — Hardpoint/SnD/
## Duel/Duo (HardpointMode/SnDMode/DuelMode/RoundMode/RoundState/HalfTime/
## Economy, et les marqueurs de zone qu'ils lisaient : HardpointPoints,
## Hardpoint, SiteA, SiteB, DuelZone) ont été supprimés — ces branches
## n'étaient déjà plus jamais atteintes en jeu (MatchConfig.set_mode()
## retombe toujours sur "tdm").
##
## LD-03 : en TDM, si la map déclare `tdm_spawns` (points neutres, seulement
## les cartes 4v4), `SpawnPoints` EST ces points-là (pas de nœud frère
## séparé) — c'est le seul moyen pour `GameWorld._get_spawn_position` (R3-IN,
## INCHANGÉ, lit toujours `spawn_points_root` = `"MapSetup/SpawnPoints"`) de
## les voir sans que GameWorld.gd ni les scènes de carte n'aient besoin de
## connaître le nom "TdmSpawnPoints". Toute map sans `tdm_spawns` (arènes,
## wasteland) garde le comportement historique : 4 points par équipe sous
## `SpawnPoints`, méta "team". Voir `_build_markers` pour le détail du
## routage.
##
## `data["nav_links"]` (chutes/sauts hors de portée du bake automatique) est
## posé en `NavigationLink3D`, un par entrée, bidirectionnel ou non selon la
## donnée (voir `_build_nav_links`) ; absent sur toute map qui ne le déclare
## pas, comportement inchangé.
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

## Capsule joueur (scenes/player/player.tscn) : radius 0.4, height 1.8. Le bake
## du navmesh (cell_size=cell_height=0.25, cf. `_build_geometry`) exige des
## agent_radius/agent_height MULTIPLES ENTIERS de ces cellules : sinon Godot
## les arrondit AU-DESSUS en silence (`bake_navigation_mesh` : "ceiled to
## cell_size/cell_height voxel units and loses precision", docs/audit/bots.md
## BOTFIX-03) — ce qui se produisait déjà avec 0.4/1.8 (1.6 et 7.2 cellules),
## donnant un rayon/hauteur effectifs de 0.5/2.0 SANS le dire. On rend ce
## comportement explicite (0.5 = 2 cellules, 2.0 = 8 cellules) au lieu de le
## subir : la géométrie de navmesh bakée est donc IDENTIQUE à l'ancienne
## (mêmes valeurs après arrondi), seul le warning disparaît, et on garde bien
## agent_radius/agent_height >= capsule réelle (jamais un bot qui passe là où
## un joueur ne passe pas).
const AGENT_RADIUS := 0.5
const AGENT_HEIGHT := 2.0
const AGENT_MAX_CLIMB := 0.5
const AGENT_MAX_SLOPE := 46.0

var nav_region: NavigationRegion3D

## Zones nommées (callouts, LD-04) — remplies dans `_enter_tree` depuis
## `data["callouts"]` (Layouts.gd : Array[{name: String, aabb: AABB}], même
## espace LOCAL à ce nœud que les autres positions de `Layouts.gd` : spawns,
## sites, hardpoints...). Vide tant que la map n'est pas construite, ou pour
## une map sans callouts déclarés (`callout_at` renvoie alors toujours "").
var _callouts: Array = []

## Repeint optionnel (maps-spec-v2.md §7) : `scripts/levels/maps/dressing/
## MapDressing.gd` pour les six maps v1. Absent => comportement 100% inchangé
## (aucune des fonctions ci-dessous n'est appelée). `for_map(map_id) -> Array` :
## entrées à poser via PropCatalog. `batches_for_map(map_id)`/`group_entries()`
## (TECH-08, `_build_dressing` ci-dessous) : regroupe ces mêmes entrées en
## `{singles, batches}` pour le chemin MultiMesh au-delà du seuil. `surface_kinds
## (map_id) -> Dictionary` (rôle -> kind peint Cartoon.painted) : fusionné dans
## la palette AVANT `_build_geometry` sous la clé "<rôle>_kind", lue par
## Kit.build_piece (voir Kit.gd §GeoBatcher).
const _DRESSING_PATH := "res://scripts/levels/maps/dressing/MapDressing.gd"

## Nettoyage du prototype 2026-09-26 (« strip to minimal prototype ») :
## Wasteland est désormais la SEULE carte — Cargo Ship, les six maps v1
## (`Layouts.gd`) et le snapshot gelé `wasteland_v3` (banc de comparaison
## bots v3<->v4) ont tous été supprimés avec leurs scènes/tests. Tout `id`
## autre que "wasteland" renvoie un dictionnaire vide, comme avant pour tout
## id inconnu de `Layouts.gd` (`_enter_tree` signale l'erreur "layout
## introuvable").
static func _data_for(id: String) -> Dictionary:
	if id == "wasteland":
		return _assemble_wasteland()
	return {}

## LD-20 "découpe en 5 fichiers" : `WastelandLayout.data()` (géométrie,
## spawns, hardpoints/sites, bounds/périmètre) reste la source — ce nœud
## fusionne par-dessus les données PURES des 3 autres fichiers de la carte
## (`WastelandMarkers.data()`, `WastelandBots.data()`, tous deux VIDES cette
## tâche, voir leur en-tête) et ajoute le décor pur de
## `WastelandDressing.entries()` (VIDE aussi) à `data["pieces"]`, exactement
## comme `_build_props` traite déjà toute pièce `type:"prop"` posée
## directement dans `wasteland.gd` (même contrat `cover`/`rot_y`/`tint`,
## aucun chemin supplémentaire). Tant que les 3 fichiers annexes sont vides,
## cette fonction ne change RIEN au comportement observable (mêmes clés,
## même Array `pieces`, dans le même ordre) — seule la STRUCTURE est en
## place pour les tâches suivantes (LD-21..LD-27) qui rempliront ces
## fichiers sans retoucher `wasteland.gd` ni `MapSetup.gd`.
## LD-40 (§12.6) : `WastelandMarkers`/`WastelandBots` sont ENCORE le contrat
## v3 (« restent à LD-41/LD-42 », hors de mon périmètre — je ne les touche
## pas) — `WastelandMarkers.data()["tdm_spawns"]` en particulier reste des
## coordonnées v3, alors que `MapSetup._build_markers` (ci-dessous) LIT
## directement cette clé pour construire les spawns réels de TDM/Hardpoint
## (donc CRITIQUE, pas un détail cosmétique comme `callouts`/
## `strong_positions`). Avant cette tâche, `WastelandLayout.data()` (v3, la
## SEULE source jusqu'ici) ne déclarait AUCUNE des clés que ces deux fichiers
## annexes fournissent : un écrasement inconditionnel ne changeait donc rien
## d'observable. Le contrat v4 (`wasteland.gd`) déclare DÉSORMAIS ses
## propres `tdm_spawns` (§9 "Marqueurs") — les laisser encore ÉCRASÉS
## romprait le blockout v4 (spawns TDM/Hardpoint téléportés sur la
## géométrie v3, hors des bornes 88 × 45 m de la v4) sans qu'aucun test de
## CE contrat ne le révèle autrement qu'en jeu. La fusion devient donc
## additive (ne comble QUE les clés absentes de `data`) : identique pour
## toute clé qu'aucune des deux versions de `WastelandLayout.data()` n'a
## jamais déclarée (`strong_positions`, `callouts`, `lanes`, `hotspots`,
## `hp_hold_points`, ...) — toujours fournie par les annexes, comportement
## inchangé ; mais n'écrase plus une clé que `wasteland.gd` choisit
## désormais de posséder lui-même.
static func _assemble_wasteland() -> Dictionary:
	var data := WastelandLayout.data()
	var markers := WastelandMarkers.data()
	for key in markers.keys():
		if not data.has(key):
			data[key] = markers[key]
	var bots := WastelandBots.data()
	for key in bots.keys():
		if not data.has(key):
			data[key] = bots[key]
	var dressing_pieces := WastelandDressing.entries()
	if not dressing_pieces.is_empty():
		(data["pieces"] as Array).append_array(dressing_pieces)
	return data

func _enter_tree() -> void:
	if nav_region != null:
		return  # déjà construit (garde-fou anti double appel)
	var data := _data_for(map_id)
	if data.is_empty():
		push_error("MapSetup : layout introuvable pour map_id=\"%s\"" % map_id)
		return
	_callouts = (data.get("callouts", []) as Array)

	var dressing: Variant = _load_dressing()
	if dressing != null:
		_merge_surface_kinds(data, dressing)

	_build_geometry(data)
	_build_nav_links(data)
	_build_kill_volumes(data)
	_build_perimeter(data)
	_build_markers(data)
	_build_game_mode(data)

	if dressing != null:
		_build_dressing(dressing)

	# Préchauffage des pipelines de rendu (TECH-01, docs/research/
	# 07_godot_tech.md §C2) : dernière étape, ne dépend d'aucune des
	# précédentes. Se détruit seul après quelques frames — voir
	# ShaderWarmup.gd.
	add_child(ShaderWarmup.new())

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

## TECH-08 (docs/research/07_godot_tech.md §C3) : emprunte le chemin
## MultiMesh de `MapDressing.batches_for_map()`/`group_entries()` — un groupe
## de plus de `MapDressing.MULTIMESH_THRESHOLD` répétitions identiques (même
## prop, même teinte, même `collide`) part en UN `PropCatalog.place_many()`
## (un draw call) plutôt qu'un `PropCatalog.place()` par exemplaire ; le reste
## (petits groupes et singletons, `grouped["singles"]`) garde le chemin
## `place()` inchangé — mêmes dictionnaires que `for_map()`, même contrat
## `rot_y_deg`/`rot_y`/`tint`/`collide` par défaut qu'avant ce chantier.
## `has_method` gardé partout (comme `surface_kinds`/`for_map` ci-dessus) :
## un `dressing` qui n'expose que `for_map()` (contrat minimal historique)
## retombe sur `group_entries()` local si dispo, sinon sur "tout en singles"
## — comportement identique à l'ancien code pour ce cas.
func _build_dressing(dressing) -> void:
	if not dressing.has_method("for_map"):
		return
	var grouped: Dictionary
	if dressing.has_method("batches_for_map"):
		grouped = dressing.batches_for_map(map_id)
	else:
		var entries: Array = dressing.for_map(map_id) as Array
		grouped = dressing.group_entries(entries) if dressing.has_method("group_entries") else {"singles": entries, "batches": []}

	for entry in (grouped["singles"] as Array):
		var d: Dictionary = entry
		var rot_y_deg: float = float(d.get("rot_y_deg", rad_to_deg(float(d.get("rot_y", 0.0)))))
		var tint: Color = d.get("tint", Color.WHITE)
		PropCatalog.place(self, String(d["prop"]), d["pos"], rot_y_deg, tint, bool(d.get("collide", true)))

	for batch in (grouped["batches"] as Array):
		var b: Dictionary = batch
		var batch_tint: Color = b.get("tint", Color.WHITE)
		PropCatalog.place_many(self, String(b["prop"]), b["transforms"] as Array, batch_tint, bool(b.get("collide", true)))

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
	# de "mismatch" entre le navmesh et la NavigationMap. AGENT_RADIUS/
	# AGENT_HEIGHT sont des multiples entiers de cette cellule (voir commentaire
	# au-dessus des constantes) : ne pas les redescendre à 0.4/1.8 sans changer
	# aussi cell_size, sous peine de réintroduire le warning "ceiled to
	# cell_size/cell_height voxel units and loses precision".
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
#  Liens de navigation déclarés par la carte (LD-22)
# ----------------------------------------------------------------------
## `NavigationLink3D` par entrée de `data["nav_links"]` (docs/research/
## 09_wasteland_vertical_slice.md §e "nav_links" : chutes, sauts, plongeons —
## des raccourcis que le bake automatique de `_build_geometry` ne peut PAS
## déduire seul, cf. `scripts/ai/BotBrain.gd` l.602 : « zéro NavigationLink3D
## dans tout le dépôt »). Absent (`data.has("nav_links")` faux) => comportement
## inchangé : aucune des 8 cartes actuelles ne déclare cette clé —
## `wasteland_bots.gd` (LD-24, hors de mon périmètre cette tâche) la
## remplira. Chaque entrée : `{"from": Vector3, "to": Vector3,
## "bidirectional": bool}` — `bidirectional` optionnel, replie sur `true`
## (même défaut que la propriété native `NavigationLink3D.bidirectional` :
## un lien qui NE précise rien reste franchissable dans les deux sens ;
## seul un lien EXPLICITEMENT à sens unique, ex. une chute qu'on ne remonte
## pas, déclare `"bidirectional": false`). Positions en espace LOCAL à ce
## nœud, même repère que les autres données de `Layouts.gd` (spawns, sites,
## hardpoints...) : `start_position`/`end_position` sont eux-mêmes relatifs
## au `Transform3D` du lien, laissé à l'identité (le nœud lui-même ne bouge
## jamais), donc `from`/`to` s'y écrivent directement sans conversion.
func _build_nav_links(data: Dictionary) -> void:
	if not data.has("nav_links"):
		return
	var i := 0
	for entry in (data["nav_links"] as Array):
		var d: Dictionary = entry
		var link := NavigationLink3D.new()
		link.name = "NavLink%d" % i
		link.start_position = d["from"] as Vector3
		link.end_position = d["to"] as Vector3
		link.bidirectional = bool(d.get("bidirectional", true))
		link.enabled = true
		add_child(link)
		i += 1

# ----------------------------------------------------------------------
#  Marqueurs (spawns, hardpoints, sites, zone de duel)
# ----------------------------------------------------------------------
func _build_markers(data: Dictionary) -> void:
	var spawns: Dictionary = data["spawns"]

	# LD-03 (docs/research/03_level_design.md §5, tests/maps/test_layouts.gd
	# §5.11 ; revue QA LD-03 : les 16-24 `tdm_spawns` posés plus bas dans
	# `Layouts.gd` finissaient sous un nœud frère "TdmSpawnPoints" que
	# personne ne lisait jamais — `GameWorld._get_spawn_position` (R3-IN,
	# HORS de mon périmètre, INCHANGÉ) lit TOUJOURS l'unique NodePath
	# `spawn_points_root`, fixé par CHAQUE scène de carte 4v4 (elles aussi
	# hors de mon périmètre) à `"MapSetup/SpawnPoints"` — jamais
	# "TdmSpawnPoints". Router ICI, dans `MapSetup`, est donc le SEUL point
	# d'intégration possible sans toucher `GameWorld.gd` ni les scènes
	# (propriété d'autres tâches, cf. contrat "ne touche à aucun fichier hors
	# de ta liste") : ce nœud est le seul à connaître À LA FOIS
	# `MatchConfig.mode_id` (déjà lu juste après par `_build_game_mode`,
	# MÊME `_enter_tree`, donc TOUJOURS synchronisé avec le mode réellement
	# instancié) et les deux jeux de points, construits ici.
	#
	# TDM (mode à spawn neutre — seul mode restant après le nettoyage du
	# prototype 2026-09-26, Hardpoint supprimé) ET la map en déclare
	# (`tdm_spawns`, uniquement les cartes 4v4 - absent des arènes/wasteland
	# v7 greybox, qui gardent alors le comportement historique ci-dessous) :
	# `SpawnPoints` lui-même devient les points NEUTRES (aucune méta "team" ->
	# `GameWorld._get_spawn_position` retombe sur "team_points = points" ->
	# `SpawnPick.pick_best`, LD-02, choisit dynamiquement parmi eux, quel que
	# soit le camp).
	var use_neutral_spawns := data.has("tdm_spawns") and MatchConfig.mode_id == "tdm"

	var spawn_root := Node3D.new()
	spawn_root.name = "SpawnPoints"
	add_child(spawn_root)

	if use_neutral_spawns:
		var n := 0
		for entry in (data["tdm_spawns"] as Array):
			var s: Dictionary = entry
			var pos: Vector3 = s["pos"]
			var look: Vector3 = s.get("look", pos)
			var xf := Transform3D(Basis(), pos)
			if look.distance_to(pos) > 0.01:
				xf = xf.looking_at(look, Vector3.UP)
			var m := Marker3D.new()
			m.name = "N%d" % (n + 1)
			m.transform = xf
			spawn_root.add_child(m)
			n += 1
	else:
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

	# Boîtes de zone (Hardpoint, SiteA/SiteB, DuelZone) : supprimées avec les
	# modes qui les câblaient (nettoyage du prototype 2026-09-26, TDM seul —
	# voir MatchConfig.MODES). `accent` (palette) ne sert donc plus ici.

# ----------------------------------------------------------------------
#  Callouts (LD-04) : repère "où suis-je ?" (docs/research/03_level_design.md
#  §2.7/§4 — aucune minimap ni callout n'existait avant cette tâche).
# ----------------------------------------------------------------------
## Nom de la zone déclarée (`Layouts.gd` : `data["callouts"]`) qui contient
## `pos` — espace LOCAL à CE nœud, le même que les autres positions de
## `Layouts.gd` (spawns, sites, hardpoints...), donc PAS forcément l'espace
## monde si ce `MapSetup` est lui-même déplacé (ex. tests isolant plusieurs
## maps par un décalage, `tests/maps/test_navmesh.gd::_setup_map`). Renvoie
## la première zone dont l'`AABB` contient `pos` (les zones ne se chevauchent
## pas dans les tables actuelles), ou "" si aucune (hors de toute zone
## déclarée, ou map/instance pas encore construite).
func callout_at(pos: Vector3) -> String:
	for entry in _callouts:
		var zone: Dictionary = entry
		var box: AABB = zone["aabb"]
		if box.has_point(pos):
			return String(zone["name"])
	return ""

# ----------------------------------------------------------------------
#  Mode de jeu : instancié depuis MatchConfig.mode_id, câblé aux marqueurs
#  (frères de GameMode sous MapSetup : les NodePath "../X" restent valides).
# ----------------------------------------------------------------------
func _build_game_mode(data: Dictionary) -> void:
	# TDM SEUL (nettoyage du prototype 2026-09-26, « strip to minimal
	# prototype » — voir MatchConfig.MODES) : Hardpoint/SnD/Duel/Duo
	# (HardpointMode/SnDMode/DuelMode/RoundMode/RoundState/HalfTime/Economy)
	# sont supprimés, cette branche ne construisait plus jamais qu'un TDMMode
	# en pratique (MatchConfig.set_mode() retombe toujours sur "tdm" pour tout
	# id absent de MatchConfig.MODES == ["tdm"]).
	# Échange de côté (§5.6.2/§7.5) : seulement sur une map déclarée
	# "asymmetric" (wasteland) — absent/faux sur toutes les autres,
	# comportement inchangé.
	var tdm := TDMMode.new()
	tdm.asymmetric_map = bool(data.get("asymmetric", false))
	tdm.name = "GameMode"
	add_child(tdm)
