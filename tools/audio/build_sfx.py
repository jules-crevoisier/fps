"""build_sfx.py — construit TOUS les bruitages du jeu depuis des sources CC0 réelles.

Remplace les anciens sons synthétisés (jugés « dégueulasses » par l'utilisateur, 2026-09-27).
Sources (téléchargées avec l'accord de l'utilisateur, jamais versionnées : art/audio/source/) :
  - The Free Firearm Sound Library (CC0, Jaszczak/Nelson/Heras/Nanney) — vraies armes, 96 kHz ;
  - Kenney Impact Sounds / RPG Audio / Interface Sounds (CC0, kenney.nl).
Chaque son est découpé, filtré, superposé et normalisé ici (numpy/scipy, E/S via ffmpeg), puis
écrit en WAV 16 bits mono 48 kHz sous assets/audio/sfx/<nom>_<n>.wav — les noms que Audio.gd
attend. La provenance de chaque fichier est écrite dans assets/audio/sfx/PROVENANCE.md.

    python tools/audio/build_sfx.py            # tout
    python tools/audio/build_sfx.py gun ui     # seulement certains groupes
"""
import io
import json
import os
import subprocess
import sys

import numpy as np
import scipy.signal as ss
from scipy.io import wavfile

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SRC = os.path.join(ROOT, "art", "audio", "source")
FIRE = os.path.join(SRC, "firearm", "Prepared SFX Library")
IMP = os.path.join(SRC, "kenney_impact-sounds", "Audio")
RPG = os.path.join(SRC, "kenney_rpg-audio", "Audio")
UIS = os.path.join(SRC, "kenney_interface-sounds", "Audio")
OUT = os.path.join(ROOT, "assets", "audio", "sfx")
SR = 48000
RNG = np.random.default_rng(20260927)

_PROV = {}          # nom de fichier -> liste de sources
_CACHE = {}


# ------------------------------------------------------------------ E/S
def load(path):
    """Fichier audio -> float32 mono 48 kHz (ffmpeg)."""
    if path in _CACHE:
        return _CACHE[path]
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-f", "f32le", "-ac", "1", "-ar", str(SR), "-"],
                         capture_output=True, check=True).stdout
    x = np.frombuffer(raw, dtype=np.float32).astype(np.float64)
    _CACHE[path] = x
    return x


def fire(folder, name=None):
    """Chemin d'un enregistrement ; sans nom, le DOSSIER (prises choisies par _resolve_pair)."""
    return os.path.join(FIRE, folder, name) if name else os.path.join(FIRE, folder)


def save(name, idx, x, sources):
    x = np.asarray(x, dtype=np.float64)
    x = np.nan_to_num(x)
    peak = np.max(np.abs(x)) if x.size else 0.0
    if peak > 0.999:            # jamais d'écrêtage numérique
        x = x * (0.999 / peak)
    fn = f"{name}_{idx}.wav"
    wavfile.write(os.path.join(OUT, fn), SR, (x * 32767.0).astype(np.int16))
    _PROV[fn] = sorted(set(os.path.relpath(s, SRC).replace("\\", "/") if os.path.isabs(s) else s for s in sources))
    return fn


# ------------------------------------------------------------------ outils DSP
def db(v):
    return 10.0 ** (v / 20.0)


def peak_norm(x, dbfs):
    p = np.max(np.abs(x))
    return x * (db(dbfs) / p) if p > 0 else x


def fade(x, fin_ms=1.0, fout_ms=20.0):
    x = x.copy()
    n_in = max(1, int(SR * fin_ms / 1000))
    n_out = max(1, int(SR * fout_ms / 1000))
    n_in = min(n_in, len(x))
    n_out = min(n_out, len(x))
    x[:n_in] *= np.linspace(0.0, 1.0, n_in)
    x[-n_out:] *= np.linspace(1.0, 0.0, n_out) ** 2
    return x


def butter(x, kind, f, order=4):
    sos = ss.butter(order, f, btype=kind, fs=SR, output="sos")
    return ss.sosfilt(sos, x)      # causal : garde l'attaque intacte (pas de pré-écho)


def hp(x, f, order=4):
    return butter(x, "highpass", f, order)


def lp(x, f, order=4):
    return butter(x, "lowpass", f, order)


def bp(x, lo, hi, order=2):
    return butter(x, "bandpass", [lo, hi], order)


def peq(x, f0, gain_db, q=1.0):
    """Filtre en cloche (RBJ)."""
    a = db(gain_db / 2.0)
    w0 = 2 * np.pi * f0 / SR
    alpha = np.sin(w0) / (2 * q)
    b = [1 + alpha * a, -2 * np.cos(w0), 1 - alpha * a]
    aa = [1 + alpha / a, -2 * np.cos(w0), 1 - alpha / a]
    return ss.lfilter(np.array(b) / aa[0], np.array(aa) / aa[0], x)


