"""Chargeur partagé de art/style/toon_style.json v2 -- SOURCE UNIQUE consommée par
les trois scripts Blender de ce dossier (toon_bd_nodes.py/ink_bake.py/
render_parity.py) ET par le shader Godot (scripts/core/ToonStyle.gd), jamais un
nombre recopié à la main : un seul endroit à corriger si le JSON change.

Contrairement à la convention "duplication delibérée entre scripts frères" de
tools/blender/*.py (ai_import_painted.py/ai_restyle.py -- éviter un couplage
fragile entre outils indépendants), ce petit module n'a AUCUNE logique métier
(juste `json.load` + résolution de chemin) : le dupliquer trois fois recopierait
la même poignée de lignes sans rien gagner en robustesse, alors qu'un seul point
de lecture du JSON réduit le risque qu'un des trois scripts dérive silencieusement
des deux autres.

Usage (chaque script ajoute d'abord son propre dossier à sys.path -- Blender ne
le fait pas toujours de façon fiable selon comment `-P` est invoqué) :
	import sys, os
	sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
	from _style import load_style, hex_to_rgb, repo_root
"""
from __future__ import annotations

import json
import os

_CACHE: dict | None = None


def repo_root() -> str:
	"""Racine du dépôt -- ce fichier vit dans <repo>/art/style/blender/."""
	here = os.path.dirname(os.path.abspath(__file__))
	return os.path.normpath(os.path.join(here, "..", "..", ".."))


def style_json_path() -> str:
	return os.path.join(repo_root(), "art", "style", "toon_style.json")


def load_style(force_reload: bool = False) -> dict:
	"""JSON complet, mis en cache (un seul `open()` par process Blender)."""
	global _CACHE
	if _CACHE is None or force_reload:
		with open(style_json_path(), "r", encoding="utf-8") as f:
			_CACHE = json.load(f)
	return _CACHE


def hex_to_rgb(value: str, alpha: float = 1.0) -> tuple:
	""""#RRGGBB" -> (r, g, b, a) en LINÉAIRE (0..1) -- Blender attend des couleurs
	linéaires pour un input Color (Principled BSDF, node Color, world) alors que
	le JSON porte des hex sRGB (comme le reste du projet, Godot fait la même
	conversion implicitement via `Color(html)` -> linéaire au rendu)."""
	v = value.lstrip("#")
	r = int(v[0:2], 16) / 255.0
	g = int(v[2:4], 16) / 255.0
	b = int(v[4:6], 16) / 255.0

	def _to_linear(c: float) -> float:
		return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4

	return (_to_linear(r), _to_linear(g), _to_linear(b), alpha)
