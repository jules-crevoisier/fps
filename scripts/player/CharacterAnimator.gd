## CharacterAnimator.gd
## Anime le CharacterBody (squelette + AnimationPlayer chargés dynamiquement,
## voir CharacterBody.gd) via un AnimationTree construit EN CODE (le squelette
## n'existe qu'après le chargement du glb de l'agent — impossible de le
## câbler dans le .tscn à l'avance, chaque agent a son propre AnimationPlayer
## interne). Nœud "CharacterAnimator" (extends AnimationTree), frère de
## "%CharacterModel" dans scenes/player/player.tscn.
##
## Les pairs DISTANTS ne font PAS tourner la state machine du joueur
## (scripts/player/states/*, PlayerStateMachine) : ce nœud lit uniquement
## `player.anim_state` (packé : locomotion + bit "en rechargement", voir
## `pack_anim_state`/`unpack_locomotion`/`unpack_reloading`) et
## `player.aim_pitch`, deux champs répliqués TOUJOURS (SceneReplicationConfig)
## posés CHAQUE tick par l'AUTORITÉ (PlayerController._update_anim_state) —
## que ce soit le PROPRIÉTAIRE réel (humain) ou le SERVEUR (bot). Même code
## pour un corps LOCAL (valeurs déjà à jour, pas de latence réseau) et un
## corps DISTANT (valeurs répliquées) : aucune branche "suis-je propriétaire ?"
## ici, hors le cas "humain local" (corps caché, voir PlayerLook — inutile de
## piloter l'AnimationTree pour un corps que personne ne voit jamais).
##
## Deux couches :
##  - "Locomotion" (AnimationNodeTransition, PLEIN CORPS) : un clip par valeur
##    de `Locomotion`, sélectionné par `locomotion_for()` (logique pure, voir
##    tests/player/test_character_animator.gd).
##  - "UpperBody" (AnimationNodeBlend2, FILTRÉ colonne/bras — design : "filtered
##    to spine/arms") : pose de visée continue (AnimationNodeBlendSpace1D,
##    Pistol_Aim_Down/Neutral/Up mélangés par `aim_blend_t(aim_pitch)`) +
##    deux one-shots empilés (Pistol_Shoot au tir, Pistol_Reload au
##    rechargement) — masquée pendant les états pleine-pose (mort/roulade/
##    étourdi/interaction/plongeon, voir `_NO_UPPER_BODY`/`upper_body_active`).
## Tir : `Weapon.fired` (prédiction LOCALE — humain propriétaire, ou SERVEUR
## pour un bot, cf. scripts/combat/Weapon.gd) + `Weapon.remote_fired`
## (broadcast serveur -> tout le monde SAUF le tireur) : les deux couvrent
## exactement l'ensemble des corps qui doivent voir le one-shot Pistol_Shoot.
## Rechargement : PAS de signal broadcast équivalent dans Weapon.gd (lecture
## SEULE autorisée sur ce fichier, hors de portée de cette tranche) — d'où le
## bit RELOADING_FLAG sur `anim_state`, posé par PlayerController en écoutant
## SON PROPRE `Weapon.reload_started` (qui ne s'émet que là où la prédiction
## tourne, càd exactement là où `anim_state` est calculé — voir plus haut) et
## répliqué à tous comme le reste de `anim_state`.
class_name CharacterAnimator
extends AnimationTree

## -- Locomotion (couche PLEIN CORPS) ----------------------------------------
## Valeurs STABLES : répliquées dans PlayerController.anim_state (packées
## avec RELOADING_FLAG) — ne jamais réordonner en cours de route (casserait
## la réplication hôte/client en vol).
enum Locomotion {
	IDLE, WALK, JOG, SPRINT,
	CROUCH_IDLE, CROUCH_FWD, SLIDE,
	AIR, JUMP_START, JUMP_LAND, DIVE,
	ROLL, STUN, INTERACT, DEAD,
}

## Bit posé sur `anim_state` EN PLUS de la locomotion (rechargement en cours,
## indépendant du bas du corps) — choisi loin des valeurs de `Locomotion`
## (qui tiennent sur 4 bits, 0..14) pour ne jamais s'y superposer.
const RELOADING_FLAG := 1 << 8

## Un clip par valeur de `Locomotion`, même ordre que l'enum (voir `clip_for`).
## Slide réutilise Crouch_Fwd (design : "Slide = pose accroupie penchée" —
## l'inclinaison vient de `_drive_lean`, pas d'un clip dédié) ; Dive réutilise
## Jump (design : "Dive = pose de saut penchée en avant", même mécanisme).
const _CLIPS := [
	"Idle", "Walk", "Jog_Fwd", "Sprint",
	"Crouch_Idle", "Crouch_Fwd", "Crouch_Fwd",
	"Jump", "Jump_Start", "Jump_Land", "Jump",
	"Roll", "Hit_Head", "Interact", "Death01",
]

## États PLEIN CORPS pendant lesquels la couche "haut du corps" (visée/tir/
## rechargement) reste masquée — la pose complète du clip domine (un mort qui
## vise, ou un plongeon aux bras qui blendent vers Pistol_Aim, n'aurait aucun
## sens visuel).
const _NO_UPPER_BODY: Array[int] = [
	Locomotion.DEAD, Locomotion.ROLL, Locomotion.STUN, Locomotion.INTERACT, Locomotion.DIVE,
]

## Locomotions qui BOUCLENT réellement en jeu (contrat GF-27,
## docs/research/10_ammo_kits_input.md §5.2/§5.3) : jamais de reset de phase à
## la transition (`AnimationNodeTransition.set_input_reset`, voir
## `configure_locomotion_transition_reset`/`_build_tree`) — sinon la boucle
## repart à l'image 0 à chaque changement de locomotion et « ne boucle jamais »
## à l'œil, même avec un clip `loop_mode = 1` bien importé. STUN et INTERACT y
## figurent aussi : leur clip d'origine est trop court pour la durée réelle de
## l'état (voir `forced_loop_mode`), donc ils doivent boucler EUX AUSSI plutôt
## que de figer leur dernière image.
const _LOOPING_LOCOMOTIONS: Array[int] = [
	Locomotion.IDLE, Locomotion.WALK, Locomotion.JOG, Locomotion.SPRINT,
	Locomotion.CROUCH_IDLE, Locomotion.CROUCH_FWD, Locomotion.SLIDE, Locomotion.AIR,
	Locomotion.STUN, Locomotion.INTERACT,
]

## Poids du calque "haut du corps" en Jog/Sprint (contrat GF-27 : "haut du
## corps selon la locomotion" — sinon les bras du clip de course sont
## totalement écrasés par la pose de visée figée, même en pleine foulée).
## Idle/Walk/Crouch/Air/Jump* restent à 1,0 (visée pleinement lisible à
## l'arrêt/en marche), DEAD/ROLL/STUN/INTERACT/DIVE restent à 0,0
## (`_NO_UPPER_BODY`, pose plein corps du clip qui domine) — voir
## `upper_body_blend_amount`.
const UPPER_BODY_BLEND_JOG := 0.7
const UPPER_BODY_BLEND_SPRINT := 0.4

