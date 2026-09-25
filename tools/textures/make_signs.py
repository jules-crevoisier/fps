"""tools/textures/make_signs.py -- ART-92

Enseignes peintes de Wasteland v4 (docs/art/WASTELAND_V4_ART_PLAN.md SS5 :
« Chaque panneau est peint en PIL : planches peintes, police Bangers-
Regular.ttf, encre et usure, regroupes dans un atlas de 12 panneaux (0 cr) »)
-- pur PIL/numpy, seeds fixes (reproductible bit a bit d'un lancement a
l'autre), 0 cr Tripo. Chaque panneau est une planche de bois peinte
(grain procedural + joints), le nom du batiment en grandes lettres
(police Bangers, l'unique police "titraille" du depot -- resources/fonts/
Bangers-Regular.ttf), une bordure d'encre epaisse et une usure (eclats de
peinture, salissures basses) -- meme esprit que les decalques peints de
tools/textures/gen_textures.py (creases/wavy_lines pour l'usure), jamais
importe directement d'ici : ce fichier est independant, comme
tools/textures/make_tileable.py l'est deja de gen_textures.py (chacun sa
petite duplication documentee plutot qu'une dependance croisee entre
generateurs paralleles).

Liste des 12 panneaux (SS5) : FORGE, MARECHAL, HOTEL, BANQUE, MAGASIN,
EPICERIE, ECHOPPES, BAZAR, SALOON (bleu, ouest) et SALOON (rouge, est),
POSTE, FUEL, GAS. Teinte par quartier (SS2 R8 / SS8) : ouest froid (tole
bleue #3E7BB5), est chaud (rouge #B8322A), centre neutre (creme et rouille).
Teintes 300-355 deg et 105-145 deg RESERVEES (surbrillance ennemie,
docs/STYLE_BIBLE.md) : jamais dans le decor, verifie pixel a pixel en fin de
generation (`check_reserved_hue`) -- echec DUR, pas un avertissement, si un
pixel du panneau (hors zone de texte, ou l'encre est neutre) y tombe.

Sortie :
    assets/textures/wasteland/signs/atlas.png   (4 colonnes x 3 rangees, un
                                                  panneau par cellule)
    assets/textures/wasteland/signs/atlas.png.import  (sidecar Godot)
    assets/textures/wasteland/signs/manifest.json     (rect pixel + team par
                                                         enseigne, cle = id)

Usage :
    python tools/textures/make_signs.py
"""
from __future__ import annotations

import json
import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

REPO_ROOT = Path(__file__).resolve().parents[2]
OUT_DIR = REPO_ROOT / "assets" / "textures" / "wasteland" / "signs"
FONT_PATH = REPO_ROOT / "resources" / "fonts" / "Bangers-Regular.ttf"

PANEL_W = 512
PANEL_H = 256

# --------------------------------------------------------------------------- palette (SS8, meme repli que toonkit._FALLBACK_PALETTE -- docs/style/tokens.json prioritaire s'il existe)

_FALLBACK_COLORS = {
    "wood_planks": "#735230",
    "wood_planks_dark": "#4a3520",
    "ink": "#1a1410",
    "paper": "#e6e1d6",
    "rust": "#6b3821",
    "west_blue": "#3E7BB5",
    "east_red": "#B8322A",
    "neutral_cream": "#DCC9A0",
}

_tokens_cache = None


def _load_tokens() -> dict:
    global _tokens_cache
    if _tokens_cache is not None:
        return _tokens_cache
    path = REPO_ROOT / "docs" / "style" / "tokens.json"
    if not path.is_file():
        _tokens_cache = {}
        return _tokens_cache
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        _tokens_cache = data.get("colors", data) if isinstance(data, dict) else {}
    except (OSError, ValueError):
        _tokens_cache = {}
    return _tokens_cache


def palette(name: str) -> str:
    tokens = _load_tokens()
    if name in tokens and isinstance(tokens[name], str):
        return tokens[name]
    return _FALLBACK_COLORS[name]


def _hex_rgb(h: str) -> tuple:
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


# --------------------------------------------------------------------------- teintes reservees (docs/STYLE_BIBLE.md : 300-355 et 105-145 interdites)

RESERVED_HUE_RANGES = ((300.0, 355.0), (105.0, 145.0))


