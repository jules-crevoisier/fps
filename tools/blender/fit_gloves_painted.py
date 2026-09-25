## tools/blender/fit_gloves_painted.py
## FP-02 (2e passage) : remplace le corps bpy en blocs de fp_gloves.glb
## (tools/blender/make_gloves.py — gant "glove" cuir plat + manchette "cuff"
## recolorée au runtime) par les DEUX gants Tripo Studio PEINTS livrés pour
## ART-84 (politique « peinture conservée », même chaîne que
## tools/blender/ai_import_painted.py / tools/blender/fit_weapon_painted.py —
## JAMAIS tools/blender/ai_restyle.py, qui jette la texture IA) :
##   assets/incoming/tripo/studio/fp_glove_grip.glb    -> nœud exporté "GloveR"
##     (main DROITE, poing refermé sur une poignée verticale imaginaire, index
##     tendu vers l'avant — cf. capture scratchpad de sondage de cette tâche).
##   assets/incoming/tripo/studio/fp_glove_support.glb -> nœud exporté "GloveL"
##     (main GAUCHE ouverte, paume face caméra dans la pose scannée — destinée
##     à cradler un garde-main par en dessous, paume vers le haut une fois
##     orientée, cf. ci-dessous).
## 1er passage de cette tâche (voir l'historique scripts/player/ViewModel.gd) :
## seules les ANCRES avaient bougé, la géométrie restait celle de
## make_gloves.py (blocs beiges + manchette bleue plate, constaté par le lead
## sur fp_shots) — CE script est ce qui manquait : la géométrie peinte
## elle-même.
##
##   blender -b --factory-startup --python-exit-code 1 -P tools/blender/fit_gloves_painted.py
##   # (aucun argument : deux sources FIXES, contrairement à
##   # fit_weapon_painted.py qui traite 7 armes pilotées par manifeste)
##
## Repère de travail — IMPORTANT (même invariant que fit_weapon_painted.py,
## sondé ici aux mêmes sources : voir scratchpad de cette tâche, rendus
## orthographiques axe-par-axe avec gizmo RGB=XYZ) : ce script importe
## DIRECTEMENT les .glb Tripo Studio bruts, jamais en ré-authorant des
## coordonnées à la main comme make_gloves.py (qui, lui, écrit dans un repère
## "cible Godot" fictif puis applique SA PROPRE rotation +90°/X de correction
## avant d'exporter). Travailler DIRECTEMENT dans le repère NATIF Blender
## (Z-up) où le résultat FINAL doit avoir : "avant" (vers Grip/Foregrip,
## canon) = **+Y**, "haut" = **+Z**, "droite" = **+X** — EXACTEMENT le repère
## que `export_yup=True` convertit en la convention Godot déjà utilisée par
## ViewModel.gd (X=droite, Y=haut, -Z=avant) — suffit donc à reproduire cette
## convention sans aucune conversion supplémentaire, comme
## fit_weapon_painted.py (voir son en-tête pour le même raisonnement détaillé).
##
## Orientation SONDÉE PAR RENDU (jamais devinée) pour chaque source, dans son
## propre repère BRUT (tel qu'importé, avant toute rotation de ce script) :
##   fp_glove_grip.glb    : +X = avant (index tendu, "index le long"),
##                           +Z = haut (dos de main visible depuis le dessus —
##                           on regarde alors la main EXACTEMENT le long de
##                           l'axe vertical d'une poignée imaginaire, comme on
##                           regarderait son propre poing serré sur un manche
##                           vu de dessus), +Y = latéral (largeur pouce-
##                           auriculaire, axe de vue du rendu "de face" qui
##                           donne le profil de poing classique). Rotation
##                           nécessaire vers le repère cible ci-dessus :
##                           +90°/Z (seule rotation à un axe qui envoie +X (BRUT,
##                           avant) sur +Y (CIBLE, avant) et +Z sur +Z SANS
##                           inverser la chiralité — la seule solution propre,
##                           voir la dérivation dans le rapport de tâche).
##   fp_glove_support.glb : +Z = avant (poignet -> bout des doigts, axe le
##                           plus long de cette source, doigts tendus vers le
##                           haut dans la pose scannée), -Y = normale de la
##                           paume (paume face à la caméra en vue "de face"),
##                           +X = latéral. Rotation nécessaire : -90°/X (envoie
##                           +Z (BRUT, avant) sur +Y (CIBLE, avant) et -Y (BRUT,
##                           normale de paume) sur +Z (CIBLE, haut) — la paume
##                           finit donc face au +Z cible, "vers le haut" une
##                           fois la main posée sous un garde-main, exactement
##                           la pose demandée).
##
## Échelle — "main adulte (paume ~9 cm)" : chaque source Tripo Studio est
## normalisée sur SON PROPRE axe le plus long (bbox ~1.0 sur cet axe, même
## convention que les 7 armes peintes, voir ai_import_painted.py) ; cet axe le
## plus long représente, sur les DEUX sources, la même mesure anatomique
## (poignet -> bout des doigts). `ADULT_HAND_LENGTH_M` (0.19 m, longueur
## poignet-majeur adulte moyenne) est donc la SEULE constante de mise à
## l'échelle nécessaire, appliquée à chaque source via SON PROPRE axe le plus
## long mesuré (jamais un facteur supposé, `_scale_factor_for_reach` mesure
## la vraie étendue avant de diviser) : la largeur du poing résultante
## (fp_glove_grip, axe latéral brut, ~0.469 avant mise à l'échelle) tombe alors
## à ~8,9 cm — la validation "paume ~9 cm" des notes de tâche, jamais visée
## directement (viser la largeur au lieu de la longueur romprait la cohérence
## d'échelle entre les deux gants, qui doivent rester des mains de MÊME
## personnage).
##
## Pivot ("creux de la paume") : calculé, jamais deviné — voir `_palm_pivot` :
## centroïde de TOUS les sommets (le poing plein pèse plus lourd que l'index
## tendu, peu de sommets, donc le centroïde reste proche de la masse
## principale du poing plutôt que dérivé vers la pointe du doigt) puis
## translaté vers la surface de la paume le long de sa normale
## (`_PALM_NORMAL_BY_GLOVE`, dans le repère CIBLE déjà tourné) d'une fraction
## de la distance centroïde -> bord réel du maillage dans cette direction
## (`_PALM_INWARD_FRACTION`) — jamais la moitié de la bbox totale (fausserait
## la mesure sur un maillage asymétrique comme un poing).
##
## Matériau : CHAQUE source ne porte qu'UN SEUL matériau image (sondé :
## tripo_mat_*, Base Color <- Image Texture 2048², aucune carte
## normal/occlusion/metallic-roughness) — gardé tel quel (jamais remplacé par
## une couleur de palette), renommé "GloveR_painted"/"GloveL_painted"
## (`keep_painted_material`, même politique ET même nettoyage de graphe de
## nœuds que ai_import_painted.py::keep_painted_materials/
## fit_weapon_painted.py::keep_painted_material — dupliqué ici à dessein, voir
## leurs en-têtes : ce dossier ne fait jamais dépendre un script d'un autre)
## pour que `ViewModel.gd::_apply_glove_materials` le reconnaisse via
## `_PAINTED_MATERIAL_MARKER` ("_painted") et route vers
## `Cartoon.painted_texture_prop` (même traitement que l'arme peinte tenue à
## côté, contour plat 2 px cohérent) — PLUS AUCUN slot "_glove"/"_cuff" séparé
## (contrairement à make_gloves.py) : la manchette fait partie de la MÊME
## texture peinte que le reste du gant et n'est PAS reteintée au runtime
## (notes de tâche : « manchette laissée à sa couleur peinte » — la vue FPS du
## joueur local ne montre de toute façon jamais que SES PROPRES gants, jamais
## une teinte ennemie 300-355°/105-145° réservée par docs/STYLE_BIBLE.md).
##
## Nettoyage léger (fusion de sommets quasi confondus + doublons de face
## exacts, bruit de triangulation IA typique) + budget de tris + normales/
## masques toonkit : même séquence, mêmes constantes que
## fit_weapon_painted.py (dupliquées ici, voir son en-tête).
##
## Ce fichier importe `bpy`/`bmesh` dans un bloc try/except (même convention
## que ai_import_painted.py/fit_weapon_painted.py) : les calculs purs
## (`scale_factor_for_reach`, `rotation matrices via constantes`) restent
## lisibles sans Blender, même si ce dossier ne fait tourner aucun test
## pytest dédié à CE fichier (liste de fichiers de la tâche FP-02 : seul
## tests/player/test_fp_gloves.gd, gdUnit4 côté Godot, existe pour cette
## tâche).
##
## FP-02 (3e passage) : MANCHE (tissu de la veste) ajoutée par `_add_sleeve` --
## lead call après relecture QA du 2e passage (constat par capture, PAS par
## AABB seul : « poignet coupé fait face à la caméra, disque crème visible »
## sur les 7 armes, lisible en particulier au zoom sur le Fracas -- voir
## scratchpad/fp02_fix_before/_zoom_fp_fracas.png du rapport de tâche -- un
## disque clair cerné d'encre, calotte plate de fin de scan Tripo Studio dont
## la texture n'a jamais été correctement peinte, cf. §"Matériau" plus haut) ET
## « la main droite lit comme une capsule sur Pistolet/Magnum/Marqueur » (voir
## le résidu déjà documenté côté scripts/player/ViewModel.gd ::
## _RIGHT_GLOVE_ANCHOR_BY_ID, pas corrigé ici -- la manche ne change PAS l'angle
## de vue sur le poing, juste ce qui pend derrière lui).
##
## Pourquoi une géométrie AJOUTÉE plutôt qu'un perçage/rebouchage de la calotte
## d'origine : sondage de cette tâche (voir rapport) -- les DEUX sources Tripo
## Studio portent 1288 (grip) / 1325 (support) arêtes de BORD, dispersées sur
## la quasi-totalité de leur boîte englobante (bruit de triangulation IA
## typique -- même famille de défaut que `merge_by_distance`/
## `remove_duplicate_faces` corrigent déjà juste au-dessus, mais PAS un seul
## trou de poignet propre et isolé à détecter puis déboucher). `_add_sleeve`
## enveloppe donc la zone de la calotte (repérée par mesure, voir
## `_SLEEVE_DEFECT_CENTER`/`_SLEEVE_DEFECT_RADIUS`) d'un "collier" évasé
## SURDIMENSIONNÉ (`_SLEEVE_NEAR_RADIUS_M`/`_SLEEVE_FAR_RADIUS_M`, garde
## `_SLEEVE_MIN_OVERLAP` -- voir la doc "FP-03" plus bas pour le passage d'un
## facteur relatif à un rayon absolu) -- la calotte d'origine se retrouve
## mécaniquement À L'INTÉRIEUR du collier (jamais visible depuis l'extérieur,
## quelle que soit l'irrégularité exacte de la géométrie scannée à cet
## endroit), sans dépendre d'une topologie propre à découper. 1ère version de
## cette tâche (ABANDONNÉE, voir la doc de `_SLEEVE_DEFECT_CENTER`) : une
## coupe le long de l'axe Y brut du gant, ou le long de l'axe de manche
## partagé -- les DEUX ratent la calotte réelle de GloveL (rendu de
## diagnostic vert, rapport de tâche : vide visible entre la main et le
## collier).
##
## FP-03 : matériau de la manche RENDU SÉPARÉ, radius ABSOLU réduit -- verdict
## du lead sur fp_shots du 2026-09-25 12h40 (checkpoint reports/checkpoints/
## 2026-09-25_FP-02/) : « plus de moignon, mais la manche est un énorme cône
## orange/brun qui remplit le coin bas-droit -- elle reprend la texture du
## gant étirée ». Deux causes distinctes, deux corrections :
##   1. Matériau : la manche du 3e passage (ci-dessous, "AUCUN nouveau
##      matériau/slot" -- lecture ABANDONNÉE ici) partageait le matériau peint
##      de la main (index 0) via un UNIQUE texel échantillonné -- un aplat de
##      la couleur peau/cuir du gant à cet endroit précis de la texture, PAS
##      un aplat de tissu. Sur un tronc de cône entier (bien plus de surface
##      visible que la main elle-même), ce texel s'affichait comme une nappe
##      de couleur peau qui LISAIT comme "le gant étiré" -- exactement le
##      symptôme rapporté. Corrigé par `_add_sleeve_material` : un DEUXIÈME
##      slot matériau, `"<glove_name>_sleeve"`, SANS texture (Principled BSDF
##      Base Color plate, `_SLEEVE_FABRIC_COLOR`), jamais reteintée avec la
##      texture peinte -- reconnu côté ViewModel.gd::_apply_glove_materials
##      (`mat_name.ends_with("_sleeve")`) qui le reteinte À SON TOUR avec la
##      couleur-clé de l'agent sélectionné (AgentDatabase.selected().color),
##      assombrie (voir la doc de ViewModel.gd pour le facteur) -- « tissu de
##      veste sombre », jamais la texture du gant, jamais une teinte d'équipe
##      (ce choix ne contredit PAS la décision lead "manchette peinte,
##      pas de teinte d'équipe" ci-dessous : cette dernière portait sur
##      l'ANCIENNE manchette bpy en bloc de make_gloves.py, fusionnée dans le
##      MÊME maillage/matériau que la main -- la MANCHE de ce passage est une
##      géométrie ET un matériau ENTIÈREMENT séparés, un concept différent).
##      Verrouillé par tests/player/test_fp_gloves.gd ::
##      test_glove_r_and_glove_l_each_carry_exactly_one_painted_material
##      (mis à jour ce passage : toujours UN SEUL matériau peint par gant,
##      mais la manche n'est plus comptée dedans) et
##      test_glove_sleeve_material_is_a_flat_colour_without_the_glove_texture.
##   2. Taille : rayon du collier ABSOLU (`_SLEEVE_NEAR_RADIUS_M`/
##      `_SLEEVE_FAR_RADIUS_M`, 6 cm / 8 cm), jamais plus dérivé du rayon de
##      calotte mesuré par un facteur relatif (`_SLEEVE_OVERLAP`/`_SLEEVE_FLARE`
##      ABANDONNÉS -- sur GloveL, `_SLEEVE_DEFECT_RADIUS` 0,0490 x l'ancien
##      `_SLEEVE_OVERLAP` 2,2 donnait un rayon proche de 0,108 m, 10,8 cm --
##      l'"énorme cône" constaté). L'acceptance de cette tâche fixe la mesure
##      anatomique directement (« rayon 5-6 cm au poignet, 7-8 cm à la
##      sortie ») : `_SLEEVE_MIN_OVERLAP` reste une garde défensive (le rayon
##      absolu doit quand même dépasser le rayon de calotte mesuré d'au moins
##      15 %, sinon `_add_sleeve` lève une erreur), mais ne PILOTE plus la
##      taille finale.
##
## Historique (3e passage, pour mémoire -- lecture ABANDONNÉE par le verdict
## ci-dessus) : « Matériau de la manche : AUCUN nouveau matériau/slot -- la
## géométrie est ajoutée DANS LE MÊME bmesh que la main, AVANT l'écriture
## finale (`bm.to_mesh`), donc ses nouvelles faces héritent du même (unique)
## matériau peint que `keep_painted_material` a déjà posé sur l'objet entier
## (index 0)... Ses UV sont réglées sur un UNIQUE texel échantillonné sur un
## point RÉEL de la main (pas la calotte) : un ton "peint" plausible et
## continu, sans étirement de texture ni nouveau matériau. » -- cette dernière
## phrase était exactement le pari qui a échoué au rendu (voir ci-dessus).
##
## Direction (repère BLENDER natif de ce script -- voir l'en-tête de fichier :
## +Y = avant/canon, +Z = haut, +X = droite) : après `export_yup=True`, -Y ICI
## devient +Z Godot (vers la caméra/le corps du joueur -- anatomiquement
## correct, l'avant-bras revient bien vers le joueur), -Z ICI devient -Y Godot
## (bas), +X ICI reste +X Godot (droite). `_SLEEVE_AXIS_BLENDER` est à
## dominante BAS/DROITE plutôt que purement vers l'arrière (acceptance FP-02,
## 3e passage : « qui sort du bord bas/droit de l'écran ») -- un tube qui
## plongerait droit vers la caméra resterait dans l'axe de vue direct (le
## symptôme même de la calotte plate) et risquerait en plus un clip par le
## near-plane (bord dur, pas un vrai "sort du cadre"). MÊME direction/longueur
## partagée par les DEUX gants et les 7 armes -- la variation par arme vient
## déjà de `weapon_scale_for`/l'ancrage par arme côté ViewModel.gd, pas une
## raison d'ajouter une 2e table ici. Mesuré au rendu (tools/fp_shots.gd) avant
## d'être retenu, voir le rapport de tâche pour les captures de confirmation.
from __future__ import annotations

