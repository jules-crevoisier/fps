"""Peinture de texture par script : rastérisation des triangles UV d'un maillage Blender.

Pour chaque texel couvert, on récupère la position 3D (et tout attribut par sommet,
interpolé en barycentrique) et une valeur par face (partie, zone...). Les scripts de
texture posent ensuite leurs aplats, leurs bandes et leur encre texel par texel, avec
des bords nets indépendants de la résolution du maillage.
Utilisé par art/utilities/grenades/texture_grenades.py et art/weapons/revolver/.
Convention des pixels Blender : origine en bas à gauche, ligne = v, colonne = u.
"""
import numpy as np


def rasterize(me, res, face_values, vert_attrs=None):
    """Rastérise les triangles UV de `me` sur une grille res x res.

    `face_values` : valeur entière par polygone (partie, zone...).
    `vert_attrs` : tableau (nb_sommets, k) optionnel, interpolé par texel.
    Renvoie (pos (res,res,3), fid (res,res) int32 = -1 hors îles, attrs (res,res,k) ou None).
    Deux passes : l'intérieur exact des triangles l'emporte sur la marge conservatrice
    (0,75 px, pour couvrir les coutures)."""
    me.calc_loop_triangles()
    uv = np.empty(len(me.loops) * 2, np.float32)
    me.uv_layers.active.data.foreach_get("uv", uv)
    uv = uv.reshape(-1, 2) * res
    co = np.empty(len(me.vertices) * 3, np.float32)
    me.vertices.foreach_get("co", co)
    co = co.reshape(-1, 3)
    extra = None if vert_attrs is None else np.asarray(vert_attrs, np.float32).reshape(len(me.vertices), -1)
    pos = np.zeros((res, res, 3), np.float32)
    fid = np.full((res, res), -1, np.int32)
    attrs = None if extra is None else np.zeros((res, res, extra.shape[1]), np.float32)
    exact = np.zeros((res, res), bool)
    for t in me.loop_triangles:
        p = uv[list(t.loops)]
        a, b, c = p
        area = (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])
        if abs(area) < 1e-9:
            continue
        x0, y0 = np.maximum(np.floor(p.min(0) - 1).astype(int), 0)
        x1 = min(int(np.ceil(p[:, 0].max() + 1)), res - 1)
        y1 = min(int(np.ceil(p[:, 1].max() + 1)), res - 1)
        if x1 < x0 or y1 < y0:
            continue
        xs, ys = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
        w = []
        dist = []
        for e0, e1 in ((b, c), (c, a), (a, b)):
            cross = (e1[0] - e0[0]) * (ys - e0[1]) - (e1[1] - e0[1]) * (xs - e0[0])
            w.append(cross / area)
            dist.append(cross * np.sign(area) / max(np.hypot(*(e1 - e0)), 1e-9))
        w = np.stack(w, -1)
        inside = np.all(np.stack(dist) >= 0.0, 0)
        near = np.all(np.stack(dist) >= -0.75, 0)
        wc = np.clip(w, 0.0, None)
        wc /= np.maximum(wc.sum(-1, keepdims=True), 1e-9)
        verts = list(t.vertices)
        sl = (slice(y0, y1 + 1), slice(x0, x1 + 1))
        write = inside | (near & ~exact[sl])
        pos[sl][write] = (wc @ co[verts])[write]
        fid[sl][write] = face_values[t.polygon_index]
        if attrs is not None:
            attrs[sl][write] = (wc @ extra[verts])[write]
        exact[sl] |= inside
    return pos, fid, attrs


def box_blur(a, r=1):
    out = np.zeros_like(a)
    for dy in range(-r, r + 1):
        for dx in range(-r, r + 1):
            out += np.roll(a, (dy, dx), axis=(0, 1))
    return out / float((2 * r + 1) ** 2)


def smoothstep(e0, e1, x):
    u = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return u * u * (3.0 - 2.0 * u)


def zone_edges(zid, cover):
    """Texels couverts dont un voisin (4-voisinage) couvert porte une autre zone."""
    edge = np.zeros(zid.shape, bool)
    for dy, dx in ((0, 1), (0, -1), (1, 0), (-1, 0)):
        nz = np.roll(zid, (dy, dx), axis=(0, 1))
        edge |= cover & (nz >= 0) & (nz != zid)
    return edge
