#!/usr/bin/env bash
# Rend les maquettes HTML (reports/ui/mockups/*.html) en PNG 1920x1080 avec Edge sans fenêtre.
#   bash tools/ui/render_mockups.sh [page ...]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
EDGE="/c/Program Files (x86)/Microsoft/Edge/Application/msedge.exe"
DIR="$ROOT/reports/ui/mockups"
OUT="$ROOT/reports/ui/renders"
mkdir -p "$OUT"
pages=("$@")
if [ ${#pages[@]} -eq 0 ]; then
  pages=()
  for f in "$DIR"/*.html; do pages+=("$(basename "$f" .html)"); done
fi
for p in "${pages[@]}"; do
  win_out="$(cygpath -w "$OUT/$p.png")"
  url="file:///$(cygpath -m "$DIR/$p.html")"
  "$EDGE" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=1 \
    --allow-file-access-from-files --window-size=1920,1080 --virtual-time-budget=2000 \
    --screenshot="$win_out" "$url" >/dev/null 2>&1 || true
  echo "rendu $p -> reports/ui/renders/$p.png"
done
