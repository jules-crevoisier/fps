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

## Échange de côté (maps-spec-v2.md §5.6.2/§7.5) — voir TDMMode.gd pour le
## détail complet de la convention (identique ici, dupliqué car GameMode.gd
## n'est pas dans mon périmètre cette manche). `side_swap_notice` reste séparé
## de `hud_state`, réécrit CHAQUE frame plus bas par la logique de capture.
@export var asymmetric_map: bool = false
var sides_swapped: bool = false
var side_swap_notice: String = ""

@rpc("authority", "call_local", "reliable")
func sync_sides_swapped(swapped: bool, notice: String) -> void:
	sides_swapped = swapped
	side_swap_notice = notice
	updated.emit()

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

## Délai (s) avant rotation en dessous duquel on annonce le prochain point
## (contrat R2 : "hardpoint next-zone preview" 15 s à l'avance).
const PREVIEW_LEAD := 15.0

func _physics_process(delta: float) -> void:
	super._physics_process(delta)  # minuteur de MATCH (10 min) commun
	if not multiplayer.is_server() or winner != -1:
		return

	if asymmetric_map and not sides_swapped:
		if HalfTime.should_swap(match_elapsed, match_time_limit, team_scores[0], team_scores[1], score_to_win):
			sync_sides_swapped.rpc(true, "CHANGEMENT DE CÔTÉ")

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
	var preview := ""
	if _points.size() > 1 and remain <= int(PREVIEW_LEAD):
		var next_index := (_point_index + 1) % _points.size()
		preview = " · prochain point P%d dans %ds" % [next_index + 1, remain]
	if present.size() == 1:
		var team: int = present.keys()[0]
		team_scores[team] += capture_rate * delta
		hud_state = "Équipe %d capture%s" % [team + 1, preview]
		check_win()
	elif present.size() >= 2:
		hud_state = "Hardpoint CONTESTÉ%s" % preview
	else:
		hud_state = "Hardpoint neutre%s" % preview

	# Synchro throttlée des scores / état.
	_sync_timer += delta
	if _sync_timer >= 0.25 or winner != -1:
		_sync_timer = 0.0
		sync_state.rpc(team_scores, winner, hud_state)

## Tic sonore CLIENT (tous les pairs, y compris l'hôte) tant que l'équipe
## LOCALE capture SEULE le point (détecté via `hud_state`, répliqué par
## `sync_state` — R-E audio, "hardpoint_tick", ≈1/s).
var _tick_sfx_timer: float = 0.0

func _process(delta: float) -> void:
	var local_team := _local_player_team()
	if local_team < 0 or not hud_state.begins_with("Équipe %d capture" % (local_team + 1)):
		_tick_sfx_timer = 0.0
		return
	_tick_sfx_timer += delta
	if _tick_sfx_timer >= 1.0:
		_tick_sfx_timer = 0.0
		_play_sfx_ui("hardpoint_tick")

## Hardpoint : la zone à tenir (même pour les deux équipes — l'objectif du
## mode, pas une cible par équipe).
func bot_goal_for(_team: int) -> Vector3:
	return _zone.global_position if _zone else Vector3.ZERO
