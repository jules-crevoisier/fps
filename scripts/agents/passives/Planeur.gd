## Planeur.gd
## Passif de Guet (docs/research/10_ammo_kits_input.md §3.3, "Planeur" -- "ses
## pans de queue-de-pie font office d'ailes") : MAINTENIR Saut en l'air
## plafonne la chute et améliore le contrôle aérien, sans jamais étourdir à
## l'atterrissage tant que le vol plané reste actif jusqu'au sol. Toute la
## mécanique est appliquée ICI, appelée à CHAQUE tick aérien par
## `scripts/player/states/Air.gd::physics_update` via le hook générique
## `Passive.on_air` (socle commun, AGT-01) -- Air.gd ne fait ensuite QUE lire
## `control_mult()` en retour pour moduler SA seule invocation de
## `air_control_move` (bonus de contrôle aérien, +30 %, voir sa docstring).
##
## Aucun `class_name` (comme les capacités concrètes -- ex. FlashAbility.gd --
## et comme BaumeAuRepos.gd, le passif sœur de Roseau) -> preload explicite
## côté appelants (Air.gd, tests/agents/test_guet_kit.gd).
##
## État PAR JOUEUR (jamais un champ de cette classe : `AgentConfig.passive`
## peut être PARTAGÉ par plusieurs Guet à la fois -- un seul `AgentConfig` par
## agent dans AgentDatabase, pas par joueur) : porté en métadonnée sur
## `player`, même motif que `AbilityController.net_apply_flash` ->
## "blinded_until" pour un bot.
extends Passive

## Vitesse de chute plafonnée UNE FOIS le vol plané actif (m/s, positif --
## comparée à `-velocity.y`).
@export var max_fall_speed: float = 2.5
## Budget de vol plané (s) -- consommé tant que Saut est tenu en l'air, remis
## à fond à CHAQUE nouvelle entrée dans "Air" (`reset_glide_budget`, "recharge
## au sol").
@export var glide_duration: float = 2.0
## Bonus MULTIPLICATIF de contrôle aérien pendant le vol plané (+30 %).
@export var air_control_bonus: float = 0.3

const _META_TIME_LEFT := "planeur_glide_time_left"
const _META_CONTROL_MULT := "planeur_air_control_mult"

func _init() -> void:
	display_name = "Planeur"
	description = "Maintenir Saut en l'air plafonne la chute (2,5 m/s max, 2 s) et améliore le contrôle aérien ; pas d'étourdissement de chute tant qu'il plane."

## Appelé CHAQUE tick physique tant que `player` est en l'air (Passive.on_air,
## câblé par Air.gd). Sans effet si Saut n'est pas tenu ou si le budget de vol
## est épuisé : la chute redevient alors normale (vitesse non plafonnée, stun
## de nouveau possible si la suite de la chute est assez haute -- "2 s max").
func on_air(player: PlayerController, delta: float) -> void:
	if player == null or player.input == null:
		return
	if not player.input.jump_held:
		player.set_meta(_META_CONTROL_MULT, 1.0)
		return
	var left: float = player.get_meta(_META_TIME_LEFT, glide_duration)
	if left <= 0.0:
		player.set_meta(_META_CONTROL_MULT, 1.0)
		return
	player.set_meta(_META_TIME_LEFT, maxf(left - delta, 0.0))
	if player.velocity.y < -max_fall_speed:
		player.velocity.y = -max_fall_speed
	# Neutralise PlayerController._check_fall_stun() (hors du périmètre de ce
	# contrat -- jamais modifié directement) : sa hauteur de chute se mesure
	# depuis `_air_peak_y` ("altitude max atteinte en l'air") jusqu'à
	# l'atterrissage. En le recollant à l'altitude COURANTE à CHAQUE tick
	# plané, la hauteur mesurée à l'atterrissage ne peut plus dépasser la
	# chute d'UN SEUL tick (très en dessous de `fall_min_height`) tant que le
	# vol plané reste actif jusqu'au sol.
	player._air_peak_y = player.global_position.y
	player.set_meta(_META_CONTROL_MULT, 1.0 + air_control_bonus)

## "Recharge au sol" : remet le budget de vol plané à fond -- appelé par
## Air.gd::enter() à CHAQUE nouvelle entrée dans l'état "Air", quel que soit
## ce qu'il restait avant.
func reset_glide_budget(player: PlayerController) -> void:
	if player:
		player.set_meta(_META_TIME_LEFT, glide_duration)

## Multiplicateur de contrôle aérien COURANT (1.0 hors vol plané) -- lu par
## Air.gd juste après avoir appelé `on_air` ci-dessus, pour moduler SA seule
## invocation de `air_control_move` (jamais un second appel ici : la
## responsabilité du mouvement reste entièrement dans Air.gd).
static func control_mult(player: PlayerController) -> float:
	if player == null:
		return 1.0
	return float(player.get_meta(_META_CONTROL_MULT, 1.0))

## Budget de vol plané restant (s) -- exposé pour les tests
## (tests/agents/test_guet_kit.gd) ; jamais réutilisé en jeu (Air.gd n'a
## besoin QUE de `control_mult` ci-dessus).
static func glide_time_left(player: PlayerController) -> float:
	if player == null:
		return 0.0
	return float(player.get_meta(_META_TIME_LEFT, 0.0))
