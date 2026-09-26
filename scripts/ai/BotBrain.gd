## BotBrain.gd
## Cerveau d'un bot : perception (ligne de vue + audition des tirs récents),
## décision (combattre ou tenir l'objectif du mode) et pilotage — via
## `player.input` (scripts/player/PlayerInput.gd), EXACTEMENT les mêmes
## champs qu'un humain, plus `look_delta` (regard, réservé aux bots) — et un
## NavigationAgent3D pour le déplacement (contract-r3.md, R3-IN#2).
##
## Enfant "BotBrain" du joueur (scenes/player/player.tscn) : NO-OP pour un
## joueur humain (`player.is_bot == false`, fixé par le serveur AVANT le spawn
## — voir GameWorld._spawn_bot). Ne tourne QUE côté serveur (le seul pair qui
## simule réellement un bot). `process_physics_priority = -150`, plus bas que
## PlayerInput (-100) : les champs de `player.input` sont posés AVANT que
## PlayerInput (no-op pour un bot) et PlayerController ne s'exécutent.
##
## Va au combat via le MÊME pipeline de validation serveur qu'un humain
## (Weapon._owner_tick tourne pour ce joueur car son autorité EST le serveur,
## voir PlayerController._enter_tree) : aucun raccourci, aucune triche —
## seulement ce que le bot peut VOIR ou ENTENDRE (pas de wall-hack).
class_name BotBrain
extends Node

const REACTION := preload("res://scripts/ai/BotReaction.gd")
const TARGET_SELECT := preload("res://scripts/ai/BotTargetSelect.gd")
const AIM := preload("res://scripts/ai/BotAim.gd")
const STUCK := preload("res://scripts/ai/BotStuck.gd")
const STYLE := preload("res://scripts/ai/BotCombatStyle.gd")
const LOOK := preload("res://scripts/ai/BotLook.gd")
const PERCEPTION := preload("res://scripts/ai/BotPerception.gd")
const MEMORY := preload("res://scripts/ai/BotMemory.gd")

const SIGHT_RANGE := 45.0                  ## Portée de vue max (m).
const SIGHT_FOV := 100.0                   ## Cône de vue total (deg).
## Portée d'audition d'un tir (m) : voir `PERCEPTION.HEAR_GUNFIRE_RADIUS_M`
## (BOT-03, 40 m — remplace l'ancienne constante fixe à 22 m) ; sprint/impact
## ont leurs propres portées, voir `_hear_enemy_sprint`/`_hear_impacts`.
const HEAR_MEMORY := 4.0                   ## Le bot se souvient d'un bruit ce temps (s).
const REPATH_INTERVAL := 0.5               ## Recalcule le chemin toutes les 0.5 s.
const REPATH_PHASE_MAX := 0.5              ## Déphasage initial (s) du minuteur de recalcul de chemin, tiré par bot (BOT-21, T3) — sans ça, tous les bots recalculent leur chemin au même tick.
const WEAPON_SPREAD_FALLBACK_DEG := 1.0    ## Dispersion (deg) utilisée si le bot n'a encore aucune arme (cfg() == null, ex. avant le premier achat).
const AVOIDANCE_RADIUS := 0.45             ## Rayon (m) d'évitement RVO entre bots (BOT-09, NavigationAgent3D.radius).
const AVOIDANCE_REF_SPEED_FALLBACK := 8.2  ## m/s — repli si `player.config` est null (ne devrait pas arriver) ; valeur par défaut de MovementConfig.sprint_speed.
const STRAFE_LOOKAHEAD := 1.0              ## m — distance de projection du strafe de combat sur la navmesh avant application (BOT-09).

var player: PlayerController
var nav_agent: NavigationAgent3D

var _difficulty: int = MatchConfig.Difficulty.VETERAN
var _target_id: int = -1
var _target_pos: Vector3 = Vector3.INF
var _tracking_time: float = 0.0
var _reaction_left: float = 0.0
var _heard_pos: Vector3 = Vector3.ZERO
var _heard_until: float = 0.0
var _strafe_dir: int = 1
var _strafe_timer: float = 2.0
var _repath_timer: float = 0.0
var _rng := RandomNumberGenerator.new()

# --- Regard hors combat (BOT-25, BotLook) -------------------------------
var _look := LOOK.new()
var _look_force_walk: bool = false            ## L6 : sortie de `_tick_look`, lue par `_tick_movement` pour `walk_held`.
## Mémoire du dernier ennemi suivi (BOT-03, BotMemory : position + vitesse +
## confiance qui décroît sur 6 s) — remplace les anciens champs bruts
## `_last_seen_enemy_pos`/`_last_seen_enemy_time` (BotLook L1 #1), alimentée
## par la perception DIRECTE de ce bot (`_tick_combat`, jamais un wall-hack)
## ET par les rapports d'équipe RETARDÉS de `PERCEPTION.latest_team_report`
## (voir `_physics_process`) — un bot se souvient maintenant aussi des
## ennemis repérés par ses coéquipiers, avec 0.5-1 s de délai.
var _enemy_memory := MEMORY.new()
var _map_knowledge_loaded: bool = false       ## Construction paresseuse (une fois par match, la carte ne change pas en cours de partie) de `_map_knowledge_cache`.
var _map_knowledge_cache: BotMapKnowledge = null

# --- Partage d'équipe retardé + réaction à un dégât reçu (BOT-03) -------
## Délai (s) avant qu'un rapport de CE bot à son équipe (`PERCEPTION.
## report_to_team`) devienne lisible par un coéquipier — tiré une fois par
## bot à `_ready()` (contrat : "0.5-1 s de délai"), jamais un délai unique
## pour toute l'équipe (varierait la "vitesse de radio" d'un bot à l'autre,
## plus organique qu'une constante).
var _team_share_delay_s: float = 0.75
## Compte à rebours (s) avant que ce bot ORIENTE sa vue vers son dernier
## attaquant connu (Health.damaged, hors combat SEULEMENT — voir
## `_on_health_damaged`) ; `< 0.0` = aucune réaction en attente.
var _damage_reaction_left_s: float = -1.0
var _damage_target_yaw_deg: float = 0.0
var _damage_target_pitch_deg: float = 0.0

# --- Anti-blocage (BOT-09, BotStuck) ------------------------------------
var _stuck := STUCK.new()
var _avoidance_safe_velocity: Vector3 = Vector3.ZERO
var _avoidance_has_velocity: bool = false     ## `false` tant qu'aucun `velocity_computed` n'est encore arrivé (premier(s) tick(s)) — la direction brute vers le prochain point de chemin sert alors de repli.

# --- Visée (BOT-26, BotAim v2 — offset qui dérive) ----------------------
## Magnitude COURANTE (deg) de l'erreur de visée — régénérée périodiquement
## par `_aim_towards` (jamais par frame), utilisée telle quelle par la
## condition de tir de `_tick_combat` (AIM.can_fire).
var _aim_error_deg: float = 0.0
## Offset FILTRÉ (deg, A2) réellement appliqué à la visée — court en
## permanence après `_aim_offset_target_*` via `AIM.offset_filter_step`
## (τ = 0.16 s), jamais un saut vers lui.
var _aim_offset_yaw_deg: float = 0.0
var _aim_offset_pitch_deg: float = 0.0
## Objectif d'offset (deg, A2/A3/A4) — retiré (gaussienne 2D anisotrope ×
## ratio de flick) à chaque régénération périodique ; `_aim_offset_*_deg`
## ci-dessus le POURSUIT sans jamais l'atteindre instantanément.
var _aim_offset_target_yaw_deg: float = 0.0
var _aim_offset_target_pitch_deg: float = 0.0
var _aim_regen_left: float = 0.0           ## Temps (s) avant la prochaine régénération de l'objectif d'offset.
var _aim_yaw_speed: float = 0.0            ## Vitesse angulaire courante (deg/s) du ressort-amortisseur — aussi lue comme "vue propre" par A9.
var _aim_pitch_speed: float = 0.0
var _prev_target_yaw_deg: float = 0.0      ## Pour mesurer la vitesse angulaire APPARENTE de la cible PERÇUE (position retardée, A5 ; pas celle du flick d'acquisition, voir _prev_target_valid).
var _prev_target_pitch_deg: float = 0.0
var _prev_target_valid: bool = false
## Historique des positions RÉELLES (A5, file de perception) de la cible
## COURANTE — `_aim_towards` y ajoute `target_pos` chaque tick où une cible
## est engagée et vise la position DÉCALÉE de `AIM.perception_delay_s`, pas
## la position vraie du tick courant. Vidé à chaque changement de cible.
var _target_history: Array = []
const TARGET_HISTORY_MAX_AGE := 0.4  ## s — au-delà du plus grand délai de perception (250 ms, Recrue) avec marge.

