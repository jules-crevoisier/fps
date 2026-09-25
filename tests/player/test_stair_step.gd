## test_stair_step.gd
## Spec (MV-01, tasks/backlog.yaml) : step-up / step-down via
## `PhysicsServer3D.body_test_motion()` (scripts/player/StairStep.gd), câblé
## dans PlayerController._physics_process AUTOUR de son move_and_slide() du
## tick (StairStep.try_step_up AVANT, StairStep.try_step_down APRÈS).
## Critères d'acceptation exacts :
##  - max_step_up 0.4 m, max_step_down 0.4 m (MovementConfig) ;
##  - en sprint contre une marche de 0.3 m -> montée SANS perte de vitesse > 10 % ;
##  - marche de 0.5 m -> bloque ;
##  - descente d'escalier sans jamais passer en état "Air" ;
##  - la tête (caméra) lisse le saut vertical sur ~80 ms ;
##  - fonctionne aussi pour les bots (même contrôleur : tous les tests ci-
##    dessous utilisent des instances BOT de scenes/player/player.tscn, comme
##    tests/player/test_state_exits.gd et tests/player/test_respawn_state_reset.gd
##    — la même PlayerController._physics_process tourne pour un bot ou pour
##    l'hôte-joueur, il n'y a qu'UN SEUL chemin de code à vérifier).
##
## Deux niveaux de test :
##  - unitaire, direct sur `StairStep` (CharacterBody3D minimal + un décor
##    StaticBody3D), rapide et précis, sans dépendre du reste du contrôleur ;
##  - intégration, sur une instance RÉELLE de scenes/player/player.tscn
##    (même méthode que tests/player/test_state_exits.gd), pour vérifier le
##    câblage dans PlayerController._physics_process et le ressenti "en jeu"
##    (vitesse conservée en sprint, jamais d'état Air en descente).
extends GdUnitTestSuite

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const DT := 1.0 / 60.0

var _next_offset_index := 0


func _offset() -> Vector3:
	var o := Vector3(float(_next_offset_index) * 60.0, 0.0, 0.0)
	_next_offset_index += 1
	return o


## Sol de décor (StaticBody3D, calque WORLD) dont la surface haute est
## exactement à `top.y` — même construction que
## tests/player/test_state_exits.gd::_floor.
func _floor(top: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = PhysicsLayers.WORLD
	body.collision_mask = 0
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)
	body.position = top - Vector3(0, size.y * 0.5, 0)
	add_child(body)
	auto_free(body)
	return body


## Construit un sol bas (dessus à `o.y`, x dans [o.x - 8 ; o.x]) et une marche
## haute (dessus à `o.y + step_height`, x dans [o.x ; o.x + 8]), avec un mur
## plein sous la marche haute (assez épais pour descendre bien sous le sol
## bas : jamais de vide, toujours un mur franc à x = o.x) — le bord de la
## marche est donc exactement à x = o.x.
func _step_up_scene(o: Vector3, step_height: float) -> void:
	_floor(o + Vector3(-4.0, 0.0, 0.0), Vector3(8, 1, 4))
	_floor(o + Vector3(4.0, step_height, 0.0), Vector3(8, 6.0, 4))


## Deux sols adjacents à des hauteurs différentes (bord à x = o.x) : haut à
## `o.y`, bas à `o.y - step_height` — pour tester la DESCENTE (aucun mur
## nécessaire ici, juste un vide franc entre les deux hauteurs).
func _step_down_scene(o: Vector3, step_height: float) -> void:
	_floor(o + Vector3(-4.0, 0.0, 0.0), Vector3(8, 1, 4))
	# Sol bas nettement plus large (30 m) que le sol haut : un bot qui sprinte
	# (8.2 m/s) sur les ~240 ticks (4 s) d'une boucle d'intégration parcourt
	# largement plus que les 8 m d'un tread "normal" — sans cette largeur, il
	# retomberait dans le vide de l'AUTRE côté (bord de map involontaire) et
	# fausserait un test qui ne s'intéresse qu'au franchissement de LA marche.
	_floor(o + Vector3(30.0, -step_height, 0.0), Vector3(60, 1, 4))


