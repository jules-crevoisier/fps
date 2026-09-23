## MainMenu.gd — Lobby type COD.
## Scène 3D en fond (plateforme + personnages cartoon qui posent, caméra qui
## balance) avec une UI par-dessus : barre d'onglets (JOUER / AGENTS / ARSENAL /
## OPTIONS) + carte de partie. Les onglets autres que JOUER embarquent les menus
## existants (mêmes scripts, signal `closed` pour revenir).
extends Node3D

const MODES := [
	{"name": "Team Deathmatch", "scene": "res://scenes/levels/tdm_map.tscn"},
	{"name": "Hardpoint", "scene": "res://scenes/levels/comp_map.tscn"},
]
const OPTIONS_SCRIPT := preload("res://scripts/ui/OptionsMenu.gd")
const ARSENAL_SCRIPT := preload("res://scripts/ui/ArsenalMenu.gd")
const AGENT_SCRIPT := preload("res://scripts/ui/AgentMenu.gd")
const FONT_BLACK := preload("res://resources/fonts/Lato-Black.ttf")

const ACCENTS := [Color(1.0, 0.55, 0.2), Color(0.3, 0.62, 1.0), Color(0.42, 0.86, 0.42)]

const TAB_PLAY := 0
const TAB_AGENTS := 1
const TAB_ARSENAL := 2
const TAB_OPTIONS := 3

var _mode_index: int = 0
var _mode_btn: Button
var _ip_field: LineEdit
var _status: Label
var _net: NetworkManager

# UI
var _tabs: Array = []
var _content: Control
var _play_panel: Control
var _embedded: Control
var _host_btn: Button

# Décor 3D
var _cam: Camera3D
var _chars: Array = []
var _t: float = 0.0

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Settings.load_all()
	_net = NetworkManager.get_net(get_tree())
	_net.disconnect_from_game()
	_net.connection_succeeded.connect(_on_connected)
	_net.connection_failed.connect(_on_failed)
	_build_world()
	_build_ui()
	_show_tab(TAB_PLAY)
	call_deferred("_focus_play")

func _process(delta: float) -> void:
	_t += delta
	# Caméra qui balance doucement façon vitrine d'opérateurs.
	if _cam:
		var sway := sin(_t * 0.22) * 1.5
		_cam.position = Vector3(sway, 2.35, 7.6)
		_cam.look_at(Vector3(sway * 0.25, 1.35, 0))
	# Léger bob "idle" sur chaque perso.
	for i in _chars.size():
		var c: Node3D = _chars[i]
		c.position.y = 0.06 + sin(_t * 1.8 + float(i) * 1.3) * 0.05
		c.rotation.y = sin(_t * 0.5 + float(i)) * 0.14

# ---------------------------------------------------------------- Décor 3D
func _build_world() -> void:
	# Éclairage studio : key chaud + rim froid (fait ressortir les contours toon) + fill doux.
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-42, -35, 0)
	key.light_energy = 1.2
	key.light_color = Color(1.0, 0.95, 0.86)
	add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-18, 150, 0)
	rim.light_energy = 1.6
	rim.light_color = Color(0.55, 0.7, 1.0)
	add_child(rim)

	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var skymat := ProceduralSkyMaterial.new()
	skymat.sky_top_color = Color(1.0, 0.78, 0.15)
	skymat.sky_horizon_color = Color(1.0, 0.52, 0.12)
	skymat.ground_horizon_color = Color(1.0, 0.52, 0.12)
	skymat.ground_bottom_color = Color(0.9, 0.36, 0.1)
	sky.sky_material = skymat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.85
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_bloom = 0.1
	we.environment = env
	add_child(we)

	# Scène "character select" comic : grand mur magenta + estrade violette.
	_box(Vector3(0, -3.4, -3.6), Vector3(32, 9, 1), Comic.MAGENTA)
	_box(Vector3(0, -0.3, 0), Vector3(11, 0.6, 5.5), Comic.PURPLE)
	_box(Vector3(0, -0.02, 0.2), Vector3(10.4, 0.16, 4.6), Color(0.1, 0.1, 0.13))

	# Personnages cartoon sur leur podium accentué.
	var xs := [-2.5, 0.0, 2.5]
	for i in 3:
		_podium(Vector3(xs[i], 0.0, 0.2), ACCENTS[i])
		_chars.append(_character(Vector3(xs[i], 0.06, 0.2), ACCENTS[i]))

	_cam = Camera3D.new()
	_cam.fov = 50
	_cam.position = Vector3(0, 2.4, 7.8)
	add_child(_cam)
	_cam.current = true