# --- Discipline de combat (BOT-04, BotCombatStyle) ----------------------
var _weapon_name: String = ""              ## Nom de l'arme équipée, mis en cache par `_tick_combat` (`STYLE.is_precision_weapon`).
var _weapon_category: int = -1             ## `WeaponConfig.Category` de l'arme équipée, -1 si aucune (`STYLE.preferred_distance_band`).
var _weapon_automatic: bool = true         ## `WeaponConfig.automatic` de l'arme équipée (`STYLE.should_burst`).
var _burst_state: Dictionary = {}          ## État PUR de la machine de rafale (`STYLE.burst_step`), {} = aucune rafale en cours.
var _semi_auto_cooldown: float = 0.0       ## Temps (s) avant le prochain appui semi-auto autorisé (`STYLE.semi_auto_interval`, BOT-21 A7).
var _ads_state: Dictionary = {}            ## État PUR de l'hystérésis ADS (`STYLE.ads_hold`), {} = première invocation sur la cible courante (BOT-21 A8).
var _last_damaged_time: float = -INF       ## Horloge `_now()` du dernier coup reçu — voir `_on_health_damaged`/`_is_targeted`.
var _health_signal_connected: bool = false ## Connexion à `Health.damaged` faite au plus tôt où le nœud est disponible (voir `_physics_process`).

# --- Munitions (BOT-04/GF-24, BotCombatStyle §MUNITIONS) -----------------
## Position d'un point de munitions (cartouchière/caisse) vers lequel faire
## un détour CE tick — `Vector3.INF` si aucun détour n'est retenu (lu par
## `_current_goal`, PRIORITAIRE sur le bruit entendu et l'objectif de mode).
var _ammo_target_pos: Vector3 = Vector3.INF

func _ready() -> void:
	process_physics_priority = -150
	player = get_parent() as PlayerController
	if player == null or not player.is_bot:
		set_physics_process(false)
		return
	_rng.randomize()
	_difficulty = MatchConfig.bot_difficulty
	_strafe_dir = 1 if _rng.randf() < 0.5 else -1
	# BOT-03 : délai de partage d'équipe propre à CE bot, tiré une fois (voir
	# la docstring de `_team_share_delay_s`).
	_team_share_delay_s = _rng.randf_range(0.5, 1.0)
	# BOT-21 (T3) : déphase le tout premier recalcul de chemin par bot — sinon
	# tous les bots (initialisés au même tick de spawn) recalculent au même
	# instant (`_repath_timer` par défaut à 0.0), un signe d'essaim synchronisé.
	_repath_timer = _rng.randf_range(0.0, REPATH_PHASE_MAX)
	nav_agent = NavigationAgent3D.new()
	nav_agent.name = "BotNavAgent"
	nav_agent.path_desired_distance = 0.8
	nav_agent.target_desired_distance = 0.8
	# BOT-09 : évitement RVO entre bots (écart #13, docs/research/02_bots_ai.md :
	# "avoidance_enabled = false, ... bots coincés les uns contre les autres").
	# La vitesse "sûre" revient plus tard via le signal `velocity_computed`
	# (Godot 4.7, "NavigationAgent Avoidance") — consommée dans `_tick_movement`.
	nav_agent.avoidance_enabled = true
	nav_agent.radius = AVOIDANCE_RADIUS
	nav_agent.velocity_computed.connect(_on_avoidance_velocity_computed)
	# ENFANT DIRECT du joueur (Node3D), PAS de BotBrain (un simple Node) :
	# NavigationAgent3D résout la position/carte de navigation depuis son
	# parent Node3D — parenté à un Node non-3D, il ne se lie à AUCUNE
	# NavigationMap (get_navigation_map() reste invalide indéfiniment).
	# `call_deferred` : ce _ready() s'exécute PENDANT que GameWorld ajoute le
	# joueur à l'arbre (add_child(player, true) traite ses enfants, dont
	# celui-ci) — un add_child SYNCHRONE sur `player` ici échoue ("Parent node
	# is busy setting up children").
	player.add_child.call_deferred(nav_agent)

func _physics_process(delta: float) -> void:
	if not multiplayer.is_server() or player == null:
		return
	var hp := player.get_node_or_null("Health") as Health
	# BOT-04/BOT-03 : connexion différée (le nœud "Health" peut ne pas encore
	# exister au premier tick, voir `_ready`) — `_on_health_damaged` mémorise
	# l'instant de chaque coup reçu pour `_is_targeted()` (BotCombatStyle.
	# strafe_interval) ET programme, hors combat, une réorientation vers
	# l'attaquant (voir sa docstring).
	if hp and not _health_signal_connected:
		hp.damaged.connect(_on_health_damaged)
		_health_signal_connected = true
	if hp and hp.is_dead:
		player.input.clear()
		_target_id = -1
		# BOT-03 : une réaction d'orientation programmée avant la mort ne doit
		# jamais s'appliquer après un respawn (attaquant d'une vie précédente).
		_damage_reaction_left_s = -1.0
		return

	var candidates := _visible_enemies()
	if candidates.is_empty():
		var heard: Variant = _hear_event()
		if heard != null:
			_heard_pos = heard
			_heard_until = _now() + HEAR_MEMORY
	else:
		_report_sightings(candidates)

	# BOT-03 : consomme le dernier rapport d'équipe déjà "arrivé" (délai
	# `_team_share_delay_s`) — fusionné dans la mémoire d'ennemi (`fuse`,
	# jamais une simple substitution), QUE ce bot voie ou non un ennemi
	# LUI-MÊME ce tick (un coéquipier peut avoir vu quelque chose que CE bot
	# ne voit pas).
	var shared := PERCEPTION.latest_team_report(int(player.team), _now(), _team_share_delay_s)
	if not shared.is_empty():
		_enemy_memory.observe(shared.pos, shared.get("vel", Vector3.ZERO), float(shared.time), _now())

	_tick_combat(delta, candidates)
	_tick_ammo(_target_id != -1)
	_tick_movement(delta)
	_tick_damage_orientation(delta)
	_tick_objective()

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0

## Partie EN LIGNE (vrai pair réseau) plutôt qu'en SOLO (entraînement, aucun
## pair — voir la docstring de `GameMode._is_authoritative` : par défaut
## `multiplayer.multiplayer_peer` est soit `null` soit un
## `OfflineMultiplayerPeer`, les DEUX cas d'une simulation locale sans humain
## distant) — utilisé par `_aim_towards` pour `PERCEPTION.
## network_perception_delay_s` (BOT-03, "0 en solo").
func _is_online_match() -> bool:
	var peer := multiplayer.multiplayer_peer
	return peer != null and not (peer is OfflineMultiplayerPeer)

## BOT-04/BOT-03 : callback de `Health.damaged` (serveur uniquement, voir sa
## docstring) — date le coup (pour `_is_targeted()`) ET, si CE bot n'a
## actuellement AUCUNE cible engagée (écart #6, docs/research/02_bots_ai.md
## §4 : "un bot touché DANS LE DOS continue sa route"), programme une
## réaction d'ORIENTATION vers l'attaquant (`_tick_damage_orientation`,
## ±20° d'erreur, BOT-03). Un bot DÉJÀ en combat garde sa vue pilotée par
## `_aim_towards` : se retourner sur un coup encaissé pendant un engagement
## déjà en cours l'en détournerait à tort.
func _on_health_damaged(_amount: float, attacker_id: int) -> void:
	_last_damaged_time = _now()
	if _target_id != -1 or player == null or player.head == null:
		return
	var attacker_pos := _attacker_position(attacker_id)
	if not attacker_pos.is_finite():
		return
	var head_pos: Vector3 = player.head.global_position
	var fwd: Vector3 = -player.global_transform.basis.z
	var to_attacker := attacker_pos - head_pos
	if fwd.length() < 0.001 or to_attacker.length() < 0.001:
		return
	var offset_deg := rad_to_deg(fwd.angle_to(to_attacker))
	var base := PERCEPTION.base_reaction_s(_difficulty)
	_damage_reaction_left_s = PERCEPTION.perception_reaction_time_s(_rng, base, offset_deg)
	var yp := LOOK.desired_yaw_pitch_deg(head_pos, attacker_pos)
	var err := PERCEPTION.orient_error_offset_deg(_rng)
	_damage_target_yaw_deg = float(yp.yaw) + err.x
	_damage_target_pitch_deg = clampf(float(yp.pitch) + err.y, -89.0, 89.0)

