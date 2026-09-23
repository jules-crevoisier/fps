## GameHUD.gd
## HUD de jeu « encre et papier » (design.md, locked) : compose les modules en
## composants (scripts/ui/hud/*) — vitalité, munitions, capacités, score/
## timer/phase, killfeed, scoreboard (Tab), manche/bombe/crédits, mort/fin.
## La zone centrale (40 %×40 %) ne contient QUE le viseur/hitmarkers/lunette
## (design.md §8). Se branche automatiquement sur le joueur local (groupe
## "local_player") et ses composants ; rien n'intercepte la souris.
extends CanvasLayer

var _player: PlayerController
var _health: Health
var _weapon: Weapon
var _abilities: Node
var _mode: Node
var _match: Node

var _crosshair: Control
var _scope: TextureRect
var _scope_reticle: Control
var _debug_label: Label
var _debug_visible: bool = false

var _health_panel: HealthPanel
var _ammo_panel: AmmoPanel
var _ability_bar: AbilityBar
var _score_panel: ScorePanel
var _round_panel: RoundPanel
var _killfeed: KillfeedPanel
var _scoreboard: ScoreboardPanel
var _death_panel: DeathPanel
var _end_panel: EndPanel
var _end_shown: bool = false

# ----------------------------------------------------------- Retours de combat (R4-FX)
var _vignette: LowHealthVignette
var _hit_marker: HitMarker
var _damage_dir: DamageDirection
var _kill_word: KillWordBurst
## Horodatage (Time.get_ticks_msec/1000) du dernier kill_logged LOCAL en
## attente d'un hit_confirmed correspondant (HitFeedback.is_kill_hit) ; < 0 =
## aucun en attente.
var _pending_kill_time: float = -1.0
var _kill_word_pick: int = 0
var _kill_word_right_side: bool = true

func _ready() -> void:
	_build()

func _build() -> void:
	_build_crosshair()
	_vignette = LowHealthVignette.new()
	add_child(_vignette)
	_damage_dir = DamageDirection.new()
	Comic.anchor(_damage_dir, Control.PRESET_CENTER)
	_damage_dir.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_damage_dir)
	_hit_marker = HitMarker.new()
	Comic.anchor(_hit_marker, Control.PRESET_CENTER)
	add_child(_hit_marker)
	_kill_word = KillWordBurst.new()
	_kill_word.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_kill_word)
	_health_panel = HealthPanel.new()
	add_child(_health_panel)
	_ammo_panel = AmmoPanel.new()
	add_child(_ammo_panel)
	_ability_bar = AbilityBar.new()
	add_child(_ability_bar)
	_score_panel = ScorePanel.new()
	add_child(_score_panel)
	_round_panel = RoundPanel.new()
	add_child(_round_panel)
	_killfeed = KillfeedPanel.new()
	add_child(_killfeed)
	_build_debug()
	_death_panel = DeathPanel.new()
	add_child(_death_panel)
	_scoreboard = ScoreboardPanel.new()
	add_child(_scoreboard)
	_end_panel = EndPanel.new()
	_end_panel.replay_pressed.connect(_on_replay)
	_end_panel.menu_pressed.connect(_on_menu)
	add_child(_end_panel)
	_build_scope()
	# Rien ne doit intercepter la souris (sinon look/lunette bloqués).
	_ignore_mouse(self)

# ----------------------------------------------------------- Zone centrale (viseur/lunette)
func _build_crosshair() -> void:
	_crosshair = Control.new()
	Comic.anchor(_crosshair, Control.PRESET_CENTER)
	_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_crosshair)
	var col := Comic.TEXT_ON_BRUSH
	_cross_line(_crosshair, Rect2(-1, -12, 2, 7), col)
	_cross_line(_crosshair, Rect2(-1, 5, 2, 7), col)
	_cross_line(_crosshair, Rect2(-12, -1, 7, 2), col)
	_cross_line(_crosshair, Rect2(5, -1, 7, 2), col)
	_cross_line(_crosshair, Rect2(-1, -1, 2, 2), col)

func _cross_line(parent: Control, r: Rect2, c: Color) -> void:
	var outline := ColorRect.new()
	outline.color = Comic.BG
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

