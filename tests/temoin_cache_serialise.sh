#!/bin/sh
# Temoin de 0209 (KosmicKrisp) : vkGetPipelineCacheData recopie le MSL et le NIR compresses au lieu de les
# recompresser a chaque appel. Natif macOS, sans Wine ni jeu. Construit le temoin dans un dossier a part (un gros
# nuanceur de calcul genere, SPIR-V par glslangValidator, embarque par xxd), puis le lance contre chaque KosmicKrisp
# donne (A/B).
#   sh tests/temoin_cache_serialise.sh [pipelines] <libvulkan_kosmickrisp.dylib>...
#   ex. : sh tests/temoin_cache_serialise.sh 150 <ancien>/libvulkan_kosmickrisp.dylib prefix/lib/libvulkan_kosmickrisp.dylib
# Verdict par pilote (derniere ligne du temoin) : ok si les sauvegardes apres la premiere coutent moins d'un
# cinquieme de la premiere, et si un cache relu rend le meme contenu, vite des sa premiere sauvegarde.
set -eu
R=$(cd "$(dirname "$0")" && cd .. && pwd)
N=150
case ${1:-} in ''|*[!0-9]*) ;; *) N=$1; shift ;; esac
[ $# -gt 0 ] || { echo "usage : $0 [pipelines] <libvulkan_kosmickrisp.dylib>..." >&2; exit 2; }
B=${TMPDIR:-/tmp}/temoin_cache_serialise.$$
mkdir -p "$B"
trap 'rm -rf "$B"' EXIT
python3 - "$B/gros.comp" <<'FIN'
import sys
# beaucoup d'arithmetique non repliable (~200 Ko de MSL), constante de specialisation : un objet distinct par pipeline
L = ['#version 450', 'layout(local_size_x = 64) in;', 'layout(constant_id = 0) const uint K = 1u;',
     'layout(set = 0, binding = 0, std430) buffer B { uint v[]; };', 'void main() {', '  uint i = gl_GlobalInvocationID.x;',
     '  uint a = v[i] + K, b = v[i + 1u] ^ K, c = v[i + 2u];']
for n in range(1500):
    L.append(f'  a = a * {2*n+3}u + (b >> {n%31+1}u); b ^= a + {n*7+1}u + K; c += (a & {n+5}u) | (b * {n%13+2}u);')
    if n % 50 == 0:
        L.append(f'  v[i + {n%200+3}u] = a ^ b ^ c;')
L += ['  v[i] = a + b + c;', '}']
open(sys.argv[1], 'w').write('\n'.join(L) + '\n')
FIN
glslangValidator -V "$B/gros.comp" -o "$B/gros.spv" >/dev/null
(cd "$B" && xxd -i gros.spv > gros_spv.h)
cc -O2 -Wall -I"$B" -I"$R/prefix/include" -o "$B/temoin" "$R/tests/temoin_cache_serialise.c"
# nice (binaire protege) effacerait les DYLD_* : on baisse la priorite du script, heritee par le temoin
renice -n 10 $$ >/dev/null
export DYLD_FALLBACK_LIBRARY_PATH=$R/prefix/lib
export MESA_SHADER_CACHE_DISABLE=true   # ni cache disque de Mesa, ni effet sur les caches de l'utilisateur
for kk in "$@"; do
   kk=$(cd "$(dirname "$kk")" && pwd)/$(basename "$kk")
   printf '{"ICD":{"api_version":"1.4.362","library_path":"%s"},"file_format_version":"1.0.1"}\n' "$kk" > "$B/icd.json"
   echo "### $kk ($(strings "$kk" | sed -n 's/^;*KK_CODEGEN=/KK_CODEGEN=/p' | head -1))"
   VK_DRIVER_FILES="$B/icd.json" "$B/temoin" "$N"
done
