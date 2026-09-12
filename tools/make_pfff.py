"""« Pfff » de ballon qui se dégonfle (la musique s'est arrêtée) → assets/sounds/pfff.wav"""
import numpy as np
from synth_common import FS, biquad_bandpass, save

rng = np.random.default_rng(31)
DUR = 0.9
t = np.arange(int(DUR * FS)) / FS
u = t / DUR
# Souffle qui descend en hauteur et en volume, avec un petit couinement de
# baudruche (sinus qui glisse vers le bas) au début.
noise = rng.normal(0, 1, len(t))
f_res = 2200 * (0.25) ** u
out = np.zeros_like(t)
# filtre à fréquence variable : on découpe en tranches
step = 1024
for i in range(0, len(t), step):
    seg = noise[i:i + step]
    out[i:i + step] = biquad_bandpass(seg, float(f_res[min(i, len(t) - 1)]), 1.2) * 3
squeak = np.sin(2 * np.pi * np.cumsum(900 * (0.4) ** np.clip(u / 0.4, 0, 1)) / FS) * np.clip(1 - u / 0.35, 0, 1) * 0.25
env = np.clip(t / 0.02, 0, 1) * (1 - u) ** 1.3
save("assets/sounds/pfff.wav", out * env + squeak)
