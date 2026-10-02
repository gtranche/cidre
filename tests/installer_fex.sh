#!/bin/sh
# Repose FEX par-dessus les stubs xtajit de Wine : « make install » les rend a
# chaque fois, et la trace affiche alors « x64 emulation not implemented ».
#
# Deux contextes :
#  - DEV : les DLL FEX sont dans third_party/FEX/build-*/Bin -> on les repose
#    (make install de Wine a pu reposer ses propres stubs juste avant).
#  - RUNTIME LIVRE : pas de dossier de build ; xtajit64.dll/xtajit.dll DANS le
#    wine livre SONT deja FEX. Rien a reposer -- surtout ne pas echouer, sinon
#    etape2 (set -e) avorte le lancement avant meme de demarrer wine.
set -e
R=$(cd "$(dirname "$0")/.." && pwd)
W=${WINE_ARM64:-$R/wine/wine11-arm64}
DEST="$W/lib/wine/aarch64-windows"
FEX_EC="$R/third_party/FEX/build-ec/Bin/libarm64ecfex.dll"
FEX_WOW="$R/third_party/FEX/build-wow64/Bin/libwow64fex.dll"

if [ -f "$FEX_EC" ] && [ -f "$FEX_WOW" ]; then
   cp "$FEX_EC"  "$DEST/xtajit64.dll"
   cp "$FEX_WOW" "$DEST/xtajit.dll"
else
   # Repli runtime : s'assurer que ce qui est livre n'est pas un stub Wine (petit).
   # FEX fait plusieurs Mo ; un stub, quelques Ko. Si trop petit, on previent.
   for f in xtajit64.dll xtajit.dll; do
      [ -f "$DEST/$f" ] || { echo "FEX absent : $DEST/$f introuvable" >&2; exit 1; }
      sz=$(wc -c < "$DEST/$f")
      [ "$sz" -gt 1000000 ] || { echo "FEX suspect ($f = $sz octets, stub ?)" >&2; exit 1; }
   done
fi

if [ -n "$WINEPREFIX" ] && [ -d "$WINEPREFIX/drive_c/windows/system32" ]; then
   cp "$DEST/xtajit64.dll" "$WINEPREFIX/drive_c/windows/system32/"
   cp "$DEST/xtajit.dll"   "$WINEPREFIX/drive_c/windows/system32/"
fi
ls -l "$DEST/xtajit64.dll" "$DEST/xtajit.dll"