## Position MONDE de `attacker_id` au moment de l'appel — même lecture que
## `Health._source_position` (hors de ma liste de fichiers), dupliquée ici
## plutôt que d'appeler une méthode `_`-préfixée d'un fichier hors périmètre
## (même discipline que `_current_bot_look_map_id`/`_map_bot_knowledge_data`
## ci-dessous) : tous les joueurs (humains ET bots) vivent sous le MÊME
## conteneur "Players" (`player.get_parent()`), nommé par leur id. `Vector3.INF`
## si introuvable (attaquant déjà déconnecté/respawn, id d'environnement <= 0).
func _attacker_position(attacker_id: int) -> Vector3:
	if attacker_id <= 0 or player == null:
		return Vector3.INF
	var players_root := player.get_parent()
	if players_root == null:
		return Vector3.INF
	var attacker := players_root.get_node_or_null(str(attacker_id))
	return (attacker as Node3D).global_position if attacker is Node3D else Vector3.INF

## `true` si un coup a été reçu il y a moins de `STYLE.TARGETED_MEMORY_SECONDS`
## — "pris pour cible" (BotCombatStyle.strafe_interval, déclenche le strafe
## réactif rapide et suspend le plantage des armes de précision).
func _is_targeted() -> bool:
	return _now() - _last_damaged_time < STYLE.TARGETED_MEMORY_SECONDS

## Nettoyage du prototype 2026-09-26 : les modes à manches (SnD/Duel/Duo,
## RoundMode/RoundState) qui exposaient une propriété `round_phase` ont été
## supprimés — TDM (seul mode restant) n'a jamais de fin de manche, toujours
## faux désormais. Conservée (plutôt que d'inliner `false` à l'appelant) :
## fonction encore appelée depuis `_compute_bot_goal`/le patron
## "marche pendant la fin de manche", au cas où un futur mode à manches
## revienne.
func _round_ending() -> bool:
	return false

# ======================================================================
#  PERCEPTION — uniquement ce que le bot peut VOIR (raycast multi-points) ou
#  ENTENDRE (tirs/sprint/impacts, PERCEPTION.HEAR_*_RADIUS_M) : aucun accès
#  direct à la position/l'état d'un ennemi hors de ces deux canaux (pas de
#  wall-hack).
# ======================================================================
func _visible_enemies() -> Array:
	var world := get_tree().get_first_node_in_group("match")
	if world == null or player.head == null:
		return []
	if float(player.get_meta("blinded_until", 0.0)) > _now():
		return []  # ébloui : ne voit rien
	var out: Array = []
	var my_team := int(player.team)
	var head_pos: Vector3 = player.head.global_position
	var fwd: Vector3 = -player.global_transform.basis.z
	var space := player.get_world_3d().direct_space_state
	var my_rid := player.get_rid()
	for child in world.get_node(world.players_root).get_children():
		if child == player or int(child.get("team")) == my_team:
			continue
		var hp := child.get_node_or_null("Health") as Health
		if hp == null or hp.is_dead:
			continue
		var enemy_head: Node3D = child.get_node_or_null("Head")
		var target_pos: Vector3 = enemy_head.global_position if enemy_head else child.global_position
		var dist := head_pos.distance_to(target_pos)
		if dist > SIGHT_RANGE:
			continue
		var to_target := target_pos - head_pos
		if fwd.length() > 0.001 and to_target.length() > 0.001:
			if rad_to_deg(fwd.angle_to(to_target)) > SIGHT_FOV * 0.5:
				continue
		var enemy_ctrl := child as PlayerController
		# BOT-03 : LOS MULTI-POINTS (tête/torse/bassin, visible si >= 1 point
		# est dégagé) — `body_height` suit la capsule COURANTE (debout ou
		# accroupie, même discipline que WeaponMath.is_headshot), 1.8 m de
		# repli défensif (ne devrait pas arriver, `child` est toujours un
		# PlayerController réel dans scenes/player/player.tscn).
		var body_height: float = enemy_ctrl.current_height if enemy_ctrl else 1.8
		var points := PERCEPTION.los_points(child.global_position, target_pos, body_height)
		if not PERCEPTION.has_los_to_any_point(space, head_pos, points, my_rid, child):
			continue
		var enemy_vel: Vector3 = enemy_ctrl.velocity if enemy_ctrl else Vector3.ZERO
		out.append({"id": str(child.name).to_int(), "distance": dist, "pos": target_pos, "vel": enemy_vel})
	return out

## Meilleur (le plus proche/urgent) évènement sonore audible CE tick — impact
## proche (BOT-03, 5 m, le plus "urgent" : ça vient de tomber tout près),
## sinon un tir (40 m), sinon un sprint ennemi (15 m). `null` si rien entendu.
func _hear_event() -> Variant:
	var impact: Variant = _hear_impacts()
	if impact != null:
		return impact
	var gunfire: Variant = _hear_gunfire()
	if gunfire != null:
		return gunfire
	return _hear_enemy_sprint()

## Position d'un tir ENNEMI récent et proche (40 m, BOT-03), ou null si rien
## entendu (le bus statique Weapon.recent_gunfire n'est alimenté que côté
## serveur — voir Weapon._server_fire).
func _hear_gunfire() -> Variant:
	var now := _now()
	var my_team := int(player.team)
	var best: Variant = null
	var best_d := PERCEPTION.HEAR_GUNFIRE_RADIUS_M
	for shot in Weapon.recent_gunfire:
		if now - float(shot.time) > PERCEPTION.HEAR_EVENT_MEMORY_S or int(shot.team) == my_team:
			continue
		var d: float = player.global_position.distance_to(shot.pos)
		if d < best_d:
			best_d = d
			best = shot.pos
	return best

## Position d'un impact de balle ENNEMI récent et TRÈS proche (5 m, BOT-03,
## écart #9 : "un joueur qui sprinte derrière un bot n'est jamais entendu" —
## un impact près de soi non plus, jusqu'ici). Lit `Weapon.recent_impacts`
## (serveur uniquement, voir sa docstring).
func _hear_impacts() -> Variant:
	var now := _now()
	var my_team := int(player.team)
	var best: Variant = null
	var best_d := PERCEPTION.HEAR_IMPACT_RADIUS_M
	for impact in Weapon.recent_impacts:
		if now - float(impact.time) > PERCEPTION.HEAR_EVENT_MEMORY_S or int(impact.team) == my_team:
			continue
		var d: float = player.global_position.distance_to(impact.pos)
		if d < best_d:
			best_d = d
			best = impact.pos
	return best

## Position d'un ennemi qui SPRINTE à moins de 15 m (BOT-03) — omnidirectionnel
## (l'ouïe n'a pas de cône de vue), quelle que soit la LOS : c'est un BRUIT,
## pas un contact visuel. `speed_ratio` lu depuis `PlayerController.
## horizontal_speed()`/`config.sprint_speed`, PUBLICS sur tout joueur (humain
## ou bot), jamais une lecture d'état "caché".
func _hear_enemy_sprint() -> Variant:
	var world := get_tree().get_first_node_in_group("match")
	if world == null:
		return null
	var my_team := int(player.team)
	var my_pos := player.global_position
	var best: Variant = null
	var best_d := PERCEPTION.HEAR_SPRINT_RADIUS_M
	for child in world.get_node(world.players_root).get_children():
		if child == player or int(child.get("team")) == my_team:
			continue
		var hp := child.get_node_or_null("Health") as Health
		if hp == null or hp.is_dead:
			continue
		var enemy := child as PlayerController
		if enemy == null or enemy.config == null or enemy.config.sprint_speed <= 0.0:
			continue
		var ratio := enemy.horizontal_speed() / enemy.config.sprint_speed
		if not PERCEPTION.is_audible_sprint(ratio):
			continue
		var d := my_pos.distance_to(enemy.global_position)
		if d < best_d:
			best_d = d
			best = enemy.global_position
	return best

## Partage à l'ÉQUIPE les ennemis ACTUELLEMENT vus par CE bot — jamais un
## lookup direct de l'état serveur, seulement ce que `_visible_enemies()`
## (raycast + cône de vue, perception réelle) vient de retourner CE tick :
##  - `GameMode.report_enemy_sighting` (BOT-01, "dernière position connue
##    partagée par l'équipe") — INSTANTANÉ, pour les BUTS de patrouille
##    (hors de mon périmètre, inchangé) ;
##  - `PERCEPTION.report_to_team` (BOT-03) — RETARDÉ (0.5-1 s), pour la
##    MÉMOIRE de combat (`BotMemory`, position + vitesse + confiance),
##    consommé dans `_physics_process`.
func _report_sightings(candidates: Array) -> void:
	var mode := get_tree().get_first_node_in_group("game_mode")
	var now := _now()
	var team := int(player.team)
	for c in candidates:
		PERCEPTION.report_to_team(team, c.pos, c.get("vel", Vector3.ZERO), now)
		if mode != null and mode.has_method("report_enemy_sighting"):
			mode.report_enemy_sighting(team, c.pos)