func _podium(pos: Vector3, accent: Color) -> void:
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.0
	cyl.bottom_radius = 1.15
	cyl.height = 0.22
	mi.mesh = cyl
	mi.position = pos + Vector3(0, 0.05, 0)
	mi.material_override = Cartoon.mat(Color(0.16, 0.15, 0.26))
	add_child(mi)
	# Anneau émissif à la couleur de l'accent.
	var ring := MeshInstance3D.new()
	var rc := CylinderMesh.new()
	rc.top_radius = 1.06
	rc.bottom_radius = 1.06
	rc.height = 0.06
	ring.mesh = rc
	ring.position = pos + Vector3(0, 0.18, 0)
	var rm := StandardMaterial3D.new()
	rm.albedo_color = accent
	rm.emission_enabled = true
	rm.emission = accent
	rm.emission_energy_multiplier = 2.0
	ring.material_override = rm
	add_child(ring)

func _box(center: Vector3, size: Vector3, color: Color) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = center
	mi.material_override = Cartoon.mat(color)
	add_child(mi)

func _character(pos: Vector3, color: Color) -> Node3D:
	var root := Node3D.new()
	root.position = pos
	add_child(root)
	var suit := Cartoon.mat(color.darkened(0.1))
	var dark := Cartoon.mat(Color(0.14, 0.14, 0.22))
	# Corps (capsule trapue) + ceinture
	root.add_child(_mesh(_capsule(0.46, 1.05), Vector3(0, 0.95, 0), suit))
	root.add_child(_mesh(_box_mesh(Vector3(0.96, 0.16, 0.7)), Vector3(0, 0.78, 0), dark))
	# Épaulettes
	root.add_child(_mesh(_sphere(0.26), Vector3(-0.5, 1.4, 0), suit))
	root.add_child(_mesh(_sphere(0.26), Vector3(0.5, 1.4, 0), suit))
	# Bras
	root.add_child(_mesh(_capsule(0.16, 0.6), Vector3(-0.55, 1.0, 0), suit))
	root.add_child(_mesh(_capsule(0.16, 0.6), Vector3(0.55, 1.0, 0), suit))
	# Tête (grosse, cartoon) + casque
	root.add_child(_mesh(_sphere(0.42), Vector3(0, 1.95, 0), Cartoon.mat(Color(0.96, 0.86, 0.74))))
	var helm := _mesh(_sphere(0.46), Vector3(0, 2.05, -0.04), suit)
	helm.scale = Vector3(1.0, 0.7, 1.0)
	root.add_child(helm)
	# Visière brillante
	var vmat := StandardMaterial3D.new()
	vmat.albedo_color = color.lightened(0.2)
	vmat.emission_enabled = true
	vmat.emission = color
	vmat.emission_energy_multiplier = 1.4
	var vis := _mesh(_box_mesh(Vector3(0.58, 0.2, 0.12)), Vector3(0, 1.95, 0.34), vmat)
	root.add_child(vis)
	return root

# --- Petits helpers de maillage ---
func _mesh(m: Mesh, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.position = pos
	mi.material_override = mat
	return mi

func _capsule(radius: float, height: float) -> CapsuleMesh:
	var c := CapsuleMesh.new()
	c.radius = radius
	c.height = height
	return c

func _sphere(radius: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0
	return s

func _box_mesh(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b

# ---------------------------------------------------------------- UI
func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)

	# Zone de contenu (sous la barre) — ajoutée d'abord pour passer SOUS la barre.
	_content = Control.new()
	_content.set_anchors_preset(Control.PRESET_FULL_RECT)
	_content.offset_top = 78
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_content)

	_build_play_panel()
	_build_top_bar(root)

func _build_top_bar(root: Control) -> void:
	var bar := Control.new()
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar.offset_bottom = 72
	root.add_child(bar)

	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.1, 0.09, 0.18, 0.92)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(bg)

	var line := ColorRect.new()
	line.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	line.offset_top = -4
	line.color = Color(1.0, 0.7, 0.18, 1)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(line)

	var hb := HBoxContainer.new()
	hb.set_anchors_preset(Control.PRESET_FULL_RECT)
	hb.offset_left = 28
	hb.offset_right = -28
	hb.add_theme_constant_override("separation", 10)
	hb.alignment = BoxContainer.ALIGNMENT_BEGIN
	bar.add_child(hb)

	var brand := Comic.label("FPS // CARTOON", 26, Comic.YELLOW)
	brand.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hb.add_child(brand)

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(28, 0)
	hb.add_child(gap)

	var group := ButtonGroup.new()
	var labels := ["JOUER", "AGENTS", "ARSENAL", "OPTIONS"]
	for i in labels.size():
		var tb := Button.new()
		tb.text = labels[i]
		tb.toggle_mode = true
		tb.button_group = group
		tb.focus_mode = Control.FOCUS_ALL
		tb.custom_minimum_size = Vector2(0, 44)
		tb.pressed.connect(_on_tab.bind(i))
		hb.add_child(tb)
		_tabs.append(tb)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(spacer)

	var who := Label.new()
	who.text = "Soldat"
	who.add_theme_color_override("font_color", Color(0.85, 0.88, 0.95))
	who.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hb.add_child(who)

	var quit := Button.new()
	quit.text = "Quitter"
	quit.custom_minimum_size = Vector2(0, 44)
	quit.pressed.connect(func(): get_tree().quit())
	hb.add_child(quit)

