#!/bin/sh
# Construit le banc graphique pour les deux architectures, contre le prefixe correspondant.
set -e
DIR=$(cd "$(dirname "$0")" && pwd); R=$(cd "$DIR/.." && pwd)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
cat > "$T/v.vert" <<'GLSL'
#version 450
layout(push_constant) uniform PC { vec4 o; } pc;
void main(){ vec2 p=vec2(float((gl_VertexIndex<<1)&2),float(gl_VertexIndex&2));
             gl_Position=vec4(p*2.0-1.0+pc.o.xy*0.0,0.0,1.0); }
GLSL
cat > "$T/f.frag" <<'GLSL'
#version 450
layout(set=0,binding=0) uniform UB { vec4 c; } ub;
layout(location=0) out vec4 o;
void main(){ o=ub.c; }
GLSL
glslangValidator -V --target-env vulkan1.3 -o "$T/vs.spv" "$T/v.vert" >/dev/null
glslangValidator -V --target-env vulkan1.3 -o "$T/fs.spv" "$T/f.frag" >/dev/null
( xxd -i -n vs_spv "$T/vs.spv"; xxd -i -n fs_spv "$T/fs.spv" ) > "$T/gfx_shaders.h"
cc -arch arm64  -std=c11 -O2 -I"$T" -I"$R/prefix/include" "$DIR/bench_cpu_gfx.c" \
   -L"$R/prefix/lib" -lvulkan -o "$R/build/bench_gfx_arm64"
cc -arch x86_64 -std=c11 -O2 -I"$T" -I"$R/prefix/include" "$DIR/bench_cpu_gfx.c" \
   -L"$R/prefix-x64/lib" -lvulkan -o "$R/build/bench_gfx_x64"
echo ok
