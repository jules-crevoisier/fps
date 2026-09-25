## TDMMode.gd
## Team Deathmatch : chaque élimination d'un ennemi rapporte 1 point à l'équipe.
## Première équipe à `score_to_win` éliminations gagne. Scoring serveur-autoritaire.
class_name TDMMode
extends GameMode

## 50 éliminations par défaut (contrat R2 : "50 kills ou 10 min") — GDScript
## interdit de redéclarer un @export hérité (GameMode.score_to_win = 250,
## pensé pour Hardpoint) : on change juste la valeur par défaut ici, avant
## qu'une éventuelle valeur de scène ne l'écrase.
func _init() -> void:
	score_to_win = 50

func _ready() -> void:
	super._ready()
	mode_name = "Team Deathmatch"
	hud_state = "Premier à %d éliminations" % score_to_win

## Échange de côté (maps-spec-v2.md §5.6.2/§7.5, maps ASYMÉTRIQUES seulement,
## ex. wasteland) : MapSetup positionne `asymmetric_map` (data "asymmetric")
## juste après avoir instancié ce mode — `false` par défaut => comportement
## 100% inchangé sur toute map symétrique. Décidé UNE SEULE FOIS par
## `HalfTime.should_swap` (50% du temps limite OU meneur à moitié du score
## limite), puis répliqué comme les autres RPC d'état (`sync_state`). Les
## joueurs vivants restent où ils sont — seul le PROCHAIN respawn utilise le
## nouveau côté (`GameWorld._get_spawn_position` lit `sides_swapped`).
## `side_swap_notice` : cartouche HUD ("CHANGEMENT DE CÔTÉ") — champ séparé de
## `hud_state` (texte d'objectif) pour ne rien lui faire perdre.
@export var asymmetric_map: bool = false
var sides_swapped: bool = false
var side_swap_notice: String = ""

@rpc("authority", "call_local", "reliable")
func sync_sides_swapped(swapped: bool, notice: String) -> void:
	sides_swapped = swapped
	side_swap_notice = notice
	updated.emit()

## Même garde que `GameMode._sync_state`/`_sync_sudden_death` (BUG-27) : sans
## pair assigné, `.rpc()` échoue MÊME en "call_local" pur ("Trying to call an
## RPC while no multiplayer peer is active.") — l'appel direct fait ce que
## `call_local` aurait fait en plus de la réplication, pour cette instance
## seule (aucun pair distant à qui répliquer).
func _sync_sides_swapped(swapped: bool, notice: String) -> void:
	if multiplayer.multiplayer_peer == null:
		sync_sides_swapped(swapped, notice)
	else:
		sync_sides_swapped.rpc(swapped, notice)

## Revanche (BUG-11) : sans ceci, `sides_swapped`/`side_swap_notice` d'un
## match précédent restaient affichés dès le lancement du suivant (bandeau
## "CHANGEMENT DE CÔTÉ" visible d'emblée sur une carte asymétrique, alors que
## `HalfTime.should_swap` n'a encore rien décidé pour CE match). Valeur locale
## posée directement — même patron que `GameMode._set_sudden_death` : l'état
## est déjà correct même sans pair distant connecté — puis répliquée.
func reset_match() -> void:
	super.reset_match()
	if not _is_authoritative():
		return
	sides_swapped = false
	side_swap_notice = ""
	_sync_sides_swapped(false, "")
	# BOT-23 : une revanche repart d'une patrouille neuve (plus l'ancienne
	# progression de couloir/investigation d'un match précédent).
	_lane_progress.clear()
	_investigate_goal.clear()
	_sighting_reaction.clear()
	_sighting_event_delays.clear()
	_kill_reaction.clear()
	_kill_event = {}
	_kill_event_delays.clear()
	# BOT-31 : le registre de rang par équipe et la laisse de couloir sont eux
	# aussi une progression de match — une revanche les reconstruit de zéro
	# (jamais les rangs figés du match précédent, potentiellement d'autres
	# bots/ids).
	_team_roster.clear()
	_team_rank.clear()
	_sighting_leash.clear()

## Minuteur de MATCH (10 min par défaut, voir GameMode.match_time_limit) :
## décide la victoire au score une fois le temps écoulé (GameMode._physics_process).
func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if _is_authoritative() and winner == -1 and asymmetric_map and not sides_swapped:
		if HalfTime.should_swap(match_elapsed, match_time_limit, team_scores[0], team_scores[1], score_to_win):
			_sync_sides_swapped(true, "CHANGEMENT DE CÔTÉ")

## BOT-23/T3 : un kill n'invalide plus TOUS les buts de bot (essaim, docs/
## research/08_bots_humanlike.md diagnostic #9) — seulement, sur une carte qui
## déclare `bot_knowledge` (BOT-22), les bots à moins de KILL_MOBILIZE_RANGE du
## kill OU affectés au couloir le plus proche du kill, chacun après son propre
## délai U(KILL_DELAY_MIN;KILL_DELAY_MAX) s (voir `_register_targeted_kill`/
## `_maybe_trigger_kill_reaction`). Sans `bot_knowledge` (autre carte),
## comportement HISTORIQUE inchangé : invalidation globale immédiate.
func on_kill(_killer_id: int, _victim_id: int, killer_team: int, victim_team: int) -> void:
	if not _is_authoritative() or winner != -1:
		return
	if killer_team >= 0 and killer_team != victim_team:
		team_scores[killer_team] += 1
		check_win()
	# BOT-31 (retour vérificateur) : la VICTIME perd sa progression de couloir/
	# son but d'investigation en cours — sans cela, un bot qui meurt loin de
	# son point de patrouille (typiquement après avoir enfin rejoint le
	# centre disputé, voir `LONE_BOT_START_BIAS`) réapparaissait à son spawn
	# en gardant ce but LOINTAIN, et devait retraverser la carte à CHAQUE
	# mort plutôt qu'une seule fois pour tout le match — alors que
	# `first_contact_median_s` (LD-27) se mesure PAR VIE. `_victim_id` reste
	# `-1` dans tous les tests existants (aucun ne simule une mort RÉELLE) :
	# ces `erase` y sont donc des no-op, sans effet sur les tests verrouillés.
	_lane_progress.erase(_victim_id)
	_investigate_goal.erase(_victim_id)
	_bot_goal_cache.erase(_victim_id)
	var bk: Dictionary = _bot_knowledge().get("bot_knowledge", {})
	if bk.is_empty():
		_invalidate_bot_goals()  # évènement BOT-01 : comportement historique (pas de connaissance de carte).
	else:
		_register_targeted_kill(bk, killer_team, victim_team)
	_sync_state(team_scores, winner, hud_state)


# ======================================================================
#  BOT-23 — patrouille TDM par couloir (T1), sans convergence (T2) ni
#  synchronisation (T3), sur une carte qui déclare `bot_knowledge` (BOT-22,
#  `BotMapKnowledge.gd`). LD-25 (vague 30) avait déjà branché la patrouille
#  par hotspots/lanes (`_lane_for_bot`/`_pick_hotspot` ci-dessous, CONSERVÉS
#  tels quels comme repli historique pour toute carte qui déclare des
#  `hotspots` mais pas encore de `bot_knowledge`) : cette section la
#  COMPLÈTE pour les cartes qui déclarent la connaissance plus riche de
#  BOT-22 (zones/couloirs/angles/perchoirs/couvertures/tenues Hardpoint),
#  sans rien changer pour les autres.
# ======================================================================

