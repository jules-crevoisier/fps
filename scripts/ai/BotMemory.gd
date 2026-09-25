## BotMemory.gd
## Mémoire PURE d'un bot sur UN ennemi suivi (BOT-03, docs/research/
## 02_bots_ai.md §2.2 "Mémoire : dernière position et vitesse connues, qui
## décroissent" + écart #7 "quand la LOS se coupe... l'ennemi est oublié
## INSTANTANÉMENT"). Remplace les deux champs bruts `_last_seen_enemy_pos`/
## `_last_seen_enemy_time` de BotBrain (BOT-25) par un état {pos, vel, time}
## qui :
##  - décroît en CONFIANCE (0..1) sur CONFIDENCE_DECAY_S (6 s, §2.2) — linéaire
##    plutôt qu'exponentielle : décroît "SUR 6 s" veut dire une confiance
##    nulle À 6 s pile, une exponentielle ne s'annule jamais tout à fait ;
##  - se FUSIONNE avec une nouvelle observation (perception directe du bot OU
##    rapport d'équipe retardé, voir BotPerception.report_to_team) par une
##    moyenne PONDÉRÉE par la confiance de chaque source à l'instant `now` —
##    pas un simple "la plus récente écrase l'autre" (ça, c'est une
##    SUBSTITUTION, pas une fusion) : deux observations aussi fraîches l'une
##    que l'autre se moyennent à parts égales, une observation fraîche
##    écrase progressivement (jamais instantanément) une mémoire qui a
##    commencé à décroître.
##
## Aucun accès à l'arbre de scène — consommé par scripts/ai/BotBrain.gd
## (`_enemy_memory`, alimenté par `_visible_enemies()` et par
## `BotPerception.latest_team_report`), testé isolément dans
## tests/ai/test_bot_memory.gd.
class_name BotMemory
extends RefCounted

## Durée (s) sur laquelle la confiance d'une observation décroît linéairement
## de 1.0 (perçue à l'instant même) à 0.0 (mémoire épuisée) — BOT-03 :
## "confiance qui décroît sur 6 s". Même valeur que `BotLook.ENEMY_MEMORY_S`
## (BOT-25, cohérence documentée : les deux couvrent la même mémoire
## d'ennemi, `BotBrain._enemy_memory` alimente désormais directement le
## `ctx.has_enemy_memory`/`ctx.enemy_pos` de BotLook).
const CONFIDENCE_DECAY_S := 6.0

# ======================================================================
#  FONCTIONS STATIQUES PURES — décroissance, extrapolation, fusion.
# ======================================================================

## Confiance (0..1) d'une observation vieille de `age_s` secondes.
static func confidence_at(age_s: float) -> float:
	return clampf(1.0 - maxf(age_s, 0.0) / CONFIDENCE_DECAY_S, 0.0, 1.0)

## Position EXTRAPOLÉE (m) d'une observation {pos, vel} vieille de `age_s`
## secondes — estimation "à l'estime" (dead reckoning) : le bot va "checker"
## cette position (Booth, docs/research/02_bots_ai.md §2.1 "The bot will move
## to check the victim's last known position"), pas nécessairement là où
## l'ennemi se trouve encore réellement (d'où la confiance qui décroît en
## parallèle : au-delà de CONFIDENCE_DECAY_S, `predicted_position` reste
## calculable mais l'appelant doit avoir cessé de lui faire confiance, voir
## `has_memory`).
static func extrapolated_position(last_pos: Vector3, last_vel: Vector3, age_s: float) -> Vector3:
	return last_pos + last_vel * maxf(age_s, 0.0)

