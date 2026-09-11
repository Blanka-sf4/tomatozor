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


GREEN = (150, 225, 150)
TONGUE = (235, 70, 110)
SWEAT = (140, 200, 255)


def draw_dino(draw, expr="normal"):
    """expr : normal | yark (dégoûté, saturation) | squish1..3 (écrasé, tap)."""
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
    # Museau, plus clair (verdâtre quand il a la nausée)
    snout = GREEN if expr == "yark" else PINK_LIGHT
    draw.ellipse(box(512, 660, 300, 190), fill=snout)
    # Narines
    draw.ellipse(box(430, 620, 38, 28), fill=PINK_DEEP)
    draw.ellipse(box(594, 620, 38, 28), fill=PINK_DEEP)

    # --- Sourcils (tête "j'écoute" : levés, intrigué) ---------------------
    if expr in ("listen", "listen_noeyes"):
        draw.arc(box(372, 330, 110, 45), start=200, end=340, fill=PINK_DEEP, width=16 * SS)
        draw.arc(box(652, 315, 110, 45), start=200, end=340, fill=PINK_DEEP, width=16 * SS)

    # --- Bouche ---------------------------------------------------------
    if expr == "yell":
        # Hurlement de joie : bouche énorme, langue au fond, dents en haut
        draw.ellipse(box(512, 770, 230, 130), fill=PINK_DEEP)
        draw.ellipse(box(512, 850, 110, 60), fill=TONGUE)
        for x in range(330, 700, 62):
            draw.polygon([p(x, 655), p(x + 50, 655), p(x + 25, 710)], fill=WHITE)
    elif expr == "tongue":
        # Langue tirée, bien au milieu, insolente
        draw.chord(box(512, 640, 300, 190), start=15, end=165, fill=PINK_DEEP)
        draw.chord(box(512, 600, 300, 190), start=15, end=165, fill=snout)
        for x in range(250, 800, 62):
            draw.polygon([p(x, 720), p(x + 50, 720), p(x + 25, 790)], fill=WHITE)
        draw.ellipse(box(512, 840, 95, 120), fill=TONGUE)
        draw.line([p(512, 760), p(512, 940)], fill=(190, 40, 80), width=6 * SS)
    elif expr == "huh":
        # "Hein ?" : petite bouche de travers
        draw.ellipse(box(560, 775, 45, 32), fill=PINK_DEEP)
    elif expr in ("listen", "listen_noeyes"):
        # Petit sourire fermé, attentif
        draw.arc(box(512, 720, 120, 70), start=20, end=160, fill=PINK_DEEP, width=14 * SS)
    elif expr == "yark":
        # Grande bouche ouverte, langue pendante, dents en haut
        draw.ellipse(box(512, 760, 200, 110), fill=PINK_DEEP)
        draw.ellipse(box(512, 830, 90, 110), fill=TONGUE)
        draw.line([p(512, 760), p(512, 920)], fill=(190, 40, 80), width=6 * SS)
        for x in range(360, 680, 62):
            draw.polygon([p(x, 665), p(x + 50, 665), p(x + 25, 720)], fill=WHITE)
    elif expr == "squish1":
        # Bouche en "O" surpris
        draw.ellipse(box(512, 770, 90, 100), fill=PINK_DEEP)
        draw.ellipse(box(512, 800, 55, 55), fill=TONGUE)
    elif expr == "squish2":
        # Sourire de travers, langue qui sort sur le côté
        draw.chord(box(512, 640, 300, 190), start=15, end=165, fill=PINK_DEEP)
        draw.chord(box(512, 600, 300, 190), start=15, end=165, fill=snout)
        for x in range(250, 800, 62):
            draw.polygon([p(x, 720), p(x + 50, 720), p(x + 25, 790)], fill=WHITE)
        draw.ellipse(box(690, 800, 70, 60), fill=TONGUE)
        draw.line([p(690, 760), p(690, 850)], fill=(190, 40, 80), width=5 * SS)
    elif expr == "squish3":
        # Bouche plate, dents serrées
        draw.rectangle([p(300, 730), p(724, 800)], fill=PINK_DEEP)
        for x in range(310, 720, 52):
            draw.polygon([p(x, 730), p(x + 44, 730), p(x + 22, 770)], fill=WHITE)
            draw.polygon([p(x, 800), p(x + 44, 800), p(x + 22, 760)], fill=WHITE)
        # Goutte de sueur
        draw.ellipse(box(820, 330, 22, 30), fill=SWEAT)
        draw.polygon([p(798, 322), p(842, 322), p(820, 280)], fill=SWEAT)
    else:
        # Sourire normal
        draw.chord(box(512, 640, 300, 190), start=15, end=165, fill=PINK_DEEP)
        draw.chord(box(512, 600, 300, 190), start=15, end=165, fill=snout)
        for x in range(250, 800, 62):
            draw.polygon([p(x, 720), p(x + 50, 720), p(x + 25, 790)], fill=WHITE)

    # Joues
    cheek = GREEN if expr == "yark" else PINK_LIGHT
    cheek_r = 80 if expr == "squish1" else 60
    draw.ellipse(box(150, 590, cheek_r, cheek_r * 0.75), fill=cheek)
    draw.ellipse(box(874, 590, cheek_r, cheek_r * 0.75), fill=cheek)

    # --- Yeux -----------------------------------------------------------
    for i, cx in enumerate((372, 652)):
        if expr in ("head_noeyes", "listen_noeyes"):
            # Blanc de l'œil seul : l'appli dessine les pupilles elle-même
            draw.ellipse(box(cx, 440, 100, 105), fill=WHITE)
        elif expr == "yell":
            # Yeux fermés de plaisir : ^ ^
            draw.line([p(cx - 70, 470), p(cx, 410), p(cx + 70, 470)], fill=BLACK, width=20 * SS, joint="curve")
        elif expr == "huh":
            # Un œil plissé, l'autre normal mais petit
            if i == 0:
                draw.ellipse(box(cx, 440, 100, 55), fill=WHITE)
                draw.line([p(cx - 80, 445), p(cx + 80, 445)], fill=BLACK, width=18 * SS)
            else:
                draw.ellipse(box(cx, 440, 100, 105), fill=WHITE)
                draw.ellipse(box(cx, 452, 45, 48), fill=BLACK)
                draw.ellipse(box(cx + 16, 438, 14, 14), fill=WHITE)
        elif expr == "yark":
            # Yeux en croix : ><
            draw.ellipse(box(cx, 440, 100, 105), fill=WHITE)
            for dx, dy in ((-55, -55), (55, 55)):
                draw.line([p(cx - dx, 440 - dy), p(cx + dx, 440 + dy)], fill=BLACK, width=22 * SS)
            for dx, dy in ((-55, 55), (55, -55)):
                draw.line([p(cx - dx, 440 - dy), p(cx + dx, 440 + dy)], fill=BLACK, width=22 * SS)
        elif expr == "squish1":
            # Yeux exorbités, pupilles qui partent chacune de leur côté
            draw.ellipse(box(cx, 440, 125, 130), fill=WHITE)
            off = -35 if i == 0 else 35
            draw.ellipse(box(cx + off, 455, 45, 48), fill=BLACK)
            draw.ellipse(box(cx + off + 14, 440, 14, 14), fill=WHITE)
        elif expr == "squish2":
            if i == 0:
                # Clin d'œil : arc épais
                draw.arc(box(cx, 460, 90, 60), start=200, end=340, fill=BLACK, width=20 * SS)
            else:
                draw.ellipse(box(cx, 440, 100, 105), fill=WHITE)
                draw.ellipse(box(cx, 452, 62, 66), fill=BLACK)
                draw.ellipse(box(cx + 22, 428, 22, 22), fill=WHITE)
        elif expr == "squish3":
            # Yeux plissés : traits
            draw.ellipse(box(cx, 440, 100, 60), fill=WHITE)
            draw.line([p(cx - 80, 445), p(cx + 80, 445)], fill=BLACK, width=18 * SS)
        else:
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
# Calque à 100 % : Android n'affiche que les 66 % centraux, donc la tête
# déborde du disque et remplit tout, comme les icônes "plein cadre".
adaptive = fg_plain.copy()
adaptive.save("assets/icon/icon_fg.png")
# Tête recadrée serrée, pour les O du titre et le bouton du mode secours.
bbox = fg_plain.getbbox()
head = fg_plain.crop(bbox)
side = max(head.size) + 20
sq = Image.new("RGBA", (side, side), (0, 0, 0, 0))
sq.alpha_composite(head, ((side - head.width) // 2, (side - head.height) // 2))
sq.resize((512, 512), Image.LANCZOS).save("assets/images/dino_head.png")

# Les autres têtes, même recadrage (même bbox → même taille à l'écran).
for expr in ("yark", "squish1", "squish2", "squish3", "yell", "tongue", "huh",
             "listen", "head_noeyes", "listen_noeyes"):
    layer = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    draw_dino(ImageDraw.Draw(layer), expr)
    layer = layer.resize((S, S), Image.LANCZOS)
    head = layer.crop(bbox)
    sq = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    sq.alpha_composite(head, ((side - head.width) // 2, (side - head.height) // 2))
    sq.resize((512, 512), Image.LANCZOS).save(f"assets/images/dino_{expr}.png")
# Géométrie des yeux dans l'image 512×512 finale, pour que l'appli place
# les pupilles au bon endroit (dessinées par-dessus les têtes "_noeyes").
scale = 512 / side
ox = (side - head.width) // 2 - bbox[0]
oy = (side - head.height) // 2 - bbox[1]
import json
eyes = {
    "left": [round((372 + ox) * scale, 1), round((440 + oy) * scale, 1)],
    "right": [round((652 + ox) * scale, 1), round((440 + oy) * scale, 1)],
    "whiteRx": round(100 * scale, 1),
    "whiteRy": round(105 * scale, 1),
    "pupilR": round(64 * scale, 1),
    "pupilDy": round(12 * scale, 1),
}
json.dump(eyes, open("assets/images/dino_eyes.json", "w"), indent=2)
print("yeux :", eyes)
print("OK icon.png + icon_fg.png + dino_head.png + 10 expressions")
