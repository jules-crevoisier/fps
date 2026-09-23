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
## Émis côté TIREUR uniquement (confirmation de hit servie par le serveur).
signal hit_confirmed(pos: Vector3, dmg: float, headshot: bool)
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

var player: PlayerController
var camera: Camera3D

# ---- Prédiction locale (propriétaire uniquement) ----
var _inv: Inventory
var _fire_clock: FireClock
var _switch_cooldown: float = 0.0
## Sensation d'arme (R3-IN#4, WeaponFeel.gd) : index du tir courant dans le
## spray (motif de recul fixe puis aléatoire), et temps écoulé depuis la fin
## d'un sprint/slide/dive (INF tant que l'action n'a jamais eu lieu).
var _spray_shot_index: int = 0
var _since_sprint: float = INF
var _since_slide: float = INF
var _since_dive: float = INF

# ---- Autorité serveur (une instance par joueur, vit sur ce nœud) ----
var _server_inv: Inventory
var _server_limiters: Dictionary = {}   # weapon_id -> RateLimiter
var _pending_shots: Array = []          # [sender_id, origin, dirs, WeaponConfig]
var rejected_shots: int = 0

static var _next_world_uid: int = 1     # compteur d'uid partagé par tous les joueurs (serveur)

## Bus statique SERVEUR des tirs récents, pour l'audition des bots
## (scripts/ai/BotBrain.gd) — alimenté uniquement dans `_server_fire`, jamais
## répliqué (chaque serveur n'a besoin que de ses propres tirs acceptés, pas
## de coût réseau). [{"pos": Vector3, "team": int, "time": float}, ...]
static var recent_gunfire: Array = []
const GUNFIRE_MEMORY_MAX := 64

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
	_inv = Inventory.new(SLOTS)
	_inv.set_loadout(WeaponDatabase.default_loadout_ids())
	_fire_clock = FireClock.new(10.0)
	if multiplayer.is_server():
		_server_inv = Inventory.new(SLOTS)
		_server_inv.set_loadout(WeaponDatabase.default_loadout_ids())
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

# ======================================================================
#  PROPRIÉTAIRE — entrée, prédiction, cosmétique
# ======================================================================
func _owner_tick(delta: float) -> void:
	if camera == null:
		camera = player.camera
	_switch_cooldown = maxf(_switch_cooldown - delta, 0.0)
	if _inv.tick(delta):
		_emit_local()  # rechargement prédit terminé

	# Sensation d'arme (R3-IN#4) : délais avant de pouvoir tirer après un
	# sprint/slide/dive — voir WeaponFeel.fire_delay_left.
	var sm := player.state_machine.current_name
	# Le sprint est AUTOMATIQUE dès qu'on bouge (docs/MOVEMENT.md) : c'est la
	# course normale, on doit pouvoir y tirer (avec la dispersion de
	# mouvement). Seuls la glissade et le plongeon imposent un délai de tir.
	_since_sprint = INF
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
	var move_blocked := c != null and WeaponFeel.fire_delay_left(c, _since_sprint, _since_slide, _since_dive) > 0.0
	var trigger := false
	if can_act and c != null and not _inv.reloading and _switch_cooldown <= 0.0 and not move_blocked:
		trigger = player.input.fire_held if c.automatic else player.input.fire_pressed
	if not trigger:
		_spray_shot_index = 0  # relâché => le prochain tir reprend le motif au début.

	var shots := _fire_clock.tick(delta, trigger and _inv.can_fire())
	if c != null:
		for i in shots:
			_fire_local(c)
		if trigger and not _inv.reloading and not _inv.can_fire() and _inv.current_id() != Inventory.EMPTY:
			_start_reload_predicted()

## Le joueur peut-il agir (tirer/recharger/ramasser) maintenant ? Le gating
## "souris capturée" (menu ouvert) vit désormais dans PlayerInput — déjà
## reflété par des champs à zéro/faux, donc pas besoin de le revérifier ici
## (et un bot n'a de toute façon pas de souris à capturer).
func _can_act() -> bool:
	if player.movement_locked:
		return false  # BUY/PREROUND (verrou serveur -> owner, PlayerController.net_set_locked)
	var hp := player.get_node_or_null("Health") as Health
	if hp and hp.is_dead:
		return false
	var s := player.state_machine.current_name
	return s != "Stun" and s != "Dive" and s != "Roll"

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

	var origin := camera.global_position
	var base_dir := -camera.global_transform.basis.z
	var aiming := player.input.aim_held
	var moving := player.horizontal_speed() > 0.5
	var airborne := not player.is_on_floor()
	var base_deg := c.spread_aim if aiming else c.spread_hip
	var spread := deg_to_rad(WeaponFeel.total_spread_deg(base_deg, c, moving, airborne))

	var dirs: Array = []
	var n: int = maxi(1, c.pellets)
	for i in n:
		var s := spread
		if c.pellets > 1:
			s = deg_to_rad(c.pellet_spread)
		dirs.append(_apply_spread(base_dir, s))

	for d in dirs:
		_spawn_tracer(origin, origin + d * c.max_range)

	# Recul (vrai recoil : déplace la visée, récupère ensuite) — motif fixe
	# (recoil_pattern/pattern_shots) puis aléatoire au-delà (WeaponFeel).
	var kick := WeaponFeel.recoil_for_shot(c, _spray_shot_index)
	_spray_shot_index += 1
	var rmult := c.recoil_aim_mult if aiming else 1.0
	var rp := deg_to_rad(kick.y) * rmult
	var ry := deg_to_rad(kick.x) * rmult
	player.add_recoil(rp, ry, c.recoil_recovery)

	_do_request_fire(origin, dirs, WeaponDatabase.id_of(c))

