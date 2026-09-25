## GameHUD.gd
## HUD de jeu « encre et papier » (design.md, locked) : compose les modules en
## composants (scripts/ui/hud/*) — vitalité, munitions, capacités, score/
## timer/phase, killfeed, scoreboard (Tab), manche/bombe/crédits, mort/fin.
## La zone centrale (40 %×40 %) ne contient QUE le viseur/hitmarkers/lunette
## (design.md §8). Se branche automatiquement sur le joueur local (groupe
## "local_player") et ses composants ; rien n'intercepte la souris.
extends CanvasLayer

## Pile partagée des overlays modaux (Pause/Achat/fin de match, BUG-U01) :
## voir PauseMenu.gd — mêmes noms de groupe. L'écran de fin de match
## s'enregistre ici pendant qu'il est affiché ; `Input.mouse_mode` n'est
## recapturé que quand la pile est vide (ne vole pas la souris à Pause/Achat
## resté ouvert par-dessus).
const MODAL_GROUP := "ui_modal_stack"

## Zone centrale 40 %×40 % (STYLE_BIBLE v3 §8.3, tokens.json
## `hud.center_zone.allowed_group`) : SEULS les nœuds de ce groupe peuvent s'y
## dessiner (réticule, hitmarker, arcs de dégâts, lunette — voir
## `_build_crosshair`/`_build`/`_build_scope`, CHK-35).
const HUD_CENTER_GROUP := "hud_center"

var _player: PlayerController
var _health: Health
var _weapon: Weapon
var _abilities: Node
var _mode: Node
var _match: Node

var _crosshair: Crosshair
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

# ----------------------------------------------------------- Minimap + zone (UX-04)
var _minimap: Minimap
var _location_label: LocationLabel
## Nœud MapSetup courant (LD-04, retrouvé via le groupe "nav_region" déjà
## établi par BotNavMesh.gd/MapSetup.gd — jamais recherché à CHAQUE image :
## acquis une fois, comme `_match`/`_mode` ci-dessous).
var _map_setup: Node
var _minimap_map_id: String = ""

# ----------------------------------------------------------- Retours de combat (R4-FX)
var _vignette: LowHealthVignette
var _hit_marker: HitMarker
var _damage_dir: DamageDirection
var _kill_word: KillWordBurst
## Victime du DERNIER kill signalé par `_on_kill_logged` où le joueur LOCAL
## est le tueur (§5 « mot de kill ... + victime ») — capturée en attendant
## `_trigger_kill_word` (voir sa doc : `Weapon.hit_confirmed` et
## `GameWorld.kill_logged` sont deux RPC serveur distincts sans garantie
## d'ordre d'arrivée, même limite déjà documentée pour `_last_death_weapon`
## ci-dessous). Jamais réutilisée après consommation (voir `_trigger_kill_word`).
var _pending_kill_victim: String = ""

# ----------------------------------------------------------- Killfeed enrichi (UX-01)
## Arme/capacité du DERNIER kill reçu par le joueur LOCAL comme VICTIME
## (relance QA ART-36, 2e passage) : capturée par `_on_kill_logged`, consommée
## par `_on_died` pour l'écran « REMBALLÉ » (§9.5 « nom du tueur ▼ + arme »).
## `Health.died(killer_id)` ne transporte PAS l'arme (voir Health.gd, hors de
## ma liste de fichiers) — seul `GameWorld.kill_logged` la connaît. Remise à
## vide par `_on_respawned` (jamais réutilisée d'une mort à l'autre : le
## joueur ne peut pas mourir deux fois sans respawn entre les deux, `Health.
## apply_damage` ignore tout dégât une fois `is_dead`). Les DEUX signaux
## (`Health.died` et `GameWorld.kill_logged`) sont des RPC serveur distincts
## sans garantie d'ordre d'arrivée documentée : `_on_died`/`_on_kill_logged`
## se complètent quel que soit l'ordre plutôt que de supposer l'un avant
## l'autre — voir leurs docs respectives.
var _last_death_weapon: String = ""

