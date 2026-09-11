"""Synthétise un pet de dino → assets/sounds/fart.wav

Usage : python3 tools/make_fart.py
"""
import numpy as np
import wave

FS = 44100
rng = np.random.default_rng(42)

DUR = 0.85
t = np.arange(int(DUR * FS)) / FS
u = t / DUR

# Fréquence de vibration : ~55 Hz, qui descend et tremblote (le sphincter
# n'est pas un oscillateur de précision).
f0 = 58 * (0.6) ** u * (1 + 0.15 * np.sin(2 * np.pi * 4.3 * t) + 0.08 * rng.normal(0, 1, len(t)).cumsum() / 200)
phase = np.cumsum(f0) / FS
# Train d'impulsions : une "pétarade" par période, forme de pulse asymétrique
pulse = np.exp(-((phase % 1.0) * 9) ** 1.4)
# Modulation d'amplitude irrégulière : ça hoquette
am = 0.6 + 0.4 * np.sin(2 * np.pi * 11 * t + 1) * np.sin(2 * np.pi * 3.7 * t)
sig = pulse * am
# Souffle
sig += rng.normal(0, 1, len(t)) * 0.12 * (1 + u)

# Résonance basse (le "corps" du son) + un peu de médium
def biquad_bandpass(x, f0, q):
    w0 = 2 * np.pi * f0 / FS
    alpha = np.sin(w0) / (2 * q)
    b0, b1, b2 = alpha, 0.0, -alpha
    a0, a1, a2 = 1 + alpha, -2 * np.cos(w0), 1 - alpha
    b0, b1, b2, a1, a2 = b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0
    y = np.zeros_like(x)
    x1 = x2 = y1 = y2 = 0.0
    for i in range(len(x)):
        y[i] = b0 * x[i] + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2, x1 = x1, x[i]
        y2, y1 = y1, y[i]
    return y

out = 1.0 * biquad_bandpass(sig, 120, 1.2) + 0.5 * biquad_bandpass(sig, 420, 2) + 0.3 * sig
# Enveloppe : attaque franche, s'essouffle sur la fin
env = np.clip(t / 0.01, 0, 1) * np.where(u < 0.6, 1.0, np.exp(-(u - 0.6) / 0.18))
out = out * env
out = out / np.max(np.abs(out)) * 0.9
pcm = (out * 32767).astype(np.int16)
with wave.open("assets/sounds/fart.wav", "wb") as w:
    w.setnchannels(1)
    w.setsampwidth(2)
    w.setframerate(FS)
    w.writeframes(pcm.tobytes())
print(f"OK fart.wav ({len(out)/FS:.2f} s)")
