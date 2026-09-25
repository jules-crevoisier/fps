## StatusEffects.gd
## État PUR (pas d'accès à l'arbre de scène) des effets de statut TEMPORAIRES
## d'un joueur : multiplicateur de vitesse au sol, verrou de saut, multiplicateur
## de durée des contrôles subis -- chacun avec sa propre minuterie. Utilisée
## deux fois par AbilityController, comme AbilityState (contract-p0.md) : une
## copie AUTORITAIRE côté serveur (`_server_status`), une copie PRÉDICTIVE côté
## propriétaire (`_owner_status`), corrigée via to_dict()/apply_dict() --
## poussée EN <= 1 TICK à chaque application (voir AbilityController.
## server_apply_speed_mult/server_apply_jump_lock/server_apply_cc_mult et
## `_push_status`, même patron que `_push_state`). Lue par
## PlayerController.ground_move (speed_mult) et can_jump (is_jump_locked).
## Testée directement (tests/agents/test_status_effects.gd).
##
## Comme AbilityState : minuteries en COMPTE À REBOURS décrémentées par
## tick(delta), JAMAIS un horodatage absolu -- un horodatage transporté du
## serveur vers le propriétaire par RPC serait comparé à une horloge locale
## dont l'epoch diffère (chaque pair démarre son moteur à un instant
## différent), ce qui casserait silencieusement toute expiration synchronisée.
class_name StatusEffects
extends RefCounted

var _speed_mult: float = 1.0
var _speed_time_left: float = 0.0
var _jump_lock_time_left: float = 0.0
var _cc_mult: float = 1.0
var _cc_time_left: float = 0.0

## Fait avancer toutes les minuteries de `delta` secondes ; un multiplicateur
## dont la minuterie retombe à zéro redevient neutre (1.0 -- plus aucun effet).
func tick(delta: float) -> void:
	if _speed_time_left > 0.0:
		_speed_time_left = maxf(_speed_time_left - delta, 0.0)
		if _speed_time_left <= 0.0:
			_speed_mult = 1.0
	if _jump_lock_time_left > 0.0:
		_jump_lock_time_left = maxf(_jump_lock_time_left - delta, 0.0)
	if _cc_time_left > 0.0:
		_cc_time_left = maxf(_cc_time_left - delta, 0.0)
		if _cc_time_left <= 0.0:
			_cc_mult = 1.0

## Multiplicateur de vitesse au sol (ex. Glu de Verrou : 0.5 pendant 1.5 s, ou
## Mèche courte de Vif : 1.1 pendant 2 s). REMPLACE tout effet de vitesse en
## cours -- pas de cumul, le dernier appliqué fait foi (deux ralentissements
## ne s'additionnent pas dans ce socle).
func apply_speed_mult(mult: float, duration: float) -> void:
	_speed_mult = mult
	_speed_time_left = duration

func speed_mult() -> float:
	return _speed_mult if _speed_time_left > 0.0 else 1.0

## Verrouille le saut (et, par construction, le slide-hop -- voir
## PlayerController.can_jump) pendant `duration` s (ex. Glu de Verrou : "ne
## peut ni sauter, ni glisser, ni plonger"). Deux verrous qui se chevauchent
## gardent le plus long restant, jamais raccourci par un second appel plus court.
func apply_jump_lock(duration: float) -> void:
	_jump_lock_time_left = maxf(_jump_lock_time_left, duration)

func is_jump_locked() -> bool:
	return _jump_lock_time_left > 0.0

## Multiplicateur GÉNÉRIQUE appliqué à la durée des contrôles SUBIS
## (étourdissement, éblouissement), en PLUS du passif de l'agent
## (Passive.modify_cc_duration) -- voir AbilityController._resolve_cc_duration,
## qui combine les deux par multiplication. < 1.0 = contrôles raccourcis,
## > 1.0 = allongés.
func apply_cc_mult(mult: float, duration: float) -> void:
	_cc_mult = mult
	_cc_time_left = duration

func cc_mult() -> float:
	return _cc_mult if _cc_time_left > 0.0 else 1.0

## Sérialise l'état runtime -- utilisé pour la correction serveur -> propriétaire
## (même patron que AbilityState.to_dict/apply_dict).
func to_dict() -> Dictionary:
	return {
		"speed_mult": _speed_mult, "speed_time_left": _speed_time_left,
		"jump_lock_time_left": _jump_lock_time_left,
		"cc_mult": _cc_mult, "cc_time_left": _cc_time_left,
	}

func apply_dict(d: Dictionary) -> void:
	if d.has("speed_mult"):
		_speed_mult = float(d["speed_mult"])
	if d.has("speed_time_left"):
		_speed_time_left = float(d["speed_time_left"])
	if d.has("jump_lock_time_left"):
		_jump_lock_time_left = float(d["jump_lock_time_left"])
	if d.has("cc_mult"):
		_cc_mult = float(d["cc_mult"])
	if d.has("cc_time_left"):
		_cc_time_left = float(d["cc_time_left"])
