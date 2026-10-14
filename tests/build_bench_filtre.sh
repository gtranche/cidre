#!/bin/sh
# Filtres de textures en D3D12 (correctifs KosmicKrisp 0135 et 0136, lanceur sans
# custom_border). Little Nightmares Enhanced Edition : 91 % du calcul dans des filtres
# de 32 lectures de texture, 3 ms par dispatch (2026-10-14). Le MSL de KosmicKrisp
# entoure chaque lecture de branchements (descripteur nul, bord emule, min/max a zero
# signe) qui empechent Metal de lancer les lectures en parallele.
#   sh tests/build_bench_filtre.sh
#   build/banc_filtre_textures build/filtre_<zero><bord><nul>.metal 1920 1080 15 1
#     111 = KosmicKrisp avant (3,70 ms), 101 = sans bord (2,49), 201 = + 0135 (2,05),
#     200 = + 0136 (0,60), 000 = nuanceur nu (0,60) ; M1 Max, medianes.
#   VK_DRIVER_FILES=<icd.json> DYLD_FALLBACK_LIBRARY_PATH=prefix/lib \
#     [CIDRE_MINMAX_ZERO_ENTIER=1] [CIDRE_TEXTURES_NULLES_SANS_BRANCHE=1] \
#     build/sonde_kk_nul_zero build/sonde_kk_nul_zero.spv      (doit finir par 0 faux)
set -e
DIR=$(cd "$(dirname "$0")" && pwd); R=$(cd "$DIR/.." && pwd)
mkdir -p "$R/build"
clang -arch arm64 -fobjc-arc -framework Metal -framework Foundation "$DIR/banc_filtre_textures.m" -o "$R/build/banc_filtre_textures"
for v in 111 101 201 200 000; do
   python3 -I "$DIR/gen_filtre_textures.py" $(echo $v | sed 's/./& /g') > "$R/build/filtre_$v.metal"
done
spirv-as --target-env vulkan1.3 "$DIR/sonde_kk_nul_zero.spvasm" -o "$R/build/sonde_kk_nul_zero.spv"
cc -arch arm64 -std=c11 -O2 -I"$R/prefix/include" "$DIR/sonde_kk_nul_zero.c" -L"$R/prefix/lib" -lvulkan -o "$R/build/sonde_kk_nul_zero"
echo "construit : banc_filtre_textures, filtre_*.metal, sonde_kk_nul_zero"