## CharacterBody3D minimal (capsule seule) pour tester StairStep en isolation,
## sans dépendre de scenes/player/player.tscn.
func _simple_body(pos: Vector3, radius: float = 0.4, height: float = 1.8) -> CharacterBody3D:
	var body := CharacterBody3D.new()
	body.collision_layer = PhysicsLayers.WORLD
	body.collision_mask = PhysicsLayers.WORLD
	var col := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = radius
	shape.height = height
	col.shape = shape
	col.position.y = height * 0.5
	body.add_child(col)
	body.position = pos
	add_child(body)
	auto_free(body)
	return body


## Instance réelle du joueur, spawnée comme un BOT (autorité SERVEUR — voir
## PlayerController._enter_tree), même méthode que
## tests/player/test_state_exits.gd::_bot_player.
func _bot_player(pos: Vector3) -> PlayerController:
	var player: PlayerController = PLAYER_SCENE.instantiate()
	player.name = str(PlayerController.BOT_ID_START + _next_offset_index)
	player.set("is_bot", true)
	player.position = pos
	player.set("spawn_point", pos)
	add_child(player)
	auto_free(player)
	return player


# ============================================================ MovementConfig

func test_movement_config_default_step_heights_are_040_meters() -> void:
	var config := MovementConfig.new()
	assert_float(config.max_step_up).append_failure_message(
		"max_step_up par défaut doit être 0.4 m (critère d'acceptation MV-01)"
	).is_equal_approx(0.4, 0.001)
	assert_float(config.max_step_down).append_failure_message(
		"max_step_down par défaut doit être 0.4 m (critère d'acceptation MV-01)"
	).is_equal_approx(0.4, 0.001)


# ================================================== StairStep.try_step_up (unitaire)

func test_try_step_up_climbs_a_030m_step_moving_only_y_never_touching_velocity() -> void:
	var o := _offset()
	_step_up_scene(o, 0.3)
	# Départ à -0.8 (>> rayon de capsule 0.4) : la capsule ne touche/ne
	# recouvre PAS encore le mur au départ (sinon body_test_motion part d'un
	# état déjà en pénétration et sa phase de récupération fausse tout).
	var body := _simple_body(o + Vector3(-0.8, 0.0, 0.0))
	await get_tree().physics_frame
	await get_tree().physics_frame
	body.velocity = Vector3(0, -1, 0)
	body.move_and_slide()
	assert_bool(body.is_on_floor()).append_failure_message(
		"préalable du test : le corps doit démarrer détecté au sol"
	).is_true()

	var velocity_before := body.velocity
	var dy := StairStep.try_step_up(body, Vector3(0.5, 0.0, 0.0), 0.4, 0.4)

	assert_float(dy).append_failure_message(
		"delta Y renvoyé = %.3f, attendu ~0.3 m (hauteur de la marche)" % dy
	).is_equal_approx(0.3, 0.03)
	assert_float(body.global_position.y).append_failure_message(
		"le corps doit être remonté au sommet de la marche (0.3 m au-dessus du sol bas)"
	).is_equal_approx(o.y + 0.3, 0.03)
	assert_vector(body.velocity).append_failure_message(
		"try_step_up ne doit JAMAIS toucher à la vélocité — seule la position Y change"
	).is_equal(velocity_before)


