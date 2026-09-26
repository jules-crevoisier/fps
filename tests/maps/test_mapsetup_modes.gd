## test_mapsetup_modes.gd
## Couvre `data["nav_links"]` (chutes/sauts hors de portée du bake automatique
## du navmesh, `MapSetup._build_nav_links`) : un `NavigationLink3D` par
## entrée, bidirectionnel ou non selon la donnée.
##
## Nettoyage du prototype 2026-09-26 (« strip to minimal prototype ») : ce
## fichier couvrait aussi les boîtes de zone (Hardpoint, SiteA, SiteB,
## DuelZone), construites par `MapSetup._build_markers` SELON LE MODE
## (Hardpoint/SnD/Duel/Duo) — ces modes, leurs marqueurs de zone et les 7
## cartes autres que Wasteland ont tous été supprimés avec eux (TDM/Wasteland
## seuls) : `_build_markers` ne construit plus aucune boîte de zone du tout,
## quel que soit le mode. Ces tests (§1 "zones selon le mode", §2 "emprise
## Hardpoint déclarée par zone") ont donc été retirés avec la fonctionnalité
## qu'ils couvraient — seul §3 (nav_links, orthogonal aux modes) survit.
extends GdUnitTestSuite

const MapSetupScript := preload("res://scripts/levels/maps/MapSetup.gd")

## `map_id` n'importe pas ici : `_build_nav_links` est appelé DIRECTEMENT,
## jamais via `_enter_tree`/`_data_for` -- aucune vraie donnée de carte n'est
## lue. Jamais ajouté à l'arbre.
func _fresh_setup() -> MapSetup:
	var setup := MapSetupScript.new()
	setup.map_id = "wasteland"
	auto_free(setup)
	return setup


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
	# Non-régression : aucune des cartes actuelles ne déclare "nav_links".
	var setup := _fresh_setup()
	setup._build_nav_links({})
	assert_array(_nav_links(setup)).is_empty()