# ======================================================================
#  COMBAT — acquisition + réaction + visée (erreur qui rétrécit en suivi).
# ======================================================================
func _tick_combat(delta: float, candidates: Array) -> void:
	# Cible "collante" : tant que la cible courante reste visible, on la
	# garde (sinon le choix "plus proche" oscille entre plusieurs ennemis à
	# distance similaire, remettant sans cesse à zéro le suivi/l'erreur de
	# visée — aucun tir n'a jamais le temps de faire baisser assez de vie
	# avant que la régénération ne compense). On ne réévalue que si la cible
	# courante n'est plus dans les candidats visibles.
	var current_still_visible := false
	for c in candidates:
		if int(c.id) == _target_id:
			current_still_visible = true
			break
	var chosen_id: int = _target_id if current_still_visible else TARGET_SELECT.choose(candidates)
	if chosen_id != _target_id:
		var had_target := _target_id != -1
		_target_id = chosen_id
		_tracking_time = 0.0
		_target_history.clear()  # A5 : une NOUVELLE cible n'hérite pas de la trajectoire perçue de l'ancienne.
		# BOT-26 (A6) : loi ex-gaussienne + pénalité hors-centre (cible à plus de
		# 35° du regard courant à l'acquisition) + délai d'ouverture du feu
		# UNIQUEMENT au premier engagement depuis le repos (`not had_target`,
		# jamais à une réacquisition interne pendant un combat déjà entamé — même
		# distinction que `_ads_state` ci-dessous).
		if chosen_id != -1:
			var acquire_offset_deg := _target_offset_from_center_deg(candidates, chosen_id)
			_reaction_left = REACTION.reaction_time(_difficulty, _rng, acquire_offset_deg, not had_target)
		else:
			_reaction_left = 0.0
		_aim_regen_left = 0.0      # force une régénération immédiate de l'erreur sur la NOUVELLE cible.
		_prev_target_valid = false # le flick d'acquisition n'est PAS un déplacement de la cible.
		_semi_auto_cooldown = 0.0 # BOT-21 (A7) : un nouvel engagement peut tirer dès que la réaction/visée le permettent.
		# BOT-21 (B7 fix, 2026-09-24) : l'hystérésis ADS (`_ads_state`) ne repart
		# à neuf QUE quand le bot ENTRE en combat depuis le repos (`not
		# had_target`) ou en SORT entièrement (`chosen_id == -1`) — jamais à
		# chaque réacquisition d'une AUTRE cible pendant un même combat continu
		# (`_target_id` passe d'un ennemi encore visible à un autre sans jamais
		# retomber à -1, ex. le premier meurt/casse la ligne de vue pendant
		# qu'un second reste visible). La remettre à `{}` À CHAQUE changement de
		# cible (ancien code) réinitialisait aussi `since_toggle` à
		# `ADS_MIN_TOGGLE_INTERVAL` ("délai déjà écoulé"), ce qui autorisait une
		# bascule immédiate hors de toute règle de délai à CHAQUE réacquisition
		# interne — mesuré en vif par le banc (tools/bot_bench.gd, hp_veteran/
		# tdm_veteran Wasteland, 2026-09-24) comme p99 = 3 bascules/engagement
		# (seuil 2.0) et 4,3 % des engagements rebasculant en < 1,5 s (seuil
		# 0 %) : le banc définit un "engagement" comme un segment continu
		# `in_combat == true`, exactement ce que cette condition préserve
		# maintenant intact au travers des réacquisitions internes. Reproduit et
		# vérifié CORRIGÉ (2026-09-25, même commande --map=wasteland
		# --phases=hp_veteran, 180 s) : p99 3.0 -> 1.0, rebasculements rapides
		# 4,3 % -> 0,0 % ; plus aucun avertissement B7.
		if not had_target or chosen_id == -1:
			_ads_state = {}

	if _target_id == -1:
		player.input.fire_held = false
		player.input.fire_pressed = false
		player.input.aim_held = false
		_target_pos = Vector3.INF
		return

	_tracking_time += delta
	_reaction_left = maxf(_reaction_left - delta, 0.0)

	var target_pos: Vector3 = player.global_position
	var target_distance: float = SIGHT_RANGE
	var target_vel: Vector3 = Vector3.ZERO
	for c in candidates:
		if int(c.id) == _target_id:
			target_pos = c.pos
			target_distance = float(c.distance)
			target_vel = c.get("vel", Vector3.ZERO)
			break
	_target_pos = target_pos
	# BOT-03/BOT-25 (BotLook, L1 #1 "dernière position ennemie connue") :
	# mémorisé UNIQUEMENT quand cette cible est RÉELLEMENT visible ce tick
	# (jamais une position reçue de l'équipe via `_report_sightings` ICI —
	# pas de wall-hack ; les rapports d'équipe RETARDÉS sont fusionnés à
	# part, voir `_physics_process`). `BotMemory.observe` FUSIONNE (jamais
	# n'écrase) avec ce qu'un rapport d'équipe aurait déjà déposé.
	_enemy_memory.observe(target_pos, target_vel, _now(), _now())

	# BOT-26 (A9 règle 2) : calculé AVANT `_aim_towards` (qui en a besoin pour
	# la dégradation de précision en mouvement) et réutilisé ci-dessous pour
	# `speed_allows_fire` — UNE seule lecture de la vitesse par tick.
	var sprint_speed := player.config.sprint_speed if player.config else AVOIDANCE_REF_SPEED_FALLBACK
	var speed_ratio := (player.horizontal_speed() / sprint_speed) if sprint_speed > 0.0 else 0.0

	_aim_towards(target_pos, delta, speed_ratio)

	# Condition de tir (BOT-02) : l'erreur COURANTE (magnitude régénérée
	# périodiquement par `_aim_towards`, jamais recalculée ici) doit passer
	# sous la demi-largeur angulaire du point visé (tête, ou torse au-delà de
	# AIM.TORSO_AIM_DISTANCE sauf Élite) PLUS la dispersion de l'arme
	# équipée — jamais "dès que la réaction est écoulée" comme avant.
	var would_aim_down_sights := _difficulty != MatchConfig.Difficulty.RECRUE
	var weapon := player.get_node_or_null("Weapon") as Weapon
	var wcfg: WeaponConfig = weapon.cfg() if weapon else null
	var weapon_spread_deg := WEAPON_SPREAD_FALLBACK_DEG
	if wcfg:
		weapon_spread_deg = wcfg.spread_aim if would_aim_down_sights else wcfg.spread_hip
	var hitbox_half_width_deg := AIM.hitbox_half_width_deg(AIM.targeted_half_width_m(_difficulty, target_distance), target_distance)
	var aim_ready := AIM.can_fire(_aim_error_deg, hitbox_half_width_deg, weapon_spread_deg)

	# BOT-04 (BotCombatStyle) : catégorie/nom de l'arme équipée, mis en cache
	# pour `_tick_movement` (plantage avant tir des armes de précision,
	# distance préférée par catégorie) — LA MÊME config que `weapon_spread_deg`
	# ci-dessus, jamais relue séparément.
	_weapon_name = wcfg.weapon_name if wcfg else ""
	_weapon_category = wcfg.category if wcfg else -1
	_weapon_automatic = wcfg.automatic if wcfg else true

	# Armes de précision (Marqueur/Percuteur/Faucheur) : tir refusé tant que la
	# vitesse dépasse 30 % du sprint. `_tick_movement` tente de PLANTER le bot
	# (aucun strafe) pour que cette condition finisse par être vraie, mais le
	# tir reste gaté ICI indépendamment de la cause du mouvement résiduel
	# (repli forcé, poussée d'un allié, etc.).
	var speed_allows_fire := STYLE.can_fire_at_speed(_weapon_name, speed_ratio)

	var base_can_shoot := _reaction_left <= 0.0 and aim_ready and speed_allows_fire
	var can_fire_now := base_can_shoot
	# Rafale (BOT-04) : armes automatiques au-delà de BURST_RANGE_M — 3-5
	# "tirs" (temps tenu × cadence, voir BotCombatStyle.burst_step) puis une
	# pause de 150-250 ms, jamais gâchette maintenue en continu à distance.
	if base_can_shoot and STYLE.should_burst(_weapon_automatic, target_distance):
		_burst_state = STYLE.burst_step(_burst_state, delta, wcfg.fire_rate if wcfg else 0.0, _rng)
		can_fire_now = bool(_burst_state.get("can_fire", false))
	else:
		_burst_state = {}

	# ADS avec hystérésis (BOT-21, A8) : `base_can_shoot and would_aim_down_sights`
	# n'est plus posé TEL QUEL sur `aim_held` (l'ADS clignotait au moindre
	# franchissement du seuil de visée) — `STYLE.ads_hold` lisse ce signal brut
	# en un maintien d'au moins 0,5-0,9 s après la dernière fois qu'il était
	# vrai, avec au plus 1 bascule par 1,5 s.
	var wants_ads := base_can_shoot and would_aim_down_sights
	_ads_state = STYLE.ads_hold(_ads_state, delta, wants_ads, _rng)
	player.input.aim_held = bool(_ads_state.get("held", false))

	if _weapon_automatic:
		player.input.fire_held = can_fire_now
		player.input.fire_pressed = can_fire_now
	else:
		# Semi-auto (BOT-21, A7) : un appui = un front montant, jamais
		# `fire_pressed` vrai en continu (métronome à cadence max) — le
		# prochain appui n'est autorisé qu'après `STYLE.semi_auto_interval`
		# (selon la distance, plafonné par la cadence de l'arme équipée).
		_semi_auto_cooldown = maxf(_semi_auto_cooldown - delta, 0.0)
		var pressed := base_can_shoot and _semi_auto_cooldown <= 0.0
		if pressed:
			_semi_auto_cooldown = STYLE.semi_auto_interval(target_distance, _rng, wcfg.fire_rate if wcfg else 0.0)
		player.input.fire_held = pressed
		player.input.fire_pressed = pressed

