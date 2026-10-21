#!/bin/sh
# Temoin de 0220 (KosmicKrisp : espaces de couleur HDR annonces seulement sur ecran HDR).
# Compte, par vulkaninfo, les couples format/espace de couleur que la surface Metal annonce,
# avec MESA_WSI_METAL_HDR=auto, 0 et 1, et rend la ligne [CIDRE_WSI] de la decision.
#   sh tests/temoin_hdr_wsi.sh [libvulkan_kosmickrisp.dylib]
# Attendu, 5 formats x 12 espaces moins A2B10G10R10 hors HDR10/HLG :
#   ecran HDR (potentiel EDR >= 4, M1 Max XDR = 16) : auto 46 (HDR10/HLG retires du BGRA8), 1 46, 0 24 ;
#   ecran SDR (iMac M4 = 2)                         : auto 24, 1 46, 0 24.
# A lancer dans une session graphique (vulkaninfo cree une surface).
set -eu
R=${R:-$(cd "$(dirname "$0")/.." && pwd)}
LIB=${1:-$R/prefix/lib/libvulkan_kosmickrisp.dylib}
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
printf '{"ICD":{"api_version":"1.4.362","library_path":"%s"},"file_format_version":"1.0.1"}' "$LIB" >"$T/icd.json"
for mode in auto 0 1; do
   MESA_WSI_METAL_HDR=$mode VK_DRIVER_FILES="$T/icd.json" \
      DYLD_FALLBACK_LIBRARY_PATH="$R/prefix/lib" "$R/prefix/bin/vulkaninfo" >"$T/vi.txt" 2>&1 || true
   n=$(awk '/Presentable Surfaces/{p=1} p && /colorSpace =/' "$T/vi.txt" | wc -l | tr -d ' ')
   hdr8=$(awk '/Presentable Surfaces/{p=1} p && /format =/{f=$3} p && /colorSpace =/{print f, $3}' "$T/vi.txt" |
          grep -c 'B8G8R8A8.*HDR10' || true)
   echo "MESA_WSI_METAL_HDR=$mode : $n couples, HDR10/HLG en BGRA8 : $hdr8 ; $(grep -m1 'CIDRE_WSI\] HDR' "$T/vi.txt" || echo 'pas de ligne [CIDRE_WSI] HDR')"
done
