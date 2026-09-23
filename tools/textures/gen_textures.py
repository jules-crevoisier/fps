"""gen_textures.py

Procedural "hand-painted Borderlands-style" material generator for the FPS's
painted-toon rework. Pure numpy/scipy/Pillow, fixed seeds (reproducible byte
-for-byte across runs), fully TILEABLE (world-space triplanar sampling in
assets/shaders/ink_toon.gdshader needs surfaces that repeat with no visible
seam).

Tileability technique: every noise field is built as a sum of octaves of
white noise blurred with a GAUSSIAN APPLIED IN THE FREQUENCY DOMAIN (an FFT
multiply is exactly a *circular* convolution) -- because the Fourier
transform of a Gaussian is a Gaussian, `ifft2(fft2(white) * gaussian(freq))`
blurs `white` while wrapping perfectly at the image border, at ANY sigma, for
ANY image size. No other tiling trick (mirroring, edge-blending) is needed:
every field derived from these (fbm, creases, blotches, streaks) inherits
the same seamlessness, including domain-warped "ink crease" lines, because
the warp field itself is one of these seamless fields and the base stripe
pattern uses an integer number of periods across the tile.

Usage:
    python tools/textures/gen_textures.py

Writes 1024x1024 albedo PNGs (+ a 512x512 grime/detail mask for materials
that call for one) to assets/textures/painted/, plus a matching
`<name>.png.import` next to each so Godot's headless importer picks up sane
defaults (mipmaps generated; sRGB decoding is handled by the `source_color`
sampler hint on the shader side, not by the import step).
"""
from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
from PIL import Image

SIZE = 1024
DETAIL_SIZE = 512
REPO_ROOT = Path(__file__).resolve().parents[2]
OUT_DIR = REPO_ROOT / "assets" / "textures" / "painted"

Shape = tuple[int, int]


# --------------------------------------------------------------------------- noise core

def _rng(seed: int) -> np.random.Generator:
    return np.random.default_rng(seed)


def circular_blur(a: np.ndarray, sigma_y: float, sigma_x: float | None = None) -> np.ndarray:
    """Seamless (wrap-around) Gaussian blur via an FFT-domain multiply.

    `fft2`/`ifft2` treat the array as periodic, so the result tiles exactly
    -- this is what makes every field below safe to sample with `repeat`.
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
    base_sigma: float = 120.0,
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
    """Hand-drawn-looking ink crease/seam lines: a striped field (an
    INTEGER period count `nx`/`ny` so it tiles exactly) domain-warped by a
    seamless noise field (classic trick for organic, non-mechanical
    linework), then measured as a distance IN FRACTION-OF-PERIOD UNITS from
    the nearest stripe center (not `sin()`, whose curvature would make the
    line's apparent width -- and any wobble -- wildly nonlinear near the
    zero crossing and prone to folding into self-intersecting loops).

    `width` is the line half-width as a fraction of one period (e.g. 0.02 =
    2% of a period). `warp_strength` is the max sideways wobble, ALSO as a
    fraction of one period -- keep it well under ~0.3 for a clean seam/plank
    line; crack/crackle callers can push it higher, where the resulting
    self-crossing loops read as authentic branching cracks instead.
    """
    h, w = shape
    warp = fbm(shape, seed + 500, octaves=3, persistence=0.5, lacunarity=2.0, base_sigma=warp_sigma) * 2.0 - 1.0
    yy, xx = np.mgrid[0:h, 0:w]
    frac = nx * xx / w + ny * yy / h + warp * warp_strength
    d = np.abs(frac - np.round(frac))  # 0 at a stripe center, up to 0.5 halfway between
    return np.clip(np.exp(-(d ** 2) / (2.0 * width * width)), 0.0, 1.0)


def blotches(shape: Shape, seed: int, coverage: float = 0.35, softness: float = 0.12, base_sigma: float = 70.0) -> np.ndarray:
    """Soft irregular patches (grime, oxidation, stains) -- a thresholded
    low/mid-frequency fbm field."""
    n = fbm(shape, seed, octaves=4, persistence=0.55, lacunarity=2.1, base_sigma=base_sigma)
    lo = 1.0 - coverage - softness
    hi = 1.0 - coverage + softness
    return np.clip((n - lo) / max(hi - lo, 1e-4), 0.0, 1.0)


def streaks(shape: Shape, seed: int, base_sigma: float = 90.0, stretch: float = 4.0, vertical: bool = True) -> np.ndarray:
    """Directional brush-stroke / drip noise (anisotropic blur -- elongated
    along one axis, so it reads as painted strokes / rain-worn drips)."""
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


def wavy_lines(shape: Shape, seed: int, n_lines: int, width: float, wobble: float, wobble_sigma: float = 140.0) -> np.ndarray:
    """`n_lines` horizontal-ish wavy grooves at even vertical spacing,
    each independently wobbling in x -- used for tire ruts."""
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
    `.orchestrator/design.md` section 6 (painted texture library) and
    section 7 (map palettes) hex values exactly, so the generator's output
    stays traceable back to the locked design doc."""
    h = h.lstrip("#")
    return np.array([int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)])


