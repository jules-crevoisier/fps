## HardpointMode.gd
## Mode Hardpoint (CoD) : une zone à tenir. Une équipe SEULE dans la zone gagne
## des points/s ; deux équipes = contesté (rien). La zone tourne d'emplacement
## toutes les `rotate_interval` secondes. Premier à `score_to_win` gagne.
## Scoring serveur-autoritaire, synchronisé au HUD.
class_name HardpointMode
extends GameMode

@export var zone_path: NodePath
@export var points_path: NodePath
@export var capture_rate: float = 1.0      # points/s
@export var rotate_interval: float = 45.0

var _zone: Area3D
var _points: Array = []
var _point_index: int = 0
var _rotate_timer: float = 0.0
var _sync_timer: float = 0.0

## Préavis déjà déclenché pour le cycle de rotation EN COURS (LD-25) — évite
## de ré-invalider le cache de but à CHAQUE frame une fois entré dans la
## fenêtre de préavis (voir `_physics_process`) ; remis à faux par `_set_zone`
## (nouvelle rotation, nouveau cycle) et `reset_match`.
var _goal_preview_active: bool = false

## BOT-24 : même patron que `_goal_preview_active` ci-dessus, mais pour la
## fenêtre de PRÉ-ROTATION propre aux buts de bot (`BOT_PREROTATE_LEAD`, 15 s)
## — évite de ré-invalider à chaque frame une fois dans CETTE fenêtre-là,
## indépendamment de celle du HUD. Remis à faux par `_set_zone`/`reset_match`.
var _bot_prerotate_active: bool = false

## Échange de côté (maps-spec-v2.md §5.6.2/§7.5) — voir TDMMode.gd pour le
## détail complet de la convention (identique ici, dupliqué car GameMode.gd
## n'est pas dans mon périmètre cette manche). `side_swap_notice` reste séparé
## de `hud_state`, réécrit CHAQUE frame plus bas par la logique de capture.
@export var asymmetric_map: bool = false
var sides_swapped: bool = false
var side_swap_notice: String = ""

@rpc("authority", "call_local", "reliable")
func sync_sides_swapped(swapped: bool, notice: String) -> void:
	sides_swapped = swapped
	side_swap_notice = notice
	updated.emit()

func _ready() -> void:
	super._ready()
	mode_name = "Hardpoint"
	_zone = get_node_or_null(zone_path) as Area3D
	var pr := get_node_or_null(points_path)
	if pr:
		_points = pr.get_children()
	if multiplayer.is_server() and not _points.is_empty():
		_set_zone.rpc(0)

@rpc("authority", "call_local", "reliable")
func _set_zone(index: int) -> void:
	_point_index = index
	if _zone and index >= 0 and index < _points.size():
		_zone.global_position = (_points[index] as Node3D).global_position
	_goal_preview_active = false  # nouveau cycle de rotation (LD-25).
	_bot_prerotate_active = false  # nouveau cycle de rotation (BOT-24).
	_invalidate_bot_goals()  # évènement BOT-01 : "la zone qui tourne".

## Revanche (BUG-11) : en plus du changement de côté (voir TDMMode.gd), la
## zone doit repartir du point 0 avec sa minuterie de rotation à zéro —
## sinon la revanche reprenait au point et à l'instant de rotation où le
## match précédent s'était arrêté. Valeurs locales posées directement (même
## patron que `GameMode._set_sudden_death`), puis répliquées ; `_set_zone`
## n'est rejoué que s'il existe des points de rotation (même garde qu'en
## `_ready()`), mais `_point_index`/`_rotate_timer` sont toujours remis à
## zéro localement même sans eux.
func reset_match() -> void:
	super.reset_match()
	if not multiplayer.is_server():
		return
	sides_swapped = false
	side_swap_notice = ""
	sync_sides_swapped.rpc(false, "")
	_rotate_timer = 0.0
	_point_index = 0
	_goal_preview_active = false
	_bot_prerotate_active = false
	if not _points.is_empty():
		_set_zone.rpc(0)