import math
import os
import sys

try:
	import bpy
	import bmesh
	from mathutils import Matrix, Vector
except ImportError:  # pragma: no cover - permet de lire ce fichier hors Blender
	bpy = None
	bmesh = None
	Matrix = None
	Vector = None

if bpy is not None:
	sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "lib"))
	import toonkit  # noqa: E402

# ---------------------------------------------------------------------------
# Constantes
# ---------------------------------------------------------------------------

MERGE_DIST_RATIO = 0.0005         # même mesure relative que ai_import_painted.py/fit_weapon_painted.py
BUDGET_TRIS = 4500                # marge au-dessus des sources brutes (4230/4095 tris) — plafond défensif
DECIMATE_MAX_ITERATIONS = 6
DECIMATE_PLANAR_ANGLE_LIMIT = 0.0872665  # ~5 degres (radians)
DECIMATE_STALL_RATIO = 0.99
TEXTURE_SIZE = 2048               # sources déjà 2048² (sondé) — jamais agrandi, voir resolved_texture_size
ALLOWED_TEXTURE_SIZES = (1024, 2048)

## Longueur poignet -> bout du majeur, adulte moyen (anthropométrie main
## humaine courante ~18-20 cm) — SEULE constante de mise à l'échelle, voir
## l'en-tête de ce fichier pour la dérivation "paume ~9 cm" à partir de
## celle-ci sur fp_glove_grip.
ADULT_HAND_LENGTH_M = 0.19

