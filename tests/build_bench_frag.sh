#!/bin/sh
set -e
DIR=$(cd "$(dirname "$0")" && pwd); R=$(cd "$DIR/.." && pwd)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
cat > "$T/v.vert" <<'GLSL'
#version 450
layout(location = 0) out vec2 uv;
void main() {
   vec2 p = vec2(float((gl_VertexIndex << 1) & 2), float(gl_VertexIndex & 2));
   uv = p;
   gl_Position = vec4(p * 2.0 - 1.0, 0.0, 1.0);
}
GLSL
mk_fs() {
cat > "$T/f.frag" <<GLSL
#version 450
layout(location = 0) in vec2 uv_in;
layout(location = 0) out vec4 c0;
$( [ "$1" -ge 2 ] && echo "layout(location = 1) out vec4 c1;" )
layout(set = 0, binding = 0) uniform sampler2D tex;
layout(push_constant) uniform PC { uint n; } pc;
void main() {
   vec4 acc = vec4(0.0);
   vec2 uv = uv_in;
   for (uint i = 0u; i < pc.n; ++i) {
      acc += texture(tex, uv);
      uv += vec2(0.00137, 0.00219);
   }
   c0 = acc * (1.0 / float(pc.n));
$( [ "$1" -ge 2 ] && echo "   c1 = c0 * 0.5;" )
}
GLSL
glslangValidator -V --target-env vulkan1.3 -o "$R/build/bench_frag_fs$1.spv" "$T/f.frag" >/dev/null
}
glslangValidator -V --target-env vulkan1.3 -o "$R/build/bench_frag_vs.spv" "$T/v.vert" >/dev/null
mk_fs 1; mk_fs 2
cc -arch arm64 -std=c11 -O2 -I"$R/prefix/include" "$DIR/bench_frag_vulkan.c" \
   -L"$R/prefix/lib" -lvulkan -o "$R/build/bench_frag_vulkan"
cc -arch arm64 -std=c11 -O2 -I"$R/prefix/include" "$DIR/bench_pass_vulkan.c" \
   -L"$R/prefix/lib" -lvulkan -o "$R/build/bench_pass_vulkan"
echo "$R/build/bench_frag_vulkan"
echo "$R/build/bench_pass_vulkan"
