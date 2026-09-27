"""analyze_mix.py

Analyse le WAV capture par tools/audio/audio_capture.gd (tache "son",
2026-09-27) : peak dBFS, % d'echantillons a la ceiling (doit rester ~0 grace
au limiteur Master), loudness court-terme dans le temps, waveform +
spectrogramme avec le journal d'evenements (events.txt) superpose.

Usage:
    python tools/audio/analyze_mix.py reports/checkpoints/2026-09-27_audio
"""
import sys
from pathlib import Path

import numpy as np
from scipy.io import wavfile
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt


def load_events(path: Path):
    events = []
    if not path.exists():
        return events
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line:
            continue
        t_str, name, db_str = line.split("\t")
        events.append((float(t_str), name, float(db_str)))
    return events


def to_float(samples: np.ndarray) -> np.ndarray:
    if samples.dtype == np.int16:
        return samples.astype(np.float64) / 32768.0
    if samples.dtype == np.int32:
        return samples.astype(np.float64) / 2147483648.0
    if samples.dtype == np.uint8:
        return (samples.astype(np.float64) - 128.0) / 128.0
    return samples.astype(np.float64)


def main(out_dir: str) -> None:
    out = Path(out_dir)
    wav_path = out / "mix.wav"
    events_path = out / "events.txt"
    png_path = out / "mix.png"

    sr, raw = wavfile.read(wav_path)
    samples = to_float(raw)
    if samples.ndim > 1:
        mono = samples.mean(axis=1)
    else:
        mono = samples

    duration = len(mono) / sr
    peak = np.max(np.abs(mono))
    peak_db = 20 * np.log10(max(peak, 1e-12))

    # % d'echantillons a la ceiling (>= -0.5 dBFS, marge pour le bruit de
    # troncature du limiteur -- jamais EXACTEMENT 1.0 en pratique).
    ceiling_lin = 10 ** (-0.5 / 20)
    at_ceiling = np.mean(np.abs(mono) >= ceiling_lin) * 100.0

    # RMS/loudness court-terme, fenetres de 200 ms (pas de 50 ms).
    win_s = 0.2
    hop_s = 0.05
    win_n = max(1, int(win_s * sr))
    hop_n = max(1, int(hop_s * sr))
    times = []
    loud_db = []
    i = 0
    while i + win_n <= len(mono):
        w = mono[i:i + win_n]
        rms = np.sqrt(np.mean(w ** 2)) + 1e-12
        loud_db.append(20 * np.log10(rms))
        times.append((i + win_n / 2) / sr)
        i += hop_n

    events = load_events(events_path)

    fig, (ax_wave, ax_loud, ax_spec) = plt.subplots(3, 1, figsize=(16, 10), sharex=True)

    t_wave = np.arange(len(mono)) / sr
    ax_wave.plot(t_wave, mono, linewidth=0.3, color="#2b6cb0")
    ax_wave.set_ylabel("amplitude")
    ax_wave.set_title(f"mix.wav -- peak={peak_db:.2f} dBFS, ceiling(>=-0.5dBFS)={at_ceiling:.3f}% des echantillons, duree={duration:.1f}s")
    ax_wave.set_ylim(-1.05, 1.05)

    ax_loud.plot(times, loud_db, color="#c05621")
    ax_loud.set_ylabel("loudness court-terme (dBFS RMS, 200ms)")
    ax_loud.set_ylim(-60, 5)

    f, t_spec, Sxx = _spectrogram(mono, sr)
    ax_spec.pcolormesh(t_spec, f, 10 * np.log10(Sxx + 1e-12), shading="auto", cmap="magma")
    ax_spec.set_ylabel("Hz")
    ax_spec.set_ylim(0, min(sr / 2, 12000))
    ax_spec.set_xlabel("temps (s)")

    # Superpose le journal d'evenements sur les 3 panneaux (ligne verticale +
    # etiquette, une seule fois par nom pour ne pas noyer le graphe).
    seen_labels = set()
    for t, name, _db in events:
        for ax in (ax_wave, ax_loud, ax_spec):
            ax.axvline(t, color="white" if ax is ax_spec else "black", alpha=0.25, linewidth=0.6)
        label = name if name not in seen_labels else None
        seen_labels.add(name)
        ax_loud.annotate(name, (t, 2), rotation=90, fontsize=5, ha="center", va="bottom", alpha=0.7)

    fig.tight_layout()
    fig.savefig(png_path, dpi=140)

    print(f"peak_dbfs={peak_db:.3f}")
    print(f"pct_at_ceiling={at_ceiling:.4f}")
    print(f"duration_s={duration:.2f}")
    print(f"sample_rate={sr}")
    print(f"n_events={len(events)}")
    print(f"png={png_path}")

    # Verifie que chaque evenement programme (foley/musique) tombe bien dans
    # une fenetre ou l'energie du mix a reellement bouge (loudness > silence
    # de fond) -- sonde grossiere : moyenne de loudness sur 100 ms autour de
    # l'instant logue doit depasser le plancher de bruit du silence pur.
    floor_db = np.percentile(loud_db, 5) if loud_db else -80.0
    misses = []
    for t, name, _db in events:
        idx = np.searchsorted(times, t)
        lo = max(0, idx - 3)
        hi = min(len(loud_db), idx + 3)
        window = loud_db[lo:hi]
        if not window or max(window) < floor_db + 1.0:
            misses.append((t, name))
    print(f"noise_floor_db={floor_db:.2f}")
    print(f"events_without_audible_energy={len(misses)}")
    for t, name in misses[:20]:
        print(f"  MISS t={t:.3f} {name}")


def _spectrogram(mono: np.ndarray, sr: int):
    from scipy.signal import spectrogram
    return spectrogram(mono, fs=sr, nperseg=2048, noverlap=1024)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "reports/checkpoints/2026-09-27_audio")
