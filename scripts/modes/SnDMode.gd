## SnDMode.gd
## Recherche & Destruction (façon CoD) : 4v4, attaquants (équipe `attacking_team()`)
## contre défenseurs, première à 6 manches, échange de camp après 5, achats
## 15 s, manche 90 s. Une bombe portée par un attaquant tiré au sort en début
## de manche, lâchée (et re-ramassable en marchant dessus) si le porteur
## meurt, posable (4 s en tenant "pickup" dans un site) puis désamorçable
## (7 s), mèche de 45 s. Tout est validé SERVEUR (contract-p0.md) : le client
## ne fait qu'ENVOYER s'il tient l'action (les conditions — site, vivant,
## côté, porteur — sont revérifiées à chaque tick serveur).
class_name SnDMode
extends RoundMode

enum BombState { CARRIED, DROPPED, PLANTED, DEFUSED, EXPLODED }

const PLANT_TIME := 4.0
const DEFUSE_TIME := 7.0
const BOMB_FUSE := 45.0
const BOMB_PICKUP_RANGE := 2.0

@export var site_a_path: NodePath
@export var site_b_path: NodePath

## --- Répliqué aux clients (HUD), voir `_sync_bomb` ---
var bomb_state: int = BombState.CARRIED
var bomb_site: String = ""
var bomb_carrier_id: int = -1
var bomb_position: Vector3 = Vector3.ZERO
var bomb_plant_ratio: float = 0.0
var bomb_defuse_ratio: float = 0.0
var bomb_fuse_left: float = BOMB_FUSE
## Solde de crédits du joueur LOCAL (poussé par le serveur), lu par BuyMenu/HUD.
var my_credits: int = 0

var economy := Economy.new()

var _site_a: Area3D
var _site_b: Area3D

# ---- Autorité SERVEUR uniquement ----
var _bomb_state: int = BombState.CARRIED
var _bomb_site: String = ""
var _bomb_carrier_id: int = -1
var _bomb_drop_pos: Vector3 = Vector3.ZERO
var _bomb_plant_pos: Vector3 = Vector3.ZERO  ## Position exacte de la pose (affichage + son "bomb_beep").
var _bomb_fuse_left: float = BOMB_FUSE
var _plant_progress: float = 0.0
var _defuse_progress: Dictionary = {}   # peer_id -> float
var _holding: Dictionary = {}           # peer_id -> bool (action "pickup" tenue)
var _pending_loadouts: Dictionary = {}  # peer_id -> Array[int] (survivants, snapshot avant respawn)
var _bomb_sync_timer: float = 0.0
## CLIENT (tous les pairs) : cadence du bip de la bombe posée, accélère dans
## les 10 dernières secondes (R-E audio, "bomb_beep").
var _beep_timer: float = 0.0

func _ready() -> void:
	super._ready()
	mode_name = "Recherche & Destruction"
	_site_a = get_node_or_null(site_a_path) as Area3D
	_site_b = get_node_or_null(site_b_path) as Area3D

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	_client_report_holding()
	_tick_bomb_beep(delta)
	if not multiplayer.is_server():
		return
	if round_state.phase == RoundState.Phase.LIVE and winner == -1:
		_server_tick_bomb(delta)
	_bomb_sync_timer += delta
	if _bomb_sync_timer >= 0.1:
		_bomb_sync_timer = 0.0
		_broadcast_bomb()

## Rejoué sur TOUS les pairs (lit uniquement l'état répliqué) : ≈1/s, ≈2/s
## dans les 10 dernières secondes de la mèche.
func _tick_bomb_beep(delta: float) -> void:
	if bomb_state != BombState.PLANTED:
		_beep_timer = 0.0
		return
	var interval := 0.5 if bomb_fuse_left <= 10.0 else 1.0
	_beep_timer += delta
	if _beep_timer >= interval:
		_beep_timer = 0.0
		_play_sfx_at("bomb_beep", bomb_position)

# ======================================================================
#  Manche : préparation / fin
# ======================================================================
func _on_new_round() -> void:
	_snapshot_survivor_loadouts()
	_reset_bomb_state()
	_assign_carrier()
	_ensure_all_economy()

