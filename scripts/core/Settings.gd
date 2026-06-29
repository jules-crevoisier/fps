## Settings.gd
## Réglages persistants (user://settings.cfg) : remap clavier/souris ET manette,
## sensibilité souris/manette, inversion Y, FOV, disposition clavier (AZERTY/QWERTY).
## Les bindings par DÉFAUT (clavier + manette) sont dans project.godot ;
## ce fichier ne stocke que les overrides du joueur.
class_name Settings
extends RefCounted

const PATH := "user://settings.cfg"

## Actions remappables (libellé affiché dans le menu Options).
const ACTIONS := {
	"move_forward": "Avancer",
	"move_back": "Reculer",
	"move_left": "Gauche",
	"move_right": "Droite",
	"jump": "Sauter",
	"walk": "Marcher (maintien)",
	"crouch": "Accroupi / Slide",
	"dive": "Plonger",
	"fire": "Tirer",
	"aim": "Viser (ADS)",
	"reload": "Recharger",
}

## Présets de disposition clavier (touches LOGIQUES = libellés imprimés).
const LAYOUTS := {
	"qwerty": {"move_forward": KEY_W, "move_back": KEY_S, "move_left": KEY_A, "move_right": KEY_D},
	"azerty": {"move_forward": KEY_Z, "move_back": KEY_S, "move_left": KEY_Q, "move_right": KEY_D},
}

static var mouse_sensitivity: float = 0.0025
static var gamepad_sensitivity: float = 3.0
static var invert_y: bool = false
static var fov: float = 90.0
static var layout: String = "qwerty"
static var _loaded: bool = false

static func load_all() -> void:
	if _loaded:
		return
	_loaded = true
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return  # premier lancement : on garde les défauts de project.godot
	mouse_sensitivity = float(cfg.get_value("input", "mouse_sensitivity", mouse_sensitivity))
	gamepad_sensitivity = float(cfg.get_value("input", "gamepad_sensitivity", gamepad_sensitivity))
	invert_y = bool(cfg.get_value("input", "invert_y", invert_y))
	fov = float(cfg.get_value("video", "fov", fov))
	layout = str(cfg.get_value("input", "layout", layout))
	for action in ACTIONS:
		var dk = cfg.get_value("binds_kb", action, null)
		if dk is Dictionary:
			var ev := _dict_to_event(dk)
			if ev:
				_replace_keyboard_event(action, ev)
		var dp = cfg.get_value("binds_pad", action, null)
		if dp is Dictionary:
			var evp := _dict_to_event(dp)
			if evp:
				_replace_joy_event(action, evp)

static func save_all() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("input", "mouse_sensitivity", mouse_sensitivity)
	cfg.set_value("input", "gamepad_sensitivity", gamepad_sensitivity)
	cfg.set_value("input", "invert_y", invert_y)
	cfg.set_value("input", "layout", layout)
	cfg.set_value("video", "fov", fov)
	for action in ACTIONS:
		var kb := _first_key_or_mouse(action)
		if kb:
			cfg.set_value("binds_kb", action, _event_to_dict(kb))
		var pad := _first_joy(action)
		if pad:
			cfg.set_value("binds_pad", action, _event_to_dict(pad))
	cfg.save(PATH)

## Applique un préset de disposition clavier (touches de déplacement).
static func apply_layout(name: String) -> void:
	if not LAYOUTS.has(name):
		return
	layout = name
	for action in LAYOUTS[name]:
		var e := InputEventKey.new()
		e.keycode = LAYOUTS[name][action] as Key  # touche logique => libellé correct
		_replace_keyboard_event(action, e)
	save_all()

## Remappe une action (clavier, souris ou manette — remplace le même type).
static func set_binding(action: String, event: InputEvent) -> void:
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		_replace_joy_event(action, event)
	else:
		_replace_keyboard_event(action, event)
	save_all()

# ------------------------------------------------------------------ AFFICHAGE
static func binding_text(action: String) -> String:
	var ev := _first_key_or_mouse(action)
	return event_text(ev) if ev else "—"

static func gamepad_text(action: String) -> String:
	var ev := _first_joy(action)
	return event_text(ev) if ev else "—"

static func event_text(ev: InputEvent) -> String:
	if ev is InputEventKey:
		# Touche logique (keycode) : libellé direct.
		if ev.keycode != 0:
			return OS.get_keycode_string(ev.keycode)
		# Touche PHYSIQUE : on affiche le libellé réel selon la disposition de
		# l'OS (Z/Q/S/D en AZERTY, W/A/S/D en QWERTY…), tout en gardant un
		# binding physique pour que ça marche quelle que soit la disposition.
		var label := DisplayServer.keyboard_get_label_from_physical(ev.physical_keycode)
		if label != 0:
			return OS.get_keycode_string(label)
		return OS.get_keycode_string(ev.physical_keycode)
	if ev is InputEventMouseButton:
		match ev.button_index:
			MOUSE_BUTTON_LEFT: return "Clic gauche"
			MOUSE_BUTTON_RIGHT: return "Clic droit"
			MOUSE_BUTTON_MIDDLE: return "Clic milieu"
			_: return "Souris %d" % ev.button_index
	if ev is InputEventJoypadButton:
		return _joy_button_name(ev.button_index)
	if ev is InputEventJoypadMotion:
		return _joy_axis_name(ev.axis, ev.axis_value)
	return "?"