## Répartition FIXE par lane ET PAR ÉQUIPE (T1, docs/research/
## 08_bots_humanlike.md §3.6 : "Deux bots au Centre... Un au Nord, un au Sud")
## — indexée par le RANG (0-3) du bot PARMI CEUX DE SA PROPRE ÉQUIPE (voir
## `_team_rank_of`), jamais par `bot_id % 4` global (BOT-31, correctif du
## diagnostic (a) : 4 bots aux ids CONSÉCUTIFS couvrent toujours les 4 restes
## 0-3 dans le MÊME ORDRE quel que soit leur bloc de départ — ex. team 0
## 9001-9004 (restes 1,2,3,0) ET team 1 9005-9008 (restes 1,2,3,0, puisque
## 9005 ≡ 9001 mod 4) retombaient donc TOUJOURS sur la répartition IDENTIQUE :
## les deux équipes doublaient la MÊME lane (Centre), au lieu de couloirs
## différents, ce qui concentrait tout le trafic/les réactions sur une seule
## lane plutôt que d'en disputer plusieurs). Team 0 double le Centre (verrou
## existant, INCHANGÉ) ; team 1 double le Canyon (décision du lead 2026-09-25)
## — toute AUTRE équipe (Duo/Duel n'utilisent pas TDMMode ; un futur mode à
## équipes supplémentaires retomberait sur le motif de team 0 par défaut).
const _LANE_BY_RANK_TEAM0 := ["C", "N", "C", "S"]
const _LANE_BY_RANK_TEAM1 := ["S", "N", "S", "C"]
## Position (0/1) du bot PARMI ceux qui partagent la même lane (les deux rangs
## à la même lettre ci-dessus, quelle que soit la lettre) — sert à leur
## assigner des TRONÇONS distincts de couloir (`_lane_slot_bounds`) pour
## qu'ils ne visent jamais le même point. Motif IDENTIQUE pour les deux
## équipes (seule la LETTRE doublée change ci-dessus, jamais la position
## relative des deux bots qui la partagent).
const _LANE_SLOT_INDEX_BY_RANK := [0, 0, 1, 0]
## Nombre de bots qui partagent cette lane (2 pour la lane doublée, 1 pour
## les deux autres).
const _LANE_SLOT_COUNT_BY_RANK := [2, 1, 2, 1]

## Tenue d'un point de couloir avant de passer au suivant (T1 : "tenue de 4 à 10 s").
const LANE_HOLD_MIN := 4.0
const LANE_HOLD_MAX := 10.0

## T2 — une "dernière position partagée" ne mobilise que les bots proches ou
## inactifs, avec un délai par bot (docs/research/08_bots_humanlike.md §3.6).
const SIGHTING_MOBILIZE_RANGE := 25.0
const SIGHTING_DELAY_MIN := 0.5
const SIGHTING_DELAY_MAX := 1.0

## BOT-30 (docs/research/09_wasteland_vertical_slice.md §e, banc bots :
## changements de but 17,4/min mesurés, seuil <= 8 ; lane_share crête
## sur-représentée à 53,9 %) : écart minimal (m) entre deux "dernières
## positions vues" SUCCESSIVES pour compter comme une info d'équipe VRAIMENT
## nouvelle (voir `_maybe_trigger_sighting_reaction`). `GameMode.
## report_enemy_sighting` est appelé à CHAQUE tick où un bot perçoit encore
## l'ennemi (perception réelle, jamais un wall-hack) : sans ce seuil, un
## ennemi qui reste globalement au même endroit (recul, strafe, visée
## pendant un échange de tirs) redéclenchait un NOUVEL évènement T2 —
## nouveau délai U(0,5;1,0) s PUIS nouveau but d'investigation décalé vers
## une couverture — à quasi CHAQUE tick tant qu'il restait visible : un
## essaim CONTINU plutôt que la réaction UNIQUE que décrit T2 ("une info
## d'équipe", docs §3.6), bien au-delà du rythme "1 à 6 changements par
## minute et par bot" que B12 est censé mesurer (docs §4). Choisi sous
## l'écart minimal déjà imposé entre coéquipiers (`_spread_from_teammates`,
## 8,5 m, voir aussi `SIGHTING_MOBILIZE_RANGE` ci-dessus, un rayon
## différent) : assez grand pour ignorer la dérive d'un combat sur place,
## assez petit pour rester réactif à un déplacement RÉEL de l'ennemi vers
## une autre zone/lane. `_maybe_trigger_kill_reaction` n'a pas besoin de
## l'équivalent : un kill (T3) est déjà un évènement UNIQUE par construction
## (`_register_targeted_kill`, un seul appel par kill réel), jamais un flux
## continu comme `report_enemy_sighting`.
const SIGHTING_REPOSITION_MIN_DELTA := 6.0

## T3 — un kill n'invalide que les bots proches ou du couloir concerné, après
## un délai par bot.
const KILL_MOBILIZE_RANGE := 30.0
const KILL_DELAY_MIN := 0.3
const KILL_DELAY_MAX := 1.2

