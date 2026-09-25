# Calques de collision — Documentation de référence

Ce document décrit les **calques physiques** (`collision_layer`/`collision_mask`)
utilisés par le jeu, comment Godot les résout réellement (vérifié par des tests
sur une vraie scène bakée, pas seulement lu dans la documentation officielle),
et le calque `PLAYER_CLIP` ajouté par LD-44 (Wasteland v4, §12.3 révisé) pour
les toits bas.

---

## 1. Calques existants (`scripts/core/PhysicsLayers.gd`)

| Calque | Bit | Constante | Rôle |
|---|---|---|---|
| Monde et joueurs | 1 (`1 << 0`) | `PhysicsLayers.WORLD` | Défaut Godot. Toute la collision de `Kit.gd` (murs, sols, bâtiments, rampes, `invisible_wall`…), le calque (`collision_layer`) du corps de joueur/bot (`scenes/player/player.tscn`). |
| Vision | 5 (`1 << 4`) | `PhysicsLayers.VISION` | Objets qui bloquent la **vue** sans bloquer les **corps** (fumée, `SmokeAbility.gd`/`AbilityController.gd`). |
| Anti-joueur (toits) | 6 (`1 << 5`) | `PhysicsLayers.PLAYER_CLIP` | LD-44 : volumes invisibles au-dessus des toits bas (`Kit.roof_clip_volumes`). Heurtés par le corps du joueur/bot, traversés par tout rayon `SHOT_MASK`. Voir §3. |

`PhysicsLayers.SHOT_MASK` = tout sauf `VISION` et `PLAYER_CLIP`
(`0xFFFFFFFF & ~VISION & ~PLAYER_CLIP`) : les rayons de tir (`Weapon.gd`), les
grenades à mèche (`FlashAbility.gd`, `RevealAbility.gd`, `StunBurstAbility.gd`…),
le grappin (`GrappleAbility.gd`) et le ping (`PingController.gd`) l'utilisent
tous — une fumée bloque la vue, un volume `player_clip` bloque le corps du
joueur, ni l'un ni l'autre ne bloque un projectile ou un rayon de collision.

Deux **corps par défaut** dans le jeu ne redéfinissent jamais leur *calque*
(`collision_layer`) :

- le joueur/bot (`CharacterBody3D`, `scenes/player/player.tscn`) : `layer=1`
  (WORLD), jamais touché par aucun script ; son **masque**
  (`collision_mask`), en revanche, vaut `33` (`WORLD | PLAYER_CLIP`, LD-44 —
  voir §3), pour heurter aussi les volumes anti-joueur des toits ;
- toute pièce posée par `Kit.gd` (`box`, `building2`, `stairs`,
  `invisible_wall`…) via `_collision_box` : `layer=1, mask=1` par défaut, sauf
  exception explicite (`roof_clip_volumes`, voir §3).

---

## 2. Comment Godot résout RÉELLEMENT une collision (vérifié par test)

La documentation officielle de Godot décrit une résolution **bidirectionnelle**
(« la collision a lieu si le calque de A correspond au masque de B, OU
l'inverse ») pour la résolution physique générale (deux corps simulés qui se
poussent). **Ce n'est PAS ce qui a été observé** pour les deux mécanismes
utilisés par ce jeu pour interroger le monde (vérifié en isolant chaque cas sur
la vraie scène bakée, `MapSetup`, deux configurations de calque essayées par
cas — voir `tests/maps/test_wasteland.gd` et `tests/maps/test_kit.gd`) :

- **`PhysicsDirectSpaceState3D.intersect_ray`/`intersect_shape`/`intersect_point`**
  (tirs, grenades, grappin, ping, sondes de test) : un objet est touché si
  `requête.collision_mask & objet.collision_layer != 0`. Le **masque propre de
  l'objet visé n'entre jamais en jeu**.