## Visée EN combat (BOT-26, BotAim v2) : la position PERÇUE de la cible (file
## de perception retardée de `AIM.perception_delay_s`, A5 — jamais sa
## position vraie du tick courant) fixe la direction exacte ; un objectif
## d'offset (gaussienne 2D anisotrope × ratio de flick, A3/A4) est retiré
## PÉRIODIQUEMENT (jamais par frame, `_aim_regen_left`/`AIM.next_regen_interval`,
## intervalle propre à la difficulté, A2) et l'offset RÉELLEMENT appliqué le
## POURSUIT en permanence via un filtre du 1er ordre (`AIM.offset_filter_step`,
## τ = 0.16 s — jamais un saut) ; la tête/le corps du bot tournent ensuite
## vers ce point via un ressort-amortisseur critique plafonné en accélération
## (`AIM.spring_step`, A1/A4 : plus de dépassement fixe).
func _aim_towards(target_pos: Vector3, delta: float, speed_ratio: float) -> void:
	var head_pos: Vector3 = player.head.global_position
	var now := _now()

	# A5 : file de perception — le bot vise la cible telle qu'elle était il y
	# a `perception_delay_s` + le délai de perception RÉSEAU (BOT-03, 60 ms
	# en ligne / 0 en solo — voir la docstring de
	# `PERCEPTION.network_perception_delay_s` et celle de `AIM.
	# perception_delay_s` §A5 : "Le +60 ms « en ligne » n'est pas géré ici,
	# hors de mon périmètre"), pas sa position vraie de CE tick.
	_target_history.append({"time": now, "pos": target_pos})
	while _target_history.size() > 1 and now - float(_target_history[0].time) > TARGET_HISTORY_MAX_AGE:
		_target_history.pop_front()
	var delay_s := AIM.perception_delay_s(_difficulty) + PERCEPTION.network_perception_delay_s(_is_online_match())
	var perceived_pos: Vector3 = AIM.delayed_position(_target_history, now, delay_s, target_pos)

	var to_target := perceived_pos - head_pos
	if to_target.length() < 0.01:
		return

	var desired_yaw_deg := rad_to_deg(atan2(-to_target.x, -to_target.z))
	var flat := Vector2(to_target.x, to_target.z).length()
	var desired_pitch_deg := rad_to_deg(clampf(atan2(to_target.y, maxf(flat, 0.001)), deg_to_rad(-89), deg_to_rad(89)))

	# Vitesse angulaire APPARENTE de la cible PERÇUE (deg/s) — mesurée d'un
	# tick à l'autre sur la direction VERS la position retardée (jamais sur le
	# flick du bot pour l'atteindre, voir la remise à zéro de
	# `_prev_target_valid` à l'acquisition, dans `_tick_combat`).
	var target_angular_speed_deg := 0.0
	if _prev_target_valid and delta > 0.0001:
		var dyaw := wrapf(desired_yaw_deg - _prev_target_yaw_deg, -180.0, 180.0)
		var dpitch := desired_pitch_deg - _prev_target_pitch_deg
		target_angular_speed_deg = sqrt(dyaw * dyaw + dpitch * dpitch) / delta
	_prev_target_yaw_deg = desired_yaw_deg
	_prev_target_pitch_deg = desired_pitch_deg
	_prev_target_valid = true

	_aim_regen_left -= delta
	if _aim_regen_left <= 0.0:
		_aim_regen_left = AIM.next_regen_interval(_rng, _difficulty)
		# A9 : la "vue propre" du bot est la vitesse angulaire COURANTE du
		# ressort (avant ce pas) — un flick qui vient de se produire dégrade la
		# précision qui suit. Aussi utilisée comme axe du "dernier flick" (A3) :
		# l'erreur s'étire dans la direction où le regard vient de bouger.
		var own_view_speed_deg := sqrt(_aim_yaw_speed * _aim_yaw_speed + _aim_pitch_speed * _aim_pitch_speed)
		_aim_error_deg = AIM.current_error_deg(_difficulty, _tracking_time, target_angular_speed_deg, own_view_speed_deg, speed_ratio)
		var axis_angle_deg := 0.0
		if own_view_speed_deg > 5.0:  # sous ce seuil, l'axe du dernier flick n'est pas défini de façon fiable : erreur isotrope par défaut.
			axis_angle_deg = rad_to_deg(atan2(_aim_pitch_speed, _aim_yaw_speed))
		var ratio := AIM.flick_ratio(_rng)
		var offset2d: Vector2 = AIM.sample_anisotropic_offset(_aim_error_deg, axis_angle_deg, _rng) * ratio
		_aim_offset_target_yaw_deg = offset2d.x
		_aim_offset_target_pitch_deg = offset2d.y

	# A2 : l'offset RÉELLEMENT appliqué ne saute JAMAIS vers son objectif —
	# il le poursuit d'un pas de filtre du 1er ordre CHAQUE tick, régénération
	# ou non.
	_aim_offset_yaw_deg = AIM.offset_filter_step(_aim_offset_yaw_deg, _aim_offset_target_yaw_deg, delta)
	_aim_offset_pitch_deg = AIM.offset_filter_step(_aim_offset_pitch_deg, _aim_offset_target_pitch_deg, delta)

	var target_yaw_deg := desired_yaw_deg + _aim_offset_yaw_deg
	var target_pitch_deg := desired_pitch_deg + _aim_offset_pitch_deg

	var params := AIM.spring_params(_difficulty)
	var max_accel_deg := AIM.angular_accel_cap_deg(_difficulty)
	var cur_yaw_deg := rad_to_deg(player.rotation.y)
	# Ramène la cible dans la fenêtre continue la plus proche de l'angle
	# courant AVANT d'intégrer le ressort — sinon un passage par ±180°
	# provoquerait un demi-tour au lieu du plus court chemin.
	var wrapped_target_yaw_deg := cur_yaw_deg + wrapf(target_yaw_deg - cur_yaw_deg, -180.0, 180.0)
	var yaw_step: Dictionary = AIM.spring_step(cur_yaw_deg, _aim_yaw_speed, wrapped_target_yaw_deg, params.k, params.d, delta, max_accel_deg)
	var cur_pitch_deg := rad_to_deg(player.head.rotation.x)
	var pitch_step: Dictionary = AIM.spring_step(cur_pitch_deg, _aim_pitch_speed, target_pitch_deg, params.k, params.d, delta, max_accel_deg)
	_aim_yaw_speed = yaw_step.speed
	_aim_pitch_speed = pitch_step.speed

	var dy := deg_to_rad(float(yaw_step.angle) - cur_yaw_deg)
	var dp := deg_to_rad(float(pitch_step.angle) - cur_pitch_deg)
	# `_apply_bot_look` applique `rotate_y(-look_delta.x)` / `head.rotate_x(-look_delta.y)`
	# (même convention que la souris humaine, voir PlayerController._look) :
	# les DEUX composantes doivent donc être négées ici pour que rotation.y et
	# head.rotation.x avancent bien de +dy / +dp vers la cible.
	player.input.look_delta = Vector2(-dy, -dp)

## Angle (deg) entre le regard COURANT du bot et la direction vers
## `target_id` dans `candidates`, au moment de l'ACQUISITION — utilisé par
## BOT-26 (A6) pour la pénalité "cible à plus de 35° du centre". Même calcul
## d'angle que le cône de vue de `_visible_enemies`, mais sur la cible
## CHOISIE plutôt qu'un simple test de seuil. `0.0` si l'un des vecteurs est
## dégénéré (bot ou cible au même point que la tête, ne devrait pas arriver
## pour une cible visible) — pas de pénalité plutôt qu'une valeur aberrante.
func _target_offset_from_center_deg(candidates: Array, target_id: int) -> float:
	if player.head == null:
		return 0.0
	var head_pos: Vector3 = player.head.global_position
	var fwd: Vector3 = -player.global_transform.basis.z
	for c in candidates:
		if int(c.id) == target_id:
			var to_target: Vector3 = (c.pos as Vector3) - head_pos
			if fwd.length() < 0.001 or to_target.length() < 0.001:
				return 0.0
			return rad_to_deg(fwd.angle_to(to_target))
	return 0.0

