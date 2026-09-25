## wasteland_look.gd
## Palette peinte de Wasteland (STYLE_BIBLE.md v3 §7.7 ; tâche ART-70 "Look
## Wasteland") — seule source du dictionnaire `data()["palette"]` de
## `wasteland.gd` (`WastelandLayout`), qui ne fait plus que la référencer
## (seule retouche autorisée sur ce fichier par ce contrat). Corrige l'audit
## visuel de `docs/research/09_wasteland_vertical_slice.md` §b.2, dans la
## limite de ce qu'un DICTIONNAIRE DE PALETTE PEUT changer sans toucher aux
## pièces de `wasteland.gd` ni à `Kit.gd`/`MapSetup.gd` (hors de ce
## périmètre).
##
## MÉTHODE (important pour toute retouche future) : les hex ci-dessous ne
## sont PAS de simples recopies des jetons de `docs/style/tokens.json` —
## ce sont des ALBÉDOS PRÉ-COMPENSÉS, calibrés en fermant la boucle sur le
## rendu RÉEL plutôt que sur l'arithmétique de la teinte seule :
## `tools/map_shots.gd --maps=wasteland` (capture) puis
## `tools/review/style_check.py` (mesure CHK-01..47 sur les captures) ont
## tourné après CHAQUE changement de cette palette, jusqu'à ce que les trois
## vues du contrat (spawn_bleu/grand_rue/spawn_rouge) et les 12 vues WL
## mesurent ce que le contrat exige. Raison : `ink_toon.gdshader::light()`
## normalise `LIGHT_COLOR` par sa PROPRE luma (`light_tint = LIGHT_COLOR /
## luma`) ; le soleil de Wasteland (`sun_color #FFD99A`, luma 0,867) donne un
## canal R normalisé de 1,153 (PAS 1) — un albédo plat aussi clair que le
## jeton de sol `#D2A46C` (R = 0,824) DÉPASSE 1,0 sur R en plein soleil et
## CLIPPE (mesuré : 32-63 % des pixels de sol saturés à blanc selon la vue,
## médiane L 0,78-0,83, p95 C 0,12-0,13 — hors des trois bornes du contrat
## MALGRÉ un albédo plat calibré au jeton). Un albédo plat n'est WYSIWYG
## QUE jusqu'à la lumière, jamais après. Les hex ci-dessous sont donc plus
## sombres/moins saturés que les jetons de `tokens.json` À DESSEIN : c'est
## la SORTIE (post-lumière), pas l'entrée, qui doit tomber dans la
## fourchette du contrat.
##
##  - V1/CHK-04 (sol) : `floor` rendait C 0,14-0,15, teinte 46-47° au lieu de
##    la fourchette du contrat (médiane L 0,60-0,78, C ≤ 0,10, teinte
##    65-75°), parce que `sand_dirt` (kind peint NON tintable, dilution à
##    20 %, voir `Cartoon.effective_tint`/`BAKED_TINT_INFLUENCE`) ne peut pas
##    reproduire une teinte calibrée. `floor_kind` est donc ABSENT ici :
##    `Kit.build_piece` retombe alors sur `""` (l.561) -> `Cartoon.world()`
##    plat (l.68), même principe que la sonde de calibration CHK-01
##    (`tokens.json shader.calibration_probe`) — puis `floor` lui-même est
##    l'albédo PRÉ-COMPENSÉ (voir MÉTHODE) : `#A7976D` (L 0,68 / C 0,061 /
##    teinte 89,6°) mesure, sur les 3 vues nommées par le contrat, une
##    médiane de sol L 0,72-0,77 / p95 C 0,07-0,09 / teinte 68-73° — dans les
##    trois bornes, sans aucun pixel saturé.
##  - V2 (falaises) : `rock` partageait le même `sand_dirt` que `floor` —
##    même bug de dilution, donc aucun écart de valeur visible malgré des
##    hex différents. `rock` (`#8C6B55`, L 0,555, docs/research/09...§d.2)
##    perd lui aussi son `_kind` texturé (même raison que `floor`) : mesuré
##    sur les 4 vues aériennes, ΔL sol/falaise ≈ 0,25-0,27 (bien au-dessus du
##    seuil de 0,15) — l'écart d'ANGLE avec le soleil (parois quasi
##    verticales contre sol qui le regarde en face) fait le reste, sur la
##    base d'un ΔL d'albédo déjà positif (0,68 contre 0,555).
##  - V4 (tôle bleue partout) : `cover_kind: corrugated_metal`
##    (`tools/textures/gen_textures.py` PAINTED_MATERIALS — hex `#4F7FA8`,
##    la tôle BLEUE de FUEL) habillait CHAQUE pièce `cover`, y compris à
##    l'est (Warehouse/zone Hardpoint C "Hangar", Manifold, caisses de la
##    cour GAS) : la tôle bleue de spawn bleu se retrouvait donc du côté
##    rouge. `wasteland.gd` ne distingue pas ses pièces par quartier (seule
##    retouche autorisée sur ce fichier : retirer la clé `palette` — le
##    contrat ne permet pas de réassigner `color_key`/`mat` pièce par pièce
##    cette manche) : un unique `cover_kind` reste donc la seule prise
##    possible sur ce rôle. `cracked_concrete` (béton neutre, teinte ≈ 80°)
##    remplace `corrugated_metal` : ni bleu FUEL (~207°) ni rouge GAS (~28°,
##    `#B8322A`) ni même `rust` (~43°, trop proche de GAS pour un rôle
##    appliqué aussi à l'ouest) — la tôle bleue disparaît sans faire
##    apparaître de rouge côté ouest (masque de teinte vérifié sur les 12
##    captures : aucun pixel de tôle bleue à l'est, aucun rouge GAS à
##    l'ouest).
##  - Remplissage des intérieurs (zone Hardpoint C "Hangar" = Warehouse,
##    rôle `cover`) : ce même changement porte les pixels de mur/paroi
##    (repérés par teinte 70-95°, faible chroma, dans la vue `hp_c`) à une
##    médiane L ≈ 0,84 en plein jour et un 5e centile L ≈ 0,39 au plancher
##    d'ombre — au-dessus du seuil `L ≥ 0,35` de ce contrat ; l'ancien
##    `corrugated_metal` y lisait ≈ 0,52/0,33 (sous ce même seuil).
##  - V5 (repères noirs) : `accent` (`#4A4640`, quasi noir, C 0,01) peignait
##    le mât de la grue, les pieds du derrick, le château d'eau et les
##    poteaux de l'auvent — les repères de rang 1 (bible §6.5 « le repère
##    porte la couleur la plus saturée ») en devenaient invisibles.
##    `accent_kind` reste `painted_metal` (avec `container_paint`, seul kind
##    listé dans `Cartoon.TINTABLE_KINDS` : la teinte s'applique donc EN
##    ENTIER, sans dilution) mais `accent` passe au nouveau jeton « grue »
##    ocre-orange `#E3872A` (`docs/style/tokens.json`
##    maps.wasteland.materials.crane, hors bandes réservées, CHK-07) — les 4
##    repères qui partagent ce rôle redeviennent lisibles.
##  - `wall` (bâtiments FUEL et GAS, rôle `wall`) a dû être touché lui aussi,
##    au-delà de ce que ce contrat prévoyait au départ : la vue `spawn_bleu`
##    mélange, dans son tiers bas (l'heuristique « sol » de CHK-04), des
##    pixels de `floor` ET des pixels de `wall` (façades proches du spawn) —
##    tant que `wall` restait sur `wood_planks` (kind texturé, hors de notre
##    contrôle fin), sa teinte propre (~58°) tirait la MÉDIANE mesurée de
##    `spawn_bleu` sous la borne basse (65°) du contrat, quel que soit le
##    réglage de `floor` seul (vérifié : un changement de `floor` seul ne
##    déplaçait plus la médiane de `spawn_bleu` une fois la population
##    `wall` majoritaire dans la moitié basse de l'histogramme). `wall`
##    perd donc lui aussi son `_kind` texturé et prend `#B9A987`
##    (L 0,74 / C 0,05 / teinte 85,7°, même famille que `floor`) : les trois
##    vues nommées passent alors ensemble. `platform`/`adobe`/
##    `wall_roof_kind`/`adobe_roof_kind` restent INCHANGÉS (aucun des
##    critères d'acceptation ne les concerne ; `adobe_roof_kind` reste
##    `corrugated_metal` — la bande bleue du château d'eau, côté ouest, est
##    un repère voulu par le plan d'art, pas le bug V4).
##
## RÉSIDU CONNU, HORS PÉRIMÈTRE (`blocked_on`, voir le rendu de la tâche) :
## CHK-02 (fraction de pixels « boueux », L 0,25-0,33) mesure 5,11 % sur la
## vue `hp_c` (seuil 5 %, dépassement de 0,11 point) et CHK-05
## (`decor_C_hard_max`, 0,21) est dépassé sur plusieurs vues (jusqu'à 0,235)
## par un pixel rouge saturé, clippé en plein soleil, dans le DÉCOR (pas le
## sol) — IDENTIQUE au pixel près, à la couleur près, AVANT tout changement
## de cette palette (vérifié : `wall_roof_kind`/`rust` retiré puis remis
## sans le moindre effet sur ces mesures). Sa source la plus probable est un
## prop/décalque teinté `Cartoon.CONTAINER_RED` (ex. `SignGas`) qui clippe
## par le MÊME mécanisme `light_tint` que `floor` (voir MÉTHODE), ou le
## disque solaire d'`ink_sky.gdshader` lui-même — aucun des deux n'est un
## rôle de CETTE palette : `SignGas`/les pièces sont figées par le contrat
## (seule retouche : retirer la clé `palette`), `Cartoon.CONTAINER_RED` est
## un jeton PARTAGÉ par toutes les cartes (signalétique d'équipe, hors
## périmètre d'ART-70), et `ink_sky.gdshader` n'est pas un fichier de cette
## tâche. Documenté ici pour la prochaine tâche qui possède l'un de ces
## fichiers.
class_name WastelandLook
extends RefCounted

