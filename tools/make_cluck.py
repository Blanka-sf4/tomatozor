"""Le poulet : « cot cot cot codèèèt » → assets/sounds/cluck.wav"""
import numpy as np
from synth_common import FS, biquad_bandpass, harmonics, save

rng = np.random.default_rng(4)


def cot(dur=0.11, f_start=900, f_end=500):
    t = np.arange(int(dur * FS)) / FS
    u = t / dur
    f0 = f_start * (f_end / f_start) ** u
    src, _ = harmonics(f0, n=8, tilt=0.8)
    v = src + rng.normal(0, 1, len(t)) * 0.08
    out = biquad_bandpass(v, 1200, 5) + 0.6 * biquad_bandpass(v, 2600, 6) + 0.2 * v
    env = np.clip(t / 0.006, 0, 1) * np.exp(-u * 4)
    return out * env


def codet(dur=0.55):
    t = np.arange(int(dur * FS)) / FS
    u = t / dur
    # "co-dèèèt" : monte franchement puis tient en chevrotant
    f0 = np.where(u < 0.2, 600 + 500 * (u / 0.2), 1100)
    f0 = f0 * (1 + 0.05 * np.sin(2 * np.pi * 22 * t) * np.clip((u - 0.2) / 0.2, 0, 1))
    src, _ = harmonics(f0, n=8, tilt=0.8)
    v = src + rng.normal(0, 1, len(t)) * 0.08
    out = biquad_bandpass(v, 1400, 5) + 0.7 * biquad_bandpass(v, 2900, 6) + 0.2 * v
    env = np.clip(t / 0.01, 0, 1) * np.where(u < 0.8, 1.0, np.exp(-(u - 0.8) / 0.05))
    return out * env


gap = np.zeros(int(0.09 * FS))
sig = np.concatenate([cot(), gap, cot(0.1, 850, 480), gap, cot(0.1, 950, 520), gap * 0.5, codet()])
save("assets/sounds/cluck.wav", sig)