func test_try_step_up_blocks_on_a_050m_step_too_high() -> void:
	var o := _offset()
	_step_up_scene(o, 0.5)
	var body := _simple_body(o + Vector3(-0.8, 0.0, 0.0))
	await get_tree().physics_frame
	await get_tree().physics_frame
	body.velocity = Vector3(0, -1, 0)
	body.move_and_slide()
	assert_bool(body.is_on_floor()).is_true()

	var pos_before := body.global_position
	var dy := StairStep.try_step_up(body, Vector3(0.5, 0.0, 0.0), 0.4, 0.4)

	assert_float(dy).append_failure_message(
		"une marche de 0.5 m dépasse max_step_up (0.4 m) : aucun step ne doit être appliqué (obtenu %.3f)" % dy
	).is_equal(0.0)
	assert_vector(body.global_position).append_failure_message(
		"la position ne doit pas bouger quand la marche est trop haute (move_and_slide la traitera comme un mur)"
	).is_equal(pos_before)


func test_try_step_up_does_nothing_when_body_was_not_on_floor() -> void:
	var o := _offset()
	_step_up_scene(o, 0.3)
	var body := _simple_body(o + Vector3(-0.1, 3.0, 0.0))  # en l'air, loin du sol
	await get_tree().physics_frame

	var dy := StairStep.try_step_up(body, Vector3(0.3, 0.0, 0.0), 0.4, 0.4)

	assert_float(dy).append_failure_message(
		"un corps qui n'était pas au sol ne doit jamais déclencher de step-up (sinon un saut/une chute serait faussé)"
	).is_equal(0.0)


# ================================================ StairStep.try_step_down (unitaire)

func test_try_step_down_catches_a_030m_ledge_and_reacquires_the_floor() -> void:
	var o := _offset()
	_step_down_scene(o, 0.3)
	# 0.6 (>> rayon de capsule 0.4) au-delà du bord (x = o.x) : la capsule est
	# ENTIÈREMENT au-dessus du sol BAS (aucun chevauchement avec le sol haut),
	# mais encore à l'altitude du sol HAUT -> rien en dessous à cette hauteur
	# -> is_on_floor() faux, comme juste après un move_and_slide() qui vient
	# de franchir le bord.
	# floor_snap_length par défaut (0.1, Godot) : NETTEMENT sous les 0.3 m de
	# cette marche, donc le snap intégré du moteur ne peut pas la rattraper
	# tout seul lors du move_and_slide() ci-dessous — la preuve que c'est bien
	# `try_step_down` qui fait le travail (son propre appel à `apply_floor_
	# snap()` a lui aussi BESOIN de `floor_snap_length` > 0 pour agir : le
	# mettre à 0 casserait try_step_down autant que le snap automatique).
	var body := _simple_body(o + Vector3(0.6, 0.0, 0.0))
	await get_tree().physics_frame
	await get_tree().physics_frame
	body.velocity = Vector3(0, -0.5, 0)
	body.move_and_slide()
	assert_bool(body.is_on_floor()).append_failure_message(
		"préalable du test : le snap par défaut du moteur (0.1 m) ne doit PAS rattraper une marche de 0.3 m à lui seul"
	).is_false()

	var dy := StairStep.try_step_down(body, true, 0.4, 0.4)

	assert_float(dy).append_failure_message(
		"delta Y renvoyé = %.3f, attendu ~ -0.3 m (hauteur de la marche descendante)" % dy
	).is_equal_approx(-0.3, 0.03)
	assert_bool(body.is_on_floor()).append_failure_message(
		"try_step_down doit forcer apply_floor_snap() : is_on_floor() doit redevenir vrai le même tick"
	).is_true()
	assert_float(body.global_position.y).append_failure_message(
		"le corps doit être redescendu sur le sol bas"
	).is_equal_approx(o.y - 0.3, 0.03)


