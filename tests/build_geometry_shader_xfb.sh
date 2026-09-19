#!/bin/sh
# Compile tests/test_geometry_shader_xfb.c avec ses shaders embarques.
set -e
DIR=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$DIR/.." && pwd)
OUT=${1:-$ROOT/build/test_geometry_shader_xfb}
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/vs.vert" <<'GLSL'
#version 450
void main() { gl_Position = vec4(0.0, 0.0, 0.0, 1.0); gl_PointSize = 1.0; }
GLSL
cat > "$TMP/gs.geom" <<'GLSL'
#version 450
layout(points) in;
layout(triangle_strip, max_vertices = 3) out;
layout(xfb_buffer = 0, xfb_stride = 16, xfb_offset = 0, location = 0) out vec4 v_cap;
void main() {
   for (int i = 0; i < 3; i++) {
      v_cap = vec4(float(gl_PrimitiveIDIn), float(i), 3.0, 4.0);
      gl_Position = vec4(0.0, 0.0, 0.0, 1.0);
      EmitVertex();
   }
   EndPrimitive();
}
GLSL
cat > "$TMP/gsms.geom" <<'GLSL'
#version 450
layout(points) in;
layout(points, max_vertices = 2) out;
layout(stream = 0, xfb_buffer = 0, xfb_stride = 16, xfb_offset = 0, location = 0) out vec4 v_a;
layout(stream = 1, xfb_buffer = 1, xfb_stride = 16, xfb_offset = 0, location = 1) out vec4 v_b;
void main() {
   v_a = vec4(float(gl_PrimitiveIDIn), 1.0, 2.0, 3.0);
   gl_Position = vec4(0.0, 0.0, 0.0, 1.0);
   EmitStreamVertex(0);
   EndStreamPrimitive(0);
   v_b = vec4(float(gl_PrimitiveIDIn), 5.0, 6.0, 7.0);
   gl_Position = vec4(0.0, 0.0, 0.0, 1.0);
   EmitStreamVertex(1);
   EndStreamPrimitive(1);
}
GLSL
cat > "$TMP/fs.frag" <<'GLSL'
#version 450
layout(location = 0) in vec4 v_cap;
layout(location = 0) out vec4 o_color;
void main() { o_color = v_cap; }
GLSL

: > "$TMP/gs_xfb_shaders.h"
for s in vs:vert gs:geom gsms:geom fs:frag; do
   n=${s%%:*}; e=${s##*:}
   glslangValidator -V --target-env vulkan1.2 -o "$TMP/$n.spv" "$TMP/$n.$e" > /dev/null
   xxd -i -n "${n}_spv" "$TMP/$n.spv" >> "$TMP/gs_xfb_shaders.h"
done

cc -std=c11 -O1 -Wall -I"$TMP" -I"$ROOT/prefix/include" \
   "$DIR/test_geometry_shader_xfb.c" \
   -L"$ROOT/prefix/lib" -lvulkan -lm -o "$OUT"
echo "$OUT"
