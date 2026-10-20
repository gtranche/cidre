#!/bin/sh
# Temoin de 0213 (runtime Vulkan de Mesa) : la taille rendue par vkGetPipelineCacheData est gardee tant que le cache
# ne change pas. Natif macOS, sans Wine ni jeu. Construit le temoin dans un dossier a part (petit nuanceur de calcul
# a constante de specialisation, SPIR-V par glslangValidator), puis le lance contre chaque KosmicKrisp donne, et
# pour le dernier aussi avec CIDRE_CACHE_TAILLE_RECALCULEE=1 (ancien comportement, memes tailles attendues).
#   sh tests/temoin_cache_taille.sh [objets] <libvulkan_kosmickrisp.dylib>...     (objets : 96505 par defaut)
set -eu
R=$(cd "$(dirname "$0")" && cd .. && pwd)
N=96505
case ${1:-} in ''|*[!0-9]*) ;; *) N=$1; shift ;; esac
[ $# -gt 0 ] || { echo "usage : $0 [objets] <libvulkan_kosmickrisp.dylib>..." >&2; exit 2; }
B=${TMPDIR:-/tmp}/temoin_cache_taille.$$
mkdir -p "$B"
trap 'rm -rf "$B"' EXIT
cat > "$B/petit.comp" <<'FIN'
#version 450
layout(local_size_x = 64) in;
layout(constant_id = 0) const uint K = 1u;
layout(set = 0, binding = 0, std430) buffer B { uint v[]; };
void main() { v[gl_GlobalInvocationID.x] = gl_GlobalInvocationID.x * K + 1u; }
FIN
glslangValidator -V "$B/petit.comp" -o "$B/petit.spv" >/dev/null
(cd "$B" && xxd -i petit.spv > petit_spv.h)
cc -O2 -Wall -I"$B" -I"$R/prefix/include" -o "$B/temoin" "$R/tests/temoin_cache_taille.c"
# nice (binaire protege) effacerait les DYLD_* : on baisse la priorite du script, heritee par le temoin
renice -n 10 $$ >/dev/null
export DYLD_FALLBACK_LIBRARY_PATH=$R/prefix/lib
export MESA_SHADER_CACHE_DISABLE=true   # ni cache disque de Mesa, ni effet sur les caches de l'utilisateur
rc=0
for kk in "$@"; do
   kk=$(cd "$(dirname "$kk")" && pwd)/$(basename "$kk")
   printf '{"ICD":{"api_version":"1.4.362","library_path":"%s"},"file_format_version":"1.0.1"}\n' "$kk" > "$B/icd.json"
   echo "### $kk ($(strings "$kk" | sed -n 's/^;*KK_CODEGEN=/KK_CODEGEN=/p' | head -1))"
   VK_DRIVER_FILES="$B/icd.json" "$B/temoin" "$N" || rc=1
done
echo "### le dernier, avec CIDRE_CACHE_TAILLE_RECALCULEE=1"
CIDRE_CACHE_TAILLE_RECALCULEE=1 VK_DRIVER_FILES="$B/icd.json" "$B/temoin" "$N" || rc=1
exit $rc
