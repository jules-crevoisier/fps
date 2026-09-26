## GameHUD.gd
## HUD minimal du prototype (décision 2026-09-26, "strip to minimal
## prototype") : réticule + hitmarker UNIQUEMENT. Tout le reste de l'ancienne
## interface de jeu (vitalité, munitions, capacités, score/timer/phase,
## minimap, killfeed, scoreboard, écrans de mort/fin, vignette de dégâts,
## mot de kill, lunette de visée...) a été supprimé avec les systèmes qu'il
## affichait (capacités, modes à manches/économie, agents multiples, armes
## multiples). Se branche automatiquement sur le joueur local (groupe
## "local_player") pour lire la dispersion RÉELLE de son arme (Crosshair,
## GF-09 — même pipeline que le tir, Weapon._fire_local) et confirmer ses
## tirs (HitMarker, sur Weapon.hit_confirmed) ; rien n'intercepte la souris.
## Échap quitte directement le jeu (pas de menu pause à ouvrir).
extends CanvasLayer

## Zone centrale 40 %×40 % (STYLE_BIBLE v3 §8.3, tokens.json
## `hud.center_zone.allowed_group`) : SEULS les nœuds de ce groupe peuvent s'y
## dessiner (réticule, hitmarker — CHK-35).
const HUD_CENTER_GROUP := "hud_center"

var _player: PlayerController
var _weapon: Weapon

var _crosshair: Crosshair
var _hit_marker: HitMarker

func _ready() -> void:
	_build()

func _build() -> void:
	_build_crosshair()
	_hit_marker = HitMarker.new()
	Comic.anchor(_hit_marker, Control.PRESET_CENTER)
	_hit_marker.add_to_group(HUD_CENTER_GROUP)
	add_child(_hit_marker)

## Réticule dynamique (GF-09) : apparence + option statique (UX-03) lues une
## fois ici depuis `Settings.crosshair_settings`/`Settings.static_crosshair`
## (déjà chargés à cet instant, voir GameWorld._ready/QuickStart.gd, avant
## qu'aucun GameHUD n'existe).
func _build_crosshair() -> void:
	_crosshair = Crosshair.new()
	Comic.anchor(_crosshair, Control.PRESET_CENTER)
	_crosshair.add_to_group(HUD_CENTER_GROUP)
	_crosshair.apply_settings(Settings.crosshair_settings)
	_crosshair.static_mode = Settings.static_crosshair
	add_child(_crosshair)

## Prototype minimal : plus de menu pause à ouvrir — Échap quitte
## directement (contrat de la tâche "strip to minimal prototype").
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		get_tree().quit()

func _process(_delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_acquire_player()
		return
	if _weapon:
		_update_crosshair()

func _acquire_player() -> void:
	var arr := get_tree().get_nodes_in_group("local_player")
	if arr.is_empty():
		return
	_player = arr[0]
	_weapon = _player.get_node_or_null("Weapon")
	if _weapon:
		_weapon.fired.connect(_on_weapon_fired)
		_weapon.hit_confirmed.connect(_on_hit_confirmed)

## Bloom du réticule (GF-09) : un tir prédit localement (`Weapon.fired`,
## propriétaire uniquement) déclenche le fondu — voir Crosshair.notify_shot.
func _on_weapon_fired(_cfg: WeaponConfig) -> void:
	if _crosshair:
		_crosshair.notify_shot()

## Recalcule l'écart du réticule CHAQUE FRAME depuis la MÊME pipeline de
## dispersion que le tir (GF-09, Weapon._fire_local : spread_hip/aim +
## WeaponFeel.move_spread_deg + air_spread_add, ou pellet_spread pour un
## fusil à pompe — jamais une approximation locale au HUD) — voir Crosshair.gd.
func _update_crosshair() -> void:
	if _crosshair == null or _weapon == null or _player == null:
		return
	var c := _weapon.cfg()
	if c == null:
		return
	var aiming: bool = _player.input.aim_held
	var airborne := not _player.is_on_floor()
	var sliding := _player.state_machine.current_name == "Slide"
	var move_spread := WeaponFeel.move_spread_deg(c, _player.horizontal_speed(), _player.config.sprint_speed, sliding)
	var air_spread := c.air_spread_add if airborne else 0.0
	var base_deg := c.spread_aim if aiming else c.spread_hip
	# Fusil à pompe (GF-13/Weapon._fire_local) : chaque plomb suit `pellet_spread`
	# directement, sans dispersion de mouvement/air ajoutée — même choix que le tir.
	var spread_deg: float = c.pellet_spread if c.pellets > 1 else WeaponFeel.total_spread_deg(base_deg, move_spread, air_spread)
	var fov_v_deg: float = _player.camera.fov if _player.camera else 90.0
	var screen_h := get_viewport().get_visible_rect().size.y
	_crosshair.update_spread(deg_to_rad(spread_deg), fov_v_deg, screen_h)

## `_pos`/`_dmg` : ignorés (le chiffre de dégâts 3D reste posé par
## `Weapon._spawn_damage_number`, hors HUD). `headshot`/`is_kill` pilotent la
## variante du hitmarker. `is_kill` vient directement du SERVEUR
## (GF-07 : Weapon.hit_confirmed).
func _on_hit_confirmed(_pos: Vector3, _dmg: float, headshot: bool, is_kill: bool) -> void:
	if _hit_marker:
		_hit_marker.show_hit(HitFeedback.marker_variant(headshot, is_kill))

# ----------------------------------------------------------- Déclencheur de capture (R4-FX)
## Réservé aux captures d'écran (tools/review/ui_shots.gd) — jamais appelé en
## jeu normal. `variant` : "normal" / "headshot" / "kill" (HitFeedback.MARKER_*).
func debug_force_hit_marker(variant: String) -> void:
	if _hit_marker:
		_hit_marker.show_hit(variant)
