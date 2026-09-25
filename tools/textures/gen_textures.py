"""gen_textures.py -- v3

Procedural "hand-painted, ink-free" texture generator for the FPS's v3 look
(docs/STYLE_BIBLE.md SS7.8): pure numpy/scipy/Pillow, fixed seeds
(byte-for-byte reproducible across runs), fully TILEABLE for the terrain and
trim families (world-space triplanar sampling in
assets/shaders/ink_toon.gdshader needs surfaces that repeat with no visible
seam).

v3 changes the METHOD (STYLE_BIBLE SS "Ce qui change", the "encre vient de la
geometrie, le detail vient des decalques" thesis):

1. No more ink baked into an albedo: `creases()` and `wavy_lines()` are never
   called by a terrain or trim-sheet builder any more (CHK-08, "Albedos sans
   encre"). Both functions remain -- they now generate CRACK DECALS only
   (`build_crack_branch`/`build_crack_wavy`), the one place SS7.8 keeps them.
2. Value variation stays small (terrain <= ~+/-3.5%, trim corrugated bands
   <= +/-6%, `base_sigma` >= 200 px), so every terrain/trim pixel keeps a
   comfortable margin above the CHK-08 floor (L >= 0.25) and the whole
   file's post-blur L standard deviation stays <= 0.04.
3. Three tileable families, plus one flat-shaded fourth:
   - assets/textures/painted/ : 7 terrains, 1024x1024 (sable, pont, paves,
     neige, calcaire, terre_battue, quai -- SS7.8 point 3).
   - assets/textures/trim/    : 4 trim-sheets, 1024x1024, one per theme
     (desert, port_cargo, ville, alpin), each five horizontal bands (light
     border, planks, corrugated metal, rivets, stencil-dash).
   - assets/textures/decals/  : one 2048x2048 RGBA decal atlas (FUEL/GAS/
     FRAGILE/GRAINES stencils, digit stencils, arrows, show stickers, impact
     stars, burns, cracks, tactical site letters A/B) + a `decal_atlas.json`
     manifest of each decal's pixel rect.
   - assets/textures/painted/ (again) : `PAINTED_MATERIALS`, 11 named prop
     materials (+ 6 grime masks) for `scripts/core/Cartoon.gd`'s existing
     `painted(kind, tint)`/`prop_uv(kind, tint)` kind vocabulary (rust,
     wood_planks, container_paint, ... -- ART-05's `_PAINTED` dict), which 27
     dependents outside this task's file list (ArenaBuilder.gd,
     PropCatalog.gd, manifest.json, ...) still address by these exact names.
     Same v3 method as the terrains (`make_terrain()`, no `creases()`/
     `wavy_lines()`, CHK-08-legal) -- ART-04B (2026-09-24) renamed these from
     their pre-v3 stems (`<name>_albedo.png`) to `material_<name>_albedo.png`
     / `material_<name>_grime.png` once `Cartoon.gd` no longer `preload()`ed
     the old names, so the old 17 files could finally be deleted instead of
     kept as a compat bridge (see `PAINTED_MATERIALS`'s own comment and
     `_remove_stale_v2_outputs()`).

Tileability technique (terrain/trim, unchanged from v2): every noise field
is a sum of octaves of white noise blurred with a GAUSSIAN APPLIED IN THE
FREQUENCY DOMAIN (an FFT multiply is exactly a *circular* convolution) --
because the Fourier transform of a Gaussian is a Gaussian,
`ifft2(fft2(white) * gaussian(freq))` blurs `white` while wrapping perfectly
at the image border, at ANY sigma, for ANY image size.

CHK-08 self-check: this script also re-derives OKLab lightness (the same
Bjoern Ottosson sRGB->OKLab conversion already used by
`tests/agents/test_agent_palette.gd`'s `_oklch()`, since no shared OKLab
utility exists in the repo yet -- ART-03/ART-05 are out of this task's file
list) and, at the end of `main()`, measures CHK-08 (0 px at L < 0.25 except
`rubber*`; post-2px-blur L std <= 0.04) on every generated terrain and
trim-sheet file, printing a PASS/FAIL report. `tools/review/style_check.py`
(ART-03) is the eventual authoritative scorer; this is this script's own
acceptance gate so `python tools/textures/gen_textures.py` alone proves the
task's "CHK-08 PASS sur tous les fichiers" criterion.

Usage:
    python tools/textures/gen_textures.py
"""
from __future__ import annotations

import sys
import json
from pathlib import Path

import numpy as np
from scipy.ndimage import binary_dilation
from PIL import Image

REPO_ROOT = Path(__file__).resolve().parents[2]
OUT_TERRAIN = REPO_ROOT / "assets" / "textures" / "painted"
OUT_TRIM = REPO_ROOT / "assets" / "textures" / "trim"
OUT_DECALS = REPO_ROOT / "assets" / "textures" / "decals"

TERRAIN_SIZE = 1024
TRIM_SIZE = 1024
DECAL_ATLAS_SIZE = 2048
DETAIL_SIZE = 512  # painted-material grime masks only -- see PAINTED_MATERIALS below.

# ART-79B: `tools/textures/make_tileable.py` replaces some of these same
# filenames with a hand-quilted photo (Tripo Studio painted sheets, see
# docs/art/WASTELAND_ART_RESET.md decision 2) UNDER THE SAME NAMES this
# script writes, so `Cartoon.gd`'s `preload()`s keep working unchanged. A
# rerun of THIS script must never silently overwrite -- or, worse, `unlink()`
# via `_remove_stale_v2_outputs()` -- one of those hand-painted files (the
# 2026-09-24 incident this task's contract calls out: "gen_textures.py ... a
# deja efface des textures v2"). `HAND_PAINTED_LIST` is the one shared
# contract between the two scripts: every repo-relative path on its own
# line is a file `make_tileable.py` has produced and this script must leave
# byte-for-byte alone.
HAND_PAINTED_LIST = REPO_ROOT / "assets" / "textures" / "painted" / "HAND_PAINTED.txt"

Shape = tuple[int, int]


def _load_hand_painted_protected() -> set[Path]:
    """Resolved, absolute paths this script must NOT (re)write -- see
    `HAND_PAINTED_LIST` above. Blank lines and '#' comments are ignored. A
    missing list -> empty set: no hand-painted texture has landed yet, so
    this script keeps generating every file exactly as before (a MISSING
    list must never be read as "protect everything", which would silently
    stop regenerating the whole procedural library)."""
    protected: set[Path] = set()
    if not HAND_PAINTED_LIST.exists():
        return protected
    for line in HAND_PAINTED_LIST.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        protected.add((REPO_ROOT / line).resolve())
    return protected


# --------------------------------------------------------------------------- noise core
# (unchanged from v2 -- still the right tool for terrain/trim broad-scale
# variation and for the two crack decals; `creases()`/`wavy_lines()` are no
# longer called by any albedo/trim builder, only by the crack decals below.)

def _rng(seed: int) -> np.random.Generator:
    return np.random.default_rng(seed)


def circular_blur(a: np.ndarray, sigma_y: float, sigma_x: float | None = None) -> np.ndarray:
    """Seamless (wrap-around) Gaussian blur via an FFT-domain multiply.

    `fft2`/`ifft2` treat the array as periodic, so the result tiles exactly
    -- this is what makes every field below safe to sample with `repeat`,
    and it is also what CHK-08's own "flou gaussien de 2 px" measurement
    below reuses.
    """
    if sigma_x is None:
        sigma_x = sigma_y
    h, w = a.shape
    fy = np.fft.fftfreq(h)
    fx = np.fft.fftfreq(w)
    gy = np.exp(-2.0 * (np.pi ** 2) * (max(sigma_y, 1e-3) ** 2) * (fy ** 2))
    gx = np.exp(-2.0 * (np.pi ** 2) * (max(sigma_x, 1e-3) ** 2) * (fx ** 2))
    kernel = np.outer(gy, gx)
    return np.real(np.fft.ifft2(np.fft.fft2(a) * kernel))


