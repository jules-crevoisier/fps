## Health.gd
## Composant de vie SERVEUR-AUTORITAIRE. À mettre en enfant du joueur.
## - Le serveur est seul à appliquer les dégâts/soins (validation centralisée).
## - La valeur est ensuite répliquée à tous les clients par RPC.
## Signaux locaux pour brancher le HUD / la mort.
class_name Health
extends Node

signal health_changed(current: float, maximum: float)
signal died(killer_id: int)
signal respawned()

@export var max_health: float = 100.0
@export var regen_delay: float = 5.0   ## Délai sans dégât avant régénération (CoD-like).
@export var regen_rate: float = 35.0   ## PV/s régénérés.

var current_health: float
var is_dead: bool = false
var _last_damage_time: float = 0.0

func _ready() -> void:
	current_health = max_health
	# L'autorité serveur (peer 1) est fixée par PlayerController._ready, APRÈS le
	# réglage récursif de l'autorité du joueur (sinon elle serait écrasée).

func _physics_process(delta: float) -> void:
	# Régénération gérée uniquement côté serveur (désactivée si regen_rate <= 0).
	if not multiplayer.is_server() or is_dead or regen_rate <= 0.0:
		return
	if current_health < max_health:
		var now := Time.get_ticks_msec() / 1000.0
		if now - _last_damage_time >= regen_delay:
			_set_health(min(current_health + regen_rate * delta, max_health))

# ---- API SERVEUR (appeler uniquement sur le serveur) ----

## Inflige des dégâts. `attacker_id` = peer de l'attaquant (0 = environnement).
func apply_damage(amount: float, attacker_id: int = 0) -> void:
	if not multiplayer.is_server() or is_dead or amount <= 0.0:
		return
	_last_damage_time = Time.get_ticks_msec() / 1000.0
	_set_health(current_health - amount)
	if current_health <= 0.0:
		_die(attacker_id)

func heal(amount: float) -> void:
	if not multiplayer.is_server() or is_dead or amount <= 0.0:
		return
	_set_health(min(current_health + amount, max_health))

## Demande de soin (depuis une capacité côté client). Appliquée par le serveur.
@rpc("any_peer", "call_local", "reliable")
func request_heal(amount: float) -> void:
	if multiplayer.is_server():
		heal(amount)

## Réinitialise la vie (respawn). Serveur uniquement.
func reset() -> void:
	if not multiplayer.is_server():
		return
	is_dead = false
	_set_health(max_health)
	_notify_respawn.rpc()

func _die(killer_id: int) -> void:
	is_dead = true
	_notify_death.rpc(killer_id)

func _set_health(value: float) -> void:
	current_health = clampf(value, 0.0, max_health)
	_sync_health.rpc(current_health, is_dead)

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

@rpc("authority", "call_local", "reliable")
func _notify_respawn() -> void:
	is_dead = false
	current_health = max_health
	respawned.emit()
	health_changed.emit(current_health, max_health)
