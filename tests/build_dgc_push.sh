#!/bin/sh
set -e
DIR=$(cd "$(dirname "$0")" && pwd); R=$(cd "$DIR/.." && pwd)
OUT=${1:-$R/build/test_dgc_push}
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
cat > "$T/cs.comp" <<'GLSL'
#version 450
layout(local_size_x = 1) in;
layout(push_constant) uniform PC { layout(offset = PCOFF) uint slot; uint value; } pc;
layout(set = 0, binding = 0) buffer Out { uint v[]; } o;
void main() { o.v[pc.slot] = pc.value; }
GLSL
sed -i '' "s/PCOFF/${PCOFF:-0}/" "$T/cs.comp"
glslangValidator -V --target-env vulkan1.3 -o "$T/cs.spv" "$T/cs.comp" >/dev/null
xxd -i -n cs_spv "$T/cs.spv" > "$T/dgc_shaders.h"
cat > "$T/m.comp" <<'GLSL'
#version 450
#extension GL_EXT_shader_explicit_arithmetic_types_int64 : require
layout(local_size_x = 1) in;
layout(push_constant) uniform PC {
   layout(offset = PCOFF) uint64_t slot; uint64_t b; uint64_t c;
} pc;
layout(set = 0, binding = 0) buffer Out { uint v[]; } o;
void main() {
   uint s = uint(pc.slot);
   o.v[s] = uint(pc.b);
   o.v[s + 8u] = uint(pc.c);
}
GLSL
sed -i '' "s/PCOFF/${PCOFF:-0}/" "$T/m.comp"
glslangValidator -V --target-env vulkan1.3 -o "$T/m.spv" "$T/m.comp" >/dev/null
xxd -i -n m_spv "$T/m.spv" > "$T/dgc_m.h"
cat > "$T/vs.vert" <<'GLSL'
#version 450
layout(push_constant) uniform PC { layout(offset = PCOFF) uint slot; uint value; } pc;
layout(set = 0, binding = 0) buffer Out { uint v[]; } o;
void main() { o.v[pc.slot] = pc.value; gl_Position = vec4(0.0); gl_PointSize = 1.0; }
GLSL
sed -i '' "s/PCOFF/${PCOFF:-0}/" "$T/vs.vert"
glslangValidator -V --target-env vulkan1.3 -o "$T/vs.spv" "$T/vs.vert" >/dev/null
xxd -i -n vs_spv "$T/vs.spv" > "$T/dgc_vs.h"
cc -std=c11 -O1 -I"$T" -I"$R/prefix/include" "$DIR/test_dgc_push.c" \
   -L"$R/prefix/lib" -lvulkan -o "$OUT"
echo "$OUT"