def normalize01(a: np.ndarray) -> np.ndarray:
    a = a - a.min()
    m = a.max()
    return a / m if m > 1e-9 else a


def fbm(
    shape: Shape,
    seed: int,
    octaves: int = 5,
    persistence: float = 0.55,
    lacunarity: float = 2.0,
    base_sigma: float = 220.0,
    aniso: tuple[float, float] = (1.0, 1.0),
) -> np.ndarray:
    """Fractal (multi-octave) seamless value noise, normalized to [0, 1]."""
    rng = _rng(seed)
    total = np.zeros(shape)
    amp = 1.0
    amp_sum = 0.0
    sigma = base_sigma
    for _ in range(octaves):
        white = rng.standard_normal(shape)
        blurred = circular_blur(white, sigma * aniso[0], sigma * aniso[1])
        total += blurred * amp
        amp_sum += amp
        amp *= persistence
        sigma /= lacunarity
    return normalize01(total / amp_sum)


def creases(
    shape: Shape,
    seed: int,
    nx: int = 0,
    ny: int = 4,
    width: float = 0.02,
    warp_strength: float = 0.1,
    warp_sigma: float = 60.0,
) -> np.ndarray:
    """Hand-drawn-looking crack/seam lines: a striped field (an INTEGER
    period count `nx`/`ny` so it tiles exactly) domain-warped by a seamless
    noise field, then measured as a distance IN FRACTION-OF-PERIOD UNITS
    from the nearest stripe center. v3 reserves this for CRACK DECALS only
    (`build_crack_branch`) -- no terrain or trim-sheet builder calls it any
    more (CHK-08).

    `width` is the line half-width as a fraction of one period. `warp_strength`
    is the max sideways wobble, also as a fraction of one period -- push it
    higher (as the crack decal does) for self-crossing loops that read as
    authentic branching cracks instead of a clean seam line.
    """
    h, w = shape
    warp = fbm(shape, seed + 500, octaves=3, persistence=0.5, lacunarity=2.0, base_sigma=warp_sigma) * 2.0 - 1.0
    yy, xx = np.mgrid[0:h, 0:w]
    frac = nx * xx / w + ny * yy / h + warp * warp_strength
    d = np.abs(frac - np.round(frac))  # 0 at a stripe center, up to 0.5 halfway between
    return np.clip(np.exp(-(d ** 2) / (2.0 * width * width)), 0.0, 1.0)


def wavy_lines(shape: Shape, seed: int, n_lines: int, width: float, wobble: float, wobble_sigma: float = 140.0) -> np.ndarray:
    """`n_lines` horizontal-ish wavy grooves at even vertical spacing, each
    independently wobbling in x. v3 reserves this for the wavy CRACK DECAL
    (`build_crack_wavy`) only -- no terrain/trim builder calls it any more."""
    h, w = shape
    yy, xx = np.mgrid[0:h, 0:w]
    mask = np.zeros(shape)
    for i in range(n_lines):
        seed_i = seed + i * 37
        wob = (fbm(shape, seed_i, octaves=3, base_sigma=wobble_sigma) * 2.0 - 1.0) * wobble
        center_y = (i + 0.5) * h / n_lines
        dy = (yy - (center_y + wob)) / (h * width)
        mask = np.maximum(mask, np.exp(-(dy ** 2) * 8.0))
    return np.clip(mask, 0.0, 1.0)


def blotches(shape: Shape, seed: int, coverage: float = 0.06, softness: float = 0.08, base_sigma: float = 220.0) -> np.ndarray:
    """Soft irregular patches -- a thresholded low/mid-frequency fbm field.
    Terrain/trim callers keep `coverage` small (SS7.8: "aucune tache de plus
    de 10% de l'aire")."""
    n = fbm(shape, seed, octaves=4, persistence=0.55, lacunarity=2.1, base_sigma=base_sigma)
    lo = 1.0 - coverage - softness
    hi = 1.0 - coverage + softness
    return np.clip((n - lo) / max(hi - lo, 1e-4), 0.0, 1.0)


def streaks(shape: Shape, seed: int, base_sigma: float = 220.0, stretch: float = 4.0, vertical: bool = True) -> np.ndarray:
    """Directional brush-stroke noise (anisotropic blur)."""
    aniso = (stretch, 1.0) if vertical else (1.0, stretch)
    return fbm(shape, seed, octaves=4, persistence=0.5, lacunarity=2.0, base_sigma=base_sigma, aniso=aniso)


def rivet_grid(shape: Shape, seed: int, nx: int, ny: int, radius: float = 0.16) -> np.ndarray:
    """Small round rivet bumps (dark ring + soft highlight) on a regular,
    tile-exact grid (`nx`/`ny` divide the tile evenly)."""
    h, w = shape
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float64)
    cell_w = w / nx
    cell_h = h / ny
    fx = (xx % cell_w) / cell_w - 0.5
    fy = (yy % cell_h) / cell_h - 0.5
    d = np.sqrt(fx * fx + fy * fy)
    ring = np.clip(1.0 - np.abs(d - radius) / (radius * 0.6), 0.0, 1.0)
    core = np.clip(1.0 - d / (radius * 0.7), 0.0, 1.0) * 0.5
    rng = _rng(seed)
    jitter = rng.uniform(0.85, 1.0, size=(ny, nx))
    jitter_full = np.kron(jitter, np.ones((int(round(cell_h)), int(round(cell_w)))))
    jitter_full = jitter_full[:h, :w]
    if jitter_full.shape != (h, w):
        jitter_full = np.ones((h, w))
    return np.clip((ring + core), 0.0, 1.0) * jitter_full


def grain(shape: Shape, seed: int, sigma: float = 1.1) -> np.ndarray:
    """Very fine, almost-white noise for a painted/canvas micro-texture."""
    return circular_blur(_rng(seed).standard_normal(shape), sigma)


# --------------------------------------------------------------------------- color compose

def fill(shape: Shape, color: tuple[float, float, float]) -> np.ndarray:
    h, w = shape
    return np.tile(np.array(color, dtype=np.float64)[None, None, :], (h, w, 1))


def lerp3(a: np.ndarray, b: np.ndarray, t: np.ndarray) -> np.ndarray:
    t = t[..., None]
    return a * (1.0 - t) + b * t


def mul_value(color: np.ndarray, v: np.ndarray, lo: float, hi: float) -> np.ndarray:
    return color * (lo + (hi - lo) * v)[..., None]


def hexc(h: str) -> np.ndarray:
    """`#RRGGBB` -> a (3,) float array in [0, 1]. Matches
    docs/style/tokens.json's `maps.*.ground`/`materials` hex values exactly,
    so the generator's output stays traceable back to the locked design
    tokens."""
    h = h.lstrip("#")
    return np.array([int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)])


# --------------------------------------------------------------------------- OKLab (CHK-08 self-check only)
#
# Standard conversion, Bjoern Ottosson (https://bottosson.github.io/posts/oklab/).
# Self-contained here for the same reason `tests/agents/test_agent_palette.gd`'s
# `_oklch()` is self-contained: no shared OKLab utility exists yet in the repo
# (StyleTokens.gd / tools/review/style_check.py are ART-03/ART-05, outside
# this task's file list).

