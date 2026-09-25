## Weapon.gd
## Enveloppe RÉSEAU autour de l'inventaire d'armes. Le nœud est autorité
## SERVEUR (fixée par PlayerController._enter_tree, après l'autorité récursive
## du propriétaire) ; le corps du joueur reste autorité du PROPRIÉTAIRE.
##  - Le PROPRIÉTAIRE prédit localement (chargeur, tir, traceurs, recul,
##    signaux HUD) avec un Inventory + FireClock locaux, pour la réactivité.
##  - Le SERVEUR garde l'inventaire AUTORITAIRE (un par joueur, sur ce nœud),
##    valide chaque requête (_server_*), résout les tirs acceptés en
##    _physics_process avec WeaponMath, et pousse l'inventaire complet au
##    propriétaire quand il REFUSE une action (ou lors d'un ramassage) ; le
##    propriétaire l'adopte tel quel (corrige la prédiction).
## L'hôte (serveur ET propriétaire de son propre joueur) et le training solo
## passent par le MÊME chemin serveur (multiplayer.is_server() est vrai dans
## les deux cas ; GameWorld héberge localement si aucun pair n'est configuré).
class_name Weapon
extends Node

signal ammo_changed(ammo: int, reserve: int)
signal weapon_changed(cfg: WeaponConfig)
## Émis côté PROPRIÉTAIRE uniquement (prédiction locale) — pour le ViewModel
## (recul, flash au canon) : voir scripts/player/ViewModel.gd.
signal fired(cfg: WeaponConfig)
signal reload_started(cfg: WeaponConfig)
## Émis côté PROPRIÉTAIRE uniquement (prédiction locale) — clic à vide : la
## gâchette est actionnée (front montant `fire_pressed`, UNE fois par appui,
## automatique ou non) sur un chargeur ET une réserve à zéro, donc aucun
## rechargement ne peut démarrer à la place (GF-12, voir Audio.should_play_dry_fire
## et Audio._wire_local_extras).
signal dry_fire()
## Émis côté TIREUR uniquement (confirmation de hit servie par le serveur) —
## UNE fois par tir ET par cible touchée (dégâts SOMMÉS sur tous les plombs
## d'un même tir qui atteignent cette cible : GF-07, voir
## `HitFeedback.aggregate_shot_hits` — avant cette tâche, un fusil à pompe à
## 12 plombs (Fracas) émettait 12 confirmations au lieu d'une). `is_kill`
## vient directement du SERVEUR (`Health.is_dead` observé juste après
## l'application des dégâts, dans la MÊME résolution de tir) : ce n'est plus
## une fenêtre de correspondance devinée côté HUD
## (`HitFeedback.KILL_MATCH_WINDOW`, supprimée).
signal hit_confirmed(pos: Vector3, dmg: float, headshot: bool, is_kill: bool)
## Émis sur CHAQUE pair SAUF le tireur (diffusion serveur des tirs ACCEPTÉS,
## unreliable_ordered) — pour le ThirdPersonWeapon / l'audio distants.
signal remote_fired(cfg: WeaponConfig, origin: Vector3, dirs: Array)
## Émis sur TOUS les pairs (id de l'arme en main, vérité serveur) : la synchro
## d'inventaire complète (_sync_inventory) ne part QUE vers le propriétaire, ce
## qui ne suffit pas aux AUTRES pairs pour savoir quelle arme afficher sur le
## ThirdPersonWeapon d'un joueur distant. Diffusion légère et peu fréquente
## (équiper/acheter/ramasser/lâcher), reliable.
signal current_id_changed(id: int)

const SLOTS := 2            # 2 emplacements façon CoD (n'importe quelle arme dans chacun)
const SWITCH_DELAY := 0.25  # petit délai de changement d'arme (prédiction locale)
const PICKUP_RANGE := 2.0   # distance max (m) pour valider un ramassage côté serveur
## Fin de rechargement anticipée acceptée par le serveur (s) : absorbe la gigue
## réseau entre la fin prédite chez le joueur et la fin serveur.
const RELOAD_TOLERANCE := 0.15
## Fenêtre d'achat en arène (Mêlée/Borne, §2.6) : au-delà de ce délai depuis le
## spawn, la boutique ne recharge plus l'inventaire EN COURS DE VIE — elle ne
## fait plus que choisir le loadout du PROCHAIN respawn (§2.2), pour fermer la
## recharge gratuite en plein combat (§2.1 constat 3). Hors arène (round/
## infinite), aucune restriction ici : voir `arena_buy_allowed`.
const ARENA_BUY_WINDOW := 10.0

var player: PlayerController
var camera: Camera3D
## Points de vue armés (GF-06, voir `_muzzle_position`) : le canon vu par CE
## joueur (ViewModel, enfant de Head/Camera3D) et celui vu par les AUTRES
## (ThirdPersonWeapon, main droite du corps) — les deux nœuds existent
## toujours (unique_name_in_owner, scenes/player/player.tscn), résolus une
## fois ici plutôt qu'à chaque tir.
var view_model: ViewModel
var third_person_weapon: ThirdPersonWeapon

# ---- Prédiction locale (propriétaire uniquement) ----
var _inv: Inventory
var _fire_clock: FireClock
var _switch_cooldown: float = 0.0
## Sensation d'arme (R3-IN#4, WeaponFeel.gd) : index du tir courant dans le
## spray (motif de recul fixe puis aléatoire), et temps écoulé depuis la fin
## d'une glissade/d'un plongeon (INF tant que l'action n'a jamais eu lieu). Le
## sprint est automatique et n'impose plus de délai (BUG-K01).
var _spray_shot_index: int = 0
var _since_slide: float = INF
var _since_dive: float = INF

# ---- Autorité serveur (une instance par joueur, vit sur ce nœud) ----
var _server_inv: Inventory
var _server_limiters: Dictionary = {}   # weapon_id -> RateLimiter
var _pending_shots: Array = []          # [sender_id, origin, dirs, WeaponConfig]
var rejected_shots: int = 0
## Temps écoulé (s) depuis le dernier spawn/refill de CE joueur (voir
## `server_refill_ammo`, remis à zéro à chaque appel — GF-20 : seul appelant,
## à chaque respawn en arène) — sert UNIQUEMENT à `arena_buy_allowed`
## (`_server_buy`), jamais lu en dehors du serveur.
var _server_time_since_spawn: float = 0.0
## Horloge de SIMULATION serveur (cumul du delta physique de CE nœud, jamais
## remise à zéro) — voir `_server_tick`/`_server_fire` (BUG-26) : source de
## temps du limiteur de cadence, à la place de `Time.get_ticks_msec()`
## (horloge murale réelle, désynchronisable du delta simulé sous charge machine).
var _server_clock: float = 0.0

static var _next_world_uid: int = 1     # compteur d'uid partagé par tous les joueurs (serveur)

## Bus statique SERVEUR des tirs récents, pour l'audition des bots
## (scripts/ai/BotBrain.gd) — alimenté uniquement dans `_server_fire`, jamais
## répliqué (chaque serveur n'a besoin que de ses propres tirs acceptés, pas
## de coût réseau). [{"pos": Vector3, "team": int, "time": float}, ...]
static var recent_gunfire: Array = []
const GUNFIRE_MEMORY_MAX := 64

## Bus statique SERVEUR des impacts de balle récents (BOT-03, docs/research/
## 02_bots_ai.md §2.2/§3 : "impacts proches 5 m") — alimenté pour CHAQUE plomb
## qui touche quelque chose (mur OU joueur, mort ou vivant : le bruit d'impact
## ne fait pas cette distinction), dans `_resolve_ray`, à la position RÉELLE
## de l'impact (`hit.position`), jamais l'origine du tir (déjà couverte par
## `recent_gunfire`). `team` = équipe du TIREUR (`player.team`, ce nœud Weapon
## appartenant toujours au tireur) : un bot ignore les impacts de SA PROPRE
## équipe, même logique de filtrage que `recent_gunfire`
## (scripts/ai/BotBrain.gd, `_hear_gunfire`/nouveau `_hear_impacts`).
static var recent_impacts: Array = []
const IMPACT_MEMORY_MAX := 64

