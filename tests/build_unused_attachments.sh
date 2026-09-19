#!/bin/sh
set -e
DIR=$(cd "$(dirname "$0")" && pwd); R=$(cd "$DIR/.." && pwd)
OUT=${1:-$R/build/test_unused_attachments}
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
cat > "$T/a.vert" <<'GLSL'
#version 450
void main() {
   vec2 p = vec2((gl_VertexIndex << 1) & 2, gl_VertexIndex & 2);
   gl_Position = vec4(p * 2.0 - 1.0, 0.0, 1.0);
}
GLSL
cat > "$T/a.frag" <<'GLSL'
#version 450
layout(location = 0) out vec4 o0;
layout(location = 1) out vec4 o1;
layout(location = 2) out vec4 o2;
layout(location = 3) out vec4 o3;
void main() {
   o0 = vec4(1.0);
   o1 = vec4(2.0);
   o2 = vec4(3.0);
   o3 = vec4(4.0);
}
GLSL
glslangValidator -V --target-env vulkan1.3 -o "$T/vs.spv" "$T/a.vert" >/dev/null
glslangValidator -V --target-env vulkan1.3 -o "$T/fs.spv" "$T/a.frag" >/dev/null
{ xxd -i -n vs_spv "$T/vs.spv"; xxd -i -n fs_spv "$T/fs.spv"; } > "$T/unusedatt_shaders.h"
cc -std=c11 -O1 -I"$T" -I"$R/prefix/include" "$DIR/test_unused_attachments.c" \
   -L"$R/prefix/lib" -lvulkan -o "$OUT"
echo "$OUT"
