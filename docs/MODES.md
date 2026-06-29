# Modes de jeu

Framework de mode **serveur-autoritaire** : scores d'équipe, condition de
victoire, synchro au HUD. Les modes concrets héritent de `GameMode`.

```
scripts/modes/
├── GameMode.gd      # base : team_scores, score_to_win, winner, on_kill, reset
├── HardpointMode.gd # capture de zone
└── TDMMode.gd       # Team Deathmatch (kills = points)
```

Le serveur calcule tout ; l'état est répliqué via `sync_state.rpc(...)`. Le HUD
lit le mode via le groupe `game_mode` (scoreboard haut-centre).

## Boucle de match (commune)

`GameWorld` (groupe `match`) gère, côté serveur :
- **stats par joueur** (`player_info` : nom, équipe, kills, morts), synchronisées,
- les **kills** (signal `Health.died` → `_record_kill`) : maj stats, **killfeed**
  (RPC `kill_logged`), **charge d'ultime** du tueur, et `mode.on_kill(...)`,
- **respawn** après délai, et **rejouer** (`reset_match` : remet scores + stats).

HUD : **killfeed** (haut-droite), **scoreboard** (maintenir **Tab**), **écran de
fin** (vainqueur + Rejouer / Menu).

---

## Hardpoint (implémenté)

Une **zone** à tenir (`Area3D` mobile) :
- Une équipe **seule** dans la zone gagne des points/s (`capture_rate`).
- Deux équipes = **contesté** (personne ne marque).
- La zone **tourne** d'emplacement toutes les `rotate_interval` secondes
  (liste de marqueurs `HardpointPoints`).
- Premier à `score_to_win` gagne.

Réglages sur le nœud `HardpointMode` de `comp_map.tscn` :
`score_to_win`, `capture_rate`, `rotate_interval`, `zone_path`, `points_path`.

Le HUD affiche `ÉQ.1 x — y ÉQ.2` + l'état (qui capture / contesté / rotation).

---

## Team Deathmatch (implémenté)

Chaque élimination d'un **ennemi** rapporte 1 point à l'équipe ; première équipe à
`score_to_win` (30) gagne. Respawn actif. Scène : `tdm_map.tscn`.

Le mode se choisit dans le menu principal (bouton **Mode : …**) avant *Héberger*.

## À venir

- **SnD** (rounds sans respawn, plant/défuse) — volontairement repoussé.
- **Économie + rounds** : crédits, phase d'achat, manches.
- Synchronisation **équipe/agent** aux autres (couleurs, plaques de nom).