def _rgb_to_hue_deg(arr01: np.ndarray) -> np.ndarray:
    """`arr01` (..., 3) RGB 0..1 -> teinte HSV en degres [0, 360). Un pixel
    quasi gris (S proche de 0, chroma << 1) a une teinte non significative :
    exclu du calcul par l'appelant (`check_reserved_hue`) via son masque de
    saturation, pas ici (cette fonction reste une conversion pure)."""
    r, g, b = arr01[..., 0], arr01[..., 1], arr01[..., 2]
    cmax = np.max(arr01, axis=-1)
    cmin = np.min(arr01, axis=-1)
    delta = cmax - cmin
    hue = np.zeros_like(cmax)
    safe = delta > 1e-6
    r_is_max = safe & (cmax == r)
    g_is_max = safe & (cmax == g) & ~r_is_max
    b_is_max = safe & (cmax == b) & ~r_is_max & ~g_is_max
    hue = np.where(r_is_max, ((g - b) / np.where(delta == 0, 1, delta)) % 6.0, hue)
    hue = np.where(g_is_max, ((b - r) / np.where(delta == 0, 1, delta)) + 2.0, hue)
    hue = np.where(b_is_max, ((r - g) / np.where(delta == 0, 1, delta)) + 4.0, hue)
    return (hue * 60.0) % 360.0


def check_reserved_hue(img: Image.Image, saturation_floor: float = 0.18, value_floor: float = 0.15) -> tuple:
    """PASS/FAIL + detail -- 0 pixel SATURE ET VISIBLE (au-dessus de
    `saturation_floor` ET `value_floor`) ne doit tomber dans une bande de
    teinte reservee. `value_floor` ecarte les pixels quasi NOIRS (encre,
    ombre portee) : la saturation HSV est instable pres du noir -- un bruit
    de +/-1 niveau de 8 bits entre canaux y donne une "saturation" elevee
    sans le moindre rapport avec une couleur visible (sonde : un pixel
    d'ombre (0.10, 0.078, 0.082) ressort a une teinte de 350 deg, dans la
    bande reservee, tout en etant PERCEPTUELLEMENT NOIR) -- ecarte ici, pas
    du fait d'une tolerance de gameplay, mais parce que ce n'est pas une
    couleur au sens ou R8 l'entend. Echec DUR sinon (jamais un
    avertissement) : c'est un critere de gameplay (surbrillance ennemie),
    pas une preference esthetique."""
    arr = np.asarray(img.convert("RGB")).astype(np.float64) / 255.0
    cmax = arr.max(axis=-1)
    cmin = arr.min(axis=-1)
    sat = np.where(cmax > 1e-6, (cmax - cmin) / np.where(cmax == 0, 1, cmax), 0.0)
    hue = _rgb_to_hue_deg(arr)
    mask = (sat >= saturation_floor) & (cmax >= value_floor)
    bad = np.zeros_like(mask)
    for lo, hi in RESERVED_HUE_RANGES:
        bad |= mask & (hue >= lo) & (hue <= hi)
    n_bad = int(bad.sum())
    ok = n_bad == 0
    return ok, f"{'PASS' if ok else 'FAIL'}  {n_bad} pixel(s) sature(s) en teinte reservee (300-355/105-145 deg)"


# --------------------------------------------------------------------------- bruit deterministe (meme technique que gen_textures.py : blur gaussien FFT, seams-safe -- ici pas besoin de raccord, juste d'un grain reproductible)

def _value_noise(h: int, w: int, seed: int, sigma: float, amp: float) -> np.ndarray:
    rng = np.random.default_rng(seed)
    white = rng.normal(size=(h, w))
    fy = np.fft.fftfreq(h)
    fx = np.fft.fftfreq(w)
    gy = np.exp(-2.0 * (np.pi ** 2) * (sigma ** 2) * (fy ** 2))
    gx = np.exp(-2.0 * (np.pi ** 2) * (sigma ** 2) * (fx ** 2))
    kernel = np.outer(gy, gx)
    blurred = np.real(np.fft.ifft2(np.fft.fft2(white) * kernel))
    std = blurred.std()
    if std > 1e-9:
        blurred = blurred / std
    return blurred * amp


# --------------------------------------------------------------------------- panneau

def _wood_background(seed: int, base_hex: str) -> Image.Image:
    """Planches peintes horizontales (grain + joints sombres), meme esprit
    que `plank_wall_parts` de make_wl_shanty_kit.py mais en 2D peint : bandes
    horizontales legerement teintees plus un grain vertical fin."""
    base = np.array(_hex_rgb(base_hex), dtype=np.float64) / 255.0
    img = np.ones((PANEL_H, PANEL_W, 3)) * base
    grain = _value_noise(PANEL_H, PANEL_W, seed, sigma=max(PANEL_H, PANEL_W) * 0.01, amp=0.05)
    blotch = _value_noise(PANEL_H, PANEL_W, seed + 1, sigma=max(PANEL_H, PANEL_W) * 0.12, amp=0.06)
    img += grain[..., None] + blotch[..., None]
    plank_h = PANEL_H / 4.0
    n_planks = 4
    for i in range(1, n_planks):
        y0 = int(i * plank_h) - 2
        y1 = int(i * plank_h) + 2
        img[max(y0, 0):min(y1, PANEL_H), :, :] *= 0.55
    img = np.clip(img, 0.03, 0.97)
    return Image.fromarray((img * 255).astype(np.uint8), mode="RGB")


