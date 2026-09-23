## TimeTrialCourse.gd
## "Contre-la-montre" (contract-r4a.md, R4-TRAIN #2) : chronomètre le
## parcours de mouvement (mêmes checkpoints que `TrainingLayout.checkpoints()`
## — CP0 = portique de départ, dernier = arrivée), calcule la médaille
## (Or/Argent/Bronze) et sauvegarde le meilleur temps local (`user://`, voir
## `TrainingRecords.gd`). Logique de progression/médaille pure dans
## `TimeTrialRules.gd`. Touche "pickup" (E) = redémarrer immédiatement, sans
## avoir à retraverser le portique de départ.
class_name TimeTrialCourse
extends Node3D

## Seuils de médaille (s) — ajustables sans casser les tests (logique pure
## dans TimeTrialRules ; ces valeurs ne sont QUE la config de cette instance).
@export var gold_time: float = 22.0
@export var silver_time: float = 30.0
@export var bronze_time: float = 40.0

const COURSE_ID := "parcours"

var _checkpoints: Array = []  # Array[Area3D], dans l'ordre de TrainingLayout.checkpoints()
var _next_cp: int = 0
var _elapsed: float = 0.0
var _running: bool = false
var _last_result_text: String = ""

var _panel: ComicPanel
var _timer_label: Label
var _result_label: Label
var _best_label: Label
var _player: PlayerController

func _ready() -> void:
	_build_checkpoints()
	_build_ui()
	_refresh_ui()

func _build_checkpoints() -> void:
	var i := 0
	for cp in TrainingLayout.checkpoints():
		var area := Area3D.new()
		area.name = String(cp["name"])
		area.position = cp["pos"]
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(10, 6, 2)
		col.shape = shape
		area.add_child(col)
		var mesh := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(10, 6, 0.2)
		mesh.mesh = bm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(Comic.ALLY.r, Comic.ALLY.g, Comic.ALLY.b, 0.12)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mesh.material_override = mat
		area.add_child(mesh)
		add_child(area)
		area.body_entered.connect(_on_checkpoint_entered.bind(i))
		_checkpoints.append(area)
		i += 1

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)

	# Assez large pour la phrase d'invite ("Traversez le portique...") SANS
	# déborder de l'écran (constaté en capture : 260 px la coupait à mi-mot) —
	# + habillage en mots (`autowrap_mode`) en filet de sécurité.
	_panel = ComicPanel.new()
	_panel.bg_color = Comic.PAPER_SHADE
	_panel.border_width = Comic.STROKE_LINE
	_panel.content_margin = Comic.SP_2
	Comic.anchor(_panel, Control.PRESET_TOP_RIGHT)
	_panel.offset_left = -340
	_panel.offset_right = -Comic.SAFE_MARGIN
	_panel.offset_top = Comic.SAFE_MARGIN
	_panel.offset_bottom = Comic.SAFE_MARGIN + 130
	layer.add_child(_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	_panel.body.add_child(box)

	_timer_label = Comic.number_label("00:00.00", Comic.SIZE_LABEL, Comic.INK)
	box.add_child(_timer_label)
	_result_label = Comic.label("", Comic.SIZE_FLOOR, Comic.GRAPHITE, Comic.FONT_SEMI)
	_result_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	box.add_child(_result_label)
	_best_label = Comic.label("", Comic.SIZE_FLOOR, Comic.GRAPHITE, Comic.FONT_SEMI)
	box.add_child(_best_label)
	_panel.visible = false

func _physics_process(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_find_player()
	else:
		var p := _player.global_position
		# Visible sur le parcours, OU hors zone si une manche tourne déjà (ne
		# jamais faire disparaître le chrono en cours de course).
		_panel.visible = _running or TrainingLayout.point_in_zone(Vector2(p.x, p.z), TrainingLayout.course_zone())
	if _running:
		_elapsed += delta
		_timer_label.text = TimeTrialRules.format_time(_elapsed)
	if Input.is_action_just_pressed("pickup"):
		_restart()

func _find_player() -> void:
	var arr := get_tree().get_nodes_in_group("local_player")
	if not arr.is_empty():
		_player = arr[0] as PlayerController

func _on_checkpoint_entered(body: Node3D, cp_index: int) -> void:
	if not (body is PlayerController) or not (body as PlayerController).is_local_human():
		return
	if cp_index == 0:
		_restart()
		return
	var before := _next_cp
	_next_cp = TimeTrialRules.advance_checkpoint(_next_cp, cp_index, _checkpoints.size())
	if _next_cp == before:
		return  # checkpoint hors ordre : ignoré (contract : progression séquentielle).
	if TimeTrialRules.is_finished(_next_cp, _checkpoints.size()):
		_finish()

func _restart() -> void:
	_running = true
	_elapsed = 0.0
	_next_cp = 1
	_last_result_text = ""
	_refresh_ui()

func _finish() -> void:
	_running = false
	var medal := TimeTrialRules.medal_for_time(_elapsed, gold_time, silver_time, bronze_time)
	var is_best := TrainingRecords.save_best_time(_elapsed, COURSE_ID)
	var medal_text := _medal_label(medal)
	_last_result_text = "%s — %s%s" % [TimeTrialRules.format_time(_elapsed), medal_text, "  (RECORD !)" if is_best else ""]
	_refresh_ui()

func _medal_label(medal: String) -> String:
	match medal:
		TimeTrialRules.MEDAL_GOLD:
			return "MÉDAILLE OR"
		TimeTrialRules.MEDAL_SILVER:
			return "MÉDAILLE ARGENT"
		TimeTrialRules.MEDAL_BRONZE:
			return "MÉDAILLE BRONZE"
		_:
			return "Aucune médaille"

func _refresh_ui() -> void:
	if _timer_label == null:
		return
	_timer_label.text = TimeTrialRules.format_time(_elapsed)
	_result_label.text = _last_result_text if _last_result_text != "" else ("Traversez le portique de départ (%s pour redémarrer)" % KeyLabel.for_action("pickup"))
	var best := TrainingRecords.load_best_time(COURSE_ID)
	_best_label.text = "Meilleur temps : %s" % (TimeTrialRules.format_time(best) if best > 0.0 else "—")
