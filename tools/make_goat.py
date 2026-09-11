"""La chèvre (celle qui hurle) → assets/images/goat_{normal,blink}.png"""
from PIL import Image, ImageDraw

S, SS = 512, 4
W = S * SS
BLACK = (30, 20, 30)
OUT = 6 * SS
FUR = (236, 232, 222)
FUR_DARK = (200, 194, 182)
HORN = (120, 95, 70)
PINKN = (230, 150, 160)
EYE = (240, 200, 90)


def p(x, y):
    return (x * SS, y * SS)


def box(cx, cy, rx, ry):
    return [p(cx - rx, cy - ry), p(cx + rx, cy + ry)]


def draw_goat(d, frame="normal"):
    # Cornes : plantées sur le crâne, courbées vers l'extérieur, effilées
    for side in (-1, 1):
        bx = 256 + side * 70  # base, sur le haut du crâne
        pts = [
            p(bx - 28, 175), p(bx + 28, 175),
            p(bx + side * 60 + 14, 110), p(bx + side * 120 + 4, 60),
            p(bx + side * 150, 30),
            p(bx + side * 110 - 10, 70), p(bx + side * 45 - 16, 120),
        ]
        d.polygon(pts, fill=HORN, outline=BLACK, width=5 * SS)
        # Stries
        for k in range(1, 4):
            d.line([p(bx + side * (20 + k * 28) - 14, 150 - k * 30), p(bx + side * (20 + k * 28) + 14, 140 - k * 30)], fill=BLACK, width=3 * SS)
    # Oreilles : longues, tombantes sur les côtés
    d.ellipse(box(110, 300, 55, 32), fill=FUR, outline=BLACK, width=OUT)
    d.ellipse(box(402, 300, 55, 32), fill=FUR, outline=BLACK, width=OUT)
    # Tête : longue (museau vers le bas)
    d.ellipse(box(256, 300, 150, 175), fill=FUR, outline=BLACK, width=OUT)
    # Toupet entre les cornes
    d.ellipse(box(256, 150, 60, 40), fill=FUR, outline=BLACK, width=OUT)
    # Museau : plus foncé
    d.ellipse(box(256, 400, 85, 65), fill=FUR_DARK)
    # Yeux : pupille horizontale (c'est ça, une chèvre)
    for cx in (200, 312):
        if frame == "blink":
            d.arc(box(cx, 290, 36, 18), start=0, end=180, fill=BLACK, width=6 * SS)
        else:
            d.ellipse(box(cx, 290, 38, 34), fill=EYE, outline=BLACK, width=4 * SS)
            d.rounded_rectangle(box(cx, 292, 22, 9), radius=8 * SS, fill=BLACK)
            d.ellipse(box(cx + 14, 278, 6, 6), fill="white")
    # Naseaux
    d.ellipse(box(232, 400, 12, 9), fill=BLACK)
    d.ellipse(box(280, 400, 12, 9), fill=BLACK)
    # Bouche : celle qui hurle, ouverte, langue
    d.ellipse(box(256, 445, 34, 26), fill=BLACK)
    d.ellipse(box(256, 455, 18, 12), fill=PINKN)
    # Barbichette
    d.polygon([p(232, 470), p(280, 470), p(256, 520)], fill=FUR_DARK, outline=BLACK, width=4 * SS)


for frame in ("normal", "blink"):
    im = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    draw_goat(ImageDraw.Draw(im), frame)
    im.resize((S, S), Image.LANCZOS).save(f"assets/images/goat_{frame}.png")
print("OK chèvre ×2")
