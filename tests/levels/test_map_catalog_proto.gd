## test_map_catalog_proto.gd
## Spec UX-37 (retour lead 2026-09-25, §3 « PROTO = UNE CARTE ») : hors mode
## dev, MapCatalog.all() ne liste que Wasteland — les 7 autres cartes restent
## définies dans le code (get_by_id/all(true) les retrouvent encore), et
## Wasteland devient la carte par défaut pour chacun des modes qu'elle
## supporte (tdm/hardpoint/snd). Duel/Duo, qu'elle ne couvre pas, gardent leur
## propre carte de duel (la_fosse/le_belvédère).
extends GdUnitTestSuite

const _OTHER_MAP_IDS := [
	"port_ferraille", "val_poussiere", "saint_ombre",
	"col_du_vautour", "la_fosse", "le_belvedere", "cargo_ship",
]

var _saved_proto_single_map: bool


func before_test() -> void:
	_saved_proto_single_map = MapCatalog.proto_single_map
	MapCatalog.proto_single_map = true


func after_test() -> void:
	MapCatalog.proto_single_map = _saved_proto_single_map


# ================================================ all() — proto à une seule carte

func test_all_lists_only_wasteland_while_the_proto_flag_is_on() -> void:
	var maps := MapCatalog.all()

	assert_int(maps.size()).append_failure_message(
		"proto_single_map actif : MapCatalog.all() ne doit lister que Wasteland (retour lead 2026-09-25 « une seule map finie »)"
	).is_equal(1)
	assert_str(str(maps[0].get("id", ""))).is_equal("wasteland")


func test_all_true_bypasses_the_proto_filter_for_dev_tools() -> void:
	var maps := MapCatalog.all(true)

	assert_int(maps.size()).append_failure_message(
		"all(true) (mode dev) doit voir le catalogue complet malgré proto_single_map"
	).is_equal(8)


func test_disabling_the_proto_flag_restores_the_full_catalog() -> void:
	MapCatalog.proto_single_map = false

	assert_int(MapCatalog.all().size()).append_failure_message(
		"proto_single_map désactivé : MapCatalog.all() doit redevenir le catalogue complet"
	).is_equal(8)


# ================================================ les autres cartes restent dans le code

func test_the_other_maps_stay_defined_in_code_and_reachable_by_id() -> void:
	for id in _OTHER_MAP_IDS:
		assert_bool(MapCatalog.get_by_id(id).is_empty()).append_failure_message(
			"la carte « %s » doit rester définie dans le code (get_by_id), même hors du menu proto" % id
		).is_false()


func test_get_by_id_is_never_filtered_by_the_proto_flag() -> void:
	# D'autres suites (ex. tests/networking/test_match_config_sync.gd, hors de
	# mon périmètre) comparent leurs attentes à MapCatalog.get_by_id("cargo_ship")
	# etc. : ce lookup ne doit JAMAIS se vider à cause du proto.
	for id in _OTHER_MAP_IDS:
		var before := MapCatalog.get_by_id(id)
		MapCatalog.proto_single_map = false
		var after := MapCatalog.get_by_id(id)
		MapCatalog.proto_single_map = true
		assert_str(str(before.get("scene", ""))).is_equal(str(after.get("scene", "")))


# ================================================ default_for() — Wasteland par défaut

func test_default_for_prefers_wasteland_for_every_mode_it_supports() -> void:
	for mode_id in ["tdm", "hardpoint", "snd"]:
		assert_str(str(MapCatalog.default_for(mode_id).get("id", ""))).append_failure_message(
			"la carte par défaut du mode « %s » doit être Wasteland (retour lead : « pas besoin d'autres map »)" % mode_id
		).is_equal("wasteland")


func test_default_for_falls_back_to_a_duel_sized_map_for_modes_wasteland_does_not_support() -> void:
	# Wasteland (4v4, asymétrique) ne déclare pas "duel"/"duo" dans ses modes —
	# le défaut de ces deux modes doit rester une VRAIE carte de duel, jamais
	# Wasteland ni un repli vide.
	for mode_id in ["duel", "duo"]:
		var entry := MapCatalog.default_for(mode_id)
		assert_str(str(entry.get("id", ""))).is_not_equal("wasteland")
		assert_str(str(entry.get("size", ""))).append_failure_message(
			"Wasteland (4v4) ne couvre pas « %s » — le défaut doit rester une carte de duel" % mode_id
		).is_equal("duel")


func test_default_for_still_works_when_the_proto_flag_is_disabled() -> void:
	MapCatalog.proto_single_map = false

	assert_str(str(MapCatalog.default_for("tdm").get("id", ""))).is_equal("wasteland")