## Poids ADDITIF (constant, jamais recalculé par frame) de la respiration
## Pistol_Idle par-dessus la pose de visée (voir `_build_tree`, nœud
## "Breathing") — assez faible pour ne jamais dénaturer les poses Down/
## Neutral/Up, assez visible pour casser l'immobilité totale du haut du corps
## à l'arrêt/en marche (contrat GF-27 "haut du corps selon la locomotion").
const UPPER_BODY_BREATH_ADD_AMOUNT := 0.35

## Vitesse (m/s) séparant Jog et Sprint À L'INTÉRIEUR de l'état "Sprint" (pas
## un état dédié : le sprint démarre en Jog tant que l'accélération n'a pas
## atteint `MovementConfig.sprint_speed` = 8.2 — voir scripts/player/states/Sprint.gd).
## Seuil "à froid" : utilisé UNIQUEMENT quand on ne sait pas encore si on
## était déjà en JOG ou en SPRINT au tick précédent (voir `locomotion_for`,
## paramètre `previous_locomotion` — premier appel, changement de state_name).
## Une fois cette information connue, `sprint_or_jog`/`JOG_SPRINT_LOW`/
## `JOG_SPRINT_HIGH` prennent le relais (hystérésis, contrat GF-27).
const JOG_SPEED_THRESHOLD := 6.0
## Hystérésis (m/s) Jog <-> Sprint (GF-27, docs/research/10_ammo_kits_input.md
## §5.3) : une fois en SPRINT, on n'en sort qu'EN DESSOUS de `JOG_SPRINT_LOW` ;
## une fois en JOG, il faut dépasser `JOG_SPRINT_HIGH` pour repasser en
## SPRINT. Bande volontairement plus large que le contrat testé ("aucun
## changement de locomotion entre 5,8 et 6,2 m/s") pour une marge confortable.
const JOG_SPRINT_LOW := 5.6
const JOG_SPRINT_HIGH := 6.4
## Vitesse (m/s) au-delà de laquelle "Crouch" affiche Crouch_Fwd plutôt que
## Crouch_Idle (les deux sont le même état de la state machine, voir
## scripts/player/states/Crouch.gd — la locomotion en dérive par la vitesse).
const CROUCH_MOVE_THRESHOLD := 0.3
## Durées (s) des fenêtres Jump_Start / Jump_Land — gérées par
## PlayerController (détection de transition sur `state_machine.current_name`).
const JUMP_START_DUR := 0.15
const JUMP_LAND_DUR := 0.18

## -- Personnalité d'animation additive par agent (§4.6/§12, tâche ART-15) ---
## Couche PUREMENT cosmétique appliquée sur "%CharacterModel"
## (scripts/player/CharacterBody.gd, sans collision, §4.1) : rebond,
## inclinaison de buste, balancement latéral, cadence de pas et squash de
## CORPS à l'atterrissage (jamais de tête, §4.6 : « jamais d'écrasement de la
## tête » ; §4.8 v3.1 : « écrasement du corps seul » ; §12 ART-15 :
## « aucun écrasement de tête »). Elle ne touche JAMAIS PlayerController ni la
## CapsuleShape3D (« aucun choix d'art ne peut modifier la hitbox ») — d'où
## les garde-fous ci-dessous, vérifiés par `profile_respects_hitbox_floor`
## (voir tests/player/test_character_animator.gd).

## Repères du gabarit debout (§4.1), au repos : ligne des yeux 1,62 m, menton
## 1,49 m. Utilisés UNIQUEMENT pour vérifier qu'un profil ne fait pas
## descendre ces repères sous le plancher du §4.6 (1,56 m / 1,43 m) — jamais
## pour piloter la hitbox elle-même, qui reste fixe par construction.
const STANDING_EYE_HEIGHT_M := 1.62
const STANDING_CHIN_HEIGHT_M := 1.49
const MIN_STANDING_EYE_HEIGHT_M := 1.56
const MIN_STANDING_CHIN_HEIGHT_M := 1.43

## Bornes du §4.6 : « buste penché de 8° au plus » et « cadence de pas de
## ×0,9 à ×1,15 ».
const MAX_TORSO_TILT_DEG := 8.0
const MIN_CADENCE_SCALE := 0.9
const MAX_CADENCE_SCALE := 1.15

## Squash de CORPS cosmétique (accent d'impact à l'atterrissage, §12 ART-15) :
## « écrasement du corps de 0,97 à 1,03 pendant au plus 80 ms », JAMAIS de
## tête (§4.6 : « jamais d'écrasement de la tête »). `body_squash_scale` est
## une fonction pure float -> float, sans accès à PlayerController ni à la
## CapsuleShape3D — appliquée sur l'échelle Y de "%CharacterModel" ENTIER
## (voir `_apply_body_squash`), donc y compris la tête si on n'y prenait pas
## garde ; `_HEAD_BONE` sert uniquement à contre-échelonner l'os de tête du
## squelette pour neutraliser cet effet sur la tête (voir plus bas).
const BODY_SQUASH_DURATION_S := 0.08
const BODY_SQUASH_MIN_SCALE := 0.97
const BODY_SQUASH_MAX_SCALE := 1.03
const _HEAD_BONE := "DEF-head"

## Recul additif du haut du corps au hit confirmé (GF-10 "Réaction visible de
## la cible", `Health.hit_reaction` — diffusé à TOUS les pairs). Bascule
## additive de la colonne (os `_FLINCH_BONE`, proche des épaules -> entraîne
## bras/tête sans toucher les jambes), superposée à la pose déjà écrite par
## l'AnimationTree ce frame (même principe que `_apply_body_squash` : lue puis
## multipliée par le delta, jamais une pose absolue — la visée/le tir en cours
## ne sont donc jamais perdus). `hit_flinch_angle_rad` est une fonction PURE,
## testée directement : une seule bosse sinusoïdale, nulle aux deux bornes
## (t=0 et t=durée) -> jamais d'à-coup à l'apparition/la disparition.
const HIT_FLINCH_DURATION_S := 0.12   # 120 ms, contrat GF-10
const HIT_FLINCH_MAX_ANGLE_DEG := 6.0 # "petit recul", pas un knockback complet
const _FLINCH_BONE := "DEF-spine.003"

## Fige la pose (GF-10) au kill, avant que la locomotion DEAD (clip Death01,
## voir `_CLIPS`) ne prenne la main : ce nœud (AnimationTree) est mis en pause
## (`active = false`) pendant `KILL_FREEZE_DURATION_S`, ce qui laisse le
## Skeleton3D sur son dernier pose calculée — jamais la simulation
## (`Health.is_dead`/`PlayerController.anim_state` répliqués restent
## inchangés, seul le rendu cosmétique de CE nœud est gelé).
const KILL_FREEZE_DURATION_S := 0.05  # 50 ms, contrat GF-10

