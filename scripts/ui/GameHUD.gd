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
## Tâche "utilitaires" — voir `_acquire_player`/`_on_charges_changed`/
## `_on_local_blinded`.
var _utility: UtilityThrower

var _crosshair: Crosshair
var _hit_marker: HitMarker
## Tâche "inventaire CS-style" (2026-09-27) : remplace l'ancien UtilityHUD
## (3 emplacements bas-centre) par le panneau 5 rangées bas-droite — voir
## InventoryHUD.gd et `_update_inventory_hud` ci-dessous.
var _inventory_hud: InventoryHUD
var _flash_overlay: ColorRect
var _flash_tween: Tween

func _ready() -> void:
	_build()

func _build() -> void:
	_build_crosshair()
	_hit_marker = HitMarker.new()
	Comic.anchor(_hit_marker, Control.PRESET_CENTER)
	_hit_marker.add_to_group(HUD_CENTER_GROUP)
	add_child(_hit_marker)
	_inventory_hud = InventoryHUD.new()
	add_child(_inventory_hud)
	_build_flash_overlay()

## Incrustation plein écran de la flashbang (contrat lead : "a full-screen
## white overlay with a fast fade-out") — hors de la zone centrale par
## construction (couvre TOUT l'écran, donc la zone centrale aussi : c'est le
## seul élément HUD volontairement au-dessus du réticule pendant l'éblouissement,
## voir son `z_index`) ; invisible (alpha 0) tant qu'aucun flash ne l'anime.
func _build_flash_overlay() -> void:
	_flash_overlay = ColorRect.new()
	Comic.anchor(_flash_overlay, Control.PRESET_FULL_RECT)
	_flash_overlay.color = Color(1, 1, 1, 0)
	_flash_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash_overlay.z_index = 100
	add_child(_flash_overlay)

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
	_update_inventory_hud()

func _acquire_player() -> void:
	var arr := get_tree().get_nodes_in_group("local_player")
	if arr.is_empty():
		return
	_player = arr[0]
	_weapon = _player.get_node_or_null("Weapon")
	if _weapon:
		_weapon.fired.connect(_on_weapon_fired)
		_weapon.hit_confirmed.connect(_on_hit_confirmed)
	_utility = _player.get_node_or_null("UtilityThrower") as UtilityThrower
	if _utility:
		_utility.charges_changed.connect(_on_charges_changed)
		_utility.local_blinded.connect(_on_local_blinded)
		_on_charges_changed(_utility.snapshot_charges())

## Compteurs de charges (tâche "utilitaires") — voir InventoryHUD.update_charges.
func _on_charges_changed(charges: Array) -> void:
	if _inventory_hud:
		_inventory_hud.update_charges(charges)

## Tâche "inventaire CS-style" : rafraîchit le panneau ENTIER chaque frame
## (armes + rangée équipée) — polling plutôt que purement signal-driven :
## `Weapon.weapon_changed`/`UtilityThrower.equipped_changed` couvrent déjà
## les changements ponctuels, mais un simple `_process` évite tout risque de
## rangée périmée si un signal était manqué (ex. acquisition tardive du
## joueur local, voir `_acquire_player`) — coût négligeable (5 rangées, pas
## de reconstruction de nœud, seulement des propriétés déjà légères comme
## `_update_crosshair` ci-dessus).
func _update_inventory_hud() -> void:
	if _inventory_hud == null or _weapon == null:
		return
	var names := []
	for cfg in _weapon.weapons:
		names.append((cfg.weapon_name as String).to_upper() if cfg else "")
	_inventory_hud.update_weapon_slots(names)
	var equipped := _weapon.current
	if _utility and _utility.is_utility_equipped():
		equipped = InventorySelection.slot_of_grenade(_utility.equipped_kind())
	_inventory_hud.set_equipped(equipped)

## Incrustation blanche plein écran (contrat lead : "a full-screen white
## overlay with a fast fade-out") — relance depuis blanc plein à CHAQUE appel
## (un nouveau flash reçu pendant le fondu d'un précédent remplace l'animation
## en cours plutôt que de s'additionner, même discipline que
## CameraShake.add_fov_punch pour un punch déjà actif). `duration` vient du
## SERVEUR (FlashMath.blind_duration_for_target, selon l'orientation au
## moment de l'éclat) : le blanc plein dure `duration`, puis fond en 0,6 s.
## = FlashMath.RECOVERY_S : l'indicateur au-dessus de la victime et l'éblouissement
## des bots durent flash + ce fondu (même durée totale partout).
const _FLASH_FADE_OUT_S := FlashMath.RECOVERY_S

func _on_local_blinded(duration: float) -> void:
	if _flash_overlay == null:
		return
	if _flash_tween:
		_flash_tween.kill()
	_flash_overlay.color.a = 1.0
	_flash_tween = create_tween()
	_flash_tween.tween_interval(maxf(duration, 0.0))
	_flash_tween.tween_property(_flash_overlay, "color:a", 0.0, _FLASH_FADE_OUT_S)

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

## Réservé aux captures d'écran (tools/rigging/utility_filmstrip.gd) — force
## l'incrustation blanche de flashbang sans dépendre du timing réseau/physique
## réel d'un lancer (même esprit que `debug_force_hit_marker` ci-dessus).
func debug_force_flash(duration: float) -> void:
	_on_local_blinded(duration)