func _build_play_panel() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.grow_horizontal = Control.GROW_DIRECTION_END
	panel.offset_left = 40
	panel.offset_bottom = -40
	panel.custom_minimum_size = Vector2(400, 0)
	_content.add_child(panel)
	_play_panel = panel

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)

	box.add_child(_burst_title("PARTIE"))

	_mode_btn = Button.new()
	_mode_btn.custom_minimum_size = Vector2(0, 40)
	_mode_btn.pressed.connect(_cycle_mode)
	box.add_child(_mode_btn)
	_update_mode_btn()

	_host_btn = Button.new()
	_host_btn.text = "▶  JOUER (héberger)"
	_host_btn.custom_minimum_size = Vector2(0, 56)
	_host_btn.add_theme_font_size_override("font_size", 22)
	_host_btn.pressed.connect(_on_host)
	box.add_child(_host_btn)

	box.add_child(HSeparator.new())

	var mp := Label.new()
	mp.text = "Multijoueur — rejoindre une IP"
	mp.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85))
	box.add_child(mp)

	_ip_field = LineEdit.new()
	_ip_field.text = "127.0.0.1"
	_ip_field.placeholder_text = "IP du serveur"
	box.add_child(_ip_field)

	var join_btn := Button.new()
	join_btn.text = "Rejoindre"
	join_btn.custom_minimum_size = Vector2(0, 44)
	join_btn.pressed.connect(_on_join)
	box.add_child(join_btn)

	box.add_child(HSeparator.new())

	var train_btn := Button.new()
	train_btn.text = "Terrain d'entraînement (solo)"
	train_btn.custom_minimum_size = Vector2(0, 44)
	train_btn.pressed.connect(_on_training)
	box.add_child(train_btn)

	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_color_override("font_color", Color(1.0, 0.7, 0.4))
	box.add_child(_status)

func _burst_title(text: String) -> Control:
	var wrap := Control.new()
	wrap.custom_minimum_size = Vector2(230, 88)
	var burst := ComicBurst.new()
	burst.color = Comic.YELLOW
	burst.back_color = Comic.MAGENTA
	burst.spikes = 18
	burst.set_anchors_preset(Control.PRESET_FULL_RECT)
	wrap.add_child(burst)
	var lbl := Comic.label(text, 34, Comic.INK, 0)
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	wrap.add_child(lbl)
	return wrap

# ---------------------------------------------------------------- Onglets
func _on_tab(idx: int) -> void:
	_show_tab(idx)

func _show_tab(idx: int) -> void:
	if _tabs.size() > idx and is_instance_valid(_tabs[idx]):
		_tabs[idx].button_pressed = true
	# Nettoie un menu embarqué éventuel.
	if _embedded and is_instance_valid(_embedded):
		_embedded.queue_free()
	_embedded = null

	if idx == TAB_PLAY:
		_play_panel.visible = true
		call_deferred("_focus_play")
		return

	_play_panel.visible = false
	var script: Script = null
	match idx:
		TAB_AGENTS: script = AGENT_SCRIPT
		TAB_ARSENAL: script = ARSENAL_SCRIPT
		TAB_OPTIONS: script = OPTIONS_SCRIPT
	if script == null:
		return
	_embedded = script.new()
	_embedded.set_anchors_preset(Control.PRESET_FULL_RECT)
	if _embedded.has_signal("closed"):
		_embedded.closed.connect(func(): _show_tab(TAB_PLAY))
	_content.add_child(_embedded)

func _focus_play() -> void:
	if _host_btn and is_instance_valid(_host_btn) and _play_panel.visible:
		_host_btn.grab_focus()

# ---------------------------------------------------------------- Réseau / jeu
func _on_host() -> void:
	if _net.host() == OK:
		_start_game()
	else:
		_status.text = "Échec de l'hébergement."

func _on_join() -> void:
	_status.text = "Connexion à %s…" % _ip_field.text
	_net.join(_ip_field.text)

func _on_connected() -> void:
	_start_game()

func _on_failed() -> void:
	_status.text = "Connexion échouée."

func _on_training() -> void:
	get_tree().change_scene_to_file("res://scenes/levels/test_arena.tscn")

func _cycle_mode() -> void:
	_mode_index = (_mode_index + 1) % MODES.size()
	_update_mode_btn()

func _update_mode_btn() -> void:
	if _mode_btn:
		_mode_btn.text = "Mode : %s  ▸" % MODES[_mode_index].name

func _start_game() -> void:
	get_tree().change_scene_to_file(MODES[_mode_index].scene)
