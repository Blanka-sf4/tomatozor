"""« Squish » rigolo quand on écrase une mascotte → assets/sounds/squish.wav"""
import numpy as np
from synth_common import FS, biquad_bandpass, harmonics, save

rng = np.random.default_rng(6)
DUR = 0.32
t = np.arange(int(DUR * FS)) / FS
u = t / DUR

# Un "boi-oing" caoutchouteux : plonge vite puis remonte en tremblant
f0 = np.where(u < 0.25, 520 * (0.35) ** (u / 0.25), 182 * (2.1) ** ((u - 0.25) / 0.75))
f0 = f0 * (1 + 0.12 * np.sin(2 * np.pi * 28 * t) * np.clip((u - 0.25) / 0.2, 0, 1))
src, _ = harmonics(f0, n=10, tilt=0.7)
v = src
out = biquad_bandpass(v, 900, 4) + 0.6 * biquad_bandpass(v, 1800, 5) + 0.3 * v
# Le "squish" mouillé au début : petit souffle bruité
wet = rng.normal(0, 1, len(t)) * np.exp(-t / 0.02) * 0.8
wet = biquad_bandpass(wet, 3000, 1.5) * 2
env = np.clip(t / 0.005, 0, 1) * np.where(u < 0.75, 1.0, np.exp(-(u - 0.75) / 0.06))
save("assets/sounds/squish.wav", out * env + wet)
