#!/bin/sh
# Sonde d'image pour d3d11.groupedBufferLoad et d3d11.uncheckedBufferRead de DXMT (patch 0121) :
# tests/probe_d3d11_tampons.c rendu trois fois avec le DXMT de build-essai (options a False, puis
# groupedBufferLoad=True, puis les deux a True), condenses compares cas par cas.
#   - dedans, bord : identiques dans les trois passes (sinon ECHEC) ;
#   - cheval (Load4 a cheval sur la fin du tampon) : doit DIFFERER avec groupedBufferLoad, c'est le
#     seul ecart documente de l'option, et la preuve que la sonde l'a bien eprouvee ;
#   - type (Buffer<T> lu hors borne) : identique avec groupedBufferLoad seul ; avec
#     uncheckedBufferRead le resultat est celui de Metal, affiche pour information.
# Comme sonde_varyings.sh : pose les DLL de build-essai dans l'arbre Wine par mv le temps du test
# et restaure ; refuse de tourner si un jeu ou un wineserver tourne.
#   SONDE_D3DCOMPILER_MS=<d3dcompiler_47.dll 32 bits de Microsoft> sh tests/sonde_tampons.sh
set -e
R=$(cd "$(dirname "$0")/.." && pwd)
BLD=${DXMT_BUILD:-$R/src/dxmt/build-essai}
OUT=${SONDE_OUT:-$R/build/sonde-tampons}
MINGW=$R/toolchain/llvm-mingw/bin
WINDLL=$R/wine/wine11-arm64/lib/wine/aarch64-windows
WINUNIX=$R/wine/wine11-arm64/lib/wine/aarch64-unix
export WINEPREFIX=${WINEPREFIX:-$R/wine/pfx-arm64ec}
EXE=probe_d3d11_tampons.exe
CACHE="$(getconf DARWIN_USER_CACHE_DIR)dxmt/$EXE"

if ps -axo command | grep -v grep | grep -qE 'wineserver|-Win64-Shipping\.exe'; then
   echo "un jeu ou un wineserver tourne : la sonde pose des DLL dans l'arbre Wine, on ne touche a rien" >&2; exit 1
fi
for f in d3d11/d3d11.dll dxgi/dxgi.dll d3d10/d3d10core.dll winemetal/winemetal.dll winemetal/unix/winemetal.so; do
   [ -f "$BLD/src/$f" ] || { echo "ECHEC : $BLD/src/$f absent (sh tests/construire_dxmt.sh)" >&2; exit 1; }
done
LC_ALL=C grep -q -a "d3d11.groupedBufferLoad" "$BLD/src/d3d11/d3d11.dll" || { echo "ECHEC : ce build ne connait pas d3d11.groupedBufferLoad" >&2; exit 1; }

mkdir -p "$OUT/dxbc" "$OUT/garde"
"$MINGW/x86_64-w64-mingw32-gcc" -O1 -o "$OUT/$EXE" "$R/tests/probe_d3d11_tampons.c" -ldxguid -luuid
winpath() { printf 'Z:%s' "$1" | tr / '\\'; }
# macOS n'a pas timeout(1)
borne() { perl -e 'alarm shift; exec @ARGV' "$@"; }