def shelf_low(x, f0, gain_db):
    a = db(gain_db / 2.0)
    w0 = 2 * np.pi * f0 / SR
    alpha = np.sin(w0) / 2 * np.sqrt(2)
    cw = np.cos(w0)
    b = [a * ((a + 1) - (a - 1) * cw + 2 * np.sqrt(a) * alpha), 2 * a * ((a - 1) - (a + 1) * cw),
         a * ((a + 1) - (a - 1) * cw - 2 * np.sqrt(a) * alpha)]
    aa = [(a + 1) + (a - 1) * cw + 2 * np.sqrt(a) * alpha, -2 * ((a - 1) + (a + 1) * cw),
          (a + 1) + (a - 1) * cw - 2 * np.sqrt(a) * alpha]
    return ss.lfilter(np.array(b) / aa[0], np.array(aa) / aa[0], x)


def compress(x, thr_db=-18.0, ratio=4.0, attack_ms=2.0, release_ms=80.0, makeup_db=0.0):
    """Compresseur crête simple (détection enveloppe lissée)."""
    env = np.abs(x)
    a_att = np.exp(-1.0 / (SR * attack_ms / 1000.0))
    a_rel = np.exp(-1.0 / (SR * release_ms / 1000.0))
    g = np.ones_like(x)
    e = 0.0
    thr = db(thr_db)
    for i, v in enumerate(env):
        e = a_att * e + (1 - a_att) * v if v > e else a_rel * e + (1 - a_rel) * v
        if e > thr:
            g[i] = (thr * (e / thr) ** (1.0 / ratio)) / e
    return x * g * db(makeup_db)


def saturate(x, drive=1.5):
    return np.tanh(x * drive) / np.tanh(drive)


def push(x, rms_db, window_s=0.12, ceiling_db=-1.0):
    """Monte le niveau moyen des `window_s` premières secondes à `rms_db`, puis arrondit tout
    ce qui dépasse le plafond (écrêtage doux tanh) : le son gagne en densité sans jamais écrêter."""
    w = x[: int(SR * window_s)]
    r = np.sqrt(np.mean(w ** 2)) if w.size else 0.0
    if r <= 0:
        return x
    y = x * (db(rms_db) / r)
    c = db(ceiling_db)
    return c * np.tanh(y / c)


def pitch(x, ratio):
    """Change la hauteur ET la durée (ratio > 1 = plus aigu, plus court)."""
    from fractions import Fraction
    fr = Fraction(1.0 / ratio).limit_denominator(200)
    return ss.resample_poly(x, fr.numerator, fr.denominator)


def mix(*layers):
    """layers = (signal, gain_db, offset_ms)."""
    n = max(len(s) + int(SR * off / 1000.0) for s, _, off in layers)
    out = np.zeros(n)
    for s, g, off in layers:
        o = int(SR * off / 1000.0)
        out[o:o + len(s)] += s * db(g)
    return out


def onsets(x, rel_thr=0.3, min_gap_s=0.25):
    win = int(0.004 * SR)
    e = np.convolve(np.abs(x), np.ones(win) / win, mode="same")
    thr = rel_thr * e.max()
    idx = np.where((e[1:] > thr) & (e[:-1] <= thr))[0]
    out = []
    for o in idx:
        if not out or o - out[-1] > min_gap_s * SR:
            out.append(int(o))
    # recule jusqu'au vrai début de l'attaque (1er échantillon > 5 % du pic local)
    fixed = []
    for o in out:
        s = max(o - int(0.01 * SR), 0)
        seg = np.abs(x[s:o + int(0.01 * SR)])
        k = np.argmax(seg > 0.05 * seg.max()) if seg.size else 0
        fixed.append(s + int(k))
    return fixed


def cut(x, start, dur_s, pre_ms=1.5, fout_ms=40.0):
    s = max(0, start - int(SR * pre_ms / 1000.0))
    return fade(x[s:s + int(SR * dur_s)], 0.5, fout_ms)


def trim_silence(x, rel=0.01, tail_ms=30.0):
    a = np.abs(x)
    if a.max() == 0:
        return x
    nz = np.where(a > rel * a.max())[0]
    s, e = nz[0], min(len(x), nz[-1] + int(SR * tail_ms / 1000.0))
    return fade(x[max(0, s - int(0.001 * SR)):e], 0.5, min(tail_ms, 25.0))


def noise(dur_s):
    return RNG.standard_normal(int(SR * dur_s))


def env_exp(n, tau_s):
    return np.exp(-np.arange(n) / (SR * tau_s))


def ir(dur_s, tau_s, lp_hz, early=()):
    """Réponse impulsionnelle synthétique : échos précoces (délai ms, gain dB) + queue diffuse."""
    n = int(SR * dur_s)
    tail = lp(noise(dur_s), lp_hz, 2) * env_exp(n, tau_s)
    h = np.zeros(n)
    h += tail * 0.35
    for d_ms, g in early:
        k = int(SR * d_ms / 1000.0)
        if k < n:
            h[k:k + 64] += lp(noise(64 / SR), lp_hz, 2) * db(g)
    return h