## Fraction de la distance centroïde -> bord réel du maillage (le long de la
## normale de paume) parcourue pour placer le pivot — 1.0 = pile sur le bord
## extérieur du maillage, 0.0 = au centroïde. La paume est une surface
## CONCAVE (creux) légèrement en retrait du bord extérieur du poing/de la
## main : 0.65 vise ce creux plutôt que la peau la plus externe (jointures) ou
## le centre géométrique (trop profond, dans la masse du maillage).
_PALM_INWARD_FRACTION = 0.65

## Repère CIBLE (après rotation, voir l'en-tête) : +Y = avant, +Z = haut, +X =
## droite. Direction de la normale de paume DANS ce repère cible, une par
## gant (sondée par rendu, voir l'en-tête) :
##   GloveR (grip)    : paume vers le bas (-Z cible) — un poing refermé sur une
##                       poignée verticale a sa paume tournée vers l'intérieur/
##                       le bas de la prise, cohérent avec le dos de main
##                       tourné vers le haut mesuré sur la source brute.
##   GloveL (support) : paume vers le haut (+Z cible) — notes de tâche :
##                       « paume vers le haut, pour la garde ».
_PALM_NORMAL_BY_GLOVE = {
	"GloveR": Vector((0.0, 0.0, -1.0)),
	"GloveL": Vector((0.0, 0.0, 1.0)),
}

