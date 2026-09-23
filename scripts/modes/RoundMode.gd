## RoundMode.gd
## Base commune aux modes "à manches" (SnD, Duel/Duo) : encapsule un RoundState
## PUR (timers, score de manches, swap de côté, point de manche/overtime) et
## pilote le déroulement SERVEUR (BUY/PREROUND -> LIVE -> POST -> manche
## suivante), répliqué aux clients par RPC. `abilities_enabled`/`buy_phase`
## (hérités de GameMode) sont tenus à jour à chaque changement de phase, et le
## monde (GameWorld, groupe "match") est verrouillé pendant BUY/PREROUND puis
## déverrouillé au passage en LIVE (`net_set_locked`). Les modes concrets
## surchargent les hooks `_on_*` : préparer la manche, décider un timeout, ou
## réagir à un kill (élimination d'équipe).
class_name RoundMode
extends GameMode

@export var rounds_to_win: int = 6
@export var swap_after: int = 5
@export var buy_duration: float = 15.0
@export var round_duration: float = 90.0
@export var post_duration: float = 4.0

## Copie AUTORITAIRE (serveur uniquement). Les clients lisent les copies
## répliquées ci-dessous (`round_phase`, `round_time_left`, `sides_swapped`,
## `team_scores`/`winner` hérités de GameMode).
var round_state: RoundState

## --- Répliqué aux clients (lecture HUD), voir `_sync_round` ---
var round_phase: int = RoundState.Phase.BUY
var round_time_left: float = 0.0
var sides_swapped: bool = false

var _sync_timer: float = 0.0

func _ready() -> void:
	super._ready()
	round_state = RoundState.new(rounds_to_win, swap_after, buy_duration, round_duration, post_duration)
	round_time_left = round_state.time_left
	buy_phase = true
	if multiplayer.is_server():
		call_deferred("_enter_buy_phase")

func _physics_process(delta: float) -> void:
	if not multiplayer.is_server() or winner != -1:
		return
	if round_state.tick(delta):
		_on_round_timeout()
	if round_state.phase == RoundState.Phase.BUY and round_state.time_left <= 0.0:
		_begin_live()
	elif round_state.phase == RoundState.Phase.POST and round_state.time_left <= 0.0 and round_state.winner == -1:
		_begin_new_round()
	winner = round_state.winner
	_sync_timer += delta
	if _sync_timer >= 0.2 or winner != -1:
		_sync_timer = 0.0
		_push_round_state()

## Manche -> LIVE (déverrouille le mouvement, prépare la manche : bombe, armes...).
func _begin_live() -> void:
	round_state.start_live()
	_set_world_locked(false)
	_on_live_start()
	_push_round_state()

## POST -> BUY/PREROUND de la manche suivante (survivants/loadout AVANT le
## respawn qui remet tout le monde en vie, puis verrouille et respawn).
func _begin_new_round() -> void:
	round_state.start_buy()
	_enter_buy_phase()

func _enter_buy_phase() -> void:
	_on_new_round()
	_set_world_locked(true)
	_respawn_all_for_round()
	_after_round_respawn()
	_push_round_state()

## Après le respawn de tous les joueurs (position/vie remises à neuf) : les
## modes concrets peuvent y réappliquer un inventaire (SnD : survivants/pistolet).
func _after_round_respawn() -> void:
	pass

## Nœuds joueurs actuels. Vide si GameWorld (groupe "match") n'existe pas
## encore (ex. tout premier `_ready()`, avant tout spawn).
func _players() -> Array:
	var world := get_tree().get_first_node_in_group("match")
	if world == null:
		return []
	return world.get_node(world.players_root).get_children()

func _player_node(id: int) -> Node3D:
	var world := get_tree().get_first_node_in_group("match")
	if world == null:
		return null
	return world.get_node(world.players_root).get_node_or_null(str(id)) as Node3D

