#!/bin/sh
# Sondes de Lumen sur M1 (KosmicKrisp 0153 atomiques 64 bits emulees, 0155 barrieres de calcul
# Apple7). Construit dans build/sondes_lumen puis lance la suite ; 0 faux attendu partout.
#   sh tests/sondes_lumen/construire_et_lancer.sh [VAR=valeur ...]
# Exemples :
#   sh tests/sondes_lumen/construire_et_lancer.sh CIDRE_ATOMIQUES_64=1          (M1 : emule)
#   sh tests/sondes_lumen/construire_et_lancer.sh CIDRE_BARRIERES_CALCUL=encodeur
#   VK_DRIVER_FILES=<icd.json> sh tests/sondes_lumen/construire_et_lancer.sh  (autre pilote)
# Chaque soumission reste courte (le M1 a redemarre sur un banc de contention extreme).
# Outils : extraire_spirv_vkd3d.py (SPIR-V d'un vkd3d-proton.cache), recenser_atomiques.py.
set -eu
for a in "$@"; do export "$a"; done
DIR=$(cd "$(dirname "$0")" && pwd); R=$(cd "$DIR/../.." && pwd); B=$R/build/sondes_lumen
mkdir -p "$B"
for s in vis64 vis32 lire64 buf64 vague quad texel args_lourd args_conso producteur consommateur ecrit prod_fmt conso_fmt; do
   glslangValidator -V --target-env vulkan1.3 -o "$B/$s.spv" "$DIR/$s.comp" >/dev/null
done
for s in sonde_atom64_charge_vk sonde_vague sonde_texel sonde_args sonde_visibilite sonde_encodeur sonde_echantillon; do
   cc -arch arm64 -std=c11 -O2 -I"$R/prefix/include" "$DIR/$s.c" -L"$R/prefix/lib" -lvulkan -Wl,-rpath,"$R/prefix/lib" -o "$B/$s"
done
export VK_DRIVER_FILES=${VK_DRIVER_FILES:-$R/prefix/share/vulkan/icd.d/kosmickrisp_mesa_icd.aarch64.json}
export MESA_SHADER_CACHE_DISABLE=1
cd "$B"
for c in "sonde_atom64_charge_vk ." \
         "sonde_vague vague.spv quad.spv" \
         "sonde_texel texel.spv 65536 3" \
         "sonde_args args_lourd.spv args_conso.spv 64 4096" \
         "sonde_visibilite producteur.spv consommateur.spv 16" \
         "sonde_encodeur ecrit.spv 512 1" \
         "sonde_echantillon prod_fmt.spv conso_fmt.spv 16 64 rgba16f"; do
   set -- $c
   n=$1; shift
   printf '%-24s %s\n' "$n" "$(./"$n" "$@" 2>&1 | grep RESULTAT | tail -1)"
done
