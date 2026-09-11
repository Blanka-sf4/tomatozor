"""Clics de métronome « animaux » : un son très court par personnage, et sa
version temps fort (plus aiguë) → assets/sounds/click_<nom>.wav, click_<nom>_hi.wav
"""
import numpy as np
from synth_common import FS, biquad_bandpass, harmonics, save

rng = np.random.default_rng(12)


def voice_click(f_start, f_end, dur, formants, tilt=0.6, trill=0.0, rough=0.0, drive=1.0, noise=0.0):
    t = np.arange(int(dur * FS)) / FS
    u = t / dur
    f0 = f_start * (f_end / f_start) ** u
    if trill:
        f0 = f0 * (1 + 0.08 * np.sin(2 * np.pi * trill * t))
    src, phase = harmonics(f0, n=14, tilt=tilt)
    if rough:
        src = src + rng.normal(0, 1, len(t)) * (0.5 + 0.5 * np.sin(phase)) * rough
    src = np.tanh(drive * src)
    out = 0.3 * src
    for f, q, w in formants:
        out = out + w * biquad_bandpass(src, f, q)
    if noise:
        n = rng.normal(0, 1, len(t)) * np.exp(-t / 0.004) * noise
        out = out + biquad_bandpass(n, 3500, 2) * 3
    env = np.clip(t / 0.004, 0, 1) * np.where(u < 0.55, 1.0, np.exp(-(u - 0.55) / 0.12))
    return out * env


def sparkle(f, dur):
    t = np.arange(int(dur * FS)) / FS
    out = (
        np.sin(2 * np.pi * f * t) * np.exp(-t / 0.05)
        + 0.5 * np.sin(2 * np.pi * f * 2.76 * t) * np.exp(-t / 0.03)
        + 0.3 * np.sin(2 * np.pi * f * 5.4 * t) * np.exp(-t / 0.015)
    )
    return out * np.clip(t / 0.002, 0, 1)


def tsk(f, dur):
    t = np.arange(int(dur * FS)) / FS
    n = rng.normal(0, 1, len(t)) * np.exp(-t / 0.006)
    return biquad_bandpass(n, f, 1.5) * 4 + np.sin(2 * np.pi * f * 0.4 * t) * np.exp(-t / 0.01) * 0.6


def make(name, fn):
    save(f"assets/sounds/click_{name}.wav", fn(1.0))
    save(f"assets/sounds/click_{name}_hi.wav", fn(1.4))


make("cat", lambda k: voice_click(820 * k, 600 * k, 0.09, [(1300, 5, 1.0), (2600, 6, 0.6)], tilt=0.8))
make("incog", lambda k: tsk(3800 * k, 0.07))
make("chicken", lambda k: voice_click(900 * k, 480 * k, 0.08, [(1200, 5, 1.0), (2600, 6, 0.6)], tilt=0.8))
make("dino", lambda k: voice_click(130 * k, 80 * k, 0.11, [(220, 2, 1.0), (700, 3, 0.7)], tilt=0.3, rough=0.3, drive=2.5))
make("goat", lambda k: voice_click(470 * k, 430 * k, 0.11, [(650, 5, 1.0), (1800, 6, 0.9)], tilt=0.45, trill=40, drive=1.6))
make("pig", lambda k: voice_click(210 * k, 170 * k, 0.10, [(480, 5, 1.0), (950, 6, 0.9)], tilt=0.4, rough=0.35))
make("unicorn", lambda k: sparkle(1900 * k, 0.12))
make("psyllo", lambda k: voice_click(480 * k, 900 * k, 0.09, [(800, 3, 1.0)], tilt=1.2))
