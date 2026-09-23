## AimValidator.gd
## Validation PURE de la direction de visée envoyée par le propriétaire avec
## request_activate(i, aim_dir) (contract-r2.md, AbilityController). Le serveur
## calcule TOUJOURS les cibles depuis sa propre vue, mais a besoin d'un vecteur
## sain pour orienter les capacités dirigées (fumée, tremplin, piège, œil...).
## Même esprit que ShotValidator pour les tirs (contract-p0.md), tolérance identique.
class_name AimValidator
extends RefCounted

const MIN_LEN := 0.99
const MAX_LEN := 1.01

static func is_valid(dir: Vector3) -> bool:
	if not (is_finite(dir.x) and is_finite(dir.y) and is_finite(dir.z)):
		return false
	var len := dir.length()
	return len >= MIN_LEN and len <= MAX_LEN
