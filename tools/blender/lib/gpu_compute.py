"""Cycles sur la carte graphique + plafond de threads CPU pour les scripts Blender.

Les scripts tournent avec `--factory-startup` : les préférences Cycles repartent à
« CPU » à chaque lancement. `use_gpu_for_cycles(scene)` active le premier backend GPU
disponible (HIP pour la Radeon RX 9060 XT du poste de dev, puis OptiX/CUDA/oneAPI/
Metal ailleurs) et, dans tous les cas, plafonne les threads de rendu à la moitié des
cœurs logiques pour que le poste reste utilisable pendant un bake. Sans GPU
compatible, le bake reste sur CPU (plafonné) : jamais d'échec à cause d'ici.
"""
from __future__ import annotations

import os

import bpy

_BACKENDS = ("HIP", "OPTIX", "CUDA", "ONEAPI", "METAL")
_configured_backend: str | None = None


def cpu_thread_cap() -> int:
	"""Moitié des cœurs logiques, au moins 2 (surchargeable par FPS_BLENDER_THREADS)."""
	env = os.environ.get("FPS_BLENDER_THREADS", "")
	if env.isdigit() and int(env) > 0:
		return int(env)
	return max(2, (os.cpu_count() or 4) // 2)


def _is_integrated(name: str) -> bool:
	n = name.lower()
	return n.endswith("(tm) graphics") or "integrated" in n or "uhd" in n or "iris" in n


def _enable_gpu_backend() -> str | None:
	"""Active le premier backend GPU qui expose un périphérique ; renvoie son nom ou None."""
	addon = bpy.context.preferences.addons.get("cycles")
	if addon is None:
		return None
	prefs = addon.preferences
	for backend in _BACKENDS:
		try:
			prefs.compute_device_type = backend
		except TypeError:
			continue  # backend absent de cette build
		prefs.refresh_devices()
		gpus = [d for d in prefs.devices if d.type == backend]
		if not gpus:
			continue
		# Carte dédiée seulement : le GPU intégré du processeur (« AMD Radeon(TM)
		# Graphics », Intel UHD/Iris) ralentit le bake au lieu de l'aider.
		discrete = [d for d in gpus if not _is_integrated(d.name)] or gpus
		for d in prefs.devices:
			d.use = d in discrete
		return backend
	prefs.compute_device_type = "NONE"
	return None


def use_gpu_for_cycles(scene: bpy.types.Scene) -> str:
	"""Règle `scene` pour un rendu/bake Cycles : GPU si possible, threads CPU plafonnés.

	Renvoie « HIP », « OPTIX »… ou « CPU ». Le backend n'est cherché qu'une fois par
	processus Blender (refresh_devices est lent)."""
	global _configured_backend
	if _configured_backend is None:
		# FPS_BLENDER_GPU=0 force le CPU (comparaison, pilote GPU en panne).
		gpu_off = os.environ.get("FPS_BLENDER_GPU", "") == "0"
		_configured_backend = "CPU" if gpu_off else (_enable_gpu_backend() or "CPU")
	scene.render.threads_mode = "FIXED"
	scene.render.threads = cpu_thread_cap()
	scene.cycles.device = "CPU" if _configured_backend == "CPU" else "GPU"
	return _configured_backend