func test_try_step_down_does_nothing_on_a_real_100m_drop() -> void:
	var o := _offset()
	_step_down_scene(o, 1.0)  # gouffre bien au-delà de max_step_down (0.4 m)
	var body := _simple_body(o + Vector3(0.6, 0.0, 0.0))
	await get_tree().physics_frame
	await get_tree().physics_frame
	body.velocity = Vector3(0, -0.5, 0)
	body.move_and_slide()
	assert_bool(body.is_on_floor()).is_false()

	var pos_before := body.global_position
	var dy := StairStep.try_step_down(body, true, 0.4, 0.4)

	assert_float(dy).append_failure_message(
		"une chute de 1.0 m dépasse max_step_down (0.4 m) : ce n'est pas une marche, doit rester une VRAIE chute (obtenu %.3f)" % dy
	).is_equal(0.0)
	assert_vector(body.global_position).append_failure_message(
		"la position ne doit pas bouger pour une vraie chute (l'état Air doit se déclencher normalement)"
	).is_equal(pos_before)
	assert_bool(body.is_on_floor()).append_failure_message(
		"une vraie chute ne doit jamais être requalifiée en sol"
	).is_false()


func test_try_step_down_ignores_a_body_that_was_not_previously_on_floor() -> void:
	var o := _offset()
	_step_down_scene(o, 0.3)
	var body := _simple_body(o + Vector3(0.6, 0.0, 0.0))
	await get_tree().physics_frame
	await get_tree().physics_frame
	body.velocity = Vector3(0, -0.5, 0)
	body.move_and_slide()

	# `was_on_floor` = faux : par ex. un saut normal, en plein vol au-dessus
	# d'une marche — ne doit surtout pas se faire aimanter au sol en l'air.
	var dy := StairStep.try_step_down(body, false, 0.4, 0.4)

	assert_float(dy).is_equal(0.0)


func test_try_step_down_ignores_a_body_rising_upward() -> void:
	var o := _offset()
	_step_down_scene(o, 0.3)
	var body := _simple_body(o + Vector3(0.6, 0.0, 0.0))
	await get_tree().physics_frame
	await get_tree().physics_frame
	body.velocity = Vector3(0, 5.0, 0)  # décolle (saut) : ne doit pas se recoller au sol.
	body.move_and_slide()

	var dy := StairStep.try_step_down(body, true, 0.4, 0.4)

	assert_float(dy).append_failure_message(
		"un corps qui décolle volontairement (velocity.y > 0, saut) ne doit jamais être recollé au sol"
	).is_equal(0.0)


# ============================================ Intégration : sprint contre une marche

func test_sprinting_bot_climbs_a_030m_step_without_losing_more_than_10_percent_speed() -> void:
	var o := _offset()
	_step_up_scene(o, 0.3)
	var player := await _grounded_sprinting_bot(o + Vector3(-6.0, 0.0, 0.0))

	var speed_before_step := 0.0
	var saw_nonzero_head_offset := false
	var crossed_tick := -1
	var max_ticks := 300

	for i in range(max_ticks):
		player._physics_process(DT)
		if not is_zero_approx(player._head_step_offset):
			saw_nonzero_head_offset = true
		if player.global_position.x < o.x - 0.2:
			speed_before_step = max(speed_before_step, player.horizontal_speed())
		elif crossed_tick < 0 and player.global_position.x > o.x + 1.0:
			crossed_tick = i

	assert_int(crossed_tick).append_failure_message(
		"le bot n'a jamais franchi la marche de 0.3 m en %d ticks — step-up cassé ou marche bloquante à tort" % max_ticks
	).is_greater_equal(0)
	assert_float(speed_before_step).append_failure_message(
		"préalable du test : la vitesse de sprint aurait dû être atteinte avant la marche"
	).is_greater_equal(player.config.sprint_speed * 0.9)

	# Vitesse mesurée une fois stabilisé SUR la marche (quelques ticks après
	# l'avoir franchie, laisse l'accélération sol re-saturer si besoin).
	var speed_after_step := 0.0
	for i in range(20):
		player._physics_process(DT)
		speed_after_step = max(speed_after_step, player.horizontal_speed())

	assert_float(speed_after_step).append_failure_message(
		"vitesse après la marche = %.2f m/s, avant = %.2f m/s : perte > 10%% (critère d'acceptation MV-01)"
			% [speed_after_step, speed_before_step]
	).is_greater_equal(speed_before_step * 0.9)
	assert_float(player.global_position.y).append_failure_message(
		"le bot doit être monté sur la marche (+0.3 m), pas resté au niveau du sol bas"
	).is_equal_approx(o.y + 0.3, 0.05)
	assert_bool(saw_nonzero_head_offset).append_failure_message(
		"le franchissement réel de la marche aurait dû déclencher un décalage de lissage caméra (_head_step_offset)"
	).is_true()
	assert_bool(player.is_bot).append_failure_message(
		"préalable du test : ce contrôleur doit être celui d'un BOT (même contrôleur que l'humain, MV-01)"
	).is_true()


