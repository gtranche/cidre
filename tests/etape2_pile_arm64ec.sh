#!/bin/sh
# Pile entierement arm64, invite x86_64 : PE Windows x86_64 -> FEX ARM64EC ->
# Wine arm64 -> DXVK -> winevulkan -> chargeur Vulkan arm64 -> KosmicKrisp ->
# Metal. Aucune traduction Rosetta nulle part.
#
#   etape2_pile_arm64ec.sh <programme.exe> [args...]
#
# WINEPREFIX doit exister ; le creer avec « wineboot --init » une premiere fois.
set -e
R=$(cd "$(dirname "$0")/.." && pwd)
WINE=${WINE:-$R/wine/wine11-arm64/bin/wine}
export WINEPREFIX=${WINEPREFIX:-$R/wine/pfx-arm64ec}
export WINEDEBUG=${WINEDEBUG:--all}
export WINEDLLOVERRIDES="${WINEDLLOVERRIDES:-mscoree,mshtml=;dxgi,d3d11=n}"
export VK_DRIVER_FILES=$R/prefix/share/vulkan/icd.d/kosmickrisp_mesa_icd.aarch64.json
export DYLD_LIBRARY_PATH=$R/wine/vklib-arm64:$R/prefix/lib
export MESA_KK_EXPERIMENTAL=${MESA_KK_EXPERIMENTAL:-custom_border,image_view_min_lod}

# Ce dossier precede les chemins systeme : il sert a presenter les bonnes
# tranches arm64. /usr/local/lib contient un libfreetype x86_64 (la pile
# Rosetta), que dlopen du soname nu trouvait d'abord -- d'ou « Wine cannot find
# the FreeType font library » alors que configure l'avait bien trouve.
mkdir -p "$R/wine/vklib-arm64"
ln -sf "$R/prefix/lib/libvulkan.1.dylib" "$R/wine/vklib-arm64/libMoltenVK.dylib"
for l in libfreetype.6.dylib libfontconfig.1.dylib; do
   [ -f /opt/homebrew/lib/$l ] && ln -sf /opt/homebrew/lib/$l "$R/wine/vklib-arm64/$l"
done

# FEX est repose a chaque fois : « make install » de Wine remet ses propres
# bouchons xtajit, et la trace dit alors « x64 emulation not implemented ».
sh "$R/tests/installer_fex.sh" >/dev/null

exec "$WINE" "$@"
