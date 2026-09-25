## Telemetry.gd
## Télémétrie locale — événements JSONL versionnés (FUN-05, docs/research/
## 05_fun_retention.md §5 : "Aucune télémétrie" §4.1). Écrit un événement par
## ligne sous user://telemetry/, un fichier par PROCESS (couvre le menu et
## tous les matchs joués pendant cette session — voir `start_session`),
## envoyé à un service externe (Talo) plus tard : ce module ne fait QUE
## écrire du JSONL local, aucun réseau HTTP ici.
##
## Schéma (v1) : chaque événement porte le socle {v, t, match_id, event}
## (voir `build_event`) plus les champs propres à son type (voir
## `_REQUIRED_FIELDS`) — validés par `validate()` avant toute écriture.
## `match_id` vide ("") = hors match (session/réglages/tutoriel avant la
## première partie).
##
## Serveur vs local (critère d'acceptation "écriture côté serveur seulement
## pour les événements de jeu") : les événements qui décrivent l'état
## AUTORITAIRE d'un match (`GAME_EVENTS`) ne s'écrivent que si l'appelant
## passe `is_server = true` à `record()` — GameWorld.gd est seul juge de
## cette valeur (`multiplayer.is_server()`). Les autres événements (session,
## sélection d'agent, réglages, tutoriel, capacité utilisée, sondage) sont
## des préférences/actions PROPRES à chaque pair et s'écrivent localement,
## sans condition.
##
## RGPD (critère d'acceptation "aucune donnée personnelle hors pseudo") :
## seuls des identifiants de pair (int) et des pseudos déjà publics en jeu
## ("Joueur %d", "BOT <prénom>") transitent ici — jamais un email, une IP ou
## un nom réel. `record()` refuse (silencieusement, en jeu on ne plante
## jamais dessus) tout événement dont une valeur textuelle ressemble à un
## email ou une IPv4 (`has_no_personal_data`).
##
## Coût (critère d'acceptation "≤ 0,1 ms par événement") : `record()` ne fait
## qu'assembler un Dictionary, le valider (quelques comparaisons de clés) et
## ajouter une ligne au FileAccess déjà ouvert (tampon interne, aucun
## `flush()` par ligne — voir `close_log`) : pas d'allocation réseau, pas de
## parsing JSON en retour. Mesuré dans tests/core/test_telemetry.gd.
class_name Telemetry
extends RefCounted

const SCHEMA_VERSION := 1

const EVENT_SESSION_START := "session_start"
const EVENT_SESSION_END := "session_end"
const EVENT_MATCH_START := "match_start"
const EVENT_MATCH_END := "match_end"
const EVENT_SPAWN := "spawn"
const EVENT_KILL := "kill"
const EVENT_ROUND_START := "round_start"
const EVENT_ROUND_END := "round_end"
const EVENT_PURCHASE := "purchase"
const EVENT_ABILITY_USED := "ability_used"
const EVENT_AGENT_SELECTED := "agent_selected"
const EVENT_SETTINGS_CHANGED := "settings_changed"
const EVENT_TUTORIAL_STEP := "tutorial_step"
const EVENT_TUTORIAL_COMPLETE := "tutorial_complete"
const EVENT_ABANDON := "abandon"
const EVENT_MATCH_PERF := "match_perf"
## Réservé à FUN-04 (micro-questionnaire post-match) : accepté dès
## maintenant pour ne pas devoir revoir le schéma quand cette tâche l'émettra.
const EVENT_SURVEY := "survey"

