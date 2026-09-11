"""« Gloups » de l'incognito → assets/sounds/gloups.wav"""
import numpy as np
from synth_common import FS, biquad_bandpass, harmonics, save

rng = np.random.default_rng(17)
DUR = 0.38
t = np.arange(int(DUR * FS)) / FS
u = t / DUR

# Une déglutition : "gl" = coup grave bref, "oup" = note qui plonge, "s" = souffle
f0 = 260 * (0.45) ** np.clip(u / 0.7, 0, 1)
src, phase = harmonics(f0, n=10, tilt=0.6)
v = src * (0.6 + 0.4 * np.sin(2 * np.pi * 30 * t))  # gargouille de gorge
out = biquad_bandpass(v, 500, 4) + 0.7 * biquad_bandpass(v, 1000, 5) + 0.3 * v
env = np.clip(t / 0.01, 0, 1) * np.where(u < 0.6, 1.0, np.exp(-(u - 0.6) / 0.1))
out = out * env
# Le coup de glotte initial
k = np.zeros_like(t)
n = int(0.025 * FS)
k[:n] = np.sin(2 * np.pi * 120 * t[:n]) * np.exp(-t[:n] / 0.006) * 2.5
# Le petit "s" final
s = rng.normal(0, 1, int(0.08 * FS)) * np.exp(-np.arange(int(0.08 * FS)) / (0.03 * FS))
s = biquad_bandpass(s, 5000, 2) * 2
save("assets/sounds/gloups.wav", np.concatenate([out + k, s * 0.4]))
