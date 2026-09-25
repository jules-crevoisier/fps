## join_sync_smoke.gd
## Test réseau à DEUX processus (hôte + client) qui reproduit BUG-02
## (docs/audit/bugs.md, corrigé par NetworkManager.build_accept_payload /
## _client_apply_server_decision) : l'hôte lance la partie sur la carte A ;
## le client, qui avait fait SA PROPRE sélection locale (carte B, à l'écran
## "Jouer" avant de cliquer "Rejoindre" — MainMenu._apply_match_config), doit
## charger la carte de l'HÔTE (A), jamais la sienne (B), une fois connecté.
## Emprunte exactement le même chemin que le vrai jeu (MainMenu._start_game
## -> get_tree().change_scene_to_file(_resolve_start_scene())) : aucun
## raccourci de test, on vérifie la SCÈNE RÉELLEMENT chargée, pas seulement
## les champs de NetworkManager/MatchConfig (déjà couverts, hors réseau réel,
## par tests/networking/test_match_config_sync.gd).
##
##   Hôte   : godot --headless --path . -s res://tools/review/join_sync_smoke.gd -- --role=host
##   Client : godot --headless --path . -s res://tools/review/join_sync_smoke.gd -- --role=client --out=DIR
##
## Comme tools/net_smoke.gd (un seul rôle "juge" le résultat), c'est ici le
## CLIENT qui écrit "<out>/join_sync_smoke.json" ({"checks":[{"name","ok",
## "detail"}]}) et porte le code de sortie 0/1 — c'est SON comportement
## (charge-t-il la bonne carte ?) qui est sous test, l'hôte n'a aucun moyen
## d'observer l'état local du client. L'hôte, lui, reste hébergé jusqu'à
## HOST_TIMEOUT puis quitte 0 sans condition (rôle passif, comme le CLIENT de
## net_smoke.gd) — il doit démarrer AVANT le client (même contrainte que
## net_smoke.gd, voir Step-NetSmoke/run_review.ps1 : ~1 s d'avance).
extends SceneTree

const DEFAULT_OUT := "res://.probe_out"
const MODE_ID := "tdm"
## Deux cartes 4v4/tdm distinctes du catalogue (scripts/levels/maps/MapCatalog.gd).
const MAP_A := "port_ferraille"  ## carte de l'HÔTE — celle qui doit être chargée.
const MAP_B := "val_poussiere"   ## sélection LOCALE du client avant de rejoindre — ne doit JAMAIS être chargée.

const HOST_TIMEOUT := 15.0
## Doit rester nettement sous HOST_TIMEOUT : l'hôte doit toujours être encore
## là quand le client termine ses vérifications (sinon `server_disconnected`
## bascule le client sur le menu pendant qu'on lit son état — voir
## NetworkManager._on_server_disconnected).
const CLIENT_TIMEOUT := 10.0

var _role: String = ""
var _out_dir: String = DEFAULT_OUT
var _started: bool = false
var _finished: bool = false
var _checks: Array = []
var _local_choice_before_join: String = ""

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--role="):
			_role = a.get_slice("=", 1)
		elif a.begins_with("--out="):
			_out_dir = a.get_slice("=", 1)

## Démarre à la première frame : pendant `_initialize`, `root` n'est pas
## encore dans l'arbre (`multiplayer` n'existe pas encore) — même contrainte
## que tools/net_smoke.gd::_start.
func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_start()
		return false
	return false

func _start() -> void:
	if _role == "host":
		_start_host()
	elif _role == "client":
		_start_client()
	else:
		push_error("join_sync_smoke : --role=host|client requis")
		quit(2)

# ==========================================================================
#  HÔTE — lance la partie sur la carte A, reste hébergé, ne juge rien.
# ==========================================================================
func _start_host() -> void:
	MatchConfig.set_mode(MODE_ID)
	MatchConfig.map_id = MAP_A
	MatchConfig.bots_enabled = false
	var net := NetworkManager.get_net(self)
	net.host()

	var scene_path := MatchConfig.resolve_scene(MODE_ID, MAP_A)
	if scene_path != "":
		change_scene_to_file(scene_path)
	else:
		push_error("join_sync_smoke (host) : impossible de résoudre la scène de la carte A (%s)" % MAP_A)

	await create_timer(HOST_TIMEOUT).timeout
	quit(0)

# ==========================================================================
#  CLIENT — sélection locale B (avant connexion), rejoint l'hôte, doit
#  finir sur la carte A. Seul rôle qui écrit le JSON / porte le verdict.
# ==========================================================================
func _start_client() -> void:
	MatchConfig.set_mode(MODE_ID)
	MatchConfig.map_id = MAP_B  # "avait choisi B" — sélection LOCALE avant de rejoindre.
	_local_choice_before_join = MatchConfig.map_id

	var net := NetworkManager.get_net(self)
	net.connection_succeeded.connect(_on_client_connected)
	net.connection_failed.connect(_on_client_connection_failed)
	net.join("127.0.0.1")

	await create_timer(CLIENT_TIMEOUT).timeout
	if not _finished:
		_add_check("client_connected_to_host", false,
			"connexion au serveur jamais établie après %.0fs (hôte absent/en retard ?)" % CLIENT_TIMEOUT)
		_finish()

