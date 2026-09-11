"""Briques communes aux synthés de cris (tools/make_*.py)."""
import numpy as np
import wave

FS = 44100


def biquad_bandpass(x, f0, q):
    """Filtre passe-bande résonant (formant)."""
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


def harmonics(f0, n=16, tilt=0.5, rng=None, jitter=0.0):
    """Somme d'harmoniques d'amplitude 1/n^tilt sur une hauteur f0(t)."""
    phase = 2 * np.pi * np.cumsum(f0) / FS
    out = np.zeros_like(f0)
    for k in range(1, n + 1):
        j = rng.normal(0, jitter) if (rng is not None and jitter) else 0.0
        out += np.sin(k * phase + j) / k ** tilt
    return out / np.max(np.abs(out)), phase


def save(path, sig):
    sig = sig / np.max(np.abs(sig)) * 0.9
    pcm = (sig * 32767).astype(np.int16)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(FS)
        w.writeframes(pcm.tobytes())
    print(f"OK {path} ({len(sig)/FS:.2f} s)")
