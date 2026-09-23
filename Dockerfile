# syntax=docker/dockerfile:1
# Dockerfile — serveur dédié headless (docs/ROADMAP.md §5, docs/SERVER.md).
# Multi-stage : stage 1 exporte le binaire "Linux Server" avec la MÊME image
# Godot que la CI (.github/workflows/ci.yml, "Export (...)") pour un binaire
# identique à celui déjà validé en CI ; stage 2 ne contient QUE ce binaire,
# sur une base minimale, utilisateur non-root.

# Source du binaire serveur : `export` (défaut) l'exporte ici avec l'image
# Godot de la CI ; `prebuilt` reprend build/server/fps_server.x86_64 déjà
# exporté (artefact du job CI "export") et évite de tirer l'image godot-ci
# (2,6 Go). BuildKit saute l'étape non utilisée.
#   docker build --build-arg BINARY_SOURCE=prebuilt -t fps-server .
ARG BINARY_SOURCE=export

# ---------------------------------------------------------------- Stage 1 : export
FROM barichello/godot-ci:4.7 AS export

# Doit rester alignée avec GODOT_VERSION dans ci.yml et config/features dans
# project.godot.
ARG GODOT_VERSION=4.7

WORKDIR /app
COPY . .

# L'image embarque les modèles d'export sous /root, mais un HOME différent
# (selon l'environnement de build) ne les y retrouverait pas — même
# relocalisation défensive que ci.yml ("Préparer les modèles d'export"),
# sans effet si $HOME est déjà /root (cas normal d'un `docker build`).
RUN if [ "$HOME" != "/root" ] && [ -d "/root/.local/share/godot/export_templates/${GODOT_VERSION}.stable" ]; then \
        mkdir -p "$HOME/.local/share/godot/export_templates/" && \
        mv "/root/.local/share/godot/export_templates/${GODOT_VERSION}.stable" \
           "$HOME/.local/share/godot/export_templates/${GODOT_VERSION}.stable"; \
    fi

RUN mkdir -p build/server \
    && godot --headless --path . --import \
    && godot --headless --path . --export-release "Linux Server" "$(pwd)/build/server/fps_server.x86_64"

# ---------------------------------------------------------------- Stage 1 bis : binaire déjà exporté
FROM scratch AS prebuilt
COPY build/server/fps_server.x86_64 /app/build/server/fps_server.x86_64

FROM ${BINARY_SOURCE} AS binary

# ---------------------------------------------------------------- Stage 2 : runtime
FROM debian:trixie-slim AS runtime

# ca-certificates : sorties HTTPS futures (télémétrie/Sentry, docs/ROADMAP.md
# §5) — rien d'autre n'est nécessaire (export "Linux Server" = binaire
# headless autonome, PCK embarqué : binary_format/embed_pck=true dans
# export_presets.cfg, donc un seul fichier à copier).
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN groupadd --system fps && useradd --system --gid fps --create-home --home-dir /home/fps fps

WORKDIR /app
COPY --from=binary /app/build/server/fps_server.x86_64 /app/fps_server.x86_64
COPY THIRD_PARTY_LICENSES.md /app/THIRD_PARTY_LICENSES.md
RUN chmod +x /app/fps_server.x86_64 && chown -R fps:fps /app

USER fps

# Lus par ServerBoot.gd (scripts/networking/ServerConfig.gd) — voir
# .env.example pour la liste complète des variables et leurs défauts.
ENV PORT=7777 \
    HEALTH_PORT=8080

EXPOSE 7777/udp
EXPOSE 8080/tcp

# Sonde HTTP GET /health (HealthServer.gd) sans dépendance externe : bash a
# /dev/tcp en builtin, présent par défaut sur debian:trixie-slim (pas besoin
# de curl/wget, qui alourdiraient l'image pour ce seul usage).
HEALTHCHECK --interval=10s --timeout=3s --start-period=20s --retries=3 \
    CMD bash -c 'exec 3<>"/dev/tcp/127.0.0.1/${HEALTH_PORT}" \
        && printf "GET /health HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n" >&3 \
        && head -c 15 <&3 | grep -q "200"' || exit 1

# L'export "Linux Server" porte le tag de fonctionnalité "dedicated_server"
# (dedicated_server=true dans export_presets.cfg) : ServerBoot.gd le détecte
# automatiquement (OS.has_feature) et démarre le serveur SANS argument
# supplémentaire — voir docs/SERVER.md pour l'équivalent en local
# (`--headless -- --server` avec le binaire desktop normal).
ENTRYPOINT ["/app/fps_server.x86_64"]
