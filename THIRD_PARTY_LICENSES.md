# Licences tierces

Tout élément qui n'a pas été créé pour ce projet est listé ici, avec sa source et sa
licence. Un asset sans ligne dans ce fichier ne doit pas entrer dans le jeu.

## Livré avec le jeu

| Élément | Chemin | Source | Licence | Texte |
|---|---|---|---|---|
| Police Barlow Condensed (SemiBold, Bold, ExtraBold, Bold Italic, ExtraBold Italic, Black Italic — titres UI v4, ajoutée 2026-09-25) — Bold Italic et ExtraBold Italic sont les VRAIES coupes italiques (`Comic.button_secondary_font()`/`Comic.title_font()`, STYLE_BIBLE v3 §8.2, ART-30) ; le cisaillement synthétique (`Comic.font_title_italic()`) reste un repli si ces fichiers venaient à manquer | `resources/fonts/BarlowCondensed-*.ttf` | Jeremy Tribby — https://github.com/jpt/barlow (récupérées sur https://github.com/google/fonts/tree/main/ofl/barlowcondensed) | SIL Open Font License 1.1 | [`resources/fonts/OFL-Barlow.txt`](resources/fonts/OFL-Barlow.txt) |
| Police Barlow Semi Condensed (Medium) | `resources/fonts/BarlowSemiCondensed-Medium.ttf` | Jeremy Tribby — https://github.com/jpt/barlow | SIL Open Font License 1.1 | [`resources/fonts/OFL-Barlow.txt`](resources/fonts/OFL-Barlow.txt) |
| Police Bangers (Regular) — onomatopée de kill UNIQUEMENT (`Comic.font_onomatopoeia()`, STYLE_BIBLE v3 §8.2, ART-30) | `resources/fonts/Bangers-Regular.ttf` | Vernon Adams — https://github.com/googlefonts/bangers (récupérée sur https://github.com/google/fonts/tree/main/ofl/bangers) | SIL Open Font License 1.1 | [`resources/fonts/OFL-Bangers.txt`](resources/fonts/OFL-Bangers.txt) |
| Moteur Godot 4.7 | (runtime) | https://godotengine.org | MIT | https://godotengine.org/license |
| Bras FP (avant-bras + mains à doigts articulés, modes avant-bras et mains flottantes) dérivés du mannequin Universal Animation Library, générés par `tools/blender/fp_rig.py` (FP-10) | `assets/models/fp/fp_arms*.glb` | Quaternius — https://quaternius.com (source : `assets/incoming/quaternius/ual.glb`) | CC0 1.0 | https://creativecommons.org/publicdomain/zero/1.0/ |
| Maillage + squelette + animations des 6 agents et des avant-bras FP (kitbash gear par-dessus le mannequin "Universal Animation Library" Standard) | `assets/models/characters/*.glb` | Quaternius — https://quaternius.com | CC0 1.0 | https://creativecommons.org/publicdomain/zero/1.0/ |

## Outils de développement (non livrés dans les builds joueurs)

| Élément | Chemin | Source | Licence | Texte |
|---|---|---|---|---|
| gdUnit4 6.2.1 | `addons/gdUnit4/` | https://github.com/godot-gdunit-labs/gdUnit4 | MIT | [`addons/gdUnit4/LICENSE`](addons/gdUnit4/LICENSE) |

## Contenu procédural du projet (généré par script)

Ces maillages sous `assets/models/**` sont des créations originales du projet : leur
géométrie part intégralement d'un script Blender (bpy) du dépôt (aucune forme importée
d'un outil IA ni d'un tiers). Ce ne sont pas des éléments tiers au sens de l'en-tête de ce
fichier ; ils sont listés ici uniquement pour que chaque fichier de `assets/models/**` ait
une ligne de traçabilité vérifiée par `tools/ai3d/licence_check.py` (règle 1 — voir aussi la
section « Contenu généré par IA » ci-dessous pour le reste de `assets/models/**`).