## Dossier des profils d'animation par agent (resources/agents/anim/*.tres,
## voir resources/agents/anim/AgentAnimProfile.gd).
const _ANIM_PROFILE_DIR := "res://resources/agents/anim/"

## Fréquence (Hz) du rebond/balancement procédural en idle/marche/course, mise
## à l'échelle par `cadence_scale` — choisie pour rester perceptible sans
## être saccadée.
const _BOUNCE_HZ := 1.6

## États "debout" auxquels s'applique la couche additive (§4.6) — jamais aux
## états pleine-pose (Slide/Dive/Crouch/Roll/Stun/Interact/Dead/Air/Jump*, qui
## ont leur propre traitement ou leur propre plage hitbox, §4.1).
const _STANDING_LOCOMOTIONS: Array[int] = [
	Locomotion.IDLE, Locomotion.WALK, Locomotion.JOG, Locomotion.SPRINT,
]

## Amplitude de pitch (rad) qui sature le blend Pistol_Aim_Down/Neutral/Up —
## au-delà, la pose Up/Down pleine suffit (le regard va jusqu'à 89°, bien plus
## que ce qu'une pose figée doit exagérer).
const AIM_PITCH_MAX := 0.87266463  # deg_to_rad(50.0), constante => pas d'appel en dehors d'une fonction

## Durée native (s) du clip `Pistol_Reload` tel qu'importé (mesurée, voir
## docs/research/10_ammo_kits_input.md §5.1) — UNIQUE clip de rechargement,
## réutilisé pour TOUTES les armes (pas de rig dédié par arme). Contrat GF-27
## "rechargement calé sur reload_time" : `reload_clip_speed` calcule le
## facteur d'échelle temporelle (`AnimationNodeTimeScale`, nœud "ReloadSpeed",
## voir `_build_tree`) qui fait durer ce clip EXACTEMENT `reload_time`,
## quelle que soit l'arme en main (1,2 à 4,2 s selon `WeaponConfig.reload_time`).
const RELOAD_CLIP_BASE_DURATION_S := 1.667
## Repli défensif si `reload_time` est invalide (≤ 0, ex. avant tout signal
## `Weapon.current_id_changed` reçu) — vitesse neutre, jamais de division par
## zéro.
const _DEFAULT_RELOAD_TIME_S := 1.8

## Os filtrés pour la couche "haut du corps" (design : "filtered to
## spine/arms" — jamais les jambes ni la tête/nuque : le regard reste porté
## par la caméra du joueur, pas par cette couche).
const _UPPER_BODY_BONES := [
	"DEF-spine.001", "DEF-spine.002", "DEF-spine.003",
	"DEF-shoulder.L", "DEF-upper_arm.L", "DEF-forearm.L", "DEF-hand.L",
	"DEF-shoulder.R", "DEF-upper_arm.R", "DEF-forearm.R", "DEF-hand.R",
]
const _FINGER_CHAINS := ["f_index", "f_middle", "f_pinky", "f_ring", "thumb"]
## Chemin du squelette DANS les pistes d'animation (relatif à
## `AnimationPlayer.root_node`, PAS à ce nœud) — identique sur les 6 glb
## personnages ET fp_arms.glb (même pipeline : racine glTF "Rig" ->
## "Skeleton3D", vérifié par sondage direct des pistes d'un clip importé).
const _SKELETON_TRACK_PREFIX := "Rig/Skeleton3D:"

# ------------------------------------------------------------------
#  API PURE — testée directement (tests/player/test_character_animator.gd),
#  sans AnimationTree ni arbre de scène.
# ------------------------------------------------------------------

## Empaquette la locomotion + le bit "en rechargement" dans l'entier répliqué.
static func pack_anim_state(locomotion: int, reloading: bool) -> int:
	return locomotion | (RELOADING_FLAG if reloading else 0)

static func unpack_locomotion(anim_state: int) -> int:
	return anim_state & (RELOADING_FLAG - 1)

static func unpack_reloading(anim_state: int) -> bool:
	return (anim_state & RELOADING_FLAG) != 0

## Sprint/Jog avec HYSTÉRÉSIS (contrat GF-27 : "aucun changement de locomotion
## quand la vitesse oscille entre 5,8 et 6,2 m/s") : `was_sprint` est la
## locomotion PRÉCÉDENTE (jamais recalculée à partir de la seule vitesse
## courante, ce qui redonnerait exactement le clignotement à corriger). Une
## fois en SPRINT, on n'en sort qu'EN DESSOUS de `JOG_SPRINT_LOW` (5,6 m/s) ;
## une fois en JOG, il faut dépasser `JOG_SPRINT_HIGH` (6,4 m/s) pour repasser
## en SPRINT — la bande [5,6 ; 6,4] ne change donc jamais d'état une fois
## qu'on y est entré, ce qui couvre largement [5,8 ; 6,2].
static func sprint_or_jog(speed: float, was_sprint: bool) -> int:
	if was_sprint:
		return Locomotion.JOG if speed <= JOG_SPRINT_LOW else Locomotion.SPRINT
	return Locomotion.SPRINT if speed >= JOG_SPRINT_HIGH else Locomotion.JOG

## Mappe (nom d'état de la state machine + vitesse + petites fenêtres de
## timing) vers une valeur de `Locomotion`. `jump_start_left`/`jump_land_left` :
## temps restant (s) dans la fenêtre Jump_Start/Jump_Land, géré par
## PlayerController (transitions détectées sur `state_machine.current_name`).
## `previous_locomotion` : valeur retournée par CET appel au tick PRÉCÉDENT
## (PlayerController la retrouve dans `anim_state` déjà répliqué, voir
## `_update_anim_state`) — sert UNIQUEMENT à l'hystérésis Jog/Sprint
## (`sprint_or_jog`). -1 (par défaut) = inconnue (premier appel) : repli sur
## l'ancien seuil unique `JOG_SPEED_THRESHOLD`, comme avant GF-27.
static func locomotion_for(state_name: String, speed: float, is_interacting: bool,
		is_dead: bool, jump_start_left: float = 0.0, jump_land_left: float = 0.0,
		previous_locomotion: int = -1) -> int:
	if is_dead:
		return Locomotion.DEAD
	if is_interacting:
		return Locomotion.INTERACT
	if jump_land_left > 0.0:
		return Locomotion.JUMP_LAND
	if jump_start_left > 0.0:
		return Locomotion.JUMP_START
	match state_name:
		"Idle":
			return Locomotion.IDLE
		"Walk":
			return Locomotion.WALK
		"Sprint":
			if previous_locomotion == Locomotion.SPRINT or previous_locomotion == Locomotion.JOG:
				return sprint_or_jog(speed, previous_locomotion == Locomotion.SPRINT)
			return Locomotion.JOG if speed < JOG_SPEED_THRESHOLD else Locomotion.SPRINT
		"Crouch":
			return Locomotion.CROUCH_FWD if speed > CROUCH_MOVE_THRESHOLD else Locomotion.CROUCH_IDLE
		"Slide":
			return Locomotion.SLIDE
		"Air":
			return Locomotion.AIR
		"Dive":
			return Locomotion.DIVE
		"Roll":
			return Locomotion.ROLL
		"Stun":
			return Locomotion.STUN
	return Locomotion.IDLE

