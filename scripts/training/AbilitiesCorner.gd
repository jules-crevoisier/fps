## AbilitiesCorner.gd
## "Capacités" (contract-r4a.md, R4-TRAIN #4) : corniche avec des mannequins
## + un sélecteur des 6 agents. `AbilityController.gd` (lu seul, pas dans mon
## lot) résout l'agent du joueur UNE fois à son `_ready` (`player.agent_index`
## répliqué au spawn) — il n'existe pas de "changement d'agent à chaud". Pour
## essayer les capacités de CHAQUE agent sans toucher AbilityController.gd/
## AgentConfig.gd (hors de mon lot), ce panneau règle `AgentDatabase.
## selected_index` (var statique publique) puis recharge la scène : le flux
## de spawn normal (agent_select=false -> AgentDatabase.selected_index,
## GameWorld.gd, lu seul) fait spawn le joueur avec l'agent choisi.
##
## Touche "pickup" (E) dans la zone : ouvre/ferme le sélecteur (souris
## relâchée, comme BuyMenu.gd) — les boutons ne sont cliquables QUE là, la
## souris restant capturée (visée FPS) le reste du temps.
class_name AbilitiesCorner
extends Node3D

const DUMMY_SCRIPT := preload("res://scripts/world/TrainingDummy.gd")

var _player: PlayerController
var _in_zone: bool = false
var _open: bool = false

var _layer: CanvasLayer
var _panel: ComicPanel
## Rappel de touche (2D, PAS un Label3D — voir TrainingBuilder.gd : un
## Label3D neuf ne s'affiche jamais dans cette scène une fois GameWorld/HUD
## en place, alors qu'un Control 2D s'affiche toujours correctement).
var _hint_panel: ComicPanel
var _hint_label: Label
var _bg: ColorRect

func _ready() -> void:
	_build_dummies()
	_build_ui()

func _build_dummies() -> void:
	for d in TrainingLayout.ability_dummies():
		var dummy := StaticBody3D.new()
		dummy.set_script(DUMMY_SCRIPT)
		dummy.name = String(d["name"])
		dummy.position = d["pos"]
		add_child(dummy)

func _build_ui() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 6
	add_child(_layer)

	_hint_panel = ComicPanel.new()
	_hint_panel.bg_color = Comic.PAPER
	_hint_panel.border_width = Comic.STROKE_LINE
	_hint_panel.content_margin = Comic.SP_2
	Comic.anchor(_hint_panel, Control.PRESET_CENTER_TOP)
	_hint_panel.offset_left = -260
	_hint_panel.offset_right = 260
	_hint_panel.offset_top = Comic.SAFE_MARGIN
	_hint_panel.offset_bottom = Comic.SAFE_MARGIN + 44
	_hint_panel.visible = false
	_layer.add_child(_hint_panel)
	_hint_label = Comic.label("", Comic.SIZE_BODY, Comic.INK, Comic.FONT_SEMI)
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_panel.body.add_child(_hint_label)

	_bg = ColorRect.new()
	_bg.color = Color(Comic.SHADOW_TINT.r, Comic.SHADOW_TINT.g, Comic.SHADOW_TINT.b, 0.6)
	_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bg.visible = false
	_layer.add_child(_bg)

	_panel = ComicPanel.new()
	_panel.bg_color = Comic.PAPER_SHADE
	_panel.border_width = Comic.STROKE_FRAME
	_panel.content_margin = Comic.SP_3
	Comic.anchor(_panel, Control.PRESET_CENTER)
	_panel.offset_left = -220
	_panel.offset_right = 220
	_panel.offset_top = -240
	_panel.offset_bottom = 240
	_panel.visible = false
	_layer.add_child(_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", Comic.SP_1)
	_panel.body.add_child(box)

	box.add_child(Comic.label("CAPACITÉS — CHANGER D'AGENT", Comic.SIZE_BODY, Comic.GRAPHITE, Comic.FONT_SEMI))

	var current := AgentDatabase.selected()
	box.add_child(Comic.label("Actuel : %s" % (current.agent_name if current else "?"), Comic.SIZE_BODY, Comic.INK, Comic.FONT_SEMI))

	var agents := AgentDatabase.all()
	for i in agents.size():
		var agent: AgentConfig = agents[i]
		var b := Button.new()
		b.text = "%s — %s" % [agent.agent_name, agent.role]
		b.custom_minimum_size = Vector2(0, 40)
		b.pressed.connect(_on_agent_picked.bind(i))
		box.add_child(b)

	var close := Button.new()
	close.text = "Fermer (%s)" % KeyLabel.for_action("pickup")
	close.custom_minimum_size = Vector2(0, 40)
	close.pressed.connect(_close)
	box.add_child(close)

func _physics_process(_delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_find_player()
		return
	var p := _player.global_position
	_in_zone = TrainingLayout.point_in_zone(Vector2(p.x, p.z), TrainingLayout.ability_zone())
	_hint_panel.visible = _in_zone and not _open
	_hint_label.text = "Capacités : %s — %s pour changer d'agent" % [_current_agent_name(), KeyLabel.for_action("pickup")]
	if not _in_zone and _open:
		_close()
	if _in_zone and Input.is_action_just_pressed("pickup"):
		if _open:
			_close()
		else:
			_open_panel()

func _current_agent_name() -> String:
	var a := AgentDatabase.selected()
	return a.agent_name if a else "?"

func _find_player() -> void:
	var arr := get_tree().get_nodes_in_group("local_player")
	if not arr.is_empty():
		_player = arr[0] as PlayerController

func _open_panel() -> void:
	_open = true
	_panel.visible = true
	_bg.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _close() -> void:
	_open = false
	_panel.visible = false
	_bg.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _on_agent_picked(index: int) -> void:
	AgentDatabase.selected_index = index
	get_tree().reload_current_scene()