## Délai (s) avant rotation en dessous duquel on annonce le prochain point
## (LD-25, docs/research/09_wasteland_vertical_slice.md §e : "préavis HP de
## 10 s" — HUD uniquement depuis BOT-24 (voir `BOT_PREROTATE_LEAD` ci-dessous
## pour le préavis PROPRE aux buts de bot) ; remplace l'ancien préavis HUD
## seul de R2, 15 s).
const PREVIEW_LEAD := 10.0

## BOT-24 (T5, docs/research/08_bots_humanlike.md §3.6) : délai (s) avant
## rotation en dessous duquel UN SEUL bot (`HP_PREROTATE_SLOT`) part déjà
## vers la zone SUIVANTE — "1 bot part vers la zone suivante 15 s avant la
## rotation". Fenêtre DISTINCTE de `PREVIEW_LEAD` (10 s, HUD seul, inchangée)
## : les deux se chevauchent (15 s > 10 s) mais chacune a son propre
## évènement d'invalidation (`_bot_prerotate_active` vs `_goal_preview_active`).
const BOT_PREROTATE_LEAD := 15.0

## BOT-24 (T5) : nombre de créneaux de rôle par zone Hardpoint — 2 "dans la
## zone" (rôle `BotMapKnowledge.ROLE_HOLD`) + 2 "en surveillance" (rôle
## `ROLE_WATCH`), jamais plus même si `hp_holds` déclare davantage de points
## de surveillance (Wasteland : 3 ou 4 selon la zone) : T5 ne veut que
## "2 bots dans la zone" et "1 ou 2 en surveillance".
const HP_HOLD_SLOTS := 2
const HP_WATCH_SLOTS := 2
const HP_ROLE_SLOT_COUNT := HP_HOLD_SLOTS + HP_WATCH_SLOTS

## Créneau (bot_id % HP_ROLE_SLOT_COUNT) qui part en PRÉ-ROTATION au lieu de
## surveiller — le DERNIER créneau de surveillance, jamais un créneau de
## tenue (les 2 bots DANS la zone ne bougent jamais avant la rotation
## réelle) : il reste donc toujours au moins 1 bot en surveillance pendant
## la fenêtre de pré-rotation, ce qui respecte "1 ou 2" (T5) dans les deux cas.
const HP_PREROTATE_SLOT := HP_ROLE_SLOT_COUNT - 1