## `true` si la couche haut-du-corps (visée/tir/rechargement) doit être
## visible pour cette locomotion (voir `_NO_UPPER_BODY`).
static func upper_body_active(locomotion: int) -> bool:
	return not _NO_UPPER_BODY.has(locomotion)

## `true` si cette locomotion boucle réellement en jeu (voir
## `_LOOPING_LOCOMOTIONS`) — pilote `configure_locomotion_transition_reset`
## (jamais de reset de phase à la transition) ET `forced_loop_mode` (STUN/
## INTERACT, dont le clip d'origine est trop court pour boucler tout seul).
static func is_looping_locomotion(locomotion: int) -> bool:
	return _LOOPING_LOCOMOTIONS.has(locomotion)

## Configure `set_input_reset` sur CHAQUE entrée déjà ajoutée à
## `transition_node` (une par valeur de `Locomotion`, voir `_build_tree`) :
## FAUX (jamais de reset de phase) sur une locomotion qui boucle, VRAI sinon
## (ex. Jump_Start/Jump_Land/Roll/Dive/Death01 : clips UNIQUES, qui doivent au
## contraire repartir proprement de l'image 0 à chaque nouvelle occurrence).
## Factorisée pour être appelée par `_build_tree` ET testée directement :
## `AnimationNodeTransition` est une Resource, aucun AnimationTree/scène requis
## (contrat GF-27 : "is_input_reset faux sur les boucles", test pur).
static func configure_locomotion_transition_reset(transition_node: AnimationNodeTransition) -> void:
	for i in Locomotion.size():
		transition_node.set_input_reset(i, not is_looping_locomotion(i))

## Mode de boucle FORCÉ (voir `_build_tree`/`_apply_forced_loop`) pour STUN et
## INTERACT — leur clip d'origine (Hit_Head 0,417 s, Interact 2,0 s, mesures
## docs/research/10_ammo_kits_input.md §5.1) est bien plus court que la durée
## réelle de l'état (étourdissement 1,8 à 2,2 s, pose/désamorçage 4 à 7 s) :
## sans boucle forcée, la pose reste FIGÉE sur la dernière image du clip pour
## tout le reste de la durée (contrat GF-27 : "aucune image figée plus de
## 0,2 s"). PINGPONG pour STUN (va-et-vient, lecture "sonné" cartoon plus
## lisible qu'un clip très court qui redémarre sec) ; LINÉAIRE pour INTERACT
## (le geste de pose/désamorçage reprend proprement du début). `Locomotion.NONE`
## (toute autre valeur) : `Animation.LOOP_NONE`, aucun changement.
static func forced_loop_mode(locomotion: int) -> int:
	match locomotion:
		Locomotion.STUN:
			return Animation.LOOP_PINGPONG
		Locomotion.INTERACT:
			return Animation.LOOP_LINEAR
	return Animation.LOOP_NONE

## Poids (0..1) du calque "haut du corps" selon la locomotion (contrat GF-27 :
## "haut du corps selon la locomotion") : 0,0 sur les états plein-corps
## (`upper_body_active` faux, la pose du clip domine), 1,0 à l'arrêt/en
## marche/accroupi/en l'air (visée pleinement lisible), réduit en Jog/Sprint
## (`UPPER_BODY_BLEND_JOG`/`UPPER_BODY_BLEND_SPRINT`) pour laisser les bras du
## clip de course balancer au lieu d'être totalement écrasés par la pose de
## visée figée.
static func upper_body_blend_amount(locomotion: int) -> float:
	if not upper_body_active(locomotion):
		return 0.0
	if locomotion == Locomotion.SPRINT:
		return UPPER_BODY_BLEND_SPRINT
	if locomotion == Locomotion.JOG:
		return UPPER_BODY_BLEND_JOG
	return 1.0

## Facteur d'échelle temporelle (`parameters/ReloadSpeed/scale`, voir
## `_build_tree`) pour que le clip `Pistol_Reload` (durée native
## `RELOAD_CLIP_BASE_DURATION_S`) dure EXACTEMENT `reload_time` secondes —
## contrat GF-27 "rechargement calé sur reload_time" (le geste se terminait
## avant la fin du VRAI rechargement sur les armes lentes, ex. Semeuse 4,2 s,
## ou finissait après sur les armes rapides). Repli défensif à 1,0 (vitesse
## native) si `reload_time` est invalide (≤ 0).
static func reload_clip_speed(reload_time: float) -> float:
	if reload_time <= 0.0:
		return 1.0
	return RELOAD_CLIP_BASE_DURATION_S / reload_time

## Position (-1..1) dans le blend de visée Pistol_Aim_Down/Neutral/Up — pitch
## en radians, positif = regarde vers le haut (convention
## PlayerController._look : `head.rotate_x(-relative.y * sensibilité)`, voir
## docstring `aim_pitch`).
static func aim_blend_t(pitch_rad: float) -> float:
	return clampf(pitch_rad / AIM_PITCH_MAX, -1.0, 1.0)

## Nom du clip pour une valeur de `Locomotion`.
static func clip_for(locomotion: int) -> String:
	if locomotion < 0 or locomotion >= _CLIPS.size():
		return "Idle"
	return _CLIPS[locomotion]

## Angle (rad) du recul additif du haut du corps (GF-10) au temps `elapsed_s`
## depuis le hit — une seule bosse sinusoïdale bornée à `HIT_FLINCH_MAX_ANGLE_DEG`,
## nulle en dehors de `[0, HIT_FLINCH_DURATION_S[` (garde-fou analogue à
## `body_squash_scale`/`BODY_SQUASH_DURATION_S` : jamais plus longtemps que le
## contrat, quel que soit l'appelant).
static func hit_flinch_angle_rad(elapsed_s: float) -> float:
	if elapsed_s < 0.0 or elapsed_s >= HIT_FLINCH_DURATION_S:
		return 0.0
	return deg_to_rad(HIT_FLINCH_MAX_ANGLE_DEG) * sin(PI * (elapsed_s / HIT_FLINCH_DURATION_S))

# ------------------------------------------------------------------
#  Personnalité d'animation par agent (§4.6, ART-15) — API PURE, testée
#  directement (tests/player/test_character_animator.gd), sans AnimationTree
#  ni arbre de scène — même esprit que le reste de ce fichier.
# ------------------------------------------------------------------

## Cache des profils déjà chargés, par nom d'agent en minuscules.
static var _profile_cache: Dictionary = {}