## BOT-31 (« laisse de couloir », décision du lead 2026-09-25, diagnostic (b) :
## les réactions T2/T3 mobilisaient des bots de TOUTES les lanes vers la
## dernière info — boucle de rétroaction qui vidait les autres couloirs vers
## celui de la dernière info, jusqu'à faire "gagner" une lane entière — alors
## qu'un confinement STRICT à sa propre lane, testé en passe 1 et annulé,
## tuait le combat à l'inverse : 1,67-5,00 kill/min, contact médian 12,5-26,7 s,
## voir reports/bot_bench/bot31_after.json / bot31_after_run2.json). Un bot de
## la MÊME lane que l'évènement reste mobilisable SANS restriction nouvelle
## (les seuils SIGHTING_MOBILIZE_RANGE/KILL_MOBILIZE_RANGE ci-dessus restent
## INCHANGÉS pour lui). Deux réglages testés au banc pour ces deux constantes
## (voir `_claim_sighting_out_of_lane_leash`/`_claim_kill_out_of_lane_leash`) :
## un rayon hors-lane RÉDUIT (14/16 m) a mesuré 3,33 kill/min, contact 19,7 s ;
## repris à l'IDENTIQUE des seuils propres à la lane (25/30 m, valeur retenue
## ci-dessous — la laisse "au plus un bot" devient alors la SEULE restriction,
## au plus proche du diagnostic (b) littéral).
##
## Retour du vérificateur (2026-09-25, sur reports/bot_bench/
## bot31_leash_run1.json + bot31_leash_run2.json) : 2,33-3,00 kill/min, contact
## médian 31,8-45,8 s, lane_share intérieurs 67,1-70,2 % (plafond 55 %), canyon
## 9,1-12,8 % (plancher 15 %), bloqué 2,39-3,05 % (plafond 3 %) — toujours hors
## critères. Investigation demandée pour CE retour (lecture seule de
## `BotMapKnowledge.lane_goals`, §3.7 "inversé pour l'équipe 1", et des points
## RÉELS de `WastelandBots._lanes()`) : la RÉPARTITION 2 contre 1 par lane
## (hypothèse du retour précédent, toujours VERROUILLÉE par le contrat, non
## touchée ici) n'est pas la seule cause mesurable. Un bot SEUL sur une lane
## que l'ÉQUIPE ADVERSE double (le Canyon pour team 0, le Centre pour team 1)
## démarrait sa patrouille (`_corridor_goal`, but INITIAL) au point le plus
## proche de SON PROPRE spawn (`_lane_slot_bounds` lui donne tout le tronçon
## `[1, upper]`, mais le but initial restait `bounds.x`, l'extrémité la plus
## proche du spawn) — jusqu'à 4 arrêts de tenue (4-10 s chacun, T1) avant
## d'atteindre le centre géométrique de la lane (indice 5 sur 0-10, TOUJOURS
## le point le plus disputé par construction, `_lanes()` étant symétrique
## est-ouest), pendant que l'équipe adverse y avait déjà 2 bots. Pire : cette
## progression de couloir n'était JAMAIS remise à zéro à la mort (`on_kill`
## ignorait `_victim_id`) — un bot qui meurt loin de son point de patrouille
## (typiquement APRÈS avoir enfin atteint le centre) réapparaissait à son
## spawn mais gardait ce but lointain, donc devait retraverser la moitié de
## la carte à CHAQUE vie, pas seulement à la toute première. Comme
## `first_contact_median_s` (LD-27) se mesure PAR VIE (remise à zéro à chaque
## spawn), ce trajet répété à chaque mort, pour le bot SEUL d'une lane
## doublée, pèse sur la médiane à CHAQUE respawn, pas une fois pour tout le
## match. Correctif (voir `_opponent_doubles_lane`/le but initial biaisé de
## `_corridor_goal`, et la remise à zéro de `_lane_progress`/`_investigate_
## goal`/`_bot_goal_cache` de la VICTIME dans `on_kill` ci-dessous) : reste
## dans mon périmètre de fichiers (TDMMode.gd), ne touche PAS à la répartition
## par rang ni à la règle "au plus un bot hors-lane, le plus proche" — les
## deux VERROUILLÉES par le contrat — et laisse `SIGHTING_MOBILIZE_RANGE_OUT_
## OF_LANE`/`KILL_MOBILIZE_RANGE_OUT_OF_LANE` INCHANGÉES (identiques aux
## seuils propres à la lane, valeur déjà retenue au retour précédent).
##
## Résultat (reports/bot_bench/bot31_fix_run1.json + bot31_fix_run2.json,
## même commande que le retour vérificateur) — AVANT (bot31_leash_run1/run2)
## -> APRÈS (bot31_fix_run1/run2) : kills/min 2,33-3,00 -> 8,00-11,00 (critère
## >= 5, les DEUX runs passent désormais) ; contact médian 31,8-45,8 s ->
## 9,47-12,84 s (critère <= 9 s, run2 rate de 0,47 s SEULEMENT — amélioration
## de ~4x, mais n'atteint pas encore le plafond dans les deux runs) ; bloqué
## 2,39-3,05 % -> 2,87-2,99 % (critère <= 3 %, les DEUX runs passent
## désormais) ; lane_share canyon 9,1-12,8 % -> 19,9-35,6 % (critère >= 15 %,
## les DEUX runs passent) ; lane_share intérieurs 67,1-70,2 % -> 43,2-63,1 %
## (critère <= 55 %, run1 passe à 43,2 %, run2 dépasse encore à 63,1 % — la
## variance entre les deux runs, sur QUI gagne le centre disputé, reste plus
## grande que la marge du critère). `hp_zone_occupancy_min_ratio` (Hardpoint,
## code NON touché par ce correctif TDM) : 67,5 %/91,1 %, déjà mesuré
## historiquement entre 43,7 % et 86,0 % sur la seule géométrie (docs/
## PLAYTEST.md §2) — variance PRÉEXISTANTE, pas une régression de ce
## correctif. Effet de bord observé, HORS des critères d'acceptation de cette
## tâche : `goal_changes_per_min` (seuil BOT-13 générique <= 8/min, pas un
## critère LD-27/BOT-31) passe de 3,6-4,2 à 10,5-11,3 — plus de morts/min
## (kills/min presque quadruplé) génèrent mécaniquement plus de remises à
## zéro de but (`on_kill` ci-dessous) — signalé au lead, non corrigé ici (le
## réduire reviendrait à limiter le taux de kill que ce correctif vise à
## relever).
const SIGHTING_MOBILIZE_RANGE_OUT_OF_LANE := SIGHTING_MOBILIZE_RANGE
const KILL_MOBILIZE_RANGE_OUT_OF_LANE := KILL_MOBILIZE_RANGE

## BOT-31 (retour vérificateur) : fraction de la profondeur du tronçon
## `[bounds.x, bounds.y]` (voir `_lane_slot_bounds`) dont le but INITIAL d'un
## bot SEUL sur une lane doublée par l'équipe adverse (`_opponent_doubles_
## lane`) est avancé au-delà de `bounds.x` (l'extrémité la plus proche de son
## propre spawn) — jamais jusqu'au centre exact (fraction 1,0), pour rester
## une patrouille PLAUSIBLE (pas un bot qui débarque instantanément au front)
## et ne pas mobiliser la laisse hors-lane d'un évènement déjà couvert par un
## test verrouillé (`tests/ai/test_bot_goals.gd::
## test_tdm_kill_only_invalidates_bots_near_the_kill_or_the_corridor_
## concerned_after_a_delay`, bot 3 hors de portée de 30 m depuis un point trop
## avancé). 1/3 : franchit les arrêts de tenue les plus proches du spawn
## (jamais utiles au contact) sans pour autant démarrer déjà au milieu de la
## lane adverse. N'affecte JAMAIS un bot dont la lane n'est PAS doublée côté
## adverse (Nord, ni doublée par team 0 ni par team 1) ni un bot d'une PAIRE
## (le bot du tronçon profond d'une lane doublée démarre déjà près du centre,
## `bounds.x` de son propre tronçon ; voir `_LANE_SLOT_INDEX_BY_RANK`).
const LONE_BOT_START_BIAS := 1.0 / 3.0

## Durée pendant laquelle un bot investigue le point retenu (sighting décalé
## vers une couverture, ou approximation de la position d'un kill) avant de
## reprendre sa patrouille de couloir — réglage maison (pas de valeur donnée
## par le contrat pour la durée d'investigation elle-même, seulement pour le
## délai de MOBILISATION ci-dessus) : `ENEMY_MEMORY_TTL` (mémoire d'équipe)
## pour un sighting réel, un peu moins pour un simple kill (indice plus
## indirect de la position ennemie).
const KILL_INVESTIGATE_TTL := 4.0

## B12 (docs/research/08_bots_humanlike.md §4) : "jamais 3 bots ou plus qui
## changent de but dans la même fenêtre de 200 ms" — les délais U(...) tirés
## indépendamment pour plusieurs bots d'un MÊME évènement (sighting ou kill)
## pourraient par pur hasard tomber à moins de 200 ms l'un de l'autre :
## `_spaced_delay` les espace d'AU MOINS cette marge. Réglé au-delà de 200 ms
## (avec une marge qui absorbe le pas de simulation/serveur, jamais infiniment
## fin) pour rester du bon côté de la fenêtre en toute rigueur.
const MIN_EVENT_SPACING := 0.35

