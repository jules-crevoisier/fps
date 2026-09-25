## test_slide_fire.gd
## GF-30 — retour de playtest 2026-09-25 : « on ne peut pas tirer quand on
## slide, c'est un peu dérangeant ». Décision lead (FPS rapide, référence
## COD/Apex) : la glissade NE bloque PLUS le tir (Weapon._owner_tick ne
## calcule plus `WeaponFeel.fire_delay_left` qu'avec le délai de plongeon, la
## glissade lui passe désormais `INF`, son sentinel "pas de pénalité" — voir
## Weapon.gd et WeaponFeel.gd) ; la dispersion de glissade EXISTANTE
## (`WeaponFeel.move_spread_deg` avec `sliding=true`, inchangée) continue de
## pénaliser la précision. Le plongeon (Dive), lui, garde son délai complet
## (`Weapon._can_act()` l'exclut toujours explicitement, comme Roll/Stun).
##
## Même méthode organique (joueur BOT réel, autorité SERVEUR, `player.input`)
## que tests/review/test_fire_every_state.gd — dont ce fichier reprend les
## helpers de scène (dupliqués ici : chaque suite gdUnit4 du dépôt porte les
## siens, voir tests/combat/test_fire_while_sprinting.gd) — mais celui-là
## reste HORS de la liste `files` de GF-30 (tasks/backlog.yaml) et n'est
## réclamé par AUCUNE tâche du backlog à ce jour : je ne le touche pas.
## RÉGRESSION CONFIRMÉE et NON corrigible ici : sa table
## `test_fire_blocked_in_slide` (ligne ~222, `_assert_fire_in_state(player,
## true, "Slide")`) fige encore l'ANCIEN comportement (glissade bloque le
## tir) et ÉCHOUE désormais après ce diff (« tir NON bloqué en Slide
## (munitions 25 -> 24) — restriction cassée ») — attendu par
## tasks/backlog.yaml:6586-6587 (« mettre à jour les tests existants qui
## figent l'ancien délai de slide SEULEMENT s'ils contredisent cette
## décision, à lister dans le rapport »). `tools/review/gameplay_probe.gd`
## (sa table ~L19-37, même sonde utilisée par tools/review/run_review.ps1)
## documente la MÊME attente obsolète et sera probablement affecté pareil —
## également hors de mon périmètre. Voir le rendu de fin de tâche GF-30 :
## `blocked_on`.
extends GdUnitTestSuite

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")

var _next_offset_index := 0


## Voir tests/review/test_fire_every_state.gd::before_test — même besoin
## cosmétique (Weapon._spawn_tracer/_spawn_impact posent leurs effets sur
## get_tree().current_scene, jamais nul en vrai match).
func before_test() -> void:
	get_tree().current_scene = self


func _offset() -> Vector3:
	var o := Vector3(float(_next_offset_index) * 60.0, 0.0, 0.0)
	_next_offset_index += 1
	return o


## Sol large (le slide doit pouvoir atteindre sa vitesse de boost avant le
## tir) — même construction que tests/review/test_fire_every_state.gd::_floor.
func _floor(top: Vector3, size: Vector3 = Vector3(60, 1, 60)) -> StaticBody3D:
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


## Instance réelle du joueur, nom >= BOT_ID_START => autorité SERVEUR (voir
## PlayerController._enter_tree) pour que Weapon._physics_process
## (_server_tick ET _owner_tick) tourne réellement en test headless — même
## méthode que tests/review/test_fire_every_state.gd::_bot_player.
func _bot_player(pos: Vector3) -> PlayerController:
	var player: PlayerController = PLAYER_SCENE.instantiate()
	player.name = str(PlayerController.BOT_ID_START + _next_offset_index)
	player.position = pos
	player.set("spawn_point", pos)
	add_child(player)
	player.set("is_bot", true)  # APRÈS add_child : voir _bot_player d'origine (BotBrain._ready).
	auto_free(player)
	return player


## Spawne au sommet du sol, force le contact réel — même méthode que
## tests/review/test_fire_every_state.gd::_grounded_bot.
func _grounded_bot(o: Vector3) -> PlayerController:
	var player := _bot_player(o)
	await get_tree().physics_frame
	await get_tree().physics_frame
	player.velocity = Vector3(0, -1, 0)
	player.move_and_slide()
	assert_bool(player.is_on_floor()).append_failure_message(
		"préalable du test : le joueur doit être détecté au sol"
	).is_true()
	var t := 0
	while t < 30 and not (player.is_on_floor() and player.state_machine.current_name == "Idle"):
		if player.state_machine.current_name != "Idle" and player.is_on_floor():
			player.state_machine.transition_to("Idle")
		await get_tree().physics_frame
		t += 1
	return player


func _weapon(player: PlayerController) -> Weapon:
	return player.get_node("Weapon") as Weapon


