## HardpointMode.gd
## Mode Hardpoint (CoD) : une zone à tenir. Une équipe SEULE dans la zone gagne
## des points/s ; deux équipes = contesté (rien). La zone tourne d'emplacement
## toutes les `rotate_interval` secondes. Premier à `score_to_win` gagne.
## Scoring serveur-autoritaire, synchronisé au HUD.
class_name HardpointMode
extends GameMode

@export var zone_path: NodePath
@export var points_path: NodePath
@export var capture_rate: float = 1.0      # points/s
@export var rotate_interval: float = 45.0

var _zone: Area3D
var _points: Array = []
var _point_index: int = 0
var _rotate_timer: float = 0.0
var _sync_timer: float = 0.0

func _ready() -> void:
	super._ready()
	mode_name = "Hardpoint"
	_zone = get_node_or_null(zone_path) as Area3D
	var pr := get_node_or_null(points_path)
	if pr:
		_points = pr.get_children()
	if multiplayer.is_server() and not _points.is_empty():
		_set_zone.rpc(0)

@rpc("authority", "call_local", "reliable")
func _set_zone(index: int) -> void:
	_point_index = index
	if _zone and index >= 0 and index < _points.size():
		_zone.global_position = (_points[index] as Node3D).global_position

func _physics_process(delta: float) -> void:
	if not multiplayer.is_server() or winner != -1:
		return

	# Rotation de la zone.
	if _points.size() > 1:
		_rotate_timer += delta
		if _rotate_timer >= rotate_interval:
			_rotate_timer = 0.0
			_set_zone.rpc((_point_index + 1) % _points.size())

	# Quelles équipes (vivantes) sont dans la zone ?
	var present := {}
	if _zone:
		for b in _zone.get_overlapping_bodies():
			if b is PlayerController:
				var hp := b.get_node_or_null("Health") as Health
				if hp and hp.is_dead:
					continue
				present[int(b.team)] = true

	var remain := int(rotate_interval - _rotate_timer)
	if present.size() == 1:
		var team: int = present.keys()[0]
		team_scores[team] += capture_rate * delta
		hud_state = "Équipe %d capture · rotation %ds" % [team + 1, remain]
		check_win()
	elif present.size() >= 2:
		hud_state = "Hardpoint CONTESTÉ"
	else:
		hud_state = "Hardpoint neutre · rotation %ds" % remain

	# Synchro throttlée des scores / état.
	_sync_timer += delta
	if _sync_timer >= 0.25 or winner != -1:
		_sync_timer = 0.0
		sync_state.rpc(team_scores, winner, hud_state)