def _srgb_to_linear(c: np.ndarray) -> np.ndarray:
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def _linear_to_srgb(c: np.ndarray) -> np.ndarray:
    c = np.clip(c, 0.0, None)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * c ** (1.0 / 2.4) - 0.055)


def _cbrt(x: np.ndarray) -> np.ndarray:
    return np.sign(x) * np.abs(x) ** (1.0 / 3.0)


def oklab_l(rgb01: np.ndarray) -> np.ndarray:
    """`rgb01`: (..., 3) sRGB in [0, 1] -> OKLab lightness, same shape minus
    the last axis."""
    lin = _srgb_to_linear(rgb01)
    r, g, b = lin[..., 0], lin[..., 1], lin[..., 2]
    l = 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b
    m = 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b
    s = 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b
    l_, m_, s_ = _cbrt(l), _cbrt(m), _cbrt(s)
    return 0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_


def hexc_at_l(hex_str: str, target_l: float, iters: int = 50) -> np.ndarray:
    """`hexc(hex_str)` rescaled (uniform linear-light gain, hue/chroma
    direction kept) to hit OKLab lightness `target_l`.

    CHK-08 caps a trim-sheet's *whole-file* post-blur L std at 0.04, but a
    trim sheet's five bands (SS7.8: border/plank/corrugated/rivet/stencil)
    are, by design, different MATERIALS with very different hexes in
    `docs/style/tokens.json` -- their lightness alone spans ~0.56-0.76,
    already ~4x the whole-file std budget before any per-band modulation is
    even added. So every trim band is built from its token hex rescaled to
    one shared target lightness: material identity comes from HUE (still
    the token color), not from baked VALUE -- value is for the shader's
    real-time shading (band_count, AO vertex mask), matching this task's
    "l'encre vient de la geometrie" thesis (SS7.8/SS "Ce qui change")."""
    lin = _srgb_to_linear(hexc(hex_str))
    lo, hi = 0.02, 6.0
    for _ in range(iters):
        mid = 0.5 * (lo + hi)
        srgb = _linear_to_srgb(np.clip(lin * mid, 0.0, 1.0))
        if float(oklab_l(srgb)) < target_l:
            lo = mid
        else:
            hi = mid
    return _linear_to_srgb(np.clip(lin * 0.5 * (lo + hi), 0.0, 1.0))


# --------------------------------------------------------------------------- PNG / import writers

def to_png(arr01: np.ndarray, path: Path) -> None:
    """Writes an opaque L or RGB PNG (terrain, trim-sheets)."""
    arr = np.clip(arr01, 0.0, 1.0)
    img = (arr * 255.0 + 0.5).astype(np.uint8)
    path.parent.mkdir(parents=True, exist_ok=True)
    if img.ndim == 2:
        Image.fromarray(img, mode="L").save(path)
    else:
        Image.fromarray(img, mode="RGB").save(path)
    print(f"  wrote {path.relative_to(REPO_ROOT)}  {img.shape[1]}x{img.shape[0]}")


def to_png_rgba(rgb01: np.ndarray, alpha01: np.ndarray, path: Path) -> None:
    """Writes an RGBA PNG (the decal atlas)."""
    rgb = np.clip(rgb01, 0.0, 1.0)
    a = np.clip(alpha01, 0.0, 1.0)
    rgba = np.concatenate([rgb, a[..., None]], axis=-1)
    img = (rgba * 255.0 + 0.5).astype(np.uint8)
    path.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(img, mode="RGBA").save(path)
    print(f"  wrote {path.relative_to(REPO_ROOT)}  {img.shape[1]}x{img.shape[0]} (RGBA)")