func _physics_process(delta: float) -> void:
	super._physics_process(delta)  # minuteur de MATCH (10 min) commun
	if not multiplayer.is_server() or winner != -1:
		return

	if asymmetric_map and not sides_swapped:
		if HalfTime.should_swap(match_elapsed, match_time_limit, team_scores[0], team_scores[1], score_to_win):
			sync_sides_swapped.rpc(true, "CHANGEMENT DE CÔTÉ")

	# Rotation de la zone.
	if _points.size() > 1:
		_rotate_timer += delta
		# BOT-24 (T5, "1 bot part vers la zone suivante 15 s avant la
		# rotation") : évènement d'invalidation PROPRE à `BOT_PREROTATE_LEAD`,
		# distinct du préavis HUD (`PREVIEW_LEAD`, 10 s) ci-dessous — même
		# discipline d'un flag "déjà déclenché" pour ne pas ré-invalider à
		# chaque frame une fois dans la fenêtre.
		if rotate_interval - _rotate_timer <= BOT_PREROTATE_LEAD and not _bot_prerotate_active:
			_bot_prerotate_active = true
			_invalidate_bot_goals()
		# Préavis LD-25 ("annoncée 10 s avant... HUD") : dès l'entrée dans la
		# fenêtre de préavis, un évènement invalide IMMÉDIATEMENT le cache de
		# but (BOT-01) pour que `_compute_bot_goal` soit relu sans attendre
		# GOAL_REFRESH_INTERVAL -- `_goal_preview_active` évite de
		# ré-invalider à CHAQUE frame une fois dans la fenêtre.
		if rotate_interval - _rotate_timer <= PREVIEW_LEAD and not _goal_preview_active:
			_goal_preview_active = true
			_invalidate_bot_goals()
		if _rotate_timer >= rotate_interval:
			_rotate_timer = 0.0
			_set_zone.rpc((_point_index + 1) % _points.size())

	# Quelles équipes (vivantes) sont dans la zone ?
	var present := {}
	if _zone:
		for b in _zone.get_overlapping_bodies():
			if b is PlayerController:
				var hp := b.get_node_or_null("Health") as Health
				if hp and hp.is_dead:
					continue
				present[int(b.team)] = true

	var remain := int(rotate_interval - _rotate_timer)
	var preview := ""
	if _points.size() > 1 and remain <= int(PREVIEW_LEAD):
		var next_index := (_point_index + 1) % _points.size()
		preview = " · prochain point P%d dans %ds" % [next_index + 1, remain]
	if present.size() == 1:
		var team: int = present.keys()[0]
		team_scores[team] += capture_rate * delta
		hud_state = "Équipe %d capture%s" % [team + 1, preview]
		check_win()
	elif present.size() >= 2:
		hud_state = "Hardpoint CONTESTÉ%s" % preview
	else:
		hud_state = "Hardpoint neutre%s" % preview

	# Synchro throttlée des scores / état.
	_sync_timer += delta
	if _sync_timer >= 0.25 or winner != -1:
		_sync_timer = 0.0
		sync_state.rpc(team_scores, winner, hud_state)

## Tic sonore CLIENT (tous les pairs, y compris l'hôte) tant que l'équipe
## LOCALE capture SEULE le point (détecté via `hud_state`, répliqué par
## `sync_state` — R-E audio, "hardpoint_tick", ≈1/s).
var _tick_sfx_timer: float = 0.0

func _process(delta: float) -> void:
	var local_team := _local_player_team()
	if local_team < 0 or not hud_state.begins_with("Équipe %d capture" % (local_team + 1)):
		_tick_sfx_timer = 0.0
		return
	_tick_sfx_timer += delta
	if _tick_sfx_timer >= 1.0:
		_tick_sfx_timer = 0.0
		_play_sfx_ui("hardpoint_tick")

## Hardpoint : TOUS les rôles (tenue, surveillance, pré-rotation) sont des
## positions à tenir (T5) — voir `GameMode.bot_holds_position`. Sans cette
## garde, l'ouïe de BotBrain (tirs à <= 22 m, quasi permanents autour d'une
## zone disputée par 8 bots) primait sur `bot_goal_for` : banc hp_veteran
## Wasteland, 58 % des ticks vivants pilotés par le bruit, 11 % par le mode.
func bot_holds_position(_team: int, _bot_id: int) -> bool:
	return _zone != null

## Position de la PROCHAINE zone de rotation — `Vector3.ZERO` si `_points`
## n'en déclare qu'une (pas de rotation) ou aucune.
func _next_zone_position() -> Vector3:
	if _points.size() <= 1:
		return Vector3.ZERO
	var next_index := (_point_index + 1) % _points.size()
	return (_points[next_index] as Node3D).global_position

## Secondes restantes avant la PROCHAINE rotation — même horloge que le HUD
## (`_physics_process`, "prochain point Pd dans Ns").
func _seconds_before_rotation() -> float:
	return rotate_interval - _rotate_timer

