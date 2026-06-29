# Agents & capacités (hero-shooter)

Système de classes façon Valorant : chaque **agent** a un jeu de **capacités**
(touches C / Q / E + **ultime** X), avec cooldowns, charges et points d'ultime.

---

## Architecture

```
scripts/agents/
├── Ability.gd            # capacité de base (métadonnées + activate())
├── abilities/            # capacités concrètes (héritent d'Ability)
│   ├── DashAbility.gd    # ruée
│   ├── HealAbility.gd    # soin (RPC serveur)
│   ├── WallAbility.gd    # mur temporaire
│   └── SurgeAbility.gd   # ULTIME : soin complet + bond
├── AgentConfig.gd        # un agent : nom, couleur, liste de capacités
├── AgentDatabase.gd      # catalogue d'agents + agent sélectionné
└── AbilityController.gd  # composant joueur : input, cooldowns, charges, ult
```

- **`Ability`** : `slot` (C/Q/E/X), `display_name`, `cooldown`, `charges`,
  `is_ultimate`, `ult_cost`, et `activate(player)` surchargée par les capacités.
- **`AbilityController`** (nœud "Abilities" sur le joueur) gère l'état runtime et
  appelle `activate()` quand la capacité est prête. Les effets de **vie** passent
  par un RPC serveur (`Health.request_heal`) ; les effets de **mouvement**
  s'exécutent côté propriétaire.

---

## Capacités actuelles (placeholders fonctionnels)

| Capacité | Effet | Cooldown / charges |
|----------|-------|--------------------|
| Dash | ruée dans la direction de déplacement | 6 s · 2 charges |
| Soin | +60 PV (validé serveur) | 14 s |
| Mur | érige un mur temporaire (8 s) devant soi | 16 s |
| Surge (ult) | soin complet + bond | charge par points |

L'ultime se charge avec le temps (placeholder) ; le gain sur les kills viendra.

---

## Agents

| Agent | Identité | C | Q | E | X |
|-------|----------|---|---|---|---|
| **Vif** | duelliste mobile | Dash | Soin | Mur | Surge |
| **Roc** | défenseur | Mur | Soin | Dash | Surge |

Les capacités sont **réarrangées par slot** selon l'agent (la même capacité peut
être sur une touche différente). Pour ajouter un agent : éditer `AgentDatabase._make`.

---

## Contrôles

| Action | Clavier | Manette |
|--------|---------|---------|
| Capacité C | C | D-pad gauche |
| Capacité Q | Q | D-pad haut |
| Capacité E | E | D-pad droite |
| Ultime | X | RB |

Sélection de l'agent : menu principal → **Agents** → *Choisir*. Le HUD affiche les
capacités (slot, nom, charges/cooldown, % d'ultime) en bas à gauche.

---

## Limites actuelles (à étendre)

- Capacités = **placeholders** (effets simples) ; à enrichir (flash, smoke, recon…).
- Le **mur** est local (visible/efficace en solo) ; réplication réseau à venir.
- L'identité d'agent n'est pas encore synchronisée aux autres joueurs (les
  capacités fonctionnent pour le propriétaire).
- Charge d'ultime sur le temps seulement (kills à brancher).
