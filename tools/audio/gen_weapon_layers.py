#!/usr/bin/env python3
"""tools/audio/gen_weapon_layers.py

Génère les COUCHES isolées du tir d'arme LOCAL (GF-11, docs/research/01_game_feel.md
§2.5 "Audio d'arme en couches") : transitoire, corps, mécanique, sub (poids —
joué uniquement pour le tireur local, jamais pour un tir distant), plus deux
queues de réverbération génériques (intérieur/extérieur, choisies au tir par
un raycast plafond, voir `Audio.gunshot_tail_name`).

RÉUTILISE la chaîne DSP déterministe de `tools/audio/gen_sfx.py` (RNG dérivé du
nom par sha256, filtres Butterworth, bruit blanc/rose, enveloppes,
`finalize`/`measure`/`verify`/`write_wav` pour les mêmes vérifications de
pic/DC) plutôt que de la dupliquer — même principe que `gen_ambience.py`.
Les couches transitoire/corps/mécanique reprennent les PARAMÈTRES par classe
d'arme de `GUN_PARAMS` (gen_sfx.py) pour rester cohérentes en timbre avec
`gunshot_<classe>_N.wav` (mix pré-existant, toujours utilisé pour les tirs
DISTANTS — la couche par couche est réservée au tireur local, cf. Audio.gd).

Usage :
    python tools/audio/gen_weapon_layers.py [--out assets/audio]

Sortie (dans <out>/sfx/) : `gunshot_<classe>_{transient,body,mech}_{1,2}.wav`,
`gunshot_<classe>_sub_1.wav` (7 classes), `tail_{indoor,outdoor}_{1,2}.wav`.
Tableau de stats + vérifications à la fin ; sort en erreur (exit 1) si une
vérification échoue.
"""
from __future__ import annotations

import sys
from pathlib import Path
from typing import Callable, Dict, List

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gen_sfx import (  # réutilise la chaîne DSP + vérifs de gen_sfx.py telle quelle
    GUN_CLASSES,
    GUN_PARAMS,
    SR,
    bandpass,
    exp_decay,
    feedback_tail,
    finalize,
    lowpass,
    measure,
    mix_at,
    pitched_sweep,
    print_table,
    resonant_click,
    rng_for,
    verify,
    white_noise,
    write_wav,
)

# ============================================================== couches de tir (par classe)


def gen_transient_layer(rng: np.random.Generator, i: int, cls: str) -> np.ndarray:
    """Claquement bref filtré passe-bande (bande propre à la classe d'arme,
    identique à la couche "transient" du mix `gunshot_<classe>` existant)."""
    p = GUN_PARAMS[cls]
    t_n = int(p["t_dur"] * SR)
    transient = bandpass(white_noise(t_n, rng), p["t_lo"], p["t_hi"], order=3)
    transient *= exp_decay(t_n, SR, p["t_dur"] * 0.35)
    return transient


def gen_body_layer(rng: np.random.Generator, i: int, cls: str) -> np.ndarray:
    """Corps/poids : balayage de hauteur descendant, assombri (identique à la
    couche "body" du mix existant)."""
    p = GUN_PARAMS[cls]
    b_n = int(p["body_dur"] * SR)
    body = pitched_sweep(b_n, SR, p["body_f0"], p["body_f1"], shape="tri", curve=3.0)
    body *= exp_decay(b_n, SR, p["body_dur"] * 0.4)
    body = lowpass(body, p["body_f1"] * 4.0, order=2)
    return body


def gen_mech_layer(rng: np.random.Generator, i: int, cls: str) -> np.ndarray:
    """Mécanique : anneau résonant bref (culasse/glissière), identique à la
    couche "click" du mix existant."""
    p = GUN_PARAMS[cls]
    c_n = int(0.010 * SR)
    return resonant_click(c_n, SR, p["click_f"], 18.0, rng) * exp_decay(c_n, SR, 0.004)


def gen_sub_layer(rng: np.random.Generator, i: int, cls: str) -> np.ndarray:
    """Sub grave : réservé au TIREUR LOCAL (voir `Audio._play_local_gunshot`) —
    donne le poids/la puissance de l'arme sans jamais être diffusé en 3D pour
    les autres joueurs. Balayage descendant très grave + coup de grosse caisse
    court, assombris (lowpass serré) pour rester sous le reste du mix."""
    p = GUN_PARAMS[cls]
    n = int(max(p["body_dur"] * 1.6, 0.12) * SR)
    f0 = max(p["body_f1"] * 0.55, 28.0)
    f1 = f0 * 0.45
    sub = pitched_sweep(n, SR, f0, f1, shape="sine", curve=2.2)
    sub *= exp_decay(n, SR, (n / SR) * 0.5)
    sub = lowpass(sub, 120.0, SR, order=3)
    thump_n = min(int(0.02 * SR), n)
    thump = white_noise(thump_n, rng) * exp_decay(thump_n, SR, 0.006)
    thump = lowpass(thump, 90.0, SR, order=2)
    return mix_at(n, (sub, 0, 1.0), (thump, 0, 0.6))


