#!/bin/sh
# Temoin hors jeu de la cle des caches de nuanceurs de KosmicKrisp (0208).
#
#   sh tests/temoin_cle_cache_kk.sh <arbre mesa avec 0208> <dossier de build>
#
# Reconstruit le pilote quatre fois dans un arbre DE TRAVAIL A PART (jamais
# src/mesa ni le runtime installe : le script modifie des sources puis les
# remet) :
#   A : l'arbre tel quel ;
#   B : A + un changement hors code (kk_wsi.c, presentation) ;
#   C : A + un changement du MSL produit (nir_to_msl.c : une ligne de plus en
#       tete de chaque nuanceur) ;
#   D : A + KK_CODEGEN_VERSION augmentee (le levier manuel).
# Pour chacun : la cle (pipelineCacheUUID), le marqueur de la reserve d'AIR
# (precompil_kk.sh kk), puis la sonde sonde_cle_cache_kk avec le
# VkPipelineCache ecrit par A, la reserve d'AIR et l'archive MTL4 de A.
# Attendu : B garde la cle, reprend les 5 pipelines du cache Vulkan, 100 % des
# bibliotheques depuis la reserve d'AIR de A et les pipelines depuis l'archive ;
# C et D changent de cle et le cache Vulkan de A est ecarte ; CIDRE_CLE_CACHE
# (secours) change la cle, CIDRE_CLE_CACHE=build redonne une cle par build.
# Lourd (4 constructions incrementales) : hors jeu, sous nice.
set -eu
R=$(cd "$(dirname "$0")/.." && pwd)
# chargeur et en-tetes Vulkan (prefix/ du checkout, meme quand le script tourne
# depuis une copie des tests)
P=${TEMOIN_PREFIX:-$R/prefix}
[ -d "$P/include/vulkan" ] || P=$HOME/Dev/proton-ouvert/prefix
S=$(cd "$1" && pwd); B=$(cd "$2" && pwd)
case "$S" in "$HOME/Dev/proton-ouvert"*) echo "refuse : $S est dans le checkout partage" >&2; exit 1 ;; esac
grep -q KK_CODEGEN_VERSION "$S/src/kosmickrisp/vulkan/kk_physical_device.c" || { echo "$S n'a pas 0208" >&2; exit 1; }
T=${TEMOIN_DIR:-$(mktemp -d "${TMPDIR:-/tmp}/temoin-cle-kk.XXXXXX")}
mkdir -p "$T"
W="$T/wrap"; mkdir -p "$W"
for c in cc c++ clang clang++; do
   printf '#!/bin/sh\nexec /usr/bin/%s -arch arm64 "$@"\n' "$c" >"$W/$c"; chmod +x "$W/$c"
done
PATH="$W:$P/bin:/opt/homebrew/bin:$PATH"
DYLIB="$B/src/kosmickrisp/vulkan/libvulkan_kosmickrisp.dylib"

# nuanceurs de la sonde
cat >"$T/c.comp" <<'GLSL'
#version 450
layout(local_size_x = 64) in;
layout(constant_id = 0) const uint K = 0u;
layout(set = 0, binding = 0) buffer Buf { float o[]; } b;
void main() {
   uint i = gl_GlobalInvocationID.x;
   b.o[i] = sin(float(i + K)) * 0.5 + float(K);
}
GLSL
cat >"$T/v.vert" <<'GLSL'
#version 450
layout(location = 0) out vec2 uv;
void main() {
   uv = vec2((gl_VertexIndex << 1) & 2, gl_VertexIndex & 2);
   gl_Position = vec4(uv * 2.0 - 1.0, 0.0, 1.0);
}
GLSL
cat >"$T/f.frag" <<'GLSL'
#version 450
layout(location = 0) in vec2 uv;
layout(location = 0) out vec4 c;
void main() { c = vec4(uv, fract(uv.x * 7.0), 1.0); }
GLSL
mkdir -p "$T/spv"
for s in c.comp:c v.vert:v f.frag:f; do
   glslangValidator -V --target-env vulkan1.3 -o "$T/spv/${s#*:}.spv" "$T/${s%%:*}" >/dev/null