## Joueurs de `team` encore en vie (round en cours). Utilisé par le HUD.
func alive_count(team: int) -> int:
	var n := 0
	for child in _players():
		if int(child.get("team")) != team:
			continue
		var hp := child.get_node_or_null("Health") as Health
		if hp == null or not hp.is_dead:
			n += 1
	return n

## Termine la manche courante au profit de `team` (0/1). Appelé par le mode
## concret (élimination d'équipe, bombe, capture de zone...).
func end_round(team: int) -> void:
	if not multiplayer.is_server() or winner != -1:
		return
	round_state.end_round(team)
	winner = round_state.winner
	_on_round_ended(team)
	_push_round_state()
	_announce_round_result.rpc(team)

## Diffusion dédiée (non throttlée, contrairement à `_sync_round`) du résultat
## de la manche qui vient de se terminer : joue le stinger gagné/perdu côté
## CLIENT selon l'équipe du joueur LOCAL (R-E audio, "round_win"/"round_lose").
@rpc("authority", "call_local", "reliable")
func _announce_round_result(winning_team: int) -> void:
	var local_team := _local_player_team()
	if local_team < 0:
		return
	_play_sfx_ui("round_win" if local_team == winning_team else "round_lose")

## --- Hooks à surcharger (serveur uniquement) ---
func _on_round_timeout() -> void:
	pass

func _on_live_start() -> void:
	pass

func _on_new_round() -> void:
	pass

func _on_round_ended(_winning_team: int) -> void:
	pass

func _build_hud_state() -> String:
	return mode_name

func _push_round_state() -> void:
	buy_phase = round_state.phase == RoundState.Phase.BUY
	team_scores = [float(round_state.wins[0]), float(round_state.wins[1])]
	hud_state = _build_hud_state()
	sync_state.rpc(team_scores, winner, hud_state)
	_sync_round.rpc(round_state.phase, round_state.time_left, round_state.sides_swapped)

@rpc("authority", "call_local", "reliable")
func _sync_round(phase: int, time_left: float, swapped: bool) -> void:
	# Détecte la TRANSITION vers LIVE (pas juste "phase == LIVE", sinon le
	# stinger rejouerait à chaque synchro throttlée pendant toute la manche).
	var entering_live := phase == RoundState.Phase.LIVE and round_phase != RoundState.Phase.LIVE
	round_phase = phase
	round_time_left = time_left
	sides_swapped = swapped
	buy_phase = phase == RoundState.Phase.BUY
	updated.emit()
	if entering_live:
		_play_sfx_ui("round_start")

func _set_world_locked(locked: bool) -> void:
	var world := get_tree().get_first_node_in_group("match")
	if world and world.has_method("set_all_locked"):
		world.set_all_locked(locked)

func _respawn_all_for_round() -> void:
	var world := get_tree().get_first_node_in_group("match")
	if world and world.has_method("respawn_all_for_round"):
		world.respawn_all_for_round()

## SnD/Duel : on attend la prochaine manche, pas de respawn immédiat.
func respawns_immediately() -> bool:
	return false

func is_match_point(team: int) -> bool:
	return round_state.is_match_point(team)

func is_overtime() -> bool:
	return round_state.is_overtime()

func reset_match() -> void:
	if not multiplayer.is_server():
		return
	round_state.reset()
	winner = -1
	_enter_buy_phase()

## Équipe qui attaque (0 par défaut, 1 après l'échange de côté). SnD/Duel s'en
## servent pour savoir qui pose la bombe / qui a l'avantage nominal.
func attacking_team() -> int:
	return 1 if sides_swapped else 0

## Tous les joueurs d'une équipe (round en cours) sont-ils morts ? Faux s'il
## n'y a personne dans cette équipe (évite une fin de manche sur déconnexion).
func _team_all_dead(team: int) -> bool:
	var found := false
	for child in _players():
		if int(child.get("team")) != team:
			continue
		found = true
		var hp := child.get_node_or_null("Health") as Health
		if hp == null or not hp.is_dead:
			return false
	return found