def _apply_wear(img: Image.Image, seed: int) -> Image.Image:
    """Usure basse (eclats/salissures pres du bas du panneau, comme un
    panneau expose aux intemperies) -- assombrit localement sans jamais
    passer sous L ~0,08 (reste lisible)."""
    arr = np.asarray(img.convert("RGB")).astype(np.float64) / 255.0
    h, w, _ = arr.shape
    dirt = _value_noise(h, w, seed + 7, sigma=max(h, w) * 0.05, amp=1.0)
    dirt = (dirt - dirt.min()) / max(dirt.max() - dirt.min(), 1e-6)
    y_ramp = np.linspace(0.15, 0.65, h)[:, None]  # plus marque en bas
    wear_mask = np.clip(dirt * y_ramp - 0.25, 0.0, 1.0)
    arr *= (1.0 - 0.5 * wear_mask[..., None])
    return Image.fromarray((np.clip(arr, 0.0, 1.0) * 255).astype(np.uint8), mode="RGB")


def _fit_font_size(draw: ImageDraw.ImageDraw, text: str, max_w: int, max_h: int) -> ImageFont.FreeTypeFont:
    size = max_h
    while size > 8:
        font = ImageFont.truetype(str(FONT_PATH), size)
        box = draw.textbbox((0, 0), text, font=font)
        if (box[2] - box[0]) <= max_w and (box[3] - box[1]) <= max_h:
            return font
        size -= 2
    return ImageFont.truetype(str(FONT_PATH), 8)


