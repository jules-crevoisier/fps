# Gestion des tâches

Un backlog unique, des dépendances explicites, une propriété exclusive des fichiers, et des vagues
de travail lancées en parallèle. Tout est scriptable : un humain ou Claude suit la même procédure.

## Les pièces

| Fichier | Rôle | Qui l'écrit |
|---|---|---|
| `tasks/backlog.yaml` | La spec : épopées, tâches, fichiers possédés, dépendances, critères d'acceptation | À la main (et `plan.py import`) |
| `tasks/state.json` | L'état : todo / doing / done / blocked, horodatages, notes | `plan.py` uniquement |
| `tasks/context.md` | Le contexte projet injecté dans chaque prompt d'agent | À la main |
| `tools/tasks/plan.py` | Validation, vagues, tâches prêtes, rendu des prompts, import, tableau | — |
| `.claude/workflows/sprint.js` | Exécute une vague : build parallèle → QA indépendant → une passe de correction | — |
| `docs/tasks/BOARD.md` | Tableau généré (avancement, vagues, graphe mermaid) | `plan.py board` |

## Les deux règles de parallélisme

1. Une tâche ne démarre que si toutes ses `depends_on` sont `done` (les `depends_on` d'une épopée
   s'appliquent à toutes ses tâches).
2. Deux tâches ne tournent jamais ensemble si leurs `files` se recoupent (même fichier, dossier
   parent ou glob). Le planificateur choisit, dans l'ordre priorité → chemin critique → taille, le
   plus grand ensemble sans conflit.

## Procédure d'une session (ex. demain 10 h)

```powershell
python tools/tasks/plan.py validate          # 0 erreur obligatoire
python tools/tasks/plan.py status            # avancement par épopée
python tools/tasks/plan.py waves --max 6     # le plan complet en vagues
python tools/tasks/plan.py ready --max 6 --brief --json
python tools/tasks/plan.py start <ids affichés>
```

Puis, dans Claude Code : `Workflow({scriptPath: "C:/Users/srko/Desktop/fps/.claude/workflows/sprint.js",
args: <JSON affiché>})`. Avec `--brief`, le JSON ne contient que id, modèle, agent et fichiers :
chaque agent lit son contrat avec `plan.py prompt <id>` et son vérificateur avec
`plan.py verify-prompt <id>`. Sans `--brief`, les prompts complets voyagent dans `args`. À la fin :

```powershell
python tools/tasks/plan.py done <ids réussis>
python tools/tasks/plan.py block <id> --reason "..."   # pour chaque échec à arbitrer
powershell -File tools/review/run_review.ps1           # revue complète après chaque vague
python tools/tasks/plan.py board
```

On relance `ready` : la vague suivante se débloque d'elle-même.

## Ajouter des tâches

- À la main dans `tasks/backlog.yaml` (garder `tasks:` en dernière clé).
- Depuis un document d'audit ou de recherche qui contient des blocs au format strict :

```
- id: GF-01
  title: ...
  files: [scripts/..., ...]
  depends_on: []
  size: S|M|L
  acceptance: ...
```

`python tools/tasks/plan.py import docs/research/01_game_feel.md --dry-run` puis sans `--dry-run`.
Le préfixe fixe l'épopée et la priorité par défaut (`BUG` → E1/P0, `GF`/`MV` → E2, `BOT` → E3,
`ART`/`A3D` → E4, `UX` → E5, `LD` → E6, `TECH` → E7, `FUN` → E8). Relire ensuite les priorités,
les dépendances croisées et les `files` (un `files` trop large sérialise tout).

## Arbitrer sans toucher aux blocs importés

- Section `overrides:` du backlog (avant `tasks:`) : `ID: {priority: P0, add_depends_on: [X], title: ..., notes: ...}`.
  Les champs remplacent ceux de la tâche ; `add_depends_on` s'ajoute.
- Doublon ou abandon : `plan.py drop ID --reason "doublon de X"` (satisfait les dépendances).
- Décision humaine attendue : `plan.py block ID --reason "..."` (bloque aussi les dépendantes).
- Jalon : `gate: [P0, P1]` sur une tâche = elle attend toutes les tâches P0/P1 de son épopée.
- Tableau HTML autonome : `plan.py html` → `reports/tasks/board.html`.

## Modèles

`model: opus` pour ce qui décide (direction artistique, architecture, recherche), `model: sonnet`
pour ce qui exécute un contrat verrouillé. Un agent Sonnet qui revient avec une question de design
remplit `blocked_on` : le lead tranche, met à jour la tâche, la relance.
