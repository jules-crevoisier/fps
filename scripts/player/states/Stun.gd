## Stun — étourdissement cartoon après une grosse chute (pas de dégâts).
## Le déplacement est figé sur place (aucun saut/slide/dive, simple friction
## au sol) et des étoiles tournent au-dessus de la tête, MAIS ce n'est plus un
## freeze total (MV-03, adouci — docs/research/01_game_feel.md #16) : le
## joueur garde la main sur la visée (la rotation caméra n'est de toute façon
## jamais lue par cet état, voir PlayerController) et sur le tir, avec une
## dispersion additionnelle `config.stun_fire_spread_add` plutôt qu'un
## blocage complet — ce dernier volet dépend de `Weapon._can_act()` et de
## `WeaponFeel.total_spread_deg`, hors de ma liste de fichiers pour cette
## tâche (blocage signalé au lead). La durée (reçue dans `msg.duration`)
## dépend de la hauteur de chute et du mode courant (`GameMode.
## fall_stun_enabled`, désactivé en Duel/Duo/SnD : PlayerController ne
## déclenche alors jamais cet état).
extends PlayerState

var _timer: float = 0.0
var _duration: float = 1.0

func enter(_from: String, msg: Dictionary = {}) -> void:
	_duration = msg.get("duration", config.stun_min_time)
	_timer = 0.0
	player.set_crouching(false)
	if player.stun_stars and player.stun_stars.has_method("show_stars"):
		player.stun_stars.show_stars()

func exit() -> void:
	if player.stun_stars and player.stun_stars.has_method("hide_stars"):
		player.stun_stars.hide_stars()

func physics_update(delta: float) -> void:
	_timer += delta
	player.apply_gravity(delta)
	player.apply_friction(config.ground_friction, delta)  # figé sur place

	# Aucune action possible pendant le stun (saut/slide/dive ignorés).
	if _timer >= _duration:
		_recover()

func _recover() -> void:
	# Plafond bas au-dessus de la tête => s'accroupir plutôt que de se relever
	# dans le décor (BUG-08) ; Crouch relèvera dès que ce sera dégagé.
	if player.is_blocked_above():
		transition_to("Crouch")
		return
	if player.input_vector == Vector2.ZERO:
		transition_to("Idle")
	elif player.input.walk_held:
		transition_to("Walk")
	else:
		transition_to("Sprint")
