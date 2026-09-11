"""Synthétise un « yaaark » de dégoût → assets/sounds/yark.wav

Usage : python3 tools/make_yark.py
"""
import numpy as np
import wave

FS = 44100
rng = np.random.default_rng(5)


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


DUR = 0.75
t = np.arange(int(DUR * FS)) / FS
u = t / DUR

# Hauteur : "YA" un peu haut, puis "aaark" qui descend et devient rauque.
f0 = 260 * (0.55) ** np.clip((u - 0.15) / 0.75, 0, 1)
f0 = f0 * (1 + 0.06 * np.sin(2 * np.pi * 7 * t) * u)  # chevrotement de dégoût

phase = 2 * np.pi * np.cumsum(f0) / FS
src = np.zeros_like(t)
for n in range(1, 16):
    src += np.sin(n * phase) / n ** 0.5
src /= np.max(np.abs(src))

# Raucité croissante : bruit modulé par la voix, de plus en plus fort.
rough = rng.normal(0, 1, len(t)) * (0.5 + 0.5 * np.sin(phase)) * (0.1 + 0.5 * u)
v = src + rough

# Formants qui glissent de "ya" (ouvert) vers "ark" (fermé, nasal)
f1 = 750 - 300 * u
f2 = 1500 - 500 * u
out = (
    1.0 * biquad_bandpass(v, 700, 4) * (1 - 0.5 * u)
    + 0.9 * biquad_bandpass(v, 1300, 5)
    + 0.5 * biquad_bandpass(v, 2500, 6) * (1 - 0.6 * u)
    + 0.3 * v
)

# Enveloppe : attaque nette ("Y"), tenue, fin étouffée sur le "rk"
env = np.clip(t / 0.02, 0, 1) * np.where(u < 0.8, 1.0, np.exp(-(u - 0.8) / 0.06))
sig = out * env

# Petit "k" final : claquement bruité très court
k = rng.normal(0, 1, int(0.04 * FS)) * np.exp(-np.arange(int(0.04 * FS)) / (0.008 * FS))
k = biquad_bandpass(k, 1800, 2) * 3
sig = np.concatenate([sig, k * 0.5])

sig = sig / np.max(np.abs(sig)) * 0.9
pcm = (sig * 32767).astype(np.int16)
with wave.open("assets/sounds/yark.wav", "wb") as w:
    w.setnchannels(1)
    w.setsampwidth(2)
    w.setframerate(FS)
    w.writeframes(pcm.tobytes())
print(f"OK yark.wav ({len(sig)/FS:.2f} s)")
