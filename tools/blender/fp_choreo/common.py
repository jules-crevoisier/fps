## tools/blender/fp_choreo/common.py -- FP-13 (docs/research/12_viewmodel_v2.md §3.5–3.7)
## DSL de chorégraphie FP en pur Python (aucun bpy) : clips décrits en
## DONNÉES (clés en fraction du clip, easing, doigts, attaches, événements),
## évaluation en espace caméra, validateurs et mesures (anticipation,
## dépassement, pic de tir, hors-cadre, carré central, couverture). Testé par
## `python -m pytest tools/blender/tests/test_fp_choreo.py` SANS Blender.
##
## Repères (même contrat que fp_camera.py) :
##   - espace CAMÉRA GODOT : X droite, Y haut, Z arrière (la caméra, à
##     l'origine, regarde -Z) ; c'est aussi l'espace du glTF exporté ;
##   - espace ARME (Godot) : origine = Grip, X droite, Y haut, -Z = canon
##     (axes des GLB v2, FP-11) ;
##   - écran « image » : (0,0) en haut à gauche, x vers la droite, y vers le
##     bas (convention de la bible §5.3 et de tools/fp_shots.gd). fp_camera.
##     project_point rend y vers le HAUT : `image_uv` fait la conversion.
##
## Rotations des clés : (tangage, lacet, roulis) en degrés, composées
## lacet(Y) · tangage(X) · roulis(Z), en axes caméra, autour de l'origine du
## repère de référence (le Grip pour l'arme). Signes = règle de la main
## droite des axes Godot : tangage + = bouche vers le haut ; lacet + = bouche
## vers la gauche ; roulis + = sens antihoraire vu du tireur (le dessus de
## l'arme part à gauche), roulis - = dessus vers la droite.
##
## Repères de référence d'une clé (`ref`) :
##   - "hip" : la pose de hanche de la cible, FIXE en espace caméra ; le
##     décalage est en axes caméra (arme : pose de hanche de l'arme ; main :
##     son repère de prise à la hanche) ;
##   - nom d'un repère de prise (« socket ») de l'arme, p. ex. "Foregrip",
##     "MagGrab" : le repère SUIT l'arme ; le décalage est en axes de l'arme
##     (x droite, y haut, z arrière de l'arme) ;
##   - "mount" (pièces seulement) : décalage local par rapport à la monture
##     courante de la pièce (arme ou main, voir `Attach`).
##
## Une main est représentée par son REPÈRE DE PRISE : origine = point de la
## paume posé sur la surface, X = direction des doigts (poignet -> jointures),
## Y = normale de la paume (vers l'objet tenu), Z = X × Y. Le générateur
## (make_fp_viewmodel.py) mesure ce repère sur l'os DEF-hand de chaque main et
## en déduit la matrice de l'os ; l'IK du bras est résolue et cuite là-bas.
from __future__ import annotations

import math
import os
import sys
from dataclasses import dataclass, field
from typing import Mapping, Sequence

HERE = os.path.dirname(os.path.abspath(__file__))
TOOLS_BLENDER_DIR = os.path.dirname(HERE)
if TOOLS_BLENDER_DIR not in sys.path:
	sys.path.insert(0, TOOLS_BLENDER_DIR)
import fp_camera  # noqa: E402 -- contrat caméra 54°/16:9 (partie pure, sans bpy)

# ---------------------------------------------------------------------------
# 1. Contrat (doc 12 §3.5) -- listes fermées.
# ---------------------------------------------------------------------------
FPS = 60
CLIP_NAMES = ("idle_loop", "run_loop", "fire", "draw", "reload", "reload_empty", "inspect")
LOOP_CLIPS = frozenset({"idle_loop", "run_loop"})
HANDS = ("hand.L", "hand.R")
PIECES = ("mag", "slide", "pump", "cylinder", "bolt", "prop")
TARGETS = ("weapon",) + HANDS + PIECES
EVENT_NAMES = frozenset({
	"equip", "mag_out", "mag_in", "mag_tap", "bolt", "slide_release", "cylinder_open", "eject",
	"speedloader_in", "cylinder_close", "hammer", "shell_in", "pump_back", "pump_fwd", "bolt_up",
	"bolt_back", "bolt_fwd", "bolt_down", "twirl", "inspect_touch",
})
EVENT_MAX_T = 0.95                    # « tous les événements < 0,95 » (critère FP-13).
FINGER_PRESETS = ("open", "flat", "grip", "trigger", "support", "pinch", "auto")
REF_HIP = "hip"
REF_MOUNT = "mount"
PARENT_WEAPON = "weapon"
DEFAULT_HIP_SOCKETS = {"hand.R": "Grip", "hand.L": "Foregrip"}

# Écran (bible §5.3, coordonnées « image ») -- critères §3.7.
CENTER_RECT = (0.40, 0.60, 0.40, 0.60)     # (x0, x1, y0, y1) : carré central 20 % × 20 %.
TOP_THIRD_RECT = (0.0, 1.0, 0.0, 1.0 / 3.0)
NEAR_M = 0.05                              # plan proche de la Camera3D Godot (défaut 0,05 m).

