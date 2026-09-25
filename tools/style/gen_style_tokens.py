"""gen_style_tokens.py

Genere scripts/core/StyleTokens.gd depuis docs/style/tokens.json (tache
ART-05, STYLE_BIBLE.md SS7.7) : source UNIQUE des palettes par carte (ciel,
soleil, elevation, ombre, sol, coulisses, brouillard) et des bandes de
teinte reservees (SS9, tokens.json "reserved") pour Cartoon.gd et ses tests
-- plus aucune valeur recopiee/retouchee a la main dans Cartoon._MAP_
PALETTES. L'ancien assombrissement de compensation sur Wasteland/Cargo Ship
(mesure contre un rendu Filmic depuis remplace par le tonemap LINEAIRE
WYSIWYG de LevelLook.gd v3 SS7.5) disparait avec ce generateur : il ne
recopie jamais que les hex bruts de tokens.json, jamais une valeur
retouchee a la main.

`fog`/`backdrop_near`/`backdrop_far` (SS7.7, "on ajoute ground, backdrop_
near, backdrop_far, fog") ne sont PAS des cles litterales de tokens.json
"maps" (qui ne donne que "ground" telle quelle, le reste etant des couleurs
de materiaux/reperes narratifs) -- ce generateur les DERIVE des jetons deja
presents, par des formules deja documentees ailleurs dans tokens.json ou
deja cablees dans le moteur :
  - `fog` : tokens.json "shader.environment.fog_color" =
    "lerp(map.sky_horizon, map.sun_color, 0.4)" -- exactement la formule
    deja cablee en dur dans LevelLook.gd (`palette["sky_horizon"].lerp(
    palette["sun_color"], 0.4)`, hors perimetre ART-05). Ce jeton est donc
    redondant avec ce calcul-la (pas une nouvelle source de verite), mais
    sert les futurs consommateurs (ART-06 "coulisses", brouillard de
    l'anneau de silhouettes) qui n'ont pas de raison de recalculer un lerp
    que ce fichier a deja fait une fois pour toutes.
  - `backdrop_far` := `sky_horizon` -- l'anneau de silhouettes le plus
    lointain (tokens.json "world.backdrop.ring_m" jusqu'a 600 m, ombrage
    "unshaded") se fond dans l'horizon, comme l'exige CHK-12 ("0% de vide
    sous l'horizon" -- une bande la plus eloignee qui ne colle pas EXACTE-
    MENT au sky_horizon laisserait un liseré de vide visible au raccord).
  - `backdrop_near` := lerp(sky_horizon, shadow_tint, 0.30) -- l'anneau le
    plus proche (150 m) garde un soupcon de la teinte d'ombre froide de la
    carte, pour se detacher un peu plus que l'horizon pur (2-3 tons par
    carte, "world.backdrop.tones_per_map"), tout en restant dans la
    fourchette pale/peu saturee de "world.value_structure.background_
    over_60m" (L 0.70-0.85, C <= 0.06) : verifie par l'auto-controle CHK-07
    ci-dessous, comme les six autres jetons de palette.

CHK-07 self-check (tokens.json "checks".CHK-07, "reserved_colours_in_data":
0, bloquant) : apres generation, ce script re-mesure chaque couleur de
chaque carte en OKLCH (meme conversion sRGB->OKLab que tests/agents/
test_agent_palette.gd's `_oklch()`/tools/look_probe.gd's `_oklab_l()` --
aucun utilitaire OKLab partage n'existe encore dans le depot, memes raisons
qu'eux) et imprime un rapport PASS/FAIL, sur le modele du self-check CHK-08
de tools/textures/gen_textures.py. `tools/review/style_check.py` (ART-03,
futur) sera le scoreur faisant autorite sur les captures/assets ; ce script
ne prouve que le "CHK-07 PASS" de CE contrat, sur les donnees qu'il emet
lui-meme.

Determinisme : aucune alea ici (contrairement a gen_textures.py) -- une
simple transcription + interpolation lineaire de tokens.json. Deux
executions produisent donc toujours le meme fichier, octet pour octet
(hors l'horodatage absent du fichier genere -- volontairement, pour rester
diffable).

Usage:
    python tools/style/gen_style_tokens.py
"""
from __future__ import annotations

import json
import math
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
TOKENS_JSON = REPO_ROOT / "docs" / "style" / "tokens.json"
OUT_GD = REPO_ROOT / "scripts" / "core" / "StyleTokens.gd"

RGB = tuple[float, float, float]

# Cles emises par carte, dans cet ordre (correspond a la phrase d'acceptation
# ART-05 : "ciel, soleil, elevation, ombre, sol, coulisses, brouillard").
_MAP_KEYS_IN_ORDER = [
    "sky_zenith", "sky_horizon",
    "sun_color", "sun_elevation_deg",
    "shadow_tint",
    "ground",
    "backdrop_near", "backdrop_far",
    "fog",
]
# Sous-ensemble ci-dessus qui sont des couleurs (donc a passer au
# self-check CHK-07) -- exclut uniquement `sun_elevation_deg` (un angle).
_COLOR_KEYS = [k for k in _MAP_KEYS_IN_ORDER if k != "sun_elevation_deg"]

