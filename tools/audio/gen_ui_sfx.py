#!/usr/bin/env python3
"""tools/audio/gen_ui_sfx.py

Génère les signatures sonores d'interface du STYLE_BIBLE.md §8.5 (tâche
ART-39) par synthèse procédurale, en RÉUTILISANT la chaîne DSP déterministe
de `tools/audio/gen_sfx.py` (RNG dérivé du nom par sha256, filtres
Butterworth, bruit rose/blanc, enveloppes, `mix_at`, `finalize`/`measure`/
`print_table`) plutôt que de dupliquer ces outils — comme le fait déjà
`tools/audio/gen_ambience.py`.

Le tableau du §8.5 a 11 lignes. Dix décrivent un seul événement ; la ligne
« Manche gagnée / perdue » décrit en fait DEUX sons bien distincts (fanfare
de cuivres montante pour la victoire, trombone descendant pour la défaite),
déclenchés à des moments différents du match : elle produit donc 2 fichiers
(`ui_round_win_fanfare`, `ui_round_lose_fanfare`). Au total : 11 événements
du §8.5, 12 fichiers générés.

| Événement (§8.5)      | Fichier                        | Durée cible |
|------------------------|---------------------------------|------------|
| Survol, focus           | ui_hover_tick_1.wav             | 30 ms      |
| Sélection               | ui_select_stick_1.wav           | 120 ms     |
| Retour                  | ui_back_slide_1.wav             | 150 ms     |
| Onglet                  | ui_tab_snap_1.wav               | 60 ms      |
| Achat                   | ui_purchase_chime_1.wav         | 250 ms     |
| Achat impossible        | ui_purchase_denied_1.wav        | 120 ms     |
| Verrouillage d'agent    | ui_agent_lock_ding_1.wav        | 600 ms     |
| Match trouvé            | ui_match_found_1.wav            | 1 200 ms   |
| Manche gagnée           | ui_round_win_fanfare_1.wav      | 1 500 ms   |
| Manche perdue           | ui_round_lose_fanfare_1.wav     | 1 500 ms   |
| Erreur                  | ui_error_tut_1.wav              | 200 ms     |
| Ultime prêt             | ui_ultimate_ready_chime_1.wav   | 400 ms     |

Bus `UI` : normalisés à -12 dB SOUS le pic de référence des armes
(`gen_sfx.PEAK_DBFS` = -1 dBFS), donc pic cible = -13 dBFS. Durées vérifiées
à ±20 % de la cible ci-dessus (contrat ART-39).

Deux éléments du §8.5 mentionnent une voix par agent superposée au son de
base (« + phrase de l'agent » sur le DING de verrouillage et sur le carillon
d'ultime) : cette voix est un asset par agent, câblée au runtime par `UiFx`
(UX-12) par-dessus le fichier généré ici — un générateur procédural
générique ne peut pas la synthétiser de façon honnête (ce serait un
placeholder). Seule la partie procédurale (DING/tampon, carillon) est
produite par ce script.

« Au plus 2 simultanées, jamais pendant un tir » (règle de mixage du §8.5)
et le branchement effectif sur les contrôles/menus sont du ressort de
`UiFx` (UX-12) : `Audio.gd` n'est pas modifié ici, conformément au contrat.

Usage :
    python tools/audio/gen_ui_sfx.py [--out assets/audio/sfx/ui]

Sortie : `<out>/<nom>_1.wav` (12 fichiers). Tableau de stats + vérifications
(pic, durée ±20 %, offset DC) à la fin ; sort en erreur (exit 1) si une
vérification échoue.
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path
from typing import Dict, List

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gen_sfx import (  # réutilise la chaîne DSP + mesure de gen_sfx.py telle quelle
    PEAK_DBFS as WEAPON_PEAK_DBFS,
    SR,
    adsr,
    bandpass,
    exp_decay,
    finalize,
    lowpass,
    measure,
    mix_at,
    pitched_sweep,
    print_table,
    resonant_click,
    rng_for,
    sine,
    white_noise,
    write_wav,
)

# Bus UI à -12 dB sous le pic de référence des armes (contrat ART-39).
UI_REL_DB = -12.0
UI_PEAK_DBFS = WEAPON_PEAK_DBFS + UI_REL_DB  # -1.0 + (-12.0) = -13.0 dBFS
DURATION_TOLERANCE = 0.20  # ±20 % (contrat ART-39)


# ============================================================== générateurs


def gen_ui_hover_tick(rng: np.random.Generator) -> np.ndarray:
    """Survol/focus : tic de papier sec, clic filtré à 4 kHz. 30 ms."""
    n = int(0.030 * SR)
    click = resonant_click(n, SR, 4000.0, 16.0, rng) * exp_decay(n, SR, 0.006)
    paper = bandpass(white_noise(n, rng), 3200, 6000, order=3) * exp_decay(n, SR, 0.004)
    return click * 0.8 + paper * 0.35


def gen_ui_select_stick(rng: np.random.Generator) -> np.ndarray:
    """Sélection : « schlack » d'autocollant qu'on colle. 120 ms."""
    n = int(0.120 * SR)
    smack_n = int(0.012 * SR)
    smack = bandpass(white_noise(smack_n, rng), 1500, 7000, order=3) * exp_decay(smack_n, SR, 0.006)
    body_off = int(0.006 * SR)
    body_n = n - body_off
    body = bandpass(white_noise(body_n, rng), 300, 1400, order=3) * adsr(body_n, SR, 0.004, 0.03, 0.09, sustain_level=0.25)
    return mix_at(n, (smack, 0, 0.9), (body, body_off, 0.6))


def gen_ui_back_slide(rng: np.random.Generator) -> np.ndarray:
    """Retour : glissement de papier (bruit filtré, centre qui descend). 150 ms."""
    n = int(0.150 * SR)
    noise = white_noise(n, rng)
    out = np.zeros(n)
    step = 600
    centers = np.linspace(3200, 700, n)
    for s in range(0, n, step):
        seg = noise[s:s + step]
        if seg.size == 0:
            continue
        c = centers[s]
        out[s:s + step] = bandpass(seg, max(c - 500, 60), c + 500, order=2)
    attack = int(0.012 * SR)
    out[:attack] *= np.linspace(0.0, 1.0, attack)
    out *= exp_decay(n, SR, 0.07)
    return out * 0.6


def gen_ui_tab_snap(rng: np.random.Generator) -> np.ndarray:
    """Onglet : claquement de carton. 60 ms."""
    n = int(0.060 * SR)
    click = resonant_click(n, SR, 900.0, 9.0, rng) * exp_decay(n, SR, 0.014)
    snap = bandpass(white_noise(n, rng), 500, 2600, order=3) * exp_decay(n, SR, 0.02)
    return click * 0.75 + snap * 0.5


def gen_ui_purchase_chime(rng: np.random.Generator) -> np.ndarray:
    """Achat : petit « ka-ching » de caisse (clic + carillon métallique). 250 ms."""
    n = int(0.250 * SR)
    ka_n = int(0.02 * SR)
    ka = resonant_click(ka_n, SR, 1600.0, 10.0, rng) * exp_decay(ka_n, SR, 0.01)
    ching_off = int(0.03 * SR)
    ching_n = n - ching_off
    parts = [(ka, 0, 0.7)]
    for k, f in enumerate([1760.0, 2637.0, 3520.0]):
        tone = sine(ching_n, SR, f) * exp_decay(ching_n, SR, 0.10 - k * 0.02)
        parts.append((tone, ching_off, 0.3 / (k + 1)))
    return mix_at(n, *parts)


def gen_ui_purchase_denied(rng: np.random.Generator) -> np.ndarray:
    """Achat impossible : « bonk » mat de bois. 120 ms."""
    n = int(0.120 * SR)
    thump = pitched_sweep(n, SR, 190.0, 85.0, shape="tri", curve=3.0) * exp_decay(n, SR, 0.05)
    thump = lowpass(thump, 500, order=2)
    dull_n = int(0.02 * SR)
    dull = bandpass(white_noise(dull_n, rng), 200, 1200, order=3) * exp_decay(dull_n, SR, 0.012)
    return mix_at(n, (thump, 0, 0.85), (dull, 0, 0.4))


def gen_ui_agent_lock_ding(rng: np.random.Generator) -> np.ndarray:
    """Verrouillage d'agent : DING de cloche (partiels inharmoniques) + tampon
    (thump large bande bref). La « phrase de l'agent » du §8.5 est une voix
    par agent superposée au runtime par UiFx (UX-12) : hors de portée d'un
    générateur procédural générique, voir docstring du module. 600 ms."""
    n = int(0.600 * SR)
    stamp_n = int(0.04 * SR)
    stamp = bandpass(white_noise(stamp_n, rng), 150, 1800, order=3) * exp_decay(stamp_n, SR, 0.012)
    bell_off = int(0.01 * SR)
    bell_n = n - bell_off
    f0 = 1046.5
    partials = [(1.0, 1.0), (2.0, 0.5), (3.01, 0.3), (4.2, 0.18)]
    parts = [(stamp, 0, 0.7)]
    for ratio, gain in partials:
        tone = sine(bell_n, SR, f0 * ratio) * exp_decay(bell_n, SR, 0.42 / ratio)
        parts.append((tone, bell_off, gain * 0.35))
    return mix_at(n, *parts)


def gen_ui_match_found(rng: np.random.Generator) -> np.ndarray:
    """Match trouvé : roulement de caisse claire (bruit filtré, tremolo qui
    accélère) + « ooh » de foule (deux bandes formantiques qui enflent). 1,2 s."""
    n = int(1.2 * SR)
    roll_n = int(0.7 * SR)
    roll = bandpass(white_noise(roll_n, rng), 250, 6500, order=3)
    t = np.arange(roll_n) / SR
    rate_hz = 6.0 + 34.0 * (t / max(roll_n / SR, 1e-6))  # accélère 6 -> 40 Hz
    phase = np.cumsum(rate_hz) / SR
    gate = 0.35 + 0.65 * (0.5 + 0.5 * np.sign(np.sin(2 * np.pi * phase)))
    roll = roll * gate * np.linspace(0.35, 1.0, roll_n) * exp_decay(roll_n, SR, 0.35)

    crowd = bandpass(white_noise(n, rng), 450, 1300, order=2) * 0.55 \
        + bandpass(white_noise(n, rng), 900, 2200, order=2) * 0.3
    crowd = crowd * adsr(n, SR, 0.35, 0.35, 0.35, sustain_level=0.8)

    return mix_at(n, (roll, 0, 0.55), (crowd, 0, 0.4))


def _fanfare_notes(n: int, notes: List[float], step_s: float, decay: float, shape: str) -> np.ndarray:
    """Notes de cuivre en arpège décalé : onde `shape` (saw = timbre cuivré une
    fois lowpassée) tenue à hauteur fixe, enveloppe exponentielle."""
    parts = []
    for k, f in enumerate(notes):
        start = int(k * step_s * SR)
        seg_n = n - start
        if seg_n <= 0:
            continue
        tone = pitched_sweep(seg_n, SR, f, f, shape=shape, curve=1.0) * exp_decay(seg_n, SR, decay)
        tone = lowpass(tone, f * 3.5, order=2)
        parts.append((tone, start, 0.28))
    return mix_at(n, *parts)


def gen_ui_round_win_fanfare(rng: np.random.Generator) -> np.ndarray:
    """Manche gagnée : fanfare de cuivres montante. 1,5 s."""
    n = int(1.5 * SR)
    notes = [392.0, 523.25, 659.25, 784.0]  # sol4 -> sol5, arpège montant affirmatif
    fanfare = _fanfare_notes(n, notes, step_s=0.16, decay=0.6, shape="saw")
    shimmer = bandpass(white_noise(n, rng), 1500, 5000, order=2) * exp_decay(n, SR, 0.25) * 0.12
    return fanfare + shimmer


def gen_ui_round_lose_fanfare(rng: np.random.Generator) -> np.ndarray:
    """Manche perdue : trombone descendant (glissando continu, timbre cuivré
    assourdi). 1,5 s."""
    n = int(1.5 * SR)
    glide = pitched_sweep(n, SR, 330.0, 110.0, shape="saw", curve=0.8) * exp_decay(n, SR, 0.9)
    glide = lowpass(glide, 900, order=3)
    growl = bandpass(white_noise(n, rng), 150, 700, order=2) * exp_decay(n, SR, 0.5) * 0.15
    return glide * 0.55 + growl


def gen_ui_error_tut(rng: np.random.Generator) -> np.ndarray:
    """Erreur : double « tut » grave. 200 ms."""
    n = int(0.200 * SR)
    tut_n = int(0.05 * SR)
    tut1 = sine(tut_n, SR, 220.0) * exp_decay(tut_n, SR, 0.02)
    tut2 = sine(tut_n, SR, 196.0) * exp_decay(tut_n, SR, 0.02)
    return mix_at(n, (tut1, 0, 0.6), (tut2, int(0.09 * SR), 0.6))


def gen_ui_ultimate_ready_chime(rng: np.random.Generator) -> np.ndarray:
    """Ultime prêt : carillon court (arpège de cloche aigu). La voix de
    l'agent est superposée par UiFx au runtime (hors de portée ici, cf.
    gen_ui_agent_lock_ding). 400 ms."""
    n = int(0.400 * SR)
    notes = [1568.0, 2093.0, 2637.0]
    parts = []
    for k, f in enumerate(notes):
        start = int(k * 0.05 * SR)
        seg_n = n - start
        if seg_n <= 0:
            continue
        tone = sine(seg_n, SR, f) * exp_decay(seg_n, SR, 0.11)
        parts.append((tone, start, 0.32))
    return mix_at(n, *parts)


SOUNDS: Dict[str, Dict] = {
    "ui_hover_tick": dict(target_s=0.030, gen=gen_ui_hover_tick),
    "ui_select_stick": dict(target_s=0.120, gen=gen_ui_select_stick),
    "ui_back_slide": dict(target_s=0.150, gen=gen_ui_back_slide),
    "ui_tab_snap": dict(target_s=0.060, gen=gen_ui_tab_snap),
    "ui_purchase_chime": dict(target_s=0.250, gen=gen_ui_purchase_chime),
    "ui_purchase_denied": dict(target_s=0.120, gen=gen_ui_purchase_denied),
    "ui_agent_lock_ding": dict(target_s=0.600, gen=gen_ui_agent_lock_ding),
    "ui_match_found": dict(target_s=1.200, gen=gen_ui_match_found),
    "ui_round_win_fanfare": dict(target_s=1.500, gen=gen_ui_round_win_fanfare),
    "ui_round_lose_fanfare": dict(target_s=1.500, gen=gen_ui_round_lose_fanfare),
    "ui_error_tut": dict(target_s=0.200, gen=gen_ui_error_tut),
    "ui_ultimate_ready_chime": dict(target_s=0.400, gen=gen_ui_ultimate_ready_chime),
}


# ============================================================== vérification


def verify_ui(stats: List[Dict], targets: Dict[str, float]) -> bool:
    ok = True
    for s in stats:
        target = targets.get(s["category"])
        if target is not None:
            lo, hi = target * (1.0 - DURATION_TOLERANCE), target * (1.0 + DURATION_TOLERANCE)
            if not (lo <= s["duration"] <= hi):
                print(f"[FAIL] {s['path'].name}: durée {s['duration'] * 1000:.1f} ms hors tolérance "
                      f"±20 % de {target * 1000:.0f} ms")
                ok = False
        if not (UI_PEAK_DBFS - 0.6 <= s["peak_db"] <= UI_PEAK_DBFS + 0.4):
            print(f"[FAIL] {s['path'].name}: pic {s['peak_db']:.2f} dBFS hors cible ({UI_PEAK_DBFS:.1f} dBFS)")
            ok = False
        if abs(s["dc"]) >= 0.003:
            print(f"[FAIL] {s['path'].name}: offset DC {s['dc']:.5f} trop élevé")
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
    parser.add_argument("--out", default="assets/audio/sfx/ui", help="dossier de sortie (relatif à la racine du repo)")
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parents[2]
    out_dir = repo_root / args.out
    out_dir.mkdir(parents=True, exist_ok=True)

    stats: List[Dict] = []
    targets: Dict[str, float] = {}

    for name, spec in SOUNDS.items():
        rng = rng_for(name)
        raw = spec["gen"](rng)
        x = finalize(raw, loop=False, peak_db=UI_PEAK_DBFS)
        path = out_dir / f"{name}_1.wav"
        write_wav(path, x)
        stats.append(measure(path, name))
        targets[name] = spec["target_s"]

    print_table(stats)
    ok = verify_ui(stats, targets)
    print(f"\n{len(stats)} fichiers générés pour les 11 événements du STYLE_BIBLE.md §8.5 "
          f"(la ligne « Manche gagnée / perdue » produit 2 fichiers distincts).")
    if not ok:
        print("ÉCHEC : au moins une vérification a échoué (voir [FAIL] ci-dessus).")
        return 1
    print(f"OK : pic {UI_PEAK_DBFS:.1f} dBFS (-12 dB sous les armes), durées ±20 %, offset DC "
          f"— toutes les vérifications passent.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
