## tools/blender/make_fp_viewmodel.py -- FP-13 (docs/research/12_viewmodel_v2.md §3.5–3.7)
## Générateur de viewmodel FP par arme : rig de bras FP-10 (UAL) + arme v2
## (FP-11 : pièces skinnées rigides sur fp_weapon/fp_mag/...) + les 7 clips du
## DSL fp_choreo, cuits à 60 i/s (IK résolue ici, attaches Child Of cuites),
## poussés dans le NLA et exportés en glTF mode ACTIONS. Sorties :
##   assets/models/fp/fp_<id>.glb               -- Skeleton3D + maillages skinnés
##                                                 arms / wpn_body / wpn_<pièce> + 7 clips
##   assets/models/fp/fp_<id>.json              -- contrat §3.6 (clips, événements, repères)
##   assets/models/fp/fp_<id>_report.json       -- contrôles §3.7 à CHAQUE image
##   assets/models/fp/fp_<id>.provenance.json   -- sources (licence_check.py)
##   <checkpoint-dir>/fp_<id>_planche_*.jpg     -- planches contact (modes avant-bras / mains flottantes)
##
## UNE commande, en Python système (lit le manifeste YAML et le .tres, lance
## Blender pour chaque mode de bras, compose les planches) :
##   python tools/blender/make_fp_viewmodel.py --id ravage \
##       --checkpoint-dir reports/checkpoints/2026-09-25_FP-13
## Options : --modes forearm,floating ; --out-dir (défaut assets/models/fp) ;
## --work-dir (défaut : dossier temporaire du système) ; --no-render ; --blender.
## Le mode "forearm" écrit le livrable dans --out-dir ; le mode "floating"
## (A/B « mains flottantes », doc 12 §3.2) écrit dans --work-dir seulement.
## Relancer la même commande après FP-10B (mains) ou FP-12B (métal) suffit :
## le rig est relu dans assets/models/fp/fp_arms*.glb et l'albédo dans
## assets/textures/weapons/<id>_albedo.png.
##
## Côté Blender (appelé par la commande ci-dessus, avec un JSON de config
## résolu -- le Python embarqué de Blender n'a pas PyYAML) :
##   blender -b --factory-startup -P tools/blender/make_fp_viewmodel.py -- --config <json>
##
## Deux familles de fonctions (même convention que fp_rig.py) :
##   1. PURES (aucun bpy) : lecture .tres/manifeste, contrat JSON, lecture GLB,
##      évaluation des contrôles, composition des planches (PIL) -- testées par
##      tools/blender/tests/test_make_fp_viewmodel.py ;
##   2. bpy : import, mesures sur le rig et l'arme, cadrage de hanche, cuisson
##      des clips, rapport, export, rendu des planches.
##
## Sondage de l'API bpy 5.2 (risque §5.3 du doc 12, `probe_bpy_api`) : Action
## à slots (`fcurve_ensure_for_datablock`), propriétés d'export
## `export_animation_mode` (ACTIONS), `export_def_bones`,
## `export_reset_pose_bones`, `export_force_sampling`,
## `export_optimize_animation_size` -- échec explicite si l'une manque.
from __future__ import annotations

import argparse
import datetime
import json
import math
import os
import re
import struct
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.dirname(os.path.dirname(HERE))
if HERE not in sys.path:
	sys.path.insert(0, HERE)

from fp_choreo import common as C  # noqa: E402
from fp_choreo import family_module  # noqa: E402

try:
	import bpy
	import bmesh
	from mathutils import Matrix, Quaternion, Vector
	from mathutils.bvhtree import BVHTree
except ImportError:  # pragma: no cover - logique pure testable hors Blender
	bpy = None

MANIFEST_DIR = os.path.join(REPO_ROOT, "tools", "ai3d", "manifests", "fp")
DEFAULT_OUT_DIR = os.path.join(REPO_ROOT, "assets", "models", "fp")
BLENDER_BIN = os.environ.get("BLENDER_BIN", r"C:\Program Files\Blender Foundation\Blender 5.2\blender.exe")
ARMS_MODES = ("forearm", "floating")
SCRIPT_REL = "tools/blender/make_fp_viewmodel.py"

# Couverture à la hanche, bras compris (doc 12 §3.7).
COVERAGE_RANGES = {
	"pistol": (0.07, 0.15), "smg": (0.11, 0.19), "rifle": (0.13, 0.21),
	"shotgun": (0.15, 0.23), "sniper": (0.12, 0.23),
}
# Seuils du rapport (doc 12 §3.7, critères d'acceptation FP-13).
THRESHOLDS = {
	"palm_R_cm": 1.5,
	"palm_L_cm": 1.5,
	"finger_penetration_mm": 5.0,
	"mag_offscreen_s": 0.15,
	"center_vertices": 0,
	"top_third_vertices": 0,
	"muzzle_x": (0.58, 0.64),
	"muzzle_y": (0.56, 0.64),
}
LEFT_PALM_CLIPS = ("idle_loop", "fire", "run_loop")       # + extrémités de reload/reload_empty.
RELOAD_CLIPS = ("reload", "reload_empty")
CENTER_EXEMPT_CLIPS = ("inspect",)
HIP_CLIPS = ("idle_loop",)                                # « à la hanche » : pose de repos.
NOMINAL_LENGTHS = {"idle_loop": 3.0, "run_loop": 0.66, "fire": 0.16, "draw": 0.40, "inspect": 3.0}
SOCKETS_EXPORTED = ("Muzzle", "Sight", "Eject", "Grip", "Foregrip", "MagWell")

# Planche contact : (clip, fraction ou nom d'événement, légende).
SHEET_SHOTS = (
	("idle_loop", 0.0, "Repos (hanche)"),
	("fire", "peak", "Pic de tir"),
	("draw", 0.5, "Dégainer 50 %"),
	("reload", 0.10, "Recharger 10 %"),
	("reload", 0.25, "Recharger 25 %"),
	("reload", 0.40, "Recharger 40 %"),
	("reload", 0.55, "Recharger 55 %"),
	("reload", 0.70, "Recharger 70 %"),
	("reload", 0.85, "Recharger 85 %"),
	("reload_empty", "bolt", "À vide : culasse"),
	("run_loop", 0.25, "Course"),
	("inspect", 0.5, "Inspection 50 %"),
)
MODE_LABELS = {"forearm": "avant-bras", "floating": "mains flottantes"}


# ---------------------------------------------------------------------------
# 1. Entrées : .tres, manifeste, configuration résolue.
# ---------------------------------------------------------------------------

def read_reload_time(tres_path: str) -> float:
	"""`reload_time` du WeaponConfig Godot (doc 12 §3.5 : lu, jamais recopié)."""
	with open(tres_path, encoding="utf-8") as fh:
		text = fh.read()
	m = re.search(r"^\s*reload_time\s*=\s*([0-9]+(?:\.[0-9]+)?)\s*$", text, re.MULTILINE)
	if m is None:
		raise ValueError(f"make_fp_viewmodel: reload_time introuvable dans {tres_path}")
	return float(m.group(1))


def _repo_path(rel: str) -> str:
	return rel if os.path.isabs(rel) else os.path.join(REPO_ROOT, rel.replace("/", os.sep))


def load_manifest(weapon_id: str, manifest_dir: str = MANIFEST_DIR) -> dict:
	import yaml
	path = os.path.join(manifest_dir, f"{weapon_id}.yaml")
	if not os.path.isfile(path):
		raise FileNotFoundError(f"make_fp_viewmodel: manifeste introuvable {path}")
	with open(path, encoding="utf-8") as fh:
		data = yaml.safe_load(fh)
	errors = validate_manifest(data, weapon_id)
	if errors:
		raise ValueError("make_fp_viewmodel: manifeste invalide :\n  - " + "\n  - ".join(errors))
	return data


def validate_manifest(data, weapon_id: str) -> list:
	errors = []
	if not isinstance(data, dict):
		return ["le manifeste n'est pas un dictionnaire"]
	for key in ("id", "family", "category", "weapon_glb", "tres", "arms", "pieces", "hip", "sockets", "ads_depth"):
		if key not in data:
			errors.append(f"clé manquante {key!r}")
	if errors:
		return errors
	if data["id"] != weapon_id:
		errors.append(f"id {data['id']!r} != {weapon_id!r}")
	try:
		fam = family_module(data["family"])
	except ValueError as exc:
		return errors + [str(exc)]
	if data["category"] not in COVERAGE_RANGES:
		errors.append(f"catégorie {data['category']!r} inconnue ({sorted(COVERAGE_RANGES)})")
	for mode in ARMS_MODES:
		if mode not in data["arms"]:
			errors.append(f"arms.{mode} manquant")
	for sock in fam.REQUIRED_SOCKETS:
		if sock not in data["sockets"]:
			errors.append(f"repère de prise {sock!r} manquant (famille {data['family']})")
	for name, spec in data["sockets"].items():
		for key in ("hand", "from", "offset", "cast", "palm", "knuckles"):
			if key not in spec:
				errors.append(f"sockets.{name}.{key} manquant")
		if spec.get("hand") not in ("L", "R"):
			errors.append(f"sockets.{name}.hand doit valoir L ou R")
		if spec.get("cast") not in ("body", "mag", "none"):
			errors.append(f"sockets.{name}.cast doit valoir body, mag ou none")
	for key in ("muzzle_screen", "convergence_m", "muzzle_depth", "coverage_target"):
		if key not in data["hip"]:
			errors.append(f"hip.{key} manquant")
	for piece in data["pieces"]:
		if piece not in C.PIECES:
			errors.append(f"pièce {piece!r} hors contrat ({C.PIECES})")
	return errors


def resolve_config(manifest: dict, mode: str, out_dir: str, render_dir: str) -> dict:
	"""Configuration complète pour le côté Blender (JSON) : chemins absolus,
	`reload_time` lu dans le .tres, paramètres de famille validés."""
	if mode not in ARMS_MODES:
		raise ValueError(f"make_fp_viewmodel: mode de bras invalide {mode!r} ({ARMS_MODES})")
	reload_time = read_reload_time(_repo_path(manifest["tres"]))
	fam = family_module(manifest["family"])
	fam.params_from_config(manifest.get("choreo") or {}, reload_time)
	albedo = manifest.get("albedo")
	arms = manifest["arms"]
	return {
		"id": manifest["id"], "family": manifest["family"], "category": manifest["category"],
		"mode": mode, "reload_time": reload_time,
		"weapon_glb": _repo_path(manifest["weapon_glb"]),
		"weapon_provenance": _repo_path(manifest["weapon_provenance"]) if manifest.get("weapon_provenance") else "",
		"albedo": _repo_path(albedo) if albedo and os.path.isfile(_repo_path(albedo)) else "",
		"arms_glb": _repo_path(arms[mode]),
		"shoulder": arms.get("shoulder", {}), "pole_offset": arms.get("pole_offset", {}),
		"shoulder_follow": arms.get("shoulder_follow", {}),
		"pieces": manifest["pieces"], "hip": manifest["hip"], "sockets": manifest["sockets"],
		"ads_depth": float(manifest["ads_depth"]), "choreo": manifest.get("choreo") or {},
		"out_dir": os.path.abspath(out_dir), "render_dir": os.path.abspath(render_dir) if render_dir else "",
		"manifest_rel": f"tools/ai3d/manifests/fp/{manifest['id']}.yaml",
		"tres_rel": manifest["tres"], "weapon_glb_rel": manifest["weapon_glb"],
		"arms_glb_rel": arms[mode], "albedo_rel": albedo or "",
	}


def output_paths(out_dir: str, weapon_id: str, mode: str) -> dict:
	stem = f"fp_{weapon_id}" if mode == "forearm" else f"fp_{weapon_id}_floating"
	return {
		"glb": os.path.join(out_dir, f"{stem}.glb"),
		"json": os.path.join(out_dir, f"{stem}.json"),
		"report": os.path.join(out_dir, f"{stem}_report.json"),
		"provenance": os.path.join(out_dir, f"{stem}.provenance.json"),
	}


