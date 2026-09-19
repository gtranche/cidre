#!/bin/sh
set -e
DIR=$(cd "$(dirname "$0")" && pwd); R=$(cd "$DIR/.." && pwd)
OUT=${1:-$R/build/test_view_mip_range}
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
cat > "$T/cs.comp" <<'GLSL'
#version 450
layout(local_size_x = 8) in;
layout(set = 0, binding = 0) uniform sampler2DArray v0;
layout(set = 0, binding = 1) uniform sampler2DArray v1;
layout(set = 0, binding = 2) buffer Out { vec4 o[18]; };
void main() {
   uint lid = gl_LocalInvocationIndex;
   o[lid] = texelFetch(v0, ivec3(0, 0, 0), int(lid));
   if (lid == 0u) {
      o[8]  = textureLod(v0, vec3(0.25, 0.25, 0.0), 0.0);
      o[9]  = textureLod(v0, vec3(0.25, 0.25, 0.0), 1.0);
      o[10] = textureLod(v0, vec3(0.25, 0.25, 0.0), 2.0);
      o[11] = textureLod(v0, vec3(0.25, 0.25, 0.0), 3.0);
      o[12] = textureLod(v1, vec3(0.25, 0.25, 0.0), 0.0);
      o[13] = textureLod(v1, vec3(0.25, 0.25, 0.0), 1.0);
      o[14] = texelFetch(v1, ivec3(0, 0, 0), 0);
      o[15] = texelFetch(v1, ivec3(0, 0, 0), 1);
      o[16] = textureLod(v0, vec3(0.25, 0.25, 0.0), 0.5);
      o[17] = textureLod(v0, vec3(0.25, 0.25, 0.0), 1.5);
   }
}
GLSL
glslangValidator -V --target-env vulkan1.2 -o "$T/cs.spv" "$T/cs.comp" >/dev/null
xxd -i -n cs_spv "$T/cs.spv" > "$T/viewmip_shaders.h"
cc -std=c11 -O1 -I"$T" -I"$R/prefix/include" "$DIR/test_view_mip_range.c" \
   -L"$R/prefix/lib" -lvulkan -o "$OUT"
echo "$OUT"
