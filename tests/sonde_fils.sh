#!/bin/sh
# Temps de creation d'un fil sous Wine quand l'espace d'adresses de l'hote est
# sature au-dessus de 4 Gio -- l'etat d'un jeu apres quelques minutes sur
# macOS 27 (Expedition 33 sur un Mac M4 : plus de 3 s par fil, GameThread fige
# dans NtCreateThreadEx -> virtual_alloc_thread_data -> map_free_area).
# Correctif : 0117-wine11-recherche-d-adresse-libre-sans-balayage.
#
#   sonde_fils.sh [dossier wine] [prefixe] [exe]
#
#   dossier wine  installation a eprouver (wine/wine11-arm64 par defaut)
#   prefixe       prefixe Wine (wine/pfx-arm64ec par defaut) ; le temoin y est
#                 copie en c:\sonde_fils.exe
#   exe           x64 (defaut, emule) ou a64 (natif)
#
#   SONDE_BINAIRES=dossier  prendre sonde_fils.exe et fragmenter_espace.dylib
#                           deja construits (machine sans chaine de compilation)
#   SONDE_FILS=n            fils par phase (16 par defaut ; l'ancien balayage
#                           peut couter des secondes par fil sur macOS 27)
#
# Pour chaque saturation (FRAGMENTER_GIO : 0, 2 et 9,4 Gio de pages posees tous
# les megaoctets par fragmenter_espace.dylib, inseree dans tous les processus
# Wine), quatre lignes : l'ancien comportement (CIDRE_RECHERCHE_PAS_A_PAS=3),
# le saut de region seul (=2), le plancher seul (=1), le correctif entier (=0).
# Sur un Wine sans le correctif les quatre lignes sont l'ancien comportement.
# Attendu avec le correctif : la ligne « entier » ne depend plus de la
# saturation, et le temoin VirtualAlloc ne bouge pas. « borne hote » : une
# demande a bornes explicites (VirtualAlloc2) dans la zone de l'hote, la
# recherche que les donnees de fil faisaient. « borne saturee » : la meme dans
# une zone saturee a dessein (FRAGMENTER_HAUT), six demandes dont l'adresse
# rendue est verifiee a l'octet dans les deux sens (temps total) ; un ecart
# fait echouer la sonde.
set -e
R=$(cd "$(dirname "$0")/.." && pwd)
WINE_DIR=${1:-$R/wine/wine11-arm64}
export WINEPREFIX=${2:-$R/wine/pfx-arm64ec}
QUEL=${3:-x64}
TMP=${TMPDIR:-/tmp}/sonde-fils-$$
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP"

if [ -n "${SONDE_BINAIRES:-}" ]; then
   # une machine sans chaine de compilation : les deux binaires, construits ailleurs
   cp "$SONDE_BINAIRES/sonde_fils.exe" "$WINEPREFIX/drive_c/sonde_fils.exe"
   cp "$SONDE_BINAIRES/fragmenter_espace.dylib" "$TMP/fragmenter_espace.dylib"
else
   case $QUEL in
      a64) CIBLE=aarch64-w64-mingw32 ;;
      *)   CIBLE=x86_64-w64-mingw32 ;;
   esac
   "$R/toolchain/llvm-mingw/bin/$CIBLE-clang" -O2 -o "$WINEPREFIX/drive_c/sonde_fils.exe" "$R/tests/sonde_fils.c"
   cc -arch arm64 -O2 -dynamiclib -o "$TMP/fragmenter_espace.dylib" "$R/tests/fragmenter_espace.c"
fi
N=${SONDE_FILS:-16}

export WINEDEBUG=-all DYLD_INSERT_LIBRARIES="$TMP/fragmenter_espace.dylib" FRAGMENTER_HAUT=1
[ -d "$R/prefix/lib" ] && export DYLD_FALLBACK_LIBRARY_PATH="$R/prefix/lib"

echo "wine : $WINE_DIR ($("$WINE_DIR/bin/wine" --version 2>/dev/null)), temoin $QUEL, $(sw_vers -productVersion), $(sysctl -n machdep.cpu.brand_string)"
rc=0
for gio in 0 2 9.4; do
   for mode in 3 2 1 0; do
      case $mode in 3) nom="ancien       " ;; 2) nom="saut seul    " ;; 1) nom="plancher seul" ;; 0) nom="entier       " ;; esac
      sortie=$(FRAGMENTER_GIO=$gio CIDRE_RECHERCHE_PAS_A_PAS=$mode "$WINE_DIR/bin/wine" 'c:\sonde_fils.exe' "$N" "$N" 2>&1 | grep -E "CreateThread|VirtualAlloc|fils partis|HORS|ECART" || true)
      FRAGMENTER_GIO=$gio CIDRE_RECHERCHE_PAS_A_PAS=$mode "$WINE_DIR/bin/wineserver" -w
      mediane() { echo "$sortie" | awk -v quoi="$1" '$0 ~ quoi { for (i = 1; i < NF; i++) if ($i == "mediane") print $(i + 1) }'; }
      garde=$(mediane "fil garde"); passant=$(mediane "fil passant"); temoin=$(mediane "VirtualAlloc 1 Mo")
      hote=$(mediane "zone hote"); sature=$(echo "$sortie" | awk '/zone saturee/ {print $(NF - 1)}')
      verdict=$(echo "$sortie" | awk -F': ' '/fils partis/ {print $2}')
      [ "$verdict" = ok ] || rc=1
      printf 'sature %4s Gio  %s  fil garde %8s us  fil passant %8s us  VirtualAlloc %4s us  borne hote %8s us  borne saturee %6s ms  %s\n' \
         "$gio" "$nom" "${garde:-?}" "${passant:-?}" "${temoin:-?}" "${hote:-?}" "${sature:-?}" "${verdict:-ECHEC}"
      echo "$sortie" | grep -E "HORS|ECART" || true
   done
done
exit $rc
