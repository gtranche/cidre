#!/bin/sh
# Compile tests/test_geometry_shader_indirect.c avec ses shaders embarques.
set -e
DIR=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$DIR/.." && pwd)
OUT=${1:-$ROOT/build/test_geometry_shader_indirect}
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/vs.vert" <<'GLSL'
#version 450
/* Un point par rangee. Le geometry shader lit cette position, ce qui force le
 * chemin vertex -> geometrie a exister vraiment. */
void main() {
   float h = 2.0 / 128.0;
   gl_Position = vec4(0.0, -1.0 + (float(gl_VertexIndex) + 0.5) * h, 0.0, 1.0);
   gl_PointSize = 1.0;
}
GLSL
cat > "$TMP/gs.geom" <<'GLSL'
#version 450
/* Compte statique : chaque point devient la rangee ou il se trouve. */
layout(points) in;
layout(triangle_strip, max_vertices = 4) out;
layout(location = 0) out vec4 v_color;
void main() {
   float h = 2.0 / 128.0;
   float yc = gl_in[0].gl_Position.y;
   float y0 = yc - h * 0.5, y1 = yc + h * 0.5;
   v_color = vec4(0.0, 1.0, 0.0, 1.0);
   gl_Position = vec4(-1.0, y0, 0.0, 1.0); EmitVertex();
   gl_Position = vec4( 1.0, y0, 0.0, 1.0); EmitVertex();
   gl_Position = vec4(-1.0, y1, 0.0, 1.0); EmitVertex();
   gl_Position = vec4( 1.0, y1, 0.0, 1.0); EmitVertex();
   EndPrimitive();
}
GLSL
cat > "$TMP/gsdyn.geom" <<'GLSL'
#version 450
/* Compte dynamique : seules les rangees paires sont peintes, et le nombre de
 * sommets emis n'est pas connu a la compilation. poly choisit alors la forme
 * indexee dynamique, dont le tampon d'indices est alloue sur le GPU. */
layout(points) in;
layout(triangle_strip, max_vertices = 4) out;
layout(location = 0) out vec4 v_color;
void main() {
   float h = 2.0 / 128.0;
   float yc = gl_in[0].gl_Position.y;
   float y0 = yc - h * 0.5, y1 = yc + h * 0.5;
   vec2 corner[4] = vec2[4](vec2(-1.0, y0), vec2(1.0, y0),
                            vec2(-1.0, y1), vec2(1.0, y1));
   int n = ((gl_PrimitiveIDIn % 2) == 0) ? 4 : 0;
   v_color = vec4(0.0, 1.0, 0.0, 1.0);
   for (int i = 0; i < n; i++) {
      gl_Position = vec4(corner[i], 0.0, 1.0);
      EmitVertex();
   }
   EndPrimitive();
}
GLSL
cat > "$TMP/fs.frag" <<'GLSL'
#version 450
layout(location = 0) in vec4 v_color;
layout(location = 0) out vec4 o_color;
void main() { o_color = v_color; }
GLSL

: > "$TMP/gs_indirect_shaders.h"
for s in vs:vert gs:geom gsdyn:geom fs:frag; do
   n=${s%%:*}; e=${s##*:}
   glslangValidator -V --target-env vulkan1.2 -o "$TMP/$n.spv" "$TMP/$n.$e" > /dev/null
   printf 'static const uint32_t %s_spv[] = {' "$n" >> "$TMP/gs_indirect_shaders.h"
   od -An -tx4 -v "$TMP/$n.spv" | tr -s ' ' '\n' | grep . |
      sed 's/^/0x/; s/$/,/' | tr -d '\n' >> "$TMP/gs_indirect_shaders.h"
   printf '};\n' >> "$TMP/gs_indirect_shaders.h"
done

cc -std=c11 -O1 -Wall -I"$TMP" -I"$ROOT/prefix/include" \
   "$DIR/test_geometry_shader_indirect.c" \
   -L"$ROOT/prefix/lib" -lvulkan -o "$OUT"
echo "$OUT"
