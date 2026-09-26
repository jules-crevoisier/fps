## ViewModel.gd
## Arme + gants vus par le joueur LOCAL uniquement — enfant de Head/Camera3D
## (voir scenes/player/player.tscn).
##
## Lead call (tâche "fp gloves", après 3 échecs successifs sur le rig
## fp_arms.glb squeletté — un bras plein réutilisant le rig corps entier des
## agents, posé "FP_Hold" puis résolu vers la main gauche via
## `solve_grip_transform`/`shortest_arc_basis` : le résultat rendait
## systématiquement un bras qui traverse l'écran de travers avec une arme
## illisible, voir scratchpad/shots/fp_final/fp_ravage.png) : plus de
## squelette, plus de pose, plus de solveur d'orientation main-cible. À la
## place, deux gants FLOTTANTS façon Rayman (assets/models/characters/
## fp_gloves.glb — pas d'avant-bras, juste une manchette courte) dont
## l'ORIGINE de chaque maillage est DÉJÀ le point de contact avec l'arme : le
## gant droit ("GloveR") se rattache tel quel (transform IDENTITÉ, modulo un
## petit ancrage/échelle PAR ARME, voir plus bas) à l'origine de l'arme (= la
## poignée, cf. tools/blender/make_weapons.py) et le gant gauche ("GloveL")
## vers son empty "Foregrip" — PAS de solveur d'orientation générique comme
## avant, juste un repositionnement dans l'arbre de scène (`_load_gloves`/
## `_attach_gloves`) et une seule petite correction locale
## (`_left_glove_anchor`, voir sa doc : "Foregrip" tombe à l'intérieur de la
## géométrie de l'arme sur les 7 modèles, donc on le pousse vers "Muzzle"
## d'une fraction fixe).
##
## FP-02 (2e passage) : la géométrie elle-même vient de
## tools/blender/fit_gloves_painted.py — DEUX mains Tripo Studio PEINTES
## (ART-84, assets/incoming/tripo/studio/fp_glove_{grip,support}.glb, main
## adulte réelle ~19 cm poignet-doigt/~9 cm de paume, pivot au creux de la
## paume, orientée vers Grip/Foregrip), PLUS les blocs beiges génériques de
## tools/blender/make_gloves.py (1er passage : seules les ancres avaient
## bougé, la géométrie restait celle des blocs — constaté par le lead sur
## fp_shots, corrigé ici). `make_gloves.py` reste dans le dépôt comme outil de
## PROTOTYPAGE (silhouette rapide sans dépendre des sources Tripo), mais ne
## nourrit plus fp_gloves.glb en production.
##
## FP-02 (3e passage) : le 2e passage avait posé la géométrie peinte mais
## laissait deux défauts constatés par capture — poignet coupé (calotte plate
## mal texturée, « disque crème ») qui fait face à la caméra sur les 7 armes,
## et un poing droit qui lit comme une capsule sans doigts sur Pistolet/
## Magnum/Marqueur. Corrigés respectivement par une MANCHE (tissu de veste,
## tronc de cône évasé ajouté au poignet de chaque gant — voir la doc "MANCHE"
## en tête de tools/blender/fit_gloves_painted.py) qui sort du cadre bas/droit
## plutôt que de laisser voir la calotte, et par un lacet PAR ARME du gant
## droit (voir `right_glove_rotation_for`/`_RIGHT_GLOVE_ROTATION_BY_ID`, même
## principe mesuré que `weapon_scale_for`) qui révèle le flanc du poing plutôt
## que son talon SEULEMENT sur ces 3 armes (jamais un lacet partagé, qui avait
## cassé le Fracas au 2e passage — voir la doc de `_RIGHT_GLOVE_ANCHOR_BY_ID`).
##
## L'arme (assets/models/weapons/*.glb, voir tools/blender/make_weapons.py et
## Weapon.model_path_for) est posée directement en enfant de CE nœud
## (`_place_weapon`) : une légère rotation lacet (`_MODEL_YAW_DEG`) tourne le
## canon vers le centre de l'écran (cadrage FPS classique : arme parallèle à
## la vue, entrant en bas à droite, canon pointant vers le viseur, côté droit
## visible) plutôt que de pointer bras tendu droit devant ; une échelle et un
## petit décalage PAR ARME (`weapon_scale_for`/`weapon_nudge_for`, FP-01 —
## repli par catégorie tant qu'une arme n'a pas son propre réglage) ajustent
## le cadrage à l'œil (voir tools/fp_shots.gd) arme par arme, chaque
## silhouette Tripo peinte ayant ses propres proportions.
##
## Matériaux : arme peinte (A3D-20, tools/blender/fit_weapon_painted.py — les 7
## armes du jeu) ET gants peints (FP-02, tools/blender/fit_gloves_painted.py)
## = `Cartoon.painted_texture_prop(...)` (texture Tripo Studio conservée,
## contour plat 2 px, voir `_PAINTED_MATERIAL_MARKER`) ; toute surface d'un
## ancien slot bpy en blocs restant ("_body"/"_grip"/"_metal"/"_accent" côté
## arme, "_glove"/"_cuff" côté gants) = `Cartoon.character(...)`/
## `Cartoon.character_surface(...)` (contour fin — voir `_THIN_OUTLINE_PX`,
## repli défensif, plus jamais produit en production, voir
## `_apply_glove_materials`). La manchette du gant peint garde SA couleur
## peinte (jamais reteintée en couleur d'équipe) — la vue FPS ne montre de
## toute façon jamais que les gants du joueur LOCAL, jamais une teinte
## ennemie réservée par docs/STYLE_BIBLE.md.
##
## Pilote une animation procédurale (sway souris, bob, recul-ressort, dip de
## rechargement, montée d'équipement, visée, tilt de slide) appliquée à CE
## nœud (`position`/`rotation`) — la racine arme+gants, donc les deux en
## héritent ensemble. En plus, un petit geste de rechargement DÉDIÉ au gant
## gauche seul (`AnimState.reload_glove_offset`) : il plonge vers la zone du
## chargeur puis revient, synchronisé sur le même minuteur que le dip
## d'ensemble (`reload_t`/`reload_dur`) mais avec sa propre trajectoire
## locale (relative à sa position de repos sur le Foregrip), pour lire comme
## un vrai geste de main plutôt qu'un simple déplacement de caméra.
## Modèle tenu PETIT et PRÈS de la caméra (jamais dans le champ de la capsule
## du joueur, rayon 0.4 m, cf. acceptance R-A2 #2) : c'est ce qui évite le
## clipping dans les murs (pas de near-plane dédié, juste la proximité —
## "the small/near trick").
## Toute la PHYSIQUE/anim est dans `AnimState` (RefCounted, sans arbre de
## scène) pour rester testable sans instancier de Node3D — voir
## tests/combat/test_weapon_fx.gd (recul/sway/bob/reload/equip/muzzle/blends)
## et tests/player/test_viewmodel_pose_math.gd (`reload_glove_offset`).
class_name ViewModel
extends Node3D

## Position de repos du modèle par rapport à la caméra (arme+gants tenus en
## bas à droite, un peu vers l'avant — jamais dans le champ de la capsule du
## joueur, rayon 0.4 m, cf. acceptance R-A2 #2). Ces valeurs supposent que la
## poignée de l'arme (son origine) est à la racine LOCALE de ce nœud (0,0,0) —
## vrai maintenant que l'arme est un enfant direct sans décalage caché (voir
## `_place_weapon` : nudge/échelle PAR ARME depuis FP-01, mais jamais de gros
## offset de compensation comme l'ancien `_ARMS_ROOT_OFFSET` du rig squeletté).
## Réglées À L'ŒIL pour TARGET_FOV_DEG (voir sa doc juste en dessous) via
## tools/fp_shots.gd — cadrage §5.3 : canon à la hanche x 0,58–0,64 / y
## 0,56–0,64, carré central 20 % × 20 % vide (ART-12 : avant cette tâche,
## `fp_ravage` couvrait ~25 % de l'écran avec le canon à x 0,52, trop centré
## et trop gros — voir docs/STYLE_BIBLE.md §5.3 ; FP-01 : les silhouettes
## Tripo peintes livrées après ART-12 débordaient à nouveau, cette fois par
## arme plutôt que par catégorie, d'où `weapon_scale_for`/`weapon_nudge_for`).
const REST_POS := Vector3(0.225, -0.185, -0.62)
## `ADS_POS.y` retouché lors du 2e passage de FP-01 (`-0.02` -> `-0.30`) pour
## `ads_sight_top_y` de tokens.json ([0,48 ; 0,52], §5.3 « bord haut de la
## hausse à y 0,50 ± 0,02 ») — mesuré par `tools/fp_shots.gd`
## (`_measure_ads_sight_top_y`, faute d'empty "Sight" dédié sur les 7 armes) :
## avant retouche, l'arme montait beaucoup trop haut en visée (~0,33, verifié
## sur le Ravage — l'arme de référence pour cette pose, voir
## `_equip_pose_weapon`) ; ce point est commun à TOUTES les armes (`ADS_POS`
## n'a pas de réglage par arme, contrairement à la hanche) et reste sous la
## couverture ADS max (28 %, §5.3) avec de la marge (~9 % mesuré).
const ADS_POS := Vector3(0.0, -0.34, -1.15)

## FOV vertical CIBLE du viewmodel (§5.3 : « 54° vertical, fixe, indépendant
## du FOV monde ») : REST_POS/ADS_POS/`weapon_scale_for`/`weapon_nudge_for` ci-
## dessus et ci-dessous sont tous réglés à l'œil en supposant CE FOV. Le FOV
## RÉEL de la caméra (`player.camera.fov`) varie pourtant sans arrêt —
## Settings.fov (options, 70–120°), bonus sprint/slide/survitesse
## (MovementConfig, piloté par PlayerCamera.gd) et surtout le zoom en visée
## (`WeaponConfig.aim_fov`, de 28° pour le Faucheur à 70° pour un pistolet,
## cf. resources/weapons/*.tres) — sans compensation, le simple fait de
## zoomer avec un sniper ferait "gonfler" l'arme à l'écran exactement comme
## n'importe quel objet fixe filmé par un zoom optique réel. `_fov_scale()`
## neutralise cet écart chaque frame (voir sa doc, appelée depuis `_process`).
const TARGET_FOV_DEG := 54.0

