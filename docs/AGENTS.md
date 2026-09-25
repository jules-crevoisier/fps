# Agents & capacités (hero-shooter)

Système de classes façon Valorant : chaque **agent** a un **passif** (toujours
actif, sans touche) et un jeu de **capacités** à touche (C / Q / E **signature**
+ **ultime** X), avec cooldowns, charges et points d'ultime. 6 agents, 3 rôles
(**Entrée**, **Contrôle**, **Soutien**) x 2, tous server-autoritaires
(contract-p0.md, contract-r2.md §R-B3). Depuis AGT-09 (docs/research/
10_ammo_kits_input.md §3.3), **chaque agent porte une capacité E qu'aucun autre
n'a** (« signature ») : les primitives partagées (mur/fumée/tremplin/piège)
restent sur C/Q/X.

---

## Architecture

```
scripts/agents/
├── Ability.gd              # capacité de base (métadonnées + activate_local/activate_server)
├── AbilityState.gd         # état pur (charges/cooldown/ultime), testé isolément
├── AbilityController.gd    # composant joueur : input, réseau, objets répliqués, effets ciblés, passif, statuts
├── AgentConfig.gd          # un agent : nom, rôle, couleur, passif, liste de capacités
├── AgentDatabase.gd        # catalogue des 6 agents + agent sélectionné
├── AimValidator.gd         # validation pure d'aim_dir (fini, normalisé)
├── AssistTracker.gd        # assistance pure (>= 40 dégâts dans les 5 s avant la mort)
├── FacingCheck.gd          # cône de vue pur (yaw du corps) — utilisé par Éblouissement
├── OutOfCombatTracker.gd   # suivi pur "hors-combat" (soin de base)
├── Passive.gd              # passif de base (Resource) : hooks on_spawn/on_kill/on_assist/
│                            # modify_cc_duration/spread_mult/on_air, tous no-op par défaut
├── StatusEffects.gd        # statuts purs (vitesse, verrou de saut, multiplicateur de contrôle), autorité serveur
├── TargetSelect.gd         # sélection de cibles pure (rayon, équipe)
├── passives/                # passifs concrets (héritent de Passive), un par agent
│   ├── MecheCourte.gd       # Vif    — charge de Ruée + vitesse sur élimination/assistance
│   ├── TeteDeCloche.gd      # Choc   — -40 % de durée des contrôles subis
│   ├── Releve.gd            # Vanne  — marque l'ennemi qui tire dans un de ses murs
│   ├── Planeur.gd           # Guet   — vol plané (Saut maintenu en l'air)
│   ├── BaumeAuRepos.gd      # Roseau — régénération de base plus rapide et généreuse
│   └── SangFroid.gd         # Verrou — dispersion/recul réduits immobile ou accroupi
└── abilities/               # capacités concrètes (héritent d'Ability)
    ├── DashAbility.gd       # mouvement (Ruée / Piquet de Vanne)
    ├── HealAbility.gd       # soin conditionnel de base (RPC serveur, hors-combat)
    ├── WallAbility.gd       # mur temporaire répliqué (Mur d'assaut / Mur / Rempart / Forteresse)
    ├── SmokeAbility.gd      # sphère de fumée opaque répliquée (Fumée / Rideau / Brume)
    ├── JumpPadAbility.gd    # tremplin répliqué (Poste avancé / Passerelle)
    ├── StunTrapAbility.gd   # piège étourdissant répliqué, détection serveur seule (Piège-choc)
    ├── FlashAbility.gd      # éblouissement : mèche 0,3 s puis LOS + face au corps, ciblé serveur
    ├── RevealAbility.gd     # reveal en zone, marqueurs "!" envoyés à l'équipe (+ délai de vol/avertissement optionnels)
    ├── BellChargeAbility.gd # SIGNATURE Choc  : Tape-la-cloche — charge d'épaule, étourdit/repousse ou s'auto-étourdit contre un mur
    ├── FauxDepartAbility.gd # SIGNATURE Vif   : Faux départ — pose une braise, un second appui y ramène instantanément
    ├── GrappleAbility.gd    # SIGNATURE Vanne : Piquet d'arpenteur — grappin, ancrage décor seul, jamais un joueur
    ├── GlueAbility.gd       # SIGNATURE Verrou: Glu — plaque collante persistante, ralentit plusieurs victimes à la fois
    ├── BalmZoneAbility.gd   # SIGNATURE Roseau: Baume du Palud — zone de soin D'ÉQUIPE (premier soin d'alliés du jeu)
    ├── StunBurstAbility.gd  # ULTIME Choc  : étourdissement instantané en zone, armement 0,4 s (Déferlante)
    ├── RenewalAbility.gd    # ULTIME Roseau: soin total D'ÉQUIPE (<= 10 m) + reveal (Sursaut)
    ├── BastionAbility.gd    # ULTIME Verrou: mur + Glu combinés au même endroit (Bastion)
    └── SurgeAbility.gd      # ULTIME Vif   : soin total + bond (Résurgence)
```

