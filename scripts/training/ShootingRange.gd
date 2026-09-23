## ShootingRange.gd
## "Stand de tir" (contract-r4a.md, R4-TRAIN #3) : mannequins statiques
## (5/15/30/50 m) + mobiles, stats touches/têtes/DPS (logique pure dans
## `RangeStats.gd`) branchées sur `Weapon.hit_confirmed` du joueur LOCAL, et
## un bouton de réinitialisation (plaque au sol) qui remet tous les
## mannequins et les stats à zéro. Le râtelier "10 armes" est le menu
## d'achat gratuit déjà câblé dans la scène (BuyMenu.gd, lu seul).
class_name ShootingRange
extends Node3D

const DUMMY_SCRIPT := preload("res://scripts/world/TrainingDummy.gd")
const MOVING_DUMMY_SCRIPT := preload("res://scripts/training/MovingDummy.gd")

var _player: PlayerController
var _weapon: Weapon
var _stats := RangeStats.new()
var _reset_cooldown: float = 0.0

var _panel: ComicPanel
var _hits_label: Label
var _headshots_label: Label
var _dps_label: Label

## Étiquettes de distance (5/15/30/50 m) : projetées à l'écran depuis la
## caméra du joueur local (`Camera3D.unproject_position`), PAS des `Label3D`
## dans le monde — un `Label3D` neuf ne s'affiche jamais dans cette scène une
## fois GameWorld/HUD en place (accroc moteur isolé, voir TrainingBuilder.gd),
## alors qu'un Control 2D (CanvasLayer) s'affiche toujours correctement.
var _distance_tags: Array = []  # Array[{node: StaticBody3D, label: Label}]

func _ready() -> void:
	_build_dummies()
	_build_reset_button()
	_build_ui()

func _build_dummies() -> void:
	for d in TrainingLayout.static_dummies():
		var dummy := StaticBody3D.new()
		dummy.set_script(DUMMY_SCRIPT)
		dummy.name = String(d["name"])
		dummy.position = d["pos"]
		add_child(dummy)
		var tag := Comic.label("%d m" % int(d["distance_m"]), Comic.SIZE_FLOOR, Comic.INK, Comic.FONT_HEAVY)
		tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tag.visible = false
		_distance_tags.append({"node": dummy, "label": tag})

	for d in TrainingLayout.moving_dummies():
		var dummy := StaticBody3D.new()
		dummy.set_script(MOVING_DUMMY_SCRIPT)
		dummy.name = String(d["name"])
		dummy.position = d["pos"]
		dummy.set("patrol_axis", d["axis"])
		dummy.set("patrol_distance", d["distance"])
		dummy.set("patrol_speed", d["speed"])
		add_child(dummy)

func _build_reset_button() -> void:
	var z: Dictionary = TrainingLayout.range_reset_zone()
	var area := Area3D.new()
	area.name = "ResetButton"
	area.position = z["pos"]
	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = float(z["radius"])
	shape.height = 1.0
	col.shape = shape
	area.add_child(col)
	add_child(area)
	area.body_entered.connect(_on_reset_entered)

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	for entry in _distance_tags:
		layer.add_child(entry["label"])

	# Bord gauche, centré verticalement : les coins sont déjà pris par le HUD
	# de combat (vie bas-gauche, munitions bas-droite — design.md §8, voir
	# GameHUD.gd, lu seul). Visible seulement sur place (voir _physics_process).
	_panel = ComicPanel.new()
	_panel.bg_color = Comic.PAPER_SHADE
	_panel.border_width = Comic.STROKE_LINE
	_panel.content_margin = Comic.SP_2
	Comic.anchor(_panel, Control.PRESET_CENTER_LEFT)
	_panel.offset_left = Comic.SAFE_MARGIN
	_panel.offset_right = Comic.SAFE_MARGIN + 260
	_panel.offset_top = -95
	_panel.offset_bottom = 95
	_panel.visible = false
	layer.add_child(_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	_panel.body.add_child(box)

	box.add_child(Comic.label("STAND DE TIR", Comic.SIZE_FLOOR, Comic.GRAPHITE, Comic.FONT_SEMI))
	_hits_label = Comic.label("Touches : 0", Comic.SIZE_BODY, Comic.INK, Comic.FONT_SEMI)
	box.add_child(_hits_label)
	_headshots_label = Comic.label("Têtes : 0 (0 %)", Comic.SIZE_BODY, Comic.INK, Comic.FONT_SEMI)
	box.add_child(_headshots_label)
	_dps_label = Comic.number_label("DPS : 0", Comic.SIZE_BODY, Comic.INK)
	box.add_child(_dps_label)
	_refresh_ui()

func _physics_process(delta: float) -> void:
	if _reset_cooldown > 0.0:
		_reset_cooldown -= delta
	if _player == null or not is_instance_valid(_player):
		_find_player()
	else:
		var p := _player.global_position
		var in_range := TrainingLayout.point_in_zone(Vector2(p.x, p.z), TrainingLayout.range_zone())
		_panel.visible = in_range
		_update_distance_tags(in_range)
	var now := Time.get_ticks_msec() / 1000.0
	_dps_label.text = "DPS : %d" % int(round(_stats.dps(now)))

## Repositionne chaque étiquette "N m" au-dessus de son mannequin, projetée
## à l'écran par la caméra ACTIVE du joueur — masquée si le mannequin est
## derrière la caméra, hors zone du stand de tir, ou pas de caméra active.
func _update_distance_tags(in_range: bool) -> void:
	var cam := _player.camera if _player else null
	if not in_range or cam == null or not cam.current:
		for entry in _distance_tags:
			(entry["label"] as Label).visible = false
		return
	for entry in _distance_tags:
		var node: Node3D = entry["node"]
		var label: Label = entry["label"]
		var world_pos := node.global_position + Vector3(0, 2.3, 0)
		if cam.is_position_behind(world_pos):
			label.visible = false
			continue
		label.visible = true
		var screen_pos := cam.unproject_position(world_pos)
		label.position = screen_pos - label.size * 0.5

func _find_player() -> void:
	var arr := get_tree().get_nodes_in_group("local_player")
	if arr.is_empty():
		return
	_player = arr[0] as PlayerController
	if _player == null:
		return
	_weapon = _player.get_node_or_null("Weapon") as Weapon
	if _weapon:
		_weapon.hit_confirmed.connect(_on_hit_confirmed)

## `pos` = point de la touche confirmée : ne compte que les touches tombant
## dans le rayon du stand de tir (`TrainingLayout.range_zone`) — un mannequin
## de la corniche "Capacités" abattu à l'arme ne doit pas fausser ces stats.
func _on_hit_confirmed(pos: Vector3, dmg: float, headshot: bool) -> void:
	if not TrainingLayout.point_in_zone(Vector2(pos.x, pos.z), TrainingLayout.range_zone()):
		return
	_stats.record_hit(dmg, headshot, Time.get_ticks_msec() / 1000.0)
	_refresh_ui()

func _on_reset_entered(body: Node3D) -> void:
	if not (body is PlayerController) or not (body as PlayerController).is_local_human():
		return
	if _reset_cooldown > 0.0:
		return
	_reset_cooldown = 1.0
	_stats.reset()
	for child in get_children():
		var hp = child.get("health")
		if hp is Health:
			hp.reset()
	_refresh_ui()

func _refresh_ui() -> void:
	if _hits_label == null:
		return
	_hits_label.text = "Touches : %d" % _stats.shots_hit
	_headshots_label.text = "Têtes : %d (%d %%)" % [_stats.headshots, int(round(_stats.headshot_ratio() * 100.0))]