## Contour d'encre pour l'arme ET les gants du viewmodel (design.md §5
## « Viewmodel et pickups : 2 px d'encre ») — plus fin que le contour
## PERSONNAGE par défaut (3 px, `Cartoon.character()` sans argument), jamais
## atténué par la distance puisque le viewmodel est toujours à quelques
## centimètres de la caméra.
const _THIN_OUTLINE_PX := 2.0

const GLOVES_PATH := "res://assets/models/characters/fp_gloves.glb"
## Repli si un gant "GloveR"/"GloveL" est introuvable dans fp_gloves.glb (ne
## devrait jamais arriver hors développement du modèle) ou si l'arme n'a pas
## d'empty "Foregrip" valide.
const _DEFAULT_FOREGRIP_LOCAL := Vector3(0.0, 0.05, -0.3)

## Légère rotation lacet (autour de Y) appliquée à l'arme (et donc aux deux
## gants, enfants d'elle) : PAS nécessaire pour la convergence canon->viseur
## (elle est déjà automatique — un canon -Z strictement parallèle à l'axe
## caméra, tiré depuis une position décalée à droite, converge tout seul vers
## le centre écran par simple perspective, vérifié via `Camera3D.
## unproject_position` pendant le réglage de cette tâche). Son seul rôle est
## de révéler le FLANC droit de l'arme (silhouette lisible en volume plutôt
## qu'un profil plat vu de dos) ; réglé à l'œil via tools/fp_shots.gd.
##
## MARQUEUR (id 3) — signalé au lead, PAS corrigible depuis CE fichier : sa
## lunette « gros feutre » (tokens.json `weapons.marqueur.signature`) ressort
## visiblement INCLINÉE en jeu (2e passage, 1er refus) alors que la carcasse,
## le canon et la crosse du MÊME modèle restent horizontaux — constaté par
## rendu (`tools/fp_shots.gd`), donc un défaut de la lunette DANS le maillage
## `assets/models/weapons/marqueur.glb` (mesh unique post-A3D-20, plus de
## slots séparés à corriger indépendamment, voir `_apply_cartoon_materials`),
## pas un souci de pose : `_MODEL_YAW_DEG` ci-dessus est un seul lacet PARTAGÉ
## par les 7 armes (pas de champ par arme) et une rotation compensatoire sur
## CETTE arme inclinerait aussi son canon/sa crosse déjà droits. Corrigible
## seulement en retouchant la géométrie (tools/blender/fit_weapon_painted.py
## ou le GLB), hors de la liste de fichiers de FP-01.
const _MODEL_YAW_DEG := 9.0

## Échelle par ARME (id `WeaponDatabase.PATHS`, FP-01) — remplace le réglage
## par CATÉGORIE d'ART-12 (conservé plus bas comme repli SEULEMENT pour les
## armes pas encore livrées par ART-13, voir `_WEAPON_SCALE_BY_CATEGORY`) :
## les silhouettes Tripo Studio peintes (A3D-20) n'ont PAS les proportions de
## l'ancien corps bpy en blocs à longueur égale (constaté aux captures
## `tools/fp_shots.gd` du 2026-09-25, après A3D-20 : Faucheur remplissait la
## moitié droite de l'écran à l'échelle SNIPER 1.90 héritée d'ART-12, Fracas
## et Ravage débordaient au-dessus du tiers haut à leurs échelles de
## catégorie) — deux armes de la MÊME catégorie (Marqueur/Ravage/Percuteur en
## fusil, par ex.) peuvent donc avoir besoin d'échelles différentes.
##
## Mesuré au masque, à chaque passe, avec l'outil OFFICIEL du projet — jamais
## un seuil ou une zone réimplémentés à la main :
## `godot --path . -s res://tools/fp_shots.gd -- --out=<dossier>` puis
## `python tools/review/style_check.py <dossier_run>` (`<dossier_run>/
## viewmodel_fp/fp/` recevant la sortie de fp_shots.gd) — CHK-28/29/30 tels que
## `docs/STYLE_BIBLE.md` §11.4 et `docs/style/tokens.json` (clé `viewmodel`)
## les définissent RÉELLEMENT :
## - CHK-28 (bloquant) : carré central 20 % × 20 % de l'image à 0 PIXEL de
##   viewmodel pile (seuil de pixel non noir > 127, comme `style_check.py`) —
##   pas un simple "résidu minime", un compte EXACTEMENT nul pour les 7 armes.
## - Tiers haut de l'écran (2e passage FP-01, décision du lead du 2026-09-25,
##   critère ajouté après le 1er refus — absent de tokens.json/style_check.py,
##   donc mesuré à la main sur les masques plutôt que via `style_check.py`) :
##   0 pixel de viewmodel dans le tiers supérieur (y < 1/3 de la hauteur) pour
##   les 7 armes, EN PLUS de CHK-28 — avant ce passage, le Fracas et le
##   Faucheur montaient jusqu'au bord haut (le Rafale et le Ravage y
##   débordaient aussi légèrement, quoique jugés "bien cadrés" au 1er passage
##   sur le seul critère CHK-28).
## - CHK-29 (bloquant) : couverture d'écran PAR CATÉGORIE (`coverage_hip` de
##   tokens.json, en pourcentage) — poing (Pistolet/Magnum) 7–10 %, SMG
##   (Rafale) 11–15 %, fusil (Marqueur/Ravage) 13–17 %, pompe/lourde
##   (Fracas — catégorie SHOTGUN ici) 15–19 %, sniper (Faucheur) 15–19 %.
##   `tools/review/style_check.py::resolve_fp_shots` compare par erreur ce
##   pourcentage (0–100) directement aux fractions (0–1) de `coverage_hip` —
##   un bug hors du périmètre de cette tâche (`tools/review/style_check.py`
##   n'est pas dans les fichiers possédés par FP-01) qui fait échouer CHK-29
##   dans le JSON final quelle que soit la couverture réelle ; les valeurs
##   ci-dessous sont validées en relisant `Finding.data` de cette même
##   fonction (coverage_pct par arme) contre la fourchette remise à la bonne
##   échelle (×100), pas contre un script maison.
## CHK-28 et le tiers haut tenus PILE pour les 7 armes peintes (id 0..6) à la
## date de ce réglage. CHK-29 (couverture) également tenu pour 6 des 7 armes —
## voir l'exception FAUCHEUR ci-dessous, un conflit géométrique réel constaté
## par la mesure, pas un oubli. CHK-30 (bouche du canon x 0,58–0,64 /
## y 0,56–0,64, §5.3) n'est PAS bloquant ("I", indicatif) : mesuré au masque
## (`fp_shots.json::weapons[].muzzle_screen`, jamais estimé à l'œil), sur les
## 7 armes SEULES Magnum (y 0,621), Fracas (y 0,637) et Faucheur (y 0,636,
## depuis le réglage ci-dessous) tombent DANS la plage y ; Pistolet (y 0,654),
## Rafale (y 0,681), Marqueur (y 0,660) et Ravage (y 0,669) en ressortent —
## 4 armes sur 7, PAS "Rafale/Marqueur/Ravage" (3) comme une relecture
## précédente l'affirmait par erreur (elle avait interverti les armes DANS la
## plage et celles qui en sortent) — accepté sciemment, CHK-28 étant bloquant
## et prioritaire, CHK-30 seulement indicatif.
##
## FAUCHEUR — conflit géométrique constaté, TOUJOURS PAS résolu par le réglage
## seul (signalé au lead, `blocked_on` du rapport de tâche) : sa lunette est
## un long tube qui, sur cette silhouette Tripo peinte, balaie la zone
## centrale de l'écran dès que l'arme est assez grande pour couvrir 15–19 %
## (cible CHK-29). Plus de 20 combinaisons échelle/décalage mesurées au 1er
## passage (masques, 2026-09-25), puis ~45 combinaisons SUPPLÉMENTAIRES à une
## 2e mesure (recherche par dichotomie sur l'échelle, de 1,28 à 2,00, ET sur
## le décalage à chaque palier, toujours via `tools/fp_shots.gd` + lecture
## directe des masques — jamais un seuil réimplémenté à la main) : DÈS que le
## carré central ET le tiers haut sont VRAIMENT à 0 pixel, la couverture
## mesurée plafonne à 12,2–12,6 % SUR TOUTE cette plage d'échelle (jamais
## 15 %+, quelle que soit l'échelle essayée) — le décalage nécessaire pour
## dégager ces deux zones fait sortir du cadre plus de silhouette que
## l'agrandissement n'en ajoute (l'arme est ancrée bas-droit et déjà coupée
## par le bord droit/bas, §5.3 « la crosse coupée par le bord droit ou le
## bas »). Meilleur point trouvé à cette 2e mesure (amélioration réelle,
## retenue ci-dessous) : CHK-28 et tiers haut à 0 PILE (priorité assumée,
## CHK-28 bloquant), couverture 12,55 % — mieux que les 11,76 % du 1er
## passage, mais TOUJOURS hors 15–19 % : la fourchette cible est
## géométriquement inatteignable pour cette silhouette avec les deux seuls
## leviers disponibles ici (`weapon_scale_for`/`weapon_nudge_for`) — à rouvrir
## seulement si le modèle `faucheur.glb` change (lunette raccourcie ou
## déplacée, hors des fichiers possédés par FP-01) ou si le lead accepte une
## fourchette de couverture réduite pour cette arme précise (décision hors de
## ce fichier — `docs/style/tokens.json` n'est pas non plus dans la liste de
## FP-01).
const _WEAPON_SCALE_BY_ID := {
	0: 0.95,   # Pistolet
	1: 1.06,   # Magnum
	2: 0.95,   # Rafale
	3: 1.01,   # Marqueur
	4: 1.14,   # Ravage
	5: 1.70,   # Fracas
	6: 1.35,   # Faucheur
}
## Décalage par ARME, même principe que `_WEAPON_SCALE_BY_ID` — voir
## `_WEAPON_NUDGE_BY_CATEGORY` pour la règle "jamais vers le haut-gauche".
const _WEAPON_NUDGE_BY_ID := {
	0: Vector3(0.02, -0.006, -0.02),
	1: Vector3(0.0, 0.02, 0.0),
	2: Vector3(0.09, -0.065, -0.04),
	3: Vector3(0.165, -0.10, -0.06),
	4: Vector3(0.145, -0.125, -0.08),
	5: Vector3(0.255, -0.135, -0.09),
	6: Vector3(0.289, -0.118, 0.0),
}
## Repli par CATÉGORIE (WeaponConfig.Category), réglage hérité d'ART-12 —
## SEULEMENT pour une arme sans entrée dans `_WEAPON_SCALE_BY_ID`/
## `_WEAPON_NUDGE_BY_ID` ci-dessus (Éclair/Semeuse/Percuteur, pas encore
## livrées par ART-13 au moment de FP-01) : un POINT DE DÉPART approximatif,
## jamais mesuré sur un vrai rendu pour ces trois armes précises — à
## revérifier au masque dès que leur modèle existe, en suivant la même
## méthode (échelle jusqu'à la couverture cible, puis nudge jusqu'à un carré
## central à 0 pixel).
const _WEAPON_SCALE_BY_CATEGORY := {
	WeaponConfig.Category.SMG: 1.13,
	WeaponConfig.Category.RIFLE: 1.46,
	WeaponConfig.Category.SHOTGUN: 2.82,
	WeaponConfig.Category.SNIPER: 1.90,
	WeaponConfig.Category.HEAVY: 1.40,
}
const _DEFAULT_WEAPON_SCALE := 1.0
## Pousse le modèle vers le bas-droit (jamais vers le haut-gauche, qui le
## ferait empiéter sur le carré central — CHK-28) : les gabarits agrandis
## ci-dessus, sans ce décalage, mordraient sur le carré central 20 % × 20 %
## (§5.3, CHK-28) puisqu'un modèle plus grand s'étend aussi plus loin vers le
## haut-gauche depuis son origine (la poignée). Mesuré à l'œil (masques).
const _WEAPON_NUDGE_BY_CATEGORY := {
	WeaponConfig.Category.SMG: Vector3(0.03, -0.02, 0.0),
	WeaponConfig.Category.RIFLE: Vector3(0.10, -0.09, 0.0),
	WeaponConfig.Category.SHOTGUN: Vector3(0.273, -0.296, 0.0),
	WeaponConfig.Category.SNIPER: Vector3(0.16, -0.16, 0.08),
	WeaponConfig.Category.HEAVY: Vector3(0.09, -0.09, 0.04),
}
const _DEFAULT_WEAPON_NUDGE := Vector3.ZERO

