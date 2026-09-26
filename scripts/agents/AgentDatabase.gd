## AgentDatabase.gd
## Catalogue des agents (construit en code) + agent sélectionné par le joueur.
## Prototype à un seul personnage (décision 2026-09-26, "strip to minimal
## prototype") : Verrou (le crapaud) est la SEULE entrée, pour le joueur ET
## tous les bots — plus aucune capacité/passif (le système d'AbilityController
## et ses primitives, scripts/agents/abilities|passives/, ont été supprimés).
## `all()` ne renvoie donc qu'un agent : `selected_index`/`get_by_index`
## retombent toujours dessus, quelle que soit la valeur reçue (bornage
## `clampi(i, 0, 0)`), sans jamais planter un appelant qui indexait encore
## plusieurs agents (GameWorld, CharacterAnimator, CharacterBody, ViewModel,
## ImpactFx, GameHUD).
class_name AgentDatabase
extends RefCounted

const ROLE_SOUTIEN := "Soutien"

## Fichier de persistance DU SEUL "dernier agent joué" — conservé pour la
## compatibilité de `record_played`/`last_played_index` (appelés par
## GameWorld au spawn réel), même si un seul agent existe désormais.
const _LAST_PLAYED_PATH := "user://agent_select.cfg"

static var _cache: Array = []
static var selected_index: int = 0
static var _last_played_loaded: bool = false
static var _last_played_index: int = -1

static func all() -> Array:
	if _cache.is_empty():
		_cache.append(_verrou())
	return _cache

static func selected() -> AgentConfig:
	return get_by_index(selected_index)

## Dernier agent avec lequel le joueur a RÉELLEMENT spawn, persistant entre
## deux lancements du jeu. -1 si aucune partie n'a encore été jouée sur cette
## machine.
static func last_played_index() -> int:
	_ensure_last_played_loaded()
	return _last_played_index

## Enregistre `index` comme dernier agent joué — appelé par GameWorld au
## moment du spawn RÉEL. `index` hors des bornes connues est ignoré (jamais
## une présélection inventée).
static func record_played(index: int) -> void:
	if index < 0 or index >= all().size():
		return
	_last_played_index = index
	_last_played_loaded = true
	var cfg := ConfigFile.new()
	cfg.set_value("agent_select", "last_played_index", index)
	cfg.save(_LAST_PLAYED_PATH)

static func _ensure_last_played_loaded() -> void:
	if _last_played_loaded:
		return
	_last_played_loaded = true
	var cfg := ConfigFile.new()
	if cfg.load(_LAST_PLAYED_PATH) == OK:
		var idx: int = int(cfg.get_value("agent_select", "last_played_index", -1))
		if idx >= 0 and idx < all().size():
			_last_played_index = idx

## Agent par index (bornes : replié sur le premier/dernier agent si hors plage —
## avec un seul agent, revient toujours à Verrou).
static func get_by_index(i: int) -> AgentConfig:
	var a := all()
	return a[clampi(i, 0, a.size() - 1)]

static func _agent(agent_name: String, role: String, desc: String, color: Color) -> AgentConfig:
	var a := AgentConfig.new()
	a.agent_name = agent_name
	a.role = role
	a.description = desc
	a.color = color
	return a

## Verrou, « le Crapaud » — ancrage tactique, seul personnage jouable du
## prototype (joueur et bots).
static func _verrou() -> AgentConfig:
	return _agent("Verrou", ROLE_SOUTIEN, "Ancrage tactique.", Color("2a5fc4"))