if [ -n "${SONDE_D3DCOMPILER_MS:-}" ]; then
   echo "== shaders compiles par $SONDE_D3DCOMPILER_MS (invite i686) =="
   "$MINGW/i686-w64-mingw32-gcc" -O1 -o "$OUT/probe_d3d11_tampons32.exe" "$R/tests/probe_d3d11_tampons.c" -ldxguid -luuid
   rm -f "$OUT"/dxbc/*.dxbc
   SONDE_D3DCOMPILER=$(winpath "$SONDE_D3DCOMPILER_MS") WINEDLLOVERRIDES="mscoree,mshtml=;d3dcompiler_47=n" \
      borne 300 sh "$R/tests/etape2_pile_arm64ec.sh" "$OUT/probe_d3d11_tampons32.exe" compiler "$(winpath "$OUT/dxbc")" \
      | grep -c "^compile " | sed 's/$/ shaders compiles/'
   "$R/wine/wine11-arm64/bin/wineserver" -k 2>/dev/null || true
else
   rm -f "$OUT"/dxbc/*.dxbc
   echo "== shaders compiles par le d3dcompiler de Wine (SONDE_D3DCOMPILER_MS non pose) =="
fi

# Pose : l'original part dans garde/ par mv, le build arrive par cp + mv.
POSES="d3d11.dll:$WINDLL:d3d11 dxgi.dll:$WINDLL:dxgi d3d10core.dll:$WINDLL:d3d10 winemetal.dll:$WINDLL:winemetal winemetal.so:$WINUNIX:winemetal/unix"
restaurer() {
   for p in $POSES; do
      f=${p%%:*}; reste=${p#*:}; d=${reste%%:*}
      [ -f "$OUT/garde/$f" ] && mv -f "$OUT/garde/$f" "$d/$f"
   done
}
trap 'restaurer' EXIT
trap 'exit 130' INT TERM
: > "$OUT/empreintes"
for p in $POSES; do
   f=${p%%:*}; reste=${p#*:}; d=${reste%%:*}; s=${reste#*:}
   [ -f "$d/$f" ] || { echo "ECHEC : $d/$f absent" >&2; exit 1; }
   echo "$(shasum -a 256 < "$d/$f" | cut -d' ' -f1) $d/$f" >> "$OUT/empreintes"
   cp -p "$BLD/src/$s/$f" "$d/$f.sonde-tmp"
   mv "$d/$f" "$OUT/garde/$f"
   mv "$d/$f.sonde-tmp" "$d/$f"
done

passe() { # <nom> <groupedBufferLoad> <uncheckedBufferRead>
   DXMT_CONFIG="d3d11.groupedBufferLoad=$2;d3d11.uncheckedBufferRead=$3" DXMT_LOG_LEVEL=warn \
   WINEDLLOVERRIDES="mscoree,mshtml=;dxgi,d3d11,d3d10core,winemetal=b" \
      borne 300 sh "$R/tests/etape2_pile_arm64ec.sh" "$OUT/$EXE" rendre "$(winpath "$OUT/dxbc")" > "$OUT/$1.txt" 2>"$OUT/$1.err" || true
   "$R/wine/wine11-arm64/bin/wineserver" -k 2>/dev/null || true
   echo "== passe $1 (groupedBufferLoad=$2, uncheckedBufferRead=$3) : $(grep -c '^cas ' "$OUT/$1.txt") cas =="
   cat "$OUT/$1.txt"
   grep '^cas ' "$OUT/$1.txt" | awk '{print $2, $3}' > "$OUT/$1.condenses"
}

rm -rf "$CACHE"
passe amont False False
passe groupe True False
passe tout True True

restaurer
trap - EXIT
rc=0
while read -r somme chemin; do
   [ "$(shasum -a 256 < "$chemin" | cut -d' ' -f1)" = "$somme" ] || { echo "ECHEC : $chemin n'a pas retrouve son contenu d'origine" >&2; rc=1; }
done < "$OUT/empreintes"
[ $rc -eq 0 ] && echo "arbre Wine restaure (5 empreintes verifiees)"

echo "== comparaison =="
for p in amont groupe tout; do
   grep -q '^FIN' "$OUT/$p.txt" || { echo "ECHEC : la passe $p n'est pas allee au bout (voir $OUT/$p.err)"; rc=1; }
   [ "$(wc -l < "$OUT/$p.condenses" | tr -d ' ')" -eq 4 ] || { echo "ECHEC : passe $p, 4 cas attendus"; rc=1; }
   if grep '^cas ' "$OUT/$p.txt" | grep -q 'couverts=0 '; then echo "ECHEC : passe $p, un cas n'a rien dessine"; rc=1; fi
done
condense() { awk -v c="$2" '$1 == c {print $2}' "$OUT/$1.condenses"; }
for c in dedans bord; do
   a=$(condense amont $c)
   [ -n "$a" ] && [ "$a" = "$(condense groupe $c)" ] && [ "$a" = "$(condense tout $c)" ] \
      && echo "$c : identique dans les trois passes" || { echo "ECHEC : $c differe (amont $a, groupe $(condense groupe $c), tout $(condense tout $c))"; rc=1; }
done
[ "$(condense amont type)" = "$(condense groupe type)" ] && echo "type : identique avec groupedBufferLoad seul" \
   || { echo "ECHEC : type differe avec groupedBufferLoad seul"; rc=1; }
[ "$(condense amont cheval)" != "$(condense groupe cheval)" ] && echo "cheval : differe avec groupedBufferLoad (ecart documente, l'option est bien eprouvee)" \
   || { echo "ECHEC : cheval identique, l'option groupedBufferLoad n'a rien change : la sonde n'a rien eprouve"; rc=1; }
[ "$(condense amont type)" = "$(condense tout type)" ] && echo "type : identique aussi avec uncheckedBufferRead (Metal rend zero hors borne sur ce GPU)" \
   || echo "type : differe avec uncheckedBufferRead (lecture hors borne laissee a Metal ; pour information)"
[ $rc -eq 0 ] && echo "SONDE TAMPONS : IMAGES IDENTIQUES" || echo "SONDE TAMPONS : ECHEC"
exit $rc
