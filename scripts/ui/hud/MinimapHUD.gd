## MinimapHUD.gd
## Minicarte (contrat lead 2026-09-27, HUD en jeu, point 6) — haut-gauche :
## plaque 244x244 NON inclinée + étiquette de nom de carte dessous
## (`MatchConfig.map_id`). Image rendue UNE FOIS au début du match par une
## Camera3D orthographique vue de dessus dans un SubViewport qui PARTAGE le
## World3D du jeu (`SubViewport.render_target_update_mode = UPDATE_ONCE` —
## un seul rendu, jamais retouché ensuite, la géométrie de la carte ne bouge
## pas). Les bornes viennent du maillage de navigation (groupe "nav_region",
## voir MapSetup.gd) — `bounds_from_vertices`/`world_to_map` sont des
## fonctions PURES, testées sans scène. Nord FIXE (jamais de rotation caméra
## avec le joueur, même convention que `tools/rigging/look_capture.gd` "top").
## Marqueurs cerclés d'encre : soi = triangle JAUNE orienté au lacet, alliés =
## points BLEUS, ennemis = points ROUGES (demande utilisateur 2026-09-27 : « un point rouge
## si on voit la personne en face ou si elle fait du bruit ») visibles
## `_ENEMY_MARKER_WINDOW_S` après avoir été REPÉRÉS : vus (champ de la caméra + ligne de vue
## libre, fumée comprise) ou entendus (`heard` : un tir, ou une course proche). Le repérage
## est calculé par GameHUD._update_minimap ; ici seulement l'affichage (`marker_visible`).
class_name MinimapHUD
extends Control

const MAP_PX := 244.0
const _ENEMY_MARKER_WINDOW_S := 1.5
## Bruit : un tir s'entend jusqu'à FIRE_HEAR_M, une course (vitesse >= RUN_NOISE_SPEED) jusqu'à
## STEP_HEAR_M ; la marche reste silencieuse (jouer lentement = rester caché).
const FIRE_HEAR_M := 60.0
const STEP_HEAR_M := 18.0
const RUN_NOISE_SPEED := 5.0
## Vue : distance max à laquelle un ennemi dans le champ est repéré.
const SIGHT_M := 80.0
const _CAPTURE_SIZE := 512
const _CAMERA_HEIGHT_ABOVE_MAP := 60.0

## Couche de dessin des marqueurs — un Control DÉDIÉ (plutôt que `_draw()`
## directement sur `MinimapHUD`) pour rester au-dessus de la texture de
## carte sans avoir à gérer l'ordre de dessin d'un `_draw()` unique.
class _MarkerLayer extends Control:
	var hud: MinimapHUD

	func _draw() -> void:
		if hud:
			hud._draw_markers(self)


var _plate: PanelContainer
var _map_texture_rect: TextureRect
var _marker_layer: _MarkerLayer
var _map_name_label: Label

var _map_bounds: AABB = AABB()
var _capture_viewport: SubViewport
var _self_pos: Vector3 = Vector3.ZERO
var _self_yaw: float = 0.0
var _allies: Array = []      # Array[Vector3]
var _enemies: Array = []     # Array[{"pos": Vector3, "last_fire": float}]


## Boîte englobante (XZ) d'un nuage de sommets (maillage de nav) — vide
## (taille nulle) si `verts` est vide. Fonction PURE.
static func bounds_from_vertices(verts: PackedVector3Array) -> AABB:
	if verts.is_empty():
		return AABB()
	var aabb := AABB(verts[0], Vector3.ZERO)
	for v in verts:
		aabb = aabb.expand(v)
	return aabb


## Position MONDE (XZ) -> pixel de la minicarte (0..map_size), NORD FIXE
## (aucune rotation caméra) : X monde -> X carte, Z monde -> Y carte. Fonction
## PURE, testée directement (tests/ui/test_minimap_hud.gd).
static func world_to_map(pos: Vector3, bounds: AABB, map_size: Vector2) -> Vector2:
	if bounds.size.x <= 0.0 or bounds.size.z <= 0.0:
		return map_size * 0.5
	var fx: float = (pos.x - bounds.position.x) / bounds.size.x
	var fz: float = (pos.z - bounds.position.z) / bounds.size.z
	return Vector2(fx * map_size.x, fz * map_size.y)