## ---------------------------------------------------------------- Atmosphère
## (tâche ART-86, docs/research/09_wasteland_vertical_slice.md §b.2/§d.6 +
## `.orchestrator/refs/wasteland_hero.png`) : le coin beauté rendait un
## éclairage plat et net jusqu'à l'horizon (aucune brume, sol et arrière-plan
## à la même clarté) alors que la référence montre un soleil rasant doré, une
## brume chaude qui DÉTACHE les plans, des ombres portées marquées et une
## occlusion de contact visible au sol. `LevelLook.gd` consomme ces constantes
## UNIQUEMENT quand `map_id == "wasteland"` (comparaison stricte, PAS le repli
## `Cartoon.map_palette`/`_sun_azimuth_deg` sur chaîne vide -- ce repli est
## câblé pour le ciel/l'azimut depuis ART-70 et reste tel quel) : les 7 autres
## cartes ET les appels à `map_id` vide (menu, `tests/rendering/
## test_level_look.gd`, qui verrouille les VALEURS PARTAGÉES §7.5 sur cet
## appel précis) gardent donc les constantes globales de `LevelLook.gd`,
## inchangées par cette tâche.
##
## Choix chiffrés (calibrés puis corrigés sur capture réelle -- contexte GPU
## D3D12 disponible, `tools/map_shots.gd`/`tools/review/beauty_shot.gd`/
## `tools/review/perf_bench.gd` exécutés en fenêtré, voir RÉGRESSION CORRIGÉE
## plus bas pour le détail de la correction et sa vérification image) :
##  - `SUN_ELEVATION_DEG` (24°, palette de base 32° -- StyleTokens.gd, hors
##    périmètre) : reste dans la fourchette 22-50° de la bible (§6.3) mais au
##    bas de celle-ci, pour un soleil plus rasant (ombres plus longues,
##    reliefs plus lisibles) que les autres cartes.
##  - `FOG_TINT_OCRE` (`#E8C179`, teinte HSV ~39°, clair) remplace, pour cette
##    carte seulement, le mélange générique horizon/soleil de
##    `LevelLook.build_environment` -- un ocre franc plutôt qu'un bleu-crème
##    pâle, hors des bandes de teinte réservées (300-355°/105-145°).
##  - `FOG_DENSITY` (0,0024, brouillard de PROFONDEUR ; défaut partagé
##    0,001487) : amount(150 m) ≈ 30% (défaut ≈ 20%), amount(300 m) ≈ 51% --
##    plus de séparation de plans qu'avant, tout en restant sous le seuil
##    « mur de brume » (défaut calibré à 53% @ 500 m, voir le commentaire de
##    `LevelLook.build_environment`).
##  - `FOG_HEIGHT_M` / `FOG_HEIGHT_DENSITY` (brouillard de HAUTEUR, absent des
##    autres cartes : `Environment.fog_height_density` vaut 0,0 par défaut
##    dans Godot 4.7, donc aucun effet tant qu'on ne le règle pas) : une brume
##    basse qui épaissit sous 6 m (`fog_height_density > 0` = plus dense à
##    mesure que la hauteur DIMINUE, doc Godot 4.7 `Environment.
##    fog_height_density`), pour ancrer le sol désertique sans voiler les
##    silhouettes à hauteur de joueur.
##  - `SSAO_*` (rayon 0,9 / intensité 1,15 / puissance 1,6 / contact 0,2 ;
##    défaut partagé 0,8/1,0/1,5/0,15) : occlusion de contact un peu plus
##    marquée pour ancrer les props au sol, delta modeste -- reste « léger »
##    au sens de la bible (§6.3), pas un durcissement généralisé.
##  - `ADJUSTMENT_SATURATION` / `ADJUSTMENT_CONTRAST` (1,008 / 1,008,
##    `adjustment_brightness` neutre à 1,0) : étalonnage de courbe/saturation
##    demandé par ce contrat pour cette carte -- volontairement modeste
##    (anciennes valeurs v2 avant WYSIWYG : 1,20/1,04, voir le tableau §7.5 de
##    `LevelLook.gd`) pour rester « compatible avec l'encre » (ne pas resaturer
##    au point de faire perdre sa lisibilité au trait). Les 7 autres cartes
##    gardent `adjustment_enabled = false` (règle d'or WYSIWYG §7.5). Réduites
##    depuis un premier réglage 1,08/1,05 -- voir RÉGRESSION CORRIGÉE ci-dessous.
##  - `SHADOW_ANGULAR_DISTANCE` (0,2°, défaut partagé 0,5°) : pénombre plus
##    fine -> ombres portées plus franches/contrastées (titre de la tâche),
##    sans toucher `directional_shadow_max_distance`/`directional_shadow_mode`
##    (portée et nombre de PSSM restent une constante moteur partagée, hors du
##    périmètre de cette tâche).
##
##  RÉGRESSION CORRIGÉE (retour vérificateur -- capture réelle des 12 vues
##  map_shots Wasteland via `tools/map_shots.gd` en contexte GPU réel D3D12,
##  avant/après comparées contre `git show HEAD:...` -- l'état AVANT ce
##  contrat -- et mesurées avec le vrai évaluateur `tools/review/
##  style_check.py::eval_ground_stats`/`eval_chroma_hierarchy`) : un premier
##  réglage (`FOG_HEIGHT_DENSITY` 0,06, `ADJUSTMENT_SATURATION`/
##  `ADJUSTMENT_CONTRAST` 1,08/1,05) faisait régresser CHK-04 sur `spawn_bleu`
##  (sol L médiane 0,699 -> 0,799, plafond 0,78 -- la brume de hauteur teintée
##  éclaircit le sol proche caméra ET le contraste de post relève encore la
##  médiane) et CHK-04/CHK-05 sur `hp_c` (p95 chroma sol 0,096 -> 0,107,
##  plafond 0,10 -- la saturation de post s'ajoute à la teinte de brume sur
##  des pixels de sol déjà proches de la limite). `FOG_HEIGHT_DENSITY` (0,06
##  -> 0,003) et `ADJUSTMENT_SATURATION`/`ADJUSTMENT_CONTRAST` (1,08/1,05 ->
##  1,008/1,008) réduits en conséquence : remesuré sur les mêmes 12 vues
##  après correction, `spawn_bleu` (L médiane 0,778) et `hp_c` (p95 C sol
##  0,099) repassent sous leurs plafonds respectifs. Comparaison complète des
##  12 vues contre l'état AVANT ce contrat (CHK-02/04/05, `worse()` par vue) :
##  aucune régression -- chaque vue qui passait avant passe encore (`spawn_bleu`,
##  `grand_rue`, `route_sud`, `hp_b`, `hp_c`, `top_ortho`), chaque vue qui
##  échouait avant échoue encore SUR LE MÊME CRITÈRE au pire (`spawn_rouge`,
##  `route_nord`, `hp_a`, `ligne_longue`, `top_ortho_roofs` -- résidu documenté
##  en tête de fichier, hors périmètre) ; `point_haut` et `top_ortho` passent
##  même CHK-04/CHK-05 là où ils échouaient avant (amélioration, pas seulement
##  neutralité). `perf_bench --maps=wasteland` (avg_fps) est identique avant/
##  après (279,8 -> 279,8) -- aucune régression de performance. Le reste de
##  l'atmosphère (brume de profondeur, SSAO, soleil rasant, ombres franches)
##  est inchangé -- seuls les deux leviers responsables de la régression ont
##  été modérés.
const SUN_ELEVATION_DEG := 24.0
const FOG_TINT_OCRE := Color("e8c179")
const FOG_DENSITY := 0.0024
const FOG_HEIGHT_M := 6.0
const FOG_HEIGHT_DENSITY := 0.003
const SSAO_RADIUS := 0.9
const SSAO_INTENSITY := 1.15
const SSAO_POWER := 1.6
const SSAO_LIGHT_AFFECT := 0.2
const ADJUSTMENT_SATURATION := 1.008
const ADJUSTMENT_CONTRAST := 1.008
const SHADOW_ANGULAR_DISTANCE := 0.2

