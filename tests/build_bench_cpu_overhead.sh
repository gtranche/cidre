#!/bin/sh
# Construit le banc pour les deux architectures, contre le prefixe correspondant.
set -e
DIR=$(cd "$(dirname "$0")" && pwd); R=$(cd "$DIR/.." && pwd)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
cat > "$T/cs.comp" <<'GLSL'
#version 450
layout(local_size_x = 1) in;
layout(set = 0, binding = 0) buffer Out { uint v[]; };
void main() { v[0] = v[0] + 1u; }
GLSL
glslangValidator -V --target-env vulkan1.2 -o "$T/cs.spv" "$T/cs.comp" >/dev/null
xxd -i -n cs_spv "$T/cs.spv" > "$T/bench_shaders.h"
cc -arch arm64  -std=c11 -O2 -I"$T" -I"$R/prefix/include" "$DIR/bench_cpu_overhead.c" \
   -L"$R/prefix/lib" -lvulkan -o "$R/build/bench_cpu_arm64"
cc -arch x86_64 -std=c11 -O2 -I"$T" -I"$R/prefix/include" "$DIR/bench_cpu_overhead.c" \
   -L"$R/prefix-x64/lib" -lvulkan -o "$R/build/bench_cpu_x64"
echo "$R/build/bench_cpu_arm64"
echo "$R/build/bench_cpu_x64"
