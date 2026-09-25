# Outils IA installés sur la machine de dev

Installés le 2026-09-24, à la demande de l'utilisateur, hors du dépôt (`C:\Users\srko\AI`).

## ComfyUI (images de concept, décalques)

- Build officiel portable AMD : `ComfyUI_windows_portable_amd.7z` v0.37.0 (Comfy-Org, GitHub),
  dans `C:\Users\srko\AI\ComfyUI_windows_portable`.
- Matériel détecté : Radeon RX 9060 XT, gfx1200, 16 Go, PyTorch 2.9.1 + ROCm 7.2.1.
- Modèle : `sd_xl_base_1.0.safetensors` (Stability AI, licence CreativeML Open RAIL++-M, usage
  commercial autorisé sous réserve des restrictions d'usage) dans `ComfyUI/models/checkpoints`.
- Lancer le serveur (API locale, pas d'exposition réseau) :

```powershell
Set-Location C:\Users\srko\AI\ComfyUI_windows_portable
.\python_embeded\python.exe -s ComfyUI\main.py --windows-standalone-build --listen 127.0.0.1 --port 8188 --disable-auto-launch
```

- Mesure : une image SDXL 1024×1024 en 25 pas ≈ 26 s, chargement du modèle compris.
- Liste blanche de modèles (licences compatibles UE et commerciales) : SDXL base, FLUX.1 schnell
  (Apache-2.0). Interdits : FLUX.1 dev (non commercial), tout modèle Hunyuan (licence hors UE).
- Rôle dans le pipeline : images de concept orthographiques et décalques uniquement. Les textures
  du jeu restent procédurales ou repeintes selon `docs/STYLE_BIBLE.md` (voir
  `docs/research/06_ai_3d_pipeline.md`).

## blender-mcp (exploration interactive dans Blender)

- Paquet `mcp-for-blender` (MIT) lancé par `uvx` (uv 0.12.18 installé dans `~\.local\bin`).
- Extension Blender : `%APPDATA%\Blender Foundation\Blender\5.2\scripts\addons\blender_mcp.py`,
  activée dans les préférences de Blender 5.2.
- Déclaré pour ce projet dans `.mcp.json` avec `DISABLE_TELEMETRY=true`. Claude Code le propose au
  prochain démarrage de session dans ce dossier.
- Utilisation : ouvrir Blender 5.2, panneau latéral (N) › « MCP for Blender » › Start MCP Server.
  Le socket n'a ni authentification ni chiffrement : localhost uniquement, arrêter après usage.
- Ne jamais appeler ses intégrations Hunyuan3D (licence interdite dans l'UE). La production
  reste en scripts Blender headless (`tools/blender/`), blender-mcp sert à explorer.

## Tripo (génération 3D par API)

- `tripo-cli` 0.5.1 (npm, officiel : documenté sur developers.tripo3d.ai/en/docs/cli, aucun
  script d'installation, ne contacte que les domaines tripo3d) installé globalement.
- Compte de l'utilisateur connecté le 2026-09-24 par autorisation navigateur (profil `default`,
  région `ov`). La clé est stockée par l'outil dans `%USERPROFILE%\.tripo`, hors du dépôt.
- Solde à la connexion : 0 crédit. Recharge par l'utilisateur (`tripo topup` ou console).
- Commandes utiles : `tripo balance`, `tripo make concept.png --for game-mobile`, `tripo usage`.
- Crédits à l'usage : 1 crédit = 0,01 $.
- Coûts (grille officielle) : image→3D 20 crédits, low-poly intelligent +10, quad +5, texture HD
  +10, auto-rig 25. Notre usage type (forme seule, on retexture nous-mêmes) : 30 crédits ≈ 0,30 $.
- La clé va dans `.env` sous `TRIPO_API_KEY` (fichier ignoré par git, jamais commité).

## Production en lot (`tools/ai3d/run_batch.py`)

Pipeline qui prend un **manifeste YAML** (une entrée par asset : arme, prop, gameplay, capacité,
décor — voir `tools/ai3d/manifests/wave1.yaml` pour la vague réelle, ou
`tools/ai3d/tests/fixtures/mini_manifest.yaml` pour un exemple minimal commenté des 3 routes) et
produit les `.glb` en lot via `tripo-cli`, avec vérification + revue groupée.

### Lancer une vague

```powershell
python tools/ai3d/run_batch.py tools/ai3d/manifests/wave1.yaml --dry-run
# une fois le plan relu et le solde suffisant :
python tools/ai3d/run_batch.py tools/ai3d/manifests/wave1.yaml --max-credits 500 --parallel 4
```

- `--only id1,id2` / `--priority P0` : ne traiter qu'un sous-ensemble du manifeste.
- `--max-credits N` (défaut 500) : plafond de dépense. Le script refuse de démarrer si le coût
  ESTIMÉ (voir plus bas) dépasse ce plafond **ou** le solde live (`tripo balance --json`) — sauf en
  `--dry-run`, qui affiche toujours le plan (et un avertissement si le run réel serait refusé),
  puisque c'est le seul mode utilisable à solde 0.
- `--parallel N` (défaut 4) : nombre de génération simultanées. L'étape de vérification (voir plus
  bas) reste TOUJOURS séquentielle — `model_preview.gd` est fenêtré, en lancer plusieurs à la fois
  est fragile sur une seule machine.
- Un id qui a déjà un `.glb` sous `assets/incoming/tripo/<category>/<id>.glb` n'est JAMAIS régénéré
  (économise des crédits en relance) sauf `--force`.
- `--ingest-only` saute entièrement la génération (donc l'estimation de coût) : ne fait que la
  vérification + la revue sur les `.glb` déjà présents. Utile pour rejouer la revue, ou pour des
  fichiers déposés à la main.

### Estimation de crédits

Barème CONSERVATEUR (jamais sous-évalué) tiré de la grille officielle ci-dessus + `tripo docs
--topic commands/generate` : base 20 crédits (génération), +15 (image de concept, routes
`image`/`multiview`), +10 (assemblage multivue), +10/+5 (marge texture/quad), +10 (low-poly
intelligent). Ce n'est PAS une facturation exacte — le coût RÉEL de chaque génération
(`credits_consumed` renvoyé par l'API) est celui écrit dans `<id>.provenance.json`.

### Routes de génération

- `text` : `tripo make "<prompt>" -p face_limit=... -p texture=... -p quad=... -p smart_low_poly=...`
- `image` : `tripo generate text-to-image "<image_prompt>"` puis `tripo generate image-to-model
  <fichier concept téléchargé>` (jamais de référence `@last`/task id entre les deux : leur
  acceptation varie selon l'endpoint, un fichier local est toujours accepté).
- `multiview` : `text-to-image` → `image-to-multiview` → `multiview-to-model`, même principe (fichiers
  locaux entre chaque étape). Chaîne non vérifiée avec de vrais crédits (solde à 0 au moment
  d'écrire ce pipeline) — à valider sur une petite entrée réelle dès que le compte est rechargé.
- Jamais de `--for`/`--then` scénario : le manifeste donne déjà tous les paramètres de génération: un
  scénario les écraserait silencieusement (ex. `--for game-pc` force `texture_quality=detailed` et
  une conversion FBX/GLTF non désirée — sondé via `tripo make ... --for game-pc --dry-run --json`).
- `--model tripo-v3.1` forcé automatiquement si `quad` ou `smart_lowpoly` est demandé (sinon
  l'auto-sélection du modèle les retire silencieusement avec un avertissement pour un petit
  `face_limit`, sondé).
- **Limite connue** : `quad: true` force une sortie FBX côté API (un maillage à quads ne peut pas
  être stocké en GLB) — une entrée avec `quad: true` échoue donc explicitement à l'étape "aucun
  .glb dans la sortie tripo" avec un message qui l'explique. Retirer `quad` pour une sortie GLB, ou
  étendre le pipeline pour accepter du FBX si le quad est vraiment nécessaire.

### Vérification + page de revue

Pour chaque asset : `tools/blender/check_asset.py` (budget de triangles de l'entrée) puis
`tools/review/model_preview.gd` (fenêtré, planche PASS/FAIL + aperçu en jeu) — les deux sont
mis en cache (jamais rejoués si le `.glb` n'a pas changé, sauf `--force`). Le tout est assemblé
dans **`assets/incoming/tripo/review.html`** : une page unique (thème sombre, même code couleur que
`tools/review/report.py`) listant toute la vague — aperçu, tris, PASS/FAIL, crédits, prompt — à
ouvrir dans un navigateur pour la revue groupée par le lead.

### Promouvoir un asset approuvé dans le jeu

1. Relire sa fiche dans `review.html` (PASS, silhouette conforme à `docs/STYLE_BIBLE.md`).
2. Prop/décor : déplacer le `.glb` (et son `.provenance.json`) vers `assets/models/props/<thème>/`
   ou `assets/models/weapons/`, l'enregistrer dans le catalogue concerné (`PropCatalog`,
   `WeaponConfig`...), puis rejouer `check_asset.py` avec `--asset-class` pour confirmer le budget
   §6.6.
3. Personnage/agent (route texte "forme seule" décrite plus haut) : `tools/blender/
   rig_tripo_character.py --in <glb> --id <agent_id>` (rigging sur le squelette commun), puis
   `tools/review/model_preview.gd` pour valider Idle/Sprint.
4. Ne jamais committer directement depuis `assets/incoming/tripo/` (dossier `.gdignore`, hors
   import Godot) : la promotion COPIE vers l'arborescence `assets/models/` réelle.

### Studio → Blender (réception manuelle, hors manifeste)

Pour un asset façonné à la main dans **Tripo Studio** (web) plutôt que généré par lot : l'extension
officielle **Tripo DCC Bridge** (copiée dans
`%APPDATA%\Blender Foundation\Blender\5.2\scripts\addons\Tripo3d_Blender_Bridge`, serveur WebSocket
local `127.0.0.1:60600`, aucune exposition réseau) reçoit chaque modèle envoyé depuis Studio
(`Exporter › Envoyer à Blender`) et `tools/ai3d/bridge_autoexport.py` l'exporte automatiquement en
GLB vers `assets/incoming/tripo/studio/<nom>.glb` :

```powershell
"C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --factory-startup --python tools/ai3d/bridge_autoexport.py
```

- Fenêtré obligatoire (le Bridge a besoin de la boucle d'événements Blender) ; journal dans
  `assets/incoming/tripo/studio/_bridge_log.txt`.
- Prérequis côté navigateur : Studio doit tourner **sur cette même machine** (un Chrome sur un
  autre PC ne peut pas atteindre `localhost:60600` ici), Chrome doit autoriser « l'accès au réseau
  local » pour `studio.tripo3d.ai` (invite de permission Chrome au premier envoi), et le bouton
  **DCC Bridge › Blender** doit être activé côté Studio.
- Validé le 2026-09-24 (Vif) : Studio › Exporter › nom + GLB + texture 2K › **Envoyer à › Blender** →
  `vif_v1.glb` en ~5 s (14 496 tris, texture JPEG embarquée). Pour une topologie **Quad**, Studio
  transmet un FBX (le Bridge l'importe, le watcher le ré-exporte en GLB triangulé) : normal.
- Si Studio perd la connexion (journal `%TEMP%	ripo3d_blender_bridge.log` : « No active
  connections remaining »), réactiver l'interrupteur **DCC Bridge › Blender** avant d'envoyer.
- Aucune préférence Blender n'est modifiée (extension activée pour la session seulement, voir sa
  docstring) ; ne pas modifier `bridge_autoexport.py` en dehors d'une tâche dédiée.
- Ces `.glb` n'ont PAS de manifeste (pas d'id/prompt/route/priority) : `run_batch.py --ingest-only`
  accepte directement le DOSSIER en entrée (au lieu d'un manifeste YAML) pour les faire vérifier et
  apparaître dans `review.html` :

```powershell
python tools/ai3d/run_batch.py assets/incoming/tripo/studio --ingest-only
```

  Catégorie déduite du préfixe du nom de fichier avant le premier `_` (`weapon_hache.glb` →
  `weapon`, `prop_baril.glb` → `prop`, `fx_etincelle.glb` → `fx`...), repli `prop` sinon ; budget de
  triangles indicatif (`STUDIO_DEFAULT_BUDGET_TRIS`, pas de budget par classe sans manifeste — la
  vraie vérification `--asset-class` se fait à la promotion, comme ci-dessus).
