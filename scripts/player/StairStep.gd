## StairStep.gd
## Step-up / step-down façon Source, via `PhysicsServer3D.body_test_motion()` —
## `move_and_slide()` seul ne monte JAMAIS les marches : une marche est un mur
## vertical pour lui (aucune fusion moteur prévue, proposition Godot #2751 ;
## voir docs/research/01_game_feel.md §2.7). Technique de référence à trois
## balayages ("lever, avancer, redescendre"), déjà largement utilisée dans
## l'écosystème Godot 4 (ex. Andicraft/stairs-character, MIT — implémentation
## indépendante ici, adaptée à notre PlayerController et à MovementConfig).
##
## Deux fonctions STATIQUES (aucun état, aucune instance), appelées par
## PlayerController._physics_process AUTOUR de son `move_and_slide()` du tick
## (jamais à l'intérieur) :
##  - `try_step_up` AVANT `move_and_slide()` : si l'avancée horizontale voulue
##    ce tick est bloquée par un rebord <= `max_step_up`, soulève le corps EN
##    Y SEULEMENT (jamais en X/Z) jusqu'au sommet de la marche — c'est le
##    `move_and_slide()` normal qui suit qui parcourt ensuite l'horizontale
##    avec la VRAIE vélocité du joueur, désormais dégagée par la marche déjà
##    franchie (aucune perte de vitesse : on n'a jamais touché vx/vz).
##  - `try_step_down` APRÈS `move_and_slide()` : si le corps vient de perdre
##    le contact au sol (bord d'une marche descendante <= `max_step_down`)
##    alors qu'il était au sol l'instant d'avant et ne monte pas (saut en
##    cours), redescend le corps sur la marche et force `apply_floor_snap()`
##    — sans ça, `is_on_floor()` resterait faux ce tick et les states
##    (Idle/Walk/Sprint/Crouch/Slide) transitionneraient vers "Air" au tick
##    suivant (`if not player.is_on_floor(): transition_to("Air")`).
##
## Les DEUX renvoient le delta vertical (m) réellement appliqué à
## `body.global_position.y` (0.0 si aucune marche franchie) : positif pour un
## step-up, négatif pour un step-down. PlayerController s'en sert pour lisser
## le saut vertical brut côté caméra (voir `_apply_step_smoothing`).
##
## `capsule_radius` (les deux fonctions) : rayon de la capsule du corps (ex.
## `collision.shape.radius`). Sert UNIQUEMENT à choisir une distance de
## sondage horizontal sûre autour de l'arête de la marche (voir
## `_edge_clearance` ci-dessous) — jamais à déplacer réellement le corps en
## X/Z. Sans cette marge, un simple sondage vertical pile à l'aplomb de
## l'arête accroche le CHANFREIN arrondi du bas de la capsule contre l'arête
## (angle de collision oblique, entre mur et sol) plutôt que le palier plat
## juste derrière — et échoue à tort au test `floor_max_angle`, y compris à
## vitesse de sprint normale (mesuré : capsule 0.4 m de rayon, ~0.14 m
## parcourus par tick à 8.2 m/s/60 Hz, tous deux trop courts pour dépasser le
## rayon de la capsule). Voir tests/player/test_stair_step.gd, qui documente
## ce cas précis.
class_name StairStep
extends RefCounted


## Un seul balayage de test (aucune vraie collision : `body_test_motion` ne
## déplace jamais le corps réel) — factorisé pour ne pas répéter la
## construction des paramètres à chaque étape ci-dessous.
static func _sweep(body: CharacterBody3D, from: Transform3D, motion: Vector3,
		margin: float, result: PhysicsTestMotionResult3D) -> bool:
	var params := PhysicsTestMotionParameters3D.new()
	params.from = from
	params.motion = motion
	params.margin = margin
	return PhysicsServer3D.body_test_motion(body.get_rid(), params, result)


## Marge de sécurité (m) ajoutée aux distances de sondage ci-dessous, en plus
## de `margin`/`capsule_radius` : absorbe le bruit numérique réel (recovery de
## body_test_motion sur les sondages précédents, etc.) qui peut grignoter
## quelques millimètres sur les calculs géométriques idéalisés — sans elle,
## un cas pile à la limite (ex. rayon exact, arête exacte) peut retomber du
## mauvais côté (mesuré en pratique, voir tests/player/test_stair_step.gd).
const _SAFETY_MARGIN := 0.05

## Distance horizontale à dépasser au-delà d'une arête pour que le CENTRE de
## la capsule (donc son chanfrein bas) soit à `>= capsule_radius` de cette
## arête : un sondage vertical pile au-dessus de l'arête accroche à coup sûr
## son chanfrein (distance centre-arête < rayon). Doubler le rayon (plutôt que
## juste l'atteindre) laisse une marge franche des deux côtés de l'arête.
static func _edge_clearance(capsule_radius: float) -> float:
	return 2.0 * maxf(capsule_radius, 0.0) + _SAFETY_MARGIN


