#!/usr/bin/env python3
"""tools/audio/gen_sfx.py

Génère TOUS les effets sonores + la boucle musicale du menu (contract-r2.md,
"R-E audio — acceptance" #1) par synthèse pure (numpy/scipy) : bruit filtré
pour les transitoires, oscillateurs à enveloppe de hauteur pour les corps
percussifs, bursts résonants pour les clics mécaniques, queues de type
delay/feedback pour les réverbérations, additif/FM pour l'UI et les carillons.

Déterministe : chaque son a un seed dérivé de son nom (sha256), reproductible
d'une exécution à l'autre sans dépendre de l'ordre de génération. 48 kHz,
16-bit PCM mono, pic -1 dBFS, silence DC retiré, coutures de boucle lissées
par cross-fade pour les sons qui bouclent (slide_loop, menu_loop).

Usage :
    python tools/audio/gen_sfx.py [--out assets/audio]

En fin d'exécution : imprime un tableau de statistiques (durée, pic dBFS, RMS
dBFS, offset DC, continuité de boucle) par catégorie, et sort en erreur
(exit 1) si une vérification échoue (impossible de "écouter" le résultat ici,
donc tout est vérifié par le calcul).
"""
from __future__ import annotations

import argparse
import hashlib
import math
import sys
from pathlib import Path
from typing import Callable, Dict, List, Optional

import numpy as np
from scipy import signal as sps
from scipy.io import wavfile

SR = 48000
PEAK_DBFS = -1.0
FADE_IN_SAMPLES = 24
FADE_OUT_SAMPLES = 64

# ============================================================== RNG déterministe


def seed_for(name: str) -> int:
    """Seed stable dérivé du nom (sha256, indépendant de l'ordre d'appel)."""
    h = hashlib.sha256(name.encode("utf-8")).digest()
    return int.from_bytes(h[:4], "little")


def rng_for(name: str) -> np.random.Generator:
    return np.random.default_rng(seed_for(name))


# ============================================================== outils DSP


def db_to_amp(db: float) -> float:
    return 10.0 ** (db / 20.0)


def amp_to_db(a: float) -> float:
    a = max(abs(a), 1e-9)
    return 20.0 * math.log10(a)


def remove_dc(x: np.ndarray) -> np.ndarray:
    if x.size == 0:
        return x
    return x - np.mean(x)


def normalize_peak(x: np.ndarray, peak_db: float = PEAK_DBFS) -> np.ndarray:
    peak = float(np.max(np.abs(x))) if x.size else 0.0
    if peak < 1e-9:
        return x
    return x * (db_to_amp(peak_db) / peak)


def fade_edges(x: np.ndarray, n_in: int = FADE_IN_SAMPLES, n_out: int = FADE_OUT_SAMPLES) -> np.ndarray:
    x = x.copy()
    n_in = min(n_in, len(x))
    n_out = min(n_out, len(x))
    if n_in > 0:
        x[:n_in] *= np.linspace(0.0, 1.0, n_in)
    if n_out > 0:
        x[-n_out:] *= np.linspace(1.0, 0.0, n_out)
    return x


def close_loop_seam(x: np.ndarray) -> np.ndarray:
    """Force x[0] == x[-1] par une rampe linéaire (correction "DC drift") sur
    tout le buffer : dérive tellement lente (un seul cycle sur toute la durée)
    qu'elle est inaudible, mais annule la discontinuité de couture au point de
    bouclage (sample n-1 -> sample 0)."""
    if x.size < 2:
        return x
    diff = float(x[0] - x[-1])
    ramp = np.linspace(0.0, diff, len(x))
    return x + ramp


def finalize(x: np.ndarray, loop: bool = False, peak_db: float = PEAK_DBFS) -> np.ndarray:
    x = remove_dc(np.asarray(x, dtype=np.float64))
    if loop:
        x = close_loop_seam(x)
        x = remove_dc(x)  # translation constante : ne casse pas l'égalité x[0]==x[-1] du cross-fade
    else:
        x = fade_edges(x)
    x = normalize_peak(x, peak_db)
    return x


def _butter(x: np.ndarray, cutoff, sr: int, order: int, btype: str) -> np.ndarray:
    if x.size == 0:
        return x
    nyq = sr * 0.5
    wn = np.clip(np.atleast_1d(np.asarray(cutoff, dtype=np.float64)) / nyq, 1e-4, 0.999)
    arg = wn if len(wn) > 1 else float(wn[0])
    sos = sps.butter(order, arg, btype=btype, output="sos")
    return sps.sosfilt(sos, x)


def lowpass(x: np.ndarray, cutoff: float, sr: int = SR, order: int = 4) -> np.ndarray:
    return _butter(x, cutoff, sr, order, "lowpass")


def highpass(x: np.ndarray, cutoff: float, sr: int = SR, order: int = 4) -> np.ndarray:
    return _butter(x, cutoff, sr, order, "highpass")


