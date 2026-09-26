"""Masque de couverture UV et débordement (« edge padding ») de texture, en numpy.

Utilisé à l'export des modèles peints : sans débordement, le fond de l'image autour des
îles UV bave sur les coutures dès que les mipmaps entrent en jeu (liserés clairs ou
sombres le long des coutures, surtout de loin).
Convention des pixels Blender : origine en bas à gauche, ligne = v, colonne = u.
"""
import numpy as np


def uv_coverage(mesh_data, width: int, height: int, margin_px: float = 0.75) -> np.ndarray:
    """Pixels (h, w) couverts par au moins un triangle UV, rasterisation conservatrice."""
    mesh_data.calc_loop_triangles()
    uv = mesh_data.uv_layers.active.data
    mask = np.zeros((height, width), bool)
    scale = np.array([width, height], float)
    for t in mesh_data.loop_triangles:
        p = np.array([uv[i].uv[:] for i in t.loops]) * scale
        a, b, c = p
        area = (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])
        if abs(area) < 1e-12:
            continue
        s = 1.0 if area > 0 else -1.0
        x0, y0 = np.maximum(np.floor(p.min(0) - 1).astype(int), 0)
        x1 = min(int(np.ceil(p[:, 0].max() + 1)), width - 1)
        y1 = min(int(np.ceil(p[:, 1].max() + 1)), height - 1)
        if x1 < x0 or y1 < y0:
            continue
        xs, ys = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
        inside = np.ones(xs.shape, bool)
        for e0, e1 in ((a, b), (b, c), (c, a)):
            d = e1 - e0
            n = np.hypot(d[0], d[1])
            if n < 1e-12:
                continue
            inside &= s * (d[0] * (ys - e0[1]) - d[1] * (xs - e0[0])) / n >= -margin_px
        mask[y0:y1 + 1, x0:x1 + 1] |= inside
    return mask


def erode(mask: np.ndarray, px: int) -> np.ndarray:
    """Retire `px` pixels au bord de chaque zone du masque (voisinage 4)."""
    out = mask.copy()
    for _ in range(px):
        for dy, dx in ((0, 1), (0, -1), (1, 0), (-1, 0)):
            out &= np.roll(mask if _ == 0 else out, (dy, dx), axis=(0, 1))
    return out


def unpainted_rim(pixels: np.ndarray, mask: np.ndarray, background, rim_px: int = 3,
                  tol: float = 0.02) -> np.ndarray:
    """Pixels couverts, à `rim_px` du bord d'une île, restés de la couleur du fond.

    Le pot de peinture s'arrête souvent juste avant le bord (anticrénelage) : ces pixels
    doivent être repeints par le débordement, pas propagés vers l'extérieur.
    """
    bg = np.asarray(background, np.float32)[: pixels.shape[2]]
    is_bg = np.all(np.abs(pixels - bg) <= tol, axis=2)
    return mask & ~erode(mask, rim_px) & is_bg


def pad_edges(pixels: np.ndarray, mask: np.ndarray, iterations: int = 8) -> np.ndarray:
    """Étend la couleur des pixels couverts sur le fond voisin, `iterations` px au plus.

    `pixels` : (h, w, c). Les pixels couverts ne changent jamais.
    """
    out = pixels.copy()
    filled = mask.copy()
    for _ in range(iterations):
        acc = np.zeros(out.shape, np.float64)
        cnt = np.zeros(mask.shape, np.float64)
        for dy, dx in ((0, 1), (0, -1), (1, 0), (-1, 0)):
            src_f = np.roll(filled, (dy, dx), axis=(0, 1))
            src_p = np.roll(out, (dy, dx), axis=(0, 1))
            acc += src_p * src_f[..., None]
            cnt += src_f
        grow = (~filled) & (cnt > 0)
        out[grow] = (acc[grow] / cnt[grow][:, None]).astype(out.dtype)
        filled |= grow
    return out