## Plus de champs `_own_kill_*` ici (relance QA UX-01) : `GameWorld._killfeed`
## résout maintenant l'arme/la capacité ET le headshot CÔTÉ SERVEUR pour TOUT
## kill, bot contre bot compris (voir `GameWorld._record_kill`/
## `_kill_weapon_name`/`_fresh_headshot`/`_fresh_active_ability`) — deviner sa
## PROPRE arme via `Weapon.hit_confirmed` (l'ancien mécanisme) ne couvrait
## jamais le kill d'un autre joueur, ce que la relance QA visait précisément.

func _ready() -> void:
	_build()

func _build() -> void:
	_build_crosshair()
	_vignette = LowHealthVignette.new()
	add_child(_vignette)
	_damage_dir = DamageDirection.new()
	Comic.anchor(_damage_dir, Control.PRESET_CENTER)
	_damage_dir.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_damage_dir.add_to_group(HUD_CENTER_GROUP)
	add_child(_damage_dir)
	_hit_marker = HitMarker.new()
	Comic.anchor(_hit_marker, Control.PRESET_CENTER)
	_hit_marker.add_to_group(HUD_CENTER_GROUP)
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
	_build_minimap()
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
## Réticule dynamique (GF-09, Crosshair.gd) : remplace l'ancien tracé de
## traits fixes (ColorRect) par un Control qui recalcule l'écart CHAQUE FRAME
## depuis la dispersion réelle — voir `_update_crosshair`. Apparence + option
## statique (UX-03) : `Settings.crosshair_settings`/`Settings.static_crosshair`
## sont déjà chargés à cet instant (`Settings.load_all()` tourne à l'entrée en
## partie — GameWorld._ready/MainMenu, avant qu'aucun GameHUD n'existe) — lus
## UNE fois ici, jamais réappliqués en boucle dans `_process` (l'éditeur de
## viseur n'est pas censé rester ouvert PENDANT un match).
func _build_crosshair() -> void:
	_crosshair = Crosshair.new()
	Comic.anchor(_crosshair, Control.PRESET_CENTER)
	_crosshair.add_to_group(HUD_CENTER_GROUP)
	_crosshair.apply_settings(Settings.crosshair_settings)
	_crosshair.static_mode = Settings.static_crosshair
	add_child(_crosshair)

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
	_scope.add_to_group(HUD_CENTER_GROUP)
	add_child(_scope)

	_scope_reticle = Control.new()
	_scope_reticle.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scope_reticle.visible = false
	_scope_reticle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scope_reticle.add_to_group(HUD_CENTER_GROUP)
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

## Minimap (haut-gauche, design.md §12) + nom de zone SOUS elle (UX-04) — les
## deux composants s'auto-positionnent dans leur `_ready()` (voir Minimap.gd/
## LocationLabel.gd), rien à faire ici qu'ajouter les nœuds.
func _build_minimap() -> void:
	_minimap = Minimap.new()
	add_child(_minimap)
	_location_label = LocationLabel.new()
	add_child(_location_label)

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

	_update_minimap()

	if _ability_bar and _abilities and _abilities.has_method("slot_info"):
		# `_abilities.agent` (AbilityController.agent, hors de mon périmètre
		# d'écriture mais un champ public déjà exposé) : sert à AbilityBar à
		# convertir le ratio de recharge en secondes (STYLE_BIBLE v3 §8.3,
		# voir AbilityBar._apply_state) -- même patron de lecture duck-typée
		# que `_mode.winner`/`_mode.team_score` ci-dessous.
		_ability_bar.refresh(_abilities.slot_info(), _abilities.agent)

	if _match == null or not is_instance_valid(_match):
		_match = get_tree().get_first_node_in_group("match")
		if _match and _match.has_signal("kill_logged") and not _match.kill_logged.is_connected(_on_kill_logged):
			_match.kill_logged.connect(_on_kill_logged)

	var local_team: int = _player.team

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
		_score_panel.update(_mode.team_score(0), _mode.team_score(1), _mode.winner, str(_mode.hud_state), ot, timer_text, local_team)
		_round_panel.update_round(_mode, local_team)
	else:
		_score_panel.hide_panel()
		_round_panel.update_round(null, local_team)

	if _scoreboard:
		var show_sb: bool = Input.is_action_pressed("scoreboard") or (_mode != null and _mode.winner >= 0)
		_scoreboard.visible = show_sb
		if show_sb:
			_scoreboard.refresh(_match, local_team)

	_update_end()

	if _weapon and _scope:
		var scoping: bool = _weapon.is_scoped() and Input.is_action_pressed("aim") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
		_scope.visible = scoping
		_scope_reticle.visible = scoping
		if _crosshair:
			_crosshair.visible = not scoping
			if not scoping:
				_update_crosshair()

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
		_weapon.fired.connect(_on_weapon_fired)
		if _weapon.cfg():
			_on_weapon_changed(_weapon.cfg())
		if _weapon.current < _weapon.mag.size():
			_on_ammo_changed(_weapon.mag[_weapon.current], _weapon.reserve_a[_weapon.current])

