#!/bin/sh
# Pile ouverte complete : PE Windows -> Wine -> winevulkan -> KosmicKrisp -> Metal 4.
#
# Substitution : winemac.so fait dlopen("libMoltenVK.dylib") en dur. On place le
# loader Vulkan sous ce nom sur DYLD_LIBRARY_PATH ; Wine n'appelle que des points
# d'entree Vulkan standards, donc il ne voit pas la difference.
set -e
R=$(cd "$(dirname "$0")/.." && pwd)
WINE=${WINE:-$R/wine/wine10/bin/wine64}

# pfx10 est le prefixe construit pour Wine 10 : c'est celui qui porte le dxgi.dll
# de DXVK et le vkd3d-proton PE. pfx est un vestige de l'etape precedente, son
# dxgi.dll est incomplet et le chargement du PE echoue avec c0000135.
if [ -z "${WINEPREFIX:-}" ]; then
   if [ -d "$R/wine/pfx10" ]; then
      WINEPREFIX=$R/wine/pfx10
   else
      WINEPREFIX=$R/wine/pfx
   fi
fi
export WINEPREFIX
export WINEDEBUG=${WINEDEBUG:--all}
export WINEDLLOVERRIDES="${WINEDLLOVERRIDES:-d3d12,d3d12core,dxgi,d3d11,d3d10core,d3d9=n}"
export VK_DRIVER_FILES=$R/prefix-x64/share/vulkan/icd.d/kosmickrisp_mesa_icd.x86_64.json
export DYLD_LIBRARY_PATH=$R/wine/vklib:$R/prefix-x64/lib
export MESA_KK_EXPERIMENTAL=${MESA_KK_EXPERIMENTAL:-custom_border,image_view_min_lod}

# Wine 10 cherche libvulkan avant MoltenVK et a ete configure sur notre loader, donc ce
# lien ne sert qu'aux Wine anterieurs (9.x), dont winemac.so fait dlopen("libMoltenVK.dylib").
mkdir -p "$R/wine/vklib"
ln -sf "$R/prefix-x64/lib/libvulkan.1.dylib" "$R/wine/vklib/libMoltenVK.dylib"

[ -d "$WINEPREFIX" ] || "$WINE" wineboot --init >/dev/null 2>&1

exec "$WINE" "$@"
