#!/bin/sh
# Banc « vrais vertex shaders » : ou va le cout de l'etage sommets d'un jeu sous
# DXMT ? Execute hors jeu, en Metal natif arm64, les vertex shaders AIR qu'airconv
# a produits (cache de shaders de DXMT), sur des maillages synthetiques de la
# taille mesuree en jeu (0115 : p50 et p90 des index par dessin), et separe
# lecture des attributs, arithmetique et sorties. Voir l'en-tete de
# banc_vs_reels_variantes.py (variantes) et de banc_vs_reels_metal.m (mesure).
#
#   sh tests/banc_vs_reels.sh                 tout : extraction, variantes, mesures, rapport
#   sh tests/banc_vs_reels.sh rapport         refait seulement build/banc-vs-reels/rapport.md
#
# Variables : BANC_EXE (defaut SandFall-Win64-Shipping.exe, Expedition 33),
#   BANC_DB (cache SQLite de DXMT), BANC_OUT (defaut build/banc-vs-reels),
#   BANC_SEULEMENT (hachages DXBC separes par des virgules, defaut tous),
#   BANC_TOP (nombre de shaders par classe pour les essais, defaut 10),
#   BANC_TOURS (defaut 3).
# Prerequis : Xcode + Metal Toolchain (metallib), llvm@15 de Homebrew (arm64).
# Duree : ~30 min pour les 285 vertex shaders d'Expedition 33 sur M1 Max.
# Ne pas lancer pendant qu'un jeu tourne : les mesures GPU ne vaudraient rien
# (et fausseraient celles du jeu).
set -e
DIR=$(cd "$(dirname "$0")" && pwd); R=$(cd "$DIR/.." && pwd)
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
EXE=${BANC_EXE:-SandFall-Win64-Shipping.exe}
DB=${BANC_DB:-$(getconf DARWIN_USER_CACHE_DIR)dxmt/$EXE/shaders_320.db}
OUT=${BANC_OUT:-$R/build/banc-vs-reels}
TOP=${BANC_TOP:-10}
TOURS=${BANC_TOURS:-3}
PY="python3 -I $DIR/banc_vs_reels_variantes.py"
BANC=$OUT/banc_vs_reels_metal

if [ "$1" = rapport ]; then exec $PY rapport --out "$OUT" --top "$TOP"; fi

[ -x "${LLVM15:-/opt/homebrew/opt/llvm@15/bin}/llvm-as" ] || { echo "llvm@15 introuvable (brew install llvm@15, ou LLVM15=...)" >&2; exit 1; }
xcrun -f metallib >/dev/null 2>&1 || { echo "metallib introuvable : Xcode + xcodebuild -downloadComponent MetalToolchain" >&2; exit 1; }
[ -f "$DB" ] || { echo "cache de shaders absent : $DB (lancer le jeu une fois sous DXMT)" >&2; exit 1; }
if ps -axo command | grep -v grep | grep -qE 'wineserver|-Win64-Shipping\.exe'; then
   [ -n "$BANC_FORCE" ] || { echo "un jeu ou un wineserver tourne : mesures GPU sans valeur (BANC_FORCE=1 pour passer outre)" >&2; exit 1; }
fi

mkdir -p "$OUT"
clang -arch arm64 -fobjc-arc -O2 -Wall -framework Metal -framework Foundation \
   "$DIR/banc_vs_reels_metal.m" -o "$BANC"

$PY extraire --db "$DB" --out "$OUT"

# 1. Tous les shaders, variantes a b c d e, deux tailles de dessin, deux remplissages.
rm -rf "$OUT/var"
$PY variantes --out "$OUT" ${BANC_SEULEMENT:+--seulement "$BANC_SEULEMENT"}
caffeinate -i "$BANC" "$OUT/manifeste.tsv" --tours "$TOURS" --passes 3 --rejets 50 --remplissages 0,1 \
   --sortie "$OUT/mesures.tsv"
$PY rapport --out "$OUT" --top "$TOP"

# 2. Les plus couteux de chaque classe : effet du nombre de sorties et de leur largeur (essais k, p, q, t, n),
#    puis de la geometrie (index partages ou non, part de triangles rejetes).
SEL=$(tr '\n' ',' < "$OUT/selection.txt")
rm -rf "$OUT/var-essais"
$PY variantes --out "$OUT" --seulement "$SEL" --variantes a,b,c,d,k2,k4,k6,p,q,t2,t3,n --suffixe=-essais
caffeinate -i "$BANC" "$OUT/manifeste-essais.tsv" --tours "$TOURS" --passes 3 --rejets 50 --remplissages 1 \
   --configs p90:74:74:1 --sortie "$OUT/mesures-essais.tsv"
grep -E '^nom|	[abcd]	' "$OUT/manifeste-essais.tsv" > "$OUT/manifeste-geometrie.tsv"
caffeinate -i "$BANC" "$OUT/manifeste-geometrie.tsv" --tours "$TOURS" --passes 3 --rejets 0,50,100 --remplissages 1 \
   --configs p90:74:74:1,soupe:74:74:0 --sortie "$OUT/mesures-geometrie.tsv"

# 3. Tous les shaders : variante a liee a un fragment shader qui ne lit aucun varying
#    (ce que Metal elague : le cout d'une passe de profondeur avec le meme VS).
grep -E '^nom|	[ab]	' "$OUT/manifeste.tsv" > "$OUT/manifeste-elagage.tsv"
caffeinate -i "$BANC" "$OUT/manifeste-elagage.tsv" --tours "$TOURS" --passes 3 --rejets 50 --remplissages 1 \
   --configs p90:74:74:1 --fragment-de b --sortie "$OUT/mesures-elagage.tsv"

# 4. Tous les shaders : a repasse par opt -O2 de LLVM 15 (un pipeline de passes plus
#    fort dans airconv rapporterait-il quelque chose ?).
rm -rf "$OUT/var-o2"
$PY variantes --out "$OUT" ${BANC_SEULEMENT:+--seulement "$BANC_SEULEMENT"} --variantes a,za --suffixe=-o2
caffeinate -i "$BANC" "$OUT/manifeste-o2.tsv" --tours "$TOURS" --passes 3 --rejets 50 --remplissages 1 \
   --configs p90:74:74:1 --sortie "$OUT/mesures-o2.tsv"

$PY rapport --out "$OUT" --top "$TOP"
echo "$OUT/rapport.md"
