#!/bin/sh
set -e
DIR=$(cd "$(dirname "$0")" && pwd); R=$(cd "$DIR/.." && pwd)
OUT=${1:-$R/build/bench_strip_unroll}
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
cat > "$T/v.vert" <<'GLSL'
#version 450
void main() {
   uint i = uint(gl_VertexIndex);
   float a = float(i) * 0.37;
   gl_Position = vec4(0.05 * cos(a), 0.05 * sin(a), 0.0, 1.0);
}
GLSL
cat > "$T/f.frag" <<'GLSL'
#version 450
layout(location = 0) out vec4 o;
void main() { o = vec4(1.0, 0.5, 0.0, 1.0); }
GLSL
glslangValidator -V --target-env vulkan1.3 -o "$T/v.spv" "$T/v.vert" >/dev/null
glslangValidator -V --target-env vulkan1.3 -o "$T/f.spv" "$T/f.frag" >/dev/null
{ xxd -i -n vs_spv "$T/v.spv"; xxd -i -n fs_spv "$T/f.spv"; } > "$T/strip_shaders.h"
cc -std=c11 -O2 -I"$T" -I"$R/prefix/include" "$DIR/bench_strip_unroll.c" \
   -L"$R/prefix/lib" -lvulkan -o "$OUT"
echo "$OUT"