func _after_round_respawn() -> void:
	var pistol := WeaponDatabase.get_by_name("Pistolet")
	var pistol_id := WeaponDatabase.id_of(pistol) if pistol else -1
	for child in _players():
		var weapon: Node = child.get_node_or_null("Weapon")
		if weapon == null or not weapon.has_method("server_set_loadout"):
			continue
		var id := str(child.name).to_int()
		var ids: Array[int] = []
		if _pending_loadouts.has(id):
			ids = _pending_loadouts[id]
		elif pistol_id >= 0:
			ids = [pistol_id]
		weapon.server_set_loadout(ids)

func _on_round_ended(winning_team: int) -> void:
	var winners: Array = []
	var losers: Array = []
	for child in _players():
		var id := str(child.name).to_int()
		_ensure_economy(id)
		if int(child.get("team")) == winning_team:
			winners.append(id)
		else:
			losers.append(id)
	economy.round_ended(winners, losers)
	_push_all_credits()

func _on_round_timeout() -> void:
	if _bomb_state == BombState.PLANTED:
		return  # la bombe posée prime sur le chrono de manche
	end_round(1 - attacking_team())  # défenseurs gagnent au chrono

func _build_hud_state() -> String:
	match round_state.phase:
		RoundState.Phase.BUY:
			return "Achats — %ds" % int(ceil(round_state.time_left))
		RoundState.Phase.LIVE:
			if _bomb_state == BombState.PLANTED:
				return "Bombe posée (%s) — %ds" % [_bomb_site, int(ceil(_bomb_fuse_left))]
			return "Manche en cours — %ds" % int(ceil(round_state.time_left))
	return "Manche terminée"

func reset_match() -> void:
	economy = Economy.new()
	super.reset_match()

# ======================================================================
#  Économie / boutique
# ======================================================================
## Appelé par Weapon._server_buy (R-A2, via has_method) : autorise/débite l'achat.
func server_try_purchase(peer_id: int, weapon_id: int) -> bool:
	if round_state.phase != RoundState.Phase.BUY:
		return false
	var cfg := WeaponDatabase.get_by_id(weapon_id)
	if cfg == null:
		return false
	_ensure_economy(peer_id)
	if not economy.spend(peer_id, cfg.cost):
		return false
	_push_credits(peer_id)
	return true

func _ensure_economy(id: int) -> void:
	if not economy.credits.has(id):
		economy.reset_player(id)
		_push_credits(id)

func _ensure_all_economy() -> void:
	for child in _players():
		_ensure_economy(str(child.name).to_int())

func _push_all_credits() -> void:
	for child in _players():
		_push_credits(str(child.name).to_int())

func _push_credits(id: int) -> void:
	if id == multiplayer.get_unique_id():
		my_credits = economy.get_credits(id)
		updated.emit()
	else:
		_receive_credits.rpc_id(id, economy.get_credits(id))

@rpc("authority", "call_remote", "reliable")
func _receive_credits(amount: int) -> void:
	my_credits = amount
	updated.emit()

# ======================================================================
#  Kills : crédits, chute de la bombe, élimination d'équipe
# ======================================================================
func on_kill(killer_id: int, victim_id: int, killer_team: int, victim_team: int) -> void:
	if not multiplayer.is_server() or winner != -1 or round_state.phase != RoundState.Phase.LIVE:
		return
	if victim_id == _bomb_carrier_id and _bomb_state == BombState.CARRIED:
		var p := _player_node(victim_id)
		_bomb_drop_pos = p.global_position if p else Vector3.ZERO
		_bomb_state = BombState.DROPPED
		_bomb_carrier_id = -1
	if killer_id > 0 and killer_team >= 0 and killer_team != victim_team:
		_ensure_economy(killer_id)
		economy.award_kill(killer_id)
		_push_credits(killer_id)
	if killer_team < 0 or killer_team == victim_team:
		return
	# Attaquants tous morts APRÈS la pose : la manche continue (défuse/explosion).
	if victim_team == attacking_team() and _bomb_state == BombState.PLANTED:
		return
	if _team_all_dead(victim_team):
		end_round(killer_team)

