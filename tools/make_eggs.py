"""Sons des easter eggs → assets/sounds/{purr,startle,splotch,giggle}.wav"""
import numpy as np
from synth_common import FS, biquad_bandpass, harmonics, save

rng = np.random.default_rng(99)

# --- Ronron du chat (boucle 1,6 s) : train d'impulsions à ~25 Hz, modulé par
# la respiration, filtré grave.
t = np.arange(int(1.6 * FS)) / FS
f = 25 + 2 * np.sin(2 * np.pi * 0.6 * t)
phase = np.cumsum(f) / FS
pulse = np.exp(-((phase % 1.0) * 6) ** 1.6)
breath = 0.55 + 0.45 * np.sin(2 * np.pi * 0.62 * t) ** 2
purr = biquad_bandpass(pulse * breath, 90, 1.5) * 3 + 0.3 * biquad_bandpass(pulse * breath, 300, 2)
# fondu aux deux bouts pour boucler proprement
fade = np.minimum(np.minimum(t / 0.05, 1), (1.6 - t) / 0.05).clip(0, 1)
save("assets/sounds/purr.wav", purr * fade)

# --- Sursaut « hein ?! » : voix qui monte vite, brève
t = np.arange(int(0.3 * FS)) / FS
u = t / 0.3
f0 = 220 * (2.6) ** u
src, _ = harmonics(f0, n=12, tilt=0.6)
out = biquad_bandpass(src, 800, 4) + 0.7 * biquad_bandpass(src, 1800, 5) + 0.3 * src
env = np.clip(t / 0.01, 0, 1) * np.where(u < 0.7, 1.0, np.exp(-(u - 0.7) / 0.08))
save("assets/sounds/startle.wav", out * env)

# --- Splotch : œuf qui se casse — craquement bref + éclaboussure mouillée
t = np.arange(int(0.45 * FS)) / FS
crack = rng.normal(0, 1, len(t)) * np.exp(-t / 0.004)
crack = biquad_bandpass(crack, 3500, 1.5) * 4
splat = rng.normal(0, 1, len(t)) * np.exp(-t / 0.08)
splat = biquad_bandpass(splat, 900, 1) * 2 * (0.5 + 0.5 * np.sin(2 * np.pi * 18 * t))
save("assets/sounds/splotch.wav", crack + splat * 0.8)

# --- Rire de Psyllo : « hi hi hi hi » bulleux, aigu, qui monte
parts = []
for k in range(5):
    dur = 0.11
    t = np.arange(int(dur * FS)) / FS
    f0 = (700 + 60 * k) * (1.25) ** (t / dur)
    src, _ = harmonics(f0, n=8, tilt=0.9)
    out = biquad_bandpass(src, 1500, 5) + 0.6 * biquad_bandpass(src, 3000, 6) + 0.2 * src
    env = np.clip(t / 0.008, 0, 1) * np.exp(-t / 0.05)
    parts.append(out * env)
    parts.append(np.zeros(int(0.04 * FS)))
save("assets/sounds/giggle.wav", np.concatenate(parts))