## Échelle de cadrage pour l'arme `weapon_id` (index `WeaponDatabase.PATHS`) —
## repli par catégorie si cette arme précise n'a pas encore son propre réglage
## (voir doc de `_WEAPON_SCALE_BY_ID`). Fonction PURE (aucun accès à l'arbre de
## scène, juste `WeaponDatabase` pour la catégorie) : testée directement dans
## tests/player/test_viewmodel_pose_math.gd.
static func weapon_scale_for(weapon_id: int) -> float:
	if _WEAPON_SCALE_BY_ID.has(weapon_id):
		return _WEAPON_SCALE_BY_ID[weapon_id]
	var cfg := WeaponDatabase.get_by_id(weapon_id)
	return _WEAPON_SCALE_BY_CATEGORY.get(cfg.category, _DEFAULT_WEAPON_SCALE) if cfg else _DEFAULT_WEAPON_SCALE

## Décalage de cadrage pour l'arme `weapon_id` — même principe de repli que
## `weapon_scale_for`, même garantie de pureté.
static func weapon_nudge_for(weapon_id: int) -> Vector3:
	if _WEAPON_NUDGE_BY_ID.has(weapon_id):
		return _WEAPON_NUDGE_BY_ID[weapon_id]
	var cfg := WeaponDatabase.get_by_id(weapon_id)
	return _WEAPON_NUDGE_BY_CATEGORY.get(cfg.category, _DEFAULT_WEAPON_NUDGE) if cfg else _DEFAULT_WEAPON_NUDGE

## Pose sprint (§5.3 « arme pivotée de 25° vers le bas et la gauche,
## couverture ≤ 20 % ») : un seul ROLL (rotation autour de l'axe de visée,
## même principe que le tilt de Slide juste en dessous dans `_process` — PAS
## une rotation de visée, l'arme ne se braque nulle part) fait pivoter toute
## la silhouette en diagonale bas-gauche en un geste lisible ; le repli
## (vers le bas et vers l'arrière, donc plus loin de la caméra) réduit la
## couverture d'écran pendant la course sans dépendre du gabarit par arme.
const SPRINT_ROLL_DEG := 25.0
const SPRINT_POS_OFFSET := Vector3(-0.02, -0.10, -0.16)

## Calque de rendu (1–20, `VisualInstance3D.layers`/`Camera3D.cull_mask`)
## dédié à l'arme+gants — aucun autre système du jeu ne s'en sert (aucune
## surbrillance, aucun minimap, rien). Réservé pour `set_mask_mode` ci-dessous,
## qui l'ajoute sur chaque maillage SANS retirer le calque 1 par défaut (donc
## sans rien changer au rendu normal) : `tools/fp_shots.gd` peut alors
## restreindre `Camera3D.cull_mask` à CE SEUL calque pour obtenir un rendu où
## rien d'autre que l'arme+gants n'existe (§5.3, masque CHK-28/29/30).
const _MASK_RENDER_LAYER := 20

## Bras premières-personne de Verrou (tâche "frog fp arms", 2026-09-26) --
## remplace les gants flottants (`_glove_r`/`_glove_l` ci-dessous) QUAND
## `assets/models/characters/frog_cowboy_fp.glb` charge avec succès
## (`_using_arms`, décidé une seule fois dans `_ready()`, voir `FPArmsRig.gd`
## pour le rig lui-même et `FPArmsMath.gd` pour les maths d'alignement/anim).
## Repli sur le chemin gants HISTORIQUE (inchangé) si ce glb est absent/
## invalide -- voir `_ready()`.
var _arms: FPArmsRig
var _using_arms: bool = false

var player: PlayerController
var weapon: Weapon
var _anim := AnimState.new()
var _current_id: int = Inventory.EMPTY
var _model: Node3D
var _muzzle: Node3D
var _muzzle_mesh: MeshInstance3D
## Les deux gants, chargés UNE FOIS (voir `_load_gloves`) et reparentés sous
## l'arme courante à chaque changement (`_attach_gloves`) — jamais recréés,
## contrairement à `_model` qui est détruit/reconstruit par arme.
var _glove_r: Node3D
var _glove_l: Node3D
## Position de repos locale du gant gauche (celle de l'empty "Foregrip" de
## l'arme courante) : le geste de rechargement (`AnimState.
## reload_glove_offset`) s'ajoute PAR-DESSUS cette valeur chaque frame plutôt
## que de la modifier directement, pour ne jamais dériver au fil des
## rechargements.
var _glove_l_rest: Vector3 = Vector3.ZERO
var _last_mouse_delta: Vector2 = Vector2.ZERO
var _ads_t: float = 1.0        # 1 = hanche, 0 = visée
var _sprint_t: float = 0.0
var _slide_t: float = 0.0
## Matériau blanc plein non éclairé partagé par `set_mask_mode` (une seule
## ressource pour tous les maillages masqués, jamais recréée par frame).
var _mask_material: StandardMaterial3D

func _ready() -> void:
	player = get_parent().get_parent().get_parent() as PlayerController
	if player == null or not player.is_local_human():
		set_process(false)
		set_process_input(false)
		visible = false
		return
	weapon = player.get_node_or_null("Weapon") as Weapon
	if weapon:
		weapon.fired.connect(_on_fired)
		weapon.reload_started.connect(_on_reload_started)
		weapon.weapon_changed.connect(_on_weapon_changed)
	position = REST_POS
	# Bras FP grenouille EN PRIORITÉ (tâche "frog fp arms") -- `add_child` AVANT
	# `load()` : FPArmsRig a besoin d'être dans l'arbre de scène pour que
	# `get_path_to` (câblage AnimationTree -> AnimationPlayer, voir
	# FPArmsRig._build_tree) calcule un chemin valide. Repli sur les gants
	# flottants historiques (`_load_gloves`, INCHANGÉ) si le glb est absent/
	# invalide -- jamais les deux à la fois (requirement 6 du contrat).
	_arms = FPArmsRig.new()
	add_child(_arms)
	_using_arms = _arms.load()
	if not _using_arms:
		_arms.queue_free()
		_arms = null
		_load_gloves()
	_refresh_model()
	# Contour post-traitement BD (2026-09-26, ToonStyle.gd) : posé UNE FOIS sur la
	# Camera3D locale -- structurel (`get_parent()` EST la Camera3D, voir la
	# docstring de ce fichier "enfant de Head/Camera3D"), donc valide dès ce
	# `_ready()` sans dépendre de l'ordre d'exécution d'un autre script (contrairement
	# à `player.camera`, peuplé par PlayerCamera.gd). DIFFÉRÉ (`call_deferred`) :
	# ce `_ready()` tourne PENDANT que GameWorld._spawn_player ajoute encore ses
	# propres enfants (même piège documenté par MapSetup.gd _enter_tree -- "Parent
	# node is busy setting up children") -- un add_child() immédiat sur la Camera3D
	# échoue silencieusement (erreur moteur, pas une exception) tant que l'arbre du
	# joueur n'a pas fini de se construire.
	call_deferred("_wire_outline_pass")

