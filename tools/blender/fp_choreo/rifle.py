## tools/blender/fp_choreo/rifle.py -- FP-13 (docs/research/12_viewmodel_v2.md §3.5)
## Famille « fusil à chargeur » : Ravage (2,5 s), puis Rafale (2,1 s) et
## Marqueur (2,4 s) en FP-18 SANS modifier ce fichier -- tout ce qui change
## d'une arme à l'autre passe par `RifleParams` (durées lues dans le .tres,
## surcharges du manifeste `tools/ai3d/manifests/fp/<id>.yaml`, section
## `choreo`). Les temps forts par défaut sont ceux du §3.5 (fractions de clip).
##
## Repères de prise attendus dans la géométrie (manifeste, section `sockets`) :
## Grip (main droite), Foregrip (main gauche à la hanche), MagGrab (main gauche
## qui tient le chargeur en place), MagTap (paume sous le culot du chargeur),
## MagTouch (paume à plat sur le flanc du chargeur, inspection), Charge (levier
## d'armement, rechargement à vide).
from __future__ import annotations

from dataclasses import dataclass, fields, replace

from .common import (
	Attach, Clip, Event, FingerKey, Key, REF_HIP, anticipation_seconds, channel_series, frame_length,
	frame_of, overshoot_ratio, peak_frame,
)

FAMILY = "rifle"
REQUIRED_SOCKETS = ("Grip", "Foregrip", "MagGrab", "MagTap", "MagTouch", "Charge")
PIECES = {"mag": "Mag"}          # pièce DSL -> nœud du GLB v2 (FP-11).
GRABS = {"mag@hand.L": "MagGrab"}

# Fenêtres d'événements du critère d'acceptation (FP-13), en fraction de clip.
EVENT_WINDOWS = {
	"reload": {"mag_out": (0.15, 0.30), "mag_in": (0.70, 0.82)},
	"reload_empty": {"mag_out": (0.15, 0.30), "mag_in": (0.70, 0.82), "bolt": (0.82, 0.92)},
}


@dataclass(frozen=True)
class RifleParams:
	"""Paramètres de la famille (valeurs par défaut = Ravage, doc 12 §3.5).
	Temps en secondes (`*_time`, `recoil_*_s`) ou en fraction de clip
	(tout le reste des instants) ; distances en mètres ; angles en degrés
	(conventions de common.py)."""
	reload_time: float
	fire_time: float = 0.16
	draw_time: float = 0.40
	idle_time: float = 3.0
	run_time: float = 0.66
	inspect_time: float = 3.0
	# Rechargement (§3.5 « Fusil à chargeur »).
	anticip_end: float = 0.07
	anticip_roll_deg: float = 6.0
	anticip_lift_m: float = 0.01
	tilt_end: float = 0.20
	tilt_roll_deg: float = -28.0
	tilt_pitch_deg: float = 8.0
	tilt_shift: tuple = (-0.04, -0.04, 0.0)
	hand_leave: float = 0.12
	mag_out: float = 0.20
	mag_pull: tuple = (0.0, -0.05, -0.012)
	mag_pull_end: float = 0.25
	mag_clear: tuple = (0.0, -0.14, -0.03)   # chargeur dégagé du puits avant de tourner vers le hors-cadre
	mag_clear_at: float = 0.29
	offscreen_by: float = 0.34
	offscreen_until: float = 0.56
	offscreen_hand: tuple = (-0.30, -0.34, 0.10)
	offscreen_rot: tuple = (-20.0, 0.0, 30.0)
	mag_below: float = 0.70
	mag_approach: tuple = (0.0, -0.10, -0.01)
	mag_in: float = 0.76
	jolt_m: float = 0.015
	jolt_deg: float = 3.0
	mag_seat: float = 0.775
	mag_tap: float = 0.80
	return_start: float = 0.84
	fore_at: float = 0.92
	fore_via: tuple = (-0.02, -0.26, 0.05)   # sous le culot puis devant la pointe du chargeur courbe
	settle_roll_deg: float = 3.0
	# Rechargement à vide : levier d'armement.
	charge_at: float = 0.845
	charge_via: tuple = (-0.02, -0.10, 0.02)  # sous le levier, le long du chargeur : la main le contourne
	charge_hold_shift: tuple = (0.02, -0.03, 0.0)  # arme plus basse et moins à gauche pendant l'armement
	charge_pull_m: float = 0.045
	charge_pulled: float = 0.875
	bolt: float = 0.88
	empty_fore_at: float = 0.96
	# Tir.
	recoil_back_m: float = 0.012
	recoil_lift_m: float = 0.002
	recoil_pitch_deg: float = 1.5
	recoil_peak_frames: int = 2
	recoil_return_s: float = 0.12
	recoil_overshoot: float = 0.15
	# Dégainer.
	draw_offset: tuple = (0.06, -0.25, 0.04)
	draw_roll_deg: float = -35.0
	draw_pitch_deg: float = -20.0
	draw_overshoot_deg: float = 4.0
	draw_overshoot_at: float = 0.70
	equip: float = 0.05
	# Inspection.
	inspect_yaw_deg: float = 35.0
	inspect_roll_deg: float = 40.0
	inspect_touch: float = 0.50
	# Repos et course.
	breath_m: float = 0.002
	breath_deg: float = 0.4
	run_pitch_deg: float = -8.0
	run_roll_deg: float = 10.0
	run_drop_m: float = 0.03
	run_bob_m: float = 0.008