def convolve(x, h):
    return ss.fftconvolve(x, h)[: len(x) + len(h) - 1]


# ------------------------------------------------------------------ armes
# classe -> (fichier proche, fichier moyenne distance, couche de poids optionnelle, mécanique)
GUNS = {
    # Revolver (Verrou) : .38 Special en prise proche, épaissi par le .45 du 1911 (un revolver de
    # cow-boy doit claquer et peser), mécanique = chien qu'on arme.
    "gunshot_revolver": (fire("Smith & Wesson 642", "V_27P.wav"), fire("Smith & Wesson 642", "V_22P.wav"),
                         fire("1911", "A_42P.wav"), "hammer"),
    "gunshot_magnum": (fire("1911", "A_42P.wav"), fire("1911", "A_34P.wav"),
                       fire("Smith & Wesson 642", "V_27P.wav"), "hammer"),
    "gunshot_pistol": (fire("Walther PPQ", None), fire("Walther PPQ", None), None, "slide"),
    # Ravage (AK) : AK-47 coup par coup en prise proche, moyenne distance pour le lointain.
    "gunshot_rifle": (fire("AK-47", "C_28P.wav"), fire("AK-47", "C_31P.wav"), None, "bolt"),
    "gunshot_marksman": (fire("SKS", None), fire("SKS", None), None, "bolt"),
    "gunshot_smg": (fire("Carl Gustav M45", "G_31P.wav"), fire("Carl Gustav M45", "G_20P.wav"), None, "bolt"),
    "gunshot_shotgun": (fire("CD", "H_21P.wav"), fire("CD", "H_16P.wav"), None, "pump"),
    "gunshot_sniper": (fire("Savage 10 .300 Blackout", None), fire("Savage 10 .300 Blackout", None), None, "bolt"),
}


def _resolve_pair(near, mid):
    """Dossier -> (1re prise « near distance », 1re autre prise) d'après les métadonnées."""
    if os.path.isdir(near):
        folder = near
        files = sorted(f for f in os.listdir(folder) if f.lower().endswith(".wav"))
        nears, mids = [], []
        for f in files:
            c = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format_tags=comment", "-of",
                                "default=nw=1:nk=1", os.path.join(folder, f)], capture_output=True, text=True).stdout
            (nears if "near distance" in c else mids).append(os.path.join(folder, f))
        near = nears[0] if nears else os.path.join(folder, files[0])
        mid = mids[0] if mids else near
    return near, mid


def mech_sound(kind, variant):
    click = load(os.path.join(RPG, "metalClick.ogg"))
    latch = load(os.path.join(RPG, "metalLatch.ogg"))
    srcs = [os.path.join(RPG, "metalClick.ogg"), os.path.join(RPG, "metalLatch.ogg")]
    if kind == "hammer":      # chien du revolver : clic sec, un peu plus grave à chaque variante
        x = mix((pitch(trim_silence(click), 1.25 - 0.1 * variant), 0, 0), (hp(trim_silence(latch), 900), -9, 18))
    elif kind == "pump":
        x = mix((pitch(trim_silence(latch), 0.8), 0, 0), (pitch(trim_silence(click), 0.9), -3, 140))
    else:                      # culasse / glissière : claquement métallique court
        x = mix((pitch(trim_silence(latch), 1.35 + 0.08 * variant), 0, 0), (hp(trim_silence(click), 1500), -6, 6))
    return peak_norm(hp(x, 300), -16), srcs


