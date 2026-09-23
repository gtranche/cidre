#!/bin/sh
# Pile ouverte, variante WoW64 : accepte les executables Windows 32 bits.
#
# Identique a etape2_pile_wine.sh, mais pointe sur le Wine construit avec
# --enable-archs=i386,x86_64 et sur un prefixe qui porte un syswow64.
set -e
R=$(cd "$(dirname "$0")/.." && pwd)
WINE=${WINE:-$R/wine/wine10-wow64/bin/wine}

WINEPREFIX=${WINEPREFIX:-$R/wine/pfx-wow64}
export WINEPREFIX
export WINEDEBUG=${WINEDEBUG:--all}
export WINEDLLOVERRIDES="${WINEDLLOVERRIDES:-d3d12,d3d12core,dxgi,d3d11,d3d10core,d3d9,d3d8=n;d3dx9_43,d3dcompiler_43=n;mscoree,mshtml=d}"
export VK_DRIVER_FILES=$R/prefix-x64/share/vulkan/icd.d/kosmickrisp_mesa_icd.x86_64.json
export DYLD_LIBRARY_PATH=$R/wine/vklib:$R/wine/deps:$R/prefix-x64/lib
export DXVK_CONFIG_FILE=${DXVK_CONFIG_FILE:-$R/dxvk.conf}
export MESA_KK_EXPERIMENTAL=${MESA_KK_EXPERIMENTAL:-custom_border,image_view_min_lod}

mkdir -p "$R/wine/vklib"
ln -sf "$R/prefix-x64/lib/libvulkan.1.dylib" "$R/wine/vklib/libMoltenVK.dylib"

[ -d "$WINEPREFIX" ] || WINEDLLOVERRIDES="mscoree,mshtml=d" "$WINE" wineboot --init >/dev/null 2>&1

exec "$WINE" "$@"