static func _joy_button_name(idx: int) -> String:
	match idx:
		JOY_BUTTON_A: return "A / Croix"
		JOY_BUTTON_B: return "B / Cercle"
		JOY_BUTTON_X: return "X / Carré"
		JOY_BUTTON_Y: return "Y / Triangle"
		JOY_BUTTON_BACK: return "Select"
		JOY_BUTTON_START: return "Start"
		JOY_BUTTON_LEFT_STICK: return "L3"
		JOY_BUTTON_RIGHT_STICK: return "R3"
		JOY_BUTTON_LEFT_SHOULDER: return "LB"
		JOY_BUTTON_RIGHT_SHOULDER: return "RB"
		JOY_BUTTON_DPAD_UP: return "D-Pad ↑"
		JOY_BUTTON_DPAD_DOWN: return "D-Pad ↓"
		JOY_BUTTON_DPAD_LEFT: return "D-Pad ←"
		JOY_BUTTON_DPAD_RIGHT: return "D-Pad →"
		_: return "Bouton %d" % idx

static func _joy_axis_name(axis: int, value: float) -> String:
	match axis:
		JOY_AXIS_TRIGGER_LEFT: return "LT"
		JOY_AXIS_TRIGGER_RIGHT: return "RT"
		JOY_AXIS_LEFT_X: return "Stick G %s" % ("→" if value > 0 else "←")
		JOY_AXIS_LEFT_Y: return "Stick G %s" % ("↓" if value > 0 else "↑")
		JOY_AXIS_RIGHT_X: return "Stick D %s" % ("→" if value > 0 else "←")
		JOY_AXIS_RIGHT_Y: return "Stick D %s" % ("↓" if value > 0 else "↑")
		_: return "Axe %d" % axis

# ------------------------------------------------------------------ HELPERS
static func _first_key_or_mouse(action: String) -> InputEvent:
	if not InputMap.has_action(action):
		return null
	for e in InputMap.action_get_events(action):
		if e is InputEventKey or e is InputEventMouseButton:
			return e
	return null

static func _first_joy(action: String) -> InputEvent:
	if not InputMap.has_action(action):
		return null
	for e in InputMap.action_get_events(action):
		if e is InputEventJoypadButton or e is InputEventJoypadMotion:
			return e
	return null

static func _replace_keyboard_event(action: String, event: InputEvent) -> void:
	if not InputMap.has_action(action):
		return
	for e in InputMap.action_get_events(action):
		if e is InputEventKey or e is InputEventMouseButton:
			InputMap.action_erase_event(action, e)
	InputMap.action_add_event(action, event)

static func _replace_joy_event(action: String, event: InputEvent) -> void:
	if not InputMap.has_action(action):
		return
	for e in InputMap.action_get_events(action):
		if e is InputEventJoypadButton or e is InputEventJoypadMotion:
			InputMap.action_erase_event(action, e)
	InputMap.action_add_event(action, event)

static func _event_to_dict(ev: InputEvent) -> Dictionary:
	if ev is InputEventKey:
		return {"type": "key", "physical": int(ev.physical_keycode), "keycode": int(ev.keycode)}
	if ev is InputEventMouseButton:
		return {"type": "mouse", "button": int(ev.button_index)}
	if ev is InputEventJoypadButton:
		return {"type": "joyb", "button": int(ev.button_index)}
	if ev is InputEventJoypadMotion:
		return {"type": "joym", "axis": int(ev.axis), "value": float(ev.axis_value)}
	return {}

static func _dict_to_event(d: Dictionary) -> InputEvent:
	match d.get("type", ""):
		"key":
			var e := InputEventKey.new()
			e.physical_keycode = int(d.get("physical", d.get("code", 0))) as Key
			e.keycode = int(d.get("keycode", 0)) as Key
			return e
		"mouse":
			var e := InputEventMouseButton.new()
			e.button_index = int(d.get("button", 1)) as MouseButton
			return e
		"joyb":
			var e := InputEventJoypadButton.new()
			e.button_index = int(d.get("button", 0)) as JoyButton
			return e
		"joym":
			var e := InputEventJoypadMotion.new()
			e.axis = int(d.get("axis", 0)) as JoyAxis
			e.axis_value = float(d.get("value", 1.0))
			return e
	return null