## Charge (et met en cache) le profil d'animation additif d'un agent depuis
## resources/agents/anim/<agent en minuscules>.tres. Jamais nul : un nom
## d'agent inconnu (ou sans fichier) reçoit un profil NEUTRE (cadence ×1,
## aucune inclinaison/rebond/balancement) plutôt qu'un plantage — même esprit
## défensif que `clip_for`/`AgentDatabase.get_by_index` ailleurs dans le
## projet.
static func load_profile(agent_name: String) -> AgentAnimProfile:
	var key := agent_name.to_lower()
	if _profile_cache.has(key):
		return _profile_cache[key]
	var path := "%s%s.tres" % [_ANIM_PROFILE_DIR, key]
	var profile: AgentAnimProfile = null
	if ResourceLoader.exists(path):
		profile = load(path) as AgentAnimProfile
	if profile == null:
		profile = AgentAnimProfile.new()
		profile.agent_name = agent_name
	_profile_cache[key] = profile
	return profile

## Cadence de pas bornée à la plage du §4.6 (×0,9 à ×1,15) — seul point
## d'entrée utilisé pour piloter `parameters/Cadence/scale` (voir
## `_build_tree`) : un profil malformé ne peut jamais faire sortir la lecture
## de l'AnimationTree de cette plage (donc jamais la vitesse RÉELLE du
## joueur, qui n'est ni lue ni écrite ici — couche 100 % cosmétique).
static func effective_cadence_scale(raw: float) -> float:
	return clampf(raw, MIN_CADENCE_SCALE, MAX_CADENCE_SCALE)

## Ligne des yeux (m), debout, une fois l'inclinaison ET le rebond du profil
## appliqués (pire cas : bas du rebond). Approximation géométrique : incliner
## le buste d'un angle θ autour d'un pivot au sol rapproche verticalement un
## point de hauteur h à h·cos(θ) ; le rebond soustrait son amplitude au pire
## moment du cycle.
static func standing_eye_height_m(profile: AgentAnimProfile) -> float:
	var tilt_rad := deg_to_rad(clampf(profile.torso_tilt_deg, 0.0, MAX_TORSO_TILT_DEG))
	return STANDING_EYE_HEIGHT_M * cos(tilt_rad) - profile.bounce_amplitude_m

## Même calcul que `standing_eye_height_m`, pour le menton.
static func standing_chin_height_m(profile: AgentAnimProfile) -> float:
	var tilt_rad := deg_to_rad(clampf(profile.torso_tilt_deg, 0.0, MAX_TORSO_TILT_DEG))
	return STANDING_CHIN_HEIGHT_M * cos(tilt_rad) - profile.bounce_amplitude_m

## `true` si le profil respecte tous les garde-fous de hitbox du §4.6 : yeux
## ≥ 1,56 m, menton ≥ 1,43 m debout, et inclinaison ≤ 8°. Sert à valider les 6
## profils livrés (resources/agents/anim/*.tres) ; ne pilote jamais le jeu.
static func profile_respects_hitbox_floor(profile: AgentAnimProfile) -> bool:
	if profile.torso_tilt_deg < 0.0 or profile.torso_tilt_deg > MAX_TORSO_TILT_DEG:
		return false
	if standing_eye_height_m(profile) < MIN_STANDING_EYE_HEIGHT_M:
		return false
	if standing_chin_height_m(profile) < MIN_STANDING_CHIN_HEIGHT_M:
		return false
	return true

## Échelle Y cosmétique du CORPS pendant le squash d'impact à l'atterrissage
## — fonction PURE (float -> float, aucun paramètre ni accès lié à la
## hitbox/au gameplay) : revient EXACTEMENT à 1.0 dès que `elapsed_s` sort de
## [0, BODY_SQUASH_DURATION_S[, donc jamais plus de 80 ms d'effet, quel que
## soit l'appelant (garde-fou §12 ART-15). Deux lobes de demi-sinusoïde,
## nuls aux deux bornes et au point médian (t=0, t=durée/2, t=durée) : le
## premier creuse jusqu'à `BODY_SQUASH_MIN_SCALE` (0,97, écrasement), le
## second dépasse jusqu'à `BODY_SQUASH_MAX_SCALE` (1,03, rebond) — exactement
## la plage « 0,97 à 1,03 » du §12, sans à-coup à l'apparition, au passage
## médian ni à la disparition.
static func body_squash_scale(elapsed_s: float) -> float:
	if elapsed_s < 0.0 or elapsed_s >= BODY_SQUASH_DURATION_S:
		return 1.0
	var half := BODY_SQUASH_DURATION_S * 0.5
	if elapsed_s < half:
		return 1.0 - (1.0 - BODY_SQUASH_MIN_SCALE) * sin(PI * (elapsed_s / half))
	var t := (elapsed_s - half) / half
	return 1.0 + (BODY_SQUASH_MAX_SCALE - 1.0) * sin(PI * t)

# ------------------------------------------------------------------
#  INSTANCE
# ------------------------------------------------------------------

var _character_body: CharacterBody
var _player: PlayerController
var _weapon: Weapon
var _health: Health
var _built: bool = false
var _current_locomotion: int = -1
var _was_reloading: bool = false
var _lean: float = 0.0   ## Inclinaison procédurale (slide/dive OU profil), lissée.
var _profile: AgentAnimProfile   ## Personnalité d'animation de l'agent (§4.6, ART-15).
var _personality_time: float = 0.0   ## Horloge du rebond/balancement, mise à l'échelle par la cadence.
var _body_squash_elapsed: float = -1.0   ## < 0 : pas de squash en cours (voir `_drive_body_squash`).
var _flinch_elapsed: float = -1.0   ## < 0 : pas de recul en cours (voir `_drive_flinch`, GF-10).
var _kill_freeze_left: float = -1.0   ## < 0 : pas de gel en cours (voir `_process`/`_on_died`, GF-10).
## Rechargement de l'arme COURANTE (s, contrat GF-27) — mis à jour par
## `_on_current_weapon_changed`, branché sur `Weapon.current_id_changed`
## (diffusé à TOUS les pairs, contrairement à `_inv` qui ne reflète l'arme
## réelle QUE côté propriétaire/serveur pour un bot : voir la docstring du
## signal dans Weapon.gd). Pilote `parameters/ReloadSpeed/scale` (voir
## `_drive_upper_body`/`reload_clip_speed`) : repli défensif tant qu'aucun
## signal n'est encore arrivé (spawn), comme `PlayerController._on_weapon_reload_started`.
var _reload_time: float = _DEFAULT_RELOAD_TIME_S