# ---------------------------------------------------------------------------
# 2. Lecture GLB (pure) : structure, durées des animations, poses de repos.
# ---------------------------------------------------------------------------

def read_glb_json(path: str) -> dict:
	with open(path, "rb") as fh:
		head = fh.read(20)
		magic, _version, _length = struct.unpack("<III", head[:12])
		if magic != 0x46546C67:
			raise ValueError(f"make_fp_viewmodel: {path} n'est pas un GLB")
		chunk_len, chunk_type = struct.unpack("<II", head[12:20])
		if chunk_type != 0x4E4F534A:
			raise ValueError(f"make_fp_viewmodel: premier bloc de {path} non JSON")
		return json.loads(fh.read(chunk_len))


def glb_summary(path: str) -> dict:
	"""Structure utile d'un GLB FP : nœuds, articulations du squelette,
	maillages skinnés (nom du nœud -> nom du maillage), durées des
	animations (max des entrées d'échantillonneur, en s)."""
	gl = read_glb_json(path)
	nodes = gl.get("nodes", [])
	joints = []
	for skin in gl.get("skins", []):
		joints.extend(nodes[j].get("name", "") for j in skin["joints"])
	skinned = {}
	for n in nodes:
		if "mesh" in n and "skin" in n:
			skinned[n.get("name", "")] = gl["meshes"][n["mesh"]].get("name", "")
	animations = {}
	for anim in gl.get("animations", []):
		t_max = 0.0
		for sampler in anim["samplers"]:
			acc = gl["accessors"][sampler["input"]]
			t_max = max(t_max, float(acc["max"][0]))
		animations[anim.get("name", "")] = t_max
	roots = [nodes[i].get("name", "") for i in gl["scenes"][gl.get("scene", 0)]["nodes"]]
	return {"joints": sorted(set(joints)), "skinned": skinned, "animations": animations, "roots": roots,
		"node_names": [n.get("name", "") for n in nodes]}


def _trs_matrix(node: dict):
	import numpy as np
	t = node.get("translation", [0.0, 0.0, 0.0])
	x, y, z, w = node.get("rotation", [0.0, 0.0, 0.0, 1.0])
	s = node.get("scale", [1.0, 1.0, 1.0])
	if "matrix" in node:
		return np.array(node["matrix"], dtype=np.float64).reshape(4, 4).T
	rot = np.array([
		[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
		[2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
		[2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)],
	])
	m = np.eye(4)
	m[:3, :3] = rot * np.array(s)[None, :]
	m[:3, 3] = t
	return m


def glb_rest_globals(path: str) -> dict:
	"""Matrices globales (espace glTF = caméra Godot) de repos de chaque nœud
	nommé -- sert à exprimer les repères dans l'espace de l'os fp_weapon, tel
	que Godot le reconstruit (Skeleton3D : repos = TRS des nœuds)."""
	import numpy as np
	gl = read_glb_json(path)
	nodes = gl["nodes"]
	out = {}

	def walk(i, parent):
		m = parent @ _trs_matrix(nodes[i])
		out[nodes[i].get("name", f"node{i}")] = m
		for c in nodes[i].get("children", []):
			walk(c, m)

	for root in gl["scenes"][gl.get("scene", 0)]["nodes"]:
		walk(root, np.eye(4))
	return out


# ---------------------------------------------------------------------------
# 3. Contrat JSON §3.6 et contrôles §3.7 (purs).
# ---------------------------------------------------------------------------

def _round_list(values, nd=5):
	return [round(float(v), nd) for v in values]


def socket_in_bone(bone_global, socket_global: C.Transform) -> dict:
	"""Repère exprimé dans l'espace de l'os (origine + base en colonnes)."""
	import numpy as np
	s = np.eye(4)
	s[:3, :3] = np.array(C.q_columns(socket_global.q)).T
	s[:3, 3] = socket_global.p
	rel = np.linalg.inv(bone_global) @ s
	basis = [rel[r, c] for c in range(3) for r in range(3)]
	return {"bone": "fp_weapon", "origin": _round_list(rel[:3, 3]), "basis": _round_list(basis)}


def build_fp_json(weapon_id: str, family: str, mode: str, clips, hip: C.Transform, anchors: dict,
		bone_global, ads_depth: float, report_summary: dict) -> dict:
	sockets = {}
	for name in SOCKETS_EXPORTED:
		if name in anchors:
			sockets[name] = socket_in_bone(bone_global, hip.compose(anchors[name]))
	sight_cam = hip.apply(anchors["Sight"].p) if "Sight" in anchors else hip.p
	muzzle_cam = hip.apply(anchors["Muzzle"].p) if "Muzzle" in anchors else hip.p
	return {
		"version": 1, "id": weapon_id, "family": family, "fps": C.FPS, "arms_mode": mode,
		"basis_layout": "columns",
		"clips": {
			clip.name: {
				"length": round(clip.length, 6), "frames": clip.frames, "loop": clip.loop,
				"events": [{"t": round(ev.t, 4), "name": ev.name, "time": round(ev.t * clip.length, 4)}
					for ev in clip.events],
			} for clip in clips
		},
		"sockets": sockets,
		"hip": {
			"weapon": {"origin": _round_list(hip.p), "basis": _round_list(hip.basis_columns())},
			"sight_cam": _round_list(sight_cam), "muzzle_cam": _round_list(muzzle_cam),
		},
		"ads_depth": ads_depth,
		"report": report_summary,
	}


def validate_fp_json(data: dict, windows: dict = None) -> list:
	"""Validation du contrat §3.6 (+ fenêtres d'événements de la famille)."""
	errors = []
	for key in ("version", "id", "family", "fps", "clips", "sockets", "hip", "ads_depth", "report"):
		if key not in data:
			errors.append(f"clé manquante {key!r}")
	if errors:
		return errors
	if data["version"] != 1:
		errors.append("version != 1")
	if data["fps"] != C.FPS:
		errors.append(f"fps {data['fps']} != {C.FPS}")
	if sorted(data["clips"]) != sorted(C.CLIP_NAMES):
		errors.append(f"clips {sorted(data['clips'])} != {sorted(C.CLIP_NAMES)}")
	for name, clip in data["clips"].items():
		if clip.get("loop") != (name in C.LOOP_CLIPS):
			errors.append(f"{name}.loop incohérent")
		if not clip.get("length", 0) > 0:
			errors.append(f"{name}.length <= 0")
		times = []
		for ev in clip.get("events", []):
			if ev.get("name") not in C.EVENT_NAMES:
				errors.append(f"{name} : événement hors liste {ev.get('name')!r}")
			if not 0.0 <= ev.get("t", -1) < C.EVENT_MAX_T:
				errors.append(f"{name}.{ev.get('name')} : t={ev.get('t')} hors de [0 ; {C.EVENT_MAX_T}[")
			times.append(ev.get("t", 0))
		if times != sorted(times):
			errors.append(f"{name} : événements non triés")
	for sname, sock in data["sockets"].items():
		if sock.get("bone") != "fp_weapon" or len(sock.get("origin", [])) != 3 or len(sock.get("basis", [])) != 9:
			errors.append(f"repère {sname} mal formé")
	for sname in ("Muzzle", "Sight", "Eject"):
		if sname not in data["sockets"]:
			errors.append(f"repère {sname} manquant")
	hip = data["hip"]
	if len(hip.get("weapon", {}).get("origin", [])) != 3 or len(hip.get("weapon", {}).get("basis", [])) != 9:
		errors.append("hip.weapon mal formé")
	if len(hip.get("sight_cam", [])) != 3:
		errors.append("hip.sight_cam mal formé")
	for key in ("coverage_hip", "muzzle_screen", "center_clear"):
		if key not in data["report"]:
			errors.append(f"report.{key} manquant")
	for clip_name, wins in (windows or {}).items():
		evs = {ev["name"]: ev["t"] for ev in data["clips"].get(clip_name, {}).get("events", [])}
		for ev_name, (lo, hi) in wins.items():
			if ev_name not in evs:
				errors.append(f"{clip_name}.{ev_name} absent")
			elif not lo <= evs[ev_name] <= hi:
				errors.append(f"{clip_name}.{ev_name} = {evs[ev_name]} hors de [{lo} ; {hi}]")
	return errors


def _check(check_id: str, desc: str, value, limit, ok: bool) -> dict:
	return {"id": check_id, "desc": desc, "value": value, "limit": limit, "pass": bool(ok)}


def evaluate_checks(report: dict) -> list:
	"""Contrôles §3.7 recalculés depuis les séries PAR IMAGE du rapport (les
	tests les recalculent de la même façon : le champ `pass` n'est jamais cru
	sur parole)."""
	th = report["thresholds"]
	clips = report["clips"]
	checks = []
	worst_r = max(max(c["palm_R_cm"]) for c in clips.values())
	checks.append(_check("palm_R", "paume droite <-> Grip, chaque image de chaque clip (cm)",
		round(worst_r, 3), th["palm_R_cm"], worst_r <= th["palm_R_cm"]))
	left = []
	for name in LEFT_PALM_CLIPS:
		left.extend(clips[name]["palm_L_cm"])
	for name in RELOAD_CLIPS:
		series = clips[name]["palm_L_cm"]
		left.extend([series[0], series[-1]])
	worst_l = max(left)
	checks.append(_check("palm_L", "paume gauche <-> Foregrip en idle/fire/run et aux extrémités du rechargement (cm)",
		round(worst_l, 3), th["palm_L_cm"], worst_l <= th["palm_L_cm"]))
	worst_f = max(max(c["finger_penetration_mm"]) for c in clips.values())
	checks.append(_check("fingers", "doigts dans l'arme, chaque image (mm)", round(worst_f, 3),
		th["finger_penetration_mm"], worst_f <= th["finger_penetration_mm"]))
	for name in RELOAD_CLIPS:
		off = clips[name]["mag_offscreen_s"]
		checks.append(_check(f"mag_offscreen.{name}", f"{name} : chargeur entièrement hors cadre entre mag_out et mag_in (s)",
			round(off, 4), th["mag_offscreen_s"], off >= th["mag_offscreen_s"]))
	center = max(max(c["center_vertices"]) for n, c in clips.items() if n not in CENTER_EXEMPT_CLIPS)
	checks.append(_check("center", "sommets dans le carré central 20 % × 20 %, tous les clips sauf inspect",
		center, th["center_vertices"], center <= th["center_vertices"]))
	top = max(max(clips[n]["top_third_vertices"]) for n in HIP_CLIPS)
	checks.append(_check("top_third", "sommets dans le tiers haut à la hanche", top, th["top_third_vertices"],
		top <= th["top_third_vertices"]))
	hip = report["hip"]
	mx, my = hip["muzzle_screen"]
	checks.append(_check("muzzle", "bouche du canon à la hanche (x, y image)", [round(mx, 4), round(my, 4)],
		[th["muzzle_x"], th["muzzle_y"]],
		th["muzzle_x"][0] <= mx <= th["muzzle_x"][1] and th["muzzle_y"][0] <= my <= th["muzzle_y"][1]))
	lo, hi = hip["coverage_range"]
	cov = hip["coverage"]
	checks.append(_check("coverage", "couverture à la hanche, bras compris", round(cov, 4), [lo, hi], lo <= cov <= hi))
	for key, (op, limit) in report["metric_thresholds"].items():
		value = report["metrics"][key]
		ok = value >= limit if op == ">=" else value <= limit
		checks.append(_check(f"metric.{key}", f"principe §3.5 : {key} {op} {limit}", round(value, 4), limit, ok))
	return checks


def lengths_check(animations: dict, reload_time: float) -> list:
	"""Durées des clips exportés : nominales ± 1 image (reload = reload_time)."""
	errors = []
	nominal = dict(NOMINAL_LENGTHS)
	nominal["reload"] = nominal["reload_empty"] = reload_time
	for name, target in nominal.items():
		if name not in animations:
			errors.append(f"animation {name} absente")
		elif abs(animations[name] - target) > 1.0 / C.FPS + 1e-6:
			errors.append(f"animation {name} : {animations[name]:.4f} s != {target} s ± 1 image")
	return errors


# ---------------------------------------------------------------------------
# 4. Planches (Python système : PIL).
# ---------------------------------------------------------------------------

def compose_sheet(entries, out_path: str, title: str, cols: int = 4, width: int = 1600) -> str:
	"""Planche contact : `entries` = [(png, légende)], grille `cols` colonnes,
	`width` px de large, carré central 20 % et réticule en surimpression
	(zone qui doit rester vide à la hanche), JPG."""
	from PIL import Image, ImageDraw, ImageFont
	images = [Image.open(p).convert("RGB") for p, _ in entries]
	cell_w = width // cols
	cell_h = int(round(cell_w * images[0].height / images[0].width))
	rows = (len(images) + cols - 1) // cols
	header = 44
	sheet = Image.new("RGB", (cell_w * cols, header + cell_h * rows), (32, 28, 26))
	draw = ImageDraw.Draw(sheet)
	try:
		font = ImageFont.truetype("arial.ttf", 18)
		font_title = ImageFont.truetype("arialbd.ttf", 22)
	except OSError:
		font = font_title = ImageFont.load_default()
	draw.text((12, 10), title, fill=(245, 236, 220), font=font_title)
	for i, (img, (_, label)) in enumerate(zip(images, entries)):
		cell = img.resize((cell_w, cell_h), Image.LANCZOS)
		overlay = ImageDraw.Draw(cell)
		x0, x1, y0, y1 = C.CENTER_RECT
		overlay.rectangle([x0 * cell_w, y0 * cell_h, x1 * cell_w, y1 * cell_h], outline=(255, 255, 255))
		cx, cy = cell_w / 2, cell_h / 2
		overlay.line([cx - 6, cy, cx + 6, cy], fill=(255, 255, 255))
		overlay.line([cx, cy - 6, cx, cy + 6], fill=(255, 255, 255))
		overlay.rectangle([0, 0, cell_w, 26], fill=(32, 28, 26))
		overlay.text((8, 4), label, fill=(245, 236, 220), font=font)
		col, row = i % cols, i // cols
		sheet.paste(cell, (col * cell_w, header + row * cell_h))
	os.makedirs(os.path.dirname(os.path.abspath(out_path)), exist_ok=True)
	sheet.save(out_path, quality=90)
	return out_path


def compose_ab(sheet_a: str, sheet_b: str, out_path: str, width: int = 1600) -> str:
	"""Deux planches l'une au-dessus de l'autre, ramenées à `width` px."""
	from PIL import Image
	a, b = Image.open(sheet_a).convert("RGB"), Image.open(sheet_b).convert("RGB")
	h = a.height + b.height
	canvas = Image.new("RGB", (max(a.width, b.width), h), (32, 28, 26))
	canvas.paste(a, (0, 0))
	canvas.paste(b, (0, a.height))
	scale = width / canvas.width
	canvas = canvas.resize((width, int(round(h * scale))), Image.LANCZOS)
	canvas.save(out_path, quality=88)
	return out_path


# ---------------------------------------------------------------------------
# 5. Orchestration (Python système) : une commande = tout le livrable.
# ---------------------------------------------------------------------------

def run_blender_mode(config: dict, work_dir: str, blender: str = BLENDER_BIN) -> dict:
	os.makedirs(work_dir, exist_ok=True)
	cfg_path = os.path.join(work_dir, f"config_{config['id']}_{config['mode']}.json")
	with open(cfg_path, "w", encoding="utf-8") as fh:
		json.dump(config, fh, indent=1, ensure_ascii=False)
	cmd = [blender, "-b", "--factory-startup", "--python-exit-code", "1",
		"-P", os.path.join(HERE, "make_fp_viewmodel.py"), "--", "--config", cfg_path]
	proc = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=3600)
	log_path = os.path.join(work_dir, f"blender_{config['id']}_{config['mode']}.log")
	with open(log_path, "w", encoding="utf-8") as fh:
		fh.write(proc.stdout)
		fh.write("\n--- stderr ---\n")
		fh.write(proc.stderr)
	if proc.returncode != 0:
		tail = "\n".join((proc.stdout + proc.stderr).splitlines()[-40:])
		raise RuntimeError(f"make_fp_viewmodel: Blender a échoué (mode {config['mode']}, journal {log_path})\n{tail}")
	for line in proc.stdout.splitlines():
		if line.startswith("FP_VM_"):
			print(line)
	return {"log": log_path}


