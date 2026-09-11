"""Trois « squish » rigolos, un par mascotte → assets/sounds/squish_{cat,incog,chicken}.wav"""
import numpy as np
from synth_common import FS, biquad_bandpass, harmonics, save

rng = np.random.default_rng(6)


def squish(path, f_hi, f_lo, dur, wobble, formant, wet_amt):
    t = np.arange(int(dur * FS)) / FS
    u = t / dur
    # Plonge vite puis remonte en tremblant : le "boi-oing"
    f0 = np.where(u < 0.25, f_hi * (f_lo / f_hi) ** (u / 0.25), f_lo * (f_hi / f_lo * 0.7) ** ((u - 0.25) / 0.75))
    f0 = f0 * (1 + 0.12 * np.sin(2 * np.pi * wobble * t) * np.clip((u - 0.25) / 0.2, 0, 1))
    src, _ = harmonics(f0, n=10, tilt=0.7)
    out = biquad_bandpass(src, formant, 4) + 0.6 * biquad_bandpass(src, formant * 2, 5) + 0.3 * src
    wet = rng.normal(0, 1, len(t)) * np.exp(-t / 0.02) * wet_amt
    wet = biquad_bandpass(wet, 3000, 1.5) * 2
    env = np.clip(t / 0.005, 0, 1) * np.where(u < 0.75, 1.0, np.exp(-(u - 0.75) / 0.06))
    save(path, out * env + wet)


# Chat : aigu, couinement de jouet qui couine
squish("assets/sounds/squish_cat.wav", 1100, 380, 0.28, 34, 1400, 0.5)
# Incognito : grave, "blorp" gêné, plus long
squish("assets/sounds/squish_incog.wav", 380, 110, 0.42, 18, 600, 1.0)
# Poulet : médium, ballon qu'on presse, tremblement rapide
squish("assets/sounds/squish_chicken.wav", 700, 220, 0.32, 48, 1000, 0.8)
# Dino : très grave, gros coussin
squish("assets/sounds/squish_dino.wav", 300, 80, 0.45, 12, 450, 1.2)
# Chèvre : bêlement écrasé, chevrotement fort
squish("assets/sounds/squish_goat.wav", 900, 320, 0.36, 60, 1200, 0.6)
# Cochon : grave-médium, groin qui couine
squish("assets/sounds/squish_pig.wav", 520, 150, 0.34, 26, 750, 1.0)
# Licorne : cristallin, très aigu
squish("assets/sounds/squish_unicorn.wav", 1600, 600, 0.26, 40, 2200, 0.3)
# Psyllo : lent, mou, bizarre
squish("assets/sounds/squish_psyllo.wav", 600, 160, 0.55, 7, 700, 0.9)