## Rotation (matrice 3x3, appliquée aux sommets BRUTS autour de l'origine)
## depuis le repère de CHAQUE source vers le repère cible commun — voir la
## dérivation complète dans l'en-tête de ce fichier. Une seule rotation par
## gant (jamais composée), à un seul axe, choisie pour être la SEULE rotation
## PROPRE (déterminant +1, préserve la chiralité de la main scannée — la
## contrainte qui élimine toute ambiguïté de signe, voir l'en-tête).
def _rotation_by_glove() -> dict:
	return {
		"GloveR": Matrix.Rotation(math.radians(90.0), 3, 'Z'),
		"GloveL": Matrix.Rotation(math.radians(-90.0), 3, 'X'),
	}


## Manche (FP-02, 3e passage) -- voir l'en-tête de fichier pour la justification
## complète.
##
## Centre + rayon de la "calotte" à recouvrir, PAR GANT -- PAS une fraction de
## l'axe Y brut du gant (1ère version de cette tâche, ABANDONNÉE : sondage —
## rapport de tâche — la calotte défectueuse de GloveR est bien au Y minimal
## (normale quasi -Y pile), mais celle de GloveL ne l'est PAS : elle tombe à
## mi-hauteur de l'étendue Y, normale à dominante -X, PAS -Y -- un simple
## Y-minimal (ou même une coupe le long de l'axe de manche partagé, ESSAYÉ ET
## ABANDONNÉ AUSSI : rendu de diagnostic vert, voir rapport de tâche, laissait
## un vide visible entre la main et le collier sur GloveL) rate cette calotte).
## Mesuré ICI par détection de la plus grande grappe de faces quasi-coplanaires
## (angle entre faces adjacentes < 4°, >= 12 faces -- signature d'une calotte
## de fin de scan plutôt que la surface organique lissée du reste de la main) :
## GloveR — 1 grappe (30 faces, normale (-0.04,-0.99,-0.12), quasi -Y pile) ;
## GloveL — 2 grappes adjacentes fusionnées (24+16 faces, normales
## (-0.74,-0.66,-0.14) et (-0.66,-0.56,-0.51), dominante -X/-Y -- la même
## calotte scindée en deux par le seuil d'angle strict, pas deux défauts
## distincts). Valeurs FIGÉES (comme `_RIGHT_GLOVE_ANCHOR_BY_ID` côté
## ViewModel.gd) plutôt que redétectées à chaque build : seulement 2 gants,
## sources Tripo Studio FIXES (`SOURCE_BY_GLOVE`) -- à remesurer avec la même
## méthode si ces sources changent un jour (voir le script de sondage,
## conservé dans le rapport de tâche).
_SLEEVE_DEFECT_CENTER = {
	"GloveR": Vector((-0.0348, -0.0803, 0.0122)),
	"GloveL": Vector((-0.0426, -0.0322, -0.0503)),
}
_SLEEVE_DEFECT_RADIUS = {
	"GloveR": 0.0405,
	"GloveL": 0.0490,
}
## FP-03 : rayons ABSOLUS (mètres), fixés par l'acceptance de cette tâche
## (« rayon 5-6 cm au poignet, 7-8 cm à la sortie ») -- PLUS dérivés de
## `_SLEEVE_DEFECT_RADIUS` par un facteur relatif (voir la doc "FP-03" en tête
## de fichier pour l'historique de cet abandon : l'ancien `_SLEEVE_OVERLAP`
## 2,2x donnait un rayon proche de 10,8 cm sur GloveL, le "énorme cône"
## constaté par le lead). Choisis au bord HAUT de chaque fourchette (6 cm /
## 8 cm plutôt que 5 cm / 7 cm) pour garder la marge de recouvrement la plus
## large possible sur la calotte défectueuse la plus grande des deux (GloveL,
## `_SLEEVE_DEFECT_RADIUS` 0,0490) tout en restant strictement dans la
## fourchette demandée.
_SLEEVE_NEAR_RADIUS_M = 0.06
_SLEEVE_FAR_RADIUS_M = 0.08
## Garde défensive (PAS un paramètre de mise en forme) : `_SLEEVE_NEAR_RADIUS_M`
## doit rester au moins cette fraction au-dessus du rayon de calotte MESURÉ
## (`_SLEEVE_DEFECT_RADIUS`, par gant) -- sinon `_add_sleeve` lève une erreur
## plutôt que de produire un collier qui laisserait la calotte défectueuse
## dépasser. 1,15 = 15 % de marge minimale : à `_SLEEVE_NEAR_RADIUS_M` = 0,06,
## GloveR passe à 0,06 / 0,0405 = 1,48 et GloveL à 0,06 / 0,0490 = 1,22 --
## les deux au-dessus du plancher.
_SLEEVE_MIN_OVERLAP = 1.15
## Longueur totale du tronc de cône -- assez pour sortir du cadre à l'écran
## (voir la doc de direction ci-dessus/en-tête de fichier) sur les 7 armes
## (échelle viewmodel `weapon_scale_for` 0,95-1,70, l'ancrage du gant hérite de
## cette échelle en tant qu'enfant du modèle d'arme -- voir ViewModel.gd
## `_attach_gloves`) : mesuré au rendu (tools/fp_shots.gd), voir rapport de
## tâche.
_SLEEVE_LENGTH = 0.34
_SLEEVE_SEGMENTS = 14
## Voir l'en-tête de fichier ("Direction") pour la dérivation Blender->Godot de
## chaque composante. Normalisé dans `_add_sleeve`.
_SLEEVE_AXIS_BLENDER = Vector((0.45, -0.5, -0.75))