- **`Ability`** : `slot` (C/Q/E/X), `display_name`, `description`, `cooldown`,
  `charges`, `is_ultimate`, `ult_cost`, `can_activate_server(player)` (condition
  serveur additionnelle, ex. hors-combat), `activate_local(player)` et
  `activate_server(player, aim_dir)`.
- **`Passive`** (Resource, `AgentConfig.passive`, `null` = agent sans passif —
  repli sûr partout) : capacité TOUJOURS active, sans touche ni cooldown.
  Hooks : `on_spawn(player)` (une fois par vie), `on_kill(player, victim_id)` /
  `on_assist(player, victim_id)` (élimination/assistance), `modify_cc_duration(d)`
  (multiplicateur de durée de contrôle SUBI), `spread_mult(player)`
  (multiplicateur de dispersion d'arme) et `on_air(player, delta)` (chaque tick
  aérien). Un passif peut aussi exposer des méthodes hors contrat, lues en
  duck-typing (`has_method(...)`) par son seul appelant : `on_wall_shot`
  (Relevé, depuis `Weapon._resolve_ray`) et `recoil_mult` (Sang-froid, depuis
  `Weapon._fire_local`).
- **`AbilityController`** (nœud "Abilities" sur le joueur, autorité serveur)
  tient l'état **autoritaire** côté serveur (`AbilityState` : charges, cooldowns,
  ultime ; `StatusEffects` : vitesse/verrou de saut/contrôle) et une copie
  prédite chez le propriétaire. Émet `ability_used(slot, name)` côté
  propriétaire (branché par l'audio). Appelle le passif de l'agent à chaque
  hook pertinent (`on_spawn` dans `_ready`, `server_on_kill`/`server_on_assist`
  exposés pour `GameWorld._record_kill`, `_resolve_cc_duration` avant
  `net_apply_stun`/`net_apply_flash`).
- **Réseau** : le propriétaire calcule sa direction de visée caméra et appelle
  `request_activate(i, aim_dir)` ; le serveur vérifie l'expéditeur, que le
  joueur est vivant, que `abilities_enabled` (propriété du nœud du groupe
  `game_mode` — false en Duel/Duo) est vrai, qu'`aim_dir` est sain
  (`AimValidator`, fini + normalisé), que la capacité l'autorise
  (`can_activate_server`) puis que l'état autoritaire le permet
  (`AbilityState.try_activate`) — **avant seulement** d'exécuter
  `activate_server`, qui calcule toute cible depuis la vue serveur (raycasts,
  `TargetSelect`). Chaque capacité a deux effets : `activate_local(player)`
  (mouvement/cosmétique, chez le propriétaire) et `activate_server(player, aim_dir)`
  (vie, objets répliqués, effets ciblés — côté serveur).
- **Objets répliqués** (mur, fumée, tremplin, piège) : construits par le
  serveur, diffusés en RPC d'autorité à TOUS les pairs (visibles/bloquants
  partout), retirés après leur durée. Un mur porte en plus la métadonnée
  `wall_owner_id` (id réseau de son propriétaire, AGT-09) : lue par
  `Weapon._resolve_ray` pour déclencher le passif Relevé de Vanne quand un
  ennemi tire dedans. Le tremplin n'agit que sur la machine du joueur concerné
  (mouvement local-autoritaire) ; le piège n'est détecté QUE par la copie
  serveur (anti-triche), qui prévient la victime individuellement. La Glu
  (zone persistante) et le Baume du Palud (zone de soin) suivent le même
  principe mais restent des `Area3D` autonomes (pas des primitives
  `AbilityController.cast_*`) : voir leurs fichiers.