def build_guns():
    tails_src = []
    for name, (near, mid, weight, mech) in GUNS.items():
        near, mid = _resolve_pair(near, mid)
        xn, xm = load(near), load(mid)
        on_n, on_m = onsets(xn), onsets(xm)
        srcs = [near, mid]
        w = None
        if weight:
            w = load(weight)
            srcs.append(weight)
            on_w = onsets(w)
        shots = []
        for k in range(3):
            o = on_n[k % len(on_n)]
            body = hp(cut(xn, o, 0.85, fout_ms=250), 45)
            if w is not None:
                ow = on_w[k % len(on_w)]
                wb = lp(hp(cut(w, ow, 0.6, fout_ms=200), 45), 1500)
                body = mix((body, 0, 0), (wb, -2, 0))   # le .45 donne du poids au .38
            body = shelf_low(peq(body, 3200, 2.5, 0.8), 140, 3.0)
            # chaîne « jeu vidéo » : un vrai coup de feu a ~30 dB d'écart crête/moyenne, inaudible
            # à côté du reste du mix. Normalisé, puis compressé fort avec une attaque qui laisse
            # passer le claquement (3 ms), puis saturé doucement : le tir claque ET remplit.
            body = compress(peak_norm(body, -1), -24, 4.0, 3.0, 70, 0)
            shots.append(push(body, -14.5, 0.12, -1.0))
        # couches du tir LOCAL
        for k in range(2):
            save(f"{name}_body", k + 1, shots[k], srcs)
            o = on_n[k % len(on_n)]
            tr = hp(cut(xn, o, 0.05, fout_ms=35), 2200)
            save(f"{name}_transient", k + 1, peak_norm(saturate(tr * 3.0, 1.2), -9), srcs)
            mx, msrc = mech_sound(mech, k)
            save(f"{name}_mech", k + 1, mx, msrc)
        n = int(SR * 0.32)
        f = np.linspace(85.0, 42.0, n)
        sub = np.sin(2 * np.pi * np.cumsum(f) / SR) * env_exp(n, 0.07)
        sub = mix((sub, 0, 0), (lp(shots[0], 140, 4)[:n], -2, 0))
        save(f"{name}_sub", 1, peak_norm(fade(sub, 1, 60), -5), srcs + ["synthèse (sinus 85->42 Hz)"])
        # tir pré-mixé (tirs des AUTRES joueurs, positionnel) + version lointaine
        for k in range(3):
            save(name, k + 1, shots[k], srcs)
        om = on_m[0]
        far = lp(hp(cut(xm, om, 1.4, fout_ms=500), 90), 2600, 2)
        far = convolve(far, ir(1.2, 0.35, 2200, ((140, -8), (320, -12))))[: int(SR * 1.8)]
        save(f"{name}_far", 1, peak_norm(fade(far, 1, 400), -7), [mid])
        tails_src.append(mid)
    # queues de réverbération partagées (extérieur : échos sur conteneurs ; intérieur : court, dense)
    imp = np.zeros(8)
    imp[0] = 1.0
    for k in range(2):
        out = convolve(imp, ir(1.6, 0.42 + 0.06 * k, 3200, ((95 + 30 * k, -3), (210, -7), (380 + 40 * k, -10))))
        out = lp(out, 2600, 4)   # extérieur : réflexions sur conteneurs, sombres et lointaines
        save("tail_outdoor", k + 1, peak_norm(fade(hp(out, 150), 1, 500), -14), ["synthèse (réponse impulsionnelle)"])
        out = convolve(imp, ir(0.7, 0.14 + 0.03 * k, 4200, ((18, -2), (37, -4), (61, -7))))
        save("tail_indoor", k + 1, peak_norm(fade(hp(out, 180), 1, 200), -13), ["synthèse (réponse impulsionnelle)"])


# ------------------------------------------------------------------ revolver : rechargement / éventail
def build_revolver_foley():
    click = trim_silence(load(os.path.join(RPG, "metalClick.ogg")))
    latch = trim_silence(load(os.path.join(RPG, "metalLatch.ogg")))
    tin = [trim_silence(load(os.path.join(IMP, f"impactTin_medium_00{i}.ogg"))) for i in range(5)]
    glass = [trim_silence(load(os.path.join(IMP, f"impactGlass_light_00{i}.ogg"))) for i in range(5)]
    plate = [trim_silence(load(os.path.join(IMP, f"impactPlate_light_00{i}.ogg"))) for i in range(5)]
    s_click, s_latch = os.path.join(RPG, "metalClick.ogg"), os.path.join(RPG, "metalLatch.ogg")
    s_tin = os.path.join(IMP, "impactTin_medium_000.ogg")
    s_glass = os.path.join(IMP, "impactGlass_light_000.ogg")
    s_plate = os.path.join(IMP, "impactPlate_light_000.ogg")
    # barillet qui bascule (bras qui s'ouvre) : déclic + glissement métallique
    save("rev_crane_open", 1, peak_norm(hp(mix((pitch(latch, 1.1), 0, 0), (pitch(click, 0.85), -4, 25)), 250), -12), [s_latch, s_click])
    # éjection : six douilles laiton qui tintent en cascade
    casings = mix(*[(pitch(glass[i % 5], 1.6 + 0.12 * (i % 3)), -3 - i, 30 + i * 28 + int(RNG.integers(0, 12))) for i in range(6)],
                  (pitch(tin[1], 1.8), -8, 10))
    save("rev_eject", 1, peak_norm(hp(casings, 700), -13), [s_glass, s_tin])
    # chargeur rapide : cliquetis des balles qui entrent + clic de libération
    load_s = mix((pitch(tin[2], 1.3), 0, 0), (pitch(plate[0], 1.5), -6, 12), (pitch(click, 1.4), -3, 180))
    save("rev_load", 1, peak_norm(hp(load_s, 400), -13), [s_tin, s_plate, s_click])
    # barillet refermé d'un coup de poignet : claquement franc
    close = mix((pitch(latch, 0.95), 0, 0), (pitch(plate[3], 1.1), -2, 4), (lp(pitch(plate[3], 0.7), 900), -6, 4))
    save("rev_crane_close", 1, peak_norm(hp(close, 150), -9), [s_latch, s_plate])
    # barillet lancé : cliquet qui ralentit (inspection / fin de rechargement)
    parts, t = [], 0.0
    for i in range(16):
        parts.append((pitch(click, 1.9 + 0.1 * (i % 2)), -2 - i * 0.9, t))
        t += 28 + i * 9
    save("rev_spin", 1, peak_norm(hp(mix(*parts), 1200), -15), [s_click])
    # chien armé (tir en éventail, entre deux coups) : clac court et sec
    for k in range(2):
        cock = mix((pitch(click, 1.05 + 0.08 * k), 0, 0), (hp(pitch(latch, 1.3), 1500), -8, 10))
        save("rev_hammer", k + 1, peak_norm(hp(cock, 400), -13), [s_click, s_latch])


