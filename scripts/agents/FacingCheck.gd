## FacingCheck.gd
## Cône de vue PUR (pas d'accès scène) : utilisé côté serveur par FlashAbility
## pour décider si une victime "fait face" au point d'éclat (contract-r2.md,
## R-B3 acceptance #2 — "flash : ... facing check from the victim's body yaw").
## Contre-jeu : une victime qui tourne le dos à la grenade n'est pas aveuglée.
## Convention de yaw identique au reste du code (DashAbility, WallAbility) :
## yaw = 0 -> le joueur fait face à -Z.
class_name FacingCheck
extends RefCounted

## `viewer_yaw` en radians (Node3D.rotation.y du corps du joueur). `fov_deg` =
## largeur TOTALE du cône (ex. 100 -> 50° de chaque côté de l'axe de face).
static func is_facing(viewer_pos: Vector3, viewer_yaw: float, target_pos: Vector3, fov_deg: float = 100.0) -> bool:
	var to_target := target_pos - viewer_pos
	to_target.y = 0.0  # le yaw ne porte que sur le plan horizontal.
	if to_target.length_squared() < 0.0001:
		return true  # la cible est juste au-dessus/en dessous du joueur -> compte comme "en face".
	to_target = to_target.normalized()
	var forward := -Basis(Vector3.UP, viewer_yaw).z
	var dot := forward.dot(to_target)
	var half_fov_cos := cos(deg_to_rad(fov_deg * 0.5))
	return dot >= half_fov_cos
