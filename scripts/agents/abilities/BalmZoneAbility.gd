## BalmZoneAbility.gd
## E signature de Roseau, "Baume du Palud" (docs/research/
## 10_ammo_kits_input.md §3.3, fiche Roseau) : lance un bocal qui forme une
## flaque de soin pour sa cordée — le premier soin D'ALLIÉS du jeu.
## Contrairement à HealAbility (auto-soin conditionnel) et RenewalAbility
## (soin total instantané, elle seule), cette capacité pose une ZONE
## (scripts/world/HealZone.gd) qui soigne toute son ÉQUIPE (elle incluse)
## pendant sa durée : filtre d'équipe, 12 PV/s, 6 s, moitié moins vite sur une
## cible touchée depuis < 1 s (délégué à HealZone, voir sa docstring).
##
## Position calculée côté SERVEUR via un raycast le long d'`aim_dir`, même
## patron que SmokeAbility.activate_server. La pose N'EST PAS diffusée aux
## autres pairs par RPC (AbilityController.cast_* — mur/fumée/tremplin/
## piège — n'est pas dans le périmètre de fichiers de ce contrat, AGT-07) :
## la zone n'existe donc QUE côté serveur. L'effet de jeu (soin) reste
## complet et correct (Health est déjà autoritaire serveur, contract-r2.md),
## mais un client distant (pas l'hôte) ne verra pas la flaque — rendu de
## tâche : à câbler plus tard via un futur `AbilityController.cast_heal_zone`,
## hors fichiers possédés ici.
extends Ability

## Portée du lancer (m).
@export var throw_range: float = 12.0
## Rayon de la flaque (m).
@export var zone_radius: float = 4.0
## Durée de vie de la flaque (s).
@export var duration: float = 6.0
## PV/s rendus aux alliés (et à elle) dans la flaque.
@export var heal_per_second: float = 12.0
## Fenêtre (s) sous laquelle une cible touchée récemment ne reçoit que la
## moitié du soin (délégué à HealZone.recent_damage_window).
@export var recent_damage_window: float = 1.0
## Teinte sarcelle de la flaque (STYLE_BIBLE : teintes réservées à l'ennemi
## interdites dans le décor -- ce sarcelle n'est ni 300–355° ni 105–145°).
@export var color: Color = Color(0.34, 0.74, 0.68)

const HEAL_ZONE := preload("res://scripts/world/HealZone.gd")


func _init() -> void:
	slot = "E"
	display_name = "Baume du Palud"
	description = "Lance une flaque de soin qui soigne toute son équipe (elle incluse) tant qu'elle y reste."
	cooldown = 24.0
	charges = 1


func activate_server(player: PlayerController, aim_dir: Vector3) -> void:
	var tree := player.get_tree()
	if tree == null:
		return
	var scene := tree.current_scene
	if scene == null:
		return
	var origin: Vector3 = player.head.global_position if player.head else player.global_position
	var space := player.get_world_3d().direct_space_state
	var hit := trajectory_hit(space, origin, aim_dir, throw_range, [player.get_rid()])
	var pos: Vector3 = hit.position if not hit.is_empty() else origin + aim_dir * throw_range
	pos.y = maxf(pos.y, player.global_position.y)  # ne s'enfonce pas sous les pieds/le sol.
	_spawn_zone(scene, pos, int(player.get("team")))


func _spawn_zone(scene: Node, pos: Vector3, team: int) -> void:
	var zone: Area3D = HEAL_ZONE.new()
	zone.name = "HealZone"
	zone.add_to_group("round_props")  # nettoyé au passage en achat / au reset (BUG-03).
	zone.owner_team = team
	zone.heal_per_second = heal_per_second
	zone.duration = duration
	zone.recent_damage_window = recent_damage_window
	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = zone_radius
	col.shape = shape
	zone.add_child(col)
	var mesh := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = zone_radius
	sm.height = zone_radius * 2.0
	mesh.mesh = sm
	mesh.material_override = Cartoon.prop(color)
	zone.add_child(mesh)
	scene.add_child(zone)
	zone.global_position = pos


## Rayon de trajectoire (point d'atterrissage de la flaque le long d'aim_dir) :
## masque PhysicsLayers.SHOT_MASK, comme SmokeAbility -- on la traverse et on
## tire au travers d'une fumée, la flaque suit la même règle de trajectoire.
## Statique et exposé pour être testable directement (voir
## tests/agents/test_roseau_kit.gd, même patron que test_ability_rays.gd).
static func trajectory_hit(space: PhysicsDirectSpaceState3D, origin: Vector3, aim_dir: Vector3, range: float, exclude: Array[RID]) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(origin, origin + aim_dir * range, PhysicsLayers.SHOT_MASK)
	q.exclude = exclude
	q.collide_with_areas = false
	return space.intersect_ray(q)