Vec3 = tuple
Quat = tuple

# ---------------------------------------------------------------------------
# 2. Algèbre (tuples) : vecteurs, quaternions (w, x, y, z), transformations.
# ---------------------------------------------------------------------------


def v_add(a, b):
	return (a[0] + b[0], a[1] + b[1], a[2] + b[2])


def v_sub(a, b):
	return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def v_scale(a, s):
	return (a[0] * s, a[1] * s, a[2] * s)


def v_dot(a, b):
	return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def v_cross(a, b):
	return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def v_len(a):
	return math.sqrt(v_dot(a, a))


def v_norm(a):
	length = v_len(a)
	if length < 1e-12:
		raise ValueError("fp_choreo: vecteur nul, direction indéfinie")
	return v_scale(a, 1.0 / length)


def v_lerp(a, b, w):
	return (a[0] + (b[0] - a[0]) * w, a[1] + (b[1] - a[1]) * w, a[2] + (b[2] - a[2]) * w)


def q_mul(a, b):
	aw, ax, ay, az = a
	bw, bx, by, bz = b
	return (
		aw * bw - ax * bx - ay * by - az * bz,
		aw * bx + ax * bw + ay * bz - az * by,
		aw * by - ax * bz + ay * bw + az * bx,
		aw * bz + ax * by - ay * bx + az * bw,
	)


def q_conj(q):
	return (q[0], -q[1], -q[2], -q[3])


def q_normalize(q):
	n = math.sqrt(sum(c * c for c in q))
	return tuple(c / n for c in q)


def q_axis_angle(axis, deg: float):
	a = v_norm(axis)
	half = math.radians(deg) / 2.0
	s = math.sin(half)
	return (math.cos(half), a[0] * s, a[1] * s, a[2] * s)


def q_rotate(q, v):
	"""Rotation de `v` par le quaternion unitaire `q`."""
	u = (q[1], q[2], q[3])
	t = v_scale(v_cross(u, v), 2.0)
	return v_add(v_add(v, v_scale(t, q[0])), v_cross(u, t))


def q_slerp(a, b, w: float):
	dot = sum(x * y for x, y in zip(a, b))
	if dot < 0.0:
		b = tuple(-c for c in b)
		dot = -dot
	if dot > 0.9995:
		return q_normalize(tuple(x + (y - x) * w for x, y in zip(a, b)))
	theta = math.acos(max(-1.0, min(1.0, dot)))
	s = math.sin(theta)
	wa = math.sin((1.0 - w) * theta) / s
	wb = math.sin(w * theta) / s
	return tuple(x * wa + y * wb for x, y in zip(a, b))


def q_angle_deg(a, b) -> float:
	"""Angle (degrés) entre deux orientations."""
	dot = abs(sum(x * y for x, y in zip(a, b)))
	return math.degrees(2.0 * math.acos(min(1.0, dot)))


def q_from_columns(x_axis, y_axis, z_axis):
	"""Quaternion d'une matrice de rotation donnée par ses COLONNES (axes
	locaux exprimés dans le repère parent) -- méthode de Shepperd."""
	m00, m10, m20 = x_axis
	m01, m11, m21 = y_axis
	m02, m12, m22 = z_axis
	trace = m00 + m11 + m22
	if trace > 0.0:
		s = math.sqrt(trace + 1.0) * 2.0
		q = (0.25 * s, (m21 - m12) / s, (m02 - m20) / s, (m10 - m01) / s)
	elif m00 > m11 and m00 > m22:
		s = math.sqrt(1.0 + m00 - m11 - m22) * 2.0
		q = ((m21 - m12) / s, 0.25 * s, (m01 + m10) / s, (m02 + m20) / s)
	elif m11 > m22:
		s = math.sqrt(1.0 + m11 - m00 - m22) * 2.0
		q = ((m02 - m20) / s, (m01 + m10) / s, 0.25 * s, (m12 + m21) / s)
	else:
		s = math.sqrt(1.0 + m22 - m00 - m11) * 2.0
		q = ((m10 - m01) / s, (m02 + m20) / s, (m12 + m21) / s, 0.25 * s)
	return q_normalize(q)


def q_columns(q):
	"""Colonnes (axes X, Y, Z) de la rotation `q`."""
	return (q_rotate(q, (1.0, 0.0, 0.0)), q_rotate(q, (0.0, 1.0, 0.0)), q_rotate(q, (0.0, 0.0, 1.0)))


AXIS_X = (1.0, 0.0, 0.0)
AXIS_Y = (0.0, 1.0, 0.0)
AXIS_Z = (0.0, 0.0, 1.0)
Q_IDENTITY = (1.0, 0.0, 0.0, 0.0)


def euler_quat(rot) -> tuple:
	"""(tangage X, lacet Y, roulis Z) en degrés -> quaternion, composé
	lacet · tangage · roulis (voir en-tête pour les signes)."""
	pitch, yaw, roll = rot
	return q_mul(q_axis_angle(AXIS_Y, yaw), q_mul(q_axis_angle(AXIS_X, pitch), q_axis_angle(AXIS_Z, roll)))