## FP-03 : couleur "peinte" cuite dans le .glb pour le matériau de manche --
## un repli plausible ("tissu de veste sombre") si le modèle est inspecté HORS
## de ViewModel (éditeur Godot, autre outil), jamais la teinte finale en jeu :
## ViewModel.gd::_apply_glove_materials reteint la manche à la couleur-clé de
## l'agent sélectionné (AgentDatabase.selected().color), assombrie, à chaque
## application (voir sa doc). Gris-brun charbonneux mat, proche de
## docs/style/tokens.json::characters.*.materials (fp_arms.dark_L = 0,30) --
## jamais une couleur vive qui lirait comme "peau"/"cuir" du gant (le défaut
## corrigé ce passage).
_SLEEVE_FABRIC_COLOR = (0.11, 0.10, 0.095)
## Tissu mat, jamais de brillance (docs/style/tokens.json::characters.*.
## materials.fabric.gloss = false).
_SLEEVE_ROUGHNESS = 0.9


def repo_root() -> str:
	return os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))


SOURCE_BY_GLOVE = {
	"GloveR": "assets/incoming/tripo/studio/fp_glove_grip.glb",
	"GloveL": "assets/incoming/tripo/studio/fp_glove_support.glb",
}
OUT_PATH = "assets/models/characters/fp_gloves.glb"


# ---------------------------------------------------------------------------
# Fonctions pures (aucune dépendance bpy)
# ---------------------------------------------------------------------------

def resolved_texture_size(original_size: int, requested_size: int) -> int:
	"""Même politique que ai_import_painted.py/fit_weapon_painted.py
	(dupliquée ici) : jamais un agrandissement au-delà de l'original, toujours
	l'une des deux tailles standard quand l'original le permet."""
	if requested_size not in ALLOWED_TEXTURE_SIZES:
		raise ValueError(f"fit_gloves_painted: texture_size {requested_size} hors {ALLOWED_TEXTURE_SIZES}")
	if original_size <= 0:
		raise ValueError(f"fit_gloves_painted: taille de texture d'origine invalide ({original_size})")
	cap = min(original_size, requested_size)
	candidates = [s for s in ALLOWED_TEXTURE_SIZES if s <= cap]
	if candidates:
		return max(candidates)
	return original_size


def scale_factor_for_reach(raw_reach_m: float, target_reach_m: float = ADULT_HAND_LENGTH_M) -> float:
	"""Facteur d'échelle UNIFORME qui porte l'étendue brute poignet->bout des
	doigts (`raw_reach_m`, mesurée sur l'axe le plus long de la source, voir
	`longest_extent`) à `target_reach_m` — même calcul que
	fit_weapon_painted.py::scale_factor_for_length, renommé ici (« reach »
	plutôt que « longueur d'arme »)."""
	if raw_reach_m <= 0:
		raise ValueError(f"fit_gloves_painted: étendue brute invalide ({raw_reach_m})")
	if target_reach_m <= 0:
		raise ValueError(f"fit_gloves_painted: étendue cible invalide ({target_reach_m})")
	return target_reach_m / raw_reach_m


# ---------------------------------------------------------------------------
# Fonctions dépendantes de bpy — jamais appelées hors de Blender.
# ---------------------------------------------------------------------------

def import_asset(path: str) -> list:
	"""Importe `path` et renvoie UNIQUEMENT les mesh NOUVELLEMENT ajoutés par
	cet import (diff avant/après) — les deux gants de ce script partagent la
	MÊME scène Blender du début à la fin (voir `main`, jamais de
	`toonkit.reset_scene()` entre les deux : GloveR déjà construit doit
	survivre pendant que GloveL s'importe), donc filtrer sur
	`scene.objects` sans diff ramasserait aussi le gant précédent déjà fini."""
	ext = os.path.splitext(path)[1].lower()
	if ext not in (".glb", ".gltf"):
		raise ValueError(f"fit_gloves_painted: extension non supportée: {ext!r} (attendu .glb/.gltf)")
	before = set(bpy.context.scene.objects)
	bpy.ops.import_scene.gltf(filepath=path)
	return [o for o in bpy.context.scene.objects if o not in before and o.type == 'MESH']