# ------------------------------------------------------------------ foley générique (Ravage, équipement)
def build_foley():
    click = trim_silence(load(os.path.join(RPG, "metalClick.ogg")))
    latch = trim_silence(load(os.path.join(RPG, "metalLatch.ogg")))
    cloth = [trim_silence(load(os.path.join(RPG, f"cloth{i}.ogg"))) for i in range(1, 5)]
    plate = [trim_silence(load(os.path.join(IMP, f"impactPlate_light_00{i}.ogg"))) for i in range(5)]
    metal = [trim_silence(load(os.path.join(IMP, f"impactMetal_light_00{i}.ogg"))) for i in range(5)]
    S = lambda *n: [os.path.join(RPG if "." in x and not x.startswith("impact") else IMP, x) for x in n]
    for k in range(3):   # chargeur retiré / inséré (Ravage)
        out = mix((pitch(latch, 1.0 + 0.05 * k), 0, 0), (pitch(metal[k], 1.2), -6, 40), (cloth[k % 4], -16, 0))
        save("reload_out", k + 1, peak_norm(hp(out, 200), -12), S("metalLatch.ogg", f"impactMetal_light_00{k}.ogg", f"cloth{k % 4 + 1}.ogg"))
        inn = mix((pitch(plate[k], 1.05), 0, 0), (pitch(latch, 0.85 + 0.05 * k), -2, 70), (pitch(click, 1.1), -5, 110))
        save("reload_in", k + 1, peak_norm(hp(inn, 180), -10), S(f"impactPlate_light_00{k}.ogg", "metalLatch.ogg", "metalClick.ogg"))
    for k in range(2):   # sortie d'arme : tissu + cliquetis
        eq = mix((cloth[k], -4, 0), (pitch(latch, 1.2 + 0.1 * k), 0, 90), (pitch(click, 1.3), -6, 150))
        save("equip", k + 1, peak_norm(hp(eq, 150), -13), S(f"cloth{k + 1}.ogg", "metalLatch.ogg", "metalClick.ogg"))
        dry = mix((pitch(click, 1.15 + 0.1 * k), 0, 0), (hp(pitch(click, 2.0), 3000), -10, 2))
        save("dry_fire", k + 1, peak_norm(hp(dry, 500), -13), S("metalClick.ogg"))