@dataclass(frozen=True)
class Transform:
	"""Transformation rigide : rotation `q` puis translation `p`."""
	p: tuple = (0.0, 0.0, 0.0)
	q: tuple = Q_IDENTITY

	def compose(self, other: "Transform") -> "Transform":
		return Transform(v_add(self.p, q_rotate(self.q, other.p)), q_normalize(q_mul(self.q, other.q)))

	def inverse(self) -> "Transform":
		qi = q_conj(self.q)
		return Transform(v_scale(q_rotate(qi, self.p), -1.0), qi)

	def apply(self, v) -> tuple:
		return v_add(self.p, q_rotate(self.q, v))

	def basis_columns(self) -> list:
		"""Base (9 flottants) : axe X, puis Y, puis Z (colonnes), comme
		`Basis(x, y, z)` de Godot."""
		cols = q_columns(self.q)
		return [c for col in cols for c in col]


def blend(a: Transform, b: Transform, w: float) -> Transform:
	return Transform(v_lerp(a.p, b.p, w), q_slerp(a.q, b.q, w))


def distance_deg(a: Transform, b: Transform) -> tuple:
	return v_len(v_sub(a.p, b.p)), q_angle_deg(a.q, b.q)


def hand_frame(origin, palm_normal, knuckles, side: str) -> Transform:
	"""Repère de prise d'une main (voir en-tête) depuis la normale de paume
	(vers l'objet) et la ligne des jointures (index -> auriculaire). La
	direction des doigts s'en déduit selon la main : droite f = k × n,
	gauche f = n × k (une main droite et une main gauche sont
	symétriques l'une de l'autre, jamais superposables par rotation)."""
	n = v_norm(palm_normal)
	k = v_norm(knuckles)
	if side == "R":
		f = v_cross(k, n)
	elif side == "L":
		f = v_cross(n, k)
	else:
		raise ValueError(f"fp_choreo: côté de main invalide {side!r} (L|R)")
	f = v_norm(f)
	n = v_norm(v_sub(n, v_scale(f, v_dot(n, f))))
	return Transform(tuple(origin), q_from_columns(f, n, v_cross(f, n)))


# ---------------------------------------------------------------------------
# 3. Easing (fraction de segment -> fraction de mouvement). "out_back"
#    dépasse d'environ 10 % avant de revenir (Penner, s = 1,70158).
# ---------------------------------------------------------------------------
_BACK_S = 1.70158


def _ease_out_back(u: float) -> float:
	x = u - 1.0
	return 1.0 + (_BACK_S + 1.0) * x * x * x + _BACK_S * x * x


EASES = {
	"linear": lambda u: u,
	"smooth": lambda u: u * u * (3.0 - 2.0 * u),
	"sine": lambda u: 0.5 - 0.5 * math.cos(math.pi * u),
	"in": lambda u: u * u * u,
	"out": lambda u: 1.0 - (1.0 - u) ** 3,
	"out_back": _ease_out_back,
}


def ease(name: str, u: float) -> float:
	if name not in EASES:
		raise ValueError(f"fp_choreo: easing inconnu {name!r} (connus : {sorted(EASES)})")
	return EASES[name](min(1.0, max(0.0, u)))


# ---------------------------------------------------------------------------
# 4. Le DSL.
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class Key:
	"""Clé d'une piste : `t` en fraction du clip ; `pos` (m) et `rot`
	(degrés, tangage/lacet/roulis) relatifs au repère `ref` ; `ease` =
	accélération du segment qui SE TERMINE sur cette clé ; `scale` =
	échelle uniforme (pièces seulement, 0,001 = cachée)."""
	t: float
	pos: tuple = (0.0, 0.0, 0.0)
	rot: tuple = (0.0, 0.0, 0.0)
	ease: str = "smooth"
	ref: str = REF_HIP
	scale: float = 1.0


@dataclass(frozen=True)
class FingerKey:
	"""Pose de doigts atteinte à `t` par `hand` : préréglage de fp_rig
	(`open`, `flat`, `grip`, `trigger`, `support`, `pinch`) ou `auto`
	(auto-prise BVH calculée par le générateur contre le repère `socket`)."""
	t: float
	hand: str
	preset: str
	socket: str = ""


@dataclass(frozen=True)
class Attach:
	"""À partir de `t`, la pièce `piece` est portée par `parent` (`weapon`,
	`hand.L`, `hand.R`) -- une contrainte Child Of cuite : la monture main
	est le repère de saisie `grabs["<pièce>@<main>"]` de la géométrie."""
	t: float
	piece: str
	parent: str


@dataclass(frozen=True)
class Event:
	t: float
	name: str