def merge_by_distance(obj, ratio: float = MERGE_DIST_RATIO) -> int:
	"""Même mesure relative que fit_weapon_painted.py::merge_by_distance
	(dupliquée ici). Renvoie le nombre de sommets retirés."""
	corners = [Vector(c) for c in obj.bound_box]
	mins = Vector((min(c.x for c in corners), min(c.y for c in corners), min(c.z for c in corners)))
	maxs = Vector((max(c.x for c in corners), max(c.y for c in corners), max(c.z for c in corners)))
	diag = max((maxs - mins).length, 1e-6)
	dist = max(1e-6, diag * ratio)
	me = obj.data
	before = len(me.vertices)
	bm = bmesh.new()
	bm.from_mesh(me)
	bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=dist)
	bm.to_mesh(me)
	bm.free()
	me.update()
	return before - len(me.vertices)


def remove_duplicate_faces(obj) -> int:
	"""Même défaut de génération IA que les scripts frères (dupliqué ici) :
	retire toute face qui partage EXACTEMENT le même ensemble de sommets
	qu'une face déjà vue."""
	me = obj.data
	bm = bmesh.new()
	bm.from_mesh(me)
	seen = {}
	dupes = []
	for f in bm.faces:
		key = frozenset(v.index for v in f.verts)
		if key in seen:
			dupes.append(f)
		else:
			seen[key] = f
	if dupes:
		bmesh.ops.delete(bm, geom=dupes, context='FACES')
	bm.to_mesh(me)
	bm.free()
	me.update()
	return len(dupes)


def keep_painted_material(obj, glove_name: str, texture_size: int) -> dict:
	"""Garde le matériau image importé — JAMAIS remplacé par une couleur de
	palette (même politique que ai_import_painted.py::keep_painted_materials/
	fit_weapon_painted.py::keep_painted_material, dupliquée ici) — et le
	RENOMME "<glove_name>_painted" pour que
	ViewModel.gd::_apply_glove_materials le reconnaisse via
	`_PAINTED_MATERIAL_MARKER`. Chaque source ne porte qu'UN SEUL matériau
	image (sondé) : pas de boucle de désambiguïsation "_N" comme le script
	frère armes (7 matériaux possibles par arme)."""
	me = obj.data
	report = []
	kept_images = []
	for mat in list(me.materials):
		if mat is None:
			continue
		image = _material_base_color_image(mat)
		if image is None:
			report.append({"name": mat.name, "has_texture": False})
			continue
		orig_w, orig_h = image.size
		new_w = resolved_texture_size(orig_w, texture_size)
		new_h = resolved_texture_size(orig_h, texture_size)
		if (new_w, new_h) != (orig_w, orig_h):
			image.scale(new_w, new_h)
		mat.name = f"{glove_name}_painted"
		mat.use_nodes = True
		nt = mat.node_tree
		for n in list(nt.nodes):
			if n.type not in ('OUTPUT_MATERIAL', 'BSDF_PRINCIPLED', 'TEX_IMAGE'):
				nt.nodes.remove(n)
		out = next((n for n in nt.nodes if n.type == 'OUTPUT_MATERIAL'), None)
		if out is None:
			out = nt.nodes.new("ShaderNodeOutputMaterial")
		bsdf = next((n for n in nt.nodes if n.type == 'BSDF_PRINCIPLED'), None)
		if bsdf is None:
			bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
		tex_nodes = [n for n in nt.nodes if n.type == 'TEX_IMAGE']
		for extra in tex_nodes[1:]:
			nt.nodes.remove(extra)
		tex = tex_nodes[0] if tex_nodes else nt.nodes.new("ShaderNodeTexImage")
		tex.image = image
		for link in list(nt.links):
			nt.links.remove(link)
		nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
		nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
		bsdf.inputs["Roughness"].default_value = 1.0
		kept_images.append(image.name)
		report.append({"name": mat.name, "has_texture": True, "image": image.name, "texture_size": [new_w, new_h]})
	return {"materials": report, "images_kept": kept_images}


def _material_base_color_image(mat):
	if mat is None or not mat.use_nodes or mat.node_tree is None:
		return None
	bsdf = mat.node_tree.nodes.get("Principled BSDF")
	if bsdf is None or "Base Color" not in bsdf.inputs:
		return None
	socket = bsdf.inputs["Base Color"]
	if not socket.is_linked:
		return None
	src = socket.links[0].from_node
	if src.type == 'TEX_IMAGE' and src.image is not None:
		return src.image
	return None


def longest_extent(obj) -> float:
	"""Étendue de bbox (locale, objet sans transform hors identité juste après
	import) sur l'axe le plus long — même mesure que fit_weapon_painted.py::
	longest_axis_index, mais renvoie directement la VALEUR (pas l'index), seule
	chose dont `scale_factor_for_reach` a besoin ici."""
	corners = [Vector(c) for c in obj.bound_box]
	xs = [c.x for c in corners]
	ys = [c.y for c in corners]
	zs = [c.z for c in corners]
	return max(max(xs) - min(xs), max(ys) - min(ys), max(zs) - min(zs))


def _apply_modifier(obj, modifier) -> None:
	name = modifier.name
	index = obj.modifiers.find(name)
	if index < 0:
		raise RuntimeError(f"fit_gloves_painted: modificateur \"{name}\" introuvable sur \"{obj.name}\"")
	if index != 0:
		with bpy.context.temp_override(object=obj, active_object=obj, selected_editable_objects=[obj]):
			move_result = bpy.ops.object.modifier_move_to_index(modifier=name, index=0)
		if 'FINISHED' not in move_result:
			raise RuntimeError(
				f"fit_gloves_painted: impossible de remonter \"{name}\" en tête de pile sur "
				f"\"{obj.name}\" ({move_result!r})")
	with bpy.context.temp_override(object=obj, active_object=obj, selected_editable_objects=[obj]):
		apply_result = bpy.ops.object.modifier_apply(modifier=name)
	if 'FINISHED' not in apply_result:
		raise RuntimeError(
			f"fit_gloves_painted: bpy.ops.object.modifier_apply a échoué ({apply_result!r}) pour "
			f"\"{name}\" sur \"{obj.name}\"")
	if obj.modifiers.find(name) >= 0:
		obj.modifiers.remove(modifier)