func _build_scope() -> void:
	var s := 256
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	img.fill(Comic.BG)
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
	_scope.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scope.visible = false
	_scope.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_scope)

	_scope_reticle = Control.new()
	_scope_reticle.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scope_reticle.visible = false
	_scope_reticle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hbar := ColorRect.new()
	hbar.color = Comic.TEXT_ON_BRUSH
	Comic.anchor(hbar, Control.PRESET_CENTER)
	hbar.offset_left = -120; hbar.offset_right = 120; hbar.offset_top = -1; hbar.offset_bottom = 1
	_scope_reticle.add_child(hbar)
	var vbar := ColorRect.new()
	vbar.color = Comic.TEXT_ON_BRUSH
	Comic.anchor(vbar, Control.PRESET_CENTER)
	vbar.offset_left = -1; vbar.offset_right = 1; vbar.offset_top = -120; vbar.offset_bottom = 120
	_scope_reticle.add_child(vbar)
	add_child(_scope_reticle)

func _build_debug() -> void:
	# Lecture vitesse/état — masquée par défaut, bascule sur F3 (action "debug_info").
	_debug_label = Comic.label("", Comic.SIZE_FLOOR, Comic.TEXT_DIM, Comic.FONT_LABEL)
	Comic.anchor(_debug_label, Control.PRESET_TOP_LEFT)
	_debug_label.offset_left = Comic.SP_3
	_debug_label.offset_top = Comic.SP_2
	_debug_label.visible = false
	add_child(_debug_label)

func _ignore_mouse(node: Node) -> void:
	for c in node.get_children():
		if c is Control and not (c is BaseButton) and not (c is Range):
			c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_ignore_mouse(c)

# ----------------------------------------------------------- Boucle
func _process(_delta: float) -> void:
	if InputMap.has_action("debug_info") and Input.is_action_just_pressed("debug_info"):
		_debug_visible = not _debug_visible
		_debug_label.visible = _debug_visible

	if _player == null or not is_instance_valid(_player):
		_acquire_player()
		return

	if _debug_visible and _debug_label:
		var ground := "SOL" if _player.is_on_floor() else "AIR"
		_debug_label.text = "%.1f m/s · %s · %s" % [_player.horizontal_speed(), _player.state_machine.current_name, ground]

	if _ability_bar and _abilities and _abilities.has_method("slot_info"):
		_ability_bar.refresh(_abilities.slot_info())

	if _match == null or not is_instance_valid(_match):
		_match = get_tree().get_first_node_in_group("match")
		if _match and _match.has_signal("kill_logged") and not _match.kill_logged.is_connected(_on_kill_logged):
			_match.kill_logged.connect(_on_kill_logged)

	if _mode == null or not is_instance_valid(_mode):
		_mode = get_tree().get_first_node_in_group("game_mode")
	if _mode:
		var ot: bool = bool(_mode.has_method("is_overtime") and _mode.is_overtime())
		var timer_text := ""
		if _mode.winner < 0:
			if "round_time_left" in _mode:
				timer_text = HudFormat.format_timer(float(_mode.round_time_left))
			elif "match_time_limit" in _mode and "match_elapsed" in _mode:
				timer_text = HudFormat.format_timer(maxf(float(_mode.match_time_limit) - float(_mode.match_elapsed), 0.0))
		_score_panel.update(_mode.team_score(0), _mode.team_score(1), _mode.winner, str(_mode.hud_state), ot, timer_text)
		_round_panel.update_round(_mode)
	else:
		_score_panel.hide_panel()

	if _scoreboard:
		var show_sb: bool = Input.is_action_pressed("scoreboard") or (_mode != null and _mode.winner >= 0)
		_scoreboard.visible = show_sb
		if show_sb:
			_scoreboard.refresh(_match)

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
		_health.damage_from_direction.connect(_on_damage_from_direction)
		_on_health_changed(_health.current_health, _health.max_health)
	if _weapon:
		_weapon.ammo_changed.connect(_on_ammo_changed)
		_weapon.weapon_changed.connect(_on_weapon_changed)
		_weapon.hit_confirmed.connect(_on_hit_confirmed)
		if _weapon.cfg():
			_on_weapon_changed(_weapon.cfg())
		if _weapon.current < _weapon.mag.size():
			_on_ammo_changed(_weapon.mag[_weapon.current], _weapon.reserve_a[_weapon.current])

func _on_health_changed(current: float, maximum: float) -> void:
	if _health_panel:
		_health_panel.update_health(current, maximum)
	if _vignette:
		_vignette.update_health(current, maximum)

func _on_ammo_changed(ammo: int, reserve: int) -> void:
	if _ammo_panel:
		_ammo_panel.update_ammo(ammo, reserve)

func _on_weapon_changed(cfg: WeaponConfig) -> void:
	if _ammo_panel and cfg:
		_ammo_panel.update_weapon(cfg.weapon_name)
	_update_inventory()

func _update_inventory() -> void:
	if _ammo_panel == null or _weapon == null:
		return
	_ammo_panel.update_inventory(_weapon.weapons, _weapon.current)

