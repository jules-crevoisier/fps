## DuelMode.gd
## Duel 1v1 / Duo 2v2 façon Gunfight (CoD) : première équipe à 6 manches,
## manche de 40 s, préround 3 s (BUY réutilisé comme préparation, sans achat —
## voir `server_try_purchase`), pas d'échange de camp, pas de capacités
## (`abilities_enabled = false`), pas de régénération pendant la manche
## (`Health.regen_enabled = false`). Équipement IMPOSÉ et IDENTIQUE aux deux
## équipes, qui tourne toutes les 2 manches (cycle sur tout `WeaponDatabase`,
## sans nom en dur : reste valide si R-B2 ajoute des armes). Si le temps d'une
## manche s'écoule sans élimination totale, une zone de capture centrale
## s'active : 3 s tenue sans contestation gagnent la manche.
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

var _capture_zone: Area3D
var _capture_active: bool = false
var _capture_team: int = -1
var _capture_progress: float = 0.0

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

## Élimination totale d'une équipe -> victoire immédiate de l'autre.
func on_kill(_killer_id: int, _victim_id: int, killer_team: int, victim_team: int) -> void:
	if not multiplayer.is_server() or winner != -1 or round_state.phase != RoundState.Phase.LIVE:
		return
	if killer_team < 0 or killer_team == victim_team:
		return
	if _team_all_dead(victim_team):
		end_round(killer_team)

# ======================================================================
#  Zone de capture (après le chrono de la manche)
# ======================================================================
func _tick_capture(delta: float) -> void:
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

# ======================================================================
#  Équipement imposé, identique, tournant toutes les 2 manches
# ======================================================================
## Duel/Duo : la zone de capture si elle est active (fin de manche sans
## élimination), sinon un ennemi vivant au hasard (petit effectif, 1 ou 2 par
## équipe — approximation raisonnable faute de connaître le bot appelant).
func bot_goal_for(team: int) -> Vector3:
	if _capture_active and _capture_zone:
		return _capture_zone.global_position
	var enemies := _team_player_positions(1 - team)
	if enemies.is_empty():
		return Vector3.ZERO
	return enemies[randi() % enemies.size()]

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