_FOG_SUN_MIX = 0.4  # tokens.json shader.environment.fog_color
_BACKDROP_NEAR_SHADOW_MIX = 0.30  # voir docstring ci-dessus


# --------------------------------------------------------------------- couleur

def hexc(h: str) -> RGB:
    """`#RRGGBB` ou `RRGGBB` -> (r, g, b) en [0, 1]."""
    h = h.lstrip("#")
    return (
        int(h[0:2], 16) / 255.0,
        int(h[2:4], 16) / 255.0,
        int(h[4:6], 16) / 255.0,
    )


def lerp3(a: RGB, b: RGB, t: float) -> RGB:
    return (
        a[0] + (b[0] - a[0]) * t,
        a[1] + (b[1] - a[1]) * t,
        a[2] + (b[2] - a[2]) * t,
    )


def to_hex(rgb: RGB) -> str:
    """(r, g, b) en [0, 1] -> `rrggbb` minuscule (arrondi, borne [0, 255])."""
    def channel(v: float) -> str:
        return f"{max(0, min(255, round(v * 255.0))):02x}"
    return "".join(channel(c) for c in rgb)


# ----------------------------------------------------------------- OKLab/OKLCH
# Conversion standard, Bjoern Ottosson (https://bottosson.github.io/posts/
# oklab/). Self-contenue ici pour la meme raison que tests/agents/
# test_agent_palette.gd._oklch() et tools/textures/gen_textures.py's oklab_l() :
# aucun utilitaire OKLab partage n'existe encore dans le depot (ART-03/ART-05
# etaient tous deux hors du perimetre de ces deux fichiers-la au moment ou ils
# ont ete ecrits).

def _srgb_to_linear(c: float) -> float:
    if c <= 0.04045:
        return c / 12.92
    return ((c + 0.055) / 1.055) ** 2.4


def oklch(rgb: RGB) -> tuple[float, float, float]:
    """(r, g, b) sRGB en [0, 1] -> (L, C, h_deg) OKLCH."""
    r, g, b = (_srgb_to_linear(c) for c in rgb)

    l = 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b
    m = 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b
    s = 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b

    l_ = (1.0 if l >= 0.0 else -1.0) * abs(l) ** (1.0 / 3.0)
    m_ = (1.0 if m >= 0.0 else -1.0) * abs(m) ** (1.0 / 3.0)
    s_ = (1.0 if s >= 0.0 else -1.0) * abs(s) ** (1.0 / 3.0)

    big_l = 0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_
    a = 1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_
    b2 = 0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_

    chroma = (a * a + b2 * b2) ** 0.5
    hue_deg = math.degrees(math.atan2(b2, a))
    if hue_deg < 0.0:
        hue_deg += 360.0
    return big_l, chroma, hue_deg


def in_reserved_band(rgb: RGB, hue_bands_deg: list[list[float]], chroma_threshold: float) -> tuple[bool, float, float]:
    _, chroma, hue_deg = oklch(rgb)
    for lo, hi in hue_bands_deg:
        if lo <= hue_deg <= hi and chroma > chroma_threshold:
            return True, chroma, hue_deg
    return False, chroma, hue_deg


# --------------------------------------------------------------------- GDScript

def gd_color(rgb: RGB) -> str:
    return f'Color("{to_hex(rgb)}")'


def indent(n: int) -> str:
    return "\t" * n


def build_map_palettes(maps: dict) -> "dict[str, dict[str, object]]":
    """tokens.json "maps" -> {map_id: {cle: valeur brute (RGB ou float)}},
    dans l'ordre `_MAP_KEYS_IN_ORDER`, en respectant l'ordre des cartes de
    tokens.json (deja trie par "number" 1..8 dans le fichier source)."""
    out: dict[str, dict[str, object]] = {}
    for map_id, entry in maps.items():
        sky_zenith = hexc(entry["sky_zenith"])
        sky_horizon = hexc(entry["sky_horizon"])
        sun_color = hexc(entry["sun_color"])
        shadow_tint = hexc(entry["shadow_tint"])
        ground = hexc(entry["ground"])
        out[map_id] = {
            "sky_zenith": sky_zenith,
            "sky_horizon": sky_horizon,
            "sun_color": sun_color,
            "sun_elevation_deg": float(entry["sun_elevation_deg"]),
            "shadow_tint": shadow_tint,
            "ground": ground,
            "backdrop_near": lerp3(sky_horizon, shadow_tint, _BACKDROP_NEAR_SHADOW_MIX),
            "backdrop_far": sky_horizon,
            "fog": lerp3(sky_horizon, sun_color, _FOG_SUN_MIX),
        }
    return out