# ======================================================================
#  Bombe : état pur côté serveur
# ======================================================================
func _reset_bomb_state() -> void:
	_bomb_state = BombState.CARRIED
	_bomb_carrier_id = -1
	_bomb_site = ""
	_bomb_drop_pos = Vector3.ZERO
	_bomb_plant_pos = Vector3.ZERO
	_bomb_fuse_left = BOMB_FUSE
	_plant_progress = 0.0
	_defuse_progress.clear()
	_holding.clear()

func _assign_carrier() -> void:
	var attackers: Array = []
	for child in _players():
		if int(child.get("team")) == attacking_team():
			attackers.append(str(child.name).to_int())
	if not attackers.is_empty():
		_bomb_carrier_id = attackers[randi() % attackers.size()]
		_bomb_state = BombState.CARRIED

func _snapshot_survivor_loadouts() -> void:
	_pending_loadouts.clear()
	for child in _players():
		var hp := child.get_node_or_null("Health") as Health
		if hp and hp.is_dead:
			continue
		var weapon: Node = child.get_node_or_null("Weapon")
		if weapon and weapon.has_method("server_current_ids"):
			_pending_loadouts[str(child.name).to_int()] = weapon.server_current_ids()

func _server_tick_bomb(delta: float) -> void:
	match _bomb_state:
		BombState.CARRIED:
			if _valid_planter(_bomb_carrier_id) and bool(_holding.get(_bomb_carrier_id, false)):
				_plant_progress += delta
				if _plant_progress >= PLANT_TIME:
					_do_plant()
			else:
				_plant_progress = 0.0
		BombState.DROPPED:
			_try_pickup_dropped()
		BombState.PLANTED:
			_bomb_fuse_left -= delta
			for id in _defender_ids():
				if _valid_defuser(id) and bool(_holding.get(id, false)):
					var prog: float = float(_defuse_progress.get(id, 0.0)) + delta
					_defuse_progress[id] = prog
					if prog >= DEFUSE_TIME:
						_do_defuse()
						return
				else:
					_defuse_progress[id] = 0.0
			if _bomb_fuse_left <= 0.0:
				_do_explode()

func _do_plant() -> void:
	var p := _player_node(_bomb_carrier_id)
	_bomb_state = BombState.PLANTED
	_bomb_fuse_left = BOMB_FUSE
	_bomb_site = _site_of(p) if p else ""
	_bomb_plant_pos = p.global_position if p else Vector3.ZERO
	_plant_progress = 0.0
	economy.award_plant(_bomb_carrier_id)
	_push_credits(_bomb_carrier_id)
	_announce_bomb_event.rpc("bomb_plant", _bomb_plant_pos)

func _do_defuse() -> void:
	_bomb_state = BombState.DEFUSED
	_announce_bomb_event.rpc("bomb_defuse", _bomb_plant_pos)
	end_round(1 - attacking_team())

func _do_explode() -> void:
	_bomb_state = BombState.EXPLODED
	end_round(attacking_team())

## Diffusion dédiée (reliable, non throttlée) des instants pose/désamorçage —
## R-E audio, "bomb_plant"/"bomb_defuse" (`_sync_bomb`, unreliable, sert
## seulement à la progression continue, pas à ces déclencheurs ponctuels).
@rpc("authority", "call_local", "reliable")
func _announce_bomb_event(sound: String, pos: Vector3) -> void:
	_play_sfx_at(sound, pos)

func _try_pickup_dropped() -> void:
	for child in _players():
		if int(child.get("team")) != attacking_team():
			continue
		var hp := child.get_node_or_null("Health") as Health
		if hp and hp.is_dead:
			continue
		if (child as Node3D).global_position.distance_to(_bomb_drop_pos) <= BOMB_PICKUP_RANGE:
			_bomb_carrier_id = str(child.name).to_int()
			_bomb_state = BombState.CARRIED
			return

func _valid_planter(id: int) -> bool:
	if id != _bomb_carrier_id or id < 0 or _bomb_state != BombState.CARRIED:
		return false
	var p := _player_node(id)
	if p == null:
		return false
	var hp := p.get_node_or_null("Health") as Health
	if hp and hp.is_dead:
		return false
	if int(p.get("team")) != attacking_team():
		return false
	return _site_of(p) != ""

