#!/bin/sh
# Construit la sonde native de MetalFX temporel avec le bloc « cidre-journal-gpu » de
# winemetal_unix.c (meme garde que le jeu), sans ARC comme winemetal.so. Ne lance rien.
set -e
T=$(cd "$(dirname "$0")" && pwd)
SRC=${WINEMETAL_UNIX:-$T/../src/dxmt/src/winemetal/unix/winemetal_unix.c} # depot Cidre
[ -f "$SRC" ] || SRC=$T/../src/winemetal/unix/winemetal_unix.c                 # arbre DXMT
awk '/cidre-journal-gpu: debut/,/cidre-journal-gpu: fin/' "$SRC" >"$T/journal_gpu_extrait.inc"
grep -q "cidre_jgpu_tampon" "$T/journal_gpu_extrait.inc" || { echo "ECHEC : bloc introuvable dans $SRC"; exit 1; }
xcrun clang -arch arm64 -O1 -Wall -ObjC -fblocks "$T/sonde_metalfx_temporel.m" -I"$T" -o "${SORTIE:-$T/sonde_metalfx_temporel}" \
   -framework Foundation -framework Metal -framework MetalFX -framework QuartzCore
file "${SORTIE:-$T/sonde_metalfx_temporel}"