## Charge fp_gloves.glb UNE FOIS (les gants eux-mêmes ne changent jamais,
## contrairement à l'arme) : extrait "GloveR"/"GloveL" de la scène importée et
## jette le reste (l'empty racine "Gloves" de tools/blender/fit_gloves_painted.py,
## qui ne sert qu'à donner à l'export un unique nœud racine). Les deux gants
## restent SANS PARENT jusqu'à la première `_attach_gloves` (appelée par
## `_refresh_model` juste après).
## Voir _ready() : add_outline_pass fait un add_child() sur la Camera3D, qui
## échoue si l'arbre du joueur est encore en train de se construire.
func _wire_outline_pass() -> void:
	ToonStyle.add_outline_pass(get_parent() as Camera3D)

func _load_gloves() -> void:
	if not ResourceLoader.exists(GLOVES_PATH):
		push_warning("ViewModel : fp_gloves introuvable (%s)" % GLOVES_PATH)
		return
	var packed := load(GLOVES_PATH) as PackedScene
	if packed == null:
		return
	var gloves := packed.instantiate() as Node3D
	if gloves == null:
		return
	_glove_r = gloves.find_child("GloveR", true, false) as Node3D
	_glove_l = gloves.find_child("GloveL", true, false) as Node3D
	for g in [_glove_r, _glove_l]:
		if g == null:
			continue
		g.get_parent().remove_child(g)
		# Efface l'owner hérité de la scène importée (le "Gloves" temporaire) :
		# sans ça, chaque réattache sous une nouvelle arme (`_attach_gloves`)
		# avertit "will make owner inconsistent" (l'owner d'origine n'existe
		# plus une fois `gloves.queue_free()` appelé ci-dessous).
		_clear_owner(g)
		_apply_glove_materials(g)
	gloves.queue_free()
	if _glove_r == null or _glove_l == null:
		push_warning("ViewModel : GloveR/GloveL introuvables dans fp_gloves.glb")

func _clear_owner(n: Node) -> void:
	n.owner = null
	for c in n.get_children():
		_clear_owner(c)

## FP-02 (2e passage) : fp_gloves.glb vient désormais de
## tools/blender/fit_gloves_painted.py (gants Tripo Studio PEINTS, ART-84) —
## chaque gant ne porte plus qu'UN SEUL matériau ("GloveR_painted"/
## "GloveL_painted", voir `keep_painted_material` côté Blender), détecté ici
## par `_PAINTED_MATERIAL_MARKER` (même marqueur, même convention EXACTE que
## `_apply_cartoon_materials` pour l'arme peinte juste à côté) et routé vers
## `Cartoon.painted_texture_prop` — son `next_pass` (contour plat 2 px, voir
## sa doc) est CONSERVÉ tel quel (`continue`, pas de réécriture), comme pour
## l'arme : jamais besoin de reposer `thin_outline` par-dessus, ce serait un
## second contour ink IDENTIQUE au premier.
##
## CONTRADICTION DE SPÉCIFICATION — RÉSOLUE PAR LE LEAD (2026-09-25, reprise
## dans l'acceptance FP-02 du 3e passage : « La manchette garde sa couleur
## peinte... pas de teinte d'équipe ») : `tasks/backlog.yaml` portait
## auparavant DEUX formulations qui s'opposaient littéralement (ses notes,
## « manchette laissée à sa couleur peinte », contre son acceptance de l'époque,
## « manchette alliée ») — signalé au lead par les 1er/2e passages de cette
## tâche (aucun des deux n'avait tranché seul, voir l'historique ci-dessous),
## qui a depuis tranché explicitement pour la 1ère lecture. Le code ci-dessous
## ET `tests/player/test_fp_gloves.gd::
## test_glove_r_and_glove_l_each_carry_exactly_one_painted_material` (qui
## verrouille l'absence de tout matériau "_cuff"/"_glove" sur fp_gloves.glb)
## suivent maintenant la décision tranchée, plus une divergence à signaler.
##
## Historique (1er/2e passage, pour mémoire) : le 1er passage avait déjà
## tranché seul pour la lecture "notes" ; la relecture QA du 2e passage avait
## jugé ce choix UNILATÉRAL (pas le mauvais choix en soi) et l'avait donc
## remis en `blocked_on` plutôt que de le figer — remonté au lead, qui a
## depuis validé cette même lecture explicitement dans l'acceptance ci-dessus.
##
## Les branches "_cuff"/"_glove" ci-dessous (ancien corps bpy en blocs de
## make_gloves.py, cuir plat + manchette recolorée à l'équipe) restent en
## repli défensif — plus jamais produites par fit_gloves_painted.py en l'état
## actuel de la lecture "notes" ci-dessus, mais gardées si make_gloves.py est
## relancé un jour en dev (jamais un crash sur un fp_gloves.glb "ancien
## style"), ET c'est le chemin qui s'activerait mécaniquement si la lecture
## "manchette alliée" était un jour implémentée (voir plus haut).
##
## FP-03 (verdict lead fp_shots 2026-09-25 12h40) : branche "_sleeve" AJOUTÉE
## — la manche (tissu de veste au poignet, tools/blender/fit_gloves_painted.py
## ::_add_sleeve/_add_sleeve_material, géométrie ET matériau SÉPARÉS de la
## main depuis ce passage, voir l'en-tête "FP-03" du script Blender) porte un
## matériau plat baked SANS texture — jamais reconnu par
## `_PAINTED_MATERIAL_MARKER`, donc jamais routé vers
## `Cartoon.painted_texture_prop` (le défaut corrigé : « elle reprend la
## texture du gant étirée »). Reteint ici à la couleur-clé de l'agent
## sélectionné (`AgentDatabase.selected().color`, seule source déjà exposée
## dans le code pour cette notion — ViewModel.gd ne connaît PAS l'agent
## autrement, aucune arme/gant ne variant par agent) assombrie via
## `_SLEEVE_DARKEN_AMOUNT` : « tissu de veste sombre » (acceptance), PAS un
## repli neutre comme "_glove" (couleur baked) NI une couleur d'équipe comme
## "_cuff" (`Cartoon.ally_color()`) — un troisième cas, distinct des deux
## précédents. Ne contredit PAS la décision lead "manchette peinte, pas de
## teinte d'équipe" (voir plus haut) : celle-ci portait sur l'ANCIENNE
## manchette bpy fondue dans le maillage/matériau de la main ; la MANCHE de ce
## passage est une géométrie ET un matériau entièrement séparés.
func _apply_glove_materials(glove: Node3D) -> void:
	for mesh in _find_mesh_instances(glove):
		if mesh.mesh == null:
			continue
		mesh.extra_cull_margin = 2.0
		# Contour fin dédié viewmodel (voir `_apply_cartoon_materials`, même
		# traitement pour l'arme) : `next_pass` déjà fabriqué par l'API
		# publique `Cartoon.character(color, outline_px)` — UNIQUEMENT pour le
		# repli "_cuff"/"_glove"/"_sleeve" (le matériau peint apporte déjà le
		# sien, voir la doc de cette fonction).
		var thin_outline := Cartoon.character(Color.WHITE, _THIN_OUTLINE_PX).next_pass
		for i in mesh.mesh.get_surface_count():
			var mat: Material = mesh.mesh.surface_get_material(i)
			var mat_name: String = mat.resource_name if mat else ""
			if mat_name.contains(_PAINTED_MATERIAL_MARKER):
				# Gants viewmodel (2026-09-26, style BD, ToonStyle.gd) : plus de
				# next_pass ici -- le contour est désormais le pass plein écran
				# (ToonStyle.add_outline_pass, posé une fois dans _ready()).
				var tex := Cartoon.texture_from_imported_material(mat)
				mesh.set_surface_override_material(i, ToonStyle.toon_material(tex))
				continue
			if mat_name.ends_with("_cuff"):
				mesh.set_surface_override_material(i, Cartoon.character_surface("cloth", Cartoon.ally_color()))
			elif mat_name.ends_with(_SLEEVE_MATERIAL_MARKER):
				var sleeve_color := AgentDatabase.selected().color.darkened(_SLEEVE_DARKEN_AMOUNT)
				mesh.set_surface_override_material(i, Cartoon.character_surface("cloth", sleeve_color))
			elif mat_name.ends_with("_glove"):
				var src := mat as BaseMaterial3D
				var color: Color = src.albedo_color if src else Color(0.42, 0.29, 0.20)
				mesh.set_surface_override_material(i, Cartoon.character_surface("gear", color))
			var applied: Material = mesh.get_surface_override_material(i)
			if applied:
				applied.next_pass = thin_outline

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_last_mouse_delta += event.relative

func _process(delta: float) -> void:
	if player == null or weapon == null:
		return
	var sm := player.state_machine.current_name if player.state_machine else ""
	var aiming := player.input.aim_held
	var c := weapon.cfg()
	var ads_speed := 1.0 / maxf(c.ads_time, 0.001) if c else 10.0
	_ads_t = _anim.ads_blend(aiming, _ads_t, delta, ads_speed)
	# `sm == "Sprint"` (avant ART-12 : `false` en dur — la pose sprint du
	# viewmodel n'activait donc jamais, ni en jeu ni dans tools/fp_shots.gd).
	_sprint_t = _anim.sprint_pose_blend(sm == "Sprint", _sprint_t, delta)
	_slide_t = _anim.slide_tilt_blend(sm == "Slide", _slide_t, delta)

	_anim.tick_sway(_last_mouse_delta, delta)
	_last_mouse_delta = Vector2.ZERO
	_anim.tick_recoil(delta)
	var bob := _anim.tick_bob(player.horizontal_speed(), 9.0, delta)
	var reload_off := _anim.tick_reload(delta)
	var equip_off := _anim.tick_equip(delta)
	var reloading := _anim.reload_t >= 0.0
	# Compensation de FOV (§5.3, voir la doc de TARGET_FOV_DEG) : en
	# projection perspective, une coordonnée écran vaut (décalage / -
	# profondeur) / tan(fov/2) — à décalage et profondeur FIXES (ceux réglés
	# à l'œil pour TARGET_FOV_DEG), il suffit donc de multiplier les axes
	# ÉCRAN (x, y) par tan(fov_réel/2) / tan(TARGET_FOV_DEG/2) pour garder le
	# même rendu quel que soit le FOV réel de la caméra — jamais z, qui reste
	# la profondeur réglée à l'œil (voir `_fov_scale`, même facteur appliqué
	# à `scale` : la taille du maillage doit suivre le même calcul).
	var fov_scale := _fov_scale()

	if _using_arms:
		_process_arms(aiming, reloading, bob, fov_scale)
	else:
		_process_gloves(delta, bob, reload_off, equip_off, fov_scale)

	if _muzzle_mesh:
		_muzzle_mesh.visible = _anim.is_muzzle_visible()
		if not _anim.tick_muzzle(delta):
			_muzzle_mesh.visible = false