func _on_kill_logged(killer: String, victim: String, killer_team: int) -> void:
	var is_local := _player != null and killer == _local_display_name()
	if _killfeed:
		_killfeed.push(killer, victim, killer_team, is_local)
	# `kill_logged` (diffusion GameWorld) précède toujours de très près le
	# `hit_confirmed` (Weapon) du même tir mortel côté tireur — voir
	# HitFeedback.is_kill_hit. On mémorise juste l'horodatage ; c'est
	# `_on_hit_confirmed` qui décide (variante croix + mot-bruit), car lui
	# seul connaît le headshot du coup.
	if is_local:
		_pending_kill_time = Time.get_ticks_msec() / 1000.0

## "Joueur %d" : identique au nom que GameWorld._spawn_player attribue à tout
## humain (jamais bot — `local_player` n'est ajouté qu'à l'humain devant CE
## clavier, voir PlayerController.is_local_human) dans `player_info`/killfeed.
func _local_display_name() -> String:
	return "Joueur %d" % str(_player.name).to_int() if _player else ""

## `_pos`/`_dmg` : position/chiffre de dégâts déjà affichés par
## `Weapon._spawn_damage_number` (cosmétique 3D) — seul `headshot` sert ici.
func _on_hit_confirmed(_pos: Vector3, _dmg: float, headshot: bool) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var is_kill := HitFeedback.is_kill_hit(now, _pending_kill_time)
	if is_kill:
		_pending_kill_time = -1.0
	if _hit_marker:
		_hit_marker.show_hit(HitFeedback.marker_variant(headshot, is_kill))
	if is_kill:
		_trigger_kill_word(headshot)

func _trigger_kill_word(headshot: bool) -> void:
	if _kill_word == null or _kill_word.is_busy():
		return
	var word := HitFeedback.sound_word(headshot, _kill_word_pick)
	_kill_word_pick += 1
	_kill_word_right_side = not _kill_word_right_side
	var vp := get_viewport().get_visible_rect().size
	_kill_word.play(word, HitFeedback.burst_rect(_kill_word_right_side, vp))

func _on_damage_from_direction(_amount: float, source_position: Vector3) -> void:
	if _damage_dir == null or _player == null:
		return
	var basis := _player.global_transform.basis
	var angle := HitFeedback.wedge_angle_deg(_player.global_position, -basis.z, basis.x, source_position)
	_damage_dir.show_damage(angle)

func _update_end() -> void:
	if _mode == null or _end_panel == null:
		return
	var over: bool = _mode.winner >= 0
	if over and not _end_shown:
		_end_shown = true
		_end_panel.show_result(_mode.winner, _mode.team_score(0), _mode.team_score(1), _match)
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif not over and _end_shown:
		_end_shown = false
		_end_panel.hide_result()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _on_replay() -> void:
	if _match == null:
		return
	if multiplayer.is_server():
		_match.reset_match()
	else:
		_match.request_reset.rpc_id(1)

func _on_menu() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")

func _on_died(_killer_id: int) -> void:
	if _death_panel:
		_death_panel.show_death()

func _on_respawned() -> void:
	if _death_panel:
		_death_panel.hide_death()

## Force la page de fin pour les captures d'écran (tests/ui/capture_shots.gd),
## jamais appelé en jeu normal (la vraie condition passe par `_update_end`).
func debug_force_end(winner: int, team0: int, team1: int) -> void:
	_end_panel.show_result(winner, team0, team1, _match)

# ----------------------------------------------------------- Déclencheurs de capture (R4-FX)
## `variant` : "normal" / "headshot" / "kill" (HitFeedback.MARKER_*).
func debug_force_hit_marker(variant: String) -> void:
	if _hit_marker:
		_hit_marker.show_hit(variant)

## `angle_deg` : voir HitFeedback.wedge_angle_deg (0 = devant, 90 = droite).
func debug_force_damage_direction(angle_deg: float = 55.0) -> void:
	if _damage_dir:
		_damage_dir.show_damage(angle_deg)

## `ratio` : 0..1, force la vignette sans dépendre d'un vrai combat.
func debug_force_vignette(ratio: float = 0.15) -> void:
	if _vignette:
		_vignette.debug_force_ratio(ratio)

func debug_force_kill_word(headshot: bool = false) -> void:
	_trigger_kill_word(headshot)

## Entrée de killfeed mise en évidence (contract-r4a.md "R4-FX" #4, "killfeed
## entry highlighted") — sans dépendre d'un vrai kill_logged.
func debug_force_killfeed_local() -> void:
	if _killfeed:
		_killfeed.push("Joueur 1", "BOT Renard", 0, true)
		_killfeed.push("BOT Iris", "Joueur 1", 1, false)