func _valid_defuser(id: int) -> bool:
	if _bomb_state != BombState.PLANTED:
		return false
	var p := _player_node(id)
	if p == null:
		return false
	var hp := p.get_node_or_null("Health") as Health
	if hp and hp.is_dead:
		return false
	if int(p.get("team")) == attacking_team():
		return false
	return _site_of(p) == _bomb_site

func _site_of(p: Node3D) -> String:
	if _site_a and _site_a.overlaps_body(p):
		return "A"
	if _site_b and _site_b.overlaps_body(p):
		return "B"
	return ""

func _defender_ids() -> Array:
	var ids: Array = []
	for child in _players():
		if int(child.get("team")) != attacking_team():
			ids.append(str(child.name).to_int())
	return ids

# ======================================================================
#  Réplication de la bombe (serveur -> tous) + envoi client de l'action tenue
# ======================================================================
func _broadcast_bomb() -> void:
	var pos := _bomb_drop_pos
	var carrier := _player_node(_bomb_carrier_id)
	if _bomb_state == BombState.CARRIED and carrier:
		pos = carrier.global_position
	elif _bomb_state == BombState.PLANTED:
		pos = _bomb_plant_pos
	var defuse_ratio := 0.0
	for v in _defuse_progress.values():
		defuse_ratio = maxf(defuse_ratio, float(v) / DEFUSE_TIME)
	var plant_ratio: float = _plant_progress / PLANT_TIME
	_sync_bomb.rpc(_bomb_state, _bomb_site, _bomb_carrier_id, pos, plant_ratio, defuse_ratio, _bomb_fuse_left)

@rpc("authority", "call_local", "unreliable_ordered")
func _sync_bomb(state: int, site: String, carrier_id: int, pos: Vector3, plant_ratio: float, defuse_ratio: float, fuse_left: float) -> void:
	bomb_state = state
	bomb_site = site
	bomb_carrier_id = carrier_id
	bomb_position = pos
	bomb_plant_ratio = plant_ratio
	bomb_defuse_ratio = defuse_ratio
	bomb_fuse_left = fuse_left
	updated.emit()

## Le joueur LOCAL tient-il "pickup" (F) ? Lu depuis son PlayerInput (déjà
## gaté "souris capturée" — voir PlayerInput.gather_from_devices), envoyé au
## serveur à chaque tick (peu coûteux à 8 joueurs, `unreliable_ordered` : un
## paquet perdu se rattrape au suivant, la progression n'avance simplement
## pas ce tick-là).
func _client_report_holding() -> void:
	var arr := get_tree().get_nodes_in_group("local_player")
	if arr.is_empty():
		return
	var me: PlayerController = arr[0]
	var holding: bool = me.input.pickup_held
	if multiplayer.is_server():
		_holding[multiplayer.get_unique_id()] = holding
	else:
		request_hold_action.rpc_id(1, holding)

@rpc("any_peer", "call_remote", "unreliable_ordered")
func request_hold_action(holding: bool) -> void:
	if multiplayer.is_server():
		_holding[multiplayer.get_remote_sender_id()] = holding

## Équivalent de `request_hold_action` pour un BOT : appelé DIRECTEMENT par
## BotBrain (côté serveur, aucun réseau — un bot n'a pas de pair réel à qui
## envoyer une RPC, voir PlayerController.BOT_ID_START).
func bot_set_holding(id: int, holding: bool) -> void:
	if multiplayer.is_server():
		_holding[id] = holding

## SnD : la bombe posée prime (aller désamorcer/défendre) ; sinon converge
## vers un site au hasard (attaquants comme défenseurs — approximation faute
## de connaître la position/le rôle exact du bot appelant).
func bot_goal_for(_team: int) -> Vector3:
	if bomb_state == BombState.PLANTED:
		return bomb_position
	var site: Area3D = _site_a if (randi() % 2 == 0) else _site_b
	if site == null:
		site = _site_b if site == _site_a else _site_a
	return site.global_position if site else Vector3.ZERO