@dataclass(frozen=True)
class Clip:
	name: str
	length: float
	loop: bool
	keys: Mapping = field(default_factory=dict)
	fingers: tuple = ()
	attach: tuple = ()
	events: tuple = ()

	@property
	def frames(self) -> int:
		"""Nombre d'intervalles à FPS : les clés vont de l'image 0 à l'image
		`frames` incluse (durée = frames / FPS)."""
		return int(round(self.length * FPS))

	def event_t(self, name: str):
		for ev in self.events:
			if ev.name == name:
				return ev.t
		return None


def frame_length(seconds: float) -> float:
	"""Durée arrondie à l'image entière la plus proche (clés à 60 i/s) --
	`reload` = `reload_time` exactement (150 images pour 2,5 s)."""
	frames = max(1, int(round(seconds * FPS)))
	return frames / FPS


@dataclass(frozen=True)
class RigGeometry:
	"""Géométrie dont dépend l'évaluation (données mesurées par le générateur
	sur le rig et l'arme réels ; synthétiques dans les tests) :
	- `hip_weapon` : pose de hanche du Grip en espace caméra ;
	- `sockets` : repères de prise (espace arme) -- `hand_frame` ;
	- `hip_sockets` : repère de chaque main à la hanche ;
	- `pieces` : pose de repos de chaque pièce dans l'arme ;
	- `grabs` : `"<pièce>@<main>" -> socket` (monture quand la main la porte)."""
	hip_weapon: Transform
	sockets: Mapping
	hip_sockets: Mapping = field(default_factory=lambda: dict(DEFAULT_HIP_SOCKETS))
	pieces: Mapping = field(default_factory=dict)
	grabs: Mapping = field(default_factory=dict)


@dataclass(frozen=True)
class FingerState:
	a: FingerKey
	b: FingerKey
	w: float


@dataclass(frozen=True)
class Pose:
	transforms: Mapping
	scales: Mapping
	fingers: Mapping
	parents: Mapping


_DEFAULT_WEAPON_KEYS = (Key(0.0), Key(1.0))


def _default_hand_keys(hand: str, geom: RigGeometry):
	sock = geom.hip_sockets[hand]
	return (Key(0.0, ref=sock), Key(1.0, ref=sock))


def _segment(keys: Sequence[Key], u: float):
	"""Clés encadrant `u` et poids EASÉ du segment (easing de la clé d'arrivée)."""
	if u <= keys[0].t:
		return keys[0], keys[0], 0.0
	if u >= keys[-1].t:
		return keys[-1], keys[-1], 0.0
	for a, b in zip(keys, keys[1:]):
		if a.t <= u < b.t:
			return a, b, ease(b.ease, (u - a.t) / (b.t - a.t))
	return keys[-1], keys[-1], 0.0


def sample_offset(keys: Sequence[Key], u: float) -> dict:
	"""Décalage interpolé composante par composante à `u` (pos, rot, échelle),
	plus les repères des deux clés encadrantes."""
	a, b, w = _segment(keys, u)
	return {
		"pos": v_lerp(a.pos, b.pos, w), "rot": v_lerp(a.rot, b.rot, w),
		"scale": a.scale + (b.scale - a.scale) * w, "ref_a": a.ref, "ref_b": b.ref, "w": w,
	}


def _weapon_world(clip: Clip, u: float, geom: RigGeometry) -> Transform:
	off = sample_offset(clip.keys.get("weapon", _DEFAULT_WEAPON_KEYS), u)
	hip = geom.hip_weapon
	return Transform(v_add(hip.p, off["pos"]), q_normalize(q_mul(euler_quat(off["rot"]), hip.q)))


def _resolve_hand(ref: str, pos, rot, hand: str, weapon: Transform, geom: RigGeometry) -> Transform:
	if ref == REF_HIP:
		base = geom.hip_weapon.compose(geom.sockets[geom.hip_sockets[hand]])
		return Transform(v_add(base.p, pos), q_normalize(q_mul(euler_quat(rot), base.q)))
	sock = geom.sockets[ref]
	local = Transform(v_add(sock.p, pos), q_normalize(q_mul(euler_quat(rot), sock.q)))
	return weapon.compose(local)


def _hand_world(clip: Clip, hand: str, u: float, weapon: Transform, geom: RigGeometry) -> Transform:
	keys = clip.keys.get(hand) or _default_hand_keys(hand, geom)
	a, b, w = _segment(keys, u)
	if a.ref == b.ref:
		pos, rot = v_lerp(a.pos, b.pos, w), v_lerp(a.rot, b.rot, w)
		return _resolve_hand(a.ref, pos, rot, hand, weapon, geom)
	ta = _resolve_hand(a.ref, a.pos, a.rot, hand, weapon, geom)
	tb = _resolve_hand(b.ref, b.pos, b.rot, hand, weapon, geom)
	return blend(ta, tb, w)


def piece_parent(clip: Clip, piece: str, u: float) -> str:
	parent = PARENT_WEAPON
	for at in clip.attach:
		if at.piece == piece and at.t <= u + 1e-12:
			parent = at.parent
	return parent