def render_gd(palettes: "dict[str, dict[str, object]]", default_map_id: str,
              hue_bands_deg: list[list[float]], chroma_threshold: float) -> str:
    lines: list[str] = []
    lines.append("## StyleTokens.gd")
    lines.append("## GENERE -- NE PAS MODIFIER A LA MAIN.")
    lines.append("## Source : docs/style/tokens.json. Generateur : tools/style/gen_style_tokens.py")
    lines.append("## (tache ART-05, STYLE_BIBLE.md SS7.7). Pour regenerer apres un changement de")
    lines.append("## tokens.json : `python tools/style/gen_style_tokens.py`.")
    lines.append("##")
    lines.append("## Palette par carte (MatchConfig.map_id) : ciel (sky_zenith/sky_horizon),")
    lines.append("## soleil (sun_color/sun_elevation_deg), ombre (shadow_tint), sol (ground),")
    lines.append("## coulisses (backdrop_near/backdrop_far) et brouillard (fog) -- voir la")
    lines.append("## docstring de gen_style_tokens.py pour la provenance/formule de chaque cle.")
    lines.append("## Cartoon.gd (scripts/core/Cartoon.gd) est le SEUL consommateur en jeu ;")
    lines.append("## LevelLook.gd/InkPost.gd/PlayerLook.gd lisent Cartoon.map_palette(), jamais")
    lines.append("## StyleTokens directement (une seule facade publique, voir Cartoon.gd SS7.7).")
    lines.append("class_name StyleTokens")
    lines.append("extends RefCounted")
    lines.append("")
    lines.append(f'const DEFAULT_MAP_ID := "{default_map_id}"')
    lines.append("")
    lines.append("## tokens.json \"reserved\" : bandes de teinte OKLCH interdites a toute")
    lines.append("## couleur de base (monde, personnage, cosmetique) au-dela de ce seuil de")
    lines.append("## chroma -- exclusives a la surbrillance ennemie (Magenta/Citron).")
    bands_literal = ", ".join(f"[{lo}, {hi}]" for lo, hi in hue_bands_deg)
    lines.append(f"const RESERVED_HUE_BANDS_DEG: Array = [{bands_literal}]")
    lines.append(f"const RESERVED_CHROMA_THRESHOLD := {chroma_threshold}")
    lines.append("")
    lines.append("const MAP_PALETTES: Dictionary = {")
    for map_id, entry in palettes.items():
        lines.append(f'{indent(1)}"{map_id}": {{')
        for key in _MAP_KEYS_IN_ORDER:
            value = entry[key]
            if key == "sun_elevation_deg":
                rendered = f"{float(value)}"
            else:
                rendered = gd_color(value)  # type: ignore[arg-type]
            lines.append(f'{indent(2)}"{key}": {rendered},')
        lines.append(f"{indent(1)}}},")
    lines.append("}")
    lines.append("")
    return "\n".join(lines)


def self_check_chk07(palettes: "dict[str, dict[str, object]]",
                      hue_bands_deg: list[list[float]], chroma_threshold: float) -> bool:
    print("\nCHK-07 self-check (aucune couleur de MAP_PALETTES dans une bande reservee) :")
    all_pass = True
    for map_id, entry in palettes.items():
        for key in _COLOR_KEYS:
            rgb: RGB = entry[key]  # type: ignore[assignment]
            bad, chroma, hue_deg = in_reserved_band(rgb, hue_bands_deg, chroma_threshold)
            status = "FAIL" if bad else "PASS"
            if bad:
                all_pass = False
                print(f"  {status} {map_id}.{key} = #{to_hex(rgb)} (h={hue_deg:.1f} deg, C={chroma:.3f})")
    n_checked = len(palettes) * len(_COLOR_KEYS)
    print(f"CHK-07: {'PASS' if all_pass else 'FAIL'} ({n_checked} couleurs verifiees sur {len(palettes)} cartes)")
    return all_pass


def main() -> int:
    data = json.loads(TOKENS_JSON.read_text(encoding="utf-8"))
    maps = data["maps"]
    reserved = data["reserved"]
    hue_bands_deg = [[float(lo), float(hi)] for lo, hi in reserved["hue_bands_deg"]]
    chroma_threshold = float(reserved["chroma_threshold"])

    palettes = build_map_palettes(maps)
    default_map_id = "wasteland"  # STYLE_BIBLE.md SS7.7 : carte par defaut du thesis (SS1).
    if default_map_id not in palettes:
        print(f"gen_style_tokens: carte par defaut '{default_map_id}' absente de tokens.json maps", file=sys.stderr)
        return 1

    gd_source = render_gd(palettes, default_map_id, hue_bands_deg, chroma_threshold)
    OUT_GD.parent.mkdir(parents=True, exist_ok=True)
    OUT_GD.write_text(gd_source, encoding="utf-8", newline="\n")
    print(f"wrote {OUT_GD.relative_to(REPO_ROOT)}  ({len(palettes)} cartes)")

    ok = self_check_chk07(palettes, hue_bands_deg, chroma_threshold)
    print("\nDone." if ok else "\nDone, but CHK-07 FAILED on at least one colour (see above).")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
