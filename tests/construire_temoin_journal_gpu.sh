#!/bin/sh
# Construit le temoin natif du journal GPU : extrait le bloc « cidre-journal-gpu »
# de winemetal_unix.c (le meme code que celui du jeu) et le compile avec
# temoin_journal_gpu.m, sans ARC comme winemetal.so. Ne lance rien.
set -e
R=$(cd "$(dirname "$0")/.." && pwd)
T=$R/tests
SRC=${DXMT_SRC:-$R/src/dxmt}/src/winemetal/unix/winemetal_unix.c
awk '/cidre-journal-gpu: debut/,/cidre-journal-gpu: fin/' "$SRC" >"$T/journal_gpu_extrait.inc"
grep -q "cidre_jgpu_tampon" "$T/journal_gpu_extrait.inc" || { echo "ECHEC : bloc introuvable dans $SRC"; exit 1; }
xcrun clang -arch arm64 -O1 -Wall -ObjC -fblocks "$T/temoin_journal_gpu.m" -I"$T" -o "${SORTIE:-$T/temoin_journal_gpu}" \
   -framework Foundation -framework Metal -framework QuartzCore
file "${SORTIE:-$T/temoin_journal_gpu}"
