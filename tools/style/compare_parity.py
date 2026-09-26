"""compare_parity.py -- compare le rendu Godot et le rendu Blender de
"parity_scene" (art/style/toon_style.json v2) : image côte-à-côte +
différence absolue moyenne, comparée à `parity_scene.max_mean_abs_diff`.

Usage :
	python tools/style/compare_parity.py \\
		--godot reports/checkpoints/2026-09-26_toon_bd/parity_godot.png \\
		--blender reports/checkpoints/2026-09-26_toon_bd/parity_blender.png \\
		--out reports/checkpoints/2026-09-26_toon_bd/parity_side_by_side.png

Sortie : image côte-à-côte (+ une 3e colonne "diff" en fausses couleurs) écrite
sur `--out`, et un résumé JSON imprimé sur stdout : {"mean_abs_diff", "target",
"pass"}. Code de sortie 0 si `mean_abs_diff <= target`, 1 sinon (jamais une
exception pour un simple dépassement de seuil -- seulement pour un fichier
manquant/illisible).
"""
from __future__ import annotations

import argparse
import json
import os
import sys

import numpy as np
from PIL import Image

_REPO_ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
_STYLE_JSON = os.path.join(_REPO_ROOT, "art", "style", "toon_style.json")


def _load_default_threshold() -> float:
	try:
		with open(_STYLE_JSON, "r", encoding="utf-8") as f:
			style = json.load(f)
		return float(style.get("parity_scene", {}).get("max_mean_abs_diff", 0.06))
	except (OSError, ValueError, KeyError):
		return 0.06


def _load_rgb(path: str, size: tuple) -> np.ndarray:
	img = Image.open(path).convert("RGB")
	if img.size != size:
		img = img.resize(size, Image.BILINEAR)
	return np.asarray(img, dtype=np.float32) / 255.0


def _parse_args() -> argparse.Namespace:
	p = argparse.ArgumentParser(description=__doc__)
	p.add_argument("--godot", required=True)
	p.add_argument("--blender", required=True)
	p.add_argument("--out", required=True)
	p.add_argument("--threshold", type=float, default=None, help="Repli sur parity_scene.max_mean_abs_diff du JSON si omis")
	return p.parse_args()


def compare(godot_path: str, blender_path: str, out_path: str, threshold: float | None = None) -> dict:
	threshold = threshold if threshold is not None else _load_default_threshold()
	godot_img = Image.open(godot_path).convert("RGB")
	size = godot_img.size
	godot_arr = np.asarray(godot_img, dtype=np.float32) / 255.0
	blender_arr = _load_rgb(blender_path, size)

	diff = np.abs(godot_arr - blender_arr)
	mean_abs_diff = float(diff.mean())

	# Fausses couleurs (rouge = écart fort) pour la 3e colonne, normalisées à
	# la différence max observée (pas au seuil -- on veut VOIR la texture de
	# l'écart, pas juste un pass/fail binaire en image).
	diff_gray = diff.mean(axis=-1)
	diff_max = max(float(diff_gray.max()), 1e-6)
	diff_vis = np.zeros_like(godot_arr)
	diff_vis[..., 0] = np.clip(diff_gray / diff_max, 0.0, 1.0)

	gutter = np.ones((size[1], 4, 3), dtype=np.float32) * 0.5
	side_by_side = np.concatenate([godot_arr, gutter, blender_arr, gutter, diff_vis], axis=1)
	out_img = Image.fromarray((np.clip(side_by_side, 0.0, 1.0) * 255.0).astype(np.uint8))
	out_dir = os.path.dirname(os.path.abspath(out_path))
	if out_dir:
		os.makedirs(out_dir, exist_ok=True)
	out_img.save(out_path)

	return {
		"mean_abs_diff": mean_abs_diff,
		"target": threshold,
		"pass": mean_abs_diff <= threshold,
		"out": out_path,
	}


def main() -> int:
	args = _parse_args()
	result = compare(args.godot, args.blender, args.out, args.threshold)
	print(json.dumps(result, indent=2))
	return 0 if result["pass"] else 1


if __name__ == "__main__":
	sys.exit(main())