| Élément | Chemin | Source | Licence | Texte |
|---|---|---|---|---|
| Props « échantillon » de démonstration de la bibliothèque toonkit | `assets/models/_samples/sample_props.glb` | `tools/blender/examples/make_sample_prop.py` | Œuvre originale du projet (générée par script du dépôt) | — |
| Coulisses d'horizon « landmark » (désert, port_cargo, city, mountain), silhouettes vues à 150-600 m | `assets/models/backdrops/*/landmark.glb` | `tools/blender/make_backdrops.py` | Œuvre originale du projet (générée par script du dépôt) | — |
| Bibliothèque de props Cargo Ship (conteneurs, coque, grue, passerelle, bittes, cabestans...) | `assets/models/props/cargo_ship/*.glb` | `tools/blender/make_props.py` (jeu `SET_CARGO`, DSL `PROPS`) | Œuvre originale du projet (générée par script du dépôt) | — |
| Bibliothèque de props Wasteland (épaves, panneaux, clôtures, shopfronts, bidons, roches basses...) — fichiers directement sous ce dossier, hors sous-dossiers `rocks/`, `shanty/`, `skins/`, `tripo/`, `tripo_far/` documentés séparément (sous-dossiers IA plus bas, `rocks/`/`shanty/` juste en dessous) | `assets/models/props/wasteland/*.glb` | `tools/blender/make_props.py` (jeu `SET_WASTELAND`, DSL `PROPS`) | Œuvre originale du projet (générée par script du dépôt) | — |
| Roches et falaises stylisées v2/v3 (rochers, blocs de falaise, mesas, paroi de canyon) et v4 (aiguilles, murs de falaise segmentés, mesas ×2 — ART-98) | `assets/models/props/wasteland/rocks/*.glb` | `tools/blender/make_stylized_rocks.py` (registres `PIECES`/`V4_PIECES`) + `tools/blender/paint_bake.py` (texture peinte cuite) | Œuvre originale du projet (générée par script du dépôt) | — |
| Kit « bidonville » v2 (murs à planches, frontons, porches, corniches, escaliers, comptoir, wagonnet, garde-corps...) | `assets/models/props/wasteland/shanty/*.glb` | `tools/blender/make_wl_shanty_kit.py` (registre `MODULES`, ART-73/ART-92) | Œuvre originale du projet (générée par script du dépôt) | — |
| Armes bpy en blocs d'origine — sauvegarde faite par `fit_weapon_painted.py` AVANT écrasement par leur version peinte Tripo (voir `assets/models/weapons/*.glb` dans la section IA ci-dessous) | `assets/models/weapons/_bpy/*.glb` | `tools/blender/make_weapons.py` | Œuvre originale du projet (générée par script du dépôt) | — |
| Peau « volumes pleins » ART-96 procédurale (type « c » du tableau `docs/art/WASTELAND_V4_ART_PLAN.md` §2 : kit v2 + `paint_bake.py` v2, aucune coque Tripo) : 3 gabarits de barricade (rue/ruelle/canyon) | `assets/models/props/wasteland/skins/covers_barricade_rue.glb` | Script Blender ad hoc de la tâche ART-96 (assemblage bmesh façon `tools/blender/make_wl_shanty_kit.py`) + `tools/blender/paint_bake.py` — classification « type c » documentée dans `docs/art/WASTELAND_V4_ART_PLAN.md` §2 | Œuvre originale du projet (générée par script du dépôt) | — |
| idem, gabarit ruelle | `assets/models/props/wasteland/skins/covers_barricade_ruelle.glb` | idem ci-dessus | Œuvre originale du projet (générée par script du dépôt) | — |
| idem, gabarit canyon | `assets/models/props/wasteland/skins/covers_barricade_canyon.glb` | idem ci-dessus | Œuvre originale du projet (générée par script du dépôt) | — |
| Peau ART-96 procédurale (type « c ») : module `crate_stack_fit` aux cotes, caisses sur quai | `assets/models/props/wasteland/skins/covers_caisses_quai.glb` | idem ci-dessus | Œuvre originale du projet (générée par script du dépôt) | — |
| Peau ART-96 procédurale (type « c ») : module `crate_stack_fit` aux cotes, caisses ouest/est | `assets/models/props/wasteland/skins/covers_caisses_w.glb` | idem ci-dessus | Œuvre originale du projet (générée par script du dépôt) | — |
| Peau ART-96 procédurale (type « c ») : muret du Goulet, traverses empilées en mur de soutènement | `assets/models/props/wasteland/skins/covers_muret_goulet.glb` | idem ci-dessus | Œuvre originale du projet (générée par script du dépôt) | — |
| Peau ART-96 procédurale (type « c ») : module `sleeper_stack`, pile de traverses | `assets/models/props/wasteland/skins/covers_pile_traverses.glb` | idem ci-dessus | Œuvre originale du projet (générée par script du dépôt) | — |
| Peau ART-96 procédurale (type « c ») : abri de pompe en planches cuites | `assets/models/props/wasteland/skins/covers_pompe.glb` | idem ci-dessus | Œuvre originale du projet (générée par script du dépôt) | — |
| Peau ART-96 procédurale (type « c ») : 2 rangs de fûts sur palette (fût procédural cuit par `paint_bake.py` v2) | `assets/models/props/wasteland/skins/covers_tonneaux.glb` | idem ci-dessus | Œuvre originale du projet (générée par script du dépôt) | — |