def _mount(piece: str, parent: str, weapon: Transform, hands: Mapping, geom: RigGeometry) -> Transform:
	rest = geom.pieces[piece]
	if parent == PARENT_WEAPON:
		return weapon.compose(rest)
	grab = geom.sockets[geom.grabs[f"{piece}@{parent}"]]
	return hands[parent].compose(grab.inverse().compose(rest))


def finger_state(clip: Clip, hand: str, u: float, geom: RigGeometry) -> FingerState:
	keys = [fk for fk in clip.fingers if fk.hand == hand]
	if not keys:
		fk = FingerKey(0.0, hand, "auto", geom.hip_sockets[hand])
		return FingerState(fk, fk, 0.0)
	if u <= keys[0].t:
		return FingerState(keys[0], keys[0], 0.0)
	if u >= keys[-1].t:
		return FingerState(keys[-1], keys[-1], 0.0)
	for a, b in zip(keys, keys[1:]):
		if a.t <= u < b.t:
			return FingerState(a, b, ease("smooth", (u - a.t) / (b.t - a.t)))
	return FingerState(keys[-1], keys[-1], 0.0)


def evaluate(clip: Clip, u: float, geom: RigGeometry) -> Pose:
	"""Pose complète à la fraction `u` : transformations en espace caméra
	(`weapon`, `hand.L`, `hand.R`, pièces présentes dans `geom.pieces`),
	échelles des pièces, état des doigts et parent de chaque pièce."""
	weapon = _weapon_world(clip, u, geom)
	hands = {hand: _hand_world(clip, hand, u, weapon, geom) for hand in HANDS}
	transforms = {"weapon": weapon, **hands}
	scales, parents = {}, {}
	for piece in geom.pieces:
		parent = piece_parent(clip, piece, u)
		mount = _mount(piece, parent, weapon, hands, geom)
		keys = clip.keys.get(piece)
		if keys:
			off = sample_offset(keys, u)
			mount = mount.compose(Transform(off["pos"], euler_quat(off["rot"])))
			scales[piece] = off["scale"]
		else:
			scales[piece] = 1.0
		transforms[piece] = mount
		parents[piece] = parent
	fingers = {hand: finger_state(clip, hand, u, geom) for hand in HANDS}
	return Pose(transforms=transforms, scales=scales, fingers=fingers, parents=parents)


def frame_fractions(clip: Clip) -> list:
	"""Fractions de clip des images 0..frames (incluses)."""
	n = clip.frames
	return [i / n for i in range(n + 1)]


# ---------------------------------------------------------------------------
# 5. Validateurs (listes d'erreurs lisibles, vides si tout va bien).
# ---------------------------------------------------------------------------


