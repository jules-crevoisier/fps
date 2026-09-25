# 06 — Pipeline 3D pilotée par IA (génération, texturage, rig, outillage agent)

> Recherche du 2026-09-23 (sources web vérifiées ce jour-là, liens en ligne).
> Périmètre : A (génération 3D IA, texturage, rig, retopo, cohérence de style) + B (outillage agent : MCP Blender/Godot, bpy headless, sources CC0).
> Contexte machine : Windows 11, AMD RX 9060 XT 16 Go (gfx1200, **pas de CUDA**), Blender 4.4/5.1/5.2, Docker, Python 3. Utilisateur **en France (UE)**.
> Ce document ne vaut pas avis juridique : les points de licence sont à relire par l'utilisateur avant tout achat.

## Résumé (10 lignes)

1. **Hunyuan3D (toutes versions 2.x) est INTERDIT pour nous** : la licence exclut l'UE, le Royaume-Uni et la Corée du Sud, et interdit même d'*afficher* ses sorties hors territoire. Cela vaut aussi via blender-mcp ou un hébergeur tiers.
2. Les modèles ouverts compatibles avec l'UE (TRELLIS.2 en MIT, Step1X-3D en Apache-2.0, SF3D/SPAR3D sous Stability Community) supposent **CUDA/Linux**. Sur notre Radeon, ils ne passent que par des forks ROCm Linux expérimentaux. TRELLIS.2 dépend en plus de nvdiffrast, dont la licence NVIDIA est non commerciale.
3. La voie réaliste : une **API payante** qui nous cède la propriété des sorties. **Tripo** coûte environ 0,20 à 0,30 $ par modèle, avec retopo, auto-rig et quad disponibles par API. **Meshy** sert de repli ; attention, ses sorties API sont supprimées au bout de 3 jours.
4. L'IA ne doit fournir que la **forme**. Le style vient de chez nous : un script `ai_restyle.py` nettoie, décime, ramène les couleurs à notre palette et fixe les normales, puis le shader `ink_toon` fait le rendu.
5. Les persos « à tête d'objet » conviennent très bien à l'IA : la tête est un **prop rigide**, attaché à l'os `head`. Il n'y a donc pas de rig IA à faire. Le corps reste sur le rig CC0 Quaternius (UAL1, plus les 130 animations CC0 de UAL2).
6. Auto-rig, seulement si besoin plus tard (créatures) : Tripo ou Meshy par API, ou UniRig (MIT, CUDA). Mixamo n'est plus maintenu et AccuRIG a des conditions floues.
7. **Le plus gros levier reste notre code** : un module `stylekit.py` partagé (biseaux, normales pondérées, normales lissées pour les contours, AO et courbure en couleurs de sommet, LOD, export glTF standard), plus une boucle de revue visuelle (turntables + captures Godot existantes).
8. **blender-mcp** (MIT, 29k étoiles) exécute du Python arbitraire dans Blender et envoie de la télémétrie par défaut. C'est utile pour explorer, pas pour produire. **godot-mcp** (MIT) n'apporte rien de plus que nos outils CLI actuels.
9. Sources CC0 sûres : Quaternius (UAL2, Toon Shooter Kit), Kenney, KayKit, Poly Haven. Sketchfab et Poly Pizza se vérifient modèle par modèle.
10. Obligations : déclarer le contenu IA pré-généré dans le questionnaire Steam (règle réécrite le 16/01/2026), et tracer chaque asset IA dans `THIRD_PARTY_LICENSES.md` (outil, plan, date, prompt).

---

## A. Génération 3D par IA

### A1. Image/texte → 3D : modèles ouverts