## Rare paire de points de couloirs DIFFÉRENTS mesurée à moins de 8 m l'une de
## l'autre sur la géométrie RÉELLE de Wasteland (`WastelandBots._bk_corridors`) :
## couloir Sud, point d'indice 6 (13; 0.37; 9.5, quai du Hangar) à 7,6 m du
## couloir Centre, point d'indice 6 (10; 0; 2.5) — sous le seuil d'écartement
## coéquipiers (T1/BOT-23, acceptance "8 m dans 90 % des échantillons"). Ce
## point est donc SAUTÉ par la patrouille (voir `_corridor_goal`) : aucun
## autre point du couloir Sud n'est à moins de 8 m d'un point du couloir
## Centre ou du couloir Nord (vérifié point à point sur les données réelles).
const _EXCLUDED_LANE_INDICES := {"S": [6]}

## team -> Array[int] (bot_id, ordre de PREMIÈRE observation par ce mode) —
## registre PAR ÉQUIPE construit ici même (BOT-31 : "calculé dans TDMMode",
## puisque `GameMode` n'en tient aucun, voir la docstring de
## `_LANE_BY_RANK_TEAM0` ci-dessus) : le rang (index dans ce tableau) de
## `bot_id` sert à choisir sa lane, JAMAIS son `bot_id` global. Figé pour
## chaque bot_id dès sa 1ère apparition (voir `_team_rank_of`) — RAZ par
## `reset_match` comme le reste de l'état bot ci-dessous.
var _team_roster: Dictionary = {}
## bot_id -> int (0-3) — rang déjà résolu (mémoïsation de `_team_rank_of`,
## sans quoi son rang dériverait si `_team_roster[team]` grandissait encore
## après sa 1ère observation).
var _team_rank: Dictionary = {}

## bot_id -> {"idx": int, "dir": 1|-1, "state": "walking"|"holding",
## "hold_until": float} — progression de PATROUILLE DE COULOIR (T1) de
## `bot_id` le long des points de sa lane assignée (voir `_corridor_goal`).
var _lane_progress: Dictionary = {}

## bot_id -> {"pos": Vector3, "expires_at": float} — but d'INVESTIGATION en
## cours (T2 sighting ou T3 kill, voir `_wasteland_bot_goal`), prioritaire sur
## la patrouille de couloir tant que non expiré.
var _investigate_goal: Dictionary = {}

## bot_id -> {"pos": Vector3, "eligible": bool, "deadline": float,
## "applied": bool} — suivi PAR BOT de la dernière "dernière position
## partagée" (T2) déjà évaluée, pour ne tirer son délai et son éligibilité
## qu'UNE FOIS par sighting (et ne pas les re-tirer à chaque tick tant que
## l'équipe continue de signaler la MÊME position).
var _sighting_reaction: Dictionary = {}
## "team:pos" -> Array[float] — délais déjà tirés pour CET évènement de
## sighting (anti-collision B12, voir `_spaced_delay`).
var _sighting_event_delays: Dictionary = {}
## "team:pos" -> {"bot_id": int, "dist": float} — l'UNIQUE bot hors-lane
## actuellement retenu (le plus proche observé jusqu'ici) pour CET évènement
## de sighting (BOT-31, laisse de couloir), voir
## `_claim_sighting_out_of_lane_leash`. Absent tant qu'aucun bot hors-lane
## éligible n'a encore été observé pour cette position.
var _sighting_leash: Dictionary = {}

## {"serial": int, "pos": Vector3, "lane": String, "time": float} — dernier
## kill CIBLABLE (T3, position connue). Vide si aucun kill localisable n'a
## encore eu lieu (voir `_register_targeted_kill`).
var _kill_event: Dictionary = {}
var _kill_serial: int = 0
## bot_id -> {"serial": int, "eligible": bool, "deadline": float,
## "applied": bool} — même rôle que `_sighting_reaction`, pour `_kill_event`.
var _kill_reaction: Dictionary = {}
## Délais déjà tirés pour l'évènement `_kill_event` COURANT (anti-collision B12).
var _kill_event_delays: Array = []

## team -> Array[float] — horodatages des derniers changements de but
## (VALEUR différente, pas juste un recalcul) déjà accordés à cette équipe,
## glissant sur MIN_EVENT_SPACING*... : voir `_may_register_change`, le garde-
## fou B12 qui s'applique à TOUTE source de changement (couloir T1, sighting
## T2, kill T3, reprise de patrouille après investigation) — pas seulement
## aux délais eux-mêmes déjà espacés par `_spaced_delay` au sein d'un même
## évènement : deux évènements DIFFÉRENTS (ex. la fin d'une investigation
## pour un bot pendant que le couloir d'un autre avance par pur hasard)
## pourraient sinon se percuter.
var _recent_change_times: Dictionary = {}


## Rang (0-3) de `bot_id` PARMI LES BOTS DE `team` (BOT-31) — établi et figé à
## sa 1ère observation par CE mode (ordre d'arrivée dans `_team_roster[team]`),
## jamais recalculé ensuite même si d'autres bots de la même équipe
## apparaissent après lui (une lane assignée ne doit pas changer en cours de
## match, `_lane_progress`/les tronçons de couloir en dépendent). `% 4` en
## sortie par sécurité (repli défensif : une équipe TDM compte normalement
## exactement 4 bots/joueurs, jamais plus, voir `_LANE_BY_RANK_TEAM0`).
func _team_rank_of(team: int, bot_id: int) -> int:
	if _team_rank.has(bot_id):
		return int(_team_rank[bot_id])
	var roster: Array = _team_roster.get(team, [])
	var rank: int = roster.size() % 4
	roster.append(bot_id)
	_team_roster[team] = roster
	_team_rank[bot_id] = rank
	return rank


## Lane assignée à `bot_id` DE `team` (T1) — voir `_LANE_BY_RANK_TEAM0`/
## `_LANE_BY_RANK_TEAM1` (BOT-31 : indexé par le RANG par équipe, plus par
## `bot_id % 4` global).
func _lane_for_bot_id(team: int, bot_id: int) -> String:
	var rank := _team_rank_of(team, bot_id)
	var by_rank: Array = _LANE_BY_RANK_TEAM1 if team == 1 else _LANE_BY_RANK_TEAM0
	return by_rank[rank]


## BOT-31 (retour vérificateur) : vrai si l'équipe ADVERSE de `team` double
## `lane` (compte `_LANE_BY_RANK_TEAM0`/`_LANE_BY_RANK_TEAM1` de L'AUTRE
## équipe) — jamais la répartition de `team` elle-même. Sert uniquement à
## décider si le bot SEUL de `team` sur `lane` doit démarrer sa patrouille
## déjà avancé vers le centre (voir `LONE_BOT_START_BIAS`/`_corridor_goal`) :
## si personne ne double `lane` en face (cas du Nord, jamais doublé par
## aucune équipe), la patrouille symétrique 1v1 d'origine (T1, BOT-23) reste
## inchangée — démarrage à `bounds.x`, comme avant BOT-31.
func _opponent_doubles_lane(team: int, lane: String) -> bool:
	var opponent_by_rank: Array = _LANE_BY_RANK_TEAM0 if team == 1 else _LANE_BY_RANK_TEAM1
	var count := 0
	for l in opponent_by_rank:
		if String(l) == lane:
			count += 1
	return count >= 2