def bandpass(x: np.ndarray, lo: float, hi: float, sr: int = SR, order: int = 4) -> np.ndarray:
    return _butter(x, [lo, hi], sr, order, "bandpass")


def white_noise(n: int, rng: np.random.Generator) -> np.ndarray:
    return rng.uniform(-1.0, 1.0, n).astype(np.float64)


def pink_noise(n: int, rng: np.random.Generator) -> np.ndarray:
    """Bruit rose approché par filtrage 1/f en fréquence (FFT)."""
    if n <= 1:
        return white_noise(n, rng)
    white = rng.standard_normal(n)
    f = np.fft.rfft(white)
    freqs = np.fft.rfftfreq(n)
    freqs[0] = freqs[1] if len(freqs) > 1 else 1.0
    f = f / np.sqrt(freqs)
    pink = np.fft.irfft(f, n)
    peak = float(np.max(np.abs(pink))) + 1e-9
    return pink / peak


def exp_decay(n: int, sr: int, tau: float) -> np.ndarray:
    t = np.arange(n) / sr
    return np.exp(-t / max(tau, 1e-4))


def adsr(n: int, sr: int, attack: float, decay: float, release: float, sustain_level: float = 0.7) -> np.ndarray:
    a = max(int(attack * sr), 0)
    d = max(int(decay * sr), 0)
    r = max(int(release * sr), 0)
    s = max(n - a - d - r, 0)
    parts = [
        np.linspace(0.0, 1.0, a, endpoint=False) if a else np.zeros(0),
        np.linspace(1.0, sustain_level, d, endpoint=False) if d else np.zeros(0),
        np.full(s, sustain_level),
        np.linspace(sustain_level, 0.0, r) if r else np.zeros(0),
    ]
    env = np.concatenate(parts) if parts else np.zeros(n)
    if len(env) < n:
        env = np.pad(env, (0, n - len(env)))
    return env[:n]


def sine(n: int, sr: int, freq: float) -> np.ndarray:
    t = np.arange(n) / sr
    return np.sin(2 * np.pi * freq * t)


def pitched_sweep(n: int, sr: int, f0: float, f1: float, shape: str = "sine", curve: float = 2.0) -> np.ndarray:
    """Oscillateur avec enveloppe de hauteur f0->f1 : intégration de phase
    correcte (cumsum de la fréquence instantanée), pas un simple glissement
    échantillon par échantillon."""
    if n <= 0:
        return np.zeros(0)
    t = np.linspace(0.0, 1.0, n)
    freq_t = f1 + (f0 - f1) * (1.0 - t) ** curve
    phase = 2 * np.pi * np.cumsum(freq_t) / sr
    if shape == "tri" or shape == "saw":
        width = 0.5 if shape == "tri" else 1.0
        return sps.sawtooth(phase, width=width)
    return np.sin(phase)


def resonant_click(n: int, sr: int, freq: float, q: float, rng: np.random.Generator) -> np.ndarray:
    """Impulsion + un peu de bruit, filtrée par un passe-bande étroit : anneau
    mécanique bref (clic de culasse, cliquet...)."""
    if n <= 0:
        return np.zeros(0)
    imp = np.zeros(n)
    imp[0] = 1.0
    imp += rng.uniform(-0.05, 0.05, n)
    bw = max(freq / max(q, 0.5), 5.0)
    lo = max(freq - bw / 2.0, 20.0)
    hi = min(freq + bw / 2.0, sr * 0.49)
    if hi <= lo:
        hi = lo + 5.0
    return bandpass(imp, lo, hi, sr, order=2)