# ------------------------------------------------------------------ déplacements
def build_movement():
    conc = [os.path.join(IMP, f"footstep_concrete_00{i}.ogg") for i in range(5)]
    cloth = [os.path.join(RPG, f"cloth{i}.ogg") for i in range(1, 5)]
    for k in range(4):
        st = trim_silence(load(conc[k]))
        walk = mix((hp(st, 70), 0, 0), (hp(trim_silence(load(cloth[k])), 800), -22, 0))
        save("footstep_walk", k + 1, peak_norm(peq(walk, 250, 3, 1.0), -19), [conc[k], cloth[k]])
        spr = mix((pitch(hp(st, 70), 1.06), 0, 0), (hp(trim_silence(load(cloth[(k + 1) % 4])), 900), -16, 0))
        save("footstep_sprint", k + 1, peak_norm(saturate(peq(spr, 250, 4, 1.0), 1.2), -14), [conc[k], cloth[(k + 1) % 4]])
    for k in range(4):   # pas sur le toit d'un conteneur : tôle qui résonne sous la semelle
        m = os.path.join(IMP, f"impactMetal_light_00{k}.ogg")
        st = trim_silence(load(conc[k]))
        mw = mix((lp(pitch(trim_silence(load(m)), 0.8), 4000), 0, 0), (hp(st, 120), -6, 0))
        save("footstep_metal_walk", k + 1, peak_norm(mw, -19), [m, conc[k]])
        ms = mix((lp(pitch(trim_silence(load(m)), 0.85), 5000), 0, 0), (hp(st, 120), -4, 0), (hp(trim_silence(load(cloth[k])), 900), -16, 0))
        save("footstep_metal_sprint", k + 1, peak_norm(ms, -14), [m, conc[k], cloth[k]])
    soft = [os.path.join(IMP, f"impactSoft_heavy_00{i}.ogg") for i in range(5)]
    for k in range(2):
        jump = mix((hp(trim_silence(load(cloth[k + 2])), 300), 0, 0), (hp(trim_silence(load(conc[k + 2])), 120), -10, 20))
        save("jump", k + 1, peak_norm(jump, -18), [cloth[k + 2], conc[k + 2]])
        land = mix((lp(trim_silence(load(soft[k])), 3000), 0, 0), (trim_silence(load(conc[k])), -3, 5), (pitch(trim_silence(load(conc[k + 1])), 0.8), -6, 60))
        save("land", k + 1, peak_norm(shelf_low(land, 120, 4), -11), [soft[k], conc[k], conc[k + 1]])
    # glissade : frottement granuleux en boucle (bruit filtré modulé, sans raccord audible)
    n = int(SR * 1.6)
    grit = bp(noise(1.6), 250, 3500, 2) * (0.6 + 0.4 * lp(np.abs(noise(1.6)), 18, 2) / 0.4)
    grit = grit * np.hanning(n) ** 0.15
    save("slide_loop", 1, peak_norm(grit, -18), ["synthèse (bruit filtré)"])
    # souffles (plongeon, dash, roulade) : bruit dont la bande balaie vers le haut puis retombe
    for name, dur, lo, hi, lvl in (("dash", 0.35, 400, 2400, -14), ("dive_whoosh", 0.5, 300, 1800, -14), ("roll", 0.45, 200, 1200, -16)):
        for k in range(2):
            n = int(SR * dur)
            t = np.linspace(0, 1, n)
            x = noise(dur)
            out = np.zeros(n)
            blk = 512
            for s in range(0, n, blk):
                c = lo + (hi - lo) * np.sin(np.pi * t[s]) * (0.9 + 0.2 * k)
                out[s:s + blk] = bp(x[s:s + blk], max(c * 0.6, 60), min(c * 1.4, SR / 2 - 100), 1)
            out *= np.sin(np.pi * t) ** 1.5
            save(name, k + 1, peak_norm(out, lvl), ["synthèse (souffle filtré)"])
    save("wall_slam", 1, peak_norm(mix((trim_silence(load(os.path.join(IMP, "impactMetal_heavy_000.ogg"))), 0, 0), (lp(trim_silence(load(soft[2])), 1500), -4, 0)), -9),
         [os.path.join(IMP, "impactMetal_heavy_000.ogg"), soft[2]])
    save("wall_slam", 2, peak_norm(mix((trim_silence(load(os.path.join(IMP, "impactMetal_heavy_002.ogg"))), 0, 0), (lp(trim_silence(load(soft[3])), 1500), -4, 0)), -9),
         [os.path.join(IMP, "impactMetal_heavy_002.ogg"), soft[3]])


# ------------------------------------------------------------------ retours de combat (signature BD)
def build_feedback():
    punch_m = [os.path.join(IMP, f"impactPunch_medium_00{i}.ogg") for i in range(5)]
    punch_h = [os.path.join(IMP, f"impactPunch_heavy_00{i}.ogg") for i in range(5)]
    bell = os.path.join(IMP, "impactBell_heavy_001.ogg")
    tick = os.path.join(UIS, "tick_002.ogg")
    conf = os.path.join(UIS, "confirmation_002.ogg")
    for k in range(2):   # touche : « tok » sec et court, lisible dans le vacarme
        t = hp(trim_silence(load(punch_m[k]))[: int(0.07 * SR)], 900)
        x = mix((saturate(t * 2.0, 1.4), 0, 0), (pitch(trim_silence(load(tick)), 1.2), -6, 0))
        save("hitmarker", k + 1, peak_norm(fade(x, 0.3, 25), -9), [punch_m[k], tick])
        # tête : « ding » de cloche aigu + claque
        b = pitch(trim_silence(load(bell)), 1.9 + 0.1 * k)[: int(0.45 * SR)]
        x = mix((hp(b, 1200), 0, 0), (hp(trim_silence(load(punch_m[k + 2]))[: int(0.06 * SR)], 700), -4, 0))
        save("headshot", k + 1, peak_norm(fade(x, 0.3, 200), -7), [bell, punch_m[k + 2]])
    # élimination : claque grave + cloche + jingle de validation (satisfaisant, comique)
    b = pitch(trim_silence(load(bell)), 1.5)[: int(0.7 * SR)]
    x = mix((shelf_low(trim_silence(load(punch_h[0])), 150, 4), 0, 0), (hp(b, 700), -3, 30), (trim_silence(load(conf)), -6, 60))
    save("kill_confirm", 1, peak_norm(fade(x, 0.3, 250), -5), [punch_h[0], bell, conf])
    for k in range(3):   # dégâts reçus : coup mat dans le ventre
        x = mix((lp(trim_silence(load(punch_h[k + 1])), 2500), 0, 0), (lp(noise(0.12) * env_exp(int(0.12 * SR), 0.03), 400), -10, 0))
        save("damage_taken", k + 1, peak_norm(shelf_low(x, 120, 5), -8), [punch_h[k + 1]])
    for k in range(2):   # étoiles au-dessus d'un joueur aveuglé : scintillement comique (verre + pincement)
        g = [os.path.join(UIS, f"glass_00{i}.ogg") for i in (1, 3, 5)]
        x = mix(*[(pitch(trim_silence(load(gp)), 1.4 + 0.15 * k + 0.1 * j), -3 - 2 * j, 60 * j) for j, gp in enumerate(g)],
                (pitch(trim_silence(load(os.path.join(UIS, "pluck_001.ogg"))), 1.6), -8, 20))
        save("stun_twinkle", k + 1, peak_norm(hp(x, 1500), -16), g + [os.path.join(UIS, "pluck_001.ogg")])
    soft = [os.path.join(IMP, f"impactSoft_heavy_00{i}.ogg") for i in range(5)]
    for k in range(2):   # mort : gros coup + chute
        x = mix((shelf_low(trim_silence(load(punch_h[4 - k])), 120, 5), 0, 0), (lp(trim_silence(load(soft[k + 3])), 2000), -3, 180),
                (pitch(trim_silence(load(os.path.join(IMP, "footstep_concrete_004.ogg"))), 0.6), -8, 260))
        save("death", k + 1, peak_norm(x, -6), [punch_h[4 - k], soft[k + 3]])