# ============================================================== queues (réverbération selon le lieu)


def gen_tail_indoor(rng: np.random.Generator, i: int) -> np.ndarray:
    """Queue INTÉRIEUR : courte, avec un flutter d'échos rapprochés (parois
    proches qui renvoient le son plusieurs fois très vite) — voir
    `Audio.gunshot_tail_name` (choisie par raycast plafond au tir local)."""
    n = int(0.55 * SR)
    base = feedback_tail(n, SR, 0.14, 3200.0, rng)
    parts = [(base, 0, 1.0)]
    for k in range(1, 5):
        delay = int(k * 0.03 * SR)
        m = max(n - delay, 0)
        if m <= 0:
            continue
        echo = base[:m] * (0.5 ** k)
        parts.append((echo, delay, 1.0))
    return mix_at(n, *parts)


def gen_tail_outdoor(rng: np.random.Generator, i: int) -> np.ndarray:
    """Queue EXTÉRIEUR : plus longue et diffuse, sans flutter — l'air libre
    n'a pas de parois proches, juste une décroissance douce et assombrie."""
    n = int(0.9 * SR)
    return feedback_tail(n, SR, 0.35, 1400.0, rng)


# ============================================================== registre

LAYER_SOUNDS: Dict[str, Dict] = {}
for _cls in GUN_CLASSES:
    LAYER_SOUNDS[f"gunshot_{_cls}_transient"] = dict(count=2, gen=(lambda rng, i, c=_cls: gen_transient_layer(rng, i, c)))
    LAYER_SOUNDS[f"gunshot_{_cls}_body"] = dict(count=2, gen=(lambda rng, i, c=_cls: gen_body_layer(rng, i, c)))
    LAYER_SOUNDS[f"gunshot_{_cls}_mech"] = dict(count=2, gen=(lambda rng, i, c=_cls: gen_mech_layer(rng, i, c)))
    LAYER_SOUNDS[f"gunshot_{_cls}_sub"] = dict(count=1, gen=(lambda rng, i, c=_cls: gen_sub_layer(rng, i, c)))

TAIL_SOUNDS: Dict[str, Dict] = {
    "tail_indoor": dict(count=2, gen=gen_tail_indoor),
    "tail_outdoor": dict(count=2, gen=gen_tail_outdoor),
}


# ============================================================== main


def main() -> int:
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except (AttributeError, ValueError):
        pass  # flux déjà UTF-8 ou non reconfigurable (ex. redirigé) : tant pis pour les accents

    import argparse
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", default="assets/audio", help="dossier de sortie (relatif à la racine du repo)")
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parents[2]
    out_sfx = repo_root / args.out / "sfx"
    out_sfx.mkdir(parents=True, exist_ok=True)

    stats: List[Dict] = []

    for name, spec in LAYER_SOUNDS.items():
        for i in range(spec["count"]):
            rng = rng_for(f"{name}_{i}")
            raw = spec["gen"](rng, i)
            x = finalize(raw, loop=False)
            path = out_sfx / f"{name}_{i + 1}.wav"
            write_wav(path, x)
            stats.append(measure(path, name))

    for name, spec in TAIL_SOUNDS.items():
        for i in range(spec["count"]):
            rng = rng_for(f"{name}_{i}")
            raw = spec["gen"](rng, i)
            x = finalize(raw, loop=False)
            path = out_sfx / f"{name}_{i + 1}.wav"
            write_wav(path, x)
            stats.append(measure(path, name))

    print_table(stats)
    ok = verify(stats)
    total_names = len(LAYER_SOUNDS) + len(TAIL_SOUNDS)
    print(f"\n{len(stats)} fichiers générés pour {total_names} sons logiques (variations comprises).")
    if not ok:
        print("ÉCHEC : au moins une vérification a échoué (voir [FAIL] ci-dessus).")
        return 1
    print("OK : pic/-1 dBFS, offset DC — toutes les vérifications passent.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