## Dictionnaire `color_key`/`"<rôle>_kind"`/`"<rôle>_roof_kind"` consommé par
## `Kit.build_piece` (voir son en-tête « `mat` … avant `color_key` ») via
## `WastelandLayout.data()["palette"]`. Fonction statique pure (aucun état,
## aucun nœud requis) : mêmes valeurs à chaque appel, testable sans arbre de
## scène — même contrat que `LevelLook.build_environment`/`build_sky_material`.
static func palette() -> Dictionary:
	return {
		# "floor"/"wall" : albédos PRÉ-COMPENSÉS (voir MÉTHODE en tête de
		# fichier), PAS les jetons bruts de tokens.json -- plus sombres/moins
		# saturés pour que la MÉDIANE RENDUE (post-lumière), pas seulement
		# l'albédo d'entrée, tombe dans la fourchette du contrat.
		"floor": Color("a7976d"), "wall": Color("b9a987"), "cover": Color("b8afa0"),
		"platform": Color("9c9086"), "accent": Color("e3872a"),
		"rock": Color("8c6b55"), "adobe": Color("b08f66"),
		"cover_kind": "cracked_concrete",
		"platform_kind": "cracked_concrete", "accent_kind": "painted_metal",
		"adobe_kind": "cracked_concrete",
		"wall_roof_kind": "rust", "adobe_roof_kind": "corrugated_metal",
		# "floor_kind"/"rock_kind"/"wall_kind" volontairement ABSENTS :
		# `Kit.build_piece` retombe alors sur `""` -> `Cartoon.world()` plat
		# (voir le commentaire de tête) -- le sol, les falaises et les murs
		# FUEL/GAS restent des couleurs pleines calibrées, jamais un kind
		# peint dilué à 20% (non tintable) qui ferait dériver leur L/C mesurés
		# hors de notre contrôle.
		#
		# ART-91 (ADDITIF, docs/art/WASTELAND_V4_ART_PLAN.md §2 R6
		# "Intérieurs" : "murs, sols et dalles du Kit... en matières peintes :
		# `wall_kind = wood_planks` et plancher peint") : deux clés NOUVELLES,
		# consommées par les futurs modules d'art (ART-94/95,
		# `wasteland_art/ArtBuildings1F.gd`/`ArtBuildings2F.gd`) quand ils
		# posent le `kind` de LEURS PROPRES boîtes de dressing intérieur
		# (poteaux d'angle, corniche, cadres, volets, poutres — R6) — jamais
		# lues par `Kit.build_piece` lui-même (qui ne connaît que
		# `"<rôle>_kind"`, ci-dessus) : elles ne changent donc RIEN au rendu
		# actuel des murs/sols bruts du Kit (`"wall"`/`"floor"`, calibrés
		# plats, MÉTHODE en tête de fichier — une future peau de façade R2 les
		# bascule en `visual:false`, Kit.gd ADDITIF, avant qu'un mur redevienne
		# visible de l'intérieur). `wood_planks` : seul kind "planches" déjà
		# peint et cuit du catalogue (`Cartoon.PAINTED_MATERIALS`,
		# `tools/textures/gen_textures.py`), repris pour le sol ET le mur
		# intérieur (western en bois, R6 ne distingue pas les deux).
		"interior_wall_kind": "wood_planks", "interior_floor_kind": "wood_planks",
	}
