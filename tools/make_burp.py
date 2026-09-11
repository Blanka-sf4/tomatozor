"""Un long rot de dino (tempo < 100) → assets/sounds/burp.wav"""
import numpy as np
from synth_common import FS, biquad_bandpass, harmonics, save

rng = np.random.default_rng(8)
DUR = 1.7
t = np.arange(int(DUR * FS)) / FS
u = t / DUR

# Hauteur : part bas, monte un peu (la pression), redescend en s'étouffant.
f0 = 75 + 35 * np.sin(np.pi * np.clip(u / 0.85, 0, 1)) - 15 * np.clip((u - 0.85) / 0.15, 0, 1)
# Gargouillis : modulation de hauteur irrégulière à ~12 Hz + tremblement lent
f0 = f0 * (1 + 0.10 * np.sin(2 * np.pi * 12.5 * t + 3 * np.sin(2 * np.pi * 1.3 * t)))

src, phase = harmonics(f0, n=24, tilt=0.35)
# Rauque : bruit modulé par la voix (gorge qui vibre)
rough = rng.normal(0, 1, len(t)) * (0.5 + 0.5 * np.sin(phase)) * 0.35
v = src + rough
# Modulation d'amplitude en "vagues" : le rot vient par bouffées
am = 0.7 + 0.3 * np.sin(2 * np.pi * 6.5 * t) * np.sin(2 * np.pi * 2.1 * t + 1)
v = v * am

# Formants d'une bouche grande ouverte ("aaa" grave) : ça fait rot et pas moteur
out = (
    1.0 * biquad_bandpass(v, 550, 4)
    + 0.7 * biquad_bandpass(v, 1100, 5)
    + 0.35 * biquad_bandpass(v, 2400, 6)
    + 0.4 * biquad_bandpass(v, 140, 2)  # le corps grave
    + 0.2 * v
)
# Attaque "b" : un pop bref au début
pop = np.zeros_like(t)
pop[: int(0.03 * FS)] = np.sin(2 * np.pi * 90 * t[: int(0.03 * FS)]) * np.exp(-t[: int(0.03 * FS)] / 0.008) * 2
env = np.clip(t / 0.03, 0, 1) * np.where(u < 0.8, 1.0, np.exp(-(u - 0.8) / 0.09))
save("assets/sounds/burp.wav", out * env + pop)
