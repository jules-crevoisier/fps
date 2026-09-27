## GameHUD.gd
## HUD complet du prototype (contrat lead 2026-09-27, "HUD en jeu") : réticule
## + hitmarker (zone centrale, INCHANGÉS), vitalité (bas-gauche), munitions +
## inventaire (bas-droite), score/chrono (haut-centre), fil des éliminations
## (haut-droite), minicarte (haut-gauche), bandeau K.O. (centre, sous la zone
## centrale), incrustation de flashbang. Se branche automatiquement sur le
## joueur local (groupe "local_player") pour lire la dispersion RÉELLE de son
## arme (Crosshair, GF-09 — même pipeline que le tir, Weapon._fire_local) et
## confirmer ses tirs (HitMarker, sur Weapon.hit_confirmed) ; rien
## n'intercepte la souris. Échap ouvre le menu pause (PauseMenu.gd, calque 50).
extends CanvasLayer

## Zone centrale 40 %×40 % (STYLE_BIBLE v3 §8.3, tokens.json
## `hud.center_zone.allowed_group`) : SEULS les nœuds de ce groupe peuvent s'y
## dessiner (réticule, hitmarker — CHK-35).
const HUD_CENTER_GROUP := "hud_center"

## Fenêtre (s) pendant laquelle un K.O. déclenché par `hit_confirmed`
## (prédiction propriétaire, immédiate) accepte le nom de victime d'un
## `GameWorld.kill_logged` déjà arrivé JUSTE avant (RPC, latence variable) —
## voir `_trigger_ko_banner`/`_on_kill_logged`.
const _KO_NAME_MATCH_WINDOW_S := 1.0

var _player: PlayerController
var _weapon: Weapon
## Tâche "utilitaires" — voir `_acquire_player`/`_on_charges_changed`/
## `_on_local_blinded`.
var _utility: UtilityThrower
var _health: Health
var _game_mode: Node
var _game_world: Node

var _crosshair: Crosshair
var _hit_marker: HitMarker
## Tâche "inventaire CS-style" (2026-09-27) : rangée de 5 emplacements
## inclinés bas-droite — voir InventoryHUD.gd et `_update_inventory_hud`.
var _inventory_hud: InventoryHUD
var _vitals_hud: VitalsHUD
var _ammo_hud: AmmoHUD
var _score_hud: ScoreHUD
var _kill_feed: KillFeed
var _minimap_hud: MinimapHUD
var _pause_menu: PauseMenu
var _ko_banner: KoBanner
## Tâche "TAB SCOREBOARD" (2026-09-27) : voile plein écran tant que l'action
## "scoreboard" est maintenue -- voir `_update_scoreboard`.
var _scoreboard: ScoreboardHUD
## Tâche "DEATH SCREEN" (2026-09-27) : affiché à la mort du joueur LOCAL,
## masqué à son respawn -- voir `_on_local_died`/`_on_local_respawned`.
var _death_screen: DeathScreen
var _flash_overlay: ColorRect
var _flash_tween: Tween

var _local_id: int = -1
var _last_local_kill_victim: String = ""
var _last_local_kill_time: float = -INF
## Tueur du joueur LOCAL (Health.died, id de pair — 0/négatif = environnement,
## même convention que Health.apply_damage) -- résolu à l'affichage de l'écran
## de mort (`_show_death_screen`), remis à -1 au respawn.
var _death_killer_id: int = -1
## Arme/tir à la tête du DERNIER `kill_logged` qui désigne le joueur LOCAL
## comme VICTIME -- le RPC kill_logged (nom/arme/tête) et le RPC Health.died
## (id du tueur) arrivent séparément, dans un ordre non garanti (même course
## que `_last_local_kill_victim`/`_KO_NAME_MATCH_WINDOW_S` ci-dessus, côté
## victime plutôt que tueur) : voir `_show_death_screen`.
var _last_local_death_weapon: String = ""
var _last_local_death_headshot: bool = false
var _last_local_death_event_time: float = -INF
## `debug_show_scoreboard` en cours (tools/ui/hud_capture.gd) : suspend le
## polling normal de l'action "scoreboard" dans `_update_scoreboard`, sinon
## celui-ci referme le tableau dès la frame suivante (action réellement
## RELÂCHÉE pendant une capture -- rien ne la maintient).
var _debug_scoreboard_forced: bool = false
## player_id -> true : Weapon.remote_fired déjà branché pour ce joueur DISTANT
## (minicarte, marqueurs ennemis) — voir `_update_minimap`.
var _connected_enemy_weapons: Dictionary = {}
## player_id -> dernier instant de tir (s, Time.get_ticks_msec) — alimente
## `MinimapHUD.marker_visible`.
var _enemy_last_fire: Dictionary = {}
## Minicarte : dernier instant où chaque ennemi a été vu ou entendu, et prochain rayon de vue.
var _enemy_last_spotted: Dictionary = {}
var _enemy_next_sight_check: Dictionary = {}