func _wait_physics(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


## Sprinte jusqu'à `slide_min_speed`, puis tape Ctrl (crouch_pressed) pour
## entrer en glissade en gardant `crouch_held` vrai (sinon Slide.physics_update
## annule la glissade dès la frame suivante, slide-cancel) — même geste que
## tests/review/test_fire_every_state.gd::test_fire_blocked_in_slide.
func _enter_slide(player: PlayerController) -> void:
	player.input.move = Vector2(0, -1)
	await _wait_physics(20)  # laisse ground_accel amener la vitesse >= slide_min_speed
	player.input.crouch_pressed = true
	player.input.crouch_held = true
	await _wait_physics(1)
	player.input.crouch_pressed = false
	await _wait_physics(1)
	assert_str(player.state_machine.current_name).append_failure_message(
		"préalable du test : l'état Slide n'est jamais devenu actif (actuel=%s)"
			% player.state_machine.current_name
	).is_equal("Slide")


## Plongeon organique (touche V) — même geste que
## tests/review/test_fire_every_state.gd::test_fire_blocked_in_dive.
func _enter_dive(player: PlayerController) -> void:
	player.input.dive_pressed = true
	await _wait_physics(1)
	player.input.dive_pressed = false
	await _wait_physics(1)
	assert_str(player.state_machine.current_name).append_failure_message(
		"préalable du test : l'état Dive n'est jamais devenu actif (actuel=%s)"
			% player.state_machine.current_name
	).is_equal("Dive")


## GF-30, critère d'acceptation : « en état Slide, un clic tire immédiatement ».
## Presse la gâchette UN SEUL tic physique (semi-auto ET auto tirent tous deux
## sur ce front montant, voir FireClock.tick/reset — "prête" par défaut, le
## premier tir après inactivité part immédiatement) et vérifie que les
## munitions ont déjà baissé sur ce même tic, sans attendre le moindre délai.
func test_fire_in_slide_is_immediate() -> void:
	var o := _offset()
	_floor(o)
	var player := await _grounded_bot(o)
	await _enter_slide(player)

	var weapon := _weapon(player)
	var ammo_before: int = weapon.mag[weapon.current]
	player.input.fire_pressed = true
	player.input.fire_held = true
	await _wait_physics(1)
	assert_str(player.state_machine.current_name).append_failure_message(
		"le joueur est sorti de Slide avant même le tir (actuel=%s) — invalide le scénario"
			% player.state_machine.current_name
	).is_equal("Slide")
	var ammo_after: int = weapon.mag[weapon.current]
	player.input.fire_pressed = false
	player.input.fire_held = false
	await _wait_physics(2)

	assert_int(ammo_after).append_failure_message(
		("GF-30 : le tir reste bloqué en Slide sur le tic de pression (munitions %d->%d) — "
			+ "la glissade ne doit plus imposer aucun délai (WeaponFeel.fire_delay_left doit "
			+ "recevoir INF pour son paramètre glissade, voir Weapon._owner_tick)")
			% [ammo_before, ammo_after]
	).is_less(ammo_before)


## GF-30, critère d'acceptation : « en Dive, le délai existe toujours ». Un
## clic pendant le plongeon ne doit RIEN tirer — Weapon._can_act() exclut
## toujours "Dive" explicitement (mécanique inchangée par cette tâche).
func test_fire_in_dive_still_blocked() -> void:
	var o := _offset()
	_floor(o)
	var player := await _grounded_bot(o)
	await _enter_dive(player)

	var weapon := _weapon(player)
	var ammo_before: int = weapon.mag[weapon.current]
	player.input.fire_pressed = true
	player.input.fire_held = true
	await _wait_physics(1)
	player.input.fire_pressed = false
	await _wait_physics(3)
	player.input.fire_held = false
	await _wait_physics(2)
	var ammo_after: int = weapon.mag[weapon.current]

	assert_int(ammo_after).append_failure_message(
		"GF-30 : le plongeon doit garder son délai — tir NON bloqué en Dive (munitions %d->%d)"
			% [ammo_before, ammo_after]
	).is_equal(ammo_before)


## GF-30, critère d'acceptation : « dispersion > dispersion à l'arrêt ». Rejoue
## EXACTEMENT le calcul de Weapon._fire_local (WeaponFeel.move_spread_deg avec
## la vitesse horizontale RÉELLE du joueur et `sliding` déduit du même nom
## d'état, scripts/combat/Weapon.gd:~408) une fois en pleine glissade (vitesse
## boostée par Slide.gd, `sliding=true`) et une fois à l'arrêt en Idle
## (vitesse nulle, `sliding=false`) — pas des valeurs synthétiques : la
## vitesse vient du VRAI mouvement de scripts/player/states/Slide.gd, donc ce
## test couvre aussi un défaut de câblage (ex. horizontal_speed() figé) que
## tests/combat/test_weapon_feel.gd (valeurs synthétiques, hors de mon
## périmètre) ne peut pas détecter.
func test_slide_dispersion_exceeds_stationary_dispersion() -> void:
	var o := _offset()
	_floor(o)
	var player := await _grounded_bot(o)
	var weapon := _weapon(player)
	var c := weapon.cfg()
	assert_object(c).append_failure_message(
		"préalable du test : aucune arme équipée"
	).is_not_null()

	# À l'arrêt (Idle, vitesse nulle) : dispersion de mouvement nulle.
	var idle_sliding := player.state_machine.current_name == "Slide"
	var idle_spread := WeaponFeel.move_spread_deg(
		c, player.horizontal_speed(), player.config.sprint_speed, idle_sliding
	)

	# En pleine glissade : Slide.gd applique slide_boost à l'entrée, donc la
	# vitesse dépasse déjà largement la zone morte (move_spread_deadzone).
	await _enter_slide(player)
	var slide_sliding := player.state_machine.current_name == "Slide"
	var slide_spread := WeaponFeel.move_spread_deg(
		c, player.horizontal_speed(), player.config.sprint_speed, slide_sliding
	)

	assert_bool(idle_sliding).append_failure_message(
		"préalable du test : le joueur ne devrait pas être en Slide au repos"
	).is_false()
	assert_bool(slide_sliding).append_failure_message(
		"préalable du test : le joueur devrait être en Slide au moment de la mesure"
	).is_true()
	assert_float(slide_spread).append_failure_message(
		("GF-30 : la dispersion de glissade (%.4f°) doit rester STRICTEMENT supérieure à la "
			+ "dispersion à l'arrêt (%.4f°) — vitesse slide=%.2f m/s, sprint_speed=%.2f m/s")
			% [slide_spread, idle_spread, player.horizontal_speed(), player.config.sprint_speed]
	).is_greater(idle_spread)
