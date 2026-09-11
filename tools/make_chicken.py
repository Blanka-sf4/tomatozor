"""Dessine le poulet à grosse tête (mode métronome).

Usage : python3 tools/make_chicken.py
Sortie : assets/images/chicken_{normal,blink,cluck}.png (512×512, fond transparent)
"""
from PIL import Image, ImageDraw

S, SS = 512, 4
W = S * SS
BLACK = (30, 20, 30)
OUT = 6 * SS
CREAM = (252, 246, 228)
RED = (225, 45, 55)
YELLOW = (250, 190, 40)
ORANGE = (235, 140, 30)


def p(x, y):
    return (x * SS, y * SS)


def box(cx, cy, rx, ry):
    return [p(cx - rx, cy - ry), p(cx + rx, cy + ry)]


def draw_chicken(d, frame="normal"):
    # Crête : trois bosses rouges
    for cx, r in ((200, 48), (256, 60), (312, 48)):
        d.ellipse(box(cx, 90, r, r), fill=RED, outline=BLACK, width=OUT)
    # Tête : grosse, presque ronde
    d.ellipse(box(256, 290, 195, 185), fill=CREAM, outline=BLACK, width=OUT)
    d.ellipse(box(256, 290, 189, 179), fill=CREAM)  # recouvre le bas de la crête
    # Caroncule (le rouge qui pend sous le bec)
    d.ellipse(box(256, 445, 34, 48), fill=RED, outline=BLACK, width=OUT)
    # Bec
    if frame == "cluck":
        d.polygon([p(196, 350), p(330, 335), p(210, 372)], fill=YELLOW, outline=BLACK, width=OUT)
        d.polygon([p(196, 380), p(330, 395), p(210, 358)], fill=ORANGE, outline=BLACK, width=OUT)
    else:
        d.polygon([p(196, 350), p(330, 365), p(200, 385)], fill=YELLOW, outline=BLACK, width=OUT)
        d.line([p(200, 368), p(322, 365)], fill=BLACK, width=3 * SS)
    # Œil (un seul bien rond, de trois quarts) + le second plus petit
    for cx, r in ((300, 40), (190, 28)):
        if frame == "blink":
            d.arc(box(cx, 280, r, r * 0.6), start=0, end=180, fill=BLACK, width=6 * SS)
        else:
            d.ellipse(box(cx, 280, r, r), fill="white", outline=BLACK, width=4 * SS)
            d.ellipse(box(cx + 4, 284, r * 0.55, r * 0.55), fill=BLACK)
            d.ellipse(box(cx + 12, 272, r * 0.2, r * 0.2), fill="white")
    # Joue
    d.ellipse(box(150, 350, 30, 22), fill=(255, 200, 200))


for frame in ("normal", "blink", "cluck"):
    im = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    draw_chicken(ImageDraw.Draw(im), frame)
    im.resize((S, S), Image.LANCZOS).save(f"assets/images/chicken_{frame}.png")
print("OK poulet ×3")
