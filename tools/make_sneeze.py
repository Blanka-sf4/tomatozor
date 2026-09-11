"""Synthétise un éternuement de mini-cheval cartoon → assets/sounds/sneeze.wav

Usage : python3 tools/make_sneeze.py
"""
import numpy as np
import wave

FS = 44100
rng = np.random.default_rng(7)


def t(dur):
    return np.arange(int(dur * FS)) / FS


def saw(freq, tt):
    return 2 * (freq * tt % 1) - 1


def env(tt, attack, decay):
    return np.minimum(tt / attack, 1) * np.exp(-np.maximum(tt - attack, 0) / decay)


# 1. Inspiration : "aaah" montant, timbre nasal (dent de scie + vibrato)
tt = t(0.28)
f = 280 + 320 * (tt / tt[-1]) ** 2
phase = np.cumsum(f) / FS
vib = 1 + 0.02 * np.sin(2 * np.pi * 6 * tt)
inhale = saw(1, phase * vib) * env(tt, 0.05, 0.4) * 0.35
# petit souffle par-dessus
inhale += rng.normal(0, 0.05, len(tt)) * env(tt, 0.1, 0.3)

gap = np.zeros(int(0.06 * FS))

# 2. Éclat : "TCHOO" — bruit blanc filtré grossièrement + coup sourd
tt = t(0.22)
noise = rng.normal(0, 1, len(tt))
# filtre passe-bas grossier par moyenne glissante, coupure qui descend
k = 6
noise = np.convolve(noise, np.ones(k) / k, mode="same")
burst = noise * env(tt, 0.004, 0.06) * 0.9
thump = np.sin(2 * np.pi * 90 * tt) * env(tt, 0.003, 0.05) * 0.8
sneeze = burst + thump

# 3. Ébrouement : "brrrrr" de lèvres — note grave modulée à 28 Hz
tt = t(0.55)
lip = saw(75, tt) * (0.5 + 0.5 * np.sign(np.sin(2 * np.pi * 28 * tt)))
lip = lip * env(tt, 0.01, 0.25) * 0.45
lip += rng.normal(0, 0.08, len(tt)) * env(tt, 0.01, 0.2)

sig = np.concatenate([inhale, gap, sneeze, lip])
sig = sig / np.max(np.abs(sig)) * 0.9
pcm = (sig * 32767).astype(np.int16)

with wave.open("assets/sounds/sneeze.wav", "wb") as w:
    w.setnchannels(1)
    w.setsampwidth(2)
    w.setframerate(FS)
    w.writeframes(pcm.tobytes())
print(f"OK sneeze.wav ({len(sig)/FS:.2f} s)")
