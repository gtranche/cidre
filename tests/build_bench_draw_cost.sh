#!/bin/sh
set -e
DIR=$(cd "$(dirname "$0")" && pwd); R=$(cd "$DIR/.." && pwd)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
cat > "$T/v.vert" <<'GLSL'
#version 450
layout(push_constant) uniform PC { vec4 v[4]; } pc;
void main() {
   uint i = uint(gl_VertexIndex);
   vec2 p = vec2(float(i & 1u), float((i >> 1) & 1u)) * 0.02 - 0.01;
   gl_Position = vec4(p + pc.v[0].xy * 0.0, 0.0, 1.0);
}
GLSL
cat > "$T/f.frag" <<'GLSL'
#version 450
layout(set = 0, binding = 0) uniform U { vec4 c; } u;
layout(location = 0) out vec4 o;
void main() { o = vec4(1.0, 0.5, 0.0, 1.0) + u.c * 0.0; }
GLSL
glslangValidator -V --target-env vulkan1.3 -o "$T/v.spv" "$T/v.vert" >/dev/null
glslangValidator -V --target-env vulkan1.3 -o "$T/f.spv" "$T/f.frag" >/dev/null
{ xxd -i -n vs_spv "$T/v.spv"; xxd -i -n fs_spv "$T/f.spv"; } > "$T/drawcost_shaders.h"
cc -arch arm64  -std=c11 -O2 -I"$T" -I"$R/prefix/include"     "$DIR/bench_draw_cost.c" \
   -L"$R/prefix/lib"     -lvulkan -o "$R/build/bench_draw_arm64"
cc -arch x86_64 -std=c11 -O2 -I"$T" -I"$R/prefix/include" "$DIR/bench_draw_cost.c" \
   -L"$R/prefix-x64/lib" -lvulkan -o "$R/build/bench_draw_x64"
echo "$R/build/bench_draw_arm64"
echo "$R/build/bench_draw_x64"
MINGW=$R/toolchain/llvm-mingw/bin/x86_64-w64-mingw32-clang
if [ -x "$MINGW" ]; then
   "$MINGW" -std=c11 -O2 -I"$T" -I"$R/prefix/include" "$DIR/bench_draw_cost.c" \
      "$R/wine/wine10/lib/wine/x86_64-windows/libvulkan-1.a" -o "$R/build/bench_draw_pe.exe"
   echo "$R/build/bench_draw_pe.exe"
fi
