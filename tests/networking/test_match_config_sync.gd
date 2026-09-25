## test_match_config_sync.gd
## Spec BUG-02 (docs/audit/bugs.md) : un client qui rejoint doit charger le
## mode/la carte/la scène du SERVEUR, jamais sa propre sélection locale
## (`scripts/ui/MainMenu.gd:648-707` appliquait la config locale avant
## `change_scene_to_file` ; aucune synchro serveur->client de MatchConfig).
## Le serveur transmet mode_id/map_id/scène dans la réponse d'authentification
## ACCEPTÉE (NetworkManager.build_accept_payload) ; le client les extrait
## (parse_accept_payload) et les applique à MatchConfig AVANT de changer de
## scène (voir NetworkManager._client_apply_server_decision,
## MainMenu._resolve_start_scene). Toutes ces fonctions sont pures : testées
## ici sans pair réseau réel (voir server_join_smoke.gd pour la vérification
## 2-process de bout en bout sur un autre chemin du handshake).
extends GdUnitTestSuite


var _saved_mode_id: String
var _saved_map_id: String
var _saved_team_size: int


func before_test() -> void:
	# MatchConfig est statique (survit au changement de scène, voir son
	# commentaire d'en-tête) : sauvegarder/restaurer évite qu'un test qui le
	# modifie n'en pollue un autre de cette suite ou d'une suite voisine.
	_saved_mode_id = MatchConfig.mode_id
	_saved_map_id = MatchConfig.map_id
	_saved_team_size = MatchConfig.team_size


func after_test() -> void:
	MatchConfig.mode_id = _saved_mode_id
	MatchConfig.map_id = _saved_map_id
	MatchConfig.team_size = _saved_team_size


# =========================================================== MatchConfig.resolve_scene

func test_resolve_scene_uses_the_catalog_entry_for_a_known_map_id() -> void:
	var expected: String = str(MapCatalog.get_by_id("cargo_ship").get("scene", ""))
	assert_str(MatchConfig.resolve_scene("tdm", "cargo_ship")).is_equal(expected)


func test_resolve_scene_falls_back_to_the_mode_default_when_map_id_is_empty() -> void:
	var expected: String = str(MapCatalog.default_for("snd").get("scene", ""))
	assert_str(MatchConfig.resolve_scene("snd", "")).is_equal(expected)


func test_resolve_scene_falls_back_to_the_mode_default_when_map_id_is_unknown() -> void:
	var expected: String = str(MapCatalog.default_for("duel").get("scene", ""))
	assert_str(MatchConfig.resolve_scene("duel", "carte-inexistante")).is_equal(expected)


# ================================================ NetworkManager.build_accept_payload (serveur)

func test_build_accept_payload_is_accepted_and_carries_the_servers_mode_and_map() -> void:
	var reply := NetworkManager.build_accept_payload("hardpoint", "col_du_vautour")
	assert_bool(reply["ok"]).is_true()
	assert_str(reply["mode_id"]).is_equal("hardpoint")
	assert_str(reply["map_id"]).is_equal("col_du_vautour")


func test_build_accept_payload_resolves_the_scene_for_the_given_map() -> void:
	var reply := NetworkManager.build_accept_payload("tdm", "col_du_vautour")
	assert_str(reply["scene"]).is_equal(str(MapCatalog.get_by_id("col_du_vautour").get("scene", "")))


func test_build_accept_payload_resolves_the_mode_default_scene_with_an_empty_map_id() -> void:
	var reply := NetworkManager.build_accept_payload("duo", "")
	assert_str(reply["scene"]).is_equal(str(MapCatalog.default_for("duo").get("scene", "")))


# ================================================ NetworkManager.parse_accept_payload (client)

func test_parse_accept_payload_extracts_the_three_fields() -> void:
	var parsed := NetworkManager.parse_accept_payload({
		"ok": true,
		"mode_id": "snd",
		"map_id": "saint_ombre",
		"scene": "res://scenes/levels/maps/saint_ombre.tscn",
	})
	assert_str(parsed["mode_id"]).is_equal("snd")
	assert_str(parsed["map_id"]).is_equal("saint_ombre")
	assert_str(parsed["scene"]).is_equal("res://scenes/levels/maps/saint_ombre.tscn")


