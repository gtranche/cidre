#!/bin/sh
# Fabrique les paquets de pipelines precompiles d'un jeu pour KosmicKrisp
# (correctif 0165), a partir d'une recolte faite en jouant avec
# MESA_KK_RECOLTE=<dossier> (msl/<cle>.metal + <cle>.opts, pipelines.*.jsonl) :
#   precompiler_kk.sh <recolte> <sortie> <appid> <famille> [arch...]
# <famille> : apple7 (recolte faite sur un M1) ou apple8 (M2 et suivants) ; le
# MSL de KosmicKrisp differe entre les deux (0153). <arch> : les architectures
# visees en plus de celle de cette machine (applegpu_g16g...), ou « toutes ».
# Etapes : MSL -> AIR (outil metal, options de KosmicKrisp) ; rejeu des
# pipelines par l'ancienne API de Metal (tests/rejouer_mtl3.m) -> archive de
# cette machine, relue telle quelle par les recherches MTL4 de KosmicKrisp ;
# script de pipelines (metal-source) -> metal-tt pour chaque autre architecture.
# Sortie, prete pour `gh release upload precompil` :
#   <appid>-<famille>-<kk>-air.tar.zst             (air/<cle>.metallib)
#   <appid>-<famille>-<kk>-<arch>.tar.zst          (archives/<arch>.metallib)
#   (.part01, .part02... au-dela de 1,9 Gio) et les lignes de precompil-index.tsv
#   (a ajouter a l'index de la release), voir tests/precompil_kk.sh.
# Prerequis : Xcode et sa chaine d'outils Metal (xcodebuild -downloadComponent
# MetalToolchain), zstd. Charge tous les coeurs : hors jeu.
# PRECOMPIL_MACOS (defaut 26.0) : -macos-version-min de metal-tt ; PRECOMPIL_PARTIE_OCTETS :
# taille des parties (essais).
set -eu
[ $# -ge 4 ] || { sed -n '/^#   precompiler_kk/,/^# Prerequis/p' "$0" >&2; exit 2; }
REC=$(cd "$1" && pwd); OUT=$2; ID=$3; FAM=$4; shift 4
case $FAM in apple7|apple8) ;; *) echo "famille : apple7 ou apple8" >&2; exit 2 ;; esac
R=$(cd "$(dirname "$0")/.." && pwd)
mkdir -p "$OUT"; OUT=$(cd "$OUT" && pwd); W="$OUT/travail"; mkdir -p "$W/air" "$W/archives"
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
METAL=$(xcrun -f metal); T=$(dirname "$(xcrun -f metal-tt)")
MACOS=${PRECOMPIL_MACOS:-26.0}
J=$(sysctl -n hw.ncpu)
KK=$(sh "$R/tests/precompil_kk.sh" kk)
ZSTD=$(command -v zstd || echo /opt/homebrew/bin/zstd)
PARTIE=${PRECOMPIL_PARTIE_OCTETS:-$((1900 * 1048576))}   # sous la limite de 2 Gio des assets de release

echo "== MSL -> AIR ($(ls "$REC/msl" | grep -c '\.metal$') bibliotheques)"
t0=$(date +%s)
ls "$REC/msl" | sed -n 's/\.metal$//p' | xargs -P "$J" -I{} sh -c '
   k=$1; rec=$2; w=$3; metal=$4; macos=$5
   [ -f "$w/air/$k.metallib" ] && exit 0
   set -- $(cat "$rec/msl/$k.opts")
   std="metal$(($1 >> 16)).$(($1 & 65535))"
   case $2 in 0) mm=safe ;; 1) mm=relaxed ;; *) mm=fast ;; esac
   case $3 in 1) ff=precise ;; *) ff=fast ;; esac
   "$metal" -std="$std" -fmetal-math-mode=$mm -fmetal-math-fp32-functions=$ff -mmacosx-version-min=$macos \
      -o "$w/air/$k.metallib.tmp" "$rec/msl/$k.metal" 2>>"$w/air.err" && mv "$w/air/$k.metallib.tmp" "$w/air/$k.metallib"