## BOT-24 (T5, docs/research/08_bots_humanlike.md §3.7) : entrée de
## `bot_knowledge.hp_holds` dont le CENTROÏDE de son tableau `hold` (points
## DANS la zone) est le plus proche de `zone_pos` — appariement par
## PROXIMITÉ, jamais par nom/ordre : aucune carte n'a besoin d'ordonner ses
## zones Hardpoint ("A"/"B"/"C"...) dans le même ordre que `_points`/
## `_point_index` (rotation posée par la scène/`MapSetup`, hors de mon
## périmètre) — même discipline que l'ancien `_hold_points_near` (LD-25).
## -1 si `holds` est vide ou si aucune entrée n'a de tableau `hold` non vide.
func _hp_holds_index_near(zone_pos: Vector3, holds: Array) -> int:
	var best_index := -1
	var best_dist := INF
	for i in holds.size():
		var pts: Array = (holds[i] as Dictionary).get("hold", [])
		if pts.is_empty():
			continue
		var centroid := Vector3.ZERO
		for p in pts:
			centroid += (p as Vector3)
		centroid /= pts.size()
		var d := centroid.distance_to(zone_pos)
		if d < best_dist:
			best_dist = d
			best_index = i
	return best_index

## Hardpoint (BOT-24, T5, docs/research/08_bots_humanlike.md §3.6) : rôles
## STABLES lus depuis `bot_knowledge.hp_holds` (`BotMapKnowledge.hp_holds`,
## BOT-22/22B) plutôt que le centre COMMUN de la zone —
##  - `bot_id % HP_ROLE_SLOT_COUNT` donne un créneau STABLE par bot (jamais 2
##    bots de la même équipe sur le même créneau tant que l'effectif ne
##    dépasse pas `HP_ROLE_SLOT_COUNT`, même répartition stable qu'ailleurs
##    dans le contrat BOT-01/23 — des ids CONSÉCUTIFS, cas normal du
##    remplissage d'équipe, couvrent tous les créneaux exactement une fois).
##  - Les 2 premiers créneaux visent les positions de TENUE (`ROLE_HOLD`,
##    DANS la zone, >= 3 m d'écart sur les données réelles) ; les suivants,
##    les positions de SURVEILLANCE (`ROLE_WATCH`, entrées à distance).
##  - `HP_PREROTATE_SLOT` (dernier créneau de surveillance) bascule sur la
##    position de la zone SUIVANTE dès `BOT_PREROTATE_LEAD` (15 s) avant la
##    rotation — SEUL ce créneau part en avance ("1 bot", T5) : les autres
##    tiennent la zone ACTUELLE jusqu'à la rotation réelle (`_set_zone`).
## Repli sur le centre commun de la zone ACTUELLE (comportement historique)
## si la carte ne déclare aucun `bot_knowledge.hp_holds` — "repli propre sur
## une carte sans données" (LD-25), inchangé pour toute carte hors Wasteland.
func _compute_bot_goal(_team: int, bot_id: int, _bot_pos: Vector3, _reached: bool = false) -> Vector3:
	if _zone == null:
		return Vector3.ZERO
	var bk: Dictionary = _bot_knowledge().get("bot_knowledge", {})
	var holds: Array = bk.get("hp_holds", [])
	if holds.is_empty():
		return _zone.global_position

	var slot := bot_id % HP_ROLE_SLOT_COUNT
	if _points.size() > 1 and slot == HP_PREROTATE_SLOT and _seconds_before_rotation() <= BOT_PREROTATE_LEAD:
		return _next_zone_position()

	var index := _hp_holds_index_near(_zone.global_position, holds)
	if index < 0:
		return _zone.global_position
	var know := BotMapKnowledge.new(bk)
	var hold_pts: Array = know.hp_holds(index, BotMapKnowledge.ROLE_HOLD)
	if slot < hold_pts.size():
		return hold_pts[slot]
	var watch_pts: Array = know.hp_holds(index, BotMapKnowledge.ROLE_WATCH)
	var watch_slot := slot - hold_pts.size()
	if watch_slot < watch_pts.size():
		return watch_pts[watch_slot]
	return _zone.global_position
