## TargetSelect.gd
## Sélection de cibles PURE (pas d'accès scène) pour les capacités à zone
## (StunBurstAbility "Déferlante", RevealAbility "Œil"/"Vision totale"...).
## Le serveur construit un tableau de candidats (Dictionary {id, pos, team, ...})
## depuis sa propre vue (joueurs vivants de la scène) puis filtre avec ces helpers
## avant d'appliquer l'effet (contract-r2.md, R-B3 acceptance #2 : "Server computes
## targets from its own view").
class_name TargetSelect
extends RefCounted

## Ne garde que les candidats à `radius` ou moins de `origin`. `exclude_team`
## (-1 par défaut = aucune exclusion) retire en plus une équipe entière — utile
## pour ne pas se cibler soi-même/son équipe une deuxième fois après `enemies_of`.
static func within_radius(origin: Vector3, candidates: Array, radius: float, exclude_team: int = -1) -> Array:
	var out: Array = []
	for c in candidates:
		var d: Dictionary = c
		if exclude_team != -1 and int(d.get("team", -1)) == exclude_team:
			continue
		var pos: Vector3 = d.get("pos", origin)
		if origin.distance_to(pos) <= radius:
			out.append(d)
	return out

## Ne garde que les candidats qui ne sont PAS dans `viewer_team` (ennemis).
static func enemies_of(candidates: Array, viewer_team: int) -> Array:
	var out: Array = []
	for c in candidates:
		var d: Dictionary = c
		if int(d.get("team", -1)) != viewer_team:
			out.append(d)
	return out