- **Effets ciblés** (étourdissement, éblouissement, reveal, impulsion) : RPC
  d'autorité envoyées directement par le serveur au(x) joueur(s) concerné(s)
  (`net_apply_stun`, `net_apply_flash`, `net_show_markers`, `net_apply_impulse`)
  — jamais de broadcast global pour un effet propre à une victime ou à une
  équipe. La durée d'un contrôle reçu passe par `_resolve_cc_duration` :
  passif de la VICTIME (ex. Tête de cloche, ×0,6) **puis** `StatusEffects.cc_mult`
  générique, combinés par multiplication.
- **Statuts** (`StatusEffects`, AGT-01) : `speed_mult` (ex. Glu : ×0,5),
  `jump_locked` (Glu : ni saut, ni glissade, ni plongeon) et `cc_mult`,
  chacun avec sa propre expiration, décomptés en continu (même hors phase
  active) et poussés au propriétaire en <= 1 tick.

---

## Primitives d'effet (contract-r2.md, R-B3 acceptance #2)

| Primitive | Où | Contre-jeu générique |
|---|---|---|
| Mouvement (local) | DashAbility | trajectoire prévisible, punir après/pendant |
| Charge d'épaule (serveur, impulsion + étourdissement) | BellChargeAbility | pas de côté possible (trajectoire figée), la Glu l'arrête |
| Grappin (serveur, ancrage décor + traction) | GrappleAbility | trajectoire rectiligne, arrivée prévisible |
| Braise/téléport de retour (serveur + destructible) | FauxDepartAbility | pré-viser la braise, ou la détruire pour annuler le retour |
| Soin (serveur) | HealAbility | pression continue empêche le soin de base (hors-combat 3 s) |
| Zone de soin d'équipe (persistante, filtre d'équipe) | BalmZoneAbility | la zone est une cible (grenade, poussée) ; PV/s faibles face à un DPS d'arme |
| Mur (objet répliqué, porte `wall_owner_id`) | WallAbility | contourner, attendre l'expiration, prendre à revers |
| Fumée (objet répliqué, opaque ; calque physique VISION : bloque la vue, pas les corps ni les balles) | SmokeAbility | s'approcher pour réduire l'angle mort, contourner |
| Tremplin (objet répliqué) | JumpPadAbility | emplacement fixe et visible, anticiper l'angle |
| Piège étourdissant (objet répliqué, déclenchement unique) | StunTrapAbility | avancer prudemment sur les axes connus |
| Glu (zone persistante, plusieurs victimes, ralentit + verrouille le saut) | GlueAbility | visible de près, destructible, contournable |
| Éblouissement (mèche 0,3 s puis LOS + face au corps) | FlashAbility | se retourner, casser la ligne de vue pendant la mèche |
| Reveal (marqueurs équipe, <= 3 s, délai de vol/avertissement optionnels) | RevealAbility | fenêtre courte, se replacer dès l'annonce |

---

## Agents

### Entrée — duellistes mobiles, ouvrent l'espace

| Agent | Passif | C | Q | E (signature) | X (ultime) |
|-------|--------|---|---|---|---|
| **Vif** | Mèche courte — chaque élimination/assistance rend une charge de Ruée (plafond 2) et +10 % de vitesse au sol (2 s) | Ruée — ruée rapide dans la direction de déplacement | Éblouissement — grenade aveuglante (mèche 0,3 s), écran blanc si l'ennemi lui fait face (<= 1,5 s) | **Faux départ** — pose une braise à ses pieds ; un second appui dans les 5 s la ramène dessus instantanément (PV/munitions conservés), braise destructible (30 dégâts) | Résurgence — soin complet instantané + bond |
| **Choc** | Tête de cloche — durée des étourdissements/éblouissements/ralentissements SUBIS réduite de 40 % | Mur d'assaut — mur de couverture temporaire, petit et rapide | Piège-choc — piège invisible, étourdit le premier ennemi au contact | **Tape-la-cloche** — charge d'épaule dans l'axe de visée : le premier ennemi touché est repoussé (3 m) et étourdi (0,5 s) ; contre un mur sans ennemi, Choc s'étourdit lui-même | Déferlante — coup de cloche (armement 0,4 s) puis étourdit instantanément tous les ennemis dans un rayon autour de l'impact |

