## GameHUD.gd
## HUD de jeu construit par code, look pro et cohérent : modules à panneaux
## arrondis translucides (vie, munitions, capacités, score), crosshair épuré,
## killfeed, scoreboard (Tab), écrans de mort et de fin. Se branche automatiquement
## sur le joueur local (groupe "local_player") et ses composants.
extends CanvasLayer

const ACCENT := Color(1.0, 0.8, 0.12)
const PANEL_BG := Color(0.07, 0.07, 0.1, 0.86)
const TEXT := Color(0.93, 0.95, 0.99)
const DIM := Color(0.62, 0.67, 0.78)
const HP_GOOD := Color(0.32, 0.86, 0.46)
const HP_BAD := Color(0.92, 0.26, 0.26)
const FONT_BLACK := preload("res://resources/fonts/Lato-Black.ttf")

var _player: PlayerController
var _health: Health
var _weapon: Weapon

var _crosshair: Control
var _hp_bar: ProgressBar
var _hp_fill_style: StyleBoxFlat
var _hp_label: Label
var _ammo_label: Label
var _reserve_label: Label
var _weapon_label: Label
var _inv_label: Label
var _debug_label: Label
var _death_panel: ColorRect
var _scope: TextureRect
var _scope_reticle: Control
var _abilities: Node
var _ability_box: HBoxContainer
var _ability_chips: Array = []
var _mode: Node
var _score_label: Label
var _objective_label: Label
var _match: Node
var _killfeed_box: VBoxContainer
var _scoreboard: Control
var _scoreboard_list: VBoxContainer
var _end_panel: Control
var _end_label: Label
var _end_shown: bool = false

func _ready() -> void:
	_build()

# ----------------------------------------------------------- Styles utilitaires
func _round_panel(bg: Color, radius: int = 6, accent_edge: bool = false) -> StyleBoxFlat:
	# Panneau "comic" : gros contour encre (ou magenta pour accent).
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.content_margin_left = 16
	s.content_margin_right = 16
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	s.set_border_width_all(5)
	s.border_color = Color(1.0, 0.13, 0.5) if accent_edge else Color(0.05, 0.05, 0.07)
	return s

func _lab(text: String, size: int, color: Color, outline: bool = false, black: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	if black:
		l.add_theme_font_override("font", FONT_BLACK)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if outline:
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
		l.add_theme_constant_override("outline_size", 5)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

# ----------------------------------------------------------- Construction
func _build() -> void:
	_build_crosshair()
	_build_health()
	_build_ammo()
	_build_abilities()
	_build_score()
	_build_killfeed()
	_build_debug()
	_build_death()
	_build_scoreboard()
	_build_end_panel()
	_build_scope()
	# Rien ne doit intercepter la souris (sinon look/lunette bloqués).
	_ignore_mouse(self)

func _build_crosshair() -> void:
	_crosshair = Control.new()
	_crosshair.set_anchors_preset(Control.PRESET_CENTER)
	_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_crosshair)
	var col := Color(0.95, 1.0, 0.97, 0.92)
	_cross_line(_crosshair, Rect2(-1, -12, 2, 7), col)
	_cross_line(_crosshair, Rect2(-1, 5, 2, 7), col)
	_cross_line(_crosshair, Rect2(-12, -1, 7, 2), col)
	_cross_line(_crosshair, Rect2(5, -1, 7, 2), col)
	_cross_line(_crosshair, Rect2(-1, -1, 2, 2), col)

func _build_health() -> void:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _round_panel(PANEL_BG, 14))
	p.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	p.grow_vertical = Control.GROW_DIRECTION_BEGIN
	p.grow_horizontal = Control.GROW_DIRECTION_END
	p.offset_left = 28
	p.offset_bottom = -28
	add_child(p)

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 14)
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	p.add_child(hb)

	var icon := _lab("✚", 30, HP_GOOD)
	hb.add_child(icon)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	hb.add_child(col)
	col.add_child(_lab("VITALITÉ", 11, DIM))

	_hp_bar = ProgressBar.new()
	_hp_bar.custom_minimum_size = Vector2(230, 14)
	_hp_bar.min_value = 0
	_hp_bar.max_value = 100
	_hp_bar.value = 100
	_hp_bar.show_percentage = false
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.5)
	bg.set_corner_radius_all(5)
	_hp_fill_style = StyleBoxFlat.new()
	_hp_fill_style.bg_color = HP_GOOD
	_hp_fill_style.set_corner_radius_all(5)
	_hp_bar.add_theme_stylebox_override("background", bg)
	_hp_bar.add_theme_stylebox_override("fill", _hp_fill_style)
	col.add_child(_hp_bar)

	_hp_label = _lab("100", 32, TEXT, false, true)
	_hp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hb.add_child(_hp_label)

