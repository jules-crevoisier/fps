## GrappleAbility — Piquet d'arpenteur (E signature de Vanne, remplace le
## Piquet-poussée) : un vrai grappin qui hale le lanceur vers un point
## d'ancrage sur le DÉCOR, jamais sur un joueur (docs/research/
## 10_ammo_kits_input.md §3.3, "Vanne" -- AGT-05).
##
## Contrairement à DashAbility (mouvement pur, aucune validation serveur), le
## point d'ancrage est calculé et validé CÔTÉ SERVEUR depuis sa PROPRE vue
## (`activate_server`, comme RevealAbility/StunTrapAbility/JumpPadAbility) :
## rayon `PhysicsLayers.SHOT_MASK` (traverse la fumée, jamais le décor réel),
## portée `max_range` (18 m, doc) + `server_margin` (1 m de tolérance réseau),
## et TOUS les joueurs exclus (jamais d'ancrage sur une tête, même motif que
## `StunTrapAbility.ground_hit`/`JumpPadAbility.ground_hit`).
##
## Le mouvement lui-même (traction) est donc TOUJOURS déclenché depuis
## l'autorité SERVEUR, via `AbilityController.net_apply_impulse` -- la même
## primitive déjà utilisée par la repoussée de Tape-la-cloche (docs/research/
## 10_ammo_kits_input.md §3.5, AGT-03/AGT-01) : appel DIRECT si le lanceur est
## simulé ICI (hôte/bot), RPC ciblée sinon (contract-r3.md). Aucune prédiction
## locale (`activate_local` reste le no-op par défaut d'`Ability`) : contrairement
## à Dash, une traction non validée serait facilement exploitable (portée/
## direction arbitraires), donc il n'y a délibérément qu'UNE seule source de
## vélocité (le serveur) -- pas de double application prédiction+correction.
## "Saut lâche le câble" et la borne "0,8 s max" de traction continue
## dépendent d'un état de mouvement (ex. scripts/player/states/Air.gd) hors
## des fichiers possédés par ce contrat -- voir le rendu de tâche AGT-05.
extends Ability

## Portée maximale de l'ancrage (m) -- docs/research/10_ammo_kits_input.md §3.3.
@export var max_range: float = 18.0
## Marge de tolérance ajoutée à `max_range` pour le rayon SERVEUR (m) --
## absorbe le décalage entre la vue du lanceur et celle, autoritaire, du
## serveur (même esprit que `ShotValidator.ORIGIN_TOLERANCE`).
@export var server_margin: float = 1.0
## Vitesse de traction imprimée au lanceur une fois l'ancrage validé (m/s).
@export var pull_speed: float = 22.0
## Durée maximale de traction (s) -- exposée pour un futur état de mouvement
## (relâche au Saut) ; non appliquée ici (hors des fichiers possédés par AGT-05).
@export var pull_duration: float = 0.8

func _init() -> void:
	slot = "E"
	display_name = "Piquet d'arpenteur"
	description = "Grappin qui hale vers un point d'ancrage sur le décor, jamais sur un joueur."
	cooldown = 10.0
	charges = 1

## SERVEUR : recalcule l'ancrage depuis SA PROPRE vue (jamais la position
## envoyée par le client) et, si un point de décor valide existe dans la
## portée, hale le lanceur vers lui. Sans ancrage valide, aucun effet --
## contrairement aux capacités de "pose" (StunTrap/JumpPad), qui retombent
## sur une position par défaut : un grappin qui haletait vers "nulle part"
## n'aurait aucun sens.
func activate_server(player: PlayerController, aim_dir: Vector3) -> void:
	var ctrl := player.get_node_or_null("Abilities")
	if ctrl == null or not ctrl.has_method("net_apply_impulse"):
		return
	var origin: Vector3 = player.head.global_position
	var space := player.get_world_3d().direct_space_state
	var hit := anchor_hit(space, origin, aim_dir, max_range + server_margin, _exclude_all_players(player))
	if hit.is_empty():
		return
	var to_anchor: Vector3 = hit.position - origin
	if to_anchor.length() < 0.01:
		return
	var pull: Vector3 = to_anchor.normalized() * pull_speed
	# Même motif d'appel que _spawn_stun_trap/cast_reveal (contract-r3.md) :
	# direct si le lanceur est simulé ICI (hôte/bot, autorité serveur partagée),
	# RPC ciblée sinon (client distant, mouvement client-autoritaire).
	if player.is_multiplayer_authority():
		ctrl.net_apply_impulse(pull)
	else:
		ctrl.net_apply_impulse.rpc_id(str(player.name).to_int(), pull)

## Rayon d'ancrage : masque `PhysicsLayers.SHOT_MASK` (ignore la fumée,
## calque VISION -- un grappin lancé à travers une fumée continue sa course,
## docs/audit/bugs.md BUG-06) ET exclut TOUS les joueurs (jamais un ancrage
## sur une tête, docs/research/10_ammo_kits_input.md §3.3 : "jamais sur un
## joueur"). Statique et exposé pour être testable directement
## (tests/agents/test_vanne_kit.gd), même convention que
## `StunTrapAbility.ground_hit`/`JumpPadAbility.ground_hit`.
static func anchor_hit(space: PhysicsDirectSpaceState3D, origin: Vector3, dir: Vector3, max_distance: float, exclude: Array[RID]) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * max_distance, PhysicsLayers.SHOT_MASK)
	q.exclude = exclude
	q.collide_with_areas = false
	return space.intersect_ray(q)

## Exclut le lanceur ET tous les autres joueurs de la scène (RID physique) --
## voir `anchor_hit` ci-dessus.
static func _exclude_all_players(player: PlayerController) -> Array[RID]:
	var rids: Array[RID] = [player.get_rid()]
	var players_root := player.get_parent()
	if players_root == null:
		return rids
	for child in players_root.get_children():
		if child == player:
			continue
		var body := child as CharacterBody3D
		if body:
			rids.append(body.get_rid())
	return rids