# ------------------------------------------------------------------ grenades
def build_grenades():
    click = trim_silence(load(os.path.join(RPG, "metalClick.ogg")))
    latch = trim_silence(load(os.path.join(RPG, "metalLatch.ogg")))
    save("grenade_pin", 1, peak_norm(hp(mix((pitch(latch, 1.5), 0, 0), (pitch(click, 1.7), -4, 120)), 800), -14),
         [os.path.join(RPG, "metalLatch.ogg"), os.path.join(RPG, "metalClick.ogg")])
    for k in range(3):   # rebonds : métal léger sur béton
        m = trim_silence(load(os.path.join(IMP, f"impactMetal_light_00{k + 1}.ogg")))
        save("grenade_bounce", k + 1, peak_norm(hp(pitch(m, 1.25 + 0.1 * k), 300), -15), [os.path.join(IMP, f"impactMetal_light_00{k + 1}.ogg")])
    # explosion de frag : fusil 12 à l'octave inférieure + grave synthétique + débris + longue queue
    near, mid = _resolve_pair(fire("CD", "H_21P.wav"), fire("CD", "H_16P.wav"))
    xs = load(near)
    o = onsets(xs)
    for k in range(2):
        blast = pitch(hp(cut(xs, o[k % len(o)], 1.2, fout_ms=500), 30), 0.52 - 0.04 * k)
        n = int(SR * 0.9)
        f = np.linspace(70.0, 28.0, n)
        boom = np.sin(2 * np.pi * np.cumsum(f) / SR) * env_exp(n, 0.22)
        deb = mix(*[(trim_silence(load(os.path.join(IMP, f"impactMining_00{i}.ogg"))), -10 - i * 2, 90 + i * 70) for i in range(5)])
        x = mix((saturate(blast * 1.6, 1.8), 0, 0), (boom, -2, 0), (hp(deb, 600), -6, 0))
        x = convolve(x, ir(1.8, 0.5, 2500, ((120, -6), (290, -9))))[: int(SR * 2.6)]
        save("explosion", k + 1, peak_norm(fade(shelf_low(x, 90, 3), 1, 800), -1),
             [near] + [os.path.join(IMP, f"impactMining_00{i}.ogg") for i in range(5)] + ["synthèse (grave)"])
    # flash : claquement très sec + éclat aigu
    p42 = fire("1911", "A_42P.wav")
    xp = load(p42)
    op = onsets(xp)
    crack = hp(cut(xp, op[0], 0.35, fout_ms=150), 1500)
    n = int(SR * 0.9)
    tt = np.arange(n) / SR
    sizzle = hp(noise(0.9), 5000, 2) * env_exp(n, 0.25) * 0.4
    x = mix((saturate(crack * 2.5, 1.6), 0, 0), (sizzle, -10, 0))
    save("flash", 1, peak_norm(fade(x, 0.5, 300), -2), [p42, "synthèse (grésillement)"])
    # acouphène du joueur aveuglé : deux sinus aigus légèrement désaccordés qui s'éteignent
    n = int(SR * 3.0)
    tt = np.arange(n) / SR
    ring = (np.sin(2 * np.pi * 3950 * tt) + 0.6 * np.sin(2 * np.pi * 4010 * tt)) * env_exp(n, 1.1)
    save("flash_ring", 1, peak_norm(fade(ring, 60, 600), -16), ["synthèse (acouphène)"])
    # fumigène : « pouf » + sifflement de gaz qui se tasse
    for k in range(2):
        n = int(SR * 2.8)
        hiss = hp(lp(noise(2.8), 4800 - 600 * k, 4), 700, 2)   # gaz sourd, pas un larsen aigu
        env = np.minimum(1.0, np.arange(n) / (SR * 0.08)) * env_exp(n, 1.1)
        pop = lp(trim_silence(load(os.path.join(IMP, f"impactPlate_heavy_00{k}.ogg"))), 2500)
        x = mix((pop, 0, 0), (hiss * env, -9, 20))
        save("smoke", k + 1, peak_norm(fade(x, 1, 700), -9), [os.path.join(IMP, f"impactPlate_heavy_00{k}.ogg"), "synthèse (sifflement)"])
    # souffle du lancer
    n = int(SR * 0.35)
    t = np.linspace(0, 1, n)
    w = bp(noise(0.35), 500, 2500, 1) * np.sin(np.pi * t) ** 2
    save("grenade_throw", 1, peak_norm(w, -17), ["synthèse (souffle)"])