func _build_ammo() -> void:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _round_panel(PANEL_BG, 14))
	p.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	p.grow_vertical = Control.GROW_DIRECTION_BEGIN
	p.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	p.offset_right = -28
	p.offset_bottom = -28
	add_child(p)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	v.alignment = BoxContainer.ALIGNMENT_END
	p.add_child(v)

	_weapon_label = _lab("", 19, ACCENT)
	_weapon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_weapon_label.size_flags_horizontal = Control.SIZE_SHRINK_END
	v.add_child(_weapon_label)

	var ammo_row := HBoxContainer.new()
	ammo_row.alignment = BoxContainer.ALIGNMENT_END
	ammo_row.add_theme_constant_override("separation", 6)
	v.add_child(ammo_row)
	_ammo_label = _lab("--", 38, TEXT, false, true)
	ammo_row.add_child(_ammo_label)
	_reserve_label = _lab("/ --", 20, DIM)
	_reserve_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ammo_row.add_child(_reserve_label)

	_inv_label = _lab("", 14, DIM)
	_inv_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_inv_label.size_flags_horizontal = Control.SIZE_SHRINK_END
	v.add_child(_inv_label)

func _build_abilities() -> void:
	_ability_box = HBoxContainer.new()
	_ability_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_ability_box.add_theme_constant_override("separation", 10)
	_ability_box.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_ability_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_ability_box.offset_bottom = -26
	_ability_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_ability_box)

func _build_score() -> void:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _round_panel(PANEL_BG, 12))
	p.set_anchors_preset(Control.PRESET_CENTER_TOP)
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.grow_vertical = Control.GROW_DIRECTION_END
	p.offset_top = 14
	add_child(p)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 1)
	p.add_child(v)
	_score_label = _lab("", 26, TEXT, false, true)
	_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_score_label)
	_objective_label = _lab("", 13, DIM)
	_objective_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_objective_label)

func _build_killfeed() -> void:
	_killfeed_box = VBoxContainer.new()
	_killfeed_box.alignment = BoxContainer.ALIGNMENT_BEGIN
	_killfeed_box.add_theme_constant_override("separation", 4)
	_killfeed_box.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_killfeed_box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_killfeed_box.offset_top = 70
	_killfeed_box.offset_right = -20
	add_child(_killfeed_box)

func _build_debug() -> void:
	# Lecture vitesse/état, volontairement discrète (haut-gauche, dim).
	_debug_label = _lab("", 13, Color(0.7, 0.74, 0.82, 0.55))
	_debug_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_debug_label.offset_left = 22
	_debug_label.offset_top = 16
	add_child(_debug_label)

func _build_death() -> void:
	_death_panel = ColorRect.new()
	_death_panel.color = Color(0.35, 0.0, 0.0, 0.42)
	_death_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_death_panel.visible = false
	_death_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_death_panel)
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_CENTER)
	v.grow_horizontal = Control.GROW_DIRECTION_BOTH
	v.grow_vertical = Control.GROW_DIRECTION_BOTH
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	_death_panel.add_child(v)
	var t := _lab("ÉLIMINÉ", 72, Color(0.95, 0.92, 0.92), true, true)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var s := _lab("Réapparition imminente…", 20, Color(0.85, 0.7, 0.7), true)
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(s)

func _build_scope() -> void:
	var s := 256
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 1))
	var c := s / 2.0
	var r := s * 0.47
	for y in s:
		for x in s:
			if Vector2(x - c, y - c).length() < r - 4.0:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
	var tex := ImageTexture.create_from_image(img)
	_scope = TextureRect.new()
	_scope.texture = tex
	_scope.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_scope.stretch_mode = TextureRect.STRETCH_SCALE
	_scope.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scope.visible = false
	_scope.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_scope)

	_scope_reticle = Control.new()
	_scope_reticle.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scope_reticle.visible = false
	_scope_reticle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hbar := ColorRect.new()
	hbar.color = Color(0, 0, 0, 0.9)
	hbar.set_anchors_preset(Control.PRESET_CENTER)
	hbar.offset_left = -120; hbar.offset_right = 120; hbar.offset_top = -1; hbar.offset_bottom = 1
	_scope_reticle.add_child(hbar)
	var vbar := ColorRect.new()
	vbar.color = Color(0, 0, 0, 0.9)
	vbar.set_anchors_preset(Control.PRESET_CENTER)
	vbar.offset_left = -1; vbar.offset_right = 1; vbar.offset_top = -120; vbar.offset_bottom = 120
	_scope_reticle.add_child(vbar)
	add_child(_scope_reticle)

func _ignore_mouse(node: Node) -> void:
	for c in node.get_children():
		if c is Control and not (c is BaseButton) and not (c is Range):
			c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_ignore_mouse(c)

