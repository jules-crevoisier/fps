## test_spawn_role.gd
## Spec (.orchestrator/maps-spec.md §4.6, bug reported by the level design
## slice) : en SnD, l'échange de côté (RoundMode.sides_swapped, après la
## manche 6) inverse les RÔLES (attaque/défense) sans changer le NUMÉRO
## d'équipe du joueur. Les marqueurs de spawn sont tagués par CÔTÉ
## géométrique fixe (team meta 0 = attaque, 1 = défense — voir MapSetup),
## donc GameWorld._get_spawn_position doit choisir le marqueur par RÔLE
## courant, pas par numéro d'équipe brut — sinon les attaquants spawnent sur
## les sites de bombe dès la manche 6. `GameWorld.spawn_side_for` est la
## fonction pure qui porte cette règle (contract-r3.md : "spawn_team = team
## if not sides_swapped else 1 - team").
extends GdUnitTestSuite


func test_no_swap_spawns_at_own_team_side() -> void:
	assert_int(GameWorld.spawn_side_for(0, false)).is_equal(0)
	assert_int(GameWorld.spawn_side_for(1, false)).is_equal(1)


func test_after_swap_team_0_spawns_on_defence_side() -> void:
	# L'équipe 0 attaquait (côté 0) avant l'échange ; après l'échange
	# (manche 6+), c'est l'équipe 1 qui attaque -> l'équipe 0 doit spawn
	# côté 1 (défense), pas rester sur le côté 0 (les sites de bombe).
	assert_int(GameWorld.spawn_side_for(0, true)).is_equal(1)


func test_after_swap_team_1_spawns_on_attack_side() -> void:
	assert_int(GameWorld.spawn_side_for(1, true)).is_equal(0)


func test_matches_attacking_team_convention() -> void:
	# RoundMode.attacking_team() renvoie 1 si sides_swapped sinon 0 :
	# l'équipe qui attaque EN CE MOMENT doit toujours spawn côté 0
	# (marqueurs "attaque"), quel que soit son numéro d'équipe brut.
	for sides_swapped in [false, true]:
		var attacking_team := 1 if sides_swapped else 0
		assert_int(GameWorld.spawn_side_for(attacking_team, sides_swapped)) \
			.append_failure_message("attaquant (équipe %d, swapped=%s) devrait spawn côté 0 (attaque)" % [attacking_team, sides_swapped]) \
			.is_equal(0)
		var defending_team := 1 - attacking_team
		assert_int(GameWorld.spawn_side_for(defending_team, sides_swapped)) \
			.append_failure_message("défenseur (équipe %d, swapped=%s) devrait spawn côté 1 (défense)" % [defending_team, sides_swapped]) \
			.is_equal(1)


func test_double_swap_returns_to_original_side() -> void:
	# Manche 12 (deuxième échange) : le rôle redevient l'original — vérifie
	# qu'il n'y a pas d'accumulation d'état, juste une fonction du booléen courant.
	var side_after_one_swap := GameWorld.spawn_side_for(0, true)
	var side_with_no_swap := GameWorld.spawn_side_for(0, false)
	assert_int(side_after_one_swap).is_not_equal(side_with_no_swap)