## Chemin HISTORIQUE (gants flottants, voir la docstring de classe) : position/
## rotation/scale de CE nœud (racine arme+gants) pilotées directement, base
## REST_POS<->ADS_POS + tout le "feel" procédural (sway/bob/recul/dip de
## rechargement/montée d'équipement/pose sprint/tilt de slide) -- comportement
## STRICTEMENT INCHANGÉ par la tâche "frog fp arms" (voir `_process_arms` pour
## le chemin bras, qui NE partage PAS cette base REST_POS/ADS_POS -- requirement
## 2 du contrat : « disable the old ADS positional offset for the frog arms »).
func _process_gloves(delta: float, bob: Vector3, reload_off: Vector3, equip_off: Vector3, fov_scale: float) -> void:
	var base := REST_POS.lerp(ADS_POS, 1.0 - _ads_t)
	var proc := Vector3(_anim.sway_offset.x, _anim.sway_offset.y, 0.0) * _ads_t \
		+ bob * _ads_t + Vector3(0, _anim.recoil_offset.y * 0.02, _anim.recoil_offset.y * 0.03) \
		+ reload_off + equip_off + SPRINT_POS_OFFSET * _sprint_t
	var target := Vector3((base.x + proc.x) * fov_scale, (base.y + proc.y) * fov_scale, base.z + proc.z)
	position = position.lerp(target, clampf(18.0 * delta, 0.0, 1.0))
	scale = Vector3(fov_scale, fov_scale, 1.0)
	rotation.z = -_slide_t * deg_to_rad(6.0) - _anim.sway_offset.x * 1.5 - _sprint_t * deg_to_rad(SPRINT_ROLL_DEG)
	rotation.x = _anim.recoil_offset.y * 0.35

	# Geste de rechargement dédié au gant gauche seul (voir doc de classe) :
	# doit être lu APRÈS `tick_reload`, qui avance le minuteur partagé
	# `reload_t`/`reload_dur`.
	if _glove_l:
		_glove_l.position = _glove_l_rest + _anim.reload_glove_offset()

## Chemin bras FP grenouille (tâche "frog fp arms") : PAS de REST_POS/ADS_POS
## (requirement 2, « disable the old ADS positional offset for the frog arms
## so it isn't applied twice » -- FP_ADS porte déjà la pose de visée) ni de
## dip de rechargement/montée d'équipement/pose-sprint-par-décalage/tilt de
## slide (les clips FP_Reload/FP_Draw/FP_Sprint les portent désormais, voir
## FPArmsRig._build_tree) -- seul le "feel" procédural que le contrat demande
## de garder (requirement 1 : « sway, walk bob, recoil kick, FOV compensation »)
## est composé ici, comme une PETITE transform LOCALE À LA CAMÉRA (`proc`) --
## FPArmsRig.align_to_camera la multiplie à `camera.global_transform` avant de
## résoudre l'alignement (voir sa docstring), donc ce décalage se lit
## exactement comme avant à l'écran (+X caméra = droite écran, etc.), sans
## jamais bouger un os individuellement.
func _process_arms(aiming: bool, reloading: bool, bob: Vector3, fov_scale: float) -> void:
	_arms.set_ads_amount(FPArmsMath.ads_blend_amount(_ads_t))
	# Pas de pose « sprint » (arme baissée) : dans ce jeu, avancer = état Sprint par défaut ;
	# l'arme doit rester prête (et la visée ne doit jamais être écrasée en mouvement).
	_arms.set_sprint_amount(0.0)

	var proc_pos := Vector3(_anim.sway_offset.x, _anim.sway_offset.y, 0.0) * _ads_t \
		+ bob * _ads_t + Vector3(0, _anim.recoil_offset.y * 0.02, _anim.recoil_offset.y * 0.03)
	var proc_rot := Basis.from_euler(Vector3(_anim.recoil_offset.y * 0.35, 0.0, -_anim.sway_offset.x * 1.5))
	_arms.align_to_camera(player.camera, Transform3D(proc_rot, proc_pos), fov_scale)

	var firing := player.input.fire_held if player.input else false
	var block_inspect := FPArmsMath.should_cancel_inspect(firing, aiming, reloading)
	if block_inspect:
		_arms.cancel_inspect()
	elif player.input and player.input.inspect_pressed:
		_arms.trigger_inspect()

## Facteur qui neutralise le FOV RÉEL de la caméra (`player.camera.fov`,
## Camera3D porté par PlayerCamera.gd — voir sa doc) pour TARGET_FOV_DEG (voir
## sa propre doc) : repli sur 1.0 (aucune compensation) si la caméra n'est
## pas encore prête, ce qui ne peut arriver qu'un seul frame avant `_ready`.
func _fov_scale() -> float:
	var cam: Camera3D = player.camera if player else null
	var actual_fov: float = cam.fov if cam else TARGET_FOV_DEG
	return tan(deg_to_rad(actual_fov) * 0.5) / tan(deg_to_rad(TARGET_FOV_DEG) * 0.5)

func _on_fired(cfg: WeaponConfig) -> void:
	if cfg == null:
		return
	_anim.kick_recoil(Vector3(0, deg_to_rad(cfg.recoil_vertical) * 6.0, 0))
	_anim.trigger_muzzle_flash()
	if _using_arms:
		# Pas de clip FP_Fire : il remplaçait la pose (visée comprise) par un tir « à la hanche »
		# et faisait sauter l'arme. Le recul procédural (`kick_recoil`, via `align_to_camera`)
		# s'ajoute à la pose courante, en visée comme à la hanche.
		_arms.cancel_inspect()

func _on_reload_started(cfg: WeaponConfig) -> void:
	if cfg:
		_anim.start_reload(cfg.reload_time)
		if _using_arms:
			_arms.trigger_reload(cfg.reload_time)
			_arms.cancel_inspect()

func _on_weapon_changed(_cfg: WeaponConfig) -> void:
	# `weapon_changed` est aussi émis à CHAQUE tir (Weapon._emit_local, avec ammo_changed) :
	# sortie d'arme seulement si l'arme change vraiment, sinon elle replongeait à chaque balle.
	var id := WeaponDatabase.id_of(weapon.cfg()) if weapon else Inventory.EMPTY
	if id == _current_id and _model:
		return
	_anim.start_equip()
	_refresh_model()
	if _using_arms:
		_arms.trigger_draw()

## (Re)charge le modèle 3D correspondant à l'arme courante, la place pour le
## cadrage FPS classique (`_place_weapon`), y rattache les deux gants
## (`_attach_gloves`) et pose les matériaux Cartoon.character(...) par slot
## (body/grip/metal/accent), avec l'accent teinté couleur d'équipe.
func _refresh_model() -> void:
	var id := WeaponDatabase.id_of(weapon.cfg()) if weapon else Inventory.EMPTY
	if id == _current_id and _model:
		return
	_current_id = id
	if _model:
		_model.queue_free()
		_model = null
	if id == Inventory.EMPTY:
		return
	var path := Weapon.model_path_for(id)
	if path.is_empty() or not ResourceLoader.exists(path):
		return
	var scene := load(path) as PackedScene
	if scene == null:
		return
	_model = scene.instantiate() as Node3D
	if _using_arms:
		# Bras FP : l'arme s'attache directement sous la BoneAttachment3D
		# "WeaponGrip" du rig (transform identité + contre-échelle, voir
		# FPArmsRig.attach_weapon) -- PAS enfant de CE nœud, contrairement au
		# chemin gants ci-dessous : aucun `add_child(_model)` ici, aucun lacet/
		# échelle/décalage PAR ARME (`_place_weapon`, `_attach_gloves`), ces
		# hacks n'existant que pour compenser l'ancien système de gants
		# flottants sans vraie main.
		_arms.attach_weapon(_model)
	else:
		add_child(_model)
		_place_weapon(id)
		_attach_gloves()
	_apply_cartoon_materials(_model)
	_muzzle = _model.find_child("Muzzle", true, false) as Node3D
	_spawn_muzzle_flash()

## Pose l'arme en enfant direct de ce nœud : lacet fixe (`_MODEL_YAW_DEG`,
## cadrage FPS classique — voir sa doc) + échelle/décalage PAR ARME
## (`weapon_scale_for`/`weapon_nudge_for`, FP-01) pour les gabarits extrêmes
## (sniper/lourde) ou simplement différents d'une arme à l'autre dans la même
## catégorie. La poignée (origine de l'arme) reste le pivot de cette rotation,
## donc aussi le point où le gant droit se rattache ensuite (`_attach_gloves`).
func _place_weapon(weapon_id: int) -> void:
	var scale := weapon_scale_for(weapon_id)
	var nudge := weapon_nudge_for(weapon_id)
	var yaw := Basis(Vector3.UP, deg_to_rad(_MODEL_YAW_DEG))
	_model.transform = Transform3D(yaw.scaled(Vector3.ONE * scale), nudge)