## Vrai si un changement de but pour `team` peut avoir lieu maintenant sans
## violer B12 ("jamais 3 changements ou plus dans une fenêtre de 200 ms") —
## et l'enregistre alors. Sinon (déjà 2 changements récents dans la fenêtre),
## refuse : l'appelant doit REPORTER son changement de quelques dixièmes de
## seconde plutôt que de l'appliquer maintenant.
func _may_register_change(team: int, now: float) -> bool:
	var recent: Array = _recent_change_times.get(team, [])
	var kept: Array = []
	for t in recent:
		if now - float(t) < 0.2:
			kept.append(t)
	if kept.size() >= 2:
		_recent_change_times[team] = kept
		return false
	kept.append(now)
	_recent_change_times[team] = kept
	return true


## Vrai si `idx` est un point de couloir à éviter (voir `_EXCLUDED_LANE_INDICES`).
func _is_excluded_index(lane: String, idx: int) -> bool:
	return (_EXCLUDED_LANE_INDICES.get(lane, []) as Array).has(idx)


## Tronçon [lo, hi] (indices INCLUS dans les points INTÉRIEURS 1..upper d'une
## lane, voir `_corridor_goal`) réservé à `bot_id` — partage la lane en
## `_LANE_SLOT_COUNT_BY_RANK` tronçons de taille égale et confine sa
## progression à l'INTÉRIEUR du sien : deux bots d'une même lane (les deux
## bots "Centre", T1) ne visent alors JAMAIS le même point ni des points
## voisins de part et d'autre d'une frontière commune, ce qui garantit
## l'écart d'au moins 8 m entre leurs buts (au lieu de le confier au hasard
## d'une progression non bornée qui finirait par les faire coïncider en fin
## de lane). Un seul tronçon (Nord/Sud, une seule lane chacun) couvre toute
## la plage 1..upper, comportement inchangé.
func _lane_slot_bounds(team: int, bot_id: int, upper: int) -> Vector2i:
	var rank := _team_rank_of(team, bot_id)
	var slot_index: int = _LANE_SLOT_INDEX_BY_RANK[rank]
	var slot_count: int = _LANE_SLOT_COUNT_BY_RANK[rank]
	if slot_count <= 1 or upper <= 1:
		return Vector2i(1, upper)
	var chunk: int = maxi(upper / slot_count, 1)
	var lo: int = 1 + slot_index * chunk
	var hi: int = upper if slot_index == slot_count - 1 else mini(lo + chunk - 1, upper)
	lo = clampi(lo, 1, upper)
	hi = clampi(hi, lo, upper)
	return Vector2i(lo, hi)


## But de patrouille de couloir (T1) pour `bot_id` : le point SUIVANT de sa
## lane assignée, tenu 4 à 10 s une fois atteint, puis le point suivant — un
## aller-retour continu (jamais figé en bout de lane) entre les bornes de son
## tronçon (`_lane_slot_bounds`), en excluant les DEUX extrémités de la lane
## (les points 0 et dernier sont les marqueurs de spawn des deux équipes,
## voir `WastelandBots._bk_corridors` — "la patrouille ne lit plus les
## marqueurs de spawn" est ainsi vrai même si ces coordonnées apparaissent,
## par construction géométrique, aux deux bouts du couloir).
func _corridor_goal(know: BotMapKnowledge, team: int, bot_id: int, bot_pos: Vector3, reached: bool) -> Vector3:
	var lane := _lane_for_bot_id(team, bot_id)
	var points := know.lane_goals(team, lane)
	if points.size() < 4:
		return points[0] if not points.is_empty() else Vector3.ZERO
	var upper := points.size() - 2
	var bounds := _lane_slot_bounds(team, bot_id, upper)
	var progress: Dictionary = _lane_progress.get(bot_id, {})
	var now := _goal_clock_now()
	if progress.is_empty():
		# BOT-31 (retour vérificateur) : le bot SEUL d'une lane doublée par
		# l'équipe adverse (Canyon pour team 0, Centre pour team 1, voir
		# `_opponent_doubles_lane`) démarre avancé vers le centre géométrique
		# de la lane (TOUJOURS le point le plus disputé, `_lanes()` étant
		# symétrique est-ouest) plutôt qu'à l'extrémité `bounds.x` la plus
		# proche de son propre spawn — sinon, seul face à 2 adversaires déjà
		# répartis sur toute la lane, il ne rejoignait le centre qu'après
		# plusieurs arrêts de tenue (T1, 4-10 s chacun). Un bot en PAIRE (sur
		# une lane doublée par SA PROPRE équipe) ou sur une lane non doublée
		# par personne (Nord) garde `bounds.x`, comportement T1 inchangé.
		var start_idx := bounds.x
		if _LANE_SLOT_COUNT_BY_RANK[_team_rank_of(team, bot_id)] == 1 \
				and _opponent_doubles_lane(team, lane):
			start_idx = bounds.x + int(round(float(bounds.y - bounds.x) * LONE_BOT_START_BIAS))
			start_idx = clampi(start_idx, bounds.x, bounds.y)
		progress = {"idx": start_idx, "dir": 1, "state": "walking", "hold_until": 0.0}
		_lane_progress[bot_id] = progress
		return points[start_idx]

	var idx: int = int(progress["idx"])
	if String(progress["state"]) == "walking":
		if reached:
			# But de couloir ATTEINT : on le TIENT 4-10 s (T1) avant d'avancer.
			progress["state"] = "holding"
			progress["hold_until"] = now + _rng.randf_range(LANE_HOLD_MIN, LANE_HOLD_MAX)
			_lane_progress[bot_id] = progress
		return points[idx]

	# state == "holding"
	if now >= float(progress["hold_until"]):
		if _may_register_change(team, now):
			var dir: int = int(progress["dir"])
			var guard := 0
			while guard < 6:
				if idx + dir > bounds.y or idx + dir < bounds.x:
					dir = -dir  # bout du tronçon : demi-tour (aller-retour continu).
				idx += dir
				guard += 1
				if not _is_excluded_index(lane, idx):
					break
			# Garde-fou (tronçon dégénéré à un seul point, jamais le cas sur les
			# données RÉELLES de Wasteland où chaque tronçon en compte plusieurs) :
			# ne sort jamais des bornes du tronçon.
			idx = clampi(idx, bounds.x, bounds.y)
			progress["idx"] = idx
			progress["dir"] = dir
			progress["state"] = "walking"
		else:
			# B12 : ce changement percuterait 2 autres changements récents de
			# l'équipe dans la même fenêtre de 200 ms — on prolonge la tenue
			# d'un peu et on retentera au prochain appel (voir `_may_register_change`).
			progress["hold_until"] = now + MIN_EVENT_SPACING
		_lane_progress[bot_id] = progress
	return points[idx]


## Point décalé d'environ 3 m vers la couverture la plus proche de `pos` (T2 :
## "point décalé de ±3 m vers une couverture") — jamais `pos` lui-même
## (investiguer une position signalée à couvert plutôt qu'à découvert). `pos`
## inchangé si la carte ne déclare aucune couverture, ou si `pos` est
## quasiment SUR la couverture la plus proche (rien à décaler).
func _cover_offset(bk: Dictionary, pos: Vector3) -> Vector3:
	var covers: Array = bk.get("covers", [])
	if covers.is_empty():
		return pos
	var nearest_pos: Vector3 = (covers[0] as Dictionary)["pos"]
	var nearest_dist := pos.distance_to(nearest_pos)
	for entry in covers:
		var d := pos.distance_to((entry as Dictionary)["pos"])
		if d < nearest_dist:
			nearest_dist = d
			nearest_pos = (entry as Dictionary)["pos"]
	var to_cover := nearest_pos - pos
	var dist := to_cover.length()
	if dist < 0.01:
		return pos
	return pos + to_cover.normalized() * minf(3.0, dist)


