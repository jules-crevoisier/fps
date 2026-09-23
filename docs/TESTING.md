# Tests (gdUnit4) & intégration continue

Ce document explique comment lancer les tests en local et ce que fait la CI.

---

## 1. Lancer les tests en local

Prérequis : **Godot 4.7** installé (ex. `Godot_v4.7-stable_win64.exe`) et le
plugin **gdUnit4** présent dans `addons/gdUnit4/` (déjà dans le repo).

```bash
GODOT_BIN=/c/Users/srko/Desktop/Godot_v4.7-stable_win64.exe tools/test.sh
```

- `GODOT_BIN` doit pointer vers l'exécutable Godot 4.7 (headless ou non, peu
  importe : le script ajoute `--headless` lui-même). Le script s'arrête avec
  une erreur explicite si `GODOT_BIN` n'est pas défini.
- Par défaut la suite lancée est `res://tests` (tout `tests/`).

### Lancer une seule suite

Passe le chemin `res://` de la suite (fichier ou dossier) en premier argument :

```bash
GODOT_BIN=/c/Users/srko/Desktop/Godot_v4.7-stable_win64.exe \
  tools/test.sh res://tests/smoke/test_smoke.gd
```

```bash
# tout un sous-dossier
GODOT_BIN=/c/Users/srko/Desktop/Godot_v4.7-stable_win64.exe \
  tools/test.sh res://tests/combat
```

### Où atterrissent les rapports

Chaque exécution crée un nouveau dossier `reports/report_<n>/` (HTML +
`results.xml` au format JUnit). Ce dossier est ignoré par git
(`.gitignore` → `reports/`).

### Codes de sortie

| Code | Sens | Bloquant ? |
|------|------|------------|
| `0`  | tous les tests passent | non |
| `100`| au moins un test a échoué | **oui** |
| `101`| avertissements seulement (pas d'échec) | non |

---

## 2. Ce que fait la CI (`.github/workflows/ci.yml`)

Déclenchée sur `push` et `pull_request`.

1. **`tests`** (Ubuntu, image `barichello/godot-ci:4.7`) :
   - importe le projet (`godot --headless --path . --import`) ;
   - lance `GODOT_BIN=godot tools/test.sh` ;
   - le job échoue si le code de sortie n'est ni `0` ni `101` (donc surtout
     sur `100` = échecs réels) ;
   - `reports/` est toujours uploadé comme artefact du job, même en cas
     d'échec ;
   - les résultats JUnit (`reports/report_*/results.xml`) sont publiés via
     `mikepenz/action-junit-report`.
2. **`export`** (dépend de `tests`) : exporte les trois presets
   (`Windows Desktop`, `Linux`, `Linux Server`) avec les modèles d'export de
   la **même version Godot 4.7**, puis uploade `build/` en artefact. L'export
   serveur dédié (`build/server/fps_server.x86_64`) est ce que consommera la
   future image Docker (Phase 1).

La CI exécute la même version de Godot que celle utilisée en local
(`4.7-stable`) pour éviter tout écart de comportement entre les tests et
l'export.

---

## 3. Le framework de test n'est pas exporté

`export_presets.cfg` exclut explicitement du build joueur/serveur tout ce qui
ne sert qu'au développement :
`addons/gdUnit4/*`, `tests/*`, `tools/*`, `reports/*`, `docs/*`,
`.orchestrator/*` (filtre `exclude_filter`, un par preset). Le plugin gdUnit4
ne fait donc partie que du projet source, jamais d'un `.exe` / build serveur
livré.
