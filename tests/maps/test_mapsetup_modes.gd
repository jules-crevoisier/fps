## test_mapsetup_modes.gd
## LD-22 (docs/research/09_wasteland_vertical_slice.md §b.2 "V9", §c.5, §e
## "nav_links") : couvre le contrat de `MapSetup.gd` qu'aucun autre fichier de
## test ne vérifie —
##  1. les boîtes de zone (Hardpoint, SiteA, SiteB, DuelZone) ne sont
##     construites QUE pour le mode qui les câble réellement dans
##     `_build_game_mode` (corrige V9 : « Les boîtes de zone translucides
##     (Hardpoint, sites A et B) sont visibles en TDM ») ;
##  2. la zone Hardpoint prend l'emprise DÉCLARÉE PAR ZONE
##     (`data["hardpoint_sizes"]`, Array PARALLÈLE à `data["hardpoints"]`),
##     avec repli sur l'ancienne taille fixe 10x4x10 si absente ;
##  3. `data["nav_links"]` devient un `NavigationLink3D` par entrée,
##     bidirectionnel ou non selon la donnée.
##
## §1 s'exerce sur les VRAIES cartes, via `_enter_tree` (même patron que
## `tests/maps/test_layouts.gd::_build_map_setup_for_mode`, §5.12). Aucune
## des 8 cartes actuelles ne déclare `hardpoint_sizes`/`nav_links` (ces clés
## arrivent avec LD-21/LD-24, `wasteland_markers.gd`/`wasteland_bots.gd`,
## hors de mon périmètre cette tâche) : §2 et §3 s'exercent donc sur des
## données SYNTHÉTIQUES, en appelant `_build_markers`/`_build_nav_links`
## directement sur un `MapSetup` frais jamais ajouté à l'arbre — même patron
## que `tests/maps/test_dressing_lod.gd` (« _build_dressing() ne touche que
## self/map_id : un Node3D frais, jamais ajouté à l'arbre... suffit »).
extends GdUnitTestSuite

const MapSetupScript := preload("res://scripts/levels/maps/MapSetup.gd")

## Cartes qui déclarent hardpoints + site_a + site_b : les 4 villes 4v4
## (Layouts.gd) + cargo_ship (hors de Layouts.MAP_IDS, routée par
## MapSetup._data_for). Wasteland RETIRÉE de cette liste (2026-09-26, « fais
## la carte block que je puisse la tester in game » — v7 greybox, TDM seul,
## voir l'en-tête de `scripts/levels/maps/layouts/wasteland.gd`) :
## `WastelandLayout.data()` ne déclare plus `hardpoints`/`site_a`/`site_b`/
## `duel_zone` du tout, donc `MapSetup._build_markers` ne construit plus ces
## zones pour elle QUEL QUE SOIT le mode — ce n'est plus « une carte de
## zones » au sens de ce test. Écart connu, signalé au rendu de tâche :
## `MapCatalog.gd` annonce encore Wasteland pour "hardpoint"/"snd" (hors de
## mon périmètre de fichiers cette manche).
const ZONE_MAP_IDS := ["port_ferraille", "val_poussiere", "saint_ombre", "col_du_vautour", "cargo_ship"]

## Arènes Duel/Duo : seule donnée de zone = duel_zone (Layouts.gd).
const DUEL_ARENA_IDS := ["la_fosse", "le_belvedere"]

var _next_offset_index := 0


# ======================================================================
#  §1 — Zones construites SELON LE MODE (V9), sur les vraies cartes.
# ======================================================================
func _build_map_setup_for_mode(map_id: String, mode_id: String) -> MapSetup:
	MatchConfig.mode_id = mode_id
	var setup := MapSetupScript.new()
	setup.map_id = map_id
	setup.position = Vector3(float(_next_offset_index) * 600.0, 0.0, 0.0)
	_next_offset_index += 1
	add_child(setup)
	return setup


func _teardown(setup: Node) -> void:
	remove_child(setup)
	setup.free()
	await get_tree().physics_frame


