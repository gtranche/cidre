#!/bin/sh
set -e
DIR=$(cd "$(dirname "$0")" && pwd); R=$(cd "$DIR/.." && pwd)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
cat > "$T/c.comp" <<'GLSL'
#version 450
layout(local_size_x = 64) in;
layout(set = 0, binding = 0) buffer B { uint n; uint pad[3]; float o[]; } b;
void main() {
   uint tid = gl_GlobalInvocationID.x;
   float acc = float(tid) * 1e-6;
   float a = 1.0000001, c = 1e-7;
   for (uint i = 0u; i < b.n; ++i)
      acc = fma(acc, a, c);
   b.o[tid] = acc;
}
GLSL
glslangValidator -V --target-env vulkan1.3 -o "$R/build/bench_alu.spv" "$T/c.comp" >/dev/null
cc -arch arm64 -std=c11 -O2 -I"$R/prefix/include" "$DIR/bench_alu_vulkan.c" \
   -L"$R/prefix/lib" -lvulkan -o "$R/build/bench_alu_vulkan"
xcrun clang -arch arm64 -fobjc-arc -O2 -o "$R/build/bench_alu_metal" "$DIR/bench_alu_metal.m" \
   -framework Foundation -framework Metal
echo "$R/build/bench_alu_vulkan"
