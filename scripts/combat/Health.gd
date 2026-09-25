## Health.gd
## Composant de vie SERVEUR-AUTORITAIRE. À mettre en enfant du joueur.
## - Le serveur est seul à appliquer les dégâts/soins (validation centralisée).
## - La valeur est ensuite répliquée à tous les clients par RPC.
## Signaux locaux pour brancher le HUD / la mort / la charge d'ultime (GameWorld).
class_name Health
extends Node

signal health_changed(current: float, maximum: float)
signal died(killer_id: int)
signal respawned()
## Dégâts effectivement appliqués (serveur uniquement) : utilisé par GameWorld
## pour charger l'ultime de l'ATTAQUANT (`amount * 0.05`, voir contract-r2.md).
signal damaged(amount: float, attacker_id: int)
## GF-10 "Réaction visible de la cible" : émis sur TOUS les pairs (contrairement
## à `damaged`, serveur uniquement) à chaque dégât confirmé encaissé par CE
## joueur — écouté par PlayerLook (flash du mesh, blanc/rouge selon `headshot`)
## et CharacterAnimator (recul additif du haut du corps). Diffusé par
## `_notify_hit_reaction` (voir plus bas), même schéma que `_sync_health`/
## `_notify_death`.
signal hit_reaction(headshot: bool)
## PROPRIÉTAIRE uniquement (contract-r4a.md "R4-FX" #2) : position MONDE de la
## source des dégâts, pour la flèche de direction du HUD (HitFeedback.gd).
## Absent (dégâts sans attaquant identifiable, ex. DamageZone) => pas émis.
signal damage_from_direction(amount: float, source_position: Vector3)

@export var max_health: float = 100.0
@export var regen_delay: float = 4.0   ## Délai sans dégât avant régénération (CoD-like).
@export var regen_rate: float = 35.0   ## PV/s régénérés.
## Régénération active dans ce mode (Duel/Duo : false pendant les manches —
## voir DuelMode._after_round_respawn). Vrai par défaut (TDM/Hardpoint/SnD).
var regen_enabled: bool = true

var current_health: float
var is_dead: bool = false
var _last_damage_time: float = 0.0
## Invulnérabilité temporaire (respawn) : les dégâts sont ignorés tant que > 0.
var _protection_left: float = 0.0

func _ready() -> void:
	current_health = max_health
	# L'autorité serveur (peer 1) est fixée par PlayerController._ready, APRÈS le
	# réglage récursif de l'autorité du joueur (sinon elle serait écrasée).

func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	if _protection_left > 0.0:
		_protection_left = maxf(_protection_left - delta, 0.0)
	# Régénération gérée uniquement côté serveur (désactivée si regen_rate <= 0
	# ou si le mode l'a coupée, ex. Duel/Duo pendant les manches).
	if is_dead or not regen_enabled or regen_rate <= 0.0:
		return
	if current_health < max_health:
		var now := Time.get_ticks_msec() / 1000.0
		if now - _last_damage_time >= regen_delay:
			_set_health(min(current_health + regen_rate * delta, max_health))

# ---- API SERVEUR (appeler uniquement sur le serveur) ----

## Inflige des dégâts. `attacker_id` = peer de l'attaquant (0 = environnement).
## `headshot` (GF-10, défaut false pour les appelants qui ne le calculent pas
## encore, ex. KillVolume/DamageZone) choisit la couleur du flash de hit
## diffusé par `hit_reaction` — n'affecte ni les dégâts ni la mort. Sans effet
## pendant une protection de spawn (`spawn_protection`).
func apply_damage(amount: float, attacker_id: int = 0, headshot: bool = false) -> void:
	if not multiplayer.is_server() or is_dead or amount <= 0.0:
		return
	if _protection_left > 0.0:
		return
	_last_damage_time = Time.get_ticks_msec() / 1000.0
	_set_health(current_health - amount)
	damaged.emit(amount, attacker_id)
	_push_damage_direction(amount, attacker_id)
	_notify_hit_reaction.rpc(headshot)
	if current_health <= 0.0:
		_die(attacker_id)

func heal(amount: float) -> void:
	if not multiplayer.is_server() or is_dead or amount <= 0.0:
		return
	_set_health(min(current_health + amount, max_health))

