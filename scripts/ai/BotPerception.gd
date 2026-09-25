## BotPerception.gd
## Capteurs complets d'un bot (BOT-03, docs/research/02_bots_ai.md §2.2 et
## tâche BOT-03) — extrait de scripts/ai/BotBrain.gd (qui gardait jusqu'ici
## la LOS mono-point et l'ouïe limitée aux tirs) :
##  - LOS multi-points (tête/torse/bassin, visible dès qu'UN point est dégagé) ;
##  - portées d'ouïe par type d'évènement (tirs/sprint ennemi/impacts proches) ;
##  - délai de perception RÉSEAU équivalent (équité bot serveur vs humain en
##    ligne, §2.2 "peeker's advantage"), réglable ;
##  - délai de réaction de PERCEPTION (orientation vers une source perçue —
##    dégât reçu — DISTINCT du délai de réaction de VISÉE de BotReaction/
##    BOT-26, qui couvre un geste plus fin) ;
##  - bus statique de partage d'équipe RETARDÉ (0.5-1 s), même schéma que
##    `Weapon.recent_gunfire`/`Weapon.recent_impacts`.
## Aucun accès à l'arbre de scène pour les fonctions qui n'en ont pas besoin
## (géométrie, portées, réaction, bus statique) — `has_los_to_any_point` reçoit
## un `PhysicsDirectSpaceState3D` déjà résolu par l'appelant (même convention
## que `BotStuck.project_strafe_to_navmesh`, qui reçoit sa navmesh en
## paramètre plutôt que d'y accéder elle-même). Consommé par
## scripts/ai/BotBrain.gd.
class_name BotPerception
extends RefCounted

# ======================================================================
#  LOS MULTI-POINTS — tête/torse/bassin (écart #8, docs/research/
#  02_bots_ai.md §4 : "un corps exposé tête cachée n'est pas vu, alors qu'une
#  tête qui dépasse de 5 cm l'est"). Visible dès qu'UN SEUL point est dégagé.
# ======================================================================

## Hauteur du point "torse"/"bassin", en fraction de `current_height`
## (PlayerController, capsule DEBOUT ou ACCROUPIE — jamais une hauteur fixe,
## même discipline que WeaponMath.is_headshot). Le point "tête" n'est PAS
## dérivé d'une fraction : il reprend directement le nœud "Head" existant
## (même position que celle déjà utilisée par la visée/le headshot), pour ne
## jamais diverger de la géométrie de tir réelle.
const TORSO_HEIGHT_RATIO := 0.55
const PELVIS_HEIGHT_RATIO := 0.28

## Les 3 points MONDE à tester pour la LOS d'une cible : tête (position réelle
## du nœud "Head"), torse, bassin — dans cet ordre (le plus déterminant en
## premier : la plupart des couvertures masquent le bas du corps avant la tête).
static func los_points(body_pos: Vector3, head_pos: Vector3, current_height: float) -> Array:
	return [
		head_pos,
		body_pos + Vector3(0.0, current_height * TORSO_HEIGHT_RATIO, 0.0),
		body_pos + Vector3(0.0, current_height * PELVIS_HEIGHT_RATIO, 0.0),
	]

## `true` si AU MOINS un des `points` est visible depuis `from` (raycast sans
## obstacle avant `target`, ou qui touche `target` lui-même — même logique
## que l'ancien `BotBrain._has_los` mono-point, répétée par point).
static func has_los_to_any_point(space: PhysicsDirectSpaceState3D, from: Vector3, points: Array, exclude_rid: RID, target: Node) -> bool:
	for p in points:
		var point: Vector3 = p
		var q := PhysicsRayQueryParameters3D.create(from, point)
		q.exclude = [exclude_rid]
		q.collide_with_areas = false
		var hit := space.intersect_ray(q)
		if hit.is_empty() or hit.collider == target:
			return true
	return false

# ======================================================================
#  OUÏE — portées par type d'évènement (écart #9, docs/research/02_bots_ai.md
#  §4 : "22 m, 1 s. Pas de pas ni d'impacts... un joueur qui sprinte derrière
#  un bot n'est jamais entendu") et §3 chiffres de référence : "tirs 40 m,
#  sprint 15 m, marche 0".
# ======================================================================
const HEAR_GUNFIRE_RADIUS_M := 40.0
const HEAR_SPRINT_RADIUS_M := 15.0
const HEAR_IMPACT_RADIUS_M := 5.0
## Fraîcheur (s) d'un évènement sonore ponctuel (tir/impact) pour être encore
## considéré "entendu maintenant" — inchangé depuis l'ancien `_hear_gunfire`
## (1.0 s), désormais partagé par les 3 sources.
const HEAR_EVENT_MEMORY_S := 1.0

