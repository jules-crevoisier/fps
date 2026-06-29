## GameHUD.gd
## HUD de jeu construit par code : crosshair, barre de vie, munitions, vitesse/état
## (debug) et écran de mort. Se branche automatiquement sur le joueur local
## (groupe "local_player") et ses composants Health / Weapon.
extends CanvasLayer

var _player: PlayerController
var _health: Health
var _weapon: Weapon

var _crosshair: Label
var _hp_fill: ColorRect
var _hp_label: Label
var _ammo_label: Label
var _weapon_label: Label
var _debug_label: Label
var _death_panel: ColorRect
var _death_label: Label
var _scope: TextureRect
var _scope_reticle: Control
var _inv_label: Label
var _abilities: Node
var _ability_label: Label
var _mode: Node
var _score_label: Label
var _match: Node
var _killfeed_box: VBoxContainer
var _scoreboard: Control
var _scoreboard_list: VBoxContainer
var _end_panel: Control
var _end_label: Label
var _end_shown: bool = false

func _ready() -> void:
	_build()

func _build() -> void:
	# Crosshair central.
	_crosshair = Label.new()
	_crosshair.text = "+"
	_crosshair.add_theme_font_size_override("font_size", 28)
	_crosshair.set_anchors_preset(Control.PRESET_CENTER)
	_crosshair.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_crosshair.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_crosshair.offset_left = -10
	_crosshair.offset_top = -18
	add_child(_crosshair)

	# Barre de vie (bas-gauche).
	var hp_bg := ColorRect.new()
	hp_bg.color = Color(0, 0, 0, 0.5)
	hp_bg.position = Vector2(24, 0)
	hp_bg.size = Vector2(260, 26)
	hp_bg.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	hp_bg.offset_left = 24
	hp_bg.offset_top = -60
	hp_bg.offset_right = 284
	hp_bg.offset_bottom = -34
	add_child(hp_bg)

	_hp_fill = ColorRect.new()
	_hp_fill.color = Color(0.2, 0.85, 0.3, 0.9)
	_hp_fill.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_hp_fill.offset_left = 26
	_hp_fill.offset_top = -58
	_hp_fill.offset_right = 282
	_hp_fill.offset_bottom = -36
	add_child(_hp_fill)

	_hp_label = _make_label(Control.PRESET_BOTTOM_LEFT, 18)
	_hp_label.offset_left = 30
	_hp_label.offset_top = -58
	_hp_label.text = "100"
	add_child(_hp_label)

	# Munitions (bas-droite).
	_ammo_label = _make_label(Control.PRESET_BOTTOM_RIGHT, 26)
	_ammo_label.offset_left = -180
	_ammo_label.offset_top = -60
	_ammo_label.offset_right = -24
	_ammo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_ammo_label.text = "-- / --"
	add_child(_ammo_label)

	# Nom de l'arme courante (au-dessus des munitions).
	_weapon_label = _make_label(Control.PRESET_BOTTOM_RIGHT, 20)
	_weapon_label.offset_left = -220
	_weapon_label.offset_top = -92
	_weapon_label.offset_right = -24
	_weapon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_weapon_label.text = ""
	add_child(_weapon_label)

	# Debug vitesse/état (haut-gauche).
	_debug_label = _make_label(Control.PRESET_TOP_LEFT, 22)
	_debug_label.offset_left = 24
	_debug_label.offset_top = 20
	add_child(_debug_label)

	# Écran de mort (plein écran, caché par défaut).
	_death_panel = ColorRect.new()
	_death_panel.color = Color(0.4, 0.0, 0.0, 0.45)
	_death_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_death_panel.visible = false
	_death_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_death_panel)

	_death_label = Label.new()
	_death_label.text = "ÉLIMINÉ"
	_death_label.add_theme_font_size_override("font_size", 64)
	_death_label.set_anchors_preset(Control.PRESET_CENTER)
	_death_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_death_label.offset_left = -300
	_death_label.offset_right = 300
	_death_label.offset_top = -40
	_death_panel.add_child(_death_label)

	# Inventaire (centre-bas) : liste des armes, courante entre crochets.
	_inv_label = _make_label(Control.PRESET_BOTTOM_WIDE, 18)
	_inv_label.offset_bottom = -16
	_inv_label.offset_top = -40
	_inv_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_inv_label.text = ""
	add_child(_inv_label)

	# Capacités (bas-gauche, au-dessus de la vie).
	_ability_label = _make_label(Control.PRESET_BOTTOM_LEFT, 18)
	_ability_label.offset_left = 24
	_ability_label.offset_top = -96
	_ability_label.offset_right = 700
	_ability_label.text = ""
	add_child(_ability_label)

	# Scoreboard (haut-centre).
	_score_label = _make_label(Control.PRESET_TOP_WIDE, 26)
	_score_label.offset_top = 14
	_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_score_label.text = ""
	add_child(_score_label)

	# Killfeed (haut-droite).
	_killfeed_box = VBoxContainer.new()
	_killfeed_box.alignment = BoxContainer.ALIGNMENT_BEGIN
	_killfeed_box.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_killfeed_box.offset_left = -420
	_killfeed_box.offset_top = 60
	_killfeed_box.offset_right = -16
	add_child(_killfeed_box)

	_build_scoreboard()
	_build_end_panel()

	_build_scope()
	# Aucun élément du HUD ne doit intercepter la souris (sinon le look est bloqué,
	# notamment le réticule de lunette centré sous le curseur capturé).
	_ignore_mouse(self)

