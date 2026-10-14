#!/bin/sh
# Banc des horodatages de calcul (correctif KosmicKrisp 0134, CIDRE_HORODATAGES_PRECIS).
# Le profileur de vkd3d-proton (VKD3D_TIMESTAMP_PROFILE) encadre chaque dispatch de deux
# horodatages ; sans 0134, KosmicKrisp rend la meme valeur pour les deux dans un meme
# encodeur de calcul, et tous les temps valent 0.
#   sh tests/build_bench_lecture.sh && sh tests/build_bench_horodatages.sh
#   VK_DRIVER_FILES=<icd.json> DYLD_FALLBACK_LIBRARY_PATH=prefix/lib [CIDRE_HORODATAGES_PRECIS=1] \
#     build/bench_horodatages lect build/lecture.spv 1048576 256 4
set -e
DIR=$(cd "$(dirname "$0")" && pwd); R=$(cd "$DIR/.." && pwd)
mkdir -p "$R/build"
cc -arch arm64 -std=c11 -O2 -I"$R/prefix/include" "$DIR/bench_horodatages.c" -L"$R/prefix/lib" -lvulkan -o "$R/build/bench_horodatages"
echo "construit : $R/build/bench_horodatages"