## Chemin du modèle 3D (.glb, voir tools/blender/make_weapons.py) pour un id
## d'arme — déduit du nom de fichier .tres dans WeaponDatabase.PATHS (même
## radical). "" si l'id est hors limites.
static func model_path_for(id: int) -> String:
	if id < 0 or id >= WeaponDatabase.PATHS.size():
		return ""
	var stem := (WeaponDatabase.PATHS[id] as String).get_file().get_basename()
	return "res://assets/models/weapons/%s.glb" % stem

func _ready() -> void:
	player = get_parent() as PlayerController
	view_model = get_node_or_null("%ViewModel") as ViewModel
	third_person_weapon = get_node_or_null("%ThirdPersonWeapon") as ThirdPersonWeapon
	_inv = Inventory.new(SLOTS)
	_inv.set_loadout(WeaponDatabase.default_loadout_ids(), _ammo_rule())
	_fire_clock = FireClock.new(10.0)
	if multiplayer.is_server():
		_server_inv = Inventory.new(SLOTS)
		_server_inv.set_loadout(WeaponDatabase.default_loadout_ids(), _ammo_rule())
		_server_time_since_spawn = 0.0
		_broadcast_current_id.rpc(_server_inv.current_id())
	_emit_local()

func _physics_process(delta: float) -> void:
	if multiplayer.is_server():
		_server_tick(delta)
	if player and player.is_multiplayer_authority():
		_owner_tick(delta)

# ======================================================================
#  VUES DE COMPATIBILITÉ (lecture seule) — GameHUD.gd / PlayerCamera.gd
# ======================================================================
var weapons: Array:
	get:
		var arr: Array = []
		if _inv:
			for id in _inv.slots:
				arr.append(WeaponDatabase.get_by_id(id))
		return arr

var mag: Array:
	get: return _inv.mag if _inv else []

var reserve_a: Array:
	get: return _inv.reserve if _inv else []

var current: int:
	get: return _inv.current if _inv else 0

func cfg() -> WeaponConfig:
	return WeaponDatabase.get_by_id(_inv.current_id()) if _inv else null

## Onomatopée de l'arme en main (docs/STYLE_BIBLE.md §9.4 "Confirmation de
## kill" : « + onomatopée de l'arme », HitFeedback.weapon_kill_word) — prête à
## être branchée par `GameHUD._trigger_kill_word` (scripts/ui/GameHUD.gd, HORS
## de mon périmètre d'écriture) à la place du mot générique historique
## `HitFeedback.sound_word` : voir le rendu de fin de tâche, `blocked_on`.
func current_kill_word() -> String:
	var c := cfg()
	return HitFeedback.weapon_kill_word(c.weapon_name if c else "")

func current_aim_fov() -> float:
	var c := cfg()
	return c.aim_fov if c else 60.0

func is_scoped() -> bool:
	var c := cfg()
	return c != null and c.scoped

## Un emplacement est-il libre ? (utilisé par WorldWeapon pour l'auto-ramassage)
func has_free_slot() -> bool:
	return _inv != null and _inv.free_slot() != -1

func _emit_local() -> void:
	if _inv and _inv.current < _inv.mag.size():
		ammo_changed.emit(_inv.mag[_inv.current], _inv.reserve[_inv.current])
	weapon_changed.emit(cfg())

func _owner_id() -> int:
	return str(player.name).to_int() if player else -1

## Passif de l'agent EN COURS de CE joueur (AGT-09, docs/research/
## 10_ammo_kits_input.md §3.5) : résolu via son nœud "Abilities" (jamais un
## champ dupliqué ici) -- `null` si l'agent n'a pas de passif, ou si le nœud
## "Abilities" n'existe pas encore (repli sûr, mêmes gardes que partout dans
## ce fichier). Utilisé côté PROPRIÉTAIRE (prédiction de dispersion/recul,
## voir `_fire_local`) : chaque pair résout SON PROPRE agent, jamais celui
## d'un autre joueur.
func _agent_passive() -> Passive:
	if player == null:
		return null
	var ctrl := player.get_node_or_null("Abilities") as AbilityController
	if ctrl == null or ctrl.agent == null:
		return null
	return ctrl.agent.passive

## Règle de munitions du mode courant (`Inventory.RULE_ROUND`/`RULE_ARENA`/
## `RULE_INFINITE`, docs/research/10_ammo_kits_input.md §2.2) — lue à CHAQUE
## appel (jamais mise en cache : le groupe "game_mode" peut ne pas encore
## exister au tout premier `_ready()`, avant que la scène de mode ait fini de
## s'instancier, et un mode `RoundMode` ne change de toute façon jamais de
## règle en cours de partie). Utilisée aussi bien côté PROPRIÉTAIRE (prédiction
## de `_inv`) que côté SERVEUR (`_server_inv`) : les deux lisent le MÊME groupe
## "game_mode" dans l'arbre de scène, peuplé identiquement sur chaque pair
## (aucune réplication réseau nécessaire, voir GameMode.ammo_rule).
##  - Aucun nœud dans le groupe "game_mode" (pas de scène de mode DU TOUT,
##    exactement le cas de l'entraînement — aucune scène de training
##    n'instancie GameMode) => réserve infinie.
##  - Un nœud présent mais dépourvu du champ `ammo_rule` (double de test
##    minimal, ex. tests/ui/test_buy_menu.gd::FakeEconomyMode) => traité comme
##    une arène : c'est le comportement le moins restrictif pour un mode
##    "normal" inconnu, et tout mode de PRODUCTION (GameMode et ses
##    sous-classes) porte, lui, toujours un `ammo_rule` réel.
func _ammo_rule() -> String:
	if player == null or not player.is_inside_tree():
		return Inventory.RULE_ARENA
	var mode := player.get_tree().get_first_node_in_group("game_mode")
	if mode == null:
		return Inventory.RULE_INFINITE
	var v = mode.get("ammo_rule")
	return String(v) if v != null else Inventory.RULE_ARENA

## Fenêtre d'achat en arène (§2.6) : la boutique ne recharge gratuitement
## l'inventaire EN COURS DE VIE que dans les `ARENA_BUY_WINDOW` premières
## secondes après le spawn — au-delà, `_server_buy` la refuse (elle continuera
## de choisir le loadout du PROCHAIN respawn, §2.2, par la prédiction du
## propriétaire qui n'est pas corrigée tant que le serveur ne pousse rien).
## Hors arène (round : le Litige a sa propre phase d'achat/`buy_phase`, le
## Duel n'a pas de boutique du tout — `DuelMode.server_try_purchase` renvoie
## faux ; infinite : entraînement, libre), aucune restriction ICI. Pure et
## statique : testée directement (tests/combat/test_inventory.gd), sans scène
## ni pair réseau — voir la docstring de RELOAD_TOLERANCE pour la même
## philosophie de tolérance/limite en constante nommée.
static func arena_buy_allowed(ammo_rule: String, time_since_spawn: float) -> bool:
	if ammo_rule != Inventory.RULE_ARENA:
		return true
	return time_since_spawn <= ARENA_BUY_WINDOW

