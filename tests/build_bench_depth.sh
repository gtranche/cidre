#!/bin/sh
set -e
DIR=$(cd "$(dirname "$0")" && pwd); R=$(cd "$DIR/.." && pwd)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
cat > "$T/v.vert" <<'GLSL'
#version 450
layout(location = 0) out vec2 uv;
layout(push_constant) uniform PC { float z; uint n; } pc;
void main() {
   vec2 p = vec2(float((gl_VertexIndex << 1) & 2), float(gl_VertexIndex & 2));
   uv = p;
   gl_Position = vec4(p * 2.0 - 1.0, pc.z, 1.0);
}
GLSL
cat > "$T/f.frag" <<'GLSL'
#version 450
layout(location = 0) in vec2 uv_in;
layout(location = 0) out vec4 c0;
layout(set = 0, binding = 0) uniform sampler2D tex;
layout(push_constant) uniform PC { float z; uint n; } pc;
void main() {
   vec4 acc = vec4(0.0);
   vec2 uv = uv_in;
   for (uint i = 0u; i < pc.n; ++i) { acc += texture(tex, uv); uv += vec2(0.00137, 0.00219); }
   c0 = acc * (1.0 / float(pc.n));
}
GLSL
glslangValidator -V --target-env vulkan1.3 -o "$R/build/bench_depth_vs.spv" "$T/v.vert" >/dev/null
glslangValidator -V --target-env vulkan1.3 -o "$R/build/bench_depth_fs.spv" "$T/f.frag" >/dev/null
cc -arch arm64 -std=c11 -O2 -I"$R/prefix/include" "$DIR/bench_depth_vulkan.c" \
   -L"$R/prefix/lib" -lvulkan -o "$R/build/bench_depth_vulkan"
clang -arch arm64 -fobjc-arc -O2 -framework Foundation -framework Metal \
   "$DIR/bench_depth_metal.m" -o "$R/build/bench_depth_metal"
echo "$R/build/bench_depth_vulkan"; echo "$R/build/bench_depth_metal"