## Minimap + zone (UX-04) — état joueur (position/cap), équipe locale
## (alliés toujours, `Minimap.ally_positions`) et ennemis RÉVÉLÉS seulement
## (`Minimap.revealed_enemy_positions`, jamais un `PlayerController` ennemi lu
## directement -- voir Minimap.gd doc de classe). Le nom de zone est relu
## CHAQUE image (`MapSetup.callout_at`), donc largement sous les 250 ms exigés
## par le contrat.
func _update_minimap() -> void:
	if _minimap == null:
		return
	if _map_setup == null or not is_instance_valid(_map_setup):
		_acquire_map_setup()

	var basis := _player.global_transform.basis
	_minimap.set_player_state(_player.global_position, -basis.z)

	var zone := ""
	if _map_setup != null and is_instance_valid(_map_setup) and _map_setup.has_method("callout_at"):
		zone = String(_map_setup.callout_at(_player.global_position))
	if _location_label:
		_location_label.set_zone_name(zone)

	var local_team: int = _player.team
	var candidates: Array = []
	var players_root := _player.get_parent()
	if players_root:
		for child in players_root.get_children():
			if child == _player or not (child is PlayerController):
				continue
			var pc := child as PlayerController
			var hp := pc.get_node_or_null("Health")
			if hp and bool(hp.get("is_dead")):
				continue  # coéquipier mort : jamais un point fantôme sur la minimap.
			candidates.append({"team": pc.team, "pos": pc.global_position})
	_minimap.set_allies(Minimap.ally_positions(candidates, local_team))

	_minimap.set_enemies(Minimap.revealed_enemy_positions(get_tree().get_nodes_in_group("round_props")))

## Retrouve le `MapSetup` de la carte courante via le groupe "nav_region"
## (établi par `MapSetup._build_geometry`/`BotNavMesh.gd` -- jamais un nouveau
## groupe, cette tâche ne touche pas à MapSetup.gd, hors de sa liste de
## fichiers). Un `nav_region` de secours (scènes sans MapSetup, ex. stand de
## tir) n'a pas `callout_at` : `_map_setup` reste alors `null`, la minimap
## affiche simplement l'état vide (aucune empreinte, aucune zone).
func _acquire_map_setup() -> void:
	var nav := get_tree().get_first_node_in_group("nav_region")
	if nav == null:
		return
	var parent := nav.get_parent()
	if parent == null or not parent.has_method("callout_at"):
		return
	_map_setup = parent
	var map_id := String(parent.get("map_id")) if "map_id" in parent else ""
	if map_id == "" or map_id == _minimap_map_id:
		return
	_minimap_map_id = map_id
	_minimap.set_layout(_layout_data_for(map_id).get("pieces", []))

