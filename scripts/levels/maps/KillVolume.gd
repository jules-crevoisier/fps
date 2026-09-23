## KillVolume.gd
## Zone de mise à mort SERVEUR (Area3D) — maps-spec-v2.md §7.3 : "MapSetup
## builds a server-only KillVolume Area3D per entry, masked to players.
## body_entered calls Health.apply_damage(max_health * 10.0, 0) once, skipping
## dead players. Killfeed cause: 'noyade'. The owner's fall_limit is set to
## the volume bottom − 2 as a backstop."
##
## Note d'implémentation : le pipeline killfeed existant (GameWorld._record_kill
## / _killfeed rpc) transporte killer/victim/team, PAS de champ "cause" — il
## n'y a donc pas de canal pour afficher littéralement "noyade". On suit la
## convention déjà en place dans ce code pour les dégâts sans tireur humain
## (voir scripts/world/DamageZone.gd) : attacker_id = 0, affiché "Environnement"
## au killfeed (GameWorld._record_kill: `killer_id > 0 ... else "Environnement"`).
## Le fall_limit abaissé sert de garde-fou réel : un joueur qui traverserait le
## volume sans déclencher body_entered (lag, désync physique) retombe quand
## même sous fall_limit et respawn via PlayerController._physics_process.
class_name KillVolume
extends Area3D

## Coordonnée Y du fond du volume, fournie par l'appelant (MapSetup, à partir
## de "kill_volumes" dans les données de map) — indépendante de la forme de
## collision utilisée pour la détection.
@export var bottom_y: float = -1000.0

## instance_id des corps actuellement "noyés" (en attente de ressortir du
## volume avant de pouvoir redéclencher) — évite de spammer apply_damage à
## chaque frame de recouvrement tant que le corps reste dans la zone.
var _handled: Dictionary = {}

func _ready() -> void:
	monitoring = true
	monitorable = false
	collision_layer = 0
	collision_mask = PhysicsLayers.WORLD
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _on_body_entered(body: Node3D) -> void:
	var pc := body as PlayerController
	if pc:
		pc.fall_limit = minf(pc.fall_limit, bottom_y - 2.0)
	if not multiplayer.is_server():
		return
	var hp := body.get_node_or_null("Health") as Health
	if hp == null:
		return
	if hp.is_dead or _handled.get(body.get_instance_id(), false):
		return
	_handled[body.get_instance_id()] = true
	hp.apply_damage(hp.max_health * 10.0, 0)

func _on_body_exited(body: Node3D) -> void:
	_handled.erase(body.get_instance_id())
