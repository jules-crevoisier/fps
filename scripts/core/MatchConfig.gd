## MatchConfig.gd
## Réglages de la partie choisis au menu (mode, carte, taille d'équipe, bots),
## lus par la scène de jeu à son chargement. Statique : survit au changement de
## scène. Le serveur (hôte ou dédié, voir MainMenu._on_host / ServerBoot) est
## seul à les CHOISIR ; un client qui rejoint reçoit mode_id/map_id/scène du
## serveur pendant l'authentification (NetworkManager.build_accept_payload /
## _client_apply_server_decision) et les applique ICI avant de changer de
## scène — jamais sa propre sélection locale (voir BUG-02, docs/audit/bugs.md).
class_name MatchConfig
extends RefCounted

enum Difficulty { RECRUE, VETERAN, ELITE }

## Identifiants de mode reconnus par MapSetup (scripts/levels/maps/).
## Prototype à un seul mode (décision 2026-09-26, "strip to minimal
## prototype") : TDM seul est sélectionnable. Hardpoint/SnD/Duel/Duo restent
## définis côté scripts/modes/ et scripts/levels/maps/MapSetup.gd (protégé,
## regénéré séparément — MapSetup._build_game_mode instancie encore
## HardpointMode/SnDMode/DuelMode par branche `match`) : cette liste réduite
## garantit qu'aucun id autre que "tdm" ne peut plus être choisi (set_mode
## retombe sur "tdm" pour tout id absent d'ici), donc que ces branches ne
## sont plus jamais atteintes en jeu, sans casser leur compilation.
const MODES := ["tdm"]

static var mode_id: String = "tdm"
## Identifiant MapCatalog ; vide = carte par défaut du mode.
static var map_id: String = ""
## Joueurs par équipe : 4 en 4v4, 2 en Duo, 1 en Duel (voir team_size_for).
static var team_size: int = 4
## Compléter les équipes avec des bots (toujours affichés « BOT »).
static var bots_enabled: bool = true
static var bot_difficulty: int = Difficulty.VETERAN

## Persistance (UX-08, docs/research/04_ui_ux.md #153 : « JOUER lance le
## dernier mode, ou Arène vs bots au premier lancement ») — ConfigFile sous
## `user://`, même patron que Settings.gd/TrainingRecords.gd. MainMenu appelle
## `load_last()` une fois à l'ouverture puis `save_last()` à chaque
## changement de sélection (mode/carte/bots/difficulté) : le menu retrouve
## donc toujours la DERNIÈRE configuration jouée, jamais besoin de la
## reconstruire depuis un état intermédiaire. Fichier absent (premier
## lancement) : `load_last()` ne touche à rien, les défauts déclarés ci-dessus
## (TDM, bots activés, Vétéran) restent — soit exactement « Arène vs bots ».
const SAVE_PATH := "user://match_config.cfg"
const _SECTION := "last"

## Taille d'équipe imposée par un mode.
static func team_size_for(id: String) -> int:
	match id:
		"duel":
			return 1
		"duo":
			return 2
	return 4

## Sélectionne un mode (et la taille d'équipe qui va avec). Un id inconnu
## retombe sur le TDM.
static func set_mode(id: String) -> void:
	mode_id = id if id in MODES else "tdm"
	team_size = team_size_for(mode_id)

## Résout la scène de niveau pour (mode_id, map_id) — même règle que
## ServerBoot._resolve_map_scene (carte demandée, sinon défaut du mode).
## Utilisée par NetworkManager.build_accept_payload : le SERVEUR (hôte ou
## dédié) résout la scène de sa propre partie et la transmet déjà résolue au
## client pendant l'authentification (voir BUG-02, docs/audit/bugs.md).
## `map_id` vide ou inconnu = carte par défaut du mode (MapCatalog.default_for) ;
## fonction pure, jamais d'erreur sur un id forgé.
static func resolve_scene(id: String, map: String) -> String:
	var entry: Dictionary = MapCatalog.get_by_id(map) if map != "" else {}
	if entry.is_empty():
		entry = MapCatalog.default_for(id)
	return str(entry.get("scene", "res://scenes/levels/tdm_map.tscn"))

## Borne un index de difficulté (0 Recrue .. 2 Élite). Fonction pure, comme
## Settings.clamp_* — reste testable sans toucher au disque, et protège
## `load_last()` contre une valeur aberrante écrite par une build future.
static func clamp_difficulty(v: int) -> int:
	return clampi(v, Difficulty.RECRUE, Difficulty.ELITE)

## Recharge le dernier mode/carte/bots/difficulté depuis `user://` (appelé une
## fois par MainMenu._ready()). Fichier absent ou illisible = premier
## lancement : ne touche à rien, les défauts ci-dessus restent (voir doc
## d'en-tête de `SAVE_PATH`). Un `mode_id` inconnu (fichier d'une build
## future) retombe sur TDM via `set_mode`, jamais un mode invalide.
static func load_last() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	set_mode(str(cfg.get_value(_SECTION, "mode_id", mode_id)))
	map_id = str(cfg.get_value(_SECTION, "map_id", map_id))
	bots_enabled = bool(cfg.get_value(_SECTION, "bots_enabled", bots_enabled))
	bot_difficulty = clamp_difficulty(int(cfg.get_value(_SECTION, "bot_difficulty", bot_difficulty)))

## Sauvegarde le mode/carte/bots/difficulté courants sous `user://`. Appelé
## par MainMenu à chaque changement de sélection (mode, carte, bots,
## difficulté) et avant de lancer une partie — jamais par ce fichier lui-même
## en dehors de ces deux points d'entrée.
static func save_last() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value(_SECTION, "mode_id", mode_id)
	cfg.set_value(_SECTION, "map_id", map_id)
	cfg.set_value(_SECTION, "bots_enabled", bots_enabled)
	cfg.set_value(_SECTION, "bot_difficulty", bot_difficulty)
	cfg.save(SAVE_PATH)

## Réservé aux tests (tests/ui/test_main_menu.gd) : efface le fichier de
## persistance pour rejouer le scénario « premier lancement » sans laisser de
## trace sur le vrai `user://` du poste — même patron que
## TrainingRecords._debug_clear().
static func _debug_clear() -> void:
	var dir := DirAccess.open("user://")
	if dir and dir.file_exists("match_config.cfg"):
		dir.remove("match_config.cfg")
