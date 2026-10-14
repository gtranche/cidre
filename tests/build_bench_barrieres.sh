#!/bin/sh
# Bancs des barrieres de cloture de KosmicKrisp (chantier DX12, 2026-10-14).
#   bench_barriere_vertex : JUSTESSE. Une passe rend T au fragment, la suivante lit
#     T au SOMMET ; une faute = C[k] != k. Mesure, sans jeu, si un mode de
#     CIDRE_NARROW_BARRIERS laisse partir le sommet avant la fin du fragment.
#   bench_barriere_chaine : RECOUVREMENT. N passes ping-pong (sommet lourd,
#     fragment lourd qui lit la passe precedente), temps mur median.
# Construire :  sh tests/build_bench_barrieres.sh
# Lancer (pilote du runtime, ou un autre par son manifeste ICD) :
#   VK_DRIVER_FILES=<icd.json> BANC_SPV=build DYLD_FALLBACK_LIBRARY_PATH=prefix/lib \
#     CIDRE_NARROW_BARRIERS=sur build/bench_barriere_vertex vf 200 64 2048 3
#   ... build/bench_barriere_chaine f 40 30000 32 32 7
# Piege : DYLD_LIBRARY_PATH=prefix/lib charge le pilote INSTALLE meme si le
# manifeste designe un autre fichier (dyld cherche d'abord par nom de fichier) ;
# passer par DYLD_FALLBACK_LIBRARY_PATH.
set -e
DIR=$(cd "$(dirname "$0")" && pwd); R=$(cd "$DIR/.." && pwd)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$R/build"
cat > "$T/bv_plein.vert" <<'GLSL'
#version 450
void main(){ vec2 p=vec2(float((gl_VertexIndex<<1)&2),float(gl_VertexIndex&2)); gl_Position=vec4(p*2.0-1.0,0.0,1.0); }
GLSL
cat > "$T/bv_lourd.frag" <<'GLSL'
#version 450
layout(location=0) out float o;
layout(push_constant) uniform PC { uint k; uint iter; uint K; } pc;
void main(){ float x=gl_FragCoord.x*0.001+gl_FragCoord.y*0.0007;
  for(uint i=0u;i<pc.iter;++i) x=sin(x)*1.0001+cos(x*0.999);
  o=float(pc.k)+(x>1e30?1.0:0.0); }
GLSL
cat > "$T/bv_lit.vert" <<'GLSL'
#version 450
layout(set=0,binding=0) uniform sampler2D t;
layout(push_constant) uniform PC { uint k; uint iter; uint K; } pc;
layout(location=0) flat out float v;
void main(){ v=textureLod(t,vec2(0.5,0.5),0.0).r;
  gl_PointSize=1.0; gl_Position=vec4((float(pc.k)-0.5)/float(pc.K)*2.0-1.0,0.0,0.0,1.0); }
GLSL
cat > "$T/bv_ecrit.frag" <<'GLSL'
#version 450
layout(location=0) flat in float v;
layout(location=0) out float o;
void main(){ o=v; }
GLSL
cat > "$T/ch_lourd.vert" <<'GLSL'
#version 450
layout(push_constant) uniform PC { uint k; uint itv; uint itf; } pc;
void main(){
  float x=float(gl_VertexIndex)*0.001;
  for(uint i=0u;i<pc.itv;++i) x=sin(x)*1.0001+cos(x*0.999);
  vec2 p=vec2(float((gl_VertexIndex<<1)&2),float(gl_VertexIndex&2));
  if(gl_VertexIndex>=3) p=vec2(0.0);
  gl_Position=vec4(p*2.0-1.0+(x>1e30?1.0:0.0),0.0,1.0); }
GLSL
cat > "$T/ch_lourd.frag" <<'GLSL'
#version 450
layout(set=0,binding=0) uniform sampler2D prev;
layout(location=0) out vec4 o;
layout(push_constant) uniform PC { uint k; uint itv; uint itf; } pc;
void main(){ vec2 uv=gl_FragCoord.xy/vec2(textureSize(prev,0));
  float x=texture(prev,uv).r+gl_FragCoord.x*0.001;
  for(uint i=0u;i<pc.itf;++i) x=sin(x)*1.0001+cos(x*0.999);
  o=vec4(fract(x),float(pc.k),0.0,1.0); }
GLSL
for s in bv_plein.vert bv_lourd.frag bv_lit.vert bv_ecrit.frag ch_lourd.vert ch_lourd.frag; do
   glslangValidator -V --target-env vulkan1.3 -o "$R/build/$s.spv" "$T/$s" >/dev/null
done
for b in bench_barriere_vertex bench_barriere_chaine; do
   cc -arch arm64 -std=c11 -O2 -I"$R/prefix/include" "$DIR/$b.c" -L"$R/prefix/lib" -lvulkan -o "$R/build/$b"
done
echo "construits : build/bench_barriere_vertex build/bench_barriere_chaine (+ nuanceurs build/*.spv)"