| Modèle | Licence | UE OK ? | AMD/Windows ? | Coût | Qualité pour du stylisé |
|---|---|---|---|---|---|
| **Hunyuan3D 2.0/2.1** (Tencent) | Tencent Hunyuan 3D Community License | **NON** : Territory « excluding the territory of the European Union, United Kingdom and South Korea », et « You must not use, reproduce, modify, distribute, or display the … Works, Output or results … outside the Territory » ([LICENSE 2.1](https://huggingface.co/tencent/Hunyuan3D-2.1/blob/main/LICENSE), [LICENSE 2.0](https://github.com/Tencent-Hunyuan/Hunyuan3D-2/blob/main/LICENSE)). La demande d'ouverture UE reste sans réponse ([issue #94](https://github.com/Tencent-Hunyuan/Hunyuan3D-2.1/issues/94)). La 2.5 n'existe qu'en service hébergé, et la plateforme est passée en 3.x ([triposr.org](https://triposr.org/blog/hunyuan3d-versions)) | CUDA | Gratuit hors UE | Très bonne (géométrie et PBR), mais **inutilisable** |
| **TRELLIS.2** (Microsoft, déc. 2025, 4 milliards de paramètres) | Code et poids en MIT ([repo](https://github.com/microsoft/TRELLIS.2)) ; dépendances **nvdiffrast / nvdiffrec** sous « Nvidia Source Code License » ([nvdiffrast](https://github.com/NVlabs/nvdiffrast)), une licence de recherche : l'usage commercial passe par NVIDIA Research Licensing | Oui pour TRELLIS.2 lui-même ; **zone grise** pour la chaîne nvdiffrast | Officiel : NVIDIA, 24 Go de VRAM, Linux seulement. Forks ROCm Linux ([TRELLIS.2-ROCm](https://github.com/Mateusz-Dera/TRELLIS.2-ROCm), [ComfyUI ROCm](https://github.com/toastmanAu/trellis-2-rocm-comfyui), [iceblue03](https://github.com/iceblue03/TRELLIS.2_rocm)) ; un fork annonce une RX 9070 XT 16 Go sous ROCm 7.2 ([TRELLIS-AMD](https://github.com/CalebisGross/TRELLIS-AMD)). **Pas de Windows natif** | Gratuit (GPU local ou loué) | Bonne ; sort des GLB en PBR ; pipeline « texturing only » séparé |
| **Step1X-3D** (StepFun) | Apache-2.0 ([repo](https://github.com/stepfun-ai/Step1X-3D)) | Oui | CUDA ; aucun portage AMD connu | Gratuit | Correcte ; peu active en 2026 ([suivi OSS](https://github.com/KAFKA2306/image2outfit/issues/683)) |
| **Stable Fast 3D / SPAR3D** (Stability) | Stability AI Community License : gratuite sous 1 M$ de revenu annuel, **inscription obligatoire** en cas d'usage commercial, sorties à nous ([licence](https://stability.ai/license), [SPAR3D](https://huggingface.co/stabilityai/stable-point-aware-3d), [SF3D](https://huggingface.co/stabilityai/stable-fast-3d)) | Oui | CUDA (aucune garantie AMD) | Gratuit sous le seuil | Moyenne : low-poly rapide, UV faits, formes molles |
| TripoSR / InstantMesh | MIT / Apache (anciens) | Oui | CUDA | Gratuit | Faible en 2026, dépassés |

**Verdict** : aucun modèle ouvert ne tourne proprement sur **Windows + Radeon** aujourd'hui. PyTorch ROCm sur Windows pour gfx1200 existe, mais en nightly et avec des retours instables ([TheRock #1066](https://github.com/ROCm/TheRock/issues/1066), [ROCm #5010](https://github.com/ROCm/ROCm/issues/5010), [matrice Windows](https://rocm.docs.amd.com/projects/radeon-ryzen/en/latest/docs/compatibility/compatibilityrad/windows/windows_compatibility.html)). Les pipelines 3D (spconv, flexgemm, cumesh, nvdiffrast) restent écrits pour CUDA. Deux options locales seulement, toutes deux à coût d'installation élevé :
- un double démarrage Linux avec ROCm 7.2 et un fork TRELLIS.2 ;
- la location d'un GPU NVIDIA à l'heure.

On ne les retient pas pour démarrer.

### A2. Services payants (API)

| Service | Licence des sorties | UE OK ? | AMD/Windows ? | Coût (sept. 2026) | Qualité pour du stylisé |
|---|---|---|---|---|---|
| **Tripo** (VAST) | Plan payant : modèles privés, droits commerciaux complets. Plan gratuit : Tripo garde les droits ([aide](https://www.tripo3d.ai/help/privacy-policy/how-to-use-tripo-models-commercially), [CGU](https://www.tripo3d.ai/terms)) | Oui (pas d'exclusion territoriale trouvée) | Cloud : indifférent | API à l'usage, **1 crédit = 0,01 $**. Image→3D : 20-30 cr. Texture : 10-30. Smart low-poly/retopo : 10-30. Quad : +5. Auto-rig : 25. Retarget : 10 par anim ([tarifs API](https://developers.tripo3d.ai/en/pricing), [docs](https://docs.tripo3d.ai/get-started/pricing.html)) | Bonne sur les objets. Retopo et rig par API, ce qui colle à un pipeline scripté |
| **Meshy** | Plan payant : le client possède ses sorties. Plan gratuit : CC BY 4.0 au nom de Meshy. **Sorties API supprimées au bout de 3 jours** ([CGU](https://www.meshy.ai/terms-of-use), [aide](https://docs.meshy.ai/en/webapp/pricing)) | Oui | Cloud | À partir de 20 $/mois. Image→3D : 20-35 cr. Remesh : 5. Retexture : 10-15. Auto-rig : 5. Animation : 3 par action ([tarifs API](https://docs.meshy.ai/en/api/pricing), [plans](https://www.meshy.ai/pricing)) | Bonne ; remesh et retexture pratiques |
| **Rodin / Hyper3D** (Deemos) | Usage des sorties non limité selon les CGU, API sur le plan Business ([tarifs](https://hyper3d.ai/pricing)) | Oui | Cloud | 30 $/mois (Creator), 120 $/mois (Business avec API) | Très bonne géométrie, mais trop cher pour nos volumes |
| **Sloyd** | Licence commerciale incluse, revente et entraînement IA exclus ([revue](https://www.stork.ai/en/sloyd-ai)) | Oui | Cloud | 15 $/mois ; API sur devis | Procédural à gabarits : topologie propre, LOD. Trop « catalogue » pour des têtes d'objet originales |
| **Kaedim** | Contrat sur mesure, retouche humaine obligatoire ([tarifs](https://www.kaedim3d.com/pricing)) | Oui | Cloud | Sur devis, plus de 1 000 $/mois | Excellente, mais hors budget et hors boucle automatique |

**Choix** : **Tripo en principal**, **Meshy en repli**. Tripo est le moins cher, facture à l'unité sans abonnement pour l'API, et offre retopo, quad et rig par API. Rodin et Kaedim sont écartés pour leur prix. Sloyd est écarté parce qu'on sait déjà faire du procédural nous-mêmes.

Précautions :
- Le compte, la carte et la clé sont à l'utilisateur. La clé va dans `.env` (déjà ignoré par git) sous `TRIPO_API_KEY`, jamais dans le dépôt.
- On télécharge **immédiatement** chaque sortie : Meshy supprime ses sorties API au bout de 3 jours.
- Tripo et Rodin sont des sociétés chinoises. On leur envoie des images conceptuelles, jamais de code ni de données de joueurs.

### A3. Texturage IA

| Outil | Licence | UE OK ? | AMD/Windows ? | Coût | Intérêt pour nous |
|---|---|---|---|---|---|
| **StableGen** (addon Blender + ComfyUI, multivue, ControlNet, IPAdapter) | GPL-3.0 ([repo](https://github.com/sakalond/StableGen)), v0.3.1 de juin 2026. La GPL s'applique à l'outil, pas aux textures produites | Oui | Oui via **ComfyUI Desktop Windows avec ROCm**, officiel depuis la v0.7.0 en janvier 2026 ([Comfy](https://blog.comfy.org/p/official-amd-rocm-support-arrives), [AMD RX 9000](https://rocm.blogs.amd.com/artificial-intelligence/comfyui-radeon-9000/README.html)) | Gratuit | Intéressant pour peindre un prop entier dans un style donné. **Le modèle de diffusion choisi fixe la licence** |
| Modèles de diffusion utilisables | **FLUX.1 schnell** en Apache-2.0 ([HF](https://huggingface.co/black-forest-labs/FLUX.1-schnell)) ; **SDXL** en OpenRAIL++, commercial autorisé ([licence](https://github.com/Stability-AI/generative-models/blob/main/model_licenses/LICENSE-SDXL1.0)) ; **Qwen-Image-2512** en Apache-2.0 ([HF](https://huggingface.co/Qwen/Qwen-Image)). **À éviter** : FLUX.1 [dev] (modèle non commercial, [licence](https://github.com/black-forest-labs/flux/blob/main/model_licenses/LICENSE-FLUX1-dev)) et Qwen-Image-2.1 (licence de recherche) | Oui pour les trois premiers | ComfyUI ROCm | Gratuit | Concepts de têtes d'objet, décalques |
| Retexture Meshy / Tripo | Selon le plan | Oui | Cloud | 10-30 cr. | Dépanne ; donne souvent un rendu réaliste « PBR », qu'il faudra aplatir |
| TRELLIS.2 texturing | MIT + nvdiffrast | Zone grise | CUDA | — | Non retenu |
| **Notre `gen_textures.py`** (numpy) | À nous | Oui | Oui | 0 | **Reste la base** des matières tuilées (rouille, tôle, bois) : déterministe, encre cuite dedans |

Recommandation : **ne pas texturer les modèles IA avec l'IA**. On transfère leurs couleurs vers notre palette et nos slots de matière (voir A6). ComfyUI (FLUX schnell ou SDXL) sert seulement à produire les **images conceptuelles** à passer en image→3D, et les décalques (logos, affiches).

### A4. Auto-rigging

| Outil | Licence | UE OK ? | AMD/Windows ? | Coût | Verdict |
|---|---|---|---|---|---|
| **Rig CC0 Quaternius UAL** (déjà utilisé) + **UAL2** (130 animations CC0 de plus, même rig « universel » compatible Godot, [page](https://quaternius.com/packs/universalanimationlibrary2.html), [itch](https://quaternius.itch.io/universal-animation-library-2)) | CC0 | Oui | Oui | 0 (Standard gratuit ≈ 60-70 % du pack ; Source payante) | **Base** : nos persos gardent ce rig, les têtes d'objet s'y attachent rigidement |
| Auto-rig Tripo / Meshy (API) | Selon le plan | Oui | Cloud | 25 cr. / 5 cr. | Pour les créatures ou mascottes non humanoïdes, plus tard |
| **UniRig** (Tsinghua + VAST, SIGGRAPH 2025) | MIT ([LICENSE](https://github.com/VAST-AI-Research/UniRig/blob/main/LICENSE)), successeur SkinTokens ([repo](https://github.com/VAST-AI-Research/SkinTokens)) | Oui | CUDA | 0 | Recherche : checkpoints partiels, pas de chemin AMD |
| Mixamo | Libre de droits en commercial, mais Adobe ne le maintient plus (pannes en 2025) ([FAQ Adobe](https://helpx.adobe.com/creative-cloud/faq/mixamo-faq.html), [état 2026](https://app.cinevva.com/guides/free-character-animations-rigging)) | Oui | Web | 0 | À éviter : pas d'API, avenir incertain |
| AccuRIG 2 (Reallusion) | Gratuit, compte ActorCore obligatoire, **conditions commerciales non trouvées** ([page](https://actorcore.reallusion.com/auto-rig), [CG Channel](https://www.cgchannel.com/2025/07/rig-and-animate-3d-characters-for-free-with-accurig-2-0/)) | ? | Windows | 0 | Écarté : GUI seulement, licence floue |

### A5. Retopo et décimation vers un budget de jeu

- **Blender** (déjà là, scriptable) :
  - modificateur `DECIMATE` en COLLAPSE, déjà utilisé dans `make_characters.py`, ou en PLANAR pour les surfaces dures ;
  - `bpy.ops.object.quadriflow_remesh` pour des quads ([manuel 5.2](https://docs.blender.org/manual/en/latest/modeling/meshes/retopology.html)) ;
  - remesh voxel pour boucher les trous d'un scan IA avant décimation.
- **Instant Meshes** (licence BSD, CLI batch, [repo](https://github.com/wjakob/instant-meshes)) : quads plus propres que QuadriFlow. Binaire externe, **pas à installer maintenant**.
- **Retopo Tripo** (« smart low-poly » 10-30 cr., quad +5) : le plus simple en production, et le résultat est déjà prévu pour l'import jeu.
- **Godot** génère ses LOD à l'import (meshoptimizer) : on ne livre que le LOD0 propre, voir 07.

Budgets proposés (à valider avec `docs/PERF.md`) :

| Type | Budget |
|---|---|
| Tête d'objet | ≤ 3 000 tris |
| Perso complet | ≤ 15 000 tris (budget déjà dans `make_characters.py`) |
| Arme en main | ≤ 10 000 tris |
| Petit prop | ≤ 1 500 tris |
| Grand prop | ≤ 5 000 tris |

### A6. Garder un look stylisé cohérent avec des sorties IA

Le problème : chaque génération IA arrive avec sa propre « lumière peinte », des textures réalistes et un maillage mou. La règle est de **garder la forme, jeter le rendu**.

1. **Entrée maîtrisée** : une image conceptuelle de face, en vue orthographique, sur fond neutre, avec un éclairage plat et des formes massives. On part d'une **planche de style** fixe (proportions, palette) plutôt que de prompts libres, et on garde le même préfixe de style et la même graine.
2. **Nettoyage** : fusion des sommets, suppression des parties isolées, remesh voxel si le maillage n'est pas étanche, puis décimation au budget.
3. **Transfert de palette** : on échantillonne la texture IA par face, on quantifie vers la palette du projet (distance Lab, `Cartoon.gd` et `design.md` v2), puis on assigne des **slots de matière** existants (`painted_metal`, `rust`, `wood`, `accent`…). On jette la texture IA. Le rendu vient ensuite de `Cartoon.painted()` et `ink_toon.gdshader`, comme pour les props scriptés.
4. **Normales** : normales pondérées (facettes nettes façon BD), plus des **normales lissées stockées à part** pour la coque de contour (voir B3).
5. **Encre** : AO et courbure cuites en couleurs de sommet, lues par le shader (bords usés, creux sombres), au lieu de l'éclairage cuit de l'IA.
6. **Revue visuelle** : turntable Blender et capture Godot, que Claude lit (PNG). Grille d'acceptation : silhouette lisible à 30 m, zéro couleur hors palette, budget de tris tenu.

---

## B. Outillage piloté par agent

### B1. Serveurs MCP Blender

| Outil | Licence | UE OK ? | AMD/Windows ? | Coût | Utilité |
|---|---|---|---|---|---|
| **ahujasid/blender-mcp** | MIT, environ 29 200 étoiles, dernier push le 21/09/2026 ([repo](https://github.com/ahujasid/blender-mcp)) | Oui, **à condition de ne jamais activer son intégration Hunyuan3D** | Oui (Blender 3.0 et plus, Python 3.10 et plus, `uv`) | 0 | Exploration interactive, captures du viewport |

Détails sur blender-mcp :
- **Ce qu'il fait** : exécute du **Python arbitraire** dans Blender, importe depuis Poly Haven, Sketchfab et Poly Pizza, génère via Hyper3D Rodin et Hunyuan3D, capture le viewport, exporte en GLB/FBX.
- **Installation selon le README actuel** : `uvx mcp-for-blender`, puis `uvx mcp-for-blender install-addon`. Le README l'appelait `uvx blender-mcp` avant : à revérifier au moment d'installer.
- **Sécurité** :
  - l'addon ouvre un socket local qui exécute tout code reçu : ne jamais l'exposer au réseau, et le fermer après usage ;
  - une télémétrie anonyme est collectée par défaut (outils utilisés, OS, versions) : la couper avec `DISABLE_TELEMETRY=true` ;
  - Sketchfab et Poly Pizza mélangent des licences CC-BY et autres : on n'importe que du CC0.
- **Verdict** : utile pour **explorer**, par exemple ajuster une pose ou une proportion en regardant le viewport. **Pas dans la chaîne de production** : nos scripts headless restent la source de vérité (déterministes, versionnés, relançables).

### B2. Serveurs MCP Godot

| Outil | Licence | État | Utilité |
|---|---|---|---|
| **Coding-Solo/godot-mcp** | MIT, environ 5 800 étoiles, dernier push le 16/04/2026 ([repo](https://github.com/Coding-Solo/godot-mcp)) | Aucun commit depuis 5 mois | Lancer l'éditeur ou le projet, lire la sortie de debug, créer une scène ou un nœud, exporter une MeshLibrary, gérer les UID (4.4+) |
| GDAI MCP, Summer Engine (hébergé), bradypp | Payant ou hébergé ([comparatif, source partiale](https://www.summerengine.com/blog/best-godot-mcp-server)) | — | Accès au debugger en direct |

**Verdict** : on n'en a pas besoin. On pilote déjà Godot 4.7 en CLI :
- `--headless` pour les tests gdUnit4 et les smoke tests ;
- `-s tools/*_shots.gd` pour les captures fenêtrées (`prop_shots.gd`, `character_shots.gd`, `fp_shots.gd`, `map_shots.gd`) ;
- la scène `benchmark.tscn`.

Un MCP ajouterait une couche sans rien permettre de nouveau.

### B3. bpy headless : bonnes pratiques pour des assets stylisés

- **Lancement reproductible** : `blender -b --factory-startup --python-exit-code 1 -P script.py -- --args`. `--factory-startup` ignore les préférences et addons de l'utilisateur. `--python-exit-code` fait échouer la CI si le script lève une exception.
- **Géométrie** :
  - bmesh pour les primitives (ce qu'on fait déjà) ;
  - **Geometry Nodes créés en Python** (`bpy.data.node_groups.new(name, "GeometryNodeTree")`, sockets via `group.interface.new_socket(...)`, [API](https://docs.blender.org/api/current/bpy.types.GeometryNodeTree.html), [tutoriel 2026](https://blog.cg-wire.com/blender-scripting-geometry-nodes-2/)) pour les détails répétitifs : rivets, planches, tôle ondulée, câbles en courbes ;
  - [NodeToPython](https://github.com/BrendanParmer/NodeToPython) convertit un node group fait à la main en script.
- **Biseaux et normales** :
  - `BEVEL` sur 2 segments, limité par angle ou par groupe de sommets (déjà en place) ;
  - puis un modificateur `WEIGHTED_NORMAL` avec `keep_sharp=True`, pour des facettes nettes sans ombrage sale ;
  - depuis Blender 4.1, `use_auto_smooth` n'existe plus : on passe par `Mesh.set_sharp_from_angle()` ou le modificateur « Smooth by Angle ».
- **Normales lissées pour la coque de contour** : c'est l'**écart principal chez nous**. On calcule la moyenne des normales par position de sommet (en ignorant les arêtes vives), puis on la stocke :
  - dans un attribut de couleur ou une UV (UV2/CUSTOM) pour les meshes statiques ;
  - dans les **tangentes** pour les meshes skinnés, car Godot skinne `TANGENT` mais pas les attributs custom ([toon-rp wiki](https://github.com/Delt06/toon-rp/wiki/Inverted-Hull-Outline), [godotshaders](https://godotshaders.com/shader/improved-inverted-hull-simplest-outline-shader-improved/)).

  Le shader `ink_outline` extrude ensuite selon cette normale : plus de coque fendue aux arêtes vives.
- **AO en couleurs de sommet** : `bpy.ops.object.bake(type='AO', target='VERTEX_COLORS')` avec Cycles et un attribut de couleur actif. Signature à vérifier par sondage, comme le veut la règle du projet. Cycles HIP gère RDNA4 depuis Blender 4.4 ([notes 4.4](https://developer.blender.org/docs/release_notes/4.4/cycles/)) ; le CPU suffit pour de l'AO par sommet. Alternative sans bake : [VertexOven](https://github.com/ForestKatsch/VertexOven).
- **Masque de courbure** pour les bords peints : on calcule la convexité par sommet en bmesh (angle entre faces adjacentes), on la stocke dans un canal de couleur, et le shader éclaircit les arêtes convexes et encre les creux.
- **Export glTF pour Godot** :
  - `export_format='GLB'`, `export_yup=True`, `export_apply=True` pour les props ;
  - depuis 4.2, les couleurs de sommet s'exportent sans être branchées dans le node tree, avec l'option de couleurs dédiée ([issue 4.1](https://projects.blender.org/blender/blender/issues/123925), [glTF-IO #1740](https://github.com/KhronosGroup/glTF-Blender-IO/issues/1740)) : à fixer explicitement dans le module partagé ;
  - noms de matériaux = noms de slots (déjà la convention) ;
  - animations : une **bibliothèque d'animations partagée** plutôt que 46 actions recopiées dans chacun des 6 GLB.
- **Rapport machine** : chaque build affiche une ligne parseable (`CHAR_TRIS`, `PROP_TRIS`… déjà en place) plus un JSON (tris, bbox, slots, attributs présents) que les tests peuvent vérifier.

### B4. Sources d'assets CC0 compatibles avec notre style

| Source | Licence | Intérêt |
|---|---|---|
| **Quaternius** : UAL 1 et 2 (rigs et animations), Toon Shooter Game Kit, Sci-Fi Modular Gun Pack, Ultimate Modular Men/Women, Universal Base Characters ([site](https://quaternius.com/), [OGA CC0](https://opengameart.org/content/all-cc0-uploader-quaternius)) | CC0 1.0 | Déjà notre base de persos. Les formes simples se restylent bien avec `ink_toon` |
| **KayKit** (Kay Lousberg) ([itch](https://kaylousberg.itch.io/kaykit)) | CC0, sans attribution | Low-poly propre, bon pour les kits de décor et les objets de tête |
| **Kenney** ([3D](https://kenney.nl/assets/category:3D/)) | CC0 | Blocs de décor, route, véhicules simples |
| **Poly Haven** | CC0 | HDRI et textures réalistes : peu utiles pour le rendu peint, sauf comme base à postériser |
| Poly Pizza, Sketchfab | **Mixte** (CC-BY, etc.) | Vérifier modèle par modèle ; seul le CC0 entre sans ligne d'attribution |

Règle existante (`THIRD_PARTY_LICENSES.md`) : aucun asset sans ligne dans le fichier. On y ajoute une section **« Contenu généré par IA »** : outil, version du modèle, plan payant (avec la preuve d'achat archivée hors du dépôt), date, prompt ou image source, chemin.

---

## Tableau comparatif (synthèse)

| Outil | Licence | UE OK ? | Tourne sur AMD/Windows ? | Coût | Qualité pour du stylisé |
|---|---|---|---|---|---|
| Hunyuan3D 2.x | Tencent Community | **Non** | Non (CUDA) | 0 | ★★★★ (interdit) |
| TRELLIS.2 | MIT + nvdiffrast (non commercial) | Zone grise | Forks ROCm Linux seulement | 0 | ★★★ |
| Step1X-3D | Apache-2.0 | Oui | Non (CUDA) | 0 | ★★ |
| SF3D / SPAR3D | Stability Community (< 1 M$) | Oui | Non (CUDA) | 0 | ★★ |
| **Tripo API** | Sorties à nous (plan payant) | Oui | Cloud | ≈ 0,20-0,55 $ par asset | ★★★ |
| Meshy API | Sorties à nous (payant), purgées à J+3 | Oui | Cloud | 20 $/mois et plus | ★★★ |
| Rodin | Usage libre | Oui | Cloud | 120 $/mois (API) | ★★★★ |
| Sloyd | Commercial, revente exclue | Oui | Cloud | 15 $/mois | ★★ |
| Kaedim | Contrat | Oui | Cloud | > 1 000 $/mois | ★★★★ |
| StableGen + ComfyUI | GPL-3 (outil) + modèle choisi | Oui (FLUX schnell, SDXL) | Oui (ComfyUI ROCm) | 0 | ★★ (textures) |
| UniRig | MIT | Oui | Non (CUDA) | 0 | ★★ (rig) |
| Mixamo | Libre de droits | Oui | Web | 0 | ★★ (abandonné) |
| blender-mcp | MIT | Oui (sans Hunyuan) | Oui | 0 | Outil d'exploration |
| godot-mcp | MIT | Oui | Oui | 0 | Redondant avec notre CLI |
| **Scripts bpy maison** | À nous | Oui | Oui | 0 | ★★ aujourd'hui, ★★★ avec `stylekit` |

---

## Écarts avec notre projet

| Fichier | Constat | Conséquence |
|---|---|---|
| `tools/blender/make_props.py` (l. 1396), `make_weapons.py` (l. 260) | `use_smooth=False` partout, aucune normale lissée stockée à part | La coque inversée (`assets/shaders/ink_outline.gdshader`) extrude selon des normales de facettes : **le contour se fend** aux arêtes vives. La roadmap dit P3.8 « normales lissées pour les contours » fait, mais le code ne le fait pas |
| `tools/blender/make_characters.py` (`_finish_object`, l. 525-571) | Biseau limité aux groupes de sommets, `harden_normals=False`, pas de normales pondérées, pas d'AO ni de courbure en couleurs de sommet | Rendu « primitive » : la courbure et l'usure ne sont pas lisibles |
| `make_characters.py` (`_export`, l. 574-594) | `export_animation_mode='ACTIONS'` : les 46 animations sont recopiées dans chacun des 6 GLB + `fp_arms.glb` | Poids disque et temps d'import multipliés ; aucune bibliothèque d'animations partagée |
| `make_characters.py` | Les têtes sont des cagoules ou chapeaux sur le mannequin ; pas de point d'attache « tête d'objet » | La DA visée (persos à tête d'objet) n'a aucun support. Il faut une ancre sur l'os `head` et un catalogue de têtes |
| `make_props.py`, `make_weapons.py`, `make_characters.py`, `make_gloves.py` | Chaque script redéfinit ses helpers (box, cyl, biseau, export) | Pas de module partagé : chaque correctif se fait 4 fois |
| `tools/textures/gen_textures.py` | Textures peintes numpy, en triplanaire monde | Bonne base, à garder. Les assets IA doivent y **revenir** (slots de kinds), pas apporter leur propre texture |
| `tools/*_shots.gd` | Captures Godot fenêtrées existantes | La boucle de revue visuelle existe côté Godot ; il manque un turntable Blender brut avant import |
| `THIRD_PARTY_LICENSES.md` | Aucune section pour le contenu IA | Traçabilité et questionnaire Steam à prévoir |
| `.env.example` | Pas de clé `TRIPO_API_KEY` / `MESHY_API_KEY` | À ajouter le jour où l'utilisateur crée le compte |

---

## Pipeline RECOMMANDÉ

Principe : **le code reste la source de vérité**. L'IA ne fournit que des **formes brutes**. Tout passe par nos scripts de restyle, puis par notre shader, et chaque asset porte une provenance.

### Étape 0 — Ce qu'on n'utilise PAS (licence ou pratique)

- **Hunyuan3D**, sous aucune forme : local, fal/Replicate/autres hébergeurs, ou intégration Hunyuan de blender-mcp. La licence 2.x interdit jusqu'à l'affichage de ses sorties dans l'UE. Le service hébergé 3.x de Tencent est aussi écarté par prudence : ses CGU n'ont pas été vérifiées ici.
- **FLUX.1 [dev]** et **Qwen-Image-2.1** : modèles non commerciaux ou de recherche.
- **Plans gratuits** de Tripo (Tripo garde les droits) et de Meshy (CC BY au nom de Meshy).
- **TRELLIS.2 en production** tant que la chaîne nvdiffrast (licence NVIDIA non commerciale) n'est pas clarifiée.
- **Sketchfab et Poly Pizza** hors CC0, sauf ligne d'attribution explicite.
- **Mixamo et AccuRIG** : non maintenu pour l'un, licence floue pour l'autre.

### Étape 1 — Fondations maison (aucune installation)

`tools/blender/stylekit.py`, un module importé par tous les `make_*.py` :
- primitives chunky, biseau et normales pondérées ;
- attribut « normale lissée » (couleur ou UV2 en statique, tangente en skinné) ;
- AO et courbure en couleurs de sommet ;
- slots de kinds ;
- export glTF standard avec rapport JSON.

On migre ensuite `make_props.py`, `make_weapons.py`, `make_gloves.py` et `make_characters.py`. On ajoute `render_turntable.py` (EEVEE, 4 vues + planche PNG) :

```bash
blender -b --factory-startup --python-exit-code 1 -P tools/blender/make_props.py
blender -b --factory-startup --python-exit-code 1 -P tools/blender/render_turntable.py -- --in assets/models/props --out reports/turntables
"$GODOT_BIN" --path . -s tools/prop_shots.gd -- --out=reports/prop_shots
```

### Étape 2 — Génération des formes (compte payant de l'utilisateur)

- L'utilisateur crée un compte **Tripo** (API, crédits à l'usage) et met `TRIPO_API_KEY=...` dans `.env`. Repli : Meshy (plan Pro, API), avec `MESHY_API_KEY`.
- `tools/ai3d/tripo_client.py` : un client HTTP (`requests`, rien d'autre à installer) contre l'API REST documentée.
  - Entrée : un JSON de commande (prompt ou image, budget de tris, retopo oui/non).
  - Sortie : `assets_src/ai_raw/<id>/model.glb` + `provenance.json` (outil, version du modèle, plan, date, coût en crédits, prompt, hash de l'image).
  - Téléchargement **immédiat**.
- Images conceptuelles, option A : la génération d'image de Tripo ou Meshy (5-15 cr.).
- Images conceptuelles, option B, locale et gratuite : **ComfyUI Desktop Windows avec ROCm** et **FLUX.1 schnell** (Apache-2.0) ou SDXL. À installer par l'utilisateur plus tard, **pas maintenant**.

```bash
python tools/ai3d/tripo_client.py --order tools/ai3d/orders/head_tv.json --out assets_src/ai_raw/head_tv
```

### Étape 3 — Restyle (le cœur de la cohérence)

`tools/blender/ai_restyle.py` enchaîne :
- import du GLB brut ;
- nettoyage (fusion, pièces isolées, remesh voxel si le maillage n'est pas étanche) ;
- décimation ou QuadriFlow au budget ;
- **transfert de palette** : échantillonnage de la texture, quantification Lab vers nos kinds et teintes, assignation des slots, texture IA jetée ;
- normales pondérées et normales lissées pour les contours, via `stylekit` ;
- AO et courbure ;
- normalisation de l'échelle et de l'origine (base au sol, +Y) ;
- export dans `assets/models/<famille>/`, avec rapport JSON et turntable.

```bash
blender -b --factory-startup --python-exit-code 1 -P tools/blender/ai_restyle.py -- --in assets_src/ai_raw/head_tv/model.glb --family heads --budget 3000 --out assets/models/heads/head_tv.glb
```

### Étape 4 — Persos à tête d'objet

- Corps : rig CC0 UAL, plus les vêtements en coques (technique actuelle).
- Tête : un prop rigide (IA restylé **ou** procédural `make_heads.py`), attaché à l'os `head` par un `BoneAttachment3D` côté Godot ou un parentage d'os côté Blender. Aucun skinning, aucun rig IA.
- Animations : bibliothèque partagée UAL1 + UAL2 (CC0) dans un seul fichier.

```bash
blender -b --factory-startup --python-exit-code 1 -P tools/blender/make_heads.py
blender -b --factory-startup --python-exit-code 1 -P tools/blender/make_characters.py
"$GODOT_BIN" --path . -s tools/character_shots.gd -- --out=reports/character_shots
```

### Étape 5 — Contrôle et traçabilité

- `tools/ai3d/licence_check.py` fait échouer le build si un asset de `assets/models/**` n'a ni provenance ni ligne dans `THIRD_PARTY_LICENSES.md`.
- Test gdUnit4 : budgets de tris, attributs présents, slots connus.
- Brouillon de la déclaration Steam « contenu IA pré-généré » (règle réécrite le 16/01/2026 : les outils de développement invisibles du joueur n'ont pas à être déclarés, les assets livrés si, [synthèse](https://www.productionalchemist.com/p/steam-ai-disclosure-rules-2026-what-indie-devs-need-to-know), [IndieForGames](https://indieforgames.com/steam-ai-disclosure-rules/)).

### Option — Exploration interactive (jamais en production)

blender-mcp, à activer seulement à la demande de l'utilisateur :

```json
{ "mcpServers": { "blender": { "command": "uvx", "args": ["mcp-for-blender"], "env": { "DISABLE_TELEMETRY": "true" } } } }
```

Règles d'usage :
- ne jamais appeler ses outils Hunyuan3D ;
- Sketchfab : CC0 seulement ;
- fermer l'addon (le socket) après la session ;
- tout ce qui est retenu est **réécrit** dans un script `tools/blender/*.py`.

---

## Risques

| # | Risque | Probabilité | Impact | Parade |
|---|---|---|---|---|
| R1 | Un asset Hunyuan3D entre par un hébergeur tiers ou par blender-mcp | Moyenne | **Bloquant** (licence : interdiction d'afficher dans l'UE) | Liste noire dans `licence_check.py` (champ `tool` de la provenance) ; outils Hunyuan de blender-mcp jamais appelés |
| R2 | Les sorties IA ne sont pas protégeables par le droit d'auteur dans l'UE (création intellectuelle humaine exigée) : un concurrent peut les copier | Moyenne | Moyen | Transformation substantielle par nos scripts (restyle, kitbash, assemblage) ; documenter la part humaine et scriptée |
| R3 | Les CGU de Tripo ou Meshy changent (prix, propriété, fermeture ; précédent : Hathora fermé en 2026) | Moyenne | Moyen | Provenance datée et archivée ; client abstrait (Tripo et Meshy interchangeables) ; les formes brutes sont gardées hors du jeu |
| R4 | Style hétérogène d'un asset IA à l'autre | Haute | Haut | Transfert de palette obligatoire, texture IA jetée, planche de style fixe, revue par turntable avec grille d'acceptation |
| R5 | Maillages IA non étanches ou trop denses (contours cassés, surcoût GPU) | Haute | Moyen | Remesh voxel et décimation ; budgets vérifiés par test ; normales lissées recalculées par nous |
| R6 | Le questionnaire Steam, mal rempli, retarde la sortie ou provoque un retrait | Faible | Haut | Section IA dans `THIRD_PARTY_LICENSES.md`, reprise telle quelle dans le questionnaire |
| R7 | blender-mcp : exécution de code arbitraire, télémétrie | Faible | Moyen | Hors production, `DISABLE_TELEMETRY=true`, socket fermé après usage |
| R8 | Pilotes ROCm Windows instables (si on tente le local) | Haute | Faible | Pas de dépendance locale à la 3D IA ; ComfyUI reste optionnel |
| R9 | Revenu au-delà de 1 M$ (Stability) ou de 1 M MAU (Tencent) | Faible | Moyen | Stability n'est pas dans le pipeline retenu ; Tencent est exclu d'office |
| R10 | Coût IA non maîtrisé | Faible | Faible | Crédits Tripo à l'usage (≈ 0,5 $ par asset complet) ; plafond de crédits par commande dans le client |

---

## Tâches

```
- id: A3D-01
  title: Bible de style 3D (proportions chunky, biseaux, palette et kinds, budgets de tris, règles de silhouette, grille d'acceptation turntable)
  files: [docs/ART_3D.md]
  depends_on: []
  size: S
  acceptance: le document fixe les budgets (tête ≤ 3k, perso ≤ 15k, arme en main ≤ 10k, petit prop ≤ 1,5k, grand prop ≤ 5k tris), la largeur de biseau par taille d'objet, la palette hex liée à Cartoon.gd et une grille de revue en 5 points ; l'utilisateur la valide

- id: A3D-02
  title: Module partagé stylekit (primitives, biseau + normales pondérées, normales lissées pour contour, AO et courbure en couleurs de sommet, slots de kinds, export glTF standard, rapport JSON)
  files: [tools/blender/stylekit.py, tests/rendering/test_stylekit_assets.gd]
  depends_on: [A3D-01]
  size: M
  acceptance: blender -b --factory-startup --python-exit-code 1 -P sur un prop de test produit un GLB dont le rapport JSON liste les attributs smooth_normal, ao et curvature et le nombre de tris ; le GLB importé dans Godot expose ces attributs (CUSTOM/COLOR/TANGENT) ; aucune API bpy supprimée depuis 4.1 (use_auto_smooth) n'est utilisée

- id: A3D-03
  title: Migrer make_props, make_weapons et make_gloves vers stylekit
  files: [tools/blender/make_props.py, tools/blender/make_weapons.py, tools/blender/make_gloves.py]
  depends_on: [A3D-02]
  size: L
  acceptance: les 3 scripts n'ont plus de helpers dupliqués ; chaque GLB régénéré porte des normales lissées et de l'AO en couleurs de sommet ; tris ≤ budgets d'A3D-01 ; tools/prop_shots.gd ne montre plus aucun contour fendu aux arêtes vives (comparaison avant/après dans reports/)

- id: A3D-04
  title: Migrer make_characters vers stylekit et bibliothèque d'animations partagée (UAL1 + UAL2 CC0)
  files: [tools/blender/make_characters.py, tools/blender/make_anim_library.py, assets/models/characters/]
  depends_on: [A3D-02]
  size: L
  acceptance: les persos ne contiennent plus leurs propres actions ; un seul fichier d'animations partagé est chargé en AnimationLibrary ; normales lissées stockées en tangentes (skinnées) ; tools/character_shots.gd montre les 6 agents animés sans régression ; ligne UAL2 ajoutée dans THIRD_PARTY_LICENSES.md

- id: A3D-05
  title: Turntable Blender headless (EEVEE, 4 vues + planche PNG) pour la revue visuelle par Claude
  files: [tools/blender/render_turntable.py]
  depends_on: [A3D-02]
  size: S
  acceptance: blender -b -P tools/blender/render_turntable.py -- --in <glb|dossier> --out <dossier> écrit une planche PNG par asset (face, profil, dos, 3/4), fond neutre, éclairage plat, en moins de 10 s par asset sur la machine de dev

- id: A3D-06
  title: Client API Tripo (repli Meshy) avec provenance et plafond de crédits
  files: [tools/ai3d/tripo_client.py, tools/ai3d/meshy_client.py, tools/ai3d/orders/example_head.json, .env.example]
  depends_on: []
  size: M
  acceptance: la clé est lue depuis l'environnement uniquement (jamais loguée) ; une commande JSON produit assets_src/ai_raw/<id>/model.glb + provenance.json (outil, modèle, plan, date, crédits, prompt, sha256 de l'image) ; le client refuse toute commande au-delà du plafond de crédits ; aucun appel réseau dans les tests (mock)

- id: A3D-07
  title: Script de restyle des sorties IA (nettoyage, budget, transfert de palette vers les kinds, normales, AO/courbure, échelle et origine)
  files: [tools/blender/ai_restyle.py]
  depends_on: [A3D-02, A3D-05]
  size: L
  acceptance: sur 3 GLB bruts de test, la sortie respecte le budget, n'a plus de texture IA, n'utilise que des slots de kinds connus de Cartoon.gd, a sa base au sol en +Y ; le turntable est généré ; la couleur moyenne de chaque slot reste à moins de ΔE 10 de la palette

- id: A3D-08
  title: Persos à tête d'objet (catalogue de têtes procédurales et IA restylées, attache à l'os head)
  files: [tools/blender/make_heads.py, assets/models/heads/, tools/blender/make_characters.py]
  depends_on: [A3D-04, A3D-07]
  size: L
  acceptance: au moins 6 têtes d'objet (au moins 3 procédurales, au moins 3 IA restylées) ≤ 3k tris chacune ; chacune se fixe à l'os head sans skinning et suit les 46 animations sans clipping visible en character_shots ; silhouette identifiable à 30 m ; validation utilisateur sur la planche

- id: A3D-09
  title: Garde-fou de licence et section IA (provenance obligatoire, liste noire Hunyuan, brouillon de déclaration Steam)
  files: [tools/ai3d/licence_check.py, THIRD_PARTY_LICENSES.md, docs/STEAM_AI_DISCLOSURE.md]
  depends_on: [A3D-06]
  size: S
  acceptance: licence_check.py sort en code 1 si un fichier de assets/models/** n'a ni ligne dans THIRD_PARTY_LICENSES.md ni provenance.json, ou si une provenance cite hunyuan, flux-dev ou qwen-image-2.1 ; branché dans tools/test.sh

- id: A3D-10
  title: (Optionnel, après accord de l'utilisateur) images conceptuelles locales via ComfyUI ROCm + FLUX.1 schnell ou SDXL
  files: [tools/ai3d/comfy_concepts.py, tools/ai3d/workflows/concept_ortho.json]
  depends_on: [A3D-01]
  size: M
  acceptance: le script envoie un workflow à un ComfyUI local (installé par l'utilisateur) et récupère une image orthographique fond neutre ; la licence du modèle utilisé est écrite dans la provenance ; refus si le modèle chargé n'est pas dans la liste blanche (flux1-schnell, sdxl-base, qwen-image-2512)

- id: A3D-11
  title: (Optionnel) configuration blender-mcp pour l'exploration, télémétrie coupée
  files: [.mcp.json, docs/ART_3D.md]
  depends_on: []
  size: S
  acceptance: l'utilisateur a approuvé l'ajout ; la config fixe DISABLE_TELEMETRY=true ; la doc rappelle l'interdiction des outils Hunyuan3D et la règle « tout ce qui est retenu est réécrit en script »
```
