## MovementTutorial.gd
## "Parcours de mouvement" (contract-r4a.md, R4-TRAIN #1) : affiche l'étape
## courante (français, touche réelle du joueur — Settings/DisplayServer) et
## détecte sa réussite depuis la state machine / vitesse du joueur local
## (logique pure dans `StepRules.gd`). Se branche tout seul sur le joueur
## local (groupe "local_player", posé quelques frames après le spawn de
## GameWorld — voir PlayerController.is_local_human) : pas de câblage manuel
## nécessaire depuis la scène.
class_name MovementTutorial
extends Node3D

var _player: PlayerController
var _prev_state: String = ""
var _step_index: int = 0
var _dive_start_pos: Vector3 = Vector3.ZERO
var _finished: bool = false

var _panel: ComicPanel
var _step_label: Label
var _progress_label: Label

func _ready() -> void:
	_build_ui()

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)

	# Haut-gauche : coin libre du HUD de combat (design.md §8 — vie bas-gauche,
	# munitions bas-droite, barre de capacités en bas : voir GameHUD.gd, lu
	# seul). Visible SEULEMENT sur le parcours (`_refresh_visibility`), donc
	# jamais superposé aux panneaux des deux autres zones non plus.
	_panel = ComicPanel.new()
	_panel.bg_color = Comic.PAPER
	_panel.border_width = Comic.STROKE_LINE
	_panel.content_margin = Comic.SP_3
	Comic.anchor(_panel, Control.PRESET_TOP_LEFT)
	_panel.offset_left = Comic.SAFE_MARGIN
	_panel.offset_top = Comic.SAFE_MARGIN
	_panel.offset_right = Comic.SAFE_MARGIN + 420
	_panel.offset_bottom = Comic.SAFE_MARGIN + 108
	layer.add_child(_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", Comic.SP_1)
	_panel.body.add_child(box)

	_progress_label = Comic.label("PARCOURS — ÉTAPE 1 / %d" % StepRules.STEP_IDS.size(), Comic.SIZE_LABEL, Comic.GRAPHITE, Comic.FONT_SEMI)
	box.add_child(_progress_label)

	_step_label = Comic.label("", Comic.SIZE_BODY, Comic.INK, Comic.FONT_BODY)
	_step_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	box.add_child(_step_label)

	_panel.visible = false
	_refresh_ui()

func _physics_process(_delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_find_player()
		return
	_refresh_visibility()
	if _finished:
		return
	_poll_continuous_steps()

## N'affiche le panneau que sur le parcours (contract-r4a.md : "on-screen
## prompts") — jamais superposé aux panneaux des deux autres zones, ni au
## HUD de combat (design.md §8 : coins déjà pris par GameHUD.gd, lu seul).
func _refresh_visibility() -> void:
	var p := _player.global_position
	_panel.visible = TrainingLayout.point_in_zone(Vector2(p.x, p.z), TrainingLayout.course_zone())

func _find_player() -> void:
	var arr := get_tree().get_nodes_in_group("local_player")
	if arr.is_empty():
		return
	_player = arr[0] as PlayerController
	if _player and _player.state_machine:
		_prev_state = _player.state_machine.current_name
		_player.state_machine.state_changed.connect(_on_state_changed)

func _on_state_changed(to_state: String) -> void:
	if _finished or _player == null:
		return
	var from_state := _prev_state
	_prev_state = to_state
	if to_state == "Dive" and from_state != "Dive":
		_dive_start_pos = _player.global_position

	var step_id: String = StepRules.STEP_IDS[_step_index]
	var completed := false
	match step_id:
		"slide":
			completed = StepRules.is_slide_step(from_state, to_state)
		"slide_cancel":
			completed = StepRules.is_slide_cancel_step(from_state, to_state)
		"slide_jump":
			completed = StepRules.is_slide_jump_step(from_state, to_state, _player.slide_jumped)
		"dive_gap":
			completed = StepRules.is_dive_gap_step(from_state, to_state, _dive_start_pos, _player.global_position)
		"landing_roll":
			completed = StepRules.is_landing_roll_step(from_state, to_state)
	if completed:
		_advance_step()

## Étapes qui ne se détectent pas à une TRANSITION mais en continu (vitesse
## au sol/en l'air) : interrogées chaque tick physique.
func _poll_continuous_steps() -> void:
	if _step_index >= StepRules.STEP_IDS.size():
		return
	var step_id: String = StepRules.STEP_IDS[_step_index]
	var completed := false
	match step_id:
		"sprint":
			completed = StepRules.is_sprint_step(_player.horizontal_speed(), _player.config.sprint_speed)
		"air_strafe":
			completed = StepRules.is_air_strafe_step(_player.state_machine.current_name, _player.horizontal_speed(), _player.config.sprint_speed)
	if completed:
		_advance_step()

func _advance_step() -> void:
	_step_index += 1
	if _step_index >= StepRules.STEP_IDS.size():
		_finished = true
	_refresh_ui()

func _refresh_ui() -> void:
	if _panel == null:
		return
	if _finished:
		_progress_label.text = "PARCOURS TERMINÉ"
		_step_label.text = "Bravo — recommencez à tout moment en retraversant le portique de départ."
		return
	var step_id: String = StepRules.STEP_IDS[_step_index]
	_progress_label.text = "PARCOURS — ÉTAPE %d / %d" % [_step_index + 1, StepRules.STEP_IDS.size()]
	var action := StepRules.action_for(step_id)
	var action_label := KeyLabel.for_action(action) if action != "" else ""
	_step_label.text = StepRules.format_text(step_id, action_label)
