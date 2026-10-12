#!/bin/sh
# Sonde d'equivalence d'image pour d3d11.narrowVaryings de DXMT (patch 0116) :
# rend les memes cas avec des varyings float4 (amont) puis a la largeur lue par
# le pixel shader, et compare les condenses des cibles de rendu (flottant 32
# bits : egalite au bit pres). Voir l'en-tete de tests/probe_d3d11_varyings.c.
#
#   sh tests/sonde_varyings.sh
#
# Variables :
#   DXMT_BUILD            build de DXMT a eprouver (defaut src/dxmt/build-essai)
#   SONDE_D3DCOMPILER_MS  chemin macOS d'un d3dcompiler_47.dll 32 bits de Microsoft
#                         (un dossier de jeu en contient souvent un). Avec lui les
#                         shaders portent les masques partiels d'un vrai jeu ; sans
#                         lui, compilateur de Wine (entrees entieres : seuls les
#                         cas « type » et « tasse » reduisent quelque chose).
#   SONDE_OUT             dossier de travail (defaut build/sonde-varyings)
#
# Le build est pose dans l'arbre Wine le temps de la sonde (Wine charge ses
# builtins de son dossier d'installation avant WINEDLLPATH), par mv, puis les
# fichiers d'origine sont remis et leurs empreintes verifiees. Ne tourne pas si
# un jeu ou un wineserver tourne. Preuve que la sonde parle : le cache de
# shaders de la sonde, vide au depart, doit contenir des varyings reduits (nom
# « regN_CmM ») apres la passe avec l'option et aucun apres la passe sans.
set -e
R=$(cd "$(dirname "$0")/.." && pwd)
BLD=${DXMT_BUILD:-$R/src/dxmt/build-essai}
OUT=${SONDE_OUT:-$R/build/sonde-varyings}
MINGW=$R/toolchain/llvm-mingw/bin
WINDLL=$R/wine/wine11-arm64/lib/wine/aarch64-windows
WINUNIX=$R/wine/wine11-arm64/lib/wine/aarch64-unix
export WINEPREFIX=${WINEPREFIX:-$R/wine/pfx-arm64ec}
EXE=probe_d3d11_varyings.exe
CACHE="$(getconf DARWIN_USER_CACHE_DIR)dxmt/$EXE"

if ps -axo command | grep -v grep | grep -qE 'wineserver|-Win64-Shipping\.exe'; then
   echo "un jeu ou un wineserver tourne : la sonde pose des DLL dans l'arbre Wine, on ne touche a rien" >&2; exit 1
fi
for f in d3d11/d3d11.dll dxgi/dxgi.dll d3d10/d3d10core.dll winemetal/winemetal.dll winemetal/unix/winemetal.so; do
   [ -f "$BLD/src/$f" ] || { echo "ECHEC : $BLD/src/$f absent (sh tests/construire_dxmt.sh)" >&2; exit 1; }
done
LC_ALL=C grep -q -a "d3d11.narrowVaryings" "$BLD/src/d3d11/d3d11.dll" || { echo "ECHEC : ce build ne connait pas d3d11.narrowVaryings" >&2; exit 1; }

mkdir -p "$OUT/dxbc" "$OUT/garde"
"$MINGW/x86_64-w64-mingw32-gcc" -O1 -o "$OUT/$EXE" "$R/tests/probe_d3d11_varyings.c" -ldxguid -luuid
winpath() { printf 'Z:%s' "$1" | tr / '\\'; }
# macOS n'a pas timeout(1)
borne() { perl -e 'alarm shift; exec @ARGV' "$@"; }