# ------------------------------------------------------------------ impacts de balles
def build_impacts():
    for k in range(3):
        c = os.path.join(IMP, f"impactMining_00{k}.ogg")
        x = mix((hp(pitch(trim_silence(load(c)), 1.3), 500), 0, 0), (hp(noise(0.05) * env_exp(int(0.05 * SR), 0.01), 2500), -8, 0))
        save("impact_concrete", k + 1, peak_norm(fade(x, 0.3, 60), -12), [c])
        m = os.path.join(IMP, f"impactMetal_medium_00{k}.ogg")
        x = mix((hp(pitch(trim_silence(load(m)), 1.4), 700), 0, 0), (hp(noise(0.03) * env_exp(int(0.03 * SR), 0.006), 3000), -6, 0))
        save("impact_metal", k + 1, peak_norm(fade(x, 0.3, 120), -11), [m])
        b = os.path.join(IMP, f"impactPunch_medium_00{k + 2}.ogg")
        save("impact_body", k + 1, peak_norm(lp(trim_silence(load(b)), 3500), -12), [b])
    for k in range(2):   # balle qui frôle : souffle bref et aigu (effet Doppler)
        n = int(SR * 0.22)
        t = np.linspace(0, 1, n)
        x = hp(noise(0.22), 2200 + 600 * k, 2) * np.exp(-((t - 0.45) ** 2) / 0.02)
        save("bullet_whizz", k + 1, peak_norm(x, -16), ["synthèse (sifflement de balle)"])


# ------------------------------------------------------------------ interface
def build_ui():
    pick = {
        "ui_hover": [("tick_001.ogg", -26), ("tick_004.ogg", -26)],
        "ui_click": [("select_002.ogg", -14), ("select_005.ogg", -14)],
        "ui_back": [("back_002.ogg", -15)],
        "ui_buy": [("confirmation_001.ogg", -12)],
        "ui_toggle": [("switch_002.ogg", -16), ("switch_005.ogg", -16)],
        "ui_tab": [("scroll_002.ogg", -17), ("scroll_004.ogg", -17)],
        "ui_confirm": [("confirmation_002.ogg", -11)],
        "ui_error": [("error_004.ogg", -14)],
    }
    for name, files in pick.items():
        for k, (f, lvl) in enumerate(files):
            p = os.path.join(UIS, f)
            save(name, k + 1, peak_norm(trim_silence(load(p)), lvl), [p])


GROUPS = {"gun": build_guns, "revolver": build_revolver_foley, "foley": build_foley, "move": build_movement,
          "feedback": build_feedback, "grenade": build_grenades, "impact": build_impacts, "ui": build_ui}


def write_provenance():
    path = os.path.join(OUT, "PROVENANCE.md")
    old = {}
    js = os.path.join(OUT, "provenance.json")
    if os.path.exists(js):
        old = json.load(io.open(js, encoding="utf-8"))
    old.update(_PROV)
    io.open(js, "w", encoding="utf-8", newline="\n").write(json.dumps(old, ensure_ascii=False, indent=1, sort_keys=True) + "\n")
    lines = ["# Bruitages — provenance", "",
             "Construits par `tools/audio/build_sfx.py` (2026-09-27) depuis des sources **CC0** :",
             "- The Free Firearm Sound Library — Ben Jaszczak, Brian Nelson, Kevin Heras, Matthew Nanney (CC0) :",
             "  https://opengameart.org/content/the-free-firearm-sound-library",
             "- Kenney Impact Sounds, RPG Audio, Interface Sounds (CC0) : https://kenney.nl",
             "- « synthèse » = généré par le script lui-même.", "",
             "| Fichier | Sources |", "|---|---|"]
    for fn in sorted(old):
        lines.append(f"| {fn} | {'; '.join(old[fn])} |")
    io.open(path, "w", encoding="utf-8", newline="\n").write("\n".join(lines) + "\n")


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    wanted = sys.argv[1:] or list(GROUPS)
    for g in wanted:
        GROUPS[g]()
        print("groupe", g, "ok")
    write_provenance()
    print(len(_PROV), "fichiers écrits")
