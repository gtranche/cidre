#!/bin/sh
# Ce qu'un jeu voit en D3D12 (Feature Level, Shader Model, atomiques 64 bits...) : lance
# build/d3d12caps.exe dans une COPIE du prefixe (APFS, cp -c, build/pfx-caps) avec la pile
# dx12 : vkd3d-proton pose dans la copie, d3d12/d3d12core natifs, DXGI de DXVK. Rien n'est
# ecrit dans pfx-arm64ec. La copie a son propre wineserver ; refuse si un wineserver tourne
# a la creation de la copie.
#   sh tests/sonde_d3d12caps.sh [VAR=valeur ...]
#   CAPS_ICD=<icd.json>     un autre KosmicKrisp que celui du runtime
#   CAPS_VKD3D=<dossier>    un autre vkd3d-proton (d3d12.dll, d3d12core.dll, ou libs/ d'un build)
#   CAPS_EXE=<sonde.exe>    une autre sonde de build/ (d3d12partage.exe : correctif 0146)
# Exemple (sm66) : sh tests/sonde_d3d12caps.sh CIDRE_VKD3D_DENORMAUX_LIBRES=1 CIDRE_DERIVEES_CALCUL=1 CIDRE_ATOMIQUES_64=1
#   M1 : SM 6.5, AtomicInt64* 0 ; M2+ : SM 6.6, AtomicInt64OnTypedResource 1.
set -u
DIR=$(cd "$(dirname "$0")" && pwd); R=$(cd "$DIR/.." && pwd)
PFX=$R/build/pfx-caps
ICD=${CAPS_ICD:-$R/prefix/share/vulkan/icd.d/kosmickrisp_mesa_icd.aarch64.json}
VKD3D=${CAPS_VKD3D:-$R/build/vkd3d-winarm64ec/libs}
EXE=${CAPS_EXE:-d3d12caps.exe}
[ -f "$R/build/$EXE" ] || { echo "build/$EXE absent : sh tests/build_sondes_sm66.sh"; exit 1; }
if [ ! -d "$PFX" ]; then
   if pgrep -q wineserver; then echo "un wineserver tourne : copie du prefixe remise a plus tard"; exit 1; fi
   cp -c -R "$R/wine/pfx-arm64ec" "$PFX" || exit 1
fi
for d in d3d12 d3d12core; do
   f=$VKD3D/$d/$d.dll; [ -f "$f" ] || f=$VKD3D/$d.dll
   cp "$f" "$PFX/drive_c/windows/system32/$d.dll" || exit 1
done
mkdir -p "$R/build/vklib-caps"
ln -sf "$R/prefix/lib/libvulkan.1.dylib" "$R/build/vklib-caps/libMoltenVK.dylib"
cp "$R/build/$EXE" "$PFX/drive_c/$EXE"
env WINEPREFIX="$PFX" WINEDEBUG=-all \
   WINEDLLOVERRIDES="mscoree,mshtml=;dxgi,d3d11=n;d3d12,d3d12core=n" \
   VK_DRIVER_FILES="$ICD" DYLD_FALLBACK_LIBRARY_PATH="$R/build/vklib-caps:$R/prefix/lib" \
   MESA_KK_EXPERIMENTAL="${MESA_KK_EXPERIMENTAL:-image_view_min_lod,fl12}" "$@" \
   "$R/wine/wine11-arm64/bin/wine" "C:\\$EXE" 2>"$R/build/d3d12caps-stderr.log"
rc=$?
WINEPREFIX="$PFX" "$R/wine/wine11-arm64/bin/wineserver" -k 2>/dev/null
WINEPREFIX="$PFX" "$R/wine/wine11-arm64/bin/wineserver" -w 2>/dev/null
exit $rc
