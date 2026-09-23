# Agents & capacités (hero-shooter)

Système de classes façon Valorant : chaque **agent** a un jeu de **capacités**
(touches C / Q / E + **ultime** X), avec cooldowns, charges et points d'ultime.
6 agents, 3 rôles (**Entrée**, **Contrôle**, **Soutien**) x 2, tous
server-autoritaires (contract-p0.md, contract-r2.md §R-B3).

---

## Architecture

```
scripts/agents/
├── Ability.gd              # capacité de base (métadonnées + activate_local/activate_server)
├── AbilityState.gd         # état pur (charges/cooldown/ultime), testé isolément
├── AbilityController.gd    # composant joueur : input, réseau, objets répliqués, effets ciblés
├── AgentConfig.gd          # un agent : nom, rôle, couleur, liste de capacités
├── AgentDatabase.gd        # catalogue des 6 agents + agent sélectionné
├── AimValidator.gd         # validation pure d'aim_dir (fini, normalisé)
├── FacingCheck.gd          # cône de vue pur (yaw du corps) — utilisé par Éblouissement
├── OutOfCombatTracker.gd   # suivi pur "hors-combat" (soin de base)
├── TargetSelect.gd         # sélection de cibles pure (rayon, équipe)
└── abilities/               # capacités concrètes (héritent d'Ability)
    ├── DashAbility.gd       # mouvement (Ruée / Charge / Piquet)
    ├── HealAbility.gd       # soin (RPC serveur, hors-combat pour le soin de base)
    ├── WallAbility.gd       # mur temporaire répliqué (Mur / Mur d'assaut / Rempart / Forteresse)
    ├── SmokeAbility.gd      # sphère de fumée opaque répliquée (Fumée / Rideau / Brume)
    ├── JumpPadAbility.gd    # tremplin répliqué (Tremplin / Poste avancé / Passerelle)
    ├── StunTrapAbility.gd   # piège étourdissant répliqué, détection serveur seule
    ├── FlashAbility.gd      # éblouissement : LOS + face au corps, ciblé serveur
    ├── RevealAbility.gd     # reveal en zone, marqueurs "!" envoyés à l'équipe seule
    ├── StunBurstAbility.gd  # ULTIME : étourdissement instantané en zone (Déferlante)
    ├── RenewalAbility.gd    # ULTIME : soin total + reveal (Sursaut)
    ├── BastionAbility.gd    # ULTIME : mur + piège combinés (Bastion)
    └── SurgeAbility.gd      # ULTIME : soin total + bond (Résurgence)
```

- **`Ability`** : `slot` (C/Q/E/X), `display_name`, `description`, `cooldown`,
  `charges`, `is_ultimate`, `ult_cost`, `can_activate_server(player)` (condition
  serveur additionnelle, ex. hors-combat), `activate_local(player)` et
  `activate_server(player, aim_dir)`.
- **`AbilityController`** (nœud "Abilities" sur le joueur, autorité serveur)
  tient l'état **autoritaire** côté serveur (`AbilityState` : charges, cooldowns,
  ultime) et une copie prédite chez le propriétaire. Émet `ability_used(slot, name)`
  côté propriétaire (branché par l'audio).
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
  partout), retirés après leur durée. Le tremplin n'agit que sur la machine du
  joueur concerné (mouvement local-autoritaire) ; le piège n'est détecté QUE
  par la copie serveur (anti-triche), qui prévient la victime individuellement.
- **Effets ciblés** (étourdissement, éblouissement, reveal) : RPC d'autorité
  envoyées directement par le serveur au(x) joueur(s) concerné(s)
  (`net_apply_stun`, `net_apply_flash`, `net_show_markers`) — jamais de
  broadcast global pour un effet propre à une victime ou à une équipe.

---

## Primitives d'effet (contract-r2.md, R-B3 acceptance #2)

| Primitive | Où | Contre-jeu générique |
|---|---|---|
| Mouvement (local) | DashAbility | trajectoire prévisible, punir après/pendant |
| Soin (serveur) | HealAbility | pression continue empêche le soin de base (hors-combat 3 s) |
| Mur (objet répliqué) | WallAbility | contourner, attendre l'expiration, prendre à revers |
| Fumée (objet répliqué, opaque ; calque physique VISION : bloque la vue, pas les corps ni les balles) | SmokeAbility | s'approcher pour réduire l'angle mort, contourner |
| Tremplin (objet répliqué) | JumpPadAbility | emplacement fixe et visible, anticiper l'angle |
| Piège étourdissant (objet répliqué) | StunTrapAbility | avancer prudemment sur les axes connus |
| Éblouissement (LOS + face au corps) | FlashAbility | tourner le dos / casser la ligne de vue |
| Reveal (marqueurs équipe, <= 3 s) | RevealAbility | fenêtre courte, se replacer dès l'annonce |

---

## Agents

### Entrée — duellistes mobiles, ouvrent l'espace