# ======================================================================
#  PROPRIÉTAIRE — entrée, prédiction, cosmétique
# ======================================================================
func _owner_tick(delta: float) -> void:
	if camera == null:
		camera = player.camera
	_switch_cooldown = maxf(_switch_cooldown - delta, 0.0)
	if _inv.tick(delta):
		_emit_local()  # rechargement prédit terminé

	# Sensation d'arme (R3-IN#4) : délais avant de pouvoir tirer après une
	# glissade/un plongeon — voir WeaponFeel.fire_delay_left. Le sprint est
	# AUTOMATIQUE dès qu'on bouge (docs/MOVEMENT.md) : c'est la course normale,
	# on doit pouvoir y tirer (avec la dispersion de mouvement) — aucun délai
	# (BUG-K01 : sprint_to_fire/_since_sprint retirés, mécanique inopérante).
	var sm := player.state_machine.current_name
	_since_slide = 0.0 if sm == "Slide" else _since_slide + delta
	_since_dive = 0.0 if sm == "Dive" else _since_dive + delta

	var can_act := _can_act()
	if can_act:
		_handle_switch_input()
		if player.input.drop_pressed:
			_request_drop()
		if player.input.reload_pressed and not _inv.reloading:
			_start_reload_predicted()

	var c := WeaponDatabase.get_by_id(_inv.current_id())
	var move_blocked := c != null and WeaponFeel.fire_delay_left(c, _since_slide, _since_dive) > 0.0
	var trigger := false
	if can_act and c != null and not _inv.reloading and _switch_cooldown <= 0.0 and not move_blocked:
		trigger = player.input.fire_held if c.automatic else player.input.fire_pressed
	if not trigger:
		_spray_shot_index = 0  # relâché => le prochain tir reprend le motif au début.

	# GF-12 : un fire_pressed reçu pendant le cooldown est mémorisé 120 ms par
	# FireClock (voir sa docstring) et tire dès que l'intervalle est écoulé —
	# corrige les clics "perdus" en fin de cooldown (docs/research/01_game_feel.md
	# #13). `can_fire()` bloque déjà l'entrée du buffer sur chargeur vide.
	var shots := _fire_clock.tick(delta, trigger and _inv.can_fire())
	if c != null:
		for i in shots:
			_fire_local(c)
		if trigger and not _inv.reloading and not _inv.can_fire() and _inv.current_id() != Inventory.EMPTY:
			if _inv.reserve[_inv.current] > 0:
				_start_reload_predicted()
			elif Audio.should_play_dry_fire(player.input.fire_pressed, _inv.mag[_inv.current], _inv.reserve[_inv.current]):
				# GF-12 : chargeur ET réserve à zéro, aucun rechargement possible —
				# clic à vide, une seule fois par appui (should_play_dry_fire ne
				# passe qu'à la frame `fire_pressed`, jamais en continu).
				dry_fire.emit()
				# §2.6 : passage AUTOMATIQUE à l'autre arme dès ce premier clic à
				# vide (plus besoin d'appuyer soi-même sur 1/2/molette) — même
				# chemin que le changement manuel (`_try_equip`, `SWITCH_DELAY`
				# inclus), donc réseau et prédiction identiques. Sans effet si
				# l'autre slot est vide ou déjà courant (`Inventory.equip` refuse).
				if _inv.slots.size() > 1:
					_try_equip((_inv.current + 1) % _inv.slots.size())

## Le joueur peut-il agir (tirer/recharger/ramasser) maintenant ? Le gating
## "souris capturée" (menu ouvert) vit désormais dans PlayerInput — déjà
## reflété par des champs à zéro/faux, donc pas besoin de le revérifier ici
## (et un bot n'a de toute façon pas de souris à capturer). "Stun" N'EST PLUS
## exclu (GF-29/MV-03, docs/research/01_game_feel.md #16) : le stun de chute
## adouci (0,6 s max) garde la main au joueur — il vise et tire toujours,
## seulement moins précisément (+`MovementConfig.stun_fire_spread_add`, voir
## `_fire_local`) — contrairement à Dive/Roll, qui restent des ACTIONS en
## cours (une animation de plongeon/roulade, pas une pénalité subie) et
## excluent donc toujours le tir.
func _can_act() -> bool:
	if player.movement_locked:
		return false  # BUY/PREROUND (verrou serveur -> owner, PlayerController.net_set_locked)
	var hp := player.get_node_or_null("Health") as Health
	if hp and hp.is_dead:
		return false
	var s := player.state_machine.current_name
	return s != "Dive" and s != "Roll"

func _handle_switch_input() -> void:
	if _inv.slots.size() <= 1:
		return
	var slot := player.input.weapon_slot_pressed
	if slot == 0:
		_try_equip(0)
	elif slot == 1:
		_try_equip(1)
	elif player.input.weapon_next_pressed:
		_try_equip((_inv.current + 1) % _inv.slots.size())
	elif player.input.weapon_prev_pressed:
		_try_equip((_inv.current - 1 + _inv.slots.size()) % _inv.slots.size())

func _try_equip(slot: int) -> void:
	if _inv.equip(slot):
		_switch_cooldown = SWITCH_DELAY
		_emit_local()
		_do_request_equip(slot)

func _start_reload_predicted() -> void:
	if _inv.start_reload():
		_emit_local()
		reload_started.emit(WeaponDatabase.get_by_id(_inv.current_id()))
	_do_request_reload()

func _fire_local(c: WeaponConfig) -> void:
	_inv.consume_round()
	_emit_local()
	fired.emit(c)

	# Trauma de tir caméra (GF-29/GF-08, docs/research/01_game_feel.md §2.1/§3) :
	# `is_local_human()`, PAS `is_multiplayer_authority()` seule — un bot
	# partage l'autorité serveur (prédiction locale, voir `_owner_tick`) mais
	# n'a personne devant un écran à secouer (contract-r3.md, "Cross-slice
	# interfaces"). `camera` est déjà résolu ici (voir `_owner_tick`, seul
	# appelant de `_fire_local`, qui le pose AVANT ce tick) ; le cast est requis
	# car ce champ reste typé `Camera3D` (compatibilité GameHUD.gd/PlayerCamera.gd).
	if player.is_local_human():
		var cam := camera as PlayerCamera
		if cam:
			cam.add_shot_trauma(WeaponFeel.shot_trauma_amount(c))

	# L'ORIGINE du tir vient de `player.head.global_position` (position LIVE,
	# la MÊME que celle relue par `_server_fire` pour `head_pos` — voir plus
	# bas dans ce fichier), PAS de `camera.global_position` : la caméra de
	# l'humain local est `top_level` et lissée (GF-03, `PlayerCamera.
	# _apply_interpolated_transform`, exécutée en `_process`, donc cadencée sur
	# le RENDU, pas la physique) et ne tourne QUE pour `is_local_human()` — une
	# caméra de bot/joueur distant simulé serveur resterait figée à sa transform
	# de spawn (voir PlayerCamera._ready). `head`, lui, est le PARENT de la
	# caméra dans la scène (jamais l'inverse) : sa position suit la capsule à
	# CHAQUE tick physique, pour tout pair, qu'il soit humain local, bot ou
	# distant — aucun risque de gel. La rotation, elle, reste bien celle de la
	# caméra (déjà LIVE, jamais lissée — voir PlayerCamera.
	# _apply_interpolated_transform : seule l'origine y est interpolée).
	#
	# BUG-26 (régression Sprint, revue 20260924-164342) : la piste "origine
	# figée" ci-dessus a été explorée et ÉCARTÉE (le tir refusé l'était même
	# avec `head_pos`, déjà en place ici) — la vraie cause était le limiteur
	# de cadence côté serveur sur horloge murale réelle, voir le commentaire
	# BUG-26 dans `_server_fire` plus bas.
	var origin := player.head.global_position
	var base_dir := -camera.global_transform.basis.z
	var aiming := player.input.aim_held
	var airborne := not player.is_on_floor()
	# Dispersion de mouvement CONTINUE (MV-02, façon Valorant) : plus un
	# booléen "moving > 0.5 m/s", mais une montée progressive avec zone morte
	# (WeaponFeel.move_spread_deg) ; en ADS la vitesse réelle est déjà réduite
	# par Sprint.gd/Walk.gd (ads_move_mult), donc la dispersion baisse d'elle-
	# même en visant, sans logique dupliquée ici.
	var sliding := player.state_machine.current_name == "Slide"
	var move_spread := WeaponFeel.move_spread_deg(c, player.horizontal_speed(), player.config.sprint_speed, sliding)
	var air_spread := c.air_spread_add if airborne else 0.0
	var base_deg := c.spread_aim if aiming else c.spread_hip
	# Passif Sang-froid de Verrou (AGT-08/AGT-09, docs/research/
	# 10_ammo_kits_input.md §3.3 : « dispersion -30 %, recul vertical -20 % »
	# immobile ou accroupi) : `Passive.spread_mult` vaut 1.0 par défaut pour
	# tout autre agent (aucun effet, comportement inchangé) -- voir
	# `WeaponFeel.total_spread_deg`/`steady_spread_mult`, déjà préparés pour ce
	# multiplicateur.
	var passive := _agent_passive()
	var passive_spread_mult := passive.spread_mult(player) if passive else 1.0
	# Dispersion additionnelle pendant le Stun (GF-29/MV-03, MovementConfig.
	# stun_fire_spread_add = 3° par défaut) : le stun de chute adouci ne fige
	# plus le tir (voir `_can_act` ci-dessus), il le rend seulement moins précis.
	var stun_spread := player.config.stun_fire_spread_add if player.state_machine.current_name == "Stun" else 0.0
	var spread := deg_to_rad(WeaponFeel.total_spread_deg(base_deg, move_spread, air_spread, passive_spread_mult, stun_spread))

	# Dispersion en DISQUE, dans le repère CAMÉRA (GF-13, WeaponFeel.spread_dir) :
	# remplace l'ancienne dispersion carrée qui tournait autour de Vector3.UP
	# MONDIAL (cône aplati en visant vers le haut/bas, docs/research/01_game_feel.md #7).
	var dirs: Array = []
	var n: int = maxi(1, c.pellets)
	for i in n:
		var s := spread
		if c.pellets > 1:
			s = deg_to_rad(c.pellet_spread) * passive_spread_mult
		dirs.append(WeaponFeel.spread_dir(base_dir, camera.global_transform.basis, s))

	var muzzle := _muzzle_position()
	for d in dirs:
		_fire_visuals(muzzle, origin, d, c.max_range)

	# Recul (vrai recoil : déplace la visée, récupère ensuite) — motif fixe
	# (recoil_pattern/pattern_shots) puis aléatoire au-delà (WeaponFeel).
	# `recoil_mult` (Sang-froid, duck-typé -- voir sa docstring) ne réduit QUE
	# la composante VERTICALE, jamais l'aléatoire horizontal (§3.3).
	var passive_recoil_mult := 1.0
	if passive and passive.has_method("recoil_mult"):
		passive_recoil_mult = passive.recoil_mult(player)
	var kick := WeaponFeel.recoil_for_shot(c, _spray_shot_index, null, passive_recoil_mult)
	_spray_shot_index += 1
	var rmult := c.recoil_aim_mult if aiming else 1.0
	var rp := deg_to_rad(kick.y) * rmult
	var ry := deg_to_rad(kick.x) * rmult
	player.add_recoil(rp, ry, c.recoil_recovery)

	_do_request_fire(origin, dirs, WeaponDatabase.id_of(c))

