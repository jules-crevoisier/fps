## ServerConfig.gd
## Configuration du serveur dédié (scripts/networking/ServerBoot.gd), lue
## depuis les variables d'environnement (déploiement Docker/Dokploy) et/ou les
## arguments `--cle=valeur` (pratique en local). Pur : `parse()` prend un
## dictionnaire d'environnement déjà résolu, jamais `OS` directement, pour
## rester testable sans processus réel (tests/networking/test_server_config.gd).
## `from_os()` est le seul point qui touche `OS`/`Crypto`, réservé à
## ServerBoot.
class_name ServerConfig
extends RefCounted

const DEFAULT_PORT := 7777
const DEFAULT_HEALTH_PORT := 8080
const DEFAULT_MODE := "tdm"
const DEFAULT_MAX_PLAYERS := 16
const DEFAULT_BOT_DIFFICULTY := "veteran"
const DEFAULT_RESTART_ON_END := true

## Toutes les clés reconnues (env ET `--cle=valeur`) — voir docs/SERVER.md.
const ENV_KEYS := [
	"PORT", "HEALTH_PORT", "MODE", "MAP", "MAX_PLAYERS", "BOTS",
	"BOT_DIFFICULTY", "MATCH_TOKEN_SECRET", "MATCH_ID", "RESTART_ON_END",
]

var port: int = DEFAULT_PORT
var health_port: int = DEFAULT_HEALTH_PORT
var mode_id: String = DEFAULT_MODE
## Identifiant MapCatalog ; vide = carte par défaut du mode (MapCatalog.default_for).
var map_id: String = ""
var max_players: int = DEFAULT_MAX_PLAYERS
var bots_enabled: bool = true
var bot_difficulty: String = DEFAULT_BOT_DIFFICULTY
## Vide = aucun jeton exigé (LAN/host — voir JoinToken).
var match_token_secret: String = ""
var match_id: String = ""
var restart_on_end: bool = DEFAULT_RESTART_ON_END

## "Faut-il démarrer en serveur dédié ?" — vrai si le build porte le tag de
## fonctionnalité `dedicated_server` (export "Linux Server", voir
## export_presets.cfg) OU si `--server` est passé en argument utilisateur
## (pratique pour tester avec le binaire desktop normal, voir docs/SERVER.md).
## Pur (les deux entrées sont déjà résolues par l'appelant, voir ServerBoot).
static func wants_dedicated(has_dedicated_server_feature: bool, user_args: PackedStringArray) -> bool:
	return has_dedicated_server_feature or user_args.has("--server")

## Construit la config depuis un dictionnaire d'environnement (String -> String,
## clés parmi ENV_KEYS) déjà fusionné avec les arguments `--cle=valeur` (voir
## `from_os`). `random_match_id` sert de repli si `MATCH_ID` est absent (un
## appelant réel passe un alea, les tests une valeur fixe).
static func parse(env: Dictionary, random_match_id: String = "") -> ServerConfig:
	var c := ServerConfig.new()
	c.port = _env_int(env, "PORT", DEFAULT_PORT)
	c.health_port = _env_int(env, "HEALTH_PORT", DEFAULT_HEALTH_PORT)
	c.mode_id = _env_str(env, "MODE", DEFAULT_MODE)
	c.map_id = _env_str(env, "MAP", "")
	c.max_players = _env_int(env, "MAX_PLAYERS", DEFAULT_MAX_PLAYERS)
	c.bots_enabled = _env_bool(env, "BOTS", true)
	c.bot_difficulty = _env_str(env, "BOT_DIFFICULTY", DEFAULT_BOT_DIFFICULTY)
	c.match_token_secret = _env_str(env, "MATCH_TOKEN_SECRET", "")
	c.match_id = _env_str(env, "MATCH_ID", random_match_id)
	c.restart_on_end = _env_bool(env, "RESTART_ON_END", DEFAULT_RESTART_ON_END)
	return c

## Correspondance avec `MatchConfig.Difficulty` (RECRUE=0, VETERAN=1, ELITE=2)
## — pas de dépendance directe à MatchConfig pour garder cette classe pure ;
## ServerBoot fait `MatchConfig.bot_difficulty = ServerConfig.difficulty_id(...)`.
static func difficulty_id(name: String) -> int:
	match name.to_lower():
		"recrue", "rookie", "easy", "0":
			return 0
		"elite", "hard", "2":
			return 2
	return 1  # veteran, valeur par défaut

static func _env_str(env: Dictionary, key: String, default_value: String) -> String:
	var v: String = String(env.get(key, ""))
	return default_value if v == "" else v

static func _env_int(env: Dictionary, key: String, default_value: int) -> int:
	var v := _env_str(env, key, "")
	return default_value if v == "" or not v.is_valid_int() else v.to_int()

static func _env_bool(env: Dictionary, key: String, default_value: bool) -> bool:
	var v := _env_str(env, key, "").to_lower()
	match v:
		"":
			return default_value
		"1", "true", "yes", "on":
			return true
		"0", "false", "no", "off":
			return false
	return default_value

## Seul point de contact avec l'OS réelle : lit les variables d'environnement
## `ENV_KEYS` puis les surcharge avec les arguments `--cle=valeur` (pratique
## pour un test local sans redéfinir tout l'environnement), et tire un
## `MATCH_ID` aléatoire si absent.
static func from_os() -> ServerConfig:
	var env := {}
	for key in ENV_KEYS:
		var v := OS.get_environment(key)
		if v != "":
			env[key] = v
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and a.contains("="):
			var kv := a.substr(2).split("=", true, 1)
			env[kv[0].to_upper()] = kv[1]
	return parse(env, Crypto.new().generate_random_bytes(6).hex_encode())