## Rattache les deux gants (chargés une fois, voir `_load_gloves`) à l'arme
## COURANTE : le droit près de son origine (`right_glove_anchor_for`, PAS pile
## dessus — voir sa doc), le gauche vers son empty "Foregrip" — pas pile
## dessus non plus, voir `_left_glove_anchor`. Aucune résolution géométrique
## basée sur une pose de squelette mesurée (l'ancien `solve_grip_transform`,
## supprimé avec fp_arms) : juste une petite correction de point d'ancrage,
## dérivée des repères déjà présents sur CETTE arme (origine, Foregrip,
## Muzzle).
func _attach_gloves() -> void:
	if _glove_r:
		_reparent(_glove_r, _model)
		_glove_r.rotation = right_glove_rotation_for(_current_id)
		_glove_r.position = right_glove_anchor_for(_current_id)
		_glove_r.scale = Vector3.ONE * right_glove_scale_for(_current_id)
	if _glove_l:
		_reparent(_glove_l, _model)
		_glove_l_rest = _left_glove_anchor()
		_glove_l.rotation = Vector3.ZERO
		_glove_l.position = _glove_l_rest
		_glove_l.scale = Vector3.ONE * left_glove_scale_for(_current_id)

## Point d'ancrage du gant DROIT — décalage depuis l'origine de l'arme (=
## repli sur transform IDENTITÉ pour une arme sans réglage ci-dessous). PAR
## ARME (id `WeaponDatabase.PATHS`, même principe que `weapon_scale_for`/
## `weapon_nudge_for`, FONCTION PURE testée dans
## tests/player/test_viewmodel_pose_math.gd).
##
## FP-02 (2e passage) : ces valeurs ont changé de sens — le gant est
## maintenant le poing Tripo Studio PEINT de tools/blender/fit_gloves_painted.py
## (voir sa doc), pivoté au CREUX DE LA PAUME (pas au sommet d'un gabarit bloc
## enveloppant) : `Mesh.get_aabb()` du gant droit à l'identité donne
## y ∈ [-0,021 ; 0,087] (repère LOCAL du gant — la quasi-totalité du poing
## est donc AU-DESSUS du pivot, seulement 2,1 cm en dessous). Repère par
## arme : `Mesh.get_aabb()` des 7 armes peintes A3D-20 donne un minimum Y à
## PILE 0.0 (origine = base du modèle) et l'empty "Foregrip" à
## y ∈ [0,044 ; 0,051] selon l'arme (voir le dump ci-dessous) — une hauteur
## plausible pour le bas du cadre/de la poignée. Ancre choisie ici :
## `Foregrip.y - 0,033` (0,033 = la moitié de l'étendue verticale du poing,
## (-0,021+0,087)/2, arrondi) pour que le MILIEU vertical du poing (pas son
## pivot) tombe à la hauteur du Foregrip — geste naturel : la main empoigne
## le milieu de la poignée, pas son bord.
##
## CONFIRMÉ PAR CAPTURE (relecture QA du 2026-09-25, correction de la LIMITE
## CONNUE d'une session précédente qui affirmait, à tort, un GPU headless
## indisponible — `godot --path . -s res://tools/fp_shots.gd -- --out=...`,
## SANS `--headless`, rend bien en fenêtré sur CETTE machine : D3D12 12_0,
## AMD Radeon RX 9060 XT, aucun repli `dummy` — voir scratchpad/fp02_fix_before/
## et fp02_fix_before.log) : ces 7 valeurs restent des estimations AABB
## (ci-dessus), mais un rendu réel confirme maintenant, pour les 7 armes, que
## le gant droit RESTE POSÉ sur le Grip (jamais flottant, jamais détaché —
## le critère d'acceptance « gants sur Grip/Foregrip » tient à l'image, pas
## seulement au chevauchement AABB du test).
##
## RÉSIDU CONSTATÉ PAR CE MÊME RENDU (signalé au lead, PAS corrigé ICI — 2e
## passage) : sur Pistolet/Magnum/Marqueur/Faucheur (id 0/1/3/6), la caméra
## voit le poing quasi dans l'axe de son propre pivot (« avant » du gant ≈ axe
## de visée) : on y lit surtout le talon du poignet — une masse arrondie
## lisse, sans doigts séparés — plutôt que le dos/le tranchant du poing (où
## les jointures/le pouce restent lisibles, cf. Rafale/Ravage/Fracas, id
## 2/4/5, nettement meilleurs sous le même éclairage). DEUX pistes testées
## ICI, rendues, puis ABANDONNÉES (aucune retenue dans le code — voir
## scratchpad/fp02_iter1/ et fp02_iter2/ pour les captures avant/après) :
##   1. Décalage `anchor.z` (Pistolet/Magnum, -0,025) : translation pure le
##      long de l'axe de l'arme, la même face du poing reste tournée vers la
##      caméra (une translation ne change pas QUELLE face on regarde) —
##      amélioration nulle à l'image.
##   2. Rotation locale du gant droit (+30° lacet, `_glove_r.rotation`,
##      testée sur toutes les armes) : améliore marginalement l'angle sur
##      certaines armes mais CASSE la lecture déjà bonne du Fracas (silhouette
##      de pouce disloquée, doigt qui semble se détacher de la main) — aucun
##      lacet unique ne convient aux 7 armes à la fois, contrairement au lacet
##      PARTAGÉ de l'arme (`_MODEL_YAW_DEG`) qui, lui, ne référence qu'un seul
##      canon toujours filmé sous le même angle.
##
## CORRIGÉ (FP-02, 3e passage, acceptance « pas de capsule » sur Pistolet/
## Magnum/Marqueur — Faucheur pas repris dans l'acceptance de cette passe,
## laissé tel quel) : exactement la piste 2 ci-dessus, mais PAR ARME plutôt
## que partagée — voir `_RIGHT_GLOVE_ROTATION_BY_ID` (même table, mesurée au
## rendu, que `_WEAPON_SCALE_BY_ID`), seules les 3 armes concernées reçoivent
## un lacet, Rafale/Ravage/Fracas/Faucheur restent à leur repli neutre — donc
## AUCUNE des deux régressions de la piste 2 (Fracas intact, la contrainte qui
## avait fait abandonner un lacet PARTAGÉ ne s'applique plus à un lacet PAR
## ARME).
const _RIGHT_GLOVE_ANCHOR_BY_ID := {
	0: Vector3(0.0, 0.011, 0.0),   # Pistolet — Foregrip.y=0,044.
	1: Vector3(0.0, 0.011, 0.0),   # Magnum — Foregrip.y=0,044.
	2: Vector3(0.0, 0.016, 0.0),   # Rafale — Foregrip.y=0,049.
	3: Vector3(0.0, 0.018, 0.0),   # Marqueur — Foregrip.y=0,051.
	4: Vector3(0.0, 0.018, 0.0),   # Ravage — Foregrip.y=0,051.
	5: Vector3(0.0, 0.018, 0.0),   # Fracas — Foregrip.y=0,051.
	6: Vector3(0.0, 0.018, 0.0),   # Faucheur — Foregrip.y=0,051.
}
const _DEFAULT_RIGHT_GLOVE_ANCHOR := Vector3.ZERO

## Point d'ancrage du gant droit pour l'arme `weapon_id` — repli neutre
## (transform identité, comportement d'avant cette tâche) si cette arme
## précise n'a pas encore son propre réglage. Fonction PURE (aucun accès à
## l'arbre de scène), même garantie que `weapon_scale_for`/`weapon_nudge_for`.
static func right_glove_anchor_for(weapon_id: int) -> Vector3:
	return _RIGHT_GLOVE_ANCHOR_BY_ID.get(weapon_id, _DEFAULT_RIGHT_GLOVE_ANCHOR)

## Rotation PROPRE du gant droit — FP-02 (3e passage), la 2e piste du RÉSIDU
## documenté juste au-dessus (voir `_RIGHT_GLOVE_ANCHOR_BY_ID`) : « sur
## Pistolet/Magnum/Marqueur (id 0/1/3), la caméra voit le poing quasi dans
## l'axe de son propre pivot... on y lit surtout le talon du poignet — une
## masse arrondie lisse, sans doigts séparés » (« capsule », acceptance
## FP-02). Le 2e passage avait essayé UN SEUL lacet partagé (+30°, toutes
## armes) : amélioration marginale sur certaines armes mais CASSE la lecture
## déjà bonne du Fracas (silhouette de pouce disloquée) — abandonné, voir la
## doc ci-dessus. Repris ICI comme une table PAR ARME (même principe que
## `_WEAPON_SCALE_BY_ID`, mesurée au rendu — `tools/fp_shots.gd` — pas
## improvisée) : SEULES les 3 armes touchées par le résidu reçoivent un lacet
## (25°, pivote le poing vers son flanc — le pouce/les jointures deviennent la
## silhouette lue plutôt que le talon du poignet, même logique que
## `_MODEL_YAW_DEG` révèle le flanc de l'arme) ; les 4 autres (Rafale/Ravage/
## Fracas/Faucheur, déjà lisibles) gardent leur repli neutre (transform
## identité) — AUCUNE régression possible sur elles, contrairement au lacet
## partagé abandonné.
const _RIGHT_GLOVE_ROTATION_BY_ID := {
	0: Vector3(0.0, deg_to_rad(38.0), 0.0),   # Pistolet
	1: Vector3(0.0, deg_to_rad(25.0), 0.0),   # Magnum
	3: Vector3(0.0, deg_to_rad(25.0), 0.0),   # Marqueur
}
const _DEFAULT_RIGHT_GLOVE_ROTATION := Vector3.ZERO

## Rotation locale du gant droit pour l'arme `weapon_id` — repli neutre
## (transform identité, comportement d'avant cette tâche) si cette arme
## précise n'a pas de résidu "capsule" connu. Fonction PURE, même garantie que
## `right_glove_anchor_for`.
static func right_glove_rotation_for(weapon_id: int) -> Vector3:
	return _RIGHT_GLOVE_ROTATION_BY_ID.get(weapon_id, _DEFAULT_RIGHT_GLOVE_ROTATION)

