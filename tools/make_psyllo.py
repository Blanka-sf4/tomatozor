"""Psyllo, le champignon psychédélique (mode métronome, muet).

Usage : python3 tools/make_psyllo.py
Sortie : assets/images/psyllo_{normal,blink}.png (512×512, fond transparent)
"""
from PIL import Image, ImageDraw
import math

S, SS = 512, 4
W = S * SS
BLACK = (30, 20, 30)
OUT = 6 * SS
CAP = (150, 60, 220)
CAP_DARK = (110, 30, 180)
DOTS = (255, 90, 200)
STEM = (245, 225, 255)
EYE = (255, 250, 200)


def p(x, y):
    return (x * SS, y * SS)


def box(cx, cy, rx, ry):
    return [p(cx - rx, cy - ry), p(cx + rx, cy + ry)]


def spiral(d, cx, cy, r, turns=2.5, width=6):
    pts = []
    n = 60
    for i in range(n):
        a = turns * 2 * math.pi * i / n
        rr = r * i / n
        pts.append(p(cx + rr * math.cos(a), cy + rr * math.sin(a)))
    d.line(pts, fill=BLACK, width=width * SS, joint="curve")


def draw_psyllo(d, frame="normal"):
    # Pied
    d.rounded_rectangle([p(196, 300), p(316, 470)], radius=50 * SS, fill=STEM, outline=BLACK, width=OUT)
    # Chapeau pointu : un cône aux flancs légèrement bombés, bord ondulé
    cone = [p(256, 20)]
    for i in range(0, 21):
        u = i / 20
        x = 256 - 236 * u
        y = 20 + 290 * u ** 0.75
        cone.insert(0, p(x, y))
    for i in range(0, 21):
        u = i / 20
        x = 256 + 236 * u
        y = 20 + 290 * u ** 0.75
        cone.append(p(x, y))
    d.polygon(cone, fill=CAP, outline=BLACK, width=OUT)
    d.rounded_rectangle([p(20, 295), p(492, 328)], radius=16 * SS, fill=CAP_DARK, outline=BLACK, width=OUT)
    # Pointe : petite boule au sommet, façon bonnet
    d.ellipse(box(256, 24, 22, 22), fill=DOTS, outline=BLACK, width=3 * SS)
    # Pois roses, tailles variées, dans le cône
    for cx, cy, r in ((150, 245, 26), (215, 150, 30), (300, 110, 20), (365, 235, 30), (256, 250, 16), (320, 190, 18)):
        d.ellipse(box(cx, cy, r, r), fill=DOTS, outline=BLACK, width=3 * SS)
    # Yeux en spirale (ou fermés)
    for cx in (225, 287):
        if frame == "blink":
            d.arc(box(cx, 360, 24, 14), start=0, end=180, fill=BLACK, width=5 * SS)
        else:
            d.ellipse(box(cx, 360, 26, 26), fill=EYE, outline=BLACK, width=4 * SS)
            spiral(d, cx, 360, 18, turns=2.2, width=4)
    # Sourire béat, un peu de travers
    d.arc(box(256, 405, 40, 26), start=10, end=170, fill=BLACK, width=6 * SS)
    d.ellipse(box(300, 418, 8, 6), fill=DOTS)


for frame in ("normal", "blink"):
    im = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    draw_psyllo(ImageDraw.Draw(im), frame)
    im.resize((S, S), Image.LANCZOS).save(f"assets/images/psyllo_{frame}.png")
print("OK psyllo ×2")
