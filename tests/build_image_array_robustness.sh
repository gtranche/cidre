#!/bin/sh
set -e
DIR=$(cd "$(dirname "$0")" && pwd); R=$(cd "$DIR/.." && pwd)
OUT=${1:-$R/build/test_image_array_robustness}
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
cat > "$T/cs.comp" <<'GLSL'
#version 450
layout(local_size_x = 1) in;
layout(set = 0, binding = 0) uniform sampler2DArray tex;
layout(set = 0, binding = 2) uniform sampler2DArray tex_mip1;
layout(set = 0, binding = 1) buffer Out { vec4 v[6]; } o;
void main() {
   o.v[0] = textureLod(tex, vec3(0.5, 0.5, 0.0), 0.0);
   o.v[1] = textureLod(tex, vec3(0.5, 0.5, 1.0), 0.0);
   o.v[2] = textureLod(tex, vec3(0.5, 0.5, 0.0), 1.0);
   o.v[3] = texelFetch(tex, ivec3(0, 0, 0), 1);
   o.v[4] = textureLod(tex_mip1, vec3(0.5, 0.5, 0.0), 0.0);
   o.v[5] = texelFetch(tex_mip1, ivec3(0, 0, 0), 0);
}
GLSL
glslangValidator -V --target-env vulkan1.2 -o "$T/cs.spv" "$T/cs.comp" >/dev/null
xxd -i -n cs_spv "$T/cs.spv" > "$T/arrayrob_shaders.h"
cc -std=c11 -O1 -I"$T" -I"$R/prefix/include" "$DIR/test_image_array_robustness.c" \
   -L"$R/prefix/lib" -lvulkan -o "$OUT"
echo "$OUT"