## Lâche l'arme courante (touche G).
func _request_drop() -> void:
	_inv.remove_current()
	_emit_local()
	_do_request_drop()

## Achat (boutique) : prédit localement, le serveur corrige s'il refuse
## (buy_enabled=false, id invalide…) en renvoyant l'inventaire.
func buy(weapon_id: int) -> void:
	if player == null or not player.is_multiplayer_authority():
		return
	_inv.give(weapon_id, _ammo_rule())
	_emit_local()
	_do_request_buy(weapon_id)

## Demande de ramassage d'une arme au sol (appelé par WorldWeapon, qui gère
## déjà son propre anti-spam). Prédit localement avec l'id connu du client.
func request_world_pickup(uid: int) -> void:
	if player == null or not player.is_multiplayer_authority():
		return
	var ww := WorldWeapon.find(uid)
	if ww:
		_inv.give(ww.weapon_id, _ammo_rule())
		_emit_local()
	_do_request_pickup(uid)

# ======================================================================
#  REQUÊTES CLIENT -> SERVEUR
#  Motif (contract-p0.md, règles globales) : le CALLER choisit — appel direct
#  côté serveur (hôte/solo OU BOT, qui partagent l'autorité serveur — voir
#  PlayerController._enter_tree), sinon RPC vers le pair 1. Le handler RPC ne
#  fait que relayer vers _server_*(sender_id, ...).
#  IMPORTANT (contract-r3.md, "Cross-slice interfaces") : l'appel direct
#  utilise `_owner_id()` (= str(player.name).to_int()), JAMAIS
#  `multiplayer.get_unique_id()` — pour l'hôte les deux coïncident (id 1),
#  mais pour un BOT (id >= 9001) `get_unique_id()` resterait 1 (l'id du
#  SERVEUR, pas celui du bot) et `_server_*` rejetterait la requête
#  (sender_id != _owner_id()).
# ======================================================================
func _do_request_fire(origin: Vector3, dirs: Array, weapon_id: int) -> void:
	if multiplayer.is_server():
		_server_fire(_owner_id(), origin, dirs, weapon_id)
	else:
		request_fire.rpc_id(1, origin, dirs, weapon_id)

@rpc("any_peer", "call_remote", "reliable")
func request_fire(origin: Vector3, dirs: Array, weapon_id: int) -> void:
	_server_fire(multiplayer.get_remote_sender_id(), origin, dirs, weapon_id)

func _do_request_buy(weapon_id: int) -> void:
	if multiplayer.is_server():
		_server_buy(_owner_id(), weapon_id)
	else:
		request_buy.rpc_id(1, weapon_id)

@rpc("any_peer", "call_remote", "reliable")
func request_buy(weapon_id: int) -> void:
	_server_buy(multiplayer.get_remote_sender_id(), weapon_id)

func _do_request_pickup(uid: int) -> void:
	if multiplayer.is_server():
		_server_pickup(_owner_id(), uid)
	else:
		request_pickup.rpc_id(1, uid)

@rpc("any_peer", "call_remote", "reliable")
func request_pickup(uid: int) -> void:
	_server_pickup(multiplayer.get_remote_sender_id(), uid)

func _do_request_drop() -> void:
	if multiplayer.is_server():
		_server_drop(_owner_id())
	else:
		request_drop.rpc_id(1)

@rpc("any_peer", "call_remote", "reliable")
func request_drop() -> void:
	_server_drop(multiplayer.get_remote_sender_id())

func _do_request_equip(slot: int) -> void:
	if multiplayer.is_server():
		_server_equip(_owner_id(), slot)
	else:
		request_equip.rpc_id(1, slot)

@rpc("any_peer", "call_remote", "reliable")
func request_equip(slot: int) -> void:
	_server_equip(multiplayer.get_remote_sender_id(), slot)

func _do_request_reload() -> void:
	if multiplayer.is_server():
		_server_reload(_owner_id())
	else:
		request_reload.rpc_id(1)

@rpc("any_peer", "call_remote", "reliable")
func request_reload() -> void:
	_server_reload(multiplayer.get_remote_sender_id())

# ======================================================================
#  SERVEUR — validation (_server_*) ; sender_id toujours vérifié == propriétaire
# ======================================================================
func _server_tick(delta: float) -> void:
	_server_clock += delta
	_server_time_since_spawn += delta
	if _server_inv == null:
		return
	# Fin de rechargement : le propriétaire l'a prédite lui-même, pas de synchro.
	_server_inv.tick(delta)
	if not _pending_shots.is_empty():
		_resolve_pending_shots()