**Contre-jeu Vif** : la ruée est prévisible en ligne droite (fenêtre de
vulnérabilité à l'atterrissage) ; tourner le dos à l'éblouissement pendant la
mèche l'annule ; pré-viser ou détruire la braise du Faux départ annule le
retour ; punir Résurgence tôt ou juste après le bond.
**Contre-jeu Choc** : Tape-la-cloche fige la trajectoire à l'armement (pas de
côté possible), et la Glu l'arrête net ; avancer prudemment sur les axes de
flanc pour le Piège-choc ; le mur d'assaut expire vite ; se disperser au son
dès le coup de cloche de la Déferlante.

### Contrôle — verrouillent l'espace, coupent les lignes de vue

| Agent | Passif | C | Q | E (signature) | X (ultime) |
|-------|--------|---|---|---|---|
| **Vanne** | Relevé — tout ennemi qui tire dans un de ses murs est marqué pour son équipe (1,5 s, 4 s par ennemi) | Mur — mur de couverture bloquant tirs et passage (8 s) | Fumée — sphère de fumée opaque : bloque la vue (bots compris), on la traverse et on tire au travers | **Piquet d'arpenteur** — grappin qui hale vers un point d'ancrage sur le DÉCOR (jamais un joueur), portée 18 m | Forteresse — mur massif et durable, ferme complètement un couloir |
| **Guet** | Planeur — maintenir Saut en l'air plafonne la chute (2,5 m/s, 2 s) et améliore le contrôle aérien (+30 %) ; pas d'étourdissement de chute tant qu'il plane | Rideau — fumée épaisse à distance, coupe une ligne de vue longue | Poste avancé — tremplin pour rotation rapide vers les hauteurs | **Coup de dé** — lance un dé qui vole 0,5 s puis révèle les ennemis proches à travers les murs (2,5 s) et les avertit (« bouger ») | Vision totale — révèle TOUS les ennemis de la carte à travers les murs (3 s) et les avertit |

**Contre-jeu Vanne** : ne pas tirer dans son béton (Relevé la trahit),
contourner plutôt ; s'approcher de la fumée pour réduire l'angle mort ; le
Piquet d'arpenteur a une trajectoire rectiligne et une arrivée prévisible ;
Forteresse se contourne par une autre rotation.
**Contre-jeu Guet** : une cible qui plane est lente et lisible (la dispersion
en l'air s'applique toujours) ; la fumée/le rideau se contournent ; le
tremplin est fixe et visible ; Coup de dé/Vision totale disent explicitement
de bouger — se replacer dès l'annonce protège.

### Soutien — sustentation et information pour l'équipe

| Agent | Passif | C | Q | E (signature) | X (ultime) |
|-------|--------|---|---|---|---|
| **Roseau** | Baume au repos — sa régénération démarre après 2,5 s sans dégât (au lieu de 4) à 40 PV/s (au lieu de 35) | Brume — petite fumée défensive pour se mettre à couvert en se soignant | Voile — révèle les ennemis proches d'un point ciblé, équipe seule (3 s) | **Baume du Palud** — lance une flaque de soin D'ÉQUIPE (elle incluse, 12 PV/s, 6 s, rayon 4 m) — premier soin d'alliés du jeu | Sursaut — soin complet instantané pour elle ET ses alliés à <= 10 m + reveal des ennemis proches |
| **Verrou** | Sang-froid — immobile (>= 0,4 s) ou accroupi : dispersion -30 %, recul vertical -20 % | Rempart — mur de couverture standard | Passerelle — tremplin partagé pour aider l'équipe à basculer de position | **Glu** — plaque collante persistante (20 s) : -50 % de vitesse, ni saut ni glissade ni plongeon, encore 1,5 s après la sortie, plusieurs victimes à la fois | Bastion — pose un mur ET une plaque de Glu au même endroit |

