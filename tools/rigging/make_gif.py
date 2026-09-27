"""Assemble les images de tools/rigging/revolver_gif.gd en GIF (une séquence par fichier + un
GIF qui les enchaîne). Palette adaptative, 30 i/s.

    python tools/rigging/make_gif.py [dossier]
"""
import glob
import os
import sys

from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
DIR = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "reports", "checkpoints", "2026-09-27_revolver", "gif")
FRAME_MS = 33
WIDTH = 480


def load(seq):
    frames = []
    for path in sorted(glob.glob(os.path.join(DIR, f"{seq}_*.png"))):
        im = Image.open(path).convert("RGB")
        im = im.resize((WIDTH, round(im.height * WIDTH / im.width)), Image.LANCZOS)
        frames.append(im.convert("P", palette=Image.ADAPTIVE, colors=128))
    return frames


def save(frames, name):
    if not frames:
        print("GIF vide", name)
        return
    out = os.path.join(DIR, name)
    frames[0].save(out, save_all=True, append_images=frames[1:], duration=FRAME_MS, loop=0, optimize=True)
    print("GIF", out, len(frames), "images", round(os.path.getsize(out) / 1e6, 2), "Mo")


allf = []
for seq in ("reload", "inspect", "fan"):
    f = load(seq)
    save(f, f"revolver_{seq}.gif")
    allf += f
save(allf, "revolver_all.gif")
