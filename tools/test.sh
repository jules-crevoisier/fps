#!/usr/bin/env bash
# Lance les tests gdUnit4 en headless.
# Usage : GODOT_BIN=/chemin/godot tools/test.sh [res://tests/...]  (défaut : res://tests)
# Codes de sortie : 0 = succès, 100 = échecs, 101 = avertissements.
set -u
GODOT="${GODOT_BIN:?definir GODOT_BIN (executable Godot 4.7)}"
TARGET="${1:-res://tests}"
cd "$(dirname "$0")/.."
"$GODOT" --headless --path . --import > /dev/null 2>&1
"$GODOT" --headless --path . -s -d --remote-debug tcp://127.0.0.1:1 \
	res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a "$TARGET" -c --ignoreHeadlessMode