## Écarte `pos` (le point d'investigation qu'on s'apprête à donner à `bot_id`)
## de tout AUTRE point d'investigation déjà en cours pour un coéquipier — T1/
## BOT-23 (écart coéquipiers >= 8 m) s'applique aussi à l'investigation
## (T2/T3) : plusieurs bots proches d'une MÊME dernière position partagée ou
## d'un même kill se dirigeraient sinon TOUS vers le même point de couverture
## le plus proche (`_cover_offset`), s'y empilant. Écarté d'AU MOINS
## `min_dist`, dans la direction opposée au voisin le plus proche déjà réglé.
func _spread_from_teammates(bot_id: int, pos: Vector3, min_dist: float = 8.5) -> Vector3:
	var result := pos
	var guard := 0
	while guard < 6:
		var clash := false
		for other_id in _investigate_goal.keys():
			if int(other_id) == bot_id:
				continue
			var other_pos: Vector3 = (_investigate_goal[other_id] as Dictionary)["pos"]
			var d := result.distance_to(other_pos)
			if d < min_dist:
				clash = true
				var away := result - other_pos
				if away.length() < 0.01:
					away = Vector3(1.0, 0.0, 0.0)
				result = other_pos + away.normalized() * min_dist
				break
		if not clash:
			break
		guard += 1
	return result


## Lane dont un point est le plus proche de `pos` (T3 : "le couloir concerné"
## par un kill) — parcourt les 3 couloirs déclarés par `bot_knowledge`.
func _nearest_lane(bk: Dictionary, pos: Vector3) -> String:
	var corridors: Dictionary = bk.get("corridors", {})
	var best_lane := ""
	var best_dist := INF
	for lane in corridors.keys():
		for p in (corridors[lane] as Array):
			var d: float = pos.distance_to(p as Vector3)
			if d < best_dist:
				best_dist = d
				best_lane = String(lane)
	return best_lane


## Tire un délai dans [lo, hi] en veillant à rester à au moins
## `MIN_EVENT_SPACING` de tout délai déjà tiré (`existing`) pour le MÊME
## évènement (sighting ou kill) — garantit B12 ("jamais 3 changements ou plus
## en 200 ms") PAR CONSTRUCTION plutôt que par chance statistique : les
## réactions d'un même évènement restent toujours espacées d'au moins cette
## marge, quelle que soit la graine du RNG.
func _spaced_delay(existing: Array, lo: float, hi: float) -> float:
	var candidate := _rng.randf_range(lo, hi)
	var guard := 0
	while guard < 8:
		var clashes := false
		for e in existing:
			if absf(candidate - float(e)) < MIN_EVENT_SPACING:
				clashes = true
				break
		if not clashes:
			break
		candidate += MIN_EVENT_SPACING
		if candidate > hi:
			candidate = lo + fmod(candidate - lo, maxf(hi - lo, 0.001))
		guard += 1
	return candidate


## T3 — enregistre un kill CIBLABLE : sa position est une APPROXIMATION (on
## ne reçoit ni la position du kill ni celle d'un joueur ici, seulement les
## équipes — `on_kill`/`GameWorld._on_player_died`, hors de ma liste de
## fichiers, ne portent pas cette donnée) prise sur la mémoire d'équipe la
## plus fraîche : celle de l'équipe qui vient de marquer (elle a
## nécessairement VU sa victime juste avant), puis celle de la victime en
## repli. Aucune mémoire fraîche pour AUCUNE équipe (pas de contact visuel
## préalable signalé) : position inconnue -> repli sûr sur l'invalidation
## globale HISTORIQUE (comportement inchangé), plutôt que de deviner.
func _register_targeted_kill(bk: Dictionary, killer_team: int, victim_team: int) -> void:
	var pos := _shared_last_seen_enemy(killer_team)
	if pos == Vector3.INF:
		pos = _shared_last_seen_enemy(victim_team)
	if pos == Vector3.INF:
		_invalidate_bot_goals()
		return
	_kill_serial += 1
	_kill_event = {"serial": _kill_serial, "pos": pos, "lane": _nearest_lane(bk, pos), "time": _goal_clock_now()}
	_kill_event_delays = []


## Évalue/applique, pour CE bot, la réaction (T3) au dernier `_kill_event` —
## appelé à CHAQUE `bot_goal_for` (avant le mécanisme générique de cache) afin
## d'observer le délai individuel même quand ce bot est loin de son but (donc
## jamais "reached", voir `GameMode.bot_goal_for`). N'agit qu'UNE FOIS par
## évènement (suivi par `serial`) : la première évaluation tire (ou refuse)
## l'éligibilité et le délai, une évaluation ultérieure ne fait qu'attendre
## puis appliquer — sous réserve de `_may_register_change` (B12) : si
## appliquer maintenant percuterait 2 autres changements récents de l'équipe,
## le délai est repoussé d'un cran plutôt qu'appliqué.
func _maybe_trigger_kill_reaction(bk: Dictionary, team: int, bot_id: int, bot_pos: Vector3) -> void:
	if _kill_event.is_empty():
		return
	var serial: int = int(_kill_event["serial"])
	var state: Dictionary = _kill_reaction.get(bot_id, {})
	if int(state.get("serial", -1)) != serial:
		var lane := _lane_for_bot_id(team, bot_id)
		var kill_pos: Vector3 = _kill_event["pos"]
		var out_of_lane := lane != String(_kill_event["lane"])
		# BOT-31 : la MÊME lane que le kill reste mobilisable SANS restriction
		# nouvelle (comportement HISTORIQUE inchangé, "les seuils existants
		# restent pour la lane propre") ; une AUTRE lane ne l'est plus que par
		# la laisse (au plus un bot, le plus proche, voir la constante
		# `KILL_MOBILIZE_RANGE_OUT_OF_LANE`).
		var eligible := true if not out_of_lane \
				else _claim_kill_out_of_lane_leash(bot_id, bot_pos.distance_to(kill_pos))
		var delay := 0.0
		if eligible:
			delay = _spaced_delay(_kill_event_delays, KILL_DELAY_MIN, KILL_DELAY_MAX)
			_kill_event_delays.append(delay)
		state = {"serial": serial, "eligible": eligible, "out_of_lane": out_of_lane,
				"deadline": float(_kill_event["time"]) + delay, "applied": false}
		_kill_reaction[bot_id] = state
	if state.get("eligible", false) and not state.get("applied", false) \
			and _goal_clock_now() >= float(state.get("deadline", 0.0)):
		if not _may_register_change(team, _goal_clock_now()):
			state["deadline"] = _goal_clock_now() + MIN_EVENT_SPACING
			_kill_reaction[bot_id] = state
			return
		state["applied"] = true
		_kill_reaction[bot_id] = state
		var goal_pos := _spread_from_teammates(bot_id, _cover_offset(bk, _kill_event["pos"] as Vector3))
		# BOT-31 : un bot mobilisé HORS de sa lane (laisse) revient à sa
		# patrouille après LANE_HOLD_MAX s sans nouveau contact, plutôt que la
		# TTL d'investigation courte (KILL_INVESTIGATE_TTL) réservée à la lane
		# propre — voir la docstring de `KILL_MOBILIZE_RANGE_OUT_OF_LANE`.
		var ttl := LANE_HOLD_MAX if state.get("out_of_lane", false) else KILL_INVESTIGATE_TTL
		_investigate_goal[bot_id] = {"pos": goal_pos, "expires_at": _goal_clock_now() + ttl}
		_bot_goal_cache.erase(bot_id)