func _ready() -> void:
	_player = get_parent() as PlayerController
	if _player and _player.is_local_human():
		# Corps caché pour l'humain local (vue FPS, voir PlayerLook) : ce
		# corps ne sera jamais visible, inutile de piloter l'AnimationTree.
		set_process(false)
		active = false
		return
	_character_body = get_node_or_null("%CharacterModel") as CharacterBody
	if _character_body == null:
		push_warning("CharacterAnimator : %CharacterModel introuvable.")
		set_process(false)
		return
	if _character_body.is_model_ready():
		_on_model_ready()
	else:
		_character_body.model_ready.connect(_on_model_ready)
	_weapon = _player.get_node_or_null("Weapon") as Weapon if _player else null
	if _weapon:
		_weapon.fired.connect(_on_fired)
		_weapon.remote_fired.connect(_on_remote_fired)
		# GF-27 "rechargement calé sur reload_time" : `current_id_changed` est
		# diffusé à TOUS les pairs (voir Weapon.gd) — jamais `_weapon.cfg()`, qui
		# ne lit `_inv` (prédiction locale) qu'à jour côté PROPRIÉTAIRE ou
		# SERVEUR pour un bot, pas sur un corps distant quelconque.
		_weapon.current_id_changed.connect(_on_current_weapon_changed)
	# GF-10 "Réaction visible de la cible" : flinch (haut du corps) + gel de
	# pose au kill, sur TOUS les pairs (Health.hit_reaction/died sont déjà
	# diffusés à tous, voir Health.gd) — jamais pour ce corps si `_player` est
	# l'humain local (early return ci-dessus, corps jamais rendu).
	_health = _player.get_node_or_null("Health") as Health if _player else null
	if _health:
		_health.hit_reaction.connect(_on_hit_reaction)
		_health.died.connect(_on_died)

func _on_model_ready() -> void:
	if _built or _character_body.get_anim_player() == null:
		return
	_profile = _resolve_profile()
	_build_tree()
	_built = true

## Résout le profil d'animation (§4.6) de l'agent JOUÉ par ce corps — même
## repli que CharacterBody._ready()/AbilityController._resolve_agent :
## `_player.agent_index` (répliqué au spawn), ou `AgentDatabase.selected_index`
## hors GameWorld (entraînement hors-ligne).
func _resolve_profile() -> AgentAnimProfile:
	var index := _player.agent_index if _player else -1
	if index < 0:
		index = AgentDatabase.selected_index
	var agent := AgentDatabase.get_by_index(index)
	return load_profile(agent.agent_name)

func _process(delta: float) -> void:
	if _kill_freeze_left >= 0.0:
		# GF-10 : pose gelée EN L'ÉTAT (ni locomotion, ni haut du corps, ni
		# recul, ni squash) tant que la fenêtre n'est pas écoulée — voir
		# `_on_died` (déclenchement, `active = false`) et sa docstring.
		_kill_freeze_left -= delta
		if _kill_freeze_left > 0.0:
			return
		_kill_freeze_left = -1.0
		active = true  # dégèle -> la locomotion DEAD (anim_state déjà répliqué) prend la main ci-dessous.
	if not _built or _player == null or not is_instance_valid(_player):
		return
	var state: int = _player.anim_state
	var locomotion := unpack_locomotion(state)
	var reloading := unpack_reloading(state)
	_drive_locomotion(locomotion)
	_drive_upper_body(locomotion, _player.aim_pitch, reloading)
	_drive_lean(locomotion, delta)
	_drive_body_squash(delta)
	_drive_flinch(delta)

func _drive_locomotion(locomotion: int) -> void:
	if locomotion == _current_locomotion:
		return
	if locomotion == Locomotion.JUMP_LAND:
		# Accent d'impact cosmétique (§12 ART-15) : squash de CORPS (0,97 à
		# 1,03) ≤ 80 ms, voir `_drive_body_squash`/`body_squash_scale` —
		# jamais de squash de tête (§4.6 : « jamais d'écrasement de la tête »).
		_body_squash_elapsed = 0.0
	_current_locomotion = locomotion
	set("parameters/Locomotion/transition_request", "state_%d" % locomotion)