_TUPLE_FIELDS = {f.name for f in fields(RifleParams) if isinstance(f.default, tuple)}
_INT_FIELDS = {"recoil_peak_frames"}


def params_from_config(config, reload_time: float) -> RifleParams:
	"""`RifleParams` pour une arme : `reload_time` (lu dans le .tres, jamais
	recopié) + surcharges `config` (section `choreo` du manifeste). Une clé
	inconnue est une erreur (faute de frappe = paramètre ignoré sinon)."""
	params = RifleParams(reload_time=float(reload_time))
	if not config:
		return params
	known = {f.name for f in fields(RifleParams)} - {"reload_time"}
	unknown = sorted(set(config) - known)
	if unknown:
		raise ValueError(f"fp_choreo.rifle: paramètres inconnus {unknown} (connus : {sorted(known)})")
	values = {}
	for name, value in config.items():
		if name in _TUPLE_FIELDS:
			values[name] = tuple(float(c) for c in value)
		elif name in _INT_FIELDS:
			values[name] = int(value)
		else:
			values[name] = float(value)
	return replace(params, **values)


def _add(a, b):
	return (a[0] + b[0], a[1] + b[1], a[2] + b[2])


def _mul(a, s):
	return (a[0] * s, a[1] * s, a[2] * s)


def _both_hands_auto(ts, hip_r="Grip", hip_l="Foregrip"):
	keys = []
	for t in ts:
		keys.append(FingerKey(t, "hand.R", "auto", hip_r))
	for t in ts:
		keys.append(FingerKey(t, "hand.L", "auto", hip_l))
	return tuple(keys)


def _grip_fingers(ts=(0.0, 1.0)):
	return tuple(FingerKey(t, "hand.R", "auto", "Grip") for t in ts)


def idle_clip(p: RifleParams) -> Clip:
	"""Respiration : 2 mm et 0,4° (§3.5), boucle."""
	weapon = (
		Key(0.0),
		Key(0.5, pos=(0.0, p.breath_m, 0.0), rot=(p.breath_deg, 0.0, 0.0), ease="sine"),
		Key(1.0, ease="sine"),
	)
	return Clip("idle_loop", frame_length(p.idle_time), True, {"weapon": weapon},
		fingers=_both_hands_auto((0.0, 1.0)))


