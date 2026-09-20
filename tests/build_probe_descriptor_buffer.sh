#!/bin/sh
set -e
DIR=$(cd "$(dirname "$0")" && pwd); R=$(cd "$DIR/.." && pwd)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
cat > "$T/cs.comp" <<'GLSL'
#version 450
layout(local_size_x = 1) in;
layout(set = 0, binding = 0) buffer In  { uint v[]; } src;
layout(set = 0, binding = 1, r32ui) uniform uimageBuffer tex;
layout(set = 0, binding = 2) buffer Out { uint v[]; } dst;
void main() {
   uint i = gl_GlobalInvocationID.x;
   dst.v[i] = src.v[i] + imageLoad(tex, int(i)).x;
   imageStore(tex, int(i), uvec4(7000u + i, 0u, 0u, 0u));
}
GLSL
glslangValidator -V --target-env vulkan1.3 -o "$R/build/probe_descbuf.spv" "$T/cs.comp" >/dev/null
cc -std=c11 -O1 -I"$R/prefix/include" "$DIR/probe_descriptor_buffer.c" \
   -L"$R/prefix/lib" -lvulkan -o "$R/build/probe_descriptor_buffer"
echo "$R/build/probe_descriptor_buffer"
