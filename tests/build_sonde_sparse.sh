#!/bin/sh
# Sonde du sparse de KosmicKrisp (drapeau fl12) : image sparse cible de rendu et
# inscriptible, une tuile liee, effacement, relecture (tuile liee = couleur, tuile
# libre = 0). Avant le correctif 0127, Metal plantait a la creation de l'image
# (« Invalid Storage Mode 0 for Placement Sparse Texture », PEAK en D3D12).
#   sh tests/build_sonde_sparse.sh
#   MESA_KK_EXPERIMENTAL=custom_border,image_view_min_lod,fl12 \
#     DYLD_FALLBACK_LIBRARY_PATH=prefix/lib build/sonde_sparse_vk
set -e
DIR=$(cd "$(dirname "$0")" && pwd); R=$(cd "$DIR/.." && pwd)
mkdir -p "$R/build"
cc -arch arm64 -std=c11 -O2 -I"$R/prefix/include" "$DIR/sonde_sparse_vk.c" -L"$R/prefix/lib" -lvulkan -o "$R/build/sonde_sparse_vk"
echo "construit : build/sonde_sparse_vk"
