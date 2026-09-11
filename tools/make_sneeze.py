"""Synthétise un hennissement de cheval → assets/sounds/sneeze.wav

Usage : python3 tools/make_sneeze.py
(le fichier garde le nom sneeze.wav pour ne rien changer dans l'appli)
"""
import numpy as np
import wave

FS = 44100
rng = np.random.default_rng(3)


def biquad_bandpass(x, f0, q):
    """Filtre passe-bande résonant (formant)."""
    w0 = 2 * np.pi * f0 / FS
    alpha = np.sin(w0) / (2 * q)
    b0, b1, b2 = alpha, 0.0, -alpha
    a0, a1, a2 = 1 + alpha, -2 * np.cos(w0), 1 - alpha
    b0, b1, b2, a1, a2 = b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0
    y = np.zeros_like(x)
    x1 = x2 = y1 = y2 = 0.0
    for i in range(len(x)):
        y[i] = b0 * x[i] + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2, x1 = x1, x[i]
        y2, y1 = y1, y[i]
    return y


# ---------------------------------------------------------------------------
# 1. Le hennissement proprement dit
# ---------------------------------------------------------------------------
DUR = 1.35
t = np.arange(int(DUR * FS)) / FS
u = t / DUR  # 0 → 1

# Hauteur : petite montée d'attaque, puis longue descente exponentielle.
f_start, f_peak, f_end = 950.0, 1250.0, 420.0
rise = np.clip(u / 0.08, 0, 1)
f0 = f_start + (f_peak - f_start) * rise
f0 = f0 * (f_end / f_peak) ** np.clip((u - 0.08) / 0.92, 0, 1) ** 0.8

# Trille : modulation de hauteur (±7 %) et d'amplitude à ~19 Hz, qui
# ralentit un peu sur la fin.
trill_rate = 21 - 6 * u
trill_phase = np.cumsum(trill_rate) / FS
trill = np.sin(2 * np.pi * trill_phase)
f0 = f0 * (1 + 0.07 * trill)
am = 0.55 + 0.45 * (0.5 + 0.5 * trill) ** 0.6

# Source harmonique : somme d'harmoniques avec léger bruit de phase,
# ce qui évite le côté "synthé propre".
phase = 2 * np.pi * np.cumsum(f0) / FS
src = np.zeros_like(t)
for n in range(1, 14):
    amp = 1.0 / n ** 0.55
    jitter = rng.normal(0, 0.02, 1)[0]
    src += amp * np.sin(n * phase + jitter)
src /= np.max(np.abs(src))

# Un peu de souffle mêlé à la voix
breath = rng.normal(0, 1, len(t)) * 0.15

# Formants du conduit vocal du cheval (approximatifs) : ça "cuivre".
voiced = src * am + breath
out = (
    1.0 * biquad_bandpass(voiced, 900, 4)
    + 0.8 * biquad_bandpass(voiced, 1700, 5)
    + 0.6 * biquad_bandpass(voiced, 2900, 6)
    + 0.35 * voiced
)

# Enveloppe : attaque 40 ms, tenue, puis descente sur le dernier tiers.
env = np.clip(t / 0.04, 0, 1) * np.where(u < 0.65, 1.0, np.exp(-(u - 0.65) / 0.16))
neigh = out * env

# ---------------------------------------------------------------------------
# 2. Ébrouement de fin ("brrrr" des naseaux)
# ---------------------------------------------------------------------------
t2 = np.arange(int(0.45 * FS)) / FS
flutter = 0.5 + 0.5 * np.sign(np.sin(2 * np.pi * 26 * t2))
snort = (rng.normal(0, 1, len(t2)) * 0.6 + np.sin(2 * np.pi * 70 * t2) * 0.4) * flutter
snort = biquad_bandpass(snort, 500, 1.5) * 2.5
snort *= np.clip(t2 / 0.02, 0, 1) * np.exp(-t2 / 0.18)

# ---------------------------------------------------------------------------
sig = np.concatenate([neigh, np.zeros(int(0.05 * FS)), snort * 0.6])
sig = sig / np.max(np.abs(sig)) * 0.9
pcm = (sig * 32767).astype(np.int16)

with wave.open("assets/sounds/sneeze.wav", "wb") as w:
    w.setnchannels(1)
    w.setsampwidth(2)
    w.setframerate(FS)
    w.writeframes(pcm.tobytes())
print(f"OK sneeze.wav ({len(sig)/FS:.2f} s)")