## Mêmes deux exceptions que `MapSetup._data_for` (Cargo Ship/Wasteland vivent
## hors de `Layouts.gd`/`Layouts.MAP_IDS`, hors de la liste de fichiers de
## cette tâche : dupliqué ici en lecture seule plutôt que d'appeler la méthode
## `_`-préfixée de MapSetup.gd, jamais touché).
func _layout_data_for(map_id: String) -> Dictionary:
	match map_id:
		"cargo_ship":
			return CargoShipLayout.data()
		"wasteland":
			return WastelandLayout.data()
	return Layouts.data_for(map_id)

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
		_ammo_panel.update_weapon(cfg.weapon_name, cfg.mag_size)
	_update_inventory()

func _update_inventory() -> void:
	if _ammo_panel == null or _weapon == null:
		return
	_ammo_panel.update_inventory(_weapon.weapons, _weapon.current)

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

func _on_kill_logged(killer: String, victim: String, killer_team: int, weapon_or_ability: String, headshot: bool) -> void:
	var is_local := _player != null and killer == _local_display_name()
	var local_team: int = _player.team if _player != null and is_instance_valid(_player) else -1
	var victim_team := _team_of(victim)
	if _killfeed:
		_killfeed.push(killer, victim, killer_team, victim_team, local_team, is_local, weapon_or_ability, headshot)
	# Écran de mort « REMBALLÉ » (§9.5, relance QA ART-36) : capture l'arme du
	# kill dont la VICTIME est le joueur local — voir la doc de `_last_death_weapon`.
	# Si `_on_died` a déjà affiché le panneau (kill_logged arrivé APRÈS
	# Health.died), on le rafraîchit avec l'arme désormais connue plutôt que de
	# la laisser vide jusqu'au respawn.
	if _player != null and victim == _local_display_name():
		_last_death_weapon = weapon_or_ability
		if _death_panel and _death_panel.visible:
			_death_panel.show_death(killer, weapon_or_ability)
	# Mot de kill (§5, KillWordBurst) : le joueur LOCAL est le tueur -- capture
	# la victime pour la prochaine `_trigger_kill_word`, et rafraîchit un burst
	# déjà affiché si `Weapon.hit_confirmed` est arrivé EN PREMIER (voir la doc
	# de `_pending_kill_victim`/`KillWordBurst.set_victim`).
	if _player != null and killer == _local_display_name():
		_pending_kill_victim = victim
		if _kill_word:
			_kill_word.set_victim(victim)

## Retrouve l'équipe de `display_name` dans `_match.player_info` (même
## dictionnaire que Scoreboard/EndPanel, alimenté par le serveur) — -1 si
## absent (jamais une équipe inventée pour la victime).
func _team_of(display_name: String) -> int:
	if _match == null or not is_instance_valid(_match):
		return -1
	var info: Dictionary = _match.player_info
	for id in info:
		if str(info[id].name) == display_name:
			return int(info[id].team)
	return -1

## "Joueur %d" : identique au nom que GameWorld._spawn_player attribue à tout
## humain (jamais bot — `local_player` n'est ajouté qu'à l'humain devant CE
## clavier, voir PlayerController.is_local_human) dans `player_info`/killfeed.
func _local_display_name() -> String:
	return "Joueur %d" % str(_player.name).to_int() if _player else ""

## `_pos`/`_dmg` : position/chiffre de dégâts déjà affichés par
## `Weapon._spawn_damage_number` (cosmétique 3D) — `headshot`/`is_kill`
## pilotent la variante du hitmarker et le mot-bruit. `is_kill` vient
## directement du SERVEUR (GF-07 : Weapon.hit_confirmed, plus de fenêtre de
## correspondance devinée avec kill_logged).
func _on_hit_confirmed(_pos: Vector3, _dmg: float, headshot: bool, is_kill: bool) -> void:
	if _hit_marker:
		_hit_marker.show_hit(HitFeedback.marker_variant(headshot, is_kill))
	if is_kill:
		_trigger_kill_word(headshot)