def validate_clip(clip: Clip, geom: RigGeometry = None) -> list:
	errors = []
	tag = f"clip {clip.name!r}"
	if clip.name not in CLIP_NAMES:
		errors.append(f"{tag} : nom hors contrat (attendus : {', '.join(CLIP_NAMES)})")
	if clip.length <= 0.0:
		errors.append(f"{tag} : durée {clip.length} <= 0")
	elif abs(clip.length * FPS - round(clip.length * FPS)) > 1e-6:
		errors.append(f"{tag} : durée {clip.length} s pas un nombre entier d'images à {FPS} i/s (frame_length)")
	if clip.loop != (clip.name in LOOP_CLIPS):
		errors.append(f"{tag} : loop={clip.loop} alors que seuls {sorted(LOOP_CLIPS)} bouclent")
	sockets = set(geom.sockets) if geom is not None else None
	for target, keys in clip.keys.items():
		ttag = f"{tag}, piste {target!r}"
		if target not in TARGETS:
			errors.append(f"{ttag} : cible inconnue (connues : {', '.join(TARGETS)})")
			continue
		if not keys:
			errors.append(f"{ttag} : aucune clé")
			continue
		times = [k.t for k in keys]
		if any(b <= a for a, b in zip(times, times[1:])):
			errors.append(f"{ttag} : clés non strictement croissantes {times}")
		if abs(times[0]) > 1e-9 or abs(times[-1] - 1.0) > 1e-9:
			errors.append(f"{ttag} : la piste doit couvrir [0 ; 1] (première clé {times[0]}, dernière {times[-1]})")
		for k in keys:
			if k.ease not in EASES:
				errors.append(f"{ttag} : easing inconnu {k.ease!r} à t={k.t}")
			if target == "weapon" and k.ref != REF_HIP:
				errors.append(f"{ttag} : l'arme ne se réfère qu'à {REF_HIP!r} (clé t={k.t} : {k.ref!r})")
			elif target in HANDS and k.ref != REF_HIP and sockets is not None and k.ref not in sockets:
				errors.append(f"{ttag} : repère {k.ref!r} absent de la géométrie (t={k.t})")
			elif target in PIECES and k.ref != REF_MOUNT:
				errors.append(f"{ttag} : une pièce se réfère à {REF_MOUNT!r} (clé t={k.t} : {k.ref!r})")
			if target not in PIECES and abs(k.scale - 1.0) > 1e-12:
				errors.append(f"{ttag} : échelle réservée aux pièces (t={k.t})")
		if clip.loop:
			a, b = keys[0], keys[-1]
			if a.ref != b.ref or v_len(v_sub(a.pos, b.pos)) > 1e-9 or v_len(v_sub(a.rot, b.rot)) > 1e-9 \
					or abs(a.scale - b.scale) > 1e-12:
				errors.append(f"{ttag} : boucle discontinue (clé 0 != clé 1)")
	for hand in HANDS:
		fk = [k for k in clip.fingers if k.hand == hand]
		times = [k.t for k in fk]
		if any(b <= a for a, b in zip(times, times[1:])):
			errors.append(f"{tag} : doigts {hand} non strictement croissants {times}")
	for k in clip.fingers:
		if k.hand not in HANDS:
			errors.append(f"{tag} : doigts sur une main inconnue {k.hand!r}")
		if k.preset not in FINGER_PRESETS:
			errors.append(f"{tag} : préréglage de doigts inconnu {k.preset!r} (connus : {', '.join(FINGER_PRESETS)})")
		if k.preset == "auto" and not k.socket:
			errors.append(f"{tag} : auto-prise sans repère à t={k.t}")
		if k.preset == "auto" and k.socket and sockets is not None and k.socket not in sockets:
			errors.append(f"{tag} : auto-prise sur un repère absent {k.socket!r}")
		if not 0.0 <= k.t <= 1.0:
			errors.append(f"{tag} : doigts hors du clip à t={k.t}")
	if clip.loop:
		for hand in HANDS:
			fk = [k for k in clip.fingers if k.hand == hand]
			if fk and (fk[0].preset, fk[0].socket) != (fk[-1].preset, fk[-1].socket):
				errors.append(f"{tag} : doigts {hand} discontinus au bouclage")
	previous_t = -1.0
	for at in clip.attach:
		if at.piece not in PIECES:
			errors.append(f"{tag} : attache d'une pièce inconnue {at.piece!r}")
		if at.parent not in (PARENT_WEAPON,) + HANDS:
			errors.append(f"{tag} : parent d'attache inconnu {at.parent!r}")
		if not 0.0 <= at.t <= 1.0:
			errors.append(f"{tag} : attache hors du clip à t={at.t}")
		if at.t < previous_t:
			errors.append(f"{tag} : attaches non triées")
		previous_t = at.t
	previous_t = -1.0
	seen = set()
	for ev in clip.events:
		if ev.name not in EVENT_NAMES:
			errors.append(f"{tag} : événement hors liste fermée {ev.name!r}")
		if not 0.0 <= ev.t < EVENT_MAX_T:
			errors.append(f"{tag} : événement {ev.name!r} à t={ev.t} hors de [0 ; {EVENT_MAX_T}[")
		if ev.t < previous_t:
			errors.append(f"{tag} : événements non triés")
		if ev.name in seen:
			errors.append(f"{tag} : événement {ev.name!r} en double")
		seen.add(ev.name)
		previous_t = ev.t
	if geom is not None and not errors:
		errors.extend(validate_attach_continuity(clip, geom))
	return errors


def validate_attach_continuity(clip: Clip, geom: RigGeometry, tol_m: float = 0.001, tol_deg: float = 0.5) -> list:
	"""Une attache cuite ne doit jamais faire sauter la pièce : à chaque
	changement de parent, la monture de l'ancien parent et celle du nouveau
	coïncident (la main est exactement sur son repère de saisie)."""
	errors = []
	for at in clip.attach:
		if at.piece not in geom.pieces:
			errors.append(f"clip {clip.name!r} : pièce {at.piece!r} absente de la géométrie")
			continue
		before = piece_parent(clip, at.piece, at.t - 1e-9)
		if before == at.parent:
			continue
		weapon = _weapon_world(clip, at.t, geom)
		hands = {hand: _hand_world(clip, hand, at.t, weapon, geom) for hand in HANDS}
		try:
			old = _mount(at.piece, before, weapon, hands, geom)
			new = _mount(at.piece, at.parent, weapon, hands, geom)
		except KeyError as exc:
			errors.append(f"clip {clip.name!r} : monture introuvable pour {at.piece!r} ({exc})")
			continue
		dist, ang = distance_deg(old, new)
		if dist > tol_m or ang > tol_deg:
			errors.append(
				f"clip {clip.name!r} : attache de {at.piece!r} vers {at.parent!r} à t={at.t} discontinue "
				f"({dist * 100:.2f} cm, {ang:.2f}°) -- la main doit être sur son repère de saisie")
	return errors


def validate_clip_set(clips: Sequence[Clip], geom: RigGeometry = None) -> list:
	errors = []
	names = [c.name for c in clips]
	if sorted(names) != sorted(CLIP_NAMES):
		errors.append(f"jeu de clips {names} != contrat {list(CLIP_NAMES)}")
	for clip in clips:
		errors.extend(validate_clip(clip, geom))
	return errors