**Contre-jeu Roseau** : la zone de Baume du Palud est elle-même une cible
(grenade, poussée) et ses PV/s pèsent peu face au DPS d'une arme ; Brume a un
rayon réduit, facile à déborder ; Sursaut ne protège pas des dégâts eux-mêmes —
la burst-down avant qu'elle ne l'active. **Contre-jeu Verrou** : le déloger
(Éblouissement, Tape-la-cloche) ou le prendre de flanc annule Sang-froid ; la
Glu est visible de près et destructible (40 dégâts) ; la Passerelle et le
Rempart sont fixes et visibles ; forcer un autre axe ou laisser expirer
Bastion (durée finie).

L'ultime se charge avec le temps (trickle <= 0,02 pt/s en arène, 0 en mode à
manches — §3.4) et sur les dégâts/kills (`GameWorld` appelle
`AbilityController.server_add_ult`).

---

## Contrôles

| Action | Clavier | Manette |
|--------|---------|---------|
| Capacité C | C | D-pad gauche |
| Capacité Q | Q (AZERTY : A) | D-pad haut |
| Capacité E (signature) | E | D-pad droite |
| Ultime | X | RB |

Les libellés affichés (barre de capacités, écran de sélection, menu Agents)
suivent toujours la VRAIE touche (AZERTY/QWERTY/manette, `PlayerInput.action_for_slot`
+ `KeyLabel.for_action`) — jamais `Ability.slot` brut, qui reste un identifiant
réseau/bots interne (docs/research/10_ammo_kits_input.md §4).

Sélection de l'agent : au lancement du match (écran de sélection, 15 s de
compte à rebours) ou menu principal → **Agents** → *Choisir*. Les deux écrans
affichent le rôle, la description de l'agent, son **passif** et le nom +
description de chacune de ses 4 capacités. Le HUD affiche les capacités (slot,
nom, charges/cooldown, % d'ultime) en bas à gauche
(`AbilityController.slot_info()`, API inchangée — ne liste que les 4 capacités
à touche, jamais le passif, qui n'a ni touche ni cooldown à afficher).

---

## Limites actuelles (à étendre)

- Le **mur/la fumée/le tremplin/le piège** sont construits par le serveur à
  partir de sa propre vue (transform du joueur ou raycast le long d'`aim_dir`)
  et répliqués ; tailles/portées/durées sont des constantes exportées par
  capacité (voir `AgentDatabase` pour les variantes par agent).
- La Glu (Verrou) et le Baume du Palud (Roseau) sont des `Area3D` construites
  directement par leur capacité, PAS répliquées visuellement à tous les pairs
  (contrairement à mur/fumée/tremplin/piège, qui passent par les `cast_*`
  d'`AbilityController`) : leur EFFET DE JEU (ralentissement, verrous, soin)
  reste complet et correct pour tout le monde (autorité serveur), mais un pair
  humain distant (pas l'hôte) ne verra pas l'objet lui-même. Un futur
  `cast_glue_zone`/`cast_heal_zone` fermerait cet écart.
- Les marqueurs de reveal sont des positions figées à l'instant du cast (pas
  un suivi continu de la cible) — cohérent avec une fenêtre courte (<= 3 s).
  `RevealAbility` peut en plus retarder la résolution (`flight_time`, Coup de
  dé : 0,5 s) et avertir individuellement chaque victime révélée
  (`warn_victims`).
- L'agent choisi est envoyé au serveur au spawn et répliqué (`agent_index`).
- Les capacités sont désactivées quand `abilities_enabled == false` sur le
  nœud du groupe `game_mode` (modes Duel/Duo, contract-r2.md).
- Tous les rayons physiques de trajectoire (point d'impact éblouissement/
  déferlante/reveal/fumée/charge/grappin) et de pose (tremplin, piège, Glu,
  arme au sol) utilisent `PhysicsLayers.SHOT_MASK` : la fumée bloque la vue,
  pas les balles — on la traverse en lançant une capacité comme en tirant au
  travers. Les rayons de POSE excluent en plus TOUS les joueurs de la scène
  (pas seulement le lanceur) : un tremplin, un piège, une Glu ou un ancrage de
  grappin n'atterrit jamais sur la tête d'un joueur (docs/audit/bugs.md
  BUG-06).
