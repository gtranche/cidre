#!/bin/sh
# Repose FEX par-dessus les stubs xtajit de Wine : « make install » les rend a
# chaque fois, et la trace affiche alors « x64 emulation not implemented ».
set -e
R=$(cd "$(dirname "$0")/.." && pwd)
W=${WINE_ARM64:-$R/wine/wine11-arm64}
cp "$R/third_party/FEX/build-ec/Bin/libarm64ecfex.dll" "$W/lib/wine/aarch64-windows/xtajit64.dll"
cp "$R/third_party/FEX/build-wow64/Bin/libwow64fex.dll" "$W/lib/wine/aarch64-windows/xtajit.dll"
if [ -n "$WINEPREFIX" ] && [ -d "$WINEPREFIX/drive_c/windows/system32" ]; then
   cp "$W/lib/wine/aarch64-windows/xtajit64.dll" "$WINEPREFIX/drive_c/windows/system32/"
   cp "$W/lib/wine/aarch64-windows/xtajit.dll" "$WINEPREFIX/drive_c/windows/system32/"
fi
ls -l "$W/lib/wine/aarch64-windows/xtajit64.dll" "$W/lib/wine/aarch64-windows/xtajit.dll"