## Tente de monter une marche AVANT le `move_and_slide()` du tick.
## `horizontal_motion` = déplacement horizontal voulu ce tick (typiquement
## `player.horizontal_velocity() * delta` : la composante Y de la vélocité —
## gravité, saut — n'a pas sa place ici, seul le mouvement au sol nous
## intéresse). `margin` < 0 (défaut) = utilise `body.safe_margin`, comme le
## `move_and_slide()` réel du corps.
##
## Ne fait RIEN (retourne 0.0, aucun mouvement appliqué) si :
##  - le corps n'était pas au sol au début du tick (`is_on_floor()`) ;
##  - il ne bouge pas horizontalement, ou `max_step_up` <= 0 ;
##  - rien ne bloque l'avancée horizontale (pas de marche à monter : le
##    `move_and_slide()` normal du tick suffira seul) ;
##  - un plafond bas empêche de se tenir debout sur la marche ;
##  - le sommet trouvé est trop incliné pour `body.floor_max_angle` (pente
##    raide ou mur non franchissable) ;
##  - la marche dépasse `max_step_up` (aucun palier trouvé dans la limite :
##    `move_and_slide()` la traitera comme un mur normal — elle "bloque").
static func try_step_up(body: CharacterBody3D, horizontal_motion: Vector3,
		max_step_up: float, capsule_radius: float, margin: float = -1.0) -> float:
	if not body.is_on_floor():
		return 0.0
	if max_step_up <= 0.0 or horizontal_motion.length() < 0.001:
		return 0.0
	var m: float = margin if margin >= 0.0 else body.safe_margin
	var dir := horizontal_motion.normalized()

	var result := PhysicsTestMotionResult3D.new()
	var origin := body.global_transform

	# 1) avance à l'horizontale : rien ne bloque => aucune marche à monter.
	#    Ce contact donne aussi, par géométrie (cylindre contre plan vertical),
	#    le point où le CENTRE de la capsule est exactement à `capsule_radius`
	#    de la face du mur — base fiable pour l'étape 3 ci-dessous.
	if not _sweep(body, origin, horizontal_motion, m, result):
		return 0.0
	var probe := origin.translated(result.get_travel())

	# 2) lève GÉNÉREUSEMENT au-delà de max_step_up (+ rayon de capsule + marge
	#    de sécurité), PAS juste jusqu'à max_step_up : un obstacle dont le
	#    sommet tombe près de max_step_up ferait sinon accrocher le chanfrein
	#    bas de la capsule contre SON arête (latéralement cette fois, symétrique
	#    au problème de l'étape 3) — l'angle de collision obtenu peut alors
	#    passer sous floor_max_angle par erreur et faire grimper une marche
	#    trop haute (mesuré, voir tests/player/test_stair_step.gd). Le VRAI
	#    plafond (max_step_up) reste appliqué plus bas sur `delta_y` : monter
	#    plus haut ICI ne fait que fiabiliser le test, jamais gagner de hauteur
	#    non voulue.
	var probe_height := max_step_up + capsule_radius + _SAFETY_MARGIN
	_sweep(body, probe, Vector3.UP * probe_height, m, result)
	probe = probe.translated(result.get_travel())
	var step_up_distance := result.get_travel().length()
	if step_up_distance < 0.001:
		return 0.0  # plafond juste au-dessus : aucune marche possible ici.

	# 3) avance de `_edge_clearance` (PAS le reliquat de ce tick, indépendant
	#    de la vitesse) au-delà du point de contact, maintenant au-dessus de
	#    l'obstacle : assez pour que le sondage vertical de l'étape 4 tombe
	#    franchement sur le dessus plat de la marche plutôt que sur son arête.
	#    Un simple TEST : n'affecte jamais le déplacement horizontal RÉEL,
	#    piloté par le move_and_slide() qui suit.
	_sweep(body, probe, dir * _edge_clearance(capsule_radius), m, result)
	probe = probe.translated(result.get_travel())

	# 4) redescend pour retrouver le sommet de la marche — jamais plus loin
	#    que ce qu'on vient de monter.
	if not _sweep(body, probe, Vector3.DOWN * step_up_distance, m, result):
		return 0.0  # rien en dessous (rebord/trou) : aucun palier, on abandonne.
	probe = probe.translated(result.get_travel())

	# 5) le sommet doit être praticable (pas plus raide que floor_max_angle).
	if result.get_collision_normal().angle_to(Vector3.UP) > body.floor_max_angle:
		return 0.0

	# 6) le VRAI plafond : même praticable et net, une marche plus haute que
	#    max_step_up doit rester un mur normal ("bloque") — l'étape 2 grimpe
	#    volontairement plus haut que max_step_up pour fiabiliser le test,
	#    donc ce n'est QU'ICI que la limite de gameplay est effectivement
	#    appliquée.
	var delta_y := probe.origin.y - origin.origin.y
	if delta_y <= 0.0 or delta_y > max_step_up:
		return 0.0

	# Seule la hauteur change ICI : X/Z restent ceux du début du tick — c'est
	# le move_and_slide() qui suit qui parcourt l'horizontale avec la vraie
	# vélocité, maintenant dégagée par la marche franchie (aucune perte de
	# vitesse : vx/vz ne sont jamais touchés).
	body.global_position.y += delta_y
	return delta_y


