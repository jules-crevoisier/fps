# 07 — Godot 4.5–4.7 : polish technique (rendu toon, perf, réseau, addons)

> Recherche du 2026-09-23 (sources vérifiées ce jour-là, liens en ligne). Version cible : **Godot 4.7.2-stable** (18/08/2026, [GitHub](https://github.com/godotengine/godot/releases)).
> Complète `docs/ROADMAP.md` §5 (stack déjà retenue : netfox, Nakama, GodotSteam, Dokploy puis Edgegap, gdUnit4). Ce document ne rouvre pas ces choix : il les précise et liste les écarts.

## Résumé (10 lignes)

1. **Contours** : on garde la coque inversée pour les persos, l'arme en main et les objets. Il lui faut des **normales lissées stockées à part**, sinon elle se fend aux arêtes vives (c'est le cas aujourd'hui).
2. Pour l'ennemi, le **stencil** (Godot 4.5+) peut remplacer la double coque, avec un contour limité aux parties visibles. Jamais de mode X-ray : ce serait un wallhack.
3. L'**encre du décor** en post-process passe aujourd'hui par un quad dans la passe transparente. À déplacer vers un **CompositorEffect post-opaque** (4.3+) qui lit la profondeur et les normales ; coût à mesurer contre le quad actuel.
4. **Stutter** : les ubershaders de 4.4 couvrent l'essentiel. Mais le **shader baker est désactivé dans nos 3 presets d'export**, alors qu'il divise par environ 20 le temps de chargement des shaders sous D3D12, notre pilote Windows. Il faut aussi un préchauffage des effets par carte et les moniteurs de compilation de pipelines dans l'overlay F3.
5. **Éclairage** : si on passe à LightmapGI, le soleil doit être en bake **Dynamic**. En Static, notre `light()` toon n'est **pas appelé** sur les surfaces cuites. Pas de SDFGI ni VoxelGI (coût, Steam Deck, lisibilité).
6. **Anticrénelage** : rien n'est réglé dans le projet. Recommandation : SMAA 1x (4.5+), sans TAA qui baverait l'encre. SSAO est à reconsidérer : il coûte une passe normales/rugosité et salit les aplats.
7. **LOD et culling** : LOD auto à l'import, visibility ranges seulement pour le décor qui ne sert pas de couvert, MultiMesh pour les répétitions. L'occlusion culling ne rapporte que peu en Forward+ (prépasse de profondeur) : on ne l'active que sur Cargo Ship après mesure.
8. **Budget à 144 fps** : 6,9 ms par frame. Proposition : GPU ≤ 5,5 ms et CPU ≤ 4 ms en 1080p en config recommandée, 1 % low ≥ 110 fps, draw calls ≤ 1 500. La référence actuelle (65 draw calls, 275 fps) date d'avant l'art pass.
9. **Réseau** : netfox (MIT, v1.35.3, commits actifs en septembre 2026) reste le bon choix. La compatibilité 4.7 n'est pas affichée, d'où le spike P1. On part d'un tick de 60 Hz, avec rewind plafonné à 200 ms, et un filtre de visibilité façon « fog of war » Valorant contre les wallhacks.
10. **Plateforme et addons** : GodotSteam 4.21 et Server 4.10 (compatibles 4.7.2), Edgegap à 0,00115 $/min/vCPU, EOSG (MIT) pour EAC plus tard. Addons maintenus : gdUnit4 6.2.1, LimboAI 1.8.1, Phantom Camera 0.11, sentry-godot 2.2.0, Beehave 2.9.3.

---

## C1. Cel-shading et contours

### Techniques de contour

| Technique | Coût | Forces | Faiblesses | Pour nous |
|---|---|---|---|---|
| **Coque inversée** (`cull_front`, extrusion en clip-space, largeur constante en pixels) | 1 draw de plus par surface (×2 pour la double coque ennemie), sommets transformés 2 à 3 fois | Contour net par objet, couleur par équipe, épaisseur contrôlée | Se **fend aux arêtes vives** sans normales lissées ; coque interne visible dans les creux ; les draws doublent | Persos, arme en main, objets ramassables. **Il manque les normales lissées** : attribut custom en statique, `TANGENT` en skinné, car Godot skinne `NORMAL` et `TANGENT` mais pas les attributs custom ([toon-rp wiki](https://github.com/Delt06/toon-rp/wiki/Inverted-Hull-Outline), [godotshaders](https://godotshaders.com/shader/improved-inverted-hull-simplest-outline-shader-improved/)) |
| **Stencil** (4.5+ ; `BaseMaterial3D.stencil_mode` = Outline ou X-ray, `stencil_outline_thickness` ; `stencil_mode` dans les shaders spatiaux) | Comme la coque, mais le contour ne se dessine qu'**en dehors** de la silhouette de l'objet | Plus de coque interne visible ; contour seulement autour de la partie visible | Le préréglage « Outline » s'appuie sur `grow` (normales) ; les presets écrasent `next_pass` (utiliser `material_overlay`) ([docs 4.5](https://docs.godotengine.org/en/4.5/classes/class_basematerial3d.html), [PR #80710](https://github.com/godotengine/godot/pull/80710), [démo](https://github.com/apples/godot-stencil-demo), [notes 4.5](https://godotengine.org/releases/4.5/)) | **Contour ennemi** (magenta ou citron) : écriture stencil dans la passe `ink_toon`, lecture « différent de » dans la passe contour. **Le mode X-ray est interdit** (information à travers les murs) |
| **Post-process profondeur + normales** (quad plein écran ou CompositorEffect) | Coût fixe par pixel, indépendant du nombre d'objets. Ordre de grandeur : un Sobel simple coûte bien moins qu'un distance field (1,15 ms en 1080p avec des groupes 16×16, [pink-arcana](https://github.com/pink-arcana/godot-distance-field-outlines)) | Couvre tout le décor d'un coup ; pas de travail par mesh | Objets fins, transparents à ordonner, épaisseur liée à la résolution | Décor : on le garde. Voir ci-dessous pour le passage en CompositorEffect |
| Distance field / jump flood | Plus de 1 ms en 1080p | Contours épais et réguliers | Trop cher pour 144 fps | Non |

**Post-process : quad actuel ou CompositorEffect ?**
- `InkPost.gd` est un quad plein écran enfant de la caméra, dans la **passe transparente**, avec des correctifs empilés (alpha = masque, visibilité réglée par caméra active).
- Un `CompositorEffect` (4.3+) insère un compute shader **après l'opaque** et avant le transparent. Il lit la profondeur et le buffer normales/rugosité (`needs_normal_roughness`), sans interaction avec l'ordre des transparents ([dépôt de référence](https://github.com/pink-arcana/godot-distance-field-outlines), [discussion](https://github.com/pink-arcana/godot-distance-field-outlines/discussions/1)).
- Le buffer normales/rugosité est déjà payé si SSAO reste actif (voir C2). Si on coupe SSAO, le compositor le réactive : ce sont de nouveaux pipelines, à préchauffer.

### Rampe toon dans `light()`

Rappels utiles pour `ink_toon.gdshader` :
- `light()` n'est appelé **que pour les lumières temps réel**. Une lumière en bake **Static** dans un LightmapGI n'appelle pas `light()` sur les surfaces cuites ([doc LightmapGI](https://docs.godotengine.org/en/stable/tutorials/3d/global_illumination/using_lightmap_gi.html)). Le soleil doit donc rester en bake **Dynamic** : seul l'indirect est cuit, et le direct passe par nos bandes.
- `ATTENUATION` contient l'ombre, y compris le shadowmask. Notre shader l'utilise déjà pour faire tomber l'ombre dans la bande sombre.
- L'ambiant (ciel, SSAO, lightmap indirecte) s'ajoute **hors** de `light()`, de façon lisse et sans bandes. Pour garder des aplats, on garde l'ambiant faible, ou on le coupe (`render_mode ambient_light_disabled`) au profit d'un terme maison en `EMISSION`, que le shader utilise déjà pour le rebond du sol.
- `render_mode diffuse_toon` existe, mais sans contrôle des bandes ni de la teinte d'ombre : notre `light()` maison est plus adapté.

## C2. Stutter de compilation des shaders

Mécanique :
- **4.4, ubershaders** : un pipeline générique est précompilé au chargement des meshes et à l'ajout des nœuds, puis les versions spécialisées se compilent en arrière-plan ([doc](https://docs.godotengine.org/en/latest/tutorials/performance/pipeline_compilations.html), [PR #90400](https://github.com/godotengine/godot/pull/90400)).
- **4.5, shader baker** (option d'export) : il précompile vers le format intermédiaire du pilote (SPIR-V, DXIL, MIL). Il réduit le temps de chargement, avec un gain d'environ ×20 sur la démo TPS sous **D3D12 et Metal** ([notes 4.5](https://godotengine.org/releases/4.5/)). Il **ne crée pas** les pipelines GPU finaux : il complète les ubershaders sans les remplacer.

Ce que les ubershaders **ne couvrent pas** (nouveaux pipelines au premier usage) :
- changement de niveau MSAA ;
- premier ReflectionProbe ;
- specular séparé (SSS, effets compositor) ;
- vecteurs de mouvement (TAA, FSR2, flou de mouvement) ;
- buffer normales/rugosité (SSAO, SSIL, SSR, SDFGI, VoxelGI) ;
- LightmapGI, VoxelGI, SDFGI ;
- modes d'ombre des lumières omni ;
- précision 16/32 bits des ombres.

Recommandations issues de la doc :
- préchauffer ces fonctions à l'écran de chargement ;
- instancier les effets (flash de bouche, impacts, fumée, capacités) **invisibles** dès le chargement de la carte ;
- ne jamais basculer ces options en plein match, seulement dans le menu ;
- surveiller les moniteurs `PIPELINE_COMPILATIONS_{CANVAS,MESH,SURFACE,DRAW,SPECIALIZATION}`. Un compteur `DRAW` non nul en match signale un trou dans la précompilation.

Cas particulier de notre projet :
- `Cartoon.gd` crée beaucoup de `ShaderMaterial` sur le même shader, ce qui ne pose pas de problème : un même shader avec des uniforms différents donne un seul pipeline.
- Chaque `next_pass` de contour est un shader à part (`cull_front`, `unshaded`), avec ses propres pipelines.
- Réglages graphiques (SSAO, ombres) : l'appliquer dans le menu, puis préchauffer au prochain chargement.

## C3. LOD, occlusion, visibility ranges

| Outil | Coût | Quand | Règle compétitive |
|---|---|---|---|
| **LOD auto de mesh** (généré à l'import, `lod_bias`) | Quasi nul | Toujours actif. Nos props bas-poly en profitent peu, les persos et les têtes IA davantage | Ne jamais changer la **silhouette d'un couvert** : collision et visuel doivent rester alignés |
| **Visibility ranges / HLOD** (begin/end, marges, fade Disabled/Self/Dependencies) ([doc](https://docs.godotengine.org/en/stable/tutorials/3d/visibility_ranges.html)) | Faible ; le fade alpha coûte plus que la bascule franche | Petit décor sans rôle en jeu : bouteilles, câbles, déchets, panneaux lointains | **Jamais** sur un objet qui bloque la vue ou les tirs. Fade `Disabled` avec hystérésis (moins cher, pas de transparence) |
| **Occlusion culling** (raster CPU via Embree, `OccluderInstance3D` cuit) ([doc](https://docs.godotengine.org/en/stable/tutorials/3d/occlusion_culling.html)) | Coût CPU ; gain **modeste en Forward+** grâce à la prépasse de profondeur | À mesurer seulement sur Cargo Ship (murs de conteneurs) ; inutile sur Wasteland, qui est ouvert | Exclure les objets dynamiques de la cuisson ; ne pas déplacer les occluders |
| **MultiMeshInstance3D** | 1 draw pour N instances | Clôtures, sacs de sable, rivets, poteaux, conteneurs identiques | Les MultiMesh ne sont pas cuits comme occluders ([forum](https://forum.godotengine.org/t/using-occluderinstance3d-with-multimeshinstance3d/42698)) |

## C4. Éclairage pour un jeu stylisé

| Option | Coût GPU | Qualité pour du stylisé | Steam Deck | Verdict |
|---|---|---|---|---|
| Soleil directionnel + ambiant du ciel + AO en couleurs de sommet | Le plus bas | Aplats nets, maîtrisés | Oui | **Base actuelle**, à garder comme préréglage bas |
| **LightmapGI** (indirect cuit, soleil en **Dynamic**, shadowmask **Replace** pour les ombres lointaines, sondes `LightmapProbe` pour les persos) ([doc](https://docs.godotengine.org/en/stable/tutorials/3d/global_illumination/using_lightmap_gi.html)) | Bas à l'exécution (texture) ; cuisson GPU hors ligne | Rebonds chauds sous les auvents, coins sombres « peints » | Oui | **Cible P3.4**. Il faut une UV2 : import « Light Baking : Static Lightmaps » avec texel size, ou UV2 faite dans Blender (`stylekit`) |
| SDFGI | Élevé | Fuites de lumière, instabilité en mouvement | Non (déjà exclu en P3.7) | Non |
| VoxelGI | Moyen à élevé | Bon en intérieur | Limite | Non |
| SSAO / SSIL | Passe normales/rugosité + effet | SSAO assombrit les aplats de façon non uniforme | À couper | Remplacer par l'AO cuit (sommets ou lightmap). SSAO devient une option |

Règle Valorant reprise en P3.4 : **aucun réglage graphique ne doit donner plus d'information**. Les ombres des joueurs doivent être identiques partout, ou absentes partout. Avec LightmapGI, le décor statique a ses ombres cuites (shadowmask). Les ombres dynamiques des joueurs sont un choix de design à trancher, et la même valeur s'applique à tous les préréglages.

## C5. Budgets de perf (shooter compétitif 144+ fps)

| Poste | Budget proposé (1080p, config recommandée) | Référence actuelle (`docs/PERF.md`, avant l'art pass) |
|---|---|---|
| Temps de frame | ≤ 6,9 ms (144 fps) ; p99 ≤ 9 ms ; 1 % low ≥ 110 fps | 274,8 fps moyen, 1 % low 180, p99 5,56 ms |
| GPU | ≤ 5,5 ms | — |
| CPU (thread principal + physique) | ≤ 4 ms, dont netfox ≤ 1 ms | — |
| Draw calls | ≤ 1 500 visibles (contours compris) | 65 |
| Triangles visibles | ≤ 2 M | — |
| Perso | ≤ 15k tris × 2 à 3 passes (toon + coques) ; 8 persos visibles ≈ 48 draws | — |
| Post-process (encre + AA) | ≤ 0,8 ms au total | — |
| Steam Deck | 60 fps en 800p, FSR 1 à 0,75, sans SSR/SSIL/SDFGI (P3.7) | — |

Méthode : la scène `benchmark.tscn` existe déjà. Il faut y ajouter les moniteurs de pipelines et un **seuil d'échec** (par exemple, un p99 au-dessus du budget fait échouer la CI), et relancer après chaque lot d'assets.

## C6. Netcode

**État du projet** : ENet et API haut niveau. Mouvement **autoritatif côté client**, répliqué par `MultiplayerSynchronizer` (`scenes/player/player.tscn`). RPC fiables pour les stats et le killfeed. Tick physique par défaut à 60 Hz (`docs/MULTIPLAYER.md`).

| Sujet | Constat | Recommandation |
|---|---|---|
| **netfox** | MIT, v1.35.3 du 23/11/2025, commits actifs jusqu'au 20/09/2026 ([releases](https://github.com/foxssake/netfox/releases), [docs](https://foxssake.github.io/netfox/latest/)). Fournit `RollbackSynchronizer` (prédiction + réconciliation), `TickInterpolator`, `RewindableAction`, physique avec rollback, simulation de réseau dégradé, input delay, filtre de visibilité, `RollbackSynchronizer` sans input pour les bots, `NetworkWeaponHitscan3D` (extras). La doc dit « Godot 4.x supported », sans mention explicite de 4.7 | Faire le spike P1 **sur 4.7.2** : 8 joueurs + bots, mesure du CPU du rollback en GDScript, tir hitscan rembobiné |
| `MultiplayerSynchronizer` | `replication_interval`, `delta_interval`, filtres de visibilité ; **ni prédiction, ni réconciliation, ni compensation de lag** | À garder pour l'état non critique (score, manche, économie), sortir du mouvement et du tir |
| Tick | Valorant tourne à 128 Hz ([Riot, netcode](https://technology.riotgames.com/news/peeking-valorants-netcode)) ; le coût du rollback croît avec le tick × les joueurs × la profondeur | **60 Hz** pour la simulation et l'envoi au départ, puis 64 ou 128 Hz si le profilage le permet. `physics_ticks_per_second` doit être égal au tick netfox |
| Compensation de lag | Rewind côté serveur à l'instant vu par le tireur | Fenêtre plafonnée à **200 ms** ; au-delà, le tir est refusé. `ShotValidator.gd` existe déjà |
| Transport | ENet (UDP, canaux fiables et non fiables) pour le serveur dédié ; WebRTC seulement pour le navigateur ou le P2P, avec serveur de signalisation ([article 4.0](https://godotengine.org/article/multiplayer-changes-godot-4-0-report-3/)) ; SteamMultiplayerPeer pour le P2P via le relais Steam ([asset](https://godotengine.org/asset-library/asset/2258)) | **ENet** pour les matchs classés et publics. Steam P2P en option pour les parties privées 1v1 ou 2v2 entre amis |
| Serveur dédié | Preset « Linux Server » avec `dedicated_server=true` déjà présent ; modes Strip Visuals / Keep / Remove par ressource ; `OS.has_feature("dedicated_server")` ([doc](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_dedicated_servers.html)) | Vérifier que Strip Visuals est appliqué aux textures, meshes et shaders. Garder les ressources lues par le serveur (collisions, navmesh) |

## C7. Steam, hébergement, anti-triche

- **GodotSteam** : avec Godot 4.7.2, le module et la GDExtension ont fusionné (les branches séparées sont retirées) ; versions **GodotSteam 4.21** et **GodotSteam Server 4.10** ([blog 2026](https://godotsteam.com/blog/archive/2026/), [Asset Store](https://store.godotengine.org/asset/godotsteam/godotsteam-gdextension/)). Pour l'authentification : le client envoie un ticket Steam, validé côté serveur (GodotSteam Server) ou par Nakama (authentification Steam), jamais cru sur parole.
- **Hébergement** :
  - Edgegap coûte **0,00115 $/min par vCPU** (≈ 0,069 $/h), plus 0,10 $/Go de sortie. Essai gratuit : 1,5 vCPU, 1 déploiement, 60 min maximum ([tarifs](https://edgegap.com/resources/pricing), [calculateur](https://edgegap.com/resources/pricing/calculator)).
  - Un match 4v4 à 1 vCPU pendant 30 min coûte environ 0,035 $.
  - Dokploy reste le premier palier (ROADMAP §5).
- **Nakama** : nakama-godot est en Apache-2.0. Commits actifs en septembre 2026, mais dernière release taguée en v3.4.0 (03/2024) : épingler un commit et tester sur 4.7.
- **Anti-triche, bases pour un serveur autoritatif** :
  1. Le client n'envoie que des **inputs** (netfox), jamais des positions ou des dégâts.
  2. Validation des entrées : vitesse de visée, cadence (`RateLimiter.gd` et `FireClock.gd` existent), portée, ligne de vue.
  3. **Filtre de visibilité** : ne pas envoyer la position d'un ennemi hors de vue, avec une marge juste avant le contact visuel. C'est le principe du fog of war de Valorant ([Riot](https://technology.riotgames.com/news/demolishing-wallhacks-valorants-fog-war)) ; netfox fournit le filtre, à nous le calcul de visibilité.
  4. Rien de secret dans le client : `gdsdecomp` reconstruit le projet (déjà en ROADMAP §5).
  5. Signalements, replays et télémétrie côté serveur.
  6. Plus tard, **EAC via EOS** : le plugin communautaire EOSG est en MIT, v2.3.1 du 15/09/2026 ([repo](https://github.com/3ddelano/epic-online-services-godot)). Son code référence les interfaces AntiCheat, mais la couverture reste à vérifier. EAC est gratuit avec EOS ([Epic](https://dev.epicgames.com/docs/epic-online-services/trust-and-safety/anti-cheat-interfaces/anti-cheat-interfaces)).

## C8. Addons Godot 4 utiles

État relevé via l'API GitHub le 23/09/2026.

| Addon | Licence | Version / état | Compat 4.7 | Usage chez nous |
|---|---|---|---|---|
| **netfox** | MIT | v1.35.3 (11/2025), push 20/09/2026 | « 4.x », à valider au spike | Netcode P1 |
| **GodotSteam** | MIT | 4.21 / Server 4.10 | Oui (4.7.2) | Steam, auth, voix |
| **gdUnit4** | MIT | v6.2.1 (20/08/2026) | Oui (déjà installé) | Tests |
| **LimboAI** | MIT | v1.8.1 (20/08/2026) | GDExtension, à vérifier | Arbres de comportement et HSM pour les bots (`scripts/ai/*` aujourd'hui fait maison) |
| Beehave | MIT | v2.9.3 (18/08/2026) | GDScript pur | Alternative plus légère à LimboAI |
| Phantom Camera | MIT | v0.11.0.3 (19/07/2026) | Oui | Caméras de menu, killcam, spectateur ; **pas** la caméra FPS |
| sentry-godot | MIT | 2.2.0 (15/09/2026) | 4.5+ | Crashs (ROADMAP §5) |
| nakama-godot | Apache-2.0 | v3.4.0 (03/2024), commits 09/2026 | À tester | Comptes, matchmaking |
| godot_debug_draw_3d | Licence propre (GitHub : « Other ») | 1.7.3 (04/2026) | À vérifier | Debug des hitboxes et du rewind ; **outil de dev, non livré** |
| EOSG | MIT | 2.3.1 (15/09/2026) | 4.3+ | EAC plus tard |
| blender-mcp / godot-mcp | MIT | Voir 06 | — | Non retenus en production |

---

## Tableau comparatif (synthèse des choix techniques)

| Sujet | Option retenue | Licence | UE OK ? | AMD/Windows ? | Coût | Qualité pour du stylisé |
|---|---|---|---|---|---|---|
| Contour des persos | Coque inversée + normales lissées + stencil ennemi | Moteur MIT | Oui | Oui (D3D12, Vulkan) | 1-2 draws par surface | ★★★★ |
| Contour du décor | CompositorEffect profondeur + normales | MIT | Oui | Oui | ≈ 0,3-0,6 ms (à mesurer) | ★★★ |
| Stutter | Ubershaders + shader baker + préchauffage | MIT | Oui | Oui | 0 | — |
| Éclairage | LightmapGI (soleil Dynamic) + AO cuit | MIT | Oui | Cuisson GPU AMD OK ; denoiser JNLM | Temps de cuisson | ★★★★ |
| AA | SMAA 1x | MIT | Oui | Oui | ≈ 0,2-0,4 ms | ★★★ (pas de flou sur l'encre) |
| Netcode | netfox | MIT | Oui | Oui | 0 | — |
| Serveurs | Dokploy puis Edgegap | Service | Oui (régions UE) | — | ≈ 0,07 $/vCPU·h | — |
| Anti-triche | Autorité serveur + filtre de visibilité, puis EAC | Maison + EOS | Oui | Oui | 0 | — |

---

## Écarts avec notre projet

| Fichier | Constat | Action |
|---|---|---|
| `export_presets.cfg` (l. 32, 92, 132) | `shader_baker/enabled=false` sur Windows, Linux et Linux Server | L'activer sur les presets client (Windows D3D12 surtout) ; inutile sur le serveur headless |
| `project.godot` `[rendering]` | Seulement `driver.windows="d3d12"` (défaut 4.6+ de toute façon) ; **aucun AA**, aucun réglage d'occlusion culling, aucun tick physique explicite | Définir AA (SMAA), `physics/common/physics_ticks_per_second` aligné sur netfox, et l'occlusion culling seulement si la mesure le justifie |
| `assets/shaders/ink_outline.gdshader` | Extrude selon `NORMAL` alors que les props et armes sont en facettes (`use_smooth=False`) | Lire la normale lissée (`CUSTOM0` ou `TANGENT`) produite par `stylekit` (06, A3D-02) |
| `scripts/core/Cartoon.gd` (`character()`, l. 301-308) | Contour ennemi = **2 coques** (couleur + encre) sur chaque surface, soit 3 passes | Stencil : écriture dans `ink_toon`, lecture dans une coque unique bicolore. Moins de draws, pas de coque interne |
| `scripts/core/InkPost.gd` + `assets/shaders/ink_edges.gdshader` | Quad dans la passe transparente ; correctifs d'ordre et de caméra empilés | Prototype en `CompositorEffect` post-opaque ; comparer ms et rendu avec `benchmark.tscn` |
| `scripts/core/LevelLook.gd` (l. 128-131) | `ssao_enabled = true` en dur | En faire une option, préchauffée, et privilégier l'AO cuit. Même valeur pour tous en classé si elle change la lisibilité |
| `scripts/core/LevelLook.gd` | Soleil avec `shadow_enabled` ; pas de LightmapGI | P3.4 : LightmapGI avec soleil en `BAKE_DYNAMIC`, shadowmask Replace, sondes pour les persos |
| `scripts/core/PerfOverlay.gd`, `scripts/levels/Benchmark.gd` | Pas de moniteurs de compilation de pipelines | Ajouter les 5 compteurs `PIPELINE_COMPILATIONS_*` ; faire échouer le benchmark si `DRAW > 0` pendant la mesure |
| `scripts/levels/maps/dressing/*.gd` | Props posés en instances individuelles | MultiMesh pour les répétitions, visibility ranges pour le décor qui ne sert pas de couvert |
| `scenes/player/player.tscn`, `scripts/player/PlayerController.gd`, `scripts/networking/*` | Mouvement autoritatif client via `MultiplayerSynchronizer` | Spike netfox (P1) puis migration ; filtre de visibilité |
| `scripts/combat/ShotValidator.gd` | Validation présente, mais sans rewind historique | Rewind par historique netfox, fenêtre ≤ 200 ms |

---

## Tâches

```
- id: TECH-01
  title: Activer le shader baker et préchauffer pipelines et effets au chargement de carte
  files: [export_presets.cfg, scripts/core/ShaderWarmup.gd, scripts/levels/maps/MapSetup.gd]
  depends_on: []
  size: M
  acceptance: shader_baker/enabled=true sur les presets Windows et Linux client ; au chargement, ShaderWarmup instancie invisibles tous les matériaux Cartoon (toon, coques, painted par kind) et les VFX, pendant au moins 2 frames ; en match, le moniteur PIPELINE_COMPILATIONS_DRAW reste à 0 sur benchmark.tscn

- id: TECH-02
  title: Moniteurs de compilation de pipelines dans l'overlay F3 et seuils d'échec du benchmark
  files: [scripts/core/PerfOverlay.gd, scripts/levels/Benchmark.gd, docs/PERF.md]
  depends_on: []
  size: S
  acceptance: F3 affiche CANVAS/MESH/SURFACE/DRAW/SPECIALIZATION ; le JSON du benchmark contient ces compteurs ; le benchmark sort en code 1 si p99 > 9 ms ou si DRAW > 0 pendant la mesure (seuils lus dans un const documenté)

- id: TECH-03
  title: Contour en coque sur normales lissées (statique CUSTOM0, skinné TANGENT)
  files: [assets/shaders/ink_outline.gdshader, scripts/core/Cartoon.gd, tests/rendering/test_outline_normals.gd]
  depends_on: [A3D-02]
  size: M
  acceptance: ink_outline extrude selon la normale lissée quand l'attribut existe, sinon selon NORMAL ; prop_shots et fp_shots ne montrent plus de fente aux arêtes vives (avant/après dans reports/) ; le test vérifie qu'un GLB stylekit expose l'attribut

- id: TECH-04
  title: Contour ennemi au stencil (coque unique, pas de coque interne, jamais d'X-ray)
  files: [assets/shaders/ink_toon.gdshader, assets/shaders/ink_outline.gdshader, scripts/core/Cartoon.gd, tests/rendering/test_enemy_outline.gd]
  depends_on: [TECH-03]
  size: M
  acceptance: un ennemi coûte au plus 2 passes au lieu de 3 ; le contour magenta ou citron n'apparaît que hors de la silhouette visible ; un ennemi derrière un mur n'a AUCUN pixel de contour visible (test de capture) ; draw calls du benchmark ≤ ceux d'avant

- id: TECH-05
  title: Encre du décor en CompositorEffect post-opaque (profondeur + normales), comparée au quad actuel
  files: [scripts/core/InkCompositor.gd, assets/shaders/ink_edges_compute.glsl, scripts/core/InkPost.gd, scripts/core/LevelLook.gd]
  depends_on: [TECH-02]
  size: L
  acceptance: rendu équivalent sur map_shots (largeur 4 px à 10 m, 1,5 px à 60 m, plancher d'opacité 40 %) ; Label3D, traceurs et flashs restent visibles sans correctif d'ordre ; coût mesuré ≤ celui du quad actuel en 1080p ; on garde la variante la moins chère, décision écrite dans docs/PERF.md

- id: TECH-06
  title: Anticrénelage SMAA et SSAO en option, avec préréglages graphiques (dont Steam Deck)
  files: [project.godot, scripts/core/Settings.gd, scripts/core/LevelLook.gd, tests/core/test_graphics_presets.gd]
  depends_on: [TECH-01]
  size: M
  acceptance: SMAA 1x par défaut, TAA indisponible ; SSAO désactivable dans le menu seulement (jamais en match) ; préréglages Bas/Recommandé/Steam Deck (FSR 1 à 0,75, sans SSR/SSIL/SDFGI) ; aucun préréglage ne change les ombres des joueurs

- id: TECH-07
  title: LightmapGI stylisé (soleil BAKE_DYNAMIC, shadowmask Replace, sondes pour les persos, UV2)
  files: [scripts/core/LevelLook.gd, scripts/levels/maps/MapSetup.gd, docs/PERF.md]
  depends_on: [A3D-03]
  size: L
  acceptance: sur Wasteland et Cargo Ship, la cuisson passe sur la machine AMD ; les bandes toon restent visibles au soleil (light() toujours appelé) ; rebond chaud visible sous les auvents ; perso éclairé par les sondes sans saut de luminosité ; perf ≥ budget C5

- id: TECH-08
  title: LOD, visibility ranges et MultiMesh pour le dressing (jamais sur un couvert)
  files: [scripts/levels/maps/dressing/MapDressing.gd, scripts/levels/maps/PropCatalog.gd, tests/maps/test_dressing_lod.gd]
  depends_on: []
  size: M
  acceptance: PropCatalog marque chaque prop « cover » ou « decor » ; seuls les « decor » reçoivent une visibility range (fade Disabled + hystérésis) ; les répétitions de plus de 8 exemplaires passent en MultiMesh ; les draw calls du benchmark baissent ; le test échoue si un prop « cover » a une visibility range

- id: TECH-09
  title: Occlusion culling sur Cargo Ship seulement, gardé si la mesure le justifie
  files: [project.godot, scripts/levels/maps/MapSetup.gd, docs/PERF.md]
  depends_on: [TECH-02, TECH-08]
  size: S
  acceptance: mesure avant/après sur Cargo Ship ; gardé seulement si le gain GPU ou le nombre d'objets dépasse 10 % sans coût CPU supérieur à 0,3 ms ; sinon retiré, avec les chiffres dans docs/PERF.md

- id: TECH-10
  title: Spike netfox sur Godot 4.7.2 (rollback du mouvement, tir hitscan rembobiné, 8 joueurs + bots)
  files: [addons/netfox/, scripts/player/PlayerController.gd, scripts/player/PlayerInput.gd, scripts/networking/NetworkManager.gd, tests/networking/test_netfox_spike.gd, THIRD_PARTY_LICENSES.md]
  depends_on: []
  size: L
  acceptance: 60 Hz de simulation, physics_ticks_per_second aligné ; avec 100 ms de latence et 2 % de pertes (simulateur netfox), le joueur local n'a aucun à-coup visible et le serveur reste autoritatif ; CPU netfox ≤ 1 ms par frame en client ; tir rembobiné refusé au-delà de 200 ms ; go ou no-go écrit dans docs/MULTIPLAYER.md

- id: TECH-11
  title: Filtre de visibilité anti-wallhack (fog of war serveur)
  files: [scripts/networking/VisibilityFilter.gd, scripts/networking/GameWorld.gd, tests/networking/test_visibility_filter.gd]
  depends_on: [TECH-10]
  size: M
  acceptance: le serveur n'envoie pas l'état d'un ennemi sans ligne de vue potentielle (plusieurs points de la capsule, marge d'anticipation ≥ 1 tick à vitesse max) ; le test prouve qu'un client derrière un conteneur ne reçoit aucune position ennemie ; aucun « pop » visible en jeu à 100 ms de latence

- id: TECH-12
  title: Préparer l'auth Steam côté serveur et épingler GodotSteam et Nakama pour 4.7.2
  files: [scripts/networking/SteamAuth.gd, scripts/networking/NetworkManager.gd, docs/SERVER.md, THIRD_PARTY_LICENSES.md]
  depends_on: [TECH-10]
  size: M
  acceptance: le client envoie un ticket Steam au handshake ; le serveur (GodotSteam Server 4.10) ou Nakama le valide avant l'entrée en jeu ; refus propre si le ticket est invalide ; versions GodotSteam 4.21 et Server 4.10 et commit nakama-godot épinglés et listés dans THIRD_PARTY_LICENSES.md
```
