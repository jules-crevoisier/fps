"""Réception automatique des modèles Tripo Studio via le DCC Bridge Blender.

Lance Blender (fenêtré — le Bridge a besoin de la boucle d'événements) avec l'extension officielle
« Tripo Bridge » (serveur WebSocket local 127.0.0.1:60600) et surveille la scène : chaque modèle
envoyé depuis Studio (Exporter › Envoyer à Blender) est exporté en GLB dans
assets/incoming/tripo/studio/<nom>.glb, puis retiré de la scène. Aucun téléchargement navigateur,
aucune préférence Blender sauvegardée (l'extension est activée pour cette session seulement).

    "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --factory-startup \
        --python tools/ai3d/bridge_autoexport.py

L'extension doit être copiée une fois dans le dossier d'extensions utilisateur de Blender 5.2
(voir docs/AI_TOOLS.md). Journal : assets/incoming/tripo/studio/_bridge_log.txt.
"""
import datetime
import re
import sys
from pathlib import Path

import addon_utils
import bpy

ROOT = Path(__file__).resolve().parents[2]
OUT_DIR = ROOT / "assets" / "incoming" / "tripo" / "studio"
LOG = OUT_DIR / "_bridge_log.txt"
ADDON = "Tripo3d_Blender_Bridge"
POLL_S = 2.0
# Un modèle est exporté quand sa hiérarchie n'a pas changé pendant ce nombre de relevés
# (le Bridge importe puis renomme la racine et corrige les matériaux en plusieurs étapes).
STABLE_POLLS = 2

_seen: dict[str, tuple[int, int]] = {}  # nom de racine -> (signature, relevés stables)
_exported: set[str] = set()


def log(msg: str) -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    line = f"{datetime.datetime.now():%H:%M:%S} {msg}"
    print(line, flush=True)
    with LOG.open("a", encoding="utf-8") as fh:
        fh.write(line + "\n")


def safe_name(name: str) -> str:
    base = re.sub(r"[^A-Za-z0-9_\-]+", "_", name).strip("_").lower()
    return base or "tripo_model"


def hierarchy(root: bpy.types.Object) -> list[bpy.types.Object]:
    out = [root]
    for child in root.children_recursive:
        out.append(child)
    return out


def signature(objs: list[bpy.types.Object]) -> int:
    parts = []
    for o in objs:
        n = len(o.data.polygons) if o.type == "MESH" and o.data else 0
        mats = ",".join(s.material.name for s in o.material_slots if s.material) if o.type == "MESH" else ""
        parts.append(f"{o.name}:{o.type}:{n}:{mats}")
    return hash("|".join(sorted(parts)))


def export_root(root: bpy.types.Object) -> None:
    objs = hierarchy(root)
    name = safe_name(root.name)
    path = OUT_DIR / f"{name}.glb"
    if path.exists():
        stamp = datetime.datetime.now().strftime("%H%M%S")
        path = OUT_DIR / f"{name}_{stamp}.glb"
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = root
    bpy.ops.export_scene.gltf(
        filepath=str(path),
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_yup=True,
        export_animations=True,
        export_skins=True,
    )
    log(f"exporté {root.name} -> {path.relative_to(ROOT).as_posix()} ({len(objs)} objets)")
    for o in objs:
        bpy.data.objects.remove(o, do_unlink=True)
    bpy.ops.outliner.orphans_purge(do_recursive=True) if hasattr(bpy.ops.outliner, "orphans_purge") else None


def poll() -> float:
    try:
        roots = [o for o in bpy.context.scene.objects if o.parent is None and o.type in {"MESH", "EMPTY", "ARMATURE"}]
        live = set()
        for root in roots:
            if root.name in _exported:
                continue
            live.add(root.name)
            sig = signature(hierarchy(root))
            prev = _seen.get(root.name)
            stable = prev[1] + 1 if prev and prev[0] == sig else 0
            _seen[root.name] = (sig, stable)
            if stable >= STABLE_POLLS and any(o.type == "MESH" for o in hierarchy(root)):
                _exported.add(root.name)
                export_root(root)
        for gone in [n for n in _seen if n not in live]:
            _seen.pop(gone, None)
    except Exception as exc:  # une erreur d'export ne doit jamais arrêter la surveillance
        log(f"ERREUR {type(exc).__name__}: {exc}")
    return POLL_S


def clear_default_scene() -> None:
    for o in list(bpy.context.scene.objects):
        bpy.data.objects.remove(o, do_unlink=True)


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    clear_default_scene()
    mod = addon_utils.enable(ADDON, default_set=False, persistent=False)
    if mod is None:
        log(f"ERREUR : extension {ADDON} introuvable (copiez-la dans le dossier addons de Blender 5.2)")
        sys.exit(1)
    log("Bridge Tripo actif (127.0.0.1:60600) — en attente de modèles depuis Studio")
    bpy.app.timers.register(poll, first_interval=POLL_S, persistent=True)


main()