## Champs additionnels requis PAR type d'événement, en plus du socle commun
## {v, t, match_id, event} (toujours vérifié par `validate`). L'ordre suit le
## titre de FUN-05 : session, match, spawn, kill, manche, achat, capacité,
## agent, réglages, tutoriel, abandon, fps/ping par match.
const _REQUIRED_FIELDS := {
	EVENT_SESSION_START: ["session_id"],
	EVENT_SESSION_END: ["session_id", "duration_s"],
	EVENT_MATCH_START: ["mode_id", "map_id", "team_size"],
	EVENT_MATCH_END: ["winner_team", "duration_s"],
	EVENT_SPAWN: ["player_id", "team", "pos"],
	## Contrat FUN-05 : positions tueur/victime, arme, distance, état de
	## mouvement, capacité active, headshot, temps depuis le spawn.
	EVENT_KILL: [
		"killer_id", "victim_id", "killer_pos", "victim_pos", "weapon",
		"distance", "movement_state", "active_ability", "headshot", "time_since_spawn",
	],
	EVENT_ROUND_START: ["round_index"],
	EVENT_ROUND_END: ["round_index", "winner_team"],
	EVENT_PURCHASE: ["player_id", "item_id", "cost"],
	EVENT_ABILITY_USED: ["player_id", "ability_id"],
	EVENT_AGENT_SELECTED: ["player_id", "agent_id"],
	EVENT_SETTINGS_CHANGED: ["player_id", "key", "value"],
	EVENT_TUTORIAL_STEP: ["player_id", "step_id"],
	EVENT_TUTORIAL_COMPLETE: ["player_id"],
	EVENT_ABANDON: ["player_id", "team"],
	EVENT_MATCH_PERF: ["avg_fps", "p99_ms", "avg_ping_ms"],
	EVENT_SURVEY: ["player_id", "fun_score"],
}

## Événements d'état de MATCH autoritaire : `record()` n'écrit ces types que
## si `is_server` est vrai (voir doc d'en-tête). Absent d'ici = écrit
## localement par CHAQUE pair, sans condition — session, agent choisi,
## réglages, tutoriel, capacité utilisée (l'ACTION du joueur), sondage, ET
## `match_perf` (fps/ping mesurés par CE pair pour lui-même, pas un état de
## match autoritaire : hôte, chaque client et le serveur dédié émettent
## chacun le leur).
const GAME_EVENTS: Array[String] = [
	EVENT_MATCH_START, EVENT_MATCH_END, EVENT_SPAWN, EVENT_KILL,
	EVENT_ROUND_START, EVENT_ROUND_END, EVENT_PURCHASE, EVENT_ABANDON,
]

const _LOG_DIR := "user://telemetry"

static var current_match_id: String = ""
static var _file: FileAccess = null
static var _log_path: String = ""
static var _session_id: String = ""
static var _session_start_t: float = 0.0

# ---------------------------------------------------------------------
#  API PURE — testée directement, sans fichier ni réseau.
# ---------------------------------------------------------------------

## Assemble le socle {v, t, match_id, event} puis fusionne `fields`. Pur :
## aucune écriture, aucune validation (voir `validate`). `match_id` :
## `current_match_id` si omis (le point d'entrée réseau, GameWorld.gd, le
## tient à jour — voir sa doc).
static func build_event(event: String, fields: Dictionary = {}, match_id: String = "") -> Dictionary:
	var mid := match_id if match_id != "" else current_match_id
	var out: Dictionary = {
		"v": SCHEMA_VERSION,
		"t": Time.get_unix_time_from_system(),
		"match_id": mid,
		"event": event,
	}
	for key in fields:
		out[key] = fields[key]
	return out

## Vrai si `data` porte le socle commun avec les bons types ET tous les
## champs requis par son `event` (voir `_REQUIRED_FIELDS`). Un `event`
## inconnu est toujours invalide (pas de schéma versionné pour lui). Pur.
static func validate(data: Dictionary) -> bool:
	if not (data.get("v") is int):
		return false
	if not (data.get("t") is float or data.get("t") is int):
		return false
	if not (data.get("match_id") is String):
		return false
	if not (data.get("event") is String):
		return false
	var event: String = data["event"]
	if not _REQUIRED_FIELDS.has(event):
		return false
	for key in _REQUIRED_FIELDS[event]:
		if not data.has(key):
			return false
	return true

