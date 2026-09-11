"""Rugissement du dino (tempo 160-220) → assets/sounds/roar.wav"""
import numpy as np
from synth_common import FS, biquad_bandpass, harmonics, save

rng = np.random.default_rng(13)
DUR = 1.9
t = np.arange(int(DUR * FS)) / FS
u = t / DUR

# --- Couche 1 : le grondement grave ---------------------------------------
f_low = 55 + 40 * np.sin(np.pi * np.clip(u / 0.9, 0, 1)) ** 0.7
f_low = f_low * (1 + 0.05 * np.sin(2 * np.pi * 9 * t))
low, ph_low = harmonics(f_low, n=30, tilt=0.3)
# Distorsion : on écrase (tanh) pour le côté "gorge de monstre"
low = np.tanh(2.5 * low)
low += rng.normal(0, 1, len(t)) * (0.5 + 0.5 * np.sin(ph_low)) * 0.3

# --- Couche 2 : le cri strident par-dessus, qui arrive après 0,3 s ---------
f_hi = 380 * (1.9) ** np.clip((u - 0.15) / 0.5, 0, 1) * (0.75) ** np.clip((u - 0.7) / 0.3, 0, 1)
f_hi = f_hi * (1 + 0.04 * np.sin(2 * np.pi * 16 * t))
hi, _ = harmonics(f_hi, n=12, tilt=0.6)
hi = np.tanh(1.8 * hi)
hi_env = np.clip((u - 0.15) / 0.2, 0, 1)

# --- Souffle rauque -----------------------------------------------------------
breath = rng.normal(0, 1, len(t)) * 0.4

v = low + 0.7 * hi * hi_env + breath
out = (
    1.0 * biquad_bandpass(v, 220, 2)     # corps
    + 0.9 * biquad_bandpass(v, 700, 3)   # gueule ouverte
    + 0.7 * biquad_bandpass(v, 1600, 4)
    + 0.5 * biquad_bandpass(v, 3200, 5)  # le mordant
    + 0.3 * v
)
# Enveloppe : monte sur 0,25 s (il prend son souffle), plein, puis retombe
env = np.clip(t / 0.25, 0, 1) ** 1.5 * np.where(u < 0.75, 1.0, np.exp(-(u - 0.75) / 0.1))
save("assets/sounds/roar.wav", np.tanh(1.5 * out * env))