def feedback_tail(n: int, sr: int, decay_tau: float, tone_cutoff: float, rng: np.random.Generator) -> np.ndarray:
    """Queue façon delay/feedback simplifiée : bruit filtré + enveloppe
    exponentielle, assombri (lowpass) progressivement — approx. convolution
    avec une réponse impulsionnelle synthétique qui se réverbère et s'éteint."""
    if n <= 0:
        return np.zeros(0)
    src = white_noise(n, rng)
    env = exp_decay(n, sr, decay_tau)
    tail = src * env
    chunks = 6
    step = max(n // chunks, 1)
    out = np.zeros(n)
    for i in range(0, n, step):
        seg = tail[i:i + step]
        if seg.size == 0:
            continue
        frac = i / n
        cutoff = max(tone_cutoff * (1.0 - 0.7 * frac), 200.0)
        out[i:i + step] = lowpass(seg, cutoff, sr, order=2)
    return out


def mix_at(total_n: int, *parts_and_offsets) -> np.ndarray:
    """parts_and_offsets: séquence de (array, offset_samples, gain)."""
    out = np.zeros(total_n)
    for arr, off, gain in parts_and_offsets:
        if arr.size == 0:
            continue
        end = min(off + len(arr), total_n)
        if end <= off:
            continue
        out[off:end] += arr[: end - off] * gain
    return out


def render_seamless(duration_s: float, sr: int, body_fn: Callable[[int, int], np.ndarray], crossfade_s: float = 0.4) -> np.ndarray:
    """Rend `body_fn` sur (duration + crossfade) échantillons puis fond en
    fondu la queue supplémentaire dans la tête : boucle sans à-coup une fois
    tronqué à `duration_s`."""
    cf = int(crossfade_s * sr)
    n = int(duration_s * sr)
    total = n + cf
    x = body_fn(total, sr)
    if cf > 0 and len(x) >= total:
        fade_in = np.linspace(0.0, 1.0, cf)
        fade_out = np.linspace(1.0, 0.0, cf)
        x = x.copy()
        x[:cf] = x[:cf] * fade_in + x[n:n + cf] * fade_out
    return x[:n]


# ============================================================== familles de sons

GUN_CLASSES = ["pistol", "magnum", "smg", "rifle", "marksman", "shotgun", "sniper"]

# Par classe : bande du transitoire, durée du corps (thump), fréquences de
# balayage du corps, fréquence du clic mécanique, tau/coupure de la queue,
# durée totale. Réglé pour que chaque classe soit reconnaissable : le pistolet
# est sec et court, le sniper est un boom long et grave, le shotgun est large
# et bas, la smg est une claque très courte, etc.
GUN_PARAMS: Dict[str, Dict[str, float]] = {
    "pistol":   dict(t_lo=1800, t_hi=6000, t_dur=0.020, body_f0=190, body_f1=75, body_dur=0.050, click_f=3200, tail_tau=0.05, tail_cut=3500, total=0.18),
    "magnum":   dict(t_lo=900,  t_hi=4200, t_dur=0.030, body_f0=115, body_f1=42, body_dur=0.100, click_f=1800, tail_tau=0.16, tail_cut=2200, total=0.38),
    "smg":      dict(t_lo=2000, t_hi=7200, t_dur=0.015, body_f0=205, body_f1=92, body_dur=0.040, click_f=3600, tail_tau=0.045, tail_cut=3800, total=0.15),
    "rifle":    dict(t_lo=1500, t_hi=6000, t_dur=0.020, body_f0=165, body_f1=66, body_dur=0.060, click_f=2800, tail_tau=0.09, tail_cut=3000, total=0.22),
    "marksman": dict(t_lo=1200, t_hi=5500, t_dur=0.022, body_f0=150, body_f1=56, body_dur=0.070, click_f=2400, tail_tau=0.14, tail_cut=2600, total=0.30),
    "shotgun":  dict(t_lo=500,  t_hi=3500, t_dur=0.035, body_f0=96,  body_f1=36, body_dur=0.120, click_f=1500, tail_tau=0.20, tail_cut=2000, total=0.42),
    "sniper":   dict(t_lo=400,  t_hi=3000, t_dur=0.040, body_f0=82,  body_f1=29, body_dur=0.160, click_f=1200, tail_tau=0.30, tail_cut=1800, total=0.62),
}

GUN_FAR_CUTOFF = {"pistol": 1200, "magnum": 900, "smg": 1300, "rifle": 1100, "marksman": 1000, "shotgun": 700, "sniper": 650}


def gen_gunshot(rng: np.random.Generator, i: int, cls: str) -> np.ndarray:
    p = GUN_PARAMS[cls]
    n = int(p["total"] * SR)
    t_n = int(p["t_dur"] * SR)
    transient = bandpass(white_noise(t_n, rng), p["t_lo"], p["t_hi"], order=3)
    transient *= exp_decay(t_n, SR, p["t_dur"] * 0.35)

    b_n = int(p["body_dur"] * SR)
    body = pitched_sweep(b_n, SR, p["body_f0"], p["body_f1"], shape="tri", curve=3.0)
    body *= exp_decay(b_n, SR, p["body_dur"] * 0.4)
    body = lowpass(body, p["body_f1"] * 4.0, order=2)

    c_n = min(int(0.010 * SR), n)
    click = resonant_click(c_n, SR, p["click_f"], 18.0, rng) * exp_decay(c_n, SR, 0.004)

    tail = feedback_tail(n, SR, p["tail_tau"], p["tail_cut"], rng)

    out = mix_at(
        n,
        (transient, 0, 1.0),
        (body, 0, 0.9),
        (click, int(0.003 * SR), 0.5),
    )
    out += tail[:n] * 0.35
    return out


def gen_gunshot_far(rng: np.random.Generator, i: int, cls: str) -> np.ndarray:
    base = gen_gunshot(rng, i, cls)
    cutoff = GUN_FAR_CUTOFF[cls]
    far = lowpass(base, cutoff, order=4)
    pad = int(0.03 * SR)
    far = np.pad(far, (0, pad))
    far = lowpass(far, cutoff, order=2)
    return far


def gen_reload_out(rng: np.random.Generator, i: int) -> np.ndarray:
    n = int(0.35 * SR)
    click1 = resonant_click(int(0.010 * SR), SR, 2600 - i * 80, 14, rng)
    slide_n = int(0.12 * SR)
    slide = bandpass(white_noise(slide_n, rng), 800, 2500, order=3) * exp_decay(slide_n, SR, 0.05)
    return mix_at(n, (click1, 0, 1.0), (slide, int(0.05 * SR), 0.6))


def gen_reload_in(rng: np.random.Generator, i: int) -> np.ndarray:
    n = int(0.30 * SR)
    slide_n = int(0.10 * SR)
    slide = bandpass(white_noise(slide_n, rng), 700, 2200, order=3) * exp_decay(slide_n, SR, 0.045)
    click2 = resonant_click(int(0.012 * SR), SR, 2200 + i * 60, 16, rng)
    return mix_at(n, (slide, 0, 0.6), (click2, int(0.08 * SR), 0.9))


def gen_dry_fire(rng: np.random.Generator, i: int) -> np.ndarray:
    n = int(0.08 * SR)
    return resonant_click(n, SR, 2000 + i * 150, 10, rng) * exp_decay(n, SR, 0.02)


def gen_equip(rng: np.random.Generator, i: int) -> np.ndarray:
    n = int(0.18 * SR)
    click = resonant_click(int(0.015 * SR), SR, 1800 + i * 100, 12, rng)
    slide_n = int(0.08 * SR)
    slide = bandpass(white_noise(slide_n, rng), 600, 2000, order=3) * exp_decay(slide_n, SR, 0.04)
    return mix_at(n, (click, 0, 1.0), (slide, int(0.02 * SR), 0.5))


def gen_hitmarker(rng: np.random.Generator, i: int) -> np.ndarray:
    n = int(0.09 * SR)
    f = 1400 + i * 90
    tone = sine(n, SR, f) * exp_decay(n, SR, 0.02)
    click = resonant_click(int(0.006 * SR), SR, 3500, 20, rng)
    return mix_at(n, (tone, 0, 0.6), (click, 0, 0.5))


def gen_headshot(rng: np.random.Generator, i: int) -> np.ndarray:
    base = gen_hitmarker(rng, i)
    n = int(0.22 * SR)
    splat_n = int(0.05 * SR)
    splat = bandpass(white_noise(splat_n, rng), 300, 5000, order=3) * exp_decay(splat_n, SR, 0.02)
    ping_n = int(0.12 * SR)
    ping = pitched_sweep(ping_n, SR, 2600, 1200, shape="sine", curve=2.5) * exp_decay(ping_n, SR, 0.05)
    return mix_at(n, (base, 0, 1.0), (splat, int(0.01 * SR), 0.5), (ping, int(0.01 * SR), 0.4))


def gen_kill_confirm(rng: np.random.Generator, i: int) -> np.ndarray:
    n = int(0.5 * SR)
    freqs = [660.0, 880.0, 1320.0]
    parts = []
    for k, f in enumerate(freqs):
        delay = int(0.02 * k * SR)
        seg_n = n - delay
        tone = sine(seg_n, SR, f) * exp_decay(seg_n, SR, 0.18)
        parts.append((tone, delay, 0.5 / (k + 1)))
    return mix_at(n, *parts)


def gen_damage_taken(rng: np.random.Generator, i: int) -> np.ndarray:
    n = int(0.22 * SR)
    crack_n = int(0.02 * SR)
    crack = bandpass(white_noise(crack_n, rng), 800, 4000, order=3) * exp_decay(crack_n, SR, 0.008)
    thump_n = int(0.15 * SR)
    thump = pitched_sweep(thump_n, SR, 140, 55, shape="tri", curve=3.0) * exp_decay(thump_n, SR, 0.07)
    thump = lowpass(thump, 300, order=2)
    return mix_at(n, (crack, 0, 0.7), (thump, 0, 0.8))


def gen_death(rng: np.random.Generator, i: int) -> np.ndarray:
    n = int(0.7 * SR)
    tone = pitched_sweep(n, SR, 320, 60, shape="sine", curve=1.6) * exp_decay(n, SR, 0.35)
    tail = feedback_tail(n, SR, 0.4, 1200, rng)
    return tone * 0.7 + tail * 0.25


def gen_footstep(rng: np.random.Generator, i: int, sprint: bool) -> np.ndarray:
    n = int((0.14 if sprint else 0.16) * SR)
    thump_n = int(n * 0.5)
    thump = pitched_sweep(thump_n, SR, 150 if sprint else 120, 55, shape="tri", curve=3.0) * exp_decay(thump_n, SR, 0.04)
    thump = lowpass(thump, 350, order=2)
    scuff = bandpass(white_noise(n, rng), 500, 4500, order=3) * exp_decay(n, SR, 0.03 if sprint else 0.045)
    return mix_at(n, (thump, 0, 0.9 if sprint else 0.7), (scuff, 0, 0.5 if sprint else 0.35))


def gen_jump(rng: np.random.Generator, i: int) -> np.ndarray:
    n = int(0.15 * SR)
    rise = pitched_sweep(n, SR, 200, 520, shape="sine", curve=1.0) * exp_decay(n, SR, 0.08)
    push_n = int(0.04 * SR)
    push = bandpass(white_noise(push_n, rng), 300, 2000, order=3) * exp_decay(push_n, SR, 0.02)
    return mix_at(n, (rise, 0, 0.4), (push, 0, 0.5))


def gen_land(rng: np.random.Generator, i: int) -> np.ndarray:
    n = int(0.22 * SR)
    thump_n = int(n * 0.7)
    thump = pitched_sweep(thump_n, SR, 130, 45, shape="tri", curve=3.0) * exp_decay(thump_n, SR, 0.08)
    thump = lowpass(thump, 300, order=2)
    dust = bandpass(white_noise(n, rng), 400, 3500, order=3) * exp_decay(n, SR, 0.06)
    return mix_at(n, (thump, 0, 1.0), (dust, 0, 0.35))


def gen_dive_whoosh(rng: np.random.Generator, i: int) -> np.ndarray:
    n = int(0.35 * SR)
    noise = white_noise(n, rng)
    out = np.zeros(n)
    step = 800
    centers = np.linspace(3500, 500, n)
    for s in range(0, n, step):
        seg = noise[s:s + step]
        if seg.size == 0:
            continue
        c = centers[s]
        out[s:s + step] = bandpass(seg, max(c - 400, 50), c + 400, order=2)
    attack = int(0.03 * SR)
    if attack > 0:
        out[:attack] *= np.linspace(0.0, 1.0, attack)
    out *= exp_decay(n, SR, 0.15)
    return out


def gen_roll(rng: np.random.Generator, i: int) -> np.ndarray:
    n = int(0.5 * SR)
    tex = bandpass(white_noise(n, rng), 300, 3000, order=3)
    lfo = 0.6 + 0.4 * np.sin(2 * np.pi * 6.0 * np.arange(n) / SR)
    return tex * lfo * exp_decay(n, SR, 0.22)


def gen_stun_twinkle(rng: np.random.Generator, i: int) -> np.ndarray:
    n = int(0.6 * SR)
    notes = [880.0, 1175.0, 1568.0, 2093.0]
    parts = []
    for k, f in enumerate(notes):
        start = int(k * 0.09 * SR)
        seg_n = min(int(0.18 * SR), n - start)
        if seg_n <= 0:
            continue
        t = np.arange(seg_n) / SR
        mod = np.sin(2 * np.pi * f * 2.01 * t) * 0.3
        tone = np.sin(2 * np.pi * f * t + mod) * exp_decay(seg_n, SR, 0.09)
        parts.append((tone, start, 0.45))
    return mix_at(n, *parts)


def gen_dash(rng: np.random.Generator, i: int) -> np.ndarray:
    n = int(0.3 * SR)
    noise = bandpass(white_noise(n, rng), 400, 4000, order=3) * exp_decay(n, SR, 0.12)
    riser = pitched_sweep(n, SR, 150, 900, shape="sine", curve=1.2) * exp_decay(n, SR, 0.14)
    return noise * 0.5 + riser * 0.35


def gen_heal(rng: np.random.Generator, i: int) -> np.ndarray:
    n = int(0.5 * SR)
    parts = []
    for k, f in enumerate([440.0, 660.0]):
        start = int(k * 0.06 * SR)
        seg_n = n - start
        tone = sine(seg_n, SR, f) * exp_decay(seg_n, SR, 0.28)
        parts.append((tone, start, 0.4))
    return mix_at(n, *parts)


def gen_wall_slam(rng: np.random.Generator, i: int) -> np.ndarray:
    n = int(0.35 * SR)
    thump_n = int(n * 0.6)
    thump = pitched_sweep(thump_n, SR, 100, 35, shape="tri", curve=3.0) * exp_decay(thump_n, SR, 0.1)
    thump = lowpass(thump, 250, order=2)
    debris = bandpass(white_noise(n, rng), 600, 4500, order=3) * exp_decay(n, SR, 0.15)
    return mix_at(n, (thump, 0, 1.0), (debris, 0, 0.4))


def gen_ult(rng: np.random.Generator, i: int) -> np.ndarray:
    n = int(1.1 * SR)
    riser = pitched_sweep(n, SR, 100, 700, shape="saw", curve=0.8) * (np.linspace(0, 1, n) ** 1.5)
    riser = lowpass(riser, 2500, order=3)
    chord = np.zeros(n)
    for f in [220.0, 277.0, 330.0, 440.0]:
        chord += sine(n, SR, f) * 0.15
    chord *= exp_decay(n, SR, 0.5)
    tail = feedback_tail(n, SR, 0.6, 2000, rng)
    return riser * 0.5 + chord * 0.4 + tail * 0.25


def gen_smoke(rng: np.random.Generator, i: int) -> np.ndarray:
    n = int(0.6 * SR)
    puff = bandpass(pink_noise(n, rng), 300, 2500, order=3)
    env = adsr(n, SR, 0.03, 0.1, 0.4, sustain_level=0.5)
    return puff * env * 0.6


def gen_flash(rng: np.random.Generator, i: int) -> np.ndarray:
    n = int(0.12 * SR)
    burst = bandpass(white_noise(n, rng), 2000, 9000, order=4) * exp_decay(n, SR, 0.03)
    ring = sine(n, SR, 3500) * exp_decay(n, SR, 0.02)
    return burst * 0.6 + ring * 0.3


def gen_reveal(rng: np.random.Generator, i: int) -> np.ndarray:
    n = int(0.35 * SR)
    tone = pitched_sweep(n, SR, 700, 1400, shape="sine", curve=1.5) * exp_decay(n, SR, 0.18)
    shimmer = sine(n, SR, 2800) * exp_decay(n, SR, 0.05) * 0.2
    return tone * 0.5 + shimmer


def gen_ability_generic(rng: np.random.Generator, i: int) -> np.ndarray:
    n = int(0.28 * SR)
    tone = sine(n, SR, 520) * exp_decay(n, SR, 0.15)
    noise = bandpass(white_noise(n, rng), 500, 3000, order=3) * exp_decay(n, SR, 0.1)
    return tone * 0.35 + noise * 0.3


def gen_ui_hover(rng: np.random.Generator, i: int) -> np.ndarray:
    n = int(0.07 * SR)
    return sine(n, SR, 900 + i * 40) * exp_decay(n, SR, 0.03) * 0.35


def gen_ui_click(rng: np.random.Generator, i: int) -> np.ndarray:
    n = int(0.06 * SR)
    tone = sine(n, SR, 1300 + i * 60) * exp_decay(n, SR, 0.025)
    click = resonant_click(int(0.008 * SR), SR, 4000, 15, rng)
    return mix_at(n, (tone, 0, 0.4), (click, 0, 0.4))


def gen_ui_back(rng: np.random.Generator, i: int) -> np.ndarray:
    n = int(0.1 * SR)
    return pitched_sweep(n, SR, 1100, 700, shape="sine", curve=1.5) * exp_decay(n, SR, 0.05) * 0.4


def gen_ui_buy(rng: np.random.Generator, i: int) -> np.ndarray:
    n = int(0.35 * SR)
    parts = []
    for k, f in enumerate([660.0, 990.0]):
        start = int(k * 0.05 * SR)
        seg_n = n - start
        tone = sine(seg_n, SR, f) * exp_decay(seg_n, SR, 0.16)
        parts.append((tone, start, 0.35))
    return mix_at(n, *parts)


def gen_round_start(rng: np.random.Generator, i: int) -> np.ndarray:
    n = int(0.8 * SR)
    out = np.zeros(n)
    for f in [440.0, 554.0, 659.0]:
        out += sine(n, SR, f) * 0.2
    out *= adsr(n, SR, 0.05, 0.15, 0.5, sustain_level=0.6)
    return out


def gen_round_win(rng: np.random.Generator, i: int) -> np.ndarray:
    n = int(1.2 * SR)
    notes = [523.0, 659.0, 784.0, 1046.0]
    parts = []
    for k, f in enumerate(notes):
        start = int(k * 0.09 * SR)
        seg_n = n - start
        tone = sine(seg_n, SR, f) * exp_decay(seg_n, SR, 0.35)
        parts.append((tone, start, 0.3))
    return mix_at(n, *parts)


def gen_round_lose(rng: np.random.Generator, i: int) -> np.ndarray:
    n = int(1.0 * SR)
    notes = [440.0, 392.0, 330.0]
    parts = []
    for k, f in enumerate(notes):
        start = int(k * 0.12 * SR)
        seg_n = n - start
        tone = sine(seg_n, SR, f) * exp_decay(seg_n, SR, 0.4)
        parts.append((tone, start, 0.3))
    return mix_at(n, *parts)


def gen_hardpoint_tick(rng: np.random.Generator, i: int) -> np.ndarray:
    n = int(0.1 * SR)
    return sine(n, SR, 1000) * exp_decay(n, SR, 0.04) * 0.4


def gen_bomb_beep(rng: np.random.Generator, i: int) -> np.ndarray:
    n = int(0.12 * SR)
    return sine(n, SR, 1500) * exp_decay(n, SR, 0.05) * 0.5


def gen_bomb_plant(rng: np.random.Generator, i: int) -> np.ndarray:
    n = int(0.5 * SR)
    clunk_n = int(0.02 * SR)
    clunk = resonant_click(clunk_n, SR, 900, 8, rng) * exp_decay(clunk_n, SR, 0.05)
    beep_n = int(0.15 * SR)
    beep = sine(beep_n, SR, 1200) * exp_decay(beep_n, SR, 0.08)
    return mix_at(n, (clunk, 0, 0.8), (beep, int(0.1 * SR), 0.4))


def gen_bomb_defuse(rng: np.random.Generator, i: int) -> np.ndarray:
    n = int(0.5 * SR)
    parts = []
    for k in range(3):
        start = int(k * 0.08 * SR)
        c_n = int(0.01 * SR)
        c = resonant_click(c_n, SR, 2500, 14, rng) * exp_decay(c_n, SR, 0.02)
        parts.append((c, start, 0.5))
    tone_n = int(0.2 * SR)
    tone = pitched_sweep(tone_n, SR, 900, 500, shape="sine", curve=1.5) * exp_decay(tone_n, SR, 0.1)
    parts.append((tone, int(0.26 * SR), 0.4))
    return mix_at(n, *parts)


def render_slide_loop_body(n: int, sr: int, rng: np.random.Generator) -> np.ndarray:
    tex = bandpass(pink_noise(n, rng), 700, 5000, order=3)
    lfo = 0.85 + 0.15 * np.sin(2 * np.pi * 3.2 * np.arange(n) / sr)
    return tex * lfo * 0.5


def render_menu_loop() -> np.ndarray:
    duration = 75.0
    crossfade = 3.0
    base_freqs = [146.83, 174.61, 220.0, 293.66]  # ré mineur-ish : ambiance encre/papier, doux

    def body(n: int, sr: int) -> np.ndarray:
        t = np.arange(n) / sr
        pad = np.zeros(n)
        for k, f in enumerate(base_freqs):
            lfo = 1.0 + 0.004 * np.sin(2 * np.pi * (0.02 + 0.005 * k) * t + k)
            pad += np.sin(2 * np.pi * f * lfo * t) * (0.10 / (k * 0.3 + 1))
        pad = lowpass(pad, 1800, sr, order=2)
        rng_local = rng_for("menu_loop_texture")
        hiss = bandpass(pink_noise(n, rng_local), 400, 6000, sr, order=2) * 0.05
        swell = 0.75 + 0.25 * np.sin(2 * np.pi * 0.05 * t)
        return (pad + hiss) * swell

    return render_seamless(duration, SR, body, crossfade_s=crossfade)


# ============================================================== registre

SOUNDS: Dict[str, Dict] = {}
for _cls in GUN_CLASSES:
    SOUNDS[f"gunshot_{_cls}"] = dict(count=3, gen=(lambda rng, i, c=_cls: gen_gunshot(rng, i, c)))
    SOUNDS[f"gunshot_{_cls}_far"] = dict(count=1, gen=(lambda rng, i, c=_cls: gen_gunshot_far(rng, i, c)))

SOUNDS.update({
    "reload_out": dict(count=3, gen=gen_reload_out),
    "reload_in": dict(count=3, gen=gen_reload_in),
    "dry_fire": dict(count=2, gen=gen_dry_fire),
    "equip": dict(count=2, gen=gen_equip),
    "hitmarker": dict(count=2, gen=gen_hitmarker),
    "headshot": dict(count=2, gen=gen_headshot),
    "kill_confirm": dict(count=1, gen=gen_kill_confirm),
    "damage_taken": dict(count=3, gen=gen_damage_taken),
    "death": dict(count=2, gen=gen_death),
    "footstep_walk": dict(count=4, gen=(lambda rng, i: gen_footstep(rng, i, False))),
    "footstep_sprint": dict(count=4, gen=(lambda rng, i: gen_footstep(rng, i, True))),
    "jump": dict(count=2, gen=gen_jump),
    "land": dict(count=2, gen=gen_land),
    "dive_whoosh": dict(count=2, gen=gen_dive_whoosh),
    "roll": dict(count=2, gen=gen_roll),
    "stun_twinkle": dict(count=2, gen=gen_stun_twinkle),
    "dash": dict(count=2, gen=gen_dash),
    "heal": dict(count=2, gen=gen_heal),
    "wall_slam": dict(count=2, gen=gen_wall_slam),
    "ult": dict(count=1, gen=gen_ult),
    "smoke": dict(count=2, gen=gen_smoke),
    "flash": dict(count=1, gen=gen_flash),
    "reveal": dict(count=2, gen=gen_reveal),
    "ability_generic": dict(count=2, gen=gen_ability_generic),
    "ui_hover": dict(count=2, gen=gen_ui_hover),
    "ui_click": dict(count=2, gen=gen_ui_click),
    "ui_back": dict(count=1, gen=gen_ui_back),
    "ui_buy": dict(count=1, gen=gen_ui_buy),
    "round_start": dict(count=1, gen=gen_round_start),
    "round_win": dict(count=1, gen=gen_round_win),
    "round_lose": dict(count=1, gen=gen_round_lose),
    "hardpoint_tick": dict(count=1, gen=gen_hardpoint_tick),
    "bomb_beep": dict(count=1, gen=gen_bomb_beep),
    "bomb_plant": dict(count=1, gen=gen_bomb_plant),
    "bomb_defuse": dict(count=1, gen=gen_bomb_defuse),
})

LOOP_SOUNDS: Dict[str, Dict] = {
    "slide_loop": dict(count=1, gen=(lambda rng, i: render_seamless(1.2, SR, (lambda n, sr: render_slide_loop_body(n, sr, rng)), crossfade_s=0.25))),
}


# ============================================================== écriture + mesure


def write_wav(path: Path, x: np.ndarray, sr: int = SR) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    x = np.clip(x, -1.0, 1.0)
    pcm = (x * 32767.0).astype(np.int16)
    wavfile.write(str(path), sr, pcm)


def measure(path: Path, category: str, is_loop: bool = False) -> Dict:
    sr, data = wavfile.read(str(path))
    x = data.astype(np.float64) / 32768.0
    peak = float(np.max(np.abs(x))) if x.size else 0.0
    rms = float(np.sqrt(np.mean(x ** 2))) if x.size else 0.0
    dc = float(np.mean(x)) if x.size else 0.0
    seam: Optional[float] = None
    if is_loop and x.size > 2:
        seam = float(abs(x[0] - x[-1]))
    return dict(
        path=path, category=category, duration=len(x) / sr if sr else 0.0,
        peak_db=amp_to_db(peak), rms_db=amp_to_db(rms), dc=dc, seam=seam, is_loop=is_loop, n=len(x),
    )


def print_table(stats: List[Dict]) -> None:
    by_cat: Dict[str, List[Dict]] = {}
    for s in stats:
        by_cat.setdefault(s["category"], []).append(s)

    header = f'{"catégorie":<22}{"n":>3}  {"durée moy.":>11}  {"pic dBFS":>10}  {"RMS dBFS":>10}  {"|DC| max":>10}  {"seam max":>10}'
    print(header)
    print("-" * len(header))
    for cat in sorted(by_cat.keys()):
        rows = by_cat[cat]
        n = len(rows)
        avg_dur = sum(r["duration"] for r in rows) / n
        avg_peak = sum(r["peak_db"] for r in rows) / n
        avg_rms = sum(r["rms_db"] for r in rows) / n
        max_dc = max(abs(r["dc"]) for r in rows)
        seams = [r["seam"] for r in rows if r["seam"] is not None]
        seam_txt = f"{max(seams):.4f}" if seams else "-"
        print(f"{cat:<22}{n:>3}  {avg_dur:>10.3f}s  {avg_peak:>9.2f}d  {avg_rms:>9.2f}d  {max_dc:>10.5f}  {seam_txt:>10}")


def verify(stats: List[Dict]) -> bool:
    ok = True
    for s in stats:
        if not (PEAK_DBFS - 0.6 <= s["peak_db"] <= PEAK_DBFS + 0.4):
            print(f"[FAIL] {s['path'].name}: pic {s['peak_db']:.2f} dBFS hors cible ({PEAK_DBFS} dBFS)")
            ok = False
        if abs(s["dc"]) >= 0.003:
            print(f"[FAIL] {s['path'].name}: offset DC {s['dc']:.5f} trop élevé")
            ok = False
        if s["is_loop"] and s["seam"] is not None and s["seam"] >= 0.01:
            print(f"[FAIL] {s['path'].name}: couture de boucle discontinue (delta={s['seam']:.4f})")
            ok = False
        if s["n"] <= 0:
            print(f"[FAIL] {s['path'].name}: fichier vide")
            ok = False
    return ok


# ============================================================== main


def main() -> int:
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except (AttributeError, ValueError):
        pass  # flux déjà UTF-8 ou non reconfigurable (ex. redirigé) : tant pis pour les accents

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", default="assets/audio", help="dossier de sortie (relatif à la racine du repo)")
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parents[2]
    out_sfx = repo_root / args.out / "sfx"
    out_music = repo_root / args.out / "music"
    out_sfx.mkdir(parents=True, exist_ok=True)
    out_music.mkdir(parents=True, exist_ok=True)

    stats: List[Dict] = []

    for name, spec in SOUNDS.items():
        for i in range(spec["count"]):
            rng = rng_for(f"{name}_{i}")
            raw = spec["gen"](rng, i)
            x = finalize(raw, loop=False)
            path = out_sfx / f"{name}_{i + 1}.wav"
            write_wav(path, x)
            stats.append(measure(path, name))

    for name, spec in LOOP_SOUNDS.items():
        for i in range(spec["count"]):
            rng = rng_for(f"{name}_{i}")
            raw = spec["gen"](rng, i)
            x = finalize(raw, loop=True)
            path = out_sfx / f"{name}_{i + 1}.wav"
            write_wav(path, x)
            stats.append(measure(path, name, is_loop=True))

    menu = finalize(render_menu_loop(), loop=True)
    menu_path = out_music / "menu_loop.wav"
    write_wav(menu_path, menu)
    stats.append(measure(menu_path, "menu_loop", is_loop=True))

    print_table(stats)
    ok = verify(stats)
    total_files = len(stats)
    total_names = len(SOUNDS) + len(LOOP_SOUNDS) + 1
    print(f"\n{total_files} fichiers générés pour {total_names} sons logiques (variations comprises).")
    if not ok:
        print("ÉCHEC : au moins une vérification a échoué (voir [FAIL] ci-dessus).")
        return 1
    print("OK : pic/-1 dBFS, offset DC, coutures de boucle — toutes les vérifications passent.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