func _ignore_mouse(node: Node) -> void:
	for c in node.get_children():
		# On laisse les éléments interactifs (boutons, sliders) recevoir la souris.
		if c is Control and not (c is BaseButton) and not (c is Range):
			c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_ignore_mouse(c)

func _build_scope() -> void:
	# Masque de lunette : noir partout sauf un disque central transparent.
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
	_scope.mouse_filter = Control.MOUSE_FILTER_IGNORE  # ne pas bloquer le look
	add_child(_scope)

	# Réticule de lunette : fine croix centrale.
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

func _build_scoreboard() -> void:
	_scoreboard = ColorRect.new()
	_scoreboard.color = Color(0.04, 0.05, 0.08, 0.85)
	_scoreboard.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scoreboard.visible = false
	add_child(_scoreboard)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scoreboard.add_child(center)
	_scoreboard_list = VBoxContainer.new()
	_scoreboard_list.custom_minimum_size = Vector2(560, 0)
	center.add_child(_scoreboard_list)
	var lbl := _make_label(Control.PRESET_TOP_LEFT, 22)
	lbl.name = "Text"
	_scoreboard_list.add_child(lbl)

func _build_end_panel() -> void:
	_end_panel = ColorRect.new()
	_end_panel.color = Color(0.04, 0.05, 0.08, 0.82)
	_end_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_end_panel.visible = false
	add_child(_end_panel)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_end_panel.add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	box.custom_minimum_size = Vector2(320, 0)
	center.add_child(box)
	_end_label = _make_label(Control.PRESET_TOP_WIDE, 48)
	_end_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_end_label)
	var replay := Button.new()
	replay.text = "Rejouer"
	replay.custom_minimum_size = Vector2(0, 46)
	replay.pressed.connect(_on_replay)
	box.add_child(replay)
	var menu := Button.new()
	menu.text = "Retour au menu"
	menu.custom_minimum_size = Vector2(0, 46)
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
	var l := Label.new()
	l.text = "%s  ▸  %s" % [killer, victim]
	l.add_theme_font_size_override("font_size", 18)
	l.add_theme_color_override("font_color", _team_color(killer_team))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	l.add_theme_constant_override("outline_size", 4)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_killfeed_box.add_child(l)
	get_tree().create_timer(5.0).timeout.connect(func(): if is_instance_valid(l): l.queue_free())

func _refresh_scoreboard() -> void:
	if _match == null or _scoreboard_list == null:
		return
	var lbl := _scoreboard_list.get_node_or_null("Text") as Label
	if lbl == null:
		return
	var info: Dictionary = _match.player_info
	var txt := "── TABLEAU DES SCORES ──\n"
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

func _make_label(preset: int, size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color(1, 1, 1))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	l.add_theme_constant_override("outline_size", 5)
	l.set_anchors_preset(preset)
	return l

func _process(_delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_acquire_player()
		return
	if _debug_label:
		var ground := "SOL" if _player.is_on_floor() else "AIR"
		_debug_label.text = "%.1f m/s  %s [%s]" % [_player.horizontal_speed(), _player.state_machine.current_name, ground]
	_update_abilities()
	_update_scoreboard()

	# Match : killfeed + scoreboard (Tab) + écran de fin.
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

	# Lunette : visible si l'arme courante est à lunette et qu'on vise.
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
	var ratio := clampf(current / maximum, 0.0, 1.0)
	if _hp_fill:
		_hp_fill.offset_right = 26 + 256 * ratio
		_hp_fill.color = Color(0.2, 0.85, 0.3, 0.9).lerp(Color(0.9, 0.2, 0.2, 0.9), 1.0 - ratio)
	if _hp_label:
		_hp_label.text = "%d" % roundi(current)

func _on_ammo_changed(ammo: int, reserve: int) -> void:
	if _ammo_label:
		_ammo_label.text = "%d / %d" % [ammo, reserve]

func _update_scoreboard() -> void:
	if _score_label == null:
		return
	if _mode == null or not is_instance_valid(_mode):
		_mode = get_tree().get_first_node_in_group("game_mode")
	if _mode == null:
		return
	if _mode.winner >= 0:
		_score_label.text = "ÉQUIPE %d GAGNE   %d - %d" % [_mode.winner + 1, _mode.team_score(0), _mode.team_score(1)]
	else:
		_score_label.text = "ÉQ.1  %d   —   %d  ÉQ.2\n%s" % [_mode.team_score(0), _mode.team_score(1), _mode.hud_state]

func _update_abilities() -> void:
	if _ability_label == null or _abilities == null or not _abilities.has_method("slot_info"):
		return
	var parts: Array = []
	for s in _abilities.slot_info():
		var t: String = "%s:%s" % [s.slot, s.name]
		if s.ult:
			t += " PRÊT" if s.ready else " %d%%" % int(s.ratio * 100.0)
		elif s.charges > 0:
			t += " x%d" % s.charges
		else:
			t += " %d%%" % int(s.ratio * 100.0)
		parts.append(t)
	_ability_label.text = "   ".join(parts)

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
		parts.append("[ %s ]" % nm if i == _weapon.current else nm)
	_inv_label.text = "   ".join(parts)

func _on_died(_killer_id: int) -> void:
	if _death_panel:
		_death_panel.visible = true

func _on_respawned() -> void:
	if _death_panel:
		_death_panel.visible = false
