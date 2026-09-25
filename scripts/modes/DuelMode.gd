## DuelMode.gd
## Duel 1v1 / Duo 2v2 façon Gunfight (CoD) : première équipe à 6 manches,
## manche de 40 s, préround 3 s (BUY réutilisé comme préparation, sans achat —
## voir `server_try_purchase`), pas d'échange de camp, pas de capacités
## (`abilities_enabled = false`), pas de régénération pendant la manche
## (`Health.regen_enabled = false`). Équipement IMPOSÉ et IDENTIQUE aux deux
## équipes, qui tourne toutes les 2 manches (cycle sur tout `WeaponDatabase`,
## sans nom en dur : reste valide si R-B2 ajoute des armes). Si le temps d'une
## manche s'écoule sans élimination totale, une zone de capture centrale
## s'active : 3 s tenue sans contestation gagnent la manche. La manche ne doit
## JAMAIS rester bloquée en impasse sur cette zone (BUG-12, docs/audit/bugs.md) :
## 45 s après l'activation sans capture -> mort subite (le PROCHAIN kill décide,
## même sans élimination totale de l'équipe adverse) ; 20 s de plus (65 s au
## total) sans vainqueur -> décision forcée à la somme des PV restants de
## chaque équipe (égalité -> victoire des défenseurs, `attacking_team()`).
class_name DuelMode
extends RoundMode

## DÉPRÉCIÉ (contract-r3.md, R3-IN#5 : "DuelMode reads MatchConfig.team_size
## instead of its old static") — `_ready()` lit désormais MatchConfig.team_size.
## Gardé pour compatibilité tant que MainMenu.gd (R3-UI) écrit encore ici ;
## R3-UI doit migrer vers `MatchConfig.team_size` puis ce champ pourra être
## retiré.
static var requested_team_size: int = 1

@export var capture_zone_path: NodePath
@export var capture_hold_time: float = 3.0

var team_size: int = 1

## BUG-12 : garantie de fin de manche en impasse sur la zone de capture — voir
## la doc d'en-tête. Délais mesurés depuis l'ACTIVATION de la zone
## (`_on_round_timeout`), pas depuis un début de contestation.
const STALEMATE_SUDDEN_DEATH_DELAY := 45.0
const STALEMATE_FORCED_DECISION_DELAY := 20.0

var _capture_zone: Area3D
var _capture_active: bool = false
var _capture_team: int = -1
var _capture_progress: float = 0.0
## Temps écoulé depuis l'activation de la zone (remis à zéro à chaque nouvelle
## manche / activation, voir `_on_new_round`/`_on_round_timeout`).
var _capture_active_elapsed: float = 0.0
## VRAI passé `STALEMATE_SUDDEN_DEATH_DELAY` : le PROCHAIN kill décide la
## manche dans `on_kill`, même sans élimination totale de l'équipe adverse.
var _stalemate_sudden_death: bool = false

## Valeurs par défaut du Duel (RoundState) : pas d'échange de camp, préround
## 3 s, manche 40 s, POST 3 s. GDScript interdit de redéclarer un @export
## hérité (RoundMode.swap_after/buy_duration/round_duration/post_duration,
## pensés pour SnD) : on change juste la valeur par défaut ici, avant
## qu'une éventuelle valeur de scène ne l'écrase.
func _init() -> void:
	swap_after = 0
	buy_duration = 3.0
	round_duration = 40.0
	post_duration = 3.0

func _ready() -> void:
	super._ready()
	team_size = clampi(MatchConfig.team_size, 1, 2)
	abilities_enabled = false
	mode_name = "Duo 2v2" if team_size == 2 else "Duel 1v1"
	_capture_zone = get_node_or_null(capture_zone_path) as Area3D

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if not multiplayer.is_server() or winner != -1:
		return
	if round_state.phase == RoundState.Phase.LIVE and _capture_active:
		_tick_capture(delta)

# ======================================================================
#  Manche : préparation / fin / timeout -> zone de capture
# ======================================================================
func _on_new_round() -> void:
	_capture_active = false
	_capture_team = -1
	_capture_progress = 0.0
	_capture_active_elapsed = 0.0
	_stalemate_sudden_death = false
	_invalidate_bot_goals()  # évènement BOT-01 : nouvelle manche.

func _after_round_respawn() -> void:
	var ids := _rotation_ids()
	for child in _players():
		var hp := child.get_node_or_null("Health") as Health
		if hp:
			hp.regen_enabled = false  # pas de régénération en Duel/Duo
		var weapon: Node = child.get_node_or_null("Weapon")
		if weapon and weapon.has_method("server_set_loadout") and not ids.is_empty():
			weapon.server_set_loadout(ids)

