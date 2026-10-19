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
#
# Garde (DEV) : un xtajit pose a la main n'est pas ecrase. etape2 appelle ce
# script a CHAQUE lancement de jeu ; il recopiait la DLL de build par-dessus un
# FEX d'essai pose dans le runtime et le prefixe, et le jeu tournait sur l'ancien
# sans que rien ne le dise (manches PEAK de 0179, 18-19/10). Une cible est
# remplacee si elle manque, si c'est un bouchon de Wine (< 1 Mo), si elle est plus
# ancienne que la DLL de build (FEX reconstruit) ; elle est gardee, avec une
# ligne sur la sortie d'erreur, si c'est un FEX different et plus recent que la
# DLL de build. CIDRE_FEX_FORCER=1 remplace dans tous les cas. Garde en DEV
# seulement : un runtime livre recopie toujours le sien dans le prefixe (apres une
# mise a jour, ses fichiers peuvent dater d'avant la copie du prefixe).
set -e
R=$(cd "$(dirname "$0")/.." && pwd)
W=${WINE_ARM64:-$R/wine/wine11-arm64}
DEST="$W/lib/wine/aarch64-windows"
FEX_EC="$R/third_party/FEX/build-ec/Bin/libarm64ecfex.dll"
FEX_WOW="$R/third_party/FEX/build-wow64/Bin/libwow64fex.dll"

# poser <source> <cible> : copie sauf si la cible est un FEX pose a la main
DEV=0
poser() {
   # deja identique : ne pas recopier (la date de la cible compte pour la suite)
   cmp -s "$1" "$2" && return 0
   if [ "$DEV" = 1 ] && [ -f "$2" ] && [ "${CIDRE_FEX_FORCER:-0}" != 1 ] && ! cmp -s "$1" "$2" \
      && [ "$(wc -c < "$2")" -gt 1000000 ] && [ "$2" -nt "$1" ]; then
      echo "installer_fex : $2 garde (FEX pose a la main, plus recent que $(basename "$1") ; CIDRE_FEX_FORCER=1 pour l'ecraser)" >&2
      return 0
   fi
   cp "$1" "$2"
}

if [ -f "$FEX_EC" ] && [ -f "$FEX_WOW" ]; then
   DEV=1
   poser "$FEX_EC"  "$DEST/xtajit64.dll"
   poser "$FEX_WOW" "$DEST/xtajit.dll"
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
   poser "$DEST/xtajit64.dll" "$WINEPREFIX/drive_c/windows/system32/xtajit64.dll"
   poser "$DEST/xtajit.dll"   "$WINEPREFIX/drive_c/windows/system32/xtajit.dll"
fi
ls -l "$DEST/xtajit64.dll" "$DEST/xtajit.dll"
