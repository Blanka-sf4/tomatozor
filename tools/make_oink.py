"""Synthétise un cochon : « groin groin groin groiiiiiing » → assets/sounds/oink.wav

Usage : python3 tools/make_oink.py
"""
import numpy as np
import wave

FS = 44100
rng = np.random.default_rng(11)


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


def voice(f0, breath=0.3):
    """Source vocale de cochon : harmoniques + souffle rauque du groin."""
    phase = 2 * np.pi * np.cumsum(f0) / FS
    src = np.zeros_like(f0)
    for n in range(1, 18):
        src += np.sin(n * phase) / n ** 0.4
    src /= np.max(np.abs(src))
    # Le "rauque" : du bruit modulé par la voix elle-même (ça râpe).
    rough = rng.normal(0, 1, len(f0)) * (0.5 + 0.5 * np.sin(phase)) * breath
    v = src + rough
    # Formants nasaux : ce qui fait "groin" plutôt que "meuh".
    return (
        1.0 * biquad_bandpass(v, 480, 5)
        + 0.9 * biquad_bandpass(v, 950, 6)
        + 0.5 * biquad_bandpass(v, 1900, 7)
        + 0.25 * v
    )


def grunt(dur=0.24):
    """Un « groin » : hauteur en cloche, attaque nette, fin étouffée."""
    t = np.arange(int(dur * FS)) / FS
    u = t / dur
    f0 = 170 + 90 * np.sin(np.pi * u) ** 0.8
    f0 = f0 * (1 + 0.03 * np.sin(2 * np.pi * 35 * t))  # petit trémolo
    v = voice(f0, breath=0.35)
    env = np.clip(t / 0.015, 0, 1) * np.where(u < 0.7, 1.0, np.exp(-(u - 0.7) / 0.08))
    return v * env


def squeal(dur=1.5):
    """« groiiiiiing » : commence en grognement, monte en couinement, redescend."""
    t = np.arange(int(dur * FS)) / FS
    u = t / dur
    # 200 Hz pendant 0.25 s, puis glissade vers 950 Hz, puis chute finale.
    f0 = np.where(
        u < 0.17,
        200 + 40 * np.sin(np.pi * u / 0.17),
        200 * (950 / 200) ** np.clip((u - 0.17) / 0.6, 0, 1),
    )
    f0 = np.where(u > 0.88, f0 * (1 - 0.5 * (u - 0.88) / 0.12), f0)
    f0 = f0 * (1 + 0.04 * np.sin(2 * np.pi * (9 + 6 * u) * t))  # vibrato
    v = voice(f0, breath=0.25)
    env = np.clip(t / 0.02, 0, 1) * np.where(u < 0.85, 1.0, np.exp(-(u - 0.85) / 0.05))
    # Le couinement est plus fort que le grognement
    env = env * (0.8 + 0.4 * np.clip((u - 0.17) / 0.4, 0, 1))
    return v * env


gap = np.zeros(int(0.13 * FS))
parts = [grunt(), gap, grunt(0.22), gap, grunt(0.26), gap, squeal()]
sig = np.concatenate(parts)
sig = sig / np.max(np.abs(sig)) * 0.9
pcm = (sig * 32767).astype(np.int16)

with wave.open("assets/sounds/oink.wav", "wb") as w:
    w.setnchannels(1)
    w.setsampwidth(2)
    w.setframerate(FS)
    w.writeframes(pcm.tobytes())
print(f"OK oink.wav ({len(sig)/FS:.2f} s)")