def sheet_entries(render_dir: str) -> list:
	entries = []
	for i, (_, _, label) in enumerate(SHEET_SHOTS):
		path = os.path.join(render_dir, f"shot_{i:02d}.png")
		if not os.path.isfile(path):
			raise FileNotFoundError(f"make_fp_viewmodel: rendu manquant {path}")
		entries.append((path, label))
	return entries


def cli_main(argv=None) -> int:
	p = argparse.ArgumentParser(description="FP-13 -- viewmodel FP par arme (doc 12 §3.5–3.7).")
	p.add_argument("--id", required=True, help="identifiant d'arme (manifeste tools/ai3d/manifests/fp/<id>.yaml)")
	p.add_argument("--modes", default="forearm,floating", help="modes de bras, séparés par des virgules")
	p.add_argument("--out-dir", default=DEFAULT_OUT_DIR, help="livrable du mode forearm")
	p.add_argument("--work-dir", default=os.path.join(tempfile.gettempdir(), "fp_viewmodel"),
		help="configs, journaux, rendus et sorties du mode floating")
	p.add_argument("--checkpoint-dir", default="", help="dossier des planches JPG (sinon --work-dir)")
	p.add_argument("--no-render", action="store_true", help="pas de planche contact")
	p.add_argument("--blender", default=BLENDER_BIN)
	args = p.parse_args(argv)
	modes = [m.strip() for m in args.modes.split(",") if m.strip()]
	manifest = load_manifest(args.id)
	work_root = os.path.join(os.path.abspath(args.work_dir), args.id)
	sheets = {}
	failed = []
	for mode in modes:
		out_dir = os.path.abspath(args.out_dir) if mode == "forearm" else os.path.join(work_root, mode, "out")
		render_dir = "" if args.no_render else os.path.join(work_root, mode, "shots")
		config = resolve_config(manifest, mode, out_dir, render_dir)
		run_blender_mode(config, os.path.join(work_root, mode), args.blender)
		paths = output_paths(out_dir, args.id, mode)
		with open(paths["report"], encoding="utf-8") as fh:
			report = json.load(fh)
		if not report["pass"]:
			failed.append(mode)
		for chk in report["checks"]:
			flag = "OK " if chk["pass"] else "ÉCHEC"
			print(f"  [{mode}] {flag} {chk['id']}: {chk['value']} (limite {chk['limit']})")
		if render_dir:
			sheet_dir = os.path.abspath(args.checkpoint_dir) if args.checkpoint_dir else work_root
			title = f"fp_{args.id} — {MODE_LABELS[mode]} — 12 poses cuites (carré central 20 % en blanc)"
			sheet = os.path.join(sheet_dir, f"fp_{args.id}_planche_{mode}.jpg")
			sheets[mode] = compose_sheet(sheet_entries(render_dir), sheet, title)
			print(f"FP_VM_SHEET {sheets[mode]}")
	if len(sheets) == 2:
		sheet_dir = os.path.dirname(sheets["forearm"])
		ab = compose_ab(sheets["forearm"], sheets["floating"], os.path.join(sheet_dir, f"fp_{args.id}_planche_AB.jpg"))
		print(f"FP_VM_SHEET {ab}")
	if failed:
		print(f"FP_VM_FAIL rapport en échec pour : {', '.join(failed)}")
		return 1
	print("FP_VM_DONE")
	return 0