func _cross_line(parent: Control, r: Rect2, c: Color) -> void:
	var outline := ColorRect.new()
	outline.color = Color(0, 0, 0, 0.55)
	outline.offset_left = r.position.x - 1
	outline.offset_top = r.position.y - 1
	outline.offset_right = r.position.x + r.size.x + 1
	outline.offset_bottom = r.position.y + r.size.y + 1
	outline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(outline)
	var rect := ColorRect.new()
	rect.color = c
	rect.offset_left = r.position.x
	rect.offset_top = r.position.y
	rect.offset_right = r.position.x + r.size.x
	rect.offset_bottom = r.position.y + r.size.y
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(rect)

# ----------------------------------------------------------- Scoreboard / fin
func _build_scoreboard() -> void:
	_scoreboard = ColorRect.new()
	_scoreboard.color = Color(0.03, 0.04, 0.07, 0.86)
	_scoreboard.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scoreboard.visible = false
	add_child(_scoreboard)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scoreboard.add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _round_panel(Color(0.08, 0.09, 0.14, 0.95), 16))
	center.add_child(panel)
	_scoreboard_list = VBoxContainer.new()
	_scoreboard_list.custom_minimum_size = Vector2(560, 0)
	panel.add_child(_scoreboard_list)
	var lbl := _lab("", 22, TEXT)
	lbl.name = "Text"
	_scoreboard_list.add_child(lbl)

func _build_end_panel() -> void:
	_end_panel = ColorRect.new()
	_end_panel.color = Color(0.03, 0.04, 0.07, 0.85)
	_end_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_end_panel.visible = false
	add_child(_end_panel)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_end_panel.add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _round_panel(Color(0.09, 0.1, 0.16, 0.97), 18))
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	box.custom_minimum_size = Vector2(360, 0)
	panel.add_child(box)
	_end_label = _lab("", 46, ACCENT, false, true)
	_end_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_end_label)
	var replay := Button.new()
	replay.text = "Rejouer"
	replay.custom_minimum_size = Vector2(0, 48)
	replay.pressed.connect(_on_replay)
	box.add_child(replay)
	var menu := Button.new()
	menu.text = "Retour au menu"
	menu.custom_minimum_size = Vector2(0, 48)
	menu.pressed.connect(func():
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn"))
	box.add_child(menu)

func _team_color(t: int) -> Color:
	match t:
		0: return Color(0.45, 0.7, 1.0)
		1: return Color(1.0, 0.5, 0.4)
	return Color(0.85, 0.85, 0.85)

func _on_kill_logged(killer: String, victim: String, killer_team: int) -> void:
	if _killfeed_box == null:
		return
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _round_panel(Color(0.05, 0.06, 0.1, 0.7), 8))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := Label.new()
	l.text = "%s   ▸   %s" % [killer, victim]
	l.add_theme_font_size_override("font_size", 17)
	l.add_theme_color_override("font_color", _team_color(killer_team))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(l)
	_killfeed_box.add_child(p)
	get_tree().create_timer(5.0).timeout.connect(func(): if is_instance_valid(p): p.queue_free())

func _refresh_scoreboard() -> void:
	if _match == null or _scoreboard_list == null:
		return
	var lbl := _scoreboard_list.get_node_or_null("Text") as Label
	if lbl == null:
		return
	var info: Dictionary = _match.player_info
	var txt := "TABLEAU DES SCORES\n"
	for team in [0, 1]:
		txt += "\nÉQUIPE %d\n" % (team + 1)
		for id in info:
			if int(info[id].team) == team:
				txt += "   %-16s  %d / %d\n" % [str(info[id].name), int(info[id].kills), int(info[id].deaths)]
	lbl.text = txt

func _update_end() -> void:
	if _mode == null or _end_panel == null:
		return
	var over: bool = _mode.winner >= 0
	if over and not _end_shown:
		_end_shown = true
		_end_label.text = "ÉQUIPE %d GAGNE !" % (_mode.winner + 1)
		_end_panel.visible = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif not over and _end_shown:
		_end_shown = false
		_end_panel.visible = false
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _on_replay() -> void:
	if _match == null:
		return
	if multiplayer.is_server():
		_match.reset_match()
	else:
		_match.request_reset.rpc_id(1)