done
cc -arch arm64 -std=c11 -O1 -Wall -I"$P/include" "$R/tests/sonde_cle_cache_kk.c" \
   -L"$P/lib" -lvulkan -o "$T/sonde"

construire() { # <etiquette>
   nice -n 10 arch -arm64 ninja -C "$B" src/kosmickrisp/vulkan/libvulkan_kosmickrisp.dylib >"$T/ninja-$1.log" 2>&1 ||
      { tail -20 "$T/ninja-$1.log"; exit 1; }
   mkdir -p "$T/$1"
   cp "$DYLIB" "$T/$1/libvulkan_kosmickrisp.dylib"
   printf '{"ICD":{"api_version":"1.4.362","library_path":"%s"},"file_format_version":"1.0.1"}\n' \
      "$T/$1/libvulkan_kosmickrisp.dylib" >"$T/$1/icd.json"
}
# <etiquette> <fichier> <ancien> <nouveau> : une substitution, remise apres
variante() {
   et=$1; f="$S/$2"
   cp -p "$f" "$T/sauve"
   python3 - "$f" "$3" "$4" <<'PY'
import sys
p, a, n = sys.argv[1:]
s = open(p).read()
assert s.count(a) == 1, a
open(p, 'w').write(s.replace(a, n, 1))
PY
   construire "$et"
   # remis avec une date neuve : avec sa date d'origine, l'objet de la
   # variante paraitrait plus recent et ninja ne recompilerait pas
   cp "$T/sauve" "$f"; touch "$f"
}

# TEMOIN_ETAPE=construire : les quatre constructions seules (sans GPU), dans
# TEMOIN_DIR ; TEMOIN_ETAPE=sonder : les sondes seules, sur les constructions
# deja faites dans TEMOIN_DIR. Sans TEMOIN_ETAPE : les deux.
ETAPE=${TEMOIN_ETAPE:-tout}
if [ "$ETAPE" != sonder ]; then
echo "== constructions (incrementales) dans $B"
construire A
variante B src/kosmickrisp/vulkan/kk_wsi.c '#include "kk_wsi.h"' \
   '#include "kk_wsi.h"
__attribute__((used)) const char kk_temoin_hors_code[] = "temoin 0208 : changement hors code";'
variante C src/kosmickrisp/compiler/nir_to_msl.c 'P(&ctx, "#include <metal_stdlib>\n");' \
   'P(&ctx, "// temoin 0208 : changement du MSL produit\n#include <metal_stdlib>\n");'
variante D src/kosmickrisp/vulkan/kk_physical_device.c '#define KK_CODEGEN_VERSION 1' '#define KK_CODEGEN_VERSION 2'
construire A2   # l'arbre remis : A de nouveau
fi
[ "$ETAPE" != construire ] || { echo "== constructions faites dans $T (sondes : TEMOIN_ETAPE=sonder TEMOIN_DIR=$T)"; exit 0; }
for x in A B C D A2; do [ -f "$T/$x/libvulkan_kosmickrisp.dylib" ] || { echo "$T/$x absent : construire d'abord" >&2; exit 1; }; done
cmp -s "$T/A/libvulkan_kosmickrisp.dylib" "$T/D/libvulkan_kosmickrisp.dylib" && { echo "D = A : variante non construite" >&2; exit 1; }
cmp -s "$T/D/libvulkan_kosmickrisp.dylib" "$T/A2/libvulkan_kosmickrisp.dylib" && { echo "A2 = D : arbre non remis" >&2; exit 1; }

