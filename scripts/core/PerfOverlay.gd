## PerfOverlay.gd  (Autoload : "Perf")
## Overlay de performance : fps, temps d'image, "1% low" (~10 s glissantes via
## FrameStats), appels de dessin / objets / primitives (RenderingServer), tick
## physique et ping RTT côté client. Masqué par défaut, F3 bascule l'affichage
## (traité en _unhandled_input pour ne jamais voler les touches de gameplay).
## Le texte n'est reformaté que quelques fois par seconde et seulement quand
## l'overlay est visible : aucune allocation par frame hors de ce texte.
extends CanvasLayer

const REFRESH_INTERVAL := 0.25 ## secondes entre deux mises à jour du texte
const HISTORY_CAPACITY := 600  ## ~10 s à 60 Hz (fixe, voir contrat FrameStats)
const TOGGLE_KEY := KEY_F3

var _stats: FrameStats
var _label: Label
var _showing: bool = false
var _refresh_left: float = 0.0

func _init() -> void:
	layer = 4096 # au-dessus du HUD de jeu / menus

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_stats = FrameStats.new(HISTORY_CAPACITY)
	_build_label()
	visible = false

func _build_label() -> void:
	_label = Label.new()
	_label.name = "PerfLabel"
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.position = Vector2(8, 8)
	var mono := SystemFont.new()
	mono.font_names = PackedStringArray(["Consolas", "Courier New", "monospace"])
	_label.add_theme_font_override("font", mono)
	_label.add_theme_font_size_override("font_size", 14)
	_label.add_theme_color_override("font_color", Color(0.95, 0.97, 0.9))
	_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0))
	_label.add_theme_constant_override("outline_size", 3)
	add_child(_label)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == TOGGLE_KEY:
		_showing = not _showing
		visible = _showing
		if _showing:
			_refresh_left = 0.0
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	_stats.add(delta * 1000.0)
	if not _showing:
		return
	_refresh_left -= delta
	if _refresh_left > 0.0:
		return
	_refresh_left = REFRESH_INTERVAL
	_label.text = _format_text(delta)

func _format_text(delta: float) -> String:
	var frame_ms := delta * 1000.0
	var avg_fps := _stats.avg_fps()
	var low1 := _stats.low_1pct_fps()
	var draw_calls := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	var objects := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)
	var primitives := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
	var physics_hz := Engine.physics_ticks_per_second
	var lines := PackedStringArray([
		"FPS %.0f (%.2f ms)  1%% low %.0f" % [avg_fps, frame_ms, low1],
		"Draw calls %d  Objects %d  Prims %d" % [draw_calls, objects, primitives],
		"Physics %d Hz%s" % [physics_hz, _ping_suffix()],
	])
	return "\n".join(lines)

## " · ping <n> ms" quand on est connecté en tant que client ENet ; sinon "".
func _ping_suffix() -> String:
	var mp := multiplayer
	if mp == null or mp.multiplayer_peer == null or mp.is_server():
		return ""
	var enet_peer := mp.multiplayer_peer as ENetMultiplayerPeer
	if enet_peer == null:
		return ""
	var host_peer := enet_peer.get_peer(1)
	if host_peer == null:
		return ""
	var rtt := host_peer.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME)
	return "  ·  ping %d ms" % int(round(rtt))