# ---------------------------------------------------------------------------
# 6. Section bpy -- jamais appelée hors de Blender.
# ---------------------------------------------------------------------------
if bpy is not None:
	import fp_camera  # noqa: E402
	import fp_rig  # noqa: E402

	FINGERS = ("thumb", "index", "middle", "ring", "pinky")
	SIDES = ("L", "R")
	HAND_OF = {"L": "hand.L", "R": "hand.R"}
	AUTO_GRIP_STEP_DEG = 2.0
	AUTO_GRIP_MAX_DEG = 95.0
	AUTO_GRIP_CONTACT_M = 0.0015
	AUTO_GRIP_DEPTH_M = 0.002
	C3 = Matrix(((1.0, 0.0, 0.0), (0.0, 0.0, -1.0), (0.0, 1.0, 0.0)))  # Godot -> Blender (vecteurs).

	# -- conversions Godot <-> Blender --------------------------------------

	def g2b(v) -> Vector:
		return Vector((v[0], -v[2], v[1]))

	def b2g(v) -> tuple:
		return (v[0], v[2], -v[1])

	def g2b_matrix(t: C.Transform) -> Matrix:
		cols = C.q_columns(t.q)
		r_g = Matrix((cols[0], cols[1], cols[2])).transposed()
		r_b = C3 @ r_g @ C3.transposed()
		m = r_b.to_4x4()
		m.translation = g2b(t.p)
		return m

	def g2b_frame(t: C.Transform) -> Matrix:
		"""Repère de prise (axes locaux ABSTRAITS : doigts, paume, X×Y) : seul
		l'espace parent change d'étiquettes -- R_b = C3 · R_g (contrairement à
		`g2b_matrix`, où l'espace local de l'arme est lui aussi réétiqueté)."""
		cols = C.q_columns(t.q)
		r_b = C3 @ Matrix((cols[0], cols[1], cols[2])).transposed()
		m = r_b.to_4x4()
		m.translation = g2b(t.p)
		return m

	def b2g_transform(m: Matrix) -> C.Transform:
		r_g = C3.transposed() @ m.to_3x3().normalized() @ C3
		cols = [tuple(r_g.col[i]) for i in range(3)]
		return C.Transform(b2g(m.translation), C.q_from_columns(*cols))

	def _np(m: Matrix):
		import numpy as np
		return np.array([list(row) for row in m], dtype=np.float64)

	def _to_godot_np(pts):
		import numpy as np
		return np.stack([pts[:, 0], pts[:, 2], -pts[:, 1]], axis=1)

	# -- sondage de l'API -----------------------------------------------------

	EXPORT_PROPS = ("export_animation_mode", "export_def_bones", "export_reset_pose_bones",
		"export_force_sampling", "export_optimize_animation_size", "export_anim_single_armature",
		"export_frame_step", "export_anim_slide_to_zero", "export_merge_animation")

	def probe_bpy_api() -> None:
		rna = bpy.ops.export_scene.gltf.get_rna_type()
		props = {p.identifier: p for p in rna.properties}
		missing = [name for name in EXPORT_PROPS if name not in props]
		if missing:
			raise RuntimeError(f"make_fp_viewmodel: exporteur glTF sans {missing} ({bpy.app.version_string})")
		modes = [e.identifier for e in props["export_animation_mode"].enum_items]
		if "ACTIONS" not in modes:
			raise RuntimeError(f"make_fp_viewmodel: export_animation_mode sans ACTIONS ({modes})")
		probe = bpy.data.actions.new("_probe")
		ok = hasattr(probe, "fcurve_ensure_for_datablock") and hasattr(probe, "slots")
		bpy.data.actions.remove(probe)
		if not ok:
			raise RuntimeError("make_fp_viewmodel: API d'Action à slots absente (Blender >= 4.4 attendu)")
		print(f"FP_VM_PROBE_OK {bpy.app.version_string}")

	# -- imports --------------------------------------------------------------

	def _clear_scene() -> None:
		for o in list(bpy.data.objects):
			bpy.data.objects.remove(o, do_unlink=True)
		bpy.data.orphans_purge(do_local_ids=True, do_linked_ids=True, do_recursive=True)

	def _import(path: str) -> list:
		before = set(bpy.data.objects)
		bpy.ops.import_scene.gltf(filepath=path)
		return [o for o in bpy.data.objects if o not in before]

	def import_arms(path: str):
		new = _import(path)
		rig = next(o for o in new if o.type == 'ARMATURE')
		arms = next(o for o in new if o.type == 'MESH' and o.parent == rig)
		for o in new:
			if o not in (rig, arms):
				bpy.data.objects.remove(o, do_unlink=True)
		for pb in rig.pose.bones:
			pb.custom_shape = None
			pb.rotation_mode = 'QUATERNION'
		return rig, arms

	def import_weapon(path: str, albedo: str, pieces: dict):
		new = _import(path)
		body = next(o for o in new if o.type == 'MESH' and o.name.startswith("Body"))
		piece_objs = {}
		for piece, node in pieces.items():
			piece_objs[piece] = next(o for o in new if o.type == 'MESH' and o.name.startswith(node))
		anchors = {}
		for o in new:
			if o.type == 'EMPTY':
				anchors[o.name.split(".")[0]] = b2g_transform(o.matrix_world)
		for piece, obj in piece_objs.items():
			anchors[pieces[piece]] = b2g_transform(obj.matrix_world)
		if albedo:
			img = bpy.data.images.load(albedo, check_existing=True)
			for mat in {m for o in [body, *piece_objs.values()] for m in o.data.materials if m}:
				for node in mat.node_tree.nodes:
					if node.type == 'TEX_IMAGE':
						node.image = img
		for o in new:
			if o.type == 'EMPTY':
				bpy.data.objects.remove(o, do_unlink=True)
		return body, piece_objs, anchors

	# -- mains et doigts --------------------------------------------------------

	def _finger_bones(side: str, finger: str) -> list:
		if finger == "thumb":
			return [f"DEF-thumb.0{i}.{side}" for i in (1, 2, 3)]
		return [f"DEF-f_{finger}.0{i}.{side}" for i in (1, 2, 3)]

	class HandModel:
		"""Main mesurée sur la GÉOMÉTRIE des os du rig importé -- jamais sur les
		angles cuits au repos (FP-10 cuit ses poings par une flexion LATÉRALE,
		autour du Z local des phalanges ; FP-10B pourra cuire autre chose) :
		- repère de prise : f = poignet -> base du majeur ; k = base de l'index
		  -> base de l'auriculaire ; n = normale de paume (f × k main droite,
		  k × f main gauche) ; origine = surface de la paume, trouvée par un
		  rayon lancé depuis l'axe du métacarpe vers n dans le maillage ;
		- doigts : base, direction « tendue » et axe de flexion (d0 × n,
		  parallèle à la ligne des jointures) en espace main ; courbures
		  ABSOLUES en degrés (0 = doigt tendu ; préréglages de fp_rig) ;
		- sommets de chaque doigt (os dominant) : auto-prise et rapport."""

		def __init__(self, rig, arms, side: str, vertex_bone: list, arms_bvh):
			self.side = side
			bones = rig.data.bones
			hand = bones[f"DEF-hand.{side}"]
			self.hand_rest = hand.matrix_local.copy()
			inv3 = self.hand_rest.to_3x3().inverted()
			wrist = hand.head_local.copy()
			k_i = bones[f"DEF-f_index.01.{side}"].head_local
			k_m = bones[f"DEF-f_middle.01.{side}"].head_local
			k_p = bones[f"DEF-f_pinky.01.{side}"].head_local
			f = (k_m - wrist).normalized()
			k = k_p - k_i
			k = (k - f * k.dot(f)).normalized()
			n = f.cross(k) if side == "R" else k.cross(f)
			start = wrist + f * (0.55 * (k_m - wrist).length)
			hit = arms_bvh.ray_cast(start, n)
			if hit[0] is None:
				raise RuntimeError(f"make_fp_viewmodel: surface de paume {side} introuvable (rayon depuis le métacarpe)")
			self.palm_depth = hit[3]
			frame = Matrix((f, n, f.cross(n))).transposed().to_4x4()
			frame.translation = hit[0]
			self.frame_rest = frame
			self.offset = frame.inverted() @ self.hand_rest    # os = repère @ offset
			self.fingers = {}
			for finger in FINGERS:
				names = _finger_bones(side, finger)
				base = bones[names[0]].head_local
				if finger == "thumb":
					# Pouce ouvert dans le plan de la paume, vers l'avant et côté index (-k) ;
					# sa flexion le ramène vers l'objet tenu (n).
					d0 = (f * 0.55 - k * 0.75).normalized()
					axis = d0.cross(n).normalized()
				else:
					d0 = (base - wrist).normalized()
					axis = d0.cross(n).normalized()
				b0 = bones[names[0]]
				b0_dir = (b0.tail_local - b0.head_local).normalized()
				contact = []
				for i, b in enumerate(vertex_bone):
					if b in names[1:]:
						contact.append(i)
					elif b == names[0] and (arms.data.vertices[i].co - b0.head_local).dot(b0_dir) > 0.5 * b0.length:
						contact.append(i)
				self.fingers[finger] = {
					"names": names, "lengths": [bones[nm].length for nm in names],
					"base_l": self.hand_rest.inverted() @ base, "d0_l": inv3 @ d0, "axis_l": inv3 @ axis,
					"rest_rot_l": [inv3 @ bones[nm].matrix_local.to_3x3() for nm in names],
					"vertices": [i for i, b in enumerate(vertex_bone) if b in names],
					"contact_vertices": contact,
				}
			self.finger_vertices = [i for fd in self.fingers.values() for i in fd["vertices"]]
			contact_all = {i for fd in self.fingers.values() for i in fd["contact_vertices"]}
			finger_set = set(self.finger_vertices)
			self.palm_vertices = [i for i, b in enumerate(vertex_bone)
				if (b == f"DEF-hand.{side}" or i in finger_set) and i not in contact_all]

		def bone_matrix(self, frame: Matrix) -> Matrix:
			return frame @ self.offset

		def frame_from_bone(self, bone_m: Matrix) -> Matrix:
			return bone_m @ self.offset.inverted()

		def finger_matrices(self, hand_m: Matrix, finger: str, curls) -> list:
			"""Matrices (armature) des 3 phalanges pour des courbures absolues
			`curls` (degrés, 0 = tendu), la main étant à `hand_m`. Orientation
			d'une phalange = flexion(axe, cumul) · alignement minimal (direction
			de repos -> direction tendue) · repos : le vrillage de repos est
			conservé, seul le pli cuit au repos est défait (pas de retournement
			de roulis d'une phalange à l'autre)."""
			data = self.fingers[finger]
			rot = hand_m.to_3x3().normalized()
			head = hand_m @ data["base_l"]
			axis = (rot @ data["axis_l"]).normalized()
			d0 = (rot @ data["d0_l"]).normalized()
			out = []
			total = 0.0
			for length, curl, rest_l in zip(data["lengths"], curls, data["rest_rot_l"]):
				total += curl
				rest = rot @ rest_l
				align = rest.col[1].normalized().rotation_difference(d0).to_matrix()
				flex = Matrix.Rotation(math.radians(total), 3, axis)
				m = (flex @ align @ rest).to_4x4()
				m.translation = head
				out.append(m)
				head = head + (flex @ d0) * length
			return out

	def dominant_bones(mesh_obj) -> list:
		names = [vg.name for vg in mesh_obj.vertex_groups]
		out = []
		for v in mesh_obj.data.vertices:
			best, best_w = "", 0.0
			for g in v.groups:
				if g.weight > best_w:
					best, best_w = names[g.group], g.weight
			out.append(best)
		return out

	# -- géométrie de l'arme (espace arme Blender) ----------------------------

	class InsideField:
		"""Intérieur/extérieur d'un maillage (espace local) par NOMBRE
		D'ENROULEMENT GÉNÉRALISÉ (Jacobson et al., 2013) : robuste aux trous
		et aux coques superposées des maillages Tripo, où la parité des rayons
		ne l'est pas (Ravage v2 : 5 528 arêtes de bord, 20 % de points
		ambigus mesurés sur 9 rayons). Évalué paresseusement au centre de
		cellules de 3 mm, puis mis en cache ; intérieur si w >= 0,5."""

		def __init__(self, obj, cell: float = 0.003, threshold: float = 0.5, margin: float = 0.01):
			import numpy as np
			me = obj.data
			me.calc_loop_triangles()
			co = np.empty(len(me.vertices) * 3, dtype=np.float64)
			me.vertices.foreach_get("co", co)
			co = co.reshape(-1, 3)
			idx = np.empty(len(me.loop_triangles) * 3, dtype=np.int64)
			me.loop_triangles.foreach_get("vertices", idx)
			self.tris = co[idx.reshape(-1, 3)]
			self.lo = co.min(axis=0) - margin
			self.hi = co.max(axis=0) + margin
			self.cell = cell
			self.threshold = threshold
			self.cache = {}

		def winding(self, points):
			"""Nombre d'enroulement généralisé de chaque point (N×3)."""
			import numpy as np
			pts = np.asarray(points, dtype=np.float64).reshape(-1, 3)
			out = np.empty(len(pts))
			for start in range(0, len(pts), 128):
				chunk = pts[start:start + 128, None, :]
				a = self.tris[None, :, 0, :] - chunk
				b = self.tris[None, :, 1, :] - chunk
				c = self.tris[None, :, 2, :] - chunk
				la, lb, lc = (np.linalg.norm(v, axis=2) for v in (a, b, c))
				det = np.einsum("pti,pti->pt", a, np.cross(b, c))
				den = (la * lb * lc + np.einsum("pti,pti->pt", a, b) * lc + np.einsum("pti,pti->pt", b, c) * la
					+ np.einsum("pti,pti->pt", c, a) * lb)
				out[start:start + 128] = np.sum(2.0 * np.arctan2(det, den), axis=1) / (4.0 * math.pi)
			return out

		def contains(self, points):
			"""Masque booléen des points (N×3, espace local) intérieurs."""
			import numpy as np
			pts = np.asarray(points, dtype=np.float64).reshape(-1, 3)
			inside = np.zeros(len(pts), dtype=bool)
			in_box = np.all((pts >= self.lo) & (pts <= self.hi), axis=1)
			if not in_box.any():
				return inside
			cells = np.floor((pts[in_box] - self.lo) / self.cell).astype(np.int64)
			keys = [tuple(k) for k in cells]
			missing = sorted({k for k in keys if k not in self.cache})
			if missing:
				centers = (np.array(missing, dtype=np.float64) + 0.5) * self.cell + self.lo
				for key, w in zip(missing, self.winding(centers)):
					self.cache[key] = w >= self.threshold
			inside[np.nonzero(in_box)[0]] = [self.cache[k] for k in keys]
			return inside

	def penetration_depths(points, grid: InsideField, bvh):
		"""Profondeur (m) de chaque point (N×3, espace local du maillage) :
		distance à la surface s'il est intérieur, 0 sinon."""
		import numpy as np
		pts = np.asarray(points, dtype=np.float64).reshape(-1, 3)
		out = np.zeros(len(pts))
		for i in np.nonzero(grid.contains(pts))[0]:
			out[i] = bvh.find_nearest(Vector(pts[i]))[3]
		return out

	class WeaponGeom:
		"""Arme en espace local Blender (Grip à l'origine) : BVH et champs
		intérieur/extérieur du corps et de chaque pièce (pièce au repos)."""

		def __init__(self, body, piece_objs: dict):
			self.body_local = [v.co.copy() for v in body.data.vertices]
			self.body_polys = [tuple(p.vertices) for p in body.data.polygons]
			self.bvh_body = BVHTree.FromPolygons(self.body_local, self.body_polys)
			self.grid_body = InsideField(body)
			self.pieces = {}
			for piece, obj in piece_objs.items():
				local = [v.co.copy() for v in obj.data.vertices]
				polys = [tuple(p.vertices) for p in obj.data.polygons]
				bvh = BVHTree.FromPolygons(local, polys)
				self.pieces[piece] = {"local": local, "polys": polys, "rest": obj.matrix_world.copy(),
					"bvh_local": bvh, "grid": InsideField(obj)}
			merged, mpolys = list(self.body_local), list(self.body_polys)
			for data in self.pieces.values():
				base = len(merged)
				merged.extend(data["rest"] @ v for v in data["local"])
				mpolys.extend(tuple(i + base for i in poly) for poly in data["polys"])
			self.bvh_all = BVHTree.FromPolygons(merged, mpolys)

		def cast(self, target: str, origin: Vector, direction: Vector) -> Vector:
			if target == "body":
				return self.bvh_body.ray_cast(origin, direction)[0]
			data = self.pieces[target]
			inv = data["rest"].inverted()
			hit = data["bvh_local"].ray_cast(inv @ origin, (inv.to_3x3() @ direction).normalized())
			return None if hit[0] is None else data["rest"] @ hit[0]

		def depths_at_rest(self, points_weapon):
			"""Profondeurs (m) de points en espace ARME dans le corps et dans
			chaque pièce À SA PLACE (chargeur engagé) : maximum des deux."""
			import numpy as np
			pts = np.asarray(points_weapon, dtype=np.float64).reshape(-1, 3)
			depth = penetration_depths(pts, self.grid_body, self.bvh_body)
			for data in self.pieces.values():
				m = _np(data["rest"].inverted())
				local = pts @ m[:3, :3].T + m[:3, 3]
				depth = np.maximum(depth, penetration_depths(local, data["grid"], data["bvh_local"]))
			return depth

	def unsigned_distance(bvh, p: Vector) -> float:
		loc = bvh.find_nearest(p)
		return 1.0 if loc[0] is None else loc[3]

	def build_sockets(cfg: dict, anchors: dict, wgeom: WeaponGeom) -> tuple:
		"""Repères de prise (espace arme Godot) : rayon depuis le point
		intérieur, dans le sens -paume, jusqu'à la surface (la paume s'y pose)."""
		sockets, depths, hands = {}, {}, {}
		for name, spec in cfg["sockets"].items():
			src = anchors[spec["from"]].p
			start = C.v_add(src, tuple(spec["offset"]))
			palm = C.v_norm(tuple(spec["palm"]))
			origin = start
			if spec["cast"] != "none":
				hit = wgeom.cast(spec["cast"], g2b(start), -g2b(palm))
				if hit is None:
					raise RuntimeError(f"make_fp_viewmodel: le rayon du repère {name} ne touche pas {spec['cast']}")
				origin = b2g(hit)
			sockets[name] = C.hand_frame(origin, palm, tuple(spec["knuckles"]), spec["hand"])
			depths[name] = C.v_len(C.v_sub(origin, start))
			hands[name] = spec["hand"]
		return sockets, depths, hands

	def _reset_pose(rig) -> None:
		for pb in rig.pose.bones:
			pb.location, pb.rotation_quaternion, pb.scale = Vector(), Quaternion(), Vector((1.0, 1.0, 1.0))
		bpy.context.view_layer.update()

	def pose_bases(rig, desired: dict) -> dict:
		"""Matrices de pose LOCALES (`matrix_basis`) qui réalisent les matrices
		armature `desired` ; un parent absent de `desired` reste au repos."""
		out = {}
		for name, d in desired.items():
			bone = rig.data.bones[name]
			if bone.parent is None:
				out[name] = bone.matrix_local.inverted() @ d
				continue
			parent_d = desired.get(bone.parent.name, bone.parent.matrix_local)
			out[name] = (bone.matrix_local.inverted() @ bone.parent.matrix_local) @ parent_d.inverted() @ d
		return out

	def set_bases(rig, bases: dict) -> None:
		for name, m in bases.items():
			loc, rot, scale = m.decompose()
			pb = rig.pose.bones[name]
			pb.location, pb.rotation_quaternion, pb.scale = loc, rot, scale

	def settle_socket(hand: HandModel, rig, arms, frame_b: Matrix, wgeom: WeaponGeom) -> float:
		"""Recule la main le long de -n (normale de paume) jusqu'à ce que la
		paume et la base des doigts ne pénètrent plus l'arme (<= 1 mm), doigts
		tendus ; renvoie le recul (m)."""
		import numpy as np
		idx = np.array(hand.palm_vertices, dtype=np.int64)
		normal = frame_b.to_3x3().col[1].normalized()
		shift = 0.0
		for _ in range(6):
			frame = frame_b.copy()
			frame.translation = frame_b.translation - normal * shift
			hand_m = hand.bone_matrix(frame)
			desired = {f"DEF-hand.{hand.side}": hand_m}
			for finger in FINGERS:
				desired.update(zip(hand.fingers[finger]["names"], hand.finger_matrices(hand_m, finger, (0.0, 0.0, 0.0))))
			_reset_pose(rig)
			set_bases(rig, pose_bases(rig, desired))
			bpy.context.view_layer.update()
			depth = float(wgeom.depths_at_rest(evaluated_vertices(arms)[idx]).max())
			if depth <= 0.001:
				break
			shift += depth
		_reset_pose(rig)
		return shift

	def auto_grip(hand: HandModel, rig, arms, frame_b: Matrix, wgeom: WeaponGeom, name: str, arm=None,
			to_weapon: Matrix = None) -> dict:
		"""Auto-prise (doc 12 §3.2) mesurée sur le VRAI maillage skinné : main
		posée sur le repère (espace arme pris comme espace armature), chaque
		doigt replie ses 3 articulations ensemble par pas de 2° depuis le doigt
		tendu jusqu'au contact (un sommet de la moitié distale du doigt à
		<= 1,5 mm de la surface) ; si un pas traverse la surface de plus de
		2 mm, on garde le pas précédent ; un doigt déjà dans l'arme tendu
		s'ouvre (jusqu'à -20°) ; plafond 95° ; déterministe. Avec `arm` (bras
		IK) et `to_weapon` (caméra -> arme), la main est posée en espace caméra
		et le bras suit : les sommets du pouce et de la paume, pondérés en
		partie sur l'avant-bras, sont mesurés dans leur vraie pose."""
		import numpy as np
		_reset_pose(rig)
		hand_m = hand.bone_matrix(frame_b)
		hand_name = f"DEF-hand.{hand.side}"
		out = {}
		for finger in FINGERS:
			data = hand.fingers[finger]
			idx = np.array(data["contact_vertices"], dtype=np.int64)

			def probe(curls):
				desired = {hand_name: hand_m}
				if arm is not None:
					upper, fore, _shift = arm.solve(b2g(hand_m.translation), hand_m.to_3x3().col[0])
					desired[f"DEF-upper_arm.{hand.side}"] = upper
					desired[f"DEF-forearm.{hand.side}"] = fore
				desired.update(zip(data["names"], hand.finger_matrices(hand_m, finger, curls)))
				set_bases(rig, pose_bases(rig, desired))
				bpy.context.view_layer.update()
				verts = evaluated_vertices(arms)[idx]
				if to_weapon is not None:
					verts = _world_np(verts, to_weapon)
				if not len(verts):
					return 1.0, 0.0
				d_min = min(unsigned_distance(wgeom.bvh_all, Vector(p)) for p in verts)
				return d_min, float(wgeom.depths_at_rest(verts).max())

			curls = [0.0, 0.0, 0.0]
			d_min, depth = probe(curls)
			# Doigt déjà dans l'arme tendu : on l'ouvre (extension) jusqu'à -20°.
			while depth > AUTO_GRIP_DEPTH_M and curls[0] > -20.0 + 1e-9:
				curls = [c - AUTO_GRIP_STEP_DEG for c in curls]
				d_min, depth = probe(curls)
			while d_min > AUTO_GRIP_CONTACT_M and depth <= 0.0 and curls[0] < AUTO_GRIP_MAX_DEG - 1e-9:
				previous = curls
				curls = [min(AUTO_GRIP_MAX_DEG, c + AUTO_GRIP_STEP_DEG) for c in curls]
				d_min, depth = probe(curls)
				if depth > AUTO_GRIP_DEPTH_M:
					curls = previous      # le pas a traversé la surface : on garde le dernier pas hors de l'arme
					break
			out[finger] = curls
		_reset_pose(rig)
		print(f"FP_VM_AUTOGRIP {hand.side}@{name} " + " ".join(f"{f}={c[0]:.0f}" for f, c in out.items()))
		return out

	# -- IK des bras (espace caméra Godot, solveurs purs de fp_rig) ----------

	class ArmModel:
		"""Bras (épaule -> coude -> poignet) en espace caméra Godot. L'épaule,
		invisible, est posée une fois pour la prise de hanche
		(fp_rig.shoulder_solve), puis suit le poignet d'une fraction `follow`
		de son déplacement (le corps accompagne l'arme : le bras droit garde sa
		direction quand l'arme bascule ; le bras gauche, qui va chercher le
		chargeur, reste plus ancré). Si le poignet sort malgré tout de
		l'allonge, l'épaule avance juste assez (décalage mesuré au rapport)."""

		def __init__(self, rig, side: str, shoulder_rest, pole_offset, follow: float):
			bones = rig.data.bones
			self.side = side
			up, fo = bones[f"DEF-upper_arm.{side}"], bones[f"DEF-forearm.{side}"]
			self.upper_rest = up.matrix_local.copy()
			self.fore_rest = fo.matrix_local.copy()
			self.l1 = (up.tail_local - up.head_local).length
			self.l2 = (bones[f"DEF-hand.{side}"].head_local - fo.head_local).length
			self.shoulder_rest = tuple(shoulder_rest)
			self.pole_offset = tuple(pole_offset)
			self.follow = float(follow)
			self.shoulder = None
			self.wrist_hip = None

		def fit_shoulder(self, wrist_g) -> dict:
			pole = C.v_add(self.shoulder_rest, self.pole_offset)
			solved = fp_rig.shoulder_solve(self.shoulder_rest, wrist_g, pole, self.l1, self.l2)
			self.shoulder = solved["shoulder"]
			self.wrist_hip = tuple(wrist_g)
			return solved

		def solve(self, wrist_g, hand_x_b: Vector) -> tuple:
			shoulder = C.v_add(self.shoulder, C.v_scale(C.v_sub(wrist_g, self.wrist_hip), self.follow))
			reach = (self.l1 + self.l2) * 0.998
			d = C.v_sub(wrist_g, shoulder)
			dist = C.v_len(d)
			shift = 0.0
			if dist > reach:
				shift = dist - reach
				shoulder = C.v_add(shoulder, C.v_scale(C.v_norm(d), shift))
			pole = C.v_add(shoulder, self.pole_offset)
			elbow, hand = fp_rig.two_bone_ik_solve(shoulder, wrist_g, pole, self.l1, self.l2)
			sb, eb, hb = g2b(shoulder), g2b(elbow), g2b(hand)
			upper = _aim(self.upper_rest, sb, eb, None)
			fore = _aim(self.fore_rest, eb, hb, hand_x_b)
			return upper, fore, shift

	def _aim(rest: Matrix, head: Vector, tail: Vector, x_hint) -> Matrix:
		y = (tail - head).normalized()
		if x_hint is None:
			rot = rest.to_3x3().col[1].rotation_difference(y).to_matrix() @ rest.to_3x3()
		else:
			x = (x_hint - y * x_hint.dot(y)).normalized()
			rot = Matrix((x, y, x.cross(y))).transposed()
		m = rot.to_4x4()
		m.translation = head
		return m

	# -- rig : os de l'arme, maillages ----------------------------------------

	def setup_weapon_bones(rig, hip_b: Matrix, piece_rest_b: dict) -> None:
		bpy.context.view_layer.objects.active = rig
		bpy.ops.object.mode_set(mode='EDIT')
		eb = rig.data.edit_bones
		root = eb["fp_root"]
		root.head, root.tail, root.roll = Vector((0, 0, 0)), Vector((0, 0.05, 0)), 0.0
		for name in fp_rig.FP_PART_BONES:
			bone = eb[name]
			bone.matrix = hip_b
			bone.length = 0.15 if name == "fp_weapon" else 0.03
		for piece, m in piece_rest_b.items():
			bone = eb[f"fp_{piece}"]
			bone.matrix = hip_b @ m
			bone.length = 0.06
		bpy.ops.object.mode_set(mode='OBJECT')

	def skin_rigid(obj, rig, bone_name: str, to_armature: Matrix, name: str) -> None:
		obj.data.transform(to_armature)
		obj.parent = None
		obj.matrix_world = Matrix.Identity(4)
		obj.parent = rig
		obj.matrix_parent_inverse = Matrix.Identity(4)
		for vg in list(obj.vertex_groups):
			obj.vertex_groups.remove(vg)
		vg = obj.vertex_groups.new(name=bone_name)
		vg.add(list(range(len(obj.data.vertices))), 1.0, 'REPLACE')
		mod = obj.modifiers.new("Armature", type='ARMATURE')
		mod.object = rig
		obj.name = name
		obj.data.name = name

	# -- pose d'une image -----------------------------------------------------

	class Baker:
		"""Calcule les matrices armature de TOUS les os pour une pose DSL
		(arme, pièces, IK des bras cuite, doigts)."""

		def __init__(self, rig, hands: dict, arms_ik: dict, grips: dict, piece_rest_b: dict):
			self.rig = rig
			self.hands = hands
			self.arms = arms_ik
			self.grips = grips
			self.piece_rest_b = piece_rest_b

		def curls(self, state: C.FingerState, side: str) -> dict:
			def resolve(fk):
				if fk.preset == "auto":
					return self.grips[(side, fk.socket)]
				return {f: list(v) for f, v in fp_rig.FINGER_PRESETS[fk.preset].items()}
			a, b = resolve(state.a), resolve(state.b)
			return {f: [x + (y - x) * state.w for x, y in zip(a[f], b[f])] for f in FINGERS}

		def pose(self, pose: C.Pose) -> tuple:
			"""(matrices armature désirées {os: Matrix}, décalage d'épaule max en m)."""
			desired = {"fp_root": self.rig.data.bones["fp_root"].matrix_local.copy()}
			weapon_b = g2b_matrix(pose.transforms["weapon"])
			desired["fp_weapon"] = weapon_b
			for name in fp_rig.FP_PART_BONES[1:]:
				desired[name] = weapon_b
			for piece in self.piece_rest_b:
				m = g2b_matrix(pose.transforms[piece])
				scale = pose.scales.get(piece, 1.0)
				desired[f"fp_{piece}"] = m @ Matrix.Diagonal((scale, scale, scale, 1.0))
			shift = 0.0
			for side in SIDES:
				hand = self.hands[side]
				frame_b = g2b_frame(pose.transforms[HAND_OF[side]])
				hand_m = hand.bone_matrix(frame_b)
				upper, fore, sh = self.arms[side].solve(b2g(hand_m.translation), hand_m.to_3x3().col[0])
				shift = max(shift, sh)
				desired[f"DEF-upper_arm.{side}"] = upper
				desired[f"DEF-forearm.{side}"] = fore
				desired[f"DEF-hand.{side}"] = hand_m
				curls = self.curls(pose.fingers[HAND_OF[side]], side)
				for finger in FINGERS:
					desired.update(zip(hand.fingers[finger]["names"], hand.finger_matrices(hand_m, finger, curls[finger])))
			return desired, shift

		def apply(self, pose: C.Pose) -> float:
			desired, shift = self.pose(pose)
			set_bases(self.rig, pose_bases(self.rig, desired))
			bpy.context.view_layer.update()
			return shift

	# -- mesures d'écran ------------------------------------------------------

	def _world_np(co, matrix_world: Matrix):
		m = _np(matrix_world)
		return co @ m[:3, :3].T + m[:3, 3]

	def evaluated_vertices(obj):
		"""Sommets évalués (armature appliquée) en espace MONDE Blender."""
		import numpy as np
		dg = bpy.context.evaluated_depsgraph_get()
		ev = obj.evaluated_get(dg)
		me = ev.to_mesh()
		buf = np.empty(len(me.vertices) * 3, dtype=np.float64)
		me.vertices.foreach_get("co", buf)
		ev.to_mesh_clear()
		return _world_np(buf.reshape(-1, 3), obj.matrix_world)

	def evaluated_triangles(obj):
		"""Triangles évalués (T×3×3) en espace MONDE Blender."""
		import numpy as np
		dg = bpy.context.evaluated_depsgraph_get()
		ev = obj.evaluated_get(dg)
		me = ev.to_mesh()
		me.calc_loop_triangles()
		co = np.empty(len(me.vertices) * 3, dtype=np.float64)
		me.vertices.foreach_get("co", co)
		idx = np.empty(len(me.loop_triangles) * 3, dtype=np.int64)
		me.loop_triangles.foreach_get("vertices", idx)
		ev.to_mesh_clear()
		return _world_np(co.reshape(-1, 3), obj.matrix_world)[idx.reshape(-1, 3)]

	class Scene:
		"""Objets de la scène FP et leurs relevés par image."""

		def __init__(self, rig, arms, meshes: dict, hands: dict, grip_depth: float, anchors_b: dict):
			self.rig, self.arms, self.meshes = rig, arms, meshes
			self.hands = hands
			self.grip_depth = grip_depth
			self.anchors_b = anchors_b

		def bone(self, name: str) -> Matrix:
			return self.rig.matrix_world @ self.rig.pose.bones[name].matrix

		def palms(self) -> tuple:
			weapon = self.bone("fp_weapon")
			fr = self.hands["R"].frame_from_bone(self.bone("DEF-hand.R"))
			grasp = fr.translation + fr.to_3x3().col[1].normalized() * self.grip_depth
			grip = weapon @ self.anchors_b["Grip"]
			fl = self.hands["L"].frame_from_bone(self.bone("DEF-hand.L"))
			fore = weapon @ self.anchors_b["Foregrip"]
			return (grasp - grip).length * 100.0, (fl.translation - fore).length * 100.0

	def hip_coverage(scene: Scene) -> float:
		import numpy as np
		tris = [evaluated_triangles(scene.arms)] + [evaluated_triangles(o) for o in scene.meshes.values()]
		tris = np.concatenate(tris)
		tris_g = np.stack([tris[..., 0], tris[..., 2], -tris[..., 1]], axis=-1)
		return C.coverage_fraction(tris_g)

	# -- cuisson d'un clip ----------------------------------------------------

	def _fcurves_write(action, rig, series: dict, n_frames: int) -> None:
		for name, channels in series.items():
			base = f'pose.bones["{name}"]'
			for prop, values in channels.items():
				width = len(values[0])
				for idx in range(width):
					fc = action.fcurve_ensure_for_datablock(rig, f"{base}.{prop}", index=idx, group_name=name)
					fc.keyframe_points.add(n_frames + 1)
					flat = []
					for frame, value in enumerate(values):
						flat.extend((float(frame), float(value[idx])))
					fc.keyframe_points.foreach_set("co", flat)
					fc.update()

	def bake_clip(clip: C.Clip, geom: C.RigGeometry, baker: Baker, rig) -> tuple:
		"""Échantillonne le clip à 60 i/s, calcule les os (IK cuite), écrit
		une Action (une clé par os et par image : l'export échantillonne ces
		mêmes images) et la rend active."""
		n = clip.frames
		names = [b.name for b in rig.data.bones]
		series = {nm: {"location": [], "rotation_quaternion": [], "scale": []} for nm in names}
		prev_q = {}
		max_shift = 0.0
		for i in range(n + 1):
			pose = C.evaluate(clip, i / n, geom)
			desired, shift = baker.pose(pose)
			max_shift = max(max_shift, shift)
			bases = pose_bases(rig, desired)
			for nm in names:
				loc, rot, scale = bases[nm].decompose()
				if nm in prev_q and prev_q[nm].dot(rot) < 0.0:
					rot = -rot
				prev_q[nm] = rot
				series[nm]["location"].append(tuple(loc))
				series[nm]["rotation_quaternion"].append(tuple(rot))
				series[nm]["scale"].append(tuple(scale))
		action = bpy.data.actions.new(clip.name)
		action.use_fake_user = True
		rig.animation_data_create()
		rig.animation_data.action = action
		_fcurves_write(action, rig, series, n)
		if action.slots and rig.animation_data.action_slot is None:
			rig.animation_data.action_slot = action.slots[0]
		return action, max_shift

	def activate(rig, action) -> None:
		rig.animation_data.action = action
		if action.slots:
			rig.animation_data.action_slot = action.slots[0]

	def _penetration_mm(points_b, matrix_inv: Matrix, grid: InsideField, bvh) -> float:
		"""Pénétration max (mm) de `points_b` (N×3, monde Blender) dans un
		maillage décrit en espace local de `matrix_inv`."""
		m = _np(matrix_inv)
		local = points_b @ m[:3, :3].T + m[:3, 3]
		depths = penetration_depths(local, grid, bvh)
		return float(depths.max()) * 1000.0 if len(depths) else 0.0

	def finger_penetration_by_finger(scene: Scene, wgeom: WeaponGeom, pieces: dict) -> dict:
		"""Pénétration max (mm) de chaque doigt à la pose courante (diagnostic)."""
		verts = evaluated_vertices(scene.arms)
		out = {}
		for side in SIDES:
			for finger, data in scene.hands[side].fingers.items():
				pts = verts[data["vertices"]]
				worst = _penetration_mm(pts, scene.bone("fp_weapon").inverted(), wgeom.grid_body, wgeom.bvh_body)
				for piece in pieces:
					piece_data = wgeom.pieces[piece]
					worst = max(worst, _penetration_mm(pts, scene.bone(f"fp_{piece}").inverted(), piece_data["grid"],
						piece_data["bvh_local"]))
				out[f"{finger}.{side}"] = round(worst, 2)
		return out

	def measure_clip(clip: C.Clip, scene: Scene, wgeom: WeaponGeom, pieces: dict) -> dict:
		"""Relevés §3.7 à CHAQUE image (poses évaluées par Blender, pas les
		cibles du DSL) : paumes, pénétration des doigts, carré central, tiers
		haut, visibilité du chargeur."""
		import numpy as np
		sc = bpy.context.scene
		palm_r, palm_l, fingers, center, top, mag_visible = [], [], [], [], [], []
		finger_idx = np.array(scene.hands["L"].finger_vertices + scene.hands["R"].finger_vertices, dtype=np.int64)
		for i in range(clip.frames + 1):
			sc.frame_set(i)
			pr, pl = scene.palms()
			palm_r.append(round(pr, 3))
			palm_l.append(round(pl, 3))
			verts = {"arms": evaluated_vertices(scene.arms)}
			for key, obj in scene.meshes.items():
				verts[key] = evaluated_vertices(obj)
			tips = verts["arms"][finger_idx]
			worst = _penetration_mm(tips, scene.bone("fp_weapon").inverted(), wgeom.grid_body, wgeom.bvh_body)
			for piece in pieces:
				data = wgeom.pieces[piece]
				worst = max(worst, _penetration_mm(tips, scene.bone(f"fp_{piece}").inverted(), data["grid"],
					data["bvh_local"]))
			fingers.append(round(worst, 3))
			all_g = _to_godot_np(np.concatenate(list(verts.values())))
			center.append(C.count_in_rect(all_g, C.CENTER_RECT))
			top.append(C.count_in_rect(all_g, C.TOP_THIRD_RECT))
			if "mag" in verts:
				mag_visible.append(not C.all_outside_frame(_to_godot_np(verts["mag"])))
			else:
				mag_visible.append(False)
		out = {"frames": clip.frames, "length": round(clip.length, 6), "palm_R_cm": palm_r, "palm_L_cm": palm_l,
			"finger_penetration_mm": fingers, "center_vertices": center, "top_third_vertices": top,
			"mag_visible": mag_visible}
		t_out, t_in = clip.event_t("mag_out"), clip.event_t("mag_in")
		if t_out is not None and t_in is not None:
			flags = [not v for v in mag_visible]
			out["mag_offscreen_s"] = C.longest_run_seconds(flags, C.frame_of(clip, t_out), C.frame_of(clip, t_in))
		return out

	# -- cadrage de hanche ----------------------------------------------------

	def place_for_hip(hip: C.Transform, geom_base: dict, anchors: dict, baker: Baker, scene: Scene,
			meshes_rest: dict, idle: C.Clip) -> dict:
		"""Pose l'arme à `hip` (maillages au repos déplacés, bras en IK sur
		les repères), mesure couverture / carré central / tiers haut / bouche."""
		geom = C.RigGeometry(hip_weapon=hip, **geom_base)
		hip_b = g2b_matrix(hip)
		for key, (obj, local_to_weapon) in meshes_rest.items():
			obj.matrix_world = hip_b @ local_to_weapon
		for side in SIDES:
			frame_b = g2b_frame(hip.compose(geom.sockets[geom.hip_sockets[HAND_OF[side]]]))
			baker.arms[side].fit_shoulder(b2g(baker.hands[side].bone_matrix(frame_b).translation))
		pose = C.evaluate(idle, 0.0, geom)
		baker.apply(pose)
		import numpy as np
		pts = [evaluated_vertices(scene.arms)]
		tris = [evaluated_triangles(scene.arms)]
		for obj, _ in meshes_rest.values():
			pts.append(evaluated_vertices(obj))
			tris.append(evaluated_triangles(obj))
		pts_g = _to_godot_np(np.concatenate(pts))
		tris_b = np.concatenate(tris)
		tris_g = np.stack([tris_b[..., 0], tris_b[..., 2], -tris_b[..., 1]], axis=-1)
		muzzle = C.image_uv(hip.apply(anchors["Muzzle"].p))
		return {
			"coverage": C.coverage_fraction(tris_g),
			"center_vertices": C.count_in_rect(pts_g, C.CENTER_RECT),
			"top_third_vertices": C.count_in_rect(pts_g, C.TOP_THIRD_RECT),
			"muzzle_screen": list(muzzle),
		}

	# -- export ---------------------------------------------------------------

	def export_glb(rig, objects: list, path: str) -> None:
		os.makedirs(os.path.dirname(path), exist_ok=True)
		bpy.ops.object.select_all(action='DESELECT')
		for o in [rig, *objects]:
			o.select_set(True)
		bpy.context.view_layer.objects.active = rig
		bpy.ops.export_scene.gltf(
			filepath=path, export_format='GLB', use_selection=True, export_apply=False, export_yup=True,
			export_materials='EXPORT', export_cameras=False, export_lights=False, export_skins=True,
			export_animations=True, export_animation_mode='ACTIONS', export_def_bones=True,
			export_reset_pose_bones=True, export_force_sampling=True, export_frame_step=1,
			export_optimize_animation_size=False, export_anim_single_armature=True,
			export_anim_slide_to_zero=False, export_merge_animation='ACTION',
		)
		print(f"FP_VM_EXPORT_OK {path}")

	# -- planche contact ------------------------------------------------------

	def _outline_material():
		mat = bpy.data.materials.new("fp_ink_outline")
		mat.use_nodes = True
		nt = mat.node_tree
		for n in list(nt.nodes):
			nt.nodes.remove(n)
		out = nt.nodes.new("ShaderNodeOutputMaterial")
		geo = nt.nodes.new("ShaderNodeNewGeometry")
		ink = nt.nodes.new("ShaderNodeEmission")
		ink.inputs["Color"].default_value = (0.02, 0.015, 0.012, 1.0)
		clear = nt.nodes.new("ShaderNodeBsdfTransparent")
		mix = nt.nodes.new("ShaderNodeMixShader")
		nt.links.new(geo.outputs["Backfacing"], mix.inputs["Fac"])
		nt.links.new(ink.outputs["Emission"], mix.inputs[1])
		nt.links.new(clear.outputs["BSDF"], mix.inputs[2])
		nt.links.new(mix.outputs["Shader"], out.inputs["Surface"])
		return mat

	def _matte_preview(mat) -> None:
		"""Aperçu de planche : albédo peint seul sur la Base Color (sans la
		couleur de sommet COLOR_0 que l'importeur glTF multiplie), mat, sans
		reflet spéculaire -- lecture des formes et des poses, pas du rendu final
		du jeu (shaders ink_toon)."""
		nt = mat.node_tree
		bsdf = nt.nodes.get("Principled BSDF")
		if bsdf is None:
			return
		image_node = next((n for n in nt.nodes if n.type == 'TEX_IMAGE' and n.image is not None), None)
		if image_node is not None:
			for link in list(bsdf.inputs["Base Color"].links):
				nt.links.remove(link)
			nt.links.new(image_node.outputs["Color"], bsdf.inputs["Base Color"])
		bsdf.inputs["Roughness"].default_value = 1.0
		bsdf.inputs["Specular IOR Level"].default_value = 0.0
		bsdf.inputs["Metallic"].default_value = 0.0

	def render_sheet(rig, clips: dict, actions: dict, objects: list, render_dir: str) -> list:
		"""12 rendus Cycles (GPU via lib/gpu_compute) sous la caméra FP du jeu
		(fp_camera.setup_camera : 54° vertical, 16:9), encre en coque
		inversée de 2,5 mm, lumière de fin d'après-midi."""
		sys.path.insert(0, os.path.join(HERE, "lib"))
		import gpu_compute
		scene = bpy.context.scene
		for track in rig.animation_data.nla_tracks:
			track.mute = True
		ink = _outline_material()
		for mat in {m for obj in objects for m in obj.data.materials if m and m.use_nodes}:
			_matte_preview(mat)
		for obj in objects:
			obj.data.materials.append(ink)
			mod = obj.modifiers.new("ink", type='SOLIDIFY')
			mod.thickness = 0.0025
			mod.offset = 1.0
			mod.use_flip_normals = True
			mod.use_rim = False
			mod.material_offset = len(obj.data.materials) - 1
		fp_camera.setup_camera(scene, render_w=800)
		scene.render.engine = 'CYCLES'
		backend = gpu_compute.use_gpu_for_cycles(scene)
		scene.cycles.samples = 32
		scene.cycles.use_denoising = True
		scene.view_settings.view_transform = 'Standard'
		scene.render.film_transparent = False
		world = bpy.data.worlds.new("fp_sheet_world")
		world.use_nodes = True
		bg = world.node_tree.nodes.get("Background")
		bg.inputs[0].default_value = (0.55, 0.66, 0.78, 1.0)
		bg.inputs[1].default_value = 0.9
		scene.world = world
		sun_data = bpy.data.lights.new("fp_sun", type='SUN')
		sun_data.energy = 3.2
		sun_data.color = (1.0, 0.93, 0.80)
		sun = bpy.data.objects.new("fp_sun", sun_data)
		sun.rotation_euler = (math.radians(35.0), math.radians(-25.0), math.radians(-30.0))
		scene.collection.objects.link(sun)
		os.makedirs(render_dir, exist_ok=True)
		paths = []
		for i, (clip_name, where, _label) in enumerate(SHEET_SHOTS):
			clip = clips[clip_name]
			if where == "peak":
				u = C.peak_frame(C.channel_series(clip, "weapon", "pos.z")) / clip.frames
			elif isinstance(where, str):
				u = clip.event_t(where)
			else:
				u = float(where)
			activate(rig, actions[clip_name])
			scene.frame_set(C.frame_of(clip, u))
			path = os.path.join(render_dir, f"shot_{i:02d}.png")
			scene.render.filepath = path
			scene.render.image_settings.file_format = 'PNG'
			bpy.ops.render.render(write_still=True)
			paths.append(path)
		print(f"FP_VM_RENDER_OK {len(paths)} rendus ({backend}) -> {render_dir}")
		return paths

	# -- pipeline complet -----------------------------------------------------

	def build(cfg: dict) -> dict:
		probe_bpy_api()
		_clear_scene()
		scene_bpy = bpy.context.scene
		scene_bpy.render.fps = C.FPS
		scene_bpy.render.fps_base = 1.0
		fam = family_module(cfg["family"])
		params = fam.params_from_config(cfg["choreo"], cfg["reload_time"])
		clips = fam.build_clips(params)
		errors = C.validate_clip_set(clips) + fam.validate_family(clips)
		if errors:
			raise RuntimeError("make_fp_viewmodel: chorégraphie invalide :\n  - " + "\n  - ".join(errors))

		rig, arms = import_arms(cfg["arms_glb"])
		rig.name = f"fp_{cfg['id']}"
		body, piece_objs, anchors = import_weapon(cfg["weapon_glb"], cfg["albedo"], cfg["pieces"])
		wgeom = WeaponGeom(body, piece_objs)
		vertex_bone = dominant_bones(arms)
		arms_bvh = BVHTree.FromPolygons([v.co.copy() for v in arms.data.vertices],
			[tuple(p.vertices) for p in arms.data.polygons])
		hands = {side: HandModel(rig, arms, side, vertex_bone, arms_bvh) for side in SIDES}
		sockets, depths, socket_hands = build_sockets(cfg, anchors, wgeom)
		pieces_rest = {piece: C.Transform(anchors[node].p) for piece, node in cfg["pieces"].items()}
		geom_base = {
			"sockets": sockets, "hip_sockets": dict(C.DEFAULT_HIP_SOCKETS), "pieces": pieces_rest,
			"grabs": dict(fam.GRABS),
		}

		# Recul de paume puis auto-prise de chaque repère de prise (espace arme).
		settles, grips = {}, {}
		for name, frame in list(sockets.items()):
			side = socket_hands[name]
			shift = settle_socket(hands[side], rig, arms, g2b_frame(frame), wgeom)
			normal = C.q_rotate(frame.q, C.AXIS_Y)
			sockets[name] = C.Transform(C.v_sub(frame.p, C.v_scale(normal, shift)), frame.q)
			settles[name] = shift
		for clip in clips:
			for fk in clip.fingers:
				side = fk.hand[-1]
				if fk.preset == "auto" and (side, fk.socket) not in grips:
					frame_b = g2b_frame(sockets[fk.socket])
					grips[(side, fk.socket)] = auto_grip(hands[side], rig, arms, frame_b, wgeom, fk.socket)

		arms_ik = {side: ArmModel(rig, side, cfg["shoulder"].get(HAND_OF[side], fp_rig.SHOULDER_REST_CAM[side]),
			cfg["pole_offset"].get(HAND_OF[side], fp_rig.POLE_OFFSET_CAM[side]),
			cfg["shoulder_follow"].get(HAND_OF[side], 0.5)) for side in SIDES}
		baker = Baker(rig, hands, arms_ik, grips, {})
		meshes = {"body": body, **piece_objs}
		meshes_rest = {"body": (body, body.matrix_world.copy())}
		for piece, obj in piece_objs.items():
			meshes_rest[piece] = (obj, obj.matrix_world.copy())
		anchors_b = {name: g2b(t.p) for name, t in anchors.items()}
		scene = Scene(rig, arms, meshes, hands, depths["Grip"], anchors_b)

		# Cadrage de hanche résolu : profondeur de bouche balayée, couverture la
		# plus proche de la cible parmi les poses qui tiennent carré central,
		# tiers haut et bouche.
		idle = next(c for c in clips if c.name == "idle_loop")
		hip_cfg = cfg["hip"]
		lo, hi, step = hip_cfg["muzzle_depth"]
		cov_lo, cov_hi = COVERAGE_RANGES[cfg["category"]]
		muzzle_local = anchors["Muzzle"].p
		candidates = []
		depth = lo
		while depth <= hi + 1e-9:
			hip = C.hip_weapon_for_depth(muzzle_local, tuple(hip_cfg["muzzle_screen"]), depth,
				hip_cfg["convergence_m"], hip_cfg.get("cant_deg", 0.0))
			meas = place_for_hip(hip, geom_base, anchors, baker, scene, meshes_rest, idle)
			meas["muzzle_depth"] = round(depth, 4)
			candidates.append(meas)
			print(f"FP_VM_HIP depth={depth:.3f} coverage={meas['coverage']:.4f} center={meas['center_vertices']} "
				f"top={meas['top_third_vertices']}")
			depth += step
		ok = [c for c in candidates if c["center_vertices"] == 0 and c["top_third_vertices"] == 0
			and cov_lo <= c["coverage"] <= cov_hi]
		pool = ok or candidates
		best = min(pool, key=lambda c: abs(c["coverage"] - hip_cfg["coverage_target"]))
		hip = C.hip_weapon_for_depth(muzzle_local, tuple(hip_cfg["muzzle_screen"]), best["muzzle_depth"],
			hip_cfg["convergence_m"], hip_cfg.get("cant_deg", 0.0))
		print(f"FP_VM_HIP_CHOSEN depth={best['muzzle_depth']} coverage={best['coverage']:.4f}")
		for side in SIDES:
			frame_b = g2b_frame(hip.compose(sockets[C.DEFAULT_HIP_SOCKETS[HAND_OF[side]]]))
			arms_ik[side].fit_shoulder(b2g(hands[side].bone_matrix(frame_b).translation))
		# Auto-prise définitive, bras posé par l'IK sur l'arme à la hanche.
		to_weapon = g2b_matrix(hip).inverted()
		for side, sock in list(grips):
			frame_b = g2b_frame(hip.compose(sockets[sock]))
			grips[(side, sock)] = auto_grip(hands[side], rig, arms, frame_b, wgeom, sock, arm=arms_ik[side],
				to_weapon=to_weapon)
		geom = C.RigGeometry(hip_weapon=hip, **geom_base)
		for clip in clips:
			errs = C.validate_clip(clip, geom)
			if errs:
				raise RuntimeError("make_fp_viewmodel: " + "; ".join(errs))

		# Squelette et maillages skinnés rigides (pose de hanche = repos des os d'arme).
		hip_b = g2b_matrix(hip)
		piece_rest_b = {piece: g2b_matrix(t) for piece, t in pieces_rest.items()}
		for pb in rig.pose.bones:
			pb.location, pb.rotation_quaternion, pb.scale = Vector(), Quaternion(), Vector((1, 1, 1))
		setup_weapon_bones(rig, hip_b, piece_rest_b)
		body.matrix_world = Matrix.Identity(4)
		skin_rigid(body, rig, "fp_weapon", hip_b, "wpn_body")
		for piece, obj in piece_objs.items():
			local = meshes_rest[piece][1]
			skin_rigid(obj, rig, f"fp_{piece}", hip_b @ local, f"wpn_{piece}")
		arms.name = "arms"
		arms.data.name = "arms"
		baker = Baker(rig, hands, arms_ik, grips, piece_rest_b)
		scene.meshes = {"body": body, **piece_objs}

		# Cuisson, rapport par image, NLA.
		actions, measures, shifts = {}, {}, {}
		for clip in clips:
			action, shift = bake_clip(clip, geom, baker, rig)
			actions[clip.name] = action
			shifts[clip.name] = round(shift * 100.0, 3)
			activate(rig, action)
			measures[clip.name] = measure_clip(clip, scene, wgeom, cfg["pieces"])
			measures[clip.name]["shoulder_shift_cm"] = shifts[clip.name]
			track = rig.animation_data.nla_tracks.new()
			track.name = clip.name
			strip = track.strips.new(clip.name, 0, action)
			if hasattr(strip, "action_slot") and strip.action_slot is None and action.slots:
				strip.action_slot = action.slots[0]
			rig.animation_data.action = None
			print(f"FP_VM_CLIP {clip.name} frames={clip.frames} palmR<={max(measures[clip.name]['palm_R_cm'])} "
				f"palmL<={max(measures[clip.name]['palm_L_cm'])} fingers<={max(measures[clip.name]['finger_penetration_mm'])} "
				f"center<={max(measures[clip.name]['center_vertices'])}")

		# Mesures de hanche sur la pose évaluée (idle, image 0).
		activate(rig, actions["idle_loop"])
		scene_bpy.frame_set(0)
		coverage = hip_coverage(scene)
		finger_hip = finger_penetration_by_finger(scene, wgeom, cfg["pieces"])
		weapon_eval = scene.bone("fp_weapon")
		muzzle_cam = b2g(weapon_eval @ anchors_b["Muzzle"])
		muzzle_screen = C.image_uv(muzzle_cam)
		rig.animation_data.action = None
		metrics = fam.family_metrics(clips, params)
		report = {
			"version": 1, "id": cfg["id"], "arms_mode": cfg["mode"], "fps": C.FPS,
			"thresholds": {k: list(v) if isinstance(v, tuple) else v for k, v in THRESHOLDS.items()},
			"hip": {
				"muzzle_depth_m": best["muzzle_depth"], "coverage": round(coverage, 5),
				"coverage_range": [cov_lo, cov_hi], "muzzle_screen": [round(muzzle_screen[0], 5), round(muzzle_screen[1], 5)],
				"center_vertices": measures["idle_loop"]["center_vertices"][0],
				"top_third_vertices": measures["idle_loop"]["top_third_vertices"][0],
				"candidates": candidates,
			},
			"metrics": {k: round(v, 5) if isinstance(v, float) else v for k, v in metrics.items()},
			"metric_thresholds": {k: [op, lim] for k, (op, lim) in fam.METRIC_THRESHOLDS.items()},
			"sockets_depth_cm": {k: round(v * 100.0, 3) for k, v in depths.items()},
			"sockets_settle_cm": {k: round(v * 100.0, 3) for k, v in settles.items()},
			"finger_penetration_hip_mm": finger_hip,
			"auto_grip_deg": {f"{s}@{sock}": {f: [round(c, 1) for c in v] for f, v in g.items()}
				for (s, sock), g in grips.items()},
			"clips": measures,
		}
		report["checks"] = evaluate_checks(report)
		report["pass"] = all(c["pass"] for c in report["checks"])

		paths = output_paths(cfg["out_dir"], cfg["id"], cfg["mode"])
		for track in rig.animation_data.nla_tracks:
			track.mute = False
		export_objects = [arms, body, *piece_objs.values()]
		export_glb(rig, export_objects, paths["glb"])

		summary = glb_summary(paths["glb"])
		length_errors = lengths_check(summary["animations"], cfg["reload_time"])
		missing_bones = sorted(set(fp_rig.DEFORM_BONE_NAMES) - set(summary["joints"]))
		extra_bones = sorted(set(summary["joints"]) & set(fp_rig.CONTROLLER_BONE_NAMES))
		report["glb"] = {"animations": {k: round(v, 5) for k, v in summary["animations"].items()},
			"skinned": summary["skinned"], "joints": len(summary["joints"]),
			"length_errors": length_errors, "missing_bones": missing_bones, "controller_bones": extra_bones}
		report["checks"].append(_check("glb", "GLB : os §3.2, aucun contrôleur, durées nominales ± 1 image",
			len(length_errors) + len(missing_bones) + len(extra_bones), 0,
			not (length_errors or missing_bones or extra_bones)))
		report["pass"] = all(c["pass"] for c in report["checks"])

		globals_ = glb_rest_globals(paths["glb"])
		summary_json = {
			"coverage_hip": round(coverage, 4), "muzzle_screen": [round(muzzle_screen[0], 4), round(muzzle_screen[1], 4)],
			"center_clear": all(c["pass"] for c in report["checks"] if c["id"] == "center"),
			"top_third_clear": all(c["pass"] for c in report["checks"] if c["id"] == "top_third"),
			"pass": report["pass"],
		}
		fp_json = build_fp_json(cfg["id"], cfg["family"], cfg["mode"], clips, hip, anchors, globals_["fp_weapon"],
			cfg["ads_depth"], summary_json)
		json_errors = validate_fp_json(fp_json, fam.EVENT_WINDOWS)
		if json_errors:
			raise RuntimeError("make_fp_viewmodel: JSON hors contrat : " + "; ".join(json_errors))
		with open(paths["json"], "w", encoding="utf-8") as fh:
			json.dump(fp_json, fh, indent=1, ensure_ascii=False)
		with open(paths["report"], "w", encoding="utf-8") as fh:
			json.dump(report, fh, indent=1, ensure_ascii=False)
		write_provenance(cfg, paths["provenance"])
		print(f"FP_VM_REPORT {'PASS' if report['pass'] else 'FAIL'} {paths['report']}")
		for chk in report["checks"]:
			print(f"FP_VM_CHECK {'OK' if chk['pass'] else 'FAIL'} {chk['id']} = {chk['value']} (limite {chk['limit']})")

		if cfg["render_dir"]:
			render_sheet(rig, {c.name: c for c in clips}, actions, export_objects, cfg["render_dir"])
		return report

	def write_provenance(cfg: dict, path: str) -> None:
		weapon_prov = {}
		if cfg["weapon_provenance"] and os.path.isfile(cfg["weapon_provenance"]):
			with open(cfg["weapon_provenance"], encoding="utf-8") as fh:
				weapon_prov = json.load(fh)
		data = {
			"tool": f"Blender {bpy.app.version_string} -- {SCRIPT_REL} (FP-13)",
			"script": SCRIPT_REL,
			"manifest": cfg["manifest_rel"],
			"date": datetime.date.today().isoformat(),
			"sources": [
				{"path": cfg["arms_glb_rel"], "generator": "tools/blender/fp_rig.py (FP-10)",
					"upstream": "assets/incoming/quaternius/ual.glb",
					"licence": "CC0 1.0 -- Quaternius, Universal Animation Library (THIRD_PARTY_LICENSES.md)"},
				{"path": cfg["weapon_glb_rel"], "generator": "tools/blender/rig_weapon_parts.py (FP-11)",
					"provenance": weapon_prov},
				*([{"path": cfg["albedo_rel"], "generator": "tools/blender/repaint_weapon.py (FP-12)"}]
					if cfg["albedo"] else []),
			],
			"licence": "Assemblage : bras CC0 (Quaternius UAL) + arme sous la provenance citée ci-dessus.",
		}
		with open(path, "w", encoding="utf-8") as fh:
			json.dump(data, fh, indent=1, ensure_ascii=False)

	def blender_main(argv=None) -> None:
		p = argparse.ArgumentParser(description="FP-13 -- côté Blender de make_fp_viewmodel.py")
		p.add_argument("--config", required=True)
		args = p.parse_args(argv)
		with open(args.config, encoding="utf-8") as fh:
			cfg = json.load(fh)
		build(cfg)

	if __name__ == "__main__":
		blender_main(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
elif __name__ == "__main__":
	sys.exit(cli_main())
