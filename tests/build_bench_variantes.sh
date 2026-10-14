#!/bin/sh
# Banc des variantes de pipeline compilees au premier dessin (chantier DX12, 2026-10-14).
# T fils enregistrent en parallele des dessins qui exigent chacun une variante de pipeline
# Metal neuve, comme les Job.Worker d'Unity en D3D12 (PEAK : ~1,6 s de compilation au
# dessin en 40 s de marche, sous le verrou global du device -> saccades).
#   sh tests/build_bench_variantes.sh
#   VK_DRIVER_FILES=<icd.json> DYLD_FALLBACK_LIBRARY_PATH=prefix/lib \
#     [CIDRE_COMPILE_HORS_VERROU=1] build/bench_variantes_paralleles build/variantes 8 128
# Une constante de specialisation tiree au hasard rend chaque execution neuve (pas de cache
# systeme de Metal d'un lancement a l'autre).
set -e
DIR=$(cd "$(dirname "$0")" && pwd); R=$(cd "$DIR/.." && pwd)
O="$R/build/variantes"; T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$O"
cat > "$T/v.vert" <<'GLSL'
#version 450
void main(){ vec2 p=vec2(float((gl_VertexIndex<<1)&2),float(gl_VertexIndex&2)); gl_Position=vec4(p*2.0-1.0,0.0,1.0); }
GLSL
glslangValidator -V --target-env vulkan1.3 -o "$O/v.vert.spv" "$T/v.vert" >/dev/null
i=0
while [ $i -lt 128 ]; do
   cat > "$T/f$i.frag" <<GLSL
#version 450
layout(constant_id=0) const float SEED = 0.0;
layout(location=0) out vec4 o;
void main(){ vec2 c=gl_FragCoord.xy*0.01; float x=c.x+$i.0*0.37+SEED; for(int k=0;k<$((i % 7 + 3));k++) x=sin(x)*1.01+cos(x*0.7+float($i)); o=vec4(fract(x),c.y,float($i)/128.0,1.0); }
GLSL
   glslangValidator -V --target-env vulkan1.3 -o "$O/f$i.frag.spv" "$T/f$i.frag" >/dev/null
   i=$((i + 1))
done
cc -arch arm64 -std=gnu11 -O2 -I"$R/prefix/include" "$DIR/bench_variantes_paralleles.c" -L"$R/prefix/lib" -lvulkan -lpthread -o "$R/build/bench_variantes_paralleles"
echo "construit : build/bench_variantes_paralleles (nuanceurs dans build/variantes)"
