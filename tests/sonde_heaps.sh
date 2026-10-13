#!/bin/sh
# Sonde de l'initialisation D3D11 de Heaps/HashLink (Dead Cells) contre DXMT :
# tests/probe_d3d11_heaps.c, compile en i686 et en x86_64, lance trois fois avec
# l'override du lanceur (dxgi,d3d11,d3d10core,winemetal=b).
#   1. cause    : DXMT pose pour le 64 bits seulement (l'etat d'avant le 2026-10-13),
#                 invite i686 -> le d3d11.dll charge est le builtin de Wine (wined3d),
#                 qui rend 887A0004 : le « DXError 887A0004 line 112 » de Dead Cells ;
#   2. temoin   : meme pose, invite x86_64 -> DXMT repond, la sequence passe ;
#   3. correctif: DXMT i386 (build i386 de construire_dxmt.sh) pose en plus dans
#                 lib/wine/i386-windows -> l'invite i686 obtient DXMT, la sequence
#                 passe et les deux pixels relus sont justes.
# Comme sonde_tampons.sh : pose les DLL par mv le temps du test et restaure
# (empreintes verifiees) ; refuse de tourner si un jeu ou un wineserver tourne,
# et ne tue jamais le wineserver (prefixe partage entre sessions).
#   sh tests/sonde_heaps.sh
# Variables : DXMT_BUILD (src/dxmt/build-essai), DXMT_BUILD_I386 ($DXMT_BUILD-i386).
set -e
R=$(cd "$(dirname "$0")/.." && pwd)
BLD=${DXMT_BUILD:-$R/src/dxmt/build-essai}
BLD32=${DXMT_BUILD_I386:-$BLD-i386}
OUT=${SONDE_OUT:-$R/build/sonde-heaps}
MINGW=$R/toolchain/llvm-mingw/bin
WINDLL=$R/wine/wine11-arm64/lib/wine/aarch64-windows
WINDLL32=$R/wine/wine11-arm64/lib/wine/i386-windows
WINUNIX=$R/wine/wine11-arm64/lib/wine/aarch64-unix
export WINEPREFIX=${WINEPREFIX:-$R/wine/pfx-arm64ec}
SYSWOW=$WINEPREFIX/drive_c/windows/syswow64

if ps -axo command | grep -v grep | grep -qE 'wineserver|-Win64-Shipping\.exe'; then
   echo "un jeu ou un wineserver tourne : la sonde pose des DLL dans l'arbre Wine, on ne touche a rien" >&2; exit 1
fi
for f in d3d11/d3d11.dll dxgi/dxgi.dll d3d10/d3d10core.dll winemetal/winemetal.dll winemetal/unix/winemetal.so; do
   [ -f "$BLD/src/$f" ] || { echo "ECHEC : $BLD/src/$f absent (sh tests/construire_dxmt.sh)" >&2; exit 1; }
done
for f in d3d11/d3d11.dll dxgi/dxgi.dll d3d10/d3d10core.dll winemetal/winemetal.dll; do
   [ -f "$BLD32/src/$f" ] || { echo "ECHEC : $BLD32/src/$f absent (sh tests/construire_dxmt.sh)" >&2; exit 1; }
done
[ -d "$SYSWOW" ] || { echo "ECHEC : pas de syswow64 dans $WINEPREFIX" >&2; exit 1; }

mkdir -p "$OUT/garde" "$OUT/garde32" "$OUT/journaux"
"$MINGW/i686-w64-mingw32-gcc" -O1 -o "$OUT/probe_d3d11_heaps32.exe" "$R/tests/probe_d3d11_heaps.c" -ldxguid -luuid
"$MINGW/x86_64-w64-mingw32-gcc" -O1 -o "$OUT/probe_d3d11_heaps64.exe" "$R/tests/probe_d3d11_heaps.c" -ldxguid -luuid
# macOS n'a pas timeout(1)
borne() { perl -e 'alarm shift; exec @ARGV' "$@"; }