func test_tdm_builds_no_hardpoint_or_site_zone_boxes() -> void:
	var previous_mode := MatchConfig.mode_id
	for id in ZONE_MAP_IDS:
		var setup := _build_map_setup_for_mode(id, "tdm")
		for nm in ["Hardpoint", "HardpointPoints", "SiteA", "SiteB", "DuelZone"]:
			assert_object(setup.get_node_or_null(nm)).append_failure_message(
				"%s (TDM) : le nœud \"%s\" existe encore -- V9 (boîte de zone visible en TDM) non corrigé" % [id, nm]
			).is_null()
		await _teardown(setup)
	MatchConfig.mode_id = previous_mode


func test_hardpoint_mode_builds_only_the_hardpoint_zone() -> void:
	var previous_mode := MatchConfig.mode_id
	for id in ZONE_MAP_IDS:
		var setup := _build_map_setup_for_mode(id, "hardpoint")
		assert_object(setup.get_node_or_null("Hardpoint")).append_failure_message(
			"%s (Hardpoint) : pas de zone \"Hardpoint\" -- HardpointMode.zone_path ne trouverait rien" % id
		).is_not_null()
		assert_object(setup.get_node_or_null("HardpointPoints")).append_failure_message(
			"%s (Hardpoint) : pas de nœud \"HardpointPoints\" -- HardpointMode.points_path ne trouverait rien" % id
		).is_not_null()
		for nm in ["SiteA", "SiteB", "DuelZone"]:
			assert_object(setup.get_node_or_null(nm)).append_failure_message(
				"%s (Hardpoint) : le nœud \"%s\" ne devrait pas exister dans ce mode" % [id, nm]
			).is_null()
		await _teardown(setup)
	MatchConfig.mode_id = previous_mode


func test_snd_mode_builds_only_the_two_site_zones() -> void:
	var previous_mode := MatchConfig.mode_id
	for id in ZONE_MAP_IDS:
		var setup := _build_map_setup_for_mode(id, "snd")
		assert_object(setup.get_node_or_null("SiteA")).append_failure_message(
			"%s (SnD) : pas de zone \"SiteA\" -- SnDMode.site_a_path ne trouverait rien" % id
		).is_not_null()
		assert_object(setup.get_node_or_null("SiteB")).append_failure_message(
			"%s (SnD) : pas de zone \"SiteB\" -- SnDMode.site_b_path ne trouverait rien" % id
		).is_not_null()
		for nm in ["Hardpoint", "HardpointPoints", "DuelZone"]:
			assert_object(setup.get_node_or_null(nm)).append_failure_message(
				"%s (SnD) : le nœud \"%s\" ne devrait pas exister dans ce mode" % [id, nm]
			).is_null()
		await _teardown(setup)
	MatchConfig.mode_id = previous_mode


func test_duel_and_duo_modes_build_only_the_duel_zone() -> void:
	var previous_mode := MatchConfig.mode_id
	for id in DUEL_ARENA_IDS:
		for mode_id in ["duel", "duo"]:
			var setup := _build_map_setup_for_mode(id, mode_id)
			assert_object(setup.get_node_or_null("DuelZone")).append_failure_message(
				"%s (%s) : pas de zone \"DuelZone\" -- DuelMode.capture_zone_path ne trouverait rien" % [id, mode_id]
			).is_not_null()
			for nm in ["Hardpoint", "HardpointPoints", "SiteA", "SiteB"]:
				assert_object(setup.get_node_or_null(nm)).append_failure_message(
					"%s (%s) : le nœud \"%s\" ne devrait pas exister sur une arène Duel/Duo" % [id, mode_id, nm]
				).is_null()
			await _teardown(setup)
	MatchConfig.mode_id = previous_mode


func test_arenas_in_tdm_have_no_duel_zone_box_either() -> void:
	# Symétrique des tests précédents : même une arène (sans hardpoints ni
	# sites) ne doit garder aucune boîte visible hors de son propre mode.
	var previous_mode := MatchConfig.mode_id
	for id in DUEL_ARENA_IDS:
		var setup := _build_map_setup_for_mode(id, "tdm")
		assert_object(setup.get_node_or_null("DuelZone")).append_failure_message(
			"%s (TDM) : le nœud \"DuelZone\" existe encore" % id
		).is_null()
		await _teardown(setup)
	MatchConfig.mode_id = previous_mode


