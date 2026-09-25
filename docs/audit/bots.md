# Audit des bots — pourquoi ils sont nuls

Date : 2026-09-23
Périmètre : `scripts/ai/BotBrain.gd`, `scripts/ai/BotReaction.gd`,
`scripts/ai/BotTargetSelect.gd`, `scripts/ai/BotNavMesh.gd`, et leurs points
d'ancrage dans `scripts/networking/GameWorld.gd`, `scripts/player/*`,
`scripts/agents/*`, `scripts/modes/*`.

Plainte joueur : « les bots sont nuls ». Ce document explique, axe par axe,
avec fichier:ligne, ce que les bots font réellement (pas ce que leur nom
suggère), puis donne une liste de correctifs priorisés.

Méthode : lecture complète de `BotBrain.gd`/`BotReaction.gd`/
`BotTargetSelect.gd`/`BotNavMesh.gd` (+ points d'ancrage dans `GameWorld.gd`,
`PlayerController.gd`, `AbilityController.gd`, `scripts/modes/*`), croisée
avec `docs/research/02_bots_ai.md` (recherche du 23/09, déjà très détaillée,
sourcée jeux de référence — CS bot/Killzone/Halo Infinite/BotPrize — et déjà
outillée de tâches **BOT-01 à BOT-13**), plus une revue dynamique (`tools/bot_smoke.gd`
en headless, TDM 4v4 hôte+7 bots Vétéran, 120 s). Les deux lectures
convergent sur les mêmes fichier:ligne — bon signe de fiabilité du
diagnostic. **Ce document ne reformule PAS `02_bots_ai.md` en détail : il
renvoie vers ses BOT-xx pour tout ce qu'il couvre déjà**, et n'ajoute des
tâches `BOTFIX-xx` que pour des bugs concrets qu'il ne couvre pas.

## Diagnostic par axe (renvoi vers `02_bots_ai.md` quand déjà couvert)

1. **Perception** — réelle (pas de wall-hack) : cône 100° + portée 45 m +
   raycast LOS (`BotBrain.gd:102-140`), ouïe sur `Weapon.recent_gunfire`
   (`BotBrain.gd:145-157`). Mais LOS testée sur un seul point (la tête) et
   aucune perception des dégâts reçus (angle mort dans le dos jamais
   corrigé) → déjà chiffré et tâché en **BOT-03** (`02_bots_ai.md` §4.6,
   4.8-4.9).
2. **Réaction / visée** — le délai de réaction et l'érosion de l'erreur
   (τ=0.8 s) sont bien exercés, pas morts (`BotBrain.gd:169-213`), mais
   l'erreur est retirée à CHAQUE frame et exprimée en mètres fixes plutôt
   qu'en angle régénéré périodiquement, et `AIM_TURN_RATE` (`BotBrain.gd:29`)
   est un plafond linéaire identique à toutes les difficultés → déjà
   chiffré et tâché en **BOT-02** (`02_bots_ai.md` §4.3-4.4, table §3).
3. **Mouvement** — navmesh réelle (`NavigationAgent3D`, `BotNavMesh.gd`),
   mais objectif ré-tiré au hasard toutes les 0.5 s en TDM/SnD (wall-hack
   caché de fait) → **BOT-01** ; pas d'anti-blocage/évitement
   (`avoidance_enabled = false`, `BotBrain.gd:62`) → **BOT-09**. **Non
   couvert par `02_bots_ai.md`** : un bot qui ARRIVE à un objectif fixe (zone
   Hardpoint, site SnD) et n'a aucune cible arrête complètement de tourner la
   tête — `move_world_dir` reste `Vector3.ZERO` (`BotBrain.gd:262-269`) et
   `_face_direction` n'est jamais appelé qu'avec ce même vecteur nul hors
   combat (`BotBrain.gd:271-275`) : le bot devient une statue qui fixe une
   direction arbitraire au lieu de scanner. Voir BOTFIX-01 ci-dessous.