# ---------------------------------------------------------------------------
# 6. Mesures sur les courbes (principes du §3.5).
# ---------------------------------------------------------------------------
CHANNELS = {"pos.x": ("pos", 0), "pos.y": ("pos", 1), "pos.z": ("pos", 2),
	"rot.x": ("rot", 0), "rot.y": ("rot", 1), "rot.z": ("rot", 2), "scale": ("scale", None)}


def channel_series(clip: Clip, target: str, channel: str) -> list:
	"""Valeur d'un canal de décalage (composante de `pos`/`rot`, ou
	`scale`) à chaque image 0..frames -- mesure DSL, indépendante du rig."""
	if channel not in CHANNELS:
		raise ValueError(f"fp_choreo: canal inconnu {channel!r}")
	keys = clip.keys.get(target)
	if not keys:
		return [0.0] * (clip.frames + 1)
	kind, idx = CHANNELS[channel]
	out = []
	for u in frame_fractions(clip):
		off = sample_offset(keys, u)
		out.append(off[kind] if idx is None else off[kind][idx])
	return out


def anticipation_seconds(series: Sequence[float], fps: int = FPS, eps: float = 1e-6) -> float:
	"""Durée (s) pendant laquelle la courbe part d'abord à CONTRE-SENS de son
	excursion principale (anticipation, §3.5), comptée avant le pic."""
	v0 = series[0]
	i_peak = max(range(len(series)), key=lambda i: abs(series[i] - v0))
	if abs(series[i_peak] - v0) <= eps:
		return 0.0
	sign = 1.0 if series[i_peak] > v0 else -1.0
	count = sum(1 for v in series[:i_peak] if sign * (v - v0) < -eps)
	return count / fps


def overshoot_ratio(series: Sequence[float], i_from: int, i_to: int) -> float:
	"""Dépassement de la course `series[i_from] -> series[i_to]`, en fraction
	de l'amplitude : excursion maximale AU-DELÀ de la valeur d'arrivée,
	dans le sens du mouvement, entre `i_from` et `i_to`."""
	start, end = series[i_from], series[i_to]
	amp = end - start
	if abs(amp) < 1e-12:
		return 0.0
	sign = 1.0 if amp > 0 else -1.0
	beyond = max(sign * (v - end) for v in series[i_from:i_to + 1])
	return max(0.0, beyond) / abs(amp)


def peak_frame(series: Sequence[float]) -> int:
	v0 = series[0]
	return max(range(len(series)), key=lambda i: abs(series[i] - v0))


def frame_of(clip: Clip, t: float) -> int:
	return int(round(t * clip.frames))


# ---------------------------------------------------------------------------
# 7. Écran : projection, carrés de contrôle, hors-cadre, couverture.
# ---------------------------------------------------------------------------


def image_uv(p_cam):
	"""Point caméra Godot -> (x, y) écran « image » (y vers le bas), ou None
	derrière le plan proche."""
	if p_cam[2] > -NEAR_M:
		return None
	uv = fp_camera.project_point(p_cam)
	if uv is None:
		return None
	return (uv[0], 1.0 - uv[1])


def project_array(points):
	"""Projection vectorisée (numpy, N×3 caméra Godot) -> (uv N×2 « image »,
	masque des points visibles : devant le plan proche)."""
	import numpy as np
	pts = np.asarray(points, dtype=np.float64).reshape(-1, 3)
	depth = -pts[:, 2]
	valid = depth > NEAR_M
	safe = np.where(valid, depth, 1.0)
	half_h = safe * math.tan(math.radians(fp_camera.FOV_Y_DEG / 2.0))
	half_w = half_h * fp_camera.ASPECT
	u = 0.5 + 0.5 * pts[:, 0] / half_w
	v = 0.5 - 0.5 * pts[:, 1] / half_h
	return np.stack([u, v], axis=1), valid


def count_in_rect(points, rect) -> int:
	"""Nombre de points visibles projetés dans `rect` = (x0, x1, y0, y1)."""
	import numpy as np
	uv, valid = project_array(points)
	x0, x1, y0, y1 = rect
	inside = valid & (uv[:, 0] >= x0) & (uv[:, 0] <= x1) & (uv[:, 1] >= y0) & (uv[:, 1] <= y1)
	return int(np.count_nonzero(inside))


def all_outside_frame(points) -> bool:
	"""Vrai si aucun point n'est visible dans le cadre [0,1]² (derrière le
	plan proche ou hors cadre)."""
	return count_in_rect(points, (0.0, 1.0, 0.0, 1.0)) == 0


def longest_run_seconds(flags: Sequence[bool], i_from: int, i_to: int, fps: int = FPS) -> float:
	"""Plus longue suite d'images `True` entre `i_from` et `i_to` inclus,
	convertie en durée PRUDENTE : n images consécutives = (n - 1) / fps (le
	temps écoulé entre la première et la dernière image observées)."""
	best = run = 0
	for i in range(max(0, i_from), min(len(flags) - 1, i_to) + 1):
		run = run + 1 if flags[i] else 0
		best = max(best, run)
	return max(0, best - 1) / fps