## Un ennemi n'est marqué que dans les `window` secondes après son dernier REPÉRAGE (vu ou
## entendu) — `last_fire_time` = -INF si jamais repéré.
static func marker_visible(now: float, last_fire_time: float, window: float = _ENEMY_MARKER_WINDOW_S) -> bool:
	if not is_finite(last_fire_time):
		return false
	return now - last_fire_time <= window


## L'ennemi fait-il assez de bruit pour être entendu à `dist` m ? Tir récent : jusqu'à
## FIRE_HEAR_M ; course (vitesse horizontale >= RUN_NOISE_SPEED) : jusqu'à STEP_HEAR_M. PURE.
static func heard(dist: float, speed: float, fired: bool) -> bool:
	if fired and dist <= FIRE_HEAR_M:
		return true
	return speed >= RUN_NOISE_SPEED and dist <= STEP_HEAR_M


func _ready() -> void:
	Comic.anchor(self, Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	_try_build_capture()


func _process(_delta: float) -> void:
	if _capture_viewport == null:
		# La NavigationRegion3D (MapSetup._bake_navigation) peut ne pas encore
		# être posée dans le groupe "nav_region" au premier `_ready()` de ce
		# HUD (ordre de construction de scène) -- retenté chaque frame, sans
		# coût une fois la capture réussie (`_try_build_capture` sort tôt).
		_try_build_capture()
	if _marker_layer:
		_marker_layer.queue_redraw()


func _build() -> void:
	_plate = PanelContainer.new()
	_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plate.custom_minimum_size = Vector2(MAP_PX, MAP_PX)
	var sb := UiTokens.plate(UiTokens.PAPER_2, 0.0, UiTokens.DROP, UiTokens.STROKE, Vector2.ZERO)
	_plate.add_theme_stylebox_override("panel", sb)
	_plate.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_plate.offset_left = UiTokens.EDGE_MARGIN
	_plate.offset_top = UiTokens.EDGE_MARGIN * 0.7
	_plate.offset_right = _plate.offset_left + MAP_PX
	_plate.offset_bottom = _plate.offset_top + MAP_PX
	add_child(_plate)

	var stack := Control.new()
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	Comic.anchor(stack, Control.PRESET_FULL_RECT)
	_plate.add_child(stack)

	_map_texture_rect = TextureRect.new()
	_map_texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# EXPAND_IGNORE_SIZE : sans lui, dès que `texture` reçoit la
	# ViewportTexture de capture (512x512, voir `_build_capture_viewport`),
	# le contrôle grandirait à CETTE taille native (expand_mode par défaut =
	# EXPAND_KEEP_SIZE) au lieu de rester calé sur la plaque 244x244 --
	# InventoryHUD._build_icon documente le même bogue.
	_map_texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_map_texture_rect.stretch_mode = TextureRect.STRETCH_SCALE
	Comic.anchor(_map_texture_rect, Control.PRESET_FULL_RECT)
	var mat := ShaderMaterial.new()
	var shader := load("res://assets/shaders/ui/minimap.gdshader")
	if shader:
		mat.shader = shader
		_map_texture_rect.material = mat
	stack.add_child(_map_texture_rect)

	_marker_layer = _MarkerLayer.new()
	_marker_layer.hud = self
	_marker_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	Comic.anchor(_marker_layer, Control.PRESET_FULL_RECT)
	stack.add_child(_marker_layer)

	_map_name_label = UiTokens.make_label("", UiTokens.label(UiTokens.T_XS, UiTokens.PAPER, 0, true), true)
	var tag := PanelContainer.new()
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tag.add_theme_stylebox_override("panel", UiTokens.plate(UiTokens.INK, 0.0, Vector2.ZERO, 0.0, Vector2(UiTokens.S2, 2)))
	tag.add_child(_map_name_label)
	tag.set_anchors_preset(Control.PRESET_TOP_LEFT)
	tag.offset_left = _plate.offset_left
	tag.offset_top = _plate.offset_bottom + UiTokens.S1
	add_child(tag)


## Cherche une NavigationRegion3D du groupe "nav_region" (MapSetup.gd) pour
## les bornes de carte, puis construit le SubViewport de capture. Ne fait
## RIEN si aucune carte n'est présente (instanciation nue en test unitaire) —
## jamais d'erreur, juste une minicarte sans image de fond.
func _try_build_capture() -> void:
	var regions := get_tree().get_nodes_in_group("nav_region") if is_inside_tree() else []
	if regions.is_empty():
		return
	var region := regions[0] as NavigationRegion3D
	var mesh := region.navigation_mesh if region else null
	if mesh == null:
		return
	var bounds := bounds_from_vertices(mesh.get_vertices())
	if bounds.size.x <= 0.01 or bounds.size.z <= 0.01:
		return
	_map_bounds = bounds
	_build_capture_viewport(bounds)


func _build_capture_viewport(bounds: AABB) -> void:
	var scene := get_tree().current_scene as Node3D
	var world: World3D = scene.get_world_3d() if scene else get_viewport().world_3d
	var sub := SubViewport.new()
	sub.size = Vector2i(_CAPTURE_SIZE, _CAPTURE_SIZE)
	sub.transparent_bg = true
	sub.own_world_3d = false
	sub.world_3d = world
	sub.render_target_update_mode = SubViewport.UPDATE_ONCE

	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = maxf(bounds.size.x, bounds.size.z)
	var center := bounds.position + bounds.size * 0.5
	var eye := Vector3(center.x, bounds.position.y + bounds.size.y + _CAMERA_HEIGHT_ABOVE_MAP, center.z)
	# Nord fixe : `Vector3.FORWARD` (= -Z monde) comme référence "haut d'image",
	# même convention que tools/rigging/look_capture.gd (vue "top").
	cam.look_at_from_position(eye, Vector3(center.x, bounds.position.y, center.z), Vector3.FORWARD)
	sub.add_child(cam)
	add_child(sub)
	_capture_viewport = sub
	_map_texture_rect.texture = sub.get_texture()


func _draw_markers(overlay: Control) -> void:
	var size := overlay.size
	if size.x <= 0.0 or size.y <= 0.0:
		size = Vector2(MAP_PX, MAP_PX)
	for ally_pos in _allies:
		var p := world_to_map(ally_pos, _map_bounds, size)
		overlay.draw_circle(p, 7.0, UiTokens.INK)
		overlay.draw_circle(p, 5.0, UiTokens.BLUE)
	var now := Time.get_ticks_msec() / 1000.0
	for enemy in _enemies:
		var e: Dictionary = enemy
		if not marker_visible(now, float(e.get("last_spotted", e.get("last_fire", -INF)))):
			continue
		var p2 := world_to_map(e["pos"], _map_bounds, size)
		overlay.draw_circle(p2, 8.5, UiTokens.INK)
		overlay.draw_circle(p2, 6.0, UiTokens.RED)
	var sp := world_to_map(_self_pos, _map_bounds, size)
	_draw_triangle(overlay, sp, 11.0, _self_yaw, UiTokens.YELLOW)


static func _draw_diamond(overlay: Control, center: Vector2, r: float, color: Color) -> void:
	var pts := PackedVector2Array([center + Vector2(0, -r), center + Vector2(r, 0), center + Vector2(0, r), center + Vector2(-r, 0)])
	overlay.draw_colored_polygon(pts, UiTokens.INK)
	var inner := PackedVector2Array()
	for p in pts:
		inner.append(center + (p - center) * 0.72)
	overlay.draw_colored_polygon(inner, color)


static func _draw_triangle(overlay: Control, center: Vector2, r: float, yaw: float, color: Color) -> void:
	# Pointe vers l'avant (yaw), base derrière — `yaw` mesuré comme
	# `Node3D.rotation.y` (0 = -Z monde = "nord"/haut d'image).
	var tip := center + Vector2(sin(yaw), -cos(yaw)) * r
	var back := center - Vector2(sin(yaw), -cos(yaw)) * r * 0.6
	var side := Vector2(cos(yaw), sin(yaw)) * r * 0.6
	var pts := PackedVector2Array([tip, back + side, back - side])
	overlay.draw_colored_polygon(pts, UiTokens.INK)
	var inner := PackedVector2Array()
	for p in pts:
		inner.append(center + (p - center) * 0.7)
	overlay.draw_colored_polygon(inner, color)


func set_map_name(map_id: String) -> void:
	_map_name_label.text = map_id.to_upper()


## GameHUD.gd -> polling depuis PlayerController (position + lacet caméra/corps).
func update_self(pos: Vector3, yaw: float) -> void:
	_self_pos = pos
	_self_yaw = yaw


func update_allies(positions: Array) -> void:
	_allies = positions


## `entries` : Array[{"pos": Vector3, "last_spotted": float}] — voir `marker_visible`.
func update_enemies(entries: Array) -> void:
	_enemies = entries
