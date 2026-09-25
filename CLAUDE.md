# Projet FPS (Godot 4.7) — instructions de session

FPS en ligne free-to-play, 4v4 (match à mort + tactique) / Duel 1v1 / Duo 2v2, 6 agents à capacités,
bots. Style : cel-shading peint et coloré, encrage épais, personnages décalés — la référence unique
est `docs/STYLE_BIBLE.md` (+ `docs/style/tokens.json`). Inspirations : `.orchestrator/refs/`
(planches Wasteland / Cargo Ship + `pinterest/pin_*.jpg`).

## Démarrer une session de travail

1. `python tools/tasks/plan.py validate` puis `status` puis `waves --max 6`.
2. `python tools/tasks/plan.py ready --max 6 --brief --json`, puis `plan.py start <ids>`.
3. Lancer le sprint : `Workflow({scriptPath: "C:/Users/srko/Desktop/fps/.claude/workflows/sprint.js", args: <JSON du ready>})`.
   Écrire en Python les modifications de fichiers du dépôt (pas de `Set-Content` PowerShell sans
   `-Encoding utf8` : il corrompt l'UTF-8), et jamais `write_text(newline=...)` invalide (fichier vidé).
4. `plan.py done|block ...`, puis `powershell -File tools/review/run_review.ps1` et lire
   `reports/review/<dernier>/summary.md`. Vague suivante.

Procédure complète : `docs/tasks/README.md`. Contexte injecté dans chaque agent : `tasks/context.md`.

## Où est quoi

- Plan maître : `docs/ROADMAP.md`. Backlog exécutable : `tasks/backlog.yaml`. Tableau : `docs/tasks/BOARD.md`.
- Recherche web consolidée : `docs/research/01..07_*.md`. Audit : `docs/audit/bugs.md`, `docs/audit/bots.md`.
- Revue automatique : `docs/REVIEW.md` (`tools/review/`). Pipeline 3D : `docs/3D_PIPELINE.md` (`tools/blender/`).
- Godot : `C:\Users\srko\Desktop\Godot_v4.7-stable_win64.exe`. Blender : `C:\Program Files\Blender Foundation\Blender 5.2\blender.exe`.

## Règles propres au projet

- Réseau autoritaire serveur ; hôte et bots simulés côté serveur (voir `tasks/context.md`).
- Tests scopés pendant l'itération, suite complète + revue complète en fin de vague.
- Toute modification visible (3D, UI, VFX) se vérifie en image (turntable, map_shots, ui_shots) avant
  d'être déclarée finie, contre la checklist de `docs/STYLE_BIBLE.md`.
- Branche de travail : `feature/aaa-roadmap` (jamais `main`). Commit seulement sur demande.
