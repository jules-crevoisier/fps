"""Planches annotées de la pellicule produite par fp_filmstrip.gd (6 colonnes, n° de frame)."""
import sys
from pathlib import Path

from PIL import Image, ImageDraw

d = Path(sys.argv[1] if len(sys.argv) > 1 else "reports/checkpoints/fp_filmstrip")
frames = sorted(d.glob("f_*.png"))
cols, rows = 6, 5
per = cols * rows
for s in range(0, len(frames), per):
    chunk = frames[s:s + per]
    w, h = Image.open(chunk[0]).size
    sheet = Image.new("RGB", (w * cols, h * rows), (20, 20, 20))
    for i, f in enumerate(chunk):
        im = Image.open(f).convert("RGB")
        ImageDraw.Draw(im).text((4, 4), f.stem[2:], fill=(255, 255, 0))
        sheet.paste(im, ((i % cols) * w, (i // cols) * h))
    out = d / f"sheet_{s // per:02d}.png"
    sheet.save(out)
    print(out)