## Contenu généré par IA

Un asset de `assets/models/**` dont la FORME initiale vient d'un outil IA (ex. Tripo,
voir `docs/research/06_ai_3d_pipeline.md` §A2) n'est pas recopié ligne par ligne ici :
sa provenance est un fichier `<nom_du_fichier>.provenance.json` à côté du `.glb`, écrit
automatiquement par `tools/ai3d/run_batch.py` (ou renseigné à la main pour un import
manuel), avec au minimum :

- `tool` (et `tool_version` si connue) : le nom de l'outil et, pour un modèle de
  diffusion utilisé en amont (image de concept), le modèle chargé ;
- `prompt` (et `image_prompt` le cas échéant) : ce qui a produit la sortie ;
- `date` : date de génération ;
- `licence` : la base légale (ex. « sorties Tripo — plan payant, usage commercial ») —
  la preuve d'achat/l'abonnement reste archivée hors du dépôt, jamais commitée.

Cette provenance sert à la fois de garde-fou de licence (`tools/ai3d/licence_check.py`,
voir plus bas) et de source pour la déclaration Steam (`docs/STEAM_AI_DISCLOSURE.md`).
L'IA ne fournit que la forme : le rendu final vient de `Cartoon.gd`/`ink_toon.gdshader`
sur notre propre palette (§A6 du même document de recherche), donc le style livré n'est
jamais celui sorti brut de l'outil IA.

**Liste noire** (aucune provenance ne doit citer, à quelque titre que ce soit, un de ces
outils — `tools/ai3d/licence_check.py` sort en erreur sinon) :

| Outil interdit | Raison |
|---|---|
| Hunyuan3D (toutes versions 2.x) | Licence Tencent qui exclut explicitement l'UE, le Royaume-Uni et la Corée du Sud, y compris pour l'affichage des sorties |
| FLUX.1 [dev] | Licence non commerciale (à ne pas confondre avec FLUX.1 schnell, Apache-2.0, autorisé) |
| Qwen-Image-2.1 | Licence de recherche (à ne pas confondre avec Qwen-Image-2512, Apache-2.0, autorisé) |

La détection est insensible à la casse et à la ponctuation : « black-forest-labs/FLUX.1-dev »,
« flux.1-dev » et « flux1-dev » sont tous reconnus comme le même modèle interdit, quelle que
soit la forme exacte de l'identifiant écrite dans la provenance (voir
`tools/ai3d/licence_check.py::_normalize`, vérifié par `--selftest`).

## Règles

- Licences acceptées pour le contenu livré : CC0, MIT, Apache-2.0, OFL, BSD, ou licence
  commerciale achetée (preuve d'achat archivée hors du dépôt).
- Pas de licence « non commerciale », pas de licence qui interdit l'usage dans un jeu
  vendu ou free-to-play.
- Polices : vérifier que l'intégration dans un jeu est permise (les polices Blambot,
  même gratuites, exigent une licence payante pour le jeu vidéo).
- Un asset de `assets/models/**` sans ligne ci-dessus NI provenance IA (voir section
  précédente) ne doit pas entrer dans le jeu — vérifié par
  `python tools/ai3d/licence_check.py` (voir aussi la liste noire ci-dessus).