def _decimate_planar_pass(obj) -> None:
	mod = obj.modifiers.new("fit_gloves_painted_decimate_planar", type='DECIMATE')
	mod.decimate_type = 'DISSOLVE'
	mod.angle_limit = DECIMATE_PLANAR_ANGLE_LIMIT
	_apply_modifier(obj, mod)
	obj.data.update()


def decimate_to_budget(obj, budget: int, max_iterations: int = DECIMATE_MAX_ITERATIONS) -> int:
	"""Même algorithme itératif que fit_weapon_painted.py::decimate_to_budget
	(dupliqué ici). No-op si déjà sous le budget (cas attendu : sources à
	4095/4230 tris pour un budget de 4500)."""
	planar_retries = 0
	for _ in range(max_iterations):
		tris = toonkit.tri_count(obj)
		if tris <= budget:
			return tris
		ratio = max(0.02, min(0.95, budget / float(tris)))
		mod = obj.modifiers.new("fit_gloves_painted_decimate", type='DECIMATE')
		mod.decimate_type = 'COLLAPSE'
		mod.ratio = ratio
		_apply_modifier(obj, mod)
		obj.data.update()
		new_tris = toonkit.tri_count(obj)
		if new_tris > budget and new_tris >= tris * DECIMATE_STALL_RATIO and planar_retries < 3:
			planar_retries += 1
			_decimate_planar_pass(obj)
	return toonkit.tri_count(obj)


def _palm_pivot(bm: "bmesh.types.BMesh", palm_normal: Vector) -> Vector:
	"""Centroïde de tous les sommets de `bm` (déjà tourné+mis à l'échelle),
	translaté vers la surface réelle du maillage le long de `palm_normal` d'une
	fraction `_PALM_INWARD_FRACTION` de la distance centroïde -> bord — voir
	l'en-tête de ce fichier pour la justification ("creux de la paume", ni le
	centre géométrique ni le bord le plus externe)."""
	verts = bm.verts
	n = len(verts)
	if n == 0:
		raise RuntimeError("fit_gloves_painted: maillage vide, pivot impossible")
	centroid = Vector((0.0, 0.0, 0.0))
	for v in verts:
		centroid += v.co
	centroid /= n
	axis = palm_normal.normalized()
	centroid_proj = centroid.dot(axis)
	max_proj = max(v.co.dot(axis) for v in verts)
	reach = max_proj - centroid_proj
	return centroid + axis * (reach * _PALM_INWARD_FRACTION)


def _add_sleeve_material(obj, glove_name: str) -> int:
	"""FP-03 : crée le matériau SÉPARÉ de la manche (`"<glove_name>_sleeve"`,
	aplat -- JAMAIS la texture peinte du gant, voir la doc "FP-03" en tête de
	fichier pour le défaut que ce passage corrige) et l'ajoute comme NOUVEAU
	slot sur `obj.data.materials` (index 1, après le slot peint index 0 posé
	par `keep_painted_material`, appelé juste avant dans `build_glove`).
	Renvoie l'index du nouveau slot, à assigner aux faces de la manche par
	`_add_sleeve`. Reconnu côté ViewModel.gd::_apply_glove_materials via
	`mat_name.ends_with("_sleeve")`, qui reteint la couleur ci-dessous avec la
	couleur-clé de l'agent sélectionné, assombrie -- voir sa doc."""
	mat = bpy.data.materials.new(f"{glove_name}_sleeve")
	mat.use_nodes = True
	nt = mat.node_tree
	for n in list(nt.nodes):
		if n.type not in ('OUTPUT_MATERIAL', 'BSDF_PRINCIPLED'):
			nt.nodes.remove(n)
	out = next((n for n in nt.nodes if n.type == 'OUTPUT_MATERIAL'), None)
	if out is None:
		out = nt.nodes.new("ShaderNodeOutputMaterial")
	bsdf = next((n for n in nt.nodes if n.type == 'BSDF_PRINCIPLED'), None)
	if bsdf is None:
		bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
	for link in list(nt.links):
		nt.links.remove(link)
	nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
	bsdf.inputs["Base Color"].default_value = (*_SLEEVE_FABRIC_COLOR, 1.0)
	bsdf.inputs["Roughness"].default_value = _SLEEVE_ROUGHNESS
	obj.data.materials.append(mat)
	return len(obj.data.materials) - 1


def _add_sleeve(bm: "bmesh.types.BMesh", glove_name: str, sleeve_material_index: int) -> None:
	"""Ajoute la manche (tronc de cône évasé) au poignet de `bm` -- voir
	l'en-tête de fichier ("MANCHE"/"FP-03") pour la justification complète.
	Doit être appelée APRÈS rotation+échelle+centrage sur le pivot
	(`_SLEEVE_DEFECT_CENTER` suppose le repère FINAL du gant), et AVANT
	`bm.to_mesh` (la nouvelle géométrie doit atterrir dans le MÊME maillage que
	la main, mais sous `sleeve_material_index` -- un slot SÉPARÉ du matériau
	peint, voir `_add_sleeve_material`, appelée par `build_glove` AVANT la
	construction de ce `bm`)."""
	axis = _SLEEVE_AXIS_BLENDER.normalized()
	center = _SLEEVE_DEFECT_CENTER[glove_name]
	defect_radius = _SLEEVE_DEFECT_RADIUS[glove_name]
	# Garde défensive -- voir la doc de `_SLEEVE_MIN_OVERLAP` : jamais un
	# collier plus petit que la calotte défectueuse qu'il doit envelopper,
	# même si `_SLEEVE_NEAR_RADIUS_M`/`_SLEEVE_FAR_RADIUS_M` venaient à
	# changer sans reprendre cette vérification.
	if _SLEEVE_NEAR_RADIUS_M < defect_radius * _SLEEVE_MIN_OVERLAP:
		raise RuntimeError(
			f"fit_gloves_painted: {glove_name} -- rayon proche de manche "
			f"({_SLEEVE_NEAR_RADIUS_M:.4f} m) sous le plancher de recouvrement "
			f"({defect_radius * _SLEEVE_MIN_OVERLAP:.4f} m) pour la calotte "
			f"défectueuse mesurée (rayon {defect_radius:.4f} m)")
	cone_center = center + axis * (_SLEEVE_LENGTH / 2.0)

	ret = bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=_SLEEVE_SEGMENTS,
		radius1=_SLEEVE_NEAR_RADIUS_M, radius2=_SLEEVE_FAR_RADIUS_M, depth=_SLEEVE_LENGTH)
	new_verts = ret["verts"]
	# `create_cone` construit debout sur SON axe Z, centré à l'origine (sondé
	# avant écriture, voir rapport de tâche) -- on le tourne (rotation du plus
	# court arc, +Z -> `axis`) puis le translate à sa position finale.
	up = Vector((0.0, 0.0, 1.0))
	rot_matrix = up.rotation_difference(axis).to_matrix()
	bmesh.ops.rotate(bm, cent=(0.0, 0.0, 0.0), matrix=rot_matrix, verts=new_verts)
	bmesh.ops.translate(bm, vec=cone_center, verts=new_verts)

	new_vert_set = set(new_verts)
	new_faces = [f for f in bm.faces if all(v in new_vert_set for v in f.verts)]
	if not new_faces:
		raise RuntimeError(f"fit_gloves_painted: {glove_name} -- aucune face de manche créée")
	# Matériau plat (`_add_sleeve_material`) : pas de texture à échantillonner,
	# contrairement au 3e passage -- l'UV n'a plus besoin de viser un texel
	# précis de la main, juste rester une valeur valide (0,0) pour tout
	# exporteur/lecteur qui suppose un calque UV complet sur le maillage.
	uv_layer = bm.loops.layers.uv.active
	zero_uv = Vector((0.0, 0.0))
	for f in new_faces:
		f.material_index = sleeve_material_index
		if uv_layer is not None:
			for loop in f.loops:
				loop[uv_layer].uv = zero_uv