## Fraction de la vitesse de sprint (`horizontal_speed()/sprint_speed`)
## au-delà de laquelle un déplacement ennemi devient audible comme un
## "sprint" — sous ce seuil (marche/course normale), le contrat BOT-03 ne
## définit aucune portée : silence, comme aujourd'hui.
const SPRINT_AUDIBLE_RATIO := 0.85

static func is_audible_sprint(speed_ratio: float) -> bool:
	return speed_ratio >= SPRINT_AUDIBLE_RATIO

# ======================================================================
#  PARTAGE D'ÉQUIPE RETARDÉ — bus STATIQUE serveur (0.5-1 s de délai, BOT-03),
#  même schéma que `Weapon.recent_gunfire`/`Weapon.recent_impacts` : un bot y
#  DÉPOSE ce qu'il vient de PERCEVOIR lui-même (jamais l'état serveur brut,
#  voir BotBrain._report_sightings), un COÉQUIPIER ne peut LIRE un dépôt que
#  `delay_s` plus tard — sans ce délai, le partage serait instantané
#  (télépathie), pas "0.5-1 s" (le temps de le dire par radio). Distinct de
#  `GameMode._last_seen_enemy`/`report_enemy_sighting` (BOT-01, hors de mon
#  périmètre) : CE bus alimente la MÉMOIRE de combat (BotMemory, position +
#  vitesse + confiance), l'autre fixe les BUTS de patrouille — deux usages,
#  deux mémoires, la même perception source (jamais un wall-hack : uniquement
#  ce qu'un bot a lui-même vu, voir `BotBrain._visible_enemies`).
# ======================================================================
static var _team_reports: Dictionary = {}  ## team:int -> Array[{"pos", "vel", "time"}]
const TEAM_REPORT_MEMORY_MAX := 16
## Au-delà de cet âge (s), un rapport n'est plus utile MÊME après son délai
## d'arrivée (mémoire BotMemory à 6 s + marge pour le délai de partage lui-même).
const TEAM_REPORT_MAX_AGE_S := 8.0

static func report_to_team(team: int, pos: Vector3, vel: Vector3, now: float) -> void:
	if not _team_reports.has(team):
		_team_reports[team] = []
	var arr: Array = _team_reports[team]
	arr.append({"pos": pos, "vel": vel, "time": now})
	while arr.size() > TEAM_REPORT_MEMORY_MAX:
		arr.pop_front()

## Rapport d'équipe le plus RÉCENT déjà "arrivé" (déposé il y a AU MOINS
## `delay_s`) à l'instant `now` — `{}` si aucun. Un dépôt trop récent (encore
## "en transit") est ignoré, jamais renvoyé en avance ; un dépôt trop vieux
## (`TEAM_REPORT_MAX_AGE_S`) est ignoré aussi (mémoire déjà épuisée de toute
## façon côté BotMemory).
static func latest_team_report(team: int, now: float, delay_s: float) -> Dictionary:
	var arr: Array = _team_reports.get(team, [])
	var best: Dictionary = {}
	for entry in arr:
		var e: Dictionary = entry
		var age := now - float(e.time)
		if age < delay_s or age > TEAM_REPORT_MAX_AGE_S:
			continue
		if best.is_empty() or float(e.time) > float(best.time):
			best = e
	return best

## Remise à zéro du bus — TESTS uniquement (chaque scénario de
## tests/ai/test_bot_memory.gd part d'un bus vide, comme les suites qui
## touchent `Weapon.recent_gunfire` le nettoient déjà entre deux cas).
static func reset_team_reports() -> void:
	_team_reports.clear()