## Tente de coller le corps à une marche descendante APRÈS le
## `move_and_slide()` du tick, pour ne jamais transiter par l'état "Air" pour
## une simple marche d'escalier. `was_on_floor` = résultat de `is_on_floor()`
## au DÉBUT de ce tick, AVANT son `move_and_slide()` (c'est `PlayerController.
## _was_on_floor`, déjà tenu à jour pour `_check_fall_stun`). `margin` < 0
## (défaut) = utilise `body.safe_margin`.
##
## Ne fait RIEN (retourne 0.0) si :
##  - le corps n'était pas au sol au début du tick, ou `max_step_down` <= 0 ;
##  - il est toujours au sol après le move_and_slide() (rien à rattraper) ;
##  - il est en train de monter (`velocity.y > 0`, saut/step-up en cours) —
##    ne jamais coller un joueur qui décolle volontairement ;
##  - rien en dessous dans la limite `max_step_down` : c'est une VRAIE chute
##    (rebord de map, gouffre...), l'état "Air" doit se déclencher normalement ;
##  - le palier trouvé est trop incliné pour `body.floor_max_angle`.
static func try_step_down(body: CharacterBody3D, was_on_floor: bool, max_step_down: float,
		capsule_radius: float, margin: float = -1.0) -> float:
	if not was_on_floor or max_step_down <= 0.0:
		return 0.0
	if body.is_on_floor():
		return 0.0  # rien à rattraper : le sol a déjà été retrouvé normalement.
	if body.velocity.y > 0.0:
		return 0.0  # décolle volontairement (saut) : ne pas le recoller au sol.
	var m: float = margin if margin >= 0.0 else body.safe_margin

	var result := PhysicsTestMotionResult3D.new()
	var origin := body.global_transform
	var probe := origin

	# Avance encore un peu (sondage AVANCÉ, voir plus bas pourquoi ce n'est PAS
	# qu'un simple test cette fois) dans la direction du mouvement horizontal
	# avant de redescendre : sans ça, le chanfrein bas de la capsule accroche
	# l'arête AMONT du bord qu'on vient de quitter (angle de collision
	# oblique) au lieu d'atteindre le palier du dessous — même raison
	# géométrique que `try_step_up`, juste après avoir franchi le bord plutôt
	# que juste avant.
	var nudge := Vector3.ZERO
	var horiz := Vector3(body.velocity.x, 0.0, body.velocity.z)
	if horiz.length() > 0.001:
		_sweep(body, probe, horiz.normalized() * _edge_clearance(capsule_radius), m, result)
		probe = probe.translated(result.get_travel())
		nudge = result.get_travel()

	# Cherche GÉNÉREUSEMENT au-delà de max_step_down (+ rayon + marge), pour la
	# même raison qu'à l'étape 2 de try_step_up : un palier dont le bord tombe
	# près de max_step_down ferait sinon accrocher le chanfrein de la capsule
	# contre CETTE arête plutôt que d'atteindre le palier réel. Le VRAI
	# plafond (max_step_down) est appliqué plus bas sur `delta_y`.
	var search_depth := max_step_down + capsule_radius + _SAFETY_MARGIN
	if not _sweep(body, probe, Vector3.DOWN * search_depth, m, result):
		return 0.0  # rien en dessous dans la limite : vraie chute, laisser faire.
	if result.get_collision_normal().angle_to(Vector3.UP) > body.floor_max_angle:
		return 0.0  # trop raide pour tenir debout : vraie chute/glissade, laisser faire.
	probe = probe.translated(result.get_travel())

	var delta_y := probe.origin.y - origin.origin.y
	if delta_y >= 0.0 or -delta_y > max_step_down:
		return 0.0  # aucune perte nette, ou palier plus bas que max_step_down : vraie chute, laisser faire.

	# `apply_floor_snap()` refait SA PROPRE vérification interne depuis la
	# position RÉELLE du corps au moment où on l'appelle — le sondage plus
	# haut (nudge purement interne à CE calcul) ne l'aide pas : si le corps
	# réel est encore près de l'arête (X/Z inchangés), elle peut retomber dans
	# le MÊME piège de chanfrein et ne jamais positionner `is_on_floor()` à
	# vrai malgré une hauteur correcte (mesuré, voir tests/player/
	# test_stair_step.gd). On place donc TEMPORAIREMENT le corps au point
	# propre déjà trouvé (décalé de `nudge`, sans arête à proximité) pour que
	# apply_floor_snap() y retrouve le sol sans ambiguïté, puis on le ramène à
	# son X/Z RÉEL (le palier est plat : la même hauteur y est valide). Godot
	# ne réévalue `is_on_floor()` qu'au PROCHAIN move_and_slide()/apply_floor_
	# snap() : le ramener en arrière ensuite par une simple écriture de
	# position ne l'invalide pas.
	body.global_position += nudge + Vector3(0.0, delta_y, 0.0)
	body.apply_floor_snap()
	body.global_position -= nudge
	return delta_y
