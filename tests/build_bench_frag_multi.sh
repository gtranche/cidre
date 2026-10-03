#!/bin/sh
set -e
DIR=$(cd "$(dirname "$0")" && pwd); R=$(cd "$DIR/.." && pwd)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$R/build"
# VS plein ecran (reutilise si present)
[ -f "$R/build/bench_frag_vs.spv" ] || { cat > "$T/v.vert" <<'GLSL'
#version 450
layout(location=0) out vec2 uv;
void main(){ vec2 p=vec2(float((gl_VertexIndex<<1)&2),float(gl_VertexIndex&2)); uv=p; gl_Position=vec4(p*2.0-1.0,0.0,1.0);}
GLSL
glslangValidator -V --target-env vulkan1.3 -o "$R/build/bench_frag_vs.spv" "$T/v.vert" >/dev/null; }
for N in 1 8 16 32 64; do
   {
     echo "#version 450"
     echo "layout(location=0) in vec2 uv_in;"
     echo "layout(location=0) out vec4 c0;"
     i=0; while [ $i -lt $N ]; do echo "layout(set=0,binding=$i) uniform sampler2D t$i;"; i=$((i+1)); done
     echo "layout(push_constant) uniform PC { uint n; } pc;"
     echo "void main(){ vec4 a=vec4(0.0); vec2 uv=uv_in;"
     i=0; while [ $i -lt $N ]; do echo "  a+=texture(t$i,uv); uv+=vec2(0.00137,0.00219);"; i=$((i+1)); done
     echo "  c0=a*(1.0/float($N)); }"
   } > "$T/f$N.frag"
   glslangValidator -V --target-env vulkan1.3 -o "$R/build/bench_multi_fs$N.spv" "$T/f$N.frag" >/dev/null
   cc -arch arm64 -std=c11 -O2 -DNTEX=${N}u -I"$R/prefix/include" "$DIR/bench_frag_multi.c" \
      -L"$R/prefix/lib" -lvulkan -o "$R/build/bench_multi_$N"
   echo "$R/build/bench_multi_$N (NTEX=$N)"
done