if [ -n "${SONDE_D3DCOMPILER_MS:-}" ]; then
   echo "== shaders compiles par $SONDE_D3DCOMPILER_MS (invite i686) =="
   "$MINGW/i686-w64-mingw32-gcc" -O1 -o "$OUT/probe_d3d11_varyings32.exe" "$R/tests/probe_d3d11_varyings.c" -ldxguid -luuid
   rm -f "$OUT"/dxbc/*.dxbc
   SONDE_D3DCOMPILER=$(winpath "$SONDE_D3DCOMPILER_MS") WINEDLLOVERRIDES="mscoree,mshtml=;d3dcompiler_47=n" \
      borne 300 sh "$R/tests/etape2_pile_arm64ec.sh" "$OUT/probe_d3d11_varyings32.exe" compiler "$(winpath "$OUT/dxbc")" \
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

passe() { # <nom> <valeur de l'option>
   DXMT_CONFIG="d3d11.narrowVaryings=$2" DXMT_LOG_LEVEL=warn \
   WINEDLLOVERRIDES="mscoree,mshtml=;dxgi,d3d11,d3d10core,winemetal=b" \
      borne 300 sh "$R/tests/etape2_pile_arm64ec.sh" "$OUT/$EXE" rendre "$(winpath "$OUT/dxbc")" > "$OUT/$1.txt" 2>"$OUT/$1.err" || true
   "$R/wine/wine11-arm64/bin/wineserver" -k 2>/dev/null || true
   # le cache est ecrit a la fermeture ; varyings reduits = noms regN_CmM dans les metallibs
   n=0
   for db in "$CACHE"/*.db; do
      [ -f "$db" ] || continue
      n=$((n + $(LC_ALL=C grep -a -o -E 'user\(reg[0-9]+_[0-3]m[0-9]+\)' "$db" | wc -l)))
   done
   echo "$n" > "$OUT/$1.reduits"
   echo "== passe $1 (d3d11.narrowVaryings=$2) : $(grep -c '^cas ' "$OUT/$1.txt") cas, $n varyings reduits dans le cache =="
   cat "$OUT/$1.txt"
}
# cache vide avant la passe d'amont seulement : apres la sonde il contient les deux
# jeux de variantes (de quoi essayer « sh tests/banc_vs_reels.sh etroit » hors jeu,
# BANC_EXE=probe_d3d11_varyings.exe)
rm -rf "$CACHE"
passe amont False
passe etroit True

restaurer
trap - EXIT
rc=0
while read -r somme chemin; do
   [ "$(shasum -a 256 < "$chemin" | cut -d' ' -f1)" = "$somme" ] || { echo "ECHEC : $chemin n'a pas retrouve son contenu d'origine" >&2; rc=1; }
done < "$OUT/empreintes"
[ $rc -eq 0 ] && echo "arbre Wine restaure (5 empreintes verifiees)"

echo "== comparaison =="
grep '^cas ' "$OUT/amont.txt" | awk '{print $2, $3}' > "$OUT/amont.condenses"
grep '^cas ' "$OUT/etroit.txt" | awk '{print $2, $3}' > "$OUT/etroit.condenses"
ncas=$(wc -l < "$OUT/amont.condenses" | tr -d ' ')
grep -q '^FIN' "$OUT/amont.txt" && grep -q '^FIN' "$OUT/etroit.txt" || { echo "ECHEC : une passe n'est pas allee au bout (voir $OUT/*.err)"; rc=1; }
[ "$ncas" -ge 11 ] || { echo "ECHEC : $ncas cas rendus, 11 attendus"; rc=1; }
if grep '^cas ' "$OUT/amont.txt" | grep -q 'couverts=0 '; then echo "ECHEC : un cas n'a rien dessine"; rc=1; fi
[ "$(cat "$OUT/amont.reduits")" -eq 0 ] || { echo "ECHEC : varyings reduits alors que l'option est a False"; rc=1; }
[ "$(cat "$OUT/etroit.reduits")" -gt 0 ] || { echo "ECHEC : aucun varying reduit avec l'option : la sonde n'a rien eprouve"; rc=1; }
if cmp -s "$OUT/amont.condenses" "$OUT/etroit.condenses"; then
   echo "$ncas cas : condenses identiques avec et sans l'option"
else
   echo "ECHEC : images differentes"; diff "$OUT/amont.condenses" "$OUT/etroit.condenses" || true; rc=1
fi
[ $rc -eq 0 ] && echo "SONDE VARYINGS : IMAGES IDENTIQUES" || echo "SONDE VARYINGS : ECHEC"
exit $rc