func _apply_spread(dir: Vector3, spread: float) -> Vector3:
	if spread <= 0.0:
		return dir
	var rx := randf_range(-spread, spread)
	var ry := randf_range(-spread, spread)
	return dir.rotated(camera.global_transform.basis.x, rx).rotated(Vector3.UP, ry).normalized()

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
	_inv.give(weapon_id)
	_emit_local()
	_do_request_buy(weapon_id)

## Demande de ramassage d'une arme au sol (appelé par WorldWeapon, qui gère
## déjà son propre anti-spam). Prédit localement avec l'id connu du client.
func request_world_pickup(uid: int) -> void:
	if player == null or not player.is_multiplayer_authority():
		return
	var ww := WorldWeapon.find(uid)
	if ww:
		_inv.give(ww.weapon_id)
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
	var now := Time.get_ticks_msec() / 1000.0
	if not _limiter_for(weapon_id, c.fire_rate).try_take(now):
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
	for d in dirs:
		_spawn_tracer(origin, origin + d * range_m)

func _server_buy(sender_id: int, weapon_id: int) -> void:
	if not multiplayer.is_server() or sender_id != _owner_id():
		return
	if _buy_enabled() and WeaponDatabase.get_by_id(weapon_id) != null and _try_purchase(sender_id, weapon_id):
		_server_inv.give(weapon_id)
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
	_server_inv.set_loadout(ids)
	_push_server_sync()
	_broadcast_current_id.rpc(_server_inv.current_id())

## Remplit chargeur + réserve de toutes les armes possédées (ex. début de
## round). Synchro poussée au propriétaire.
func server_refill_ammo() -> void:
	if not multiplayer.is_server() or _server_inv == null:
		return
	for i in _server_inv.slots.size():
		var id: int = _server_inv.slots[i]
		if id == Inventory.EMPTY:
			continue
		var c := WeaponDatabase.get_by_id(id)
		if c:
			_server_inv.mag[i] = c.mag_size
			_server_inv.reserve[i] = c.reserve_ammo
	_server_inv.reloading = false
	_server_inv.reload_left = 0.0
	_push_server_sync()

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
		var displaced := _server_inv.give(ww.weapon_id)
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
		for d in dirs:
			_resolve_ray(space, shooter_id, origin, d, c)
	_pending_shots.clear()

func _resolve_ray(space: PhysicsDirectSpaceState3D, shooter_id: int, origin: Vector3, dir: Vector3, c: WeaponConfig) -> void:
	var q := PhysicsRayQueryParameters3D.create(origin, origin + dir.normalized() * c.max_range, PhysicsLayers.SHOT_MASK)
	q.exclude = [player.get_rid()]
	q.collide_with_areas = false
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return
	var collider: Node = hit.collider
	var hp := collider.get_node_or_null("Health") as Health
	if hp == null or hp.is_dead:
		return
	var dist: float = origin.distance_to(hit.position)
	var headshot: bool = WeaponMath.is_headshot(hit.position.y, collider.global_position.y)
	var dmg := WeaponMath.damage_at(dist, c)
	if headshot:
		dmg *= c.headshot_mult
	hp.apply_damage(dmg, shooter_id)
	# Affiche le chiffre de dégâts chez le TIREUR (feedback de hit). Ce nœud
	# Weapon appartient TOUJOURS au tireur (shooter_id == _owner_id() : ce
	# sont ses propres tirs en attente, mis en file par _server_fire) — donc
	# `player.is_multiplayer_authority()` dit si le tireur est simulé ICI
	# (hôte OU bot) ; sinon un RPC ciblé est nécessaire (client distant).
	if player.is_multiplayer_authority():
		_spawn_damage_number(hit.position, dmg, headshot)  # hôte/bot : direct
	else:
		_show_hit.rpc_id(shooter_id, hit.position, dmg, headshot)

@rpc("authority", "call_remote", "reliable")
func _show_hit(pos: Vector3, dmg: float, headshot: bool) -> void:
	_spawn_damage_number(pos, dmg, headshot)

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
#  Cosmétique local (traceur, chiffre de dégâts) — identique tous pairs
# ======================================================================
func _spawn_damage_number(pos: Vector3, dmg: float, headshot: bool) -> void:
	# Ce chemin ne s'exécute QUE chez le tireur (appel direct si hôte-tireur,
	# sinon via _show_hit reçu par le tireur) : signal "shooter only" correct.
	hit_confirmed.emit(pos, dmg, headshot)
	var l := Label3D.new()
	l.text = str(int(round(dmg)))
	l.font_size = 64
	l.pixel_size = 0.007
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.modulate = Color(1.0, 0.4, 0.2) if headshot else Color(1, 1, 1)
	l.outline_modulate = Color(0, 0, 0, 0.9)
	l.outline_size = 10
	var scene := player.get_tree().current_scene
	if scene == null:
		return
	scene.add_child(l)
	l.global_position = pos + Vector3(randf_range(-0.15, 0.15), 0.25, 0.0)
	var t := l.create_tween()
	t.tween_property(l, "global_position:y", l.global_position.y + 0.9, 0.7)
	t.parallel().tween_property(l, "modulate:a", 0.0, 0.7)
	t.tween_callback(l.queue_free)

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