## Échelle PROPRE du gant droit (composée avec `weapon_scale_for` puisque le
## gant est un enfant du modèle d'arme, voir `_attach_gloves`).
##
## FP-02 (2e passage) : table RÉINITIALISÉE à 1.0 (repli neutre) partout —
## l'ancien gabarit `parts_glove_r` (tools/blender/make_gloves.py, blocs
## génériques bien plus gros qu'une vraie main, d'où le besoin de le réduire
## de 40 à 55 % par arme) n'existe plus. Le nouveau gant
## (tools/blender/fit_gloves_painted.py) est mis à l'échelle DIRECTEMENT sur
## une main adulte réelle (~19 cm poignet-doigt, voir sa doc) : à 1.0, sa
## taille est déjà celle visée, aucune réduction par arme n'est présumée
## nécessaire. Repère laissé en place (table + fonction PURE) pour un
## réglage futur si un rendu (`tools/fp_shots.gd` — voir sa confirmation
## GPU réelle sur `_RIGHT_GLOVE_ANCHOR_BY_ID`) révèle qu'une arme précise en
## a besoin.
const _RIGHT_GLOVE_SCALE_BY_ID := {}
const _DEFAULT_RIGHT_GLOVE_SCALE := 1.0

## Échelle du gant droit pour l'arme `weapon_id` — repli neutre (1.0, gant à
## l'échelle adulte réelle de fit_gloves_painted.py) si cette arme précise
## n'a pas de réglage particulier. Fonction PURE, même garantie que les
## autres réglages par arme de ce fichier.
static func right_glove_scale_for(weapon_id: int) -> float:
	return _RIGHT_GLOVE_SCALE_BY_ID.get(weapon_id, _DEFAULT_RIGHT_GLOVE_SCALE)

## Même repli neutre que `_RIGHT_GLOVE_SCALE_BY_ID`, pour le gant GAUCHE
## (FP-02 : table réinitialisée à 1.0, ancien gabarit `parts_glove_l`
## disparu — voir la doc ci-dessus).
const _LEFT_GLOVE_SCALE_BY_ID := {}
const _DEFAULT_LEFT_GLOVE_SCALE := 1.0

## Échelle du gant gauche pour l'arme `weapon_id` — même repli neutre que
## `right_glove_scale_for`.
static func left_glove_scale_for(weapon_id: int) -> float:
	return _LEFT_GLOVE_SCALE_BY_ID.get(weapon_id, _DEFAULT_LEFT_GLOVE_SCALE)

## L'empty "Foregrip" (tools/blender/make_weapons.py, `(muzzle_x, muzzle_y*
## 0.85, muzzle_z*fraction)`) a été placé comme cible de main de SQUELETTE,
## pas comme surface : sur les 7 armes, il tombe à l'INTÉRIEUR du bloc "body"
## (constaté par rendu — le gant gauche disparaissait, avalé par la
## géométrie de l'arme). Le pousser vers "Muzzle" d'une fraction FIXE de la
## distance restante (`_FOREGRIP_FORWARD_T`) le fait sortir de ce bloc quelle
## que soit la longueur de l'arme (canon court de pistolet ou long de fusil
## de précision), SANS lire la géométrie réelle de l'arme (empties seuls) —
## ce constat porte sur la géométrie de l'ARME, indépendant du gant, donc
## INCHANGÉ par FP-02.
##
## FP-02 (2e passage) : `_LEFT_GLOVE_DOWN_NUDGE` change de raison d'être. Le
## gant gauche est maintenant la main Tripo Studio PEINTE de
## tools/blender/fit_gloves_painted.py, pivotée AU CREUX DE LA PAUME — sa
## propre surface de paume est donc DÉJÀ quasiment au pivot
## (`Mesh.get_aabb()` à l'identité : y ∈ [-0,107 ; 0,019], la quasi-totalité
## du maillage PEND sous le pivot, seulement 1,9 cm dépasse au-dessus,
## exactement le creux voulu contre le dessous du garde-main). L'ancienne
## valeur (0,15 ; 0,10 ; 0) compensait un pivot d'ancien gabarit bloc
## profondément différent (make_gloves.py) ; réduite ici à une fraction
## (0,06 ; 0,03 ; 0), initialement le temps d'un rendu de confirmation.
##
## CONFIRMÉ PAR CAPTURE (relecture QA du 2026-09-25, voir la note GPU réelle
## sur `_RIGHT_GLOVE_ANCHOR_BY_ID`) : ce nudge, PARTAGÉ par les 7 armes (pas
## de table par arme ici), pose le gant gauche sur/sous le garde-main sans
## flotter pour les 7 — confirmé à l'image, pas seulement par l'AABB. Lecture
## constatée VARIABLE selon l'arme, comme pour le gant droit (voir le résidu
## documenté là-bas) : nette (jointures/pouce lisibles) sur Rafale/Ravage/
## Fracas, plus lisse/tubulaire sur Faucheur — même famille de résidu
## (caméra quasi dans l'axe du poignet plutôt que de son tranchant), PAS
## corrigée ici pour la même raison (un nudge global qui améliorerait
## Faucheur risquerait de dégrader les armes déjà bonnes sous le même
## réglage partagé ; une table par arme dédiée serait une extension
## d'architecture, pas une "correction", et devrait être mesurée avec le
## même sérieux que `_WEAPON_SCALE_BY_ID` plutôt qu'ajoutée à la hâte ici).
const _FOREGRIP_FORWARD_T := 0.4
const _LEFT_GLOVE_DOWN_NUDGE := Vector3(0.06, 0.03, 0.0)

func _left_glove_anchor() -> Vector3:
	var foregrip := _model.find_child("Foregrip", true, false) as Node3D
	var muzzle := _model.find_child("Muzzle", true, false) as Node3D
	var anchor: Vector3 = foregrip.position if foregrip else _DEFAULT_FOREGRIP_LOCAL
	if muzzle:
		anchor = anchor.lerp(muzzle.position, _FOREGRIP_FORWARD_T)
	return anchor + _LEFT_GLOVE_DOWN_NUDGE

func _reparent(node: Node3D, new_parent: Node3D) -> void:
	var old := node.get_parent()
	if old == new_parent:
		return
	if old:
		old.remove_child(node)
	new_parent.add_child(node)

## Slots de l'ancien corps bpy en blocs (tools/blender/make_weapons.py,
## `SLOT_NAMES`) — remplacés arme par arme par la version Tripo Studio peinte
## (tools/blender/fit_weapon_painted.py, A3D-20) : un modèle peint ne porte
## PLUS ces quatre slots mais un seul matériau nommé "<id>_painted" (ou
## "<id>_painted_N" au-delà du premier, voir `keep_painted_material`), détecté
## ci-dessous par `_PAINTED_MATERIAL_MARKER` AVANT la boucle par slot — la
## texture peinte conservée (jamais un aplat de palette) passe par
## `Cartoon.painted_texture_prop` (même matériau que les repères
## d'environnement peints, `scripts/dev/BeautyCorner.gd::_repaint_painted`),
## PAS `Cartoon.character()` : son contour plat à 2 px (jamais atténué par la
## distance, `Cartoon.painted_texture_prop`) coïncide déjà avec
## `_THIN_OUTLINE_PX` voulu ici (voir sa doc : le viewmodel est toujours à
## quelques centimètres de la caméra). Une arme dont AUCUNE surface ne
## correspond ni à un ancien slot ni à ce marqueur (cas dégénéré) garde son
## matériau importé tel quel, jamais un crash.
const _PAINTED_MATERIAL_MARKER := "_painted"

## FP-03 : marqueur du matériau SÉPARÉ de la manche (tools/blender/
## fit_gloves_painted.py::_add_sleeve_material) — voir la doc de
## `_apply_glove_materials` pour le routage complet.
const _SLEEVE_MATERIAL_MARKER := "_sleeve"
## Fraction (0..1, `Color.darkened`) appliquée à la couleur-clé de l'agent
## sélectionné pour obtenir le ton "tissu de veste sombre" de la manche —
## acceptance FP-03, PAS un repli neutre : Vif (#ee6a24, orange vif) devient
## ainsi un brun-brique sombre plausible plutôt qu'une teinte vive en plein
## champ de vision. 0,55 vise une luminosité proche de
## docs/style/tokens.json::characters.*.materials (fp_arms.dark_L = 0,30 —
## zone sombre déjà tolérée sur les avant-bras) sans dépendre d'une conversion
## OKLCH complète ici (le shader `world()`/`character_surface` fait déjà sa
## propre conversion de teinte, voir Cartoon.gd) : un simple facteur de
## luminosité linéaire suffit, jamais visé au pixel près comme un token de
## contraste WCAG.
const _SLEEVE_DARKEN_AMOUNT := 0.55

func _apply_cartoon_materials(model: Node3D) -> void:
	var palette := {
		"body": Cartoon.INK.lightened(0.35),
		"grip": Color(0.14, 0.13, 0.12),
		"metal": Color(0.55, 0.56, 0.6),
		"accent": Cartoon.ally_color(),
	}
	for mesh in _find_mesh_instances(model):
		if mesh.mesh == null:
			continue
		# Le AABB exporté par Blender pour la surface "body" (fusion de
		# plusieurs blocs disjoints du même matériau) est parfois un cube
		# unité par défaut au lieu des bornes réelles (bug de l'exporteur
		# glTF constaté sur les 7 armes, vertices corrects mais AABB fausse) :
		# sans marge de culling, Godot peut couper l'arme hors champ alors
		# qu'elle est bien face caméra. Même parade que InkPost.gd.
		mesh.extra_cull_margin = 2.0
		for i in mesh.mesh.get_surface_count():
			var mat: Material = mesh.mesh.surface_get_material(i)
			var name: String = mat.resource_name if mat else ""
			if name.contains(_PAINTED_MATERIAL_MARKER):
				# Arme viewmodel (Ravage, seule arme de WeaponDatabase.PATHS -- style BD
				# 2026-09-26, ToonStyle.gd) : plus de next_pass ici, voir _apply_glove_materials.
				var tex := Cartoon.texture_from_imported_material(mat)
				mesh.set_surface_override_material(i, ToonStyle.toon_material(tex))
				continue
			for slot in palette.keys():
				if name.ends_with("_%s" % slot):
					mesh.set_surface_override_material(i, Cartoon.character(palette[slot], _THIN_OUTLINE_PX))
					break

