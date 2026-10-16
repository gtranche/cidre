#!/bin/sh
# Essai de bout en bout des pipelines precompiles (0165, tests/precompiler_kk.sh,
# tests/precompil_kk.sh), sans jeu, avec les bancs Vulkan natifs de build/ :
#   1. recolte    : MESA_KK_RECOLTE, cache local vide
#   2. fabrication: precompiler_kk.sh -> assets + precompil-index.tsv (cette
#                   architecture + applegpu_g16g)
#   3. telechargement : precompil_kk.sh telecharger depuis file:// (comme une
#                   release), puis « dossier » (ce que le lanceur pose)
#   4. lecture    : MESA_KK_PRECOMPIL = ce dossier, cache local vide -> attendu :
#                   0 bibliotheque compilee, tous les pipelines lus dans l'archive
#   5. temoin     : cache local vide, sans paquet -> tout compile
#   sh tests/essai_precompil_kk.sh [<libvulkan_kosmickrisp.dylib avec 0165>]
# Defaut : prefix/lib du depot. Hors jeu seulement (charge tous les coeurs).
set -eu
R=$(cd "$(dirname "$0")/.." && pwd)
L=${1:-$R/prefix/lib/libvulkan_kosmickrisp.dylib}
LC_ALL=C grep -aq MESA_KK_PRECOMPIL "$L" || { echo "$L n'a pas 0165"; exit 1; }
E=$(mktemp -d "${TMPDIR:-/tmp}/essai-precompil.XXXXXX")
printf '{"ICD":{"api_version":"1.4.362","library_path":"%s"},"file_format_version":"1.0.1"}\n' "$L" >"$E/icd.json"
[ -x "$R/build/puce-gpu" ] || cc -arch arm64 -O1 -fobjc-arc -framework Foundation -framework Metal -o "$R/build/puce-gpu" "$R/tests/puce_gpu.m"
for s in bench_draw_vulkan bench_depth_vulkan bench_alu_vulkan; do
   [ -x "$R/build/$s" ] || { echo "build/$s absent (tests/build_bench_*.sh)"; exit 1; }
done
ok=0; ko=0
verif() { if [ "$2" = "$3" ]; then ok=$((ok + 1)); echo "  ok   $1"; else ko=$((ko + 1)); echo "  KO   $1 : attendu « $2 », obtenu « $3 »"; fi; }
# <etiquette> <recolte|-> <paquet|-> <cache> : les trois bancs ; somme des stats KK
bancs() {
   et=$1; rec=$2; pre=$3; cache=$4
   for b in "bench_draw_vulkan 50 1 1" "bench_depth_vulkan 16 2 1" "bench_alu_vulkan 1000 1024"; do
      set -- $b
      ( cd "$R" && env -u MESA_KK_RECOLTE -u MESA_KK_PRECOMPIL \
         $( [ "$rec" = - ] || echo "MESA_KK_RECOLTE=$rec" ) $( [ "$pre" = - ] || echo "MESA_KK_PRECOMPIL=$pre" ) \
         MESA_KK_PIPELINE_CACHE="$cache" VK_DRIVER_FILES="$E/icd.json" \
         DYLD_FALLBACK_LIBRARY_PATH="$(dirname "$L"):$R/prefix/lib" MESA_KK_COMPILE_STATS=1 \
         "build/$1" "$2" "$3" ${4:-} ) >"$E/$et-$1.log" 2>&1 || echo "  $1 : code $?"
   done
   cat "$E/$et"-*.log | sed -n 's/^KK compile: library \([0-9]*\) calls.*(\([0-9]*\) from AIR), pipeline \([0-9]*\) calls.*, \([0-9]*\) from archives/\1 \2 \3 \4/p' |
      awk '{ l += $1; a += $2; p += $3; h += $4 } END { printf "%d %d %d %d\n", l, a, p, h }'
}
echo "== 1. recolte"
set -- $(bancs recolte "$E/recolte" - "$E/cache-1")
echo "  $1 bibliotheques compilees, $3 pipelines"
LIBS=$1; PIPES=$3
echo "== 2. fabrication"
FAM=$(sh "$R/tests/precompil_kk.sh" famille)
# parties de 50 Ko : le decoupage et le reassemblage au telechargement servent aussi
PRECOMPIL_PARTIE_OCTETS=50000 sh "$R/tests/precompiler_kk.sh" "$E/recolte" "$E/release" 990001 "$FAM" applegpu_g16g | sed 's/^/  /'
verif "assets decoupes en parties" oui "$(ls "$E/release" | grep -q '\.part02$' && echo oui || echo non)"
echo "== 3. telechargement (file://)"
export CIDRE_DIR="$E/cidre" CIDRE_PRECOMPIL_URL="file://$E/release"
verif "etat avant : disponible" disponible "$(sh "$R/tests/precompil_kk.sh" etat 990001 | sed -n 's/^etat=//p')"
sh "$R/tests/precompil_kk.sh" telecharger 990001 | sed 's/^/  /'
D=$(sh "$R/tests/precompil_kk.sh" dossier 990001)
verif "dossier pour le lanceur" "$CIDRE_DIR/precompil/990001/$FAM" "$D"
verif "etat apres : installe" installe "$(sh "$R/tests/precompil_kk.sh" etat 990001 | sed -n 's/^etat=//p')"
verif "autre jeu : absent" absent "$(sh "$R/tests/precompil_kk.sh" etat 990002 | sed -n 's/^etat=//p')"
echo "== 4. lecture du paquet installe, cache local vide"
set -- $(bancs lecture - "$D" "$E/cache-2")
verif "aucune bibliotheque compilee" 0 "$1"
verif "toutes chargees depuis l'AIR" "$LIBS" "$2"
verif "tous les pipelines lus dans l'archive" "$PIPES" "$4"
echo "== 5. temoin, cache local vide"
set -- $(bancs temoin - - "$E/cache-3")
verif "temoin : tout compile" "$LIBS 0" "$1 $2"
verif "temoin : aucun pipeline d'archive" 0 "$4"
rm -rf "${E:?}"
echo "$((ok + ko)) verifications, $ko en echec"
[ "$ko" -eq 0 ]
