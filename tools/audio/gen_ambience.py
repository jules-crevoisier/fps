#!/usr/bin/env python3
"""tools/audio/gen_ambience.py

Génère les boucles d'ambiance de carte, les stings de musique de match et la
boucle percussive de dernière minute (contract-r4a.md, "R4-AMB — ambiances et
musique") en RÉUTILISANT la chaîne de synthèse déterministe de
`tools/audio/gen_sfx.py` (RNG dérivé du nom par sha256, filtres Butterworth,
bruit rose/blanc, enveloppes, `render_seamless` pour les coutures de boucle,
`finalize`/`measure`/`verify` pour les mêmes vérifications de pic/DC/couture)
plutôt que de dupliquer ces outils.

Six ambiances (une par carte de `Layouts.MAP_IDS`) : Port-Ferraille (eau,
mouettes, grincements de métal), Val-Poussière (vent sec, volets, carillon
lointain), Saint-Ombre (pluie, gouttes, tonnerre lointain), Col du Vautour
(rafales de vent de montagne, drapeau qui claque), La Fosse (vent de carrière,
ruissellement de gravier), Le Belvédère (calme urbain à l'aube, oiseaux).
Quatre stings de musique de MATCH (pas de manche — voir `round_start`/
`round_win`/`round_lose` déjà gérés par `RoundMode.gd`, hors de portée ici) :
`match_start`, `match_last_minute`, `match_victory`, `match_defeat`. Une
boucle percussive basse intensité `last_minute_loop` jouée pendant la
dernière minute du match.

Usage :
    python tools/audio/gen_ambience.py [--out assets/audio]

Sortie : `<out>/music/ambience_<map_id>.wav` (x6), `<out>/music/match_*.wav`
(x4), `<out>/music/last_minute_loop.wav`. Tableau de stats + vérifications à
la fin ; sort en erreur (exit 1) si une vérification échoue.
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path
from typing import Callable, Dict, List

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gen_sfx import (  # réutilise la chaîne DSP + vérifs de gen_sfx.py telle quelle
    SR,
    adsr,
    bandpass,
    exp_decay,
    feedback_tail,
    finalize,
    lowpass,
    measure,
    mix_at,
    pink_noise,
    pitched_sweep,
    print_table,
    render_seamless,
    resonant_click,
    rng_for,
    sine,
    verify,
    white_noise,
    write_wav,
)

CROSSFADE_S = 3.0

# ============================================================== outils partagés


def _sparse_events(n: int, sr: int, rng: np.random.Generator, count: int,
                    event_fn: Callable[[np.random.Generator], np.ndarray], jitter: float = 0.7) -> np.ndarray:
    """Place `count` évènements (rendus par `event_fn(rng)`) à des offsets
    semi-aléatoires : le buffer est découpé en `count` créneaux égaux, chaque
    évènement tombe à une position aléatoire autour du centre de son créneau
    (`jitter` in [0,1] élargit la fenêtre aléatoire autour du centre) —
    toujours exactement `count` évènements, sans boucle de rejet (donc jamais
    bloquant), déterministe (un seul `rng` partagé, consommé dans l'ordre)."""
    out = np.zeros(n)
    if count <= 0 or n <= 0:
        return out
    slot = n / count
    for k in range(count):
        center = slot * (k + 0.5)
        off = int(np.clip(center + rng.uniform(-0.5, 0.5) * slot * jitter, 0, max(n - 1, 0)))
        ev = event_fn(rng)
        end = min(off + len(ev), n)
        if end <= off:
            continue
        out[off:end] += ev[: end - off]
    return out


# ============================================================== six ambiances de carte


def gen_ambience_port_ferraille(n: int, sr: int, rng: np.random.Generator) -> np.ndarray:
    """Quais embrumés : clapot d'eau, mouettes lointaines, grincements de métal."""
    water = bandpass(pink_noise(n, rng), 80, 900, sr, order=3)
    t = np.arange(n) / sr
    lfo = 0.6 + 0.4 * np.sin(2 * np.pi * 0.09 * t + 0.7 * np.sin(2 * np.pi * 0.021 * t))
    water = water * lfo * 0.5

    def gull(rgn: np.random.Generator) -> np.ndarray:
        m = int(0.9 * sr)
        cry = pitched_sweep(m, sr, 1800, 2600, shape="sine", curve=1.4) * exp_decay(m, sr, 0.35)
        return bandpass(cry, 1200, 3200, sr, order=2) * 0.4
    gulls = _sparse_events(n, sr, rng, 6, gull)

    def creak(rgn: np.random.Generator) -> np.ndarray:
        m = int(0.6 * sr)
        return resonant_click(m, sr, 220, 6, rgn) * exp_decay(m, sr, 0.4) * 0.35
    creaks = _sparse_events(n, sr, rng, 5, creak)

    return water + gulls + creaks


def gen_ambience_val_poussiere(n: int, sr: int, rng: np.random.Generator) -> np.ndarray:
    """Ville-frontière écrasée de soleil : vent sec, volets, carillon lointain."""
    wind = bandpass(pink_noise(n, rng), 300, 3500, sr, order=3)
    t = np.arange(n) / sr
    lfo = 0.5 + 0.5 * np.sin(2 * np.pi * 0.05 * t)
    wind = wind * lfo * 0.42

    def shutter(rgn: np.random.Generator) -> np.ndarray:
        m = int(0.25 * sr)
        return resonant_click(m, sr, 500, 5, rgn) * exp_decay(m, sr, 0.15) * 0.5
    shutters = _sparse_events(n, sr, rng, 5, shutter)

    def chime(rgn: np.random.Generator) -> np.ndarray:
        m = int(1.1 * sr)
        notes = [1046.0, 1318.5, 1568.0]
        f = notes[int(rgn.integers(0, len(notes)))]
        return sine(m, sr, f) * exp_decay(m, sr, 0.5) * 0.22
    chimes = _sparse_events(n, sr, rng, 7, chime)

    return wind + shutters + chimes


def gen_ambience_saint_ombre(n: int, sr: int, rng: np.random.Generator) -> np.ndarray:
    """Nuit pluvieuse : pluie continue, gouttes, tonnerre lointain."""
    rain = lowpass(bandpass(white_noise(n, rng), 1200, 9000, sr, order=3), 7000, sr, order=2) * 0.28

    def drip(rgn: np.random.Generator) -> np.ndarray:
        m = int(0.15 * sr)
        return resonant_click(m, sr, 1800, 12, rgn) * exp_decay(m, sr, 0.05) * 0.45
    drips = _sparse_events(n, sr, rng, 12, drip)

    def thunder(rgn: np.random.Generator) -> np.ndarray:
        m = int(2.2 * sr)
        return feedback_tail(m, sr, 1.1, 300, rgn) * 0.5
    thunders = _sparse_events(n, sr, rng, 2, thunder)

    return rain + drips + thunders


def gen_ambience_col_du_vautour(n: int, sr: int, rng: np.random.Generator) -> np.ndarray:
    """Base de montagne enneigée : rafales de vent, drapeau qui claque."""
    base_wind = bandpass(pink_noise(n, rng), 150, 2200, sr, order=3)
    t = np.arange(n) / sr
    gust = 0.45 + 0.55 * np.clip(np.sin(2 * np.pi * 0.045 * t) + 0.3 * np.sin(2 * np.pi * 0.017 * t + 1.3), -1.0, 1.0)
    wind = base_wind * gust * 0.5

    def flap(rgn: np.random.Generator) -> np.ndarray:
        m = int(0.12 * sr)
        return bandpass(white_noise(m, rgn), 200, 1800, sr, order=2) * exp_decay(m, sr, 0.05) * 0.5
    flaps = _sparse_events(n, sr, rng, 16, flap)

    return wind + flaps


def gen_ambience_la_fosse(n: int, sr: int, rng: np.random.Generator) -> np.ndarray:
    """Carrière symétrique : vent de carrière sec, ruissellement de gravier."""
    wind = bandpass(pink_noise(n, rng), 200, 2600, sr, order=3)
    t = np.arange(n) / sr
    lfo = 0.55 + 0.45 * np.sin(2 * np.pi * 0.03 * t)
    wind = wind * lfo * 0.4

    def trickle(rgn: np.random.Generator) -> np.ndarray:
        m = int(0.5 * sr)
        return bandpass(white_noise(m, rgn), 2000, 8000, sr, order=3) * exp_decay(m, sr, 0.2) * 0.3
    trickles = _sparse_events(n, sr, rng, 9, trickle)

    return wind + trickles


def gen_ambience_le_belvedere(n: int, sr: int, rng: np.random.Generator) -> np.ndarray:
    """Toits au petit matin : calme urbain à l'aube, oiseaux."""
    hush = lowpass(pink_noise(n, rng), 1200, sr, order=2) * 0.22

    def bird(rgn: np.random.Generator) -> np.ndarray:
        m = int(0.4 * sr)
        f0 = 2200.0 + float(rgn.uniform(-300, 500))
        f1 = f0 + float(rgn.uniform(400, 900))
        return pitched_sweep(m, sr, f0, f1, shape="sine", curve=1.8) * exp_decay(m, sr, 0.12) * 0.28
    birds = _sparse_events(n, sr, rng, 13, bird)

    return hush + birds


AMBIENCE_SPECS: Dict[str, Dict] = {
    "ambience_port_ferraille": dict(duration=78.0, gen=gen_ambience_port_ferraille),
    "ambience_val_poussiere": dict(duration=72.0, gen=gen_ambience_val_poussiere),
    "ambience_saint_ombre": dict(duration=84.0, gen=gen_ambience_saint_ombre),
    "ambience_col_du_vautour": dict(duration=75.0, gen=gen_ambience_col_du_vautour),
    "ambience_la_fosse": dict(duration=66.0, gen=gen_ambience_la_fosse),
    "ambience_le_belvedere": dict(duration=80.0, gen=gen_ambience_le_belvedere),
}


def render_ambience(name: str, spec: Dict) -> np.ndarray:
    rng = rng_for(name)

    def body(n: int, sr: int) -> np.ndarray:
        return spec["gen"](n, sr, rng)

    return render_seamless(spec["duration"], SR, body, crossfade_s=CROSSFADE_S)


# ============================================================== stings de musique de MATCH
# (distincts de round_start/round_win/round_lose, déjà gérés par RoundMode.gd
# pour les manches SnD/Duel — ici : début de PARTIE, dernière minute,
# victoire/défaite de partie, pour tous les modes.)


def gen_match_start(rng: np.random.Generator) -> np.ndarray:
    n = int(1.3 * SR)
    notes = [220.0, 277.18, 329.63, 440.0]  # la mineur, affirmatif
    parts = []
    for k, f in enumerate(notes):
        start = int(k * 0.04 * SR)
        seg_n = n - start
        tone = sine(seg_n, SR, f) * exp_decay(seg_n, SR, 0.5)
        parts.append((tone, start, 0.32))
    swell = bandpass(white_noise(n, rng), 400, 3000, order=3) * adsr(n, SR, 0.05, 0.2, 0.3, sustain_level=0.15)
    parts.append((swell, 0, 0.3))
    return mix_at(n, *parts)


def gen_match_last_minute(rng: np.random.Generator) -> np.ndarray:
    n = int(0.8 * SR)
    stab_n = int(0.05 * SR)
    stab = resonant_click(stab_n, SR, 700, 5, rng) * exp_decay(stab_n, SR, 0.03)
    rise = lowpass(pitched_sweep(n, SR, 300, 900, shape="saw", curve=1.0) * exp_decay(n, SR, 0.28), 2200, order=3)
    return mix_at(n, (stab, 0, 0.6), (rise, int(0.02 * SR), 0.4))


def gen_match_victory(rng: np.random.Generator) -> np.ndarray:
    n = int(1.8 * SR)
    notes = [261.63, 329.63, 392.0, 523.25, 659.25]
    parts = []
    for k, f in enumerate(notes):
        start = int(k * 0.08 * SR)
        seg_n = n - start
        tone = sine(seg_n, SR, f) * exp_decay(seg_n, SR, 0.55)
        parts.append((tone, start, 0.28))
    tail = feedback_tail(n, SR, 0.5, 2500, rng)
    parts.append((tail, 0, 0.15))
    return mix_at(n, *parts)


def gen_match_defeat(rng: np.random.Generator) -> np.ndarray:
    n = int(1.8 * SR)
    notes = [392.0, 349.23, 293.66, 220.0]
    parts = []
    for k, f in enumerate(notes):
        start = int(k * 0.14 * SR)
        seg_n = n - start
        tone = sine(seg_n, SR, f) * exp_decay(seg_n, SR, 0.6)
        parts.append((tone, start, 0.3))
    low = lowpass(pitched_sweep(n, SR, 160, 55, shape="tri", curve=2.0) * exp_decay(n, SR, 0.5), 300, order=2)
    parts.append((low, 0, 0.35))
    return mix_at(n, *parts)


MATCH_STINGS: Dict[str, Callable[[np.random.Generator], np.ndarray]] = {
    "match_start": gen_match_start,
    "match_last_minute": gen_match_last_minute,
    "match_victory": gen_match_victory,
    "match_defeat": gen_match_defeat,
}


# ============================================================== boucle percussive dernière minute


def render_last_minute_loop() -> np.ndarray:
    """Boucle basse intensité (percussion sourde + tapis léger), jouée en
    superposition de l'ambiance de carte pendant les 60 dernières secondes du
    match (voir `Audio.is_last_minute`)."""
    duration = 6.0
    crossfade = 0.4
    bpm = 100.0
    beat = 60.0 / bpm

    def body(n: int, sr: int) -> np.ndarray:
        rng = rng_for("last_minute_loop_texture")
        pad = bandpass(pink_noise(n, rng), 120, 900, sr, order=2) * 0.10
        out = np.zeros(n)
        beats = max(int(round((n / sr) / beat)), 1)
        for k in range(beats):
            off = int(k * beat * sr)
            if off >= n:
                break
            m = min(int(0.09 * sr), n - off)
            thump = pitched_sweep(m, sr, 120, 45, shape="tri", curve=3.0) * exp_decay(m, sr, 0.05)
            thump = lowpass(thump, 260, sr, order=2)
            gain = 0.55 if k % 2 == 0 else 0.32
            out[off:off + m] += thump[:m] * gain
        return out + pad

    return render_seamless(duration, SR, body, crossfade_s=crossfade)


# ============================================================== main


def main() -> int:
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except (AttributeError, ValueError):
        pass

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", default="assets/audio", help="dossier de sortie (relatif à la racine du repo)")
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parents[2]
    out_music = repo_root / args.out / "music"
    out_music.mkdir(parents=True, exist_ok=True)

    stats: List[Dict] = []

    for name, spec in AMBIENCE_SPECS.items():
        x = finalize(render_ambience(name, spec), loop=True)
        path = out_music / f"{name}.wav"
        write_wav(path, x)
        stats.append(measure(path, "ambience", is_loop=True))

    for name, gen in MATCH_STINGS.items():
        rng = rng_for(name)
        x = finalize(gen(rng), loop=False)
        path = out_music / f"{name}.wav"
        write_wav(path, x)
        stats.append(measure(path, "match_sting"))

    x = finalize(render_last_minute_loop(), loop=True)
    path = out_music / "last_minute_loop.wav"
    write_wav(path, x)
    stats.append(measure(path, "last_minute_loop", is_loop=True))

    print_table(stats)
    ok = verify(stats)
    print(f"\n{len(stats)} fichiers générés (6 ambiances de carte + {len(MATCH_STINGS)} stings de match + 1 boucle dernière minute).")
    if not ok:
        print("ÉCHEC : au moins une vérification a échoué (voir [FAIL] ci-dessus).")
        return 1
    print("OK : pic/-1 dBFS, offset DC, coutures de boucle — toutes les vérifications passent.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
