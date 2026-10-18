#!/usr/bin/env python3
"""Compare les images relues par tests/sonde_fg_present.cpp (PPM P6, gris) a la
scene vraie : l'image vraie N doit ressembler a la scene a N-1 (Present compte a
partir de 1), l'image generee presentee juste avant elle a la scene a N-1,5 ; on
la compare aussi au melange 50/50 des vraies N-1 et N.
   python3 sonde_fg_present.py <prefixe> <N>   (lit <prefixe>-<N-1>.ppm, -<N>.ppm, -<N>-generee.ppm)
"""
import math
import sys

VX, VY = 6.0, 2.0


def scene(x, y, t):
    x -= VX * t
    y -= VY * t
    v = 0.8 if (math.floor(x / 24.0) + math.floor(y / 24.0)) & 1 else 0.2
    if math.fmod(abs(x + 2.0 * y), 61.0) < 2.0:
        v = 1.0
    dx, dy = x + VX * t - 200, y + VY * t - 150
    if dx * dx + dy * dy < 3600:
        v = 0.5
    return v


def lire(chemin):
    d = open(chemin, 'rb').read()
    champs, pos = [], 0
    while len(champs) < 4:
        while d[pos:pos + 1].isspace():
            pos += 1
        fin = pos
        while not d[fin:fin + 1].isspace():
            fin += 1
        champs.append(d[pos:fin])
        pos = fin
    pos += 1
    w, h = int(champs[1]), int(champs[2])
    return w, h, [d[pos + 3 * i] / 255.0 for i in range(w * h)]


def psnr(a, b, w, h, pas=3):
    se, n = 0.0, 0
    for y in range(24, h - 24, pas):
        for x in range(24, w - 24, pas):
            e = a[y * w + x] - b[y * w + x]
            se += e * e
            n += 1
    return 99.0 if se == 0 else 10 * math.log10(n / se)


pre, n = sys.argv[1], int(sys.argv[2])
w, h, vraie_prec = lire(f'{pre}-{n - 1}.ppm')
_, _, vraie = lire(f'{pre}-{n}.ppm')
import os
if not os.path.exists(f'{pre}-{n}-generee.ppm'):
    # sans generation d'images : seule la qualite de DLSS (vraie N contre la scene)
    r = [scene(x + 0.5, y + 0.5, n - 1) for y in range(h) for x in range(w)]
    print(f'vraie {n} contre scene({n - 1}) : {psnr(vraie, r, w, h):.2f} dB ; vraie {n - 1} contre scene({n - 2}) : '
          f'{psnr(vraie_prec, [scene(x + 0.5, y + 0.5, n - 2) for y in range(h) for x in range(w)], w, h):.2f} dB')
    sys.exit(0)
_, _, generee = lire(f'{pre}-{n}-generee.ppm')
ref = lambda t: [scene(x + 0.5, y + 0.5, t) for y in range(h) for x in range(w)]
r_vraie, r_mi = ref(n - 1), ref(n - 1.5)
melange = [(a + b) / 2 for a, b in zip(vraie_prec, vraie)]
print(f'vraie {n} contre scene({n - 1}) : {psnr(vraie, r_vraie, w, h):.2f} dB')
pg, pm = psnr(generee, r_mi, w, h), psnr(melange, r_mi, w, h)
print(f'generee contre scene({n - 1.5}) : {pg:.2f} dB ; melange des vraies : {pm:.2f} dB ; vraie {n} : {psnr(vraie, r_mi, w, h):.2f} dB')
print('OK' if pg > pm + 3 else 'ECHEC : la generee ne bat pas le melange')
sys.exit(0 if pg > pm + 3 else 1)