func _ready() -> void:
	_build()

func _build() -> void:
	_pause_menu = PauseMenu.new()
	add_child(_pause_menu)
	_build_crosshair()
	_hit_marker = HitMarker.new()
	Comic.anchor(_hit_marker, Control.PRESET_CENTER)
	_hit_marker.add_to_group(HUD_CENTER_GROUP)
	add_child(_hit_marker)
	_inventory_hud = InventoryHUD.new()
	add_child(_inventory_hud)
	_vitals_hud = VitalsHUD.new()
	add_child(_vitals_hud)
	_ammo_hud = AmmoHUD.new()
	add_child(_ammo_hud)
	_score_hud = ScoreHUD.new()
	add_child(_score_hud)
	_kill_feed = KillFeed.new()
	add_child(_kill_feed)
	_minimap_hud = MinimapHUD.new()
	add_child(_minimap_hud)
	_minimap_hud.set_map_name(MatchConfig.map_id)
	_ko_banner = KoBanner.new()
	add_child(_ko_banner)
	_death_screen = DeathScreen.new()
	add_child(_death_screen)
	# Dernier ajouté = tout en haut de la pile de dessin (voile plein écran
	# tant que "scoreboard" est maintenu, contrat "hors de la vue de rien").
	_scoreboard = ScoreboardHUD.new()
	add_child(_scoreboard)
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

## Échap ouvre le menu pause (REPRENDRE / PARAMÈTRES / QUITTER VERS LE SALON / QUITTER LE JEU).
## Une fois ouvert, c'est PauseMenu lui-même (enfant, donc servi en premier) qui se referme sur
## Échap. La partie continue derrière (réseau autoritaire serveur, voir PauseMenu.gd).
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and _pause_menu and not _pause_menu.is_open():
		_pause_menu.open()
		get_viewport().set_input_as_handled()