## RGPD : refuse toute valeur textuelle ressemblant à un email (contient "@")
## ou à une IPv4 (4 groupes numériques séparés par des points). Les seules
## chaînes attendues ici sont des pseudos déjà publics en jeu et des
## identifiants techniques (arme, capacité, état de mouvement) : aucun des
## deux motifs ne doit jamais y matcher légitimement.
static func has_no_personal_data(data: Dictionary) -> bool:
	for key in data:
		var value = data[key]
		if value is String and (value.contains("@") or _looks_like_ipv4(value)):
			return false
	return true

static func _looks_like_ipv4(s: String) -> bool:
	var parts := s.split(".")
	if parts.size() != 4:
		return false
	for part in parts:
		if part.is_empty() or not part.is_valid_int():
			return false
		var n := part.to_int()
		if n < 0 or n > 255:
			return false
	return true

# ---------------------------------------------------------------------
#  Écriture JSONL (user://telemetry/, un fichier par process — voir
#  `start_session`) — dépôt local ; l'envoi Talo est hors périmètre FUN-05.
# ---------------------------------------------------------------------

## (Ré)ouvre le journal au chemin donné (par défaut : un fichier horodaté
## sous user://telemetry/). Ferme d'abord un journal déjà ouvert. Réservé à
## `start_session` en jeu ; les tests l'appellent directement avec un chemin
## dédié pour s'isoler du répertoire utilisateur réel.
static func open_log(path: String = "") -> void:
	close_log()
	var target := path
	if target == "":
		DirAccess.make_dir_recursive_absolute(_LOG_DIR)
		target = "%s/session_%d.jsonl" % [_LOG_DIR, int(Time.get_unix_time_from_system())]
	_log_path = target
	_file = FileAccess.open(target, FileAccess.WRITE)
	if _file == null:
		push_warning("Telemetry: impossible d'ouvrir %s (err=%s)" % [target, FileAccess.get_open_error()])

static func close_log() -> void:
	if _file != null:
		_file.close()
		_file = null

static func log_path() -> String:
	return _log_path

static func is_log_open() -> bool:
	return _file != null

## Démarre la session locale de télémétrie (idempotent : un appel ultérieur,
## ex. au chargement d'une autre carte dans le même process, ne réouvre rien
## et n'émet pas un second `session_start`). Écrit toujours (événement HORS
## `GAME_EVENTS`), même côté client.
static func start_session() -> void:
	if _file != null:
		return
	_session_id = "s_%d_%d" % [int(Time.get_unix_time_from_system()), randi() % 1000000]
	_session_start_t = Time.get_unix_time_from_system()
	open_log()
	record(EVENT_SESSION_START, {"session_id": _session_id})

## Termine la session (durée = depuis `start_session`) puis ferme le fichier.
static func end_session() -> void:
	if _file == null:
		return
	var duration := Time.get_unix_time_from_system() - _session_start_t
	record(EVENT_SESSION_END, {"session_id": _session_id, "duration_s": duration})
	close_log()

## Construit, valide (schéma + RGPD) puis écrit UNE ligne JSONL. Les
## événements de `GAME_EVENTS` ne s'écrivent que si `is_server` est vrai
## (critère d'acceptation "écriture côté serveur seulement pour les
## événements de jeu") — l'événement construit est quand même retourné (les
## tests n'ont pas besoin d'un fichier ouvert pour vérifier le socle/schéma).
## Un événement invalide ou porteur d'une donnée personnelle est ignoré en
## silence (`push_warning` seulement) : jamais d'erreur bloquante en jeu.
static func record(event: String, fields: Dictionary = {}, match_id: String = "", is_server: bool = true) -> Dictionary:
	var data := build_event(event, fields, match_id)
	if GAME_EVENTS.has(event) and not is_server:
		return data
	if not validate(data):
		push_warning("Telemetry: événement invalide ignoré (%s)" % event)
		return data
	if not has_no_personal_data(data):
		push_warning("Telemetry: donnée personnelle détectée, événement ignoré (%s)" % event)
		return data
	if _file != null:
		_file.store_line(JSON.stringify(data))
	return data