## Laisse de couloir (T3, BOT-31) : n'accorde la mobilisation HORS-LANE
## qu'au bot le plus proche du kill parmi ceux déjà observés pour CET
## évènement (`_kill_event`, remis à zéro à chaque nouveau kill CIBLABLE, voir
## `_register_targeted_kill`) — au plus UN à la fois. Un bot plus proche que
## le titulaire actuel le REMPLACE (`_release_out_of_lane_leash` fait revenir
## l'ancien titulaire à sa patrouille) : le titulaire final, une fois tous les
## bots de l'équipe observés pour cet évènement, est bien le plus proche.
func _claim_kill_out_of_lane_leash(bot_id: int, dist: float) -> bool:
	if dist > KILL_MOBILIZE_RANGE_OUT_OF_LANE:
		return false
	var holder_id: int = int(_kill_event.get("leash_bot_id", -1))
	if holder_id != -1 and holder_id != bot_id and dist >= float(_kill_event.get("leash_dist", INF)):
		return false
	if holder_id != -1 and holder_id != bot_id:
		_release_out_of_lane_leash(_kill_reaction, holder_id)
	_kill_event["leash_bot_id"] = bot_id
	_kill_event["leash_dist"] = dist
	return true


## Fait revenir `prev_bot_id` à sa patrouille de couloir (BOT-31, laisse) :
## soit il vient d'expirer (LANE_HOLD_MAX sans nouveau contact, voir
## `_wasteland_bot_goal`), soit un AUTRE bot hors-lane, plus proche, vient de
## lui prendre sa place de titulaire unique (voir `_claim_kill_out_of_lane_
## leash`/`_claim_sighting_out_of_lane_leash`) — dans les deux cas, sa
## réaction en cours est invalidée et son but recalculé au prochain appel.
func _release_out_of_lane_leash(reaction_map: Dictionary, prev_bot_id: int) -> void:
	if reaction_map.has(prev_bot_id):
		var st: Dictionary = reaction_map[prev_bot_id]
		st["eligible"] = false
		reaction_map[prev_bot_id] = st
	_investigate_goal.erase(prev_bot_id)
	_bot_goal_cache.erase(prev_bot_id)


## Même rôle que `_maybe_trigger_kill_reaction`, pour la dernière position
## d'ennemi PARTAGÉE par l'équipe (T2) — n'éligibilise que les bots à moins de
## SIGHTING_MOBILIZE_RANGE du point OU "inactifs" (aucune progression de
## couloir encore établie : `_lane_progress` vide pour ce bot, lu comme
## "vient de spawn/n'a encore rien à faire", cf. contrat T2 "ou inactifs").
## Redessine l'éligibilité/le délai dès que la position SIGNALÉE change
## réellement (`is_new`) — pas à chaque tick de rafraîchissement de la MÊME
## position (sinon le délai ne finirait jamais de s'écouler tant que l'équipe
## continue de voir le même ennemi), ni sur une simple DÉRIVE sous
## SIGHTING_REPOSITION_MIN_DELTA (BOT-30 : un ennemi qui reste globalement au
## même endroit d'un tick à l'autre — recul, strafe, visée — n'est pas une
## information nouvelle, voir la docstring de la constante).
func _maybe_trigger_sighting_reaction(bk: Dictionary, team: int, bot_id: int, bot_pos: Vector3) -> void:
	var seen := _shared_last_seen_enemy(team)
	if seen == Vector3.INF:
		return
	var state: Dictionary = _sighting_reaction.get(bot_id, {})
	var is_new := state.is_empty() \
			or (state.get("pos", Vector3.INF) as Vector3).distance_to(seen) >= SIGHTING_REPOSITION_MIN_DELTA
	if is_new:
		var key := "%d:%s" % [team, seen]
		var lane := _lane_for_bot_id(team, bot_id)
		var event_lane := _nearest_lane(bk, seen)
		var out_of_lane := lane != event_lane
		var eligible: bool
		if not out_of_lane:
			# BOT-31 : la MÊME lane que l'info reste mobilisable SANS
			# restriction nouvelle — formule HISTORIQUE inchangée ("les
			# seuils existants restent pour la lane propre").
			var inactive := not _lane_progress.has(bot_id)
			eligible = inactive or bot_pos.distance_to(seen) <= SIGHTING_MOBILIZE_RANGE
		else:
			# Une AUTRE lane ne l'est plus que par la laisse (au plus un bot,
			# le plus proche) — jamais via "inactif" (un bot tout juste réveillé
			# hors de sa lane ne doit pas se précipiter vers une info d'une
			# lane qui n'est pas la sienne).
			eligible = _claim_sighting_out_of_lane_leash(key, bot_id, bot_pos.distance_to(seen))
		var delay := 0.0
		if eligible:
			var existing: Array = _sighting_event_delays.get(key, [])
			delay = _spaced_delay(existing, SIGHTING_DELAY_MIN, SIGHTING_DELAY_MAX)
			existing.append(delay)
			_sighting_event_delays[key] = existing
		state = {"pos": seen, "eligible": eligible, "out_of_lane": out_of_lane,
				"deadline": _goal_clock_now() + delay, "applied": false}
		_sighting_reaction[bot_id] = state
	if state.get("eligible", false) and not state.get("applied", false) \
			and _goal_clock_now() >= float(state.get("deadline", 0.0)):
		if not _may_register_change(team, _goal_clock_now()):
			# B12 : repousse d'un cran plutôt que de percuter 2 autres
			# changements récents de l'équipe (voir `_may_register_change`).
			state["deadline"] = _goal_clock_now() + MIN_EVENT_SPACING
			_sighting_reaction[bot_id] = state
			return
		state["applied"] = true
		_sighting_reaction[bot_id] = state
		var goal_pos := _spread_from_teammates(bot_id, _cover_offset(bk, seen))
		# BOT-31 : un bot mobilisé HORS de sa lane (laisse) revient à sa
		# patrouille après LANE_HOLD_MAX s sans nouveau contact, plutôt que la
		# mémoire d'équipe standard (ENEMY_MEMORY_TTL, réservée à la lane
		# propre) — voir la docstring de `SIGHTING_MOBILIZE_RANGE_OUT_OF_LANE`.
		var ttl := LANE_HOLD_MAX if state.get("out_of_lane", false) else ENEMY_MEMORY_TTL
		_investigate_goal[bot_id] = {"pos": goal_pos, "expires_at": _goal_clock_now() + ttl}
		_bot_goal_cache.erase(bot_id)