func _process(_delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_acquire_player()
		return
	if _weapon:
		_update_crosshair()
	_update_inventory_hud()
	_update_game_mode_hud()
	_update_minimap()
	_update_scoreboard()

func _acquire_player() -> void:
	var arr := get_tree().get_nodes_in_group("local_player")
	if arr.is_empty():
		return
	_player = arr[0]
	_local_id = str(_player.name).to_int()
	_weapon = _player.get_node_or_null("Weapon")
	if _weapon:
		_weapon.fired.connect(_on_weapon_fired)
		_weapon.hit_confirmed.connect(_on_hit_confirmed)
		_weapon.ammo_changed.connect(_on_ammo_changed)
		_weapon.weapon_changed.connect(_on_weapon_changed)
		_weapon.reload_started.connect(_on_reload_started)
		# état initial : le joueur apparaît arme en main, aucun signal n'arrive avant le 1er tir
		_on_weapon_changed(_weapon.cfg())
	_utility = _player.get_node_or_null("UtilityThrower") as UtilityThrower
	if _utility:
		_utility.charges_changed.connect(_on_charges_changed)
		_utility.local_blinded.connect(_on_local_blinded)
		_utility.equipped_changed.connect(_on_equipped_changed)
		_on_charges_changed(_utility.snapshot_charges())
	_health = _player.get_node_or_null("Health") as Health
	if _health:
		_health.health_changed.connect(_on_health_changed)
		_health.died.connect(_on_local_died)
		_health.respawned.connect(_on_local_respawned)
		_vitals_hud.update_hp(_health.current_health, _health.max_health)
	_vitals_hud.set_character_name("Verrou")
	_acquire_game_world()

func _acquire_game_world() -> void:
	if _game_world != null and is_instance_valid(_game_world):
		return
	_game_world = get_tree().get_first_node_in_group("match")
	if _game_world and not _game_world.kill_logged.is_connected(_on_kill_logged):
		_game_world.kill_logged.connect(_on_kill_logged)
	if _game_world and not _game_world.stats_changed.is_connected(_on_stats_changed):
		_game_world.stats_changed.connect(_on_stats_changed)

## Compteurs de charges (tâche "utilitaires") — voir InventoryHUD.update_charges.
## Rafraîchit aussi AmmoHUD si une grenade est ACTUELLEMENT en main (son
## compte doit suivre les mêmes charges).
func _on_charges_changed(charges: Array) -> void:
	if _inventory_hud:
		_inventory_hud.update_charges(charges)
	if _utility and _utility.is_utility_equipped():
		var k := _utility.equipped_kind()
		_ammo_hud.show_grenade(k, int(charges[k]) if k < charges.size() else 0)

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

## Score/chrono (ScoreHUD) — le mode de jeu (groupe "game_mode",
## MapSetup._build_game_mode) peut apparaître APRÈS ce HUD selon l'ordre de
## construction de la scène ; retenté chaque frame tant qu'il est introuvable.
func _update_game_mode_hud() -> void:
	if _game_mode == null or not is_instance_valid(_game_mode):
		_game_mode = get_tree().get_first_node_in_group("game_mode")
	if _game_mode == null:
		return
	_score_hud.update_scores(_game_mode.team_scores, _player.team, _game_mode.score_to_win)
	_score_hud.update_clock(_game_mode.match_elapsed, _game_mode.match_time_limit)

## Minicarte : soi (position + lacet), alliés (points), ennemis (points rouges, visibles
## 1,5 s après avoir été VUS ou ENTENDUS -- voir MinimapHUD.heard/marker_visible).
func _update_minimap() -> void:
	if _minimap_hud == null:
		return
	_minimap_hud.update_self(_player.global_position, _player.rotation.y)
	var allies: Array = []
	var enemies: Array = []
	if _game_world:
		var players := _game_world.get_node_or_null(_game_world.players_root)
		if players:
			for child in players.get_children():
				if child == _player or not (child is PlayerController):
					continue
				var pc := child as PlayerController
				if pc.team == _player.team:
					allies.append(pc.global_position)
				else:
					var pid := str(pc.name).to_int()
					_ensure_enemy_weapon_connected(pc, pid)
					_spot_enemy(pc, pid)
					enemies.append({"pos": pc.global_position, "last_spotted": _enemy_last_spotted.get(pid, -INF)})
	_minimap_hud.update_allies(allies)
	_minimap_hud.update_enemies(enemies)

## Repérage d'un ennemi pour la minicarte : entendu (tir récent ou course proche,
## MinimapHUD.heard) ou vu (dans le champ de la caméra, à portée, ligne de vue libre à travers
## le décor ET la fumée -- masque WORLD|VISION, comme UtilityThrower.smoke_between). Le rayon
## de vue n'est lancé que tous les 0,1 s par ennemi.
func _spot_enemy(pc: PlayerController, pid: int) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var dist := _player.global_position.distance_to(pc.global_position)
	var fired := now - float(_enemy_last_fire.get(pid, -INF)) <= 0.1
	if MinimapHUD.heard(dist, pc.horizontal_speed(), fired):
		_enemy_last_spotted[pid] = now
		return
	if dist > MinimapHUD.SIGHT_M or now < float(_enemy_next_sight_check.get(pid, 0.0)):
		return
	_enemy_next_sight_check[pid] = now + 0.1
	var cam := _player.camera
	var target := pc.global_position + Vector3(0.0, 1.2, 0.0)
	if cam == null or not cam.is_position_in_frustum(target):
		return
	var query := PhysicsRayQueryParameters3D.create(cam.global_position, target, PhysicsLayers.WORLD | PhysicsLayers.VISION)
	query.exclude = [_player.get_rid(), pc.get_rid()]
	if _player.get_world_3d().direct_space_state.intersect_ray(query).is_empty():
		_enemy_last_spotted[pid] = now

## Branche `Weapon.remote_fired` d'un joueur ENNEMI une seule fois (bruit de tir, minicarte).
func _ensure_enemy_weapon_connected(pc: PlayerController, pid: int) -> void:
	if _connected_enemy_weapons.has(pid):
		return
	var w := pc.get_node_or_null("Weapon") as Weapon
	if w == null:
		return
	_connected_enemy_weapons[pid] = true
	w.remote_fired.connect(func(_cfg, _origin, _dirs): _enemy_last_fire[pid] = Time.get_ticks_msec() / 1000.0)

## Tâche "TAB SCOREBOARD" : affiché plein écran tant que l'action
## "scoreboard" est MAINTENUE (contrat point 1), masqué au relâchement.
## Les rangées ne sont reconstruites qu'à l'OUVERTURE (fraîcheur immédiate)
## et sur `GameWorld.stats_changed` (`_on_stats_changed`, contrat "updates
## live") -- jamais reconstruites chaque frame (coût inutile, les nœuds
## existent déjà). L'en-tête (chrono) suit en revanche chaque frame tant que
## le tableau est affiché, comme ScoreHUD.
func _update_scoreboard() -> void:
	if _scoreboard == null or _debug_scoreboard_forced:
		return
	var held := Input.is_action_pressed("scoreboard")
	var was_shown := _scoreboard.visible
	if held and not was_shown and _game_world:
		_scoreboard.update_rows(_game_world.player_info, _player.team, _local_id)
	_scoreboard.set_shown(held)
	_score_hud.visible = not held   # l'en-tête du tableau reprend score et chrono
	if not held:
		return
	if _game_mode == null or not is_instance_valid(_game_mode):
		_game_mode = get_tree().get_first_node_in_group("game_mode")
	if _game_mode == null:
		return
	_scoreboard.update_header(_game_mode.mode_name, MatchConfig.map_id, _game_mode.match_elapsed, _game_mode.match_time_limit, _game_mode.score_to_win)
	_scoreboard.update_scores(_game_mode.team_scores, _player.team)

## `GameWorld.stats_changed` (contrat "updates live on stats_changed") --
## rafraîchit les rangées immédiatement à chaque kill/mort, que le tableau
## soit affiché ou non (prêt dès la prochaine pression de Tab).
func _on_stats_changed() -> void:
	if _scoreboard == null or _player == null or _game_world == null:
		return
	_scoreboard.update_rows(_game_world.player_info, _player.team, _local_id)

func _on_health_changed(current: float, maximum: float) -> void:
	_vitals_hud.update_hp(current, maximum)

func _on_ammo_changed(ammo: int, reserve: int) -> void:
	if _utility and _utility.is_utility_equipped():
		return  # une grenade est affichée à la place, voir _on_equipped_changed.
	_ammo_hud.set_reloading(false)
	var c := _weapon.cfg() if _weapon else null
	_ammo_hud.update_ammo(ammo, reserve, c.mag_size if c else 0)

func _on_weapon_changed(cfg: WeaponConfig) -> void:
	if _utility == null or not _utility.is_utility_equipped():
		_ammo_hud.set_weapon(cfg)
		_refresh_ammo()

## Relit chargeur/réserve de l'arme courante : `ammo_changed` n'est pas réémis quand on revient
## d'une grenade (ni à un simple changement d'arme), le panneau restait sur « 0 / 0 ».
func _refresh_ammo() -> void:
	if _weapon == null:
		return
	var c := _weapon.cfg()
	var i := _weapon.current
	if c == null or i >= _weapon.mag.size():
		return
	_ammo_hud.update_ammo(int(_weapon.mag[i]), int(_weapon.reserve_a[i]), c.mag_size)

func _on_reload_started(_cfg: WeaponConfig) -> void:
	_ammo_hud.set_reloading(true)

## `kind == -1` : retour à l'arme (contrat "inventaire CS-style" point 6) —
## AmmoHUD réaffiche l'arme courante ; sinon, la grenade équipée remplace le
## fil de munitions (contrat "HUD en jeu" point 2).
func _on_equipped_changed(kind: int) -> void:
	if kind == -1:
		_ammo_hud.set_weapon(_weapon.cfg() if _weapon else null)
		_refresh_ammo()
		return
	var charges: Array = _utility.snapshot_charges() if _utility else []
	_ammo_hud.show_grenade(kind, int(charges[kind]) if kind < charges.size() else 0)

## Bulle de dégâts (tâche "utilitaires") : voir Health.hit_reaction --
## `debug_force_flash` ci-dessous pour les captures.
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
func _on_weapon_fired(_cfg: WeaponConfig, _is_fan: bool = false) -> void:
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
## (GF-07 : Weapon.hit_confirmed) — déclenche aussi le bandeau K.O. (contrat
## point 7).
func _on_hit_confirmed(_pos: Vector3, _dmg: float, headshot: bool, is_kill: bool) -> void:
	if _hit_marker:
		_hit_marker.show_hit(HitFeedback.marker_variant(headshot, is_kill))
	if is_kill:
		_trigger_ko_banner()

## Le nom de la victime vient du dernier `GameWorld.kill_logged` qui désigne
## le joueur LOCAL comme tueur, s'il est arrivé (RPC) dans les
## `_KO_NAME_MATCH_WINDOW_S` dernières secondes — sinon le bandeau montre
## juste "K.O. !" (voir KoBanner.show_ko) ; `_on_kill_logged` le relance avec
## le bon nom si ce RPC arrive juste APRÈS.
func _trigger_ko_banner() -> void:
	var victim := ""
	if Time.get_ticks_msec() / 1000.0 - _last_local_kill_time <= _KO_NAME_MATCH_WINDOW_S:
		victim = _last_local_kill_victim
	_ko_banner.show_ko(victim)

func _local_display_name() -> String:
	if _game_world == null or _local_id == -1:
		return ""
	var info: Dictionary = _game_world.player_info.get(_local_id, {})
	return String(info.get("name", ""))

## Fil des éliminations (contrat point 5) — alimenté par la diffusion réseau
## déjà existante (`GameWorld._killfeed`/`kill_logged`, hors de mon périmètre
## d'écriture : rien à ajouter côté réseau). Relance aussi le bandeau K.O.
## avec le nom exact si le tueur est le joueur LOCAL (voir `_trigger_ko_banner`).
func _on_kill_logged(killer: String, victim: String, killer_team: int, weapon_or_ability: String, headshot: bool) -> void:
	var local_name := _local_display_name()
	var is_local_killer := local_name != "" and killer == local_name
	_kill_feed.add_kill(killer, victim, killer_team, _player.team if _player else 0, weapon_or_ability, headshot, is_local_killer)
	if is_local_killer:
		_last_local_kill_victim = victim
		_last_local_kill_time = Time.get_ticks_msec() / 1000.0
		_ko_banner.show_ko(victim)
	# Tâche "DEATH SCREEN" : ce `kill_logged` désigne le joueur LOCAL comme
	# VICTIME -- garde l'arme/tir à la tête pour l'écran de mort (voir
	# `_show_death_screen`), et le relance directement si `Health.died` est
	# déjà arrivé sans cette info (même course que le bandeau K.O. ci-dessus).
	if local_name != "" and victim == local_name:
		_last_local_death_weapon = weapon_or_ability
		_last_local_death_headshot = headshot
		_last_local_death_event_time = Time.get_ticks_msec() / 1000.0
		if _health and _health.is_dead:
			_show_death_screen()

## `Health.died` du joueur LOCAL (contrat "DEATH SCREEN" point 2) — `killer_id`
## est l'unique donnée fiable de cette RPC (nom/arme viennent séparément de
## `kill_logged`, voir ci-dessus) ; 0/négatif = suicide/environnement (même
## convention que Health.apply_damage "attacker_id = 0 = environnement").
func _on_local_died(killer_id: int) -> void:
	_death_killer_id = killer_id
	_show_death_screen()

## `Health.respawned` du joueur LOCAL — masque l'écran de mort et restaure les
## éléments centraux qu'il avait cachés (contrat point 3).
## Vie, munitions et inventaire n'ont aucun sens pendant l'écran de mort (et l'anneau de
## réapparition occupe le bas-centre, là où est la barre d'inventaire).
func _set_combat_hud_visible(v: bool) -> void:
	for n in [_vitals_hud, _ammo_hud, _inventory_hud]:
		if n:
			n.visible = v

func _on_local_respawned() -> void:
	_death_killer_id = -1
	_death_screen.hide_death()
	_set_combat_hud_visible(true)
	if _crosshair:
		_crosshair.visible = true
	if _hit_marker:
		_hit_marker.visible = true

## Nom du tueur `killer_id` depuis `GameWorld.player_info` (même source que
## `_local_display_name`) — "" si inconnu (pair parti, id invalide).
func _resolve_killer_name(killer_id: int) -> String:
	if killer_id <= 0 or _game_world == null:
		return ""
	var info: Dictionary = _game_world.player_info.get(killer_id, {})
	return String(info.get("name", ""))

## PV ACTUELS du tueur `killer_id`, SEULEMENT s'ils sont fiables côté client :
## `Health.current_health` est répliqué à TOUS les pairs par RPC directe
## (`Health._sync_health`, pas seulement au propriétaire — contrairement à
## `damage_from_direction` par exemple), donc lisible pour n'importe quel
## joueur vivant du groupe "Players". `null` si non résolvable (environnement,
## tueur déjà parti/parti de l'arbre) -- l'appelant masque alors la ligne
## plutôt que d'afficher une valeur inventée (contrat "ONLY if reliably
## available").
func _resolve_killer_hp(killer_id: int) -> Variant:
	if killer_id <= 0 or _game_world == null:
		return null
	var players := _game_world.get_node_or_null(_game_world.players_root)
	if players == null:
		return null
	var killer_node := players.get_node_or_null(str(killer_id))
	if killer_node == null:
		return null
	var hp := killer_node.get_node_or_null("Health") as Health
	if hp == null:
		return null
	return hp.current_health

## Construit et affiche l'écran de mort à partir de l'état connu MAINTENANT
## (`_death_killer_id`, posé par `_on_local_died` ; arme/tête, posés par
## `_on_kill_logged` s'ils sont arrivés dans `_KO_NAME_MATCH_WINDOW_S`) --
## appelée par les DEUX déclencheurs possibles (`_on_local_died` en premier en
## général, `_on_kill_logged` en second si son RPC arrive après coup), jamais
## affichée tant que `Health.is_dead` n'est pas vrai (garde contre un
## `kill_logged` en retard reçu APRÈS le respawn).
func _show_death_screen() -> void:
	if _health == null or not _health.is_dead:
		return
	var killer_id := _death_killer_id
	var is_env := DeathScreen.is_environment_death(killer_id)
	var killer_name := DeathScreen.killer_display_name(killer_id, _resolve_killer_name(killer_id))
	var weapon := ""
	var headshot := false
	if not is_env and Time.get_ticks_msec() / 1000.0 - _last_local_death_event_time <= _KO_NAME_MATCH_WINDOW_S:
		weapon = _last_local_death_weapon
		headshot = _last_local_death_headshot
	var hp_variant: Variant = _resolve_killer_hp(killer_id)
	var has_hp := not is_env and hp_variant != null
	var hp_value: float = float(hp_variant) if hp_variant != null else 0.0
	var delay: float = _game_world.respawn_delay if _game_world else 3.0
	# Contrat point 3 : masque le centre de l'écran (réticule, hitmarker, K.O.)
	# tant que l'écran de mort est affiché -- le fil des éliminations reste visible.
	if _crosshair:
		_crosshair.visible = false
	if _hit_marker:
		_hit_marker.visible = false
	_ko_banner.visible = false
	_set_combat_hud_visible(false)
	_death_screen.show_death(killer_name, is_env, weapon, headshot, hp_value, has_hp, delay)

# ----------------------------------------------------------- Déclencheur de capture (R4-FX)
## Réservé aux captures d'écran (tools/review/ui_shots.gd, tools/ui/hud_capture.gd)
## — jamais appelé en jeu normal. `variant` : "normal" / "headshot" / "kill"
## (HitFeedback.MARKER_*).
func debug_force_hit_marker(variant: String) -> void:
	if _hit_marker:
		_hit_marker.show_hit(variant)

## Réservé aux captures d'écran (tools/rigging/utility_filmstrip.gd) — force
## l'incrustation blanche de flashbang sans dépendre du timing réseau/physique
## réel d'un lancer (même esprit que `debug_force_hit_marker` ci-dessus).
func debug_force_flash(duration: float) -> void:
	_on_local_blinded(duration)

## Réservé aux captures d'écran (tools/ui/hud_capture.gd) — force le fil des
## éliminations + le bandeau K.O. sans dépendre du timing réseau réel d'un kill.
func debug_force_kill_feed_and_ko(killer: String, victim: String, killer_team: int, weapon_or_ability: String, headshot: bool, is_local_killer: bool) -> void:
	_kill_feed.add_kill(killer, victim, killer_team, _player.team if _player else 0, weapon_or_ability, headshot, is_local_killer)
	if is_local_killer:
		_ko_banner.show_ko(victim)

## Réservé aux captures d'écran (tools/ui/hud_capture.gd) — affiche/masque le
## tableau des scores sans dépendre du maintien réel de l'action "scoreboard".
func debug_show_scoreboard(shown: bool) -> void:
	if _scoreboard == null:
		return
	_debug_scoreboard_forced = shown
	_score_hud.visible = not shown
	if shown and _game_world and _player:
		_scoreboard.update_rows(_game_world.player_info, _player.team, _local_id)
	if shown and _game_mode == null:
		_game_mode = get_tree().get_first_node_in_group("game_mode")
	if shown and _game_mode:
		_scoreboard.update_header(_game_mode.mode_name, MatchConfig.map_id, _game_mode.match_elapsed, _game_mode.match_time_limit, _game_mode.score_to_win)
		_scoreboard.update_scores(_game_mode.team_scores, _player.team if _player else 0)
	_scoreboard.set_shown(shown)

## Réservé aux captures d'écran (tools/ui/hud_capture.gd) — force l'écran de
## mort sans dépendre du timing réseau réel d'une mort. `killer` vide = repli
## "L'ENVIRONNEMENT" (pas de ligne d'arme), même contrat que `_show_death_screen`.
## PV du tueur fixé à 45 (valeur de démonstration de la maquette) quand `killer`
## est renseigné -- une vraie mort en jeu passe toujours par `_show_death_screen`.
func debug_force_death(killer: String, weapon_or_ability: String, headshot: bool) -> void:
	if _death_screen == null:
		return
	var is_env := killer.is_empty()
	if _crosshair:
		_crosshair.visible = false
	if _hit_marker:
		_hit_marker.visible = false
	_ko_banner.visible = false
	_set_combat_hud_visible(false)
	var delay: float = _game_world.respawn_delay if _game_world else 3.0
	_death_screen.show_death(
		DeathScreen.killer_display_name(0 if is_env else 1, killer), is_env,
		weapon_or_ability, headshot, 45.0, not is_env, delay
	)