# ======================================================================
#  MUNITIONS (BOT-04/GF-24, BotCombatStyle §MUNITIONS, docs/research/
#  10_ammo_kits_input.md §2.7) — recharge hors combat sous 40 %, passage au
#  pistolet à sec, détour vers une cartouchière/caisse à <= 12 m. Tout passe
#  par `player.input.reload_pressed`/`weapon_slot_pressed`, EXACTEMENT comme
#  pour un humain (Weapon._owner_tick/_handle_switch_input) : aucun accès
#  direct à Weapon._inv ni RPC dédié.
# ======================================================================
func _tick_ammo(in_combat: bool) -> void:
	_ammo_target_pos = Vector3.INF
	player.input.reload_pressed = false
	player.input.weapon_slot_pressed = -1

	var weapon := player.get_node_or_null("Weapon") as Weapon
	if weapon == null:
		return
	var mags: Array = weapon.mag
	var reserves: Array = weapon.reserve_a
	var slot := weapon.current
	if slot < 0 or slot >= mags.size() or slot >= reserves.size():
		return
	var mag: int = int(mags[slot])
	var reserve: int = int(reserves[slot])
	var wcfg := weapon.cfg()
	var mag_size: int = wcfg.mag_size if wcfg else 0
	var weapon_name := wcfg.weapon_name if wcfg else ""

	player.input.reload_pressed = STYLE.should_self_reload(in_combat, mag, mag_size, reserve)

	var pistol_slot := _pistol_slot(weapon, slot)
	if STYLE.should_switch_to_pistol(weapon_name, mag, reserve, pistol_slot != -1):
		player.input.weapon_slot_pressed = pistol_slot

	if STYLE.wants_ammo_detour(in_combat, reserve, mag_size):
		_ammo_target_pos = STYLE.nearest_ammo_point(player.global_position, _ammo_pack_positions())

## Emplacement (0/1) d'un pistolet AUTRE que `exclude_slot`, -1 si aucun —
## lu depuis `Weapon.weapons` (vue de compatibilité, WeaponConfig par
## emplacement) plutôt qu'un index de slot fixe : le pistolet du loadout par
## défaut (slot 1, WeaponDatabase.default_loadout_ids) peut avoir été
## remplacé en boutique (`_maybe_buy`/un achat humain donne l'arme au slot
## COURANT s'il n'y a plus de slot libre, voir Inventory.give).
func _pistol_slot(weapon: Weapon, exclude_slot: int) -> int:
	var configs: Array = weapon.weapons
	for i in configs.size():
		if i == exclude_slot:
			continue
		var c: WeaponConfig = configs[i]
		if c and c.weapon_name == STYLE.PISTOL_WEAPON_NAME:
			return i
	return -1

## Positions des cartouchières encore vivantes (GF-22, AmmoPack.gd) — lues
## depuis son registre statique uid -> instance (même bus que la lecture de
## `Weapon.recent_gunfire` pour l'audition : une source déjà exposée par un
## AUTRE système, jamais réécrite ici, hors de ma liste de fichiers). Les
## caisses du Comptoir (GF-25, AmmoCrate.gd) n'existent pas encore : rien à
## lire de leur côté tant que ce fichier n'existe pas.
func _ammo_pack_positions() -> Array:
	var out: Array = []
	for pack in AmmoPack._registry.values():
		if pack and is_instance_valid(pack):
			out.append((pack as Node3D).global_position)
	return out

## Regard HORS COMBAT (BOT-25, BotLook, remplace `_face_direction`/
## `_idle_pitch_correction` de BOT-21 — L1-L6, absorbe BOTFIX-01) : attention
## dirigée (mémoire ennemie/ouïe, angles K, pré-visée des coins, balayage une
## fois le but atteint), tangage vers un point réel plutôt qu'un simple retour
## à l'horizon, ressort plafonné en vitesse/accélération. `move_world_dir`
## sert de repli (« point du chemin 4 m devant ») ET de cap pour L6 (marche
## si le regard s'en écarte de plus de 70°) — sans lui, le cône de vue
## resterait figé à l'orientation du spawn et le bot ne détecterait jamais
## personne (même besoin que l'ancien `_face_direction`).
func _tick_look(delta: float, move_world_dir: Vector3, has_active_path: bool) -> void:
	if player.head == null:
		_look_force_walk = false
		return
	var ctx := {
		"bot_pos": player.global_position,
		"eye_pos": player.head.global_position,
		"cur_yaw_deg": rad_to_deg(player.rotation.y),
		"cur_pitch_deg": rad_to_deg(player.head.rotation.x),
		"move_dir": move_world_dir,
		"path_points": _upcoming_path_points(),
		# BOT-03 : `BotMemory` remplace les anciens champs bruts
		# `_last_seen_enemy_pos`/`_last_seen_enemy_time` — même fenêtre de 6 s
		# que `LOOK.ENEMY_MEMORY_S` (voir la docstring de
		# `BotMemory.CONFIDENCE_DECAY_S`), désormais alimentée aussi par les
		# rapports d'équipe RETARDÉS (pas seulement la perception directe de
		# CE bot).
		"has_enemy_memory": _enemy_memory.has_memory(_now()),
		"enemy_pos": _enemy_memory.predicted_position(_now()),
		"has_heard": _now() < _heard_until,
		"heard_pos": _heard_pos,
		"map_knowledge": _map_knowledge(),
		# Rôles de tenue (perchoir/surveillance, BOT-24/27) pas encore
		# assignés à ce stade : repli sur "le bot est arrivé et ne navigue
		# plus" comme approximation de "tenue d'angle" (L1) — à affiner
		# quand un rôle explicite atteindra BotBrain (hors de mon périmètre :
		# BotMapKnowledge n'expose pas encore les perchoirs eux-mêmes).
		"holding_angle": not has_active_path,
		"goal_reached": not has_active_path,
		"rng": _rng,
	}
	var result := _look.tick(delta, ctx)
	player.input.look_delta = result.look_delta
	_look_force_walk = bool(result.force_walk)

## Points de chemin à venir (MONDE, sans la position actuelle du bot) pour
## `BotLook` (pré-visée des coins L2, repli "point du chemin 4 m devant" L1) —
## lu depuis le MÊME `NavigationAgent3D` que `_tick_movement`, jamais un
## second calcul de chemin.
func _upcoming_path_points() -> Array:
	if nav_agent == null:
		return []
	var raw: PackedVector3Array = nav_agent.get_current_navigation_path()
	var out: Array = []
	for i in range(raw.size()):
		var p: Vector3 = raw[i]
		if i == 0 and player.global_position.distance_to(p) < 0.1:
			continue  # premier point = position courante de l'agent : pas un point "à venir".
		out.append(p)
		if out.size() >= 6:
			break
	return out

## Connaissance de carte (BOT-22/22B, BotMapKnowledge) pour `BotLook` (angles K,
## balayage L5) — construite UNE fois par bot (la carte ne change pas en cours
## de match) depuis la source PURE et PUBLIQUE de la carte courante
## (`WastelandBots.data()`), jamais une méthode `_`-préfixée de `GameMode`
## (même discipline que `GameHUD._acquire_map_setup`, voir GameMode.gd
## `_current_map_id`/`_bot_knowledge` : dupliquer la lecture d'un champ/source
## PUBLIC plutôt que d'appeler du `_`-préfixé hors de mon périmètre). `null`
## pour toute carte qui n'expose pas encore ces données.
func _map_knowledge() -> BotMapKnowledge:
	if not _map_knowledge_loaded:
		_map_knowledge_loaded = true
		var data := _map_bot_knowledge_data()
		_map_knowledge_cache = BotMapKnowledge.new(data) if not data.is_empty() else null
	return _map_knowledge_cache

## Nettoyage du prototype 2026-09-26 : plus aucune carte n'expose de données
## de connaissance de carte (voir GameMode._bot_knowledge) — `null`
## inconditionnel, `BotLook` retombe sur ses replis génériques (L1..).
func _map_bot_knowledge_data() -> Dictionary:
	return {}

## Identifiant de la carte courante — même lecture que `GameMode._current_map_id`
## (champ PUBLIC `map_id` du `MapSetup` parent du mode), dupliquée ici plutôt
## que d'appeler la méthode `_`-préfixée de GameMode.gd (hors de ma liste de
## fichiers). `""` si aucun mode/`MapSetup` trouvé (ex. tests qui ajoutent le
## mode ailleurs).
func _current_bot_look_map_id() -> String:
	var mode := get_tree().get_first_node_in_group("game_mode")
	if mode == null:
		return ""
	var parent := mode.get_parent()
	if parent != null and "map_id" in parent:
		return String(parent.get("map_id"))
	return ""

