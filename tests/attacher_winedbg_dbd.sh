#!/bin/sh
# Lit, dans le processus du jeu Dead by Daylight EN COURS, les octets x86-64 aux
# ADRESSES FAUTIVES déjà connues par la trace +seh, pour les désassembler et identifier
# l'objet NULL déréférencé (cause du « save game could not be read »).
#
# Méthode : winedbg sous cette pile ne peut PAS « continuer » proprement (single-step ARM64
# non implémenté), et le jeu est un processus enfant qu'un lanceur ne suivrait pas. Mais
# winedbg S'ATTACHE bien à un process vivant et LIT sa mémoire. Les adresses des fautes sont
# fixes (base image 0x140000000, confirmée). Donc : on s'attache, on lit les octets à ces
# adresses, on se détache. Aucun « cont », aucune faute à attraper en direct.
#
# Usage :
#   1. Lance DbD normalement. Pendant le CHARGEMENT (avant/pendant « SAVE GAME ERROR »,
#      tant que le process vit -- il tempête plusieurs minutes), lance :
#        sh tests/attacher_winedbg_dbd.sh
#   2. Décode :  sh tests/desas_x86.sh --log build/logs/attach-dbd-DERNIER.log
#
# Si « info share » montre une base ≠ 0x140000000 (ASLR), relance en passant la base :
#   BASE=0x<base> sh tests/attacher_winedbg_dbd.sh
set -e
R=$(cd "$(dirname "$0")/.." && pwd)
WINE="$R/wine/wine11-arm64/bin/wine"
export WINEPREFIX="${WINEPREFIX:-$R/wine/pfx-arm64ec}"
export WINEDEBUG=-all
export DYLD_LIBRARY_PATH="$R/wine/vklib-arm64:$R/prefix/lib"
export FEX_HOSTFEATURES="${FEX_HOSTFEATURES:-enablecrypto}"

mkdir -p "$R/build/logs"
HORO=$(date '+%Y.%m.%d-%H.%M.%S')
LOG="$R/build/logs/attach-dbd-$HORO.log"
ln -sf "$LOG" "$R/build/logs/attach-dbd-DERNIER.log"

# Adresses fautives relevées par la trace +seh (base 0x140000000). On lit, à chacune,
# l'instruction fautive (x/80b addr) et son contexte amont (x/128b addr-0x80 : ce qui a
# mis le registre à NULL). RVA = addr - 0x140000000, pour recalculer si la base diffère.
BASE="${BASE:-0x140000000}"
RVAS="0x1638EB5 0x158C0E6 0x167A2E9 0x14BA6E0"

echo "=== recherche du processus du jeu ===" >&2
PROCS=$(printf 'info process\nquit\n' | "$WINE" winedbg 2>/dev/null)
PID=$(printf '%s\n' "$PROCS" | awk '/[Ss]hipping\.exe/ {gsub(/^ +/,""); print $1; exit}')
[ -n "$PID" ] || PID=$(printf '%s\n' "$PROCS" | awk '/DeadByDaylight/ && !/faux_steam/ {gsub(/^ +/,""); print $1; exit}')
if [ -z "$PID" ]; then
   echo "Processus DbD introuvable. Le jeu tourne-t-il (en chargement) ?" >&2
   printf '%s\n' "$PROCS" | grep -aiE "\.exe'" | grep -aivE "services|lsass|rpcss|winedevice|svchost|plugplay|winedbg|conhost|explorer|start\.exe|wineboot" >&2
   exit 1
fi
echo "cible : pid 0x$PID  (base $BASE)" >&2
echo "journal : $LOG" >&2

# Construire les commandes : info share (vérifier la base), puis lecture à chaque adresse.
{
   echo "attach 0x$PID"
   echo "info share"
   for rva in $RVAS; do
      ADDR=$(printf '0x%x' $((BASE + rva)))
      echo "x/80b $ADDR"
      BEFORE=$(printf '0x%x' $((BASE + rva - 0x80)))
      echo "x/128b $BEFORE"
   done
   echo quit
} > "$R/build/logs/attach-cmds.txt"

"$WINE" winedbg < "$R/build/logs/attach-cmds.txt" > "$LOG" 2>&1 || true

echo "=== terminé ===" >&2
echo "base image constatée (vérifier = $BASE) :" >&2
grep -aiE "Shipping|DeadByDaylight.*[0-9a-f]{8}-" "$LOG" | head -3 >&2 || true
echo "décoder :  sh $R/tests/desas_x86.sh --log $R/build/logs/attach-dbd-DERNIER.log" >&2
