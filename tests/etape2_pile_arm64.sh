#!/bin/sh
# Pile entierement ARM64 : PE Windows aarch64 -> Wine arm64 -> loader Vulkan arm64
# -> KosmicKrisp arm64 -> Metal 4.  Aucune traduction Rosetta nulle part.
set -e
R=$(cd "$(dirname "$0")/.." && pwd)
WINE=${WINE:-$R/wine/wine11-arm64/bin/wine}

if [ -z "${WINEPREFIX:-}" ]; then WINEPREFIX=$R/wine/pfx-arm64; fi
export WINEPREFIX
export WINEDEBUG=${WINEDEBUG:--all}
export WINEDLLOVERRIDES="${WINEDLLOVERRIDES:-d3d12,d3d12core=n}"
export VK_DRIVER_FILES=$R/prefix/share/vulkan/icd.d/kosmickrisp_mesa_icd.aarch64.json
export DYLD_LIBRARY_PATH=$R/wine/vklib-arm64:$R/prefix/lib
export MESA_KK_EXPERIMENTAL=${MESA_KK_EXPERIMENTAL:-custom_border,image_view_min_lod}

mkdir -p "$R/wine/vklib-arm64"
ln -sf "$R/prefix/lib/libvulkan.1.dylib" "$R/wine/vklib-arm64/libMoltenVK.dylib"

[ -d "$WINEPREFIX" ] || "$WINE" wineboot --init >/dev/null 2>&1

exec "$WINE" "$@"
