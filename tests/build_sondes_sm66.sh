#!/bin/sh
# Sondes du Shader Model 6.6 (Unreal 5 en D3D12, option sm66 ; correctifs 0142 a 0144).
#   sh tests/build_sondes_sm66.sh
# Construit dans build/ :
#   sonde_sm66                ce que le GPU offre en Metal (atomiques 64 bits, denormaux,
#                             derivees en calcul) ; M1 : rien en 64 bits ; M2+ : min/max
#   sonde_derivees            derivees en calcul (CIDRE_DERIVEES_CALCUL=1) : quads et lineaire
#   sonde_atom64_vk           atomiques 64 bits sur tampon (CIDRE_ATOMIQUES_64=1, M2+)
#   sonde_img64_vk            atomiques 64 bits sur image R64_UINT (CIDRE_ATOMIQUES_64=1, M2+)
#   d3d12caps.exe             ce qu'un jeu voit en D3D12 (sh tests/sonde_d3d12caps.sh)
# Lancer une sonde Vulkan (pilote du runtime, ou un autre par son manifeste ICD) :
#   VK_DRIVER_FILES=<icd.json> DYLD_FALLBACK_LIBRARY_PATH=prefix/lib CIDRE_DERIVEES_CALCUL=1 \
#     build/sonde_derivees build/derivees_quads.spv build/derivees_lineaire.spv   (0 faux)
set -e
DIR=$(cd "$(dirname "$0")" && pwd); R=$(cd "$DIR/.." && pwd)
mkdir -p "$R/build"
clang -arch arm64 -fobjc-arc -framework Metal -framework Foundation "$DIR/sonde_sm66.m" -o "$R/build/sonde_sm66"
for s in derivees_quads derivees_lineaire atom64 img64; do
   glslangValidator -V --target-env vulkan1.3 -o "$R/build/$s.spv" "$DIR/$s.comp" >/dev/null
done
for s in sonde_derivees sonde_atom64_vk sonde_img64_vk; do
   cc -arch arm64 -std=c11 -O2 -I"$R/prefix/include" "$DIR/$s.c" -L"$R/prefix/lib" -lvulkan -o "$R/build/$s"
done
"$R/toolchain/llvm-mingw/bin/arm64ec-w64-mingw32-clang" -O2 "$DIR/d3d12caps.c" -o "$R/build/d3d12caps.exe" -ld3d12 -luuid
echo "construit : sonde_sm66, sonde_derivees, sonde_atom64_vk, sonde_img64_vk, d3d12caps.exe (+ .spv)"