def run_clip(p: RifleParams) -> Clip:
	"""Course (remplace le roulis de 25°) : tangage -8°, roulis 10° vers la
	gauche, arme abaissée de 3 cm, deux appuis par cycle."""
	base_pos = (0.01, -p.run_drop_m, 0.0)
	base_rot = (p.run_pitch_deg, 0.0, p.run_roll_deg)
	weapon = (
		Key(0.0, pos=base_pos, rot=base_rot),
		Key(0.25, pos=_add(base_pos, (-0.004, -p.run_bob_m, 0.0)), rot=_add(base_rot, (1.0, 1.0, 1.5)), ease="sine"),
		Key(0.5, pos=base_pos, rot=base_rot, ease="sine"),
		Key(0.75, pos=_add(base_pos, (0.004, -p.run_bob_m, 0.0)), rot=_add(base_rot, (1.0, -1.0, -1.5)), ease="sine"),
		Key(1.0, pos=base_pos, rot=base_rot, ease="sine"),
	)
	return Clip("run_loop", frame_length(p.run_time), True, {"weapon": weapon},
		fingers=_both_hands_auto((0.0, 1.0)))


def fire_clip(p: RifleParams) -> Clip:
	"""Pic de recul à `recoil_peak_frames` images, retour à `recoil_return_s`
	avec `recoil_overshoot` de dépassement (§3.5 : le gros du recul reste le
	ressort procédural du jeu)."""
	length = frame_length(p.fire_time)
	frames = int(round(length * 60))
	t_peak = p.recoil_peak_frames / frames
	t_ret = min(0.9, round(p.recoil_return_s * 60) / frames)
	over = p.recoil_overshoot
	weapon = (
		Key(0.0),
		Key(t_peak, pos=(0.0, p.recoil_lift_m, p.recoil_back_m), rot=(p.recoil_pitch_deg, 0.0, 0.0), ease="out"),
		Key(t_ret, pos=(0.0, -p.recoil_lift_m * over, -p.recoil_back_m * over),
			rot=(-p.recoil_pitch_deg * over, 0.0, 0.0), ease="smooth"),
		Key(1.0, ease="smooth"),
	)
	return Clip("fire", length, False, {"weapon": weapon}, fingers=_both_hands_auto((0.0, 1.0)))


def draw_clip(p: RifleParams) -> Clip:
	"""Départ en bas à droite (-25 cm, roulis -35°, tangage -20°), dépassement
	de roulis de +4° à 0,70 (le dépassement est angulaire : un dépassement de
	position vers le haut ferait entrer la bouche dans le carré central)."""
	weapon = (
		Key(0.0, pos=p.draw_offset, rot=(p.draw_pitch_deg, 0.0, p.draw_roll_deg)),
		Key(p.draw_overshoot_at, rot=(0.0, 0.0, p.draw_overshoot_deg), ease="out"),
		Key(1.0, ease="smooth"),
	)
	return Clip("draw", frame_length(p.draw_time), False, {"weapon": weapon},
		fingers=_both_hands_auto((0.0, 1.0)), events=(Event(p.equip, "equip"),))


def _reload_weapon_common(p: RifleParams):
	tilt_rot = (p.tilt_pitch_deg, 0.0, p.tilt_roll_deg)
	return [
		Key(0.0),
		Key(p.anticip_end, pos=(0.0, p.anticip_lift_m, 0.0), rot=(0.0, 0.0, p.anticip_roll_deg), ease="out"),
		Key(p.tilt_end, pos=p.tilt_shift, rot=tilt_rot, ease="smooth"),
		Key(0.45, pos=_add(p.tilt_shift, (-0.005, -0.005, 0.0)),
			rot=_add(tilt_rot, (1.0, 0.0, -2.0)), ease="smooth"),
		Key(p.mag_below, pos=p.tilt_shift, rot=tilt_rot, ease="smooth"),
		Key(p.mag_in, pos=_add(p.tilt_shift, (0.0, p.jolt_m, 0.0)),
			rot=_add(tilt_rot, (p.jolt_deg, 0.0, p.jolt_deg * 0.5)), ease="out"),
		Key(p.mag_seat + 0.01, pos=p.tilt_shift, rot=tilt_rot, ease="smooth"),
		Key(p.mag_tap, pos=_add(p.tilt_shift, (0.0, 0.006, 0.0)), rot=_add(tilt_rot, (1.5, 0.0, 0.0)), ease="out"),
		Key(p.mag_tap + 0.025, pos=p.tilt_shift, rot=tilt_rot, ease="smooth"),
	], tilt_rot