def _clip_near(poly, near: float):
	"""Découpe (Sutherland–Hodgman) d'un polygone caméra par le plan z = -near."""
	out = []
	n = len(poly)
	for i in range(n):
		a, b = poly[i], poly[(i + 1) % n]
		ina, inb = a[2] <= -near, b[2] <= -near
		if ina:
			out.append(a)
		if ina != inb:
			w = (-near - a[2]) / (b[2] - a[2])
			out.append(tuple(a[j] + (b[j] - a[j]) * w for j in range(3)))
	return out


def coverage_fraction(triangles, width: int = 384, height: int = 216, near: float = NEAR_M) -> float:
	"""Fraction de l'écran couverte par des triangles caméra (T×3×3),
	découpés au plan proche puis rastérisés au centre des pixels (grille
	`width`×`height`, même ratio 16:9 que la caméra)."""
	import numpy as np
	tris = np.asarray(triangles, dtype=np.float64).reshape(-1, 3, 3)
	mask = np.zeros((height, width), dtype=bool)
	th = math.tan(math.radians(fp_camera.FOV_Y_DEG / 2.0))
	aspect = fp_camera.ASPECT

	def to_px(p):
		d = -p[..., 2]
		u = 0.5 + 0.5 * p[..., 0] / (d * th * aspect)
		v = 0.5 - 0.5 * p[..., 1] / (d * th)
		return np.stack([u * width, v * height], axis=-1)

	front = np.all(tris[:, :, 2] <= -near, axis=1)
	behind = np.all(tris[:, :, 2] > -near, axis=1)
	polys = [tri for tri in tris[front]]
	for tri in tris[~front & ~behind]:
		clipped = _clip_near([tuple(v) for v in tri], near)
		for i in range(1, len(clipped) - 1):
			polys.append(np.array([clipped[0], clipped[i], clipped[i + 1]]))
	if not polys:
		return 0.0
	px = to_px(np.asarray(polys))
	for tri in px:
		x_min = max(0, int(math.floor(tri[:, 0].min() - 0.5)))
		x_max = min(width - 1, int(math.ceil(tri[:, 0].max() - 0.5)))
		y_min = max(0, int(math.floor(tri[:, 1].min() - 0.5)))
		y_max = min(height - 1, int(math.ceil(tri[:, 1].max() - 0.5)))
		if x_min > x_max or y_min > y_max:
			continue
		xs = np.arange(x_min, x_max + 1) + 0.5
		ys = np.arange(y_min, y_max + 1) + 0.5
		gx, gy = np.meshgrid(xs, ys)
		(ax, ay), (bx, by), (cx, cy) = tri
		area = (bx - ax) * (cy - ay) - (by - ay) * (cx - ax)
		if abs(area) < 1e-12:
			continue
		w0 = (bx - ax) * (gy - ay) - (by - ay) * (gx - ax)
		w1 = (cx - bx) * (gy - by) - (cy - by) * (gx - bx)
		w2 = (ax - cx) * (gy - cy) - (ay - cy) * (gx - cx)
		if area > 0:
			inside = (w0 >= 0) & (w1 >= 0) & (w2 >= 0)
		else:
			inside = (w0 <= 0) & (w1 <= 0) & (w2 <= 0)
		mask[y_min:y_max + 1, x_min:x_max + 1] |= inside
	return float(mask.mean())


# ---------------------------------------------------------------------------
# 8. Cadrage de hanche (doc 12 : « bouche x 0,61 / y 0,60 »).
# ---------------------------------------------------------------------------


def screen_ray(img_uv) -> tuple:
	"""Direction caméra (z = -1) du rayon qui passe par le point écran
	« image » `img_uv`."""
	th = math.tan(math.radians(fp_camera.FOV_Y_DEG / 2.0))
	x = (2.0 * img_uv[0] - 1.0) * th * fp_camera.ASPECT
	y = (1.0 - 2.0 * img_uv[1]) * th
	return (x, y, -1.0)


def hip_weapon_for_depth(muzzle_local, muzzle_img_uv, muzzle_depth: float, convergence_m: float,
		cant_deg: float = 0.0) -> Transform:
	"""Pose de hanche du Grip telle que la bouche (`muzzle_local`, espace
	arme) se projette EXACTEMENT sur `muzzle_img_uv` à la profondeur
	`muzzle_depth`, canon (-Z arme) pointé vers le point de convergence
	(0, 0, -convergence) de l'axe de visée, puis incliné de `cant_deg` en
	roulis autour du canon (+ = dessus vers la gauche)."""
	muzzle_cam = v_scale(screen_ray(muzzle_img_uv), muzzle_depth)
	d = v_norm(v_sub((0.0, 0.0, -convergence_m), muzzle_cam))
	z_axis = v_scale(d, -1.0)
	x_axis = v_norm(v_cross(AXIS_Y, z_axis))
	y_axis = v_cross(z_axis, x_axis)
	q = q_mul(q_axis_angle(z_axis, cant_deg), q_from_columns(x_axis, y_axis, z_axis))
	q = q_normalize(q)
	grip = v_sub(muzzle_cam, q_rotate(q, muzzle_local))
	return Transform(grip, q)