# <etiquette> <cache vulkan> <reserve d'air> <archive> [VAR=val...]
sonde() {
   et=$1; vc=$2; air=$3; arch=$4; shift 4
   env "$@" VK_DRIVER_FILES="$T/$et/icd.json" DYLD_FALLBACK_LIBRARY_PATH="$P/lib" \
      MESA_KK_COMPILE_STATS=1 MESA_KK_AIR_LOCAL="$air" MESA_KK_PIPELINE_CACHE="$arch" \
      "$T/sonde" "$T/spv" "$vc" >"$T/sonde.out" 2>"$T/sonde.err" || { cat "$T/sonde.err"; exit 1; }
   ligne=$(tail -1 "$T/sonde.out")
   stats=$(sed -n 's/^KK compile: library \([0-9]*\) calls.*, \([0-9]*\) from local AIR, \([0-9]*\) local AIR written), pipeline \([0-9]*\) calls.*, \([0-9]*\) from archives/bib=\1 air_local=\2 air_ecrit=\3 pip_metal=\4 archive=\5/p' "$T/sonde.err" | tail -1)
   echo "$ligne $stats"
}
champ() { printf '%s\n' "$1" | tr ' ' '\n' | sed -n "s/^$2=//p"; }
ok=0; ko=0
verif() { if [ "$2" = "$3" ]; then ok=$((ok + 1)); echo "  ok   $1 ($3)"; else ko=$((ko + 1)); echo "  KO   $1 : attendu « $2 », obtenu « $3 »"; fi; }
diff_() { if [ "$2" != "$3" ]; then ok=$((ok + 1)); echo "  ok   $1 ($2 -> $3)"; else ko=$((ko + 1)); echo "  KO   $1 : identiques ($2)"; fi; }
marq() { CIDRE_KK_DYLIB="$T/$1/libvulkan_kosmickrisp.dylib" sh "$R/tests/precompil_kk.sh" kk; }
uuid_build() { CIDRE_CLE_CACHE=build sonde "$1" "$T/jetable-$1" "$T/air-jetable" "$T/arch-jetable" | sed 's/ .*//; s/^uuid=//'; }

echo "== les binaires different tous (identifiant de build)"
for x in B C D; do
   diff_ "dylib $x != A" "$(shasum "$T/A/libvulkan_kosmickrisp.dylib" | cut -c1-12)" "$(shasum "$T/$x/libvulkan_kosmickrisp.dylib" | cut -c1-12)"
done

echo "== A : premier lancement, caches vides"
AIR="$T/air/$(marq A)"
a1=$(sonde A "$T/vk-A" "$AIR" "$T/archive"); echo "  $a1"
verif "A froid : rien depuis le cache Vulkan" 0 "$(champ "$a1" servis)"
verif "A froid : bibliotheques ecrites dans la reserve" "$(champ "$a1" bib)" "$(champ "$a1" air_ecrit)"
UA=$(champ "$a1" uuid)
cp "$T/vk-A" "$T/vk-A.ref"
a2=$(sonde A "$T/vk-A" "$AIR" "$T/archive"); echo "  $a2"
verif "A chaud : 5 pipelines depuis le cache Vulkan" 5 "$(champ "$a2" servis)"

echo "== B : pilote reconstruit, changement hors code"
verif "B : meme marqueur de reserve d'AIR" "$(marq A)" "$(marq B)"
cp "$T/vk-A.ref" "$T/vk-B"
b1=$(sonde B "$T/vk-B" "$T/air/$(marq B)" "$T/archive"); echo "  $b1"
verif "B : meme pipelineCacheUUID" "$UA" "$(champ "$b1" uuid)"
verif "B : cache Vulkan de A accepte" 1 "$(champ "$b1" acceptees)"
verif "B : 5 pipelines depuis le cache Vulkan de A" 5 "$(champ "$b1" servis)"
# sans cache Vulkan : le MSL est regenere, la reserve d'AIR et l'archive de A servent
b2=$(sonde B "$T/vk-B-vide" "$T/air/$(marq B)" "$T/archive"); echo "  $b2"
verif "B sans cache Vulkan : aucune bibliotheque compilee depuis le MSL" 0 "$(champ "$b2" bib)"
verif "B sans cache Vulkan : toutes les bibliotheques depuis la reserve de A" "$(champ "$a1" air_ecrit)" "$(champ "$b2" air_local)"
verif "B sans cache Vulkan : rien d'ecrit dans la reserve" 0 "$(champ "$b2" air_ecrit)"
verif "B sans cache Vulkan : pipelines Metal depuis l'archive de A" "$(champ "$b2" pip_metal)" "$(champ "$b2" archive)"
diff_ "ancienne cle (CIDRE_CLE_CACHE=build) : A et B different" "$(uuid_build A)" "$(uuid_build B)"