def paint_panel(panel_id: str, text: str, team: str, seed: int) -> Image.Image:
    """Un panneau peint complet : fond planches, bordure d'encre epaisse,
    texte centre (police Bangers) dans la teinte d'equipe, usure. `team` :
    "west" (froid, tole bleue), "east" (chaud, rouge), "neutral" (creme et
    rouille) -- SS2 R8 / SS8."""
    img = _wood_background(seed, palette("wood_planks"))

    ink = _hex_rgb(palette("ink"))
    draw = ImageDraw.Draw(img)
    border = 10
    draw.rectangle(
        [border, border, PANEL_W - border, PANEL_H - border],
        outline=ink, width=6)
    draw.rectangle(
        [border + 12, border + 12, PANEL_W - border - 12, PANEL_H - border - 12],
        outline=ink, width=2)

    text_color = {
        "west": _hex_rgb(palette("west_blue")),
        "east": _hex_rgb(palette("east_red")),
        "neutral": _hex_rgb(palette("neutral_cream")),
    }[team]
    max_w, max_h = PANEL_W - border * 4, PANEL_H - border * 4
    font = _fit_font_size(draw, text, max_w, max_h)
    box = draw.textbbox((0, 0), text, font=font)
    tx = (PANEL_W - (box[2] - box[0])) / 2.0 - box[0]
    ty = (PANEL_H - (box[3] - box[1])) / 2.0 - box[1]
    # Ombre portee (encre) puis lettrage peint -- lisibilite sur le grain de bois.
    shadow_offset = max(2, PANEL_H // 64)
    draw.text((tx + shadow_offset, ty + shadow_offset), text, font=font, fill=ink)
    draw.text((tx, ty), text, font=font, fill=text_color, stroke_width=2, stroke_fill=ink)

    img = _apply_wear(img, seed)
    img = img.filter(ImageFilter.GaussianBlur(radius=0.4))  # adoucit l'aliasing du texte peint
    return img


# --------------------------------------------------------------------------- liste des 12 enseignes (SS5)


# SS5 dit "un atlas de 12 panneaux" mais sa propre liste en enumere 13 (FUEL
# ET GAS comptent double : FORGE, MARECHAL, HOTEL, BANQUE, MAGASIN,
# EPICERIE, ECHOPPES, BAZAR, SALOON x2, POSTE, FUEL, GAS = 13). FUEL/GAS
# sont le zonage ouest-froid/est-chaud repete dans TOUT le document (SS2 R8,
# SS8, la table des reperes) -- en retirer un casserait cette symetrie
# centrale plutot que de corriger un simple decompte. Ecart signale au lead
# (rendu de tache) plutot que "corrige" en silence en supprimant une
# enseigne du plan.
SIGN_PANELS = [
    ("forge", "FORGE", "west"),
    ("marechal", "MARÉCHAL", "east"),
    ("hotel", "HÔTEL", "west"),
    ("banque", "BANQUE", "east"),
    ("magasin", "MAGASIN", "west"),
    ("epicerie", "ÉPICERIE", "east"),
    ("echoppes", "ÉCHOPPES", "west"),
    ("bazar", "BAZAR", "east"),
    ("saloon_bleu", "SALOON", "west"),
    ("saloon_rouge", "SALOON", "east"),
    ("poste", "POSTE", "neutral"),
    ("fuel", "FUEL", "west"),
    ("gas", "GAS", "east"),
]

COLS = math.ceil(math.sqrt(len(SIGN_PANELS)))
ROWS = math.ceil(len(SIGN_PANELS) / COLS)


# --------------------------------------------------------------------------- import Godot (meme gabarit que gen_textures.py::write_import)

IMPORT_TEMPLATE = """[remap]

importer="texture"
type="CompressedTexture2D"
uid="uid://{uid_stub}"
path="res://.godot/imported/{stem}.png-{fake_md5}.ctex"
metadata={{
"vram_texture": false
}}

[deps]

source_file="res://{res_path}"
dest_files=["res://.godot/imported/{stem}.png-{fake_md5}.ctex"]

[params]

compress/mode=0
compress/high_quality=false
compress/lossy_quality=0.7
compress/uastc_level=0
compress/rdo_quality_loss=0.0
compress/hdr_compression=1
compress/normal_map=0
compress/channel_pack=0
mipmaps/generate=true
mipmaps/limit=-1
roughness/mode=0
roughness/src_normal=""
process/channel_remap/red=0
process/channel_remap/green=1
process/channel_remap/blue=2
process/channel_remap/alpha=3
process/fix_alpha_border=true
process/premult_alpha=false
process/normal_map_invert_y=false
process/hdr_as_srgb=false
process/hdr_clamp_exposure=false
process/size_limit=0
detect_3d/compress_to=0
"""


def write_import(png_path: Path) -> None:
    """Sidecar `.import` ecrit a la main (pas d'editeur Godot ici) --
    mipmaps generes, compression sans perte, `uid` absent (Godot lui en
    attribue un au prochain `--import`), meme convention que
    `tools/textures/gen_textures.py::write_import` (dupliquee, pas
    importee -- voir l'en-tete de ce fichier)."""
    res_path = png_path.relative_to(REPO_ROOT).as_posix()
    stem = png_path.stem
    fake_md5 = "0" * 32
    uid_stub = format(abs(hash(res_path)) % (36 ** 13), "013x")
    content = IMPORT_TEMPLATE.format(res_path=res_path, stem=stem, fake_md5=fake_md5, uid_stub=uid_stub)
    png_path.with_suffix(png_path.suffix + ".import").write_text(content, encoding="utf-8", newline="\n")


# --------------------------------------------------------------------------- assemblage atlas + manifeste

def build_atlas() -> dict:
    """Peint les 12 panneaux, les assemble en atlas (grille COLS x ROWS),
    ecrit `atlas.png` (+ `.import`) et `manifest.json` ({id: {rect_px, team,
    text}}). Verifie SS8/STYLE_BIBLE (teintes reservees) sur l'atlas ENTIER
    avant d'ecrire quoi que ce soit -- echec dur, rien n'est ecrit."""
    atlas = Image.new("RGB", (PANEL_W * COLS, PANEL_H * ROWS), _hex_rgb(palette("wood_planks_dark")))
    manifest = {"panel_w": PANEL_W, "panel_h": PANEL_H, "cols": COLS, "rows": ROWS, "panels": {}}
    for i, (panel_id, text, team) in enumerate(SIGN_PANELS):
        col, row = i % COLS, i // COLS
        seed = 1000 + i
        panel_img = paint_panel(panel_id, text, team, seed)
        x0, y0 = col * PANEL_W, row * PANEL_H
        atlas.paste(panel_img, (x0, y0))
        manifest["panels"][panel_id] = {
            "text": text, "team": team,
            "rect_px": [x0, y0, PANEL_W, PANEL_H],
            "uv_rect": [x0 / atlas.width, y0 / atlas.height, PANEL_W / atlas.width, PANEL_H / atlas.height],
        }

    ok, detail = check_reserved_hue(atlas)
    if not ok:
        raise RuntimeError(f"make_signs: teinte reservee detectee dans l'atlas -- {detail}")

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    atlas_path = OUT_DIR / "atlas.png"
    atlas.save(atlas_path)
    write_import(atlas_path)
    manifest_path = OUT_DIR / "manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2, ensure_ascii=False), encoding="utf-8")

    print(f"MAKE_SIGNS_OK {len(SIGN_PANELS)} panneau(x) -> {atlas_path} ({detail})")
    return {"atlas_path": str(atlas_path), "manifest_path": str(manifest_path),
        "manifest": manifest, "reserved_hue_check": detail, "ok": True}


def main() -> None:
    build_atlas()


if __name__ == "__main__":
    main()