## Même rôle que `_claim_kill_out_of_lane_leash`, pour une réaction de
## sighting (T2) — un titulaire PAR "team:pos" (`key`, même format que
## `_sighting_event_delays`), jamais nettoyé explicitement (une position déjà
## vue peut redevenir "la dernière info" plus tard dans le match, même
## discipline que `_sighting_event_delays` ci-dessus).
func _claim_sighting_out_of_lane_leash(key: String, bot_id: int, dist: float) -> bool:
	if dist > SIGHTING_MOBILIZE_RANGE_OUT_OF_LANE:
		return false
	var holder: Dictionary = _sighting_leash.get(key, {})
	var holder_id: int = int(holder.get("bot_id", -1))
	if holder_id != -1 and holder_id != bot_id and dist >= float(holder.get("dist", INF)):
		return false
	if holder_id != -1 and holder_id != bot_id:
		_release_out_of_lane_leash(_sighting_reaction, holder_id)
	_sighting_leash[key] = {"bot_id": bot_id, "dist": dist}
	return true


## Point d'entrée (T2/T3) : avant le mécanisme générique de cache
## (`GameMode.bot_goal_for`), laisse une chance aux réactions d'équipe/de kill
## en cours de forcer un recalcul CIBLÉ (`_bot_goal_cache.erase`) — seulement
## sur une carte avec `bot_knowledge` ; sinon comportement historique
## inchangé (super direct, comme avant BOT-23).
func bot_goal_for(team: int, bot_id: int, bot_pos: Vector3) -> Vector3:
	var bk: Dictionary = _bot_knowledge().get("bot_knowledge", {})
	if not bk.is_empty():
		_maybe_trigger_kill_reaction(bk, team, bot_id, bot_pos)
		_maybe_trigger_sighting_reaction(bk, team, bot_id, bot_pos)
	return super.bot_goal_for(team, bot_id, bot_pos)


## Couloir affecté à `bot_id` (LD-25, docs/research/09_wasteland_vertical_
## slice.md §e "affectation de lane par bot (répartition 1-2-1)") — modulo
## STABLE du nombre de lanes déclarées par la carte : deux bots consécutifs
## de la même équipe retombent déjà sur des lanes différentes dès que
## l'équipe compte plus de bots que de lanes (ex. 4 bots / 3 lanes ->
## 1-2-1). `""` si la carte n'en déclare aucune (`lanes` vide). CONSERVÉ tel
## quel (BOT-23 ne réécrit pas LD-25) : repli pour toute carte qui déclare
## des `hotspots` mais pas encore de `bot_knowledge` (BOT-22).
func _lane_for_bot(bot_id: int, lanes: Dictionary) -> String:
	var keys := lanes.keys()
	if keys.is_empty():
		return ""
	return String(keys[bot_id % keys.size()])


## Hotspot de patrouille (LD-25 §e "remplace les marqueurs de spawn comme
## points de patrouille TDM") pour `bot_id`, dans sa lane assignée en
## priorité (repli sur tout hotspot de la carte si sa lane n'en déclare
## aucun) — tiré au hasard parmi les candidats, à L'EXCEPTION du but
## actuellement en cache si `exclude_current` (même contrat que
## `GameMode._pick_patrol_point` : un hotspot ATTEINT ne doit pas être
## réassigné aussitôt). `Vector3.ZERO` si la carte ne déclare aucun hotspot
## (appelant : repli sur `_pick_patrol_point`, voir `_compute_bot_goal`).
## CONSERVÉ tel quel (repli hotspots/spawn, cartes sans `bot_knowledge`).
func _pick_hotspot(bot_id: int, knowledge: Dictionary, exclude_current: bool) -> Vector3:
	var hotspots: Array = knowledge.get("hotspots", [])
	if hotspots.is_empty():
		return Vector3.ZERO
	var lane := _lane_for_bot(bot_id, knowledge.get("lanes", {}))
	var in_lane: Array = []
	for entry in hotspots:
		if String((entry as Dictionary).get("lane", "")) == lane:
			in_lane.append(entry)
	var candidates: Array = in_lane if not in_lane.is_empty() else hotspots

	var exclude: Vector3 = Vector3.INF
	if exclude_current:
		var cached: Dictionary = _bot_goal_cache.get(bot_id, {})
		if not cached.is_empty():
			exclude = cached.get("pos", Vector3.INF)

	var positions: Array = []
	for entry in candidates:
		var pos: Vector3 = (entry as Dictionary)["pos"]
		if candidates.size() > 1 and exclude != Vector3.INF and pos.distance_to(exclude) <= 0.01:
			continue
		positions.append(pos)
	if positions.is_empty():
		return (candidates[0] as Dictionary)["pos"]
	return positions[_rng.randi() % positions.size()]


## TDM : "va patrouiller / va voir la dernière info connue" — JAMAIS la
## position VIVANTE d'un ennemi (contrat BOT-01, docs/research/02_bots_ai.md
## §4.1 : l'ancien `enemies[randi() % size]` était un wall-hack caché, en plus
## d'être instable).
## BOT-23 : sur une carte qui déclare `bot_knowledge` (BOT-22), la patrouille
## de couloir (T1, `_corridor_goal`) remplace désormais le tirage de hotspot
## — la "dernière position connue" n'est plus prioritaire pour TOUS les bots
## de l'équipe (essaim, T2) : seuls les bots mobilisés par
## `_maybe_trigger_sighting_reaction` l'investiguent (`_wasteland_bot_goal`),
## les autres continuent leur couloir. Sur toute AUTRE carte (pas de
## `bot_knowledge`), comportement LD-25 inchangé : mémoire d'équipe partagée
## en priorité pour tous, sinon hotspot, sinon marqueur de spawn.
func _compute_bot_goal(team: int, bot_id: int, bot_pos: Vector3, reached: bool = false) -> Vector3:
	var knowledge := _bot_knowledge()
	var bk: Dictionary = knowledge.get("bot_knowledge", {})
	if not bk.is_empty():
		return _wasteland_bot_goal(bk, team, bot_id, bot_pos, reached)
	var seen := _shared_last_seen_enemy(team)
	if seen != Vector3.INF:
		return seen
	if not (knowledge.get("hotspots", []) as Array).is_empty():
		return _pick_hotspot(bot_id, knowledge, reached)
	return _pick_patrol_point(bot_id, bot_pos, reached)


## But effectif sur une carte à `bot_knowledge` : le point d'investigation en
## cours (T2/T3, tant qu'il n'a pas expiré) sinon la patrouille de couloir
## (T1). Jamais les marqueurs de spawn (`_pick_patrol_point`) ni un hotspot
## aléatoire (`_pick_hotspot`) : ces deux replis LD-25 restent réservés aux
## cartes SANS `bot_knowledge`, voir `_compute_bot_goal`.
func _wasteland_bot_goal(bk: Dictionary, team: int, bot_id: int, bot_pos: Vector3, reached: bool) -> Vector3:
	if _investigate_goal.has(bot_id):
		var inv: Dictionary = _investigate_goal[bot_id]
		var now := _goal_clock_now()
		if now < float(inv["expires_at"]):
			return inv["pos"]
		# Investigation expirée : la reprise de la patrouille de couloir est
		# elle-même un CHANGEMENT de but (B12) — si elle percuterait 2 autres
		# changements récents de l'équipe, prolonge l'investigation d'un cran
		# plutôt que de basculer maintenant.
		if not _may_register_change(team, now):
			inv["expires_at"] = now + MIN_EVENT_SPACING
			_investigate_goal[bot_id] = inv
			return inv["pos"]
		_investigate_goal.erase(bot_id)
	var know := BotMapKnowledge.new(bk)
	return _corridor_goal(know, team, bot_id, bot_pos, reached)
