# Serveur dédié

Ce document décrit le serveur dédié headless (docs/ROADMAP.md §5, phases
P1.6/P1.7) : démarrage, variables d'environnement, déploiement Dokploy,
chemin de montée en charge vers Edgegap, et notes de sécurité.

---

## 1. Architecture en un coup d'œil

- **`scripts/networking/ServerBoot.gd`** (autoload `Boot`) : détecte le mode
  serveur dédié (tag de fonctionnalité `dedicated_server` de l'export "Linux
  Server", ou argument `--server`), lit la config (`ServerConfig.gd`),
  configure `MatchConfig`, héberge (`NetworkManager`), démarre la sonde de
  santé et charge la carte. Sinon (build normal) : ne fait RIEN, le menu
  principal démarre comme d'habitude.
- **`scripts/networking/HealthServer.gd`** : `GET /health` → JSON
  `{status, players, mode, map, uptime_s}`.
- **`scripts/networking/NetworkManager.gd`** : handshake de connexion
  (version de protocole + jeton optionnel) avant que le pair n'entre en jeu.
- **`scripts/networking/GameWorld.gd`** : en serveur dédié, le process
  serveur n'est **jamais** un joueur (pas de spawn local, pas d'écran de
  sélection d'agent, pas de caméra/HUD) ; les bots continuent de remplir les
  équipes normalement.
- **Un conteneur = un match** (pas plusieurs parties par process — un crash
  n'en tue qu'une).

---

## 2. Lancer en local

### Avec le binaire desktop normal (dev, pas besoin d'exporter)

```bash
MODE=tdm MAP=port_ferraille BOTS=1 \
  "$GODOT_BIN" --headless --path . -- --server
```

`--server` force le mode dédié même sur un build qui n'a pas le tag
`dedicated_server` (réservé à l'export "Linux Server", voir §5). Le serveur
écoute sur `127.0.0.1:7777` (UDP, jeu) et `127.0.0.1:8080` (TCP, santé) :

```bash
curl http://127.0.0.1:8080/health
# {"map":"port_ferraille","mode":"tdm","players":0,"status":"ok","uptime_s":12}
```

### Avec Docker Compose

```bash
cp .env.example .env    # ajuster au besoin
docker compose up --build
```

### À partir d'un binaire déjà exporté (sans l'image godot-ci de 2,6 Go)

Le job CI `export` produit `build/server/fps_server.x86_64`. Avec ce fichier en
place (artefact téléchargé depuis GitHub Actions), l'image se construit sur la
seule base `debian:trixie-slim` :

```bash
docker build --build-arg BINARY_SOURCE=prebuilt -t fps-server .
```

C'est ce que fait le job CI `docker` : build, démarrage d'un match TDM avec
bots, attente de `/health`, puis affichage de la taille de l'image.

---

## 3. Variables d'environnement

Lues par `ServerConfig.gd` (`tests/networking/test_server_config.gd` couvre
le détail des valeurs par défaut/formats acceptés). Toutes optionnelles.

| Variable | Défaut | Description |
|---|---|---|
| `PORT` | `7777` | Port UDP du jeu (ENet). |
| `HEALTH_PORT` | `8080` | Port TCP de la sonde `GET /health`. |
| `MODE` | `tdm` | `tdm` \| `hardpoint` \| `snd` \| `duel` \| `duo`. |
| `MAP` | *(défaut du mode)* | Identifiant `MapCatalog` (ex. `port_ferraille`). |
| `MAX_PLAYERS` | `16` | Capacité ENet (joueurs humains simultanés). |
| `BOTS` | `true` | Remplit les équipes avec des bots (`true`/`1`/`yes`/`on` ↔ `false`/`0`/`no`/`off`). |
| `BOT_DIFFICULTY` | `veteran` | `recrue` \| `veteran` \| `elite`. |
| `MATCH_TOKEN_SECRET` | *(vide)* | Secret HMAC-SHA256 des jetons de connexion — vide = aucun jeton exigé (voir §6). |
| `MATCH_ID` | *(aléatoire)* | Identifiant de partie, lié aux jetons de connexion. |
| `RESTART_ON_END` | `true` | Fin de match : relance sur la même carte/mode (`true`) ou quitte avec le code 0 (`false`, laisse l'orchestrateur recycler le conteneur). |

Chaque clé peut aussi être passée en argument `--CLE=valeur` (utile pour un
test local rapide sans fichier `.env`), qui prime sur la variable
d'environnement du même nom.

---

## 4. Déployer sur Dokploy

1. Créer une application Dokploy de type **Docker Compose**, pointer vers ce
   dépôt (`docker-compose.yml` à la racine).
2. Renseigner les variables de l'onglet **Environment** avec les clés du §3
   (au minimum `MODE`/`MAP` ; laisser `MATCH_TOKEN_SECRET` vide tant qu'il
   n'y a pas de matchmaking externe).
3. Ouvrir le port **UDP** `7777` (ou la valeur de `PORT`) dans les réglages
   réseau du service — Dokploy expose les ports TCP par défaut, l'UDP doit
   être activé explicitement pour ce service.
4. Déployer. Dokploy utilise le `HEALTHCHECK` du `Dockerfile` pour les
   bascules sans coupure (zero-downtime swap) — un serveur qui ne répond pas
   `200` sur `/health` n'est jamais mis en trafic.

### Plusieurs matchs

Un conteneur = un match (§1). Pour N matchs simultanés sur la même
instance Dokploy : dupliquer le service `fps-server` du compose (un nom, un
`PORT` et un mapping de port différents par copie — voir les commentaires de
`docker-compose.yml`), ou créer N applications Dokploy distinctes à partir du
même `Dockerfile`. `RESTART_ON_END=true` (défaut) fait qu'un conteneur reste
en place et enchaîne les matchs, sans redéploiement.

### Montée en charge : Edgegap

Le pool fixe sur Dokploy est le point de départ (une poignée de serveurs,
une seule région). Pour plusieurs régions et de l'allocation à la demande
(un conteneur par match, démarré/arrêté automatiquement selon la demande
joueurs), l'étape suivante est **Edgegap** : même image Docker (ce
`Dockerfile` n'a pas besoin de changer), Edgegap route les joueurs vers
l'instance la plus proche et gère le cycle de vie du conteneur — c'est
exactement ce que permet déjà `RESTART_ON_END=false` (le conteneur quitte
proprement en code 0 une fois le match fini, pour être recyclé par
l'orchestrateur plutôt que réutilisé en place). Non fait dans cette
livraison : intégration à l'API Edgegap (matchmaking → allocation de
conteneur) — voir docs/ROADMAP.md §5 pour le reste du plan (Nakama,
matchmaking, classements).

---

## 5. Vérifier sans builder l'image Docker

L'image `barichello/godot-ci:4.7` doit être tirée pour builder — étape
volontairement PAS automatisée ici (nécessite l'accord explicite de
l'utilisateur, voir la procédure de vérification). En attendant :

- **Localement** : §2 ci-dessus (binaire desktop + `--server`), `curl
  /health`, et `tools/net_smoke.gd` / `tests/networking/server_join_smoke.gd`
  (jonction normale + refus de version, voir leurs en-têtes de fichier pour
  la commande exacte).
- **Syntaxe compose seule** (si Docker est installé, sans tirer d'image) :
  `docker compose config`.
- **Suite de tests** : `bash tools/test.sh` (parties pures — config, jeton,
  version — dans `tests/networking/`).

---

## 6. Sécurité

- **Le client est open source** (docs/ROADMAP.md §5, gdsdecomp reconstitue
  tout build) : rien de secret ne doit vivre côté client. Le code serveur
  (`scripts/networking/ServerBoot.gd`, `HealthServer.gd`) est exclu des
  exports client par `export_presets.cfg` (`exclude_filter`), mais ce n'est
  qu'une couche — l'autorité réelle reste le SERVEUR (voir
  docs/MULTIPLAYER.md §2 : vie, armes, capacités, spawn — tout côté serveur).
- **Handshake de connexion** : chaque pair envoie sa version de protocole
  (`ProtocolVersion.gd`) avant d'entrer en jeu ; une version différente est
  refusée avec un motif (`NetworkManager.last_disconnect_reason`) — évite
  qu'un client desynchronisé (format de message RPC différent) ne rejoigne.
- **Jetons de connexion optionnels** (`MATCH_TOKEN_SECRET`, `JoinToken.gd`) :
  HMAC-SHA256 liant un `player_id` (fourni par un matchmaking externe, pas
  l'id de pair ENet) à un `match_id`. Vide par défaut — le LAN/host play
  normal n'a jamais besoin d'en configurer. À activer dès qu'un service de
  matchmaking distribue l'accès aux serveurs.
- **`MATCH_TOKEN_SECRET` ne doit JAMAIS être journalisé** — `ServerBoot._log_event`
  ne loggue que `token_required` (booléen), jamais le secret lui-même ; à
  vérifier dans toute évolution de la journalisation.
- **`.env` ne doit jamais être committé** — `.env.example` liste les clés
  attendues sans valeur sensible ; s'assurer que `.env` figure dans
  `.gitignore` avant tout `git add` (absent du `.gitignore` actuel au moment
  de cette livraison — à ajouter).
- **Anti-triche** : au-delà du handshake, l'autorité serveur sur tout le
  gameplay (docs/MULTIPLAYER.md) reste la protection principale. EAC via EOS
  reste à étudier plus tard (docs/ROADMAP.md §5) — non traité ici.
- Conteneur non-root (`USER fps` dans le `Dockerfile`), aucune image
  `:latest` (base `debian:trixie-slim` pinnée en majeur.mineur), aucun
  secret en `ARG`/gravé dans l'image (variables d'environnement runtime
  uniquement).
