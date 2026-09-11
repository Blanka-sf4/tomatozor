"""Dessine l'icône TOMATOZOR (tête de dino rose) en 1024x1024.

Usage : python3 tools/make_icon.py
Sortie : assets/icon/icon.png (fond) et assets/icon/icon_fg.png (dino seul,
         fond transparent, pour l'icône adaptative Android).
"""
from PIL import Image, ImageDraw, ImageFilter

S = 1024
SS = 4  # suréchantillonnage pour l'anti-aliasing
W = S * SS

PINK = (255, 105, 180)
PINK_DARK = (219, 62, 140)
PINK_LIGHT = (255, 160, 205)
CREAM = (255, 240, 245)
BLACK = (40, 20, 40)
WHITE = (255, 255, 255)


def p(x, y):
    """Coordonnées en unités 0..1024 → pixels suréchantillonnés."""
    return (x * SS, y * SS)


def draw_dino(draw):
    # Cou
    draw.polygon([p(300, 620), p(470, 560), p(520, 900), p(250, 900)], fill=PINK)
    # Crâne : gros ovale
    draw.ellipse([p(260, 250), p(700, 640)], fill=PINK)
    # Museau : ovale allongé vers la droite
    draw.ellipse([p(480, 380), p(880, 620)], fill=PINK)
    # Mâchoire inférieure
    draw.polygon([p(520, 560), p(860, 560), p(820, 660), p(540, 660)], fill=PINK_DARK)
    # Bouche (ligne sombre)
    draw.line([p(520, 560), p(860, 560)], fill=BLACK, width=8 * SS)
    # Dents
    for x in range(560, 840, 60):
        draw.polygon([p(x, 560), p(x + 40, 560), p(x + 20, 610)], fill=WHITE)
    # Narine
    draw.ellipse([p(800, 440), p(830, 470)], fill=BLACK)
    # Épines sur le crâne
    for i, x in enumerate(range(300, 620, 80)):
        h = 90 + 30 * (i % 2)
        draw.polygon([p(x, 300), p(x + 40, 300 - h), p(x + 80, 290)], fill=PINK_DARK)
    # Œil
    draw.ellipse([p(560, 320), p(680, 440)], fill=WHITE)
    draw.ellipse([p(600, 350), p(670, 420)], fill=BLACK)
    draw.ellipse([p(640, 360), p(662, 382)], fill=WHITE)  # reflet
    # Joue claire
    draw.ellipse([p(430, 470), p(520, 540)], fill=PINK_LIGHT)
    # Petit bras ridicule
    draw.ellipse([p(430, 700), p(560, 760)], fill=PINK_DARK)
    draw.ellipse([p(530, 700), p(600, 750)], fill=PINK_DARK)


# --- calque dino, fond transparent ----------------------------------------
fg = Image.new("RGBA", (W, W), (0, 0, 0, 0))
draw_dino(ImageDraw.Draw(fg))
fg = fg.resize((S, S), Image.LANCZOS)

# --- fond dégradé ------------------------------------------------------------
bg = Image.new("RGB", (S, S))
px = bg.load()
for y in range(S):
    t = y / S
    r = int(60 + (120 - 60) * t)
    g = int(20 + (40 - 20) * t)
    b = int(90 + (160 - 90) * t)
    for x in range(S):
        px[x, y] = (r, g, b)

# --- icône complète (fond + dino, avec une ombre douce) ---------------------
shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
shadow.paste((0, 0, 0, 140), (0, 0, S, S), fg.split()[3])
shadow = shadow.filter(ImageFilter.GaussianBlur(18))
icon = bg.convert("RGBA")
icon.alpha_composite(shadow, (12, 18))
icon.alpha_composite(fg)
icon.convert("RGB").save("assets/icon/icon.png")

# Pour l'icône adaptative, Android rogne les bords : on centre le dino dans
# une zone sûre (66 % du canevas) sur fond transparent.
fg_small = fg.resize((int(S * 0.66), int(S * 0.66)), Image.LANCZOS)
adaptive = Image.new("RGBA", (S, S), (0, 0, 0, 0))
off = (S - fg_small.width) // 2
adaptive.alpha_composite(fg_small, (off, off))
adaptive.save("assets/icon/icon_fg.png")
print("OK icon.png + icon_fg.png")