## Bascule l'arme+gants en mode "masque" pour tools/fp_shots.gd (§5.3,
## CHK-28/29/30) : matériau blanc plein non éclairé sur CHAQUE maillage
## (jamais les couleurs Cartoon réelles — la crosse de `_apply_cartoon_
## materials` ("grip") est du quasi-noir, indiscernable d'un fond noir) plus
## `_MASK_RENDER_LAYER` (voir sa doc) pour que la caméra de fp_shots puisse
## ensuite isoler l'arme+gants du reste du monde via `cull_mask`. Exclut le
## flash au canon (`_muzzle_mesh`, jamais visible pendant une capture statique
## hanche/ADS/sprint — pas de logique de restauration dédiée à lui écrire).
## `enabled = false` restaure exactement les matériaux/calques normaux du jeu
## (`_apply_cartoon_materials`/`_apply_glove_materials` relisent la couleur
## d'origine depuis le matériau importé, jamais depuis l'override qu'on vient
## de poser : idempotent, sûr à rappeler ici).
func set_mask_mode(enabled: bool) -> void:
	if _model == null:
		return
	if enabled and _mask_material == null:
		_mask_material = StandardMaterial3D.new()
		_mask_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mask_material.albedo_color = Color.WHITE
	for mesh in _find_mesh_instances(_model):
		if mesh == _muzzle_mesh or mesh.mesh == null:
			continue
		mesh.set_layer_mask_value(_MASK_RENDER_LAYER, enabled)
		if enabled:
			for i in mesh.mesh.get_surface_count():
				mesh.set_surface_override_material(i, _mask_material)
	if not enabled:
		_apply_cartoon_materials(_model)
		if _glove_r:
			_apply_glove_materials(_glove_r)
		if _glove_l:
			_apply_glove_materials(_glove_l)

func _find_mesh_instances(root: Node) -> Array:
	var out: Array = []
	if root is MeshInstance3D:
		out.append(root)
	for c in root.get_children():
		out.append_array(_find_mesh_instances(c))
	return out

## Position MONDE du canon (empty "Muzzle" du modèle 3D courant, voir
## `_refresh_model`) — utilisée par Weapon.gd (GF-06) pour dessiner le
## traceur (et y poser l'effet d'impact) depuis l'arme telle que la voit CE
## joueur en premier lieu, plutôt que depuis la caméra (voir
## Weapon._muzzle_position). Repli sur la position de ce nœud (déjà proche
## de la caméra, REST_POS) si le modèle n'est pas encore chargé (ex. tout
## premier tir avant que `_refresh_model` n'ait posé `_muzzle`).
func muzzle_global_position() -> Vector3:
	return _muzzle.global_position if _muzzle else global_position

func _spawn_muzzle_flash() -> void:
	if _muzzle == null:
		return
	_muzzle_mesh = MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(0.12, 0.12)
	_muzzle_mesh.mesh = qm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.92, 0.55)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_muzzle_mesh.material_override = mat
	_muzzle_mesh.visible = false
	_muzzle.add_child(_muzzle_mesh)


## Anim procédurale PURE (aucun accès à l'arbre de scène) : recul-ressort,
## sway souris, bob marche/sprint, dip de rechargement (+ son geste de gant
## gauche dédié), montée d'équipement, flash au canon, et les blends visée/
## sprint/slide. Testée directement dans tests/combat/test_weapon_fx.gd et
## tests/player/test_viewmodel_pose_math.gd via `ViewModel.AnimState.new()`.
class AnimState extends RefCounted:
	const RECOIL_STIFFNESS := 140.0
	const RECOIL_DAMPING := 16.0
	const SWAY_MAX := 0.05
	const SWAY_FOLLOW := 8.0
	const SWAY_SENS := 0.002
	const EQUIP_DUR := 0.28
	const MUZZLE_DUR := 0.05
	## Trajectoire locale (relative à sa position de repos sur le Foregrip)
	## du gant gauche pendant le rechargement : descend et recule légèrement
	## (vers la zone du chargeur — toujours plus bas et plus proche du corps
	## que le Foregrip, cf. les gabarits "chargeur" de tools/blender/
	## make_weapons.py) puis revient. Générique (pas par arme) : le geste n'a
	## pas besoin d'atteindre le chargeur au pixel près, juste de LIRE comme
	## une main qui va chercher un chargeur.
	const RELOAD_GLOVE_REACH := Vector3(0.0, -0.10, 0.12)

	var recoil_offset: Vector3 = Vector3.ZERO
	var _recoil_vel: Vector3 = Vector3.ZERO

	var sway_offset: Vector2 = Vector2.ZERO

	var bob_time: float = 0.0

	var reload_t: float = -1.0
	var reload_dur: float = 1.0

	var equip_t: float = -1.0

	var muzzle_t: float = -1.0

	## Ressort critique-amorti simplifié (Euler semi-implicite) : impulsion,
	## puis retour naturel vers 0. `tick_recoil` doit être appelé chaque frame.
	func kick_recoil(amount: Vector3) -> void:
		_recoil_vel += amount

	func tick_recoil(delta: float) -> void:
		var accel := -recoil_offset * RECOIL_STIFFNESS - _recoil_vel * RECOIL_DAMPING
		_recoil_vel += accel * delta
		recoil_offset += _recoil_vel * delta

	## Décalage de sway (mouse-lag) : suit l'opposé du mouvement souris puis
	## décroît vers 0 dès que la souris s'arrête. Clampé à SWAY_MAX.
	func tick_sway(mouse_delta: Vector2, delta: float) -> void:
		var target := -mouse_delta * SWAY_SENS
		target.x = clampf(target.x, -SWAY_MAX, SWAY_MAX)
		target.y = clampf(target.y, -SWAY_MAX, SWAY_MAX)
		sway_offset = sway_offset.lerp(target, clampf(SWAY_FOLLOW * delta, 0.0, 1.0))

	## Bob sinusoïdal proportionnel à la vitesse horizontale ; plat à l'arrêt.
	func tick_bob(speed: float, max_speed: float, delta: float) -> Vector3:
		var ratio := clampf(speed / maxf(max_speed, 0.01), 0.0, 1.4)
		if speed > 0.1:
			bob_time += delta * lerp(6.0, 11.0, clampf(ratio, 0.0, 1.0))
		else:
			bob_time = 0.0
			return Vector3.ZERO
		var y := sin(bob_time) * 0.015 * ratio
		var x := cos(bob_time * 0.5) * 0.01 * ratio
		return Vector3(x, y, 0.0)

	## Démarre le dip de rechargement (descend puis remonte sur `dur` s).
	func start_reload(dur: float) -> void:
		reload_dur = maxf(dur, 0.05)
		reload_t = 0.0

	func tick_reload(delta: float) -> Vector3:
		if reload_t < 0.0:
			return Vector3.ZERO
		reload_t += delta
		var p := clampf(reload_t / reload_dur, 0.0, 1.0)
		var dip := sin(p * PI) * 0.12
		if p >= 1.0:
			reload_t = -1.0
			return Vector3.ZERO
		return Vector3(0.0, -dip, 0.0)

	## Décalage LOCAL (relatif à sa position de repos sur le Foregrip) du gant
	## gauche pendant le rechargement : plonge vers la zone du chargeur puis
	## revient, synchronisé sur le MÊME minuteur que le dip d'ensemble
	## (`reload_t`/`reload_dur`, avancés par `tick_reload` — à appeler APRÈS
	## lui dans la même frame, comme dans `_process`). Pure (aucun accès à
	## l'arbre de scène), testable directement : voir
	## tests/player/test_viewmodel_pose_math.gd.
	func reload_glove_offset() -> Vector3:
		if reload_t < 0.0:
			return Vector3.ZERO
		var p := clampf(reload_t / reload_dur, 0.0, 1.0)
		return RELOAD_GLOVE_REACH * sin(p * PI)

	## Montée d'équipement : l'arme remonte depuis le bas sur EQUIP_DUR s.
	func start_equip() -> void:
		equip_t = 0.0

	func tick_equip(delta: float) -> Vector3:
		if equip_t < 0.0:
			return Vector3.ZERO
		equip_t += delta
		var p := clampf(equip_t / EQUIP_DUR, 0.0, 1.0)
		var eased := 1.0 - pow(1.0 - p, 3.0)
		if p >= 1.0:
			equip_t = -1.0
			return Vector3.ZERO
		return Vector3(0.0, -(1.0 - eased) * 0.25, (1.0 - eased) * 0.08)

	func trigger_muzzle_flash() -> void:
		muzzle_t = MUZZLE_DUR

	func is_muzzle_visible() -> bool:
		return muzzle_t > 0.0

	## Renvoie faux une fois le flash éteint (permet à l'appelant de masquer
	## le mesh au tick où l'extinction se produit).
	func tick_muzzle(delta: float) -> bool:
		if muzzle_t < 0.0:
			return false
		muzzle_t -= delta
		return muzzle_t > 0.0

	## Vers 0 (visée) ou 1 (hanche) — utilisé pour mélanger sway/bob et centrer
	## le modèle en ADS.
	func ads_blend(is_aiming: bool, current: float, delta: float, speed: float = 10.0) -> float:
		return move_toward(current, 0.0 if is_aiming else 1.0, speed * delta)

	func sprint_pose_blend(is_sprinting: bool, current: float, delta: float, speed: float = 6.0) -> float:
		return move_toward(current, 1.0 if is_sprinting else 0.0, speed * delta)

	func slide_tilt_blend(is_sliding: bool, current: float, delta: float, speed: float = 8.0) -> float:
		return move_toward(current, 1.0 if is_sliding else 0.0, speed * delta)