' _ {} "$REC" "$W" "$METAL" "$MACOS"
echo "   $(ls "$W/air" | grep -c '\.metallib$') AIR en $(( $(date +%s) - t0 )) s ; erreurs : $(cat "$W/air.err" 2>/dev/null | grep -c 'error:')"

echo "== rejeu des pipelines (archive de cette machine)"
B="$R/build/rejouer-mtl3"
[ -x "$B" ] && [ ! "$R/tests/rejouer_mtl3.m" -nt "$B" ] ||
   xcrun clang -arch arm64 -fobjc-arc -O2 -framework Foundation -framework Metal "$R/tests/rejouer_mtl3.m" -o "$B"
cat "$REC"/pipelines.*.jsonl >"$W/pipelines.jsonl"
"$B" "$W/air" "$W/pipelines.jsonl" "$W/locale.metallib" "$J"

echo "== script de pipelines (metal-source)"
rm -rf "${W:?}/script"
"$T/metal-source" --flatbuffers=json -o="$W/script" "$W/locale.metallib" >/dev/null 2>&1
LOCALE=$(ls "$W/script" | grep '^applegpu_' | head -1)
mv "$W/locale.metallib" "$W/archives/$LOCALE.metallib"
python3 -I "$R/tests/reecrire_script_pipelines.py" "$(find "$W/script" -name '*.mtlp-json' | head -1)" "$W/script.mtlp-json" "$W/air" | sed 's/^/   /'

ARCHS="$*"
[ "$ARCHS" = toutes ] && ARCHS=$("$T/applegpu-nt" -available-archs macos "$MACOS" 2>/dev/null | grep '^applegpu_' | tr '\n' ' ')
for a in $ARCHS; do
   [ "$a" = "$LOCALE" ] && continue
   t0=$(date +%s)
   if "$T/metal-tt" -arch "$a" -macos-version-min "$MACOS" "$W/script.mtlp-json" -o "$W/archives/$a.metallib" >"$W/metal-tt-$a.log" 2>&1; then
      echo "== metal-tt $a : $(( $(date +%s) - t0 )) s, $(( $(stat -f %z "$W/archives/$a.metallib") / 1048576 )) Mo"
   else
      echo "== metal-tt $a : ECHEC (voir $W/metal-tt-$a.log)"; rm -f "$W/archives/$a.metallib"
   fi
done

echo "== paquets"
: >"$OUT/precompil-index.tsv"
emballer() { # <element> <contenu relatif a W>
   nom="$ID-$FAM-$KK-$1.tar.zst"
   (cd "$W" && tar -cf - "$2") | "$ZSTD" -19 -q -T0 -o "$OUT/$nom" -f
   taille=$(stat -f %z "$OUT/$nom"); sha=$(shasum -a 256 "$OUT/$nom" | cut -c1-64); parties=1
   if [ "$taille" -gt "$PARTIE" ]; then
      split -b "$PARTIE" -a 2 "$OUT/$nom" "$OUT/$nom.part"
      parties=0
      for p in "$OUT/$nom".part*; do parties=$((parties + 1)); mv "$p" "$(printf '%s.part%02d' "$OUT/$nom" "$parties")"; done
      rm -f "$OUT/$nom"
   fi
   printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$ID" "$FAM" "$KK" "$1" "$nom" "$parties" "$taille" "$sha" >>"$OUT/precompil-index.tsv"
   echo "   $nom : $(( taille / 1048576 )) Mo ($parties partie(s))"
}
emballer air air
for f in "$W"/archives/*.metallib; do a=$(basename "$f" .metallib); emballer "$a" "archives/$a.metallib"; done
echo "index : $OUT/precompil-index.tsv"
