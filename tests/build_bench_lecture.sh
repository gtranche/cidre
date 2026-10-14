#!/bin/sh
# Banc des lectures memoire des nuanceurs de calcul (correctif KosmicKrisp 0132).
# Sur macOS <= 26, le contournement KK 6 rend tout acces memoire global « coherent »
# (non cache) a cause d'un bogue de Metal : une lecture apres une ecriture a la meme
# adresse, dans le meme fil, n'est pas ordonnee. 0132 rend leur cache aux lectures
# qui ne peuvent pas tomber dans ce cas (acces en lecture seule, ou nuanceur sans
# aucune ecriture memoire). Little Nightmares Enhanced Edition en D3D12 : 73 % du
# temps GPU en nuanceurs de calcul (2026-10-14).
#   sh tests/build_bench_lecture.sh
#   VK_DRIVER_FILES=<icd.json> DYLD_FALLBACK_LIBRARY_PATH=prefix/lib [CIDRE_LECTURES_CACHEES=1] \
#     build/bench_lecture lect build/lecture.spv 1048576 512 7     (vitesse)
#   ... build/bench_lecture rw build/rw.spv 1000                   (le motif du bogue : doit rester JUSTE)
set -e
DIR=$(cd "$(dirname "$0")" && pwd); R=$(cd "$DIR/.." && pwd)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$R/build"
cat > "$T/lecture.comp" <<'GLSL'
#version 450
layout(local_size_x=64) in;
layout(std430, set=0, binding=0) readonly buffer In { uint d[]; } src;
layout(std430, set=0, binding=1) writeonly buffer Out { uint o[]; } dst;
layout(push_constant) uniform PC { uint mask; uint iters; } pc;
void main(){ uint g=gl_GlobalInvocationID.x; uint acc=g;
  for(uint i=0u;i<pc.iters;++i){ acc = acc*1664525u + src.d[(g*7u + i*131u + (acc&15u)) & pc.mask]; }
  dst.o[g]=acc; }
GLSL
cat > "$T/rw.comp" <<'GLSL'
#version 450
layout(local_size_x=1) in;
layout(std430, set=0, binding=0) buffer In { uint d[]; } src;
layout(std430, set=0, binding=1) buffer Out { uint o[]; } dst;
layout(push_constant) uniform PC { uint mask; uint iters; } pc;
void main(){ for(uint i=0u;i<pc.iters;++i){ uint v=src.d[0]; src.d[0]=v+1u; } dst.o[0]=src.d[0]; }
GLSL
glslangValidator -V --target-env vulkan1.3 -o "$R/build/lecture.spv" "$T/lecture.comp" >/dev/null
glslangValidator -V --target-env vulkan1.3 -o "$R/build/rw.spv" "$T/rw.comp" >/dev/null
cc -arch arm64 -std=c11 -O2 -I"$R/prefix/include" "$DIR/bench_lecture.c" -L"$R/prefix/lib" -lvulkan -o "$R/build/bench_lecture"
echo "construit : build/bench_lecture (nuanceurs build/lecture.spv, build/rw.spv)"