- **`CharacterBody3D.move_and_collide`/`move_and_slide`** (déplacement d'un
  joueur ou d'un bot — la manière dont `PlayerController.gd` bouge le corps) :
  même règle, `corps_qui_bouge.collision_mask & cible.collision_layer != 0`.
  Là aussi, **le masque de la cible n'entre jamais en jeu** : donner un `mask`
  à une cible statique ne suffit PAS à la rendre heurtable par un joueur dont
  le masque n'inclut pas son calque.

Conséquence directe : pour qu'un joueur heurte un volume, ce volume **doit**
être sur un calque que le `collision_mask` du joueur inclut — un `mask` posé
sur la cible seule ne suffit jamais. Avant LD-44, le masque par défaut du
joueur ne contenait que `WORLD`, et `SHOT_MASK` incluait tout sauf `VISION` :
**tout calque qui rendait alors un volume heurtable par le joueur le rendait
aussi visible à `SHOT_MASK`** — sauf `VISION` lui-même, qui n'est heurté par
aucun corps. Un seul calque ne pouvait donc pas être à la fois « heurté par le
joueur » et « invisible à `SHOT_MASK` » sans toucher soit `SHOT_MASK`
(`scripts/core/PhysicsLayers.gd`), soit le masque par défaut du joueur
(`scenes/player/player.tscn`) — précisément les deux changements que LD-44 a
faits pour créer `PLAYER_CLIP` (§3) : le masque du joueur inclut maintenant
`WORLD | PLAYER_CLIP`, et `SHOT_MASK` exclut `PLAYER_CLIP`.

**Exception : `Area3D` (monitoring).** Une zone qui *surveille* (`monitoring =
true`) utilise SON PROPRE `collision_mask` contre le `collision_layer` du
corps survolé — c'est elle qui « regarde », pas le corps qui la scanne. C'est
le mécanisme déjà utilisé par `KillVolume.gd` (`collision_layer = 0,
collision_mask = PhysicsLayers.WORLD`, `body_entered` détecte bien les
joueurs) : une zone peut donc *détecter* un joueur sans que celui-ci ait à
inclure quoi que ce soit dans son propre masque. Elle ne *bloque* rien par
elle-même (ce n'est pas un solide) : il faudrait une réaction scriptée
(pousser le corps, annuler sa vitesse) pour en faire un mur — hors du
périmètre de cette tâche (voir §4).

---

## 3. `player_clip` (LD-44, Wasteland v4 §12.3 révisé)

Décision utilisateur (2026-09-25) : les toits passent de 60° (faîte jusqu'à
20,3 m sur les Saloons, cachant le château d'eau et la silhouette de la ville)
à des toits **bas** (25-30°, `Kit.ROOF_PITCH_DEG`), faîte plafonnée à la
corniche + 3 m (`Kit.ROOF_MAX_RISE`, `Kit.roof_ridge_rise`). Un pan à 25-30°
est **sous** `MapSetup.AGENT_MAX_SLOPE` (46°) — Recast peut donc désormais
inclure le toit dans le bake, contrairement à l'ancien pan à 60° (LD-40) —
d'où le besoin d'un volume anti-joueur.

`Kit.roof_clip_boxes`/`Kit.roof_clip_volumes` posent, pour chaque `building2`
à toit à versants, deux volumes (un par pan, sud et nord) qui collent
**exactement** à la surface du toit (mêmes points d'avant-toit/faîtage que
`pitched_roof_boxes`, aucun jeu) et s'étendent de `Kit.ROOF_CLIP_HEIGHT`
(12 m, mesurés perpendiculairement à la pente — donc toujours ≥ 12 m de
hauteur verticale réelle) vers le haut. Collision seule, jamais de visuel
(comme `invisible_wall`).

**Calque retenu : `layer = mask = PhysicsLayers.PLAYER_CLIP`** (bit dédié,
JAMAIS `WORLD`) — voir §1. Conséquence (§2) :

| Exigence de la décision | Statut |
|---|---|
| Heurté par les joueurs et les bots (aucun toit atteignable, saut/grappin/planeur) | **Fait**, vérifié par un `CharacterBody3D.move_and_collide` réel sur la scène bakée (`tests/maps/test_wasteland.gd::test_no_roof_point_is_physically_reachable_by_a_moving_player_body`) |
| Faîte ≤ corniche + 3 m | **Fait** (`tests/maps/test_wasteland.gd::test_every_pitched_roof_ridge_stays_within_3m_of_its_cornice`, `tests/maps/test_kit.gd`) |
| Aucun chemin de navmesh n'atteint un toit | **Fait** (`tests/maps/test_wasteland.gd::test_no_navmesh_path_reaches_a_roof_ridge`) |
| Traversé par les tirs/grenades/capacités de lancer (`SHOT_MASK`) | **Fait** (`tests/maps/test_wasteland.gd::test_a_shot_ray_passes_through_the_roof_clip_volume`) |

### Résolution (décision lead 2026-09-25)

Le blocage initial de LD-44 (rendu de tâche, `blocked_on`) tenait à ce que le
calque `WORLD` rendait le volume `player_clip` **aussi** solide pour
`SHOT_MASK`. Le lead a tranché les deux points hors périmètre initial et a
élargi la liste de fichiers de LD-44 pour les appliquer, DANS CET ORDRE :

1. **`scripts/core/PhysicsLayers.gd`** : nouvelle constante dédiée
   `const PLAYER_CLIP := 1 << 5`, exclue de `SHOT_MASK`
   (`const SHOT_MASK := 0xFFFFFFFF & ~VISION & ~PLAYER_CLIP`).
2. **Le masque par défaut du joueur** (`scenes/player/player.tscn`, nœud
   `Player`) inclut désormais ce bit en plus de `WORLD` :
   `collision_layer = 1`, `collision_mask = 33` (`WORLD | PLAYER_CLIP`) —
   sinon le joueur ne heurterait plus `player_clip` du tout (§2 : c'est le
   masque du CORPS QUI BOUGE qui compte, jamais celui de la cible). Aucun
   script ne réécrit ce masque à l'exécution (`scripts/player/` ne touche
   jamais `collision_layer`/`collision_mask`) : la valeur de la scène est la
   valeur réelle en jeu, pour un joueur comme pour un bot (même scène).

Avec ces deux points tranchés, `Kit.roof_clip_volumes` passe désormais
`layer = mask = PhysicsLayers.PLAYER_CLIP` (au lieu de `WORLD`) —
`Kit.roof_clip_volumes`/`roof_clip_boxes` acceptaient déjà `layer`/`mask` via
`_collision_box` (signature additive), donc ce changement ne touche aucune
autre pièce du kit : `Kit.invisible_wall` (barrières Duel/Duo, périmètre de
carte) reste sur `WORLD` par défaut, inchangé.

Le comportement complet de la décision est donc en place : un volume
`player_clip` arrête le corps d'un joueur ou d'un bot (saut, grappin simulé,
planeur — un déplacement, toujours arrêté par une collision réelle) mais
laisse passer un rayon `SHOT_MASK` (tir, grenade à mèche, grappin visé,
capacité de lancer), vérifié par les deux tests physiques réels de
`tests/maps/test_wasteland.gd` cités ci-dessus.