def _reload_hand_common(p: RifleParams):
	return [
		Key(0.0, ref="Foregrip"),
		Key(p.anticip_end, ref="Foregrip"),
		Key(p.hand_leave, pos=(0.0, -0.03, 0.02), ref="Foregrip", ease="in"),
		Key(p.mag_out, ref="MagGrab", ease="smooth"),
		Key(p.mag_pull_end, pos=p.mag_pull, ref="MagGrab", ease="in"),
		Key(p.mag_clear_at, pos=p.mag_clear, ref="MagGrab", ease="linear"),
		Key(p.offscreen_by, pos=p.offscreen_hand, rot=p.offscreen_rot, ref=REF_HIP, ease="smooth"),
		Key(0.45, pos=_add(p.offscreen_hand, (-0.02, -0.02, 0.0)), rot=p.offscreen_rot, ref=REF_HIP, ease="smooth"),
		Key(p.offscreen_until, pos=p.offscreen_hand, rot=p.offscreen_rot, ref=REF_HIP, ease="smooth"),
		Key(p.mag_below, pos=p.mag_approach, ref="MagGrab", ease="out"),
		Key(p.mag_in - 0.015, pos=_mul(p.mag_approach, 0.12), ref="MagGrab", ease="smooth"),
		Key(p.mag_in, pos=(0.0, p.jolt_m, 0.0), ref="MagGrab", ease="out"),
		Key(p.mag_seat, ref="MagGrab", ease="smooth"),
		Key(p.mag_tap, ref="MagTap", ease="in"),
	]


def _reload_fingers_common(p: RifleParams):
	return [
		FingerKey(0.0, "hand.L", "auto", "Foregrip"),
		FingerKey(p.anticip_end, "hand.L", "auto", "Foregrip"),
		FingerKey(p.mag_out - 0.05, "hand.L", "open"),
		FingerKey(p.mag_out, "hand.L", "auto", "MagGrab"),
		FingerKey(p.mag_seat, "hand.L", "auto", "MagGrab"),
		FingerKey(p.mag_tap - 0.01, "hand.L", "flat"),
	]


def _reload_attach(p: RifleParams):
	return (Attach(p.mag_out, "mag", "hand.L"), Attach(p.mag_seat, "mag", "weapon"))


def reload_clip(p: RifleParams) -> Clip:
	weapon, tilt_rot = _reload_weapon_common(p)
	weapon += [
		Key(p.return_start, pos=_mul(p.tilt_shift, 0.8), rot=_mul(tilt_rot, 0.8), ease="smooth"),
		Key(0.95, pos=(0.0, 0.002, 0.0), rot=(-0.5, 0.0, p.settle_roll_deg), ease="smooth"),
		Key(1.0, ease="smooth"),
	]
	hand_l = _reload_hand_common(p) + [
		Key(p.mag_tap + 0.03, pos=(0.0, -0.05, 0.0), ref="MagTap", ease="out"),
		Key(p.fore_at - 0.05, pos=p.fore_via, ref="Foregrip", ease="smooth"),
		Key(p.fore_at, ref="Foregrip", ease="smooth"),
		Key(1.0, ref="Foregrip"),
	]
	fingers = _reload_fingers_common(p) + [
		FingerKey(p.mag_tap + 0.03, "hand.L", "flat"),
		FingerKey(p.fore_at, "hand.L", "auto", "Foregrip"),
		FingerKey(1.0, "hand.L", "auto", "Foregrip"),
	]
	return Clip("reload", frame_length(p.reload_time), False, {"weapon": tuple(weapon), "hand.L": tuple(hand_l)},
		fingers=_grip_fingers() + tuple(fingers), attach=_reload_attach(p),
		events=(Event(p.mag_out, "mag_out"), Event(p.mag_in, "mag_in"), Event(p.mag_tap, "mag_tap")))