## Le temps de la manche (40 s) s'écoule sans élimination totale : la zone de
## capture centrale devient active (jusqu'à la fin de la manche).
func _on_round_timeout() -> void:
	_capture_active = true
	_capture_team = -1
	_capture_progress = 0.0
	_capture_active_elapsed = 0.0
	_stalemate_sudden_death = false
	_invalidate_bot_goals()  # évènement BOT-01 : la zone de capture s'active.

func _build_hud_state() -> String:
	match round_state.phase:
		RoundState.Phase.BUY:
			return "Préparation — %ds" % int(ceil(round_state.time_left))
		RoundState.Phase.LIVE:
			if _capture_active:
				return "ZONE DE CAPTURE ACTIVE"
			return "Manche en cours — %ds" % int(ceil(round_state.time_left))
	return "Manche terminée"

## Duel/Duo : équipement imposé, pas de boutique.
func server_try_purchase(_peer_id: int, _weapon_id: int) -> bool:
	return false

## Élimination totale d'une équipe -> victoire immédiate de l'autre. Passé la
## mort subite de l'impasse sur la zone (BUG-12), le PROCHAIN kill décide même
## sans élimination totale (sinon un Duo 2v2 pourrait rester bloqué si les deux
## équipes gardent un survivant hors de la zone).
func on_kill(_killer_id: int, _victim_id: int, killer_team: int, victim_team: int) -> void:
	if not multiplayer.is_server() or winner != -1 or round_state.phase != RoundState.Phase.LIVE:
		return
	if killer_team < 0 or killer_team == victim_team:
		return
	_invalidate_bot_goals()  # évènement BOT-01 : un kill peut rendre un but obsolète.
	if _stalemate_sudden_death or _team_all_dead(victim_team):
		end_round(killer_team)

# ======================================================================
#  Zone de capture (après le chrono de la manche)
# ======================================================================
func _tick_capture(delta: float) -> void:
	_capture_active_elapsed += delta
	if not _stalemate_sudden_death and _capture_active_elapsed >= STALEMATE_SUDDEN_DEATH_DELAY:
		_stalemate_sudden_death = true
	if _capture_active_elapsed >= STALEMATE_SUDDEN_DEATH_DELAY + STALEMATE_FORCED_DECISION_DELAY:
		_force_stalemate_decision()
		return
	if _capture_zone == null:
		return
	var present := {}
	for b in _capture_zone.get_overlapping_bodies():
		if b is PlayerController:
			var hp := b.get_node_or_null("Health") as Health
			if hp and hp.is_dead:
				continue
			present[int(b.team)] = true
	if present.size() == 1:
		var team: int = present.keys()[0]
		if team != _capture_team:
			_capture_team = team
			_capture_progress = 0.0
		_capture_progress += delta
		if _capture_progress >= capture_hold_time:
			end_round(team)
	else:
		_capture_team = -1
		_capture_progress = 0.0

## BUG-12 : 65 s (45 + 20) après l'activation de la zone, toujours aucun
## vainqueur (personne n'a tenu la zone seul, aucun kill depuis la mort
## subite) -> décision forcée à la somme des PV restants (`Health.
## current_health`, déjà à 0 pour un joueur mort) de chaque équipe. Égalité ->
## victoire des défenseurs (`attacking_team()`, même convention que SnD).
func _force_stalemate_decision() -> void:
	var sums := [0.0, 0.0]
	for child in _players():
		var team: int = int(child.get("team"))
		if team < 0 or team > 1:
			continue
		var hp := child.get_node_or_null("Health") as Health
		if hp:
			sums[team] += hp.current_health
	if absf(sums[0] - sums[1]) < 0.001:
		end_round(1 - attacking_team())
	else:
		end_round(0 if sums[0] > sums[1] else 1)

# ======================================================================
#  Équipement imposé, identique, tournant toutes les 2 manches
# ======================================================================
## Duel/Duo : la zone de capture si elle est active (fin de manche sans
## élimination) ; sinon la dernière position ennemie repérée PAR L'ÉQUIPE
## (mémoire partagée, jamais l'état serveur brut — contrat BOT-01) ou, à
## défaut, un point de patrouille de la carte. Petit effectif (1 ou 2 par
## équipe) : mêmes règles de non-omniscience que TDM, voir TDMMode.
## _compute_bot_goal.
func _compute_bot_goal(team: int, bot_id: int, bot_pos: Vector3, reached: bool = false) -> Vector3:
	if _capture_active and _capture_zone:
		return _capture_zone.global_position
	var seen := _shared_last_seen_enemy(team)
	if seen != Vector3.INF:
		return seen
	return _pick_patrol_point(bot_id, bot_pos, reached)

func _rotation_ids() -> Array[int]:
	var all := WeaponDatabase.all()
	var ids: Array[int] = []
	if all.is_empty():
		return ids
	var idx := (round_state.rounds_played / 2) % all.size()
	var id := WeaponDatabase.id_of(all[idx])
	if id >= 0:
		ids.append(id)
	return ids