func _server_fire(sender_id: int, origin: Vector3, dirs: Array, weapon_id: int) -> void:
	if not multiplayer.is_server() or sender_id != _owner_id():
		return
	if _round_locked():
		_reject_shot()
		return
	var hp := player.get_node_or_null("Health") as Health
	if hp and hp.is_dead:
		_reject_shot()
		return
	if weapon_id != _server_inv.current_id():
		_reject_shot()
		return
	var c := WeaponDatabase.get_by_id(weapon_id)
	_server_inv.finish_reload_if_within(RELOAD_TOLERANCE)
	if c == null or not _server_inv.can_fire():
		_reject_shot()
		return
	# BUG-26 : l'horloge du limiteur de cadence DOIT être celle de la
	# SIMULATION serveur (`_server_clock`, cumul du `delta` physique de CE
	# nœud — voir `_server_tick`), jamais `Time.get_ticks_msec()` (horloge
	# MURALE réelle). Le client prédit sa cadence via FireClock, qui tourne
	# lui aussi sur le delta physique SIMULÉ (60 Hz fixe) — les deux horloges
	# ne divergent JAMAIS l'une de l'autre par construction. Avec l'horloge
	# murale, le deuxième tir d'une rafale à cadence pile (10 tirs/s ici,
	# burst=2, aucune marge) exigeait un écart réel d'AU MOINS 100 ms entre
	# les deux tirs pour regagner le jeton consommé par le premier : sous
	# charge machine (plusieurs process Godot en parallèle, revue
	# 20260924-164342, sondes agents concurrentes), le moteur peut exécuter
	# deux tics physiques successifs avec un écart réel MOINDRE que leur
	# delta simulé (rattrapage après un ralentissement) — le jeton n'a alors
	# pas eu le temps de se reconstituer et le serveur refuse à tort un tir
	# que le client a pourtant bien cadencé. Seul le Sprint (le SEUL état qui
	# maintient l'appui sur la gâchette assez longtemps pour atteindre ce
	# deuxième tir dans la fenêtre du sonde, cf. gameplay_probe._check_fire_in_state)
	# exposait la fenêtre de course. `_server_clock` élimine la dépendance au
	# temps réel SANS affaiblir l'anti-triche (le serveur cadence lui-même sa
	# propre horloge, immunisée à toute manipulation du client).
	if not _limiter_for(weapon_id, c.fire_rate).try_take(_server_clock):
		_reject_shot()
		return
	# Vue serveur de la tête : position répliquée + hauteur debout (l'accroupi
	# n'est simulé que chez le propriétaire). La tolérance de ShotValidator
	# couvre cet écart ; la lag compensation (P1.3) le remplacera.
	var head_pos: Vector3 = player.head.global_position
	if not ShotValidator.is_valid(origin, head_pos, dirs, c.pellets):
		_reject_shot()
		return
	# Tir accepté : le propriétaire a déjà prédit exactement ce décompte, donc
	# pas de synchro (elle arriverait en retard et écraserait ses tirs suivants).
	_server_inv.consume_round()
	_pending_shots.append([sender_id, origin, dirs, c])
	# Tirer met fin à la protection de spawn (Health : R-B1, pas encore fixée
	# à l'écriture de ce fichier — appel défensif).
	if hp and hp.has_method("end_spawn_protection"):
		hp.end_spawn_protection()
	_remember_gunfire(origin, int(player.team))
	_broadcast_remote_shot(sender_id, weapon_id, origin, dirs)

## Alimente le bus statique d'audition des bots (voir `recent_gunfire`
## ci-dessus) — SERVEUR uniquement, un tir accepté à la fois.
static func _remember_gunfire(pos: Vector3, team: int) -> void:
	recent_gunfire.append({"pos": pos, "team": team, "time": Time.get_ticks_msec() / 1000.0})
	while recent_gunfire.size() > GUNFIRE_MEMORY_MAX:
		recent_gunfire.pop_front()

## Alimente le bus statique d'impacts (voir `recent_impacts` ci-dessus) —
## SERVEUR uniquement, un plomb touché à la fois (voir `_resolve_ray`).
static func _remember_impact(pos: Vector3, team: int) -> void:
	recent_impacts.append({"pos": pos, "team": team, "time": Time.get_ticks_msec() / 1000.0})
	while recent_impacts.size() > IMPACT_MEMORY_MAX:
		recent_impacts.pop_front()

func _reject_shot() -> void:
	rejected_shots += 1
	_push_server_sync()

func _limiter_for(weapon_id: int, fire_rate: float) -> RateLimiter:
	if not _server_limiters.has(weapon_id):
		_server_limiters[weapon_id] = RateLimiter.new(fire_rate, 2.0)
	return _server_limiters[weapon_id]

## Diffuse le FX d'un tir ACCEPTÉ à tous les pairs SAUF le tireur (signal
## `remote_fired`, unreliable_ordered — juste du cosmétique, une perte
## occasionnelle n'a pas d'importance). Le serveur lui-même (hôte joueur) le
## reçoit par appel direct s'il n'est pas le tireur (jamais de RPC vers soi,
## comme le reste du fichier).
func _broadcast_remote_shot(sender_id: int, weapon_id: int, origin: Vector3, dirs: Array) -> void:
	for peer_id in multiplayer.get_peers():
		if peer_id != sender_id:
			_remote_shot_fx.rpc_id(peer_id, weapon_id, origin, dirs)
	# Écho local (sur le SERVEUR) uniquement si CE tireur n'est pas simulé ici
	# (`player.is_multiplayer_authority()` — pas `sender_id == get_unique_id()` :
	# pour un BOT, sender_id >= 9001 ne coïncidera jamais avec l'id réel du
	# serveur alors que sa prédiction locale (_fire_local) tourne bien ICI,
	# comme celle de l'hôte — sinon le traceur serait dupliqué).
	if not player.is_multiplayer_authority():
		_remote_shot_fx(weapon_id, origin, dirs)

@rpc("authority", "call_remote", "unreliable_ordered")
func _remote_shot_fx(weapon_id: int, origin: Vector3, dirs: Array) -> void:
	var c := WeaponDatabase.get_by_id(weapon_id)
	remote_fired.emit(c, origin, dirs)
	var range_m: float = c.max_range if c else 200.0
	var muzzle := _muzzle_position()
	for d in dirs:
		_fire_visuals(muzzle, origin, d, range_m)

func _server_buy(sender_id: int, weapon_id: int) -> void:
	if not multiplayer.is_server() or sender_id != _owner_id():
		return
	var rule := _ammo_rule()
	if _buy_enabled() and arena_buy_allowed(rule, _server_time_since_spawn) \
			and WeaponDatabase.get_by_id(weapon_id) != null and _try_purchase(sender_id, weapon_id):
		_server_inv.give(weapon_id, rule)
		_broadcast_current_id.rpc(_server_inv.current_id())
		return  # identique à la prédiction du propriétaire
	_push_server_sync()

## Boutique : délègue au mode de jeu s'il définit sa propre règle d'achat
## (ex. crédits SnD) ; sinon autorisé par défaut (training).
func _try_purchase(peer_id: int, weapon_id: int) -> bool:
	var mode := player.get_tree().get_first_node_in_group("game_mode")
	if mode and mode.has_method("server_try_purchase"):
		return mode.server_try_purchase(peer_id, weapon_id)
	return true

func _buy_enabled() -> bool:
	var m := player.get_tree().get_first_node_in_group("match")
	if m == null:
		return true
	var v = m.get("buy_enabled")
	return true if v == null else bool(v)

## Manche verrouillée (BUY/PREROUND, GameWorld.round_locked — R-B1, serveur
## autoritaire) : aucun tir accepté tant que c'est le cas. Groupe "match"
## absent (training) ou propriété absente => pas de verrou.
func _round_locked() -> bool:
	var m := player.get_tree().get_first_node_in_group("match")
	if m == null:
		return false
	var v = m.get("round_locked")
	return false if v == null else bool(v)

# ======================================================================
#  API SERVEUR — appelée par le mode de jeu (respawn, achat forcé, etc.)
# ======================================================================

## Remplace le loadout complet côté serveur (ex. reset de round). Synchro
## poussée au propriétaire.
func server_set_loadout(ids: Array[int]) -> void:
	if not multiplayer.is_server() or _server_inv == null:
		return
	_server_inv.set_loadout(ids, _ammo_rule())
	_push_server_sync()
	_broadcast_current_id.rpc(_server_inv.current_id())