IMPORT_TEMPLATE = """[remap]

importer="texture"
type="CompressedTexture2D"

[deps]

source_file="res://{res_path}"
dest_files=["res://.godot/imported/{stem}.{ext}-{fake_md5}.ctex"]

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
    """Hand-write a Godot 4 `.import` sidecar so a headless `--import` pass
    (no editor GUI) still gets sane defaults: mipmaps generated (so
    triplanar/trim sampling at distance doesn't alias/shimmer) and lossless
    compression (no VRAM-compressor dependency, deterministic bytes for CI).
    sRGB decoding is NOT set here: it comes from the `source_color` hint on
    the shader's sampler uniform instead. `uid` is intentionally omitted --
    Godot assigns and persists one on the next `--import` pass."""
    res_path = png_path.relative_to(REPO_ROOT).as_posix()
    stem = png_path.stem
    fake_md5 = "0" * 32  # placeholder; Godot rewrites dest_files with the real hash on import.
    content = IMPORT_TEMPLATE.format(res_path=res_path, stem=stem, ext="png", fake_md5=fake_md5)
    import_path = png_path.with_suffix(png_path.suffix + ".import")
    import_path.write_text(content, encoding="utf-8", newline="\n")


# --------------------------------------------------------------------------- CHK-08 self-check
#
# docs/STYLE_BIBLE.md CHK-08: "textures assets/textures/painted/*_albedo.png
# et trim-sheets : 0 pixel a L < 0.25 (sauf rubber*) ; ecart-type de L apres
# flou gaussien de 2 px <= 0.04". The decal atlas is out of CHK-08's scope
# (it legitimately carries ink-black stencil/outline colors), so it is not
# checked here.

CHK08_STD_MAX = 0.04
CHK08_L_MIN = 0.25


def check_chk08(png_path: Path, exempt: bool = False) -> tuple[bool, str]:
    img = Image.open(png_path).convert("RGB")
    arr = np.asarray(img).astype(np.float64) / 255.0
    l = oklab_l(arr)
    min_l = float(l.min())
    blurred = circular_blur(l, 2.0)
    std = float(blurred.std())
    ok_min = exempt or min_l >= CHK08_L_MIN
    ok_std = std <= CHK08_STD_MAX
    status = "PASS" if (ok_min and ok_std) else "FAIL"
    detail = f"{status}  min_L={min_l:.4f} (>= {CHK08_L_MIN} {'exempt' if exempt else 'required'})  std_L(blur2px)={std:.4f} (<= {CHK08_STD_MAX})"
    return ok_min and ok_std, detail


# --------------------------------------------------------------------------- terrains (assets/textures/painted/)
#
# SS7.8 point 3: "Terrain 1024^2 : sable, pont, paves, neige, calcaire,
# terre_battue, quai." Base hex per terrain is each map's own
# docs/style/tokens.json `maps.<id>.ground` (or the matching `materials`
# entry for pont/quai), kept exact so the generator stays traceable to the
# locked tokens:
#   sable         -- wasteland.ground            #D2A46C
#   pont          -- cargo_ship.ground            #8D959B  (steel deck)
#   paves         -- saint_ombre.ground           #6E6A73  (pavés mouillés)
#   neige         -- col_du_vautour.ground        #F1F4F8
#   calcaire      -- la_fosse.ground              #E3D3AE
#   terre_battue  -- val_poussiere.ground         #C9A06E
#   quai          -- port_ferraille.ground        #BBA98C

def make_terrain(
    base_hex: str,
    seed: int,
    *,
    fleck_coverage: float = 0.05,
    fleck_tint: float = 0.05,
    streak_amount: float = 0.0,
    grain_amount: float = 0.010,
) -> np.ndarray:
    """Generic flat-painted terrain builder: one broad (>=200 px) fbm value
    pass, a second finer one, optional sparse small flecks (pebbles/grit,
    capped well under the 10% area ceiling) and fine canvas grain -- no
    `creases()`/`wavy_lines()` anywhere (CHK-08). Every multiplier stays a
    gentle +/-1.5 to 3.5% so even the darkest terrain base
    (`paves` #6E6A73, OKLab L ~= 0.53) keeps a wide margin over the CHK-08
    L >= 0.25 floor."""
    shape = (TERRAIN_SIZE, TERRAIN_SIZE)
    base = hexc(base_hex)
    color = fill(shape, base)
    big = fbm(shape, seed, octaves=3, persistence=0.55, lacunarity=2.0, base_sigma=260.0)
    color = mul_value(color, big, 0.965, 1.035)
    fine = fbm(shape, seed + 1, octaves=4, persistence=0.5, lacunarity=2.0, base_sigma=210.0)
    color = mul_value(color, fine, 0.985, 1.015)
    if streak_amount > 0.0:
        s = streaks(shape, seed + 2, base_sigma=240.0, stretch=3.0, vertical=False)
        color = mul_value(color, s, 1.0 - streak_amount, 1.0 + streak_amount)
    if fleck_coverage > 0.0:
        flecks = blotches(shape, seed + 3, coverage=fleck_coverage, softness=0.04, base_sigma=9.0)
        color = mul_value(color, flecks, 1.0, 1.0 - fleck_tint)
    color = np.clip(color + (grain(shape, seed + 4, 1.2) - 0.5)[..., None] * grain_amount, 0.0, 1.0)
    return color


TERRAINS: dict[str, dict] = {
    "sable": {"hex": "#D2A46C", "seed": 201, "fleck_coverage": 0.06, "fleck_tint": 0.05, "grain_amount": 0.012},
    "pont": {"hex": "#8D959B", "seed": 202, "fleck_coverage": 0.0, "streak_amount": 0.02, "grain_amount": 0.008},
    "paves": {"hex": "#6E6A73", "seed": 203, "fleck_coverage": 0.08, "fleck_tint": 0.035, "grain_amount": 0.008},
    "neige": {"hex": "#F1F4F8", "seed": 204, "fleck_coverage": 0.0, "grain_amount": 0.006},
    "calcaire": {"hex": "#E3D3AE", "seed": 205, "fleck_coverage": 0.05, "fleck_tint": 0.04, "grain_amount": 0.012},
    "terre_battue": {"hex": "#C9A06E", "seed": 206, "fleck_coverage": 0.07, "fleck_tint": 0.05, "grain_amount": 0.012},
    "quai": {"hex": "#BBA98C", "seed": 207, "fleck_coverage": 0.0, "streak_amount": 0.015, "grain_amount": 0.008},
}


# --------------------------------------------------------------------------- trim-sheets (assets/textures/trim/)
#
# SS7.8 point 3: "Trim-sheets 1024^2 par theme (desert, port-cargo, ville,
# alpin) : bandes de planche, de tole ondulee (rayures de valeur +/-6%, pas
# de flou), de rivets, de pochoirs, de bordure claire." Five equal-height
# horizontal bands, top to bottom: light border, planks, corrugated metal,
# rivets, stencil-dash. Every base hex below is a `docs/style/tokens.json`
# `maps.*.materials` entry with OKLab L >= 0.40, so even the corrugated
# band's +/-6% swing never nears the CHK-08 L >= 0.25 floor.

TRIM_TARGET_L = 0.62  # shared band lightness -- see `hexc_at_l`

TRIM_THEMES: dict[str, dict[str, str]] = {
    "desert": {  # Wasteland materials
        "border": "#B8AFA0", "plank": "#9C6A42", "corrugated": "#4F7FA8", "rivet": "#B5562A", "stencil": "#C58B4E",
    },
    "port_cargo": {  # Cargo Ship materials
        "border": "#EDEBE4", "plank": "#9C6A42", "corrugated": "#2F63B8", "rivet": "#C8322B", "stencil": "#EDEBE4",
    },
    "ville": {  # Saint-Ombre materials. `corrugated` uses `stone` rather than
        # the more saturated `cast_iron` (#4A505C, OKLab L ~= 0.43): its ~0.19
        # gap from TRIM_TARGET_L needed a rescale large enough to visibly
        # oversaturate toward blue -- `stone` sits within ~0.02 of the target
        # already, so it rescales with no perceptible hue drift.
        "border": "#D9C7A5", "plank": "#9C6A42", "corrugated": "#8C7F72", "rivet": "#A5492F", "stencil": "#D9C7A5",
    },
    "alpin": {  # Col du Vautour materials. `rivet` uses `rust` rather than
        # `barriers`/hazard yellow (#F2B51D, L ~= 0.81): same oversaturation
        # risk as above at that gap size.
        "border": "#E6E1D6", "plank": "#9C6A42", "corrugated": "#7E7A86", "rivet": "#B5562A", "stencil": "#E6E1D6",
    },
}


def _band_border(w: int, h: int, base_hex: str, seed: int) -> np.ndarray:
    """Light cap-strip band: a soft rounded highlight down the middle."""
    shape = (h, w)
    yy, _ = np.mgrid[0:h, 0:w]
    mid = h / 2.0
    prof = np.clip(1.0 - np.abs((yy - mid) / mid), 0.0, 1.0)
    color = fill(shape, hexc_at_l(base_hex, TRIM_TARGET_L))
    color = mul_value(color, prof, 0.97, 1.035)
    color = mul_value(color, fbm(shape, seed, octaves=3, base_sigma=max(h, 220.0)), 0.985, 1.015)
    return color


def _band_plank(w: int, h: int, base_hex: str, seed: int, n_planks: int = 10) -> np.ndarray:
    """Vertical plank band: gentle per-plank tint step, no seam ink."""
    shape = (h, w)
    _, xx = np.mgrid[0:h, 0:w]
    plank_id = np.floor(xx * n_planks / w).astype(int) % n_planks
    tint = _rng(seed).uniform(-0.03, 0.03, size=n_planks)
    tint_field = tint[plank_id]
    color = fill(shape, hexc_at_l(base_hex, TRIM_TARGET_L))
    color = color * (1.0 + tint_field[..., None])
    color = mul_value(color, fbm(shape, seed + 1, octaves=4, base_sigma=max(h, 220.0), aniso=(1.0, 4.0)), 0.98, 1.02)
    return np.clip(color, 0.0, 1.0)


def _band_corrugated(w: int, h: int, base_hex: str, seed: int, n_ribs: int = 16) -> np.ndarray:
    """Corrugated metal band: sharp (unblurred) cosine ribs, +/-6% value --
    SS7.8's one named exception to the +/-4% default, still far above the
    CHK-08 floor since every base hex here has OKLab L >= 0.40."""
    shape = (h, w)
    _, xx = np.mgrid[0:h, 0:w]
    phase = 2.0 * np.pi * xx * n_ribs / w
    rib = 0.5 + 0.5 * np.cos(phase)
    color = fill(shape, hexc_at_l(base_hex, TRIM_TARGET_L))
    color = mul_value(color, rib, 0.94, 1.06)
    return color


def _band_rivet(w: int, h: int, base_hex: str, seed: int) -> np.ndarray:
    """Rivet band: a tile-exact grid of small rivet bumps, gentle +/-5%."""
    shape = (h, w)
    nx = max(4, w // 64)
    ny = max(1, h // 64)
    rivets = rivet_grid(shape, seed, nx=nx, ny=ny, radius=0.22)
    color = fill(shape, hexc_at_l(base_hex, TRIM_TARGET_L))
    color = mul_value(color, np.clip(rivets, 0.0, 1.0), 0.95, 1.05)
    return color


def _band_stencil(w: int, h: int, base_hex: str, seed: int) -> np.ndarray:
    """Stencil-dash band: a repeating grid of small rectangular cut marks
    (a generic "pochoir" texture, distinct from the named word stencils in
    the decal atlas) -- geometric hard edges, but only a gentle 10% dip, so
    it never approaches the CHK-08 ink floor."""
    shape = (h, w)
    yy, xx = np.mgrid[0:h, 0:w]
    cols, rows = 14, 2
    cell_w, cell_h = w / cols, h / rows
    fx = xx % cell_w
    fy = yy % cell_h
    dash = ((fx > cell_w * 0.38) & (fx < cell_w * 0.62) & (fy > cell_h * 0.52) & (fy < cell_h * 0.74))
    color = fill(shape, hexc_at_l(base_hex, TRIM_TARGET_L))
    color = mul_value(color, (~dash).astype(np.float64), 0.95, 1.0)
    color = mul_value(color, fbm(shape, seed, octaves=3, base_sigma=max(h, 220.0)), 0.99, 1.01)
    return color


def build_trim_sheet(palette: dict[str, str], seed: int) -> np.ndarray:
    w = TRIM_SIZE
    band_h = TRIM_SIZE // 5
    bands = [
        _band_border(w, band_h, palette["border"], seed + 1),
        _band_plank(w, band_h, palette["plank"], seed + 2),
        _band_corrugated(w, band_h, palette["corrugated"], seed + 3),
        _band_rivet(w, band_h, palette["rivet"], seed + 4),
        _band_stencil(w, band_h, palette["stencil"], seed + 5),
    ]
    color = np.concatenate(bands, axis=0)
    remainder = TRIM_SIZE - color.shape[0]
    if remainder > 0:
        color = np.concatenate([color, np.repeat(color[-1:], remainder, axis=0)], axis=0)
    color = np.clip(color + (grain((TRIM_SIZE, TRIM_SIZE), seed + 50, 1.0) - 0.5)[..., None] * 0.008, 0.0, 1.0)
    return color


# --------------------------------------------------------------------------- decal atlas (assets/textures/decals/)
#
# SS7.8 point 3 / task acceptance: "pochoirs FUEL, GAS, numeros, fleches,
# FRAGILE, GRAINES, autocollants de l'emission, etoiles d'impact, brulures,
# fissures, lettres A/B". Unlike terrain/trim, the atlas is RGBA and is OUT
# of CHK-08's scope (real ink/stencil colors are the point of a decal).

INK = "#1A1410"
FUEL_HEX = "#3E7BB5"   # tokens.json maps.wasteland.materials.fuel_sign
GAS_HEX = "#B8322A"    # tokens.json maps.wasteland.materials.gas_sign
SITE_FILL_HEX = "#F2C230"   # tokens.json world.site_decal.color
SITE_OUTLINE_HEX = "#1A1410"  # tokens.json world.site_decal.outline
STICKER_BG_HEX = "#F4EDE1"    # papier
STICKER_RING_HEXES = ("#C8242C", "#F2C230", "#3B8BFF")  # pinceau / objectif / allie

# 5x7 dot-matrix glyphs -- 'X' = ink, '.' = empty. Only the letters actually
# needed by FUEL/GAS/FRAGILE/GRAINES/site A/B are defined, plus digits 0-9.
GLYPHS: dict[str, tuple[str, ...]] = {
    "A": (".XXX.", "X...X", "X...X", "XXXXX", "X...X", "X...X", "X...X"),
    "B": ("XXXX.", "X...X", "X...X", "XXXX.", "X...X", "X...X", "XXXX."),
    "E": ("XXXXX", "X....", "X....", "XXXX.", "X....", "X....", "XXXXX"),
    "F": ("XXXXX", "X....", "X....", "XXXX.", "X....", "X....", "X...."),
    "G": (".XXXX", "X....", "X....", "X.XXX", "X...X", "X...X", ".XXXX"),
    "I": ("XXXXX", "..X..", "..X..", "..X..", "..X..", "..X..", "XXXXX"),
    "L": ("X....", "X....", "X....", "X....", "X....", "X....", "XXXXX"),
    "N": ("X...X", "XX..X", "X.X.X", "X.X.X", "X..XX", "X...X", "X...X"),
    "R": ("XXXX.", "X...X", "X...X", "XXXX.", "X.X..", "X..X.", "X...X"),
    "S": (".XXXX", "X....", "X....", ".XXX.", "....X", "....X", "XXXX."),
    "U": ("X...X", "X...X", "X...X", "X...X", "X...X", "X...X", ".XXX."),
    "0": (".XXX.", "X...X", "X..XX", "X.X.X", "XX..X", "X...X", ".XXX."),
    "1": ("..X..", ".XX..", "..X..", "..X..", "..X..", "..X..", ".XXX."),
    "2": (".XXX.", "X...X", "....X", "...X.", "..X..", ".X...", "XXXXX"),
    "3": ("XXXX.", "....X", "....X", ".XXX.", "....X", "....X", "XXXX."),
    "4": ("...X.", "..XX.", ".X.X.", "X..X.", "XXXXX", "...X.", "...X."),
    "5": ("XXXXX", "X....", "X....", "XXXX.", "....X", "....X", "XXXX."),
    "6": (".XXX.", "X....", "X....", "XXXX.", "X...X", "X...X", ".XXX."),
    "7": ("XXXXX", "....X", "...X.", "..X..", ".X...", ".X...", ".X..."),
    "8": (".XXX.", "X...X", "X...X", ".XXX.", "X...X", "X...X", ".XXX."),
    "9": (".XXX.", "X...X", "X...X", ".XXXX", "....X", "....X", ".XXX."),
}


def glyph_mask(ch: str, cell: int) -> np.ndarray:
    rows = GLYPHS[ch]
    small = np.array([[c == "X" for c in row] for row in rows], dtype=bool)  # (7, 5)
    return np.kron(small, np.ones((cell, cell), dtype=bool))  # (7*cell, 5*cell)


def word_width(word: str, cell: int, gap: int = 1) -> int:
    return len(word) * (5 + gap) * cell - gap * cell


def word_height(cell: int) -> int:
    return 7 * cell


def word_mask(word: str, cell: int, gap: int = 1) -> np.ndarray:
    h = word_height(cell)
    total_w = word_width(word, cell, gap)
    mask = np.zeros((h, total_w), dtype=bool)
    x = 0
    for ch in word:
        gm = glyph_mask(ch, cell)
        mask[:, x:x + gm.shape[1]] |= gm
        x += gm.shape[1] + gap * cell
    return mask


def flat_decal(mask: np.ndarray, color_hex: str) -> tuple[np.ndarray, np.ndarray]:
    """A single flat-color stencil cut: RGB filled with `color_hex` where
    `mask` is set, alpha = `mask`."""
    h, w = mask.shape
    rgb = fill((h, w), hexc(color_hex))
    alpha = mask.astype(np.float64)
    return rgb, alpha


def build_word_stencil(word: str, cell: int, color_hex: str) -> tuple[np.ndarray, np.ndarray]:
    return flat_decal(word_mask(word, cell), color_hex)


def build_digit_stencil(digit: str, cell: int) -> tuple[np.ndarray, np.ndarray]:
    return flat_decal(glyph_mask(digit, cell), INK)


def build_site_letter(letter: str, cell: int, outline_px: int) -> tuple[np.ndarray, np.ndarray]:
    """Tactical bomb-site letter (A/B): `site_decal` yellow fill on a thick
    ink outline, per `docs/style/tokens.json` `world.site_decal`."""
    base = glyph_mask(letter, cell)
    h, w = base.shape
    padded = np.zeros((h + 2 * outline_px, w + 2 * outline_px), dtype=bool)
    padded[outline_px:outline_px + h, outline_px:outline_px + w] = base
    outline = binary_dilation(padded, structure=np.ones((2 * outline_px + 1, 2 * outline_px + 1), dtype=bool))
    rgb = np.zeros((*outline.shape, 3))
    rgb[outline] = hexc(SITE_OUTLINE_HEX)
    rgb[padded] = hexc(SITE_FILL_HEX)
    alpha = outline.astype(np.float64)
    return rgb, alpha


def _radial_grid(size: int) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float64)
    cx = cy = size / 2.0
    dx, dy = xx - cx, yy - cy
    r = np.sqrt(dx * dx + dy * dy) / (size * 0.5)
    theta = np.arctan2(dy, dx)
    return r, theta, dx


def build_arrow_straight(size: int) -> tuple[np.ndarray, np.ndarray]:
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float64)
    cx = size / 2.0
    shaft = (np.abs(xx - cx) < size * 0.11) & (yy > size * 0.40) & (yy < size * 0.92)
    t = np.clip(yy / (size * 0.46), 0.0, 1.0)
    half_w = t * (size * 0.30)
    head = (yy <= size * 0.46) & (np.abs(xx - cx) <= half_w)
    return flat_decal(shaft | head, INK)


def build_arrow_chevron(size: int) -> tuple[np.ndarray, np.ndarray]:
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float64)
    cx = size / 2.0

    def band(y0: float, y1: float) -> np.ndarray:
        t = np.clip((yy - y0) / (y1 - y0), 0.0, 1.0)
        half_w = t * (size * 0.42)
        thickness = size * 0.11
        return (yy >= y0) & (yy < y1) & (np.abs(np.abs(xx - cx) - half_w) < thickness)

    mask = band(size * 0.08, size * 0.52) | band(size * 0.50, size * 0.94)
    return flat_decal(mask, INK)


def build_impact_star(size: int, seed: int, points: int = 7) -> tuple[np.ndarray, np.ndarray]:
    r, theta, _ = _radial_grid(size)
    noise = fbm((size, size), seed, octaves=3, base_sigma=max(size * 0.15, 12.0))
    spike = 0.5 + 0.5 * np.cos(points * theta + noise * 2.0)
    edge = 0.28 + 0.5 * spike ** 1.8
    body = r <= edge
    crack_len = 0.28 + 0.60 * (spike ** 3)
    cracks = (r > edge) & (r <= edge + crack_len) & (spike > 0.75)
    mask = body | cracks
    rgb = fill((size, size), hexc(INK))
    alpha = mask.astype(np.float64) * np.clip(1.0 - r * 0.15, 0.0, 1.0)
    return rgb, alpha


def build_burn(size: int, seed: int) -> tuple[np.ndarray, np.ndarray]:
    r, _, _ = _radial_grid(size)
    n = fbm((size, size), seed, octaves=4, persistence=0.55, base_sigma=max(size * 0.12, 10.0))
    radial = np.clip(1.0 - r, 0.0, 1.0) ** 1.3
    field = np.clip(n * 0.6 + radial * 0.6 - 0.35, 0.0, 1.0)
    core = np.array([0.06, 0.045, 0.035])
    ring = np.array([0.24, 0.20, 0.16])
    rgb = lerp3(fill((size, size), ring), fill((size, size), core), np.clip(field * 1.4, 0.0, 1.0))
    alpha = np.clip(field * 1.3, 0.0, 1.0)
    return rgb, alpha


def build_crack_branch(size: int, seed: int) -> tuple[np.ndarray, np.ndarray]:
    """The one place `creases()` still runs (SS7.8 point 1): a branching
    crack decal, high `warp_strength` so the domain-warped stripe folds into
    self-crossing loops instead of a clean seam."""
    shape = (size, size)
    c1 = creases(shape, seed, nx=3, ny=2, width=0.014, warp_strength=0.55, warp_sigma=34.0)
    c2 = creases(shape, seed + 7, nx=2, ny=3, width=0.012, warp_strength=0.5, warp_sigma=28.0)
    field = np.clip(c1 + c2, 0.0, 1.0)
    r, _, _ = _radial_grid(size)
    bound = np.clip(1.0 - r, 0.0, 1.0) ** 0.6
    field = field * bound
    rgb = fill(shape, hexc(INK))
    alpha = np.clip(field * 1.1, 0.0, 1.0)
    return rgb, alpha


def build_crack_wavy(size: int, seed: int) -> tuple[np.ndarray, np.ndarray]:
    """The one place `wavy_lines()` still runs (SS7.8 point 1): a single
    wide, wandering fracture."""
    shape = (size, size)
    field = wavy_lines(shape, seed, n_lines=1, width=0.05, wobble=size * 0.16)
    r, _, _ = _radial_grid(size)
    bound = np.clip(1.0 - r, 0.0, 1.0) ** 0.5
    field = np.clip(field, 0.0, 1.0) * bound
    rgb = fill(shape, hexc(INK))
    alpha = np.clip(field * 1.1, 0.0, 1.0)
    return rgb, alpha


def _polygon_mask(size: int, n_sides: int, rotation_deg: float = 0.0, scale: float = 0.42) -> np.ndarray:
    """A regular `n_sides`-gon, apothem-distance formula (standard: a point
    is inside a regular polygon iff its radius is under
    `apothem / cos(angle_to_nearest_edge_center)`)."""
    r, theta, _ = _radial_grid(size)
    theta = theta - np.deg2rad(rotation_deg)
    seg = 2.0 * np.pi / n_sides
    theta_mod = np.mod(theta + seg / 2.0, seg) - seg / 2.0
    edge_r = (scale * 2.0) * np.cos(seg / 2.0) / np.cos(theta_mod)
    return r <= edge_r


def build_sticker(size: int, seed: int, points: int, ring_hex: str) -> tuple[np.ndarray, np.ndarray]:
    """SS8.1 layer-2 "autocollant": an inclined-12-degree hexagonal badge,
    thick ink outline, hard offset shadow, papier body, a star/diamond/
    triangle icon in the show's accent colour -- one of the tournament's
    ("BRIC-A-BRAC", SS3) merch stickers."""
    body = _polygon_mask(size, 6, rotation_deg=12.0, scale=0.40)
    outline_px = max(2, int(size * 0.028))
    outline = binary_dilation(body, structure=np.ones((2 * outline_px + 1, 2 * outline_px + 1), dtype=bool))
    shadow_off = max(2, int(size * 0.045))
    shadow = np.zeros_like(outline)
    shadow[shadow_off:, shadow_off:] = outline[:-shadow_off, :-shadow_off]

    r, theta, _ = _radial_grid(size)
    theta_i = theta - np.deg2rad(12.0)
    spike = 0.5 + 0.5 * np.cos(points * theta_i)
    icon_edge = 0.10 + 0.14 * spike ** 1.6
    icon = r <= icon_edge

    rgb = np.zeros((size, size, 3))
    alpha = np.zeros((size, size))
    rgb[shadow] = hexc(INK)
    alpha[shadow] = 1.0
    rgb[outline] = hexc(INK)
    alpha[outline] = 1.0
    rgb[body] = hexc(STICKER_BG_HEX)
    alpha[body] = 1.0
    rgb[icon] = hexc(ring_hex)
    alpha[icon] = 1.0
    return rgb, alpha


# --------------------------------------------------------------------------- decal atlas layout / packer

class _ShelfPacker:
    """Deterministic left-to-right, top-to-bottom shelf packer: simple and
    fully reproducible given a fixed call order (which every call site below
    hardcodes)."""

    def __init__(self, atlas_w: int, atlas_h: int, margin: int = 24) -> None:
        self.atlas_w = atlas_w
        self.atlas_h = atlas_h
        self.margin = margin
        self.x = margin
        self.y = margin
        self.row_h = 0
        self.rects: dict[str, tuple[int, int, int, int]] = {}

    def place(self, name: str, w: int, h: int) -> tuple[int, int]:
        if self.x + w + self.margin > self.atlas_w:
            self.x = self.margin
            self.y += self.row_h + self.margin
            self.row_h = 0
        if self.y + h + self.margin > self.atlas_h:
            raise ValueError(f"decal atlas overflow placing {name!r} ({w}x{h}) at y={self.y}: atlas is {self.atlas_w}x{self.atlas_h}")
        pos = (self.x, self.y)
        self.rects[name] = (self.x, self.y, w, h)
        self.x += w + self.margin
        self.row_h = max(self.row_h, h)
        return pos


def build_decal_atlas() -> tuple[np.ndarray, np.ndarray, dict[str, tuple[int, int, int, int]]]:
    size = DECAL_ATLAS_SIZE
    atlas_rgb = np.zeros((size, size, 3))
    atlas_alpha = np.zeros((size, size))
    packer = _ShelfPacker(size, size, margin=24)

    def put(name: str, rgb: np.ndarray, alpha: np.ndarray) -> None:
        h, w = alpha.shape
        x, y = packer.place(name, w, h)
        atlas_rgb[y:y + h, x:x + w] = rgb
        atlas_alpha[y:y + h, x:x + w] = alpha

    word_cell = 16
    put("stencil_fuel", *build_word_stencil("FUEL", word_cell, FUEL_HEX))
    put("stencil_gas", *build_word_stencil("GAS", word_cell, GAS_HEX))
    put("stencil_fragile", *build_word_stencil("FRAGILE", word_cell, INK))
    put("stencil_graines", *build_word_stencil("GRAINES", word_cell, INK))

    for d in "0123456789":
        put(f"num_{d}", *build_digit_stencil(d, word_cell))

    put("arrow_straight", *build_arrow_straight(160))
    put("arrow_chevron", *build_arrow_chevron(160))

    put("impact_star_small", *build_impact_star(160, seed=301, points=7))
    put("impact_star_large", *build_impact_star(220, seed=302, points=9))

    put("burn_small", *build_burn(220, seed=311))
    put("burn_large", *build_burn(300, seed=312))

    put("crack_branch", *build_crack_branch(280, seed=321))
    put("crack_wavy", *build_crack_wavy(280, seed=322))

    for name, (points, ring_hex) in {
        "sticker_star": (5, STICKER_RING_HEXES[0]),
        "sticker_diamond": (4, STICKER_RING_HEXES[1]),
        "sticker_triangle": (3, STICKER_RING_HEXES[2]),
    }.items():
        put(name, *build_sticker(260, seed=331, points=points, ring_hex=ring_hex))

    site_cell, site_outline_px = 48, 6
    put("site_a", *build_site_letter("A", site_cell, site_outline_px))
    put("site_b", *build_site_letter("B", site_cell, site_outline_px))

    return atlas_rgb, atlas_alpha, packer.rects


# --------------------------------------------------------------------------- registry / main

# v3 replaces the eleven all-in-one prop materials of v2 in CONTENT (SS7.8
# point 3, "au lieu de" -- no more ink baked in, CHK-08-legal) but not in
# NAME: `scripts/core/Cartoon.gd`'s `painted(kind, tint)`/`prop_uv(kind,
# tint)` (class_name Cartoon, 27 dependents -- ArenaBuilder.gd/WorldWeapon.gd/
# MapSetup.gd/PropCatalog.gd/etc., all outside this task's file list) still
# address props by these exact 11 names (rust, wood_planks, container_paint,
# ...), so this script keeps producing one texture per name -- just no longer
# under their pre-v3 filenames.
#
# History (why the filenames moved, ART-04B, 2026-09-24): the pre-v3 script
# wrote these 17 files as `<name>_albedo.png` / `<name>_grime.png` --
# hand-painted, ink-baked (rust drips, plate seams, tread pattern). v3's first
# pass (ART-04) kept writing those SAME 17 filenames, only with the v3
# ink-free method, purely so `Cartoon.gd`'s `const _TEX_* :=
# preload("res://assets/textures/painted/<stem>.png")` (parsed at PARSE TIME
# in Godot 4) would not throw "Can't preload resource file" and take the
# whole game down -- deleting them outright, before every preload() pointing
# at them was updated, previously broke the build this same day (see
# `_remove_stale_v2_outputs()` below). ART-04B is that update: `Cartoon.gd`'s
# 17 preloads now point at the `material_<name>_*.png` names below instead,
# so the old pre-v3 stems are dead weight and this script deletes them.
#
# Built with the SAME `make_terrain()` used for the 7 official terrains,
# seeded from each material's own docs/style/tokens.json-traced base hex (kept
# in the `mat_*()` docstrings of the pre-v3 script) so each material reads as
# the right family (rust orange, tole blue, bois brown, ...) even though it no
# longer carries the pre-v3 script's hand-painted rust drips/plate seams/tread
# pattern. `container_paint` uses the CONTAINER_WHITE neutral (#E6E1D6,
# Cartoon.gd's own token) since that material is tinted at runtime by
# `Cartoon.painted(&"container_paint", tint)`.
PAINTED_MATERIALS: dict[str, dict] = {
    "painted_metal": {"hex": "#A13326", "seed": 701, "fleck_coverage": 0.05, "fleck_tint": 0.05, "grain_amount": 0.014, "grime_seed": 901},
    "rust": {"hex": "#B5562A", "seed": 702, "fleck_coverage": 0.06, "fleck_tint": 0.05, "grain_amount": 0.014, "grime_seed": None},
    "corrugated_metal": {"hex": "#4F7FA8", "seed": 703, "streak_amount": 0.02, "grain_amount": 0.010, "grime_seed": 902},
    "container_paint": {"hex": "#E6E1D6", "seed": 704, "fleck_coverage": 0.03, "fleck_tint": 0.03, "grain_amount": 0.008, "grime_seed": 903},
    "wood_planks": {"hex": "#9C6A42", "seed": 705, "streak_amount": 0.025, "grain_amount": 0.012, "grime_seed": 904},
    "sand_dirt": {"hex": "#C79359", "seed": 706, "fleck_coverage": 0.07, "fleck_tint": 0.05, "grain_amount": 0.012, "grime_seed": None},
    "cracked_concrete": {"hex": "#B8AFA0", "seed": 707, "fleck_coverage": 0.04, "fleck_tint": 0.04, "grain_amount": 0.010, "grime_seed": 905},
    "asphalt": {"hex": "#302F33", "seed": 708, "fleck_coverage": 0.05, "fleck_tint": 0.04, "grain_amount": 0.010, "grime_seed": None},
    "ship_deck": {"hex": "#A6A08C", "seed": 709, "streak_amount": 0.02, "grain_amount": 0.010, "grime_seed": 906},
    "rubber_tire": {"hex": "#2B2724", "seed": 710, "fleck_coverage": 0.0, "grain_amount": 0.012, "grime_seed": None},
    "dirty_glass": {"hex": "#3C5A6E", "seed": 711, "streak_amount": 0.015, "grain_amount": 0.008, "grime_seed": None},
}


def grime_generic(seed: int, blotch_coverage: float = 0.3, streak_stretch: float = 6.0) -> np.ndarray:
    """512^2 greyscale detail-mask (a multiply amount, not a color albedo --
    out of CHK-08's `*_albedo.png` scope, same as the decal atlas). Ported
    unchanged from the pre-v3 script: it was already `creases()`/
    `wavy_lines()`-free (a soft blotch/streak field), so it needs no v3
    rework."""
    shape = (DETAIL_SIZE, DETAIL_SIZE)
    b = blotches(shape, seed, coverage=blotch_coverage, softness=0.15, base_sigma=90)
    s = streaks(shape, seed + 1, base_sigma=40, stretch=streak_stretch, vertical=True)
    drip = np.clip(s - 0.6, 0, 1) * 2.0
    mask = np.clip(np.maximum(b * 0.8, drip), 0.0, 1.0)
    mask = mask * (0.7 + 0.3 * fbm(shape, seed + 2, octaves=3, base_sigma=6))
    return np.clip(mask, 0.0, 1.0)


def _write_material_textures(protected: set[Path]) -> list[Path]:
    OUT_TERRAIN.mkdir(parents=True, exist_ok=True)
    written: list[Path] = []
    for name, spec in PAINTED_MATERIALS.items():
        albedo_path = OUT_TERRAIN / f"material_{name}_albedo.png"
        if albedo_path.resolve() in protected:
            print(f"  skipped {albedo_path.relative_to(REPO_ROOT)} (hand-painted, see HAND_PAINTED.txt)")
        else:
            albedo = make_terrain(
                spec["hex"], spec["seed"],
                fleck_coverage=spec.get("fleck_coverage", 0.0),
                fleck_tint=spec.get("fleck_tint", 0.05),
                streak_amount=spec.get("streak_amount", 0.0),
                grain_amount=spec.get("grain_amount", 0.010),
            )
            to_png(albedo, albedo_path)
            write_import(albedo_path)
            written.append(albedo_path)
        grime_seed = spec["grime_seed"]
        if grime_seed is not None:
            grime_path = OUT_TERRAIN / f"material_{name}_grime.png"
            if grime_path.resolve() in protected:
                print(f"  skipped {grime_path.relative_to(REPO_ROOT)} (hand-painted, see HAND_PAINTED.txt)")
            else:
                mask = grime_generic(grime_seed)
                to_png(mask, grime_path)
                write_import(grime_path)
                written.append(grime_path)
    return written


# `scripts/core/Cartoon.gd` `preload()`ed these 17 pre-v3-named files (see
# `PAINTED_MATERIALS`'s comment above); ART-04B rewired every one of its 17
# `const _TEX_* := preload(...)` onto `material_<name>_*.png` instead, so it
# is now safe to delete them -- the 2026-09-24 incident was deleting them
# BEFORE that rewiring landed, which broke GDScript parsing project-wide.
_V2_STEMS: tuple[str, ...] = tuple(PAINTED_MATERIALS.keys())


def _remove_stale_v2_outputs(protected: set[Path]) -> list[Path]:
    removed: list[Path] = []
    for stem in _V2_STEMS:
        for suffix in ("_albedo", "_grime"):
            for ext in (".png", ".png.import"):
                path = OUT_TERRAIN / f"{stem}{suffix}{ext}"
                if path.exists() and path.resolve() not in protected:
                    path.unlink()
                    removed.append(path)
    return removed


def _write_terrains(protected: set[Path]) -> list[Path]:
    """Writes the 7 official terrains (SS7.8 point 3), skipping any output
    already listed in `HAND_PAINTED_LIST` (ART-79B: `terrain_sable`/
    `terrain_terre_battue` are two of the twelve materials
    `tools/textures/make_tileable.py` replaces under these same
    filenames)."""
    OUT_TERRAIN.mkdir(parents=True, exist_ok=True)
    terrain_files: list[Path] = []
    for name, spec in TERRAINS.items():
        path = OUT_TERRAIN / f"terrain_{name}_albedo.png"
        if path.resolve() in protected:
            print(f"  skipped {path.relative_to(REPO_ROOT)} (hand-painted, see HAND_PAINTED.txt)")
            continue
        print(f"[terrain:{name}]")
        albedo = make_terrain(
            spec["hex"], spec["seed"],
            fleck_coverage=spec.get("fleck_coverage", 0.0),
            fleck_tint=spec.get("fleck_tint", 0.05),
            streak_amount=spec.get("streak_amount", 0.0),
            grain_amount=spec.get("grain_amount", 0.010),
        )
        to_png(albedo, path)
        write_import(path)
        terrain_files.append(path)
    return terrain_files


def main() -> int:
    protected = _load_hand_painted_protected()
    if protected:
        print(f"Hand-painted outputs protected (ART-79B, see {HAND_PAINTED_LIST.relative_to(REPO_ROOT)}): {len(protected)} file(s)")

    print(f"Removing stale pre-v3 painted-material outputs (ART-04B) -> {OUT_TERRAIN.relative_to(REPO_ROOT)}")
    for p in _remove_stale_v2_outputs(protected):
        print(f"  removed {p.relative_to(REPO_ROOT)}")

    print(f"Writing painted-material textures (Cartoon.gd painted()/prop_uv() library, see PAINTED_MATERIALS) -> {OUT_TERRAIN.relative_to(REPO_ROOT)}")
    material_written = _write_material_textures(protected)
    material_albedo_files = [p for p in material_written if p.stem.endswith("_albedo")]
    for p in material_written:
        print(f"  wrote {p.relative_to(REPO_ROOT)}")

    print(f"Generating terrains -> {OUT_TERRAIN.relative_to(REPO_ROOT)}")
    terrain_files = _write_terrains(protected)

    print(f"Generating trim-sheets -> {OUT_TRIM.relative_to(REPO_ROOT)}")
    OUT_TRIM.mkdir(parents=True, exist_ok=True)
    trim_files: list[Path] = []
    for i, (theme, palette) in enumerate(TRIM_THEMES.items()):
        print(f"[trim:{theme}]")
        sheet = build_trim_sheet(palette, seed=401 + i * 20)
        path = OUT_TRIM / f"trim_{theme}.png"
        to_png(sheet, path)
        write_import(path)
        trim_files.append(path)

    print(f"Generating decal atlas -> {OUT_DECALS.relative_to(REPO_ROOT)}")
    OUT_DECALS.mkdir(parents=True, exist_ok=True)
    atlas_rgb, atlas_alpha, rects = build_decal_atlas()
    atlas_path = OUT_DECALS / "decal_atlas.png"
    to_png_rgba(atlas_rgb, atlas_alpha, atlas_path)
    write_import(atlas_path)
    manifest_path = OUT_DECALS / "decal_atlas.json"
    manifest = {
        "atlas": "decal_atlas.png",
        "size": [DECAL_ATLAS_SIZE, DECAL_ATLAS_SIZE],
        "decals": {name: {"x": x, "y": y, "w": w, "h": h} for name, (x, y, w, h) in sorted(rects.items())},
    }
    manifest_path.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8", newline="\n")
    print(f"  wrote {manifest_path.relative_to(REPO_ROOT)}  ({len(rects)} decals)")

    print("\nCHK-08 self-check (albedos sans encre) -- 7 terrains + 4 trim-sheets + 11 painted materials (STYLE_BIBLE CHK-08 covers every assets/textures/painted/*_albedo.png):")
    all_pass = True
    for path in terrain_files + trim_files + material_albedo_files:
        exempt = "rubber" in path.stem
        ok, detail = check_chk08(path, exempt=exempt)
        all_pass = all_pass and ok
        print(f"  {path.relative_to(REPO_ROOT)}: {detail}")
    n_checked = len(terrain_files) + len(trim_files) + len(material_albedo_files)
    print(f"CHK-08: {'PASS' if all_pass else 'FAIL'} ({n_checked} files checked; decal atlas and *_grime.png masks are out of CHK-08's scope)")

    print("\nDone." if all_pass else "\nDone, but CHK-08 FAILED on at least one file (see above).")
    return 0 if all_pass else 1


if __name__ == "__main__":
    sys.exit(main())
