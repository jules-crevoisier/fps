## AssistTracker.gd
## Suivi PUR (pas d'accès scène) des dégâts infligés à une victime, pour
## déterminer les ASSISTANCES à sa mort (docs/research/10_ammo_kits_input.md
## §3.5) : une assistance = un attaquant (autre que le tueur) qui a infligé
## AU MOINS 40 dégâts cumulés sur la victime dans les 5 s qui précèdent sa
## mort. Un seul instrument PARTAGÉ pour toute la partie (une entrée par
## victime), pensé pour être alimenté par GameWorld._on_player_damaged
## (`record_damage`, à chaque dégât) et consommé par GameWorld._record_kill
## (`assists_for_kill`, à la mort) -- ces deux points d'appel vivent dans
## GameWorld.gd, hors des fichiers possédés par ce contrat ; le câblage est
## laissé à la tâche qui possède ce fichier. Horodatage injecté par
## l'appelant (même style que OutOfCombatTracker) pour rester testable sans
## horloge réelle.
class_name AssistTracker
extends RefCounted

const ASSIST_MIN_DAMAGE := 40.0
const ASSIST_WINDOW := 5.0

## victim_id -> Array[{attacker_id: int, amount: float, at: float}]
var _hits: Dictionary = {}

## Appelé côté SERVEUR à chaque dégât encaissé par `victim_id`. Un dégât venu
## de l'environnement/de soi-même (`attacker_id <= 0` ou `== victim_id`), ou
## nul/négatif, n'ouvre jamais d'assistance.
func record_damage(victim_id: int, attacker_id: int, amount: float, now: float) -> void:
	if attacker_id <= 0 or attacker_id == victim_id or amount <= 0.0:
		return
	if not _hits.has(victim_id):
		_hits[victim_id] = []
	_hits[victim_id].append({"attacker_id": attacker_id, "amount": amount, "at": now})

## Liste des ids d'attaquants qui ont infligé >= ASSIST_MIN_DAMAGE cumulés sur
## `victim_id` dans la fenêtre ASSIST_WINDOW précédant `now` (l'instant de la
## mort) -- le TUEUR (`killer_id`) est toujours exclu (un kill n'est jamais
## aussi sa propre assistance). Purge l'historique de cette victime dans tous
## les cas : une mort ferme la fenêtre, la vie suivante ne doit rien hériter
## des dégâts d'avant.
func assists_for_kill(victim_id: int, killer_id: int, now: float) -> Array:
	var totals: Dictionary = {}  # attacker_id -> dégâts cumulés dans la fenêtre
	for hit in _hits.get(victim_id, []):
		if now - hit.at > ASSIST_WINDOW:
			continue
		totals[hit.attacker_id] = totals.get(hit.attacker_id, 0.0) + hit.amount
	_hits.erase(victim_id)
	var out: Array = []
	for attacker_id in totals:
		if attacker_id != killer_id and totals[attacker_id] >= ASSIST_MIN_DAMAGE:
			out.append(attacker_id)
	return out
