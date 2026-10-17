#!/usr/bin/env python3
"""Mesure une capture d'ecran de tests/sonde_centrage_plein_ecran.exe.

  python3 -I sonde_centrage_mesurer.py capture.png

Sur la rangee du milieu : premier pixel rouge (bande gauche de la mire),
dernier pixel vert (bande droite), et ce qu'il y a en dehors. Sortie 0 si
l'image est centree (marges egales a 1 % de la largeur pres) et ses marges
noires ; 1 sinon (image excentree : Wine sans 0171).
"""
import sys
from PIL import Image


def genre(p):
    r, g, b = p[:3]
    # couleurs de la mire apres gestion des couleurs de l'ecran (P3) :
    # rouge ~ (234, 51, 35), vert ~ (117, 251, 76), bleu ~ (0, 0, 245)
    if r > 150 and g < 110 and b < 110:
        return "rouge"
    if g > 150 and r < 160 and b < 140:
        return "vert"
    if b > 150 and r < 90 and g < 90:
        return "bleu"
    if r < 24 and g < 24 and b < 24:
        return "noir"
    return "autre"


def main():
    im = Image.open(sys.argv[1]).convert("RGB")
    w, h = im.size
    y = h // 2
    rangee = [genre(im.getpixel((x, y))) for x in range(w)]
    if "rouge" not in rangee or "vert" not in rangee:
        print(f"capture {w}x{h} : mire introuvable sur la rangee {y}")
        return 2
    debut = rangee.index("rouge")
    fin = w - 1 - rangee[::-1].index("vert")
    gauche, droite = debut, w - 1 - fin
    hors = rangee[:debut] + rangee[fin + 1:]
    noirs = sum(1 for g in hors if g == "noir")
    print(f"capture {w}x{h} ; image de x={debut} a x={fin} ({fin - debut + 1} px) ; "
          f"marges {gauche} | {droite} px ; hors image : {noirs}/{len(hors)} noirs")
    centree = abs(gauche - droite) <= w // 100
    sombre = not hors or noirs >= 0.98 * len(hors)
    print("CENTREE" if centree and sombre else "EXCENTREE" if not centree else "MARGES NON NOIRES")
    return 0 if centree and sombre else 1


if __name__ == "__main__":
    sys.exit(main())
