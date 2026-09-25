"""Assemble les images de tools/review/anim_reel.gd en GIF animés (30 i/s),
un GIF par clip (« idle », « walk », « jog_fwd », « sprint », « pistol_shoot »,
« roll », « equipe »), et contrôle que chaque clip qui boucle en jeu boucle
aussi proprement dans son GIF.

    python tools/review/anim_gif.py <dossier des images> [--width 960]

Écrit :
  - <dossier>/<tag>_animations.gif pour chaque préfixe d'image (<tag>_NNN.png)
  - <dossier>/summary.md, qui liste chaque clip contrôlé et les LOOP_FAIL

Le contrôle de boucle compare l'image 0 d'un clip à son image de contrôle
« <tag>_wrap.png » (produite par anim_reel.gd pour les seuls clips qui
bouclent en jeu : Idle, Walk, Jog_Fwd, Sprint, equipe) : si trop de pixels
diffèrent entre les deux, le raccord « saute » à l'œil et le clip est marqué
LOOP_FAIL. Un clip unique (Pistol_Shoot, Roll : n'a pas vocation à boucler en
jeu) n'a pas d'image « _wrap » et n'est donc jamais contrôlé.
"""
import argparse
import re
from collections import defaultdict
from pathlib import Path

from PIL import Image, ImageChops

# Écart de canal (0-255) au-delà duquel un pixel compte comme « différent »
# entre deux images — tolère le bruit de rendu (grain peint, anticrénelage)
# sans jamais masquer un vrai saut de pose.
LOOP_DIFF_CHANNEL_THRESHOLD = 24
# En dessous de ce plancher absolu (% de l'image), le raccord est toujours
# jugé propre, quel que soit le ratio ci-dessous (protège d'une division par
# un bruit de pas d'image quasi nul).
LOOP_ABS_FLOOR_PCT = 0.5
# Le nombre de personnages dans la rangée et la vitesse du clip changent
# l'écart BRUT en pixels (plus de personnages en mouvement = plus de pixels
# qui changent à chaque image), donc un seuil en % fixe de l'image n'est pas
# comparable d'un clip ou d'un effectif à l'autre. On compare à la place
# l'écart 0/N+1 au bruit de mouvement NORMAL du même clip, dans la même
# scène : l'écart entre l'image 0 et l'image 1 (un pas d'image ordinaire).
# Mesuré (verrou seul, puis les 6 agents, D3D12) : un raccord propre est à
# 0,00–0,74x ce bruit ; une pose à mi-cycle (mise en défaut volontaire, pour
# calibrer une VRAIE rupture) est à 1,55–7,32x. Le seuil se place entre les
# deux avec de la marge des deux côtés.
LOOP_STEP_RATIO_MAX = 1.5


def _loop_diff_pct(image_a: Path, image_b: Path) -> float:
	"""Part (%) de pixels dont le canal le plus écarté dépasse le seuil."""
	im0 = Image.open(image_a).convert("RGB")
	im1 = Image.open(image_b).convert("RGB")
	if im0.size != im1.size:
		return 100.0
	diff = ImageChops.difference(im0, im1)
	r, g, b = diff.split()
	worst = ImageChops.lighter(ImageChops.lighter(r, g), b)
	hist = worst.point(lambda p: 255 if p > LOOP_DIFF_CHANNEL_THRESHOLD else 0).histogram()
	differing = hist[255]
	total = im0.width * im0.height
	return 100.0 * differing / total


def _check_loops(root: Path, tags: list[str]) -> list[dict]:
	"""Contrôle 0/N+1 pour chaque tag qui a une image `<tag>_wrap.png`."""
	checks: list[dict] = []
	for tag in tags:
		wrap = root / f"{tag}_wrap.png"
		frame0 = root / f"{tag}_000.png"
		frame1 = root / f"{tag}_001.png"
		if not wrap.is_file() or not frame0.is_file():
			continue
		wrap_pct = _loop_diff_pct(frame0, wrap)
		step_pct = _loop_diff_pct(frame0, frame1) if frame1.is_file() else None
		if wrap_pct <= LOOP_ABS_FLOOR_PCT:
			ok = True
		elif step_pct is not None:
			ok = wrap_pct <= step_pct * LOOP_STEP_RATIO_MAX
		else:
			ok = False  # au-delà du plancher et aucun repère de bruit normal : prudence
		checks.append({"tag": tag, "pct": wrap_pct, "step_pct": step_pct, "ok": ok})
		status = "LOOP_OK" if ok else "LOOP_FAIL"
		repere = f"pas_normal={step_pct:.2f}%" if step_pct is not None else "pas_normal=n/a"
		print(f"{status} {tag} diff={wrap_pct:.2f}% {repere}")
	return checks


def _ratio_text(check: dict) -> str:
	if check["step_pct"] is None or check["step_pct"] <= 0.0:
		return "n/a"
	return f"{check['pct'] / check['step_pct']:.2f}x"


def _write_summary(root: Path, results: list[dict], checks: list[dict]) -> None:
	by_tag = {c["tag"]: c for c in checks}
	lines = ["# Reel d'animations — revue des boucles", ""]
	lines.append("| Clip | Images | GIF | Boucle |")
	lines.append("|---|---|---|---|")
	for r in results:
		tag = r["tag"]
		check = by_tag.get(tag)
		if check is None:
			boucle = "non contrôlé (clip unique)"
		elif check["ok"]:
			boucle = f"OK ({check['pct']:.2f}%, {_ratio_text(check)} du pas normal)"
		else:
			boucle = f"LOOP_FAIL ({check['pct']:.2f}%, {_ratio_text(check)} du pas normal)"
		lines.append(f"| {tag} | {r['frames']} | {r['gif'].name} | {boucle} |")
	lines.append("")
	failed = [c for c in checks if not c["ok"]]
	lines.append("## LOOP_FAIL")
	if failed:
		for c in failed:
			lines.append(
				f"- {c['tag']} : écart {c['pct']:.2f}% entre l'image 0 et l'image N+1, "
				f"{_ratio_text(c)} le pas normal (seuil {LOOP_STEP_RATIO_MAX:.1f}x, "
				f"plancher {LOOP_ABS_FLOOR_PCT:.1f}%)"
			)
	else:
		lines.append("Aucun : tous les clips contrôlés bouclent sous le seuil.")
	(root / "summary.md").write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> None:
	ap = argparse.ArgumentParser()
	ap.add_argument("frames_dir")
	ap.add_argument("--width", type=int, default=960)
	args = ap.parse_args()
	root = Path(args.frames_dir)
	groups: dict[str, list[Path]] = defaultdict(list)
	for p in sorted(root.glob("*_[0-9][0-9][0-9].png")):
		groups[re.sub(r"_\d{3}$", "", p.stem)].append(p)
	results: list[dict] = []
	for tag, files in groups.items():
		frames = []
		for f in files:
			im = Image.open(f).convert("RGB")
			w, h = im.size
			im = im.crop((0, int(h * 0.07), w, int(h * 0.965)))
			im = im.resize((args.width, round(im.height * args.width / w)), Image.LANCZOS)
			frames.append(im.quantize(colors=160, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE))
		out = root / f"{tag}_animations.gif"
		frames[0].save(out, save_all=True, append_images=frames[1:], duration=33, loop=0, optimize=True, disposal=2)
		print(f"ANIM_GIF {out} frames={len(frames)}")
		results.append({"tag": tag, "frames": len(frames), "gif": out})
	checks = _check_loops(root, sorted(groups.keys()))
	if results:
		_write_summary(root, results, checks)


if __name__ == "__main__":
	main()