## Remplit chargeur + réserve de toutes les armes possédées (ex. début de
## round). Synchro poussée au propriétaire.
func server_refill_ammo() -> void:
	if not multiplayer.is_server() or _server_inv == null:
		return
	var rule := _ammo_rule()
	for i in _server_inv.slots.size():
		var id: int = _server_inv.slots[i]
		if id == Inventory.EMPTY:
			continue
		var c := WeaponDatabase.get_by_id(id)
		if c:
			_server_inv.mag[i] = c.mag_size
			_server_inv.reserve[i] = Inventory.reserve_for(c, rule)
	_server_inv.reloading = false
	_server_inv.reload_left = 0.0
	# GF-21 §2.6 : ce respawn (seul appelant, GameWorld._on_player_died) rouvre
	# la fenêtre d'achat gratuite de l'arène pour ARENA_BUY_WINDOW secondes.
	_server_time_since_spawn = 0.0
	_push_server_sync()

## GF-22 (docs/research/10_ammo_kits_input.md §2.4, « Cartouchière ») : ajoute
## `mags` chargeur(s) (`WeaponConfig.mag_size`) à la RÉSERVE de CHAQUE arme
## possédée, plafonné à la réserve de la RÈGLE COURANTE (`_ammo_rule()` —
## arène en Mêlée/Borne, infinie en entraînement : jamais de plafond arène en
## dur, sinon un ramassage en entraînement plafonnerait à tort une réserve déjà
## réglée sur `Inventory.INFINITE_RESERVE`). Renvoie vrai si AU MOINS une
## réserve a réellement augmenté — l'appelant (AmmoPack, seul appelant prévu)
## s'en sert pour ne consommer/désapparaître le ramassage QUE s'il a servi à
## quelque chose (§2.4 : « si l'une de ses réserves n'est pas pleine ») ; un
## ramassage sans effet (toutes les réserves déjà au plafond) laisse la
## cartouchière au sol pour un autre joueur. Synchro poussée au propriétaire
## uniquement si quelque chose a changé (même prudence que `_server_pickup`).
func server_add_reserve_mags(mags: int = 1) -> bool:
	if not multiplayer.is_server() or _server_inv == null:
		return false
	var rule := _ammo_rule()
	var changed := false
	for i in _server_inv.slots.size():
		var id: int = _server_inv.slots[i]
		if id == Inventory.EMPTY:
			continue
		var c := WeaponDatabase.get_by_id(id)
		if c == null:
			continue
		var cap := Inventory.reserve_for(c, rule)
		var target := mini(_server_inv.reserve[i] + mags * c.mag_size, cap)
		if target != _server_inv.reserve[i]:
			_server_inv.reserve[i] = target
			changed = true
	if changed:
		_push_server_sync()
	return changed

## Ids possédés côté serveur (copie en lecture seule), [] si l'inventaire
## serveur n'existe pas (client pur).
func server_current_ids() -> Array[int]:
	var ids: Array[int] = []
	if _server_inv == null:
		return ids
	for id in _server_inv.slots:
		ids.append(id)
	return ids

func _server_pickup(sender_id: int, uid: int) -> void:
	if not multiplayer.is_server() or sender_id != _owner_id():
		return
	var ww := WorldWeapon.find(uid)
	var hp := player.get_node_or_null("Health") as Health
	var alive := not (hp and hp.is_dead)
	if ww and is_instance_valid(ww) and ww.is_armed() and alive \
			and player.global_position.distance_to(ww.global_position) <= PICKUP_RANGE:
		var displaced := _server_inv.give(ww.weapon_id, _ammo_rule())
		_server_despawn_world_weapon(ww.uid)
		if displaced != Inventory.EMPTY:
			var fwd := -player.global_transform.basis.z
			_server_spawn_world_weapon(displaced, player.global_position + Vector3(0, 1.1, 0) + fwd * 0.4, Vector3.ZERO)
	_push_server_sync()
	_broadcast_current_id.rpc(_server_inv.current_id())

func _server_drop(sender_id: int) -> void:
	if not multiplayer.is_server() or sender_id != _owner_id():
		return
	var id := _server_inv.current_id()
	if id == Inventory.EMPTY:
		_push_server_sync()
		return
	_server_inv.remove_current()
	var fwd := -player.global_transform.basis.z
	var vel := player.velocity * 0.6 + fwd * 4.0 + Vector3(0, 3.0, 0)
	_server_spawn_world_weapon(id, player.global_position + Vector3(0, 1.1, 0) + fwd * 0.4, vel)
	_broadcast_current_id.rpc(_server_inv.current_id())

func _server_equip(sender_id: int, slot: int) -> void:
	if not multiplayer.is_server() or sender_id != _owner_id():
		return
	if not _server_inv.equip(slot):
		_push_server_sync()
	else:
		_broadcast_current_id.rpc(_server_inv.current_id())

func _server_reload(sender_id: int) -> void:
	if not multiplayer.is_server() or sender_id != _owner_id():
		return
	if not _server_inv.start_reload():
		_push_server_sync()

## Pousse l'inventaire serveur complet au propriétaire. Seulement quand le
## serveur REFUSE ou fait autre chose que la prédiction (tir refusé, ramassage) :
## une synchro après une action acceptée arriverait avec un aller-retour de
## retard et effacerait les actions prédites entre-temps. Appel direct si le
## serveur EST le propriétaire (hôte/solo).
func _push_server_sync() -> void:
	if not multiplayer.is_server() or _server_inv == null:
		return
	var d := _server_inv.to_dict()
	# `player.is_multiplayer_authority()` (pas une comparaison d'id) : vrai
	# pour l'hôte-joueur ET pour un bot, qui partagent l'autorité serveur —
	# un RPC vers `_owner_id()` d'un bot (>= 9001) n'atteindrait aucun pair réel.
	if player.is_multiplayer_authority():
		_apply_sync(d)
	else:
		_sync_inventory.rpc_id(_owner_id(), d)

@rpc("authority", "call_remote", "reliable")
func _sync_inventory(d: Dictionary) -> void:
	_apply_sync(d)

func _apply_sync(d: Dictionary) -> void:
	_inv = Inventory.from_dict(d)
	_emit_local()

## Diffuse l'id de l'arme en main à TOUS les pairs (voir `current_id_changed`
## plus haut) : contrairement à `_sync_inventory`, ce n'est PAS réservé au
## propriétaire — les tiers en ont besoin pour le ThirdPersonWeapon.
@rpc("authority", "call_local", "reliable")
func _broadcast_current_id(id: int) -> void:
	current_id_changed.emit(id)

# ======================================================================
#  SERVEUR — résolution des tirs acceptés (rayons, dégâts, headshot)
# ======================================================================
func _resolve_pending_shots() -> void:
	var space := player.get_world_3d().direct_space_state
	for shot in _pending_shots:
		var shooter_id: int = shot[0]
		var origin: Vector3 = shot[1]
		var dirs: Array = shot[2]
		var c: WeaponConfig = shot[3]
		_resolve_shot(space, shooter_id, origin, dirs, c)
	_pending_shots.clear()