## Fusionne DEUX observations `{"pos": Vector3, "vel": Vector3, "time": float}`
## (`{}` = aucune observation) en une seule, pondérée par la confiance de
## chacune À L'INSTANT `now` (`confidence_at(now - time)`) — pas une simple
## priorité "la plus récente gagne" : c'est une moyenne, la marque d'une
## vraie fusion (voir l'en-tête). Le `time` du résultat est le PLUS RÉCENT
## des deux (l'estampille temporelle de la donnée la plus à jour disponible,
## utilisée ensuite pour la décroissance/l'extrapolation à partir du résultat
## fusionné). Si les deux confiances sont nulles (mémoires également
## épuisées), la division 0/0 est évitée en gardant simplement la plus
## récente des deux (aucune pondération n'a alors de sens).
static func fuse(a: Dictionary, b: Dictionary, now: float) -> Dictionary:
	if a.is_empty():
		return b.duplicate()
	if b.is_empty():
		return a.duplicate()
	var wa := confidence_at(now - float(a.time))
	var wb := confidence_at(now - float(b.time))
	var total := wa + wb
	if total <= 0.0001:
		return (b if float(b.time) > float(a.time) else a).duplicate()
	var pos: Vector3 = (a.pos as Vector3) * wa + (b.pos as Vector3) * wb
	var vel: Vector3 = (a.vel as Vector3) * wa + (b.vel as Vector3) * wb
	return {"pos": pos / total, "vel": vel / total, "time": maxf(float(a.time), float(b.time))}

# ======================================================================
#  ÉTAT D'INSTANCE — une mémoire PAR ennemi suivi (BotBrain n'en garde qu'une
#  seule, le dernier ennemi engagé/signalé — même granularité que l'ancien
#  `_last_seen_enemy_pos`/`_time` qu'elle remplace).
# ======================================================================

var _record: Dictionary = {}  ## `{}` (jamais observé) ou `{"pos", "vel", "time"}`.

## Enregistre une observation FRAÎCHE (perception directe OU rapport
## d'équipe déjà arrivé, voir `BotPerception.latest_team_report`) — fusionnée
## avec la mémoire existante plutôt que de l'écraser (voir `fuse`).
## `now` : horloge du RÉCEPTEUR (`BotBrain._now()`), pas forcément celle de
## l'observation elle-même (un rapport d'équipe retardé porte SON PROPRE
## `time`, antérieur à `now` — voir `fuse`, qui pondère par l'âge RÉEL de
## chaque source à `now`, pas par leur ordre d'arrivée).
func observe(pos: Vector3, vel: Vector3, time: float, now: float) -> void:
	_record = fuse(_record, {"pos": pos, "vel": vel, "time": time}, now)

## Confiance (0..1) de la mémoire courante à l'instant `now` — 0.0 si jamais
## rien observé.
func confidence(now: float) -> float:
	if _record.is_empty():
		return 0.0
	return confidence_at(now - float(_record.time))

## `true` tant que la mémoire n'est pas totalement épuisée (confiance > 0).
func has_memory(now: float) -> bool:
	return confidence(now) > 0.0

## Position extrapolée de la mémoire courante à `now` — `Vector3.INF` si
## jamais rien observé (distinct d'une position monde valide, même
## convention que `GameMode._shared_last_seen_enemy`).
func predicted_position(now: float) -> Vector3:
	if _record.is_empty():
		return Vector3.INF
	return extrapolated_position(_record.pos, _record.vel, now - float(_record.time))

## Dernière vitesse connue (`Vector3.ZERO` si jamais rien observé) —
## exposée pour un futur usage tactique (prédiction de cachette, §2.2 "Killzone
## prédit les cachettes probables"), hors périmètre de cette tâche.
func last_velocity() -> Vector3:
	return _record.get("vel", Vector3.ZERO)

## Copie en lecture seule de l'état interne — pour les tests.
func to_dict() -> Dictionary:
	return _record.duplicate()

## Oublie tout (ex. respawn/changement de manche) — jamais appelé par un
## simple "je ne le vois plus", uniquement par un évènement qui invalide
## toute mémoire passée (hors périmètre de cette tâche : aucun appelant
## actuel dans BotBrain, exposé pour un futur BOT-08/couche équipe).
func clear() -> void:
	_record = {}