func test_parse_accept_payload_defaults_missing_fields_to_empty_strings() -> void:
	# Réponse malformée/tronquée (voir _client_apply_server_decision) : jamais
	# une erreur GDScript, juste des champs vides.
	var parsed := NetworkManager.parse_accept_payload({"ok": true})
	assert_str(parsed["mode_id"]).is_equal("")
	assert_str(parsed["map_id"]).is_equal("")
	assert_str(parsed["scene"]).is_equal("")


# ================================================ Sérialisation bout en bout (aller-retour JSON)

func test_accept_payload_round_trips_through_json_unchanged() -> void:
	var sent := NetworkManager.build_accept_payload("hardpoint", "wasteland")
	var wire: Variant = JSON.parse_string(JSON.stringify(sent))
	var received := NetworkManager.parse_accept_payload(wire as Dictionary)
	assert_str(received["mode_id"]).is_equal(sent["mode_id"])
	assert_str(received["map_id"]).is_equal(sent["map_id"])
	assert_str(received["scene"]).is_equal(sent["scene"])


# ================================================ BUG-02 : le client reçoit le choix du SERVEUR

## Reproduit le scénario du bug : le client avait choisi un mode/une carte
## dans SON propre menu (comme `MainMenu._apply_match_config()` le fait avant
## `_net.join()`), mais l'hôte a réellement lancé autre chose. Après le
## handshake (build_accept_payload côté serveur -> JSON -> parse_accept_payload
## côté client -> application à MatchConfig, exactement le chemin de
## `_client_apply_server_decision`), le client doit se retrouver avec le
## mode/la carte/la scène du SERVEUR, jamais sa sélection locale d'origine.
func test_client_ends_up_with_the_hosts_map_after_it_had_chosen_a_different_one() -> void:
	# Sélection locale du client avant de rejoindre.
	MatchConfig.set_mode("tdm")
	MatchConfig.map_id = "port_ferraille"

	# L'hôte joue en réalité une partie SnD sur Cargo Ship.
	var host_reply := NetworkManager.build_accept_payload("snd", "cargo_ship")
	var wire: Variant = JSON.parse_string(JSON.stringify(host_reply))
	var config := NetworkManager.parse_accept_payload(wire as Dictionary)

	# Application côté client (voir _client_apply_server_decision).
	MatchConfig.set_mode(str(config["mode_id"]))
	MatchConfig.map_id = str(config["map_id"])

	assert_str(MatchConfig.mode_id) \
		.append_failure_message("le client devrait charger le mode de l'hôte (snd), pas sa propre sélection (tdm)") \
		.is_equal("snd")
	assert_str(MatchConfig.map_id) \
		.append_failure_message("le client devrait charger la carte de l'hôte (cargo_ship), pas sa propre sélection (port_ferraille)") \
		.is_equal("cargo_ship")
	assert_str(str(config["scene"])).is_equal(str(MapCatalog.get_by_id("cargo_ship").get("scene", "")))


## Même scénario mais avec un mode qui change aussi la taille d'équipe
## (`MatchConfig.team_size_for`) : le client avait choisi TDM (4v4) mais
## l'hôte joue en Duel (1v1) — `team_size` doit lui aussi suivre le serveur.
func test_client_team_size_follows_the_hosts_mode_not_its_own() -> void:
	MatchConfig.set_mode("tdm")
	MatchConfig.map_id = ""
	assert_int(MatchConfig.team_size).is_equal(4)

	var host_reply := NetworkManager.build_accept_payload("duel", "la_fosse")
	var config := NetworkManager.parse_accept_payload(host_reply)
	MatchConfig.set_mode(str(config["mode_id"]))
	MatchConfig.map_id = str(config["map_id"])

	assert_int(MatchConfig.team_size).is_equal(1)