# ======================================================================
#  §2 — Emprise HP déclarée PAR ZONE (data["hardpoint_sizes"]), sur données
#  synthétiques : aucune des 8 cartes actuelles ne déclare cette clé (elle
#  arrivera avec LD-21, wasteland_markers.gd, hors de mon périmètre) --
#  la verrouiller ici fixe le CONTRAT que MapSetup doit honorer dès qu'une
#  carte la déclarera, sans dépendre d'un fichier hors de ma liste.
# ======================================================================
static func _palette() -> Dictionary:
	return {"accent": Color(0.5, 0.5, 0.5)}


static func _spawns() -> Dictionary:
	return {
		0: [{"pos": Vector3(-10.0, 1.0, 0.0), "look": Vector3(-5.0, 1.0, 0.0)}],
		1: [{"pos": Vector3(10.0, 1.0, 0.0), "look": Vector3(5.0, 1.0, 0.0)}],
	}


## `map_id` n'importe pas ici : `_build_markers` est appelé DIRECTEMENT,
## jamais via `_enter_tree`/`_data_for` -- aucune vraie donnée de carte n'est
## lue. Jamais ajouté à l'arbre (voir en-tête de fichier).
func _fresh_setup() -> MapSetup:
	var setup := MapSetupScript.new()
	setup.map_id = "wasteland"
	auto_free(setup)
	return setup


## `zone` a TROIS enfants une fois posée par `_build_markers` : la collision
## de la boîte, son `MeshInstance3D` (le `BoxMesh` translucide), et le
## décalque "H" au sol (`SiteDecals.place_hardpoint_letter`, LUI-MÊME un
## `MeshInstance3D`, nommé "HardpointDecal", sur un `QuadMesh` -- PAS un
## `BoxMesh`). On distingue le mesh de la BOÎTE du décalque par son `mesh`
## (`BoxMesh`), jamais par le seul type de nœud `MeshInstance3D`.
func _hardpoint_zone_box(setup: MapSetup) -> Dictionary:
	var zone := setup.get_node_or_null("Hardpoint") as Area3D
	assert_object(zone).append_failure_message("pas de nœud \"Hardpoint\" construit").is_not_null()
	var col: CollisionShape3D = null
	var mesh: MeshInstance3D = null
	for child in zone.get_children():
		if child is CollisionShape3D:
			col = child
		elif child is MeshInstance3D and (child as MeshInstance3D).mesh is BoxMesh:
			mesh = child
	assert_object(col).append_failure_message("pas de CollisionShape3D sous \"Hardpoint\"").is_not_null()
	assert_object(mesh).append_failure_message("pas de MeshInstance3D (BoxMesh) sous \"Hardpoint\"").is_not_null()
	return {"collision_size": (col.shape as BoxShape3D).size, "mesh_size": (mesh.mesh as BoxMesh).size}


func test_hardpoint_zone_uses_the_size_declared_for_its_own_zone() -> void:
	var previous_mode := MatchConfig.mode_id
	MatchConfig.mode_id = "hardpoint"
	var setup := _fresh_setup()
	var data := {
		"palette": _palette(),
		"spawns": _spawns(),
		"hardpoints": [Vector3(0.5, 1.5, -8.5), Vector3(-13.0, 1.5, 1.0), Vector3(14.0, 1.5, 6.0)],
		# §c.5 : Grue (index 0, la SEULE zone réellement construite -- une
		# unique Area3D, voir MapSetup._build_markers) = 9x7x9, jamais la
		# taille générique 10x4x10 qui servait pour toute la carte avant LD-22.
		"hardpoint_sizes": [Vector3(9.0, 7.0, 9.0), Vector3(9.0, 4.0, 9.0), Vector3(10.0, 4.0, 8.0)],
	}
	setup._build_markers(data)
	var box := _hardpoint_zone_box(setup)
	assert_vector(box["collision_size"] as Vector3).append_failure_message(
		"emprise Hardpoint=%s, attendu (9,7,9) (hardpoint_sizes[0], PAS la taille générique 10x4x10)" % [box["collision_size"]]
	).is_equal_approx(Vector3(9.0, 7.0, 9.0), Vector3.ONE * 0.001)
	assert_vector(box["mesh_size"] as Vector3).append_failure_message(
		"le mesh visuel de la zone Hardpoint doit suivre la même emprise que sa collision"
	).is_equal_approx(Vector3(9.0, 7.0, 9.0), Vector3.ONE * 0.001)
	MatchConfig.mode_id = previous_mode