func _on_client_connection_failed() -> void:
	if _finished:
		return
	_add_check("client_connected_to_host", false, "connexion refusée/échouée (NetworkManager.connection_failed)")
	_finish()

func _on_client_connected() -> void:
	if _finished:
		return
	var net := NetworkManager.get_net(self)
	# `_client_apply_server_decision` (NetworkManager.gd) a déjà tourné et
	# appliqué la décision serveur à MatchConfig AVANT ce signal (voir sa
	# doc : "match_config_received... AVANT connection_succeeded") — tout ce
	# qui suit lit donc un état déjà stabilisé, sans course.
	var received_map_id := net.received_map_id
	var received_scene := net.received_scene
	var overwritten_map_id := MatchConfig.map_id

	_add_check("client_local_choice_was_map_b_before_join", _local_choice_before_join == MAP_B,
		"sélection locale du client juste avant net.join() : \"%s\" (attendu \"%s\")" % [_local_choice_before_join, MAP_B])
	_add_check("client_received_host_map_id_is_a", received_map_id == MAP_A,
		"map_id reçu du serveur pendant la poignée de main : \"%s\" (attendu \"%s\", la carte de l'HÔTE — pas \"%s\", la sélection locale)" % [
			received_map_id, MAP_A, MAP_B])
	_add_check("match_config_overwritten_to_host_choice", overwritten_map_id == MAP_A,
		"MatchConfig.map_id après la poignée de main : \"%s\" (attendu \"%s\" — BUG-02 : la sélection locale ne doit jamais survivre à la connexion)" % [
			overwritten_map_id, MAP_A])

	await _check_client_loads_scene_a(received_scene)
	_finish()

## Reproduit EXACTEMENT MainMenu._start_game() : change_scene_to_file sur la
## scène transmise par le serveur — puis vérifie la scène RÉELLEMENT chargée
## (pas seulement le champ `received_scene`, qui pourrait être juste mais
## jamais utilisé par un bug ailleurs dans la chaîne).
func _check_client_loads_scene_a(received_scene: String) -> void:
	var scene_a := String(MapCatalog.get_by_id(MAP_A).get("scene", ""))
	var scene_b := String(MapCatalog.get_by_id(MAP_B).get("scene", ""))
	if received_scene == "":
		_add_check("client_loaded_scene_is_map_a_not_b", false,
			"received_scene vide — la poignée de main n'a transmis aucune scène, chargement impossible")
		return
	change_scene_to_file(received_scene)
	await _wait_physics(6)  # change_scene_to_file est différé — laisse le changement de scène se terminer.
	var loaded_path := current_scene.scene_file_path if current_scene else ""
	var ok := loaded_path == scene_a and loaded_path != scene_b
	_add_check("client_loaded_scene_is_map_a_not_b", ok,
		"scène réellement chargée (current_scene.scene_file_path) : \"%s\" — attendu \"%s\" (carte A, l'hôte), jamais \"%s\" (carte B, choix local)" % [
			loaded_path, scene_a, scene_b])

func _wait_physics(n: int = 1) -> void:
	for i in n:
		await physics_frame

# ==========================================================================
#  RÉSULTAT — seul le CLIENT appelle ceci (voir doc d'en-tête).
# ==========================================================================
func _add_check(name: String, ok: bool, detail: String) -> void:
	_checks.append({"name": name, "ok": ok, "detail": detail})
	print("CHECK %s ok=%s — %s" % [name, ok, detail])

func _finish() -> void:
	if _finished:
		return
	_finished = true
	var ok_count := 0
	for c in _checks:
		if bool(c["ok"]):
			ok_count += 1
	var all_ok := ok_count == _checks.size() and _checks.size() > 0
	_write_json(_out_dir.path_join("join_sync_smoke.json"), {"checks": _checks})
	print("JOIN_SYNC_SMOKE ok=%s checks=%d/%d" % [all_ok, ok_count, _checks.size()])
	quit(0 if all_ok else 1)

func _write_json(path: String, data: Dictionary) -> void:
	var abs_path := ProjectSettings.globalize_path(path) if path.begins_with("res://") else path
	var dir := abs_path.get_base_dir()
	if dir != "" and not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(abs_path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "\t"))
		f.close()
	else:
		print("JOIN_SYNC_SMOKE_WARN impossible d'écrire ", abs_path)