echo "== C : changement du MSL produit"
diff_ "C : marqueur de reserve d'AIR change" "$(marq A)" "$(marq C)"
cp "$T/vk-A.ref" "$T/vk-C"
c1=$(sonde C "$T/vk-C" "$T/air/$(marq C)" "$T/archive"); echo "  $c1"
diff_ "C : pipelineCacheUUID change" "$UA" "$(champ "$c1" uuid)"
verif "C : cache Vulkan de A ecarte" 0 "$(champ "$c1" servis)"
verif "C : aucune bibliotheque de A reprise (MSL different)" 0 "$(champ "$c1" air_local)"

echo "== D : KK_CODEGEN_VERSION augmentee"
diff_ "D : marqueur change" "$(marq A)" "$(marq D)"
cp "$T/vk-A.ref" "$T/vk-D"
d1=$(sonde D "$T/vk-D" "$T/air/$(marq D)" "$T/archive"); echo "  $d1"
diff_ "D : pipelineCacheUUID change" "$UA" "$(champ "$d1" uuid)"
verif "D : cache Vulkan de A ecarte" 0 "$(champ "$d1" servis)"

echo "== secours et options"
cp "$T/vk-A.ref" "$T/vk-S"
s1=$(sonde A "$T/vk-S" "$AIR" "$T/archive" CIDRE_CLE_CACHE=sel1); echo "  $s1"
diff_ "CIDRE_CLE_CACHE=sel1 change la cle" "$UA" "$(champ "$s1" uuid)"
verif "CIDRE_CLE_CACHE=sel1 : cache de A ecarte" 0 "$(champ "$s1" servis)"
cp "$T/vk-A.ref" "$T/vk-O"
o1=$(sonde A "$T/vk-O" "$AIR" "$T/archive" CIDRE_LECTURES_CACHEES=1); echo "  $o1"
diff_ "option de code (CIDRE_LECTURES_CACHEES) change la cle" "$UA" "$(champ "$o1" uuid)"
verif "A2 (arbre remis) : cle de A" "$UA" "$(sonde A2 "$T/vk-A2" "$T/air-A2" "$T/arch-A2" | sed 's/ .*//; s/^uuid=//')"

echo "== reserve d'AIR : reprise d'un dossier d'avant 0208 (precompil_kk.sh air_local)"
CD="$T/cidre"; mkdir -p "$CD/air-local/990001/b5d0ebf8c19c/air"; : >"$CD/air-local/990001/b5d0ebf8c19c/air/x.metallib"
d=$(CIDRE_DIR="$CD" CIDRE_KK_DYLIB="$T/A/libvulkan_kosmickrisp.dylib" sh "$R/tests/precompil_kk.sh" air_local 990001)
verif "dossier d'avant 0208 repris sous la cle" "$CD/air-local/990001/$(marq A)" "$d"
verif "son AIR est garde" oui "$([ -f "$d/air/x.metallib" ] && echo oui || echo non)"
d=$(CIDRE_DIR="$CD" CIDRE_KK_DYLIB="$T/B/libvulkan_kosmickrisp.dylib" sh "$R/tests/precompil_kk.sh" air_local 990001)
verif "B (hors code) : meme dossier, AIR garde" oui "$([ -f "$d/air/x.metallib" ] && echo oui || echo non)"
d=$(CIDRE_DIR="$CD" CIDRE_KK_DYLIB="$T/C/libvulkan_kosmickrisp.dylib" sh "$R/tests/precompil_kk.sh" air_local 990001)
# le dossier de la nouvelle cle n'est cree par le pilote qu'a sa premiere ecriture
verif "C (code change) : dossier de C designe, l'ancien retire" "$CD/air-local/990001/$(marq C) 0 non" "$d $(ls "$CD/air-local/990001" | wc -l | tr -d ' ') $([ -d "$CD/air-local/990001/$(marq A)" ] && echo oui || echo non)"

echo "== $ok ok, $ko KO ($T)"
[ "$ko" = 0 ]
