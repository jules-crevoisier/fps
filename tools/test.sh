#!/usr/bin/env bash
# Lance le garde-fou de licence des assets 3D puis les tests gdUnit4 en headless.
# Usage : GODOT_BIN=/chemin/godot tools/test.sh [res://tests/...]  (défaut : res://tests)
# Codes de sortie : 0 = succès, 1 = violation de licence (voir
#                   tools/ai3d/licence_check.py, section « Contenu généré par IA »
#                   de THIRD_PARTY_LICENSES.md), 100 = échecs gdUnit4,
#                   101 = avertissements gdUnit4.
set -u
GODOT="${GODOT_BIN:?definir GODOT_BIN (executable Godot 4.7)}"
TARGET="${1:-res://tests}"
cd "$(dirname "$0")/.."

# Garde-fou de licence (docs/research/06_ai_3d_pipeline.md §10) : un asset de
# assets/models/** sans ligne dans THIRD_PARTY_LICENSES.md ni provenance.json,
# ou une provenance citant un outil de la liste noire (Hunyuan3D, FLUX.1 [dev],
# Qwen-Image-2.1), fait échouer la suite avant même de lancer Godot.
if ! python3 tools/ai3d/licence_check.py; then
	echo "tools/test.sh : garde-fou de licence en échec (tools/ai3d/licence_check.py) — suite interrompue" >&2
	exit 1
fi

"$GODOT" --headless --path . --import > /dev/null 2>&1
"$GODOT" --headless --path . -s -d --remote-debug tcp://127.0.0.1:1 \
	res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a "$TARGET" -c --ignoreHeadlessMode
