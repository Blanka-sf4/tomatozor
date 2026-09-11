"""Chèvre qui hurle (tempo > 220) → assets/sounds/goat.wav"""
import numpy as np
from synth_common import FS, biquad_bandpass, harmonics, save

rng = np.random.default_rng(21)
DUR = 1.6
t = np.arange(int(DUR * FS)) / FS
u = t / DUR

# Hauteur : un "aaAAAH" tendu, ~330 Hz qui monte à 430 puis casse à la fin.
f0 = 330 + 100 * np.clip(u / 0.3, 0, 1) - 60 * np.clip((u - 0.85) / 0.15, 0, 1)
# LE chevrotement : vibrato fort et un peu irrégulier à ~7 Hz
trem_rate = 7 + 1.5 * np.sin(2 * np.pi * 0.7 * t)
trem = np.sin(2 * np.pi * np.cumsum(trem_rate) / FS)
f0 = f0 * (1 + 0.09 * trem)
am = 0.55 + 0.45 * (0.5 + 0.5 * trem) ** 0.8

src, phase = harmonics(f0, n=20, tilt=0.45, rng=rng, jitter=0.05)
# Voix "forcée" : un peu de saturation et de souffle
v = np.tanh(1.6 * src) * am + rng.normal(0, 1, len(t)) * 0.12

# Formants d'un "è" nasillard et plaintif
out = (
    1.0 * biquad_bandpass(v, 650, 5)
    + 1.0 * biquad_bandpass(v, 1800, 6)
    + 0.6 * biquad_bandpass(v, 2700, 7)
    + 0.3 * v
)
env = np.clip(t / 0.05, 0, 1) * np.where(u < 0.82, 1.0, np.exp(-(u - 0.82) / 0.05))
save("assets/sounds/goat.wav", out * env)