# ======================================================================
#  MOUVEMENT — navmesh vers l'objectif du mode (ou le dernier bruit entendu),
#  évitement RVO entre bots, strafe en combat (projeté sur la navmesh),
#  anti-blocage (BotStuck, SEULE source de saut — BOT-21, M1).
# ======================================================================
func _tick_movement(delta: float) -> void:
	# En combat, l'objectif de déplacement devient la cible engagée elle-même
	# (se rapprocher/contourner) — sinon le bot continue de naviguer vers
	# l'objectif du MODE (souvent un ennemi DIFFÉRENT côté TDM), et peut
	# s'éloigner de la cible qu'il est justement en train de canarder. SAUF
	# pour un bot qui tient une position (`chases_combat_target`, Hardpoint
	# T5) : il se bat DEPUIS son point (strafe local ci-dessous) au lieu de
	# quitter la zone pour poursuivre sa cible.
	var holds := _mode_holds_position()
	var engaged := _target_id != -1 and _target_pos != Vector3.INF
	var goal := _target_pos if chases_combat_target(engaged, holds) else _current_goal(holds)
	_repath_timer -= delta
	if _repath_timer <= 0.0 and nav_agent:
		_repath_timer = REPATH_INTERVAL
		nav_agent.target_position = goal

	var nav_map: RID = nav_agent.get_navigation_map() if nav_agent else RID()
	var has_active_path := nav_agent != null and nav_map.is_valid() \
			and NavigationServer3D.map_get_iteration_id(nav_map) != 0 \
			and not nav_agent.is_navigation_finished()

	var move := Vector2.ZERO
	var move_world_dir := Vector3.ZERO
	if has_active_path:
		var next_pos := nav_agent.get_next_path_position()
		var dir := next_pos - player.global_position
		dir.y = 0.0
		move_world_dir = dir
		# BOT-09 : évitement RVO — `dir` (direction brute vers le prochain
		# point de chemin) est soumis au NavigationServer3D pour être dévié
		# des AUTRES bots enregistrés sur la même carte ; la vitesse "sûre"
		# revient via `velocity_computed` (consommée au tick suivant,
		# `_avoidance_safe_velocity` — décalage d'une frame inhérent à l'API
		# Godot, sans conséquence à 60 Hz).
		if nav_agent.avoidance_enabled:
			var ref_speed := player.config.sprint_speed if player.config else AVOIDANCE_REF_SPEED_FALLBACK
			var desired_velocity := Vector3.ZERO
			if dir.length() > 0.05:
				desired_velocity = dir.normalized() * ref_speed
			nav_agent.set_velocity(desired_velocity)
			if _avoidance_has_velocity and _avoidance_safe_velocity.length() > 0.05:
				move_world_dir = _avoidance_safe_velocity
		move = _world_dir_to_local_move(move_world_dir)

	var in_combat := _target_id != -1
	if not in_combat:
		# Regarde où il marche (BOT-25, BotLook) : sans ça le cône de vue
		# reste figé à l'orientation du spawn et le bot ne détecte jamais
		# personne.
		_tick_look(delta, move_world_dir, has_active_path)
	else:
		_look_force_walk = false
	if in_combat:
		var target_distance := player.global_position.distance_to(_target_pos) if _target_pos != Vector3.INF else SIGHT_RANGE
		var is_precision := STYLE.is_precision_weapon(_weapon_name)
		var targeted := _is_targeted()
		# BOT-04 : une arme de précision déjà à sa distance préférée, et PAS
		# sous le feu (`targeted`), se PLANTE (aucun strafe, aucune correction
		# de distance) pour repasser sous le seuil de vitesse exigé par
		# `_tick_combat` avant de tirer — elle recommence à strafer dès
		# qu'elle encaisse un coup (survie avant précision).
		var plant := is_precision and not targeted and STYLE.in_preferred_band(_weapon_category, target_distance)
		if plant:
			move = Vector2.ZERO
		else:
			_strafe_timer -= delta
			if _strafe_timer <= 0.0:
				_strafe_timer = STYLE.strafe_interval(_rng, targeted)
				_strafe_dir = -_strafe_dir
			move.x = clampf(move.x + float(_strafe_dir) * 0.8, -1.0, 1.0)
			# Distance préférée par catégorie d'arme (BOT-04, écart #11,
			# docs/research/02_bots_ai.md : "un pompe tente d'engager un
			# sniper à 40 m") : recule si la cible est trop proche pour la
			# catégorie équipée, avance si elle est trop loin.
			if STYLE.should_retreat(_weapon_category, target_distance):
				move.y = clampf(move.y + 0.6, -1.0, 1.0)
			elif STYLE.should_advance(_weapon_category, target_distance):
				move.y = clampf(move.y - 0.6, -1.0, 1.0)
		# BOT-09 : le déplacement de STRAFE est projeté sur la navmesh
		# (map_get_closest_point) AVANT d'être appliqué — jamais suivi
		# aveuglément hors de la surface navigable (écart #11, docs/research/
		# 02_bots_ai.md : "un strafe latéral... qui pousse hors du chemin").
		move = _project_combat_move_to_navmesh(move, nav_map)

	# Anti-blocage (BOT-09, BotStuck) : vitesse moyenne < 0.5 m/s sur 1 s avec
	# chemin actif -> wiggle 0.3 s, puis saut, puis repath vers un point
	# intermédiaire alternatif. Prioritaire sur le déplacement normal calculé
	# ci-dessus : un bot bloqué ne doit pas continuer à pousser dans le même
	# obstacle en même temps qu'il essaie de s'en dégager.
	var stuck_state := _stuck.update(delta, player.global_position, has_active_path)
	if stuck_state.move_override != null:
		move = stuck_state.move_override as Vector2
	if bool(stuck_state.request_repath) and nav_agent:
		var alt := _stuck.alternate_repath_point(player.global_position, move_world_dir, nav_map)
		nav_agent.target_position = alt
		# Laisse le point alternatif en place le temps d'y arriver, sinon le
		# repath périodique ci-dessus (toutes les REPATH_INTERVAL) l'écrase
		# avant que le bot ait pu s'en approcher.
		_repath_timer = STUCK.ALT_TARGET_HOLD_SECONDS

	player.input.move = move
	# BOT-04 : marche (walk_held) en ENQUÊTE (bruit récent en mémoire, pas de
	# cible visible) ou en FIN DE ROUND (approche furtive — Booth, docs/
	# research/02_bots_ai.md : "sneaking") ; sprint dans tous les autres cas,
	# combat compris (inchangé). Un bot qui tient une position n'enquête pas
	# (`hearing_diverts_goal`) : il rejoint son point au pas de course.
	var investigating := not in_combat and hearing_diverts_goal(_now() < _heard_until, holds)
	# BOT-25 (BotLook, L6) : marche aussi quand le regard s'écarte de plus de
	# 70° du cap de déplacement (jamais de sprint à reculons) — un signal EN
	# PLUS de l'enquête/fin de round de BOT-21, jamais à leur place.
	player.input.walk_held = STYLE.should_walk(investigating, _round_ending()) or _look_force_walk

	# BOT-21 (M1, écart #2 de 08_bots_humanlike.md : "sauts/accroupis au hasard
	# toutes les 3-7 s, même à l'arrêt", perçu comme du teabag) : plus AUCUN
	# tirage aléatoire de saut/accroupi/plongeon, en combat ou hors combat. Le
	# SEUL saut restant vient de l'anti-blocage (BotStuck, ci-dessus) — jamais
	# de `crouch_pressed` (le contrat l'interdit explicitement sous 1 m/s hors
	# combat ; aucune autre raison de s'accroupir n'existe encore, voir
	# BOT-25/BOT-27 pour la couverture/tir de précision à venir).
	if bool(stuck_state.jump_pressed):
		player.input.jump_pressed = true
		player.input.jump_held = true
	else:
		player.input.jump_pressed = false
		player.input.jump_held = false
	player.input.crouch_pressed = false
	player.input.crouch_held = false
	player.input.dive_pressed = false
	# NOTE (BOT-21, 3e passage, statut vérifié au 2026-09-25 par QA indépendant) :
	# ce fichier n'a AUCUNE autre source de jump_pressed/crouch_pressed que
	# `stuck_state` ci-dessus (grep "jump_pressed\|crouch_pressed" sur ce
	# fichier : uniquement les lignes 585-593) — confirmé par relecture
	# complète, pas seulement par grep. L'hypothèse "sauts de NavigationLink" du
	# contrat ne tient pas : zéro NavigationLink3D dans tout le dépôt (grep -r
	# "NavigationLink" scripts/ scenes/ tools/, aucun résultat) — Wasteland n'en
	# a aucun.
	# tools/bot_bench.gd (BOT-20) mesure B14 en vif : sur 2 runs réels
	# indépendants (hp_veteran + tdm_veteran, Wasteland, 2026-09-25,
	# reports/bot_bench/qa_verify_BOT21.json et _ts1.json), `b14_random_jumps`
	# ressort à 50 puis 222 (jamais 0) — l'avertissement B14 persiste les deux
	# fois.
	# Cause identifiée, et cette fois vérifiée de façon INDÉPENDANTE par le QA
	# (grep + lecture croisée de tools/bot_bench.gd et scripts/ai/BotStuck.gd,
	# pas seulement mon diagnostic statique) : la SEULE source de saut restante
	# est BotStuck (`_stuck.update()`, scripts/ai/BotStuck.gd, hors de ma liste
	# de fichiers), dont la docstring dit explicitement que la "phase" RENVOYÉE
	# par `update()` (celle dont le comportement produit CE tick) n'est "jamais
	# la phase interne après transition". Or tools/bot_bench.gd:1140 et :1318
	# lit `stuck.get("_phase")` (le champ INTERNE, post-transition) APRÈS que ce
	# nœud (priorité -150) a déjà tourné ce tick — au tick précis où
	# `Phase.JUMP` produit `jump_pressed = true`, `update()` fait AUSSI
	# transiter `_phase` vers `Phase.REQUEST_REPATH` dans le MÊME appel
	# (BotStuck.gd, case Phase.JUMP). Le banc lit donc systématiquement `_phase
	# == REQUEST_REPATH` (jamais `JUMP`) sur CE tick, et son filtre
	# `stuck_phase != BotStuck.Phase.JUMP` compte alors CHAQUE saut légitime de
	# déblocage comme "aléatoire" — un faux positif, pas une preuve d'un vrai
	# geste suspect. Correction hors de mon périmètre (tools/bot_bench.gd et/ou
	# scripts/ai/BotStuck.gd, aucun des deux dans ma liste de fichiers de
	# BOT-21) : blocage réel, non résolu à ce stade — voir `blocked_on` du rendu
	# de BOT-21 pour la décision du lead (élargir la liste de fichiers de
	# BOT-21, ou traiter dans une tâche dédiée touchant tools/bot_bench.gd et/ou
	# scripts/ai/BotStuck.gd).