# ----------------------------------------------------------- Boucle
func _process(_delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_acquire_player()
		return
	if _debug_label:
		var ground := "SOL" if _player.is_on_floor() else "AIR"
		_debug_label.text = "%.1f m/s · %s · %s" % [_player.horizontal_speed(), _player.state_machine.current_name, ground]
	_update_abilities()
	_update_scoreboard()

	if _match == null or not is_instance_valid(_match):
		_match = get_tree().get_first_node_in_group("match")
		if _match and _match.has_signal("kill_logged") and not _match.kill_logged.is_connected(_on_kill_logged):
			_match.kill_logged.connect(_on_kill_logged)
	if _scoreboard:
		var show_sb: bool = Input.is_action_pressed("scoreboard") or (_mode != null and _mode.winner >= 0)
		_scoreboard.visible = show_sb
		if show_sb:
			_refresh_scoreboard()
	_update_end()

	if _weapon and _scope:
		var scoping: bool = _weapon.is_scoped() and Input.is_action_pressed("aim") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
		_scope.visible = scoping
		_scope_reticle.visible = scoping
		if _crosshair:
			_crosshair.visible = not scoping

func _acquire_player() -> void:
	var arr := get_tree().get_nodes_in_group("local_player")
	if arr.is_empty():
		return
	_player = arr[0]
	_health = _player.get_node_or_null("Health")
	_weapon = _player.get_node_or_null("Weapon")
	_abilities = _player.get_node_or_null("Abilities")
	if _health:
		_health.health_changed.connect(_on_health_changed)
		_health.died.connect(_on_died)
		_health.respawned.connect(_on_respawned)
		_on_health_changed(_health.current_health, _health.max_health)
	if _weapon:
		_weapon.ammo_changed.connect(_on_ammo_changed)
		_weapon.weapon_changed.connect(_on_weapon_changed)
		if _weapon.cfg():
			_on_weapon_changed(_weapon.cfg())
		if _weapon.current < _weapon.mag.size():
			_on_ammo_changed(_weapon.mag[_weapon.current], _weapon.reserve_a[_weapon.current])

func _on_health_changed(current: float, maximum: float) -> void:
	if _hp_bar:
		_hp_bar.max_value = maximum
		_hp_bar.value = current
	if _hp_fill_style:
		var ratio := clampf(current / maximum, 0.0, 1.0)
		_hp_fill_style.bg_color = HP_BAD.lerp(HP_GOOD, ratio)
	if _hp_label:
		_hp_label.text = "%d" % roundi(current)

func _on_ammo_changed(ammo: int, reserve: int) -> void:
	if _ammo_label:
		_ammo_label.text = "%d" % ammo
	if _reserve_label:
		_reserve_label.text = "/ %d" % reserve

func _update_scoreboard() -> void:
	if _score_label == null:
		return
	if _mode == null or not is_instance_valid(_mode):
		_mode = get_tree().get_first_node_in_group("game_mode")
	if _mode == null:
		return
	if _mode.winner >= 0:
		_score_label.text = "%d   ÉQUIPE %d GAGNE   %d" % [_mode.team_score(0), _mode.winner + 1, _mode.team_score(1)]
		_objective_label.text = ""
	else:
		_score_label.text = "ÉQ.1   %d   —   %d   ÉQ.2" % [_mode.team_score(0), _mode.team_score(1)]
		_objective_label.text = str(_mode.hud_state)

func _update_abilities() -> void:
	if _ability_box == null or _abilities == null or not _abilities.has_method("slot_info"):
		return
	var infos: Array = _abilities.slot_info()
	# Construit les badges crantés une fois (nombre de slots stable par agent).
	if _ability_chips.size() != infos.size():
		for ch in _ability_box.get_children():
			ch.queue_free()
		_ability_chips.clear()
		for i in infos.size():
			var s: Dictionary = infos[i]
			var col: Color = Comic.SLOT_COLORS[i % Comic.SLOT_COLORS.size()]
			if s.ult:
				col = Comic.RED
			var chip := ComicChip.new()
			chip.setup(str(s.slot), str(s.name), col)
			_ability_box.add_child(chip)
			_ability_chips.append(chip)
		return
	# Met à jour le statut de chaque badge.
	for i in infos.size():
		var s: Dictionary = infos[i]
		var chip: ComicChip = _ability_chips[i]
		var txt := ""
		var dim := true
		if s.ult:
			txt = "PRÊT" if s.ready else "%d%%" % int(s.ratio * 100.0)
			dim = not s.ready
		elif s.charges > 0:
			txt = "x%d" % s.charges
			dim = false
		else:
			txt = "%d%%" % int(s.ratio * 100.0)
			dim = true
		chip.set_status(txt, dim)

func _on_weapon_changed(cfg: WeaponConfig) -> void:
	if _weapon_label and cfg:
		_weapon_label.text = cfg.weapon_name
	_update_inventory()

func _update_inventory() -> void:
	if _inv_label == null or _weapon == null:
		return
	var parts: Array = []
	for i in _weapon.weapons.size():
		var w = _weapon.weapons[i]
		var nm: String = w.weapon_name if w else "—"
		parts.append(("● " + nm) if i == _weapon.current else ("○ " + nm))
	_inv_label.text = "    ".join(parts)

func _on_died(_killer_id: int) -> void:
	if _death_panel:
		_death_panel.visible = true

func _on_respawned() -> void:
	if _death_panel:
		_death_panel.visible = false
