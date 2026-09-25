#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""tools/textures/tests/test_make_signs.py

Tests pytest de tools/textures/make_signs.py (ART-92, plan SS5 « enseignes »).
Aucune dependance a Godot/Blender (pur PIL/numpy) : ce fichier importe le
module directement, comme tools/textures/tests/test_make_tileable.py importe
gen_textures.py. `OUT_DIR`/`FONT_PATH` restent les vrais chemins du depot
(la police Bangers-Regular.ttf existe reellement dans resources/fonts/, et
ce module ecrit dans assets/textures/wasteland/signs/ -- la meme sortie
qu'un lancement normal du script, contrairement a make_tileable.py qui
monkeypatche vers un faux depot : ici il n'y a ni source Tripo ni risque
d'ecraser un fichier peint a la main, juste une regeneration deterministe
d'un atlas procedural, donc un vrai chemin de sortie est sans risque et
verifie en plus que `.import`/`manifest.json` atterrissent au bon endroit).

Lancer :
    python -m pytest tools/textures/tests/test_make_signs.py -q
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

import pytest

TOOLS_TEXTURES = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS_TEXTURES))

import make_signs as ms  # noqa: E402


@pytest.fixture(scope="module")
def built():
    """Construit l'atlas UNE fois pour tout le module (le rendu PIL de 13
    panneaux prend quelques secondes) et renvoie son resultat."""
    return ms.build_atlas()


def test_font_file_exists():
    """SS5 : « police resources/fonts/Bangers-Regular.ttf »."""
    assert ms.FONT_PATH.is_file(), f"police introuvable : {ms.FONT_PATH}"


def test_thirteen_panels_listed():
    """SS5 enumere 13 enseignes (FUEL et GAS comptent double dans la liste,
    voir le commentaire de SIGN_PANELS) -- jamais reduit a 12 en supprimant
    FUEL ou GAS, qui porte a lui seul le zonage ouest-froid/est-chaud
    repete dans tout le document (SS2 R8, SS8)."""
    assert len(ms.SIGN_PANELS) == 13
    ids = [p[0] for p in ms.SIGN_PANELS]
    assert len(ids) == len(set(ids)), "identifiants de panneau dupliques"
    assert "fuel" in ids and "gas" in ids


def test_atlas_written_with_import_sidecar_and_manifest(built):
    assert Path(built["atlas_path"]).is_file()
    assert Path(built["atlas_path"] + ".import").is_file()
    assert Path(built["manifest_path"]).is_file()


def test_atlas_dimensions_match_grid(built):
    from PIL import Image
    img = Image.open(built["atlas_path"])
    manifest = built["manifest"]
    assert img.size == (ms.PANEL_W * manifest["cols"], ms.PANEL_H * manifest["rows"])


def test_manifest_has_one_entry_per_panel_with_valid_rect(built):
    manifest = built["manifest"]
    assert len(manifest["panels"]) == len(ms.SIGN_PANELS)
    atlas_w = ms.PANEL_W * manifest["cols"]
    atlas_h = ms.PANEL_H * manifest["rows"]
    for panel_id, text, team in ms.SIGN_PANELS:
        entry = manifest["panels"][panel_id]
        assert entry["text"] == text, panel_id
        assert entry["team"] == team, panel_id
        x0, y0, w, h = entry["rect_px"]
        assert w == ms.PANEL_W and h == ms.PANEL_H, panel_id
        assert 0 <= x0 <= atlas_w - w, panel_id
        assert 0 <= y0 <= atlas_h - h, panel_id


def test_manifest_json_is_valid_utf8_with_accents(built):
    """Les noms peints portent des accents (« HÔTEL », « ÉPICERIE ») --
    verifie que le JSON les garde tels quels (`ensure_ascii=False`), pas
    echappes en `\\uXXXX` ni corrompus."""
    raw = Path(built["manifest_path"]).read_text(encoding="utf-8")
    data = json.loads(raw)
    assert data["panels"]["hotel"]["text"] == "HÔTEL"
    assert "É" in data["panels"]["epicerie"]["text"]


def test_reserved_hue_check_passes_on_full_atlas(built):
    """docs/STYLE_BIBLE.md : teintes 300-355 deg et 105-145 deg interdites
    dans le decor (reservees a la surbrillance ennemie) -- verifie sur
    l'atlas REELLEMENT ecrit, pas juste sur les couleurs nominales de la
    palette."""
    from PIL import Image
    img = Image.open(built["atlas_path"])
    ok, detail = ms.check_reserved_hue(img)
    assert ok, detail


def test_team_colors_are_not_reserved_hues():
    """Sonde direte des 3 teintes d'equipe (SS8) : aucune ne tombe dans une
    bande reservee, independamment de tout rendu de panneau."""
    import numpy as np
    for name in ("west_blue", "east_red", "neutral_cream"):
        rgb = np.array(ms._hex_rgb(ms.palette(name)), dtype=np.float64).reshape(1, 1, 3) / 255.0
        hue = float(ms._rgb_to_hue_deg(rgb)[0, 0])
        for lo, hi in ms.RESERVED_HUE_RANGES:
            assert not (lo <= hue <= hi), f"{name} (hue={hue:.1f}) tombe dans la bande reservee [{lo},{hi}]"


def test_west_and_east_signs_use_distinct_team_colors():
    """Zonage SS8 : ouest froid (bleu), est chaud (rouge) -- jamais la meme
    teinte des deux cotes d'un meme batiment mirroir (Forge/Marechal,
    Hotel/Banque, ...)."""
    by_id = {p[0]: p for p in ms.SIGN_PANELS}
    pairs = [("forge", "marechal"), ("hotel", "banque"), ("magasin", "epicerie"),
        ("echoppes", "bazar"), ("saloon_bleu", "saloon_rouge"), ("fuel", "gas")]
    for west_id, east_id in pairs:
        assert by_id[west_id][2] == "west"
        assert by_id[east_id][2] == "east"


def test_regeneration_is_deterministic(built, tmp_path, monkeypatch):
    """Seeds fixes (contrat ART-92 : « pur PIL/numpy, seeds fixes,
    reproductible bit a bit ») -- deux rendus du MEME panneau (memes
    arguments) doivent produire des pixels identiques."""
    import numpy as np
    a = ms.paint_panel("hotel", "HÔTEL", "west", seed=1002)
    b = ms.paint_panel("hotel", "HÔTEL", "west", seed=1002)
    assert np.array_equal(np.asarray(a), np.asarray(b))


if __name__ == "__main__":
    import pytest as _pytest
    raise SystemExit(_pytest.main([__file__, "-q"]))
