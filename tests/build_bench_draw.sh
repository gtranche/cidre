#!/bin/sh
set -e
DIR=$(cd "$(dirname "$0")" && pwd); R=$(cd "$DIR/.." && pwd)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
cat > "$T/v.vert" <<'GLSL'
#version 450
void main() {
   uint tri = uint(gl_VertexIndex) / 3u;
   uint corner = uint(gl_VertexIndex) % 3u;
   float a = float(tri & 63u) * 0.001;
   vec2 base = vec2(-0.9 + a, -0.9 + a);
   vec2 off = corner == 0u ? vec2(0.0, 0.0)
            : (corner == 1u ? vec2(0.004, 0.0) : vec2(0.0, 0.004));
   gl_Position = vec4(base + off, 0.0, 1.0);
}
GLSL
cat > "$T/f.frag" <<'GLSL'
#version 450
layout(location = 0) out vec4 c;
void main() { c = vec4(1.0); }
GLSL
glslangValidator -V --target-env vulkan1.3 -o "$R/build/bench_draw_vs.spv" "$T/v.vert" >/dev/null
glslangValidator -V --target-env vulkan1.3 -o "$R/build/bench_draw_fs.spv" "$T/f.frag" >/dev/null
cc -arch arm64 -std=c11 -O2 -I"$R/prefix/include" "$DIR/bench_draw_vulkan.c" \
   -L"$R/prefix/lib" -lvulkan -o "$R/build/bench_draw_vulkan"
clang -arch arm64 -fobjc-arc -O2 -framework Foundation -framework Metal \
   "$DIR/bench_draw_metal.m" -o "$R/build/bench_draw_metal"
echo "$R/build/bench_draw_vulkan"
echo "$R/build/bench_draw_metal"
