#!/bin/sh
# Garde de tests/installer_fex.sh : un xtajit pose a la main n'est pas ecrase.
#
#   tester_installer_fex.sh     installer_fex.sh copie dans une arborescence
#                               temporaire (fausses DLL de build, runtime, prefixe)
#
# Cas : bouchon de Wine remplace ; cible identique laissee sans message ; FEX
# reconstruit (DLL de build plus recente) remplace ; FEX pose a la main (plus
# recent, different) garde avec une ligne sur la sortie d'erreur, au runtime comme
# au prefixe ; CIDRE_FEX_FORCER=1 remplace ; runtime livre sans build inchange.
set -u
R=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d "${TMPDIR:-/tmp}/tester_installer_fex.XXXXXX")
trap 'rm -rf "$T"' EXIT
ECHECS=0; N=0
verif() { N=$((N + 1)); if [ "$2" = "$3" ]; then echo "ok    $1"; else echo "KO    $1 : attendu « $2 », obtenu « $3 »"; ECHECS=$((ECHECS + 1)); fi; }

mkdir -p "$T/tests" "$T/third_party/FEX/build-ec/Bin" "$T/third_party/FEX/build-wow64/Bin" \
         "$T/wine/wine11-arm64/lib/wine/aarch64-windows" "$T/pfx/drive_c/windows/system32"
cp "$R/tests/installer_fex.sh" "$T/tests/"
EC=$T/third_party/FEX/build-ec/Bin/libarm64ecfex.dll
WOW=$T/third_party/FEX/build-wow64/Bin/libwow64fex.dll
D=$T/wine/wine11-arm64/lib/wine/aarch64-windows
P=$T/pfx/drive_c/windows/system32
# une « DLL » de 1,1 Mo dont le premier octet dit la version
dll() { { printf '%s' "$2"; head -c 1100000 /dev/zero; } > "$1"; }
ver() { head -c 1 "$1" 2>/dev/null; }
lancer() { WINEPREFIX="$T/pfx" sh "$T/tests/installer_fex.sh" 2>"$T/err" >/dev/null; echo $?; }
vieillir() { touch -t 202601010000 "$@"; }

echo "== 1. bouchons de Wine remplaces"
dll "$EC" A; dll "$WOW" a
printf 'stub' > "$D/xtajit64.dll"; printf 'stub' > "$D/xtajit.dll"
verif "code de sortie" 0 "$(lancer)"
verif "runtime xtajit64 = build" A "$(ver "$D/xtajit64.dll")"
verif "runtime xtajit = build" a "$(ver "$D/xtajit.dll")"
verif "prefixe xtajit64 = build" A "$(ver "$P/xtajit64.dll")"
verif "rien sur la sortie d'erreur" "" "$(cat "$T/err")"

echo "== 2. deja en place : rien dit"
verif "code de sortie" 0 "$(lancer)"
verif "rien sur la sortie d'erreur" "" "$(cat "$T/err")"

echo "== 3. FEX reconstruit (build plus recente) : remplace"
vieillir "$D/xtajit64.dll" "$P/xtajit64.dll"
dll "$EC" B
verif "code de sortie" 0 "$(lancer)"
verif "runtime = nouveau build" B "$(ver "$D/xtajit64.dll")"
verif "prefixe = nouveau build" B "$(ver "$P/xtajit64.dll")"

echo "== 4. FEX pose a la main au runtime et au prefixe : garde"
vieillir "$EC" "$WOW"
dll "$D/xtajit64.dll" E; dll "$P/xtajit64.dll" E
verif "code de sortie" 0 "$(lancer)"
verif "runtime garde" E "$(ver "$D/xtajit64.dll")"
verif "prefixe garde" E "$(ver "$P/xtajit64.dll")"
verif "xtajit (32 bits) toujours le build" a "$(ver "$D/xtajit.dll")"
# le prefixe, identique au runtime garde, est recopie sans rien dire
verif "une ligne (le runtime)" 1 "$(grep -c 'garde (FEX pose a la main' "$T/err")"

echo "== 5. pose au runtime seul : le prefixe le suit"
vieillir "$EC" "$WOW"; vieillir "$P/xtajit64.dll"
dll "$D/xtajit64.dll" F
verif "code de sortie" 0 "$(lancer)"
verif "runtime garde" F "$(ver "$D/xtajit64.dll")"
verif "prefixe = la pose du runtime" F "$(ver "$P/xtajit64.dll")"

echo "== 5b. pose au prefixe seul (runtime = build) : gardee"
cp "$EC" "$D/xtajit64.dll"; vieillir "$EC" "$WOW" "$D/xtajit64.dll"
dll "$P/xtajit64.dll" H
verif "code de sortie" 0 "$(lancer)"
verif "prefixe garde" H "$(ver "$P/xtajit64.dll")"
verif "une ligne (le prefixe)" 1 "$(grep -c "$P/xtajit64.dll garde" "$T/err")"

echo "== 6. CIDRE_FEX_FORCER=1 : remplace"
dll "$D/xtajit64.dll" G; dll "$P/xtajit64.dll" G
verif "code de sortie" 0 "$(CIDRE_FEX_FORCER=1 lancer)"
verif "runtime = build" B "$(ver "$D/xtajit64.dll")"
verif "prefixe = build" B "$(ver "$P/xtajit64.dll")"
verif "rien sur la sortie d'erreur" "" "$(cat "$T/err")"

echo "== 7. runtime livre (pas de build) : inchange"
rm -rf "$T/third_party"
dll "$D/xtajit64.dll" L; vieillir "$D/xtajit64.dll"
verif "code de sortie" 0 "$(lancer)"
verif "runtime livre inchange" L "$(ver "$D/xtajit64.dll")"
verif "prefixe = runtime livre, meme s'il date d'avant" L "$(ver "$P/xtajit64.dll")"
printf 'stub' > "$D/xtajit.dll"
verif "bouchon dans un runtime livre : echec" 1 "$(lancer)"

echo "$N verifications, $ECHECS en echec"
[ "$ECHECS" -eq 0 ]
