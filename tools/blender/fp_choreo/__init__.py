## tools/blender/fp_choreo -- FP-13 (docs/research/12_viewmodel_v2.md §3.5)
## Chorégraphies FP décrites en données (aucun bpy) : `common` porte le DSL,
## les validateurs et les mesures ; un module par famille d'armes construit
## les 7 clips (`rifle` = fusil à chargeur : Ravage, puis Rafale et Marqueur
## en FP-18, sans modification). `make_fp_viewmodel.py` choisit la famille
## par le champ `family` du manifeste `tools/ai3d/manifests/fp/<id>.yaml`.
from __future__ import annotations

from . import common, rifle

FAMILIES = {
	"rifle": rifle,
}


def family_module(name: str):
	"""Module de la famille `name` (doit exposer `params_from_config` et
	`build_clips`) ; ValueError si la famille n'existe pas."""
	if name not in FAMILIES:
		raise ValueError(f"fp_choreo: famille inconnue {name!r} (connues : {sorted(FAMILIES)})")
	return FAMILIES[name]


__all__ = ["FAMILIES", "common", "family_module", "rifle"]