4. **Ciblage** — plus proche visible, avec un bon anti-oscillation (cible
   collante tant qu'elle reste visible, `BotBrain.gd:162-178`) ; pas de
   pondération menace/PV → **BOT-06/BOT-07** (position/utility).
5. **Capacités** — bots utilisent le VRAI pipeline serveur
   (`AbilityController._server_activate`, mêmes vérifications que
   l'humain), mais le déclenchement est un tirage 0.2 %/tick sans aucune
   condition (`BotBrain.gd:353-361`) → déjà chiffré et tâché en **BOT-10**.
   **Non couvert** : pendant qu'un bot pose/désamorce la bombe
   (`bot_set_holding()`, `BotBrain.gd:331-332` → `SnDMode.gd:391-396`), il
   n'écrit jamais `player.input.pickup_held` — lu par
   `PlayerController.gd:239` pour l'animation d'interaction — donc le bot
   plante/désamorce sans jouer l'animation correspondante (juste
   cosmétique, mais très visible). Voir BOTFIX-02.
6. **Économie** — le bot achète, mais toujours `default_loadout_ids()[0]`
   (le fusil de départ), rachète même s'il le possède déjà → déjà chiffré
   et tâché en **BOT-12**.
7. **Objectifs** — pose/défuse/capture routés par les mêmes fonctions
   serveur que l'humain (pas de triche), mais aucune coordination d'équipe
   (site choisi au hasard par appel, pas par round) → **BOT-01**/**BOT-08**.
8. **Difficulté** — seulement 2 axes réglés (réaction, erreur de visée),
   tout le reste (perception, vitesse de rotation, capacités, achat) est
   identique Recrue/Vétéran/Élite → déjà chiffré et tâché en **BOT-11**.

**Non couvert, hors `scripts/ai/*` (trouvé en dynamique)** : le bake du
navmesh dans `scripts/levels/maps/MapSetup.gd:28-29,162-163,169-170` fixe
`agent_radius=0.4`/`agent_height=1.8` avec `cell_size=cell_height=0.25` — pas
des multiples entiers (1.6 et 7.2 cellules), donc `bake_navigation_mesh`
arrondit AU-DESSUS (rayon effectif ~0.5 m, hauteur ~2.0 m), confirmé par
`tools/bot_smoke.gd` en headless :
```
WARNING: Property agent_radius is ceiled to cell_size voxel units and loses precision.
WARNING: Property agent_height is ceiled to cell_height voxel units and loses precision.
```
Un bot a donc besoin d'un passage ~25 % plus large/haut que sa vraie capsule
pour que la navmesh le considère franchissable : risque concret d'éviter
des couloirs/portes qu'un joueur humain franchit sans problème. Voir
BOTFIX-03.

**Édge case mineur, non couvert** : `Vector3.ZERO` sert de sentinelle
"aucun objectif" (`GameMode.gd:125-126`, lu par `BotBrain.gd:317-320`) — un
objectif de gameplay légitimement situé pile à l'origine du monde serait
silencieusement traité comme "pas d'objectif". Improbable sur les cartes
actuelles ; à corriger en même temps que BOT-01 (remplacer par une
sentinelle non-coordonnée, ex. `Vector3.INF`) plutôt qu'en tâche séparée.

## Liste de correctifs priorisée

Reprend l'ordre déjà recommandé par `02_bots_ai.md` §1.10
(BOT-01 → BOT-02 → BOT-04 → BOT-03 → BOT-09 → tactique/équipe/reste), en y
insérant les correctifs propres à cet audit :

1. **BOT-01** (objectifs stables/sans omniscience) — le plus gros gain
   perçu, tout mode confondu.
2. **BOTFIX-01** (arrêter de statufier un bot arrivé sur un objectif) — se
   fait naturellement au même endroit que BOT-01/BOT-07 (le remplacement du
   `_current_goal`/comportement idle), coût marginal si fait en même temps.
3. **BOT-02** (modèle de visée humain) puis **BOT-04** (discipline de
   combat) puis **BOT-03** (perception complète, mémoire, dégâts reçus).
4. **BOTFIX-03** (agent_radius/agent_height multiples de cell_size dans
   `MapSetup.gd`) — un correctif d'une ligne (`AGENT_RADIUS=0.5`,
   `AGENT_HEIGHT=2.0`, ou `cell_size=0.2`) avant tout travail de navigation
   plus poussé (BOT-05/06/09), sinon ces tâches hériteraient d'une navmesh
   déjà biaisée.
5. **BOT-09** (anti-blocage/évitement), puis BOT-05 → BOT-08 (tactique et
   équipe), BOT-10 (capacités), BOT-11 (difficulté multi-axes), BOT-12
   (achat), BOT-13 (banc de mesure).
6. **BOTFIX-02** (animation manquante pendant pose/désamorçage bot) —
   cosmétique, à faire quand on touche `BotBrain._tick_objective` pour
   BOT-01/BOT-08, faible coût marginal.

## Tâches

```
- id: BOTFIX-01
  title: "Bot idle : scanner au lieu de figer la direction une fois l'objectif atteint"
  files: [scripts/ai/BotBrain.gd]
  depends_on: []
  size: S
  acceptance: "un bot sans cible visible/entendue qui a atteint son objectif (nav_agent.is_navigation_finished()) balaie lentement le regard (yaw oscillant, ex. ±40° sur quelques secondes) au lieu de rester figé ; ne régresse pas le comportement en combat (aim_held/_face_direction en combat inchangés)."

- id: BOTFIX-02
  title: "Jouer l'animation d'interaction pendant qu'un bot pose/désamorce la bombe"
  files: [scripts/ai/BotBrain.gd, scripts/player/PlayerController.gd]
  depends_on: []
  size: S
  acceptance: "pendant que bot_set_holding(id, true) est actif pour un bot (BotBrain -> SnDMode.gd:391-396), player.input.pickup_held est vrai pour ce bot et PlayerController._update_anim_state (ligne 239) joue l'animation d'interaction, visible en observant le bot depuis un autre joueur."

- id: BOTFIX-03
  title: "Aligner agent_radius/agent_height du bake navmesh sur des multiples de cell_size/cell_height"
  files: [scripts/levels/maps/MapSetup.gd]
  depends_on: []
  size: S
  acceptance: "godot --headless --path . -s res://tools/bot_smoke.gd ne produit plus les WARNING 'ceiled to cell_size/cell_height voxel units and loses precision' ; agent_radius/agent_height restent >= aux valeurs actuelles (jamais un bot qui passe là où un joueur ne passe pas)."
```
