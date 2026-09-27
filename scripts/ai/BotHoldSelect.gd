## BotHoldSelect.gd
## Sélection PURE (tâche "bots humains", 2026-09-27, écart « ils courent
## partout dans la map ») d'un point de TENUE parmi les spots bakés par
## `BotSpots.bake` (`GameWorld.bot_spots`, tools/bake_bot_spots.gd) — un bot
## sans objectif de mode/mémoire d'équipe fraîche (Shipment : pas de
## `bot_knowledge`/`hotspots` authored, voir GameMode._bot_knowledge) doit
## désormais REJOINDRE UN SPOT À COUVERT et s'y TENIR (voir TDMMode._pick_hold_
## spot, seul consommateur, qui gère la durée de tenue U(3;8) s), plutôt que
## de patrouiller sans fin entre des marqueurs de spawn.
##
## PUR comme BotAim/BotStuck/BotMapKnowledge : aucun accès à l'arbre de scène —
## reçoit `spots` (Array de Dictionary, exactement le schéma `BotSpots.spots`,
## voir sa docstring : "position"/"coverage_crouch"/"coverage_stand"/"sniping"/
## "approach_points") en paramètre. Testé isolément dans
## tests/ai/test_bot_hold_select.gd avec des Dictionary synthétiques (pas
## besoin d'une vraie ressource BotSpots bakée pour tester le CLASSEMENT).
class_name BotHoldSelect
extends RefCounted

## Distance (m) mini/maxi d'un spot candidat depuis la position courante du
## bot — mini pour que "tenir un point" reste une VRAIE relocalisation (pas le
## spot où le bot se tient déjà), maxi pour rester une reposition raisonnable,
## pas une traversée de carte.
const MIN_RANGE_M := 4.0
const MAX_RANGE_M := 22.0
## Un spot à moins de cette distance de `exclude_pos` (le point tenu
## PRÉCÉDEMMENT par ce bot) est écarté — sans ça, "reposition" pourrait
## retomber sur le MÊME spot juste après l'avoir quitté.
const EXCLUDE_RADIUS_M := 0.5


## `spots` : Array de Dictionary (schéma `BotSpots.spots`). `exclude_pos` :
## `Vector3.INF` si aucun spot précédent à écarter. Renvoie `{"found": false}`
## si aucun spot À COUVERT ne tombe dans la bande [MIN_RANGE_M, MAX_RANGE_M]
## (hors `exclude_pos`), sinon `{"found": true, "pos": Vector3}` — un candidat
## tiré au hasard parmi ceux qui qualifient (`rng`), pas nécessairement le plus
## proche : un choix systématiquement "le plus proche" retomberait toujours
## sur le même petit sous-ensemble de spots (même écart que BUG-REGR-01,
## GameMode._pick_patrol_point).
static func pick_hold_spot(
		spots: Array,
		bot_pos: Vector3,
		exclude_pos: Vector3,
		rng: RandomNumberGenerator,
		min_range: float = MIN_RANGE_M,
		max_range: float = MAX_RANGE_M) -> Dictionary:
	var candidates: Array = []
	for entry in spots:
		var spot: Dictionary = entry
		var pos: Vector3 = spot.get("position", Vector3.ZERO)
		if exclude_pos.is_finite() and pos.distance_to(exclude_pos) <= EXCLUDE_RADIUS_M:
			continue
		var d := bot_pos.distance_to(pos)
		if d < min_range or d > max_range:
			continue
		if not BotSpots.is_covered(spot):
			continue
		candidates.append(pos)
	if candidates.is_empty():
		return {"found": false}
	return {"found": true, "pos": candidates[rng.randi() % candidates.size()]}