def to_png(arr01: np.ndarray, path: Path) -> None:
    arr = np.clip(arr01, 0.0, 1.0)
    img = (arr * 255.0 + 0.5).astype(np.uint8)
    path.parent.mkdir(parents=True, exist_ok=True)
    if img.ndim == 2:
        Image.fromarray(img, mode="L").save(path)
    else:
        Image.fromarray(img, mode="RGB").save(path)
    print(f"  wrote {path.relative_to(REPO_ROOT)}  {img.shape[1]}x{img.shape[0]}")


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
    (no editor GUI) still gets sane defaults for a *repeating 3D world
    texture*: mipmaps generated (so triplanar sampling at distance doesn't
    alias/shimmer) and lossless compression (no VRAM-compressor dependency,
    deterministic bytes for CI). sRGB decoding is NOT set here: it comes
    from the `source_color` hint on the shader's sampler uniform instead,
    which is the Godot 4 way to mark a *specific sampler* as sRGB regardless
    of how the texture resource itself was imported. `uid` is intentionally
    omitted -- Godot assigns and persists one on the next `--import` pass.
    """
    res_path = png_path.relative_to(REPO_ROOT).as_posix()
    stem = png_path.stem
    fake_md5 = "0" * 32  # placeholder; Godot rewrites dest_files with the real hash on import.
    content = IMPORT_TEMPLATE.format(res_path=res_path, stem=stem, ext="png", fake_md5=fake_md5)
    import_path = png_path.with_suffix(png_path.suffix + ".import")
    import_path.write_text(content, encoding="utf-8", newline="\n")


# --------------------------------------------------------------------------- materials

def mat_painted_metal(seed: int = 101) -> np.ndarray:
    """Painted hull steel -- design.md SS6 "Coque" #A13326/#22262B: a dark
    near-black steel plate scarred by rust-red paint patches, riveted seam
    grid in dark warm ink."""
    shape = (SIZE, SIZE)
    paint_c = hexc("#A13326")
    steel_c = hexc("#22262B")
    wear_c = hexc("#E08A3C")  # Rouille "edges" -- bright oxidation halo around a chip
    color = fill(shape, paint_c)
    color = mul_value(color, fbm(shape, seed, base_sigma=140), 0.86, 1.12)
    strokes = streaks(shape, seed + 2, base_sigma=90, stretch=5.0, vertical=True)
    color = mul_value(color, strokes, 0.9, 1.08)
    chip = np.clip((fbm(shape, seed + 3, base_sigma=55) - 0.66) / 0.14, 0.0, 1.0) ** 1.4
    color = lerp3(color, fill(shape, steel_c), chip)
    halo = np.clip(chip * 1.8, 0.0, 1.0) - chip  # thin ring just outside each chip
    color = lerp3(color, fill(shape, wear_c), np.clip(halo, 0.0, 1.0))
    seam = np.clip(creases(shape, seed + 10, nx=5, ny=0, width=0.028, warp_strength=0.12) +
                    creases(shape, seed + 11, nx=0, ny=3, width=0.028, warp_strength=0.12), 0.0, 1.0)
    ink = np.array([0.10, 0.065, 0.045])
    color = lerp3(color, fill(shape, ink), seam * 0.8)
    color = np.clip(color + (grain(shape, seed + 20, 1.0) - 0.5)[..., None] * 0.05, 0.0, 1.0)
    return color


def mat_rust(seed: int = 102) -> np.ndarray:
    """Streaked oxidation: warm orange -> dark umber, drip streaks, sparse
    ink crackle."""
    shape = (SIZE, SIZE)
    orange = hexc("#B5562A")  # Rouille
    umber = orange * 0.52
    bright = hexc("#E08A3C")  # Rouille "edges"
    base = fbm(shape, seed, octaves=5, base_sigma=100)
    color = lerp3(fill(shape, orange), fill(shape, umber), base)
    drip = streaks(shape, seed + 1, base_sigma=70, stretch=6.0, vertical=True)
    color = lerp3(color, fill(shape, bright), np.clip(drip - 0.55, 0, 1) * 2.0 * (1 - base))
    color = lerp3(color, fill(shape, umber), np.clip(drip * 0.4 - base * 0.5, 0, 1))
    crackle = creases(shape, seed + 12, nx=9, ny=7, width=0.02, warp_strength=0.28, warp_sigma=40)
    ink = np.array([0.12, 0.06, 0.035])
    color = lerp3(color, fill(shape, ink), crackle * blotches(shape, seed + 13, coverage=0.4, base_sigma=140) * 0.6)
    color = np.clip(color + (grain(shape, seed + 20, 1.0) - 0.5)[..., None] * 0.05, 0.0, 1.0)
    return color


def mat_corrugated_metal(seed: int = 103) -> np.ndarray:
    """Painted corrugated sheet: cosine ribs with baked shading, streaked
    paint, rust bleed at troughs."""
    shape = (SIZE, SIZE)
    h, w = shape
    yy, xx = np.mgrid[0:h, 0:w]
    n_ribs = 24
    phase = 2.0 * np.pi * xx * n_ribs / w
    rib_shade = 0.5 + 0.5 * np.cos(phase - 0.6)  # baked "lit from upper-left" shading
    base = hexc("#4F7FA8")  # Tole
    wear_c = hexc("#E9DDBF")  # Tole wear/highlight -- cream paint chipping through
    color = fill(shape, base)
    color = mul_value(color, rib_shade, 0.62, 1.18)
    color = mul_value(color, fbm(shape, seed, base_sigma=160), 0.9, 1.08)
    strokes = streaks(shape, seed + 2, base_sigma=60, stretch=8.0, vertical=True)
    color = mul_value(color, strokes, 0.92, 1.05)
    chip = np.clip((fbm(shape, seed + 4, base_sigma=50) - 0.58) / 0.16, 0.0, 1.0) * np.clip(rib_shade * 1.4, 0, 1)
    color = lerp3(color, fill(shape, wear_c), np.clip(chip * 1.15, 0.0, 1.0))
    trough = np.clip(np.cos(phase) * -1.0, 0.0, 1.0)  # troughs = where rust collects
    rust_bleed = trough * np.clip(fbm(shape, seed + 4, base_sigma=50) - 0.35, 0, 1) * 1.6
    rust_c = hexc("#B5562A")  # Rouille bleed at the troughs
    color = lerp3(color, fill(shape, rust_c), np.clip(rust_bleed, 0, 1))
    # Stronger plate-seam ink (lead review: rib boundaries need to read
    # clearly so props don't look like flat painted boxes).
    seam = creases(shape, seed + 11, nx=0, ny=4, width=0.028, warp_strength=0.1)
    ink = np.array([0.07, 0.045, 0.03])
    color = lerp3(color, fill(shape, ink), np.clip(seam * 0.95, 0.0, 1.0))
    color = np.clip(color + (grain(shape, seed + 20, 1.0) - 0.5)[..., None] * 0.045, 0.0, 1.0)
    return color


def mat_container_paint(seed: int = 104) -> np.ndarray:
    """Near-neutral, TINT-ABLE base (multiplied by `Cartoon.painted()`'s
    tint in-shader) with corrugated rib shading baked and light grime, so
    the same texture works for red/blue/orange/white shipping containers.

    Fixed after a lead review of the cargo_ship target render: `n_ribs` was
    20 per 3 m triplanar tile (a rib every ~15 cm) -- far finer than a real
    ISO container's corrugation (~1 rib per 25-30 cm), so it read as a
    blurry smear rather than individual ribs. Halved the rib count and
    sharpened the shading contrast so each rib reads as a distinct panel;
    added rust drip streaks from the top edge and a few small stencil-mark
    blotches (a tiling texture can't place a literal door or corner casting
    at a fixed spot on every box size, but ribs/rust/stencils read correctly
    at any scale)."""
    shape = (SIZE, SIZE)
    h, w = shape
    yy, xx = np.mgrid[0:h, 0:w]
    n_ribs = 9
    phase = 2.0 * np.pi * xx * n_ribs / w
    rib_shade = 0.5 + 0.5 * np.cos(phase - 0.5)
    base_v = 0.74
    color = fill(shape, (base_v, base_v, base_v))
    color = mul_value(color, rib_shade, 0.60, 1.22)
    color = mul_value(color, fbm(shape, seed, base_sigma=180), 0.92, 1.06)
    strokes = streaks(shape, seed + 2, base_sigma=70, stretch=6.0, vertical=True)
    color = mul_value(color, strokes, 0.95, 1.04)
    grime_m = blotches(shape, seed + 5, coverage=0.16, softness=0.14, base_sigma=110)
    color = mul_value(color, 1.0 - grime_m, 0.78, 1.0)
    plate_seam = creases(shape, seed + 11, nx=0, ny=5, width=0.018, warp_strength=0.08) * 0.5 + \
        creases(shape, seed + 12, nx=8, ny=0, width=0.015, warp_strength=0.08) * 0.5
    color = mul_value(color, 1.0 - np.clip(plate_seam, 0, 1), 0.55, 1.0)
    # Rust drips: streaks biased to originate near the top of the tile
    # (yy small) and fade downward, confined mostly to rib troughs.
    drip_noise = streaks(shape, seed + 7, base_sigma=35, stretch=9.0, vertical=True)
    top_bias = np.clip(1.0 - yy / (h * 0.85), 0.0, 1.0) ** 0.6
    drip = np.clip(drip_noise - 0.62, 0.0, 1.0) * 2.6 * top_bias * np.clip(1.0 - rib_shade * 1.3, 0.0, 1.0)
    rust_c = hexc("#8A4A28")
    color = lerp3(color, fill(shape, rust_c), np.clip(drip, 0.0, 0.85))
    # A handful of small dark "stencil mark" blotches -- sparse, low
    # coverage, irregular placement (not a repeating grid, so it doesn't
    # read as an obvious tiling artifact at typical container scale).
    stencil = blotches(shape, seed + 17, coverage=0.035, softness=0.02, base_sigma=14)
    ink_c = np.array([0.08, 0.07, 0.065])
    color = lerp3(color, fill(shape, ink_c), stencil * 0.7)
    color = np.clip(color + (grain(shape, seed + 20, 1.0) - 0.5)[..., None] * 0.035, 0.0, 1.0)
    return color


def mat_wood_planks(seed: int = 105) -> np.ndarray:
    """Weathered wood planks, warm brown grain, ink seams between boards."""
    shape = (SIZE, SIZE)
    h, w = shape
    yy, xx = np.mgrid[0:h, 0:w]
    n_planks = 8
    plank_id = np.floor(yy * n_planks / h)
    rng = _rng(seed)
    plank_tint = rng.uniform(-0.06, 0.06, size=int(n_planks) + 1)
    tint_field = plank_tint[plank_id.astype(int) % plank_tint.size]
    base = hexc("#9C6A42")  # Bois
    edge_c = hexc("#C99A68")  # Bois "edges" -- sun-bleached plank edge highlight
    color = fill(shape, base)
    grainy = fbm(shape, seed, octaves=5, base_sigma=45, aniso=(6.0, 1.0))
    color = mul_value(color, grainy, 0.78, 1.18)
    color = color + tint_field[..., None] * 0.5
    knot = blotches(shape, seed + 6, coverage=0.05, softness=0.05, base_sigma=90)
    knot_c = base * 0.5
    color = lerp3(color, fill(shape, knot_c), knot)
    # Stronger, darker plank-boundary ink (lead review: props read as flat
    # boxes without a clearer seam/wear break at each plank edge).
    seams = creases(shape, seed + 11, nx=0, ny=n_planks, width=0.017, warp_strength=0.045, warp_sigma=30)
    ink = np.array([0.055, 0.032, 0.020])
    color = lerp3(color, fill(shape, ink), np.clip(seams * 1.1, 0.0, 1.0))
    # Wear: convex edges lighter (design.md SS6) -- each plank's long edges pick
    # up the "Bois edges" highlight instead of just darkening. Widened/
    # stronger so the plank break reads clearly at prop distance.
    edge_wear = np.clip(1.0 - np.abs(np.sin(np.pi * yy * n_planks / h)) / 0.22, 0.0, 1.0) * 0.5
    color = lerp3(color, fill(shape, edge_c), edge_wear)
    color = np.clip(color + (grain(shape, seed + 20, 0.8) - 0.5)[..., None] * 0.04, 0.0, 1.0)
    return color


def mat_sand_dirt(seed: int = 106) -> np.ndarray:
    """Desert sand/dirt with tire ruts. Reworked after a lead review of the
    wasteland target render ("flat orange reads like plastic"): a tighter,
    less saturated ochre base (#B8864E-#D1A067, per the reference) instead
    of the more saturated raw "Sable" hex; a large-scale (multi-metre) value
    layer so the ground reads as uneven packed earth rather than a flat
    tint; thin wind-ripple striations; darker ruts; denser, more varied
    pebbles."""
    shape = (SIZE, SIZE)
    tan_a = hexc("#D1A067")
    tan_b = hexc("#B8864E")
    color = lerp3(fill(shape, tan_a), fill(shape, tan_b), fbm(shape, seed, octaves=5, base_sigma=90))
    # Large-scale value variation -- broad lighter/darker patches (sun-baked
    # crust vs. shadowed packed earth), on top of the fine grain below.
    large_scale = fbm(shape, seed + 30, octaves=3, persistence=0.6, base_sigma=340)
    color = mul_value(color, large_scale, 0.72, 1.20)
    color = mul_value(color, fbm(shape, seed + 1, octaves=4, base_sigma=30), 0.88, 1.1)
    # Wind ripples: many thin, low-contrast wavy striations (not ruts).
    ripples = creases(shape, seed + 40, nx=0, ny=48, width=0.05, warp_strength=0.06, warp_sigma=20)
    color = mul_value(color, 1.0 - ripples, 0.9, 1.0)
    ruts = wavy_lines(shape, seed + 7, n_lines=2, width=0.022, wobble=26.0)
    rut_c = tan_b * 0.55
    color = lerp3(color, fill(shape, rut_c), ruts * 0.75)
    pebble_lg = blotches(shape, seed + 9, coverage=0.09, softness=0.05, base_sigma=9)
    pebble_sm = blotches(shape, seed + 19, coverage=0.14, softness=0.04, base_sigma=4)
    pebble_c = hexc("#8F6A42")
    color = lerp3(color, fill(shape, pebble_c), np.clip(pebble_lg * 0.6 + pebble_sm * 0.4, 0, 1) * 0.55)
    color = np.clip(color + (grain(shape, seed + 20, 1.2) - 0.5)[..., None] * 0.045, 0.0, 1.0)
    return color


def mat_cracked_concrete(seed: int = 107) -> np.ndarray:
    """Pale warm concrete (design.md SS6 "Beton"), stains, thin ink crack
    lines."""
    shape = (SIZE, SIZE)
    base = hexc("#B8AFA0")  # Beton
    color = fill(shape, base)
    color = mul_value(color, fbm(shape, seed, octaves=5, base_sigma=130), 0.88, 1.1)
    stain = blotches(shape, seed + 4, coverage=0.22, softness=0.18, base_sigma=160)
    stain_c = np.array([0.50, 0.47, 0.40])
    color = lerp3(color, fill(shape, stain_c), stain * 0.5)
    crack_a = creases(shape, seed + 11, nx=5, ny=3, width=0.012, warp_strength=0.32, warp_sigma=50)
    crack_b = creases(shape, seed + 12, nx=3, ny=6, width=0.010, warp_strength=0.28, warp_sigma=45)
    crack = np.clip(crack_a + crack_b, 0.0, 1.0) * blotches(shape, seed + 13, coverage=0.5, base_sigma=200)
    ink = np.array([0.14, 0.12, 0.10])
    color = lerp3(color, fill(shape, ink), crack * 0.85)
    color = np.clip(color + (grain(shape, seed + 20, 1.0) - 0.5)[..., None] * 0.04, 0.0, 1.0)
    return color


def mat_asphalt(seed: int = 108) -> np.ndarray:
    """Speckled asphalt with sparse sun-bleached patches and a branching
    hairline crack network (two crossing crease families, like
    cracked_concrete)."""
    shape = (SIZE, SIZE)
    base = np.array([0.19, 0.185, 0.20])
    color = fill(shape, base)
    speck = fbm(shape, seed, octaves=6, persistence=0.6, base_sigma=3)
    color = mul_value(color, speck, 0.72, 1.4)
    color = mul_value(color, fbm(shape, seed + 1, octaves=4, base_sigma=110), 0.85, 1.15)
    worn = blotches(shape, seed + 3, coverage=0.16, softness=0.12, base_sigma=140)
    worn_c = np.array([0.30, 0.29, 0.27])
    color = lerp3(color, fill(shape, worn_c), worn * 0.55)
    crack_a = creases(shape, seed + 11, nx=4, ny=5, width=0.01, warp_strength=0.3, warp_sigma=45)
    crack_b = creases(shape, seed + 12, nx=5, ny=3, width=0.009, warp_strength=0.3, warp_sigma=40)
    crack = np.clip(crack_a + crack_b, 0.0, 1.0) * blotches(shape, seed + 13, coverage=0.45, base_sigma=180)
    ink = np.array([0.05, 0.05, 0.055])
    color = lerp3(color, fill(shape, ink), crack * 0.65)
    color = np.clip(color + (grain(shape, seed + 20, 1.0) - 0.5)[..., None] * 0.035, 0.0, 1.0)
    return color


def mat_ship_deck(seed: int = 109) -> np.ndarray:
    """Painted steel deck. Lightened/warmed from design.md's raw SS6 "Pont"
    #8D959B (a lead review of the cargo_ship target render found it reading
    as distinctly BLUE once the scene's blue-violet shadow tint multiplied
    over it -- #8D959B's own chroma is low enough that the shadow tint
    dominated its hue). A lighter, warmer grey holds its own neutral-warm
    read even under that tint. Hazard-yellow stripes now run at every seam
    (was 1-in-4, too sparse to read), plus rust streaks bleeding from the
    seams and rivet lines (Cargo Ship ref)."""
    shape = (SIZE, SIZE)
    base = hexc("#A6A08C")  # lighter, warmer than raw "Pont"
    color = fill(shape, base)
    color = mul_value(color, fbm(shape, seed, octaves=5, base_sigma=150), 0.88, 1.1)
    strokes = streaks(shape, seed + 2, base_sigma=100, stretch=5.0, vertical=False)
    color = mul_value(color, strokes, 0.92, 1.06)
    plate_seam = creases(shape, seed + 11, nx=0, ny=4, width=0.02, warp_strength=0.08)
    ink = np.array([0.09, 0.065, 0.05])
    color = lerp3(color, fill(shape, ink), plate_seam * 0.75)
    # Hazard stripe at EVERY seam now (design.md ref: yellow/black safety
    # striping reads clearly along hatch/seam edges, not just occasionally).
    hazard_band = creases(shape, seed + 11, nx=0, ny=4, width=0.016, warp_strength=0.08)
    tick = (np.floor(np.mgrid[0:shape[0], 0:shape[1]][1] / 22) % 2 == 0).astype(np.float64)
    hazard_c = lerp3(fill(shape, hexc("#F2B51D")), fill(shape, hexc("#2A2622")), tick)
    color = lerp3(color, hazard_c, np.clip(hazard_band, 0, 1) * 0.9)
    # Rust streaks bleeding down from the seams.
    rust_drip = streaks(shape, seed + 6, base_sigma=30, stretch=10.0, vertical=True)
    rust_mask = np.clip(rust_drip - 0.6, 0.0, 1.0) * 2.2 * np.clip(plate_seam * 1.6, 0.0, 1.0)
    color = lerp3(color, fill(shape, hexc("#8A4A28")), np.clip(rust_mask, 0.0, 0.7))
    rivets = rivet_grid(shape, seed + 15, nx=16, ny=4, radius=0.18)
    seam_band = creases(shape, seed + 11, nx=0, ny=4, width=0.06, warp_strength=0.08)  # wider band to host rivets
    rivet_c = base * 1.12
    color = lerp3(color, fill(shape, rivet_c), np.clip(rivets, 0, 1) * seam_band * 0.9)
    wear = np.clip((fbm(shape, seed + 3, base_sigma=45) - 0.62) / 0.14, 0, 1) ** 1.3
    wear_c = base * 1.3
    color = lerp3(color, fill(shape, wear_c), wear * 0.6)
    color = np.clip(color + (grain(shape, seed + 20, 1.0) - 0.5)[..., None] * 0.045, 0.0, 1.0)
    return color


def mat_rubber_tire(seed: int = 110) -> np.ndarray:
    """Near-black rubber (design.md SS6 "Pneus" #2B2724) with a diamond
    tread pattern."""
    shape = (SIZE, SIZE)
    base = hexc("#2B2724")  # Pneus
    color = fill(shape, base)
    color = mul_value(color, fbm(shape, seed, octaves=4, base_sigma=25), 0.85, 1.25)
    tread_a = creases(shape, seed + 11, nx=10, ny=10, width=0.05, warp_strength=0.03, warp_sigma=25)
    tread_b = creases(shape, seed + 12, nx=10, ny=-10, width=0.05, warp_strength=0.03, warp_sigma=25)
    tread = np.clip(tread_a + tread_b, 0.0, 1.0)
    tread_c = base * 0.4
    color = lerp3(color, fill(shape, tread_c), tread * 0.7)
    color = np.clip(color + (grain(shape, seed + 20, 1.0) - 0.5)[..., None] * 0.03, 0.0, 1.0)
    return color


def mat_dirty_glass(seed: int = 111) -> np.ndarray:
    """Stylised, opaque-painted "dirty glass" (design.md SS6 "Vitres"
    #3C5A6E) -- a soft diagonal highlight band, grime drips."""
    shape = (SIZE, SIZE)
    h, w = shape
    yy, xx = np.mgrid[0:h, 0:w]
    base = hexc("#3C5A6E")  # Vitres
    color = fill(shape, base)
    diag = (xx + yy) / (w + h)
    highlight = np.clip(1.0 - np.abs((diag % 0.5) - 0.25) / 0.06, 0.0, 1.0) * 0.35
    color = np.clip(color + highlight[..., None], 0.0, 1.0)
    drip = streaks(shape, seed + 1, base_sigma=60, stretch=7.0, vertical=True)
    grime_c = np.array([0.30, 0.33, 0.32])
    color = lerp3(color, fill(shape, grime_c), np.clip(drip - 0.55, 0, 1) * 1.6)
    color = mul_value(color, fbm(shape, seed, octaves=4, base_sigma=100), 0.92, 1.05)
    color = np.clip(color + (grain(shape, seed + 20, 1.0) - 0.5)[..., None] * 0.02, 0.0, 1.0)
    return color


# --------------------------------------------------------------------------- grime/detail masks (512^2, grayscale)

def grime_generic(seed: int, blotch_coverage: float = 0.3, streak_stretch: float = 6.0) -> np.ndarray:
    shape = (DETAIL_SIZE, DETAIL_SIZE)
    b = blotches(shape, seed, coverage=blotch_coverage, softness=0.15, base_sigma=90)
    s = streaks(shape, seed + 1, base_sigma=40, stretch=streak_stretch, vertical=True)
    drip = np.clip(s - 0.6, 0, 1) * 2.0
    mask = np.clip(np.maximum(b * 0.8, drip), 0.0, 1.0)
    mask = mask * (0.7 + 0.3 * fbm(shape, seed + 2, octaves=3, base_sigma=6))
    return np.clip(mask, 0.0, 1.0)


# --------------------------------------------------------------------------- registry

MATERIALS: dict[str, dict] = {
    "painted_metal": {"albedo": mat_painted_metal, "grime_seed": 901},
    "rust": {"albedo": mat_rust, "grime_seed": None},
    "corrugated_metal": {"albedo": mat_corrugated_metal, "grime_seed": 902},
    "container_paint": {"albedo": mat_container_paint, "grime_seed": 903},
    "wood_planks": {"albedo": mat_wood_planks, "grime_seed": 904},
    "sand_dirt": {"albedo": mat_sand_dirt, "grime_seed": None},
    "cracked_concrete": {"albedo": mat_cracked_concrete, "grime_seed": 905},
    "asphalt": {"albedo": mat_asphalt, "grime_seed": None},
    "ship_deck": {"albedo": mat_ship_deck, "grime_seed": 906},
    "rubber_tire": {"albedo": mat_rubber_tire, "grime_seed": None},
    "dirty_glass": {"albedo": mat_dirty_glass, "grime_seed": None},
}


def main() -> int:
    print(f"Generating painted textures -> {OUT_DIR.relative_to(REPO_ROOT)}")
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for name, spec in MATERIALS.items():
        print(f"[{name}]")
        albedo = spec["albedo"]()
        albedo_path = OUT_DIR / f"{name}_albedo.png"
        to_png(albedo, albedo_path)
        write_import(albedo_path)
        grime_seed = spec["grime_seed"]
        if grime_seed is not None:
            mask = grime_generic(grime_seed)
            grime_path = OUT_DIR / f"{name}_grime.png"
            to_png(mask, grime_path)
            write_import(grime_path)
    print("Done.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
