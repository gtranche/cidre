#!/bin/sh
set -e
DIR=$(cd "$(dirname "$0")" && pwd); R=$(cd "$DIR/.." && pwd)
OUT=${1:-$R/build/test_polygon_mode}
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
cat > "$T/vs.vert" <<'GLSL'
#version 450
void main() {
   vec2 p[3] = vec2[3](vec2(-0.9, 0.9), vec2(0.9, 0.9), vec2(0.0, -0.9));
   gl_Position = vec4(p[gl_VertexIndex], 0.0, 1.0);
}
GLSL
cat > "$T/fs.frag" <<'GLSL'
#version 450
layout(location = 0) out vec4 o;
void main() { o = vec4(1.0, 1.0, 1.0, 1.0); }
GLSL
: > "$T/polygon_shaders.h"
for s in vs:vert fs:frag; do
   n=${s%%:*}; e=${s##*:}
   glslangValidator -V --target-env vulkan1.2 -o "$T/$n.spv" "$T/$n.$e" >/dev/null
   xxd -i -n "${n}_spv" "$T/$n.spv" >> "$T/polygon_shaders.h"
done
cc -std=c11 -O1 -I"$T" -I"$R/prefix/include" "$DIR/test_polygon_mode.c" \
   -L"$R/prefix/lib" -lvulkan -o "$OUT"
echo "$OUT"