## Contrat GF-27 : "haut du corps selon la locomotion" (`upper_body_blend_amount`,
## remplace l'ancien tout-ou-rien) + "rechargement calé sur reload_time"
## (`parameters/ReloadSpeed/scale`, voir `_build_tree` — le nœud existe
## toujours, `reload_clip_speed` a un repli défensif si jamais aucun signal
## `current_id_changed` n'est encore arrivé).
func _drive_upper_body(locomotion: int, pitch: float, reloading: bool) -> void:
	set("parameters/UpperBody/blend_amount", upper_body_blend_amount(locomotion))
	set("parameters/AimPose/blend_position", aim_blend_t(pitch))
	set("parameters/ReloadSpeed/scale", reload_clip_speed(_reload_time))
	if reloading and not _was_reloading:
		set("parameters/ReloadShot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	_was_reloading = reloading

func _on_fired(_cfg: WeaponConfig) -> void:
	_trigger_shoot()

func _on_remote_fired(_cfg: WeaponConfig, _origin: Vector3, _dirs: Array) -> void:
	_trigger_shoot()

func _trigger_shoot() -> void:
	if not _built:
		return
	set("parameters/ShootShot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)

## GF-27 : arme en main CHANGÉE (équipée/achetée/ramassée/lâchée, voir
## `Weapon.current_id_changed`, diffusé à TOUS les pairs) — recalcule
## `_reload_time` depuis `WeaponDatabase` (lecture pure, jamais `_weapon.cfg()`
## dont l'inventaire local n'est à jour que côté propriétaire/serveur pour un
## bot, voir la docstring de `_reload_time`). Id inconnu (arme retirée, jamais
## en pratique) : repli défensif sur `_DEFAULT_RELOAD_TIME_S`.
func _on_current_weapon_changed(id: int) -> void:
	var cfg := WeaponDatabase.get_by_id(id)
	_reload_time = cfg.reload_time if cfg else _DEFAULT_RELOAD_TIME_S

## GF-10 : lance le recul additif du haut du corps (voir `_drive_flinch`) à
## chaque dégât confirmé encaissé par ce corps — `headshot` ne change QUE la
## couleur du flash (PlayerLook), pas ce recul, identique dans les deux cas.
func _on_hit_reaction(_headshot: bool) -> void:
	if not _built:
		return
	_flinch_elapsed = 0.0

## GF-10 : fige la pose au kill (voir `_process`) — `active = false` arrête
## l'AnimationTree EN L'ÉTAT (le Skeleton3D garde son dernier pose calculée,
## voir docstring `KILL_FREEZE_DURATION_S`) ; `_process` la réactive après
## `KILL_FREEZE_DURATION_S` et laisse la locomotion DEAD prendre la main
## normalement (anim_state répliqué reflète déjà la mort à ce moment-là).
func _on_died(_killer_id: int) -> void:
	if not _built:
		return
	_kill_freeze_left = KILL_FREEZE_DURATION_S
	active = false

## Inclinaison procédurale plein-corps (pas une piste d'anim) : Slide penche
## en avant façon glissade, Dive pique du nez, et — debout/en marche/course
## uniquement — la couche additive du §4.6 ajoute l'inclinaison PROPRE à
## l'agent (bornée à `MAX_TORSO_TILT_DEG`). Toujours appliquée sur le MODÈLE
## cosmétique (`_character_body`, sans collision), jamais sur ce nœud (qui
## reste l'AnimationTree pur) ni sur `_player`/la CapsuleShape3D.
func _drive_lean(locomotion: int, delta: float) -> void:
	var target := 0.0
	if locomotion == Locomotion.SLIDE:
		target = deg_to_rad(18.0)
	elif locomotion == Locomotion.DIVE:
		target = deg_to_rad(35.0)
	elif _profile and _STANDING_LOCOMOTIONS.has(locomotion):
		target = deg_to_rad(clampf(_profile.torso_tilt_deg, 0.0, MAX_TORSO_TILT_DEG))
	_lean = move_toward(_lean, target, deg_to_rad(200.0) * delta)
	if _character_body:
		_character_body.rotation.x = _lean
	_drive_personality_bounce(locomotion, delta)

## Rebond vertical et balancement latéral cosmétiques du §4.6, en idle/marche/
## course seulement (`_STANDING_LOCOMOTIONS`) — jamais sur `_player`/
## PlayerController : seul "%CharacterModel" (`_character_body`, sans
## collision, §4.1) est modifié, donc jamais d'effet sur le gameplay
## (vitesse, position répliquée, hitbox) même quand le mouvement réel du
## joueur est réduit ou nul (idle).
func _drive_personality_bounce(locomotion: int, delta: float) -> void:
	if _character_body == null:
		return
	if _profile == null or not _STANDING_LOCOMOTIONS.has(locomotion):
		_personality_time = 0.0
		_character_body.position.y = 0.0
		_character_body.rotation.z = 0.0
		return
	_personality_time += delta * effective_cadence_scale(_profile.cadence_scale)
	var phase := _personality_time * TAU * _BOUNCE_HZ
	_character_body.position.y = sin(phase) * _profile.bounce_amplitude_m
	_character_body.rotation.z = sin(phase * 0.5) * deg_to_rad(_profile.lateral_sway_deg)

## Fait avancer le squash de CORPS cosmétique (§12 ART-15), déclenché à
## l'atterrissage (voir `_drive_locomotion`) — s'éteint tout seul après
## `BODY_SQUASH_DURATION_S` (≤ 80 ms, garde-fou) via `body_squash_scale`
## (fonction pure, testée directement).
func _drive_body_squash(delta: float) -> void:
	if _body_squash_elapsed < 0.0:
		return
	_body_squash_elapsed += delta
	if _body_squash_elapsed >= BODY_SQUASH_DURATION_S:
		_body_squash_elapsed = -1.0
		_apply_body_squash(1.0)
		return
	_apply_body_squash(body_squash_scale(_body_squash_elapsed))

## Applique l'échelle Y cosmétique sur "%CharacterModel" ENTIER (jamais la
## capsule/hitbox, §4.1 — un nœud Node3D frère de ce nœud, sans collision) :
## c'est le squash de CORPS du §12. Comme cette échelle de nœud porte sur
## TOUT le modèle, elle contre-échelonne aussitôt l'os de tête du squelette
## par l'inverse (`1 / scale_y`) pour que les sommets pondérés sur
## "DEF-head" restent à taille constante — donc AUCUN écrasement de tête
## (§4.6), même transitoirement pendant le squash. No-op défensif si le
## squelette ou l'os sont absents (modèle pas encore chargé, ou glb sans
## "DEF-head").
func _apply_body_squash(scale_y: float) -> void:
	if _character_body == null:
		return
	_character_body.scale.y = scale_y
	var skeleton := _character_body.get_skeleton()
	if skeleton == null:
		return
	var idx := skeleton.find_bone(_HEAD_BONE)
	if idx == -1:
		return
	var inverse_y := 1.0 / scale_y if not is_zero_approx(scale_y) else 1.0
	skeleton.set_bone_pose_scale(idx, Vector3(1.0, inverse_y, 1.0))

## Fait avancer le recul additif du haut du corps (GF-10), déclenché à chaque
## `Health.hit_reaction` (voir `_on_hit_reaction`) — s'éteint tout seul après
## `HIT_FLINCH_DURATION_S` (garde-fou, comme le squash) sans qu'aucun "reset"
## explicite soit nécessaire : `_apply_flinch` est additive et relit la pose
## fraîchement calculée par l'AnimationTree à CHAQUE frame (jamais de résidu
## d'une frame à l'autre, voir sa docstring).
func _drive_flinch(delta: float) -> void:
	if _flinch_elapsed < 0.0:
		return
	_flinch_elapsed += delta
	if _flinch_elapsed >= HIT_FLINCH_DURATION_S:
		_flinch_elapsed = -1.0
		return
	_apply_flinch(hit_flinch_angle_rad(_flinch_elapsed))

## Bascule additive de l'os `_FLINCH_BONE` (haut du corps, GF-10) : composée
## APRÈS la pose déjà écrite par l'AnimationTree ce frame (même principe que
## `_apply_body_squash`) — on LIT la rotation animée courante puis on la
## multiplie par le delta de recul, donc la pose de visée/tir en cours n'est
## jamais perdue, seulement inclinée en plus. No-op défensif si le squelette
## ou l'os sont absents (modèle pas encore chargé, ou glb sans `_FLINCH_BONE`).
func _apply_flinch(angle_rad: float) -> void:
	if _character_body == null:
		return
	var skeleton := _character_body.get_skeleton()
	if skeleton == null:
		return
	var idx := skeleton.find_bone(_FLINCH_BONE)
	if idx == -1:
		return
	var base := skeleton.get_bone_pose_rotation(idx)
	skeleton.set_bone_pose_rotation(idx, base * Quaternion(Vector3.RIGHT, angle_rad))

# ------------------------------------------------------------------
#  Construction de l'AnimationTree EN CODE — le squelette/AnimationPlayer
#  n'existent qu'après le chargement dynamique du glb (un par agent), donc
#  impossible de câbler ça dans le .tscn à l'avance.
# ------------------------------------------------------------------

func _build_tree() -> void:
	anim_player = get_path_to(_character_body.get_anim_player())

	var bt := AnimationNodeBlendTree.new()

	# -- Couche "Locomotion" (plein corps, sélection par transition) --------
	var locomotion_node := AnimationNodeTransition.new()
	for i in Locomotion.size():
		locomotion_node.add_input("state_%d" % i)
	# GF-27 : jamais de reset de phase à la transition sur une locomotion qui
	# boucle (voir `configure_locomotion_transition_reset`/`is_looping_locomotion`)
	# — sinon Idle/Walk/Jog/Sprint/... « ne bouclent jamais » à l'œil, même
	# avec un clip bien importé en boucle.
	configure_locomotion_transition_reset(locomotion_node)
	locomotion_node.xfade_time = 0.15
	bt.add_node("Locomotion", locomotion_node)
	for i in Locomotion.size():
		var leaf := AnimationNodeAnimation.new()
		leaf.animation = clip_for(i)
		var leaf_name := "Loco_%d" % i
		bt.add_node(leaf_name, leaf)
		bt.connect_node("Locomotion", i, leaf_name)
	# GF-27 : STUN (Hit_Head, 0,417 s) et INTERACT (Interact, 2,0 s) ont un
	# clip d'origine bien plus court que la durée réelle de l'état (2,2 s
	# d'étourdissement, 4 à 7 s de pose/désamorçage) — sans boucle FORCÉE, la
	# pose reste figée sur la dernière image du clip pour tout le reste de la
	# durée (contrat : "aucune image figée plus de 0,2 s").
	_apply_forced_loop(bt, Locomotion.STUN)
	_apply_forced_loop(bt, Locomotion.INTERACT)

	# -- Couche "haut du corps" (visée continue + respiration + one-shots) --
	var aim_pose := AnimationNodeBlendSpace1D.new()
	var aim_down := AnimationNodeAnimation.new()
	aim_down.animation = "Pistol_Aim_Down"
	var aim_neutral := AnimationNodeAnimation.new()
	aim_neutral.animation = "Pistol_Aim_Neutral"
	var aim_up := AnimationNodeAnimation.new()
	aim_up.animation = "Pistol_Aim_Up"
	aim_pose.add_blend_point(aim_down, -1.0, -1, &"down")
	aim_pose.add_blend_point(aim_neutral, 0.0, -1, &"neutral")
	aim_pose.add_blend_point(aim_up, 1.0, -1, &"up")
	bt.add_node("AimPose", aim_pose)

	# GF-27 "haut du corps selon la locomotion" : Pistol_Idle (respiration en
	# boucle) ajoutée par-dessus la pose de visée à poids FIXE — la visée
	# continue reste pleinement lisible (positions Down/Neutral/Up conservées),
	# mais la pose n'est plus totalement statique à l'arrêt/en marche.
	var idle_breath := AnimationNodeAnimation.new()
	idle_breath.animation = "Pistol_Idle"
	bt.add_node("IdleBreath", idle_breath)
	var breathing := AnimationNodeAdd2.new()
	bt.add_node("Breathing", breathing)
	bt.connect_node("Breathing", 0, "AimPose")
	bt.connect_node("Breathing", 1, "IdleBreath")

	var shoot_shot := AnimationNodeOneShot.new()
	shoot_shot.fadein_time = 0.03
	shoot_shot.fadeout_time = 0.08
	bt.add_node("ShootShot", shoot_shot)
	bt.connect_node("ShootShot", 0, "Breathing")
	var shoot_clip := AnimationNodeAnimation.new()
	shoot_clip.animation = "Pistol_Shoot"
	bt.add_node("ShootClip", shoot_clip)
	bt.connect_node("ShootShot", 1, "ShootClip")

	# GF-27 "rechargement calé sur reload_time" : ReloadSpeed (AnimationNodeTimeScale)
	# étire/accélère le clip Pistol_Reload (durée native RELOAD_CLIP_BASE_DURATION_S)
	# pour qu'il dure EXACTEMENT `reload_time` de l'arme en main — voir
	# `reload_clip_speed`/`_on_current_weapon_changed`/`_drive_upper_body`.
	var reload_shot := AnimationNodeOneShot.new()
	reload_shot.fadein_time = 0.05
	reload_shot.fadeout_time = 0.15
	bt.add_node("ReloadShot", reload_shot)
	bt.connect_node("ReloadShot", 0, "ShootShot")
	var reload_clip := AnimationNodeAnimation.new()
	reload_clip.animation = "Pistol_Reload"
	bt.add_node("ReloadClip", reload_clip)
	var reload_speed := AnimationNodeTimeScale.new()
	bt.add_node("ReloadSpeed", reload_speed)
	bt.connect_node("ReloadSpeed", 0, "ReloadClip")
	bt.connect_node("ReloadShot", 1, "ReloadSpeed")

	# -- Cadence : vitesse de lecture propre à l'agent (§4.6, ×0,9 à ×1,15) -
	# Ne modifie QUE la vitesse de LECTURE du clip dans l'AnimationTree —
	# jamais MovementConfig ni la vitesse réelle du joueur (couche 100 %
	# cosmétique, voir docstring de AgentAnimProfile.cadence_scale).
	var cadence := AnimationNodeTimeScale.new()
	bt.add_node("Cadence", cadence)
	bt.connect_node("Cadence", 0, "Locomotion")

	# -- Fusion : plein corps (base) + haut du corps (filtré spine/bras) ----
	var upper_body := AnimationNodeBlend2.new()
	upper_body.filter_enabled = true
	for path in _filter_paths():
		upper_body.set_filter_path(path, true)
	bt.add_node("UpperBody", upper_body)
	bt.connect_node("UpperBody", 0, "Cadence")
	bt.connect_node("UpperBody", 1, "ReloadShot")

	bt.connect_node("output", 0, "UpperBody")

	tree_root = bt
	active = true
	set("parameters/Cadence/scale", effective_cadence_scale(_profile.cadence_scale if _profile else 1.0))
	set("parameters/Breathing/add_amount", UPPER_BODY_BREATH_ADD_AMOUNT)
	set("parameters/ReloadSpeed/scale", reload_clip_speed(_reload_time))

## Force le clip d'origine de `locomotion` à boucler (contrat GF-27, voir
## `forced_loop_mode`) même si son `Animation.loop_mode` importé ne boucle pas
## (STUN/INTERACT : clips uniques, voir docs/research/10_ammo_kits_input.md
## §5.1) : bascule sur une timeline personnalisée de la durée RÉELLE du clip
## (`use_custom_timeline`/`timeline_length`, jamais étirée : `stretch_time_scale
## = false`) avec le `loop_mode` forcé. No-op défensif si l'AnimationPlayer ou
## le clip nommé sont introuvables (modèle pas encore chargé).
func _apply_forced_loop(bt: AnimationNodeBlendTree, locomotion: int) -> void:
	var leaf := bt.get_node("Loco_%d" % locomotion) as AnimationNodeAnimation
	var ap := _character_body.get_anim_player() if _character_body else null
	if leaf == null or ap == null or not ap.has_animation(leaf.animation):
		return
	var anim := ap.get_animation(leaf.animation)
	leaf.use_custom_timeline = true
	leaf.timeline_length = anim.length
	leaf.stretch_time_scale = false
	leaf.loop_mode = forced_loop_mode(locomotion)

## Chemins de piste (relatifs à `AnimationPlayer.root_node`) pour la couche
## "haut du corps" : colonne + les deux bras, doigts inclus.
func _filter_paths() -> Array:
	var names: Array = _UPPER_BODY_BONES.duplicate()
	for side in ["L", "R"]:
		for chain in _FINGER_CHAINS:
			for seg in [1, 2, 3]:
				names.append("DEF-%s.0%d.%s" % [chain, seg, side])
	var paths: Array = []
	for n in names:
		paths.append(NodePath(_SKELETON_TRACK_PREFIX + n))
	return paths
