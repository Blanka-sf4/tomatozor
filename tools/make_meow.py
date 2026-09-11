"""Miaulement du chat → assets/sounds/meow.wav"""
import numpy as np
from synth_common import FS, biquad_bandpass, harmonics, save

rng = np.random.default_rng(9)
DUR = 0.7
t = np.arange(int(DUR * FS)) / FS
u = t / DUR

# "mi-aaa-ou" : monte vite, tient, redescend en fermant la bouche.
f0 = np.where(u < 0.25, 520 + 300 * (u / 0.25), 820)
f0 = np.where(u > 0.55, 820 * (0.62) ** ((u - 0.55) / 0.45), f0)
f0 = f0 * (1 + 0.025 * np.sin(2 * np.pi * 6 * t))  # léger vibrato
src, phase = harmonics(f0, n=12, tilt=0.7)
v = src + rng.normal(0, 1, len(t)) * 0.06

# Formants qui glissent : "i" (fermé, aigu) → "a" (ouvert) → "ou" (fermé, grave)
f1 = np.where(u < 0.25, 400 + 400 * (u / 0.25), 800)
f1 = np.where(u > 0.55, 800 - 450 * ((u - 0.55) / 0.45), f1)
# Approximation : on mélange trois filtres fixes avec des poids qui bougent
w_i = np.clip(1 - u / 0.3, 0, 1)
w_a = np.clip(1 - abs(u - 0.4) / 0.3, 0, 1)
w_ou = np.clip((u - 0.5) / 0.4, 0, 1)
out = (
    biquad_bandpass(v, 2600, 6) * w_i * 0.8
    + biquad_bandpass(v, 1100, 5) * (w_i * 0.5 + w_a * 1.0 + w_ou * 0.3)
    + biquad_bandpass(v, 600, 5) * (w_a * 0.5 + w_ou * 1.0)
    + 0.35 * v
)
# Le "m" du début : attaque douce et nasale
env = np.clip(t / 0.06, 0, 1) ** 1.5 * np.where(u < 0.8, 1.0, np.exp(-(u - 0.8) / 0.08))
save("assets/sounds/meow.wav", out * env)
