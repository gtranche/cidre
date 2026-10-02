#!/bin/sh
# Désassemble des octets x86-64 bruts (ceux qu'on sort de winedbg avec « x/..b $pc »).
# winedbg sous cette pile ne sait pas désassembler le x86-64 invité ; on récupère donc
# les octets et on les décode ici (clang assemble les .byte, llvm-objdump désassemble).
#
#   tests/desas_x86.sh "8a 80 19 01 00 00 88 44 24 2f 48 8d 0d e1 0f 00"
#   echo "8a 80 19 ..." | tests/desas_x86.sh
#   tests/desas_x86.sh --log build/logs/winedbg-dbd-XXX.log   # extrait les octets du journal
#
# Option --base 0x141638EB5 : affiche les adresses à partir de ce RIP (sinon à partir de 0).
set -e
R=$(cd "$(dirname "$0")/.." && pwd)
T="$R/toolchain/llvm-mingw-20260908-ucrt-macos-universal"
BASE=0

while [ $# -gt 0 ]; do
   case "$1" in
      --base) BASE=$2; shift 2 ;;
      --log)  LOG=$2; shift 2 ;;
      *) break ;;
   esac
done

if [ -n "${LOG:-}" ]; then
   # Dans un journal winedbg, les lignes d'octets ressemblent à :
   #   0x0000014000101e crash+0x101e:  8a 80 19 01 00 00 88 44 24 2f ...
   BYTES=$(grep -aoE ':  ([0-9a-f]{2} )+[0-9a-f]{2}' "$LOG" | sed 's/^:  //' | tr '\n' ' ')
elif [ $# -gt 0 ]; then
   BYTES="$*"
else
   BYTES=$(cat)
fi

# normaliser : garder les paires hexa, séparées par des virgules préfixées 0x
HEX=$(printf '%s' "$BYTES" | tr 'A-F' 'a-f' | grep -aoE '[0-9a-f]{2}' | paste -sd, - | sed 's/\([0-9a-f][0-9a-f]\)/0x\1/g')
[ -n "$HEX" ] || { echo "aucun octet à désassembler" >&2; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
{ echo '.text'; echo '.globl f'; echo 'f:'; echo ".byte $HEX"; } > "$TMP/d.s"
"$T/bin/clang" --target=x86_64-pc-windows-msvc -c "$TMP/d.s" -o "$TMP/d.o" 2>/dev/null
echo "=== désassemblage x86-64 (base $BASE) ==="
"$T/bin/llvm-objdump" -d --triple=x86_64 --adjust-vma="$BASE" "$TMP/d.o" 2>/dev/null \
   | grep -aE '^[[:space:]]+[0-9a-f]+:' \
   | sed -E 's/^[[:space:]]+//'