func test_sprinting_bot_is_blocked_by_a_050m_step_too_high() -> void:
	var o := _offset()
	_step_up_scene(o, 0.5)
	var player := await _grounded_sprinting_bot(o + Vector3(-6.0, 0.0, 0.0))

	for i in range(180):
		player._physics_process(DT)

	assert_float(player.global_position.x).append_failure_message(
		"une marche de 0.5 m (> max_step_up 0.4 m) doit BLOQUER : le bot ne devrait jamais dépasser le pied du mur (x = %.2f)"
			% player.global_position.x
	).is_less(o.x + 0.3)
	assert_float(player.global_position.y).append_failure_message(
		"le bot ne doit jamais être monté sur une marche trop haute"
	).is_equal_approx(o.y, 0.05)


## Fait sprinter un bot vers +X (aucune rotation : `wish_dir` = (input.x, 0,
## input.y) en transform identité, voir PlayerController._read_input) — même
## préalable "posé au sol" que tests/player/test_state_exits.gd::_grounded_bot.
func _grounded_sprinting_bot(pos: Vector3) -> PlayerController:
	var player := _bot_player(pos)
	await get_tree().physics_frame
	await get_tree().physics_frame
	player.velocity = Vector3(0, -1, 0)
	player.move_and_slide()
	assert_bool(player.is_on_floor()).append_failure_message(
		"préalable du test : le bot doit être détecté au sol"
	).is_true()
	player.state_machine.transition_to("Sprint")
	player.input.move = Vector2(1.0, 0.0)
	player.input.walk_held = false
	return player


# ================================================== Intégration : descente d'escalier

func test_descending_a_030m_ledge_never_transitions_to_air_state() -> void:
	var o := _offset()
	_step_down_scene(o, 0.3)
	var player := await _grounded_sprinting_bot(o + Vector3(-6.0, 0.0, 0.0))
	# `floor_snap_length` reste à sa valeur RÉELLE de jeu (0.4 m par défaut —
	# voir PlayerController._ready) : on vérifie le comportement de bout en
	# bout tel qu'il sera vraiment vécu en partie, pas un montage artificiel.
	# (Note : `apply_floor_snap()`, appelée par StairStep.try_step_down, a de
	# toute façon BESOIN de `floor_snap_length` > 0 pour agir — le mettre à 0
	# casserait try_step_down autant que le snap automatique du moteur.)

	var ever_air := false
	var max_ticks := 90
	for i in range(max_ticks):
		player._physics_process(DT)
		if player.state_machine.current_name == "Air":
			ever_air = true

	assert_bool(ever_air).append_failure_message(
		"le bot est passé par l'état \"Air\" en descendant une marche de 0.3 m — critère d'acceptation MV-01 violé"
	).is_false()
	assert_float(player.global_position.x).append_failure_message(
		"le bot n'a jamais franchi la marche descendante en %d ticks" % max_ticks
	).is_greater(o.x + 1.0)
	assert_float(player.global_position.y).append_failure_message(
		"le bot doit avoir suivi la marche vers le bas (-0.3 m)"
	).is_equal_approx(o.y - 0.3, 0.05)