## Onomatopée DE L'ARME en main (STYLE_BIBLE v3 §9.4 « + onomatopée de
## l'arme », relance QA UX-01) — remplace le mot générique historique
## `HitFeedback.sound_word` (encore verrouillé par
## tests/ui/test_hit_feedback.gd, hors de mon périmètre d'écriture, mais plus
## appelé ici). `headshot` n'influence plus le MOT (retiré de la table §9.4
## v3 — seul le hitmarker `CLONK` orange le distingue encore, voir
## `HitFeedback.marker_variant`) : gardé en paramètre pour les appelants
## existants (`_on_hit_confirmed`, `debug_force_kill_word`,
## tests/ui/capture_shots.gd `kill_word`/`kill_word_headshot`).
## Ne rend JAMAIS la main tôt sur `_kill_word.is_busy()` (relance QA) : un
## doublé/triplé plus rapide que les 700 ms du burst précédent doit quand même
## faire avancer le compteur multi-kill (`KillWordBurst._update_streak`, sur
## SA PROPRE horloge murale, indépendante de `is_busy()`) — `play()` relance
## simplement le burst par-dessus plutôt que d'ignorer le kill suivant.
func _trigger_kill_word(_headshot: bool) -> void:
	if _kill_word == null:
		return
	var word := _weapon.current_kill_word() if _weapon else HitFeedback.weapon_kill_word("")
	var vp := get_viewport().get_visible_rect().size
	# Meilleure estimation disponible (voir la doc de `_pending_kill_victim`) :
	# "" si `GameWorld.kill_logged` n'est pas encore arrivé -- `KillWordBurst.
	# set_victim` rattrapera alors le burst déjà affiché depuis `_on_kill_logged`.
	_kill_word.play(word, _pending_kill_victim, KillWordBurst.burst_rect_v4(vp))
	_pending_kill_victim = ""

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
		var local_team: int = _player.team if _player != null and is_instance_valid(_player) else -1
		_end_panel.show_result(_mode.winner, _mode.team_score(0), _mode.team_score(1), _match, local_team, _agent_colors_for_match())
		add_to_group(MODAL_GROUP)
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif not over and _end_shown:
		_end_shown = false
		_end_panel.hide_result()
		remove_from_group(MODAL_GROUP)
		if get_tree().get_nodes_in_group(MODAL_GROUP).is_empty():
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _on_replay() -> void:
	if _match == null or not is_instance_valid(_match):
		return
	if multiplayer.is_server():
		_match.reset_match()
	else:
		_match.request_reset.rpc_id(1)

func _on_menu() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")

## Résout le tueur (§9.5, relance QA ART-36 2e passage) : le nom vient de
## `_match.player_info` — un champ « spawn only », déjà présent bien avant
## cette mort, donc SANS dépendance à l'ordre d'arrivée des RPC (contrairement
## à l'arme, voir `_last_death_weapon`). `killer_id <= 0` (environnement/chute)
## ou entrée absente (déconnecté entre-temps) : chaîne vide — DeathPanel
## retombe alors sur son état VIDE par défaut (« Réapparition imminente… »),
## jamais un nom inventé.
func _on_died(killer_id: int) -> void:
	if _death_panel == null:
		return
	_death_panel.show_death(_resolve_player_name(killer_id), _last_death_weapon)

func _resolve_player_name(player_id: int) -> String:
	if player_id <= 0 or _match == null or not is_instance_valid(_match):
		return ""
	var info: Dictionary = _match.player_info
	if not info.has(player_id):
		return ""
	return str(info[player_id].name)

func _on_respawned() -> void:
	if _death_panel:
		_death_panel.hide_death()
	_last_death_weapon = ""