def build_glove(glove_name: str, root: str) -> object:
	"""Pipeline complet (import -> nettoyage -> matériau peint -> rotation ->
	échelle -> pivot -> budget -> normales/masques) pour UN gant. Renvoie
	l'objet bpy final, nommé `glove_name` ("GloveR"/"GloveL"), prêt à
	sélectionner pour l'export."""
	source_path = os.path.join(root, SOURCE_BY_GLOVE[glove_name])
	mesh_objs = import_asset(source_path)
	if not mesh_objs:
		raise RuntimeError(f"fit_gloves_painted: aucun mesh dans la source {source_path}")
	obj = toonkit.join(mesh_objs) if len(mesh_objs) > 1 else mesh_objs[0]

	merge_by_distance(obj)
	remove_duplicate_faces(obj)
	material_report = keep_painted_material(obj, glove_name, TEXTURE_SIZE)
	sleeve_material_index = _add_sleeve_material(obj, glove_name)

	raw_reach = longest_extent(obj)
	scale = scale_factor_for_reach(raw_reach)
	rotation = _rotation_by_glove()[glove_name]

	bm = bmesh.new()
	bm.from_mesh(obj.data)
	bmesh.ops.rotate(bm, cent=(0, 0, 0), matrix=rotation, verts=bm.verts)
	bmesh.ops.scale(bm, vec=Vector((scale, scale, scale)), verts=bm.verts)
	pivot = _palm_pivot(bm, _PALM_NORMAL_BY_GLOVE[glove_name])
	bmesh.ops.translate(bm, vec=-pivot, verts=bm.verts)
	_add_sleeve(bm, glove_name, sleeve_material_index)
	bm.to_mesh(obj.data)
	bm.free()
	obj.data.update()

	decimate_to_budget(obj, BUDGET_TRIS)

	toonkit.weighted_normals(obj)
	toonkit.smooth_normal_attrs(obj)
	toonkit.bake_vertex_ao(obj)
	toonkit.curvature_edge_mask(obj)

	if obj.modifiers:
		raise RuntimeError(
			f"fit_gloves_painted: {len(obj.modifiers)} modificateur(s) encore empilé(s) sur "
			f"\"{obj.name}\" avant l'export ({[m.name for m in obj.modifiers]})")

	obj.name = glove_name
	obj.data.name = glove_name

	final_tris = toonkit.tri_count(obj)
	sleeve_material_name = obj.data.materials[sleeve_material_index].name
	print(f"GLOVE_PAINTED_OK {glove_name} tris={final_tris} scale={scale:.4f} pivot={tuple(pivot)} "
		f"size={tuple(obj.dimensions)} materials={material_report['materials']} "
		f"sleeve_material={sleeve_material_name!r}")
	return obj


def main() -> None:
	root = repo_root()
	toonkit.reset_scene()
	gloves_root = bpy.data.objects.new("Gloves", None)
	gloves_root.empty_display_type = 'PLAIN_AXES'
	bpy.context.scene.collection.objects.link(gloves_root)

	## PAS de `toonkit.reset_scene()` par gant ici : les deux gants partagent
	## la même scène du début à la fin (`gloves_root` + le gant précédent déjà
	## construit doivent survivre pendant que le suivant s'importe) — voir la
	## doc de `import_asset`, qui isole chaque import par diff avant/après.
	built = []
	for glove_name in ("GloveR", "GloveL"):
		obj = build_glove(glove_name, root)
		obj.parent = gloves_root
		built.append(obj)

	out_path = os.path.join(root, OUT_PATH)
	os.makedirs(os.path.dirname(out_path), exist_ok=True)
	bpy.ops.object.select_all(action='DESELECT')
	gloves_root.select_set(True)
	for o in built:
		o.select_set(True)
	bpy.ops.export_scene.gltf(
		filepath=out_path,
		export_format='GLB',
		use_selection=True,
		export_apply=True,
		export_yup=True,
		export_materials='EXPORT',
		export_vertex_color='ACTIVE',
		export_all_vertex_colors=True,
		export_attributes=True,
		export_cameras=False,
		export_lights=False,
		export_animations=False,
	)
	print(f"GLOVES_PAINTED_OK -> {out_path}")


if __name__ == "__main__":
	main()