def reload_empty_clip(p: RifleParams) -> Clip:
	"""Comme `reload`, plus la main gauche sur le levier d'armement : tirer
	`charge_pull_m` vers l'arrière, lâcher à `bolt` (événement)."""
	weapon, tilt_rot = _reload_weapon_common(p)
	held = _add(p.tilt_shift, p.charge_hold_shift)
	held_rot = _mul(tilt_rot, 0.9)
	weapon += [
		Key(p.bolt - 0.02, pos=held, rot=held_rot, ease="smooth"),
		Key(p.bolt, pos=_add(held, (0.0, 0.006, 0.004)), rot=_add(held_rot, (2.0, 0.0, 1.0)), ease="out"),
		Key(p.bolt + 0.03, pos=_mul(p.tilt_shift, 0.7), rot=_mul(tilt_rot, 0.7), ease="smooth"),
		Key(0.97, pos=(0.0, 0.002, 0.0), rot=(-0.5, 0.0, p.settle_roll_deg), ease="smooth"),
		Key(1.0, ease="smooth"),
	]
	hand_l = _reload_hand_common(p) + [
		Key(p.mag_tap + 0.015, pos=(0.0, -0.04, 0.0), ref="MagTap", ease="out"),
		Key(p.charge_at - 0.015, pos=p.charge_via, ref="Charge", ease="smooth"),
		Key(p.charge_at, ref="Charge", ease="smooth"),
		Key(p.charge_pulled, pos=(-0.006, 0.0, p.charge_pull_m), ref="Charge", ease="in"),
		Key(p.bolt + 0.005, pos=(-0.025, 0.012, p.charge_pull_m + 0.01), ref="Charge", ease="out"),
		Key(p.empty_fore_at - 0.04, pos=(-0.07, -0.06, 0.0), ref="Foregrip", ease="smooth"),
		Key(p.empty_fore_at, ref="Foregrip", ease="smooth"),
		Key(1.0, ref="Foregrip"),
	]
	fingers = _reload_fingers_common(p) + [
		FingerKey(p.mag_tap + 0.015, "hand.L", "open"),
		FingerKey(p.charge_at - 0.012, "hand.L", "open"),
		FingerKey(p.charge_at, "hand.L", "auto", "Charge"),
		FingerKey(p.charge_pulled, "hand.L", "auto", "Charge"),
		FingerKey(p.bolt + 0.01, "hand.L", "open"),
		FingerKey(p.empty_fore_at, "hand.L", "auto", "Foregrip"),
		FingerKey(1.0, "hand.L", "auto", "Foregrip"),
	]
	return Clip("reload_empty", frame_length(p.reload_time), False,
		{"weapon": tuple(weapon), "hand.L": tuple(hand_l)},
		fingers=_grip_fingers() + tuple(fingers), attach=_reload_attach(p),
		events=(Event(p.mag_out, "mag_out"), Event(p.mag_in, "mag_in"), Event(p.mag_tap, "mag_tap"),
			Event(p.bolt, "bolt")))


