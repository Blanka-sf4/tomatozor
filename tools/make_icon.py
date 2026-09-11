"""Dessine l'icône TOMATOZOR : tête de dino rose, de face, plein cadre.

Usage : python3 tools/make_icon.py
Sortie : assets/icon/icon.png (icône complète) et assets/icon/icon_fg.png
         (calque avant-plan pour l'icône adaptative Android).
"""
from PIL import Image, ImageDraw, ImageFilter

S = 1024
SS = 4  # suréchantillonnage pour l'anti-aliasing
W = S * SS

PINK = (255, 105, 180)
PINK_DARK = (214, 58, 138)
PINK_DEEP = (160, 30, 100)
PINK_LIGHT = (255, 170, 210)
BLACK = (40, 18, 40)
WHITE = (255, 255, 255)


# Facteur de zoom : > 1 = la tête déborde du cadre (on veut qu'elle prenne
# vraiment toute la place).
ZOOM = 1.22
CX, CY = 512, 560  # centre du zoom (le milieu de la tête)


def p(x, y):
    return ((CX + (x - CX) * ZOOM) * SS, (CY + (y - CY) * ZOOM) * SS)


def box(cx, cy, rx, ry):
    return [p(cx - rx, cy - ry), p(cx + rx, cy + ry)]


def draw_dino(draw, margin=0):
    """margin : réduction homothétique (0 = plein cadre)."""
    # Épines : dessinées d'abord, la tête vient par-dessus.
    for i, x in enumerate(range(150, 900, 105)):
        h = 130 if i % 2 == 0 else 95
        draw.polygon([p(x, 240), p(x + 52, 240 - h), p(x + 105, 240)], fill=PINK_DARK)
    # Tête : gros ovale qui déborde presque du cadre.
    draw.ellipse(box(512, 560, 470, 430), fill=PINK)
    # Arcades sourcilières (un peu menaçant, c'est un dino)
    draw.ellipse(box(360, 400, 150, 70), fill=PINK_DARK)
    draw.ellipse(box(664, 400, 150, 70), fill=PINK_DARK)
    draw.ellipse(box(512, 520, 480, 380), fill=PINK)  # recouvre le bas des arcades
    # Museau, plus clair
    draw.ellipse(box(512, 660, 300, 190), fill=PINK_LIGHT)
    # Narines
    draw.ellipse(box(430, 620, 38, 28), fill=PINK_DEEP)
    draw.ellipse(box(594, 620, 38, 28), fill=PINK_DEEP)
    # Bouche : large sourire, bande sombre en arc
    draw.chord(box(512, 640, 300, 190), start=15, end=165, fill=PINK_DEEP)
    draw.chord(box(512, 600, 300, 190), start=15, end=165, fill=PINK_LIGHT)
    # Dents : triangles pointant vers le bas le long de la lèvre supérieure
    for x in range(250, 800, 62):
        draw.polygon([p(x, 720), p(x + 50, 720), p(x + 25, 790)], fill=WHITE)
    # Joues
    draw.ellipse(box(150, 590, 60, 45), fill=PINK_LIGHT)
    draw.ellipse(box(874, 590, 60, 45), fill=PINK_LIGHT)
    # Yeux : blanc, pupille centrée (regard vers l'utilisateur), reflet
    for cx in (372, 652):
        draw.ellipse(box(cx, 440, 100, 105), fill=WHITE)
        draw.ellipse(box(cx, 452, 62, 66), fill=BLACK)
        draw.ellipse(box(cx + 22, 428, 22, 22), fill=WHITE)
        draw.ellipse(box(cx - 18, 478, 9, 9), fill=WHITE)


# --- calque dino, fond transparent ----------------------------------------
fg = Image.new("RGBA", (W, W), (0, 0, 0, 0))
draw_dino(ImageDraw.Draw(fg))
fg = fg.resize((S, S), Image.LANCZOS)

# --- fond dégradé violet -------------------------------------------------------
bg = Image.new("RGB", (S, S))
px = bg.load()
for y in range(S):
    t = y / S
    px_row = (int(60 + 60 * t), int(20 + 20 * t), int(90 + 70 * t))
    for x in range(S):
        px[x, y] = px_row

# --- icône complète ---------------------------------------------------------------
shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
shadow.paste((0, 0, 0, 150), (0, 0, S, S), fg.split()[3])
shadow = shadow.filter(ImageFilter.GaussianBlur(20))
icon = bg.convert("RGBA")
icon.alpha_composite(shadow, (0, 16))
icon.alpha_composite(fg)
icon.convert("RGB").save("assets/icon/icon.png")

# Icône adaptative : Android rogne les bords (cercle, squircle…), on garde
# la tête dans la zone sûre (~72 % du canevas).
# Le calque plein cadre est dessiné sans zoom (le dino tient dans le
# canevas), puis réduit à 80 % : rogné en rond, la tête remplit le disque.
fg_plain = Image.new("RGBA", (W, W), (0, 0, 0, 0))
ZOOM = 1.0
draw_dino(ImageDraw.Draw(fg_plain))
fg_plain = fg_plain.resize((S, S), Image.LANCZOS)
fg_small = fg_plain.resize((int(S * 0.80), int(S * 0.80)), Image.LANCZOS)
adaptive = Image.new("RGBA", (S, S), (0, 0, 0, 0))
off = (S - fg_small.width) // 2
adaptive.alpha_composite(fg_small, (off, off + 10))
adaptive.save("assets/icon/icon_fg.png")
# Tête recadrée serrée, pour les O du titre et le bouton du mode secours.
bbox = fg_plain.getbbox()
head = fg_plain.crop(bbox)
side = max(head.size) + 20
sq = Image.new("RGBA", (side, side), (0, 0, 0, 0))
sq.alpha_composite(head, ((side - head.width) // 2, (side - head.height) // 2))
sq.resize((512, 512), Image.LANCZOS).save("assets/images/dino_head.png")
print("OK icon.png + icon_fg.png + dino_head.png")
