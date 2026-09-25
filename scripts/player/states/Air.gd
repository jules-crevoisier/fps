## Air — en l'air, modèle CS / Valorant (air-strafe style Source) : on n'ajoute de
## la vitesse que jusqu'à une petite "vitesse souhaitée" dans la direction visée ;
## en tournant la souris tout en strafant, on redresse et on gagne de la vitesse.
## Le momentum est conservé (pas de friction aérienne).
##
## Planeur (Guet, docs/research/10_ammo_kits_input.md §3.3, AGT-06) : câble ICI
## le hook générique `Passive.on_air()` (socle commun, AGT-01) à CHAQUE tick
## aérien -- ne fait rien pour un agent sans Planeur (Passive.on_air est un
## no-op par défaut). Planeur lui-même plafonne `player.velocity.y` et
## neutralise le stun de chute (voir sa docstring) ; le bonus de contrôle
## aérien (+30 %), lui, doit repasser par ICI (Planeur ne peut pas appeler
## `air_control_move` lui-même sans dupliquer l'appel juste en dessous) :
## `Planeur.control_mult()` lit le multiplicateur qu'`on_air` vient de déposer
## en métadonnée sur `player`, neutre (1.0) hors vol plané.
extends PlayerState

const PlaneurScript := preload("res://scripts/agents/passives/Planeur.gd")

func enter(_from: String, _msg: Dictionary = {}) -> void:
	player.set_crouching(false)
	var passive = _agent_passive()
	if passive is PlaneurScript:
		passive.reset_glide_budget(player)

func physics_update(delta: float) -> void:
	player.apply_gravity(delta)
	var passive = _agent_passive()
	if passive:
		passive.on_air(player, delta)
	if player.wish_dir != Vector3.ZERO:
		# 1) air-strafe Source : gagne de la vitesse en tournant la souris + strafe.
		player.accelerate(player.wish_dir, config.air_wishspeed, config.air_accel, delta)
		# 2) contrôle direct : freine / réoriente dans toutes les directions
		# (+30 % pendant le vol plané de Guet -- voir doc de tête).
		var control := config.air_control
		if passive is PlaneurScript:
			control *= PlaneurScript.control_mult(player)
		player.air_control_move(control, delta)

	# Saut bufferisé encore valable via coyote time.
	if player.jump_buffered() and player.can_jump():
		player.do_jump()
		return

	if player.is_on_floor():
		_land()

func _land() -> void:
	player.slide_jumped = false
	# Landing roll au bon timing (dive pressé juste avant l'atterrissage) => roulade
	# qui annule le stun de chute.
	if player.land_roll_buffered():
		player.consume_roll_buffer()
		transition_to("Roll")
		return
	# Atterrir crouch maintenu + assez vite => slide-hop. Glu de Verrou
	# (AGT-08, 2e passage -- vague 28 refusée) : gardé derrière
	# `player.is_jump_locked()`, même raison que Walk.gd/Sprint.gd -- un
	# atterrissage englué ne doit pas enchaîner sur une glissade. Voir
	# tests/agents/test_verrou_kit.gd.
	if config.slide_hop_enabled and player.input.crouch_held \
			and player.horizontal_speed() >= config.slide_min_speed \
			and not player.is_jump_locked():
		transition_to("Slide")
		return
	if player.input_vector == Vector2.ZERO:
		transition_to("Idle")
	elif player.input.walk_held:
		transition_to("Walk")
	else:
		transition_to("Sprint")

## Passif de l'agent de CE joueur (docs/research/10_ammo_kits_input.md §3.5)
## -- accès duck-typé via le nœud sibling "Abilities" (même motif que
## PlayerController._status_effects/is_jump_locked) : `null` si absent (scène
## de test minimale sans nœud "Abilities", agent sans passif...).
func _agent_passive():
	var ctrl := player.get_node_or_null("Abilities")
	if ctrl == null:
		return null
	var agent = ctrl.get("agent")
	if agent == null:
		return null
	return agent.get("passive")
