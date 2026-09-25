## Contexte projet (commun à toutes les tâches)

Jeu : FPS en ligne free-to-play (cosmétiques plus tard), Godot 4.7 (Forward+, D3D12, Jolt), GDScript
typé. Modes : 4v4 (match à mort par équipe + tactique pose/désamorçage), Duel 1v1, Duo 2v2. Six
agents à capacités. Bots pour remplir les parties. Direction artistique : cel-shading peint et
coloré, encrage épais, personnages décalés à tête d'objet — la référence est docs/STYLE_BIBLE.md
(+ docs/style/tokens.json). Retour joueur à corriger en priorité : « bots nuls, interface pas ok,
3D terrible, bugs partout, pas jouable ».

Dépôt : C:\Users\srko\Desktop\fps (Windows 11). Godot : C:\Users\srko\Desktop\Godot_v4.7-stable_win64.exe
Blender : "C:\Program Files\Blender Foundation\Blender 5.2\blender.exe"

### Architecture à respecter
- Réseau autoritaire serveur (peer 1). Client -> serveur : RPC `any_peer` -> `_server_*(sender_id, ...)`
  avec contrôle du propriétaire. Serveur -> client : RPC `authority`. L'hôte et les bots (ids >= 9001)
  sont simulés sur le serveur : appel direct au lieu de `rpc_id` vers eux-mêmes.
- Health / Weapon / Abilities : autorité serveur. Le serveur ne resynchronise le client qu'en cas de rejet.
- Entrées joueur via `player.input` (PlayerInput) — les bots utilisent la même abstraction.
- Configuration de partie : scripts/core/MatchConfig.gd. Cartes : scripts/levels/maps/ (MapCatalog,
  MapSetup, PropCatalog, dressing/). Couches physiques : scripts/core/PhysicsLayers.gd.
- Rendu : assets/shaders/ (ink_toon, contours, InkPost, ciel), scripts/core/Cartoon.gd, LevelLook.gd.
  Teintes réservées (surbrillance ennemie) : 300–355° et 105–145° interdites dans le décor.
- Minuteries : jamais de lambda capturant un nœud dans `get_tree().create_timer()` ; utiliser un tween
  porté par le nœud ou `connect(node.queue_free)`.

### Conventions
- Commentaires et docs en français, identifiants en anglais. Pas de TODO, pas de code mort, pas de
  texte factice.
- Tests gdUnit4 dans tests/. Pendant l'itération, lancer UNIQUEMENT le périmètre de la tâche :
  `& "C:\Users\srko\Desktop\Godot_v4.7-stable_win64.exe" --headless --path . -s -d --remote-debug tcp://127.0.0.1:1 res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests/<dossier_ou_fichier> -c --ignoreHeadlessMode`
  (si tu as ajouté un `class_name` ou un asset : `--headless --path . --import` d'abord).
- Revue automatique : `powershell -File tools/review/run_review.ps1 -Quick` (ou `-Only <étapes>`).
- Un test ne se réécrit jamais pour coller au code. Si un critère contredit le code existant, arrête-toi
  et signale-le.
- Ne committe pas. Ne touche à aucun fichier hors de ta liste : d'autres agents travaillent en parallèle.
- Git en LECTURE SEULE : `git status`, `git diff`, `git log`, `git show` uniquement. Jamais `git stash`, `reset`,
  `checkout -- <fichier>`, `restore`, `clean` : l'arbre contient le travail non commité de plusieurs agents à la
  fois (incident du 2026-09-25 : un stash/reset/pop a fait disparaître des fichiers d'autres tâches pendant une
  vague). Pour comparer avec l'état d'origine d'un fichier : `git show HEAD:<chemin>`.
- Recherches BORNÉES au dépôt : jamais `find /` ni une recherche sur tout le disque (incident du 2026-09-25 :
  11 `find /` orphelins ont saturé 8 cœurs du poste de l'utilisateur pendant plus d'un jour). Utiliser Glob/Grep,
  ou `find <dossier du dépôt> ...` précédé de `timeout 60`. Tout Godot/Blender lancé doit se terminer (timeout).
  Les entrées `find` encore listées par Windows sont DÉJÀ terminées (HasExited, 0 % CPU) : les ignorer. Ne jamais
  arrêter/tuer un processus que tu n'as pas lancé toi-même, et ne jamais bloquer ta tâche pour ça — le lead gère.
- Bruit connu : erreurs « material is null » en headless sur les cartes repeintes (rendu factice).
- Toute tâche au rendu visible dépose 1 à 4 captures JPG (≤ 1600 px) dans reports/checkpoints/<AAAA-MM-JJ>_<id-tâche>/ et les cite dans son rendu : le lead les envoie à l'utilisateur à chaque étape.