## Aplat couleur-clé de l'agent joué, par id de pair (relance QA ART-36, 2e
## passage — voir la note de tête de fichier d'EndPanel._mvp_card) :
## `player_info` (GameWorld.gd) ne porte pas l'identité d'agent, mais
## `PlayerController.agent_index` (répliqué "spawn only", voir GameWorld.
## _spawn_player) si — bots ET humains, même après le spawn. Parcouru comme
## `_update_minimap` parcourt déjà `players_root` (même conteneur "Players"),
## jamais via une méthode `_`-préfixée de GameWorld. `{}` si le joueur local
## n'est pas encore acquis (ex. capture isolée sans match réel) — EndPanel
## retombe alors honnêtement sur la couleur d'équipe, voir sa doc.
func _agent_colors_for_match() -> Dictionary:
	var colors := {}
	if _player == null or not is_instance_valid(_player):
		return colors
	var players_root := _player.get_parent()
	if players_root == null:
		return colors
	for child in players_root.get_children():
		if not (child is PlayerController):
			continue
		var pc := child as PlayerController
		if pc.agent_index < 0:
			continue
		colors[str(pc.name).to_int()] = AgentDatabase.get_by_index(pc.agent_index).color
	return colors

## Force la page de fin pour les captures d'écran (tests/ui/capture_shots.gd),
## jamais appelé en jeu normal (la vraie condition passe par `_update_end`).
## `local_team_override` : force l'équipe locale affichée (0/1) — sert
## UNIQUEMENT aux captures des DEUX perspectives (relance QA UX-01 : « le HUD
## est relatif au joueur local, donc à vérifier depuis les deux équipes » —
## voir tests/ui/capture_shots.gd `--team=` et tools/review/ui_shots.gd).
## `-1` (défaut) : équipe RÉELLE du joueur local si déjà acquis (test_arena),
## sinon 0 — comportement historique, inchangé pour tout appelant existant.
## Passe aussi `_agent_colors_for_match()` (relance QA ART-36, 2e passage) :
## la carte MVP de la capture `end` doit prouver l'aplat de l'agent, pas
## seulement l'appel réel en jeu.
func debug_force_end(winner: int, team0: int, team1: int, local_team_override: int = -1) -> void:
	var local_team := local_team_override if local_team_override >= 0 else (_player.team if _player != null and is_instance_valid(_player) else 0)
	_end_panel.show_result(winner, team0, team1, _match, local_team, _agent_colors_for_match())

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

## Victime de démonstration (même convention que `debug_force_killfeed_local`
## ci-dessous, "BOT Renard") : `_trigger_kill_word` seul n'a normalement de
## victime qu'après un VRAI `_on_kill_logged` (voir sa doc) -- une capture
## d'écran isolée (tests/ui/capture_shots.gd `kill_word`/`kill_word_headshot`)
## n'en déclenche jamais un, donc rien ne le remplirait sans ce repli.
func debug_force_kill_word(headshot: bool = false) -> void:
	_pending_kill_victim = "BOT Renard"
	_trigger_kill_word(headshot)

## Entrée de killfeed mise en évidence (contract-r4a.md "R4-FX" #4, "killfeed
## entry highlighted") — sans dépendre d'un vrai kill_logged. Démontre aussi
## l'enrichissement UX-01 (icône d'arme/capacité — noms RÉELS du catalogue,
## resources/weapons/ravage.tres et scripts/agents/abilities/FlashAbility.gd —
## ✦ headshot, victime colorée par équipe) : le kill d'équipe 0 sur équipe 1
## (headshot au Ravage) et le kill d'équipe 1 sur équipe 0 (Éblouissement,
## capacité) sont FIXES ; seule la coloration allié/ennemi change avec
## `local_team_override` (relance QA UX-01, mêmes captures des deux équipes
## que `debug_force_end` ci-dessus — voir sa docstring).
func debug_force_killfeed_local(local_team_override: int = -1) -> void:
	if _killfeed:
		var local_team := local_team_override if local_team_override >= 0 else (_player.team if _player != null and is_instance_valid(_player) else 0)
		_killfeed.push("Joueur 1", "BOT Renard", 0, 1, local_team, true, "Ravage", true)
		_killfeed.push("BOT Iris", "Joueur 1", 1, 0, local_team, false, "Éblouissement", false)
