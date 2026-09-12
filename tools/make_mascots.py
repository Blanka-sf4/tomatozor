"""Dessine les mascottes : le chat tricolore et l'incognito.

Usage : python3 tools/make_mascots.py
Sortie : assets/images/cat_{normal,blink,ear,meow}.png
         assets/images/incog_{normal,peek,hide}.png   (512×512, fond transparent)
"""
from PIL import Image, ImageDraw

S = 512
SS = 4
W = S * SS
BLACK = (30, 20, 30)
OUT = 6 * SS  # épaisseur du contour, même esprit que le dino


def p(x, y):
    return (x * SS, y * SS)


def box(cx, cy, rx, ry):
    return [p(cx - rx, cy - ry), p(cx + rx, cy + ry)]


# ---------------------------------------------------------------------------
# Le chat tricolore (roux / blanc / brun, nez rose)
# ---------------------------------------------------------------------------
ORANGE = (240, 140, 50)
BROWN = (110, 70, 45)
WHITE = (250, 246, 240)
PINK = (255, 120, 160)
AMBER = (240, 190, 60)


def draw_cat(d, frame="normal"):
    ear_tilt = 1 if frame == "ear" else 0
    # Oreilles (triangles), la droite bouge sur la frame "ear"
    d.polygon([p(100, 190), p(135, 40), p(235, 160)], fill=ORANGE, outline=BLACK, width=OUT)
    d.polygon([p(120, 165), p(140, 85), p(205, 155)], fill=PINK)
    rx = 30 * ear_tilt
    d.polygon([p(412, 190), p(377 + rx, 40 + 15 * ear_tilt), p(277, 160)], fill=BROWN, outline=BLACK, width=OUT)
    d.polygon([p(392, 165), p(372 + rx, 85 + 10 * ear_tilt), p(307, 155)], fill=PINK)
    # Tête
    d.ellipse(box(256, 290, 190, 165), fill=WHITE, outline=BLACK, width=OUT)
    # Taches : roux à gauche, brun à droite (le calico)
    d.pieslice(box(256, 290, 184, 159), start=180, end=270, fill=ORANGE)
    d.pieslice(box(256, 290, 184, 159), start=270, end=340, fill=BROWN)
    d.ellipse(box(190, 200, 70, 50), fill=ORANGE)
    d.ellipse(box(330, 215, 60, 45), fill=BROWN)
    # Museau blanc
    d.ellipse(box(256, 355, 115, 80), fill=WHITE)
    # Yeux
    for cx in (185, 327):
        if frame == "blink":
            d.arc(box(cx, 275, 40, 22), start=0, end=180, fill=BLACK, width=5 * SS)
        else:
            d.ellipse(box(cx, 272, 40, 30), fill=AMBER, outline=BLACK, width=4 * SS)
            d.ellipse(box(cx, 272, 10, 24), fill=BLACK)
            d.ellipse(box(cx + 12, 262, 6, 6), fill=WHITE)
    # Nez rose
    d.polygon([p(236, 330), p(276, 330), p(256, 352)], fill=PINK, outline=BLACK, width=3 * SS)
    # Bouche
    if frame == "meow":
        d.ellipse(box(256, 392, 34, 30), fill=BLACK)
        d.ellipse(box(256, 405, 20, 14), fill=PINK)
    else:
        d.line([p(256, 352), p(256, 372)], fill=BLACK, width=4 * SS)
        d.arc(box(236, 372, 20, 14), start=0, end=180, fill=BLACK, width=4 * SS)
        d.arc(box(276, 372, 20, 14), start=0, end=180, fill=BLACK, width=4 * SS)
    # Moustaches
    for side in (-1, 1):
        for dy in (-12, 4, 20):
            x0 = 256 + side * 60
            d.line([p(x0, 360 + dy), p(x0 + side * 120, 345 + dy * 1.6)], fill=BLACK, width=3 * SS)


# ---------------------------------------------------------------------------
# L'incognito (chapeau, lunettes noires, derrière son journal)
# ---------------------------------------------------------------------------
SKIN = (245, 205, 170)
HAT = (70, 60, 75)
HATBAND = (30, 25, 35)
PAPER = (235, 230, 215)
INK = (90, 90, 100)


def draw_incog(d, frame="normal"):
    paper_top = {"normal": 262, "peek": 335, "hide": 228, "mustache": 372}[frame]
    hat_dy = 48 if frame == "hide" else 0
    # Tête (cachée en partie par le journal)
    d.ellipse(box(256, 245, 118, 128), fill=SKIN, outline=BLACK, width=OUT)
    # Nez et bouche (visibles seulement en "peek" / "mustache")
    d.polygon([p(256, 255), p(272, 292), p(248, 292)], fill=(230, 180, 150), outline=BLACK, width=3 * SS)
    if frame == "mustache":
        # Grosse moustache en guidon, sourire gêné, joues rouges
        for side in (-1, 1):
            d.chord(box(256 + side * 48, 305, 52, 18), start=180, end=360, fill=(50, 30, 20))
            d.ellipse(box(256 + side * 92, 300, 14, 14), fill=(50, 30, 20))
        d.arc(box(256, 335, 30, 14), start=10, end=170, fill=BLACK, width=5 * SS)
        d.ellipse(box(170, 325, 22, 14), fill=(255, 150, 150))
        d.ellipse(box(342, 325, 22, 14), fill=(255, 150, 150))
    else:
        d.line([p(226, 312), p(286, 312)], fill=BLACK, width=5 * SS)
    # Lunettes noires
    for cx in (203, 309):
        d.rounded_rectangle(box(cx, 220, 46, 28), radius=14 * SS, fill=BLACK)
    d.line([p(249, 218), p(263, 218)], fill=BLACK, width=6 * SS)
    d.line([p(157, 214), p(140, 205)], fill=BLACK, width=6 * SS)
    d.line([p(355, 214), p(372, 205)], fill=BLACK, width=6 * SS)
    # Chapeau (baissé sur les yeux en "hide")
    d.rounded_rectangle([p(150, 62 + hat_dy), p(362, 165 + hat_dy)], radius=22 * SS, fill=HAT, outline=BLACK, width=OUT)
    d.rectangle([p(150, 135 + hat_dy), p(362, 160 + hat_dy)], fill=HATBAND)
    d.ellipse(box(256, 162 + hat_dy, 190, 30), fill=HAT, outline=BLACK, width=OUT)
    # Journal, par-dessus tout
    d.rectangle([p(48, paper_top), p(464, 500)], fill=PAPER, outline=BLACK, width=OUT)
    d.line([p(256, paper_top), p(256, 500)], fill=BLACK, width=4 * SS)
    # Gros titre + colonnes de texte (des traits)
    y = paper_top + 22
    d.rectangle([p(70, y), p(240, y + 26)], fill=INK)
    d.rectangle([p(272, y), p(442, y + 26)], fill=INK)
    y += 44
    while y < 480:
        for x0, x1 in ((70, 240), (272, 442)):
            d.rectangle([p(x0, y), p(x1 - 20, y + 8)], fill=(170, 170, 175))
        y += 20


for name, fn, frames in (
    ("cat", draw_cat, ("normal", "blink", "ear", "meow")),
    ("incog", draw_incog, ("normal", "peek", "hide", "mustache")),
):
    for frame in frames:
        im = Image.new("RGBA", (W, W), (0, 0, 0, 0))
        fn(ImageDraw.Draw(im), frame)
        im.resize((S, S), Image.LANCZOS).save(f"assets/images/{name}_{frame}.png")
print("OK mascottes : cat ×4, incog ×3")