func test_falling_off_a_real_100m_ledge_still_transitions_to_air_state() -> void:
	# Garde de non-régression : une VRAIE chute (bien au-delà de max_step_down)
	# doit continuer à déclencher l'état "Air" normalement — StairStep ne doit
	# pas transformer chaque bord de map en trampoline magnétique.
	var o := _offset()
	_step_down_scene(o, 1.0)
	var player := await _grounded_sprinting_bot(o + Vector3(-6.0, 0.0, 0.0))

	var saw_air := false
	for i in range(240):
		player._physics_process(DT)
		if player.state_machine.current_name == "Air":
			saw_air = true

	assert_bool(saw_air).append_failure_message(
		"une chute de 1.0 m doit toujours déclencher l'état \"Air\" — StairStep ne doit gérer QUE les petites marches"
	).is_true()


# ========================================================== Lissage caméra (~80 ms)

func test_head_step_offset_decays_to_about_one_over_e_after_smooth_time() -> void:
	var o := _offset()
	var player := _bot_player(o)
	await get_tree().physics_frame

	# Simule un step-up de 0.3 m survenu CE tick (comme le ferait
	# PlayerController._physics_process juste après StairStep.try_step_up).
	player._apply_step_smoothing(0.3, DT)
	var offset_right_after := player._head_step_offset

	assert_float(offset_right_after).append_failure_message(
		"un step-up de +0.3 m doit décaler la tête vers le BAS d'autant (elle rattrape ensuite) : décalage obtenu %.4f"
			% offset_right_after
	).is_less(0.0)
	assert_float(player.head.position.y).append_failure_message(
		"head.position.y doit intégrer _head_step_offset (voir _apply_body_height)"
	).is_equal_approx(player.current_height - 0.2 + offset_right_after, 0.0001)

	# Fait s'écouler quelques ticks de plus et vérifie la formule de
	# décroissance EXACTE (exponentielle, constante de temps
	# `stair_step_smooth_time`) — indépendant de tout arrondi de tick.
	var ticks := int(round(player.config.stair_step_smooth_time / DT))
	for i in range(ticks):
		player._apply_step_smoothing(0.0, DT)

	var expected := offset_right_after * exp(-(float(ticks) * DT) / player.config.stair_step_smooth_time)
	assert_float(player._head_step_offset).append_failure_message(
		"décroissance exponentielle de constante de temps stair_step_smooth_time attendue (attendu %.5f, obtenu %.5f)"
			% [expected, player._head_step_offset]
	).is_equal_approx(expected, 0.0005)
	# Vérif qualitative liée au critère "~80 ms" : après ~stair_step_smooth_time
	# écoulées, il doit rester nettement MOINS de la moitié du décalage d'origine.
	assert_float(absf(player._head_step_offset)).append_failure_message(
		"après ~%.0f ms (stair_step_smooth_time), le décalage devrait avoir nettement diminué"
			% (player.config.stair_step_smooth_time * 1000.0)
	).is_less(absf(offset_right_after) * 0.5)

	# Convergence complète après plusieurs constantes de temps : la caméra ne
	# doit JAMAIS garder un décalage résiduel permanent.
	for i in range(ticks * 6):
		player._apply_step_smoothing(0.0, DT)
	assert_float(player._head_step_offset).append_failure_message(
		"le décalage de lissage doit converger vers 0 (jamais de biais caméra permanent)"
	).is_equal_approx(0.0, 0.01)
	assert_float(player.head.position.y).is_equal_approx(player.current_height - 0.2, 0.01)


func test_head_step_offset_stays_zero_without_any_step_event() -> void:
	var o := _offset()
	var player := _bot_player(o)
	await get_tree().physics_frame

	for i in range(30):
		player._apply_step_smoothing(0.0, DT)

	assert_float(player._head_step_offset).append_failure_message(
		"sans aucun événement de marche, le décalage de lissage doit rester nul"
	).is_equal(0.0)