## Active une invulnérabilité temporaire (respawn / début de manche). Serveur uniquement.
func spawn_protection(seconds: float) -> void:
	if not multiplayer.is_server():
		return
	_protection_left = maxf(seconds, 0.0)

## Met fin immédiatement à la protection de spawn (ex. dès que le joueur tire
## — appelé par Weapon.gd après un tir accepté, voir contract-r2.md).
func end_spawn_protection() -> void:
	if not multiplayer.is_server():
		return
	_protection_left = 0.0

## Réinitialise la vie (respawn). Serveur uniquement.
func reset() -> void:
	if not multiplayer.is_server():
		return
	is_dead = false
	_protection_left = 0.0
	_set_health(max_health)
	_notify_respawn.rpc()

func _die(killer_id: int) -> void:
	is_dead = true
	_notify_death.rpc(killer_id)

func _set_health(value: float) -> void:
	current_health = clampf(value, 0.0, max_health)
	_sync_health.rpc(current_health, is_dead)

## Résout la position MONDE de l'attaquant à l'instant du coup, en cherchant
## un joueur nommé `attacker_id` parmi les FRÈRES de notre propre joueur (tous
## les joueurs — humains et bots — vivent sous le même conteneur "Players" de
## GameWorld, voir GameWorld._spawn_player). Volontairement SANS dépendance à
## Weapon.gd/GameWorld.gd (hors périmètre R4-FX) : ce nœud se suffit à
## lui-même. `Vector3.INF` = pas de source identifiable (environnement,
## attaquant déjà déconnecté/respawn).
func _source_position(attacker_id: int) -> Vector3:
	if attacker_id <= 0:
		return Vector3.INF
	var me := get_parent()
	var players := me.get_parent() if me else null
	var attacker := players.get_node_or_null(str(attacker_id)) if players else null
	return attacker.global_position if attacker is Node3D else Vector3.INF

## Pousse `(amount, source_position)` au PROPRIÉTAIRE uniquement (contract-r4a.md
## "R4-FX" #2) — jamais aux autres pairs (pas leur direction de dégâts).
## Appel DIRECT si le propriétaire est SIMULÉ SERVEUR (hôte/bot, contract-p0.md
## "réseau") : un RPC vers son id n'atteindrait aucun pair réel pour un bot.
func _push_damage_direction(amount: float, attacker_id: int) -> void:
	var src := _source_position(attacker_id)
	if not src.is_finite():
		return
	var owner_node := get_parent()
	if owner_node == null:
		return
	if owner_node.is_multiplayer_authority():
		_emit_damage_direction(amount, src)  # hôte/bot : appel direct (contract-p0.md)
	else:
		_receive_damage_direction.rpc_id(str(owner_node.name).to_int(), amount, src)

func _emit_damage_direction(amount: float, source_position: Vector3) -> void:
	damage_from_direction.emit(amount, source_position)

# ---- RPCs serveur -> clients ----

@rpc("authority", "call_local", "reliable")
func _sync_health(value: float, dead: bool) -> void:
	current_health = value
	is_dead = dead
	health_changed.emit(current_health, max_health)

@rpc("authority", "call_local", "reliable")
func _notify_death(killer_id: int) -> void:
	is_dead = true
	died.emit(killer_id)

## GF-10 : diffuse le flash/flinch cosmétique à TOUS les pairs — même schéma
## que `_sync_health`/`_notify_death` (`call_local` : le serveur se l'applique
## aussi à lui-même s'il joue l'hôte).
@rpc("authority", "call_local", "reliable")
func _notify_hit_reaction(headshot: bool) -> void:
	hit_reaction.emit(headshot)

@rpc("authority", "call_local", "reliable")
func _notify_respawn() -> void:
	is_dead = false
	current_health = max_health
	respawned.emit()
	health_changed.emit(current_health, max_health)

## PROPRIÉTAIRE uniquement (`call_remote`, ciblé par `.rpc_id()` dans
## `_push_damage_direction` — jamais reçu par le serveur lui-même, qui passe
## par l'appel direct de `_emit_damage_direction` pour l'hôte/un bot).
@rpc("authority", "call_remote", "reliable")
func _receive_damage_direction(amount: float, source_position: Vector3) -> void:
	_emit_damage_direction(amount, source_position)