def inspect_clip(p: RifleParams) -> Clip:
	"""Lacet +35° (flanc gauche), puis roulis pour présenter le flanc droit
	(le §3.5 écrit « −40° » : dans la convention de common.py, c'est +40°
	-- dessus vers la gauche -- qui tourne le flanc droit vers la caméra ; on
	garde l'intention). La main gauche touche le chargeur à 0,5."""
	yaw, roll = p.inspect_yaw_deg, p.inspect_roll_deg
	weapon = (
		Key(0.0),
		Key(0.06, pos=(0.005, 0.0, 0.0), rot=(-2.0, -4.0, 3.0), ease="out"),
		Key(0.22, pos=(-0.07, 0.04, 0.05), rot=(6.0, yaw, 8.0), ease="smooth"),
		Key(0.40, pos=(-0.065, 0.035, 0.05), rot=(4.0, yaw - 4.0, 6.0), ease="smooth"),
		Key(0.50, pos=(-0.06, 0.03, 0.05), rot=(4.0, yaw - 7.0, 5.0), ease="smooth"),
		Key(0.66, pos=(-0.03, 0.03, 0.03), rot=(4.0, 0.0, roll), ease="smooth"),
		Key(0.82, pos=(-0.03, 0.03, 0.03), rot=(3.0, -3.0, roll - 4.0), ease="smooth"),
		Key(0.94, rot=(-0.5, 0.0, -roll * 0.1), ease="smooth"),
		Key(1.0, ease="smooth"),
	)
	hand_l = (
		Key(0.0, ref="Foregrip"),
		Key(0.36, ref="Foregrip"),
		Key(0.41, pos=(-0.05, -0.05, 0.0), ref="Foregrip", ease="smooth"),
		Key(0.46, ref="MagTouch", ease="smooth"),
		Key(0.54, pos=(0.0, -0.01, 0.0), ref="MagTouch", ease="smooth"),
		Key(0.58, pos=(-0.05, -0.05, 0.0), ref="Foregrip", ease="smooth"),
		Key(0.62, ref="Foregrip", ease="smooth"),
		Key(1.0, ref="Foregrip"),
	)
	fingers = (
		FingerKey(0.0, "hand.L", "auto", "Foregrip"),
		FingerKey(0.36, "hand.L", "auto", "Foregrip"),
		FingerKey(0.44, "hand.L", "flat"),
		FingerKey(0.56, "hand.L", "flat"),
		FingerKey(0.62, "hand.L", "auto", "Foregrip"),
		FingerKey(1.0, "hand.L", "auto", "Foregrip"),
	)
	return Clip("inspect", frame_length(p.inspect_time), False, {"weapon": weapon, "hand.L": hand_l},
		fingers=_grip_fingers() + fingers, events=(Event(p.inspect_touch, "inspect_touch"),))


def build_clips(p: RifleParams) -> tuple:
	"""Les 7 clips du contrat, dans l'ordre de common.CLIP_NAMES."""
	return (idle_clip(p), run_clip(p), fire_clip(p), draw_clip(p), reload_clip(p), reload_empty_clip(p),
		inspect_clip(p))


def validate_family(clips) -> list:
	"""Fenêtres d'événements du critère d'acceptation (propres à la famille)."""
	errors = []
	by_name = {c.name: c for c in clips}
	for clip_name, windows in EVENT_WINDOWS.items():
		clip = by_name.get(clip_name)
		if clip is None:
			errors.append(f"rifle : clip {clip_name!r} absent")
			continue
		for ev_name, (lo, hi) in windows.items():
			t = clip.event_t(ev_name)
			if t is None:
				errors.append(f"rifle : {clip_name}.{ev_name} absent")
			elif not lo <= t <= hi:
				errors.append(f"rifle : {clip_name}.{ev_name} = {t} hors de [{lo} ; {hi}]")
	return errors


def family_metrics(clips, p: RifleParams) -> dict:
	"""Principes du §3.5 mesurés sur les courbes du DSL : anticipation (s),
	dépassement (fraction de l'amplitude), image du pic de tir."""
	by_name = {c.name: c for c in clips}
	out = {}
	for name in ("reload", "reload_empty"):
		clip = by_name[name]
		out[f"{name}.anticipation_s"] = anticipation_seconds(channel_series(clip, "weapon", "rot.z"))
		series = channel_series(clip, "hand.L", "pos.y")
		out[f"{name}.mag_in_overshoot"] = overshoot_ratio(series, frame_of(clip, p.mag_below), frame_of(clip, p.mag_seat))
	inspect = by_name["inspect"]
	out["inspect.anticipation_s"] = anticipation_seconds(channel_series(inspect, "weapon", "rot.y"))
	draw = by_name["draw"]
	roll = channel_series(draw, "weapon", "rot.z")
	out["draw.overshoot"] = overshoot_ratio(roll, 0, len(roll) - 1)
	fire = by_name["fire"]
	out["fire.peak_frame"] = peak_frame(channel_series(fire, "weapon", "pos.z"))
	return out


METRIC_THRESHOLDS = {
	"reload.anticipation_s": (">=", 0.06),
	"reload_empty.anticipation_s": (">=", 0.06),
	"inspect.anticipation_s": (">=", 0.06),
	"draw.overshoot": (">=", 0.10),
	"reload.mag_in_overshoot": (">=", 0.10),
	"reload_empty.mag_in_overshoot": (">=", 0.10),
	"fire.peak_frame": ("<=", 2),
}