# Pose : <fichier>:<destination>:<source dans le build>:<garde>. L'original part
# dans la garde par mv, le build arrive par cp + mv ; un fichier qui n'existait pas
# (winemetal.dll hors d'un lancement DXMT) est simplement retire a la fin.
POSES64="d3d11.dll:$WINDLL:$BLD/src/d3d11:garde dxgi.dll:$WINDLL:$BLD/src/dxgi:garde d3d10core.dll:$WINDLL:$BLD/src/d3d10:garde winemetal.dll:$WINDLL:$BLD/src/winemetal:garde winemetal.so:$WINUNIX:$BLD/src/winemetal/unix:garde"
POSES32="d3d11.dll:$WINDLL32:$BLD32/src/d3d11:garde32 dxgi.dll:$WINDLL32:$BLD32/src/dxgi:garde32 d3d10core.dll:$WINDLL32:$BLD32/src/d3d10:garde32 winemetal.dll:$WINDLL32:$BLD32/src/winemetal:garde32"
POSEES=
champs() { f=${1%%:*}; r1=${1#*:}; d=${r1%%:*}; r2=${r1#*:}; s=${r2%%:*}; g=${r2#*:}; }
poser() {
   for p in "$@"; do
      champs "$p"
      if [ -f "$d/$f" ]; then
         echo "$(shasum -a 256 < "$d/$f" | cut -d' ' -f1) $d/$f" >> "$OUT/empreintes"
         cp -p "$s/$f" "$d/$f.sonde-tmp"
         mv "$d/$f" "$OUT/$g/$f"
         mv "$d/$f.sonde-tmp" "$d/$f"
      else
         echo "absent $d/$f" >> "$OUT/empreintes"
         cp -p "$s/$f" "$d/$f"
      fi
      POSEES="$POSEES $p"
   done
}
restaurer() {
   for p in $POSEES; do
      champs "$p"
      if [ -f "$OUT/$g/$f" ]; then mv -f "$OUT/$g/$f" "$d/$f"
      elif grep -q "^absent $d/$f\$" "$OUT/empreintes" 2>/dev/null; then rm -f "$d/$f"; fi
   done
   POSEES=
   rm -f "$SYSWOW/winemetal.dll.sonde"
   [ ! -f "$OUT/garde32/syswow-winemetal.dll" ] || mv -f "$OUT/garde32/syswow-winemetal.dll" "$SYSWOW/winemetal.dll"
   [ ! -f "$OUT/syswow-winemetal-posee" ] || { rm -f "$SYSWOW/winemetal.dll" "$OUT/syswow-winemetal-posee"; }
}
trap 'restaurer' EXIT
trap 'exit 130' INT TERM
: > "$OUT/empreintes"

passe() { # <nom> <exe>
   rm -rf "$OUT/journaux/$1"; mkdir -p "$OUT/journaux/$1"
   DXMT_LOG_LEVEL=info DXMT_LOG_PATH="$OUT/journaux/$1" \
   WINEDLLOVERRIDES="mscoree,mshtml=;dxgi,d3d11,d3d10core,winemetal=b" \
      borne 120 sh "$R/tests/etape2_pile_arm64ec.sh" "$OUT/$2" > "$OUT/$1.txt" 2>"$OUT/$1.err" || true
   # on attend la fin du wineserver, on ne le tue pas : si un jeu a demarre entre
   # temps sur ce prefixe partage, -k l'emporterait
   borne 60 "$R/wine/wine11-arm64/bin/wineserver" -w 2>/dev/null || true
   echo "== passe $1 ($2) =="
   cat "$OUT/$1.txt"
}

poser $POSES64
passe cause probe_d3d11_heaps32.exe
passe temoin probe_d3d11_heaps64.exe

poser $POSES32
# le chargeur resout l'import winemetal.dll de d3d11.dll par le dossier systeme
# de l'invite : syswow64 pour un i386 (comme system32 dans le lanceur)
if [ -f "$SYSWOW/winemetal.dll" ]; then mv "$SYSWOW/winemetal.dll" "$OUT/garde32/syswow-winemetal.dll"; else : > "$OUT/syswow-winemetal-posee"; fi
cp -p "$BLD32/src/winemetal/winemetal.dll" "$SYSWOW/winemetal.dll"
passe correctif probe_d3d11_heaps32.exe

restaurer
trap - EXIT
rc=0
while read -r somme chemin; do
   if [ "$somme" = absent ]; then
      [ ! -e "$chemin" ] || { echo "ECHEC : $chemin aurait du etre retire" >&2; rc=1; }
   else
      [ "$(shasum -a 256 < "$chemin" | cut -d' ' -f1)" = "$somme" ] || { echo "ECHEC : $chemin n'a pas retrouve son contenu d'origine" >&2; rc=1; }
   fi
done < "$OUT/empreintes"
[ $rc -eq 0 ] && echo "arbre Wine restaure ($(wc -l < "$OUT/empreintes" | tr -d ' ') fichiers verifies)"

echo "== verdict =="
a() { grep -q "$2" "$OUT/$1.txt"; }
if a cause "hr=887A0004" && a cause "builtin Wine (wined3d)"; then
   echo "cause : sans DXMT i386, l'invite 32 bits tombe sur le d3d11 builtin de Wine, qui rend 887A0004"
else echo "ECHEC : la passe cause n'a pas reproduit 887A0004 par wined3d (voir $OUT/cause.txt)"; rc=1; fi
if a temoin "^rendu : DXMT" && a temoin "^FIN ok"; then echo "temoin : l'invite 64 bits obtient DXMT, sequence complete"
else echo "ECHEC : le temoin 64 bits ne passe pas en DXMT (voir $OUT/temoin.txt, $OUT/temoin.err)"; rc=1; fi
if a correctif "^rendu : DXMT" && a correctif "^FIN ok"; then echo "correctif : avec DXMT i386 pose, l'invite 32 bits obtient DXMT, sequence complete, pixels justes"
else echo "ECHEC : l'invite 32 bits ne passe pas en DXMT i386 (voir $OUT/correctif.txt, $OUT/correctif.err, $OUT/journaux/correctif)"; rc=1; fi
[ $rc -eq 0 ] && echo "SONDE HEAPS : CAUSE REPRODUITE, CORRECTIF VERIFIE" || echo "SONDE HEAPS : ECHEC"
exit $rc