# ======================================================================
#  DÉLAI DE PERCEPTION RÉSEAU — un bot serveur n'a structurellement AUCUNE
#  latence réseau, contrairement à un humain en ligne (71-141 ms de retard
#  structurel, peeker's advantage, docs/research/02_bots_ai.md §2.2/§3) :
#  ce délai ADDITIONNEL simule cet écart en partie EN LIGNE (réglable, défaut
#  60 ms), nul en solo (entraînement, aucun humain distant à qui l'avantage
#  profiterait). Additionné par BotBrain._aim_towards à `BotAim.
#  perception_delay_s` (voir la docstring de BotAim §A5 : "Le +60 ms « en
#  ligne » (BOT-03) n'est pas géré ici, hors de mon périmètre").
# ======================================================================

## RÉGLABLE (contrat BOT-03 : "délai de perception réseau réglable") — valeur
## par défaut 60 ms, modifiable en jeu (menu réseau futur) ou par les tests.
static var online_perception_delay_s: float = 0.06

static func network_perception_delay_s(is_online: bool) -> float:
	return online_perception_delay_s if is_online else 0.0

# ======================================================================
#  RÉACTION DE PERCEPTION — DISTINCTE de BotReaction (BOT-26, loi
#  ex-gaussienne calibrée pour la VISÉE) : ce délai plus simple couvre un
#  geste plus grossier, "tourner la tête vers ce qu'on vient de percevoir"
#  (dégât reçu, bruit) — contrat BOT-03 : "réaction = N(base, 40 ms) + 120 ms
#  si cible > 35° du centre". Même seuil d'angle que
#  `BotReaction.OFF_CENTER_ANGLE_DEG`/`OFF_CENTER_PENALTY_S` (35°/120 ms) :
#  cohérence documentée plutôt que dupliquée en aveugle, PAS un appel croisé
#  (BotReaction.gd est hors de ma liste de fichiers).
# ======================================================================
const REACTION_SIGMA_S := 0.04
const REACTION_OFF_CENTER_ANGLE_DEG := 35.0
const REACTION_OFF_CENTER_PENALTY_S := 0.12

## Base (s) de la réaction de PERCEPTION par difficulté — mêmes ordres de
## grandeur que le socle μ de BotReaction (§3.8 : "le socle reste au même
## ordre de grandeur, seule une vraie variance... s'y ajoute désormais"),
## réutilisés ici avec une loi Normale simple plutôt qu'ex-gaussienne (ce
## délai couvre un réflexe d'orientation, pas la précision fine d'un tir).
static func base_reaction_s(difficulty: int) -> float:
	match difficulty:
		MatchConfig.Difficulty.RECRUE:
			return 0.400
		MatchConfig.Difficulty.ELITE:
			return 0.200
		_:
			return 0.280  # VETERAN

## Délai (s) avant que le bot ORIENTE sa vue vers une source perçue —
## N(base, 40 ms), + 120 ms si `offset_deg` (écart angulaire entre le regard
## courant et la source à l'instant de la perception) dépasse 35°. Jamais
## négatif (un tirage extrême de la Normale pourrait autrement produire une
## réaction "avant" la perception elle-même).
static func perception_reaction_time_s(rng: RandomNumberGenerator, base_s: float, offset_deg: float) -> float:
	var t := rng.randfn(base_s, REACTION_SIGMA_S)
	if absf(offset_deg) > REACTION_OFF_CENTER_ANGLE_DEG:
		t += REACTION_OFF_CENTER_PENALTY_S
	return maxf(t, 0.0)

# ======================================================================
#  ORIENTATION VERS L'ATTAQUANT — ±20° d'erreur (BOT-03) : un bot qui vient
#  d'encaisser un coup se RETOURNE vers d'où ça vient, il ne vise pas encore
#  (contrairement à l'erreur de visée de BotAim, bien plus fine) — un
#  décalage aléatoire est appliqué autour de la direction EXACTE de
#  l'attaquant, jamais une orientation parfaite.
# ======================================================================
const DAMAGE_ORIENT_ERROR_DEG := 20.0

## Décalage aléatoire {yaw, pitch} (deg, chaque axe dans [-20°, +20°]) à
## ajouter à la direction EXACTE de l'attaquant.
static func orient_error_offset_deg(rng: RandomNumberGenerator) -> Vector2:
	return Vector2(
		rng.randf_range(-DAMAGE_ORIENT_ERROR_DEG, DAMAGE_ORIENT_ERROR_DEG),
		rng.randf_range(-DAMAGE_ORIENT_ERROR_DEG, DAMAGE_ORIENT_ERROR_DEG)
	)