## Résout TOUS les plombs d'UN tir, puis les agrège PAR CIBLE
## (`HitFeedback.aggregate_shot_hits`, pure et testée hors scène) avant
## d'appliquer les dégâts et de confirmer le hit — GF-07 : un fusil à pompe
## (12 plombs, ex. Fracas) qui touche une seule cible applique UNE seule fois
## la somme des dégâts et émet UNE seule confirmation, pas douze.
func _resolve_shot(space: PhysicsDirectSpaceState3D, shooter_id: int, origin: Vector3, dirs: Array, c: WeaponConfig) -> void:
	var pellet_hits: Array = []           # -> HitFeedback.aggregate_shot_hits (un plomb touché = une entrée)
	var context: Dictionary = {}          # target_id -> {"health": Health, "pos": Vector3} (dernier plomb touché)
	for d in dirs:
		var res := _resolve_ray(space, origin, d, c, shooter_id)
		if res.is_empty():
			continue
		var target_id: int = res["target_id"]
		context[target_id] = {"health": res["health"], "pos": res["pos"]}
		pellet_hits.append({"target": target_id, "dmg": res["dmg"], "headshot": res["headshot"]})
	for agg in HitFeedback.aggregate_shot_hits(pellet_hits):
		var target_id: int = agg["target"]
		var ctx: Dictionary = context[target_id]
		var hp: Health = ctx["health"]
		if hp == null or hp.is_dead:
			continue  # déjà tuée par un agrégat précédent de ce MÊME tir (cibles multiples)
		var dmg: float = agg["dmg"]
		# GF-10 (relance QA) : le drapeau headshot doit être transmis à
		# `apply_damage` — c'est lui qui choisit la couleur du flash de hit
		# diffusé par `Health.hit_reaction` (voir sa docstring). Avant ce
		# correctif, `agg["headshot"]` n'était lu qu'une ligne plus bas
		# (`_confirm_hit`, pour le chiffre de dégâts chez le tireur) : le rim
		# rouge du headshot n'était donc jamais visible par le vrai chemin de
		# tir, seulement par un appel direct à `Health.apply_damage` en test.
		hp.apply_damage(dmg, shooter_id, agg["headshot"])
		# `is_kill` vient du SERVEUR : `Health.is_dead` est déjà à jour ici,
		# `apply_damage` ayant appelé `_die` de façon SYNCHRONE si la cible
		# est tombée à 0 PV (voir Health.gd) — dans la MÊME résolution de tir.
		_confirm_hit(shooter_id, ctx["pos"], dmg, agg["headshot"], hp.is_dead, target_id)

## Raycast + calcul de dégâts pour UN SEUL plomb. `{}` si rien touché ou si la
## cible est déjà morte. `target_id` = clé stable de la cible (l'id du
## joueur touché, voir `PlayerController._enter_tree` : `str(name).to_int()`)
## utilisée pour l'agrégation (`_resolve_shot`) et l'empilement des chiffres
## (`_spawn_damage_number`).
func _resolve_ray(space: PhysicsDirectSpaceState3D, origin: Vector3, dir: Vector3, c: WeaponConfig, shooter_id: int) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(origin, origin + dir.normalized() * c.max_range, PhysicsLayers.SHOT_MASK)
	q.exclude = [player.get_rid()]
	q.collide_with_areas = false
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return {}
	# BOT-03 : bruit d'impact (mur OU joueur, mort ou vivant -- le bruit ne
	# fait pas cette distinction) à la position RÉELLE de l'impact, pour
	# l'audition des bots (`recent_impacts`, voir sa docstring) -- AVANT tout
	# `return {}` anticipé ci-dessous, un impact fait du bruit même s'il ne
	# blesse personne (mur) ou ne compte pas comme un hit valide (cible déjà
	# morte).
	_remember_impact(hit.position, int(player.team))
	var collider: Node = hit.collider
	var hp := collider.get_node_or_null("Health") as Health
	if hp == null:
		_notify_wall_shot(collider, shooter_id)  # AGT-09 : passif Relevé -- pas une cible (mur, décor).
		return {}
	if hp.is_dead:
		return {}
	var dist: float = origin.distance_to(hit.position)
	# `current_height` est répliquée (always) et appliquée à la capsule sur
	# CE pair (voir PlayerController._apply_body_height, GF-04) : le seuil de
	# tête suit donc la cible debout OU accroupie, plus jamais 1.4 m fixe —
	# et une cible accroupie a une capsule plus basse, donc un tir trop haut
	# ne touche déjà plus rien (hit.is_empty() ci-dessus) avant même d'arriver ici.
	var target := collider as PlayerController
	# 1.8 = MovementConfig.stand_height par défaut : repli défensif seul (Health
	# n'existe que sur scenes/player/player.tscn, donc `target` est toujours
	# non-null en pratique — ce cas ne devrait jamais s'exécuter).
	var body_height: float = target.current_height if target else 1.8
	var headshot: bool = WeaponMath.is_headshot(hit.position.y, collider.global_position.y, body_height)
	var dmg := WeaponMath.damage_at(dist, c)
	if headshot:
		dmg *= c.headshot_mult
	var target_id: int = target.name.to_int() if target else 0
	return {"health": hp, "pos": hit.position, "dmg": dmg, "headshot": headshot, "target_id": target_id}

## Passif Relevé de Vanne (AGT-05/AGT-09, docs/research/10_ammo_kits_input.md
## §3.3) : « tout ennemi qui tire dans un de ses murs est marqué pour son
## équipe ». `collider` vient d'un rayon qui a touché QUELQUE CHOSE sans
## Health (donc jamais un joueur, mort ou vivant) -- un mur posé par
## `AbilityController._spawn_barrier` porte sa métadonnée `wall_owner_id`
## (AGT-09) ; tout autre décor (sans cette métadonnée) ne fait rien ici.
## `shooter_id` est le TIREUR (déjà résolu par `_server_fire`/`_resolve_shot`),
## jamais `_owner_id()` (ce nœud Weapon appartient au tireur, mais le MUR
## appartient à sa victime potentielle -- un joueur peut très bien tirer dans
## son PROPRE mur, `Releve.on_wall_shot` l'ignore déjà via la vérif d'équipe).
func _notify_wall_shot(collider: Node, shooter_id: int) -> void:
	if not collider.has_meta("wall_owner_id"):
		return
	var owner_id := int(collider.get_meta("wall_owner_id"))
	if owner_id == shooter_id or player == null:
		return  # tir dans son propre mur : jamais une marque (Releve.on_wall_shot le vérifie aussi par équipe).
	var players_root := player.get_parent()
	if players_root == null:
		return
	var wall_owner := players_root.get_node_or_null(str(owner_id)) as PlayerController
	var attacker := players_root.get_node_or_null(str(shooter_id)) as PlayerController
	if wall_owner == null or attacker == null:
		return
	var owner_ctrl := wall_owner.get_node_or_null("Abilities") as AbilityController
	if owner_ctrl == null or owner_ctrl.agent == null or owner_ctrl.agent.passive == null:
		return
	if owner_ctrl.agent.passive.has_method("on_wall_shot"):
		owner_ctrl.agent.passive.on_wall_shot(wall_owner, attacker, Time.get_ticks_msec() / 1000.0)

## Affiche le chiffre de dégâts chez le TIREUR (feedback de hit). Ce nœud
## Weapon appartient TOUJOURS au tireur (shooter_id == _owner_id() : ce sont
## ses propres tirs en attente, mis en file par _server_fire) — donc
## `player.is_multiplayer_authority()` dit si le tireur est simulé ICI (hôte
## OU bot) ; sinon un RPC ciblé est nécessaire (client distant).
func _confirm_hit(shooter_id: int, pos: Vector3, dmg: float, headshot: bool, is_kill: bool, target_id: int) -> void:
	if player.is_multiplayer_authority():
		_spawn_damage_number(pos, dmg, headshot, is_kill, target_id)  # hôte/bot : direct
	else:
		_show_hit.rpc_id(shooter_id, pos, dmg, headshot, is_kill, target_id)

@rpc("authority", "call_remote", "reliable")
func _show_hit(pos: Vector3, dmg: float, headshot: bool, is_kill: bool, target_id: int) -> void:
	_spawn_damage_number(pos, dmg, headshot, is_kill, target_id)

# ======================================================================
#  SERVEUR — armes au sol : uid + diffusion spawn/despawn (voir WorldWeapon.gd)
# ======================================================================
func _server_spawn_world_weapon(weapon_id: int, pos: Vector3, vel: Vector3) -> void:
	if not multiplayer.is_server() or weapon_id < 0:
		return
	var uid := _next_world_uid
	_next_world_uid += 1
	_broadcast_world_spawn.rpc(uid, weapon_id, pos, vel)

