## HealZone.gd
## Zone (Area3D) qui soigne les joueurs à l'intérieur. Soin CÔTÉ SERVEUR
## uniquement (Health est autoritaire serveur, contract-r2.md). Deux usages :
## - zone de test NEUTRE posée en dur par une carte (scripts/levels/
##   GulagBuilder.gd, "Gulag" : `_zone(..., HEAL_ZONE, "HealZone")`) : ne règle
##   ni `owner_team` ni `duration` -> comportement d'origine inchangé (soigne
##   TOUT le monde, zone permanente) ;
## - "Baume du Palud" de Roseau (E signature, docs/research/
##   10_ammo_kits_input.md §3.3), posée par BalmZoneAbility.activate_server,
##   qui règle `owner_team` (filtre d'équipe), `heal_per_second` (12) et
##   `duration` (6 s, auto-destruction).
## `recent_damage_window` (défaut 1 s) : une cible touchée par un dégât
## (Health.damaged, signal PUBLIC — jamais un accès direct à l'état interne de
## Health.gd, hors périmètre de ce contrat) il y a moins de cette fenêtre ne
## reçoit que la MOITIÉ du soin (contre le kite-heal en plein échange).
class_name HealZone
extends Area3D

## PV/s rendus à une cible qui n'a PAS été touchée depuis `recent_damage_window`.
@export var heal_per_second: float = 40.0
## Équipe soignée (-1 = toutes les équipes -- comportement d'origine, utilisé
## par la zone de test neutre du Gulag).
@export var owner_team: int = -1
## Durée de vie de la zone (s) : se détruit d'elle-même à l'expiration.
## 0.0 (défaut) = permanente -- comportement d'origine (zone de test du Gulag).
@export var duration: float = 0.0
## Fenêtre (s) sous laquelle une cible touchée récemment ne reçoit que la
## moitié du soin.
@export var recent_damage_window: float = 1.0

## Horodatage (s, `Time.get_ticks_msec() / 1000.0`) du dernier dégât reçu par
## chaque Health suivie, indexé par son instance id -- alimenté par le signal
## PUBLIC `Health.damaged`.
var _damage_times: Dictionary = {}
## Callables connectées à `Health.damaged`, indexées par instance id de la
## Health suivie (pour une déconnexion propre à la sortie de zone).
var _connections: Dictionary = {}


func _ready() -> void:
	if duration > 0.0:
		# Connexion à SOI-MÊME (aucun nœud tiers capturé dans une fermeture) :
		# conforme à la règle du projet sur les minuteries (jamais de lambda
		# capturant un nœud dans get_tree().create_timer()).
		get_tree().create_timer(duration).timeout.connect(queue_free)
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	for body in get_overlapping_bodies():
		if owner_team != -1 and int(body.get("team")) != owner_team:
			continue
		var hp := body.get_node_or_null("Health") as Health
		if hp == null or hp.is_dead:
			continue
		var rate := heal_per_second
		if _is_recently_damaged(hp):
			rate *= 0.5
		hp.heal(rate * delta)


func _on_body_entered(body: Node3D) -> void:
	var hp := body.get_node_or_null("Health") as Health
	if hp == null:
		return
	var id := hp.get_instance_id()
	if _connections.has(id):
		return
	var cb := _on_tracked_damaged.bind(id)
	hp.damaged.connect(cb)
	_connections[id] = cb


func _on_body_exited(body: Node3D) -> void:
	var hp := body.get_node_or_null("Health") as Health
	if hp == null:
		return
	var id := hp.get_instance_id()
	if not _connections.has(id):
		return
	if hp.damaged.is_connected(_connections[id]):
		hp.damaged.disconnect(_connections[id])
	_connections.erase(id)
	_damage_times.erase(id)


func _on_tracked_damaged(_amount: float, _attacker_id: int, id: int) -> void:
	_damage_times[id] = Time.get_ticks_msec() / 1000.0


func _is_recently_damaged(hp: Health) -> bool:
	var id := hp.get_instance_id()
	if not _damage_times.has(id):
		return false
	var last: float = _damage_times[id]
	return (Time.get_ticks_msec() / 1000.0) - last < recent_damage_window