## Reçoit la vitesse "sûre" (déviée des autres bots) calculée par le
## NavigationServer3D pour CE NavigationAgent3D (BOT-09, avoidance_enabled) —
## voir son usage dans `_tick_movement`.
func _on_avoidance_velocity_computed(safe_velocity: Vector3) -> void:
	_avoidance_safe_velocity = safe_velocity
	_avoidance_has_velocity = true

## BOT-09 : convertit `local_move` (repère du bot) en direction MONDE, projette
## un point à STRAFE_LOOKAHEAD m dans cette direction sur la navmesh
## (`BotStuck.project_strafe_to_navmesh`), puis reconvertit le résultat en
## déplacement local — un strafe qui viserait hors de la surface navigable
## (bord de toit, vide) revient tronqué au lieu d'être suivi aveuglément.
func _project_combat_move_to_navmesh(local_move: Vector2, nav_map: RID) -> Vector2:
	if not nav_map.is_valid() or local_move.length() < 0.01:
		return local_move
	var world_dir := player.global_transform.basis * Vector3(local_move.x, 0.0, local_move.y)
	if world_dir.length() < 0.01:
		return local_move
	var lookahead := player.global_position + world_dir.normalized() * STRAFE_LOOKAHEAD
	var projected := STUCK.project_strafe_to_navmesh(lookahead, nav_map)
	var projected_flat := projected - player.global_position
	projected_flat.y = 0.0
	if projected_flat.length() < 0.01:
		return Vector2.ZERO  # bord de navmesh atteint : strafe annulé plutôt que suivi hors du chemin.
	return _world_dir_to_local_move(projected_flat) * local_move.length()

func _world_dir_to_local_move(world_dir: Vector3) -> Vector2:
	if world_dir.length() < 0.05:
		return Vector2.ZERO
	var local := player.global_transform.basis.inverse() * world_dir.normalized()
	return Vector2(local.x, local.z).normalized()

## Applique, UNE FOIS que le délai programmé par `_on_health_damaged` s'est
## écoulé, l'orientation ±20° vers le dernier attaquant connu (BOT-03,
## critère : "en <= réaction+100 ms" — le compte à rebours EST la réaction,
## la correction est appliquée en UN seul tick dès qu'il expire, donc bien
## avant la marge de 100 ms). Appelée APRÈS `_tick_movement` (qui a déjà posé
## `player.input.look_delta` via `_tick_look` hors combat) : cette
## orientation, quand elle se déclenche, a le dernier mot pour CE tick.
## No-op si le bot est entré en combat entre-temps (`_target_id != -1` : sa
## vue est alors pilotée par `_aim_towards`, voir `_on_health_damaged`) —
## l'orientation programmée est alors simplement abandonnée, jamais appliquée
## en plus de la visée de combat.
func _tick_damage_orientation(delta: float) -> void:
	if _damage_reaction_left_s < 0.0:
		return
	_damage_reaction_left_s -= delta
	if _damage_reaction_left_s > 0.0:
		return
	_damage_reaction_left_s = -1.0
	if _target_id != -1 or player == null or player.head == null:
		return
	var cur_yaw_deg := rad_to_deg(player.rotation.y)
	var cur_pitch_deg := rad_to_deg(player.head.rotation.x)
	var dy := deg_to_rad(wrapf(_damage_target_yaw_deg - cur_yaw_deg, -180.0, 180.0))
	var dp := deg_to_rad(_damage_target_pitch_deg - cur_pitch_deg)
	# Même convention que `_aim_towards`/`_tick_look` : `look_delta` négatif
	# pour que `rotate_y(-look_delta.x)`/`head.rotate_x(-look_delta.y)`
	# avancent bien vers la cible.
	player.input.look_delta = Vector2(-dy, -dp)

## Un tir entendu récemment (`hearing_active`) détourne-t-il le DÉPLACEMENT
## du bot vers le bruit ? Jamais quand le mode lui fait tenir une position
## (`GameMode.bot_holds_position`, Hardpoint T5) : le bruit ne sert alors
## qu'au regard (BotLook, `has_heard`/`heard_pos` de `_tick_look`). Fonction
## PURE, testée par tests/ai/test_bot_goals_hardpoint.gd.
static func hearing_diverts_goal(hearing_active: bool, holds_position: bool) -> bool:
	return hearing_active and not holds_position

## En combat (`engaged` : cible visible), le bot navigue-t-il vers sa CIBLE
## plutôt que vers son but ? Pas s'il tient une position (voir
## `hearing_diverts_goal`) : il vise et strafe depuis son point. Fonction PURE.
static func chases_combat_target(engaged: bool, holds_position: bool) -> bool:
	return engaged and not holds_position

## Le mode courant fait-il tenir une position à CE bot
## (`GameMode.bot_holds_position`) ? Lu une fois par tick par `_tick_movement`.
func _mode_holds_position() -> bool:
	var mode := get_tree().get_first_node_in_group("game_mode")
	return mode != null and mode.has_method("bot_holds_position") \
			and bool(mode.bot_holds_position(int(player.team), str(player.name).to_int()))

## Objectif courant : un détour munitions prime (GF-24, BotCombatStyle
## §MUNITIONS — une réserve au sec, hors combat, est plus urgent qu'aller voir
## un bruit ou tenir un point), sinon un bruit récent (aller voir) — SAUF si
## le mode fait tenir une position à ce bot (`hearing_diverts_goal`) —, sinon
## l'objectif du mode de jeu (`bot_goal_for(team, bot_id, bot_pos)` — BOT-01,
## cache STABLE tenu par GameMode, ajouté à chaque mode possédé par R3-IN),
## sinon on reste sur place.
func _current_goal(holds_position: bool) -> Vector3:
	if _ammo_target_pos != Vector3.INF:
		return _ammo_target_pos
	if hearing_diverts_goal(_now() < _heard_until, holds_position):
		return _heard_pos
	var mode := get_tree().get_first_node_in_group("game_mode")
	if mode and mode.has_method("bot_goal_for"):
		var bot_id := str(player.name).to_int()
		var g: Vector3 = mode.bot_goal_for(int(player.team), bot_id, player.global_position)
		if g != Vector3.ZERO:
			return g
	return player.global_position

# ======================================================================
#  OBJECTIF DE MODE (SnD : tenir pickup pour poser/désamorcer ; achat) et
#  capacité rare — via les MÊMES points d'entrée qu'un humain.
# ======================================================================
func _tick_objective() -> void:
	var mode := get_tree().get_first_node_in_group("game_mode")
	if mode == null:
		return
	if mode.has_method("bot_set_holding"):
		mode.bot_set_holding(str(player.name).to_int(), _target_id == -1)