func _server_despawn_world_weapon(uid: int) -> void:
	if not multiplayer.is_server():
		return
	_broadcast_world_despawn.rpc(uid)

@rpc("authority", "call_local", "reliable")
func _broadcast_world_spawn(uid: int, weapon_id: int, pos: Vector3, vel: Vector3) -> void:
	var scene := player.get_tree().current_scene if player else null
	WorldWeapon.spawn_local(uid, weapon_id, pos, vel, scene)

@rpc("authority", "call_local", "reliable")
func _broadcast_world_despawn(uid: int) -> void:
	WorldWeapon.despawn_local(uid)

# ======================================================================
#  Cosmétique local (traceur, impact, chiffre de dégâts) — identique tous
#  pairs (GF-06 : traceur du muzzle jusqu'à l'impact prédit localement, voir
#  docs/research/01_game_feel.md #6 et « Séparation standard »)
# ======================================================================

## Origine VISUELLE du traceur pour CE tir (le rayon LOGIQUE, lui, part
## toujours de la tête — voir `origin` dans `_fire_local`/`_remote_shot_fx`,
## inchangé depuis BUG-26) : le canon du ViewModel si CE joueur EST le joueur humain local
## (son propre point de vue, `player.is_local_human()`), sinon celui de son
## ThirdPersonWeapon (vu par tous les AUTRES pairs — joueurs distants ET
## bots, dont le ViewModel reste toujours caché, voir ViewModel._ready).
## Repli sur la caméra si le modèle 3D correspondant n'est pas encore chargé
## (ex. tout premier tir juste après l'équipement).
func _muzzle_position() -> Vector3:
	if player and player.is_local_human() and view_model:
		return view_model.muzzle_global_position()
	if third_person_weapon:
		return third_person_weapon.muzzle_global_position()
	return camera.global_position if camera else Vector3.ZERO

## Raycast LOCAL (cosmétique, prédit — voir docs/research/01_game_feel.md,
## « Séparation standard » : on prédit ce qui est certain, on attend le
## serveur pour ce qui a des conséquences) dans l'espace physique de CE
## client, MÊME masque que la résolution serveur (`PhysicsLayers.SHOT_MASK`,
## voir `_resolve_ray`) — sert uniquement à savoir où arrêter le traceur et
## poser l'effet d'impact, SANS jamais infliger de dégâts ni attendre le
## serveur. `{}` si rien touché ou si le joueur n'est plus dans l'arbre
## (ex. juste après un despawn).
func _local_impact(origin: Vector3, dir: Vector3, max_range: float) -> Dictionary:
	if player == null or not player.is_inside_tree():
		return {}
	var space := player.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(origin, origin + dir.normalized() * max_range, PhysicsLayers.SHOT_MASK)
	q.exclude = [player.get_rid()]
	q.collide_with_areas = false
	return space.intersect_ray(q)

## Trace le traceur du `muzzle` jusqu'au premier impact d'un raycast LOCAL
## (`_local_impact`, même masque que le serveur) et y pose l'effet d'impact
## (`ImpactFx`), dans la MÊME frame que le tir — appelé aussi bien pour la
## prédiction locale (`_fire_local`) que pour l'écho cosmétique d'un tir
## distant (`_remote_shot_fx`). Sans impact touché (rayon dans le vide), le
## traceur va jusqu'à `max_range` et aucun `ImpactFx` n'apparaît.
func _fire_visuals(muzzle: Vector3, origin: Vector3, dir: Vector3, max_range: float) -> void:
	var hit := _local_impact(origin, dir, max_range)
	var end_pos: Vector3 = hit.position if not hit.is_empty() else origin + dir.normalized() * max_range
	_spawn_tracer(muzzle, end_pos)
	if not hit.is_empty():
		_spawn_impact(hit.position, hit.normal)

func _spawn_impact(pos: Vector3, normal: Vector3) -> void:
	if player == null or not player.is_inside_tree():
		return
	ImpactFx.spawn(player.get_tree().current_scene, pos, normal)

## Empilement des chiffres PAR CIBLE (GF-07, `HitFeedback.should_stack_damage`/
## `damage_stack_scale`) : target_id -> {"node": DamageNumber3D, "total":
## float, "count": int, "time": float}. Un nouveau tir sur une cible déjà
## marquée il y a moins de `HitFeedback.DAMAGE_STACK_WINDOW` (0,8 s, STYLE_BIBLE
## §9.4) fait GROSSIR le chiffre existant (total cumulé, échelle plus grande)
## au lieu d'en poser un nouveau par-dessus (façon Borderlands/Apex) — voir
## `_spawn_damage_number`. La création du nœud, son rendu (STYLE_BIBLE §9.4 :
## Barlow Condensed ExtraBold, contour encre 3 px, headshot ×1,25) et son
## animation (montée + fondu) sont délégués à `DamageNumber3D` : ce dictionnaire
## ne garde que la comptabilité d'empilement, propre à Weapon.gd.
var _stacked_numbers: Dictionary = {}

func _spawn_damage_number(pos: Vector3, dmg: float, headshot: bool, is_kill: bool, target_id: int) -> void:
	# Ce chemin ne s'exécute QUE chez le tireur (appel direct si hôte-tireur,
	# sinon via _show_hit reçu par le tireur) : signal "shooter only" correct.
	hit_confirmed.emit(pos, dmg, headshot, is_kill)

	# Punch FOV lourd au kill confirmé (GF-29/GF-08) — joueur LOCAL uniquement
	# (même garde que le trauma de tir ci-dessus dans `_fire_local` : un bot
	# tireur n'a pas d'écran à secouer). `player.camera`, pas `camera` (ce champ
	# de Weapon) : ce chemin peut s'exécuter hors de `_owner_tick`
	# (`_show_hit`, reçu par RPC chez un tireur distant) où `camera` n'a jamais
	# été résolu.
	if is_kill and player and player.is_local_human():
		var cam := player.camera as PlayerCamera
		if cam:
			cam.punch_fov_heavy()

	var now := Time.get_ticks_msec() / 1000.0
	var stack: Dictionary = _stacked_numbers.get(target_id, {})
	var node: DamageNumber3D = stack.get("node")
	var stacking := not stack.is_empty() and is_instance_valid(node) \
		and HitFeedback.should_stack_damage(now - float(stack.get("time", -INF)))

	var total: float = (float(stack.get("total", 0.0)) + dmg) if stacking else dmg
	var count: int = (int(stack.get("count", 0)) + 1) if stacking else 1

	if stacking:
		node.apply(total, headshot, count)  # relance l'animation à partir de la position/alpha ACTUELLES
	else:
		var scene := player.get_tree().current_scene
		if scene == null:
			return
		node = DamageNumber3D.spawn(scene, pos, total, headshot, count)
		node.tree_exiting.connect(_on_damage_number_expired.bind(target_id, node))

	_stacked_numbers[target_id] = {"node": node, "total": total, "count": count, "time": now}

## Fin de vie d'un chiffre de dégâts (DamageNumber3D se libère lui-même en fin
## de fondu) : oublie son empilement, SAUF si un nouveau chiffre a déjà pris
## sa place entre-temps sur la même cible (le `node` ne correspondrait alors
## plus à l'entrée courante).
func _on_damage_number_expired(target_id: int, node: DamageNumber3D) -> void:
	if _stacked_numbers.get(target_id, {}).get("node") == node:
		_stacked_numbers.erase(target_id)

func _spawn_tracer(from: Vector3, to: Vector3) -> void:
	var mesh := MeshInstance3D.new()
	var im := ImmediateMesh.new()
	mesh.mesh = im
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.95, 0.5)
	mesh.material_override = mat
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	im.surface_add_vertex(from)
	im.surface_add_vertex(to)
	im.surface_end()
	player.get_tree().current_scene.add_child(mesh)
	var t := mesh.create_tween()
	t.tween_property(mat, "albedo_color:a", 0.0, 0.08)
	t.tween_callback(mesh.queue_free)
