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
## Site retenu pour TOUTE la manche (contrat BOT-01 : "site choisi une fois
## par round par équipe" — plus de tirage A/B à CHAQUE appel de `bot_goal_for`,
## qui faisait osciller les bots entre les deux sites). Choisi par
## `_pick_round_site` au début de chaque manche (`_on_new_round`), partagé par
## attaquants ET défenseurs (défendre là où la bombe va être posée est la
## lecture tactique la plus simple ; la pondération par danger et les rôles
## par bot sont BOT-08, hors périmètre ici).
var _round_site: Area3D

# ---- Autorité SERVEUR uniquement ----
var _bomb_state: int = BombState.CARRIED
var _bomb_site: String = ""
var _bomb_carrier_id: int = -1
var _bomb_drop_pos: Vector3 = Vector3.ZERO
var _bomb_plant_pos: Vector3 = Vector3.ZERO  ## Position exacte de la pose (affichage + son "bomb_beep").
## Dernière position CONNUE du porteur (mise à jour à chaque tick tant qu'il
## existe, voir `_server_tick_bomb`/`_assign_carrier`) : sert à lâcher la bombe
## là où il se trouvait si son nœud disparaît (déconnexion en LIVE, BUG-10),
## puisqu'à cet instant `_player_node(_bomb_carrier_id)` ne renvoie déjà plus rien.
var _bomb_carrier_last_pos: Vector3 = Vector3.ZERO
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
	_pick_round_site()
	_invalidate_bot_goals()  # évènement BOT-01 : nouvelle manche.

## Tire le site de la manche UNE SEULE FOIS (contrat BOT-01) — jamais à
## chaque appel de `_compute_bot_goal`. Repli sur l'unique site existant si un
## seul est câblé (ex. scène de test).
func _pick_round_site() -> void:
	if _site_a == null:
		_round_site = _site_b
	elif _site_b == null:
		_round_site = _site_a
	else:
		_round_site = _site_a if (randi() % 2 == 0) else _site_b

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
	elif id < PlayerController.BOT_ID_START:
		_receive_credits.rpc_id(id, economy.get_credits(id))
	# BOT (id >= PlayerController.BOT_ID_START) : simulé ICI, sur le SERVEUR —
	# aucun pair réel derrière cet id, un `rpc_id` échouerait ("Attempt to
	# call RPC with unknown peer ID"), comme documenté partout ailleurs dans
	# le jeu pour ce même motif (Weapon.gd._push_server_sync,
	# AbilityController.gd._push_state) : appel DIRECT côté serveur au lieu
	# du réseau. Ici, la fonction locale équivalente n'a RIEN de plus à faire
	# que ce qui est déjà fait : `my_credits` ne représente QUE le HUD du
	# joueur humain LOCAL de cette machine (jamais un bot, qui n'a pas de HUD
	# — voir PlayerController.is_local_human) et écraser `my_credits` avec le
	# solde du bot corromprait l'affichage de l'hôte-joueur s'il est en train
	# de jouer ; `economy.credits[id]`, déjà à jour à cet instant, reste
	# l'unique source de vérité qui concerne un bot.

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
	_invalidate_bot_goals()  # évènement BOT-01 : un kill peut rendre un but obsolète.
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
	_bomb_carrier_last_pos = Vector3.ZERO
	_bomb_fuse_left = BOMB_FUSE
	_plant_progress = 0.0
	_defuse_progress.clear()
	_holding.clear()

## Choisit un porteur parmi les attaquants PRÉSENTS (`_players()`). Peut ne
## trouver personne si les attaquants n'ont pas fini d'apparaître (spawn
## asynchrone après connexion) — laisse alors `_bomb_carrier_id == -1`,
## rattrapé par `_on_live_start` (BUG-10 : "porteur attribué au début du live
## si absent").
func _assign_carrier() -> void:
	var attackers: Array = []
	for child in _players():
		if int(child.get("team")) == attacking_team():
			attackers.append(str(child.name).to_int())
	if not attackers.is_empty():
		_bomb_carrier_id = attackers[randi() % attackers.size()]
		_bomb_state = BombState.CARRIED
		var p := _player_node(_bomb_carrier_id)
		if p:
			_bomb_carrier_last_pos = p.global_position

