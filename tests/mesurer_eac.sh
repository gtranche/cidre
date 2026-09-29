#!/bin/sh
# Mesurer ce que devient un jeu protege par Easy Anti-Cheat sur notre pile.
#
#   mesurer_eac.sh <dossier du jeu> [secondes]
#
# Trois constats, dans cet ordre, parce qu'ils ne repondent pas a la meme
# question :
#
#   1. l'inventaire   -- quels fichiers EAC le depot porte-t-il ? Un binaire
#                        natif de l'hote (.so, .dylib) changerait tout : c'est
#                        ce vers quoi Proton relaie sous Linux. On regarde.
#   2. l'amorceur     -- start_protected_game.exe, le chemin normal. On note ou
#                        il s'arrete et ce que son journal dit.
#   3. le jeu seul    -- lance directement, sans amorceur. Ce n'est pas un
#                        contournement : la doc d'Epic dit que « the game will
#                        not be prevented from running in offline, solo, or
#                        unprotected modes which are outside the scope of
#                        anti-cheat protection ». Les sessions protegees, elles,
#                        restent refusees cote serveur, et c'est tres bien.
#
# On ne touche a rien dans le depot du jeu, et on ne dissimule rien a EAC.
set -e
R=$(cd "$(dirname "$0")/.." && pwd)
JEU=${1:?usage: mesurer_eac.sh <dossier du jeu> [secondes]}
DUREE=${2:-120}
S=${S:-/tmp/eac-$$}
mkdir -p "$S"
[ -d "$JEU" ] || { echo "dossier introuvable : $JEU"; exit 2; }

echo "=== 1. inventaire EAC de $JEU"
find "$JEU" -iname "*EasyAntiCheat*" -o -iname "*start_protected_game*" -o -iname "*anticheat*" \
   2>/dev/null | sed "s|^$JEU/||" | sort | head -40
echo
echo "--- binaires, par machine :"
export PATH="$R/toolchain/llvm-mingw-20260908-ucrt-macos-universal/bin:$PATH"
find "$JEU" \( -iname "*EasyAntiCheat*" -o -iname "*start_protected_game*" \) \
     \( -name "*.dll" -o -name "*.exe" -o -name "*.so" -o -name "*.dylib" \) 2>/dev/null |
while read -r f; do
   m=$(llvm-readobj --file-headers "$f" 2>/dev/null | sed -n 's/.*Machine: \([A-Za-z0-9_]*\).*/\1/p' | head -1)
   [ -n "$m" ] || m=$(file -b "$f" | cut -c1-40)
   printf "  %-52s %s\n" "$(basename "$f")" "$m"
done
echo
echo "--- moteur natif de l'hote (ce vers quoi Proton relaie sous Linux) :"
if find "$JEU" \( -iname "*easyanticheat*.so" -o -iname "*easyanticheat*.dylib" \) 2>/dev/null | grep -q .; then
   find "$JEU" \( -iname "*easyanticheat*.so" -o -iname "*easyanticheat*.dylib" \) | sed 's|^|  |'
else
   echo "  aucun -- rien a relayer"
fi
echo
echo "--- Settings.json :"
find "$JEU" -ipath "*EasyAntiCheat*" -name "Settings.json" -exec sh -c 'echo "  $1 :"; sed "s|^|    |" "$1"' _ {} \; 2>/dev/null | head -30

lancer() {
   nom=$1; exe=$2; shift 2
   echo
   echo "=== $nom"
   [ -f "$exe" ] || { echo "  absent : $exe"; return; }
   ( cd "$(dirname "$exe")" && \
     WINEDEBUG=${WINEDEBUG:-+loaddll,+process} \
     sh "$R/tests/etape2_pile_arm64ec.sh" "$(basename "$exe")" "$@" >"$S/$nom.log" 2>&1 ) &
   p=$!
   i=0
   while [ $i -lt "$DUREE" ] && kill -0 $p 2>/dev/null; do sleep 3; i=$((i + 3)); done
   kill -0 $p 2>/dev/null && { pkill -f "$(basename "$exe")" 2>/dev/null || true; echo "  toujours vivant apres ${i}s"; } \
                          || echo "  termine avant ${DUREE}s"
   wait $p 2>/dev/null || true
   echo "  --- ce que la trace dit :"
   grep -aiE "easyanticheat|anticheat|start_protected" "$S/$nom.log" | sed 's/^[0-9a-f]*://' | sort -u | head -12
   grep -aE "^[0-9a-f]*:err:" "$S/$nom.log" | sed 's/^[0-9a-f]*://' | sort -u | head -8
   echo "  --- journal complet : $S/$nom.log"
}

BOOT=$(find "$JEU" -iname "start_protected_game.exe" 2>/dev/null | head -1)
[ -n "$BOOT" ] && lancer "2-amorceur" "$BOOT"

# Le jeu lui-meme. Settings.json nomme l'executable que l'amorceur lance ; on
# le lit plutot que de deviner, et on retombe sur le plus gros .exe du depot si
# le fichier est absent.
CIBLE=$(find "$JEU" -ipath "*EasyAntiCheat*" -name "Settings.json" -exec cat {} \; 2>/dev/null |
        sed -n 's/.*"executable"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
if [ -n "$CIBLE" ]; then
   CIBLE=$(printf '%s' "$CIBLE" | tr '\\' '/')
   EXE="$JEU/$CIBLE"
   echo
   echo "Settings.json designe : $CIBLE"
else
   EXE=$(find "$JEU" -maxdepth 3 -name "*.exe" ! -iname "*start_protected*" ! -iname "*crash*" \
         ! -iname "*unins*" -exec ls -S {} + 2>/dev/null | head -1)
   echo
   echo "Settings.json muet, on prend le plus gros executable : $EXE"
fi
[ -n "$EXE" ] && lancer "3-jeu-seul" "$EXE"

echo
echo "=== journaux de l'amorceur EAC laisses par le jeu"
find "$JEU" -ipath "*EasyAntiCheat*" -name "*.log" -newermt "-10 minutes" 2>/dev/null |
   while read -r l; do echo "  --- $l"; tail -20 "$l" | sed 's/^/    /'; done

echo
echo "resultats dans $S"