| Agent | Identité | C | Q | E | X (ultime) |
|-------|----------|---|---|---|---|
| **Vif** | duelliste mobile | Ruée — ruée rapide dans la direction de déplacement | Éblouissement — grenade aveuglante, écran blanc si l'ennemi lui fait face (<= 1,5 s) | Tremplin — pose un tremplin qui propulse vers le haut | Résurgence — soin complet instantané + bond |
| **Choc** | brise-lignes | Charge — charge puissante en ligne droite, franchit les petits obstacles | Piège-choc — piège invisible, étourdit le premier ennemi au contact | Mur d'assaut — mur de couverture temporaire, petit et rapide | Déferlante — étourdit instantanément tous les ennemis dans un rayon autour de l'impact |

**Contre-jeu Vif** : la ruée est prévisible en ligne droite (fenêtre de
vulnérabilité à l'atterrissage) ; tourner le dos à l'éblouissement l'annule ;
le tremplin est visible et fixe ; punir Résurgence tôt ou juste après le bond.
**Contre-jeu Choc** : se décaler latéralement face à la charge (trajectoire
fixe) ; avancer prudemment sur les axes de flanc pour le piège ; le mur
d'assaut expire vite ; se disperser dès l'annonce de la Déferlante.

### Contrôle — verrouillent l'espace, coupent les lignes de vue

| Agent | Identité | C | Q | E | X (ultime) |
|-------|----------|---|---|---|---|
| **Roc** | bastion défensif | Mur — mur de couverture bloquant tirs et passage (8 s) | Fumée — sphère de fumée opaque : bloque la vue (bots compris), on la traverse et on tire au travers | Piquet — petite poussée pour se replacer sans quitter sa position | Forteresse — mur massif et durable, ferme complètement un couloir |
| **Guet** | vigie | Rideau — fumée épaisse à distance, coupe une ligne de vue longue | Poste avancé — tremplin pour rotation rapide vers les hauteurs | Œil — marqueur qui révèle les ennemis à travers les murs dans un rayon, équipe seule (3 s) | Vision totale — révèle TOUS les ennemis de la carte à travers les murs (3 s) |

**Contre-jeu Roc** : attendre l'expiration du mur ou le prendre à revers ;
s'approcher de la fumée pour réduire l'angle mort ; le Piquet a une portée
courte et prévisible ; Forteresse se contourne par une autre rotation.
**Contre-jeu Guet** : la fumée/le rideau se contournent ; le tremplin est fixe
et visible une fois repéré ; Œil et Vision totale ont une fenêtre très courte
(3 s) — rester immobile en zone non prioritaire dès l'annonce protège.

### Soutien — sustentation et information pour l'équipe

| Agent | Identité | C | Q | E | X (ultime) |
|-------|----------|---|---|---|---|
| **Baume** | soigneuse | Apaisement — se soigne, uniquement si aucun dégât depuis 3 s | Voile — révèle les ennemis proches d'un point ciblé, équipe seule (3 s) | Brume — petite fumée défensive pour se mettre à couvert en se soignant | Sursaut — soin complet instantané (sans condition) + reveal des ennemis proches |
| **Verrou** | ancrage tactique | Chausse-trape — piège invisible, étourdit le premier ennemi au contact | Passerelle — tremplin partagé pour aider l'équipe à basculer de position | Rempart — mur de couverture standard | Bastion — pose un mur ET un piège étourdissant au même endroit |

**Contre-jeu Baume** : la pression continue (dégâts répétés) l'empêche de se
soigner ; Brume a un rayon réduit, facile à déborder ; Sursaut ne protège pas
des dégâts eux-mêmes — la burst-down avant qu'elle ne l'active. **Contre-jeu
Verrou** : avancer prudemment sur les axes de flanc connus pour la
Chausse-trape ; la Passerelle et le Rempart sont fixes et visibles ; forcer un
autre axe ou laisser expirer Bastion (durée finie).

L'ultime se charge avec le temps (trickle <= 0,1 pt/s côté `AbilityState`) et
sur les dégâts/kills (`GameWorld` appelle `AbilityController.server_add_ult`).

---

## Contrôles

| Action | Clavier | Manette |
|--------|---------|---------|
| Capacité C | C | D-pad gauche |
| Capacité Q | Q | D-pad haut |
| Capacité E | E | D-pad droite |
| Ultime | X | RB |

Sélection de l'agent : au lancement du match (écran de sélection, 15 s de
compte à rebours) ou menu principal → **Agents** → *Choisir*. Les deux écrans
affichent le rôle, la description de l'agent et le nom + description de
chacune de ses 4 capacités. Le HUD affiche les capacités (slot, nom,
charges/cooldown, % d'ultime) en bas à gauche (`AbilityController.slot_info()`,
API inchangée).

---

## Limites actuelles (à étendre)

- Le **mur/la fumée/le tremplin/le piège** sont construits par le serveur à
  partir de sa propre vue (transform du joueur ou raycast le long d'`aim_dir`)
  et répliqués ; tailles/portées/durées sont des constantes exportées par
  capacité (voir `AgentDatabase` pour les variantes par agent).
- Les marqueurs de reveal sont des positions figées à l'instant du cast (pas
  un suivi continu de la cible) — cohérent avec une fenêtre courte (<= 3 s).
- L'agent choisi est envoyé au serveur au spawn et répliqué (`agent_index`).
- Les capacités sont désactivées quand `abilities_enabled == false` sur le
  nœud du groupe `game_mode` (modes Duel/Duo, contract-r2.md).
