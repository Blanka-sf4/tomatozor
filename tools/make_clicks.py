"""Clics de métronome en bois → assets/sounds/click.wav et click_hi.wav"""
import numpy as np
from synth_common import FS, biquad_bandpass, save

rng = np.random.default_rng(3)


def wood(f_res, dur=0.06):
    t = np.arange(int(dur * FS)) / FS
    # Un coup : bruit très bref + résonance du bois (deux modes)
    hit = rng.normal(0, 1, len(t)) * np.exp(-t / 0.0015)
    body = (
        np.sin(2 * np.pi * f_res * t) * np.exp(-t / 0.012)
        + 0.5 * np.sin(2 * np.pi * f_res * 2.7 * t) * np.exp(-t / 0.006)
    )
    return biquad_bandpass(hit, f_res, 3) * 4 + body


save("assets/sounds/click.wav", wood(1300))
save("assets/sounds/click_hi.wav", wood(1900))
