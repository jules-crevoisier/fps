## test_map_catalog.gd
## Spec (brief lead 2026-09-28, Canyon Express) : MapCatalog porte désormais
## DEUX cartes -- Shipment (scène présente) et Canyon Express (scène pas
## encore livrée, art/collision Blender du lead en cours). `default_for`
## continue de retomber sur Shipment. `catalog_has_scene`/`selectable`
## laissent le sélecteur de carte du salon dégrader proprement tant que
## `canyon_express.tscn` n'existe pas. `look_for` généralise le gating
## LevelLook.gd (`map_id == "shipment"` -> `look == "toon"`).
extends GdUnitTestSuite


func test_catalog_lists_shipment_and_canyon_express_in_order() -> void:
	var all := MapCatalog.all()
	assert_int(all.size()).is_equal(2)
	assert_str(str(all[0]["id"])).is_equal("shipment")
	assert_int(int(all[0]["number"])).is_equal(1)
	assert_str(str(all[1]["id"])).is_equal("canyon_express")
	assert_int(int(all[1]["number"])).is_equal(2)


func test_canyon_express_entry_matches_the_locked_contract() -> void:
	var entry := MapCatalog.get_by_id("canyon_express")
	assert_bool(entry.is_empty()).is_false()
	assert_str(str(entry["name"])).is_equal("Canyon Express")
	assert_str(str(entry["scene"])).is_equal("res://scenes/levels/maps/canyon_express.tscn")
	assert_str(str(entry["size"])).is_equal("4v4")
	assert_bool(bool(entry["asymmetric"])).is_false()
	assert_array(entry["modes"] as Array).contains("tdm")


func test_both_entries_declare_a_toon_look() -> void:
	assert_str(str(MapCatalog.get_by_id("shipment")["look"])).is_equal("toon")
	assert_str(str(MapCatalog.get_by_id("canyon_express")["look"])).is_equal("toon")


func test_default_for_tdm_is_still_shipment() -> void:
	assert_str(str(MapCatalog.default_for("tdm")["id"])).is_equal("shipment")


# --------------------------------------------------------------- look_for()

func test_look_for_known_toon_maps() -> void:
	assert_str(MapCatalog.look_for("shipment")).is_equal("toon")
	assert_str(MapCatalog.look_for("canyon_express")).is_equal("toon")


func test_look_for_unknown_or_empty_id_is_empty_string() -> void:
	assert_str(MapCatalog.look_for("")).is_equal("")
	assert_str(MapCatalog.look_for("does_not_exist")).is_equal("")
	# Cartes legacy (v1, retirées du catalogue mais encore un id d'ambiance
	# valide -- voir Audio.gd) : jamais "toon", comportement historique
	# (pipeline Cartoon/ink_toon) inchangé.
	assert_str(MapCatalog.look_for("port_ferraille")).is_equal("")


# ----------------------------------------------------- catalog_has_scene()/selectable()

func test_catalog_has_scene_is_true_for_shipment() -> void:
	assert_bool(MapCatalog.catalog_has_scene("shipment")).is_true()


func test_catalog_has_scene_is_false_for_canyon_express_until_its_scene_lands() -> void:
	# Le lead modélise encore Canyon Express en parallèle (Blender) --
	# aucune scene .tscn n'existe encore sous ce nom. Le jour où elle
	# existe, ce test (et selectable(), ci-dessous) basculent tout seuls.
	assert_bool(MapCatalog.catalog_has_scene("canyon_express")).is_equal(
		ResourceLoader.exists("res://scenes/levels/maps/canyon_express.tscn"))


func test_catalog_has_scene_is_false_for_an_unknown_id() -> void:
	assert_bool(MapCatalog.catalog_has_scene("does_not_exist")).is_false()


func test_selectable_only_lists_maps_whose_scene_exists() -> void:
	var selectable := MapCatalog.selectable()
	for entry in selectable:
		assert_bool(ResourceLoader.exists(str(entry["scene"]))).append_failure_message(
			"selectable() a renvoyé une carte sans scène : %s" % entry["id"]
		).is_true()
	# Shipment est TOUJOURS sélectionnable (sa scène est bien réelle) --
	# Canyon Express ne l'est que si sa scène a fini par être livrée.
	var ids: Array = []
	for entry in selectable:
		ids.append(str(entry["id"]))
	assert_array(ids).contains("shipment")
	if not ResourceLoader.exists("res://scenes/levels/maps/canyon_express.tscn"):
		assert_bool(ids.has("canyon_express")).is_false()