## BUG-10 : `_assign_carrier` (appelé à l'entrée en BUY, voir `_on_new_round`)
## peut n'avoir trouvé aucun attaquant encore présent, OU le porteur choisi
## peut s'être déconnecté PENDANT la phase d'achat (la bombe n'est tickée
## qu'en LIVE — voir `_physics_process` — rien ne l'aurait détecté avant).
## Retente l'attribution une fois le monde déverrouillé si le porteur actuel
## n'est toujours pas un joueur VALIDE.
func _on_live_start() -> void:
	if _bomb_carrier_id == -1 or _player_node(_bomb_carrier_id) == null:
		_assign_carrier()

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
	_purge_absent_defuse_progress()
	match _bomb_state:
		BombState.CARRIED:
			var carrier := _player_node(_bomb_carrier_id)
			if carrier == null:
				# Porteur disparu (déconnexion en LIVE, BUG-10) : la bombe tombe
				# DROPPED à sa DERNIÈRE position connue — sinon elle restait
				# "portée" par un id fantôme, plus jamais ramassable ni posable.
				_bomb_drop_pos = _bomb_carrier_last_pos
				_bomb_state = BombState.DROPPED
				_bomb_carrier_id = -1
				_plant_progress = 0.0
			else:
				_bomb_carrier_last_pos = carrier.global_position
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
						_do_defuse(id)
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
	# §3.4 (AGT-02) : bonus fixe d'ultime au poseur, qui remplace le gain
	# continu (coupé en mode à manches par AbilityController._sync_ult_charge_rate).
	_charge_ult_for_objective(_bomb_carrier_id)
	_invalidate_bot_goals()  # évènement BOT-01 : "bombe posée".
	_announce_bomb_event.rpc("bomb_plant", _bomb_plant_pos)

## `defuser_id` : le défenseur DONT la progression vient d'atteindre
## DEFUSE_TIME (voir l'appelant dans `_server_tick_bomb`) -- seul destinataire
## du bonus d'ultime ci-dessous (§3.4, AGT-02) : les autres défenseurs présents
## n'ont pas eux-mêmes désamorcé.
func _do_defuse(defuser_id: int) -> void:
	_bomb_state = BombState.DEFUSED
	_announce_bomb_event.rpc("bomb_defuse", _bomb_plant_pos)
	_charge_ult_for_objective(defuser_id)
	end_round(1 - attacking_team())

## Point d'entrée commun pose/désamorçage (§3.4, AGT-02) : relaie vers
## GameWorld.charge_ult_for_objective (groupe "match", GameWorld.gd hors de la
## liste de fichiers de cette tâche), +1 pt d'ultime fixe pour `player_id` --
## même motif que `_set_world_locked`/`_respawn_all_for_round` de RoundMode.gd
## (`has_method`, jamais un cast dur : GameWorld peut être absent d'une scène
## de test minimale, voir tests/modes/test_snd_bot_credits.gd). Sans effet
## silencieux si "match" n'existe pas encore, ou si le mode continu (arène)
## n'a jamais coupé le gain -- `charge_ult_for_objective` se garde lui-même
## côté SERVEUR (voir sa doc, GameWorld.gd).
func _charge_ult_for_objective(player_id: int) -> void:
	var world := get_tree().get_first_node_in_group("match")
	if world and world.has_method("charge_ult_for_objective"):
		world.charge_ult_for_objective(player_id)

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

## Ne garde dans `_defuse_progress` que les ids de joueurs ENCORE présents
## (`_players()`) : sans ce filtre, la progression d'un défenseur qui se
## déconnecte pendant qu'il désamorce y restait pour toujours et continuait à
## alimenter `bomb_defuse_ratio` (`_broadcast_bomb` fait le MAX de TOUTES les
## valeurs du dictionnaire, absent ou pas) — la barre de désamorçage restait
## affichée à tous après son départ (BUG-10, "progression fantôme").
func _purge_absent_defuse_progress() -> void:
	if _defuse_progress.is_empty():
		return
	var present: Array = []
	for child in _players():
		present.append(str(child.name).to_int())
	for id in _defuse_progress.keys().duplicate():
		if not present.has(id):
			_defuse_progress.erase(id)

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

## SnD : la bombe posée prime (aller désamorcer/défendre — `bomb_position` est
## l'état RÉPLIQUÉ de l'objectif, pas une position ennemie) ; sinon le site
## retenu UNE FOIS pour toute la manche par `_pick_round_site` (contrat
## BOT-01 : "site choisi une fois par round par équipe" — plus le tirage A/B
## par appel qui faisait osciller les bots entre les deux sites).
func _compute_bot_goal(_team: int, _bot_id: int, _bot_pos: Vector3, _reached: bool = false) -> Vector3:
	if bomb_state == BombState.PLANTED:
		return bomb_position
	return _round_site.global_position if _round_site else Vector3.ZERO
