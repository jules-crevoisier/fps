## RevealAbility — révèle des ennemis pour l'équipe du lanceur (marqueurs "!"
## visibles à travers les murs, <= 3 s — contract-r2.md, R-B3 acceptance #2).
## Le SERVEUR construit la liste des ennemis vivants depuis sa propre vue,
## filtre avec TargetSelect (logique pure testée), puis pousse les positions
## UNIQUEMENT aux coéquipiers (AbilityController.cast_reveal, RPC ciblées).
## `reveal_all` (ultime "Vision totale") ignore le point d'impact et révèle
## tous les ennemis de la carte.
extends Ability

@export var throw_range: float = 20.0
@export var reveal_radius: float = 10.0
@export var reveal_all: bool = false
@export var duration: float = 3.0
## "Coup de dé" (Guet, docs/research/10_ammo_kits_input.md §3.3) : délai de
## vol avant résolution -- 0 par défaut (comportement d'origine inchangé pour
## "Œil"/"Voile"/"Vision totale", qui ne le fixent pas). Même motif que
## StunBurstAbility.arm_delay : c'est la RECHERCHE des cibles elle-même qui
## attend (pas seulement un VFX retardé), donc une victime qui bouge pendant
## le vol peut sortir du rayon avant la résolution.
@export var flight_time: float = 0.0
## Avertissement reçu par les SEULES victimes révélées (jamais le reste de
## leur équipe, jamais un broadcast) -- false par défaut (comportement
## d'origine inchangé pour "Voile"/"Vision totale", qui ne l'activent pas).
@export var warn_victims: bool = false

func _init() -> void:
	slot = "E"
	display_name = "Œil"
	description = "Marqueur qui révèle les ennemis à travers les murs dans un rayon, visible seulement par son équipe (3 s)."
	cooldown = 24.0
	charges = 1

## Coroutine (GDScript autorise l'appel sans `await` côté appelant --
## AbilityController._server_activate ne fait qu'invoquer `ab.activate_server`
## sans attendre son retour, comme pour toute autre capacité, même motif que
## StunBurstAbility.activate_server) : reprend après `flight_time` via
## `await create_timer(...).timeout`, JAMAIS un `connect(lambda capturant
## player)` (CLAUDE.md, règle des minuteries).
func activate_server(player: PlayerController, aim_dir: Vector3) -> void:
	var ctrl := player.get_node_or_null("Abilities")
	if ctrl == null or not ctrl.has_method("cast_reveal"):
		return

	# Point d'impact (où le dé s'arrête) : figé DÈS le lancer, à partir
	# d'`aim_dir`/`origin` valides à CET instant -- le délai de vol ci-dessous
	# ne retarde QUE la résolution (recherche des cibles), jamais la
	# trajectoire elle-même.
	var cast_pos := Vector3.ZERO
	if not reveal_all:
		var origin: Vector3 = player.head.global_position
		var space := player.get_world_3d().direct_space_state
		var hit := trajectory_hit(space, origin, aim_dir, throw_range, [player.get_rid()])
		cast_pos = hit.position if not hit.is_empty() else origin + aim_dir * throw_range

	if flight_time > 0.0:
		await player.get_tree().create_timer(flight_time).timeout
		# `Ability` hérite de `Resource` (pas de propriété `multiplayer` bare,
		# contrairement à un Node) -- on passe par celle du joueur, comme
		# `is_multiplayer_authority()` ailleurs dans les autres capacités.
		if not is_instance_valid(player) or not player.multiplayer.is_server():
			return
		var self_hp := player.get_node_or_null("Health") as Health
		if self_hp and self_hp.is_dead:
			return  # Guet mort pendant le vol du dé : plus de lanceur.

	var players_root := player.get_parent()
	if players_root == null:
		return
	var my_team := int(player.get("team"))
	var candidates: Array = []
	for child in players_root.get_children():
		if child == player:
			continue
		var other := child as CharacterBody3D
		if other == null:
			continue
		var ohp := other.get_node_or_null("Health") as Health
		if ohp and ohp.is_dead:
			continue
		candidates.append({"pos": other.global_position, "team": int(other.get("team")), "node": other})
	var enemies := TargetSelect.enemies_of(candidates, my_team)

	var revealed: Array
	if reveal_all:
		revealed = enemies
	else:
		revealed = TargetSelect.within_radius(cast_pos, enemies, reveal_radius)

	if revealed.is_empty():
		return
	var marks: Array = []
	for r in revealed:
		marks.append(r.pos)
	ctrl.cast_reveal(players_root, my_team, marks, duration)

	if warn_victims:
		_warn_victims(revealed, duration)

## Prévient CHAQUE victime révélée -- ELLE SEULE (jamais le reste de son
## équipe, jamais un broadcast) : lui pousse SON PROPRE marqueur
## (AbilityController.net_show_markers, déjà une RPC ciblée un-à-un -- seul
## mécanisme existant pour "pousser un signal positionnel à UN client précis"
## hors du périmètre de ce contrat, AbilityController.gd n'étant pas dans les
## fichiers possédés ici), à SA PROPRE position, pendant `warn_duration`.
## Contre-jeu explicite (docs §3.3) : "l'avertissement dit de bouger" -- la
## victime sait qu'un marqueur figé existe désormais là où elle vient d'être vue.
func _warn_victims(revealed: Array, warn_duration: float) -> void:
	for v in victims_to_warn(revealed):
		var victim: CharacterBody3D = v
		if not is_instance_valid(victim):
			continue
		if bool(victim.get("is_bot")):
			continue  # cosmétique : un bot n'a pas d'écran (même garde que cast_reveal).
		var victim_ctrl := victim.get_node_or_null("Abilities")
		if victim_ctrl == null or not victim_ctrl.has_method("net_show_markers"):
			continue
		var own_mark := [victim.global_position]
		if victim.is_multiplayer_authority():
			victim_ctrl.net_show_markers(own_mark, warn_duration)  # hôte ou bot : appel direct
		else:
			victim_ctrl.net_show_markers.rpc_id(str(victim.name).to_int(), own_mark, warn_duration)

## Sélection PURE des nœuds à prévenir depuis la liste déjà filtrée par
## TargetSelect (chaque entrée de `revealed` porte un `node`, ajouté par
## `activate_server` ci-dessus) -- testable sans scène
## (tests/agents/test_guet_kit.gd).
static func victims_to_warn(revealed: Array) -> Array:
	var out: Array = []
	for r in revealed:
		var d: Dictionary = r
		var node = d.get("node")
		if node != null:
			out.append(node)
	return out

## Rayon de trajectoire (centre de la zone révélée le long d'aim_dir) :
## masque PhysicsLayers.SHOT_MASK — la fumée (calque VISION) bloque la vue,
## pas ce rayon de visée ; un Œil lancé à travers une fumée continue sa
## course (docs/audit/bugs.md BUG-06). Statique et exposé pour être testable
## directement (tests/agents/test_ability_rays.gd).
static func trajectory_hit(space: PhysicsDirectSpaceState3D, origin: Vector3, aim_dir: Vector3, range: float, exclude: Array[RID]) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(origin, origin + aim_dir * range, PhysicsLayers.SHOT_MASK)
	q.exclude = exclude
	q.collide_with_areas = false
	return space.intersect_ray(q)