func test_hardpoint_zone_falls_back_to_the_fixed_size_when_undeclared() -> void:
	# Non-régression : les 8 cartes actuelles ne déclarent PAS
	# "hardpoint_sizes" -- l'emprise doit rester EXACTEMENT 10x4x10
	# (tests/maps/test_dressing.gd en dépend : "Hardpoint zones are 10x4x10").
	var previous_mode := MatchConfig.mode_id
	MatchConfig.mode_id = "hardpoint"
	var setup := _fresh_setup()
	var data := {
		"palette": _palette(),
		"spawns": _spawns(),
		"hardpoints": [Vector3(0.0, 1.5, 0.0)],
	}
	setup._build_markers(data)
	var box := _hardpoint_zone_box(setup)
	assert_vector(box["collision_size"] as Vector3).append_failure_message(
		"sans \"hardpoint_sizes\", l'emprise doit rester 10x4x10 (repli historique)"
	).is_equal_approx(Vector3(10.0, 4.0, 10.0), Vector3.ONE * 0.001)
	MatchConfig.mode_id = previous_mode


# ======================================================================
#  §3 — nav_links : NavigationLink3D par entrée, bidirectionnel ou non.
# ======================================================================
func _nav_links(setup: MapSetup) -> Array:
	var out: Array = []
	for child in setup.get_children():
		if child is NavigationLink3D:
			out.append(child)
	return out


func test_nav_links_are_created_as_navigation_link_3d_nodes() -> void:
	var setup := _fresh_setup()
	var data := {
		"nav_links": [
			# §e : toit FUEL -> place (6,4 m de chute), sens non précisé --
			# doit rester franchissable dans les deux sens (défaut natif).
			{"from": Vector3(0.0, 6.4, -17.5), "to": Vector3(0.0, 0.0, -13.0)},
			# §e : plongeon Réservoir -> toit du hangar, sens UNIQUE déclaré.
			{"from": Vector3(0.5, 6.7, -8.5), "to": Vector3(0.5, 3.2, -8.5), "bidirectional": false},
		],
	}
	setup._build_nav_links(data)
	var links := _nav_links(setup)
	assert_int(links.size()).append_failure_message("attendu 2 NavigationLink3D, un par entrée de \"nav_links\"").is_equal(2)

	var first := links[0] as NavigationLink3D
	assert_vector(first.start_position).is_equal_approx(Vector3(0.0, 6.4, -17.5), Vector3.ONE * 0.001)
	assert_vector(first.end_position).is_equal_approx(Vector3(0.0, 0.0, -13.0), Vector3.ONE * 0.001)
	assert_bool(first.bidirectional).append_failure_message(
		"sans \"bidirectional\" déclaré, le lien doit rester bidirectionnel (défaut natif de NavigationLink3D)"
	).is_true()

	var second := links[1] as NavigationLink3D
	assert_vector(second.start_position).is_equal_approx(Vector3(0.5, 6.7, -8.5), Vector3.ONE * 0.001)
	assert_vector(second.end_position).is_equal_approx(Vector3(0.5, 3.2, -8.5), Vector3.ONE * 0.001)
	assert_bool(second.bidirectional).append_failure_message(
		"\"bidirectional\": false doit produire un lien à SENS UNIQUE"
	).is_false()


func test_nav_links_absent_leaves_no_navigation_link_3d_node() -> void:
	# Non-régression : aucune des 8 cartes actuelles ne déclare "nav_links".
	var setup := _fresh_setup()
	setup._build_nav_links({})
	assert_array(_nav_links(setup)).is_empty()
